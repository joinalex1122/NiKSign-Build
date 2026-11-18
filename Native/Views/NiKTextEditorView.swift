import SwiftUI

private struct NiKTextEditReview: Identifiable, Sendable {
    let id = UUID()
    let document: NiKEditableTextDocument
    let preview: NiKTextChangePreview
}

struct NiKTextEditorView: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var recovery = NiKRecoveryController.shared
    @AppStorage("nik.language") private var language = "vi"
    @State private var document: NiKEditableTextDocument?
    @State private var text = ""
    @State private var busy = false
    @State private var error: String?
    @State private var status = ""
    @State private var confirmDiscard = false
    @State private var review: NiKTextEditReview?
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    private var dirty: Bool { document.map { text != $0.text } ?? false }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 8) {
                TextEditor(text: $text).font(.system(.footnote, design: .monospaced))
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .disabled(busy || document == nil)
                if let error { Text(error).font(.footnote).foregroundStyle(.red).padding(.horizontal) }
                if !status.isEmpty { Text(status).font(.footnote).foregroundStyle(.secondary).padding(.horizontal) }
                Text(t("Lưu tạo backup trước khi ghi. JSON/plist phải hợp lệ; thay đổi bên ngoài không bị ghi đè.", "Saving creates a backup first. JSON/plist must be valid; external changes are not overwritten."))
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal).padding(.bottom, 8)
            }
            .navigationTitle(url.lastPathComponent).navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t("Đóng", "Close")) { if dirty { confirmDiscard = true } else { dismiss() } }.disabled(busy)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button(t("Xem thay đổi & Lưu", "Review & Save")) { prepareReview() }.disabled(!dirty || busy)
                        Button(t("Định dạng JSON/plist", "Format JSON/plist")) { format() }.disabled(document == nil || busy)
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
            .overlay { if busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        }
        .interactiveDismissDisabled(dirty || busy)
        .task { await load() }
        .confirmationDialog(t("Bỏ thay đổi chưa lưu?", "Discard Unsaved Changes?"), isPresented: $confirmDiscard) {
            Button(t("Bỏ thay đổi và đóng", "Discard and Close"), role: .destructive) { dismiss() }
            Button(t("Tiếp tục sửa", "Keep Editing"), role: .cancel) {}
        }
        .sheet(item: $review) { value in
            NiKTextReviewSheet(review: value, busy: busy, error: error, language: language,
                cancel: { if !busy { review = nil } }, save: { save(value) })
        }
    }
    private func load() async {
        guard document == nil, !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let snapshot = try await recovery.snapshot(url)
            let opened = try await Task.detached { try NiKEditableTextDocument.open(snapshot) }.value
            document = opened; text = opened.text
        } catch { self.error = error.localizedDescription }
    }
    private func format() {
        guard let document, !busy else { return }
        busy = true; error = nil
        let draft = text
        Task {
            defer { busy = false }
            do { text = try await Task.detached { try document.formatted(draft) }.value }
            catch { self.error = error.localizedDescription }
        }
    }
    private func prepareReview() {
        guard let document, !busy else { return }
        let draft = text
        busy = true; error = nil; status = ""
        Task {
            defer { busy = false }
            do {
                let value = try await Task.detached {
                    let data = try document.encoded(draft)
                    let updated = try NiKEditableTextDocument.open(.init(url: document.snapshot.url, data: data, digest: NiKFileDigest.sha256(data: data)))
                    return NiKTextEditReview(document: updated, preview: .compare(document.text, updated.text))
                }.value
                if value.document.snapshot.data == document.snapshot.data {
                    self.document = value.document; text = value.document.text
                    status = t("Nội dung không thay đổi; không tạo backup thừa.", "Contents are unchanged; no redundant backup was created.")
                } else { review = value }
            } catch { self.error = error.localizedDescription }
        }
    }
    private func save(_ value: NiKTextEditReview) {
        guard let document, !busy else { return }
        busy = true; error = nil
        Task {
            defer { busy = false }
            do {
                let snapshot = try await recovery.write(value.document.snapshot.data, snapshot: document.snapshot)
                self.document = .init(snapshot: snapshot, text: value.document.text, format: value.document.format)
                text = value.document.text; review = nil
                status = t("Đã lưu và giữ backup trong Cài đặt → Khôi phục tệp.", "Saved. A backup is available in Settings → File Recovery.")
            } catch { self.error = error.localizedDescription }
        }
    }
}

private struct NiKTextReviewSheet: View {
    let review: NiKTextEditReview
    let busy: Bool
    let error: String?
    let language: String
    let cancel: () -> Void
    let save: () -> Void
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    var body: some View {
        NavigationStack {
            List {
                if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                Section(t("Vùng nội dung trước khi sửa", "Previous Change Region")) {
                    ForEach(Array(review.preview.removed.enumerated()), id: \.offset) { _, line in
                        Text("− " + line).font(.system(.caption, design: .monospaced)).foregroundStyle(.red).textSelection(.enabled)
                    }
                }
                Section(t("Vùng nội dung sẽ lưu", "Change Region to Save")) {
                    ForEach(Array(review.preview.added.enumerated()), id: \.offset) { _, line in
                        Text("+ " + line).font(.system(.caption, design: .monospaced)).foregroundStyle(.green).textSelection(.enabled)
                    }
                }
                if review.preview.truncatedFile || review.preview.omittedLines > 0 {
                    Text(t("Bản xem trước đã lược bớt nội dung dài. Bản lưu vẫn là toàn bộ nội dung đã kiểm tra.", "Long preview content is truncated. Saving uses the complete validated contents.")).font(.caption).foregroundStyle(.secondary)
                }
                Text(t("Backup gốc được ghi và kiểm SHA-256 trước khi đổi tệp.", "The original backup is written and SHA-256 checked before changing the file.")).font(.caption)
            }
            .navigationTitle(t("Xem thay đổi", "Review Changes"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("Quay lại", "Back"), action: cancel).disabled(busy) }
                ToolbarItem(placement: .confirmationAction) { Button(t("Lưu", "Save"), action: save).disabled(busy) }
            }
        }.interactiveDismissDisabled(busy)
    }
}
