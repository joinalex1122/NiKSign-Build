import SwiftUI
import UniformTypeIdentifiers

struct NiK3105V2HubView: View {
    var initialDialerURL: URL? = nil
    @StateObject private var systemFeatures = NiKSystemFeaturesStore()
    @State private var selectedSection = 0

    // Workspace v9 state
    @State private var workspaces: [(url: URL, project: NiKWorkspaceV9Project)] = []
    @State private var newWorkspaceName = ""
    @State private var includeSampleRules = true
    @State private var selectedWorkspaceURL: URL?
    @State private var activeProject: NiKWorkspaceV9Project?
    @State private var fieldInputs: [String: NiKPatchFieldUserValue] = [:]

    // Dialer (.3105pass) state
    @State private var dialerPackages: [NiKDialerPackage] = []
    @State private var importingDialer = false

    @State private var alertMessage = ""

    var body: some View {
        VStack(spacing: 0) {
            Picker("Nhóm chức năng 3105 2.0", selection: $selectedSection) {
                Text("Patch v9 & AppGroup").tag(0)
                Text("Dialer (.3105pass)").tag(1)
                Text("Footnote & Tính năng").tag(2)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            switch selectedSection {
            case 0:
                workspaceV9View
            case 1:
                dialerView
            default:
                systemFeaturesView
            }
        }
        .navigationTitle("Bộ công cụ 3105 2.0")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reloadWorkspaces()
            dialerPackages = NiKDialerService.loadInstalledPackages()
            if let url = initialDialerURL {
                selectedSection = 1
                do {
                    _ = try NiKDialerService.importPackage(from: url)
                    dialerPackages = NiKDialerService.loadInstalledPackages()
                    alertMessage = "Đã nhập gói Dialer \(url.lastPathComponent)."
                } catch {
                    alertMessage = error.localizedDescription
                }
            }
        }
        .fileImporter(isPresented: $importingDialer, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let pkg = try NiKDialerService.importPackage(from: url)
                dialerPackages = NiKDialerService.loadInstalledPackages()
                alertMessage = "Đã nhập gói Dialer '\(pkg.name)' (\(pkg.items.count) phím)."
            } catch {
                alertMessage = error.localizedDescription
            }
        }
        .alert("3105 2.0", isPresented: Binding(get: { !alertMessage.isEmpty }, set: { if !$0 { alertMessage = "" } })) {
            Button("Đóng") { alertMessage = "" }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Section 0: Workspace v9 (Application + AppGroup + settings.json + Plist/JSON Merge)

    private var workspaceV9View: some View {
        List {
            Section("Tạo Workspace chuẩn 3105 2.0 (Schema v9)") {
                TextField("Tên dự án Patch (VD: LocketV9)", text: $newWorkspaceName)
                Toggle("Tạo kèm mẫu settings.json, %3105_Overwrite% & %3105_MatchPrefix%", isOn: $includeSampleRules)
                Button("Tạo Workspace Application + AppGroup") {
                    do {
                        let created = try NiKWorkspaceV9Service.createWorkspace(
                            named: newWorkspaceName,
                            includeSampleSampleRule: includeSampleRules
                        )
                        newWorkspaceName = ""
                        reloadWorkspaces()
                        selectWorkspace(created.workspaceURL, project: created.project)
                        alertMessage = "Đã tạo workspace '\(created.project.name)' tại Documents/Patches/ với đầy đủ settings.json, Application/ và AppGroup/."
                    } catch {
                        alertMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
            }

            Section("Danh sách Workspace v9 (\(workspaces.count))") {
                if workspaces.isEmpty {
                    Text("Chưa có workspace v9 nào. Hãy bấm Tạo ở trên để khởi tạo cấu trúc Application/, AppGroup/ và settings.json.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(workspaces, id: \.url) { entry in
                        Button {
                            selectWorkspace(entry.url, project: entry.project)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(entry.project.name).font(.headline)
                                    Text("\(entry.project.rules.count) ánh xạ · \(entry.project.settings.fields.count) trường settings.json")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if selectedWorkspaceURL == entry.url {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if let project = activeProject, let wsURL = selectedWorkspaceURL {
                Section("Chi tiết & Tùy chỉnh: \(project.name)") {
                    Button("Đồng bộ lại từ thư mục Workspace") {
                        do {
                            let synced = try NiKWorkspaceV9Service.synchronizeWorkspace(at: wsURL)
                            selectWorkspace(wsURL, project: synced)
                            alertMessage = "Đã đồng bộ \(synced.rules.count) quy tắc và \(synced.settings.fields.count) trường tùy chỉnh."
                        } catch {
                            alertMessage = error.localizedDescription
                        }
                    }

                    if !project.settings.fields.isEmpty {
                        ForEach(project.settings.fields) { field in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text("\(field.label) (\(field.type))")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("{{\(field.id)}}")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(.secondary)
                                }
                                if let options = field.options, !options.isEmpty {
                                    Picker(field.label, selection: bindingForFieldValue(field)) {
                                        ForEach(options) { opt in
                                            Text(opt.label).tag(opt.value)
                                        }
                                    }
                                    .pickerStyle(.menu)
                                } else if field.type == "boolean" {
                                    Toggle("Giá trị Boolean", isOn: Binding(
                                        get: { bindingForFieldValue(field).wrappedValue.lowercased() == "true" },
                                        set: { bindingForFieldValue(field).wrappedValue = $0 ? "true" : "false" }
                                    ))
                                } else {
                                    TextField("Nhập giá trị cho \(field.id)", text: bindingForFieldValue(field))
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .font(.caption.monospaced())
                                }
                                if field.canRemove == true {
                                    Toggle("Xoá trường này (canRemove)", isOn: bindingForFieldRemove(field))
                                        .font(.caption)
                                        .tint(.red)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }

                    ForEach(project.rules) { rule in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(rule.scope.rawValue)/\(rule.identifier)")
                                .font(.caption.weight(.semibold))
                            Text(rule.relativePath)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text("Chế độ: \(rule.mode == .replaceFile ? "Thay thế toàn bộ file" : (rule.mode == .mergePlist ? "Sửa/Merge nội dung Plist" : "Sửa/Merge nội dung JSON"))")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        .padding(.vertical, 2)
                    }

                    Button("Áp dụng Patch v9 (Application & AppGroup)") {
                        do {
                            let result = try NiKWorkspaceV9Service.apply(project: project, userValues: fieldInputs)
                            let skippedNote = result.skippedIdentifiers.isEmpty
                                ? ""
                                : " (Bỏ qua container chưa có trên máy: \(result.skippedIdentifiers.joined(separator: ", ")))"
                            alertMessage = "Đã áp dụng \(result.appliedCount) quy tắc thành công\(skippedNote)."
                        } catch {
                            alertMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    if NiKWorkspaceV9Service.hasBackupReceipt(projectID: project.id) {
                        Button("Khôi phục file gốc (Restore)", role: .destructive) {
                            do {
                                let count = try NiKWorkspaceV9Service.restore(projectID: project.id)
                                alertMessage = "Đã khôi phục \(count) tệp về nguyên bản trước khi áp dụng."
                            } catch {
                                alertMessage = error.localizedDescription
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Section 1: Dialer (.3105pass)

    private var dialerView: some View {
        List {
            Section("Quản lý gói Dialer (.3105pass)") {
                Button("Nhập gói .3105pass từ Tệp") {
                    importingDialer = true
                }
                Button("Tạo gói .3105pass mẫu (Sáng / Tối / Chữ đậm)") {
                    do {
                        let sample = try NiKDialerService.createSamplePackage()
                        dialerPackages = NiKDialerService.loadInstalledPackages()
                        alertMessage = "Đã tạo gói mẫu '\(sample.name)' với đủ 3 kiểu phím: Sáng, Tối và Chữ đậm."
                    } catch {
                        alertMessage = error.localizedDescription
                    }
                }
                Text("Hỗ trợ tự nhận diện kiểu phím Sáng (Light), Tối (Dark) và Chữ đậm (Bold) theo dữ liệu trên thiết bị, kèm sao lưu và khôi phục an toàn.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Gói Dialer đã nhập (\(dialerPackages.count))") {
                if dialerPackages.isEmpty {
                    Text("Chưa có gói .3105pass nào.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dialerPackages) { pkg in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(pkg.name).font(.headline)
                            Text("Số phím: \(pkg.items.count) · Kiểu nhận diện: \(pkg.detectedStyles.map(\.rawValue).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Button("Áp dụng") {
                                    do {
                                        alertMessage = try NiKDialerService.apply(pkg)
                                    } catch {
                                        alertMessage = error.localizedDescription
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                Button("Khôi phục") {
                                    do {
                                        alertMessage = try NiKDialerService.restore(pkg)
                                    } catch {
                                        alertMessage = error.localizedDescription
                                    }
                                }
                                .buttonStyle(.bordered)

                                Spacer()

                                Button(role: .destructive) {
                                    NiKDialerService.deletePackage(pkg)
                                    dialerPackages = NiKDialerService.loadInstalledPackages()
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }

    // MARK: - Section 2: Footnote, Supervised & Cleaner Feature Package

    private var systemFeaturesView: some View {
        Form {
            Section("Tính năng 3105 (Cài / Gỡ từ Kho & Đã cài)") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dọn dẹp (3105 Cleaner)")
                            .font(.headline)
                        Text(systemFeatures.isCleanerInstalled ? "Trạng thái: Đã cài đặt" : "Trạng thái: Đã gỡ")
                            .font(.caption)
                            .foregroundStyle(systemFeatures.isCleanerInstalled ? .green : .secondary)
                    }
                    Spacer()
                    Button(systemFeatures.isCleanerInstalled ? "Gỡ tính năng" : "Cài đặt") {
                        systemFeatures.toggleCleanerInstallation()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(systemFeatures.isCleanerInstalled ? .red : .orange)
                }
            }

            Section("Footnote màn hình khóa (Lock Screen Footnote)") {
                TextField("Nội dung hiển thị ở cuối màn hình khóa…", text: $systemFeatures.footnoteText)
                Button("Áp dụng Footnote màn hình khóa") {
                    systemFeatures.applyFootnote()
                }
            }

            Section("Chế độ Giám sát (Supervised Mode)") {
                Toggle("Bật trạng thái Supervised (IsSupervised)", isOn: $systemFeatures.isSupervisedEnabled)
                TextField("Tên tổ chức hiển thị (OrganizationName)", text: $systemFeatures.organizationName)
                Button("Cập nhật cấu hình Supervised") {
                    systemFeatures.applySupervisedState()
                }
            }

            Section("Sao lưu & Khôi phục hệ thống") {
                Button("Khôi phục Footnote & Supervised về nguyên gốc", role: .destructive) {
                    systemFeatures.restoreOriginalSystemConfigs()
                }
                if !systemFeatures.lastStatusMessage.isEmpty {
                    Text(systemFeatures.lastStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private func reloadWorkspaces() {
        workspaces = NiKWorkspaceV9Service.listWorkspaces()
        if selectedWorkspaceURL == nil, let first = workspaces.first {
            selectWorkspace(first.url, project: first.project)
        }
    }

    private func selectWorkspace(_ url: URL, project: NiKWorkspaceV9Project) {
        selectedWorkspaceURL = url
        activeProject = project
        var nextInputs: [String: NiKPatchFieldUserValue] = [:]
        for field in project.settings.fields {
            if let existing = fieldInputs[field.id] {
                nextInputs[field.id] = existing
            } else {
                nextInputs[field.id] = NiKPatchFieldUserValue(
                    stringValue: field.defaultValue ?? "",
                    removeField: false
                )
            }
        }
        fieldInputs = nextInputs
    }

    private func bindingForFieldValue(_ field: NiKPatchSettingField) -> Binding<String> {
        Binding(
            get: { fieldInputs[field.id]?.stringValue ?? field.defaultValue ?? "" },
            set: { newValue in
                var current = fieldInputs[field.id] ?? NiKPatchFieldUserValue(stringValue: "", removeField: false)
                current.stringValue = newValue
                fieldInputs[field.id] = current
            }
        )
    }

    private func bindingForFieldRemove(_ field: NiKPatchSettingField) -> Binding<Bool> {
        Binding(
            get: { fieldInputs[field.id]?.removeField ?? false },
            set: { newValue in
                var current = fieldInputs[field.id] ?? NiKPatchFieldUserValue(stringValue: field.defaultValue ?? "", removeField: false)
                current.removeField = newValue
                fieldInputs[field.id] = current
            }
        )
    }
}

private extension NiKWorkspaceV9Service {
    static func createWorkspace(named rawName: String, includeSampleSampleRule: Bool) throws -> (workspaceURL: URL, project: NiKWorkspaceV9Project) {
        try createWorkspace(named: rawName, includeSampleLocketRule: includeSampleSampleRule)
    }
}
