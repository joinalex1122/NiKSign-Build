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
    @StateObject private var certStore = NiKCertificateStore.shared
    @State private var selectedTab = 1
    @State private var showImporter = false
    @State private var importKind = "ipa"
    @State private var message = ""
    @State private var busy = false

    // Signing inputs & saved certificates
    @State private var useSavedCert = true
    @State private var customCertLabel = ""
    @State private var ipa: URL?
    @State private var p12: URL?
    @State private var profile: URL?
    @State private var p12Password = ""

    // Signing customization & tweak injection options
    @State private var signingOptions = NiKSigningOptions()
    @ObservedObject private var queue = NiKSigningQueue.shared
    @State private var trackedJobID: UUID?
    private var trackedJob: NiKSigningJob? { queue.jobs.first { $0.id == trackedJobID } }
    private var signedArtifact: NiKSignedArtifact? { trackedJob?.output }
    private var signingProgress: NiKSigningProgress? {
        guard let job = trackedJob, job.state.isActive else { return nil }
        return NiKSigningProgress(step: job.state == .packaging ? 6 : 3, totalSteps: 6, fraction: job.fraction, description: job.step)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            signingTab
                .tabItem { Label("Ký IPA", systemImage: "signature") }
                .tag(1)
            altSourceTab
                .tabItem { Label("Kho IPA", systemImage: "shippingbox") }
                .tag(2)
            infoTab
                .tabItem { Label("Thông tin", systemImage: "info.circle") }
                .tag(4)
        }
        .disabled(busy)
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            attempt { guard let url = try result.get().first else { return }; try receive(url) }
        }
        .task(id: initialURL) {
            guard let url = initialURL else { return }
            switch url.pathExtension.lowercased() {
            case "ipa": importKind = "ipa"; selectedTab = 1
            case "p12": importKind = "p12"; useSavedCert = false; selectedTab = 1
            case "mobileprovision": importKind = "profile"; useSavedCert = false; selectedTab = 1
            case "dylib", "deb": importKind = "tweak"; selectedTab = 1
            default: message = "Chỉ hỗ trợ IPA, chứng chỉ và dylib/deb."; return
            }
            attempt { try receive(url) }
        }
        .alert("NiKSign", isPresented: Binding(get: { !message.isEmpty }, set: { if !$0 { message = "" } })) {
            Button("Đóng") { message = "" }
        } message: { Text(message) }
    }

    private var signingTab: some View {
        NavigationStack {
            Form {
                Section("1. Gói ứng dụng IPA") {
                    NavigationLink("Hàng đợi ký") { NiKSigningQueueView(queue: queue) }
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
                                do { try certStore.removeProfile(active) }
                                catch { message = error.localizedDescription }
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

                        NavigationLink("Cài qua HTTPS cục bộ") { NiKInstallIPAView(url: artifact.ipaURL) }

                    }


                }
            }.navigationTitle("Ký IPA")
        }
    }

    private var altSourceTab: some View {
        NavigationStack { NiKSourceLibraryView(library: NiKLibrary.shared) }
    }

    private var infoTab: some View {
        NavigationStack {
            Form {
                Section("Công cụ ký IPA") {
                    Text("Quản lý chứng chỉ trong Keychain, tùy chỉnh IPA, chèn dylib/deb và ký ứng dụng trên thiết bị.")
                    NavigationLink("Kiểm tra Mach-O / DEB / TAR") { NiKInspectView() }
                    NavigationLink("Giấy phép mã nguồn mở") { NiKLicensesView() }
                }
            }.navigationTitle("NiKSign")
        }
    }

    private var hasValidCredentialSelection: Bool {
        if useSavedCert && !certStore.profiles.isEmpty {
            return certStore.selectedProfile != nil
        }
        return p12 != nil && profile != nil
    }

    private func attempt(_ action: () throws -> Void) {
        do { try action() } catch { message = error.localizedDescription }
    }

    private func pick(_ kind: String) { importKind = kind; showImporter = true }

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
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Components", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let copy = directory.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
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
                trackedJobID = nil
            case "p12":
                if let p12 { try? FileManager.default.removeItem(at: p12) }
                p12 = copy
            default:
                if let profile { try? FileManager.default.removeItem(at: profile) }
                profile = copy
            }
            return
        }

        throw NiKError("Chỉ hỗ trợ IPA, p12, mobileprovision, dylib và deb.")
    }

    private func clearTemporaryCredentials() {
        for url in [p12, profile].compactMap({ $0 }) { try? FileManager.default.removeItem(at: url) }
        p12 = nil; profile = nil; p12Password = ""
    }

    private func sign() {
        guard let ipa else { return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let certificate: NiKCertificateProfile
                if useSavedCert, let saved = certStore.selectedProfile { certificate = saved }
                else if let p12, let profile {
                    certificate = try certStore.importProfile(p12URL: p12, provisionURL: profile, password: p12Password, customName: customCertLabel)
                    useSavedCert = true
                    clearTemporaryCredentials()
                } else { throw NiKError("Hãy nhập đủ chứng chỉ và profile.") }
                guard var item = await NiKLibrary.shared.receiveItem(ipa) else { throw NiKError(NiKLibrary.shared.error) }
                item.certificateID = certificate.id
                item.options = signingOptions
                guard NiKLibrary.shared.save(item) else { throw NiKError(NiKLibrary.shared.error) }
                let job = NiKSigningJob(libraryID: item.id, title: item.title, input: item.ipaURL, certificateID: certificate.id, options: signingOptions)
                try queue.enqueue([job])
                trackedJobID = job.id
                message = "Đã thêm vào hàng đợi. Mở Hàng đợi ký để theo dõi."
            } catch { message = error.localizedDescription }
        }
    }
}
