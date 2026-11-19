import Foundation
@main struct OTAURLsSmoke {
    static func main() throws {
        let manifest = NiKOTAURLs.manifest(port: 43210, token: "ab12cd34")!
        let install = NiKOTAURLs.install(manifest: manifest)!
        precondition(install.absoluteString.hasPrefix("itms-services://?"))
        let components = URLComponents(url: install, resolvingAgainstBaseURL: false)!
        precondition(components.queryItems?.first(where: { $0.name == "action" })?.value == "download-manifest")
        precondition(components.queryItems?.first(where: { $0.name == "url" })?.value == manifest.absoluteString)
        precondition(NiKOTAURLs.manifest(port: 0, token: "ab") == nil)
        precondition(NiKOTAURLs.manifest(port: 123, token: "../outside") == nil)
        precondition(NiKOTAURLs.install(manifest: URL(string: "http://127.0.0.1:123/test")!) == nil)
        precondition(NiKOTAURLs.install(manifest: URL(string: "https://example.com/test")!) == nil)
        let external = NiKSemiLocalOTA.manifest(port: 8080)!
        let externalInstall = NiKOTAURLs.install(manifest: external)!
        let query = URLComponents(url: externalInstall, resolvingAgainstBaseURL: false)!.queryItems!
        precondition(query.first { $0.name == "url" }?.value == external.absoluteString)
        precondition(externalInstall.absoluteString.contains("https%3A%2F%2F"))
        for value in ["https://signtools.github.io/ota-me/data/8080?bad=1", "https://signtools.github.io.evil.test/ota-me/data/8080", "https://user@signtools.github.io/ota-me/data/8080", "https://signtools.github.io:443/ota-me/data/8080", "https://signtools.github.io/ota-me/data/08080"] {
            precondition(NiKOTAURLs.install(manifest: URL(string: value)!) == nil)
        }
        precondition(NiKSemiLocalOTA.manifest(port: 3999) == nil && NiKSemiLocalOTA.manifest(port: 9000) == nil)
        let item: [String: Any] = ["items": [["assets": [["kind": "software-package", "url": "http://127.0.0.1:8080/ota-me"]], "metadata": ["kind": "software", "bundle-identifier": "com.foo.bar", "bundle-version": "2.0", "title": "Local app"]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: item, format: .xml, options: 0)
        try NiKSemiLocalOTA.validate(data, port: 8080)
        func rejects(_ bytes: Data) {
            do { try NiKSemiLocalOTA.validate(bytes, port: 8080); fatalError("Bad manifest accepted") } catch {}
        }
        rejects(Data("<html>Unavailable</html>".utf8))
        rejects(Data(repeating: 0, count: 65537))
        for wrong in ["http://127.0.0.1:8081/ota-me", "http://evil.test/app.ipa", "http://127.0.0.1:8080/elsewhere"] {
            let text = String(data: data, encoding: .utf8)!.replacingOccurrences(of: "http://127.0.0.1:8080/ota-me", with: wrong)
            rejects(Data(text.utf8))
        }
        print("PASS: nested OTA URL encoding, pinned public endpoint, static manifest bounds and exact loopback asset validation")
    }
}
