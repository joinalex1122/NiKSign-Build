import Foundation

/// Main-actor leases close the gap between checking jobs and starting background I/O.
@MainActor final class NiKFileMutationReservations {
    static let shared = NiKFileMutationReservations()
    struct Lease: Sendable { let id: UUID }
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    private var leases: [UUID: [String]] = [:]
    static func path(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path.lowercased().precomposedStringWithCanonicalMapping
    }
    private static func inside(_ path: String, _ parent: String) -> Bool {
        path == parent || path.hasPrefix(parent == "/" ? "/" : parent + "/")
    }
    static func overlaps(_ first: String, _ second: String) -> Bool { inside(first, second) || inside(second, first) }
    static func isWithin(_ url: URL, root: URL) -> Bool { inside(path(url), path(root)) }
    func reserve(_ paths: [URL], protected: [URL] = [], readOnlyRoots: [URL] = []) throws -> Lease {
        guard !paths.isEmpty, (paths + protected + readOnlyRoots).allSatisfy(\.isFileURL) else { throw Failure(message: "Thao tác cần đường dẫn tệp cục bộ.") }
        let keys = paths.map(Self.path)
        let protectedKeys = protected.map(Self.path)
        let roots = readOnlyRoots.map(Self.path)
        guard !keys.contains(where: { key in protectedKeys.contains { Self.overlaps(key, $0) } }) else {
            throw Failure(message: "Tệp/thư mục đang được một công việc ký sử dụng. Hãy hủy hoặc đợi công việc kết thúc.")
        }
        guard !keys.contains(where: { key in roots.contains { Self.overlaps(key, $0) } }) else {
            throw Failure(message: "Vùng thư viện được quản lý riêng. Hãy dùng màn Thư viện IPA để nhập/xóa IPA.")
        }
        guard !keys.contains(where: { key in leases.values.joined().contains { Self.overlaps(key, $0) } }) else {
            throw Failure(message: "Tệp/thư mục đang có thao tác khác; hãy đợi hoàn tất.")
        }
        let lease = Lease(id: UUID())
        leases[lease.id] = keys
        return lease
    }
    func release(_ lease: Lease) { leases.removeValue(forKey: lease.id) }
    func isReserved(_ url: URL) -> Bool {
        let key = Self.path(url)
        return leases.values.joined().contains { Self.overlaps(key, $0) }
    }
}
