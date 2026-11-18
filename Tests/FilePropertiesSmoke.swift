import Foundation

@main struct FilePropertiesSmoke {
    static func fails(_ action: () throws -> Void) {
        do { try action() } catch { return }
        fatalError("Expected file properties error")
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let url = root.appendingPathComponent("Tài liệu.txt")
        try Data("hello".utf8).write(to: url)
        let properties = try NiKFileProperties.inspect(url, root: root, hash: true)
        precondition(properties.name == "Tài liệu.txt" && properties.size == 5 && !properties.isDirectory)
        precondition(properties.sha256 == "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824")
        fails { _ = try NiKFileProperties.inspect(url, root: root, hash: true, digestLimit: 3) }
        let directory = root.appendingPathComponent("Folder")
        try fm.createDirectory(at: directory, withIntermediateDirectories: false)
        let folder = try NiKFileProperties.inspect(directory, root: root, hash: false)
        precondition(folder.isDirectory && folder.size == nil && folder.sha256 == nil)
        fails { _ = try NiKFileProperties.inspect(directory, root: root, hash: true) }
        let link = root.appendingPathComponent("alias")
        try fm.createSymbolicLink(at: link, withDestinationURL: url)
        fails { _ = try NiKFileProperties.inspect(link, root: root, hash: true) }
        fails { _ = try NiKFileProperties.inspect(url, root: directory, hash: false) }
        print("PASS: file metadata/Unicode/known SHA256, directory semantics, hash limits and symlink/outside-root rejection")
    }
}
