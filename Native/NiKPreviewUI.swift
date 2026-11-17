import UIKit
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation
import ImageIO

struct NiKLibraryItem: Codable, Identifiable {
    var id = UUID()
    var title: String
    var version: String
    var bundleID: String
    var filename: String
    var certificateID: UUID?
    var options = NiKSigningOptions()
    var signedPath: String?
}

@MainActor final class NiKLibrary: ObservableObject {
    @Published var items: [NiKLibraryItem] = []
    @Published var error = ""
    static let shared = NiKLibrary()
    nonisolated static var root: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("IPALibrary") }
    @Published var receiving = false
    @Published var notice = ""
    private var index: URL { Self.root.appendingPathComponent("library.json") }
    init() {
        do {
            try FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: index.path) { items = try JSONDecoder().decode([NiKLibraryItem].self, from: Data(contentsOf: index)) }
        } catch { self.error = error.localizedDescription }
    }
    @discardableResult func save(_ item: NiKLibraryItem) -> Bool {
        var updated = items
        if let i = updated.firstIndex(where: { $0.id == item.id }) { updated[i] = item }
        else { updated.insert(item, at: 0) }
        do {
            try JSONEncoder().encode(updated).write(to: index, options: .atomic)
            items = updated
            error = ""
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func remove(_ item: NiKLibraryItem) throws {
        let updated = items.filter { $0.id != item.id }
        let data = try JSONEncoder().encode(updated)
        // Commit the index before publishing the changed list.
        try data.write(to: index, options: .atomic)
        items = updated
        if FileManager.default.fileExists(atPath: item.ipaURL.path) {
            try FileManager.default.removeItem(at: item.ipaURL)
        }
    }
    func receive(_ url: URL) async {
        guard !receiving else { error = "Đang nhập một IPA khác. Hãy đợi hoàn tất rồi thử lại."; return }
        error = ""
        receiving = true
        defer { receiving = false }
        do {
            let item = try await Task.detached { try Self.importIPA(url) }.value
            guard save(item) else {
                try? FileManager.default.removeItem(at: item.ipaURL)
                if let icon = item.iconURL { try? FileManager.default.removeItem(at: icon) }
                return
            }
            notice = "Đã nhập \(item.title) vào thư viện IPA."
        } catch { self.error = error.localizedDescription }
    }
    nonisolated static func importIPA(_ url: URL) throws -> NiKLibraryItem {
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
            guard data.count + chunk.count <= 1_048_576 else { throw NiKError("Info.plist vượt 1 MB.") }
            data.append(chunk)
        }
        guard crc == metadata[0].checksum,
              let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { throw NiKError("Không đọc được IPA.") }
        let filename = UUID().uuidString + ".ipa"
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: local, to: root.appendingPathComponent(filename))
        // Icon extraction is optional. Missing/asset-catalog-only icons use the UI fallback.
        let appPath = String(metadata[0].path.dropLast("Info.plist".count))
        let icons = info["CFBundleIcons"] as? [String: Any]
        let primary = icons?["CFBundlePrimaryIcon"] as? [String: Any]
        let names = primary?["CFBundleIconFiles"] as? [String] ?? info["CFBundleIconFiles"] as? [String] ?? []
        for name in names.reversed() {
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
    @AppStorage("nik.mode") private var mode = ""
    @AppStorage("nik.theme") private var theme = "system"
    @AppStorage("nik.language") private var language = "vi"
    @AppStorage("nik.certPrompted") private var certPrompted = false
    @StateObject private var library = NiKLibrary.shared
    @StateObject private var certificates = NiKCertificateStore.shared
    @State private var choice = "both"
    @State private var tab = 0
    @State private var prompt = false
    @EnvironmentObject private var appState: AppState
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    private var hasSigner: Bool { mode == "sign" || mode == "both" }
    var body: some View {
        Group {
            if mode.isEmpty { welcome }
            else {
               activeTabView
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .safeAreaInset(edge: .bottom, spacing: 0) { liquidGlassTabBar }
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .tint(.cyan)
        .preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil)
        .onAppear { configure() }
        .onChange(of: mode) { _, _ in configure() }
        .onChange(of: library.notice) { _, notice in if !notice.isEmpty && hasSigner { tab = 0 } }
        .alert(t("Thêm chứng chỉ ký?", "Add Signing Certificate?"), isPresented: $prompt) {
            Button(t("Nhập chứng chỉ", "Import Certificate")) { tab = 3 }
            Button(t("Để sau", "Later"), role: .cancel) {}
        } message: { Text(t("Quản lý nhiều chứng chỉ tại Cài đặt. Bạn có thể chọn riêng cho từng IPA.", "Manage multiple certificates in Settings. You can choose one for each IPA.")) }
    }
    private func configure() {
        guard !mode.isEmpty else { return }
        if mode == "tools" && tab == 0 { tab = 1 }
        if mode == "sign" && tab == 1 { tab = 0 }
        if mode != "sign" { appState.detectSupport() }
        if hasSigner && !certPrompted { certPrompted = true; prompt = true }
    }
    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer(); NiKBrand()
            Text("Chào mừng đến NiKSign").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(t("Chọn cách bạn muốn sử dụng", "Choose how you want to use it")).foregroundStyle(.secondary)
            ForEach(["sign", "tools", "both"], id: \.self) { value in
                Button { choice = value } label: {
                    HStack {
                        Image(systemName: value == "sign" ? "signature" : "square.stack.3d.up").font(.title2)
                        VStack(alignment: .leading) {
                            Text(value == "sign" ? t("Ký IPA", "Sign IPA") : value == "tools" ? "3105" : "Cả hai").font(.headline)
                            Text(value == "sign" ? "Quản lý, tùy chỉnh và ký ứng dụng" : value == "tools" ? "Dự án, ứng dụng và công cụ" : "Đầy đủ tính năng NiKSign").font(.caption).foregroundStyle(.secondary)
                        }; Spacer(); Image(systemName: choice == value ? "checkmark.circle.fill" : "circle")
                    }.padding().background(choice == value ? Color.cyan.opacity(0.12) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                }.buttonStyle(.plain)
            }
            Text("Bạn có thể đổi trong Cài đặt.").font(.footnote).foregroundStyle(.secondary)
            Button("Tiếp tục") { mode = choice }.buttonStyle(.borderedProminent).controlSize(.large)
            Spacer()
        }.padding(24).frame(maxWidth: .infinity).background(Color(uiColor: .systemGroupedBackground))
    }
    private var settings: some View {
        NiKSettingsView(certificates: certificates, library: library)
    }
    private var activeTabView: some View {
        TabView(selection: $tab) {
            if hasSigner {
                NiKLibraryView(library: library, certificates: certificates)
                    .tag(0).toolbar(.hidden, for: .tabBar)
            }
            if mode != "sign" {
                NiKHubPreview().tag(1).toolbar(.hidden, for: .tabBar)
            }
            NiKFilesHome().tag(2).toolbar(.hidden, for: .tabBar)
            settings.tag(3).toolbar(.hidden, for: .tabBar)
        }
    }

    @ViewBuilder
    private var liquidGlassTabBar: some View {
        HStack(spacing: 4) {
            if hasSigner {
                tabBarButton(index: 0, title: t("Ký IPA", "Sign IPA"), icon: "signature")
            }
            if mode != "sign" {
                tabBarButton(index: 1, title: "3105", icon: "square.stack.3d.up")
            }
            tabBarButton(index: 2, title: t("Tệp", "Files"), icon: "folder.fill")
            tabBarButton(index: 3, title: t("Cài đặt", "Settings"), icon: "gearshape.fill")
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
                    searchBarCard
                    certificateBannerCard
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
                            if !library.error.isEmpty { errorMessage = library.error }
                        }
                    }
                }
            }
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
            HStack(spacing: 12) {
                NiKAppIcon(url: item.iconURL, size: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(item.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text("v\(item.version) · \(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
    private var trailingMenu: some View {
        Menu {
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
    @AppStorage("nik.defaultCertificate") private var defaultCertificate = ""
    @AppStorage("nik.language") private var language = "vi"
    @Environment(\.dismiss) private var dismiss

    @State private var signing = false
    @State private var progressText = ""
    @State private var tweakPicker = false
    @State private var signedURL: URL?
    @State private var errorMessage: String?

    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }

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
                if let signedURL {
                    signedResultCard(signedURL)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 96)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) {
                        do { try library.remove(item); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    } label: {
                        Label(t("Xóa IPA khỏi thư viện", "Remove IPA"), systemImage: "trash")
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
        .disabled(signing)
        .navigationBarBackButtonHidden(signing)
        .onAppear { signedURL = item.signedPath.map { URL(fileURLWithPath: $0) } }
        .onDisappear { if library.items.contains(where: { $0.id == item.id }) { library.save(item) } }
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
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var optionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("Tùy chọn chỉnh sửa", "Signing Options"))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            TextField(t("Tên ứng dụng mới (tùy chọn)", "Custom Display Name"), text: $item.options.customDisplayName)
                .textFieldStyle(.roundedBorder)
            TextField(t("Bundle ID mới (tùy chọn)", "Custom Bundle ID"), text: $item.options.customBundleID)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            TextField(t("Phiên bản mới (tùy chọn)", "Custom Version"), text: $item.options.customVersion)
                .textFieldStyle(.roundedBorder)
            DisclosureGroup(t("Cấu hình nâng cao", "Advanced Options")) {
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
                NavigationLink(t("Kiểm tra tệp", "Inspect Files")) { NiKInspectView() }
            }
            Button(t("Lưu tùy chỉnh", "Save Options")) { library.save(item) }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    @ViewBuilder
    private var signActionCard: some View {
        Button {
            Task { await sign() }
        } label: {
            HStack(spacing: 10) {
                if signing {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "signature")
                }
                Text(signing ? progressText : t("Ký IPA ngay", "Sign IPA Now"))
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(activeCertificate == nil || signing ? Color.gray.opacity(0.45) : Color.accentColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .disabled(activeCertificate == nil || signing)
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
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func sign() async {
        guard let cert = activeCertificate else {
            errorMessage = t("Không đọc được thông tin chứng chỉ.", "Unable to load certificate credentials.")
            return
        }
        library.save(item)
        signing = true
        progressText = t("Đang ký IPA...", "Signing IPA...")
        defer { signing = false }
        do {
            let credentials = try certificates.credentials(for: cert)
            let output = try await SigningService.shared.signDetailed(
                ipa: item.ipaURL,
                p12: credentials.p12,
                profile: credentials.provision,
                password: credentials.password,
                options: item.options
            )
            signedURL = output.ipaURL
            item.signedPath = output.ipaURL.path
            library.save(item)
        } catch {
            errorMessage = error.localizedDescription
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
                    savedProfileRow(profile)
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
            TextField(t("Tên gợi nhớ (tùy chọn)", "Custom Name (optional)"), text: $name)
                .textFieldStyle(.roundedBorder)
            SecureField(t("Mật khẩu tệp .p12", ".p12 Password"), text: $password)
                .textFieldStyle(.roundedBorder)
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

struct NiKLocalFiles: View {
    let directory: URL
    let title: String
    init(directory: URL, title: String = "Tệp") {
        self.directory = directory
        self.title = title
    }

    @AppStorage("nik.language") private var language = "vi"
    @AppStorage("nik.defaultCertificate") private var defaultCertificate = ""

    @State private var items: [NiKFileItem] = []
    @State private var query = ""
    @State private var sort: NiKFilesSort = .name
    @State private var isSelecting = false
    @State private var selectedIDs: Set<String> = []

    @State private var importing = false
    @State private var creatingFolder = false
    @State private var newFolderName = ""

    @State private var renameTarget: NiKFileItem?
    @State private var renameText = ""
    @State private var folderTarget: NiKFolderTarget?
    @State private var previewDoc: NiKPreviewDocument?
    @State private var hexTarget: NiKPreviewDocument?
    @State private var shareItem: NiKShareItem?

    @State private var zipTarget: NiKFileItem?
    @State private var ipaTarget: NiKFileItem?
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
    }

    @ViewBuilder
    private var mainView: some View {
        ScrollView {
            VStack(spacing: 12) {
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
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                trailingToolbarMenu
            }
        }
        .onAppear { reload() }
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
            Button(t("Xóa", "Delete"), role: .destructive) {
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
        if filtered.isEmpty {
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
                    rowEntry(item)
                }
            }
        }
    }

    @ViewBuilder
    private func rowEntry(_ item: NiKFileItem) -> some View {
        if item.isDirectory && !isSelecting {
            NavigationLink {
                NiKLocalFiles(directory: item.url, title: item.name)
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
            Button {
                hexTarget = NiKPreviewDocument(url: item.url)
            } label: {
                Label(t("Xem Hex", "Hex View"), systemImage: "number.square")
            }
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
            do { try FileManager.default.removeItem(at: item.url); reload() }
            catch { alertMessage = error.localizedDescription }
        } label: {
            Label(t("Xóa", "Delete"), systemImage: "trash")
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
        } else {
            previewDoc = NiKPreviewDocument(url: item.url)
        }
    }

    private func reload() {
        do {
            let urls = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
            items = try urls.compactMap { url in
                let vals = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey])
                guard vals.isSymbolicLink != true else { return nil }
                return NiKFileItem(url: url, name: url.lastPathComponent, isDirectory: vals.isDirectory ?? false,
                    size: Int64(vals.fileSize ?? 0), modifiedAt: vals.contentModificationDate ?? Date())
            }
        } catch { alertMessage = error.localizedDescription }
    }

    private func createFolder() {
        do {
            let target = try NiKFileOperations.child(named: newFolderName, in: directory)
            try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
            newFolderName = ""
            reload()
        } catch { alertMessage = error.localizedDescription }
    }

    private func performRename() {
        guard let target = renameTarget else { return }
        do {
            let dest = try NiKFileOperations.child(named: renameText, in: target.url.deletingLastPathComponent())
            if dest != target.url { try FileManager.default.moveItem(at: target.url, to: dest) }
            renameTarget = nil
            reload()
        } catch { alertMessage = error.localizedDescription }
    }

    private func deleteSelected() {
        var failures: [String] = []
        for item in items where selectedIDs.contains(item.id) {
            do { try FileManager.default.removeItem(at: item.url); selectedIDs.remove(item.id) }
            catch { failures.append(item.name + ": " + error.localizedDescription) }
        }
        isSelecting = !selectedIDs.isEmpty
        reload()
        if !failures.isEmpty { alertMessage = failures.joined(separator: "\n") }
    }

    private func unzipHere(_ url: URL) {
        guard !fileBusy else { return }
        fileBusy = true
        Task {
            defer { fileBusy = false }
            do {
                let dest = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent)
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

