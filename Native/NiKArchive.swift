import Foundation
import ZIPFoundation

/// Extract into a private staging directory, then publish a complete folder without overwriting.
enum NiKArchive {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func extract(_ source: URL, to destination: URL,
                        limit: UInt64 = 1_073_741_824, entryLimit: Int = 50_000) throws {
        let fm = FileManager.default
        guard !fm.fileExists(atPath: destination.path) else {
            throw Failure(message: "Thư mục đích đã tồn tại. Hãy đổi tên hoặc chọn vị trí khác.")
        }
        let archive = try Archive(url: source, accessMode: .read)
        var total: UInt64 = 0
        var paths = Set<String>()
        for entry in archive {
            let path = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains("\0"),
                  !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  entry.type != .symlink,
                  paths.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw Failure(message: "ZIP chứa đường dẫn không an toàn, trùng tên hoặc liên kết.")
            }
            guard paths.count <= entryLimit, entry.uncompressedSize <= limit - total else {
                throw Failure(message: "ZIP vượt giới hạn số tệp hoặc dung lượng giải nén.")
            }
            total += entry.uncompressedSize
        }
        let stage = destination.deletingLastPathComponent().appendingPathComponent(".unzip-" + UUID().uuidString)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        var written: UInt64 = 0
        for entry in archive {
            let target = stage.appendingPathComponent(entry.path)
            if entry.type == .directory {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard fm.createFile(atPath: target.path, contents: nil) else {
                throw Failure(message: "Không tạo được tệp giải nén.")
            }
            let handle = try FileHandle(forWritingTo: target)
            defer { try? handle.close() }
            var entryBytes: UInt64 = 0
            let crc = try archive.extract(entry) { chunk in
                let size = UInt64(chunk.count)
                guard size <= limit - written, size <= entry.uncompressedSize - entryBytes else {
                    throw Failure(message: "Dữ liệu ZIP vượt kích thước đã khai báo.")
                }
                written += size
                entryBytes += size
                try handle.write(contentsOf: chunk)
            }
            guard crc == entry.checksum, entryBytes == entry.uncompressedSize else {
                throw Failure(message: "ZIP bị hỏng (CRC hoặc kích thước không khớp).")
            }
        }
        try fm.moveItem(at: stage, to: destination)
    }
}

enum NiKFileOperations {
    static func child(named name: String, in directory: URL) throws -> URL {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/"),
              !name.contains("\\"), !name.contains("\0") else {
            throw NiKArchive.Failure(message: "Tên không hợp lệ. Không dùng /, \\, . hoặc ..")
        }
        return directory.appendingPathComponent(name)
    }

    static func transfer(_ source: URL, into directory: URL, copy: Bool) throws {
        let fm = FileManager.default
        let source = source.resolvingSymlinksInPath().standardizedFileURL
        let directory = directory.resolvingSymlinksInPath().standardizedFileURL
        guard directory.path != source.path, !directory.path.hasPrefix(source.path + "/") else {
            throw NiKArchive.Failure(message: "Không thể đặt thư mục vào chính nó hoặc thư mục con của nó.")
        }
        let destination = try child(named: source.lastPathComponent, in: directory)
        guard !fm.fileExists(atPath: destination.path) else {
            throw NiKArchive.Failure(message: "Đích đã có tệp cùng tên.")
        }
        if copy {
            let stage = directory.appendingPathComponent(".copy-" + UUID().uuidString)
            defer { try? fm.removeItem(at: stage) }
            try fm.copyItem(at: source, to: stage)
            try fm.moveItem(at: stage, to: destination)
        } else {
            try fm.moveItem(at: source, to: destination)
        }
    }
}
