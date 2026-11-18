import Foundation

@main struct TextDocumentSmoke {
    static func expectFailure(_ action: () throws -> Void) {
        do { try action() } catch { return }
        fatalError("Expected validation error")
    }
    static func snapshot(_ data: Data, ext: String) throws -> NiKEditableFileSnapshot {
        .init(url: URL(fileURLWithPath: "/tmp/fixture." + ext), data: data, digest: try NiKFileDigest.sha256(data: data))
    }
    static func main() throws {
        let data = Data("{\"enabled\":false,\"count\":0}".utf8)
        let json = try NiKEditableTextDocument.open(snapshot(data, ext: "json"))
        let output = try json.encoded("{\"enabled\":true,\"count\":12}")
        let object = try JSONSerialization.jsonObject(with: output) as! [String: Any]
        precondition(object["enabled"] as? Bool == true)
        expectFailure { _ = try json.encoded("{broken") }
        precondition(json.snapshot.data == data)
        let original: [String: Any] = ["enabled": false, "number": 0, "date": Date(timeIntervalSince1970: 123), "blob": Data([0,1,2])]
        let binary = try PropertyListSerialization.data(fromPropertyList: original, format: .binary, options: 0)
        let plist = try NiKEditableTextDocument.open(snapshot(binary, ext: "plist"))
        precondition(plist.format == .plistBinary)
        let unchanged = try plist.encoded(plist.text)
        precondition(unchanged == binary)
        let fractional = try PropertyListSerialization.data(fromPropertyList: ["nested": [Date(timeIntervalSince1970: 123.456)]], format: .binary, options: 0)
        expectFailure { _ = try NiKEditableTextDocument.open(snapshot(fractional, ext: "plist")) }
        let changed = plist.text.replacingOccurrences(of: "<false/>", with: "<true/>")
        let encoded = try plist.encoded(changed)
        precondition(encoded.starts(with: Data("bplist".utf8)))
        let parsed = try PropertyListSerialization.propertyList(from: encoded, format: nil) as! [String: Any]
        precondition(parsed["enabled"] as? Bool == true)
        precondition(parsed["blob"] as? Data == original["blob"] as? Data)
        precondition(parsed["date"] as? Date == original["date"] as? Date)
        expectFailure { _ = try plist.encoded("not a property list") }
        expectFailure { _ = try NiKEditableTextDocument.open(snapshot(Data([0xff, 0x00, 0xfe]), ext: "txt")) }
        expectFailure { _ = try NiKEditableTextDocument.open(snapshot(Data(repeating: 65, count: 2 * 1_048_576 + 1), ext: "txt")) }
        let diff = NiKTextChangePreview.compare("first\nold\nlast", "first\nnew\nlast")
        precondition(diff.unchangedPrefix == 1 && diff.removed == ["old"] && diff.added == ["new"])
        let empty = NiKTextChangePreview.compare("same", "same")
        precondition(empty.removed.isEmpty && empty.added.isEmpty)
        let large = NiKTextChangePreview.compare(String(repeating: "x\n", count: 20_002), "new")
        precondition(large.truncatedFile)
        print("PASS: JSON validation, original preservation, binary plist round-trip with data/date/bool, invalid/big input rejection and bounded linear change preview")
    }
}
