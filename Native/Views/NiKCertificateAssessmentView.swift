import SwiftUI

struct NiKCertificateAssessmentView: View {
    let profile: NiKCertificateProfile
    var bundleID: String? = nil
    var allowMismatch = false
    @AppStorage("nik.language") private var language = "vi"
    @AppStorage("nik.deviceUDID") private var deviceUDID = ""
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    private var assessment: NiKCertificateAssessment {
        NiKCertificateCompatibility.assess(profile, bundleID: bundleID, deviceUDID: deviceUDID, allowMismatch: allowMismatch)
    }
    var body: some View {
        List {
            Section(t("Bộ chứng chỉ", "Certificate Pair")) {
                LabeledContent(t("Tên", "Name"), value: profile.name)
                LabeledContent("Team", value: profile.teamName)
                LabeledContent("Team ID", value: profile.teamID)
                LabeledContent("Bundle ID", value: profile.bundleIDPattern)
                LabeledContent(t("Loại phân phối", "Distribution"), value: distributionText)
                if let date = profile.certificateExpirationDate { LabeledContent(t("Hạn chứng chỉ", "Certificate Expiry"), value: date.formatted()) }
                if let date = profile.expirationDate { LabeledContent(t("Hạn profile", "Profile Expiry"), value: date.formatted()) }
                Text(profile.sha1Fingerprint).font(.caption.monospaced()).textSelection(.enabled)
            }
            Section(t("Thiết bị đích (tùy chọn)", "Target Device (Optional)")) {
                TextField("UDID", text: $deviceUDID).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text(t("UDID do bạn nhập, không tự lấy từ hệ thống. Để trống nếu chưa biết; khi đó không xác nhận được thiết bị có trong profile.", "Enter the UDID yourself; it is not obtained from the system. Leaving it blank leaves device membership unverified.")).font(.caption).foregroundStyle(.secondary)
                NavigationLink(t("Thiết bị trong profile", "Devices in Profile") + " (\(profile.provisionedUDIDs.count))") {
                    List(profile.provisionedUDIDs, id: \.self) { Text($0).font(.caption.monospaced()).textSelection(.enabled) }
                        .navigationTitle(t("UDID được phép", "Provisioned UDIDs"))
                }
            }
            Section(t("Kết quả phân tích", "Assessment")) {
                if let bundleID { Text("Bundle ID: " + bundleID).font(.caption.monospaced()) }
                Text(assessment.canSign ? t("Không có lỗi chặn trong các kiểm tra hiện có.", "No blocking issue in the available checks.") : t("Có lỗi cần xử lý trước khi ký.", "Resolve the blocking issues before signing."))
                    .foregroundStyle(assessment.canSign ? Color.green : Color.red)
                ForEach(assessment.issues) { issue in
                    Label(language == "en" ? issue.en : issue.vi, systemImage: issue.severity == .blocking ? "xmark.octagon" : "exclamationmark.triangle")
                        .font(.footnote).foregroundStyle(issue.severity == .blocking ? Color.red : Color.orange)
                }
                Text(t("Đây là phân tích dữ liệu ngoại tuyến; chưa xác minh thu hồi, chữ ký CMS của Apple hoặc khả năng cài đặt trên iPhone.", "This is offline metadata analysis; revocation, Apple's CMS signature and iPhone installation eligibility are not verified.")).font(.caption).foregroundStyle(.secondary)
            }
            Section(t("Quyền profile cho phép", "Profile Entitlements")) {
                if let permissions = profile.entitlements {
                    ForEach(permissions.keys.sorted(), id: \.self) { key in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(key).font(.caption.bold())
                            Text(permissions[key]?.displayText ?? "").font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                } else { Text(t("Bản lưu cũ chưa có dữ liệu quyền; nhập lại để xem chi tiết.", "This older record has no entitlement details; reimport to inspect them.")) }
            }
        }
        .navigationTitle(t("Phân tích chứng chỉ", "Certificate Assessment"))
        .safeAreaInset(edge: .bottom) { Color.clear.frame(height: 100) }
    }
    private var distributionText: String {
        switch assessment.distribution {
        case .development: return "Development"
        case .adHoc: return "Ad Hoc"
        case .enterprise: return "Enterprise / In-House"
        case .appStore: return "App Store"
        case .unknown: return t("Chưa xác định", "Unknown")
        }
    }
}
