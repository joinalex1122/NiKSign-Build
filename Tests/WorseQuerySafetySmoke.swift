import Foundation
#if os(Linux)
import Glibc
#else
import Darwin
#endif
@main struct WorseQuerySafetySmoke {
    enum Stop: Error { case injected }
    static func rejects(_ action: () throws -> Void) { do { try action(); fatalError("Expected rejection") } catch {} }
    static func main() throws {
        let fm = FileManager.default
        if CommandLine.arguments.count == 3 {
            let group = URL(fileURLWithPath: CommandLine.arguments[2])
            try NiKGroupCacheTransaction.withCache(groupRoot: group, target: "/tmp/nik-wq-target") {
                try fm.createSymbolicLink(atPath: group.appendingPathComponent("Library/Caches").path, withDestinationPath: "/tmp/nik-wq-target")
                exit(0) // Simulate process death, not a Swift error/defer unwind.
            }
            fatalError("Child should have exited")
        }
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let caches = root.appendingPathComponent("Library/Caches")
        try fm.createDirectory(at: caches, withIntermediateDirectories: true)
        try Data("original".utf8).write(to: caches.appendingPathComponent("keep"))
        let before = try fm.attributesOfItem(atPath: caches.path)[.systemFileNumber] as! NSNumber
        func checkOriginal() throws {
            let bytes = try Data(contentsOf: caches.appendingPathComponent("keep"))
            precondition(bytes == Data("original".utf8))
            precondition(tryValue { try fm.attributesOfItem(atPath: caches.path)[.systemFileNumber] as! NSNumber } == before)
        }
        try NiKGroupCacheTransaction.withCache(groupRoot: root, target: "/tmp/nik-wq-target") {
            try fm.createDirectory(at: caches, withIntermediateDirectories: false)
        }
        try checkOriginal()
        rejects {
            try NiKGroupCacheTransaction.withCache(groupRoot: root, target: "/tmp/nik-wq-target") {
                try fm.createSymbolicLink(atPath: caches.path, withDestinationPath: "/tmp/nik-wq-target")
                throw Stop.injected
            }
        }
        try checkOriginal()
        let child = Process(); child.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]); child.arguments = ["--crash", root.path]
        try child.run(); child.waitUntilExit(); precondition(child.terminationStatus == 0)
        try NiKGroupCacheTransaction.withCache(groupRoot: root, target: "/tmp/nik-wq-target") {}
        try checkOriginal()
        rejects {
            try NiKGroupCacheTransaction.withCache(groupRoot: root, target: "/tmp/nik-wq-target") {
                try fm.createDirectory(at: caches, withIntermediateDirectories: false)
                try Data("new".utf8).write(to: caches.appendingPathComponent("new"))
            }
        }
        precondition(fm.fileExists(atPath: root.appendingPathComponent("Library/.NiKSign-WQ-Transaction/OriginalCaches/keep").path))
        let newer = try Data(contentsOf: caches.appendingPathComponent("new")); precondition(newer == Data("new".utf8))
        try fm.removeItem(at: caches.appendingPathComponent("new"))
        try NiKGroupCacheTransaction.withCache(groupRoot: root, target: "/tmp/nik-wq-target") {}
        try checkOriginal()
        precondition(NiKWorseQueryPolicy.supports(major: 27, minor: 2, patch: 0))
        precondition(!NiKWorseQueryPolicy.supports(major: 27, minor: 3, patch: 0))
        precondition(!NiKWorseQueryPolicy.supports(major: 26, minor: 7, patch: 3))
        precondition(NiKWorseQueryPolicy.allowedPath("/private/var/mobile/Containers/Data/Application/UUID") != nil)
        precondition(NiKWorseQueryPolicy.allowedPath("/var/mobile/Containers/Data/Application/../../../../etc") == nil)
        precondition(NiKWorseQueryPolicy.allowedPath("/etc") == nil)
        print("PASS: cache bytes/inode preserved, exception and process-death recovery, conflict backup preserved, OS/path scope guards")
    }
    static func tryValue<T>(_ body: () throws -> T) -> T { try! body() }
}
