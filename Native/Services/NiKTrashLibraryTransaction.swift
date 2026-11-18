import Foundation

enum NiKTrashOperations {
    static func move(_ url: URL, item: NiKLibraryItem?, store: NiKTrashStore) async throws -> NiKTrashRecord {
        let operationID = UUID()
        return try await Task.detached {
            do { return try store.trash(url, libraryItem: item, operationID: operationID) }
            catch {
                let originalError = error
                do {
                    try store.recover()
                    if let record = store.history().first(where: { $0.id == operationID }), [.trashed, .trashedNeedsIndex].contains(record.state) { return record }
                } catch {}
                throw originalError
            }
        }.value
    }
}

/// Shared production/test orchestration; callbacks commit the actual library index.
@MainActor enum NiKTrashLibraryTransaction {
    struct RollbackFailure: LocalizedError {
        let original: Error
        let rollback: Error
        var errorDescription: String? { original.localizedDescription + "\nKhôi phục còn chờ trong Thùng rác: " + rollback.localizedDescription }
    }
    static func remove(_ item: NiKLibraryItem, source: URL, store: NiKTrashStore,
                       commitRemoval: (NiKLibraryItem) throws -> Void,
                       commitRestoration: (NiKLibraryItem) throws -> Void) async throws {
        let record = try await NiKTrashOperations.move(source, item: item, store: store)
        do {
            _ = try await Task.detached { try store.pendingLibraryRemoval(record.id) }.value
            try commitRemoval(item)
        } catch {
            let originalError = error
            do { try await restore(record.id, store: store, commitRestoration: commitRestoration) }
            catch { throw RollbackFailure(original: originalError, rollback: error) }
            throw originalError
        }
        try await Task.detached { try store.finishLibraryRemoval(record.id) }.value
    }
    static func restore(_ id: UUID, store: NiKTrashStore,
                        commitRestoration: (NiKLibraryItem) throws -> Void) async throws {
        let record = try await Task.detached {
            do { return try store.restore(id) }
            catch {
                let originalError = error
                do { try store.recover(); return try store.restoredRecord(id) }
                catch { throw originalError }
            }
        }.value
        if record.state == .restoredNeedsIndex, let snapshot = record.libraryItem {
            try commitRestoration(snapshot)
            try await Task.detached { try store.finishLibraryRestore(id) }.value
        }
    }
    static func finishPendingRemoval(_ id: UUID, store: NiKTrashStore,
                                     commitRemoval: (NiKLibraryItem) throws -> Void) async throws {
        let record = try await Task.detached { try store.pendingLibraryRemoval(id) }.value
        guard let snapshot = record.libraryItem else { throw NiKFileBrowserState.Failure(message: "Thiếu metadata thư viện.") }
        try commitRemoval(snapshot)
        try await Task.detached { try store.finishLibraryRemoval(id) }.value
    }
}
