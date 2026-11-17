import Foundation

struct NiKEditableTextDocument: Sendable {
    enum Format: Sendable { case utf8, json, plistXML, plistBinary }
    let snapshot: NiKEditableFileSnapshot
    let text: String
    let format: Format
    static func open(_ snapshot: NiKEditableFileSnapshot) throws -> Self {
        guard snapshot.data.count <= 2 * 1_048_576 else { throw Failure(message: "Trình sửa văn bản giới hạn 2 MB; dùng xem trước/Hex cho tệp lớn.") }
        let ext = snapshot.url.pathExtension.lowercased()
        if ext == "plist" || ext == "mobileconfig" {
            var format = PropertyListSerialization.PropertyListFormat.xml
            let value = try PropertyListSerialization.propertyList(from: snapshot.data, format: &format)
            let xml = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
            guard xml.count <= 2 * 1_048_576 else { throw Failure(message: "Biểu diễn XML vượt giới hạn editor 2 MB.") }
            if format != .xml {
                let roundTrip = try PropertyListSerialization.propertyList(from: xml, format: nil)
                guard NSDictionary(dictionary: ["value": value]).isEqual(to: ["value": roundTrip]) else {
                    throw Failure(message: "Plist này có giá trị không giữ nguyên được qua XML (ví dụ ngày có phần lẻ). Chưa hỗ trợ sửa văn bản; tệp gốc được giữ nguyên.")
                }
            }
            guard let text = String(data: format == .xml ? snapshot.data : xml, encoding: .utf8) else { throw Failure(message: "Không đọc được plist UTF-8.") }
            return .init(snapshot: snapshot, text: text, format: format == .binary ? .plistBinary : .plistXML)
        }
        guard let text = String(data: snapshot.data, encoding: .utf8), !snapshot.data.contains(0) else { throw Failure(message: "Tệp không phải văn bản UTF-8; hãy dùng xem trước/Hex.") }
        if ext == "json" {
            _ = try JSONSerialization.jsonObject(with: snapshot.data, options: [.fragmentsAllowed])
            return .init(snapshot: snapshot, text: text, format: .json)
        }
        return .init(snapshot: snapshot, text: text, format: .utf8)
    }
    func encoded(_ edited: String) throws -> Data {
        if edited == text { return snapshot.data }
        let raw = Data(edited.utf8)
        guard raw.count <= 2 * 1_048_576 else { throw Failure(message: "Văn bản vượt 2 MB.") }
        switch format {
        case .utf8: return raw
        case .json:
            _ = try JSONSerialization.jsonObject(with: raw, options: [.fragmentsAllowed])
            return raw
        case .plistXML, .plistBinary:
            let value = try PropertyListSerialization.propertyList(from: raw, format: nil)
            return try PropertyListSerialization.data(fromPropertyList: value, format: format == .plistBinary ? .binary : .xml, options: 0)
        }
    }
    func formatted(_ input: String) throws -> String {
        switch format {
        case .json:
            let value = try JSONSerialization.jsonObject(with: Data(input.utf8), options: [.fragmentsAllowed])
            let data = try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed])
            return String(decoding: data, as: UTF8.self)
        case .plistXML, .plistBinary:
            let value = try PropertyListSerialization.propertyList(from: Data(input.utf8), format: nil)
            let data = try PropertyListSerialization.data(fromPropertyList: value, format: .xml, options: 0)
            return String(decoding: data, as: UTF8.self)
        case .utf8: return input
        }
    }
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }
}

struct NiKTextChangePreview: Sendable {
    let removed: [String]
    let added: [String]
    let unchangedPrefix: Int
    let omittedLines: Int
    let truncatedFile: Bool
    static func compare(_ before: String, _ after: String) -> Self {
        let old = before.split(separator: "\n", maxSplits: 20_000, omittingEmptySubsequences: false)
        let new = after.split(separator: "\n", maxSplits: 20_000, omittingEmptySubsequences: false)
        guard old.count <= 20_000, new.count <= 20_000 else {
            return .init(removed: [String(before.prefix(8_000))], added: [String(after.prefix(8_000))], unchangedPrefix: 0, omittedLines: 0, truncatedFile: true)
        }
        var prefix = 0
        while prefix < min(old.count, new.count), old[prefix] == new[prefix] { prefix += 1 }
        var suffix = 0
        while suffix < min(old.count, new.count) - prefix,
              old[old.count - 1 - suffix] == new[new.count - 1 - suffix] { suffix += 1 }
        let removed = old[prefix..<(old.count - suffix)]
        let added = new[prefix..<(new.count - suffix)]
        return .init(removed: removed.prefix(100).map { String($0.prefix(4_000)) }, added: added.prefix(100).map { String($0.prefix(4_000)) }, unchangedPrefix: prefix,
                     omittedLines: max(0, removed.count - 100) + max(0, added.count - 100),
                     truncatedFile: removed.prefix(100).contains { $0.count > 4_000 } || added.prefix(100).contains { $0.count > 4_000 })
    }
}
