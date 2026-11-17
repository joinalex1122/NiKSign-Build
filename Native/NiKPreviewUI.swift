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
                TabView(selection: $tab) {
                    if hasSigner {
                        NiKLibraryView(library: library, certificates: certificates).tabItem { Label(t("Ký IPA", "Sign IPA"), systemImage: "signature") }.tag(0)
                    }
                    if mode != "sign" { NiKHubPreview().tabItem { Label("3105", systemImage: "square.stack.3d.up") }.tag(1) }
                    NavigationStack {
                        NiKFilesHome()
                    }.tabItem { Label(t("Tệp", "Files"), systemImage: "folder") }.tag(2)
                    settings.tabItem { Label(t("Cài đặt",, "Settings"), systemImage: "gearshape") }.tag(3)
                }
            }
        }
        .tint(.cyan)
        .preferredColorScheme(theme == "dark" ? .dark : theme == "light" ? .light : nil)
        .onAppear { configure() }
        .onChange(of: mode) { _, _ in configure() }
        .onChange(of: library.notice) { _, notice in if !notice.isEmpty && hasSigner { tab = 0 } }
        .alert(t("Thêm chứng chỉ ký?",, "Add Signing Certificate?") isPresented: $prompt) {
            Button(t("Nhập chứng chỉ", "Import Certificate")) { tab = 3 }
            Button(t("Để sau", "Later"), role: .cancel) {}
        } message: { Text(t("Quản lý nhiều chứng chỉ tại Cài đặt. Bạn có thể chọn riêng cho từng IPA.") }, "Manage multiple certificates in Settings. You can choose one for each IPA.")
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
            Text(t(("Chọn cách bạn muốn sử dụng"), "Choose how you want to use it").foregroundStyle(.secondary)
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
       let ver = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "3.3.0"; let build = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "330"; func card<C: View>(@ViewBuilder _ c: () -> C) -> some View { c().padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground)).clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) }; func row(_ icon: String, _ color: Color, _ title: String, _ sub: String) -> some View { HStack(spacing: 12) { Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 30); VStack(alignment: .leading, spacing: 2) { Text(title).font(.body.weight(.medium)).foregroundStyle(.primary); Text(sub).font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary) } }; return NavigationStack { ScrollView { VStack(spacing: 12) { card { HStack(spacing: 14) { NiKBrand(); VStack(alignment: .leading, spacing: 4) { Text("NiKSign").font(.title2.bold()); Text("\(t("Phiên bản", "Version")) \(ver) (\(build))").font(.caption).foregroundStyle(.secondary) }; Spacer() } }; card { VStack(spacing: 14) { Menu { Button("Tiếng Việt") { language = "vi" }; Button("English") { language = "en" } } label: { row("globe", .blue, t("Ngôn ngữ", "Language"), language == "en" ? "English" : "Tiếng Việt") }; Divider(); Menu { Button(t("Chỉ ký IPA", "Sign IPA only")) { mode = "sign" }; Button(t("Chỉ 3105", "3105 only")) { mode = "tools" }; Button(t("Cả hai", "Both")) { mode = "both" } } label: { row("slider.horizontal.3", .indigo, t("Chế độ", "Mode"), mode == "sign" ? t("Chỉ ký IPA", "Sign IPA only") : mode == "tools" ? t("Chỉ 3105", "3105 only") : t("Cả hai", "Both")) }; Divider(); Menu { Button(t("Theo hệ thống", "System")) { theme = "system" }; Button(t("Sáng", "Light")) { theme = "light" }; Button(t("Tối", "Dark")) { theme = "dark" } } label: { row("paintbrush", .purple, t("Giao diện", "Appearance"), theme == "light" ? t("Sáng", "Light") : theme == "dark" ? t("Tối", "Dark") : t("Theo hệ thống", "System")) } } }; card { NavigationLink { NiKCertificateSettings(store: certificates) } label: { row("signature", .orange, t("Chứng chỉ", "Certificates"), "\(certificates.certificates.count) \(t("chứng chỉ đã lưu", "saved certificates"))") } }; card { VStack(spacing: 14) { Link(destination: URL(string: "https://t.me/nikvn21")!) { row("paperplane.fill", .cyan, t("Kênh Telegram", "Telegram Channel"), t("@nikvn21 · Cộng đồng & cập nhật NiKSign", "@nikvn21 · Community & NiKSign updates")) }; Divider(); Link(destination: URL(string: "https://github.com/joinalex1122/NiKSign-Build")!) { row("globe", .teal, t("Trang web & Mã nguồn", "Website & Source Code"), "github.com/joinalex1122/NiKSign-Build") }; Divider(); NavigationLink { List { Section(t("Sao chép nhanh", "Quick Copy")) { Button { UIPasteboard.general.string = "niksign://" } label: { Label("niksign://", systemImage: "doc.on.doc") }; Button { UIPasteboard.general.string = "threeoneosfive://" } label: { Label("threeoneosfive://", systemImage: "doc.on.doc") } }; Section(t("Hướng dẫn", "Guide")) { Text(t("Dùng niksign:// hoặc threeoneosfive:// để mở nhanh ứng dụng hoặc truyền tệp IPA từ ứng dụng khác.", "Use niksign:// or threeoneosfive:// to quickly open the app or pass IPA files from other apps.")).font(.footnote).foregroundStyle(.secondary) } }.navigationTitle("URL Scheme") } label: { row("link", .green, "URL Scheme", "niksign:// · threeoneosfive://") }; Divider(); NavigationLink { List { Section(t("Trạng thái hiện tại", "Current Status")) { Text(library.notice.isEmpty ? t("Không có thông báo mới", "No recent notices") : library.notice).font(.footnote) }; Section(t("Thư mục tạm", "Temporary Directory")) { Text(FileManager.default.temporaryDirectory.path).font(.caption2).foregroundStyle(.secondary); Button(t("Dọn bộ nhớ đệm", "Clear Cache"), role: .destructive) { let tmp = FileManager.default.temporaryDirectory; (try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil))?.forEach { try? FileManager.default.removeItem(at: $0) } } } }.navigationTitle(t("Nhật ký", "Logs")) } label: { row("text.alignleft", .gray, t("Nhật ký", "Logs"), t("Trạng thái & dọn bộ nhớ đệm", "Status & cache cleanup")) } } }; card { VStack(spacing: 14) { NavigationLink { ScrollView { Text(t("NiKSign xử lý hoàn toàn ngoại tuyến trên thiết bị của bạn. Bạn tự chịu trách nhiệm về chứng chỉ và tệp IPA sử dụng.", "NiKSign processes everything completely offline on your device. You are responsible for the certificates and IPA files you use.")).padding() }.navigationTitle(t("Điều khoản dịch vụ", "Terms of Service")) } label: { row("doc.text.fill", .blue, t("Điều khoản dịch vụ", "Terms of Service"), t("Sử dụng ngoại tuyến trên thiết bị", "Offline on-device usage")) }; Divider(); NavigationLink { ScrollView { Text(t("NiKSign cam kết xử lý ngoại tuyến trên thiết bị, không thu thập, lưu trữ hay gửi dữ liệu cá nhân, chứng chỉ hay tệp IPA lên máy chủ bên ngoài.", "NiKSign is committed to offline on-device processing and does not collect, store, or transmit personal data, certificates, or IPA files to external servers.")).padding() }.navigationTitle(t("Chính sách bảo mật", "Privacy Policy")) } label: { row("lock.shield.fill", .mint, t("Chính sách bảo mật", "Privacy Policy"), t("Cam kết xử lý ngoại tuyến", "Offline processing commitment")) }; Divider(); NavigationLink { NiKLicensesView() } label: { row("doc.plaintext", .secondary, t("Thành phần bên thứ ba và giấy phép", "Third-Party Components & Licenses"), "ZIPFoundation · OpenSSL") } } } }.padding() }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle(t("Cài đặt", "Settings"))
        }
    }
}

