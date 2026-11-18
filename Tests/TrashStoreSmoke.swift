import Foundation

@main struct TrashStoreSmoke {
    struct Injected: Error {}
    static func fails(_ action: () throws -> Void) {
        do { try action() } catch { return }
        fatalError("Expected trash operation failure")
    }
    static func check(_ value: @autoclosure () throws -> Bool) throws { let result = try value(); precondition(result) }
    static func main() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }
        func fixture(_ name: String) throws -> (URL, URL, URL) {
            let path = base.appendingPathComponent(name)
            let docs = path.appendingPathComponent("Documents"), trash = path.appendingPathComponent("Support/Trash")
            try fm.createDirectory(at: docs, withIntermediateDirectories: true)
            let file = docs.appendingPathComponent("Tài liệu.txt")
            try Data("original".utf8).write(to: file)
            return (docs, trash, file)
        }
        do {
            let (docs, directory, file) = try fixture("normal")
            let store = try NiKTrashStore(directory: directory, root: docs)
            let record = try store.trash(file)
            precondition(record.state == .trashed && record.bytes == 8 && !fm.fileExists(atPath: file.path))
            fails { try store.removeFinished([record.id]) }
            try check(try Data(contentsOf: store.backupURL(record.id)) == Data("original".utf8))
            try Data("new file".utf8).write(to: file)
            fails { _ = try store.restore(record.id) }
            try check(try Data(contentsOf: file) == Data("new file".utf8))
            let before = try Data(contentsOf: directory.appendingPathComponent("index.json"))
            fails { try store.purge(record.id, confirmingPermanentDeletion: false) }
            try check(try Data(contentsOf: directory.appendingPathComponent("index.json")) == before)
            try fm.removeItem(at: file)
            _ = try store.restore(record.id)
            try check(try Data(contentsOf: file) == Data("original".utf8))
            precondition(store.history()[0].state == .restored)
            let next = try store.trash(file)
            try Data("keep this".utf8).write(to: file)
            try store.purge(next.id, confirmingPermanentDeletion: true)
            try check(try Data(contentsOf: file) == Data("keep this".utf8))
            precondition(store.history().first { $0.id == next.id }?.state == .purged)
            try store.removeFinished([record.id, next.id])
            precondition(store.history().isEmpty)
            try check(try Data(contentsOf: file) == Data("keep this".utf8))
        }
        for (number, point) in [NiKTrashStore.Checkpoint.afterPrepare, .afterMove, .beforeFinalCommit].enumerated() {
            let (docs, directory, file) = try fixture("trash-failure-\(number)")
            let store = try NiKTrashStore(directory: directory, root: docs, failureInjector: { if $0 == point { throw Injected() } })
            fails { _ = try store.trash(file) }
            precondition(store.history()[0].state == .trashPrepared)
            let reopened = try NiKTrashStore(directory: directory, root: docs)
            let record = reopened.history()[0]
            if point == .afterPrepare {
                precondition(record.state == .aborted && fm.fileExists(atPath: file.path))
            } else {
                precondition(record.state == .trashed && !fm.fileExists(atPath: file.path))
                _ = try reopened.restore(record.id)
            }
            try check(try Data(contentsOf: file) == Data("original".utf8))
        }
        for (number, point) in [NiKTrashStore.Checkpoint.afterPrepare, .afterMove, .beforeFinalCommit].enumerated() {
            let (docs, directory, file) = try fixture("restore-failure-\(number)")
            var injecting = false
            let store = try NiKTrashStore(directory: directory, root: docs, failureInjector: { if injecting && $0 == point { throw Injected() } })
            let record = try store.trash(file)
            injecting = true
            fails { _ = try store.restore(record.id) }
            let reopened = try NiKTrashStore(directory: directory, root: docs)
            if point == .afterPrepare { precondition(reopened.history()[0].state == .trashed); _ = try reopened.restore(record.id) }
            else { precondition(reopened.history()[0].state == .restored) }
            try check(try Data(contentsOf: file) == Data("original".utf8))
        }
        do {
            let (docs, directory, file) = try fixture("purge-failure")
            var injecting = false
            let store = try NiKTrashStore(directory: directory, root: docs, failureInjector: { if injecting && $0 == .beforeFinalCommit { throw Injected() } })
            let record = try store.trash(file)
            injecting = true
            fails { try store.purge(record.id, confirmingPermanentDeletion: true) }
            let reopened = try NiKTrashStore(directory: directory, root: docs)
            precondition(reopened.history()[0].state == .purged && !fm.fileExists(atPath: file.path))
        }
        do {
            let (docs, directory, _) = try fixture("folder")
            let nested = docs.appendingPathComponent("Folder/Sub/file.txt")
            try fm.createDirectory(at: nested.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("nested".utf8).write(to: nested)
            let store = try NiKTrashStore(directory: directory, root: docs)
            let record = try store.trash(docs.appendingPathComponent("Folder"))
            precondition(record.bytes == 6 && record.identity.isDirectory)
            _ = try store.restore(record.id)
            try check(try Data(contentsOf: nested) == Data("nested".utf8))
            let fileRecord = try store.trash(nested)
            try fm.removeItem(at: docs.appendingPathComponent("Folder"))
            _ = try store.restore(fileRecord.id)
            try check(try Data(contentsOf: nested) == Data("nested".utf8))
            try fm.createSymbolicLink(at: docs.appendingPathComponent("alias"), withDestinationURL: nested)
            fails { _ = try store.trash(docs.appendingPathComponent("alias")) }
            fails { _ = try store.trash(docs) }
        }
        do {
            let (docs, directory, _) = try fixture("library")
            let library = docs.appendingPathComponent("IPALibrary")
            try fm.createDirectory(at: library, withIntermediateDirectories: false)
            let file = library.appendingPathComponent("app.ipa")
            try Data("IPA fixture".utf8).write(to: file)
            let item = NiKLibraryItem(title: "App", version: "1", bundleID: "com.example.app", filename: "app.ipa")
            let store = try NiKTrashStore(directory: directory, root: docs)
            fails { _ = try store.trash(file) }
            let record = try store.trash(file, libraryItem: item)
            let restored = try store.restore(record.id)
            precondition(restored.state == .restoredNeedsIndex && restored.libraryItem?.id == item.id)
            try store.finishLibraryRestore(record.id)
            precondition(store.history()[0].state == .restored)
        }
        do {
            let (docs, directory, file) = try fixture("index-failure")
            let store = try NiKTrashStore(directory: directory, root: docs)
            try fm.createDirectory(at: directory.appendingPathComponent("index.json"), withIntermediateDirectories: false)
            fails { _ = try store.trash(file) }
            precondition(fm.fileExists(atPath: file.path) && store.history().isEmpty)
        }
        do {
            let (docs, directory, file) = try fixture("corrupt")
            let store = try NiKTrashStore(directory: directory, root: docs)
            _ = try store.trash(file)
            let index = directory.appendingPathComponent("index.json")
            let data = Data("corrupt trash journal".utf8)
            try data.write(to: index, options: .atomic)
            fails { _ = try NiKTrashStore(directory: directory, root: docs) }
            fails { try store.purge(store.history()[0].id, confirmingPermanentDeletion: true) }
            try check(try Data(contentsOf: index) == data)
        }
        print("PASS: trash/restore/purge, no overwrite, journal-before-move, recovery at trash/restore/purge failure boundaries, nested folders/parents, symlink/root guards, pending library metadata and corrupt/stale index preservation")
    }
}
