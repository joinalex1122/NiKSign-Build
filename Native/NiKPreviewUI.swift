import UIKit
import SwiftUI
import UniformTypeIdentifiers
import ZIPFoundation

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
    func save(_ item: NiKLibraryItem) {
        if let i = items.firstIndex(where: { $0.id == item.id }) { items[i] = item }
        else { items.insert(item, at: 0) }
        do { try JSONEncoder().encode(items).write(to: index, options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    func receive(_ url: URL) async {
        guard !receiving else { error = "Đang nhập một IPA khác. Hãy đợi hoàn tất rồi thử lại."; return }
        receiving = true
        defer { receiving = false }
        do {
            let item = try await Task.detached { try Self.importIPA(url) }.value
            save(item)
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
    @StateObject private var certificates = NiKCertificateStore()
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
               ZStack(alignment: .bottom) {
                        activeTabView
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        liquidGlassTabBar
                    }
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
       let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "3.3.0"; let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "330"; func card<C: View>(@ViewBuilder _ c: () -> C) -> some View { c().padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) }; func row(_ icon: String, _ color: Color, _ title: String, _ sub: String) -> some View { HStack(spacing: 12) { Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 30); VStack(alignment: .leading, spacing: 2) { Text(title).font(.body.weight(.medium)).foregroundStyle(.primary); Text(sub).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) } }; return NavigationStack { ScrollView { VStack(spacing: 12) { card { HStack(spacing: 14) { NiKBrand(); VStack(alignment: .leading, spacing: 4) { Text("NiKSign").font(.title2.bold()); Text("\(t("Phiên bản", "Version")) \(ver) (\(build))").font(.caption).foregroundStyle(.secondary) }; Spacer() } }; card { VStack(spacing: 14) { Menu { Button("Tiếng Việt") { language = "vi" }; Button("English") { language = "en" } } label: { row("globe", .blue, t("Ngôn ngữ", "Language"), language == "en" ? "English" : "Tiếng Việt") }; Divider(); Menu { Button(t("Chỉ ký IPA", "Sign IPA only")) { mode = "sign" }; Button(t("Chỉ 3105", "3105 only")) { mode = "tools" }; Button(t("Cả hai", "Both")) { mode = "both" } } label: { row("slider.horizontal.3", .indigo, t("Chế độ", "Mode"), mode == "sign" ? t("Chỉ ký IPA", "Sign IPA only") : mode == "tools" ? t("Chỉ 3105", "3105 only") : t("Cả hai", "Both")) }; Divider(); Menu { Button(t("Theo hệ thống", "System")) { theme = "system" }; Button(t("Sáng", "Light")) { theme = "light" }; Button(t("Tối", "Dark")) { theme = "dark" } } label: { row("paintbrush", .purple, t("Giao diện", "Appearance"), theme == "light" ? t("Sáng", "Light") : theme == "dark" ? t("Tối", "Dark") : t("Theo hệ thống", "System")) } } }; card { NavigationLink { NiKCertificateSettings(store: certificates) } label: { row("signature", .orange, t("Chứng chỉ", "Certificates"), "\(certificates.profiles.count) \(t("chứng chỉ đã lưu", "saved certificates"))") } }; card { VStack(spacing: 14) { Link(destination: URL(string: "https://t.me/nikvn21")!) { row("paperplane.fill", .cyan, t("Kênh Telegram", "Telegram Channel"), t("@nikvn21 · Cộng đồng & cập nhật NiKSign", "@nikvn21 · Community & NiKSign updates")) }; Divider(); Link(destination: URL(string: "https://github.com/joinalex1122/NiKSign-Build")!) { row("globe", .teal, t("Trang web & Mã nguồn", "Website & Source Code"), "github.com/joinalex1122/NiKSign-Build") }; Divider(); NavigationLink { List { Section(t("Sao chép nhanh", "Quick Copy")) { Button { UIPasteboard.general.string = "niksign://" } label: { Label("niksign://", systemImage: "doc.on.doc") }; Button { UIPasteboard.general.string = "threeoneosfive://" } label: { Label("threeoneosfive://", systemImage: "doc.on.doc") } }; Section(t("Hướng dẫn", "Guide")) { Text(t("Dùng niksign:// hoặc threeoneosfive:// để mở nhanh ứng dụng hoặc truyền tệp IPA từ ứng dụng khác.", "Use niksign:// or threeoneosfive:// to quickly open the app or pass IPA files from other apps.")).font(.footnote).foregroundStyle(.secondary) } }.navigationTitle("URL Scheme") } label: { row("link", .green, "URL Scheme", "niksign:// · threeoneosfive://") }; Divider(); NavigationLink { List { Section(t("Trạng thái hiện tại", "Current Status")) { Text(library.notice.isEmpty ? t("Không có thông báo mới", "No recent notices") : library.notice).font(.footnote) }; Section(t("Thư mục tạm", "Temporary Directory")) { Text(FileManager.default.temporaryDirectory.path).font(.caption2).foregroundStyle(.secondary); Button(t("Dọn bộ nhớ đệm", "Clear Cache"), role: .destructive) { let tmp = FileManager.default.temporaryDirectory; (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil))?.forEach { try? FileManager.default.removeItem(at: $0) } } } }.navigationTitle(t("Nhật ký", "Logs")) } label: { row("text.alignleft", .gray, t("Nhật ký", "Logs"), t("Trạng thái & dọn bộ nhớ đệm", "Status & cache cleanup")) } } }; card { VStack(spacing: 14) { NavigationLink { ScrollView { Text(t("NiKSign xử lý hoàn toàn ngoại tuyến trên thiết bị của bạn. Bạn tự chịu trách nhiệm về chứng chỉ và tệp IPA sử dụng.", "NiKSign processes everything completely offline on your device. You are responsible for the certificates and IPA files you use.")).padding() }.navigationTitle(t("Điều khoản dịch vụ", "Terms of Service")) } label: { row("doc.text.fill", .blue, t("Điều khoản dịch vụ", "Terms of Service"), t("Sử dụng ngoại tuyến trên thiết bị", "Offline on-device usage")) }; Divider(); NavigationLink { ScrollView { Text(t("NiKSign cam kết xử lý ngoại tuyến trên thiết bị, không thu thập, lưu trữ hay gửi dữ liệu cá nhân, chứng chỉ hay tệp IPA lên máy chủ bên ngoài.", "NiKSign is committed to offline on-device processing and does not collect, store, or transmit personal data, certificates, or IPA files to external servers.")).padding() }.navigationTitle(t("Chính sách bảo mật", "Privacy Policy")) } label: { row("lock.shield.fill", .mint, t("Chính sách bảo mật", "Privacy Policy"), t("Cam kết xử lý ngoại tuyến", "Offline processing commitment")) }; Divider(); NavigationLink { NiKLicensesView() } label: { row("doc.plaintext", .secondary, t("Thành phần bên thứ ba và giấy phép", "Third-Party Components & Licenses"), "ZIPFoundation · OpenSSL") } } } }.padding() }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle(t("Cài đặt", "Settings"))
        }
    }
    @ViewBuilder
    private var activeTabView: some View {
        switch tab {
        case 0 where hasSigner:
            NiKLibraryView(library: library, certificates: certificates)
        case 1 where mode != "sign":
            NiKHubPreview()
        case 2:
            NavigationStack { NiKFilesHome() }
        case 3:
            settings
        default:
            if hasSigner {
                NiKLibraryView(library: library, certificates: certificates)
            } else {
                NavigationStack { NiKFilesHome() }
            }
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

enum NiKCertZipHelper {
    static func extractPairAndPassword(from zipURL: URL) throws -> (p12: URL, provision: URL, password: String?, tempDir: URL) {
        let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("nikcert-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: zipURL, to: tmpDir)

        var p12URL: URL?
        var provURL: URL?
        var txtURLs: [URL] = []

        if let enumerator = FileManager.default.enumerator(at: tmpDir, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let file as URL in enumerator {
                let path = file.path
                if path.contains("__MACOSX") || file.lastPathComponent.hasPrefix("._") { continue }
                let ext = file.pathExtension.lowercased()
                if ext == "p12" && p12URL == nil {
                    p12URL = file
                } else if ext == "mobileprovision" && provURL == nil {
                    provURL = file
                } else if ext == "txt" {
                    txtURLs.append(file)
                }
            }
        }

        guard let foundP12 = p12URL else {
            throw NSError(domain: "NiKCert", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tệp .p12 trong gói .zip"])
        }
        guard let foundProv = provURL else {
            throw NSError(domain: "NiKCert", code: 2, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy tệp .mobileprovision trong gói .zip"])
        }

        var foundPass: String?
        let sortedTxt = txtURLs.sorted {
            let a = $0.lastPathComponent.lowercased().contains("pass")
            let b = $1.lastPathComponent.lowercased().contains("pass")
            return a && !b
        }
        for txt in sortedTxt {
            if let raw = try? String(contentsOf: txt, encoding: .utf8) {
                let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    foundPass = trimmed
                    break
                }
            }
        }
        return (foundP12, foundProv, foundPass, tmpDir)
    }

    static func findPairInDirectory(for fileURL: URL) -> (p12: URL?, provision: URL?) {
        let folder = fileURL.deletingLastPathComponent()
        let items = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        let ext = fileURL.pathExtension.lowercased()
        let base = fileURL.deletingPathExtension().lastPathComponent.lowercased()

        let p12Candidates = items.filter { $0.pathExtension.lowercased() == "p12" && !$0.lastPathComponent.hasPrefix("._") }
        let provCandidates = items.filter { $0.pathExtension.lowercased() == "mobileprovision" && !$0.lastPathComponent.hasPrefix("._") }

        if ext == "p12" {
            let matchedProv = provCandidates.first { $0.deletingPathExtension().lastPathComponent.lowercased() == base } ?? provCandidates.first
            return (fileURL, matchedProv)
        } else if ext == "mobileprovision" {
            let matchedP12 = p12Candidates.first { $0.deletingPathExtension().lastPathComponent.lowercased() == base } ?? p12Candidates.first
            return (matchedP12, fileURL)
        }
        return (p12Candidates.first, provCandidates.first)
    }

    static func documentsCertificateFiles() -> [URL] {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return [] }
        var results: [URL] = []
        if let enumerator = FileManager.default.enumerator(at: docs, includingPropertiesForKeys: [.isRegularFileKey]) {
            for case let file as URL in enumerator {
                let path = file.path
                if path.contains("__MACOSX") || file.lastPathComponent.hasPrefix("._") { continue }
                let ext = file.pathExtension.lowercased()
                if ext == "p12" || ext == "mobileprovision" || ext == "zip" {
                    results.append(file)
                }
            }
        }
        return results.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }
}

struct NiKLibraryView: View {
    @ObservedObject var library: NiKLibrary
    @ObservedObject var certificates: NiKCertificateStore
    @AppStorage("nik_language") private var language = "vi"
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
                            if let err = library.error { errorMessage = err }
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
            VStack(spacing: 10) {
                ForEach(filtered) { item in
                    ipaCardRow(item)
                }
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
    @AppStorage("nik_language") private var language = "vi"
    @Environment(\.dismiss) private var dismiss

    @State private var signing = false
    @State private var progressText = ""
    @State private var signedURL: URL?
    @State private var errorMessage: String?

    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }

    private var activeCertificate: NiKCertificateProfile? {
        if let id = item.certificateID, let match = certificates.profiles.first(where: { $0.id == id }) {
            return match
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
                        library.remove(item)
                        dismiss()
                    } label: {
                        Label(t("Xóa IPA khỏi thư viện", "Remove IPA"), systemImage: "trash")
                    }
                } label: {
                    NiKGlassCircleIcon(systemName: "ellipsis")
                }
            }
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
                    get: { item.certificateID ?? activeCertificate?.id },
                    set: {
                        item.certificateID = $0
                        library.save(item)
                    }
                )) {
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
        guard let cert = activeCertificate,
              let credentials = try? certificates.credentials(for: cert) else {
            errorMessage = t("Không đọc được thông tin chứng chỉ.", "Unable to load certificate credentials.")
            return
        }
        library.save(item)
        signing = true
        progressText = t("Đang ký IPA...", "Signing IPA...")
        defer { signing = false }
        do {
            let output = try await SigningService.shared.signDetailed(
                ipa: item.ipaURL,
                p12: credentials.p12,
                profile: credentials.provision,
                password: credentials.password,
                options: item.options
            )
            signedURL = output.ipaURL
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
    @AppStorage("nik_language") private var language = "vi"

    @State private var name = ""
    @State private var password = ""
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
                store.removeProfile(profile)
                if isDefault {
                    defaultCertificate = store.profiles.first?.id.uuidString ?? ""
                }
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
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let tempCopy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        do {
            try FileManager.default.copyItem(at: url, to: tempCopy)
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
            p12URL = extracted.p12
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
        } catch {
            message = error.localizedDescription
            isSuccess = false
        }
    }
}

struct NiKLocalFiles: View {
    let directory: URL
    let title: String

    @AppStorage("nik_language") private var language = "vi"
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
            try? FileManager.default.removeItem(at: item.url)
            reload()
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
            onSaveCert: completeCertImport
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
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        items = urls.map { url in
            let vals = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            return NiKFileItem(
                url: url,
                name: url.lastPathComponent,
                isDirectory: vals?.isDirectory ?? false,
                size: Int64(vals?.fileSize ?? 0),
                modifiedAt: vals?.contentModificationDate ?? Date()
            )
        }
    }

    private func createFolder() {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let target = directory.appendingPathComponent(trimmed)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        reload()
    }

    private func performRename() {
        guard let target = renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let dest = target.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        try? FileManager.default.moveItem(at: target.url, to: dest)
        renameTarget = nil
        reload()
    }

    private func deleteSelected() {
        for item in items where selectedIDs.contains(item.id) {
            try? FileManager.default.removeItem(at: item.url)
        }
        selectedIDs.removeAll()
        isSelecting = false
        reload()
    }

    private func unzipHere(_ url: URL) {
        let dest = url.deletingLastPathComponent().appendingPathComponent(url.deletingPathExtension().lastPathComponent)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
            try FileManager.default.unzipItem(at: url, to: dest)
            reload()
        } catch {
            alertMessage = error.localizedDescription
        }
    }

    private func startCertImportFromZip(_ url: URL) {
        do {
            let extracted = try NiKCertZipHelper.extractPairAndPassword(from: url)
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
            let store = NiKCertificateStore()
            let saved = try store.importProfile(p12URL: p12, provisionURL: prov, password: certPasswordInput, customName: "")
            if defaultCertificate.isEmpty {
                defaultCertificate = saved.id.uuidString
            }
            alertMessage = t("Đã lưu chứng chỉ: ", "Saved certificate: ") + saved.name
        } catch {
            alertMessage = error.localizedDescription
        }
        certPendingP12 = nil
        certPendingProvision = nil
        certPasswordInput = ""
    }
}

