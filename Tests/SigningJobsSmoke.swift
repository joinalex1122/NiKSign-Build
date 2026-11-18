import Foundation

@main struct SigningJobsSmoke {
    static func expectFailure(_ action: () throws -> Void) {
        do { try action() } catch { return }
        fatalError("Expected failure")
    }
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? fm.removeItem(at: root) }
        let url = root.appendingPathComponent("jobs.json")
        let defaults = try JSONDecoder().decode(NiKSigningOptions.self, from: Data("{}".utf8))
        precondition(defaults == NiKSigningOptions())
        expectFailure { _ = try JSONDecoder().decode(NiKSigningOptions.self, from: Data("{\"schemaVersion\":99}".utf8)) }
        let journal = try NiKSigningJobJournal(url: url)
        var options = NiKSigningOptions()
        options.customDisplayName = "Original snapshot"
        let first = NiKSigningJob(libraryID: UUID(), title: "Một IPA", input: root.appendingPathComponent("input.ipa"), certificateID: UUID(), options: options)
        try journal.append([first])
        options.customDisplayName = "Changed after queue"
        precondition(journal.jobs[0].options.customDisplayName == "Original snapshot")
        expectFailure { try journal.append([first]) }
        precondition(journal.jobs.count == 1)
        var running = first
        running.state = .signing
        try journal.replace(running)
        expectFailure { try journal.removeFinished([first.id]) }
        let reopened = try NiKSigningJobJournal(url: url)
        precondition(reopened.jobs[0].state == .interrupted)
        let recoveredAgain = try NiKSigningJobJournal(url: url)
        precondition(recoveredAgain.jobs[0].state == .interrupted)
        let sentinel = root.appendingPathComponent("blocked")
        try Data("preserve".utf8).write(to: sentinel)
        let failedWrite = try NiKSigningJobJournal(url: root.appendingPathComponent("nested/index.json"))
        try fm.removeItem(at: root.appendingPathComponent("nested"))
        try fm.moveItem(at: sentinel, to: root.appendingPathComponent("nested"))
        expectFailure { try failedWrite.append([first]) }
        precondition(failedWrite.jobs.isEmpty)
        try reopened.removeFinished([first.id])
        precondition(reopened.jobs.isEmpty)
        try Data("not json".utf8).write(to: url)
        expectFailure { _ = try NiKSigningJobJournal(url: url) }
        let preserved = try String(contentsOf: url, encoding: .utf8)
        precondition(preserved == "not json")
        let removalURL = root.appendingPathComponent("removal/index.json")
        let removal = try NiKSigningJobJournal(url: removalURL)
        var active = NiKSigningJob(libraryID: UUID(), title: "active", input: root, certificateID: UUID(), options: defaults)
        active.state = .signing; active.fraction = 0.84
        let queued = NiKSigningJob(libraryID: UUID(), title: "queued", input: root, certificateID: UUID(), options: defaults)
        var finished = NiKSigningJob(libraryID: UUID(), title: "finished", input: root, certificateID: UUID(), options: defaults)
        finished.state = .failed
        try removal.append([active, queued, finished])
        try removal.requestRemoval([active.id, queued.id, finished.id])
        precondition(removal.jobs.count == 1 && removal.jobs[0].id == active.id)
        precondition(removal.jobs[0].state == .signing && removal.jobs[0].removalRequested == true && removal.jobs[0].fraction == 0.84)
        expectFailure { try removal.removeFinished([active.id]) }
        // A process restart has no running native call: recover and finish the pending removal.
        let afterRemovalRecovery = try NiKSigningJobJournal(url: removalURL)
        precondition(afterRemovalRecovery.jobs.isEmpty)
        let recoveredRemoval = try NiKSigningJobJournal(url: removalURL)
        precondition(recoveredRemoval.jobs.isEmpty)
        print("PASS: immutable job snapshot, duplicate rejection, interrupted recovery, failed commit leaves state intact, safe history removal and corrupt journal preservation")
    }
}
