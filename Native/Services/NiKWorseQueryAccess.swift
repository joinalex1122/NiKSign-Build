import Foundation

enum NiKWorseQueryAccess {
    private static let lock = NSRecursiveLock()
    private static var message: String?
    static var lastError: String? { lock.lock(); defer { lock.unlock() }; return message }
    static var isApplicable: Bool {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return NiKWorseQueryPolicy.supports(major: v.majorVersion, minor: v.minorVersion, patch: v.patchVersion)
    }
    static func acquire(_ target: String) -> Int64 {
        lock.lock(); defer { lock.unlock() }
        guard isApplicable, let path = NiKWorseQueryPolicy.allowedPath(target) else { return -255 }
        var error: NSError?
        guard let groups = NiKSignedAppGroupIdentifiers(&error), !groups.isEmpty else {
            message = error?.localizedDescription ?? "Chữ ký NiKSign không có App Group hợp lệ. Cần profile cấp App Group trước khi dùng worse_query."
            return -1
        }
        for group in groups {
            guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) else { continue }
            let canonical = root.standardizedFileURL.resolvingSymlinksInPath().path
            guard path != canonical, !path.hasPrefix(canonical + "/") else { continue }
            var handle: Int64 = -1
            do {
                handle = try NiKGroupCacheTransaction.withCache(groupRoot: root, target: path) {
                    // App Group access uses alternate flags on iOS26, standard flags on27.
                    handle = worse_query(path, group, ProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26, true)
                    return handle
                }
                if handle >= 0 { message = nil; return handle }
                message = "worse_query từ chối cấp quyền (mã \(handle))."
            } catch {
                if handle >= 0 { worse_query_release(handle) }
                message = error.localizedDescription
                return -1 // Preserve an unresolved cache journal; never move on and hide it.
            }
        }
        if message == nil { message = "iOS không trả container cho App Group đã ký." }
        return -1
    }
    static func release(_ handle: Int64) { if handle >= 0 { worse_query_release(handle) } }
}
