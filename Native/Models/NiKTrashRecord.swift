import Foundation

struct NiKTrashIdentity: Codable, Equatable, Sendable {
    let device: UInt64
    let inode: UInt64
    let isDirectory: Bool
    static func read(_ url: URL) throws -> Self {
        let values = try FileManager.default.attributesOfItem(atPath: url.path)
        let type = values[.type] as? FileAttributeType
        guard type == .typeRegular || type == .typeDirectory,
              let device = values[.systemNumber] as? NSNumber,
              let inode = values[.systemFileNumber] as? NSNumber else {
            throw NiKFileBrowserState.Failure(message: "Không nhận diện được tệp/thư mục thường; không theo symlink.")
        }
        if type == .typeRegular {
            guard let links = values[.referenceCount] as? NSNumber, links.uint64Value == 1 else {
                throw NiKFileBrowserState.Failure(message: "Tệp có nhiều liên kết cứng hoặc chưa xác định được ownership; hãy tạo bản sao riêng trước.")
            }
        }
        return .init(device: device.uint64Value, inode: inode.uint64Value, isDirectory: type == .typeDirectory)
    }
}
struct NiKTrashRecord: Codable, Identifiable, Sendable {
    enum State: String, Codable, Sendable {
        case trashPrepared, trashedNeedsIndex, trashed, restorePrepared, restoredNeedsIndex, restored
        case purgePrepared, purged, aborted, missing, needsReview
    }
    enum Action: String, Codable, Sendable { case trash, restore, purge }
    let id: UUID
    let original: NiKFileLocation
    let identity: NiKTrashIdentity
    let bytes: UInt64
    let createdAt: Date
    var updatedAt: Date
    var state: State
    var pendingAction: Action? = nil
    let libraryItem: NiKLibraryItem?
}
