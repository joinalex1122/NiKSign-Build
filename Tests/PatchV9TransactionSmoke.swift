import Foundation

@main
struct PatchV9TransactionSmoke {
    static let fm = FileManager.default
    static var passed = 0

    struct Fixture {
        let root: URL
        let backups: URL
        let a: URL
        let b: URL
        init() throws {
            root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
            backups = root.appendingPathComponent("backups")
            a = root.appendingPathComponent("A")
            b = root.appendingPathComponent("B")
            for url in [backups, a, b] { try fm.createDirectory(at: url, withIntermediateDirectories: true) }
        }
        func resolve(_ scope: NiKContainerScope, _ id: String) throws -> URL {
            if id == "app.test.a" { return a }
            if id == "app.test.b" { return b }
            throw NiKError("Unavailable")
        }
        func receipt(_ id: UUID) -> URL { backups.appendingPathComponent("\(id.uuidString).json") }
    }

    static func rule(_ id: String = "app.test.a", path: String = "config.txt", value: String = "patched") -> NiKWorkspaceV9Rule {
        NiKWorkspaceV9Rule(scope: .application, identifier: id, relativePath: path, mode: .replaceFile, payloadData: Data(value.utf8))
    }
    static func require(_ ok: Bool, _ message: String) throws {
        if !ok { throw NiKError(message) }
    }
    static func expectFailure(_ action: () throws -> Void) throws {
        do { try action() } catch { return }
        throw NiKError("Expected failure")
    }
    static func contents(_ url: URL) throws -> String { try String(contentsOf: url, encoding: .utf8) }
    static func test(_ name: String, _ action: (Fixture) throws -> Void) throws {
        let f = try Fixture()
        defer { try? fm.removeItem(at: f.root) }
        try action(f)
        passed += 1
        print("PASS: \(name)")
    }

