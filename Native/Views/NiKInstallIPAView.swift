import SwiftUI

struct NiKInstallIPAView: View {
    let url: URL
    @ObservedObject private var install = NiKInstallationController.shared
    @ObservedObject private var server = NiKHTTPSOTAServer.shared
    @AppStorage("nik.language") private var language = "vi"
    @Environment(\.dismiss) private var dismiss
    @State private var automaticallyRequested = false
    @State private var showConsent = false
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    private var correctFile: Bool { install.fileURL == url }
    private var standard: Bool { install.method == .standard }
    var body: some View {
        NavigationStack {
            List {
                Section(t("Ứng dụng", "Application")) {
                    Text(correctFile ? install.metadata?.title ?? url.lastPathComponent : url.lastPathComponent)
                    if correctFile, let info = install.metadata { Text(info.bundleID + " · " + info.version).font(.caption) }
                }
                Section(t("Phương thức cài", "Installation Method")) {
                    Picker(t("Phương thức", "Method"), selection: $install.method) {
                        Text(t("Tiêu chuẩn", "Standard")).tag(NiKInstallationController.Method.standard)
                        Text(t("HTTPS nội bộ", "Local HTTPS")).tag(NiKInstallationController.Method.localHTTPS)
                    }.disabled(install.busy)
                    if standard {
                        Text(t("Manifest qua HTTPS công khai của SignTools; IPA được tải từ máy chủ HTTP chỉ trên iPhone. Không cần hồ sơ HTTPS localhost cho phương thức này.", "The manifest uses SignTools public HTTPS; the IPA is served over HTTP only on this iPhone. This method does not require a localhost HTTPS profile.")).font(.footnote)
                        Text(t("Dịch vụ signtools.github.io thấy IP mạng và số cổng được yêu cầu. NiKSign không gửi IPA, tên ứng dụng, Bundle ID, UDID, chứng chỉ hay mật khẩu cho dịch vụ này.", "signtools.github.io sees your network IP and the requested port. NiKSign does not send it the IPA, app name, bundle ID, UDID, signing certificates or passwords.")).font(.caption).foregroundStyle(.secondary)
                        Text(t("Hộp thoại iOS có thể hiện tên chung “Local app”. Tên và Bundle ID bên trong IPA vẫn giữ nguyên.", "The iOS prompt may show the generic name “Local app”. The IPA’s own name and bundle ID remain unchanged.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(t("Cài đặt", "Installation")) {
                    if install.busy { ProgressView(t("Đang kiểm tra IPA / kết nối…", "Checking IPA / connection…")) }
                    if correctFile {
                        if !install.isInstallerRunning && !install.busy { Text(t("Máy chủ đã dừng. Bấm Chuẩn bị lại trước khi cài.", "Server stopped. Prepare again before installing.")) }
                        switch install.phase {
                        case .ready:
                            Label(standard ? t("Máy chủ IPA và manifest đã kiểm tra", "IPA Server and Manifest Checked") : t("Kiểm tra HTTPS trong NiKSign: đạt", "HTTPS Check in NiKSign: Passed"), systemImage: "checkmark.shield")
                        case .consentRequired:
                            Text(t("Bấm Cài đặt để xác nhận sử dụng manifest công khai lần đầu.", "Tap Install to confirm the first use of the public manifest."))
                        case .trustRequired:
                            Text(t("HTTPS nội bộ chưa được tin cậy. Bạn có thể chuyển sang Tiêu chuẩn hoặc mở thiết lập tin cậy bên dưới.", "Local HTTPS is not trusted. Switch to Standard or open trust setup below."))
                        case .requestSent:
                            Text(t("Đã gửi yêu cầu cho iOS. Chỉ khi có yêu cầu IPA bên dưới mới biết máy đã bắt đầu truy cập tệp; đây chưa phải xác nhận cài xong.", "Request sent to iOS. An IPA request below indicates access to the file has started; it does not confirm installation completed."))
                        default: EmptyView()
                        }
                        if let notice = install.deliveryNotice { Text(notice).font(.footnote).foregroundStyle(.orange) }
                        if let error = install.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    }
                    Button(t("Kiểm tra / Chuẩn bị lại", "Check / Prepare Again")) { Task { await install.prepare(url) } }.disabled(install.busy)
                    Button(t("Cài đặt", "Install")) {
                        if install.phase == .consentRequired { showConsent = true }
                        else { Task { await install.install() } }
                    }.disabled(!correctFile || install.busy || !install.isInstallerRunning || install.phase == .trustRequired || install.metadata == nil)
                    if correctFile, install.isInstallerRunning {
                        if standard {
                            Text(t("Yêu cầu IPA trên iPhone: \(install.localIPARequests)", "IPA Requests on iPhone: \(install.localIPARequests)")).font(.caption)
                            Text(t("Manifest do dịch vụ HTTPS công khai phục vụ; không đếm là kết nối vào NiKSign.", "The manifest is served by the public HTTPS service; it is not counted as a connection to NiKSign.")).font(.caption2).foregroundStyle(.secondary)
                        } else {
                            Text(t("Kết nối: \(server.acceptedConnections)", "Connections: \(server.acceptedConnections)")).font(.caption)
                            if let error = server.connectionError { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                            Text(t("Manifest: \(server.manifestRequests) · IPA: \(server.ipaRequests)", "Manifest: \(server.manifestRequests) · IPA: \(server.ipaRequests)")).font(.caption)
                        }
                    }
                }
                if !standard {
                    Section(t("Thiết lập HTTPS nội bộ", "Local HTTPS Setup")) {
                        NavigationLink(t("Mở thiết lập tin cậy", "Open Trust Setup")) { NiKTrustSetupView() }
                        Text(t("Kiểm tra HTTPS trong app không chứng minh trình cài iOS sẽ chấp nhận cùng chứng nhận. Nếu vẫn lỗi 127.0.0.1, chọn phương thức Tiêu chuẩn.", "An HTTPS check in the app does not prove the iOS installer will accept the same certificate. If 127.0.0.1 still fails, select Standard.")).font(.footnote)
                    }
                }
                Section {
                    Text(t("Giữ NiKSign chạy trong khi iOS tải IPA. Chứng chỉ ký, profile, thiết bị được phép và giới hạn của iOS vẫn quyết định ứng dụng có cài được hay không.", "Keep NiKSign running while iOS downloads the IPA. Signing credentials, provisioning, device eligibility and iOS restrictions still determine whether installation succeeds.")).font(.footnote)
                    Button(t("Dừng máy chủ cài đặt", "Stop Installation Server"), role: .destructive) { install.stop() }.disabled(install.busy)
                }
            }
            .navigationTitle(t("Cài IPA đã ký", "Install Signed IPA"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(t("Đóng", "Close")) { dismiss() } } }
            .alert(t("Dùng manifest công khai?", "Use the Public Manifest?"), isPresented: $showConsent) {
                Button(t("Đồng ý & Cài đặt", "Allow & Install")) {
                    install.allowPublicManifest()
                    Task { await install.install() }
                }
                Button(t("Hủy", "Cancel"), role: .cancel) {}
            } message: {
                Text(t("NiKSign sẽ kết nối signtools.github.io để lấy manifest theo số cổng. Dịch vụ thấy IP mạng; IPA và chứng chỉ ở lại trên máy. Hộp thoại iOS có thể hiện “Local app”.", "NiKSign will contact signtools.github.io for a port-specific manifest. The service sees your network IP; your IPA and certificates stay on-device. The iOS prompt may show “Local app”."))
            }
            .onChange(of: install.method) { _, _ in Task { await install.prepare(url) } }
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
