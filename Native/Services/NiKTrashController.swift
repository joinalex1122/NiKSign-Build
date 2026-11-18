import Foundation
import Combine

@MainActor final class NiKTrashController: ObservableObject {
    static let shared = NiKTrashController()
    @Published private(set) var records: [NiKTrashRecord] = []
    @Published private(set) var busy = false
    @Published private(set) var storageAvailable = false
    @Published var message: String?
    let recoveryIndexURL: URL
    private let opening: Task<NiKTrashStore, Error>
    init() {
        let fm = FileManager.default
        let documents = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let directory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("NiKSign/Trash")
        recoveryIndexURL = directory.appendingPathComponent("index.json")
        opening = Task.detached {
            try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
            return try NiKTrashStore(directory: directory, root: documents)
        }
    }
    func refresh() async {
        do {
            let store = try await opening.value
            records = try await Task.detached { try store.recover(); return store.history() }.value
            storageAvailable = true
        } catch { storageAvailable = false; message = error.localizedDescription }
    }
    func trash(_ url: URL) async throws {
        guard !busy else { throw NiKError("Thùng rác đang có thao tác khác.") }
        busy = true; defer { busy = false }
        let store = try await opening.value
        let lease = try NiKManagedFileAccess.reserve([url])
        defer { NiKFileMutationReservations.shared.release(lease) }
        do { _ = try await NiKTrashOperations.move(url, item: nil, store: store) }
        catch { await refresh(); throw error }
        await refresh()
    }
    func removeLibraryItem(_ item: NiKLibraryItem) async throws {
        guard !busy else { throw NiKError("Thùng rác đang có thao tác khác.") }
        busy = true; defer { busy = false }
        let store = try await opening.value
        let source = item.ipaURL
        let lease = try NiKManagedFileAccess.reserve([source], allowManagedLibrary: true)
        defer { NiKFileMutationReservations.shared.release(lease) }
        do {
            try await NiKTrashLibraryTransaction.remove(item, source: source, store: store,
                commitRemoval: { try NiKLibrary.shared.commitTrashRemoval($0) },
                commitRestoration: { try NiKLibrary.shared.commitTrashRestoration($0) })
        } catch { await refresh(); throw error }
        await refresh()
    }
    func restore(_ id: UUID) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let store = try await opening.value
            let target = try await Task.detached { try store.originalURL(id) }.value
            let libraryItem = records.first { $0.id == id }?.libraryItem
            let lease = try NiKManagedFileAccess.reserve([target], allowManagedLibrary: libraryItem != nil)
            defer { NiKFileMutationReservations.shared.release(lease) }
            try await NiKTrashLibraryTransaction.restore(id, store: store,
                commitRestoration: { try NiKLibrary.shared.commitTrashRestoration($0) })
        } catch { message = error.localizedDescription }
        await refresh()
    }
    func finishPendingRemoval(_ id: UUID) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let store = try await opening.value
            _ = try await Task.detached { try store.pendingLibraryRemoval(id) }.value
            let target = try await Task.detached { try store.originalURL(id) }.value
            let lease = try NiKManagedFileAccess.reserve([target], allowManagedLibrary: true)
            defer { NiKFileMutationReservations.shared.release(lease) }
            try await NiKTrashLibraryTransaction.finishPendingRemoval(id, store: store,
                commitRemoval: { try NiKLibrary.shared.commitTrashRemoval($0) })
        } catch { message = error.localizedDescription }
        await refresh()
    }
    func purge(_ id: UUID, confirmingPermanentDeletion: Bool) async {
        guard !busy, confirmingPermanentDeletion else { return }
        busy = true; defer { busy = false }
        do {
            let store = try await opening.value
            if let item = records.first(where: { $0.id == id })?.libraryItem, NiKLibrary.shared.items.contains(where: { $0.id == item.id }) {
                throw NiKError("Thư viện vẫn còn mục IPA này. Hãy khôi phục hoặc hoàn tất cập nhật thư viện trước khi xóa vĩnh viễn.")
            }
            let entry = try await Task.detached { try store.entryDirectory(id) }.value
            let lease = try NiKManagedFileAccess.reserve([entry], allowManagedLibrary: true)
            defer { NiKFileMutationReservations.shared.release(lease) }
            try await Task.detached { try store.purge(id, confirmingPermanentDeletion: true) }.value
        } catch { message = error.localizedDescription }
        await refresh()
    }
    func exportBackup(_ id: UUID) async throws -> (url: URL, directory: URL) {
        guard !busy else { throw NiKError("Thùng rác đang có thao tác khác.") }
        busy = true; defer { busy = false }
        let store = try await opening.value
        guard let record = records.first(where: { $0.id == id }), let name = record.original.components.last else { throw NiKError("Không tìm thấy mục.") }
        return try await Task.detached {
            let source = try store.backupForReview(id)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("NiKTrashExport-" + UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            do {
                let target = directory.appendingPathComponent(name)
                try FileManager.default.copyItem(at: source, to: target)
                return (target, directory)
            } catch { try? FileManager.default.removeItem(at: directory); throw error }
        }.value
    }
    func clearFinished() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let store = try await opening.value
            let ids = Set(records.filter { [.restored, .purged, .aborted].contains($0.state) }.map(\.id))
            try await Task.detached { try store.removeFinished(ids) }.value
        } catch { message = error.localizedDescription }
        await refresh()
    }
}
