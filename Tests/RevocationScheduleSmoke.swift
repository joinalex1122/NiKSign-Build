import Foundation
@main struct RevocationScheduleSmoke {
    static func main() {
        let now = Date(timeIntervalSince1970: 100000)
        precondition(NiKRevocationSchedule.isDue(status: nil, checkedAt: nil, attemptedAt: nil, now: now))
        precondition(!NiKRevocationSchedule.isDue(status: nil, checkedAt: nil, attemptedAt: now, now: now))
        precondition(!NiKRevocationSchedule.isDue(status: .good, checkedAt: now.addingTimeInterval(-3600), attemptedAt: nil, now: now))
        precondition(NiKRevocationSchedule.isDue(status: .good, checkedAt: now.addingTimeInterval(-21600), attemptedAt: nil, now: now))
        precondition(NiKRevocationSchedule.isDue(status: .unknown, checkedAt: now.addingTimeInterval(-900), attemptedAt: nil, now: now))
        precondition(!NiKRevocationSchedule.isDue(status: .revoked, checkedAt: now.addingTimeInterval(-21600), attemptedAt: nil, now: now))
        print("PASS: OCSP initial check, good/unknown/revoked intervals and offline retry backoff")
    }
}
