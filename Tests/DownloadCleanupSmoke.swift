import Foundation

@main struct DownloadCleanupSmoke {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let outside = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root); try? fm.removeItem(at: outside) }
        func folder(_ name: String, old: Bool) throws -> URL {
            let url = root.appendingPathComponent(name)
            try fm.createDirectory(at: url, withIntermediateDirectories: false)
            try Data("keep original".utf8).write(to: url.appendingPathComponent("payload"))
            if old { try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: url.path) }
            return url
        }
        let owned = try folder("NiKSign-Network-" + UUID().uuidString, old: true)
        let fresh = try folder("NiKSign-Network-" + UUID().uuidString, old: false)
        let invalid = try folder("NiKSign-Network-user-data", old: true)
        let unrelated = try folder("User Data", old: true)
        let regular = root.appendingPathComponent("NiKSign-Network-" + UUID().uuidString)
        try Data("keep".utf8).write(to: regular)
        try fm.setAttributes([.modificationDate: Date(timeIntervalSince1970: 100)], ofItemAtPath: regular.path)
        let link = root.appendingPathComponent("NiKSign-Network-" + UUID().uuidString)
        try fm.createSymbolicLink(at: link, withDestinationURL: outside)
        let removed = try NiKHTTPDownload.discardAbandoned(in: root)
        precondition(removed == 1 && !fm.fileExists(atPath: owned.path))
        for url in [fresh, invalid, unrelated, regular, link, outside] { precondition(fm.fileExists(atPath: url.path)) }
        print("PASS: abandoned download cleanup removes only old UUID-owned folders; fresh/unrelated/file/symlink targets are preserved")
    }
}
