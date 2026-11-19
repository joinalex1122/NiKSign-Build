import Foundation

enum NiKOTALandingPage {
    static func html(title: String, bundleID: String, installURL: URL) -> String {
        func escape(_ value: String) -> String {
            value.replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "'", with: "&#39;")
        }
        return """
        <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>NiKSign</title></head>
        <body><h1>\(escape(title))</h1><p>\(escape(bundleID))</p><p><a href="\(escape(installURL.absoluteString))">Cài đặt / Install</a></p><p>Giữ NiKSign chạy trong khi tải IPA. Keep NiKSign running during the download.</p></body></html>
        """
    }
}
