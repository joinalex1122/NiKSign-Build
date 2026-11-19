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
        let html = NiKOTALandingPage.html(title: "<App & \"Title\">", bundleID: "com.demo.app", installURL: install)
        precondition(!html.contains("<App &") && html.contains("&lt;App &amp;"))
        precondition(html.contains("itms-services://?action=download-manifest&amp;url="))
        print("PASS: local HTTPS nested URL encoding and HTML metadata escaping")
    }
}
