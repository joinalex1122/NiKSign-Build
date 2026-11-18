import Foundation

@main struct SourceDownloadSmoke {
    static func fails(_ action: () throws -> Void) {
        do { try action() } catch { return }
        fatalError("Expected feed validation failure")
    }
    static func main() async throws {
        let base = URL(string: CommandLine.arguments[1])!
        let source = base.appendingPathComponent("source/apps.json")
        let expected = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824"
        let entry: [String: Any] = ["name": "Ứng dụng", "bundleIdentifier": "com.example.app", "versions": [["version": "2.0", "size": 5, "downloadURL": "/small", "sha256": expected.uppercased()]]]
        func feed(_ entries: [[String: Any]]) throws -> Data { try JSONSerialization.data(withJSONObject: ["name": "Test source", "apps": entries]) }
        let parsed = try NiKSourceDownloadService.parseFeed(data: feed([entry]), sourceURL: source)
        precondition(parsed.count == 1 && parsed[0].version == "2.0" && parsed[0].sha256 == expected)
        precondition(parsed[0].downloadURL == base.appendingPathComponent("small"))
        fails { _ = try NiKSourceDownloadService.parseFeed(data: Data("{}".utf8), sourceURL: source) }
        fails { _ = try NiKSourceDownloadService.parseFeed(data: feed([entry, entry]), sourceURL: source) }
        fails { _ = try NiKSourceDownloadService.parseFeed(data: Data(repeating: 0, count: 16 * 1_048_576 + 1), sourceURL: source) }
        var bad = entry; bad["versions"] = nil; bad["downloadURL"] = "file:///private/data"
        fails { _ = try NiKSourceDownloadService.parseFeed(data: feed([bad]), sourceURL: source) }
        bad["downloadURL"] = "/small"; bad["sha256"] = "not-a-hash"
        fails { _ = try NiKSourceDownloadService.parseFeed(data: feed([bad]), sourceURL: source) }
        let empty = try NiKSourceDownloadService.parseFeed(data: feed([["name": "Missing metadata"]]), sourceURL: source)
        precondition(empty.isEmpty)
        let fm = FileManager.default
        let before = Set(try fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path).filter { $0.hasPrefix("NiKSign-Network-") })
        let downloaded = try await NiKSourceDownloadService.downloadIPA(base.appendingPathComponent("small"), expectedSHA256: expected)
        precondition(downloaded.sha256 == expected && downloaded.url.pathExtension == "ipa")
        let data = try Data(contentsOf: downloaded.url)
        precondition(data == Data("hello".utf8))
        try downloaded.discard()
        do {
            _ = try await NiKSourceDownloadService.downloadIPA(base.appendingPathComponent("small"), expectedSHA256: String(repeating: "0", count: 64))
            fatalError("Hash mismatch was accepted")
        } catch {}
        let after = Set(try fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path).filter { $0.hasPrefix("NiKSign-Network-") })
        precondition(before == after)
        print("PASS: feed schema/relative URL/version/hash parsing, duplicate/protocol/size rejection, actual streamed SHA256 verification and mismatch cleanup; IPA validation remains in library import")
    }
}
