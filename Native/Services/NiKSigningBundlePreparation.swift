import Foundation

/// All edits/removals happen before native signing and resource sealing.
enum NiKSigningBundlePreparation {
    struct CodeBundle { let url: URL; let executable: URL; let identifier: String }
    static func codeBundles(in app: URL) throws -> [CodeBundle] {
        let fm = FileManager.default
        var urls = [app]
        if let walker = fm.enumerator(at: app, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]) {
            for case let url as URL in walker {
                if url.pathExtension == "dSYM" { walker.skipDescendants(); continue }
                let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isDirectory == true, values.isSymbolicLink != true, ["app", "appex", "framework", "xctest"].contains(url.pathExtension) { urls.append(url) }
            }
        }
        return try urls.map { url in
            let base = url.resolvingSymlinksInPath().path + "/"
            let plistURL = url.appendingPathComponent("Info.plist").resolvingSymlinksInPath()
            guard plistURL.path.hasPrefix(base), (try plistURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= 1_048_576,
                  let info = try PropertyListSerialization.propertyList(from: Data(contentsOf: plistURL), format: nil) as? [String: Any],
                  let identifier = info["CFBundleIdentifier"] as? String,
                  let name = info["CFBundleExecutable"] as? String, !name.isEmpty, !name.contains("/"), !name.contains("\\"), name != ".", name != ".." else { throw NiKProvisioningValidation.Failure(message: "Metadata/executable bundle không hợp lệ: " + url.lastPathComponent) }
            _ = try NiKPathValidator.canonicalBundleIdentifier(identifier)
            _ = try NiKPathValidator.canonicalRelativePath(name)
            let executable = url.appendingPathComponent(name).resolvingSymlinksInPath()
            guard executable.path.hasPrefix(base), try executable.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { throw NiKProvisioningValidation.Failure(message: "Executable phải nằm trong chính bundle: " + url.lastPathComponent) }
            return CodeBundle(url: url, executable: executable, identifier: identifier)
        }
    }
    static func prepare(app: URL, oldID: String, newID: String, profilePattern: String, removeAll: Bool, buildVersion: String? = nil, shortVersion: String? = nil) throws -> [String] {
        let fm = FileManager.default
        var warnings: [String] = []
        // This single iPhone profile cannot provision the companion WatchOS app.
        for name in ["Watch", "WatchKit", "com.apple.WatchPlaceholder", "AppClips"] {
            let path = app.appendingPathComponent(name)
            if fm.fileExists(atPath: path.path) { try fm.removeItem(at: path); warnings.append("Đã gỡ \(name): cần profile riêng cho bundle phụ.") }
        }
        for folder in ["PlugIns", "Extensions"] {
            let path = app.appendingPathComponent(folder)
            guard fm.fileExists(atPath: path.path) else { continue }
            if removeAll { try fm.removeItem(at: path); warnings.append("Đã gỡ \(folder) theo tùy chọn."); continue }
            for bundle in try fm.contentsOfDirectory(at: path, includingPropertiesForKeys: nil) where bundle.pathExtension == "appex" {
                let infoURL = bundle.appendingPathComponent("Info.plist")
                let data = try Data(contentsOf: infoURL)
                guard var info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                      let original = info["CFBundleIdentifier"] as? String else { throw NiKProvisioningValidation.Failure(message: "Extension thiếu Bundle ID: " + bundle.lastPathComponent) }
                let id = original.hasPrefix(oldID + ".") ? newID + String(original.dropFirst(oldID.count)) : original
                let platforms = info["CFBundleSupportedPlatforms"] as? [String]
                let platformMatches = platforms == nil || platforms!.contains("iPhoneOS")
                guard platformMatches, id.hasPrefix(newID + "."), NiKProvisioningValidation.bundleMatches(pattern: profilePattern, bundleID: id) else {
                    try fm.removeItem(at: bundle)
                    warnings.append("Đã gỡ \(bundle.lastPathComponent): profile đơn hoặc nền tảng không hỗ trợ \(id).")
                    continue
                }
                info["CFBundleIdentifier"] = id
                if let buildVersion { info["CFBundleVersion"] = buildVersion }
                if let shortVersion { info["CFBundleShortVersionString"] = shortVersion }
                try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: infoURL, options: .atomic)
            }
        }
        return warnings
    }
}
