import SwiftUI
import UniformTypeIdentifiers
import QuickLook

/// Copy mode asks File Providers to download/materialize the document before returning it.
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
    @State private var session = FilesTabSession()
    private var supported: Bool {
        let v = AppInfo.versionTuple
        return ExploitSupportPolicy.isSupported(major: v.major, minor: v.minor, patch: v.patch, build: AppInfo.osBuild)
    }
    var body: some View {
        List {
            Section("Trong NiKSign") {
                NavigationLink("Tệp đã nhập") { NiKLocalFiles(directory: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]) }
                NavigationLink("Thư viện IPA") { NiKLocalFiles(directory: NiKLibrary.root) }
            }
            Section("Trên thiết bị") {
                NavigationLink("Tệp hệ thống · Chỉ đọc") { NiKSystemFiles(directory: URL(fileURLWithPath: "/", isDirectory: true)) }
                NavigationLink("Dữ liệu ứng dụng đã cài") { AppDataBrowserView(tabSession: $session) }
                    .disabled(mode == "sign" || !supported)
                if mode == "sign" { Text("Bật chế độ 3105 hoặc Cả hai trong Cài đặt để dùng trình duyệt dữ liệu ứng dụng.") }
                if !supported {
                    Text("iOS \(AppInfo.osVersion) (\(AppInfo.osBuild)) chưa được bộ 3105 hiện tại hỗ trợ. Dữ liệu riêng của ứng dụng khác vẫn bị iOS giới hạn.")
                }
                Text("Trình duyệt hệ thống chỉ hiển thị đường dẫn được iOS cho phép đọc; không tự cấp thêm quyền.")
            }.font(.subheadline)
        }.navigationTitle("Tệp")
    }
}

struct NiKSystemFiles: View {
    let directory: URL
    @State private var entries: [URL] = []
    @State private var preview: NiKPreviewDocument?
    @State private var message = ""
    @State private var query = ""

    private var filteredEntries: [URL] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return entries }
        return entries.filter { $0.lastPathComponent.localizedCaseInsensitiveContains(trimmed) }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm dd/MM/yy"
        return formatter
    }()

    var body: some View {
        List {
            Section { Text(directory.path).font(.caption.monospaced()).textSelection(.enabled) }
            if !message.isEmpty { Section("Không đọc được thư mục") { Text(message); Text("iOS có thể giới hạn quyền truy cập đường dẫn này.") } }
            ForEach(filteredEntries, id: \.self) { url in
                let isDirectory = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if isDirectory {
                    NavigationLink {
                        NiKSystemFiles(directory: url)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(url.lastPathComponent)
                                Text(metadataText(for: url, isDirectory: true))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "folder")
                        }
                    }
                } else {
                    HStack {
                        Button {
                            preview = NiKPreviewDocument(url: url)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(url.lastPathComponent)
                                    Text(metadataText(for: url, isDirectory: false))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "doc")
                            }
                        }
                        Spacer()
                        ShareLink(item: url) {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .buttonStyle(.borderless)
        .navigationTitle(directory.lastPathComponent.isEmpty ? "/" : directory.lastPathComponent)
        .searchable(text: $query, prompt: "Tìm tệp")
        .onAppear { reload() }
        .refreshable { reload() }
        .sheet(item: $preview) { NiKQuickLook(url: $0.url) }
    }

    private func metadataText(for url: URL, isDirectory: Bool) -> String {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey])
        let dateText = values?.contentModificationDate.map { Self.dateFormatter.string(from: $0) } ?? "--:-- --/--/--"
        if isDirectory {
            return "\(dateText) • Thư mục"
        }
        if let fileSize = values?.fileSize {
            let sizeText = ByteCountFormatter.string(fromByteCount: Int64(fileSize), countStyle: .file)
            return "\(dateText) • \(sizeText)"
        }
        return dateText
    }

    private func reload() {
        do {
            entries = try FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey]
            )
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            message = ""
        } catch {
            entries = []
            message = error.localizedDescription
        }
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
