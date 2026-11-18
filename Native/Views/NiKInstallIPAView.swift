import SwiftUI

struct NiKInstallIPAView: View {
    let url: URL
    @ObservedObject private var install = NiKInstallationController.shared
    @ObservedObject private var server = NiKHTTPSOTAServer.shared
    @AppStorage("nik.language") private var language = "vi"
    @Environment(\.dismiss) private var dismiss
    @State private var automaticallyRequested = false
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    private var correctFile: Bool { install.fileURL == url }
    var body: some View {
        NavigationStack {
            List {
                Section(t("Ứng dụng", "Application")) {
                    Text(correctFile ? install.metadata?.title ?? url.lastPathComponent : url.lastPathComponent)
                    if correctFile, let info = install.metadata { Text(info.bundleID + " · " + info.version).font(.caption) }
                }
                Section(t("Cài đặt", "Installation")) {
                    if install.busy { ProgressView(t("Đang kiểm tra IPA / HTTPS…", "Checking IPA / HTTPS…")) }
                    if correctFile {
                        if !server.isRunning && !install.busy { Text(t("Máy chủ đã dừng. Bấm Chuẩn bị lại trước khi cài.", "Server stopped. Prepare again before installing.")) }
                        switch install.phase {
                        case .ready: Label(t("HTTPS đã được hệ thống tin cậy", "HTTPS is trusted by the system"), systemImage: "checkmark.shield")
                        case .trustRequired: Text(t("HTTPS nội bộ chưa được tin cậy. Làm theo hướng dẫn bên dưới trước khi cài.", "Local HTTPS is not trusted. Complete the steps below before installing."))
                        case .requestSent: Text(t("Đã gửi yêu cầu cho iOS. Việc mở liên kết không xác nhận hộp thoại đã hiện hoặc ứng dụng đã cài.", "Request sent to iOS. Opening the link does not confirm a prompt appeared or the app was installed."))
                        default: EmptyView()
                        }
                        if let error = install.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    }
                    Button(t("Kiểm tra / Chuẩn bị lại", "Check / Prepare Again")) { Task { await install.prepare(url) } }
                        .disabled(install.busy)
                    Button(t("Cài đặt", "Install")) { Task { await install.install() } }
                        .disabled(!correctFile || install.busy || !server.isRunning || install.phase == .trustRequired || install.metadata == nil)
                    if correctFile, server.isRunning {
                        Text(t("Manifest: \(server.manifestRequests) yêu cầu · IPA: \(server.ipaRequests) yêu cầu", "Manifest: \(server.manifestRequests) requests · IPA: \(server.ipaRequests) requests")).font(.caption)
                    }
                }
                Section(t("Thiết lập HTTPS lần đầu", "First-time HTTPS Setup")) {
                    Text(t("1. Tải hồ sơ HTTPS bằng nút bên dưới.\n2. Vào Cài đặt → Cài đặt chung → VPN & Quản lý thiết bị, cài hồ sơ NiKSign Local HTTPS OTA.\n3. Vào Cài đặt chung → Giới thiệu → Cài đặt tin cậy chứng nhận, bật tin cậy đầy đủ cho chứng nhận của hồ sơ vừa cài (tên localhost).\n4. Quay lại NiKSign, bấm Kiểm tra / Chuẩn bị lại rồi Cài đặt.", "1. Download the HTTPS profile below.\n2. In Settings → General → VPN & Device Management, install NiKSign Local HTTPS OTA.\n3. In General → About → Certificate Trust Settings, enable full trust for the certificate from that profile (named localhost).\n4. Return to NiKSign, check/prepare again, then install."))
                        .font(.footnote)
                    Button(t("Tải hồ sơ HTTPS trong Safari", "Download HTTPS Profile in Safari")) { Task { await install.downloadTrustProfile() } }
                        .disabled(install.busy)
                }
                Section {
                    Text(t("Máy chủ chỉ phục vụ nội bộ trên thiết bị. Chứng chỉ ký/profile, UDID và giới hạn của iOS vẫn quyết định IPA có cài được hay không. Nếu yêu cầu đã gửi nhưng IPA vẫn không được tải, hãy kiểm tra hồ sơ tin cậy và giới hạn cài đặt của máy.", "The server only serves this device locally. Signing credentials, provisioning, device membership and iOS restrictions still determine installation eligibility. If the request was sent but the IPA is not fetched, check HTTPS trust and device installation restrictions.")).font(.footnote)
                    Button(t("Dừng máy chủ cài đặt", "Stop Installation Server"), role: .destructive) { install.stop() }
                        .disabled(install.busy)
                }
            }
            .navigationTitle(t("Cài IPA đã ký", "Install Signed IPA"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(t("Đóng", "Close")) { dismiss() } } }
            .task {
                await install.prepare(url)
                if !Task.isCancelled, correctFile, install.phase == .ready, !automaticallyRequested {
                    automaticallyRequested = true
                    await install.install()
                }
            }
        }
    }
}
