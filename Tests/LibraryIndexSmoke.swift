import Foundation

@main struct LibraryIndexSmoke {
    static func fails(_ action: () throws -> Void) {
        do { try action() } catch { return }
        fatalError("Expected index validation failure")
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let url = root.appendingPathComponent("library.json")
        let store = try NiKLibraryIndexStore(url: url)
        let item = NiKLibraryItem(title: "Ứng dụng", version: "1.0", bundleID: "com.example.test", filename: "app.ipa")
        try store.commit([item])
        let loaded = try NiKLibraryIndexStore(url: url)
        precondition(loaded.items.count == 1 && loaded.items[0].title == item.title)
        fails { try store.commit([item, item]) }
        precondition(store.items.count == 1)
        var other = item; other.id = UUID()
        fails { try store.commit([item, other]) }
        other.filename = "APP.IPA"
        fails { try store.commit([item, other]) }
        for filename in ["../escape.ipa", "/outside.ipa", "a/b.ipa", "a\\b.ipa", ".ipa", "x.ipa\n", "image.png"] {
            var invalid = item; invalid.filename = filename
            fails { _ = try NiKLibraryIndex.encode([invalid]) }
        }
        let external = Data("external change".utf8)
        try external.write(to: url, options: .atomic)
        fails { try store.commit([]) }
        let unchanged = try Data(contentsOf: url)
        precondition(unchanged == external && store.items.count == 1)
        fails { _ = try NiKLibraryIndexStore(url: url) }
        let stillPreserved = try Data(contentsOf: url)
        precondition(stillPreserved == external)
        try fm.removeItem(at: url)
        fails { try loaded.commit([]) }
        let target = root.appendingPathComponent("private.json")
        try external.write(to: target)
        try fm.createSymbolicLink(at: url, withDestinationURL: target)
        fails { _ = try NiKLibraryIndexStore(url: url) }
        try fm.removeItem(at: url)
        try fm.createSymbolicLink(at: url, withDestinationURL: root.appendingPathComponent("missing"))
        fails { _ = try NiKLibraryIndexStore(url: url) }
        precondition(!fm.fileExists(atPath: root.appendingPathComponent("missing").path))
        print("PASS: library round-trip, duplicate/path rejection, stale index writes blocked, corrupt index preserved, symlink/dangling symlink rejection")
    }
}
