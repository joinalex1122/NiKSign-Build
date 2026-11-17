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

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate < Date()
    }

    var daysRemaining: Int? {
        guard let expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
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

