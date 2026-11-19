import Foundation

struct NiKSignedApp: Identifiable, Sendable {
    var id: URL { url }
    let url: URL
    let title: String
    let bundleID: String?
    let version: String?
    let size: Int64
    let modified: Date
    let issue: String?
}

/// Signed files are the source of truth, independent of signing queue history.
enum NiKSignedApps {
    static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Signed", isDirectory: true)
    }
    static func scan(directory: URL = directory) throws -> [NiKSignedApp] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: directory.path) else { return [] }
        let files = try fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey], options: [.skipsHiddenFiles])
        guard files.count <= 5000 else { throw NiKInstallMetadata.Failure(message: "Thư mục Signed có quá nhiều tệp. Hãy dọn bớt trong mục Tệp.") }
        var result: [NiKSignedApp] = []
        for url in files {
            try Task.checkCancellation()
            guard NiKSignedFileAccess.available(url.path, directory: directory) != nil else { continue }
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            let metadata: NiKInstallMetadata?
            let issue: String?
            do { metadata = try NiKInstallMetadata.read(url, validateArchive: false); issue = nil }
            catch is CancellationError { throw CancellationError() }
            catch { metadata = nil; issue = error.localizedDescription }
            result.append(NiKSignedApp(url: url, title: metadata?.title ?? url.deletingPathExtension().lastPathComponent,
                bundleID: metadata?.bundleID, version: metadata?.version,
                size: Int64(values.fileSize ?? 0), modified: values.contentModificationDate ?? .distantPast, issue: issue))
        }
        return result.sorted { $0.modified == $1.modified ? $0.url.lastPathComponent < $1.url.lastPathComponent : $0.modified > $1.modified }
    }
}
