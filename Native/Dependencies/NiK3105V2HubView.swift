import SwiftUI
import UniformTypeIdentifiers

struct NiK3105V2HubView: View {
    @AppStorage("nik.language") private var language = "vi"
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
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
            Picker(t("Nhóm chức năng 3105 2.0", "3105 2.0 Functions"), selection: $selectedSection) {
                Text("Patch v9 & AppGroup").tag(0)
                Text("Dialer (.3105pass)").tag(1)
                Text(t("Footnote & Tính năng", "Footnote & Features")).tag(2)
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
        .padding(.bottom, 100)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(t("Bộ công cụ 3105 2.0", "3105 2.0 Tools"))
        .listStyle(.insetGrouped)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reloadWorkspaces()
            dialerPackages = NiKDialerService.loadInstalledPackages()
            if let url = initialDialerURL {
                selectedSection = 1
                do {
                    _ = try NiKDialerService.importPackage(from: url)
                    dialerPackages = NiKDialerService.loadInstalledPackages()
                    alertMessage = t("Đã nhập gói Dialer \(url.lastPathComponent).", "Imported Dialer package \(url.lastPathComponent).")
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
                alertMessage = t("Đã nhập gói Dialer '\(pkg.name)' (\(pkg.items.count) phím).", "Imported Dialer '\(pkg.name)' (\(pkg.items.count) keys).")
            } catch {
                alertMessage = error.localizedDescription
            }
        }
        .alert("3105 2.0", isPresented: Binding(get: { !alertMessage.isEmpty }, set: { if !$0 { alertMessage = "" } })) {
            Button(t("Đóng", "Close")) { alertMessage = "" }
        } message: {
            Text(alertMessage)
        }
    }

    // MARK: - Section 0: Workspace v9 (Application + AppGroup + settings.json + Plist/JSON Merge)

