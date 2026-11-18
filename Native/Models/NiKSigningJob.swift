import Foundation

enum NiKSigningJobState: String, Codable, Sendable {
    case queued, checking, signing, packaging, succeeded, failed, cancelled, interrupted
    var isActive: Bool { self == .checking || self == .signing || self == .packaging }
    var isTerminal: Bool { !isActive && self != .queued }
}

struct NiKSigningJob: Codable, Identifiable, Sendable {
    let id: UUID
    let libraryID: UUID
    let title: String
    let input: URL
    let certificateID: UUID
    let options: NiKSigningOptions
    let createdAt: Date
    var updatedAt: Date
    var state: NiKSigningJobState
    var fraction: Double
    var step: String
    var error: String?
    var output: NiKSignedArtifact?

    init(libraryID: UUID, title: String, input: URL, certificateID: UUID, options: NiKSigningOptions) {
        id = UUID(); self.libraryID = libraryID; self.title = title; self.input = input
        self.certificateID = certificateID; self.options = options
        createdAt = Date(); updatedAt = createdAt; state = .queued; fraction = 0; step = ""
    }
}

/// The caller serializes access. Commit the journal before publishing any UI changes.
final class NiKSigningJobJournal {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    private struct Document: Codable { let version: Int; let jobs: [NiKSigningJob] }
    let url: URL
    private(set) var jobs: [NiKSigningJob]

    init(url: URL) throws {
        self.url = url
        let fm = FileManager.default
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: url.path) {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 16 * 1_048_576 else {
                throw Failure(message: "Nhật ký ký không hợp lệ hoặc vượt 16 MB.")
            }
            let document = try JSONDecoder().decode(Document.self, from: Data(contentsOf: url))
            guard document.version == 1, Set(document.jobs.map(\.id)).count == document.jobs.count else {
                throw Failure(message: "Phiên bản nhật ký không hỗ trợ hoặc có ID trùng.")
            }
            jobs = document.jobs
        } else { jobs = [] }
        let needsRecovery = jobs.contains { $0.state.isActive }
        var recovered = jobs
        for index in recovered.indices where recovered[index].state.isActive {
            recovered[index].state = .interrupted
            recovered[index].updatedAt = Date()
            recovered[index].step = "Công việc bị gián đoạn. Có thể thử lại từ bản gốc."
        }
        if needsRecovery { try commit(recovered) }
    }

    func append(_ batch: [NiKSigningJob]) throws {
        guard !batch.isEmpty else { return }
        let all = jobs + batch
        guard all.count <= 5_000, Set(all.map(\.id)).count == all.count else {
            throw Failure(message: "Hàng đợi quá lớn hoặc công việc bị trùng ID.")
        }
        try commit(all)
    }

    func replace(_ job: NiKSigningJob) throws {
        guard let index = jobs.firstIndex(where: { $0.id == job.id }) else {
            throw Failure(message: "Không tìm thấy công việc trong nhật ký.")
        }
        var updated = jobs
        updated[index] = job
        try commit(updated)
    }

    func removeFinished(_ ids: Set<UUID>) throws {
        guard !jobs.contains(where: { ids.contains($0.id) && !$0.state.isTerminal }) else {
            throw Failure(message: "Không thể xóa công việc đang chờ hoặc đang chạy.")
        }
        try commit(jobs.filter { !ids.contains($0.id) })
    }

    private func commit(_ updated: [NiKSigningJob]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(Document(version: 1, jobs: updated))
        guard data.count <= 16 * 1_048_576 else { throw Failure(message: "Nhật ký vượt 16 MB.") }
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        jobs = updated
    }
}
