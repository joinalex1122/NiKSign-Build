import Foundation
import Security

@main struct HTTPSOTASmoke {
    @MainActor static func main() async throws {
        let directory = URL(fileURLWithPath: CommandLine.arguments[1])
        let service = "com.niksign.https-test." + UUID().uuidString
        defer { SecItemDelete([kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service] as CFDictionary) }
        let server = NiKHTTPSOTAServer(identityLoader: { try NiKLocalTLSIdentity.loadOrCreateServer(service: service) })
        server.configure(ipaURL: directory.appendingPathComponent("fixture.ipa"), bundleIdentifier: "com.fixture.app", bundleVersion: "123", title: "Fixture & <App>")
        try server.start()
        try await server.waitUntilReady()
        try server.exportMobileConfig().write(to: directory.appendingPathComponent("trust.mobileconfig"))
        let data = try JSONSerialization.data(withJSONObject: ["manifest": server.manifestURL!.absoluteString, "landing": server.landingURL!.absoluteString])
        FileHandle.standardOutput.write(data + Data([10]))
        let deadline = Date().addingTimeInterval(90)
        while Date() < deadline && !FileManager.default.fileExists(atPath: directory.appendingPathComponent("stop").path) {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        server.stop()
        precondition(!server.isRunning && !server.isServingIPA && server.port == 0)
        FileHandle.standardOutput.write(Data("STOPPED\n".utf8))
    }
}
