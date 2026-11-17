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
let directory = URL(fileURLWithPath: CommandLine.arguments[1])
let modern = try Data(contentsOf: directory.appendingPathComponent("modern.p12"))
let legacy = try Data(contentsOf: directory.appendingPathComponent("legacy.p12"))
let modernInfo = try NiKCertificateStore.inspectP12(data: modern, password: " test password ")
let legacyInfo = try NiKCertificateStore.inspectP12(data: legacy, password: " test password ")
precondition(modernInfo.derData == legacyInfo.derData)
precondition(modernInfo.sha1Hex == legacyInfo.sha1Hex)
precondition(!modernInfo.derData.isEmpty && modernInfo.sha1Hex.count == 40)
expectFailure { _ = try NiKCertificateStore.inspectP12(data: legacy, password: "wrong") }
expectFailure { _ = try NiKCertificateStore.inspectP12(data: Data(legacy.prefix(20)), password: " test password ") }
expectFailure { _ = try NiKCertificateStore.inspectP12(data: Data(), password: "") }
print("PASS: modern and legacy p12 identity inspection, matching DER/fingerprint, password spaces, wrong password and damaged input")
