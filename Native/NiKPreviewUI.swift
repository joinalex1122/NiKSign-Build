import UIKit
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation
import ImageIO

@MainActor final class NiKLibrary: ObservableObject {
    @Published var items: [NiKLibraryItem] = []
    @Published var error = ""
    static let shared = NiKLibrary()
    nonisolated static var root: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("IPALibrary") }
    @Published var receiving = false
    @Published var notice = ""
    @Published private(set) var loadFailure: String?
    private var indexStore: NiKLibraryIndexStore?
    var recoveryIndexURL: URL { index }
    private var index: URL { Self.root.appendingPathComponent("library.json") }
    init() {
        do {
            try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
            guard try Self.root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw NiKError("Thư mục thư viện không được là symlink.")
            }
            let store = try NiKLibraryIndexStore(url: index)
            indexStore = store; items = store.items
        } catch { self.error = error.localizedDescription; loadFailure = error.localizedDescription }
    }
    @discardableResult func save(_ item: NiKLibraryItem) -> Bool {
        guard let indexStore else { error = loadFailure ?? "Không mở được index thư viện; giữ nguyên để khôi phục."; return false }
        var updated = items
        if let i = updated.firstIndex(where: { $0.id == item.id }) { updated[i] = item }
        else { updated.insert(item, at: 0) }
        do {
            try indexStore.commit(updated)
            items = updated
            error = ""
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func remove(_ item: NiKLibraryItem) async throws {
        guard indexStore != nil else { throw NiKError(loadFailure ?? "Index thư viện chưa sẵn sàng.") }
        guard let stored = items.first(where: { $0.id == item.id }) else { throw NiKError("Không còn IPA này trong thư viện.") }
        guard !NiKSigningQueue.shared.jobs.contains(where: { $0.libraryID == stored.id && !$0.state.isTerminal }) else { throw NiKError("Hãy hủy hoặc hoàn tất công việc ký trước khi xóa IPA này.") }
        do { try await NiKTrashController.shared.removeLibraryItem(stored) }
        catch { self.error = error.localizedDescription; throw error }
    }
    func commitTrashRemoval(_ snapshot: NiKLibraryItem) throws {
        guard let indexStore else { throw NiKError(loadFailure ?? "Index thư viện chưa sẵn sàng.") }
        try indexStore.removeForTrash(snapshot); items = indexStore.items
    }
    func commitTrashRestoration(_ snapshot: NiKLibraryItem) throws {
        guard let indexStore else { throw NiKError(loadFailure ?? "Index thư viện chưa sẵn sàng.") }
        try indexStore.restoreFromTrash(snapshot); items = indexStore.items
    }
    @discardableResult func receive(_ url: URL, expectedBundleID: String? = nil) async -> Bool {
        await receiveItem(url, expectedBundleID: expectedBundleID) != nil
    }
    func receiveItem(_ url: URL, expectedBundleID: String? = nil) async -> NiKLibraryItem? {
        guard indexStore != nil else { error = loadFailure ?? "Index thư viện chưa sẵn sàng; giữ nguyên để khôi phục."; return nil }
        guard !receiving else { error = "Đang nhập một IPA khác. Hãy đợi hoàn tất rồi thử lại."; return nil }
        error = ""
        receiving = true
        var stagedItem: NiKLibraryItem?
        var committed = false
        defer {
            receiving = false
            if !committed, let stagedItem {
                try? FileManager.default.removeItem(at: stagedItem.ipaURL)
                if let icon = stagedItem.iconURL { try? FileManager.default.removeItem(at: icon) }
            }
        }
        do {
            try Task.checkCancellation()
            let importing = Task.detached { try Self.importIPA(url, expectedBundleID: expectedBundleID) }
            let item = try await withTaskCancellationHandler(operation: { try await importing.value }, onCancel: { importing.cancel() })
            stagedItem = item
            try Task.checkCancellation()
            guard save(item) else { return nil }
            committed = true
            notice = "Đã nhập \(item.title) vào thư viện IPA."
            return item
        } catch { self.error = error.localizedDescription; return nil }
    }
    nonisolated static func importIPA(_ url: URL, expectedBundleID: String? = nil) throws -> NiKLibraryItem {
        guard url.pathExtension.lowercased() == "ipa" else { throw NiKError("Hãy chọn tệp IPA.") }
        let staging = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        let local = try NiKFileImport.copy(url, into: staging)
        var count: UInt64 = 0, size: UInt64 = 0
        guard local.path.withCString({ NiKZipCheck($0, &count, &size) }) == 0 else { throw NiKError("IPA hỏng hoặc vượt giới hạn.") }
        let zip = try Archive(url: local, accessMode: .read)
        let metadata = zip.filter { $0.path.hasPrefix("Payload/") && $0.path.split(separator: "/").count == 3 && $0.path.hasSuffix(".app/Info.plist") }
        guard metadata.count == 1, metadata[0].uncompressedSize <= 1_048_576 else { throw NiKError("Info.plist không hợp lệ.") }
        var data = Data()
        let crc = try zip.extract(metadata[0]) { chunk in
            try Task.checkCancellation()
            guard data.count + chunk.count <= 1_048_576 else { throw NiKError("Info.plist vượt 1 MB.") }
            data.append(chunk)
        }
        guard crc == metadata[0].checksum,
              let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw NiKError("Không đọc được IPA.") }
        if let expectedBundleID, info["CFBundleIdentifier"] as? String != expectedBundleID {
            throw NiKError("Bundle ID trong IPA không khớp nguồn; không nhập thư viện.")
        }
        try Task.checkCancellation()
        let filename = UUID().uuidString + ".ipa"
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let ownedIPA = root.appendingPathComponent(filename)
        let ownedIcon = root.appendingPathComponent(filename + ".png")
        var completed = false
        defer {
            if !completed {
                try? FileManager.default.removeItem(at: ownedIPA)
                try? FileManager.default.removeItem(at: ownedIcon)
            }
        }
        try FileManager.default.copyItem(at: local, to: ownedIPA)
        // Icon extraction is optional. Missing/asset-catalog-only icons use the UI fallback.
        let appPath = String(metadata[0].path.dropLast("Info.plist".count))
        let icons = info["CFBundleIcons"] as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let names = primary?["CFBundleIconFiles"] as? [String] ?? info["CFBundleIconFiles"] as? [String] ?? []
        for name in names.reversed() {
            try Task.checkCancellation()
            let stem = (name as NSString).deletingPathExtension
            var found = false
            for suffix in ["@3x.png", "@2x.png", ".png"] {
                guard let entry = zip[appPath + stem + suffix], entry.uncompressedSize <= 4 * 1_048_576 else { continue }
                do {
                    var png = Data()
                    let crc = try zip.extract(entry) { chunk in
                        guard png.count + chunk.count <= 4 * 1_048_576 else { throw NiKError("Icon quá lớn.") }
                        png.append(chunk)
                    }
                    guard crc == entry.checksum, let source = CGImageSourceCreateWithData(png as CFData, nil),
                          let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                            kCGImageSourceCreateThumbnailFromImageAlways: true,
                            kCGImageSourceThumbnailMaxPixelSize: 180,
                            kCGImageSourceCreateThumbnailWithTransform: true
                          ] as CFDictionary), let data = UIImage(cgImage: thumb).pngData() else { continue }
                    try data.write(to: root.appendingPathComponent(filename + ".png"), options: .atomic)
                    found = true
                    break
                } catch { continue }
            }
            if found { break }
        }
        try Task.checkCancellation()
        completed = true
        return NiKLibraryItem(title: info["CFBundleDisplayName"] as? String ?? info["CFBundleName"] as? String ?? url.deletingPathExtension().lastPathComponent,
            version: info["CFBundleShortVersionString"] as? String ?? "?", bundleID: info["CFBundleIdentifier"] as? String ?? "?", filename: filename)
    }
}

