import Foundation

struct NiKFileRecoveryRecord: Codable, Identifiable, Sendable {
    enum State: String, Codable, Sendable { case prepared, committed, aborted, restored, restoreFailed, needsReview }
    let id: UUID
    let target: URL
    let originalDigest: String
    let replacementDigest: String
    let originalSize: Int
    var originalPermissions: Int?
    let createdAt: Date
    var updatedAt: Date
    var state: State
    var message: String?
}

struct NiKEditableFileSnapshot: Sendable {
    let url: URL
    let data: Data
    let digest: String
}
