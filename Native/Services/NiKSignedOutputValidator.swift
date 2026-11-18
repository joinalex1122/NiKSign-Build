import Foundation
import ZIPFoundation

/// Structural and CRC validation, not an assertion that Apple's installation policy will accept a signature.
enum NiKSignedOutputValidator {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func validate(_ url: URL, expectedBundleID: String) throws {
        let archive = try Archive(url: url, accessMode: .read)
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
                  !path.contains("\\"), !path.contains("\0"), entry.type != .symlink,
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
        // This checks preservation of the requested app ID, never membership in a profile.
        guard plist["CFBundleIdentifier"] as? String == expectedBundleID else {
            throw Failure(message: "Bundle ID đầu ra khác ID đã yêu cầu. Đây không phải bước đối chiếu ID với profile.")
        }
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
        guard archive[appRoot + "_CodeSignature/CodeResources"]?.type == .file else {
            throw Failure(message: "IPA đầu ra thiếu _CodeSignature/CodeResources.")
        }
        guard let binaryEntry = archive[appRoot + executable] else { throw Failure(message: "Thiếu executable đầu ra.") }
        var magic = Data()
        _ = try archive.extract(binaryEntry) { chunk in
            if magic.count < 4 { magic.append(chunk.prefix(4 - magic.count)) }
        }
        let supported: [[UInt8]] = [[0xcf,0xfa,0xed,0xfe], [0xfe,0xed,0xfa,0xcf], [0xca,0xfe,0xba,0xbe], [0xbe,0xba,0xfe,0xca], [0xca,0xfe,0xba,0xbf], [0xbf,0xba,0xfe,0xca]]
        guard supported.contains(Array(magic)) else { throw Failure(message: "Executable đầu ra không phải Mach-O.") }
    }
}
