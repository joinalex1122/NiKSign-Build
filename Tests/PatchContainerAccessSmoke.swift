import Foundation
@main struct PatchContainerAccessSmoke {
    static func main() throws {
        let primary = "/tmp/nik-primary", fallback = "/tmp/nik-fallback"
        let primaryPath = URL(fileURLWithPath: primary).standardizedFileURL.resolvingSymlinksInPath().path
        let fallbackPath = URL(fileURLWithPath: fallback).standardizedFileURL.resolvingSymlinksInPath().path
        var lookups = 0, probes = 0
        func resolve(_ value: String?, valid: Bool = true, denied: Bool = false) throws -> URL {
            try NiKPatchContainerAccess.resolve(bundleID: "com.example.target", primary: value,
                fallback: { lookups += 1; return fallback }, validatePath: { _ in valid },
                probe: { _ in probes += 1; if denied { throw CocoaError(.fileReadNoPermission) } })
        }
        precondition(tryValue { try resolve(primary).path } == primaryPath)
        precondition(lookups == 0 && probes == 1)
        precondition(tryValue { try resolve(nil).path } == fallbackPath)
        precondition(lookups == 1 && probes == 2)
        do { _ = try resolve(nil, valid: false); fatalError("Reject invalid root") }
        catch let e as NiKPatchAccessFailure { if case .unresolved = e.reason {} else { fatalError() } }
        do { _ = try resolve(primary, denied: true); fatalError("Reject denied root") }
        catch let e as NiKPatchAccessFailure { if case .unreadable = e.reason {} else { fatalError() } }
        print("PASS: primary/exact-ID fallback, invalid-root rejection and denied access are distinct; no writes in preflight")
    }
    static func tryValue<T>(_ body: () throws -> T) -> T { try! body() }
}
