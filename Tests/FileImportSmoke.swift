import Foundation

@main struct FileImportSmoke {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("Mẫu thử.ipa")
        try Data("original".utf8).write(to: source)
        let destination = root.appendingPathComponent("Imported")
        let first = try NiKFileImport.copy(source, into: destination)
        let copied = try Data(contentsOf: first)
        precondition(copied == Data("original".utf8))
        let second = try NiKFileImport.copy(source, into: destination)
        precondition(first != second && second.lastPathComponent == "Mẫu thử (1).ipa")
        let inPlace = try NiKFileImport.copy(first, into: destination)
        precondition(inPlace != first)
        try expectFailure { _ = try NiKFileImport.copy(root, into: destination) }
        try expectFailure { _ = try NiKFileImport.copy(root.appendingPathComponent("missing"), into: destination) }
        let blocker = root.appendingPathComponent("blocked")
        try Data().write(to: blocker)
        try expectFailure { _ = try NiKFileImport.copy(source, into: blocker) }
        let preserved = try Data(contentsOf: source)
        precondition(preserved == Data("original".utf8))
        let pending = try fm.contentsOfDirectory(atPath: destination.path).filter { $0.hasPrefix(".import-") }
        precondition(pending.isEmpty)
        precondition(ExploitSupportPolicy.isSupported(major: 27, minor: 2, patch: 0, build: "official"))
        precondition(!ExploitSupportPolicy.isSupported(major: 27, minor: 3, patch: 0, build: "unknown"))
        precondition(!ExploitSupportPolicy.isSupported(major: 28, minor: 0, patch: 0, build: "unknown"))
        print("PASS: coordinated import, Unicode, duplicate names, same-directory copy, directory/missing/unwritable rejection, cleanup and iOS 27.2 support guard")
    }
    static func expectFailure(_ action: () throws -> Void) throws {
        do { try action() } catch { return }
        throw NiKFileImport.Failure(message: "Expected import error")
    }
}
