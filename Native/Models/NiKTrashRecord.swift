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
        return .init(device: device.uint64Value, inode: inode.uint64Value, isDirectory: type == .typeDirectory)
    }
}
struct NiKTrashRecord: Codable, Identifiable, Sendable {
    enum State: String, Codable, Sendable {
        case trashPrepared, trashed, restorePrepared, restoredNeedsIndex, restored
        case purgePrepared, purged, aborted, missing, needsReview
    }
    let id: UUID
    let original: NiKFileLocation
    let identity: NiKTrashIdentity
    let bytes: UInt64
    let createdAt: Date
    var updatedAt: Date
    var state: State
    let libraryItem: NiKLibraryItem?
}
