import Foundation

/// Serve an owned, immutable snapshot: GCDWebServer allows existing responses to
/// drain after its listener stops. Releasing the original file's lease must not
/// allow a later edit to change bytes already being installed by iOS.
struct NiKInstallationPayload: Sendable {
    let directory: URL
    let url: URL
    let metadata: NiKInstallMetadata
    static func prepare(_ source: URL) throws -> Self {
        let fm = FileManager.default
        let directory = fm.temporaryDirectory.appendingPathComponent("NiKSign-Install-" + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var transferred = false
        defer { if !transferred { try? fm.removeItem(at: directory) } }
        try Task.checkCancellation()
        let url = directory.appendingPathComponent("app.ipa")
        try fm.copyItem(at: source, to: url)
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw NiKInstallMetadata.Failure(message: "Bản IPA cài đặt không phải tệp thường.")
        }
        let info = try NiKInstallMetadata.read(url)
        try Task.checkCancellation()
        transferred = true
        return Self(directory: directory, url: url, metadata: info)
    }
    /// Called once at shared controller initialization, before this process can
    /// own a live payload. UIKit's app-private temporary directory is isolated.
    static func recoverAbandoned(in root: URL = FileManager.default.temporaryDirectory) {
        let prefix = "NiKSign-Install-"
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { return }
        for entry in entries {
            guard entry.lastPathComponent.hasPrefix(prefix),
                  UUID(uuidString: String(entry.lastPathComponent.dropFirst(prefix.count))) != nil,
                  let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                  values.isDirectory == true, values.isSymbolicLink != true else { continue }
            try? FileManager.default.removeItem(at: entry)
        }
    }
    func discard() { try? FileManager.default.removeItem(at: directory) }
}
