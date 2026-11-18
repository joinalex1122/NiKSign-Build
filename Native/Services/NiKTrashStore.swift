import Foundation

/// Serialized, journal-before-rename trash. Prepared phases are recoverable after termination.
final class NiKTrashStore: @unchecked Sendable {
    enum Checkpoint { case afterPrepare, afterMove, beforeFinalCommit }
    private struct Document: Codable { let version: Int; let records: [NiKTrashRecord] }
    let directory: URL
    let root: URL
    private let index: URL
    private let lock = NSRecursiveLock()
    private var records: [NiKTrashRecord] = []
    private var baseline: Data?
    private let fail: ((Checkpoint) throws -> Void)?
    init(directory: URL, root: URL, failureInjector: ((Checkpoint) throws -> Void)? = nil) throws {
        self.directory = directory.standardizedFileURL; self.root = root.standardizedFileURL
        index = directory.appendingPathComponent("index.json"); fail = failureInjector
        let trashPath = directory.standardizedFileURL.resolvingSymlinksInPath().path
        let documentsPath = root.standardizedFileURL.resolvingSymlinksInPath().path
        guard directory.isFileURL, root.isFileURL,
              !trashPath.hasPrefix(documentsPath + "/"), trashPath != documentsPath else {
            throw failure("Thùng rác phải nằm ngoài thư mục tài liệu.")
        }
        _ = try NiKFileLocation().resolve(in: root)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw failure("Thùng rác không được là symlink.") }
        if exists(index) {
            let values = try index.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 8 * 1_048_576 else { throw failure("Index thùng rác không hợp lệ hoặc vượt 8 MB.") }
            let data = try Data(contentsOf: index)
            guard data.count <= 8 * 1_048_576 else { throw failure("Index thùng rác vượt 8 MB.") }
            let document = try JSONDecoder().decode(Document.self, from: data)
            guard document.version == 1 else { throw failure("Version thùng rác chưa hỗ trợ.") }
            try validate(document.records)
            records = document.records; baseline = data
        }
        try recover()
    }
    private func failure(_ message: String) -> NiKFileBrowserState.Failure { .init(message: message) }
    private func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
    private func entry(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString, isDirectory: true) }
    private func payload(_ id: UUID) -> URL { entry(id).appendingPathComponent("payload") }
    private func matches(_ url: URL, _ record: NiKTrashRecord) -> Bool { (try? NiKTrashIdentity.read(url)) == record.identity }
    private func validate(_ values: [NiKTrashRecord]) throws {
        guard values.count <= 5_000, Set(values.map(\.id)).count == values.count else { throw failure("Quá nhiều mục thùng rác hoặc ID trùng.") }
        for record in values {
            try record.original.validate()
            guard !record.original.components.isEmpty, record.bytes <= 4_294_967_296 else { throw failure("Đích/dung lượng thùng rác không hợp lệ.") }
            guard record.original.components.first?.lowercased() != "ipalibrary" || record.libraryItem != nil else { throw failure("Mục thư viện cần metadata để khôi phục an toàn.") }
            if let item = record.libraryItem {
                _ = try NiKLibraryIndex.encode([item])
                guard record.original.components.first?.lowercased() == "ipalibrary", record.original.components.last == item.filename else { throw failure("Metadata thư viện không khớp mục thùng rác.") }
            }
        }
    }
    private func commit(_ updated: [NiKTrashRecord]) throws {
        try validate(updated)
        _ = try NiKFileLocation().resolve(in: directory)
        let data = try JSONEncoder().encode(Document(version: 1, records: updated))
        guard data.count <= 8 * 1_048_576 else { throw failure("Index thùng rác vượt 8 MB.") }
        let current: Data?
        if exists(index) {
            let values = try index.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 8 * 1_048_576 else { throw failure("Index thùng rác đổi bên ngoài hoặc không hợp lệ.") }
            current = try Data(contentsOf: index)
        } else { current = nil }
        guard current == baseline else { throw failure("Index thùng rác đã đổi bên ngoài; chưa ghi đè.") }
        #if os(iOS)
        try data.write(to: index, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: index, options: .atomic)
        #endif
        baseline = data; records = updated
    }
    private func replace(_ record: NiKTrashRecord) throws {
        guard let i = records.firstIndex(where: { $0.id == record.id }) else { throw failure("Không tìm thấy mục thùng rác.") }
        var updated = records; updated[i] = record; try commit(updated)
    }
    private func target(_ record: NiKTrashRecord, createParents: Bool) throws -> URL {
        try record.original.validate()
        _ = try NiKFileLocation().resolve(in: root)
        var parent = root
        for name in record.original.components.dropLast() {
            parent.appendPathComponent(name, isDirectory: true)
            if exists(parent) { _ = try NiKFileLocation.from(parent, root: root) }
            else if createParents { try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false) }
        }
        return parent.appendingPathComponent(record.original.components.last!)
    }
    private func checkEntry(_ id: UUID) throws {
        _ = try NiKFileLocation(components: [id.uuidString]).resolve(in: directory)
    }
    func history() -> [NiKTrashRecord] { lock.lock(); defer { lock.unlock() }; return records.sorted { $0.createdAt > $1.createdAt } }
    func recover() throws {
        lock.lock(); defer { lock.unlock() }
        var updated = records, changed = false
        for i in updated.indices {
            var record = updated[i]
            let phase: NiKTrashRecord.Action?
            switch record.state {
            case .trashPrepared: phase = .trash
            case .restorePrepared: phase = .restore
            case .purgePrepared: phase = .purge
            case .needsReview, .missing: phase = record.pendingAction
            default: phase = nil
            }
            guard let phase else { continue }
            record.pendingAction = phase
            let backup = payload(record.id)
            do {
                try checkEntry(record.id)
                if phase == .purge {
                    record.state = exists(backup) ? .purgePrepared : .purged
                } else {
                    let original = try target(record, createParents: false)
                    if phase == .trash {
                        if matches(backup, record), !exists(original) { record.state = record.libraryItem == nil ? .trashed : .trashedNeedsIndex }
                        else if !exists(backup), matches(original, record) { record.state = .aborted }
                        else { record.state = exists(backup) || exists(original) ? .needsReview : .missing }
                    } else {
                        if matches(original, record), !exists(backup) { record.state = record.libraryItem == nil ? .restored : .restoredNeedsIndex }
                        else if matches(backup, record), !exists(original) { record.state = record.libraryItem == nil ? .trashed : .trashedNeedsIndex }
                        else { record.state = exists(backup) || exists(original) ? .needsReview : .missing }
                    }
                }
            } catch { record.state = .needsReview }
            if ![.needsReview, .missing, .purgePrepared].contains(record.state) { record.pendingAction = nil }
            if record.state != updated[i].state || record.pendingAction != updated[i].pendingAction {
                record.updatedAt = Date(); updated[i] = record; changed = true
            }
        }
        if changed { try commit(updated) }
    }
    private func move(_ source: URL, to destination: URL, identity: NiKTrashIdentity) throws {
        func checked(_ from: URL, _ to: URL) throws {
            guard !exists(to), try NiKTrashIdentity.read(from) == identity else { throw failure("Đích đã có tệp hoặc nguồn thay đổi; chưa di chuyển.") }
            try FileManager.default.moveItem(at: from, to: to)
        }
        #if os(iOS) || os(macOS)
        var coordinationError: NSError?, operationError: Error?
        NSFileCoordinator().coordinate(writingItemAt: source, options: .forMoving, writingItemAt: destination, options: .forReplacing, error: &coordinationError) { from, to in
            do { try checked(from, to) } catch { operationError = error }
        }
        if let coordinationError { throw coordinationError }
        if let operationError { throw operationError }
        #else
        try checked(source, destination)
        #endif
    }

    private func size(_ url: URL) throws -> UInt64 {
        let fm = FileManager.default
        let identity = try NiKTrashIdentity.read(url)
        if !identity.isDirectory {
            let values = try fm.attributesOfItem(atPath: url.path)
            return (values[.size] as? NSNumber)?.uint64Value ?? 0
        }
        var bytes: UInt64 = 0, count = 0
        var listingError: Error?
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isSymbolicLinkKey], options: [], errorHandler: { _, error in listingError = error; return false }) else { throw failure("Không liệt kê được thư mục cần đưa vào thùng rác.") }
        while let child = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            count += 1
            guard count <= 50_000 else { throw failure("Thư mục vượt 50.000 mục.") }
            let childIdentity = try NiKTrashIdentity.read(child)
            if !childIdentity.isDirectory {
                let values = try fm.attributesOfItem(atPath: child.path)
                let amount = (values[.size] as? NSNumber)?.uint64Value ?? 0
                guard amount <= 4_294_967_296 - bytes else { throw failure("Thư mục vượt 4 GB.") }
                bytes += amount
            }
        }
        if let listingError { throw listingError }
        return bytes
    }
    func trash(_ url: URL, libraryItem: NiKLibraryItem? = nil, operationID: UUID = UUID()) throws -> NiKTrashRecord {
        lock.lock(); defer { lock.unlock() }
        let parent = try NiKFileLocation.from(url.deletingLastPathComponent(), root: root)
        let location = NiKFileLocation(components: parent.components + [url.lastPathComponent])
        try location.validate()
        guard location.components.first?.lowercased() != "ipalibrary" || libraryItem != nil else { throw failure("Dùng màn Thư viện IPA để xóa/khôi phục IPA có metadata.") }
        let identity = try NiKTrashIdentity.read(url), bytes = try size(url)
        guard bytes <= 4_294_967_296 else { throw failure("Mục vượt 4 GB.") }
        let retained = records.filter { ![.purged, .restored, .aborted, .restoredNeedsIndex].contains($0.state) }.reduce(UInt64(0)) { $0 + $1.bytes }
        guard retained <= 4_294_967_296 - bytes else { throw failure("Thùng rác đạt giới hạn 4 GB. Hãy khôi phục hoặc xóa vĩnh viễn một số mục.") }
        guard !records.contains(where: { $0.id == operationID }), !exists(entry(operationID)) else { throw failure("Operation ID đã được sử dụng.") }
        let record = NiKTrashRecord(id: operationID, original: location, identity: identity, bytes: bytes,
            createdAt: Date(), updatedAt: Date(), state: .trashPrepared, pendingAction: .trash, libraryItem: libraryItem)
        try FileManager.default.createDirectory(at: entry(record.id), withIntermediateDirectories: false)
        try commit(records + [record])
        try fail?(.afterPrepare)
        try move(url, to: payload(record.id), identity: identity)
        try fail?(.afterMove)
        guard matches(payload(record.id), record) else { throw failure("Mục đã đổi trong khi di chuyển; giữ journal để kiểm tra.") }
        var completed = record; completed.state = libraryItem == nil ? .trashed : .trashedNeedsIndex; completed.pendingAction = nil; completed.updatedAt = Date()
        try fail?(.beforeFinalCommit)
        try replace(completed)
        return completed
    }
    func restore(_ id: UUID) throws -> NiKTrashRecord {
        lock.lock(); defer { lock.unlock() }
        try recover()
        guard var record = records.first(where: { $0.id == id }) else { throw failure("Không tìm thấy mục.") }
        guard [.trashed, .trashedNeedsIndex, .restoredNeedsIndex].contains(record.state) else { throw failure("Mục chưa ở trạng thái có thể khôi phục.") }
        let original = try target(record, createParents: true)
        if record.state == .restoredNeedsIndex, matches(original, record), !exists(payload(id)) { return record }
        guard [.trashed, .trashedNeedsIndex].contains(record.state) else { throw failure("Mục chưa ở trạng thái có thể khôi phục; giữ dữ liệu để kiểm tra.") }
        try checkEntry(id)
        guard matches(payload(id), record) else { throw failure("Backup thay đổi hoặc thiếu; không khôi phục tự động.") }
        guard !exists(original) else { throw failure("Đích đã có tệp. Hãy di chuyển/đổi tên tệp mới trước, không ghi đè.") }
        record.state = .restorePrepared; record.pendingAction = .restore; record.updatedAt = Date(); try replace(record)
        try fail?(.afterPrepare)
        try move(payload(id), to: original, identity: record.identity)
        try fail?(.afterMove)
        record.state = record.libraryItem == nil ? .restored : .restoredNeedsIndex
        record.pendingAction = nil
        record.updatedAt = Date()
        try fail?(.beforeFinalCommit)
        try replace(record)
        return record
    }
    func restoredRecord(_ id: UUID) throws -> NiKTrashRecord {
        lock.lock(); defer { lock.unlock() }
        guard let record = records.first(where: { $0.id == id }), [.restored, .restoredNeedsIndex].contains(record.state),
              matches(try target(record, createParents: false), record), !exists(payload(id)) else { throw failure("Chưa xác nhận được dữ liệu đã khôi phục.") }
        return record
    }
    func entryDirectory(_ id: UUID) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        guard records.contains(where: { $0.id == id }) else { throw failure("Không tìm thấy mục.") }
        try checkEntry(id)
        return entry(id)
    }
    func originalURL(_ id: UUID) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        guard let record = records.first(where: { $0.id == id }) else { throw failure("Không tìm thấy mục.") }
        return try target(record, createParents: false)
    }
    func pendingLibraryRemoval(_ id: UUID) throws -> NiKTrashRecord {
        lock.lock(); defer { lock.unlock() }
        guard let record = records.first(where: { $0.id == id }), record.state == .trashedNeedsIndex, record.libraryItem != nil else { throw failure("Không có yêu cầu cập nhật thư viện đang chờ.") }
        try checkEntry(id)
        guard matches(payload(id), record), !exists(try target(record, createParents: false)) else { throw failure("Backup/đích không còn đúng trạng thái xóa đang chờ.") }
        return record
    }
    func finishLibraryRemoval(_ id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        var record = try pendingLibraryRemoval(id)
        record.state = .trashed; record.updatedAt = Date()
        try fail?(.beforeFinalCommit); try replace(record)
    }

    func finishLibraryRestore(_ id: UUID) throws {
        lock.lock(); defer { lock.unlock() }
        guard var record = records.first(where: { $0.id == id }), record.state == .restoredNeedsIndex,
              matches(try target(record, createParents: false), record) else { throw failure("Chưa xác nhận được dữ liệu khôi phục.") }
        record.state = .restored; record.updatedAt = Date()
        try fail?(.beforeFinalCommit); try replace(record)
    }
    /// Manual review export only; unlike restore this makes no identity guarantee.
    func backupForReview(_ id: UUID) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        guard records.contains(where: { $0.id == id }) else { throw failure("Không tìm thấy mục.") }
        try checkEntry(id)
        let values = try FileManager.default.attributesOfItem(atPath: payload(id).path)
        guard let type = values[.type] as? FileAttributeType, type == .typeRegular || type == .typeDirectory else { throw failure("Không xuất symlink hoặc tệp đặc biệt.") }
        return payload(id)
    }
    func backupURL(_ id: UUID) throws -> URL {
        lock.lock(); defer { lock.unlock() }
        try checkEntry(id)
        guard let record = records.first(where: { $0.id == id }), matches(payload(id), record) else { throw failure("Không còn backup nhận diện được.") }
        return payload(id)
    }
    func removeFinished(_ ids: Set<UUID>) throws {
        lock.lock(); defer { lock.unlock() }
        guard !ids.isEmpty else { return }
        let removing = records.filter { ids.contains($0.id) }
        guard removing.allSatisfy({ [.restored, .purged, .aborted].contains($0.state) && !exists(payload($0.id)) }) else {
            throw failure("Chỉ dọn lịch sử đã kết thúc và không còn payload cần giữ.")
        }
        try commit(records.filter { !ids.contains($0.id) })
        for record in removing {
            if (try? FileManager.default.contentsOfDirectory(atPath: entry(record.id).path).isEmpty) == true {
                try? FileManager.default.removeItem(at: entry(record.id))
            }
        }
    }

    func purge(_ id: UUID, confirmingPermanentDeletion: Bool) throws {
        lock.lock(); defer { lock.unlock() }
        guard confirmingPermanentDeletion else { throw failure("Cần xác nhận xóa vĩnh viễn backup.") }
        guard var record = records.first(where: { $0.id == id }), [.trashed, .needsReview, .missing, .purgePrepared].contains(record.state) else { throw failure("Mục không thể xóa vĩnh viễn ở trạng thái này.") }
        try checkEntry(id)
        record.state = .purgePrepared; record.pendingAction = .purge; record.updatedAt = Date(); try replace(record)
        try fail?(.afterPrepare)
        if exists(payload(id)) { try FileManager.default.removeItem(at: payload(id)) }
        try fail?(.beforeFinalCommit)
        record.state = .purged; record.pendingAction = nil; record.updatedAt = Date(); try replace(record)
    }
}
