import Foundation

/// A static public manifest: only its port is requested from the provider.
/// App metadata, IPA bytes, signing keys and provisioning files are never uploaded.
enum NiKSemiLocalOTA {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
    static func manifest(port: Int) -> URL? {
        guard (4000...8999).contains(port) else { return nil }
        return URL(string: "https://signtools.github.io/ota-me/data/\(port)")
    }
    static func package(port: Int) -> URL? {
        guard manifest(port: port) != nil else { return nil }
        return URL(string: "http://127.0.0.1:\(port)/ota-me")
    }
    static func isManifest(_ url: URL) -> Bool {
        guard url.scheme == "https", url.host == "signtools.github.io", url.port == nil,
              url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              let port = Int(url.lastPathComponent), let expected = manifest(port: port) else { return false }
        return expected == url
    }
    static func validate(_ data: Data, port: Int) throws {
        guard data.count <= 65536, let expected = package(port: port),
              let document = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let items = document["items"] as? [[String: Any]], items.count == 1,
              let assets = items[0]["assets"] as? [[String: Any]], assets.count == 1,
              assets[0]["kind"] as? String == "software-package",
              assets[0]["url"] as? String == expected.absoluteString,
              let info = items[0]["metadata"] as? [String: Any],
              info["kind"] as? String == "software",
              info["bundle-identifier"] as? String == "com.foo.bar",
              info["bundle-version"] as? String == "2.0",
              info["title"] as? String == "Local app" else {
            throw Failure(message: "Manifest công khai đã thay đổi hoặc trỏ sai địa chỉ. NiKSign đã dừng yêu cầu cài đặt.")
        }
    }
}
