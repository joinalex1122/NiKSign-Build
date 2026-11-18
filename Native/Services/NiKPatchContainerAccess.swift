import Foundation

struct NiKPatchAccessFailure: LocalizedError {
    enum Reason { case unresolved, unreadable }
    let bundleID: String
    let reason: Reason
    func message(english: Bool) -> String {
        switch reason {
        case .unresolved:
            return english
                ? "Cannot resolve the data container for \(bundleID). Check the exact installed Bundle ID, open the target app once, and check 3105 access. A failed lookup does not prove the app is uninstalled. No patch file was changed."
                : "Chưa xác định được container dữ liệu của \(bundleID). Kiểm tra đúng Bundle ID đã cài, mở app đích một lần và kiểm tra quyền truy cập 3105. Tra cứu thất bại không chứng minh app chưa cài. Chưa thay đổi tệp patch nào."
        case .unreadable:
            return english
                ? "Found the container for \(bundleID), but iOS does not allow reading it. Check 3105 access on this device. Changing NiKSign's Bundle ID or signing it does not grant system access. No patch file was changed."
                : "Đã tìm thấy container của \(bundleID), nhưng iOS không cho đọc. Kiểm tra quyền truy cập 3105 trên máy này. Đổi Bundle ID hoặc ký NiKSign không tự cấp quyền hệ thống. Chưa thay đổi tệp patch nào."
        }
    }
    var errorDescription: String? { message(english: false) }
}

enum NiKPatchContainerAccess {
    static func resolve(bundleID: String, primary: String?, fallback: () -> String?,
                        validatePath: (String) -> Bool, probe: (URL) throws -> Void) throws -> URL {
        for path in [primary, primary == nil ? fallback() : nil].compactMap({ $0 }) {
            let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.resolvingSymlinksInPath()
            guard validatePath(root.path) else { continue }
            do { try probe(root); return root }
            catch { throw NiKPatchAccessFailure(bundleID: bundleID, reason: .unreadable) }
        }
        throw NiKPatchAccessFailure(bundleID: bundleID, reason: .unresolved)
    }
}
