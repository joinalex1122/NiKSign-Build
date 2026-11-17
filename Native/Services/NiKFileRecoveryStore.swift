import Foundation

/// All mutable state and filesystem operations are serialized by the recursive lock.
/// Roots are supplied by the application, never accepted from a backup manifest.
final class NiKFileRecoveryStore: @unchecked Sendable {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    enum Checkpoint: Sendable, Equatable { case afterBackupPersisted, afterTargetWrite, beforeFinalJournalCommit }
    private let failureInjector: (@Sendable (Checkpoint) throws -> Void)?
    private struct Document: Codable { let version: Int; let records: [NiKFileRecoveryRecord] }
    private let lock = NSRecursiveLock()
    private let directory: URL
    private let roots: [URL]
    private let deniedTargets: [URL]
    private let index: URL
    private var records: [NiKFileRecoveryRecord] = []
    private let maximumFileBytes = 32 * 1_048_576
    private let maximumBackupBytes = 256 * 1_048_576

    init(directory: URL, editableRoots: [URL], deniedTargets: [URL] = [], failureInjector: (@Sendable (Checkpoint) throws -> Void)? = nil) throws {
        self.failureInjector = failureInjector
        self.deniedTargets = deniedTargets.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        self.directory = directory.standardizedFileURL.resolvingSymlinksInPath()
        roots = editableRoots.map { $0.standardizedFileURL.resolvingSymlinksInPath() }
        index = self.directory.appendingPathComponent("index.json")
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: index.path) {
            let values = try index.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 16 * 1_048_576 else { throw Failure(message: "Index khôi phục không hợp lệ.") }
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: index))
            guard document.version == 1, document.records.count <= 20_000,
                  document.records.allSatisfy({ $0.originalSize >= 0 && $0.originalSize <= maximumFileBytes }),
                  Set(document.records.map(\.id)).count == document.records.count else { throw Failure(message: "Schema hoặc ID bản sao lưu không hợp lệ.") }
            records = document.records
            try reconcileDiscardedBackups()
            try reconcilePreparedRecords()
        }
    }
    func history() -> [NiKFileRecoveryRecord] { lock.withLock { records } }

    func snapshot(_ url: URL) throws -> NiKEditableFileSnapshot {
        try lock.withLock {
            let target = try checkedTarget(url)
            return try coordinateRead(target) { coordinated in
                _ = try self.checkedTarget(coordinated)
                let data = try self.readBounded(coordinated)
                return NiKEditableFileSnapshot(url: target, data: data, digest: try NiKFileDigest.sha256(data: data))
            }
        }
    }

    @discardableResult
    func write(_ data: Data, to url: URL, expectedDigest: String) throws -> NiKFileRecoveryRecord {
        try lock.withLock {
            guard data.count <= maximumFileBytes else { throw Failure(message: "Tệp chỉnh sửa vượt 32 MB.") }
            let target = try checkedTarget(url)
            return try coordinateWrite(target) { coordinated in
                _ = try self.checkedTarget(coordinated)
                let original = try self.readBounded(coordinated)
                let digest = try NiKFileDigest.sha256(data: original)
                guard digest == expectedDigest else { throw Failure(message: "Tệp đã thay đổi từ lúc mở. Hãy tải lại hoặc so sánh trước khi ghi.") }
                let attributes = try FileManager.default.attributesOfItem(atPath: coordinated.path)
                let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue
                let replacement = try NiKFileDigest.sha256(data: data)
                guard digest != replacement else { throw Failure(message: "Không có thay đổi cần lưu.") }
                let used = self.records.reduce(0) { $0 + $1.originalSize }
                guard original.count <= self.maximumBackupBytes - min(used, self.maximumBackupBytes) else {
                    throw Failure(message: "Backup đã đạt giới hạn 256 MB. Hãy xuất/khôi phục và quản lý lịch sử trước khi sửa tiếp.")
                }
                let id = UUID()
                try self.checkedStorageRoot()
                let folder = self.directory.appendingPathComponent(id.uuidString)
                let backup = folder.appendingPathComponent("original")
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
                var registered = false
                defer { if !registered { try? FileManager.default.removeItem(at: folder) } }
                try self.writeProtected(original, to: backup)
                guard try NiKFileDigest.sha256(file: backup) == digest else { throw Failure(message: "Bản sao lưu không khớp SHA-256.") }
                var record = NiKFileRecoveryRecord(id: id, target: target, originalDigest: digest,
                    replacementDigest: replacement, originalSize: original.count, originalPermissions: permissions, createdAt: Date(), updatedAt: Date(), state: .prepared)
                try self.commit(self.records + [record]) // Recovery data is durable before the target changes.
                registered = true
                do {
                    try self.failureInjector?(.afterBackupPersisted)
                    guard try NiKFileDigest.sha256(file: coordinated) == digest else { throw Failure(message: "Tệp thay đổi trong lúc tạo backup.") }
                    try data.write(to: coordinated, options: .atomic)
                    try self.restorePermissions(record, at: coordinated)
                    try self.failureInjector?(.afterTargetWrite)
                    guard try NiKFileDigest.sha256(file: coordinated) == replacement else { throw Failure(message: "Dữ liệu sau ghi không khớp.") }
                    record.state = .committed; record.updatedAt = Date()
                    try self.failureInjector?(.beforeFinalJournalCommit)
                    try self.update(record)
                    return record
                } catch {
                    let operationError = error
                    if let current = try? NiKFileDigest.sha256(file: coordinated) {
                        if current == replacement {
                            do {
                                try original.write(to: coordinated, options: .atomic)
                                try self.restorePermissions(record, at: coordinated)
                                guard try NiKFileDigest.sha256(file: coordinated) == digest else { throw Failure(message: "Rollback không khớp.") }
                                record.state = .aborted
                            } catch { record.state = .needsReview }
                        } else { record.state = current == digest ? .aborted : .needsReview }
                    } else { record.state = .needsReview }
                    record.message = operationError.localizedDescription; record.updatedAt = Date()
                    try? self.update(record) // A failed journal update leaves the durable prepared record for reopening.
                    throw operationError
                }
            }
        }
    }

    @discardableResult
    func restore(_ id: UUID) throws -> NiKFileRecoveryRecord {
        try lock.withLock {
            guard var record = records.first(where: { $0.id == id }) else { throw Failure(message: "Không tìm thấy bản sao lưu.") }
            do {
                let target = try checkedTarget(record.target)
                let original = try readBounded(checkedBackup(id))
                guard try NiKFileDigest.sha256(data: original) == record.originalDigest else { throw Failure(message: "Backup đã hỏng hoặc thay đổi; không khôi phục.") }
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                _ = try checkedTarget(target)
                return try coordinateWrite(target) { coordinated in
                    _ = try self.checkedTarget(coordinated)
                    if FileManager.default.fileExists(atPath: coordinated.path) {
                        let current = try NiKFileDigest.sha256(file: coordinated)
                        guard current == record.replacementDigest || current == record.originalDigest else {
                            throw Failure(message: "Tệp đích có thay đổi mới. Hãy giữ/xuất phiên bản mới để so sánh; không ghi đè tự động.")
                        }
                    }
                    try original.write(to: coordinated, options: .atomic)
                    try self.restorePermissions(record, at: coordinated)
                    guard try NiKFileDigest.sha256(file: coordinated) == record.originalDigest else { throw Failure(message: "Khôi phục không khớp SHA-256.") }
                    record.state = .restored; record.updatedAt = Date(); record.message = nil
                    try self.update(record)
                    return record
                }
            } catch {
                record.state = .restoreFailed; record.updatedAt = Date(); record.message = error.localizedDescription
                try? self.update(record)
                throw error
            }
        }
    }

    func backupURL(_ id: UUID) throws -> URL {
        try lock.withLock {
            guard let record = records.first(where: { $0.id == id }) else { throw Failure(message: "Không tìm thấy bản sao lưu.") }
            let url = try checkedBackup(id)
            let data = try readBounded(url)
            guard try NiKFileDigest.sha256(data: data) == record.originalDigest else { throw Failure(message: "Backup không khớp SHA-256.") }
            return url
        }
    }

    func discardBackup(_ id: UUID, confirmingLossOfRestore: Bool) throws {
        try lock.withLock {
            guard confirmingLossOfRestore else { throw Failure(message: "Cần xác nhận mất khả năng khôi phục của backup này.") }
            guard records.contains(where: { $0.id == id }) else { throw Failure(message: "Không tìm thấy backup.") }
            try checkedStorageRoot()
            let folder = directory.appendingPathComponent(id.uuidString)
            let staged = directory.appendingPathComponent(".discard-" + id.uuidString)
            let exists = FileManager.default.fileExists(atPath: folder.path)
            if exists {
                _ = try checkedBackup(id)
                try FileManager.default.moveItem(at: folder, to: staged)
            }
            do { try commit(records.filter { $0.id != id }) }
            catch {
                if exists { try? FileManager.default.moveItem(at: staged, to: folder) }
                throw error
            }
            if exists { try FileManager.default.removeItem(at: staged) }
        }
    }

    private func reconcileDiscardedBackups() throws {
        for url in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            let name = url.lastPathComponent
            guard name.hasPrefix(".discard-"), let id = UUID(uuidString: String(name.dropFirst(9))) else { continue }
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure(message: "Thư mục dọn backup không hợp lệ.") }
            if records.contains(where: { $0.id == id }) {
                let original = directory.appendingPathComponent(id.uuidString)
                guard !FileManager.default.fileExists(atPath: original.path) else { throw Failure(message: "Backup có xung đột; giữ cả hai bản để kiểm tra.") }
                try FileManager.default.moveItem(at: url, to: original)
            } else { try FileManager.default.removeItem(at: url) }
        }
    }

    private func checkedTarget(_ input: URL) throws -> URL {
        let target = input.standardizedFileURL
        let path = target.path
        guard !deniedTargets.contains(where: { path == $0.path || path.hasPrefix($0.path + "/") }) else {
            throw Failure(message: "Tệp này do ứng dụng quản lý; chỉ xem, không sửa trực tiếp.")
        }
        guard input.isFileURL, let root = roots.first(where: { path.hasPrefix($0.path + "/") }),
              path != directory.path, !path.hasPrefix(directory.path + "/") else {
            throw Failure(message: "Vị trí này không nằm trong vùng chỉnh sửa được cho phép.")
        }
        guard (try root.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true,
              target.resolvingSymlinksInPath().path.hasPrefix(root.path + "/") else { throw Failure(message: "Root hoặc đường dẫn bị thay bằng symlink.") }
        var current = root
        let relative = String(path.dropFirst(root.path.count + 1))
        for component in relative.split(separator: "/") {
            current.appendPathComponent(String(component))
            if (try? current.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                throw Failure(message: "Không sửa/khôi phục qua symbolic link.")
            }
        }
        return target
    }

    private func checkedStorageRoot() throws {
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true,
              directory.resolvingSymlinksInPath().path == directory.path else { throw Failure(message: "Root backup đã thay đổi hoặc là symlink.") }
        guard (try? index.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else {
            throw Failure(message: "Index backup là symlink.")
        }
    }
    private func checkedBackup(_ id: UUID) throws -> URL {
        try checkedStorageRoot()
        let folder = directory.appendingPathComponent(id.uuidString)
        let values = try folder.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw Failure(message: "Thư mục backup không hợp lệ.") }
        return folder.appendingPathComponent("original")
    }
    private func restorePermissions(_ record: NiKFileRecoveryRecord, at target: URL) throws {
        if let permissions = record.originalPermissions {
            try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: target.path)
        }
    }

    private func readBounded(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              (values.fileSize ?? maximumFileBytes + 1) <= maximumFileBytes else { throw Failure(message: "Chỉ hỗ trợ tệp thường tối đa 32 MB.") }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while let chunk = try handle.read(upToCount: 65_536), !chunk.isEmpty {
            try Task.checkCancellation()
            guard chunk.count <= maximumFileBytes - data.count else { throw Failure(message: "Tệp vượt 32 MB.") }
            data.append(chunk)
        }
        return data
    }

    private func writeProtected(_ data: Data, to url: URL) throws {
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
    }
    private func update(_ record: NiKFileRecoveryRecord) throws {
        guard let i = records.firstIndex(where: { $0.id == record.id }) else { throw Failure(message: "Index thiếu bản sao lưu.") }
        var updated = records; updated[i] = record; try commit(updated)
    }
    private func commit(_ updated: [NiKFileRecoveryRecord]) throws {
        try checkedStorageRoot()
        guard updated.count <= 20_000 else { throw Failure(message: "Quá nhiều bản sao lưu; hãy quản lý lịch sử.") }
        let data = try JSONEncoder().encode(Document(version: 1, records: updated))
        guard data.count <= 16 * 1_048_576 else { throw Failure(message: "Index backup vượt 16 MB.") }
        try writeProtected(data, to: index)
        records = updated
    }
    private func reconcilePreparedRecords() throws {
        var updated = records
        var changed = false
        for i in updated.indices where updated[i].state == .prepared {
            changed = true
            let record = updated[i]
            let digest = try? NiKFileDigest.sha256(file: checkedTarget(record.target))
            let backupDigest = try? NiKFileDigest.sha256(file: checkedBackup(record.id))
            if backupDigest != record.originalDigest {
                updated[i].state = .needsReview
                updated[i].message = "Backup của công việc gián đoạn bị thiếu hoặc đã thay đổi."
                updated[i].updatedAt = Date()
                continue
            }
            updated[i].state = digest == record.originalDigest ? .aborted : digest == record.replacementDigest ? .committed : .needsReview
            updated[i].message = "Đã phát hiện công việc gián đoạn; đối chiếu tệp trước khi tiếp tục."
            updated[i].updatedAt = Date()
        }
        if changed { try commit(updated) }
    }
    private func coordinateRead<T>(_ url: URL, operation: @escaping (URL) throws -> T) throws -> T {
        #if os(Linux)
        return try operation(url)
        #else
        var failure: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &failure) { target in
            result = Result { try operation(target) }
        }
        if let failure { throw failure }
        guard let result else { throw Failure(message: "File coordinator chưa trả về kết quả đọc.") }
        return try result.get()
        #endif
    }
    private func coordinateWrite<T>(_ url: URL, operation: @escaping (URL) throws -> T) throws -> T {
        #if os(Linux)
        return try operation(url)
        #else
        var failure: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &failure) { target in
            result = Result { try operation(target) }
        }
        if let failure { throw failure }
        guard let result else { throw Failure(message: "File coordinator chưa trả về kết quả.") }
        return try result.get()
        #endif
    }
}