    private var workspaceV9View: some View {
        List {
            Section(t("Tạo Workspace chuẩn 3105 2.0 (Schema v9)", "Create 3105 Workspace (Schema v9)")) {
                TextField(t("Tên dự án Patch (VD: LocketV9)", "Patch Project Name (e.g. LocketV9)"), text: $newWorkspaceName)
                Toggle(t("Tạo kèm mẫu settings.json, %3105_Overwrite% & %3105_MatchPrefix%", "Include sample settings.json, %3105_Overwrite% & %3105_MatchPrefix%"), isOn: $includeSampleRules)
                Button(t("Tạo Workspace Application + AppGroup", "Create Application + AppGroup Workspace")) {
                    do {
                        let created = try NiKWorkspaceV9Service.createWorkspace(
                            named: newWorkspaceName,
                            includeSampleSampleRule: includeSampleRules
                        )
                        newWorkspaceName = ""
                        reloadWorkspaces()
                        selectWorkspace(created.workspaceURL, project: created.project)
                        alertMessage = t("Đã tạo workspace '\(created.project.name)' tại Documents/Patches/ với đầy đủ settings.json, Application/ và AppGroup/.", "Created workspace '\(created.project.name)' in Documents/Patches/ with settings.json, Application/ and AppGroup/.")
                    } catch {
                        alertMessage = error.localizedDescription
                    }
                }
                .buttonStyle(.borderedProminent)
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))

            Section(t("Danh sách Workspace v9 (\(workspaces.count))", "Workspace v9 (\(workspaces.count))")) {
                if workspaces.isEmpty {
                    Text(t("Chưa có workspace v9 nào. Hãy bấm Tạo ở trên để khởi tạo cấu trúc Application/, AppGroup/ và settings.json.", "No v9 workspaces yet. Create one above with Application/, AppGroup/ and settings.json."))
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
                                    Text(t("\(entry.project.rules.count) ánh xạ · \(entry.project.settings.fields.count) trường settings.json", "\(entry.project.rules.count) mappings · \(entry.project.settings.fields.count) settings.json fields"))
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
            .listRowBackground(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))

            if let project = activeProject, let wsURL = selectedWorkspaceURL {
                Section(t("Chi tiết & Tùy chỉnh: \(project.name)", "Details & Options: \(project.name)")) {
                    Button(t("Đồng bộ lại từ thư mục Workspace", "Reload from Workspace Folder")) {
                        do {
                            let synced = try NiKWorkspaceV9Service.synchronizeWorkspace(at: wsURL)
                            selectWorkspace(wsURL, project: synced)
                            alertMessage = t("Đã đồng bộ \(synced.rules.count) quy tắc và \(synced.settings.fields.count) trường tùy chỉnh.", "Loaded \(synced.rules.count) rules and \(synced.settings.fields.count) custom fields.")
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
                                    Toggle(t("Giá trị Boolean", "Boolean Value"), isOn: Binding(
                                        get: { bindingForFieldValue(field).wrappedValue.lowercased() == "true" },
                                        set: { bindingForFieldValue(field).wrappedValue = $0 ? "true" : "false" }
                                    ))
                                } else {
                                    TextField(t("Nhập giá trị cho \(field.id)", "Enter value for \(field.id)"), text: bindingForFieldValue(field))
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                        .font(.caption.monospaced())
                                }
                                if field.canRemove == true {
                                    Toggle(t("Xoá trường này (canRemove)", "Remove This Field (canRemove)"), isOn: bindingForFieldRemove(field))
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
                            Text("\(t("Chế độ", "Mode")): \(rule.mode == .replaceFile ? t("Thay thế toàn bộ file", "Replace Entire File") : (rule.mode == .mergePlist ? t("Sửa/Merge nội dung Plist", "Edit/Merge Plist") : t("Sửa/Merge nội dung JSON", "Edit/Merge JSON")))")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                        .padding(.vertical, 2)
                    }

                    Button(t("Áp dụng Patch v9 (Application & AppGroup)", "Apply Patch v9 (Application & AppGroup)")) {
                        do {
                            let result = try NiKWorkspaceV9Service.apply(project: project, userValues: fieldInputs)
                            let skippedNote = result.skippedIdentifiers.isEmpty
                                ? ""
                                : " (\(t("Bỏ qua container chưa có trên máy", "Skipped Missing Containers")): \(result.skippedIdentifiers.joined(separator: ", ")))"
                            alertMessage = t("Đã áp dụng \(result.appliedCount) quy tắc thành công\(skippedNote).", "Applied \(result.appliedCount) rules successfully\(skippedNote).")
                        } catch {
                            alertMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.borderedProminent)

                    if NiKWorkspaceV9Service.hasBackupReceipt(projectID: project.id) {
                        Button(t("Khôi phục file gốc (Restore)", "Restore Original Files"), role: .destructive) {
                            do {
                                let count = try NiKWorkspaceV9Service.restore(projectID: project.id)
                                alertMessage = t("Đã khôi phục \(count) tệp về nguyên bản trước khi áp dụng.", "Restored \(count) original files.")
                            } catch {
                                alertMessage = error.localizedDescription
                            }
                        }
                    }
                }
                .listRowBackground(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
            }
        }
    }

    // MARK: - Section 1: Dialer (.3105pass)

    private var dialerView: some View {
        List {
            Section(t("Quản lý gói Dialer (.3105pass)", "Manage Dialer Packages (.3105pass)")) {
                Button(t("Nhập gói .3105pass từ Tệp", "Import .3105pass from Files")) {
                    importingDialer = true
                }
                Button(t("Tạo gói .3105pass mẫu (Sáng / Tối / Chữ đậm)", "Create Sample .3105pass (Light / Dark / Bold)")) {
                    do {
                        let sample = try NiKDialerService.createSamplePackage()
                        dialerPackages = NiKDialerService.loadInstalledPackages()
                        alertMessage = t("Đã tạo gói mẫu '\(sample.name)' với đủ 3 kiểu phím: Sáng, Tối và Chữ đậm.", "Created sample '\(sample.name)' with Light, Dark and Bold keys.")
                    } catch {
                        alertMessage = error.localizedDescription
                    }
                }
                Text(t("Hỗ trợ tự nhận diện kiểu phím Sáng (Light), Tối (Dark) và Chữ đậm (Bold) theo dữ liệu trên thiết bị, kèm sao lưu và khôi phục an toàn.", "Detects Light, Dark and Bold key styles from device data, with backup and restore."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))

            Section(t("Gói Dialer đã nhập (\(dialerPackages.count))", "Imported Dialer Packages (\(dialerPackages.count))")) {
                if dialerPackages.isEmpty {
                    Text(t("Chưa có gói .3105pass nào.", "No .3105pass packages yet."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(dialerPackages) { pkg in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(pkg.name).font(.headline)
                            Text("\(t("Số phím", "Keys")): \(pkg.items.count) · \(t("Kiểu nhận diện", "Detected Styles")): \(pkg.detectedStyles.map(\.rawValue).joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 12) {
                                Button(t("Áp dụng", "Apply")) {
                                    do {
                                        alertMessage = try NiKDialerService.apply(pkg)
                                    } catch {
                                        alertMessage = error.localizedDescription
                                    }
                                }
                                .buttonStyle(.borderedProminent)

                                Button(t("Khôi phục", "Restore")) {
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
            .listRowBackground(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
        }
    }

    // MARK: - Section 2: Footnote, Supervised & Cleaner Feature Package

    private var systemFeaturesView: some View {
        Form {
            Section(t("Tính năng 3105 (Cài / Gỡ từ Kho & Đã cài)", "3105 Features (Install / Remove)")) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("Dọn dẹp (3105 Cleaner)", "3105 Cleaner"))
                            .font(.headline)
                        Text(systemFeatures.isCleanerInstalled ? t("Trạng thái: Đã cài đặt", "Status: Installed") : t("Trạng thái: Đã gỡ", "Status: Removed"))
                            .font(.caption)
                            .foregroundStyle(systemFeatures.isCleanerInstalled ? Color.green : Color.secondary)
                    }
                    Spacer()
                    Button(systemFeatures.isCleanerInstalled ? t("Gỡ tính năng", "Remove Feature") : t("Cài đặt", "Install")) {
                        systemFeatures.toggleCleanerInstallation()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(systemFeatures.isCleanerInstalled ? .red : .orange)
                }
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))

            Section(t("Footnote màn hình khóa (Lock Screen Footnote)", "Lock Screen Footnote")) {
                TextField(t("Nội dung hiển thị ở cuối màn hình khóa…", "Text at the bottom of the lock screen…"), text: $systemFeatures.footnoteText)
                Button(t("Áp dụng Footnote màn hình khóa", "Apply Lock Screen Footnote")) {
                    systemFeatures.applyFootnote()
                }
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))

            Section(t("Chế độ Giám sát (Supervised Mode)", "Supervised Mode")) {
                Toggle(t("Bật trạng thái Supervised (IsSupervised)", "Enable Supervised State (IsSupervised)"), isOn: $systemFeatures.isSupervisedEnabled)
                TextField(t("Tên tổ chức hiển thị (OrganizationName)", "Organization Name (OrganizationName)"), text: $systemFeatures.organizationName)
                Button(t("Cập nhật cấu hình Supervised", "Update Supervised Configuration")) {
                    systemFeatures.applySupervisedState()
                }
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))

            Section(t("Sao lưu & Khôi phục hệ thống", "System Backup & Restore")) {
                Button(t("Khôi phục Footnote & Supervised về nguyên gốc", "Restore Original Footnote & Supervised"), role: .destructive) {
                    systemFeatures.restoreOriginalSystemConfigs()
                }
                if !systemFeatures.lastStatusMessage.isEmpty {
                    Text(systemFeatures.lastStatusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color(uiColor: .secondarySystemGroupedBackground)))
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
