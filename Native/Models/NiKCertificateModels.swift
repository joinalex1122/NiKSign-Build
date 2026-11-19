import Foundation

struct NiKCertificateProfile: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var certSummary: String
    var teamName: String
    var teamID: String
    var appIDName: String
    var bundleIDPattern: String
    var creationDate: Date?
    var expirationDate: Date?
    var provisionedUDIDs: [String]
    var certMatchesProvision: Bool
    var sha1Fingerprint: String
    var p12Filename: String
    var provisionFilename: String
    var createdAt: Date
    var certificateExpirationDate: Date?
    var certificateCreationDate: Date?
    var provisionsAllDevices: Bool?
    var allowsDebugging: Bool?
    var entitlements: [String: NiKPlistValue]?

    enum RevocationStatus: String, Codable, Sendable { case good, revoked, unknown }
    var revocationStatus: RevocationStatus?
    var revocationCheckedAt: Date?

    var isKnownRevoked: Bool { revocationStatus == .revoked }
    var effectiveExpirationDate: Date? {
        [expirationDate, certificateExpirationDate].compactMap { $0 }.min()
    }
    func remainingSeconds(at now: Date) -> TimeInterval? {
        effectiveExpirationDate.map { max(0, $0.timeIntervalSince(now)) }
    }
    func freshRevocationStatus(at now: Date) -> RevocationStatus {
        if isKnownRevoked { return .revoked }
        guard let checked = revocationCheckedAt, now >= checked,
              now.timeIntervalSince(checked) < 86400 else { return .unknown }
        return revocationStatus ?? .unknown
    }

    var isExpired: Bool {
        guard let effectiveExpirationDate else { return false }
        return effectiveExpirationDate <= Date()
    }

    var daysRemaining: Int? {
        guard let seconds = remainingSeconds(at: Date()) else { return nil }
        return Int(ceil(seconds / 86400))
    }
}

struct NiKProvisionMetadata: Sendable {
    let name: String
    let teamName: String
    let teamID: String
    let appIDName: String
    let bundleIDPattern: String
    let creationDate: Date?
    let expirationDate: Date?
    let provisionedUDIDs: [String]
    let developerCertificatesDER: [Data]
    let provisionsAllDevices: Bool
    let allowsDebugging: Bool
    let entitlements: [String: NiKPlistValue]
}

