import Foundation
import Security

struct NiKError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

func expectFailure(_ operation: () throws -> Void) {
    do { try operation() } catch { return }
    fatalError("Expected invalid certificate/password rejection")
}
do {
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let modern = try Data(contentsOf: directory.appendingPathComponent("modern.p12"))
let legacy = try Data(contentsOf: directory.appendingPathComponent("legacy.p12"))
let modernInfo = try NiKCertificateStore.inspectP12(data: modern, password: " test password ")
let legacyInfo = try NiKCertificateStore.inspectP12(data: legacy, password: " test password ")
precondition(modernInfo.derData == legacyInfo.derData)
precondition(modernInfo.sha1Hex == legacyInfo.sha1Hex)
precondition(!modernInfo.derData.isEmpty && modernInfo.sha1Hex.count == 40)
precondition((modernInfo.expirationDate ?? .distantPast) > Date())
precondition((modernInfo.notBeforeDate ?? .distantFuture) <= Date())
let provisioningXML = try PropertyListSerialization.data(fromPropertyList: [
    "Name": "Metadata fixture", "TeamIdentifier": ["TEAM"], "ApplicationIdentifierPrefix": ["SEED"],
    "Entitlements": ["application-identifier": "SEED.com.example.*", "get-task-allow": true],
    "ProvisionedDevices": ["UDID-ONE"], "DeveloperCertificates": [modernInfo.derData],
    "ExpirationDate": Date().addingTimeInterval(3600)
] as [String: Any], format: .xml, options: 0)
let metadata = try NiKCertificateStore.parseMobileProvision(data: provisioningXML)
precondition(metadata.teamID == "TEAM" && metadata.bundleIDPattern == "com.example.*")
precondition(metadata.allowsDebugging && !metadata.provisionsAllDevices)
precondition(metadata.entitlements["get-task-allow"] == .bool(true))
expectFailure { _ = try NiKCertificateStore.inspectP12(data: legacy, password: "wrong") }
expectFailure { _ = try NiKCertificateStore.inspectP12(data: Data(legacy.prefix(20)), password: " test password ") }
expectFailure { _ = try NiKCertificateStore.inspectP12(data: Data(), password: "") }
print("PASS: modern and legacy p12 identity inspection, matching DER/fingerprint, password spaces, wrong password and damaged input")

// Use an isolated service and remove synthetic test credentials afterward.
let service = "com.niksign.tests.ota." + UUID().uuidString
let deleteQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service
]
defer { SecItemDelete(deleteQuery as CFDictionary) }
let firstTLS = try NiKLocalTLSIdentity.loadOrCreate(service: service)
let secondTLS = try NiKLocalTLSIdentity.loadOrCreate(service: service)
precondition(firstTLS.1 == secondTLS.1)
precondition(SecCertificateCreateWithData(nil, firstTLS.1 as CFData) != nil)
try firstTLS.1.write(to: directory.appendingPathComponent("local-ota.cer"))
print("PASS: actual local TLS identity generation, DER certificate and stable Keychain reload")

let mobileConfig = try NiKOTAProfile.encode(certificateDER: firstTLS.1)
let profile = try PropertyListSerialization.propertyList(from: mobileConfig, format: nil) as! [String: Any]
precondition(profile["PayloadType"] as? String == "Configuration")
let payloads = profile["PayloadContent"] as! [[String: Any]]
precondition(payloads.count == 1)
precondition(payloads[0]["PayloadType"] as? String == "com.apple.security.root")
precondition(payloads[0]["PayloadContent"] as? Data == firstTLS.1)
precondition(payloads[0]["PayloadVersion"] as? Int == 1)
precondition(profile["PayloadRemovalDisallowed"] as? Bool == false)
print("PASS: real mobileconfig builder, root certificate payload and DER round trip")
try await MainActor.run {
    let root = directory.appendingPathComponent("corrupt-store")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let index = root.appendingPathComponent("index.json")
    let original = Data("preserve corrupt index".utf8)
    try original.write(to: index)
    let store = NiKCertificateStore(rootDirectory: root)
    precondition(store.loadFailure != nil)
    do {
        _ = try store.importProfile(p12URL: directory.appendingPathComponent("modern.p12"), provisionURL: directory.appendingPathComponent("unused.mobileprovision"), password: " test password ")
        fatalError("Corrupt store must reject new imports")
    } catch { }
    let after = try Data(contentsOf: index)
    precondition(after == original)
}
print("PASS: corrupt certificate index is preserved and blocks destructive re-import")


} catch {
    fputs("Certificate regression failed: \(error.localizedDescription)\n", stderr)
    exit(1)
}
