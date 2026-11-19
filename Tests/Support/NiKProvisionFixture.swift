import Foundation

/// Test-only OpenSSL CLI fixture, using fresh keys rather than Apple credentials.
final class NiKProvisionFixture {
    let directory: URL
    let openssl: String
    let der: Data
    init(directory: URL) throws {
        self.directory = directory.appendingPathComponent("profile-fixture")
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
        openssl = ProcessInfo.processInfo.environment["NIK_TEST_OPENSSL"] ?? "/usr/bin/openssl"
        try Self.run(openssl, ["req", "-x509", "-newkey", "rsa:2048", "-noenc", "-keyout", self.directory.appendingPathComponent("key.pem").path,
            "-out", self.directory.appendingPathComponent("cert.pem").path, "-days", "2", "-subj", "/CN=NiKSign fixture"])
        try Self.run(openssl, ["x509", "-in", self.directory.appendingPathComponent("cert.pem").path, "-outform", "DER", "-out", self.directory.appendingPathComponent("cert.der").path])
        der = try Data(contentsOf: self.directory.appendingPathComponent("cert.der"))
    }
    static func run(_ executable: String, _ args: [String]) throws {
        let process = Process(); process.executableURL = URL(fileURLWithPath: executable); process.arguments = args
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw NSError(domain: "OpenSSL fixture failed", code: Int(process.terminationStatus)) }
    }
    func profile(pattern: String = "com.example.*", expiration: Date = Date().addingTimeInterval(86400), certificate: Data? = nil) throws -> Data {
        try sign(["Name": "Fixture", "TeamName": "Fixture", "TeamIdentifier": ["TEAMFIX123"], "ApplicationIdentifierPrefix": ["SEEDFIX123"],
            "CreationDate": Date().addingTimeInterval(-3600), "ExpirationDate": expiration,
            "DeveloperCertificates": [certificate ?? der], "ProvisionsAllDevices": true,
            "Entitlements": ["application-identifier": "SEEDFIX123." + pattern, "com.apple.developer.team-identifier": "TEAMFIX123", "keychain-access-groups": ["SEEDFIX123.*"]]])
    }
    func detached(_ data: Data) throws -> Data {
        let input = directory.appendingPathComponent("content"), output = directory.appendingPathComponent("detached.der")
        try data.write(to: input)
        try Self.run(openssl, ["cms", "-sign", "-binary", "-in", input.path, "-out", output.path, "-outform", "DER", "-signer", directory.appendingPathComponent("cert.pem").path, "-inkey", directory.appendingPathComponent("key.pem").path])
        return try Data(contentsOf: output)
    }
    func sign(_ properties: [String: Any]) throws -> Data {
        let input = directory.appendingPathComponent("profile.plist"), output = directory.appendingPathComponent("profile.cms")
        try PropertyListSerialization.data(fromPropertyList: properties, format: .xml, options: 0).write(to: input)
        try Self.run(openssl, ["cms", "-sign", "-binary", "-nodetach", "-in", input.path, "-out", output.path, "-outform", "DER",
            "-signer", directory.appendingPathComponent("cert.pem").path, "-inkey", directory.appendingPathComponent("key.pem").path])
        return try Data(contentsOf: output)
    }
}
