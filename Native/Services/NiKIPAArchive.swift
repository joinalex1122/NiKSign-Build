import Foundation
import ZIPFoundation

/// Preserve bundle-internal links without permitting archive writes through a link.
enum NiKIPAArchive {
    static func paths(_ archive: Archive) throws -> [String: String] {
        var links: [String: String] = [:], names = Set<String>(), folded = Set<String>()
        for entry in archive {
            let path = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            _ = try NiKPathValidator.canonicalRelativePath(path)
            guard names.insert(path).inserted, folded.insert(path.precomposedStringWithCanonicalMapping.lowercased()).inserted else { throw NiKProvisioningValidation.Failure(message: "IPA có đường dẫn trùng.") }
            if entry.type == .symlink {
                guard !path.split(separator: "/").contains("_CodeSignature"), !path.hasSuffix("/embedded.mobileprovision") else { throw NiKProvisioningValidation.Failure(message: "Metadata chữ ký không được là symlink.") }
                guard entry.uncompressedSize <= 4096 else { throw NiKProvisioningValidation.Failure(message: "Symlink trong IPA quá dài.") }
                var bytes = Data()
                let crc = try archive.extract(entry) { bytes.append($0) }
                guard crc == entry.checksum, let target = String(data: bytes, encoding: .utf8), !target.isEmpty,
                      !target.hasPrefix("/"), !target.contains("\\"), !target.contains("\0") else { throw NiKProvisioningValidation.Failure(message: "Symlink IPA không hợp lệ.") }
                links[path] = target
            }
        }
        for path in names {
            var parts = path.split(separator: "/").map(String.init)
            parts.removeLast()
            while !parts.isEmpty {
                guard links[parts.joined(separator: "/")] == nil else { throw NiKProvisioningValidation.Failure(message: "IPA có mục ghi xuyên symlink.") }
                parts.removeLast()
            }
        }
        for path in links.keys {
            let resolved = try resolve(path, links: links)
            let root = path.split(separator: "/").prefix(2).joined(separator: "/")
            guard root.hasPrefix("Payload/"), root.hasSuffix(".app"), resolved.hasPrefix(root + "/"),
                  names.contains(resolved) || names.contains(where: { $0.hasPrefix(resolved + "/") }) else { throw NiKProvisioningValidation.Failure(message: "Symlink IPA thoát bundle hoặc trỏ đến mục không tồn tại.") }
        }
        return links
    }
    static func resolve(_ path: String, links: [String: String], depth: Int = 0) throws -> String {
        guard depth < 40 else { throw NiKProvisioningValidation.Failure(message: "Symlink IPA có vòng lặp.") }
        var stack: [String] = []
        let parts = path.split(separator: "/").map(String.init)
        for (index, part) in parts.enumerated() {
            if part == "." { continue }
            if part == ".." {
                guard !stack.isEmpty else { throw NiKProvisioningValidation.Failure(message: "Symlink IPA thoát thư mục.") }
                stack.removeLast(); continue
            }
            stack.append(part)
            if let target = links[stack.joined(separator: "/")] {
                stack.removeLast()
                return try resolve((stack + [target] + parts.dropFirst(index + 1)).joined(separator: "/"), links: links, depth: depth + 1)
            }
        }
        return stack.joined(separator: "/")
    }
    static func extract(_ archive: Archive, to work: URL) throws {
        let links = try paths(archive)
        let fm = FileManager.default
        for entry in archive where entry.type != .symlink {
            try Task.checkCancellation()
            let url = work.appendingPathComponent(entry.path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let crc = try archive.extract(entry, to: url)
            guard crc == entry.checksum else { throw NiKProvisioningValidation.Failure(message: "IPA bị lỗi CRC khi giải nén.") }
        }
        for (path, target) in links {
            let url = work.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.createSymbolicLink(atPath: url.path, withDestinationPath: target)
        }
    }
}
