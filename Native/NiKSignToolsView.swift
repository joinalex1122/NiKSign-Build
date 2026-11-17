import SwiftUI
import UniformTypeIdentifiers

struct ExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.data] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct NiKSignView: View {
    var initialURL: URL? = nil
    @StateObject private var certStore = NiKCertificateStore()
    @StateObject private var altSourceStore = NiKAltSourceStore()
    @State private var selectedTab = 1
    @State private var showImporter = false
    @State private var importKind = "document"
    @State private var text = "{\n  \"appearance\": \"dark\",\n  \"enabled\": true\n}"
    @State private var name = "config.json"
    @State private var message = ""
    @State private var busy = false
    @State private var exportDocument: ExportDocument?
    @State private var exporting = false
    @State private var exportName = "config.json"
    @State private var packageData: Data?
    @State private var packageKey: Data?
    @State private var pendingPackage: Data?
    @State private var patchPassword = ""
    @State private var initialDialerURL: URL?

    // Signing inputs & saved certificates
    @State private var useSavedCert = true
    @State private var customCertLabel = ""
    @State private var ipa: URL?
    @State private var p12: URL?
    @State private var profile: URL?
    @State private var p12Password = ""

    // Signing customization & tweak injection options
    @State private var signingOptions = NiKSigningOptions()
    @State private var signingProgress: NiKSigningProgress?
    @State private var signedArtifact: NiKSignedArtifact?

    // OTA & Loopback server state
    @State private var loopback = NiKLoopbackServer()
    @State private var loopbackURL: URL?
    @State private var manifestURL: URL?
    @Environment(\.openURL) private var openURL

