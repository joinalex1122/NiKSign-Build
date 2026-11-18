import Foundation
import Combine

struct NiKPlistEditRequest: Identifiable, Sendable {
    enum Action: Sendable { case replace([NiKPlistPathPart]), insert([NiKPlistPathPart]), append([NiKPlistPathPart]) }
    let id = UUID()
    let action: Action
    let revision: Int
    let value: NiKPlistValue?
}
struct NiKPlistReview: Identifiable, Sendable {
    let id = UUID()
    let revision: Int
    let document: NiKTypedPlistDocument
    let diff: NiKPlistSemanticDiff
    let previousFormat: NiKTypedPlistDocument.Format
}
struct NiKPlistNodeEntry: Identifiable, Sendable {
    let path: [NiKPlistPathPart]
    let name: String
    let value: NiKPlistValue
    var id: [NiKPlistPathPart] { path }
}
struct NiKPlistNodePage: Sendable {
    let revision: Int
    let value: NiKPlistValue
    let entries: [NiKPlistNodeEntry]
    let total: Int
}

@MainActor final class NiKPlistEditorController: ObservableObject {
    let url: URL
    @Published private(set) var document: NiKTypedPlistDocument?
    @Published private(set) var revision = 0
    @Published private(set) var busy = false
    @Published var error: String?
    @Published private(set) var saved = false
    private var undoStack: [NiKTypedPlistDocument] = []
    var canUndo: Bool { !undoStack.isEmpty && !busy }
    init(url: URL) { self.url = url }
    func load() async {
        guard document == nil, !busy else { return }
        busy = true; defer { busy = false }
        do {
            let snapshot = try await NiKRecoveryController.shared.snapshot(url)
            document = try await Task.detached { try NiKTypedPlistDocument(snapshot: snapshot) }.value
            revision += 1
        } catch { self.error = error.localizedDescription }
    }
    private func mutate(expected: Int? = nil, _ action: (inout NiKTypedPlistDocument) throws -> Void) -> Bool {
        guard !busy, let current = document else { return false }
        do {
            if let expected, expected != revision { throw NiKError("Cây plist đã đổi; hãy đợi nạp lại trước khi thao tác.") }
            var updated = current
            try action(&updated)
            guard updated.format != current.format || !NiKTypedPlistDocument.same(updated.value, current.value) else { error = nil; return true }
            undoStack.append(current); if undoStack.count > 20 { undoStack.removeFirst() }
            document = updated; revision += 1; error = nil; saved = false
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func setFormat(_ format: NiKTypedPlistDocument.Format) { _ = mutate { $0.format = format } }
    func undo() {
        guard !busy, let previous = undoStack.popLast() else { return }
        document = previous; revision += 1; error = nil; saved = false
    }
    func request(_ action: NiKPlistEditRequest.Action, expected: Int) -> NiKPlistEditRequest? {
        guard !busy, let document else { return nil }
        do {
            guard expected == revision else { throw NiKError("Cây đã đổi; hãy đợi nạp lại.") }
            let value: NiKPlistValue?
            switch action { case .replace(let path): value = try document.node(at: path); case .insert, .append: value = nil }
            return .init(action: action, revision: revision, value: value)
        } catch { self.error = error.localizedDescription; return nil }
    }
    func apply(_ request: NiKPlistEditRequest, key: String, value: NiKPlistValue) -> Bool {
        mutate(expected: request.revision) { document in
            switch request.action {
            case .replace(let path): try document.replace(at: path, with: value)
            case .insert(let path): try document.insert(key: key, value: value, into: path)
            case .append(let path): try document.append(value, to: path)
            }
        }
    }
    func remove(_ path: [NiKPlistPathPart], expected: Int) { _ = mutate(expected: expected) { try $0.remove(at: path) } }
    func move(_ parent: [NiKPlistPathPart], from: Int, to: Int, expected: Int) { _ = mutate(expected: expected) { try $0.moveArrayElement(at: parent, from: from, to: to) } }
    func page(_ path: [NiKPlistPathPart], limit: Int) async throws -> NiKPlistNodePage {
        guard let document else { throw NiKError("Chưa nạp plist.") }
        let currentRevision = revision, cap = max(0, min(100_000, limit))
        let worker = Task.detached {
            try Task.checkCancellation()
            let value = try document.node(at: path)
            let entries: [NiKPlistNodeEntry], total: Int
            switch value {
            case .dictionary(let values):
                total = values.count
                let keys = try values.keys.sorted { first, second in try Task.checkCancellation(); return first < second }
                entries = try keys.prefix(cap).map { key in
                    try Task.checkCancellation()
                    return .init(path: path + [.key(key)], name: String(decoding: key.utf8.prefix(256), as: UTF8.self), value: values[key]!)
                }
            case .array(let values):
                total = values.count
                entries = try values.prefix(cap).enumerated().map { index, value in
                    try Task.checkCancellation()
                    return .init(path: path + [.index(index)], name: "[\(index)]", value: value)
                }
            default: total = 0; entries = []
            }
            return NiKPlistNodePage(revision: currentRevision, value: value, entries: entries, total: total)
        }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
    func prepareReview() async throws -> NiKPlistReview? {
        guard !busy, let document, document.isDirty else { return nil }
        busy = true; defer { busy = false }
        let currentRevision = revision
        return try await Task.detached {
            let data = try document.encoded()
            if data == document.snapshot.data { return nil }
            let snapshot = NiKEditableFileSnapshot(url: document.snapshot.url, data: data, digest: try NiKFileDigest.sha256(data: data))
            return NiKPlistReview(revision: currentRevision, document: try NiKTypedPlistDocument(snapshot: snapshot), diff: document.diff(), previousFormat: document.originalFormat)
        }.value
    }
    func save(_ review: NiKPlistReview) async -> Bool {
        guard !busy, let document, review.revision == revision else { return false }
        busy = true; defer { busy = false }
        do {
            let saved = try await NiKRecoveryController.shared.write(review.document.snapshot.data, snapshot: document.snapshot)
            guard saved.digest == review.document.snapshot.digest else { throw NiKError("Digest sau lưu chưa khớp; hãy kiểm tra lịch sử khôi phục.") }
            self.document = review.document; undoStack.removeAll(); revision += 1
            error = nil; self.saved = true
            return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func exportDraft() async throws -> (url: URL, directory: URL) {
        guard !busy, let document else { throw NiKError("Chưa nạp plist hoặc đang xử lý.") }
        busy = true; defer { busy = false }
        return try await Task.detached {
            let data = try document.encoded()
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NiKPlistDraft-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            let target = directory.appendingPathComponent(document.snapshot.url.lastPathComponent)
            do { try data.write(to: target, options: .atomic); return (target, directory) }
            catch { try? FileManager.default.removeItem(at: directory); throw error }
        }.value
    }
}
