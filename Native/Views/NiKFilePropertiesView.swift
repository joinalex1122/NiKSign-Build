import SwiftUI

struct NiKFilePropertiesView: View {
    let url: URL
    let root: URL
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nik.language") private var language = "vi"
    @State private var properties: NiKFileProperties?
    @State private var busy = false
    @State private var error: String?
    @State private var work: Task<Void, Never>?
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    var body: some View {
        NavigationStack {
            List {
                if let properties {
                    LabeledContent(t("Tên", "Name"), value: properties.name)
                    LabeledContent(t("Loại", "Type"), value: properties.isDirectory ? t("Thư mục", "Folder") : url.pathExtension.uppercased())
                    if let size = properties.size { LabeledContent(t("Dung lượng", "Size"), value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file)) }
                    if let date = properties.createdAt { LabeledContent(t("Tạo", "Created")) { Text(date, style: .date) } }
                    if let date = properties.modifiedAt { LabeledContent(t("Sửa", "Modified")) { Text(date, style: .date) } }
                    if let permissions = properties.permissions { LabeledContent("POSIX", value: String(format: "%03o", permissions)) }
                    if let digest = properties.sha256 {
                        Section("SHA-256") { Text(digest).font(.system(.caption, design: .monospaced)).textSelection(.enabled) }
                    }
                    if !properties.isDirectory {
                        Button(t("Tính lại SHA-256", "Calculate SHA-256")) { load(hash: true) }.disabled(busy)
                    }
                }
                if busy { ProgressView() }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Text(t("SHA-256 chỉ mô tả nội dung tệp, không xác minh nhà phát hành hay quyền cài đặt.", "SHA-256 identifies file contents; it does not verify the publisher or installation permissions."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle(t("Thuộc tính", "Properties"))
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("Đóng", "Close")) { work?.cancel(); dismiss() } } }
        }
        .task { if properties == nil { load(hash: false) } }
        .onDisappear { work?.cancel() }
    }
    private func load(hash: Bool) {
        guard !busy else { return }
        busy = true; error = nil
        let target = url, root = root
        work = Task {
            defer { busy = false; work = nil }
            let worker = Task.detached { try NiKFileProperties.inspect(target, root: root, hash: hash) }
            do {
                let result = try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
                try Task.checkCancellation()
                properties = result
            } catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
    }
}