struct NiKBrand: View {
    var body: some View {
        Text("NiK").font(.system(size: 30, weight: .bold, design: .rounded)).italic()
            .foregroundStyle(LinearGradient(colors: [.cyan, .purple], startPoint: .leading, endPoint: .trailing))
            .frame(width: 64, height: 64).background(Color(red: 0.025, green: 0.05, blue: 0.17), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct NiKPreviewRoot: View {
    @AppStorage("nik.theme") private var theme = "system"
    @AppStorage("nik.language") private var language = "vi"
    @AppStorage("nik.certPrompted") private var certPrompted = false
    @AppStorage("nik.otaTrustIntro.v1") private var trustIntroAcknowledged = false
    @StateObject private var library = NiKLibrary.shared
    @StateObject private var certificates = NiKCertificateStore.shared
    @State private var tab = 0
    @State private var prompt = false
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    var body: some View {
        Group {
            if !trustIntroAcknowledged {
                NavigationStack { NiKTrustSetupView(onContinue: { trustIntroAcknowledged = true }) }
            } else {
               activeTabView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaInset(edge: .bottom, spacing: 0) { liquidGlassTabBar }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .tint(.cyan)
        .preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil)
        .onAppear { configure() }
        .onChange(of: trustIntroAcknowledged) { _, _ in configure() }
        .onChange(of: library.notice) { _, notice in if !notice.isEmpty { tab = 0 } }
        .alert(t("Không nhập được IPA", "IPA Import Failed"), isPresented: Binding(
            get: { !library.error.isEmpty }, set: { if !$0 { library.error = "" } }
        )) { Button("OK", role: .cancel) {} } message: { Text(library.error) }
        .alert(t("Thêm chứng chỉ ký?", "Add Signing Certificate?"), isPresented: $prompt) {
            Button(t("Nhập chứng chỉ", "Import Certificate")) { tab = 2 }
            Button(t("Để sau", "Later"), role: .cancel) {}
        } message: { Text(t("Quản lý nhiều chứng chỉ tại Cài đặt. Bạn có thể chọn riêng cho từng IPA.", "Manage multiple certificates in Settings. You can choose one for each IPA.")) }
    }
    private func configure() {
        if trustIntroAcknowledged && !certPrompted { certPrompted = true; prompt = true }
    }
    private var settings: some View {
        NiKSettingsView(certificates: certificates, library: library)
    }
    private var activeTabView: some View {
        ZStack {
            switch tab {
            case 0:
                NiKLibraryView(library: library, certificates: certificates)
            case 1:
                NiKFilesHome()
            default:
                settings
            }
        }
    }

    @ViewBuilder
    private var liquidGlassTabBar: some View {
        HStack(spacing: 4) {
            tabBarButton(index: 0, title: t("Ký IPA", "Sign IPA"), icon: "signature")
            tabBarButton(index: 1, title: t("Tệp", "Files"), icon: "folder.fill")
            tabBarButton(index: 2, title: t("Cài đặt", "Settings"), icon: "gearshape.fill")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(
            Capsule()
                .stroke(
                    LinearGradient(
                        colors: [.white.opacity(0.45), .white.opacity(0.12), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.38), radius: 18, x: 0, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func tabBarButton(index: Int, title: String, icon: String) -> some View {
        let selected = tab == index
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                tab = index
            }
        } label: {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: selected ? .semibold : .regular))
                Text(title)
                    .font(.system(size: 10, weight: selected ? .semibold : .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(selected ? Color.white : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background {
                if selected {
                    Capsule()
                        .fill(Color.black.opacity(0.55))
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.15), lineWidth: 0.8)
                        )
                }
            }
        }
        .buttonStyle(.plain)
    }
}

struct NiKGlassCircleIcon: View {
    let systemName: String
    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.primary)
            .frame(width: 34, height: 34)
            .background(.ultraThinMaterial, in: Circle())
            .overlay(
                Circle()
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.45), .white.opacity(0.1)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.8
                    )
            )
    }
}

struct NiKCardPressButtonStyle: ButtonStyle {
    var selected: Bool = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        selected
                            ? Color.accentColor.opacity(0.18)
                            : (configuration.isPressed ? Color(uiColor: .secondarySystemGroupedBackground) : Color.clear)
                    )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        selected
                            ? Color.accentColor.opacity(0.55)
                            : (configuration.isPressed ? Color.white.opacity(0.12) : Color.clear),
                        lineWidth: 1
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}