    var body: some View {
        TabView(selection: $selectedTab) {
            editorTab
                .tabItem { Label("Trình sửa", systemImage: "doc.text") }
                .tag(0)
            signingTab
                .tabItem { Label("Ký IPA", systemImage: "signature") }
                .tag(1)
            altSourceTab
                .tabItem { Label("Kho IPA", systemImage: "shippingbox") }
                .tag(2)
            v2HubTab
                .tabItem { Label("3105 2.0", systemImage: "sparkles.rectangle.stack") }
                .tag(3)
            infoTab
                .tabItem { Label("Thông tin", systemImage: "info.circle") }
                .tag(4)
        }
        .onDisappear { stopLoopback() }
        .disabled(busy)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            attempt { guard let url = try result.get().first else { return }; try receive(url) }
        }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .data, defaultFilename: exportName) { result in
            if case .failure(let error) = result { message = error.localizedDescription }
        }
        .task(id: initialURL) {
            guard let url = initialURL else { return }
            switch url.pathExtension.lowercased() {
            case "ipa": importKind = "ipa"; selectedTab = 1
            case "p12": importKind = "p12"; useSavedCert = false; selectedTab = 1
            case "mobileprovision": importKind = "profile"; useSavedCert = false; selectedTab = 1
            case "dylib", "deb": importKind = "tweak"; selectedTab = 1
            case "3105pass":
                initialDialerURL = url
                selectedTab = 3
                return
            default: importKind = "document"; selectedTab = 0
            }
            attempt { try receive(url) }
        }
        .alert("NiKSign", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) {
            Button("Đóng") { message = "" }
        } message: { Text(message) }
    }

    private var v2HubTab: some View {
        NavigationStack {
            NiK3105V2HubView(initialDialerURL: initialDialerURL)
        }
    }

    private var editorTab: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Button("Mở tệp") { pick("document") }
                    Spacer()
                    Button("Tệp mới") { resetDocument() }
                    Button("Xuất") { exportEdited() }.disabled(pendingPackage != nil)
                }
                Text(name).font(.caption).foregroundStyle(.secondary)
                Button("Tạo gói .3105 mẫu cho dữ liệu của bạn") { attempt { try newPackage() } }
                if pendingPackage != nil {
                    SecureField("Mật khẩu gói .3105", text: $patchPassword)
                    Button("Mở khóa") { attempt { try unlockPackage() } }
                }
                if packageData != nil {
                    Text("Gói .3105: sửa metadata và rules dạng JSON; replacementData là Base64. Giữ ID để xuất lại gói gốc.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextEditor(text: $text).font(.system(.footnote, design: .monospaced))
                    .autocorrectionDisabled().textInputAutocapitalization(.never)
                Text("Chỉ sửa bản sao bạn nhập. Xuất để lưu vào Tệp; không ghi vào app khác.")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding().navigationTitle("NiKSign · Tệp")
        }
    }

    private var signingTab: some View {
        NavigationStack {
            Form {
                Section("1. Gói ứng dụng IPA") {
                    Button(ipa?.lastPathComponent ?? "Chọn tệp .ipa từ Tệp") { pick("ipa") }
                    Button("Duyệt & tải từ Kho AltSource") { selectedTab = 2 }
                        .font(.caption)
                }

                Section("2. Quản lý chứng chỉ (.p12 & .mobileprovision)") {
                    if !certStore.profiles.isEmpty {
                        Picker("Nguồn chứng chỉ", selection: $useSavedCert) {
                            Text("Đã lưu (\(certStore.profiles.count))").tag(true)
                            Text("Chọn tệp lẻ").tag(false)
                        }
                        .pickerStyle(.segmented)
                    }

                    if useSavedCert && !certStore.profiles.isEmpty {
                        Picker("Bộ chứng chỉ", selection: $certStore.selectedProfileID) {
                            ForEach(certStore.profiles) { prof in
                                Text(prof.name).tag(Optional(prof.id))
                            }
                        }
                        if let active = certStore.selectedProfile {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Chứng chỉ: \(active.certSummary)").font(.caption)
                                Text("Team: \(active.teamName.isEmpty ? "N/A" : active.teamName) (\(active.teamID)) · App ID: \(active.bundleIDPattern)")
                                    .font(.caption2).foregroundStyle(.secondary)
                                HStack(spacing: 8) {
                                    Text(active.certMatchesProvision ? "Khớp Profile" : "Lệch Profile")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(active.certMatchesProvision ? Color.green : Color.orange)
                                    if let days = active.daysRemaining {
                                        Text(days >= 0 ? "Còn \(days) ngày" : "Đã hết hạn")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(days >= 0 ? Color.secondary : Color.red)
                                    }
                                    Text("\(active.provisionedUDIDs.count) UDID")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Button("Xóa bộ chứng chỉ đang chọn", role: .destructive) {
                                certStore.removeProfile(active)
                            }
                            .font(.caption)
                        }
                    } else {
                        Button(p12?.lastPathComponent ?? "Chọn khóa .p12") { pick("p12") }
                        Button(profile?.lastPathComponent ?? "Chọn hồ sơ .mobileprovision") { pick("profile") }
                        SecureField("Mật khẩu .p12", text: $p12Password)
                        TextField("Tên gợi nhớ (tùy chọn)", text: $customCertLabel)
                        Button("Kiểm tra & Lưu vào Kho chứng chỉ (Keychain)") {
                            attempt {
                                guard let p12, let profile else {
                                    throw NiKError("Cần chọn đủ tệp .p12 và .mobileprovision trước khi lưu.")
                                }
                                let saved = try certStore.importProfile(
                                    p12URL: p12,
                                    provisionURL: profile,
                                    password: p12Password,
                                    customName: customCertLabel
                                )
                                customCertLabel = ""
                                useSavedCert = true
                                message = "Đã lưu bộ chứng chỉ \"\(saved.name)\" (SHA-1: \(saved.sha1Fingerprint.prefix(12))…)."
                            }
                        }
                        .disabled(p12 == nil || profile == nil)
                        Button("Xóa tệp chứng chỉ tạm", role: .destructive) { clearTemporaryCredentials() }
                            .font(.caption)
                    }
                }

                Section("3. Tùy biến Info.plist & Gói IPA") {
                    TextField("Đổi Bundle ID (VD: com.user.app)", text: $signingOptions.customBundleID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Đổi tên hiển thị (CFBundleDisplayName)", text: $signingOptions.customDisplayName)
                    TextField("Đổi phiên bản (CFBundleShortVersionString)", text: $signingOptions.customVersion)
                        .textInputAutocapitalization(.never)
                    TextField("Hạ/Ghi đè MinimumOSVersion (VD: 15.0)", text: $signingOptions.minimumOSVersion)
                        .keyboardType(.decimalPad)
                    Toggle("Bật chia sẻ tệp (UIFileSharingEnabled)", isOn: $signingOptions.enableFileSharing)
                    Toggle("Bỏ giới hạn thiết bị (UISupportedDevices)", isOn: $signingOptions.removeSupportedDevicesRestriction)
                    Toggle("Gỡ PlugIns / Watch / App Extensions", isOn: $signingOptions.removeExtensions)
                }

                Section("4. Chèn Tweak (.dylib / .deb)") {
                    Button("Thêm tệp .dylib hoặc gói .deb") { pick("tweak") }
                    Toggle("Chèn dạng Weak Dylib (LC_LOAD_WEAK_DYLIB)", isOn: $signingOptions.weakDylibInjection)
                    if !signingOptions.injectedFiles.isEmpty {
                        ForEach(signingOptions.injectedFiles, id: \.self) { url in
                            HStack {
                                Text(url.lastPathComponent).font(.caption.monospaced())
                                Spacer()
                                Button(role: .destructive) {
                                    try? FileManager.default.removeItem(at: url)
                                    signingOptions.injectedFiles.removeAll { $0 == url }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    } else {
                        Text("Chưa có tweak nào trong hàng đợi. Hỗ trợ giải nén .deb lấy .dylib và gắn LC_LOAD_DYLIB vào binary chính.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("5. Ký số & Xuất IPA") {
                    Button(busy ? "Đang xử lý ký…" : "Ký và xuất IPA") { sign() }
                        .buttonStyle(.borderedProminent)
                        .disabled(busy || ipa == nil || !hasValidCredentialSelection)

                    if let progress = signingProgress {
                        VStack(alignment: .leading, spacing: 6) {
                            ProgressView(value: progress.fraction)
                            Text("Bước \(progress.step)/\(progress.totalSteps): \(progress.description)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let artifact = signedArtifact {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Đã xuất: \(artifact.displayName) (\(artifact.bundleID) · v\(artifact.version))")
                                .font(.caption.weight(.semibold))
                            if !artifact.injectedDylibs.isEmpty {
                                Text("Đã chèn dylib: \(artifact.injectedDylibs.joined(separator: ", "))")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        ShareLink("Chia sẻ / Lưu IPA đã ký", item: artifact.ipaURL)

                        Text("Máy chủ nội bộ dùng HTTP để tải IPA và xem manifest. Cài OTA cần nơi lưu trữ HTTPS hợp lệ; bạn có thể chia sẻ IPA cho dịch vụ cài đặt đang dùng.")
                            .font(.caption).foregroundStyle(.secondary)

                        Button("Bật tải IPA & xem Manifest cục bộ") {
                            attempt {
                                guard let url = loopback.start(
                                    file: artifact.ipaURL,
                                    bundleID: artifact.bundleID,
                                    version: artifact.version,
                                    title: artifact.displayName,
                                    httpsHost: nil
                                ) else {
                                    if let error = loopback.lastError { throw error }
                                    throw NiKError("Không khởi động được máy chủ nội bộ.")
                                }
                                loopbackURL = url
                                manifestURL = loopback.manifestURL
                            }
                        }
                    }

                    if let loopbackURL {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("IPA URL: \(loopbackURL.absoluteString)")
                                .font(.caption2.monospaced())
                                .textSelection(.enabled)
                            if let manifestURL {
                                Text("Manifest: \(manifestURL.absoluteString)")
                                    .font(.caption2.monospaced())
                                    .textSelection(.enabled)
                            }
                            Button("Dừng máy chủ nội bộ", role: .destructive) { stopLoopback() }
                                .font(.caption)
                        }
                    }
                }
            }.navigationTitle("Ký IPA")
        }
    }

    private var altSourceTab: some View {
        NavigationStack {
            NiKAltSourceView(store: altSourceStore) { downloadedURL, appMetadata in
                if let ipa { try? FileManager.default.removeItem(at: ipa) }
                ipa = downloadedURL
                signedArtifact = nil
                stopLoopback()
                if signingOptions.customDisplayName.isEmpty {
                    signingOptions.customDisplayName = appMetadata.name
                }
                selectedTab = 1
            }
            .navigationTitle("Kho AltSource")
        }
    }

    private var infoTab: some View {
        NavigationStack {
            Form {
                Section("Khả năng của bản 3.3") {
                    Text("Các module bổ sung theo tài liệu 3105 2.0, cần kiểm thử trên thiết bị: Workspace v9 (Application + AppGroup + settings.json), bộ trộn Plist/JSON (%3105_Overwrite%, %3105_MatchPrefix%, %3105_Remove%), trình cài Dialer (.3105pass), Footnote màn hình khóa, Supervised và quản lý gói tính năng Cleaner.")
                    Text("Quản lý nhiều bộ chứng chỉ .p12/.mobileprovision với mật khẩu lưu trong Keychain, đối chiếu chứng chỉ X.509 DER và kiểm tra hạn sử dụng.")
                    Text("Tùy biến Info.plist, trích xuất .dylib từ .deb để gắn LC_LOAD_DYLIB vào binary Mach-O 64-bit, máy chủ OTA manifest.plist và trình duyệt kho AltSource JSON.")
                }
                Section("Công cụ & giấy phép") {
                    NavigationLink("Kiểm tra Mach-O / DEB / TAR") { NiKInspectView() }
                    NavigationLink("Giấy phép mã nguồn mở") { NiKLicensesView() }
                }
                Section("Nguồn tham khảo") {
                    Link("3105 · YangJiiii · GPL-3.0", destination: URL(string: "https://github.com/YangJiiii/3105")!)
                    Link("Feather · luồng ký IPA", destination: URL(string: "https://github.com/claration/feather")!)
                    Link("Zsign · nhân ký MIT", destination: URL(string: "https://github.com/claration/zsign")!)
                    Text("NiKSign 3.3 · mã sửa đổi GPL-3.0. Giấy phép và nguồn tương ứng đi kèm gói source.")
                }
            }.navigationTitle("Thông tin")
        }
    }

    private var hasValidCredentialSelection: Bool {
        if useSavedCert && !certStore.profiles.isEmpty {
            return certStore.selectedProfile != nil
        }
        return p12 != nil && profile != nil
    }

    private func stopLoopback() {
        loopback.stop()
        loopbackURL = nil
        manifestURL = nil
    }

    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { message = error.localizedDescription }
    }

    private func pick(_ kind: String) { importKind = kind; showImporter = true }

    private func resetDocument() {
        packageData = nil; packageKey = nil; pendingPackage = nil; patchPassword = ""
        name = "config.json"; text = "{\n  \"enabled\": true\n}"
    }

    private func receive(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        let limit: Int
        if importKind == "ipa" {
            limit = 1_073_741_824
        } else if importKind == "tweak" {
            limit = 67_108_864
        } else {
            limit = 16_777_216
        }
        guard size <= limit else { throw NiKError("Tệp vượt giới hạn \(limit / 1_048_576) MB.") }

        if importKind == "tweak" {
            let ext = url.pathExtension.lowercased()
            guard ext == "dylib" || ext == "deb" else {
                throw NiKError("Cần chọn tệp .dylib hoặc .deb.")
            }
            let safeName = url.lastPathComponent
            let copy = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString)-\(safeName)")
            try FileManager.default.copyItem(at: url, to: copy)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: copy.path)
            signingOptions.injectedFiles.append(copy)
            return
        }

        if importKind != "document" {
            let ext = ["ipa": "ipa", "p12": "p12", "profile": "mobileprovision"][importKind]!
            guard url.pathExtension.lowercased() == ext else { throw NiKError("Cần chọn tệp .\(ext).") }
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).\(ext)")
            try FileManager.default.copyItem(at: url, to: copy)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: copy.path)
            switch importKind {
            case "ipa":
                if let ipa { try? FileManager.default.removeItem(at: ipa) }
                ipa = copy
                signedArtifact = nil
                stopLoopback()
            case "p12":
                if let p12 { try? FileManager.default.removeItem(at: p12) }
                p12 = copy
            default:
                if let profile { try? FileManager.default.removeItem(at: profile) }
                profile = copy
            }
            return
        }

        let data = try Data(contentsOf: url)
        if data.starts(with: Data("3105PATCH\0".utf8)) {
            _ = try PatchPackageCodec.inspect(data)
            packageData = nil; packageKey = nil; text = ""; name = url.lastPathComponent
            pendingPackage = data; patchPassword = ""
            if !(try PatchPackageCodec.inspect(data)).isPasswordProtected { try unlockPackage() }
        } else {
            let rendered: String
            let newName: String
            if let object = try? JSONSerialization.jsonObject(with: data) {
                rendered = String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self)
                newName = url.deletingPathExtension().lastPathComponent + ".json"
            } else {
                let object = try PropertyListSerialization.propertyList(from: data, format: nil)
                rendered = String(decoding: try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0), as: UTF8.self)
                newName = url.deletingPathExtension().lastPathComponent + ".plist"
            }
            packageData = nil; packageKey = nil; pendingPackage = nil; patchPassword = ""
            text = rendered; name = newName
        }
    }

    private func unlockPackage() throws {
        guard let pendingPackage else { return }
        let decoded = try PatchPackageCodec.decode(pendingPackage, password: patchPassword)
        guard !decoded.project.isPrivate else { throw NiKError("Gói riêng tư: bản này không mở để sửa nội dung.") }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        text = String(decoding: try encoder.encode(decoded.project), as: UTF8.self)
        packageData = pendingPackage; packageKey = decoded.contentKey
        self.pendingPackage = nil; patchPassword = ""
    }

    private func newPackage() throws {
        let rule = PatchRule(bundleID: "app.niksign.example", relativePath: "Documents/config.json",
            replacementFilename: "config.json", replacementData: Data("{\"appearance\":\"dark\"}".utf8))
        let project = PatchProject(name: "MyAppearance", rules: [rule])
        let encoded = try PatchPackageCodec.encodeNew(project: project, password: nil)
        packageData = nil; packageKey = nil; patchPassword = ""
        pendingPackage = encoded.data; name = "MyAppearance.3105"
        try unlockPackage()
    }

    private func exportEdited() {
        attempt {
            let data: Data
            if let packageData, let packageKey {
                let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
                let project = try decoder.decode(PatchProject.self, from: Data(text.utf8))
                data = try PatchPackageCodec.update(packageData, project: project, contentKey: packageKey)
            } else if name.hasSuffix(".plist") {
                let object = try PropertyListSerialization.propertyList(from: Data(text.utf8), format: nil)
                data = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
            } else {
                let object = try JSONSerialization.jsonObject(with: Data(text.utf8))
                data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            }
            exportName = name; exportDocument = ExportDocument(data: data); exporting = true
        }
    }

    private func clearTemporaryCredentials() {
        for url in [p12, profile].compactMap({ $0 }) { try? FileManager.default.removeItem(at: url) }
        p12 = nil; profile = nil; p12Password = ""
    }

    private func sign() {
        guard let ipa else { return }
        let activeP12: URL
        let activeProfile: URL
        let activePassword: String
        let shouldCleanupTemp: Bool

        do {
            if useSavedCert, let saved = certStore.selectedProfile {
                let creds = try certStore.credentials(for: saved)
                activeP12 = creds.p12
                activeProfile = creds.provision
                activePassword = creds.password
                shouldCleanupTemp = false
            } else if let p12, let profile {
                activeP12 = p12
                activeProfile = profile
                activePassword = p12Password
                shouldCleanupTemp = true
            } else {
                return
            }
        } catch {
            message = error.localizedDescription
            return
        }

        let currentOptions = signingOptions
        stopLoopback()
        busy = true
        signedArtifact = nil
        signingProgress = NiKSigningProgress(step: 1, totalSteps: 6, fraction: 0.05, description: "Khởi tạo tiến trình ký…")

        Task {
            defer {
                busy = false
                signingProgress = nil
                if shouldCleanupTemp {
                    clearTemporaryCredentials()
                }
            }
            do {
                let artifact = try await SigningService.shared.signDetailed(
                    ipa: ipa,
                    p12: activeP12,
                    profile: activeProfile,
                    password: activePassword,
                    options: currentOptions,
                    onProgress: { stepProgress in
                        Task { @MainActor in
                            self.signingProgress = stepProgress
                        }
                    }
                )
                signedArtifact = artifact
                message = "Đã ký thành công \(artifact.displayName) (\(artifact.bundleID) v\(artifact.version))."
            } catch {
                message = error.localizedDescription
            }
        }
    }
}
