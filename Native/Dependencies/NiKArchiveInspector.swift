import Foundation
import ArArchiveKit
import SWCompression

struct NiKArchiveInspector {
    static func report(at url: URL) throws -> String {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 16_777_216 else { throw NiKError("Trình xem nhận tối đa 16 MB.") }
        let data = try Data(contentsOf: url)
        switch url.pathExtension.lowercased() {
        case "deb", "ar", "a":
            let expectedCount = try validateShortAR(data)
            let archive = try ArArchiveReader(archive: Array(data))
            guard archive.count == expectedCount else { throw NiKError("ArArchiveKit không đọc đủ mục; archive chưa được hỗ trợ.") }
            return "AR / DEB · \(archive.count) mục\nChỉ xem danh mục, không cài hoặc thực thi.\n\n" + archive.headers.prefix(2000).map {
                "\($0.name) · \($0.size) bytes"
            }.joined(separator: "\n")
        case "tar":
            let entries = try TarContainer.info(container: data)
            return "TAR · \(entries.count) mục\nChỉ xem metadata, không giải nén.\n\n" + entries.prefix(2000).map {
                "\($0.name) · \($0.size ?? 0) bytes · \($0.type)"
            }.joined(separator: "\n")
        default:
            return try NiKBinaryInspector.report(at: url)
        }
    }
    // ArArchiveKit indexes directly into buffers. Validate boundaries first and
    // restrict this UI to common/GNU short filenames (the usual .deb format).
    static func validateShortAR(_ data: Data) throws -> Int {
        let b = [UInt8](data)
        guard b.count >= 68, Array(b.prefix(8)) == Array("!<arch>\n".utf8) else {
            throw NiKError("Không phải archive AR hợp lệ.")
        }
        var offset = 8, count = 0
        while offset < b.count {
            guard b.count - offset >= 60 else { throw NiKError("Header AR bị cắt ngắn.") }
            let h = Array(b[offset..<(offset + 60)])
            func field(_ a: Int, _ z: Int) -> String {
                String(decoding: h[a..<z], as: UTF8.self).trimmingCharacters(in: .whitespaces)
            }
            let name = field(0,16)
            guard !name.isEmpty, !name.hasPrefix("/"), !name.hasPrefix("#1/"),
                  h[58] == 96, h[59] == 10,
                  let length = Int(field(48,58)), length > 0,
                  length <= b.count - offset - 60 else {
                throw NiKError("AR có header hỏng, mục rỗng hoặc tên mở rộng chưa hỗ trợ.")
            }
            offset += 60 + length
            if length % 2 != 0 {
                guard offset < b.count, b[offset] == 10 else { throw NiKError("AR thiếu byte đệm.") }
                offset += 1
            }
            count += 1
            guard count <= 2000 else { throw NiKError("AR vượt 2.000 mục.") }
        }
        return count
    }
}
