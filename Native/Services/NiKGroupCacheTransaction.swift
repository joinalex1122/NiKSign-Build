import Foundation

/// The PoC temporarily replaces Library/Caches. Preserve its contents and recover after process death.
enum NiKGroupCacheTransaction {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    private struct Record: Codable {
        let schema: Int
        let target: String
        let originalInode: UInt64?
        let originalDevice: UInt64?
    }
    private static func identity(_ url: URL) throws -> (UInt64, UInt64) {
        let a = try FileManager.default.attributesOfItem(atPath: url.path)
        guard a[.type] as? FileAttributeType == .typeDirectory,
              let inode = a[.systemFileNumber] as? NSNumber, let device = a[.systemNumber] as? NSNumber else {
            throw Failure(message: "Cache App Group không phải thư mục thường; giữ nguyên để kiểm tra.")
        }
        return (inode.uint64Value, device.uint64Value)
    }
    static func withCache<T>(groupRoot: URL, target: String, action: () throws -> T) throws -> T {
        let fm = FileManager.default
        let library = groupRoot.appendingPathComponent("Library", isDirectory: true)
        try fm.createDirectory(at: library, withIntermediateDirectories: true)
        _ = try identity(groupRoot)
        _ = try identity(library)
        let caches = library.appendingPathComponent("Caches", isDirectory: true)
        let journal = library.appendingPathComponent(".NiKSign-WQ-Transaction", isDirectory: true)
        let backup = journal.appendingPathComponent("OriginalCaches", isDirectory: true)
        let recordURL = journal.appendingPathComponent("record.json")
        func exists(_ url: URL) -> Bool { (try? fm.attributesOfItem(atPath: url.path)) != nil }
        func recover() throws {
            guard exists(journal) else { return }
            _ = try identity(journal)
            let attributes = try fm.attributesOfItem(atPath: recordURL.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  ((attributes[.size] as? NSNumber)?.intValue ?? Int.max) <= 8192 else {
                throw Failure(message: "Journal cache không hợp lệ; giữ nguyên backup.")
            }
            let bytes = try Data(contentsOf: recordURL)
            guard bytes.count <= 8192 else { throw Failure(message: "Journal cache quá lớn; giữ nguyên backup.") }
            let record = try JSONDecoder().decode(Record.self, from: bytes)
            guard record.schema == 1 else { throw Failure(message: "Journal cache chưa hỗ trợ; giữ nguyên backup.") }
            if exists(backup) {
                let original = try identity(backup)
                guard original.0 == record.originalInode, original.1 == record.originalDevice else {
                    throw Failure(message: "Backup cache đổi identity; giữ nguyên để kiểm tra.")
                }
                if exists(caches) {
                    let type = try fm.attributesOfItem(atPath: caches.path)[.type] as? FileAttributeType
                    if type == .typeSymbolicLink {
                        guard try fm.destinationOfSymbolicLink(atPath: caches.path) == record.target else { throw Failure(message: "Cache có symlink khác; không ghi đè.") }
                    } else {
                        _ = try identity(caches)
                        guard try fm.contentsOfDirectory(atPath: caches.path).isEmpty else { throw Failure(message: "Cache có dữ liệu mới; backup được giữ để khôi phục thủ công.") }
                    }
                    try fm.removeItem(at: caches)
                }
                try fm.moveItem(at: backup, to: caches)
            } else if let inode = record.originalInode {
                let current = try identity(caches)
                guard current.0 == inode, current.1 == record.originalDevice else { throw Failure(message: "Không xác minh được cache gốc; giữ journal.") }
            } else if exists(caches) {
                let type = try fm.attributesOfItem(atPath: caches.path)[.type] as? FileAttributeType
                if type == .typeSymbolicLink {
                    guard try fm.destinationOfSymbolicLink(atPath: caches.path) == record.target else { throw Failure(message: "Cache có symlink ngoài giao dịch.") }
                    try fm.removeItem(at: caches)
                } else {
                    _ = try identity(caches)
                    guard try fm.contentsOfDirectory(atPath: caches.path).isEmpty else { throw Failure(message: "Cache mới có dữ liệu; giữ nguyên.") }
                    try fm.removeItem(at: caches)
                }
            }
            guard Set(try fm.contentsOfDirectory(atPath: journal.path)) == ["record.json"] else { throw Failure(message: "Journal có tệp lạ; giữ nguyên.") }
            try fm.removeItem(at: journal)
        }
        try recover()
        let original = exists(caches) ? try identity(caches) : nil
        try fm.createDirectory(at: journal, withIntermediateDirectories: false)
        let record = Record(schema: 1, target: target, originalInode: original?.0, originalDevice: original?.1)
        try JSONEncoder().encode(record).write(to: recordURL, options: .atomic)
        if original != nil { try fm.moveItem(at: caches, to: backup) }
        do {
            let value = try action()
            try recover()
            return value
        } catch {
            try recover()
            throw error
        }
    }
}