struct NiKLibraryView: View {
    @ObservedObject var library: NiKLibrary
    @ObservedObject var certificates: NiKCertificateStore
    @AppStorage("nik.libraryGrid") private var grid = false
    @State private var query = ""
    @State private var importing = false
    @State private var busy = false
    private var filtered: [NiKLibraryItem] { library.items.filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) || $0.bundleID.localizedCaseInsensitiveContains(query) } }
    var body: some View {
        NavigationStack {
            ScrollView {
                if library.receiving { ProgressView("Đang nhập IPA…").padding() }
                if !library.notice.isEmpty { Text(library.notice).font(.caption).foregroundStyle(.secondary).padding(.horizontal) }
                if library.items.isEmpty { VStack(spacing: 16) { NiKBrand(); Text("Thư viện IPA trống").font(.title2.bold()); Text("Bấm + để nhập IPA từ Tệp.").foregroundStyle(.secondary) }.padding(40) }
                LazyVGrid(columns: grid ? [GridItem(.adaptive(minimum: 150))] : [GridItem(.flexible())], spacing: 12) {
                    ForEach(filtered) { item in
                        NavigationLink { NiKIPADetail(item: item, library: library, certificates: certificates) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack { Image(systemName: "app.fill").font(.largeTitle).foregroundStyle(.cyan); Text(item.title).font(.headline); Spacer() }
                                Text(item.version).font(.caption).foregroundStyle(.secondary)
                                Text(item.signedPath == nil ? "Chưa ký" : "Đã ký").font(.caption).foregroundStyle(item.signedPath == nil ? Color.cyan : Color.green)
                            }.padding().frame(maxWidth: .infinity, alignment: .leading).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
                        }.buttonStyle(.plain)
                    }
                }.padding()
            }.background(Color(uiColor: .systemGroupedBackground)).navigationTitle("Ký IPA")
            .searchable(text: $query, prompt: "Tìm ứng dụng")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { grid.toggle() } label: { Image(systemName: grid ? "list.bullet" : "square.grid.2x2") }.accessibilityLabel("Đổi danh sách/lưới")
                    Button { importing = true } label: { Image(systemName: "plus") }.disabled(library.receiving).accessibilityLabel("Nhập IPA")
                }
            }
            .sheet(isPresented: $importing) {
                NiKFilePicker { result in
                    switch result {
                    case .success(let url): Task { await library.receive(url) }
                    case .failure(let error): library.error = error.localizedDescription
                    }
                }
            }
            .alert("NiKSign", isPresented: Binding(get: { !library.error.isEmpty }, set: { if !$0 { library.error = "" } })) { Button("Đóng") { library.error = "" } } message: { Text(library.error) }
        }
    }
}

