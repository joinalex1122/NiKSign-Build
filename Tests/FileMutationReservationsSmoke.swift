import Foundation

@main struct FileMutationReservationsSmoke {
    @MainActor static func fails(_ action: () throws -> Void) {
        do { try action() } catch { return }
        fatalError("Expected file mutation protection failure")
    }
    @MainActor static func main() throws {
        let registry = NiKFileMutationReservations()
        let root = URL(fileURLWithPath: "/tmp/nik-mutation-fixtures")
        let input = root.appendingPathComponent("App.ipa")
        let injected = root.appendingPathComponent("Components/tweak.dylib")
        fails { _ = try registry.reserve([root], protected: [input, injected]) }
        fails { _ = try registry.reserve([input], protected: [input]) }
        fails { _ = try registry.reserve([root.appendingPathComponent("Components")], protected: [injected]) }
        fails { _ = try registry.reserve([root.appendingPathComponent("app.IPA")], protected: [input]) }
        fails { _ = try registry.reserve([root], readOnlyRoots: [root.appendingPathComponent("IPALibrary")]) }
        fails { _ = try registry.reserve([root.appendingPathComponent("IPALibrary/library.json")], readOnlyRoots: [root.appendingPathComponent("IPALibrary")]) }
        let lease = try registry.reserve([input])
        precondition(registry.isReserved(input) && registry.isReserved(root))
        precondition(!registry.isReserved(URL(fileURLWithPath: root.path + "-sibling/App.ipa")))
        fails { _ = try registry.reserve([input]) }
        fails { _ = try registry.reserve([root]) }
        let other = try registry.reserve([root.appendingPathComponent("other.txt")])
        registry.release(lease)
        precondition(!registry.isReserved(input))
        registry.release(other)
        fails { _ = try registry.reserve([URL(string: "https://example.test/file")!]) }
        let global = try registry.reserve([URL(fileURLWithPath: "/")])
        precondition(registry.isReserved(input))
        registry.release(global)
        print("PASS: input/component/ancestor/managed-root protection, active leases, release, path boundaries and case/protocol normalization")
    }
}
