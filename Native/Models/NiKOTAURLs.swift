import Foundation

enum NiKOTAURLs {
    static func manifest(port: UInt16, token: String) -> URL? {
        guard port > 0, !token.isEmpty, token.count <= 128,
              token.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else { return nil }
        return URL(string: "https://127.0.0.1:\(port)/\(token)/manifest.plist")
    }
    static func install(manifest: URL) -> URL? {
        guard manifest.scheme == "https", manifest.host == "127.0.0.1", manifest.port != nil else { return nil }
        var parts = URLComponents()
        parts.scheme = "itms-services"
        parts.host = "" // Required authority: itms-services://?action=..., not itms-services:?action=...
        parts.queryItems = [URLQueryItem(name: "action", value: "download-manifest"), URLQueryItem(name: "url", value: manifest.absoluteString)]
        return parts.url
    }
}
