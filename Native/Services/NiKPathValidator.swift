import Foundation

/// Validation for user IPA archives and bundle identifiers only.
enum NiKPathValidator {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func canonicalBundleIdentifier(_ raw: String) throws -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !value.isEmpty, value.utf8.count <= 255, UUID(uuidString: value) == nil, parts.count >= 2,
              parts.allSatisfy({ !$0.isEmpty && $0.first != "-" && $0.last != "-" && $0.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 } }) else {
            throw Failure(message: "Bundle ID không hợp lệ.")
        }
        return value
    }
    static func canonicalRelativePath(_ value: String) throws -> String {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !value.isEmpty, value.utf8.count <= 4096, !value.hasPrefix("/"), !value.contains("\\"),
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw Failure(message: "Đường dẫn trong IPA không an toàn.")
        }
        return parts.joined(separator: "/")
    }
}