struct NiKLibraryView: View {
    @State private var installTarget: NiKPreviewDocument?
    @AppStorage("nik.libraryGrid") private var grid = false
    @ObservedObject var library: NiKLibrary
    @ObservedObject var certificates: NiKCertificateStore
    @AppStorage("nik.language") private var language = "vi"
    @State private var query = ""
    @State private var importing = false
    @State private var errorMessage: String?

    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }

    private var filtered: [NiKLibraryItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return library.items }
        return library.items.filter {
            $0.title.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let failure = library.loadFailure {
                        Text(failure).font(.footnote).foregroundStyle(.red)
                        ShareLink(t("Xuất index để khôi phục", "Export Index for Recovery"), item: library.recoveryIndexURL)
                    }
                    searchBarCard
                    certificateBannerCard
                    NavigationLink { NiKSignedAppsView() } label: {
                        Label(t("Ứng dụng đã ký", "Signed Applications"), systemImage: "app.badge.checkmark")
                            .frame(maxWidth: .infinity, alignment: .leading).padding()
                            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                    }
                    libraryListCard
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(t("Ký IPA", "Sign IPA"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    trailingMenu
                }
            }
            .sheet(isPresented: $importing) {
                NiKFilePicker { result in
                    if case .success(let url) = result {
                        let scoped = url.startAccessingSecurityScopedResource()
                        Task {
                            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                            await library.receive(url)
                        }
                    }
                }
            }
            .sheet(item: $installTarget) { NiKInstallIPAView(url: $0.url) }
            .alert(t("Thông báo", "Notice"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    @ViewBuilder
    private var searchBarCard: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(t("Tìm IPA theo tên hoặc Bundle ID...", "Search IPA by name or Bundle ID..."), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
    }

    @ViewBuilder
    private var certificateBannerCard: some View {
        NavigationLink {
            NiKCertificateSettings(store: certificates)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: certificates.profiles.isEmpty ? "exclamationmark.shield.fill" : "checkmark.seal.fill")
                    .font(.title3)
                    .foregroundStyle(certificates.profiles.isEmpty ? Color.orange : Color.green)
                    .frame(width: 38, height: 38)
                    .background(
                        (certificates.profiles.isEmpty ? Color.orange : Color.green).opacity(0.15),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(t("Chứng chỉ ký", "Signing Certificate"))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(certificates.profiles.isEmpty
                         ? t("Chưa có chứng chỉ · Chạm để thêm", "No certificate · Tap to add")
                         : "\(certificates.profiles.count) " + t("chứng chỉ sẵn sàng", "certificates ready"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var libraryListCard: some View {
        if filtered.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "shippingbox")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary)
                Text(t("Chưa có tệp IPA nào", "No IPA files yet"))
                    .font(.headline)
                Text(t("Nhấn nút + ở góc trên để nhập tệp .ipa từ thiết bị hoặc chọn từ tab Tệp.", "Tap + above to import an .ipa file or pick from Files tab."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    importing = true
                } label: {
                    Label(t("Nhập IPA", "Import IPA"), systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: grid ? 2 : 1), spacing: 10) {
                ForEach(filtered) { item in ipaCardRow(item) }
            }
        }
    }

    @ViewBuilder
    private func ipaCardRow(_ item: NiKLibraryItem) -> some View {
        NavigationLink {
            NiKIPADetail(item: item, library: library, certificates: certificates)
        } label: {
            Group {
                if grid { ipaGridCard(item) } else { ipaListCard(item) }
            }
            .padding(14)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Menu(t("Thêm vào hàng đợi", "Add to Queue")) {
                ForEach(certificates.profiles) { cert in
                    Button(cert.name) { enqueue(item, certificate: cert) }
                }
                if certificates.profiles.isEmpty { Text(t("Nhập chứng chỉ trong Cài đặt", "Import a certificate in Settings")) }
            }
        }
    }

@ViewBuilder
private func ipaGridCard(_ item: NiKLibraryItem) -> some View {
VStack(alignment: .leading, spacing: 10) {
HStack(alignment: .top) {
NiKAppIcon(url: item.iconURL, size: 52)
.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
Spacer(minLength: 0)
if NiKSignedFileAccess.available(item.signedPath) != nil {
Text(t("Đã ký", "Signed"))
.font(.caption2.weight(.semibold))
.padding(.horizontal, 8)
.padding(.vertical, 3)
.background(Color.green.opacity(0.16), in: Capsule())
.foregroundStyle(.green)
}
}
Text(item.title)
.font(.subheadline.weight(.semibold))
.foregroundStyle(.primary)
.lineLimit(2)
.multilineTextAlignment(.leading)
Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
.font(.caption)
.foregroundStyle(.secondary)
.lineLimit(1)
}
.frame(maxWidth: .infinity, alignment: .leading)
}

@ViewBuilder
private func ipaListCard(_ item: NiKLibraryItem) -> some View {
HStack(spacing: 12) {
NiKAppIcon(url: item.iconURL, size: 50)
.clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
VStack(alignment: .leading, spacing: 4) {
Text(item.title)
.font(.body.weight(.semibold))
.foregroundStyle(.primary)
.lineLimit(1)
Text(item.bundleID)
.font(.caption)
.foregroundStyle(.secondary)
.lineLimit(1)
HStack(spacing: 6) {
Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
.font(.caption2.weight(.medium))
.padding(.horizontal, 7)
.padding(.vertical, 2)
.background(Color.secondary.opacity(0.14), in: Capsule())
.foregroundStyle(.secondary)
if NiKSignedFileAccess.available(item.signedPath) != nil {
Text(t("Đã ký", "Signed"))
.font(.caption2.weight(.semibold))
.padding(.horizontal, 7)
.padding(.vertical, 2)
.background(Color.green.opacity(0.16), in: Capsule())
.foregroundStyle(.green)
}
}
}
Spacer(minLength: 0)
if NiKSignedFileAccess.available(item.signedPath) != nil {
    Button {
        installSigned(item)
    } label: {
        Text(t("Cài đặt", "Install"))
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.accentColor.opacity(0.16), in: Capsule())
            .foregroundStyle(Color.accentColor)
    }
    .buttonStyle(.borderless)
}
Image(systemName: "chevron.right")
.font(.caption.weight(.semibold))
.foregroundStyle(.tertiary)
}
}

private func enqueue(_ item: NiKLibraryItem, certificate: NiKCertificateProfile) {
    do {
        var snapshot = item.options
        snapshot.targetDeviceUDID = UserDefaults.standard.string(forKey: "nik.deviceUDID") ?? ""
        let job = NiKSigningJob(libraryID: item.id, title: item.title, input: item.ipaURL, certificateID: certificate.id, options: snapshot)
        try NiKSigningQueue.shared.enqueue([job])
        errorMessage = t("Đã thêm vào hàng đợi ký.", "Added to the signing queue.")
    } catch { errorMessage = error.localizedDescription }
}

private func installSigned(_ item: NiKLibraryItem) {
    guard let url = NiKSignedFileAccess.available(item.signedPath) else {
        errorMessage = t("Không tìm thấy IPA đã ký. Hãy khôi phục tệp hoặc ký lại.", "Signed IPA is missing. Restore it or sign again.")
        return
    }
    installTarget = NiKPreviewDocument(url: url)
}

    @ViewBuilder
    private var trailingMenu: some View {
        Menu {
            NavigationLink(t("Nguồn IPA", "IPA Sources")) { NiKSourceLibraryView(library: library) }
            NavigationLink(t("Ký nhiều IPA", "Batch Signing")) { NiKBatchSigningView(library: library, certificates: certificates) }
            NavigationLink(t("Hàng đợi ký", "Signing Queue")) { NiKSigningQueueView(queue: NiKSigningQueue.shared) }
            Button { grid.toggle() } label: {
                Label(grid ? t("Danh sách", "List") : t("Lưới", "Grid"), systemImage: grid ? "list.bullet" : "square.grid.2x2")
            }
            Button {
                importing = true
            } label: {
                Label(t("Nhập IPA từ Tệp", "Import IPA"), systemImage: "plus.circle")
            }
            NavigationLink {
                NiKCertificateSettings(store: certificates)
            } label: {
                Label(t("Quản lý Chứng chỉ", "Manage Certificates"), systemImage: "checkmark.seal")
            }
        } label: {
            NiKGlassCircleIcon(systemName: "ellipsis")
        }
    }
}

struct NiKIPADetail: View {
    @State var item: NiKLibraryItem
    @ObservedObject var library: NiKLibrary
    @ObservedObject var certificates: NiKCertificateStore
    @ObservedObject private var signingQueue = NiKSigningQueue.shared
    @AppStorage("nik.defaultCertificate") private var defaultCertificate = ""
    @AppStorage("nik.deviceUDID") private var targetDeviceUDID = ""
    @AppStorage("nik.language") private var language = "vi"
    @AppStorage("nik.interfaceMode") private var interfaceMode = "basic"
    @Environment(\.dismiss) private var dismiss

    @State private var tweakPicker = false
    @State private var deleting = false
    @State private var signedURL: URL?
    @State private var errorMessage: String?
@ObservedObject private var otaServer = NiKHTTPSOTAServer.shared
@State private var otaStatusMessage = ""
    @State private var installTarget: NiKPreviewDocument?
    @State private var deferredInstallURL: URL?
    @State private var showSigningProgressSheet = false
    @State private var trackedJobID: UUID?
    @State private var autoInstallAfterSigning = false
@State private var saveStatusMessage = ""
@State private var mobileConfigShare: NiKOTAShareURL?

    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }

    private var activeJob: NiKSigningJob? { signingQueue.jobs.first { $0.libraryID == item.id && !$0.state.isTerminal } }
    private var completedJob: NiKSigningJob? { signingQueue.jobs.last { $0.libraryID == item.id && $0.state == .succeeded } }

    private var certificateAssessment: NiKCertificateAssessment? {
        guard let cert = activeCertificate else { return nil }
        let custom = item.options.customBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        return NiKCertificateCompatibility.assess(cert, bundleID: custom.isEmpty ? item.bundleID : custom,
            deviceUDID: targetDeviceUDID, allowMismatch: item.options.allowCertificateMismatch)
    }

    private var activeCertificate: NiKCertificateProfile? {
        if let id = item.certificateID {
            return certificates.profiles.first(where: { $0.id == id })
        }
        if let def = UUID(uuidString: defaultCertificate),
           let match = certificates.profiles.first(where: { $0.id == def }) {
            return match
        }
        return certificates.profiles.first
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                certificateCard
                optionsCard
                signActionCard
                NavigationLink(t("Theo dõi hàng đợi ký", "Monitor Signing Queue")) { NiKSigningQueueView(queue: signingQueue) }
                if let activeJob {
                    ProgressView(value: activeJob.fraction)
                    Text(activeJob.step).font(.caption).foregroundStyle(.secondary)
                }
                if let signedURL, NiKSignedFileAccess.available(signedURL.path) != nil {
                    signedResultCard(signedURL)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 96)
        }
        .disabled(deleting)
        .overlay { if deleting { ProgressView(t("Đang chuyển vào Thùng rác…", "Moving to Trash…")).padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        guard !deleting else { return }
                        deleting = true
                        Task {
                            defer { deleting = false }
                            do { try await library.remove(item); dismiss() }
                            catch { errorMessage = error.localizedDescription }
                        }
                    } label: {
                        Label(t("Chuyển IPA vào Thùng rác", "Move IPA to Trash"), systemImage: "trash")
                    }
                } label: {
                    NiKGlassCircleIcon(systemName: "ellipsis")
                }
            }
        }
        .sheet(isPresented: $tweakPicker) {
            NiKFilePicker { result in
                do {
                    let url = try result.get()
                    guard ["dylib", "deb"].contains(url.pathExtension.lowercased()) else { throw NiKError("Hãy chọn dylib hoặc deb.") }
                    let directory = NiKLibrary.root.appendingPathComponent("Components/" + item.id.uuidString)
                    let target = try NiKFileImport.copy(url, into: directory)
                    item.options.injectedFiles.append(target)
                    library.save(item)
                } catch { errorMessage = error.localizedDescription }
            }
        }
        .sheet(isPresented: $showSigningProgressSheet, onDismiss: {
            if let pending = deferredInstallURL {
                deferredInstallURL = nil
                installTarget = NiKPreviewDocument(url: pending)
            }
        }) {
            NiKLCSignProgressSheet(job: trackedJob, itemTitle: item.title,
                onInstall: { url in startHTTPSInstall(for: url) },
                onClose: { showSigningProgressSheet = false })
        }
        .sheet(item: $installTarget) { NiKInstallIPAView(url: $0.url) }
        .onAppear { signedURL = NiKSignedFileAccess.available(item.signedPath); syncCompletedJob() }
        .onChange(of: completedJob?.id) { _, _ in syncCompletedJob() }
        .onDisappear {
            if !deleting && library.items.contains(where: { $0.id == item.id }) { library.save(item) }
        }
        .alert(t("Lỗi ký IPA", "Signing Error"), isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var headerCard: some View {
        HStack(spacing: 14) {
            NiKAppIcon(url: item.iconURL, size: 60)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.headline)
                Text(item.bundleID)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("v\(item.version) · \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var certificateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(t("Chứng chỉ sử dụng", "Certificate"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            if certificates.profiles.isEmpty {
                NavigationLink {
                    NiKCertificateSettings(store: certificates)
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color.accentColor)
                        Text(t("Thêm chứng chỉ (.p12 + .mobileprovision)", "Add certificate (.p12 + .mobileprovision)"))
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            } else {
                Picker(t("Chứng chỉ", "Certificate"), selection: Binding(
                    get: { item.certificateID },
                    set: {
                        item.certificateID = $0
                        library.save(item)
                    }
                )) {
                    Text(t("Theo chứng chỉ mặc định", "Use Default Certificate")).tag(nil as UUID?)
                    ForEach(certificates.profiles) { cert in
                        Text(cert.name).tag(Optional(cert.id))
                    }
                }
                .pickerStyle(.menu)
                if let assessment = certificateAssessment {
                    ForEach(assessment.issues.sorted { $0.severity == .blocking && $1.severity != .blocking }) { issue in
                        Text(language == "en" ? issue.en : issue.vi).font(.caption)
                            .foregroundStyle(issue.severity == .blocking ? Color.red : Color.orange)
                    }
                }
                if let certificate = activeCertificate,
                   certificateAssessment?.issues.contains(where: { $0.code == "bundle.mismatch" }) == true {
                    Text(t("Bundle ID trong profile: ", "Profile Bundle ID: ") + certificate.bundleIDPattern)
                        .font(.caption.monospaced()).textSelection(.enabled)
                    Text(t("NiKSign vẫn ký và giữ nguyên Bundle ID nếu bạn không sửa. Đổi ID bên dưới là tùy chọn; có thể ảnh hưởng đăng nhập, thông báo và nhóm ứng dụng.", "NiKSign can sign and keep the original Bundle ID. Changing it below is optional and can affect sign-in, notifications and app groups."))
                        .font(.caption).foregroundStyle(.secondary)
                    if !certificate.bundleIDPattern.contains("*") && !certificate.bundleIDPattern.isEmpty {
                        Button(t("Dùng Bundle ID của profile cho IPA này", "Use the profile Bundle ID for this IPA")) {
                            item.options.customBundleID = certificate.bundleIDPattern
                            library.save(item)
                        }
                        .disabled(activeJob != nil)
                    }
                }
                if let certificate = activeCertificate {
                    NavigationLink(t("Phân tích chứng chỉ với IPA này", "Assess Certificate for This IPA")) {
                        NiKCertificateAssessmentView(profile: certificate,
                            bundleID: item.options.customBundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? item.bundleID : item.options.customBundleID.trimmingCharacters(in: .whitespacesAndNewlines),
                            allowMismatch: item.options.allowCertificateMismatch)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var activeAdvancedOptions: [String] {
        var result: [String] = []
        if !item.options.minimumOSVersion.isEmpty { result.append("iOS ≥ " + item.options.minimumOSVersion) }
        if item.options.enableFileSharing { result.append(t("Chia sẻ tệp", "File sharing")) }
        if item.options.removeSupportedDevicesRestriction { result.append(t("Bỏ giới hạn thiết bị", "Remove device restriction")) }
        if item.options.removeExtensions { result.append(t("Gỡ Extensions / Watch", "Remove Extensions / Watch")) }
        if item.options.weakDylibInjection { result.append("Weak dylib") }
        if item.options.allowCertificateMismatch { result.append(t("Cho phép cert/profile lệch", "Allow cert/profile mismatch")) }
        if !item.options.injectedFiles.isEmpty { result.append("\(item.options.injectedFiles.count) " + t("thành phần chèn", "injected components")) }
        return result
    }

    @ViewBuilder
    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(t("Tùy chọn chỉnh sửa", "Signing Options"))
                    .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                Spacer()
                Button(interfaceMode == "advanced" ? t("Cơ bản", "Basic") : t("Nâng cao", "Advanced")) {
                    interfaceMode = interfaceMode == "advanced" ? "basic" : "advanced"
                }.font(.caption.weight(.semibold))
            }
            if !activeAdvancedOptions.isEmpty {
                Text(t("Đang áp dụng: ", "Currently applied: ") + activeAdvancedOptions.joined(separator: " · "))
                    .font(.caption).foregroundStyle(.orange)
            }
            if interfaceMode != "advanced" {
                Text(t("Chế độ cơ bản giữ nguyên mọi tùy chọn nâng cao đã lưu. Chuyển Nâng cao để xem hoặc thay đổi.", "Basic mode preserves all saved advanced options. Switch to Advanced to inspect or change them."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            TextField(t("Tên ứng dụng mới (tùy chọn)", "Custom Display Name"), text: $item.options.customDisplayName)
                .textFieldStyle(.roundedBorder)
            TextField(t("Bundle ID mới (tùy chọn)", "Custom Bundle ID"), text: $item.options.customBundleID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            TextField(t("Phiên bản mới (tùy chọn)", "Custom Version"), text: $item.options.customVersion)
                .textFieldStyle(.roundedBorder)
            if interfaceMode == "advanced" {
                TextField("Minimum iOS", text: $item.options.minimumOSVersion).textFieldStyle(.roundedBorder)
                Toggle(t("Chia sẻ tệp", "File Sharing"), isOn: $item.options.enableFileSharing)
                Toggle(t("Bỏ UISupportedDevices", "Remove UISupportedDevices"), isOn: $item.options.removeSupportedDevicesRestriction)
                Toggle(t("Gỡ App Extensions / Watch", "Remove App Extensions / Watch"), isOn: $item.options.removeExtensions)
                Toggle("Weak Dylib", isOn: $item.options.weakDylibInjection)
                Button(t("Thêm dylib / deb", "Add dylib / deb")) { tweakPicker = true }
                ForEach(item.options.injectedFiles, id: \.self) { url in
                    HStack {
                        Text(url.lastPathComponent).font(.caption)
                        Spacer()
                        Button { item.options.injectedFiles.removeAll { $0 == url } } label: { Image(systemName: "minus.circle") }
                    }
                }
                NavigationLink(t("Kiểm tra tệp", "Inspect Files")) { NiKInspectView(initialURL: item.ipaURL) }
            }
            Button(t("Lưu tùy chỉnh", "Save Options")) { library.save(item) }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var signActionCard: some View {
        let signDisabled = activeCertificate == nil || activeJob != nil || certificateAssessment?.canSign == false
        VStack(spacing: 10) {
            Button(t("Thêm vào hàng đợi", "Add to Queue")) {
                Task { await sign(showProgress: false) }
            }.disabled(signDisabled)
            Button {
                Task { await sign(autoInstall: false) }
            } label: {
                HStack(spacing: 10) {
                    if activeJob != nil {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: "signature")
                    }
                    Text(activeJob != nil ? t("Đang chờ / đang xử lý", "Queued / Processing") : t("Ký IPA ngay", "Sign IPA Now"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(signDisabled ? Color.gray.opacity(0.45) : Color.accentColor)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(signDisabled)

            Button {
                Task { await sign(autoInstall: true) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "bolt.badge.checkmark.fill")
                    Text(t("Ký & Cài đặt luôn", "Sign & Install Now"))
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(signDisabled ? Color.gray.opacity(0.45) : Color.green)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .disabled(signDisabled)

            if let readyURL = NiKSignedFileAccess.available(signedURL?.path ?? item.signedPath) {
                Button {
                    startHTTPSInstall(for: readyURL)
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.down.app.fill")
                        Text(t("Cài đặt ngay", "Install Now"))
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private func signedResultCard(_ url: URL) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(t("Đã ký thành công!", "Signed Successfully!"), systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text(url.lastPathComponent)
                .font(.caption)
                .foregroundStyle(.secondary)
            ShareLink(item: url) {
                Label(t("Chia sẻ / Xuất IPA đã ký", "Share / Export Signed IPA"), systemImage: "square.and.arrow.up")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.18), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
signedInstallControls(url)
signedSaveToFilesButton(url)
if !otaStatusMessage.isEmpty {
Text(otaStatusMessage)
.font(.caption)
.foregroundStyle(.secondary)
}
if !saveStatusMessage.isEmpty {
Text(saveStatusMessage)
.font(.caption)
.foregroundStyle(.green)
}
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
.sheet(item: $mobileConfigShare) { share in
NiKShareSheet(items: [share.url])
                                 }
    }

private struct NiKOTAShareURL: Identifiable {
let id = UUID()
let url: URL
}

@ViewBuilder
private func signedInstallControls(_ url: URL) -> some View {
Button {
startHTTPSInstall(for: url)
} label: {
Label(t("Cài đặt trực tiếp (HTTPS OTA)", "Direct Install (HTTPS OTA)"), systemImage: "arrow.down.app.fill")
.font(.subheadline.weight(.semibold))
.frame(maxWidth: .infinity)
.padding(.vertical, 12)
.background(Color.accentColor.opacity(0.16), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}
Button {
exportTrustProfile()
} label: {
Label(t("Xuất chứng chỉ tin cậy (.mobileconfig)", "Export Trust Profile (.mobileconfig)"), systemImage: "checkmark.shield")
.font(.caption.weight(.semibold))
.frame(maxWidth: .infinity)
.padding(.vertical, 10)
.background(Color.orange.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
}
}

@ViewBuilder
private func signedSaveToFilesButton(_ url: URL) -> some View {
Button {
saveToDocuments(url)
} label: {
Label(t("Lưu vào thư mục Tệp", "Save to Files Folder"), systemImage: "folder.badge.plus")
.font(.subheadline.weight(.semibold))
.frame(maxWidth: .infinity)
.padding(.vertical, 12)
.background(Color.blue.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
}
}

private func startHTTPSInstall(for url: URL) {
    guard NiKSignedFileAccess.available(url.path) != nil else {
        errorMessage = t("Không tìm thấy IPA đã ký. Hãy khôi phục tệp hoặc ký lại.", "Signed IPA is missing. Restore it or sign again.")
        return
    }
    if showSigningProgressSheet {
        deferredInstallURL = url
        showSigningProgressSheet = false
    } else {
        installTarget = NiKPreviewDocument(url: url)
    }
}

private func exportTrustProfile() {
do {
let data = try otaServer.exportMobileConfig()
let dest = FileManager.default.temporaryDirectory.appendingPathComponent("NiKSign-HTTPS-CA.mobileconfig")
try data.write(to: dest, options: .atomic)
mobileConfigShare = NiKOTAShareURL(url: dest)
} catch {
otaStatusMessage = error.localizedDescription
}
}

private func saveToDocuments(_ url: URL) {
do {
let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let dest = try NiKFileImport.copy(url, into: docs)
saveStatusMessage = t("Đã lưu vào Tệp: \(dest.lastPathComponent)", "Saved to Files: \(dest.lastPathComponent)")
} catch {
saveStatusMessage = error.localizedDescription
}
}

    private var trackedJob: NiKSigningJob? {
        if let trackedJobID { return signingQueue.jobs.first { $0.id == trackedJobID } }
        return activeJob
    }

    private func sign(autoInstall: Bool = false, showProgress: Bool = true) async {
        guard let cert = activeCertificate else {
            errorMessage = t("Hãy chọn chứng chỉ hợp lệ.", "Choose an available certificate.")
            return
        }
        do {
            guard library.save(item) else { throw NiKError(library.error) }
            var snapshot = item.options
            snapshot.targetDeviceUDID = targetDeviceUDID
            let job = NiKSigningJob(libraryID: item.id, title: item.title, input: item.ipaURL, certificateID: cert.id, options: snapshot)
            trackedJobID = job.id
            autoInstallAfterSigning = autoInstall
            try signingQueue.enqueue([job])
            showSigningProgressSheet = showProgress
        } catch {
            autoInstallAfterSigning = false
            errorMessage = error.localizedDescription
        }
    }

    private func syncCompletedJob() {
        guard let artifact = completedJob?.output else { return }
        signedURL = NiKSignedFileAccess.available(artifact.ipaURL.path)
        item.signedPath = artifact.ipaURL.path
        item.signedBundleID = artifact.bundleID
        item.signedVersion = artifact.version
        item.signedDisplayName = artifact.displayName
        if autoInstallAfterSigning, let job = completedJob, trackedJobID == nil || job.id == trackedJobID {
            autoInstallAfterSigning = false
            startHTTPSInstall(for: artifact.ipaURL)
        }
    }
}

private struct NiKLCSignProgressSheet: View {
    let job: NiKSigningJob?
    let itemTitle: String
    let onInstall: (URL) -> Void
    let onClose: () -> Void
    @AppStorage("nik.language") private var language = "vi"
        private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    
    private var steps: [(Double, String)] {
        [
            (0.12, t("1. Kiểm tra khóa và profile", "1. Check key and profile")),
            (0.30, t("2. Kiểm tra và giải nén IPA", "2. Validate and extract IPA")),
            (0.50, t("3. Phân tích ứng dụng", "3. Inspect application")),
            (0.68, t("4. Áp dụng tùy chỉnh", "4. Apply customizations")),
            (0.84, t("5. Ký với Zsign", "5. Sign with Zsign")),
            (0.96, t("6. Đóng gói và kiểm tra đầu ra", "6. Package and validate output"))
        ]
    }

    private var progress: Double {
        if job?.state == .succeeded { return 1.0 }
        return min(max(job?.fraction ?? 0.0, 0.0), 1.0)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Text(itemTitle).font(.headline).lineLimit(1)
                    Text(job?.state == .succeeded ? t("Ký thành công!", "Signing Succeeded!") : (job?.state.isTerminal == true ? t("Ký thất bại", "Signing Failed") : t("Đang ký ứng dụng...", "Signing App...")))
                        .font(.subheadline)
                        .foregroundStyle(job?.state == .succeeded ? .green : (job?.state.isTerminal == true ? .red : .secondary))
                    ProgressView(value: progress).tint(job?.state == .succeeded ? .green : .accentColor)
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                VStack(alignment: .leading, spacing: 12) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { idx, step in
                        let done = job?.state == .succeeded || (idx < steps.count - 1 ? progress >= steps[idx + 1].0 : progress >= 1.0)
                        let active = !done && progress >= step.0 && job?.state.isTerminal != true
                        HStack(spacing: 12) {
                            if done {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            } else if active {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "circle").foregroundStyle(.tertiary)
                            }
                            Text(step.1)
                                .font(.subheadline.weight(active || done ? .semibold : .regular))
                                .foregroundStyle(done || active ? .primary : .secondary)
                            Spacer()
                        }
                    }
                }
                .padding()
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                if let error = job?.error, !error.isEmpty {
                    Text(error).font(.footnote).foregroundStyle(.red).textSelection(.enabled)
                }
                Spacer()

                if job?.state == .succeeded, let ipaURL = job?.output?.ipaURL {
                    Button {
                        onInstall(ipaURL)
                    } label: {
                        Label(t("Cài đặt ngay", "Install Now"), systemImage: "arrow.down.app.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
            .padding()
            .navigationTitle(t("Tiến trình ký", "Signing Progress"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(t("Đóng", "Close"), action: onClose)
                }
            }
        }
    }
}

struct NiKCertificateSettings: View {
    enum CertPickMode: Identifiable {
        case p12, provision, zip
        var id: Int {
            switch self {
            case .p12: return 0
            case .provision: return 1
            case .zip: return 2
            }
        }
    }

    @ObservedObject var store: NiKCertificateStore
    @AppStorage("nik.defaultCertificate") private var defaultCertificate = ""
    @AppStorage("nik.language") private var language = "vi"

    @State private var name = ""
    @State private var password = ""
@State private var showPassword = false
    @StateObject private var temporaryFiles = NiKTemporaryFiles()
    @State private var p12URL: URL?
    @State private var provisionURL: URL?
    @State private var pickMode: CertPickMode?
    @State private var docFiles: [URL] = []
    @State private var message: String?
    @State private var isSuccess = false

    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let failure = store.loadFailure {
                    Text(failure).font(.footnote).foregroundStyle(.red)
                    ShareLink(t("Xuất index để khôi phục", "Export Index for Recovery"), item: store.recoveryIndexURL)
                }
                savedProfilesCard
                importFilesCard
                documentsQuickLoadCard
                credentialsAndSaveCard
                if let message {
                    statusBannerCard(message)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 96)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(t("Chứng chỉ", "Certificates"))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reloadDocuments() }
        .sheet(item: $pickMode) { mode in
            NiKFilePicker { result in
                if case .success(let url) = result {
                    handlePickedURL(url, mode: mode)
                }
            }
        }
    }

    @ViewBuilder
    private var savedProfilesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(t("Chứng chỉ đã lưu", "Saved Certificates"), systemImage: "checkmark.seal.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(store.profiles.count)")
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.16), in: Capsule())
            }
            if store.profiles.isEmpty {
                Text(t("Chưa có chứng chỉ nào được lưu.", "No certificates saved yet."))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(store.profiles) { profile in
                    VStack(alignment: .leading, spacing: 8) {
                        savedProfileRow(profile)
                        NiKCertificateStatusView(profile: profile, store: store)
                    }
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func savedProfileRow(_ profile: NiKCertificateProfile) -> some View {
        let isDefault = defaultCertificate == profile.id.uuidString
        HStack(spacing: 12) {
            Button {
                defaultCertificate = profile.id.uuidString
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isDefault ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isDefault ? Color.green : Color.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(profile.name)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(profile.teamName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .buttonStyle(.plain)

            NavigationLink { NiKCertificateAssessmentView(profile: profile) } label: {
                Image(systemName: "info.circle").padding(8)
            }.buttonStyle(.plain)
            Button(role: .destructive) {
                do {
                    try store.removeProfile(profile)
                    if isDefault { defaultCertificate = store.profiles.first?.id.uuidString ?? "" }
                } catch { message = error.localizedDescription; isSuccess = false }
            } label: {
                Image(systemName: "trash")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .padding(8)
                    .background(Color.red.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(Color(uiColor: .tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private var importFilesCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Nhập chứng chỉ mới", "Import Certificate"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            Button {
                pickMode = .zip
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "doc.zipper")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(t("Nhập nhanh từ file .zip (certificate.zip)", "Quick Import from .zip"))
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(t("Tự giải nén tìm .p12, .mobileprovision và mật khẩu .txt", "Auto-extract .p12, .mobileprovision & .txt password"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)

            filePickRow(
                title: t("Tệp khóa (.p12)", "Key File (.p12)"),
                fileURL: p12URL,
                icon: "key.fill",
                color: .orange
            ) {
                pickMode = .p12
            }

            filePickRow(
                title: t("Hồ sơ (.mobileprovision)", "Provisioning Profile (.mobileprovision)"),
                fileURL: provisionURL,
                icon: "doc.badge.gearshape.fill",
                color: .blue
            ) {
                pickMode = .provision
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func filePickRow(title: String, fileURL: URL?, icon: String, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(fileURL?.lastPathComponent ?? t("Chạm để chọn tệp...", "Tap to select file..."))
                        .font(.caption)
                        .foregroundStyle(fileURL == nil ? Color.secondary : Color.green)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: fileURL == nil ? "folder.badge.plus" : "checkmark.circle.fill")
                    .foregroundStyle(fileURL == nil ? Color.secondary : Color.green)
            }
            .padding(12)
            .background(Color(uiColor: .tertiarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var documentsQuickLoadCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(t("Tệp có sẵn trong Documents", "Available in Documents"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    reloadDocuments()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption.weight(.semibold))
                }
            }

            if docFiles.isEmpty {
                Text(t("Không có tệp .p12, .mobileprovision hoặc .zip nào trong Documents.", "No .p12, .mobileprovision, or .zip files in Documents."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(docFiles, id: \.path) { file in
                    Button {
                        loadDocumentFile(file)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: iconForCertFile(file))
                                .foregroundStyle(colorForCertFile(file))
                                .frame(width: 30, height: 30)
                                .background(colorForCertFile(file).opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.lastPathComponent)
                                    .font(.subheadline.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(file.pathExtension.uppercased())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(t("Nạp", "Load"))
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Color.accentColor.opacity(0.16), in: Capsule())
                        }
                        .padding(10)
                        .background(Color(uiColor: .tertiarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var credentialsAndSaveCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Thông tin & Lưu", "Credentials & Save"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 6) {
Text(t("Tên gợi nhớ (tuỳ chọn)", "Custom Name (optional)"))
.font(.caption.weight(.medium))
.foregroundStyle(.secondary)
TextField(t("Tên gợi nhớ (tuỳ chọn)", "Custom Name (optional)"), text: $name)
.textFieldStyle(.roundedBorder)
.textContentType(.none)
}
VStack(alignment: .leading, spacing: 6) {
Text(t("Mật khẩu .p12 (để trống nếu không có)", ".p12 Password (leave empty if none)"))
.font(.caption.weight(.medium))
.foregroundStyle(.secondary)
HStack(spacing: 8) {
Group {
if showPassword {
TextField(t("Mật khẩu .p12 (để trống nếu không có)", ".p12 Password (leave empty if none)"), text: $password)
} else {
SecureField(t("Mật khẩu .p12 (để trống nếu không có)", ".p12 Password (leave empty if none)"), text: $password)
}
}
.textFieldStyle(.roundedBorder)
.textContentType(.none)
.textInputAutocapitalization(.never)
.autocorrectionDisabled()
Button {
showPassword.toggle()
} label: {
Image(systemName: showPassword ? "eye.slash" : "eye")
.foregroundStyle(.secondary)
}
.buttonStyle(.plain)
}
}
         
            Button {
                saveCertificate()
            } label: {
                Text(t("Kiểm tra & Lưu", "Verify & Save"))
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background((p12URL == nil || provisionURL == nil) ? Color.gray.opacity(0.45) : Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(p12URL == nil || provisionURL == nil)
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private func statusBannerCard(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: isSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isSuccess ? .green : .orange)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .padding(14)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func reloadDocuments() {
        docFiles = NiKCertZipHelper.documentsCertificateFiles()
    }

    private func iconForCertFile(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "p12": return "key.fill"
        case "mobileprovision": return "doc.badge.gearshape.fill"
        default: return "doc.zipper"
        }
    }

    private func colorForCertFile(_ url: URL) -> Color {
        switch url.pathExtension.lowercased() {
        case "p12": return .orange
        case "mobileprovision": return .blue
        default: return .purple
        }
    }

    private func handlePickedURL(_ url: URL, mode: CertPickMode) {
        do {
            let tempCopy = try temporaryFiles.copy(url)
            switch mode {
            case .p12:
                p12URL = tempCopy
                message = t("Đã nạp tệp .p12: ", "Loaded .p12: ") + url.lastPathComponent
                isSuccess = true
            case .provision:
                provisionURL = tempCopy
                message = t("Đã nạp tệp .mobileprovision: ", "Loaded .mobileprovision: ") + url.lastPathComponent
                isSuccess = true
            case .zip:
                loadZipCertificate(tempCopy)
            }
        } catch {
            message = error.localizedDescription
            isSuccess = false
        }
    }

    private func loadDocumentFile(_ url: URL) {
        let ext = url.pathExtension.lowercased()
        if ext == "zip" {
            loadZipCertificate(url)
        } else if ext == "p12" {
            p12URL = url
            message = t("Đã nạp .p12 từ Documents: ", "Loaded .p12: ") + url.lastPathComponent
            isSuccess = true
        } else if ext == "mobileprovision" {
            provisionURL = url
            message = t("Đã nạp .mobileprovision từ Documents: ", "Loaded .mobileprovision: ") + url.lastPathComponent
            isSuccess = true
        }
    }

    private func loadZipCertificate(_ url: URL) {
        do {
            let extracted = try NiKCertZipHelper.extractPairAndPassword(from: url)
            temporaryFiles.retain(extracted.tempDir)
            p12URL = extracted.p12
            password = ""
            provisionURL = extracted.provision
            if let pass = extracted.password, !pass.isEmpty {
                password = pass
                message = t("Đã giải nén .p12, .mobileprovision và mật khẩu từ .txt. Bấm Kiểm tra & Lưu!", "Extracted .p12, .mobileprovision, and password. Tap Verify & Save!")
            } else {
                message = t("Đã giải nén .p12 và .mobileprovision. Nhập mật khẩu .p12 rồi bấm Kiểm tra & Lưu.", "Extracted .p12 and .mobileprovision. Enter password and tap Verify & Save.")
            }
            isSuccess = true
        } catch {
            message = error.localizedDescription
            isSuccess = false
        }
    }

    private func saveCertificate() {
        guard let k = p12URL, let p = provisionURL else { return }
        do {
            let saved = try store.importProfile(p12URL: k, provisionURL: p, password: password, customName: name)
            if defaultCertificate.isEmpty {
                defaultCertificate = saved.id.uuidString
            }
            message = t("Đã lưu chứng chỉ: ", "Saved certificate: ") + saved.name
            isSuccess = true
            name = ""
            password = ""
            p12URL = nil
            provisionURL = nil
            temporaryFiles.clear()
        } catch {
            message = error.localizedDescription
            isSuccess = false
        }
    }
}

private struct NiKSwipeToDeleteRow<Content: View>: View {
    let itemID: String
    @Binding var swipedItemID: String?
    let isDisabled: Bool
    let deleteTitle: String
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var dragOffset: CGFloat = 0
    private let openOffset: CGFloat = -96

    private var isOpen: Bool {
        !isDisabled && swipedItemID == itemID
    }

    private var currentOffset: CGFloat {
        if isDisabled { return 0 }
        let base = isOpen ? openOffset : 0
        return min(0, max(openOffset - 24, base + dragOffset))
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            if currentOffset < -4 {
                Button(role: .destructive) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        swipedItemID = nil
                        dragOffset = 0
                    }
                    onDelete()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "trash")
                            .font(.subheadline.weight(.semibold))
                        Text(deleteTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(.red)
                    .frame(width: 84, height: 38)
                    .background(
                        Capsule()
                            .fill(Color.white)
                            .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                    )
                }
                .buttonStyle(.plain)
                .padding(.trailing, 6)
                .transition(.opacity.combined(with: .scale(scale: 0.92)))
            }

            content()
                .offset(x: currentOffset)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 16, coordinateSpace: .local)
                        .onChanged { value in
                            guard !isDisabled else { return }
                            let dx = value.translation.width
                            let dy = value.translation.height
                            guard abs(dx) > abs(dy) * 1.25 else { return }
                            if dx < 0 && swipedItemID != itemID {
                                swipedItemID = nil
                            }
                            dragOffset = dx
                        }
                        .onEnded { value in
                            guard !isDisabled else {
                                dragOffset = 0
                                return
                            }
                            let dx = value.translation.width
                            let dy = value.translation.height
                            let predicted = value.predictedEndTranslation.width
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                if abs(dx) > abs(dy) * 1.25 {
                                    if isOpen {
                                        if dx > 24 || predicted > 40 {
                                            swipedItemID = nil
                                        }
                                    } else {
                                        if dx < -44 || predicted < -72 {
                                            swipedItemID = itemID
                                        }
                                    }
                                }
                                dragOffset = 0
                            }
                        }
                )
        }
        .onChange(of: isDisabled) { _, disabled in
            if disabled {
                dragOffset = 0
                if swipedItemID == itemID {
                    swipedItemID = nil
                }
            }
        }
    }
}

struct NiKLocalFiles: View {
    private let rootTitle: String
    @StateObject private var browser: NiKFileBrowserController
    private var directory: URL { browser.directory }
    private var title: String { browser.selected.location.components.last ?? rootTitle }
    init(directory: URL, title: String = "Tệp") {
        rootTitle = title
        _browser = StateObject(wrappedValue: NiKFileBrowserController(root: directory))
    }

    @AppStorage("nik.language") private var language = "vi"
    @AppStorage("nik.defaultCertificate") private var defaultCertificate = ""

    @State private var items: [NiKFileItem] = []
    @State private var listingError: String?
    @State private var visibleAnchor: String?
    @State private var query = ""
    @State private var sort: NiKFilesSort = .name
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []
    @State private var swipedItemID: String?

    @State private var importing = false
    @State private var creatingFolder = false
    @State private var newFolderName = ""

    @State private var renameTarget: NiKFileItem?
    @State private var renameText = ""
    @State private var editorDoc: NiKPreviewDocument?
    @State private var typedPlistDoc: NiKPreviewDocument?
    @State private var propertiesDoc: NiKPreviewDocument?
    @State private var folderTarget: NiKFolderTarget?
    @State private var previewDoc: NiKPreviewDocument?
    @State private var hexTarget: NiKPreviewDocument?
    @State private var shareItem: NiKShareItem?

    @State private var zipTarget: NiKFileItem?
    @State private var ipaTarget: NiKFileItem?
    @State private var installTarget: NiKPreviewDocument?
    @StateObject private var temporaryFiles = NiKTemporaryFiles()
    @State private var fileBusy = false
    @State private var certPendingP12: URL?
    @State private var certPendingProvision: URL?
    @State private var certPasswordInput = ""
    @State private var showCertPasswordPrompt = false
    @State private var alertMessage: String?

    private static let rowDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm dd/MM/yy"
        return df
    }()

    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }

    private var filtered: [NiKFileItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let base = q.isEmpty ? items : items.filter { $0.name.lowercased().contains(q) }
        return base.sorted { a, b in
            if a.isDirectory != b.isDirectory { return a.isDirectory && !b.isDirectory }
            switch sort {
            case .name: return a.name.localizedStandardCompare(b.name) == .orderedAscending
            case .date: return a.modifiedAt > b.modifiedAt
            case .size: return a.size > b.size
            }
        }
    }

    var body: some View {
        mainView
            .disabled(fileBusy)
            .overlay { if fileBusy { ProgressView("Đang xử lý…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
            .modifier(applySheets)
            .modifier(applyDialogsAndAlerts)
            .sheet(item: $editorDoc) { NiKTextEditorView(url: $0.url) }
            .sheet(item: $typedPlistDoc) { NiKTypedPlistEditorView(url: $0.url) }
            .sheet(item: $propertiesDoc) { NiKFilePropertiesView(url: $0.url, root: browser.root) }
            .sheet(item: $installTarget) { NiKInstallIPAView(url: $0.url) }
    }

    @ViewBuilder
    private var mainView: some View {
        ScrollView {
            VStack(spacing: 12) {
                browserControls
                searchBar
                if isSelecting {
                    selectionBar
                }
                filesListContent
            }
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 96)
        }
        .scrollPosition(id: $visibleAnchor)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                trailingToolbarMenu
            }
        }
        .onAppear { loadBrowserTab(); if let message = browser.message { alertMessage = message; browser.message = nil } }
        .onChange(of: browser.state.selectedID) { oldID, _ in browser.rememberAnchor(visibleAnchor, tabID: oldID); loadBrowserTab() }
        .onChange(of: browser.selected.location) { _, _ in loadBrowserTab() }
        .onChange(of: browser.selected.showsHidden) { _, _ in reload() }
        .onChange(of: browser.message) { _, message in
            if let message { alertMessage = message; browser.message = nil }
        }
        .onChange(of: query) { _, value in
            let bounded = String(value.prefix(512))
            if bounded != value { query = bounded }
            browser.setOptions(query: bounded, sort: sort)
        }
        .onChange(of: sort) { _, _ in browser.setOptions(query: query, sort: sort) }
        .onChange(of: visibleAnchor) { _, anchor in browser.scrollAnchor = anchor }
        .onChange(of: isSelecting) { _, selecting in if selecting { swipedItemID = nil } }
    }

    private func loadBrowserTab() {
        query = browser.selected.query; sort = browser.selected.sort
        selectedIDs.removeAll(); isSelecting = false; swipedItemID = nil
        let anchor = browser.scrollAnchor
        reload()
        visibleAnchor = anchor
    }

    private var browserControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(browser.state.tabs) { tab in
                        Button { browser.select(tab.id) } label: {
                            Text(tab.location.components.last ?? rootTitle).font(.caption.weight(.semibold)).lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(tab.id == browser.state.selectedID ? Color.accentColor.opacity(0.2) : Color.secondary.opacity(0.08), in: Capsule())
                        }.contextMenu {
                            Button(t("Đóng tab", "Close Tab"), role: .destructive) { browser.closeTab(tab.id) }.disabled(browser.state.tabs.count == 1)
                        }
                    }
                }
            }
            HStack(spacing: 16) {
                Button { browser.travel(-1) } label: { Image(systemName: "chevron.left") }
                    .disabled(browser.selected.historyIndex == 0).accessibilityLabel(t("Lùi", "Back"))
                Button { browser.travel(1) } label: { Image(systemName: "chevron.right") }
                    .disabled(browser.selected.historyIndex + 1 == browser.selected.history.count).accessibilityLabel(t("Tiến", "Forward"))
                Button { browser.open(browser.root) } label: { Image(systemName: "house") }.accessibilityLabel(t("Thư mục gốc", "Root Folder"))
                Text(browser.selected.location.components.isEmpty ? rootTitle : browser.selected.location.components.joined(separator: " / "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }.buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(t("Tìm tệp hoặc thư mục...", "Search files or folders..."), text: $query)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
    }

    @ViewBuilder
    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text("\(selectedIDs.count) " + t("đã chọn", "selected"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Spacer()
            Button(t("Thùng rác", "Trash"), role: .destructive) {
                deleteSelected()
            }
            .font(.caption.weight(.semibold))
            .disabled(selectedIDs.isEmpty)
            Button(t("Xong", "Done")) {
                isSelecting = false
                selectedIDs.removeAll()
            }
            .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
    }

    @ViewBuilder
    private var filesListContent: some View {
        if let listingError {
            VStack(alignment: .leading, spacing: 8) {
                Label(t("Không đọc được thư mục", "Unable to Read Folder"), systemImage: "exclamationmark.triangle")
                Text(listingError).font(.caption).foregroundStyle(.secondary)
                Button(t("Thử lại", "Retry")) { reload() }
                Button(t("Về thư mục gốc", "Open Root Folder")) { browser.open(browser.root) }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(16)
        } else if filtered.isEmpty {
            VStack(spacing: 10) {
                Image(systemName: "folder")
                    .font(.system(size: 34))
                    .foregroundStyle(.secondary)
                Text(t("Thư mục trống", "Empty Folder"))
                    .font(.headline)
                Text(t("Nhấn nút ... ở góc trên để nhập tệp hoặc tạo thư mục mới.", "Tap ... above to import files or create a folder."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(28)
            .background(Color(uiColor: .secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        } else {
            LazyVStack(spacing: 4) {
                ForEach(filtered) { item in
                    NiKSwipeToDeleteRow(
                        itemID: item.id,
                        swipedItemID: $swipedItemID,
                        isDisabled: isSelecting,
                        deleteTitle: t("Xóa", "Delete"),
                        onDelete: {
                            swipedItemID = nil
                            trashItems([item])
                        }
                    ) {
                       rowEntry(item)
                    }
                    .id(item.name)
                }
            }.scrollTargetLayout()
        }
    }

    @ViewBuilder
    private func rowEntry(_ item: NiKFileItem) -> some View {
        if item.isDirectory && !isSelecting {
            Button {
                browser.open(item.url)
            } label: {
                rowContent(item)
            }
            .buttonStyle(NiKCardPressButtonStyle())
            .contextMenu { rowContextMenu(item) }
        } else {
            Button {
                handleTap(item)
            } label: {
                rowContent(item)
            }
            .buttonStyle(NiKCardPressButtonStyle(selected: isSelecting && selectedIDs.contains(item.id)))
            .contextMenu { rowContextMenu(item) }
        }
    }

    @ViewBuilder
    private func rowContent(_ item: NiKFileItem) -> some View {
        HStack(spacing: 12) {
            if isSelecting {
                Image(systemName: selectedIDs.contains(item.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selectedIDs.contains(item.id) ? Color.accentColor : Color.secondary)
            }
            Image(systemName: iconName(for: item))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconColor(for: item))
                .frame(width: 40, height: 40)
                .background(
                    iconColor(for: item).opacity(0.16),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(item.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitleText(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if item.isDirectory {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var trailingToolbarMenu: some View {
        Menu {
            NavigationLink(t("Thùng rác", "Trash")) { NiKTrashView() }
            Button(t("Tab mới tại đây", "New Tab Here")) { browser.newTab() }.disabled(browser.state.tabs.count >= 12)
            Button(t("Đóng tab hiện tại", "Close Current Tab"), role: .destructive) { browser.closeTab(browser.state.selectedID) }.disabled(browser.state.tabs.count == 1)
            Button(browser.state.favorites.contains(browser.selected.location) ? t("Bỏ yêu thích vị trí", "Unfavorite Location") : t("Yêu thích vị trí", "Favorite Location")) { browser.toggleFavorite() }
            Menu(t("Vị trí yêu thích", "Favorite Locations")) {
                ForEach(Array(browser.state.favorites.enumerated()), id: \.offset) { _, location in
                    Button(location.components.isEmpty ? rootTitle : location.components.joined(separator: " / ")) { browser.openFavorite(location) }
                }
            }.disabled(browser.state.favorites.isEmpty)
            Button(browser.selected.showsHidden ? t("Ẩn tệp ẩn", "Hide Hidden Files") : t("Hiện tệp ẩn", "Show Hidden Files")) { browser.toggleHidden() }
            Divider()
            Button {
                importing = true
            } label: {
                Label(t("Nhập tệp", "Import File"), systemImage: "square.and.arrow.down")
            }
            Button {
                newFolderName = ""
                creatingFolder = true
            } label: {
                Label(t("Thư mục mới", "New Folder"), systemImage: "folder.badge.plus")
            }
            Button {
                isSelecting.toggle()
                if !isSelecting { selectedIDs.removeAll() }
            } label: {
                Label(isSelecting ? t("Hủy chọn", "Cancel Selection") : t("Chọn nhiều", "Select"), systemImage: "checkmark.circle")
            }
            Menu(t("Sắp xếp", "Sort")) {
                Button(t("Tên", "Name")) { sort = .name }
                Button(t("Ngày sửa", "Date")) { sort = .date }
                Button(t("Dung lượng", "Size")) { sort = .size }
            }
        } label: {
            NiKGlassCircleIcon(systemName: "ellipsis")
        }
    }

    @ViewBuilder
    private func rowContextMenu(_ item: NiKFileItem) -> some View {
        if !item.isDirectory, NiKSignedFileAccess.available(item.url.path) != nil {
            Button(t("Cài đặt", "Install")) { installTarget = NiKPreviewDocument(url: item.url) }
        }

        if !item.isDirectory {
            let ext = item.url.pathExtension.lowercased()
            if ext == "zip" {
                Button {
                    startCertImportFromZip(item.url)
                } label: {
                    Label(t("Nhập làm Chứng chỉ (.zip)", "Import as Certificate (.zip)"), systemImage: "checkmark.seal")
                }
                Button {
                    unzipHere(item.url)
                } label: {
                    Label(t("Giải nén tại đây", "Unzip Here"), systemImage: "archivebox")
                }
            } else if ext == "p12" || ext == "mobileprovision" {
                Button {
                    startCertImportFromPair(item.url)
                } label: {
                    Label(t("Lưu làm Chứng chỉ", "Save as Certificate"), systemImage: "checkmark.seal")
                }
            }
            Button {
                previewDoc = NiKPreviewDocument(url: item.url)
            } label: {
                Label(t("Xem trước", "Preview"), systemImage: "eye")
            }
            Menu {
                Button(t("Xem Hex", "Hex View")) { hexTarget = NiKPreviewDocument(url: item.url) }
                Button(t("Thuộc tính & SHA-256", "Properties & SHA-256")) { propertiesDoc = NiKPreviewDocument(url: item.url) }
            } label: { Label(t("Kiểm tra tệp", "Inspect File"), systemImage: "number.square") }
        } else {
            Button(t("Thuộc tính", "Properties")) { propertiesDoc = NiKPreviewDocument(url: item.url) }
        }
        Button {
            renameTarget = item
            renameText = item.name
        } label: {
            Label(t("Đổi tên", "Rename"), systemImage: "pencil")
        }
        Button {
            folderTarget = NiKFolderTarget(item: item, isCopy: true)
        } label: { Label(t("Sao chép", "Copy"), systemImage: "doc.on.doc") }
        Button {
            folderTarget = NiKFolderTarget(item: item, isCopy: false)
        } label: {
            Label(t("Di chuyển", "Move"), systemImage: "folder")
        }
        Button {
            shareItem = NiKShareItem(url: item.url)
        } label: {
            Label(t("Chia sẻ", "Share"), systemImage: "square.and.arrow.up")
        }
        Button(role: .destructive) {
            trashItems([item])
        } label: {
            Label(t("Chuyển vào Thùng rác", "Move to Trash"), systemImage: "trash")
        }
    }

    private var applySheets: some ViewModifier {
        SheetModifier(
            importing: $importing,
            directory: directory,
            previewDoc: $previewDoc,
            hexTarget: $hexTarget,
            shareItem: $shareItem,
            folderTarget: $folderTarget,
            alertMessage: $alertMessage,
            busy: $fileBusy,
            onReload: reload
        )
    }

    private var applyDialogsAndAlerts: some ViewModifier {
        DialogAlertModifier(
            t: t,
            creatingFolder: $creatingFolder,
            newFolderName: $newFolderName,
            renameTarget: $renameTarget,
            renameText: $renameText,
            zipTarget: $zipTarget,
            ipaTarget: $ipaTarget,
            showCertPasswordPrompt: $showCertPasswordPrompt,
            certPasswordInput: $certPasswordInput,
            alertMessage: $alertMessage,
            onCreateFolder: createFolder,
            onRename: performRename,
            onUnzip: unzipHere,
            onCertZip: startCertImportFromZip,
            onPreview: { previewDoc = NiKPreviewDocument(url: $0) },
            onShare: { shareItem = NiKShareItem(url: $0) },
            onInstall: { installTarget = NiKPreviewDocument(url: $0) },
            onSaveCert: completeCertImport,
            onCancelCert: clearPendingCertificate
        )
    }

    private func subtitleText(for item: NiKFileItem) -> String {
        let dateStr = Self.rowDateFormatter.string(from: item.modifiedAt)
        if item.isDirectory {
            return "\(dateStr) · " + t("Thư mục", "Folder")
        }
        let sizeStr = ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file)
        return "\(dateStr) · \(sizeStr)"
    }

    private func iconName(for item: NiKFileItem) -> String {
        if item.isDirectory { return "folder.fill" }
        switch item.url.pathExtension.lowercased() {
        case "ipa": return "shippingbox.fill"
        case "zip": return "doc.zipper"
        case "p12": return "key.fill"
        case "mobileprovision": return "doc.badge.gearshape.fill"
        case "plist", "json", "xml", "txt", "log": return "doc.text.fill"
        default: return "doc.fill"
        }
    }

    private func iconColor(for item: NiKFileItem) -> Color {
        if item.isDirectory { return .blue }
        switch item.url.pathExtension.lowercased() {
        case "ipa": return .indigo
        case "zip": return .purple
        case "p12": return .orange
        case "mobileprovision": return .teal
        default: return .gray
        }
    }

    private func handleTap(_ item: NiKFileItem) {
        if isSelecting {
            if selectedIDs.contains(item.id) { selectedIDs.remove(item.id) }
            else { selectedIDs.insert(item.id) }
            return
        }
        let ext = item.url.pathExtension.lowercased()
        if ext == "zip" {
            zipTarget = item
        } else if ext == "ipa" {
            ipaTarget = item
        } else if ext == "p12" || ext == "mobileprovision" {
            startCertImportFromPair(item.url)
        } else if ext == "plist" {
            typedPlistDoc = NiKPreviewDocument(url: item.url)
        } else if ["txt", "text", "json", "mobileconfig", "xml", "yaml", "yml", "md", "log", "csv", "strings", "conf", "cfg", "ini", "js", "css", "html", "swift", "sh"].contains(ext) || ext.isEmpty {
            editorDoc = NiKPreviewDocument(url: item.url)
        } else {
            previewDoc = NiKPreviewDocument(url: item.url)
        }
    }

    private func reload() {
        do {
            _ = try browser.selected.location.resolve(in: browser.root)
            let urls = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: browser.selected.showsHidden ? [] : [.skipsHiddenFiles])
            items = try urls.compactMap { url in
                let vals = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                guard vals.isSymbolicLink != true else { return nil }
                return NiKFileItem(url: url, name: url.lastPathComponent, isDirectory: vals.isDirectory ?? false,
                    size: Int64(vals.fileSize ?? 0), modifiedAt: vals.contentModificationDate ?? Date())
            }
            listingError = nil
        } catch { items = []; listingError = error.localizedDescription }
    }

    private func createFolder() {
        do {
            let target = try NiKFileOperations.child(named: newFolderName, in: directory)
            let lease = try NiKManagedFileAccess.reserve([target])
            defer { NiKFileMutationReservations.shared.release(lease) }
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            newFolderName = ""
            reload()
        } catch { alertMessage = error.localizedDescription }
    }

    private func performRename() {
        guard let target = renameTarget else { return }
        do {
            let dest = try NiKFileOperations.child(named: renameText, in: target.url.deletingLastPathComponent())
            let lease = try NiKManagedFileAccess.reserve([target.url, dest])
            defer { NiKFileMutationReservations.shared.release(lease) }
            if dest != target.url { try FileManager.default.moveItem(at: target.url, to: dest) }
            renameTarget = nil
            reload()
        } catch { alertMessage = error.localizedDescription }
    }

    private func deleteSelected() { trashItems(items.filter { selectedIDs.contains($0.id) }) }
    private func trashItems(_ targets: [NiKFileItem]) {
        guard !fileBusy, !targets.isEmpty else { return }
        fileBusy = true
        Task {
            defer { fileBusy = false }
            var failures: [String] = []
            for item in targets {
                do { try await NiKTrashController.shared.trash(item.url); selectedIDs.remove(item.id) }
                catch { failures.append(item.name + ": " + error.localizedDescription) }
            }
            isSelecting = !selectedIDs.isEmpty
            reload()
            if !failures.isEmpty {
                alertMessage = failures.prefix(20).joined(separator: "\n")
                if failures.count > 20 { alertMessage = (alertMessage ?? "") + "\n+ \(failures.count - 20) " + t("lỗi khác", "more errors") }
            }
        }
    }

    private func unzipHere(_ url: URL) {
        guard !fileBusy else { return }
        fileBusy = true
        Task {
            defer { fileBusy = false }
            do {
                let dest = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent)
                let lease = try NiKManagedFileAccess.reserve([dest])
                defer { NiKFileMutationReservations.shared.release(lease) }
                try await Task.detached { try NiKArchive.extract(url, to: dest) }.value
                reload()
            } catch { alertMessage = error.localizedDescription }
        }
    }

    private func startCertImportFromZip(_ url: URL) {
        do {
            let extracted = try NiKCertZipHelper.extractPairAndPassword(from: url)
            temporaryFiles.clear()
            temporaryFiles.retain(extracted.tempDir)
            certPendingP12 = extracted.p12
            certPendingProvision = extracted.provision
            certPasswordInput = extracted.password ?? ""
            showCertPasswordPrompt = true
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func startCertImportFromPair(_ url: URL) {
        let pair = NiKCertZipHelper.findPairInDirectory(for: url)
        guard let p12 = pair.p12 else {
            alertMessage = t("Không tìm thấy tệp .p12 cặp đôi trong cùng thư mục.", "No matching .p12 file found in the same folder.")
            return
        }
        guard let prov = pair.provision else {
            alertMessage = t("Không tìm thấy tệp .mobileprovision cặp đôi trong cùng thư mục.", "No matching .mobileprovision file found in the same folder.")
            return
        }
        certPendingP12 = p12
        certPendingProvision = prov
        certPasswordInput = ""
        showCertPasswordPrompt = true
    }

    private func completeCertImport() {
        guard let p12 = certPendingP12, let prov = certPendingProvision else { return }
        do {
            let store = NiKCertificateStore.shared
            let saved = try store.importProfile(p12URL: p12, provisionURL: prov, password: certPasswordInput, customName: "")
            if defaultCertificate.isEmpty {
                defaultCertificate = saved.id.uuidString
            }
            alertMessage = t("Đã lưu chứng chỉ: ", "Saved certificate: ") + saved.name
        } catch {
            alertMessage = error.localizedDescription
        }
        clearPendingCertificate()
    }
    private func clearPendingCertificate() {
        certPendingP12 = nil
        certPendingProvision = nil
        certPasswordInput = ""
        temporaryFiles.clear()
    }
}

private struct SheetModifier: ViewModifier {
    @Binding var importing: Bool
    let directory: URL
    @Binding var previewDoc: NiKPreviewDocument?
    @Binding var hexTarget: NiKPreviewDocument?
    @Binding var shareItem: NiKShareItem?
    @Binding var folderTarget: NiKFolderTarget?
    @Binding var alertMessage: String?
    @Binding var busy: Bool
    let onReload: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $importing) {
                NiKFilePicker { result in
                    if case .success(let url) = result {
                        Task {
                            busy = true
                            defer { busy = false }
                            do {
                                let destination = directory
                                try NiKManagedFileAccess.validateCreationDirectory(destination)
                                _ = try await Task.detached { try NiKFileImport.copy(url, into: destination) }.value
                                onReload()
                            } catch { alertMessage = error.localizedDescription }
                        }
                    }
                }
            }
            .sheet(item: $previewDoc) { doc in NiKQuickLook(url: doc.url) }
            .sheet(item: $hexTarget) { doc in NiKHexViewerSheet(url: doc.url) }
            .sheet(item: $shareItem) { item in NiKShareSheet(items: [item.url]) }
            .sheet(item: $folderTarget) { target in
                NiKFolderPickerSheet(item: target.item, isCopy: target.isCopy) { onReload() }
            }
    }
}

private struct DialogAlertModifier: ViewModifier {
    let t: (String, String) -> String
    @Binding var creatingFolder: Bool
    @Binding var newFolderName: String
    @Binding var renameTarget: NiKFileItem?
    @Binding var renameText: String
    @Binding var zipTarget: NiKFileItem?
    @Binding var ipaTarget: NiKFileItem?
    @Binding var showCertPasswordPrompt: Bool
    @Binding var certPasswordInput: String
    @Binding var alertMessage: String?

    let onCreateFolder: () -> Void
    let onRename: () -> Void
    let onUnzip: (URL) -> Void
    let onCertZip: (URL) -> Void
    let onPreview: (URL) -> Void
    let onShare: (URL) -> Void
    let onInstall: (URL) -> Void
    let onSaveCert: () -> Void
    let onCancelCert: () -> Void

    func body(content: Content) -> some View {
        content
            .alert(t("Thư mục mới", "New Folder"), isPresented: $creatingFolder) {
                TextField(t("Tên thư mục", "Folder name"), text: $newFolderName)
                Button(t("Tạo", "Create"), action: onCreateFolder)
                Button(t("Hủy", "Cancel"), role: .cancel) {}
            }
            .alert(t("Đổi tên", "Rename"), isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField(t("Tên mới", "New name"), text: $renameText)
                Button(t("Lưu", "Save"), action: onRename)
                Button(t("Hủy", "Cancel"), role: .cancel) { renameTarget = nil }
            }
            .confirmationDialog(zipTarget?.name ?? "ZIP", isPresented: Binding(
                get: { zipTarget != nil },
                set: { if !$0 { zipTarget = nil } }
            )) {
                if let z = zipTarget {
                    Button(t("Nhập làm Chứng chỉ (.zip)", "Import as Certificate (.zip)")) { onCertZip(z.url) }
                    Button(t("Giải nén tại đây", "Unzip Here")) { onUnzip(z.url) }
                    Button(t("Xem trước", "Preview")) { onPreview(z.url) }
                    Button(t("Chia sẻ", "Share")) { onShare(z.url) }
                }
                Button(t("Hủy", "Cancel"), role: .cancel) {}
            }
            .confirmationDialog(ipaTarget?.name ?? "IPA", isPresented: Binding(
                get: { ipaTarget != nil },
                set: { if !$0 { ipaTarget = nil } }
            )) {
                if let ipa = ipaTarget {
                    if NiKSignedFileAccess.available(ipa.url.path) != nil {
                        Button(t("Cài đặt", "Install")) { onInstall(ipa.url) }
                    }
                    Button(t("Nhập vào thư viện ký", "Import for Signing")) {
                        Task { await NiKLibrary.shared.receive(ipa.url) }
                    }
                    Button(t("Xem trước", "Preview")) { onPreview(ipa.url) }
                    Button(t("Giải nén tại đây", "Unzip Here")) { onUnzip(ipa.url) }
                    Button(t("Chia sẻ", "Share")) { onShare(ipa.url) }
                }
                Button(t("Hủy", "Cancel"), role: .cancel) {}
            }
            .alert(t("Mật khẩu Chứng chỉ (.p12)", "Certificate Password (.p12)"), isPresented: $showCertPasswordPrompt) {
                SecureField(t("Nhập mật khẩu .p12", "Enter .p12 password"), text: $certPasswordInput)
                Button(t("Lưu chứng chỉ", "Save Certificate"), action: onSaveCert)
                Button(t("Hủy", "Cancel"), role: .cancel, action: onCancelCert)
            } message: {
                Text(t("Nhập mật khẩu của tệp .p12 để lưu vào kho chứng chỉ.", "Enter the .p12 password to save to your certificate library."))
            }
            .alert(t("Thông báo", "Notice"), isPresented: Binding(
                get: { alertMessage != nil },
                set: { if !$0 { alertMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(alertMessage ?? "")
            }
    }
}

