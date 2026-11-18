import Foundation

enum NiKLibraryIndex {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func load(_ url: URL) throws -> [NiKLibraryItem] {
        try decode(read(url))
    }
    static func read(_ url: URL) throws -> Data {
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              let size = values.fileSize, size <= 16 * 1_048_576 else {
            throw Failure(message: "Index thư viện không phải tệp thường hoặc vượt 16 MB. Giữ nguyên để khôi phục.")
        }
        let data = try Data(contentsOf: url)
        guard data.count <= 16 * 1_048_576 else { throw Failure(message: "Index thư viện vượt 16 MB.") }
        return data
    }
    static func decode(_ data: Data) throws -> [NiKLibraryItem] {
        guard data.count <= 16 * 1_048_576 else { throw Failure(message: "Index thư viện vượt 16 MB.") }
        let items = try JSONDecoder().decode([NiKLibraryItem].self, from: data)
        try validate(items)
        return items
    }
    static func encode(_ items: [NiKLibraryItem]) throws -> Data {
        try validate(items)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(items)
        guard data.count <= 16 * 1_048_576 else { throw Failure(message: "Index thư viện vượt 16 MB.") }
        return data
    }
    private static func validate(_ items: [NiKLibraryItem]) throws {
        guard items.count <= 5_000, Set(items.map(\.id)).count == items.count,
              Set(items.map { $0.filename.precomposedStringWithCanonicalMapping.lowercased() }).count == items.count else {
            throw Failure(message: "Index thư viện quá lớn hoặc có IPA/ID trùng.")
        }
        for item in items {
            let name = item.filename
            guard !name.isEmpty, name.utf8.count <= 255,
                  !name.contains("/"), !name.contains("\\"),
                  !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  (name as NSString).pathExtension.lowercased() == "ipa", name != ".ipa" else {
                throw Failure(message: "Index thư viện chứa tên IPA không an toàn; chưa thay đổi tệp gốc.")
            }
        }
    }
}

/// The owner serializes access. Reject external index edits instead of overwriting them.
final class NiKLibraryIndexStore {
    let url: URL
    private(set) var items: [NiKLibraryItem]
    private var baseline: Data?
    init(url: URL) throws {
        self.url = url
        if Self.exists(url) {
            let data = try NiKLibraryIndex.read(url)
            items = try NiKLibraryIndex.decode(data)
            baseline = data
        } else { items = [] }
    }
    func commit(_ updated: [NiKLibraryItem]) throws {
        let data = try NiKLibraryIndex.encode(updated)
        #if os(iOS) || os(macOS)
        var coordinationError: NSError?
        var writeError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forReplacing, error: &coordinationError) { coordinated in
            do { try checkedWrite(data, to: coordinated) } catch { writeError = error }
        }
        if let coordinationError { throw coordinationError }
        if let writeError { throw writeError }
        #else
        try checkedWrite(data, to: url)
        #endif
        baseline = data
        items = updated
    }
    func removeForTrash(_ snapshot: NiKLibraryItem) throws {
        try verifyCurrent()
        if let current = items.first(where: { $0.id == snapshot.id }), current != snapshot {
            throw NiKLibraryIndex.Failure(message: "IPA đã đổi tùy chọn/metadata sau yêu cầu xóa; giữ backup để kiểm tra.")
        }
        try commit(items.filter { $0.id != snapshot.id })
    }
    func restoreFromTrash(_ snapshot: NiKLibraryItem) throws {
        try verifyCurrent()
        if let current = items.first(where: { $0.id == snapshot.id }) {
            guard current.filename == snapshot.filename, current.bundleID == snapshot.bundleID else { throw NiKLibraryIndex.Failure(message: "ID thư viện đang trỏ tới IPA khác; không ghi đè metadata.") }
            return // Preserve newer options/results after a physical rollback.
        }
        try commit([snapshot] + items)
    }
    func verifyCurrent() throws {
        let current = Self.exists(url) ? try NiKLibraryIndex.read(url) : nil
        guard current == baseline else { throw NiKLibraryIndex.Failure(message: "Index thư viện đã đổi bên ngoài; hãy mở lại app để nạp dữ liệu mới.") }
    }
    private func checkedWrite(_ data: Data, to target: URL) throws {
        let current = Self.exists(target) ? try NiKLibraryIndex.read(target) : nil
        guard current == baseline else {
            throw NiKLibraryIndex.Failure(message: "Danh mục thư viện đã đổi bên ngoài. Không ghi đè; hãy mở lại app để nạp phiên bản mới.")
        }
        #if os(iOS)
        try data.write(to: target, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: target, options: .atomic)
        #endif
    }
    private static func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }
}
