import Foundation

struct NiKSigningOptions: Sendable, Codable, Equatable {
    var customBundleID: String = ""
    var customDisplayName: String = ""
    var customVersion: String = ""
    var minimumOSVersion: String = ""
    var enableFileSharing: Bool = false
    var removeSupportedDevicesRestriction: Bool = false
    var removeExtensions: Bool = false
    var weakDylibInjection: Bool = false
    var allowCertificateMismatch: Bool = false
    var injectedFiles: [URL] = []
}

struct NiKSigningProgress: Sendable {
    let step: Int
    let totalSteps: Int
    let fraction: Double
    let description: String
}

struct NiKSignedArtifact: Sendable, Codable, Equatable {
    let ipaURL: URL
    let bundleID: String
    let displayName: String
    let version: String
    let injectedDylibs: [String]
    let certificateSummary: String
    let teamName: String
}

