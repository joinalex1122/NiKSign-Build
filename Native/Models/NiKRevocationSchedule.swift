import Foundation

enum NiKRevocationSchedule {
    static func isDue(status: NiKCertificateProfile.RevocationStatus?, checkedAt: Date?, attemptedAt: Date?, now: Date) -> Bool {
        // Failed/offline attempts are retried after 15 minutes, never on every UI refresh.
        if let attemptedAt, now.timeIntervalSince(attemptedAt) < 900 { return false }
        guard let checkedAt else { return true }
        let interval: TimeInterval = status == .good ? 6 * 3600 : status == .revoked ? 24 * 3600 : 900
        return now.timeIntervalSince(checkedAt) >= interval
    }
}
