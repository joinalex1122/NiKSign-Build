import Foundation

@main struct DiagnosticsSmoke {
    static func main() throws {
        let marker = "PRIVATE_SENTINEL_7421"
        var options = NiKSigningOptions()
        options.targetDeviceUDID = marker + "_UDID"
        options.injectedFiles = [URL(fileURLWithPath: "/private/" + marker + ".dylib")]
        var job = NiKSigningJob(libraryID: UUID(), title: marker + "_APP",
            input: URL(fileURLWithPath: "/private/" + marker + ".ipa"), certificateID: UUID(), options: options)
        job.error = marker + "_PASSWORD https://example.test/?token=" + marker
        job.step = marker + "_LOG"
        job.state = .failed
        job.fraction = .nan
        job.updatedAt = job.createdAt.addingTimeInterval(-10)
        let record = NiKFileRecoveryRecord(id: UUID(), target: URL(fileURLWithPath: "/private/" + marker),
            originalDigest: marker + "_DIGEST", replacementDigest: marker, originalSize: 42,
            originalPermissions: nil, createdAt: Date(), updatedAt: Date(), state: .restoreFailed, message: marker)
        let report = NiKDiagnosticReport.make(jobs: [job], recovery: [record], appVersion: "3.3.0",
            appBuild: "330", systemVersion: marker)
        let data = try report.encoded()
        let text = String(decoding: data, as: UTF8.self)
        precondition(!text.contains(marker))
        precondition(!text.contains(job.certificateID.uuidString) && !text.contains(job.libraryID.uuidString))
        precondition(!text.contains(job.id.uuidString) && !text.contains(record.id.uuidString))
        precondition(report.jobs.count == 1 && report.jobs[0].state == .failed)
        precondition(report.jobs[0].hasError && !report.jobs[0].hasOutput)
        precondition(report.jobs[0].progressPercent == 0 && report.jobs[0].elapsedSeconds == 0)
        precondition(report.systemVersion == "unknown")
        precondition(report.jobCounts["failed"] == 1 && report.recoveryCounts["restoreFailed"] == 1)
        job.fraction = 4
        job.updatedAt = job.createdAt.addingTimeInterval(100_000_000)
        let bounded = NiKDiagnosticReport.make(jobs: Array(repeating: job, count: 1_005), recovery: [],
            appVersion: "3.3.0", appBuild: "330", systemVersion: "27.2")
        precondition(bounded.jobs.count == 1_000 && bounded.omittedJobs == 5)
        precondition(bounded.jobs[0].progressPercent == 100 && bounded.jobs[0].elapsedSeconds == 31_536_000)
        _ = try bounded.encoded()
        let decoded = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        precondition(decoded["schemaVersion"] as? Int == 1)
        print("PASS: allowlisted diagnostic export excludes secrets/paths/identifiers/raw errors and bounds invalid progress/durations/report size")
    }
}
