import Foundation

enum NiKOTAHTTP {
    struct Failure: Error {}
    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        init(_ text: String) throws {
            let lines = text.components(separatedBy: "\r\n")
            let parts = (lines.first ?? "").split(separator: " ")
            guard parts.count == 3, ["HTTP/1.0", "HTTP/1.1"].contains(parts[2]) else { throw Failure() }
            method = String(parts[0]); path = String(parts[1])
            var values: [String: String] = [:]
            for line in lines.dropFirst() where !line.isEmpty {
                guard let colon = line.firstIndex(of: ":") else { throw Failure() }
                let key = line[..<colon].lowercased(), value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                guard !key.isEmpty, values[key] == nil else { throw Failure() }
                values[key] = value
            }
            headers = values
        }
    }
    struct FileResponse {
        let status: String
        let offset: UInt64
        let length: UInt64
        let contentRange: String?
        static func make(size: UInt64, range: String?) -> Self {
            func invalid() -> Self { .init(status: "416 Range Not Satisfiable", offset: 0, length: 0, contentRange: "bytes */\(size)") }
            guard let range else { return .init(status: "200 OK", offset: 0, length: size, contentRange: nil) }
            guard range.hasPrefix("bytes="), size > 0 else { return invalid() }
            let parts = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
            func number(_ text: Substring) -> UInt64? {
                guard !text.isEmpty, text.utf8.allSatisfy({ (48...57).contains($0) }) else { return nil }
                return UInt64(text)
            }
            guard parts.count == 2 else { return invalid() }
            let start: UInt64, end: UInt64
            if parts[0].isEmpty {
                guard let suffix = number(parts[1]), suffix > 0 else { return invalid() }
                start = size - min(size, suffix); end = size - 1
            } else {
                guard let value = number(parts[0]), value < size else { return invalid() }
                start = value
                if parts[1].isEmpty { end = size - 1 }
                else { guard let value = number(parts[1]), value >= start else { return invalid() }; end = min(size - 1, value) }
            }
            return .init(status: "206 Partial Content", offset: start, length: end - start + 1, contentRange: "bytes \(start)-\(end)/\(size)")
        }
    }
    static func manifest(ipaURL: URL, bundleID: String, buildVersion: String, title: String) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: ["items": [[
            "assets": [["kind": "software-package", "url": ipaURL.absoluteString]],
            "metadata": ["bundle-identifier": bundleID, "bundle-version": buildVersion, "kind": "software", "title": title]
        ]]], format: .xml, options: 0)
    }
}
