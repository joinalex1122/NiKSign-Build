import Foundation
import ZIPFoundation

/// Structural and CRC validation, not an assertion that Apple's installation policy will accept a signature.
enum NiKSignedOutputValidator {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func validate(_ url: URL, expectedBundleID: String, certificateDER: Data? = nil, expectedProfile: Data? = nil) throws {
        let archive = try Archive(url: url, accessMode: .read)
        let archiveLinks = try NiKIPAArchive.paths(archive)
        var total: UInt64 = 0
        var count = 0
        var paths = Set<String>()
        var plist: [String: Any]?
        var appRoot: String?
        for entry in archive {
            try Task.checkCancellation()
            count += 1
            guard count <= 50_000, entry.uncompressedSize <= 1_073_741_824 - total else {
                throw Failure(message: "IPA đầu ra vượt giới hạn.")
            }
            total += entry.uncompressedSize
            let path = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            let parts = path.split(separator: "/", omittingEmptySubsequences: false)
            guard !parts.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  !path.contains("\\"), !path.contains("\0"),
                  paths.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else {
                throw Failure(message: "IPA đầu ra có đường dẫn không hợp lệ.")
            }
            let isInfo = parts.count == 3 && parts[0] == "Payload" && parts[1].hasSuffix(".app") && parts[2] == "Info.plist"
            var bytes = Data()
            if isInfo {
                guard plist == nil, entry.uncompressedSize <= 1_048_576 else { throw Failure(message: "Info.plist đầu ra không hợp lệ.") }
            }
            var size: UInt64 = 0
            let crc = try archive.extract(entry) { data in
                try Task.checkCancellation()
                guard UInt64(data.count) <= entry.uncompressedSize - size else { throw Failure(message: "Kích thước ZIP đầu ra không khớp.") }
                size += UInt64(data.count)
                if isInfo { bytes.append(data) }
            }
            guard crc == entry.checksum, size == entry.uncompressedSize else { throw Failure(message: "IPA đầu ra bị lỗi CRC/kích thước.") }
            if isInfo {
                guard let decoded = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any] else {
                    throw Failure(message: "Info.plist đầu ra không phải dictionary.")
                }
                plist = decoded
                appRoot = "Payload/" + String(parts[1]) + "/"
            }
        }
        guard let plist, let appRoot else { throw Failure(message: "IPA đầu ra thiếu Payload/*.app/Info.plist.") }
        // Preserve requested identity; provisioning membership is separately validated below.
        guard plist["CFBundleIdentifier"] as? String == expectedBundleID else {
            throw Failure(message: "Bundle ID đầu ra khác ID đã yêu cầu.")
        }
        guard let build = plist["CFBundleVersion"] as? String, !build.isEmpty else { throw Failure(message: "IPA thiếu CFBundleVersion.") }
        guard let executable = plist["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), !executable.contains("\\"), executable != ".", executable != ".." else {
            throw Failure(message: "CFBundleExecutable đầu ra không hợp lệ.")
        }
        guard archive[appRoot + executable]?.type == .file,
              (archive[appRoot + executable]?.uncompressedSize ?? 0) >= 28 else {
            throw Failure(message: "IPA đầu ra thiếu executable hoặc executable quá ngắn.")
        }
        guard archive[appRoot + "embedded.mobileprovision"]?.type == .file else {
            throw Failure(message: "IPA đầu ra thiếu embedded.mobileprovision.")
        }
        guard let provision = archive[appRoot + "embedded.mobileprovision"], provision.uncompressedSize <= 16 * 1_048_576 else { throw Failure(message: "Provisioning profile đầu ra quá lớn.") }
        var profileData = Data()
        _ = try archive.extract(provision) { profileData.append($0) }
        if let expectedProfile, profileData != expectedProfile { throw Failure(message: "Profile đầu ra khác profile đã chọn.") }
        try NiKProvisioningValidation.validate(profileData, bundleID: expectedBundleID, certificateDER: certificateDER)
        guard archive[appRoot + "_CodeSignature/CodeResources"]?.type == .file else {
            throw Failure(message: "IPA đầu ra thiếu _CodeSignature/CodeResources.")
        }
        for entry in archive where entry.path.hasPrefix(appRoot) && entry.path.hasSuffix("/Info.plist") && entry.uncompressedSize <= 1_048_576 {
            let root = String(entry.path.dropLast("Info.plist".count))
            guard [".appex/", ".app/", ".framework/"].contains(where: { root.hasSuffix($0) }), root != appRoot else { continue }
            let infoPath = try NiKIPAArchive.resolve(entry.path, links: archiveLinks)
            guard let infoEntry = archive[infoPath], infoEntry.type == .file, infoEntry.uncompressedSize <= 1_048_576 else { throw Failure(message: "Info.plist bundle con không hợp lệ.") }
            var data = Data()
            _ = try archive.extract(infoEntry) { data.append($0) }
            guard let nested = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let id = nested["CFBundleIdentifier"] as? String,
                  let executable = nested["CFBundleExecutable"] as? String,
                  !executable.isEmpty, !executable.contains("/"), !executable.contains("\\"), executable != ".", executable != ".." else { throw Failure(message: "Metadata bundle con đầu ra không hợp lệ: " + root) }
            let realExecutable = try NiKIPAArchive.resolve(root + executable, links: archiveLinks)
            guard archive[realExecutable]?.type == .file, archive[root + "_CodeSignature/CodeResources"]?.type == .file else { throw Failure(message: "Bundle con thiếu executable hoặc resource seal: " + root) }
            guard let mode = archive[realExecutable]?.fileAttributes[.posixPermissions] as? NSNumber, mode.intValue & 0o100 != 0 else { throw Failure(message: "Executable bundle con thiếu quyền thực thi: " + root) }
            if !root.hasSuffix(".framework/") {
                guard nested["CFBundleVersion"] as? String == build,
                      plist["CFBundleShortVersionString"] == nil || nested["CFBundleShortVersionString"] as? String == plist["CFBundleShortVersionString"] as? String else { throw Failure(message: "Phiên bản extension không khớp ứng dụng chính: " + id) }
                guard id.hasPrefix(expectedBundleID + "."), let profile = archive[root + "embedded.mobileprovision"], profile.uncompressedSize <= 16 * 1_048_576 else { throw Failure(message: "Extension có định danh/profile không hợp lệ: " + id) }
                var bytes = Data(); _ = try archive.extract(profile) { bytes.append($0) }
                if let expectedProfile, bytes != expectedProfile { throw Failure(message: "Profile bundle con khác profile đã chọn: " + id) }
                try NiKProvisioningValidation.validate(bytes, bundleID: id, certificateDER: certificateDER)
            }
        }
        guard let binaryEntry = archive[appRoot + executable] else { throw Failure(message: "Thiếu executable đầu ra.") }
        guard let mode = binaryEntry.fileAttributes[.posixPermissions] as? NSNumber, mode.intValue & 0o100 != 0 else { throw Failure(message: "Executable trong IPA thiếu quyền thực thi.") }
        var magic = Data()
        _ = try archive.extract(binaryEntry) { chunk in
            if magic.count < 4 { magic.append(chunk.prefix(4 - magic.count)) }
        }
        let supported: [[UInt8]] = [[0xcf,0xfa,0xed,0xfe], [0xfe,0xed,0xfa,0xcf], [0xca,0xfe,0xba,0xbe], [0xbe,0xba,0xfe,0xca], [0xca,0xfe,0xba,0xbf], [0xbf,0xba,0xfe,0xca]]
        guard supported.contains(Array(magic)) else { throw Failure(message: "Executable đầu ra không phải Mach-O.") }
    }
}
