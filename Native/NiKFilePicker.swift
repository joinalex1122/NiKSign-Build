import SwiftUI
import UniformTypeIdentifiers
import QuickLook

/// Copy mode asks File Providers to download/materializer the document before returning it.
struct NiKFilePicker: UIViewControllerRepresentable {
    var onResult: (Result<URL, Error>) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.item], asCopy: true)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: NiKFilePicker
        init(parent: NiKFilePicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.dismiss()
            if let url = urls.first { parent.onResult(.success(url)) }
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { parent.dismiss() }
    }
}

struct NiKFilesHome: View {
    @AppStorage("nik.mode") private var mode = ""
    @AppStorage("nik.language") private var language = "vi"
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    @State private var session = FilesTabSession()
    private var supported: Bool {
        let v = AppInfo.versionTuple
        return ExploitSupportPolicy.isSupported(major: v.major, minor: v.minor, patch: v.patch, build: AppInfo.osBuild)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    NavigationLink {
                        NiKLocalFiles(directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0], title: t("Tệp đã nhập", "Imported Files"))
                    } label: {
                        homeCard(
                            title: t("Tệp đã nhập", "Imported Files"),
                            subtitle: t("Tài liệu và tệp đã nhập vào ứng dụng", "Documents imported into NiKSign"),
                            icon: "tray.and.arrow.down.fill",
                            color: .blue
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NiKLocalFiles(directory: NiKLibrary.root, title: t("Thư viện IPA", "IPA Library"))
                    } label: {
                        homeCard(
                            title: t("Thư viện IPA", "IPA Library"),
                            subtitle: t("Kho lưu trữ gói IPA cục bộ", "Local IPA storage"),
                            icon: "shippingbox.fill",
                            color: .orange
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        NiKSystemFiles(directory: URL(fileURLWithPath: "/", isDirectory: true))
                    } label: {
                        homeCard(
                            title: t("Tệp hệ thống · Chỉ đọc", "System Files · Read Only"),
                            subtitle: t("Duyệt hệ thống tệp ở chế độ chỉ đọc", "Read-only system file browser"),
                            icon: "internaldrive.fill",
                            color: .purple
                        )
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        AppDataBrowserView(tabSession: $session)
                    } label: {
                        homeCard(
                            title: t("Dữ liệu ứng dụng đã cài", "Installed App Data"),
                            subtitle: t("Quản lý và xem dữ liệu ứng dụng", "Browse application data"),
                            icon: "app.badge.fill",
                            color: .green
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(mode == "sign" || !supported)
                    .opacity((mode == "sign" || !supported) ? 0.45 : 1)

                    if mode == "sign" {
                        Text(t("Bật chế độ 3105 hoặc Cả hai trong Cài đặt để dùng trình duyệt dữ liệu ứng dụng.", "Enable 3105 or Both in Settings to browse application data."))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                    if !supported {
                        Text(t("Không hỗ trợ trên iOS", "Unsupported on iOS") + " \(AppInfo.osVersion) (\(AppInfo.osBuild)).")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 100)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle(t("Tệp", "Files"))
        }
    }

    private func homeCard(title: String, subtitle: String, icon: String, color: Color) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(color.opacity(0.18))
                    .frame(width: 40, height: 40)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
    }
}

struct NiKSystemFiles: View {
    let directory: URL
    @State private var entries: [URL] = []
    @State private var message = ""
    @State private var query = ""
    @State private var showHidden = false
    @State private var accessHandle: Int64 = -1
    @State private var preview: NiKPreviewDocument?

    private var filtered: [URL] {
        query.isEmpty ? entries : entries.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Tìm tệp", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule()
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                )
                .padding(.bottom, 8)

                Text(directory.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 6)

                if !message.isEmpty {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        )
                        .padding(.bottom, 6)
                }

                Toggle("Hiện tệp ẩn", isOn: $showHidden)
                    .padding(.horizontal, 12)
                    .onChange(of: showHidden) { _, _ in reload() }

                ForEach(filtered, id: \.self) { url in
                    let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                    if isDir {
                        NavigationLink {
                            NiKSystemFiles(directory: url)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 18))
                                    .foregroundStyle(.blue)
                                    .frame(width: 30)
                                Text(url.lastPathComponent)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(NiKLCSignRowButtonStyle())
                    } else {
                        HStack(spacing: 8) {
                            Button {
                                preview = NiKPreviewDocument(url: url)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "doc.fill")
                                        .font(.system(size: 18))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 30)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(url.lastPathComponent)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text(metadataText(for: url))
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(NiKLCSignRowButtonStyle())

                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 34, height: 34)
                                    .background(.ultraThinMaterial, in: Circle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .padding(.bottom, 100)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(directory.path == "/" ? "Tệp hệ thống" : directory.lastPathComponent)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.primary)
                        .frame(width: 34, height: 34)
                        .background(.ultraThinMaterial, in: Circle())
                        .overlay(
                            Circle()
                                .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .refreshable { reload() }
        .onAppear { reload() }
        .onDisappear { NiKWorseQueryAccess.release(accessHandle); accessHandle = -1 }
        .sheet(item: $preview) { NiKQuickLook(url: $0.url) }
    }

    private func metadataText(for url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let size = ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
        if let date = values?.contentModificationDate {
            let formatted = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
            return "\(size) · \(formatted)"
        }
        return size
    }

    private func reload() {
        NiKWorseQueryAccess.release(accessHandle)
        accessHandle = NiKWorseQueryAccess.isApplicable ? NiKWorseQueryAccess.acquire(directory.path) : -1
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
                options: showHidden ? [] : [.skipsHiddenFiles]
            ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            message = entries.isEmpty ? "Không có mục nào hiển thị. Có thể thử bật Hiện tệp ẩn. Danh sách trống không xác nhận quyền truy cập hệ thống." : ""
        } catch {
            entries = []
            let detail = error as NSError
            message = "Không đọc được \(directory.path).\n\(error.localizedDescription)\n[\(detail.domain):\(detail.code)]\nỨng dụng có thể chưa có quyền ngoài sandbox. Ký IPA không tự cấp quyền đọc hệ thống; cần kiểm tra trạng thái truy cập 3105 trên thiết bị này."
        }
    }
}

private struct NiKLCSignRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(configuration.isPressed ? Color(uiColor: .secondarySystemGroupedBackground) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(configuration.isPressed ? Color.white.opacity(0.12) : Color.clear, lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct NiKPreviewDocument: Identifiable {
    let id = UUID()
    let url: URL
}

struct NiKQuickLook: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            NiKQuickLookController(url: url)
                .ignoresSafeArea(.container, edges: .bottom)
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Đóng") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

private struct NiKQuickLookController: UIViewControllerRepresentable {
    let url: URL
    func makeCoordinator() -> Coordinator { Coordinator(url: url) }
    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }
    func updateUIViewController(_ controller: QLPreviewController, context: Context) {}
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        init(url: URL) { self.url = url }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
            url as NSURL
        }
    }
}
