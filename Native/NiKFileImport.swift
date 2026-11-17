import Foundation

enum NiKFileImport {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    /// Coordinate File Provider/iCloud reads; never overwrite an existing user file.
    static func copy(_ source: URL, into directory: URL) throws -> URL {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let originalName = source.lastPathComponent
        guard !originalName.isEmpty, originalName != ".", originalName != ".." else { throw Failure(message: "Tên tệp không hợp lệ.") }
        let staged = directory.appendingPathComponent(".import-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staged) }
        var coordinatorError: NSError?
        var readError: Error?
        var copied = false
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinatorError) { readable in
            do {
                let values = try readable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                guard values.isRegularFile == true, values.isSymbolicLink != true else { throw Failure(message: "Hãy chọn một tệp, không phải thư mục hoặc liên kết.") }
                try fm.copyItem(at: readable, to: staged)
                copied = true
            } catch { readError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let readError { throw readError }
        guard copied else { throw Failure(message: "Nhà cung cấp tệp chưa trả về dữ liệu. Hãy tải tệp về máy rồi thử lại.") }
        let stem = (originalName as NSString).deletingPathExtension
        let ext = (originalName as NSString).pathExtension
        for number in 0..<10_000 {
            let name = number == 0 ? originalName : stem + " (\(number))" + (ext.isEmpty ? "" : "." + ext)
            let target = directory.appendingPathComponent(name)
            if fm.fileExists(atPath: target.path) { continue }
            do { try fm.moveItem(at: staged, to: target); return target }
            catch {
                if fm.fileExists(atPath: target.path) { continue }
                throw error
            }
        }
        throw Failure(message: "Có quá nhiều tệp trùng tên.")
    }
}
