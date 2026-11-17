import SwiftUI

struct NiKSettingsView: View {
    @ObservedObject var certificates: NiKCertificateStore
    @ObservedObject var library: NiKLibrary
    @AppStorage("nik.language") private var language = "vi"
    @AppStorage("nik.mode") private var mode = "both"
    @AppStorage("nik.theme") private var theme = "system"
    @AppStorage("nik.interfaceMode") private var interfaceMode = "basic"
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    brandCard
                    preferencesCard
                    card {
                        NavigationLink { NiKCertificateSettings(store: certificates) } label: {
                            row("signature", .orange, t("Chứng chỉ", "Certificates"), "\(certificates.profiles.count) " + t("chứng chỉ đã lưu", "saved certificates"))
                        }
                    }
                    card {
                    NavigationLink { NiKRecoveryHistoryView() } label: {
                        row("arrow.uturn.backward", .indigo, t("Khôi phục tệp", "File Recovery"), t("Backup và lịch sử chỉnh sửa", "Backups and Edit History"))
                    }
                }
                linksCard
                    legalCard
                }.padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(t("Cài đặt", "Settings"))
        }
    }
    private var brandCard: some View {
        card {
            HStack(spacing: 14) {
                NiKBrand()
                VStack(alignment: .leading, spacing: 4) {
                    Text("NiKSign").font(.title2.bold())
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "3.3.0") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "330"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
    private var preferencesCard: some View {
        card {
            VStack(spacing: 14) {
                Menu {
                    Button("Tiếng Việt") { language = "vi" }
                    Button("English") { language = "en" }
                } label: { row("globe", .blue, t("Ngôn ngữ", "Language"), language == "en" ? "English" : "Tiếng Việt") }
                Divider()
                Menu {
                    Button(t("Chỉ ký IPA", "Sign IPA only")) { mode = "sign" }
                    Button(t("Chỉ 3105", "3105 only")) { mode = "tools" }
                    Button(t("Cả hai", "Both")) { mode = "both" }
                } label: { row("slider.horizontal.3", .indigo, t("Chế độ", "Mode"), mode == "sign" ? "IPA" : mode == "tools" ? "3105" : "IPA + 3105") }
                Divider()
                Menu {
                    Button(t("Cơ bản", "Basic")) { interfaceMode = "basic" }
                    Button(t("Nâng cao", "Advanced")) { interfaceMode = "advanced" }
                } label: {
                    row("switch.2", .teal, t("Mức tùy chỉnh", "Customization Level"), interfaceMode == "advanced" ? t("Nâng cao", "Advanced") : t("Cơ bản", "Basic"))
                }
                Text(t("Đổi mức hiển thị giữ nguyên tùy chọn của từng IPA và hàng đợi đang chạy.", "Changing the display level preserves each IPA’s options and running jobs."))
                    .font(.caption).foregroundStyle(.secondary)
                Divider()
                Menu {
                    Button(t("Theo hệ thống", "System")) { theme = "system" }
                    Button(t("Sáng", "Light")) { theme = "light" }
                    Button(t("Tối", "Dark")) { theme = "dark" }
                } label: { row("paintbrush", .purple, t("Giao diện", "Appearance"), theme == "light" ? t("Sáng", "Light") : theme == "dark" ? t("Tối", "Dark") : t("Theo hệ thống", "System")) }
            }
        }
    }
    private var linksCard: some View {
        card {
            VStack(spacing: 14) {
                Link(destination: URL(string: "https://t.me/nikvn21")!) {
                    row("paperplane.fill", .cyan, t("Kênh Telegram", "Telegram Channel"), "@nikvn21")
                }
                Divider()
                Link(destination: URL(string: "https://github.com/joinalex1122/NiKSign-Build")!) {
                    row("globe", .teal, t("Trang web & Mã nguồn", "Website & Source Code"), "github.com/joinalex1122/NiKSign-Build")
                }
                Divider()
                NavigationLink { schemes } label: { row("link", .green, "URL Scheme", "niksign:// · threeoneosfive://") }
                Divider()
                NavigationLink { NiKDiagnosticsView() } label: { row("stethoscope", .gray, t("Chẩn đoán & Báo cáo", "Diagnostics & Report"), t("Xem trước và xuất trạng thái đã ẩn thông tin riêng", "Preview and export status without private details")) }
            }
        }
    }
    private var schemes: some View {
        List {
            ForEach(["niksign://", "threeoneosfive://"], id: \.self) { scheme in
                Button { UIPasteboard.general.string = scheme } label: { Label(scheme, systemImage: "doc.on.doc") }
            }
            Text(t("Dùng các URL này để mở ứng dụng. Để nhập IPA, dùng nút Nhập hoặc Chia sẻ → NiKSign trong ứng dụng Tệp.", "Use these URLs to open the app. Import an IPA using Import or Share → NiKSign in Files."))
                .font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle("URL Scheme")
    }
    private var logs: some View {
        List {
            Text(library.error.isEmpty ? (library.notice.isEmpty ? t("Không có thông báo mới", "No recent notices") : library.notice) : library.error)
            Text(t("Tệp tạm được dọn khi thao tác hoàn tất. IPA đã xuất được giữ lại để bạn chia sẻ.", "Temporary files are cleaned up when operations finish. Exported IPAs are retained for sharing."))
                .font(.footnote).foregroundStyle(.secondary)
        }.navigationTitle(t("Nhật ký", "Logs"))
    }
    private var legalCard: some View {
        card {
            VStack(spacing: 14) {
                NavigationLink {
                    ScrollView { Text(t("Việc ký và chỉnh sửa IPA được xử lý trên thiết bị. Bạn quản lý chứng chỉ và quyền sử dụng tệp của mình.", "IPA signing and editing run on your device. You manage your certificates and file permissions.")).padding() }
                        .navigationTitle(t("Điều khoản dịch vụ", "Terms of Service"))
                } label: { row("doc.text.fill", .blue, t("Điều khoản dịch vụ", "Terms of Service"), "NiKSign") }
                Divider()
                NavigationLink {
                    ScrollView { Text(t("Chứng chỉ và IPA được xử lý trên thiết bị. Mật khẩu chứng chỉ đã lưu nằm trong Keychain. Các chức năng tải nguồn và liên kết bên ngoài sử dụng mạng khi bạn mở chúng.", "Certificates and IPAs are processed on-device. Saved certificate passwords use Keychain. Repository downloads and external links access the network when opened.")).padding() }
                        .navigationTitle(t("Chính sách bảo mật", "Privacy Policy"))
                } label: { row("lock.shield.fill", .mint, t("Chính sách bảo mật", "Privacy Policy"), t("Dữ liệu trên thiết bị", "On-device data")) }
                Divider()
                NavigationLink { NiKLicensesView() } label: {
                    row("doc.plaintext", .secondary, t("Thành phần và giấy phép", "Components & Licenses"), "ZIPFoundation · OpenSSL · Zsign")
                }
            }
        }
    }
    private func card<C: View>(@ViewBuilder _ content: () -> C) -> some View {
        content().padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
    private func row(_ icon: String, _ color: Color, _ title: String, _ subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(color).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.medium)).foregroundStyle(.primary)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.tertiary)
        }
    }
}
