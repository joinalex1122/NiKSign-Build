import Foundation

struct NiKLibraryItem: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    var version: String
    var bundleID: String
    var filename: String
    var certificateID: UUID?
    var options = NiKSigningOptions()
    var signedPath: String?
    var signedBundleID: String?
    var signedVersion: String?
    var signedDisplayName: String?
}

