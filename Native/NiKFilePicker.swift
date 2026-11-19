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
    @AppStorage("nik.language") private var language = "vi"
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
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

                    NavigationLink { NiKSignedAppsView() } label: {
                        homeCard(title: t("Ứng dụng đã ký", "Signed Applications"),
                                 subtitle: t("Cài đặt, chia sẻ và quản lý IPA đã ký", "Install, share and manage signed IPAs"),
                                 icon: "app.badge.checkmark", color: .cyan)
                    }.buttonStyle(.plain)

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
