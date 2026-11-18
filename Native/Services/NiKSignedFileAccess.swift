import Foundation

enum NiKSignedFileAccess {
    static func available(_ path: String?, directory: URL? = nil) -> URL? {
        guard let path else { return nil }
        let root = (directory ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Signed")).standardizedFileURL.resolvingSymlinksInPath()
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let canonical = url.resolvingSymlinksInPath()
        guard canonical.path.hasPrefix(root.path + "/"), canonical.pathExtension.lowercased() == "ipa",
              let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]),
              values.isRegularFile == true, values.isSymbolicLink != true else { return nil }
        return url
    }
}
