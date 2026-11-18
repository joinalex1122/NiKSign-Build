import Foundation

@main struct TrashLibraryTransactionSmoke {
    struct Injected: Error {}
    @MainActor static func fails(_ action: () async throws -> Void) async {
        do { try await action() } catch { return }
        fatalError("Expected transaction failure")
    }
    static func check(_ value: @autoclosure () throws -> Bool) throws { let result = try value(); precondition(result) }
    @MainActor static func main() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        func fixture(_ name: String, injector: ((NiKTrashStore.Checkpoint) throws -> Void)? = nil) throws -> (URL, NiKLibraryItem, NiKLibraryIndexStore, NiKTrashStore) {
            let path = base.appendingPathComponent(name), docs = path.appendingPathComponent("Documents")
            let library = docs.appendingPathComponent("IPALibrary")
            try fm.createDirectory(at: library, withIntermediateDirectories: true)
            let file = library.appendingPathComponent("app.ipa")
            try Data("original IPA".utf8).write(to: file)
            let item = NiKLibraryItem(title: "App", version: "1", bundleID: "com.example.app", filename: "app.ipa")
            let index = try NiKLibraryIndexStore(url: library.appendingPathComponent("library.json"))
            try index.commit([item])
            let trash = try NiKTrashStore(directory: path.appendingPathComponent("Support/Trash"), root: docs, failureInjector: injector)
            return (file, item, index, trash)
        }
        do {
            let (file, item, index, store) = try fixture("normal")
            try await NiKTrashLibraryTransaction.remove(item, source: file, store: store, commitRemoval: index.removeForTrash, commitRestoration: index.restoreFromTrash)
            precondition(index.items.isEmpty && !fm.fileExists(atPath: file.path) && store.history()[0].state == .trashed)
            try await NiKTrashLibraryTransaction.restore(store.history()[0].id, store: store, commitRestoration: index.restoreFromTrash)
            precondition(index.items == [item] && store.history()[0].state == .restored)
            try check(try Data(contentsOf: file) == Data("original IPA".utf8))
        }
        for commitBeforeError in [false, true] {
            let (file, item, index, store) = try fixture("index-error-\(commitBeforeError)")
            await fails {
                try await NiKTrashLibraryTransaction.remove(item, source: file, store: store, commitRemoval: { snapshot in
                    if commitBeforeError { try index.removeForTrash(snapshot) }
                    throw Injected()
                }, commitRestoration: index.restoreFromTrash)
            }
            precondition(index.items == [item] && store.history()[0].state == .restored)
            try check(try Data(contentsOf: file) == Data("original IPA".utf8))
        }
        do {
            let (file, item, index, store) = try fixture("rollback-index-error")
            await fails {
                try await NiKTrashLibraryTransaction.remove(item, source: file, store: store,
                    commitRemoval: { _ in throw Injected() }, commitRestoration: { _ in throw Injected() })
            }
            precondition(fm.fileExists(atPath: file.path) && store.history()[0].state == .restoredNeedsIndex)
            try await NiKTrashLibraryTransaction.restore(store.history()[0].id, store: store, commitRestoration: index.restoreFromTrash)
            precondition(store.history()[0].state == .restored && index.items == [item])
        }
        do {
            var injecting = false
            let (file, item, index, store) = try fixture("final-marker-error", injector: { if injecting && $0 == .beforeFinalCommit { throw Injected() } })
            await fails {
                try await NiKTrashLibraryTransaction.remove(item, source: file, store: store,
                    commitRemoval: { try index.removeForTrash($0); injecting = true }, commitRestoration: index.restoreFromTrash)
            }
            precondition(index.items.isEmpty && store.history()[0].state == .trashedNeedsIndex)
            let reopened = try NiKTrashStore(directory: store.directory, root: store.root)
            try await NiKTrashLibraryTransaction.finishPendingRemoval(reopened.history()[0].id, store: reopened, commitRemoval: index.removeForTrash)
            precondition(reopened.history()[0].state == .trashed)
        }
        do {
            let (file, item, index, store) = try fixture("newer-options")
            var updated = item; updated.options.customDisplayName = "Newer configuration"
            await fails {
                try await NiKTrashLibraryTransaction.remove(item, source: file, store: store,
                    commitRemoval: { snapshot in try index.commit([updated]); try index.removeForTrash(snapshot) },
                    commitRestoration: index.restoreFromTrash)
            }
            precondition(index.items == [updated] && store.history()[0].state == .restored)
            try check(try Data(contentsOf: file) == Data("original IPA".utf8))
        }
        do {
            let (file, item, index, store) = try fixture("foreign-index")
            try await NiKTrashLibraryTransaction.remove(item, source: file, store: store, commitRemoval: index.removeForTrash, commitRestoration: index.restoreFromTrash)
            var foreign = item; foreign.filename = "other.ipa"
            try index.commit([foreign])
            await fails { try await NiKTrashLibraryTransaction.restore(store.history()[0].id, store: store, commitRestoration: index.restoreFromTrash) }
            precondition(index.items == [foreign] && store.history()[0].state == .restoredNeedsIndex && fm.fileExists(atPath: file.path))
        }
        do {
            let (file, item, index, store) = try fixture("prepared-library")
            let record = try store.trash(file, libraryItem: item)
            precondition(record.state == .trashedNeedsIndex && index.items == [item])
            let reopened = try NiKTrashStore(directory: store.directory, root: store.root)
            try await NiKTrashLibraryTransaction.finishPendingRemoval(record.id, store: reopened, commitRemoval: index.removeForTrash)
            precondition(index.items.isEmpty && reopened.history()[0].state == .trashed)
        }
        do {
            let (file, item, _, store) = try fixture("recover-final-move", injector: { if $0 == .afterMove { throw Injected() } })
            let record = try await NiKTrashOperations.move(file, item: item, store: store)
            precondition(record.state == .trashedNeedsIndex && !fm.fileExists(atPath: file.path))
        }
        print("PASS: real trash/library transaction orchestration, removal/restore, metadata failure rollback, pending/retry markers, preserved newer options and foreign index conflicts")
    }
}
