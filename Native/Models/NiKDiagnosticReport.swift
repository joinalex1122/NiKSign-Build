import Foundation

/// Export an allowlist of operational facts. Never serialize a job, credential,
/// recovery record, raw error, file name, URL or log message into this report.
struct NiKDiagnosticReport: Codable, Sendable {
    struct Job: Codable, Sendable {
        let position: Int
        let state: NiKSigningJobState
        let progressPercent: Int
        let elapsedSeconds: Int
        let hasOutput: Bool
        let hasError: Bool
    }
    let schemaVersion: Int
    let generatedAt: Date
    let appVersion: String
    let appBuild: String
    let systemVersion: String
    let jobCounts: [String: Int]
    let jobs: [Job]
    let omittedJobs: Int
    let recoveryCounts: [String: Int]
    let signingStorageAvailable: Bool
    let recoveryStorageAvailable: Bool
    let certificateStorageAvailable: Bool
    let limitations: [String]

    static func make(jobs allJobs: [NiKSigningJob], recovery: [NiKFileRecoveryRecord],
                     appVersion: String, appBuild: String, systemVersion: String,
                     signingStorageAvailable: Bool = false, recoveryStorageAvailable: Bool = false, certificateStorageAvailable: Bool = false,
                     now: Date = Date()) -> Self {
        let selected = allJobs.suffix(1_000)
        var jobCounts: [String: Int] = [:]
        for job in allJobs { jobCounts[job.state.rawValue, default: 0] += 1 }
        var recoveryCounts: [String: Int] = [:]
        for record in recovery { recoveryCounts[record.state.rawValue, default: 0] += 1 }
        let details = selected.enumerated().map { index, job in
            let fraction = job.fraction.isFinite ? min(1, max(0, job.fraction)) : 0
            let elapsed = job.updatedAt.timeIntervalSince(job.createdAt)
            return Job(position: index + 1, state: job.state, progressPercent: Int((fraction * 100).rounded()),
                       elapsedSeconds: elapsed.isFinite ? Int(min(31_536_000, max(0, elapsed))) : 0,
                       hasOutput: job.output != nil, hasError: job.error != nil)
        }
        return .init(schemaVersion: 1, generatedAt: now,
                     appVersion: safeVersion(appVersion), appBuild: safeVersion(appBuild),
                     systemVersion: safeVersion(systemVersion), jobCounts: jobCounts, jobs: details,
                     omittedJobs: max(0, allJobs.count - selected.count), recoveryCounts: recoveryCounts,
                     signingStorageAvailable: signingStorageAvailable, recoveryStorageAvailable: recoveryStorageAvailable,
                     certificateStorageAvailable: certificateStorageAvailable,
                     limitations: [
                        "Contains status summaries only; raw errors, names, paths, IDs, URLs, UDIDs and credentials are excluded.",
                        "Reports local application state; does not prove Apple signature trust, installation or system access.",
                        "Counts are loaded snapshots; check storage availability flags before interpreting empty history.",
                        "Build audit results must be obtained from the matching GitHub Actions commit."
                     ])
    }
    private static func safeVersion(_ value: String) -> String {
        guard value.count <= 40, value.range(of: #"^[0-9]+(?:[.][0-9]+)*$"#, options: .regularExpression) != nil else { return "unknown" }
        return value
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}
