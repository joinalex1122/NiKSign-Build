import Foundation

@main struct TypedPlistSmoke {
    static func fails(_ action: () throws -> Void) {
        do { try action() } catch { return }
        fatalError("Expected typed plist validation failure")
    }
    static func check(_ value: @autoclosure () throws -> Bool, line: UInt = #line) throws { let result = try value(); precondition(result, "Failed at fixture line \(line)") }
    static func document(_ value: Any, format: PropertyListSerialization.PropertyListFormat = .binary) throws -> NiKTypedPlistDocument {
        let data = try PropertyListSerialization.data(fromPropertyList: value, format: format, options: 0)
        return try .init(snapshot: .init(url: URL(fileURLWithPath: "/tmp/fixture.plist"), data: data, digest: "fixture"))
    }
    static func main() throws {
        let date = Date(timeIntervalSince1970: 123.456789)
        var doc = try document(["flag": false, "number": NSNumber(value: Int64.min), "large": NSNumber(value: UInt64.max), "date": date,
                                "data": Data([0,1,255]), "list": ["a", "b", "c"]] as [String: Any])
        let original = doc.snapshot.data
        try check(try doc.encoded() == original)
        try doc.replace(at: [.key("flag")], with: .bool(true))
        let output = try doc.encoded()
        let parsed = try PropertyListSerialization.propertyList(from: output, format: nil) as! [String: Any]
        precondition(parsed["date"] as? Date == date && parsed["data"] as? Data == Data([0,1,255]))
        precondition(parsed["flag"] as? Bool == true)
        precondition((parsed["large"] as? NSNumber)?.uint64Value == UInt64.max)
        precondition(doc.diff().totalChanges == 1 && doc.diff().preview[0].path == [.key("flag")])
        try doc.moveArrayElement(at: [.key("list")], from: 0, to: 2)
        try check(try doc.node(at: [.key("list"), .index(2)]) == .string("a"))
        try doc.append(.dictionary(["enabled": .bool(false)]), to: [.key("list")])
        try doc.replace(at: [.key("list"), .index(3), .key("enabled")], with: .integer(7))
        try doc.insert(key: "added", value: .data(Data([5])), into: [])
        fails { try doc.insert(key: "added", value: .string("overwrite"), into: []) }
        fails { try doc.remove(at: []) }
        fails { try doc.replace(at: [.index(0)], with: .string("wrong type")) }
        fails { try doc.moveArrayElement(at: [.key("list")], from: 99, to: 0) }
        fails { try doc.replace(at: [.key("number")], with: .real(.infinity)) }
        let prior = doc.value
        fails { try doc.remove(at: [.key("missing")]) }
        precondition(NiKTypedPlistDocument.same(doc.value, prior))
        doc.format = .xml
        fails { _ = try doc.encoded() } // Fractional Date must never be silently truncated.
        doc.format = .binary
        _ = try doc.encoded()
        let nfc = "\u{00e9}", nfd = "e\u{0301}"
        var unicode = try document([nfc: nfc])
        try unicode.replace(at: [.key(nfc)], with: .string(nfd))
        precondition(unicode.isDirty && unicode.diff().totalChanges == 1)
        try unicode.remove(at: [.key(nfc)]); try unicode.insert(key: nfd, value: .string(nfd), into: [])
        precondition(unicode.diff().totalChanges == 2)
        let unicodeResult = try PropertyListSerialization.propertyList(from: unicode.encoded(), format: nil) as! [String: Any]
        precondition(unicodeResult.keys.first!.utf8.elementsEqual(nfd.utf8))
        precondition(!NiKTypedPlistDocument.same(.real(-0.0), .real(0.0)))
        var many = try document([String: Any]())
        for index in 0..<250 { try many.insert(key: "key\(index)", value: .integer(Int64(index)), into: []) }
        let limited = many.diff(limit: 20)
        precondition(limited.totalChanges == 250 && limited.preview.count == 20)
        var deep = NiKPlistValue.string("leaf")
        for _ in 0..<66 { deep = .array([deep]) }
        fails { try many.replace(at: [], with: deep) }
        // One data object referenced 20 times: ~1 MB on disk, 20 MB expanded.
        var alias = Data("bplist00".utf8)
        alias.append(contentsOf: [0x4f, 0x12, 0x00, 0x10, 0x00, 0x00])
        alias.append(Data(repeating: 65, count: 1_048_576))
        let arrayOffset = alias.count
        alias.append(contentsOf: [0xaf, 0x10, 20]); alias.append(Data(repeating: 0, count: 20))
        let tableOffset = alias.count
        func append32(_ value: Int) { var data = UInt32(value).bigEndian; withUnsafeBytes(of: &data) { alias.append(contentsOf: $0) } }
        func append64(_ value: Int) { var data = UInt64(value).bigEndian; withUnsafeBytes(of: &data) { alias.append(contentsOf: $0) } }
        append32(8); append32(arrayOffset)
        alias.append(contentsOf: [0,0,0,0,0,0,4,1]); append64(2); append64(1); append64(tableOffset)
        let raw = alias
        let expanded = try PropertyListSerialization.propertyList(from: raw, format: nil) as! NSArray
        precondition(expanded.count == 20 && (expanded[0] as! NSData).length == 1_048_576 && raw.count < 2 * 1_048_576)
        fails { _ = try NiKTypedPlistDocument(snapshot: .init(url: URL(fileURLWithPath: "/tmp/alias.plist"), data: raw, digest: "fixture")) }
        print("PASS: typed edits/arrays/diff, bool/int/UInt64/data/fractional Date preservation, no-op bytes, literal Unicode/negative-zero semantics, mutation atomicity, limits and aliased binary plist expansion guard")
    }
}