struct NiKIPADetail: View {
    @State var item: NiKLibraryItem
    @ObservedObject var library: NiKLibrary
    @ObservedObject var certificates: NiKCertificateStore
    @AppStorage("nik.defaultCertificate") private var defaultCertificate = ""
    @State private var busy = false
    @State private var status = ""
    @State private var tweakPicker = false
    var body: some View {
        Form {
            Section { HStack { NiKBrand(); VStack(alignment: .leading) { Text(item.title).font(.headline); Text(item.bundleID).font(.caption); Text("Bản gốc được giữ lại").font(.caption).foregroundStyle(.secondary) } } }
            Section {
                Picker("Chứng chỉ ký", selection: $item.certificateID) {
                    Text("Mặc định").tag(nil as UUID?)
                    ForEach(certificates.profiles) { Text($0.name).tag(Optional($0.id)) }
                }
            }
            Section("Tùy chỉnh") {
                NavigationLink("Thông tin ứng dụng") {
                    Form {
                        TextField("Tên hiển thị", text: $item.options.customDisplayName)
                        TextField("Bundle ID", text: $item.options.customBundleID).textInputAutocapitalization(.never).autocorrectionDisabled()
                        TextField("Phiên bản", text: $item.options.customVersion)
                        TextField("iOS tối thiểu", text: $item.options.minimumOSVersion)
                        Text("Để trống để giữ giá trị gốc. Đổi iOS tối thiểu không đảm bảo tương thích.").font(.footnote)
                    }.navigationTitle("Thông tin ứng dụng")
                }
                NavigationLink("Cấu hình") {
                    Form {
                        Toggle("Chia sẻ tệp", isOn: $item.options.enableFileSharing)
                        Toggle("Bỏ UISupportedDevices", isOn: $item.options.removeSupportedDevicesRestriction)
                        Toggle("Gỡ App Extensions / Watch", isOn: $item.options.removeExtensions)
                    }.navigationTitle("Cấu hình")
                }
                NavigationLink("Thành phần") {
                    Form {
                        Button("Thêm dylib / deb") { tweakPicker = true }
                        Toggle("Liên kết Weak Dylib", isOn: $item.options.weakDylibInjection)
                        ForEach(item.options.injectedFiles, id: \.self) { url in Text(url.lastPathComponent) }
                        .onDelete { item.options.injectedFiles.remove(atOffsets: $0) }
                    }.navigationTitle("Thành phần")
                }
                NavigationLink("Nâng cao · Kiểm tra tệp") { NiKInspectView() }
                Section("Ký & đóng gói") {
                    Text("Bản thử dùng mức nén mặc định. Sửa biểu tượng, Info.plist tùy ý, Mach-O và entitlements sẽ được bổ sung sau; hiện không có công tắc giả.").font(.footnote).foregroundStyle(.secondary)
                    Button("Lưu tùy chỉnh") { library.save(item); status = "Đã lưu tùy chỉnh cho IPA này." }
                    Button(busy ? "Đang ký…" : "Ký IPA") { sign() }.buttonStyle(.borderedProminent)
                    if busy { ProgressView() }
                    if !status.isEmpty { Text(status).font(.footnote).textSelection(.enabled) }
                    if let path = item.signedPath { ShareLink("Chia sẻ / Lưu IPA đã ký", item: URL(fileURLWithPath: path)) }
                    ShareLink("Xuất IPA gốc", item: NiKLibrary.root.appendingPathComponent(item.filename))
                }
            }
        }.navigationTitle("Tùy chỉnh IPA").disabled(busy).navigationBarBackButtonHidden(busy)
        .onDisappear { library.save(item) }
        .fileImporter(isPresented: $tweakPicker, allowedContentTypes: [.data]) { result in
            do {
                let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard ["dylib", "deb"].contains(url.pathExtension.lowercased()) else { throw NiKError("Cần chọn dylib hoặc deb.") }
                let target = NiKLibrary.root.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
                try FileManager.default.copyItem(at: url, to: target)
                item.options.injectedFiles.append(target); library.save(item)
            } catch { status = error.localizedDescription }
        }
    }
    private func sign() {
        let id = item.certificateID ?? UUID(uuidString: defaultCertificate)
        guard let cert = certificates.profiles.first(where: { $0.id == id }) else { status = "Chọn chứng chỉ cho IPA hoặc đặt mặc định trong Cài đặt → Chứng chỉ."; return }
        do {
            let credentials = try certificates.credentials(for: cert)
            let input = NiKLibrary.root.appendingPathComponent(item.filename)
            let options = item.options
            busy = true; status = "Đang kiểm tra và ký…"; library.save(item)
            Task {
                do {
                    let output = try await SigningService.shared.signDetailed(ipa: input, p12: credentials.p12, profile: credentials.provision, password: credentials.password, options: options)
                    item.signedPath = output.ipaURL.path; library.save(item); status = "Đã ký và xuất IPA."
                } catch { status = error.localizedDescription }
                busy = false
            }
        } catch { status = error.localizedDescription }
    }
}

