import Foundation
import Combine

@MainActor final class NiKSigningQueue: ObservableObject {
    static let shared = NiKSigningQueue()
    @Published private(set) var jobs: [NiKSigningJob] = []
    @Published private(set) var isRunning = false
    @Published private(set) var cancellationRequests: Set<UUID> = []
    @Published var message: String?
    private var journal: NiKSigningJobJournal?
    private var worker: Task<Void, Never>?
    private var activeTask: Task<NiKSignedArtifact, Error>?
    private var activeID: UUID?

    init() {
        do {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            journal = try NiKSigningJobJournal(url: support.appendingPathComponent("NiKSign/Jobs/index.json"))
            jobs = journal?.jobs ?? []
        } catch { message = error.localizedDescription }
    }

    func enqueue(_ batch: [NiKSigningJob]) throws {
        guard let journal else { throw NiKError("Không mở được nhật ký công việc. Giữ nguyên tệp để kiểm tra/khôi phục.") }
        guard !batch.contains(where: { job in jobs.contains(where: { $0.libraryID == job.libraryID && !$0.state.isTerminal }) }) else {
            throw NiKError("IPA này đã có công việc đang chờ/chạy.")
        }
        try journal.append(batch)
        jobs = journal.jobs
        start()
    }

    func start() {
        guard worker == nil, journal != nil else { return }
        worker = Task { [weak self] in
            guard let self else { return }
            self.isRunning = true
            defer { self.isRunning = false; self.worker = nil }
            while let next = self.jobs.first(where: { $0.state == .queued }) {
                if !(await self.run(next)) { break }
            }
        }
    }

    func cancel(_ id: UUID) {
        guard var job = jobs.first(where: { $0.id == id }), !job.state.isTerminal else { return }
        if activeID == id {
            cancellationRequests.insert(id)
            activeTask?.cancel()
            return // Keep the operation active until its native call reaches a safe boundary.
        }
        job.state = .cancelled; job.updatedAt = Date(); job.step = "Đã hủy"
        do { try persist(job) } catch { message = error.localizedDescription }
    }

    func retry(_ id: UUID) {
        guard let old = jobs.first(where: { $0.id == id }), [.failed, .cancelled, .interrupted].contains(old.state) else { return }
        let newJob = NiKSigningJob(libraryID: old.libraryID, title: old.title, input: old.input, certificateID: old.certificateID, options: old.options)
        do { try enqueue([newJob]) } catch { message = error.localizedDescription }
    }

    func clearFinished() {
        do {
            guard let journal else { return }
            try journal.removeFinished(Set(jobs.filter { $0.state.isTerminal }.map(\.id)))
            jobs = journal.jobs
        } catch { message = error.localizedDescription }
    }

    private func persist(_ job: NiKSigningJob) throws {
        guard let journal else { throw NiKError("Nhật ký chưa sẵn sàng.") }
        try journal.replace(job)
        jobs = journal.jobs
    }

    private func updateProgress(_ progress: NiKSigningProgress, id: UUID) {
        guard activeID == id, var job = jobs.first(where: { $0.id == id }), job.state.isActive else { return }
        job.fraction = progress.fraction; job.step = progress.description; job.updatedAt = Date()
        job.state = progress.step <= 1 ? .checking : progress.step >= 6 ? .packaging : .signing
        do { try persist(job) }
        catch {
            message = error.localizedDescription
            cancellationRequests.insert(id)
            activeTask?.cancel()
        }
    }

    private func run(_ initial: NiKSigningJob) async -> Bool {
        var job = initial
        job.state = .checking; job.updatedAt = Date()
        do { try persist(job) } catch { message = error.localizedDescription; return false }
        activeID = job.id
        defer { activeID = nil; activeTask = nil; cancellationRequests.remove(job.id) }
        do {
            guard let cert = NiKCertificateStore.shared.profiles.first(where: { $0.id == job.certificateID }) else {
                throw NiKError("Chứng chỉ của công việc không còn tồn tại. Không tự thay bằng chứng chỉ khác.")
            }
            let credentials = try NiKCertificateStore.shared.credentials(for: cert)
            let jobID = job.id, input = job.input, options = job.options
            activeTask = Task {
                try await SigningService.shared.signDetailed(ipa: input, p12: credentials.p12,
                    profile: credentials.provision, password: credentials.password, options: options,
                    onProgress: { progress in Task { @MainActor [weak self] in self?.updateProgress(progress, id: jobID) } })
            }
            guard let task = activeTask else { throw CancellationError() }
            let output = try await task.value
            job.output = output
            if cancellationRequests.contains(job.id) {
                try FileManager.default.removeItem(at: output.ipaURL)
                job.output = nil
                throw CancellationError()
            }
            job.state = .succeeded; job.fraction = 1; job.step = "Đã ký và kiểm tra cấu trúc đầu ra"
            job.updatedAt = Date()
            try persist(job)
            if var item = NiKLibrary.shared.items.first(where: { $0.id == job.libraryID }) {
                item.signedPath = output.ipaURL.path
                item.signedBundleID = output.bundleID; item.signedVersion = output.version; item.signedDisplayName = output.displayName
                if !NiKLibrary.shared.save(item) { message = NiKLibrary.shared.error }
            }
            return true
        } catch {
            job.state = error is CancellationError ? .cancelled : .failed
            job.error = error is CancellationError ? nil : error.localizedDescription
            job.step = error is CancellationError ? "Đã hủy tại điểm an toàn" : "Công việc thất bại"
            job.updatedAt = Date()
            do { try persist(job); return true }
            catch { message = "Không ghi được kết quả công việc. Nhật ký giữ trạng thái để khôi phục: " + error.localizedDescription; return false }
        }
    }
}
