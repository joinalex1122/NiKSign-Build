import Foundation
import Combine

@MainActor final class NiKRecoveryController: ObservableObject {
    static let shared = NiKRecoveryController()
    @Published private(set) var records: [NiKFileRecoveryRecord] = []
    @Published private(set) var busy = false
    @Published var message: String?
    private let opening: Task<NiKFileRecoveryStore, Error>

    init() {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let workspaces = support.appendingPathComponent("NiKSign/Workspaces")
        let recovery = support.appendingPathComponent("NiKSign/Recovery")
        let index = NiKLibrary.root.appendingPathComponent("library.json")
        opening = Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: workspaces, withIntermediateDirectories: true)
            return try NiKFileRecoveryStore(directory: recovery, editableRoots: [documents, workspaces], deniedTargets: [index])
        }
    }
    func refresh() async {
        do {
            let store = try await opening.value
            records = await Task.detached { store.history() }.value
        } catch { message = error.localizedDescription }
    }
    func snapshot(_ url: URL) async throws -> NiKEditableFileSnapshot {
        let store = try await opening.value
        return try await Task.detached { try store.snapshot(url) }.value
    }
    func write(_ data: Data, snapshot: NiKEditableFileSnapshot) async throws -> NiKEditableFileSnapshot {
        guard !busy else { throw NiKError("Đang xử lý một thao tác khôi phục/chỉnh sửa khác.") }
        busy = true
        defer { busy = false }
        let store = try await opening.value
        let record = try await Task.detached { try store.write(data, to: snapshot.url, expectedDigest: snapshot.digest) }.value
        await refresh()
        return .init(url: snapshot.url, data: data, digest: record.replacementDigest)
    }
    func restore(_ id: UUID) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let store = try await opening.value
            _ = try await Task.detached { try store.restore(id) }.value
        } catch { message = error.localizedDescription }
        await refresh()
    }
    func exportBackup(_ id: UUID) async throws -> URL {
        let store = try await opening.value
        return try await Task.detached { try store.backupURL(id) }.value
    }
    func discard(_ id: UUID) async {
        guard !busy else { return }
        busy = true
        defer { busy = false }
        do {
            let store = try await opening.value
            try await Task.detached { try store.discardBackup(id, confirmingLossOfRestore: true) }.value
        } catch { message = error.localizedDescription }
        await refresh()
    }
}