struct NiKCertificateSettings: View {
    @ObservedObject var store: NiKCertificateStore
    @AppStorage("nik.defaultCertificate") private var selected = ""
    @State private var importing = false
    @State private var isKey = true
    @State private var key: Data?
    @State private var provision: Data?
    @State private var password = ""
    @State private var name = ""
    @State private var message = ""
    var body: some View {
        Form {
            Section("Đã lưu") {
                Picker("Mặc định", selection: $selected) {
                    Text("Chưa chọn").tag("")
                    ForEach(store.profiles) { Text($0.name).tag($0.id.uuidString) }
                }
                ForEach(store.profiles) { p in VStack(alignment: .leading) { Text(p.name); Text(p.teamName).font(.caption).foregroundStyle(.secondary) } }
                .onDelete { offsets in for p in offsets.map({ store.profiles[$0] }) { store.removeProfile(p); if selected == p.id.uuidString { selected = "" } } }
            }
            Section("Thêm chứng chỉ") {
                TextField("Tên gợi nhớ", text: $name)
                Button(key == nil ? "Chọn .p12" : "Đã chọn .p12") { isKey = true; importing = true }
                Button(provision == nil ? "Chọn .mobileprovision" : "Đã chọn profile") { isKey = false; importing = true }
                SecureField("Mật khẩu .p12", text: $password)
                Button("Kiểm tra & Lưu") { save() }.disabled(key == nil || provision == nil)
                if !message.isEmpty { Text(message).font(.footnote) }
            }
        }.navigationTitle("Chứng chỉ")
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data]) { result in
            do {
                let url = try result.get(); let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8_388_608 else { throw NiKError("Tệp vượt 8 MB.") }
                let data = try Data(contentsOf: url)
                if isKey { key = data } else { provision = data }
            } catch { message = error.localizedDescription }
        }
    }
    private func save() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: dir) }
        do {
            guard let key, let provision else { return }
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let k = dir.appendingPathComponent("key.p12"), p = dir.appendingPathComponent("profile.mobileprovision")
            try key.write(to: k, options: .completeFileProtection); try provision.write(to: p, options: .completeFileProtection)
            let saved = try store.importProfile(p12URL: k, provisionURL: p, password: password, customName: name)
            if selected.isEmpty { selected = saved.id.uuidString }
            self.key = nil; self.provision = nil; password = ""; name = ""; message = "Đã lưu chứng chỉ."
        } catch { message = error.localizedDescription }
    }
}

