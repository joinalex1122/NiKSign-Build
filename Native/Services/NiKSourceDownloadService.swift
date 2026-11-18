import Foundation

struct NiKDownloadedIPA: Sendable {
    let url: URL
    let stagingDirectory: URL
    let sha256: String
    func discard() throws { try FileManager.default.removeItem(at: stagingDirectory) }
}

enum NiKSourceDownloadService {
    static func parseFeed(data: Data, sourceURL: URL) throws -> [NiKAltSourceApp] {
        try NiKHTTPDownload.validate(sourceURL)
        guard data.count <= 16 * 1_048_576 else { throw NiKHTTPDownload.Failure(message: "JSON nguồn vượt 16 MB.") }
        let feed = try JSONDecoder().decode(NiKAltSourceFeed.self, from: data)
        guard let entries = feed.apps, entries.count <= 5_000 else { throw NiKHTTPDownload.Failure(message: "Nguồn cần mảng apps và tối đa 5.000 ứng dụng.") }
        let sourceTitle = feed.name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = sourceTitle?.isEmpty == false ? sourceTitle! : sourceURL.host ?? "AltSource"
        var result: [NiKAltSourceApp] = []
        var identifiers = Set<String>()
        for entry in entries {
            guard let appName = entry.name, !appName.isEmpty, let bundle = entry.bundleIdentifier, !bundle.isEmpty else { continue }
            guard appName.count <= 4_096, bundle.count <= 512, (entry.versions?.count ?? 0) <= 1_000 else {
                throw NiKHTTPDownload.Failure(message: "Metadata nguồn vượt giới hạn.")
            }
            let latest = entry.versions?.first
            guard let candidate = latest?.downloadURL ?? entry.downloadURL,
                  let downloadURL = URL(string: candidate.relativeString, relativeTo: sourceURL)?.absoluteURL else { continue }
            try NiKHTTPDownload.validate(downloadURL)
            let version = latest?.version ?? entry.version ?? "1.0"
            let hash = try normalizedHash(latest?.sha256 ?? entry.sha256)
            let size = latest?.size ?? entry.size
            guard version.count <= 128, size == nil || size! >= 0 else { throw NiKHTTPDownload.Failure(message: "Phiên bản/dung lượng nguồn không hợp lệ.") }
            let id = sourceURL.absoluteString + "#" + bundle + "#" + version
            guard identifiers.insert(id).inserted else { throw NiKHTTPDownload.Failure(message: "Nguồn có ứng dụng trùng Bundle ID và phiên bản.") }
            result.append(.init(name: appName, bundleIdentifier: bundle, developerName: entry.developerName ?? title,
                version: version, versionDate: latest?.date ?? entry.versionDate, sizeBytes: size,
                downloadURL: downloadURL, iconURL: entry.iconURL,
                localizedDescription: latest?.localizedDescription ?? entry.localizedDescription ?? entry.subtitle ?? "",
                sourceName: title, sourceURL: sourceURL, sha256: hash))
        }
        return result
    }
    static func normalizedHash(_ input: String?) throws -> String? {
        guard let input else { return nil }
        let hash = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard hash.utf8.count == 64, hash.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw NiKHTTPDownload.Failure(message: "SHA-256 nguồn phải có đúng 64 ký tự hex.")
        }
        return hash
    }
    static func fetchFeed(_ url: URL) async throws -> [NiKAltSourceApp] {
        let receipt = try await NiKHTTPDownload.download(url, limit: 16 * 1_048_576, timeout: 30)
        defer { try? receipt.discard() }
        try Task.checkCancellation()
        let data = try Data(contentsOf: receipt.url)
        return try parseFeed(data: data, sourceURL: url)
    }
    static func downloadIPA(_ url: URL, expectedSHA256: String?,
                            progress: @escaping @Sendable (NiKHTTPDownload.Progress) -> Void = { _ in }) async throws -> NiKDownloadedIPA {
        let expected = try normalizedHash(expectedSHA256)
        let receipt = try await NiKHTTPDownload.download(url, limit: 1_073_741_824, timeout: 300, progress: progress)
        do {
            try Task.checkCancellation()
            let hashing = Task.detached { try NiKFileDigest.sha256(file: receipt.url) }
            let digest = try await withTaskCancellationHandler(operation: { try await hashing.value }, onCancel: { hashing.cancel() })
            try Task.checkCancellation()
            if let expected, expected != digest { throw NiKHTTPDownload.Failure(message: "SHA-256 không khớp nguồn; không nhập IPA.") }
            let destination = receipt.directory.appendingPathComponent(UUID().uuidString + ".ipa")
            try FileManager.default.moveItem(at: receipt.url, to: destination)
            return .init(url: destination, stagingDirectory: receipt.directory, sha256: digest)
        } catch { try? receipt.discard(); throw error }
    }
}
