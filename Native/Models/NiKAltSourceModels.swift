import Foundation

struct NiKAltSourceApp: Identifiable, Hashable, Sendable {
    var id: String { "\(sourceURL.absoluteString)#\(bundleIdentifier)#\(version)" }
    let name: String
    let bundleIdentifier: String
    let developerName: String
    let version: String
    let versionDate: String?
    let sizeBytes: Int64?
    let downloadURL: URL
    let iconURL: URL?
    let localizedDescription: String
    let sourceName: String
    let sourceURL: URL
    let sha256: String?
}

struct NiKAltSourceFeed: Codable, Sendable {
    struct AppEntry: Codable, Sendable {
        struct VersionEntry: Codable, Sendable {
            let sha256: String?
            let version: String?
            let date: String?
            let size: Int64?
            let downloadURL: URL?
            let localizedDescription: String?
        }
        let sha256: String?
        let name: String?
        let bundleIdentifier: String?
        let developerName: String?
        let version: String?
        let versionDate: String?
        let size: Int64?
        let downloadURL: URL?
        let iconURL: URL?
        let localizedDescription: String?
        let subtitle: String?
        let versions: [VersionEntry]?
    }
    let name: String?
    let subtitle: String?
    let description: String?
    let apps: [AppEntry]?
}

