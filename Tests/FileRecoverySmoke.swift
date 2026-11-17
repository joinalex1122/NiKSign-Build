import Foundation

@main struct FileRecoverySmoke {
    enum InjectedFailure: Error { case disk }
    static func check(_ condition: @autoclosure () throws -> Bool) throws {
        let result = try condition()
        precondition(result)
    }
    static func expectFailure(_ action: () throws -> Void) {
        do { try action() } catch { return }
        fatalError("Expected failure")
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let docs = root.appendingPathComponent("Documents")
        let backups = root.appendingPathComponent("Recovery")
        try fm.createDirectory(at: docs, withIntermediateDirectories: true)
        let file = docs.appendingPathComponent("sample.txt")
        let original = Data("original".utf8), edited = Data("edited".utf8)
        try original.write(to: file)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        try check(try NiKFileDigest.sha256(data: Data("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let store = try NiKFileRecoveryStore(directory: backups, editableRoots: [docs])
        let snapshot = try store.snapshot(file)
        let record = try store.write(edited, to: file, expectedDigest: snapshot.digest)
        precondition(record.state == .committed)
        try check(try Data(contentsOf: file) == edited)
        try check((try fm.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue == 0o600)
        let backup = try store.backupURL(record.id)
        try check(try Data(contentsOf: backup) == original)
        expectFailure { _ = try store.write(Data("stale".utf8), to: file, expectedDigest: snapshot.digest) }
        try check(try Data(contentsOf: file) == edited)
        let newer = Data("newer external edit".utf8)
        try newer.write(to: file)
        expectFailure { _ = try store.restore(record.id) }
        precondition(store.history().first?.state == .restoreFailed)
        try check(try Data(contentsOf: file) == newer)
        let savedNewer = docs.appendingPathComponent("saved-newer.txt")
        try fm.moveItem(at: file, to: savedNewer)
        _ = try store.restore(record.id)
        try check(try Data(contentsOf: file) == original)
        try check(try Data(contentsOf: savedNewer) == newer)
        precondition(store.history().first?.state == .restored)
        for (name, checkpoint) in [("backup", NiKFileRecoveryStore.Checkpoint.afterBackupPersisted), ("write", .afterTargetWrite), ("commit", .beforeFinalJournalCommit)] {
            let recovery = root.appendingPathComponent(name)
            let faultStore = try NiKFileRecoveryStore(directory: recovery, editableRoots: [docs], failureInjector: { point in
                if point == checkpoint { throw InjectedFailure.disk }
            })
            let source = try faultStore.snapshot(file)
            expectFailure { _ = try faultStore.write(edited, to: file, expectedDigest: source.digest) }
            try check(try Data(contentsOf: file) == original)
            precondition(faultStore.history().first?.state == .aborted)
            try check(try Data(contentsOf: faultStore.backupURL(faultStore.history()[0].id)) == original)
        }
        let blocked = try NiKFileRecoveryStore(directory: root.appendingPathComponent("blocked"), editableRoots: [docs])
        try fm.createDirectory(at: root.appendingPathComponent("blocked/index.json"), withIntermediateDirectories: false)
        expectFailure { _ = try blocked.write(edited, to: file, expectedDigest: snapshot.digest) }
        try check(try Data(contentsOf: file) == original)
        precondition(blocked.history().isEmpty)
        let outside = root.appendingPathComponent("outside.txt")
        try Data("outside".utf8).write(to: outside)
        expectFailure { _ = try store.snapshot(outside) }
        let link = docs.appendingPathComponent("link.txt")
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        expectFailure { _ = try store.snapshot(link) }
        let folderLink = docs.appendingPathComponent("folder-link")
        try fm.createSymbolicLink(at: folderLink, withDestinationURL: root)
        expectFailure { _ = try store.snapshot(folderLink.appendingPathComponent("outside.txt")) }
        let changed = try store.write(edited, to: file, expectedDigest: snapshot.digest)
        let changedBackup = try store.backupURL(changed.id)
        try Data("tampered".utf8).write(to: changedBackup)
        expectFailure { _ = try store.restore(changed.id) }
        try check(try Data(contentsOf: file) == edited)
        expectFailure { _ = try store.backupURL(changed.id) }
        // Simulate interruption after the target was written but before its committed journal update.
        let index = backups.appendingPathComponent("index.json")
        var object = try JSONSerialization.jsonObject(with: Data(contentsOf: index)) as! [String: Any]
        var records = object["records"] as! [[String: Any]]
        records[0]["state"] = "prepared"
        object["records"] = records
        try JSONSerialization.data(withJSONObject: object).write(to: index)
        // The first record's backup remains intact and its target has replacement bytes.
        let recovered = try NiKFileRecoveryStore(directory: backups, editableRoots: [docs])
        precondition(recovered.history()[0].state == .committed)
        let historyBefore = recovered.history().count
        expectFailure { try recovered.discardBackup(record.id, confirmingLossOfRestore: false) }
        precondition(recovered.history().count == historyBefore)
        let folder = backups.appendingPathComponent(record.id.uuidString)
        let pendingDiscard = backups.appendingPathComponent(".discard-" + record.id.uuidString)
        try fm.moveItem(at: folder, to: pendingDiscard)
        let afterInterruptedDiscard = try NiKFileRecoveryStore(directory: backups, editableRoots: [docs])
        precondition(fm.fileExists(atPath: folder.path))
        precondition(!fm.fileExists(atPath: pendingDiscard.path))
        try afterInterruptedDiscard.discardBackup(record.id, confirmingLossOfRestore: true)
        precondition(!fm.fileExists(atPath: folder.path))
        precondition(!afterInterruptedDiscard.history().contains { $0.id == record.id })
        try check(try Data(contentsOf: file) == edited)
        let protected = try NiKFileRecoveryStore(directory: root.appendingPathComponent("protected-recovery"), editableRoots: [docs], deniedTargets: [file])
        expectFailure { _ = try protected.snapshot(file) }
        try Data("corrupt journal".utf8).write(to: index)
        expectFailure { _ = try NiKFileRecoveryStore(directory: backups, editableRoots: [docs]) }
        try check(try String(contentsOf: index) == "corrupt journal")
        print("PASS: SHA256, snapshot/backup, stale edit rejection, restore conflict/retry, permissions, failures at three write boundaries, journal-before-write, root/symlink guards, corrupt backup/index and interrupted recovery")
    }
}
