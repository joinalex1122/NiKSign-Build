import SwiftUI

/// Acknowledging this screen never records that a certificate is trusted.
/// Only a successful HTTPS request using system validation can establish that.
struct NiKTrustSetupView: View {
    var onContinue: (() -> Void)? = nil
    @ObservedObject private var install = NiKInstallationController.shared
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("nik.language") private var language = "vi"
    @State private var downloaded = false
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    var body: some View {
        List {
            Section {
                Label(t("Chuẩn bị cài IPA đã ký", "Prepare to Install Signed IPAs"), systemImage: "checkmark.shield.fill")
                    .font(.headline)
                Text(t("Cài Tiêu chuẩn không cần hồ sơ HTTPS localhost. Thiết lập dưới đây chỉ dành cho phương thức HTTPS nội bộ tùy chọn. Chứng nhận HTTPS khác với chứng chỉ ký ứng dụng.", "Standard installation does not need a localhost HTTPS profile. The setup below is only for the optional Local HTTPS method. HTTPS and app signing certificates are separate."))
            }
            Section(t("Trạng thái", "Status")) {
                switch install.trustState {
                case .unknown: Text(t("Chưa kiểm tra", "Not checked"))
                case .checking: ProgressView(t("Đang kiểm tra HTTPS…", "Checking HTTPS…"))
                case .trusted: Label(t("Kiểm tra HTTPS trong NiKSign: đạt", "HTTPS Check in NiKSign: Passed"), systemImage: "checkmark.shield")
                case .required: Text(t("Cần cài hồ sơ và bật tin cậy đầy đủ", "Install the profile and enable full trust"))
                case .unavailable: Text(t("Chưa kết nối được máy chủ nội bộ", "Cannot connect to the local server"))
                }
                if let message = install.trustError { Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled) }
                Button(t("Kiểm tra tin cậy", "Check Trust")) { Task { await install.checkTrust() } }
                    .disabled(install.busy)
            }
            Section(t("Thực hiện trong Cài đặt", "Complete in Settings")) {
                Text(t("1. Bấm Tải hồ sơ HTTPS và cho phép Safari tải hồ sơ.\n2. Vào Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị → NiKSign Local HTTPS OTA → Cài đặt.\n3. Vào Cài đặt → Cài đặt chung → Giới thiệu → Cài đặt tin cậy chứng nhận → bật tin cậy đầy đủ cho localhost.\n4. Quay lại NiKSign và kiểm tra tin cậy.", "1. Tap Download HTTPS Profile and allow Safari to download it.\n2. Open Settings → General → VPN & Device Management → NiKSign Local HTTPS OTA → Install.\n3. Open Settings → General → About → Certificate Trust Settings → enable full trust for localhost.\n4. Return to NiKSign and check trust."))
                    .font(.footnote)
                Button(t("Tải hồ sơ HTTPS trong Safari", "Download HTTPS Profile in Safari")) {
                    downloaded = true
                    Task { await install.downloadTrustProfile() }
                }.disabled(install.busy)
                Text(t("iOS yêu cầu bạn tự xác nhận hai bước trong Cài đặt. NiKSign không thể bật tin cậy thay bạn. Hồ sơ chỉ chứa chứng nhận công khai của máy này.", "iOS requires you to confirm both steps in Settings. NiKSign cannot enable trust for you. The profile contains only this device’s public certificate."))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            if let onContinue {
                Section {
                    Button((install.method == .standard || install.trustState == .trusted) ? t("Tiếp tục", "Continue") : t("Để sau", "Later"), action: onContinue)
                        .frame(maxWidth: .infinity)
                    Text(t("Bạn có thể mở lại tại Cài đặt → Tin cậy & Cài IPA.", "You can return in Settings → Trust & IPA Installation."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(t("Tin cậy & Cài IPA", "Trust & IPA Installation"))
        .task { if install.method == .localHTTPS { await install.checkTrust() } }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active, downloaded { Task { await install.checkTrust() } }
        }
    }
}
