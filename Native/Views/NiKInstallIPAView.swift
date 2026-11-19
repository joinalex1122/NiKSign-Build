import SwiftUI
import CoreImage.CIFilterBuiltins

struct NiKInstallIPAView: View {
    let url: URL
    @ObservedObject private var install = NiKInstallationController.shared
    @ObservedObject private var server = NiKHTTPSOTAServer.shared
    @AppStorage("nik.language") private var language = "vi"
    @Environment(\.dismiss) private var dismiss
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    private var correctFile: Bool { install.fileURL == url }
    var body: some View {
        NavigationStack {
            List {
                Section(t("Ứng dụng", "Application")) {
                    Text(correctFile ? install.metadata?.title ?? url.lastPathComponent : url.lastPathComponent)
                    if correctFile, let info = install.metadata { Text(info.bundleID + " · " + info.version).font(.caption) }
                }
                Section(t("Cài qua HTTPS cục bộ", "Local HTTPS Installation")) {
                    if install.busy { ProgressView(t("Đang kiểm tra IPA / kết nối…", "Checking IPA / connection…")) }
                    if correctFile {
                        switch install.phase {
                        case .ready: Label(t("Kiểm tra HTTPS trong NiKSign: đạt", "HTTPS Check in NiKSign: Passed"), systemImage: "checkmark.shield")
                        case .trustRequired: Text(t("Cần thiết lập tin cậy HTTPS bên dưới trước khi cài.", "Set up HTTPS trust below before installing."))
                        case .requestSent: Text(t("Đã gửi yêu cầu cho iOS; chưa xác nhận cài đặt hoàn tất.", "Request sent to iOS; installation is not yet confirmed."))
                        default: EmptyView()
                        }
                        if let notice = install.deliveryNotice { Text(notice).font(.footnote).foregroundStyle(.orange) }
                        if let error = install.error { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    }
                    Button(t("Kiểm tra / Chuẩn bị lại", "Check / Prepare Again")) { Task { await install.prepare(url) } }.disabled(install.busy)
                    Button(t("Cài đặt", "Install")) { Task { await install.install() } }
                        .disabled(!correctFile || install.busy || !install.isInstallerRunning || ![.ready, .requestSent].contains(install.phase))
                    if correctFile, install.isInstallerRunning {
                        Text(t("Kết nối: \(server.acceptedConnections)", "Connections: \(server.acceptedConnections)")).font(.caption)
                        Text("Manifest: \(server.manifestRequests) · IPA: \(server.ipaRequests)").font(.caption)
                        if let error = server.connectionError { Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled) }
                    }
                }
                if correctFile, install.isInstallerRunning, let link = server.landingURL {
                    Section(t("Liên kết cài đặt", "Installation Link")) {
                        if let qr = Self.qr(link.absoluteString) {
                            Image(uiImage: qr).interpolation(.none).resizable().scaledToFit()
                                .frame(width: 180, height: 180).padding().background(.white)
                                .accessibilityLabel(t("Mã QR liên kết cài đặt", "Installation link QR code"))
                        }
                        Link(t("Mở trang cài trong Safari", "Open Installation Page in Safari"), destination: link)
                        ShareLink(item: link) { Label(t("Chia sẻ liên kết", "Share Link"), systemImage: "square.and.arrow.up") }
                        Button(t("Sao chép liên kết", "Copy Link")) { UIPasteboard.general.url = link }
                        Text(link.absoluteString).font(.caption2).textSelection(.enabled)
                        Text(t("Liên kết 127.0.0.1 và QR chỉ dùng trên chính iPhone này khi máy chủ còn chạy. Không thể dùng để cài từ máy khác.", "The 127.0.0.1 link and QR work only on this iPhone while the server is running. They cannot install on another device.")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section(t("Tin cậy HTTPS", "HTTPS Trust")) {
                    NavigationLink(t("Mở thiết lập tin cậy", "Open Trust Setup")) { NiKTrustSetupView() }
                    Text(t("Bạn cần cài hồ sơ và bật tin cậy đầy đủ trong Cài đặt. Kiểm tra trong app đạt chưa chứng minh trình cài iOS chấp nhận cùng chứng nhận.", "Install the profile and enable full trust in Settings. A successful app check does not prove the iOS installer accepts the same certificate.")).font(.footnote)
                }
                Section {
                    Text(t("Giữ NiKSign chạy khi iOS tải IPA. Chứng chỉ, profile và giới hạn thiết bị vẫn quyết định khả năng cài đặt.", "Keep NiKSign running while iOS downloads the IPA. Signing credentials, provisioning and device restrictions determine installation eligibility.")).font(.footnote)
                    Button(t("Dừng máy chủ", "Stop Server"), role: .destructive) { install.stop() }.disabled(install.busy)
                }
            }
            .navigationTitle(t("Cài IPA đã ký", "Install Signed IPA"))
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button(t("Đóng", "Close")) { dismiss() } } }
            .task { await install.prepare(url) }
        }
    }
    private static func qr(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        guard let output = filter.outputImage,
              let cg = CIContext().createCGImage(output.transformed(by: .init(scaleX: 6, y: 6)), from: output.extent.applying(.init(scaleX: 6, y: 6))) else { return nil }
        return UIImage(cgImage: cg)
    }
}
