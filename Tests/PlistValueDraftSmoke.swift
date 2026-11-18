import Foundation

@main struct PlistValueDraftSmoke {
    static func fails(_ action: () throws -> Void) {
        do { try action() } catch { return }
        fatalError("Expected draft validation failure")
    }
    static func check(_ value: @autoclosure () throws -> Bool) throws { let result = try value(); precondition(result) }
    static func main() throws {
        let precise = Date(timeIntervalSinceReferenceDate: 1e-100)
        let date = NiKPlistValueDraft(.date(precise))
        try check(try date.parsed() == .date(precise))
        var changedDate = date; changedDate.text = "0.000000001"
        if case .date(let value) = try changedDate.parsed() { precondition(value.timeIntervalSinceReferenceDate == 1e-9) } else { fatalError("Wrong type") }
        var integer = NiKPlistValueDraft(.integer(Int64.min)); integer.text = "9223372036854775808"
        fails { _ = try integer.parsed() }
        integer.select(.unsigned)
        try check(try integer.parsed() == .unsigned(9_223_372_036_854_775_808))
        integer.text = "7"
        try check(try integer.parsed() == .integer(7))
        var data = NiKPlistValueDraft(.data(Data([0,1,255])))
        data.text = "AA H/ \n"
        try check(try data.parsed() == .data(Data([0,1,255])))
        data.text = "AAH/%"
        fails { _ = try data.parsed() }
        var real = NiKPlistValueDraft(.real(-0.0))
        try check(NiKTypedPlistDocument.same(try real.parsed(), .real(-0.0)))
        real.text = "NaN"
        fails { _ = try real.parsed() }
        var boolean = NiKPlistValueDraft(.bool(false)); boolean.boolValue = true
        try check(try boolean.parsed() == .bool(true))
        let container = NiKPlistValue.array([.string("keep")])
        var nested = NiKPlistValueDraft(container)
        nested.select(.dictionary)
        try check(try nested.parsed() == .dictionary([:]))
        nested.select(.array)
        try check(try nested.parsed() == container)
        var unicode = NiKPlistValueDraft(.string("\u{00e9}")); unicode.text = "e\u{0301}"
        precondition(unicode.hasChanges)
        if case .string(let text) = try unicode.parsed() { precondition(text.utf8.elementsEqual(unicode.text.utf8)) } else { fatalError("Wrong type") }
        print("PASS: typed scalar drafts preserve tiny Date/negative zero/Unicode, validate numeric/Base64 input and preserve existing containers without implicit clearing")
    }
}