    static func main() throws {
        try test("original survives repeated apply; new files are removed on restore") { f in
            let file = f.a.appendingPathComponent("config.txt")
            try Data("original".utf8).write(to: file)
            let project = NiKWorkspaceV9Project(name: "Repeat", rules: [rule(), rule(path: "new.txt")])
            _ = try NiKWorkspaceV9Service.apply(project: project, userValues: [:], customContainerResolver: f.resolve, backupDirectory: f.backups)
            let journal = try JSONDecoder().decode(NiKWorkspaceV9BackupReceipt.self, from: Data(contentsOf: f.receipt(project.id)))
            try require(journal.entries.first?.originalBytes == Data("original".utf8), "Missing original journal")
            try expectFailure { _ = try NiKWorkspaceV9Service.apply(project: project, userValues: [:], customContainerResolver: f.resolve, backupDirectory: f.backups) }
            let restored = try NiKWorkspaceV9Service.restore(projectID: project.id, customContainerResolver: f.resolve, backupDirectory: f.backups)
            try require(restored == 2 && contents(file) == "original", "Restore lost original")
            try require(!fm.fileExists(atPath: f.a.appendingPathComponent("new.txt").path), "New file not removed")
            try require(!fm.fileExists(atPath: f.receipt(project.id).path), "Completed receipt retained")
        }
        try test("unavailable container retains only pending entries for retry") { f in
            for file in [f.a, f.b] { try Data("original".utf8).write(to: file.appendingPathComponent("config.txt")) }
            let project = NiKWorkspaceV9Project(name: "Partial", rules: [rule(), rule("app.test.b")])
            _ = try NiKWorkspaceV9Service.apply(project: project, userValues: [:], customContainerResolver: f.resolve, backupDirectory: f.backups)
            try expectFailure {
                _ = try NiKWorkspaceV9Service.restore(projectID: project.id, customContainerResolver: { scope, id in
                    if id == "app.test.b" { throw NiKError("Unavailable") }
                    return try f.resolve(scope, id)
                }, backupDirectory: f.backups)
            }
            let pending = try JSONDecoder().decode(NiKWorkspaceV9BackupReceipt.self, from: Data(contentsOf: f.receipt(project.id)))
            try require(pending.entries.count == 1 && pending.entries[0].identifier == "app.test.b", "Pending backup discarded")
            let count = try NiKWorkspaceV9Service.restore(projectID: project.id, customContainerResolver: f.resolve, backupDirectory: f.backups)
            try require(count == 1 && contents(f.b.appendingPathComponent("config.txt")) == "original", "Retry failed")
        }
        try test("journal failure happens before target writes") { f in
            let file = f.a.appendingPathComponent("config.txt")
            try Data("original".utf8).write(to: file)
            let blocker = f.root.appendingPathComponent("not-a-directory")
            try Data().write(to: blocker)
            let project = NiKWorkspaceV9Project(name: "Journal failure", rules: [rule()])
            try expectFailure { _ = try NiKWorkspaceV9Service.apply(project: project, userValues: [:], customContainerResolver: f.resolve, backupDirectory: blocker) }
            try require(contents(file) == "original", "Wrote target before durable backup")
        }
        try test("write failure rolls back previously written files") { f in
            let file = f.a.appendingPathComponent("config.txt")
            try Data("original".utf8).write(to: file)
            try Data().write(to: f.a.appendingPathComponent("blocked"))
            let project = NiKWorkspaceV9Project(name: "Rollback", rules: [rule(), rule(path: "blocked/child")])
            try expectFailure { _ = try NiKWorkspaceV9Service.apply(project: project, userValues: [:], customContainerResolver: f.resolve, backupDirectory: f.backups) }
            try require(contents(file) == "original", "Rollback did not restore original")
            try require(!fm.fileExists(atPath: f.receipt(project.id).path), "Successful rollback left pending journal")
        }
        try test("duplicate paths fail before any writes") { f in
            let project = NiKWorkspaceV9Project(name: "Duplicates", rules: [rule(), rule()])
            try expectFailure { _ = try NiKWorkspaceV9Service.apply(project: project, userValues: [:], customContainerResolver: f.resolve, backupDirectory: f.backups) }
            try require(!fm.fileExists(atPath: f.a.appendingPathComponent("config.txt").path), "Duplicate wrote target")
        }
        try test("symlink target cannot escape the container") { f in
            try fm.createSymbolicLink(at: f.a.appendingPathComponent("link"), withDestinationURL: f.b)
            let project = NiKWorkspaceV9Project(name: "Symlink", rules: [rule(path: "link/config.txt")])
            try expectFailure { _ = try NiKWorkspaceV9Service.apply(project: project, userValues: [:], customContainerResolver: f.resolve, backupDirectory: f.backups) }
            try require(!fm.fileExists(atPath: f.b.appendingPathComponent("config.txt").path), "Escaped container")
        }
        try test("resolve each container once per apply and once per restore") { f in
            var calls = 0
            let project = NiKWorkspaceV9Project(name: "Cache", rules: (0..<100).map { rule(path: "file-\($0)") })
            let resolver: (NiKContainerScope, String) throws -> URL = { scope, id in calls += 1; return try f.resolve(scope, id) }
            _ = try NiKWorkspaceV9Service.apply(project: project, userValues: [:], customContainerResolver: resolver, backupDirectory: f.backups)
            try require(calls == 1, "Repeated resolution during apply")
            _ = try NiKWorkspaceV9Service.restore(projectID: project.id, customContainerResolver: resolver, backupDirectory: f.backups)
            try require(calls == 2, "Repeated resolution during restore")
        }
        try test("duplicate setting IDs throw instead of trapping") { _ in
            let field = NiKPatchSettingField(id: "name", label: "Name")
            let schema = NiKPatchSettingsSchema(fields: [field, field])
            try expectFailure { _ = try NiKDynamicPayloadMerger.merge(targetData: nil, payloadData: Data("{}".utf8), isPlist: false, schema: schema, userValues: [:]) }
        }
        try test("failed restore write remains retryable") { f in
            let file = f.a.appendingPathComponent("config.txt")
            try Data("original".utf8).write(to: file)
            let project = NiKWorkspaceV9Project(name: "Failed restore", rules: [rule()])
            _ = try NiKWorkspaceV9Service.apply(project: project, userValues: [:], customContainerResolver: f.resolve, backupDirectory: f.backups)
            try fm.removeItem(at: file)
            try fm.createDirectory(at: file, withIntermediateDirectories: true)
            try Data().write(to: file.appendingPathComponent("child"))
            try expectFailure { _ = try NiKWorkspaceV9Service.restore(projectID: project.id, customContainerResolver: f.resolve, backupDirectory: f.backups) }
            try require(fm.fileExists(atPath: f.receipt(project.id).path), "Failed restore deleted journal")
            try fm.removeItem(at: file)
            _ = try NiKWorkspaceV9Service.restore(projectID: project.id, customContainerResolver: f.resolve, backupDirectory: f.backups)
            try require(contents(file) == "original", "Failed retry")
        }
        print("PASS: \(passed) transaction regression scenarios")
    }
}