struct NiKHubPreview: View {
    @State private var section = 2
    @State private var session = FilesTabSession()
    var body: some View {
        NavigationStack {
            VStack {
                Picker("Nhóm", selection: $section) { Text("Dự án").tag(0); Text("Ứng dụng").tag(1); Text("Công cụ").tag(2) }.pickerStyle(.segmented).padding()
                if section == 0 { PatchProjectsView() }
                else if section == 1 { AppDataBrowserView(tabSession: $session) }
                else {
                    List {
                        NavigationLink("Wallpaper · Hình nền") { WallpaperLabView() }
                        NavigationLink("Dialer · Footnote · Supervised") { NiK3105V2HubView() }
                        NavigationLink("Cleaner · Dọn dẹp") { CleanerView() }
                        NavigationLink("Nguồn & công cụ 3105 gốc") { ContentView() }
                        Text("Khả năng sử dụng tùy thuộc thiết bị. Các công cụ chuyên sâu dùng bộ xử lý 3105 hiện có.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }.navigationTitle("3105")
        }
    }
}

struct NiKLocalFiles: View {
    let directory: URL
    @State private var files: [URL] = []
    @State private var preview: NiKPreviewDocument?
    @State private var query = ""
    @State private var importing = false
    @State private var message = ""
    @State private var newName = ""
    @State private var createFolder = false
    var body: some View {
        List {
            ForEach(files.filter { query.isEmpty || $0.lastPathComponent.localizedCaseInsensitiveContains(query) }, id: \.self) { url in
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    NavigationLink { NiKLocalFiles(directory: url) } label: { Label(url.lastPathComponent, systemImage: "folder") }
                } else {
                    HStack {
                        Button { preview = NiKPreviewDocument(url: url) } label: { Label(url.lastPathComponent, systemImage: url.pathExtension == "ipa" ? "app" : "doc") }
                        Spacer(); ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        if url.pathExtension.lowercased() == "ipa" {
                            Button { Task { await NiKLibrary.shared.receive(url) } } label: { Image(systemName: "plus.app") }.accessibilityLabel("Thêm vào thư viện IPA")
                        }
                    }
                }
            }
        }.buttonStyle(.borderless).navigationTitle(directory.lastPathComponent == "Documents" ? "Tệp" : directory.lastPathComponent)
        .searchable(text: $query, prompt: "Tìm tệp")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { importing = true } label: { Image(systemName: "square.and.arrow.down") }
                Button { createFolder = true } label: { Image(systemName: "folder.badge.plus") }
            }
        }
        .sheet(item: $preview) { NiKQuickLook(url: $0.url) }
        .onAppear { reload() }
        .refreshable { reload() }
        .alert("Thư mục mới", isPresented: $createFolder) {
            TextField("Tên thư mục", text: $newName)
            Button("Tạo") {
                do {
                    guard !newName.isEmpty, !newName.contains("/"), !newName.contains("\\"), newName != ".", newName != ".." else { throw NiKError("Tên không hợp lệ.") }
                    try FileManager.default.createDirectory(at: directory.appendingPathComponent(newName), withIntermediateDirectories: false)
                    newName = ""; reload()
                } catch { message = error.localizedDescription }
            }
            Button("Hủy", role: .cancel) {}
        }
        .alert("Tệp", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) { Button("Đóng") { message = "" } } message: { Text(message) }
        .sheet(isPresented: $importing) {
            NiKFilePicker { result in
                do {
                    let url = try result.get()
                    let target = directory
                    Task {
                        do {
                            let imported = try await Task.detached { try NiKFileImport.copy(url, into: target) }.value
                            reload(); message = "Đã nhập \(imported.lastPathComponent)."
                        } catch { message = error.localizedDescription }
                    }
                } catch { message = error.localizedDescription }
            }
        }
    }

    private func reload() {
        do {
            files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: .skipsHiddenFiles)
                .filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true }
                .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        } catch { message = error.localizedDescription }
    }
}
