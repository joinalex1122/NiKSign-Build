import Foundation

@main struct TLSServerCertificateSmoke {
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        let ca = try Data(contentsOf: root.appendingPathComponent("ca.p12"))
        let identity = try NiKTLSServerCertificate.create(caP12: ca, password: "test-ca")
        try identity.certificateDER.write(to: root.appendingPathComponent("leaf.cer"))
        try identity.p12.write(to: root.appendingPathComponent("leaf.p12"))
        try identity.password.write(to: root.appendingPathComponent("leaf-password"), atomically: true, encoding: .utf8)
        func rejects(_ bytes: Data, _ password: String) {
            do { _ = try NiKTLSServerCertificate.create(caP12: bytes, password: password); fatalError("Expected invalid CA rejection") }
            catch { }
        }
        rejects(ca, "wrong")
        rejects(Data(ca.prefix(20)), "test-ca")
        rejects(Data(), "")
        rejects(try Data(contentsOf: root.appendingPathComponent("not-ca.p12")), "test-ca")
        print("PASS: server leaf generation and malformed/password/non-CA rejection")
    }
}
