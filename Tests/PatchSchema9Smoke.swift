import Foundation
#if canImport(CryptoKit)
import CryptoKit
#endif

@main struct PatchSchema9Smoke {
    static func reject(_ body: () throws -> Void) { do { try body(); fatalError("Expected rejection") } catch {} }
    static func main() throws {
        let rule = PatchRule(bundleID: "app.example.fixture", relativePath: "Documents/test.plist", replacementFilename: "test.plist", replacementData: Data([1, 2, 3]))
        let directory = PatchDirectory(bundleID: rule.bundleID, relativePath: "Documents")
        let project = PatchProject(name: "Synthetic schema9", directories: [directory], rules: [rule])
        let encoder = PropertyListEncoder(); encoder.outputFormat = .binary
        var object = try PropertyListSerialization.propertyList(from: encoder.encode(project), format: nil) as! [String: Any]
        object["appGroupIdentifiers"] = [String](); object["systemAppGroupIdentifiers"] = [String](); object["settings"] = [String]()
        var rules = object["rules"] as! [[String: Any]]
        rules[0]["operation"] = "replace"; rules[0]["containerKind"] = "application"; object["rules"] = rules
        var directories = object["directories"] as! [[String: Any]]
        directories[0]["containerKind"] = "application"; object["directories"] = directories
        let hex = try NiKFileDigest.sha256(data: rule.replacementData)
        let digest = Data(stride(from: 0, to: hex.count, by: 2).map { offset -> UInt8 in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)!
        })
        func payload(_ object: [String: Any], digest: Data = digest) throws -> Data {
            try PropertyListSerialization.data(fromPropertyList: ["project": object, "replacementDigests": [rule.id.uuidString: digest]], format: .binary, options: 0)
        }
        let originalPayload = try payload(object)
        let converted = try NiKPatchSchema9Compatibility.convertPayload(originalPayload, packageID: project.id)
        let normalized = try PropertyListSerialization.propertyList(from: converted, format: nil) as! [String: Any]
        let decoded = try PropertyListDecoder().decode(PatchProject.self, from: PropertyListSerialization.data(fromPropertyList: normalized["project"]!, format: .binary, options: 0))
        precondition(decoded == project)
        precondition((normalized["replacementDigests"] as! [String: Data])[rule.id.uuidString] == digest)
        for key in ["appGroupIdentifiers", "systemAppGroupIdentifiers", "settings", "unknownFeature"] {
            var bad = object; bad[key] = ["unsupported"]
            reject { _ = try NiKPatchSchema9Compatibility.convertPayload(payload(bad), packageID: project.id) }
        }
        for pair in [("operation", "delete"), ("operation", "mergePlist"), ("containerKind", "appGroup"), ("relativePath", "../escape"), ("unknownFeature", "x")] {
            var bad = object, badRules = rules; badRules[0][pair.0] = pair.1; bad["rules"] = badRules
            reject { _ = try NiKPatchSchema9Compatibility.convertPayload(payload(bad), packageID: project.id) }
        }
        var bad = object; bad["isPrivate"] = true
        reject { _ = try NiKPatchSchema9Compatibility.convertPayload(payload(bad), packageID: project.id) }
        bad = object; var badDirectories = directories; badDirectories[0]["containerKind"] = "systemAppGroup"; bad["directories"] = badDirectories
        reject { _ = try NiKPatchSchema9Compatibility.convertPayload(payload(bad), packageID: project.id) }
        reject { _ = try NiKPatchSchema9Compatibility.convertPayload(payload(object, digest: Data(repeating: 0, count: 32)), packageID: project.id) }
        reject { _ = try NiKPatchSchema9Compatibility.convertPayload(originalPayload, packageID: UUID()) }
        // Binary plist aliases one 1 MB data object 129 times without allocating/writing 129 MB.
        var alias = Data("bplist00".utf8)
        alias.append(contentsOf: [0x4f, 0x12, 0x00, 0x10, 0x00, 0x00]); alias.append(Data(repeating: 1, count: 1_048_576))
        let arrayOffset = alias.count
        alias.append(contentsOf: [0xaf, 0x10, 129]); alias.append(Data(repeating: 0, count: 129))
        let tableOffset = alias.count
        func append32(_ value: Int) { var n = UInt32(value).bigEndian; withUnsafeBytes(of: &n) { alias.append(contentsOf: $0) } }
        func append64(_ value: Int) { var n = UInt64(value).bigEndian; withUnsafeBytes(of: &n) { alias.append(contentsOf: $0) } }
        append32(8); append32(arrayOffset)
        alias.append(contentsOf: [0, 0, 0, 0, 0, 0, 4, 1]); append64(2); append64(1); append64(tableOffset)
        do {
            _ = try NiKPatchSchema9Compatibility.convertPayload(alias, packageID: project.id)
            fatalError("Expanded binary plist references must be bounded")
        } catch PatchPackageError.sizeLimitExceeded {} catch { fatalError("Expected expansion size limit") }
        #if canImport(CryptoKit)
        let key = Data(repeating: 7, count: 32)
        let sealed = try AES.GCM.seal(originalPayload, using: SymmetricKey(data: key), authenticating: Data("3105PATCH/v9/payload/\(project.id.uuidString)".utf8)).combined!
        var envelope: [String: Any] = ["schemaVersion": 9, "packageID": project.id.uuidString, "isPasswordProtected": false,
            "publicContentKey": key, "keyFingerprint": Data(SHA256.hash(data: key)), "encryptedPayload": sealed]
        func pack(_ envelope: [String: Any]) throws -> Data { Data("3105PATCH\0".utf8) + (try PropertyListSerialization.data(fromPropertyList: envelope, format: .binary, options: 0)) }
        let input = try pack(envelope)
        precondition(tryValue { try PatchPackageCodec.inspect(input).schemaVersion } == 3)
        precondition(tryValue { try PatchPackageCodec.decode(input, password: nil).project } == project)
        precondition(tryValue { try PatchPackageCodec.decode(input, contentKey: key).project } == project)
        var changed = project; changed.name = "Edited after import"
        let updated = try PatchPackageCodec.update(input, project: changed, contentKey: key)
        precondition(tryValue { try PatchPackageCodec.decode(updated, password: nil).project } == changed)
        let legacy = try PatchPackageCodec.encodeNew(project: project, password: " password ")
        precondition(tryValue { try NiKPatchSchema9Compatibility.normalize(legacy.data) } == legacy.data)
        var corrupt = sealed; corrupt[corrupt.count - 1] ^= 1; envelope["encryptedPayload"] = corrupt
        reject { _ = try PatchPackageCodec.inspect(pack(envelope)) }
        envelope["encryptedPayload"] = sealed; envelope["extraFeature"] = true
        reject { _ = try PatchPackageCodec.inspect(pack(envelope)) }
        envelope.removeValue(forKey: "extraFeature"); envelope["isPasswordProtected"] = true
        reject { _ = try PatchPackageCodec.inspect(pack(envelope)) }
        #endif
        print("PASS: schema9 lossless subset, metadata/container/operation/path/digest rejection; Apple builds also exercise authenticated codec import/update")
    }
    static func tryValue<T>(_ body: () throws -> T) -> T { try! body() }
}
