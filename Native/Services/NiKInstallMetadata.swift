import Foundation
import ZIPFoundation

struct NiKInstallMetadata: Sendable {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    let bundleID: String
    let version: String
    let title: String
    static func read(_ url: URL) throws -> Self {
        let zip = try Archive(url: url, accessMode: .read)
        let entries = zip.filter { entry in
            let parts = entry.path.split(separator: "/", omittingEmptySubsequences: false)
            return parts.count == 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
        }
        guard entries.count == 1, entries[0].uncompressedSize <= 1_048_576 else { throw Failure(message: "IPA không có đúng một Info.plist ứng dụng hợp lệ.") }
        var data = Data()
        let checksum = try zip.extract(entries[0]) { chunk in
            try Task.checkCancellation()
            guard data.count + chunk.count <= 1_048_576 else { throw Failure(message: "Info.plist vượt giới hạn.") }
            data.append(chunk)
        }
        guard checksum == entries[0].checksum,
              let info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let bundleID = info["CFBundleIdentifier"] as? String, !bundleID.isEmpty, bundleID.utf8.count <= 255,
              let version = (info["CFBundleVersion"] ?? info["CFBundleShortVersionString"]) as? String,
              !version.isEmpty, version.utf8.count <= 255 else { throw Failure(message: "Thiếu Bundle ID hoặc phiên bản cài đặt trong IPA.") }
        let title = (info["CFBundleDisplayName"] ?? info["CFBundleName"]) as? String ?? bundleID
        guard title.utf8.count <= 1024 else { throw Failure(message: "Tên ứng dụng quá dài.") }
        try NiKSignedOutputValidator.validate(url, expectedBundleID: bundleID)
        return Self(bundleID: bundleID, version: version, title: title)
    }
}
