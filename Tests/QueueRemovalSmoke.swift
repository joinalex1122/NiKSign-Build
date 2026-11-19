import Foundation
#if canImport(Combine)
import Combine
#else
protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
#endif

// Test doubles isolate signing latency; the queue/journal and cancellation/removal code are production.
struct NiKError: LocalizedError { let value: String; init(_ value: String) { self.value = value }; var errorDescription: String? { value } }
struct FixtureCertificate { let id: UUID; var isKnownRevoked = false }
@MainActor final class NiKCertificateStore {
    static let shared = NiKCertificateStore()
    var profiles: [FixtureCertificate] = []
    func credentials(for certificate: FixtureCertificate) throws -> (p12: URL, provision: URL, password: String) {
        (URL(fileURLWithPath: "/fixture.p12"), URL(fileURLWithPath: "/fixture.mobileprovision"), "")
    }
}
@MainActor final class NiKLibrary {
    static let shared = NiKLibrary()
    var items: [NiKLibraryItem] = []
    var error = ""
    func save(_ item: NiKLibraryItem) -> Bool { true }
}
actor SigningService {
    static let shared = SigningService()
    var entered = false
    var pause = true
    var gate: CheckedContinuation<Void, Never>?
    var output = URL(fileURLWithPath: "/fixture.ipa")
    func release() { gate?.resume(); gate = nil }
    func configure(output: URL) { self.output = output; pause = false; entered = false }
    func signDetailed(ipa: URL, p12: URL, profile: URL, password: String, options: NiKSigningOptions,
                      onProgress: (@Sendable (NiKSigningProgress) -> Void)?) async throws -> NiKSignedArtifact {
        entered = true
        if pause { await withCheckedContinuation { gate = $0 } }
        try Task.checkCancellation()
        return NiKSignedArtifact(ipaURL: output, bundleID: "com.example.fixture", displayName: "Fixture", version: "1", injectedDylibs: [], certificateSummary: "fixture", teamName: "fixture")
    }
}
@main struct QueueRemovalSmoke {
    @MainActor static func wait(_ predicate: () -> Bool) async throws {
        for _ in 0..<500 { if predicate() { return }; try await Task.sleep(nanoseconds: 10_000_000) }
        fatalError("Queue did not reach its safe boundary")
    }
    @MainActor static func main() async throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let id = UUID(); NiKCertificateStore.shared.profiles = [.init(id: id)]
        let queue = NiKSigningQueue(journalURL: root.appendingPathComponent("jobs.json"))
        func job(_ title: String) -> NiKSigningJob { NiKSigningJob(libraryID: UUID(), title: title, input: root.appendingPathComponent(title + ".ipa"), certificateID: id, options: .init()) }
        let active = job("active"), waiting = job("queued")
        try queue.enqueue([active, waiting])
        for _ in 0..<500 { if await SigningService.shared.entered { break }; try await Task.sleep(nanoseconds: 10_000_000) }
        let entered = await SigningService.shared.entered
        precondition(entered)
        queue.remove([active.id, waiting.id])
        precondition(queue.jobs.count == 1 && queue.jobs[0].id == active.id)
        precondition(queue.jobs[0].state.isActive && queue.jobs[0].removalRequested == true && queue.isRunning)
        await SigningService.shared.release()
        try await wait { queue.jobs.isEmpty && !queue.isRunning }
        let output = root.appendingPathComponent("existing-signed.ipa"); try Data([1, 2, 3]).write(to: output)
        await SigningService.shared.configure(output: output)
        let success = job("success"); try queue.enqueue([success])
        try await wait { queue.jobs.first?.state == .succeeded && !queue.isRunning }
        queue.remove([success.id]); precondition(queue.jobs.isEmpty)
        let retained = try Data(contentsOf: output); precondition(retained == Data([1, 2, 3]))
        NiKCertificateStore.shared.profiles[0].isKnownRevoked = true
        let revoked = job("revoked"); try queue.enqueue([revoked])
        try await wait { queue.jobs.first?.state == .failed && !queue.isRunning }
        precondition(queue.jobs.first?.error?.contains("thu hồi") == true)
        print("PASS: known-revoked job fails before the signer runs")
        print("PASS: real queue keeps active record until cancellation boundary, removes queued jobs, and preserves signed files when history is removed")
    }
}