private struct SheetModifier: ViewModifier {
    @Binding var importing: Bool
    let directory: URL
    @Binding var previewDoc: NiKPreviewDocument?
    @Binding var hexTarget: NiKPreviewDocument?
    @Binding var shareItem: NiKShareItem?
    @Binding var folderTarget: NiKFolderTarget?
    let onReload: () -> Void

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $importing) {
                NiKFilePicker { result in
                    if case .success(let url) = result {
                        Task {
                            _ = try? NiKFileImport.copy(url, into: directory)
                            onReload()
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
                    Button(t("Xem trước", "Preview")) { onPreview(ipa.url) }
                    Button(t("Giải nén tại đây", "Unzip Here")) { onUnzip(ipa.url) }
                    Button(t("Chia sẻ", "Share")) { onShare(ipa.url) }
                }
                Button(t("Hủy", "Cancel"), role: .cancel) {}
            }
            .alert(t("Mật khẩu Chứng chỉ (.p12)", "Certificate Password (.p12)"), isPresented: $showCertPasswordPrompt) {
                SecureField(t("Nhập mật khẩu .p12", "Enter .p12 password"), text: $certPasswordInput)
                Button(t("Lưu chứng chỉ", "Save Certificate"), action: onSaveCert)
                Button(t("Hủy", "Cancel"), role: .cancel) { certPasswordInput = "" }
            } message: {
                Text(t("Nhập mật khẩu của tệp .p12 để lưu trực tiếp vào NiKCertificateStore.", "Enter the .p12 password to save directly to NiKCertificateStore."))
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

