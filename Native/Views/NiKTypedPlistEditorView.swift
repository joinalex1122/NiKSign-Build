import SwiftUI

struct NiKTypedPlistEditorView: View {
    let url: URL
    @StateObject private var editor: NiKPlistEditorController
    @StateObject private var temporaryFiles = NiKTemporaryFiles()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nik.language") private var language = "vi"
    @State private var discard = false
    @State private var request: NiKPlistEditRequest?
    @State private var review: NiKPlistReview?
    @State private var share: NiKShareItem?
    init(url: URL) { self.url = url; _editor = StateObject(wrappedValue: NiKPlistEditorController(url: url)) }
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    var body: some View {
        NavigationStack {
            Group {
                if editor.document != nil {
                    NiKPlistTreeLevel(editor: editor, path: [], name: url.lastPathComponent, request: $request)
                } else {
                    VStack(spacing: 12) {
                        if editor.busy { ProgressView() }
                        if let error = editor.error { Text(error).foregroundStyle(.red).font(.footnote) }
                    }.padding()
                }
            }
            .navigationTitle(url.lastPathComponent).navigationBarTitleDisplayMode(.inline)
            .overlay { if editor.busy { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
        }
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 12) {
                Button(t("Đóng", "Close")) { if editor.document?.isDirty == true { discard = true } else { dismiss() } }
                    .buttonStyle(.bordered).disabled(editor.busy)
                Menu {
                    Button(t("Hoàn tác bản nháp", "Undo Draft Edit")) { editor.undo() }.disabled(!editor.canUndo)
                    Button(t("Xuất bản nháp", "Export Draft")) { export() }.disabled(editor.busy || editor.document == nil)
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                Spacer()
                Button(t("Xem & Lưu", "Review & Save")) { prepareReview() }
                    .buttonStyle(.borderedProminent).disabled(editor.busy || editor.document?.isDirty != true)
            }.padding(.horizontal, 16).padding(.vertical, 10).background(.bar)
        }
        .task { await editor.load() }
        .interactiveDismissDisabled(editor.busy || editor.document?.isDirty == true)
        .confirmationDialog(t("Bỏ thay đổi chưa lưu?", "Discard Unsaved Changes?"), isPresented: $discard) {
            Button(t("Bỏ thay đổi và đóng", "Discard and Close"), role: .destructive) { dismiss() }
            Button(t("Tiếp tục sửa", "Keep Editing"), role: .cancel) {}
        }
        .sheet(item: $request) { value in
            NiKPlistValueSheet(request: value, language: language) { key, parsed in
                guard editor.apply(value, key: key, value: parsed) else { throw NiKError(editor.error ?? "Chưa áp dụng được thay đổi.") }
            }
        }
        .sheet(item: $review) { value in
            NiKPlistReviewSheet(editor: editor, review: value, language: language,
                close: { review = nil }, save: { Task { if await editor.save(value) { review = nil } } })
        }
        .sheet(item: $share) { NiKShareSheet(items: [$0.url]) }
    }
    private func prepareReview() {
        Task { do { review = try await editor.prepareReview() } catch { editor.error = error.localizedDescription } }
    }
    private func export() {
        Task {
            do { let result = try await editor.exportDraft(); temporaryFiles.retain(result.directory); share = NiKShareItem(url: result.url) }
            catch { editor.error = error.localizedDescription }
        }
    }
}

private struct NiKPlistTreeLevel: View {
    @ObservedObject var editor: NiKPlistEditorController
    let path: [NiKPlistPathPart]
    let name: String
    @Binding var request: NiKPlistEditRequest?
    @Environment(\.dismiss) private var dismiss
    @AppStorage("nik.language") private var language = "vi"
    @State private var page: NiKPlistNodePage?
    @State private var limit = 250
    @State private var loading = false
    @State private var error: String?
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    var body: some View {
        List {
            if let error { Text(error).font(.footnote).foregroundStyle(.red) }
            if let error = editor.error { Text(error).font(.footnote).foregroundStyle(.red) }
            if editor.saved { Text(t("Đã lưu, có backup trong Cài đặt → Khôi phục tệp.", "Saved. Backup is in Settings → File Recovery.")).font(.caption).foregroundStyle(.green) }
            if path.isEmpty, let document = editor.document {
                Picker(t("Định dạng lưu", "Save Format"), selection: Binding(get: { document.format }, set: { editor.setFormat($0) })) {
                    Text("XML").tag(NiKTypedPlistDocument.Format.xml)
                    Text(t("Nhị phân", "Binary")).tag(NiKTypedPlistDocument.Format.binary)
                }.disabled(editor.busy)
                Text(t("Sửa bản nháp, xem thay đổi rồi lưu; tối đa 20 lượt hoàn tác bản nháp. Đổi định dạng phải giữ nguyên kiểu và độ chính xác.", "Edit a draft, review, then save; up to 20 draft undo steps. Format conversion must preserve types and precision."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let page {
                Section {
                    switch page.value {
                    case .dictionary:
                        Button(t("Thêm khóa", "Add Key")) { request = editor.request(.insert(path), expected: page.revision) }
                    case .array:
                        Button(t("Thêm phần tử", "Append Element")) { request = editor.request(.append(path), expected: page.revision) }
                    default:
                        Button { request = editor.request(.replace(path), expected: page.revision) } label: {
                            valueLabel(name: name, value: page.value)
                        }
                    }
                    ForEach(page.entries) { entry in row(entry, page: page) }
                    if page.entries.count < page.total {
                        Button(t("Nạp thêm", "Load More") + " (\(page.entries.count)/\(page.total))") { limit = min(page.total, limit + 250) }
                    }
                }
                Button(t("Sửa giá trị / đổi kiểu nút này", "Edit Value / Change This Node's Type")) { request = editor.request(.replace(path), expected: page.revision) }
            }
            if loading { ProgressView() }
            if error != nil && !path.isEmpty { Button(t("Quay lại", "Back")) { dismiss() } }
        }
        .disabled(editor.busy)
        .navigationTitle(name).navigationBarTitleDisplayMode(.inline)
        .task(id: "\(editor.revision)-\(limit)") {
            loading = true
            defer { loading = false }
            do {
                let result = try await editor.page(path, limit: limit)
                try Task.checkCancellation()
                page = result; error = nil
            } catch is CancellationError {} catch { page = nil; self.error = error.localizedDescription }
        }
    }
    @ViewBuilder private func row(_ entry: NiKPlistNodeEntry, page: NiKPlistNodePage) -> some View {
        Group {
            switch entry.value {
            case .array, .dictionary:
                NavigationLink { NiKPlistTreeLevel(editor: editor, path: entry.path, name: entry.name, request: $request) } label: { valueLabel(name: entry.name, value: entry.value) }
            default:
                Button { request = editor.request(.replace(entry.path), expected: page.revision) } label: { valueLabel(name: entry.name, value: entry.value) }
            }
        }
        .contextMenu {
            Button(t("Sửa giá trị / kiểu", "Edit Value / Type")) { request = editor.request(.replace(entry.path), expected: page.revision) }
            if case .index(let index)? = entry.path.last {
                if index > 0 { Button(t("Lên một vị trí", "Move Up")) { editor.move(path, from: index, to: index - 1, expected: page.revision) } }
                if index + 1 < page.total { Button(t("Xuống một vị trí", "Move Down")) { editor.move(path, from: index, to: index + 1, expected: page.revision) } }
            }
            Button(t("Xóa nút", "Remove Node"), role: .destructive) { editor.remove(entry.path, expected: page.revision) }
        }
    }
    private func valueLabel(name: String, value: NiKPlistValue) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(name.isEmpty ? "\"\"" : name).font(.body.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
            Text(NiKPlistValueDraft.Kind(value).title(english: language == "en") + " · " + NiKPlistValueDraft.summary(value))
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NiKPlistValueSheet: View {
    let request: NiKPlistEditRequest
    let language: String
    let apply: (String, NiKPlistValue) throws -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: NiKPlistValueDraft
    @State private var key = ""
    @State private var error: String?
    @State private var discard = false
    init(request: NiKPlistEditRequest, language: String, apply: @escaping (String, NiKPlistValue) throws -> Void) {
        self.request = request; self.language = language; self.apply = apply
        _draft = State(initialValue: NiKPlistValueDraft(request.value))
    }
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    private var dirty: Bool { draft.hasChanges || !key.isEmpty }
    var body: some View {
        NavigationStack {
            Form {
                if case .insert = request.action { TextField(t("Khóa", "Key"), text: $key).textInputAutocapitalization(.never).autocorrectionDisabled() }
                Picker(t("Kiểu", "Type"), selection: Binding(get: { draft.kind }, set: { draft.select($0) })) {
                    ForEach(NiKPlistValueDraft.Kind.allCases, id: \.self) { Text($0.title(english: language == "en")).tag($0) }
                }
                switch draft.kind {
                case .bool: Toggle(t("Giá trị", "Value"), isOn: $draft.boolValue)
                case .array, .dictionary:
                    Text(t("Giữ cấu trúc cùng kiểu hiện có; chuyển kiểu tạo container rỗng. Mở cây để sửa từng phần tử.", "An existing container of this type is preserved; changing type creates an empty container. Open the tree to edit its children.")).font(.footnote)
                case .string, .data:
                    TextEditor(text: $draft.text).font(.system(.footnote, design: .monospaced)).frame(minHeight: 180)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    if draft.kind == .data { Text(t("Nhập Base64; chỉ bỏ qua khoảng trắng, ký tự sai bị từ chối.", "Enter Base64; only whitespace is ignored. Invalid characters are rejected.")).font(.caption) }
                case .date:
                    TextField(t("Số giây từ 01/01/2001 UTC", "Seconds since 2001-01-01 UTC"), text: $draft.text)
                        .keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                    Text(t("Dùng mốc 2001 của plist để giữ cả phần lẻ rất nhỏ; không phải giây Unix từ 1970.", "Uses the plist's 2001 reference epoch to preserve very small fractions; this is not Unix time since 1970.")).font(.caption)
                default:
                    TextField(t("Giá trị số", "Numeric Value"), text: $draft.text)
                        .keyboardType(.numbersAndPunctuation).textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                if let error { Text(error).font(.footnote).foregroundStyle(.red) }
                Text(t("Áp dụng chỉ sửa bản nháp. Bạn còn xem diff và xác nhận lưu; thay kiểu sẽ thay toàn bộ giá trị nút.", "Apply changes the draft only. Review and confirm saving afterwards; changing type replaces the node's complete value."))
                    .font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle(t("Giá trị có kiểu", "Typed Value"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("Hủy", "Cancel")) { if dirty { discard = true } else { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t("Áp dụng", "Apply")) {
                        do {
                            try apply(key, draft.parsed())
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }
                }
            }
        }
        .interactiveDismissDisabled(dirty)
        .confirmationDialog(t("Bỏ dữ liệu đang nhập?", "Discard This Input?"), isPresented: $discard) {
            Button(t("Bỏ và đóng", "Discard and Close"), role: .destructive) { dismiss() }
            Button(t("Tiếp tục sửa", "Keep Editing"), role: .cancel) {}
        }
    }
}

private struct NiKPlistReviewSheet: View {
    @ObservedObject var editor: NiKPlistEditorController
    let review: NiKPlistReview
    let language: String
    let close: () -> Void
    let save: () -> Void
    private func t(_ vi: String, _ en: String) -> String { language == "en" ? en : vi }
    var body: some View {
        NavigationStack {
            List {
                if let error = editor.error { Text(error).font(.footnote).foregroundStyle(.red) }
                LabeledContent(t("Định dạng", "Format"), value: review.previousFormat.rawValue + " → " + review.document.format.rawValue)
                LabeledContent(t("Thay đổi theo trường", "Field Changes"), value: String(review.diff.totalChanges))
                ForEach(Array(review.diff.preview.enumerated()), id: \.offset) { _, change in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(pathText(change.path)).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                        Text("− " + (change.before.map(NiKPlistValueDraft.summary) ?? "∅")).font(.caption).foregroundStyle(.red)
                        Text("+ " + (change.after.map(NiKPlistValueDraft.summary) ?? "∅")).font(.caption).foregroundStyle(.green)
                    }
                }
                if review.diff.totalChanges > review.diff.preview.count { Text(t("Đã lược bớt preview dài; bản lưu dùng toàn bộ dữ liệu đã kiểm tra.", "Long preview truncated; saving uses the complete validated data.")).font(.caption) }
                Text(t("Lưu tạo backup và kiểm SHA-256 để không ghi đè thay đổi bên ngoài.", "Saving creates a backup and checks SHA-256 to avoid overwriting external changes.")).font(.caption).foregroundStyle(.secondary)
            }
            .navigationTitle(t("Xem thay đổi", "Review Changes"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("Quay lại", "Back"), action: close).disabled(editor.busy) }
                ToolbarItem(placement: .confirmationAction) { Button(t("Lưu", "Save"), action: save).disabled(editor.busy) }
            }
        }.interactiveDismissDisabled(editor.busy)
    }
    private func pathText(_ parts: [NiKPlistPathPart]) -> String {
        parts.reduce("$") { text, part in
            switch part {
            case .key(let key): return text + "[" + String(decoding: key.utf8.prefix(256), as: UTF8.self).debugDescription + "]"
            case .index(let index): return text + "[\(index)]"
            }
        }
    }
}
