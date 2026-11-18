import Foundation
import CoreFoundation
#if canImport(CryptoKit)
import CryptoKit
#endif

/// Only the observed public application/replace subset is losslessly representable by codec v3.
/// Authentication and semantic validation finish before returning any migrated bytes.
enum NiKPatchSchema9Compatibility {
    static let maximumBytes = 64 * 1_048_576
    private static let magic = Data("3105PATCH\0".utf8)

    static func normalize(_ data: Data) throws -> Data {
        guard data.count <= maximumBytes else { throw PatchPackageError.sizeLimitExceeded }
        guard data.starts(with: magic) else { return data }
        struct Header: Decodable { let schemaVersion: Int }
        let encoded = Data(data.dropFirst(magic.count))
        guard let header = try? PropertyListDecoder().decode(Header.self, from: encoded), header.schemaVersion == 9 else { return data }
        let object = try PropertyListSerialization.propertyList(from: encoded, format: nil)
        try boundGraph(object)
        guard let envelope = object as? [String: Any],
              Set(envelope.keys) == Set(["schemaVersion", "packageID", "isPasswordProtected", "publicContentKey", "keyFingerprint", "encryptedPayload"]),
              let protected = envelope["isPasswordProtected"] as? NSNumber,
              CFGetTypeID(protected) == CFBooleanGetTypeID(), !protected.boolValue,
              let identifier = envelope["packageID"] as? String, let id = UUID(uuidString: identifier),
              let key = envelope["publicContentKey"] as? Data, key.count == 32,
              let fingerprint = envelope["keyFingerprint"] as? Data,
              let cipher = envelope["encryptedPayload"] as? Data, cipher.count >= 28,
              try NiKFileDigest.sha256(data: key) == hex(fingerprint) else {
            throw PatchPackageError.unsupportedVersion
        }
        #if canImport(CryptoKit)
        do {
            let secret = SymmetricKey(data: key)
            let aad = Data("3105PATCH/v9/payload/\(id.uuidString)".utf8)
            let payload = try AES.GCM.open(AES.GCM.SealedBox(combined: cipher), using: secret, authenticating: aad)
            let converted = try convertPayload(payload, packageID: id)
            let sealed = try AES.GCM.seal(converted, using: secret,
                authenticating: Data("3105PATCH/v3/payload/\(id.uuidString)".utf8))
            guard let combined = sealed.combined else { throw PatchPackageError.invalidPasswordOrCorruptedPackage }
            var result = envelope
            result["schemaVersion"] = 3
            result["encryptedPayload"] = combined
            let output = magic + (try PropertyListSerialization.data(fromPropertyList: result, format: .binary, options: 0))
            guard output.count <= maximumBytes else { throw PatchPackageError.sizeLimitExceeded }
            return output
        } catch let error as PatchPackageError { throw error }
        catch { throw PatchPackageError.invalidPasswordOrCorruptedPackage }
        #else
        throw PatchPackageError.unsupportedVersion
        #endif
    }

    static func convertPayload(_ data: Data, packageID: UUID) throws -> Data {
        guard data.count <= maximumBytes else { throw PatchPackageError.sizeLimitExceeded }
        let object = try PropertyListSerialization.propertyList(from: data, format: nil)
        try boundGraph(object)
        guard var payload = object as? [String: Any], Set(payload.keys) == Set(["project", "replacementDigests"]),
              var project = payload["project"] as? [String: Any] else { throw PatchPackageError.invalidProject }
        let base: Set<String> = ["id", "name", "author", "isPrivate", "createdAt", "updatedAt", "bundleIdentifiers", "directories", "rules"]
        guard Set(project.keys).isSubset(of: base.union(["appGroupIdentifiers", "systemAppGroupIdentifiers", "settings"])) else { throw PatchPackageError.unsupportedVersion }
        for key in ["appGroupIdentifiers", "systemAppGroupIdentifiers", "settings"] {
            if let value = project[key] {
                guard let items = value as? [Any], items.isEmpty else { throw PatchPackageError.unsupportedVersion }
                project.removeValue(forKey: key)
            }
        }
        guard var directories = project["directories"] as? [[String: Any]],
              var rules = project["rules"] as? [[String: Any]], directories.count <= 5_000, rules.count <= 5_000 else {
            throw PatchPackageError.sizeLimitExceeded
        }
        for index in directories.indices {
            guard Set(directories[index].keys) == Set(["id", "containerKind", "bundleID", "relativePath"]),
                  directories[index]["containerKind"] as? String == "application" else { throw PatchPackageError.unsupportedVersion }
            directories[index].removeValue(forKey: "containerKind")
        }
        for index in rules.indices {
            guard Set(rules[index].keys) == Set(["id", "operation", "containerKind", "bundleID", "relativePath", "replacementFilename", "replacementData"]),
                  rules[index]["containerKind"] as? String == "application",
                  rules[index]["operation"] as? String == "replace" else { throw PatchPackageError.unsupportedVersion }
            rules[index].removeValue(forKey: "containerKind")
            rules[index].removeValue(forKey: "operation")
        }
        project["directories"] = directories; project["rules"] = rules
        let projectData = try PropertyListSerialization.data(fromPropertyList: project, format: .binary, options: 0)
        let decoded = try PropertyListDecoder().decode(PatchProject.self, from: projectData)
        guard decoded.id == packageID, !decoded.isPrivate else { throw PatchPackageError.invalidProject }
        try PatchPackageCodec.validate(decoded)
        guard let digests = payload["replacementDigests"] as? [String: Data], digests.count == decoded.rules.count else {
            throw PatchPackageError.invalidPasswordOrCorruptedPackage
        }
        for rule in decoded.rules {
            guard let digest = digests[rule.id.uuidString], digest.count == 32,
                  try NiKFileDigest.sha256(data: rule.replacementData) == hex(digest) else { throw PatchPackageError.invalidPasswordOrCorruptedPackage }
        }
        payload["project"] = project
        let result = try PropertyListSerialization.data(fromPropertyList: payload, format: .binary, options: 0)
        guard result.count <= maximumBytes else { throw PatchPackageError.sizeLimitExceeded }
        return result
    }

    private static func hex(_ data: Data) -> String { data.map { String(format: "%02x", $0) }.joined() }
    private static func boundGraph(_ object: Any) throws {
        var nodes = 0, bytes = 0
        func visit(_ value: Any, depth: Int) throws {
            nodes += 1
            guard depth <= 64, nodes <= 100_000 else { throw PatchPackageError.sizeLimitExceeded }
            if let data = value as? Data { bytes += data.count }
            else if let string = value as? String { bytes += string.utf16.count * 2 }
            else if let dict = value as? [String: Any] {
                for (key, item) in dict { try visit(key, depth: depth + 1); try visit(item, depth: depth + 1) }
            } else if let array = value as? [Any] { for item in array { try visit(item, depth: depth + 1) } }
            guard bytes <= 128 * 1_048_576 else { throw PatchPackageError.sizeLimitExceeded }
        }
        try visit(object, depth: 0)
    }
}
