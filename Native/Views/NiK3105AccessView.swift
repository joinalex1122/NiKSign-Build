import SwiftUI

struct NiK3105AccessView: View {
    @AppStorage("nik.language") private var language = "vi"
    @State private var groups: [String]?
    @State private var accessible: Set<String> = []
    @State private var error: String?
    @State private var checked = false
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    var body: some View {
        List {
            Section(t("Bản đang cài", "Installed Build")) {
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "?")
                Text(ProcessInfo.processInfo.operatingSystemVersionString)
            }
            Section(t("Điều kiện App Group", "App Group Requirements")) {
                if checked {
                    switch NiK3105AccessAssessment.stage(groups: groups, accessible: accessible, backendAvailable: false) {
                    case .unknownEntitlements: Text(t("Chưa đọc được quyền App Group của chữ ký.", "Unable to read signed App Group entitlements."))
                    case .missingAppGroup: Text(t("Chữ ký hiện không có App Group. Cần profile cho phép một App Group riêng và ký app với entitlement phù hợp.", "This signature has no App Group. A profile authorizing an App Group and corresponding signed entitlements are required."))
                    case .inaccessibleAppGroup: Text(t("Có khai báo App Group nhưng chưa mở được container. Cần kiểm tra profile và cách ký/cài.", "App Groups are declared but no container could be opened. Check provisioning and signing/installation."))
                    case .missingBackend: Text(t("Đã có container App Group; bộ truy cập worse_query chưa được tích hợp trong bản NiKSign này.", "An App Group container is available; this NiKSign build does not yet integrate the worse_query backend."))
                    case .candidate: Text(t("Đủ điều kiện để thử, chưa xác minh quyền dữ liệu ứng dụng khác.", "Prerequisites met for testing; access to other applications is not verified."))
                    }
                    ForEach(groups ?? [], id: \.self) { group in
                        LabeledContent(group, value: accessible.contains(group) ? t("Mở được container", "Container available") : t("Chưa mở được", "Unavailable"))
                            .font(.caption)
                    }
                    if let error { Text(error).font(.caption).foregroundStyle(.secondary) }
                }
                Button(t("Kiểm tra quyền thực tế", "Check Actual Entitlements")) { check() }
            }
            Section(t("Đối chiếu với 3105 2.2 Beta 1", "Comparison with 3105 2.2 Beta 1")) {
                Text(t("Ảnh kiểm thử iOS 27.2 (24B119) dùng worse_query và báo App Group: Có. Đường này không cần ghép đôi/VPN. NiKSign hiện có bộ truy cập cũ; đổi nhãn hỗ trợ iOS hoặc bật Chế độ nhà phát triển không thay thế bộ truy cập đó.", "The tested iOS 27.2 (24B119) screenshot reports worse_query and an available App Group, without pairing/VPN. NiKSign currently uses the older backend; changing compatibility labels or enabling Developer Mode does not replace that backend."))
                Text(t("Thêm khóa vào Info.plist hoặc đổi Bundle ID không tự cấp App Group. Màn này chỉ kiểm tra quyền của NiKSign, không chạy khai thác hoặc sửa tệp.", "Adding an Info.plist key or changing Bundle ID does not grant an App Group. This screen only checks NiKSign's own permissions; it does not invoke an exploit or modify files."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(t("Truy cập 3105", "3105 Access"))
        .task { check() }
    }
    private func check() {
        var detail: NSError?
        groups = NiKSignedAppGroupIdentifiers(&detail)
        error = detail?.localizedDescription
        accessible = []
        for group in groups ?? [] {
            if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group),
               (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                accessible.insert(group)
            }
        }
        checked = true
    }
}
