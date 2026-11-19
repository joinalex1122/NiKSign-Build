import Foundation

@main struct HTTPDownloadSmoke {
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Int64 = 0
        func record(_ count: Int64) { lock.lock(); value = count; lock.unlock() }
        var count: Int64 { lock.lock(); defer { lock.unlock() }; return value }
    }
    static func fails(_ action: () async throws -> Void) async {
        do { try await action() } catch { return }
        fatalError("Expected HTTP validation failure")
    }
    static func main() async throws {
        let base = URL(string: CommandLine.arguments[1])!
        let fm = FileManager.default
        let before = Set(try fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path).filter { $0.hasPrefix("NiKSign-Network-") })
        let receipt = try await NiKHTTPDownload.download(base.appendingPathComponent("small"), limit: 100)
        let data = try Data(contentsOf: receipt.url)
        precondition(receipt.bytes == 5 && data == Data("hello".utf8))
        try receipt.discard()
        precondition(!fm.fileExists(atPath: receipt.directory.path))
        await fails { _ = try await NiKHTTPDownload.download(base.appendingPathComponent("redirect"), limit: 100, allowRedirects: false) }
        let redirected = try await NiKHTTPDownload.download(base.appendingPathComponent("redirect"), limit: 100)
        precondition(redirected.bytes == 5)
        try redirected.discard()
        for endpoint in ["declared-large", "stream-large", "loop", "empty", "failure"] {
            await fails { _ = try await NiKHTTPDownload.download(base.appendingPathComponent(endpoint), limit: 100) }
        }
        for raw in ["file:///tmp/private", "ftp://example.test/file", "https://user:secret@example.test/file"] {
            await fails { _ = try await NiKHTTPDownload.download(URL(string: raw)!, limit: 100) }
        }
        let counter = Counter()
        let pending = Task {
            try await NiKHTTPDownload.download(base.appendingPathComponent("slow"), limit: 1_048_576, progress: { counter.record($0.bytes) })
        }
        for _ in 0..<100 {
            if counter.count > 0 { break }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        precondition(counter.count > 0)
        pending.cancel()
        do { _ = try await pending.value; fatalError("Cancellation did not stop transfer") }
        catch is CancellationError {} // A cancellation is distinct from an HTTP/server error.
        let after = Set(try fm.contentsOfDirectory(atPath: fm.temporaryDirectory.path).filter { $0.hasPrefix("NiKSign-Network-") })
        precondition(after == before)
        print("PASS: streamed HTTP download, redirect, declared/actual limits, HTTP/empty/protocol errors, progress, cancellation and owned staging cleanup")
    }
}
