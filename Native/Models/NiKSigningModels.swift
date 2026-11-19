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
    var targetDeviceUDID: String = ""
    private(set) var schemaVersion = 1

    init() {}
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, customBundleID, customDisplayName, customVersion, minimumOSVersion
        case enableFileSharing, removeSupportedDevicesRestriction, removeExtensions, weakDylibInjection
        case allowCertificateMismatch, injectedFiles, targetDeviceUDID
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .schemaVersion, in: values, debugDescription: "Unsupported signing options version")
        }
        customBundleID = try values.decodeIfPresent(String.self, forKey: .customBundleID) ?? ""
        customDisplayName = try values.decodeIfPresent(String.self, forKey: .customDisplayName) ?? ""
        customVersion = try values.decodeIfPresent(String.self, forKey: .customVersion) ?? ""
        minimumOSVersion = try values.decodeIfPresent(String.self, forKey: .minimumOSVersion) ?? ""
        enableFileSharing = try values.decodeIfPresent(Bool.self, forKey: .enableFileSharing) ?? false
        removeSupportedDevicesRestriction = try values.decodeIfPresent(Bool.self, forKey: .removeSupportedDevicesRestriction) ?? false
        removeExtensions = try values.decodeIfPresent(Bool.self, forKey: .removeExtensions) ?? false
        weakDylibInjection = try values.decodeIfPresent(Bool.self, forKey: .weakDylibInjection) ?? false
        allowCertificateMismatch = try values.decodeIfPresent(Bool.self, forKey: .allowCertificateMismatch) ?? false
        injectedFiles = try values.decodeIfPresent([URL].self, forKey: .injectedFiles) ?? []
        targetDeviceUDID = try values.decodeIfPresent(String.self, forKey: .targetDeviceUDID) ?? ""
    }
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
    var warnings: [String]? = nil
}

