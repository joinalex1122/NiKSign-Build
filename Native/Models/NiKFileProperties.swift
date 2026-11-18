import Foundation

struct NiKFileProperties: Sendable {
    let name: String
    let isDirectory: Bool
    let size: Int64?
    let modifiedAt: Date?
    let createdAt: Date?
    let permissions: Int?
    let sha256: String?

    static func inspect(_ url: URL, root: URL, hash: Bool, digestLimit: Int64 = 1_073_741_824) throws -> Self {
        _ = try NiKFileLocation.from(url.deletingLastPathComponent(), root: root)
        let before = try FileManager.default.attributesOfItem(atPath: url.path)
        let type = before[.type] as? FileAttributeType
        guard type == .typeRegular || type == .typeDirectory else {
            throw NiKFileBrowserState.Failure(message: "Chỉ xem thuộc tính tệp thường/thư mục; không theo symlink.")
        }
        let directory = type == .typeDirectory
        let size = (before[.size] as? NSNumber)?.int64Value
        var digest: String?
        if hash {
            guard !directory, let size, size >= 0, size <= digestLimit else {
                throw NiKFileBrowserState.Failure(message: "SHA-256 áp dụng cho tệp thường tối đa 1 GB; không băm đệ quy thư mục.")
            }
            digest = try NiKFileDigest.sha256(file: url)
            let after = try FileManager.default.attributesOfItem(atPath: url.path)
            guard before[.size] as? NSNumber == after[.size] as? NSNumber,
                  before[.modificationDate] as? Date == after[.modificationDate] as? Date,
                  before[.systemFileNumber] as? NSNumber == after[.systemFileNumber] as? NSNumber,
                  before[.type] as? FileAttributeType == after[.type] as? FileAttributeType else {
                throw NiKFileBrowserState.Failure(message: "Tệp đã thay đổi trong khi băm; hãy thử lại.")
            }
        }
        return .init(name: url.lastPathComponent, isDirectory: directory, size: directory ? nil : size,
            modifiedAt: before[.modificationDate] as? Date, createdAt: before[.creationDate] as? Date,
            permissions: (before[.posixPermissions] as? NSNumber)?.intValue, sha256: digest)
    }
}
