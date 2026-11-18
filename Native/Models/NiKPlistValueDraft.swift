import Foundation

struct NiKPlistValueDraft: Sendable {
    enum Kind: String, CaseIterable, Sendable {
        case string, integer, unsigned, real, bool, data, date, array, dictionary
        init(_ value: NiKPlistValue) {
            switch value {
            case .string: self = .string
            case .integer: self = .integer
            case .unsigned: self = .unsigned
            case .real: self = .real
            case .bool: self = .bool
            case .data: self = .data
            case .date: self = .date
            case .array: self = .array
            case .dictionary: self = .dictionary
            }
        }
        func title(english: Bool) -> String {
            switch self {
            case .string: return english ? "String" : "Chuỗi"
            case .integer: return "Int64"
            case .unsigned: return "UInt64"
            case .real: return english ? "Real" : "Số thực"
            case .bool: return "Boolean"
            case .data: return "Data · Base64"
            case .date: return english ? "Date" : "Ngày"
            case .array: return "Array"
            case .dictionary: return "Dictionary"
            }
        }
    }
    private let original: NiKPlistValue?
    private let initialKind: Kind
    private let initialText: String
    private let initialBool: Bool
    private(set) var kind: Kind
    var text: String
    var boolValue: Bool
    var hasChanges: Bool { kind != initialKind || !text.utf8.elementsEqual(initialText.utf8) || boolValue != initialBool }
    init(_ value: NiKPlistValue? = nil) {
        original = value
        let value = value ?? .string("")
        kind = Kind(value); initialKind = kind
        switch value {
        case .string(let value): text = value
        case .integer(let value): text = String(value)
        case .unsigned(let value): text = String(value)
        case .real(let value): text = String(value)
        case .bool(let value): text = value ? "true" : "false"
        case .data(let value): text = value.base64EncodedString()
        case .date(let value): text = String(value.timeIntervalSinceReferenceDate)
        case .array, .dictionary: text = ""
        }
        if case .bool(let value) = value { boolValue = value } else { boolValue = false }
        initialText = text; initialBool = boolValue
    }
    mutating func select(_ newKind: Kind) {
        kind = newKind
        if newKind == initialKind { text = initialText; boolValue = initialBool }
    }
    func parsed() throws -> NiKPlistValue {
        guard text.utf8.count <= 8 * 1_048_576 else { throw failure("Dữ liệu nhập vượt 8 MB.") }
        if !hasChanges, let original { return original }
        let number = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .string: return .string(text)
        case .integer:
            guard let value = Int64(number) else { throw failure("Cần số nguyên Int64 hợp lệ.") }; return .integer(value)
        case .unsigned:
            guard let value = UInt64(number) else { throw failure("Cần số nguyên UInt64 không âm.") }
            return value <= UInt64(Int64.max) ? .integer(Int64(value)) : .unsigned(value)
        case .real:
            guard let value = Double(number), value.isFinite else { throw failure("Cần số thực hữu hạn, dùng dấu chấm thập phân.") }; return .real(value)
        case .bool: return .bool(boolValue)
        case .data:
            let clean = text.filter { !$0.isWhitespace }
            guard let value = Data(base64Encoded: clean) else { throw failure("Data cần Base64 hợp lệ; không bỏ qua ký tự sai.") }; return .data(value)
        case .date:
            guard let value = Double(number), value.isFinite else { throw failure("Cần số giây hữu hạn tính từ 01/01/2001 UTC.") }
            return .date(Date(timeIntervalSinceReferenceDate: value))
        case .array:
            if let original, case .array = original, initialKind == .array { return original }
            return .array([])
        case .dictionary:
            if let original, case .dictionary = original, initialKind == .dictionary { return original }
            return .dictionary([:])
        }
    }
    private func failure(_ message: String) -> NiKTypedPlistDocument.Failure { .init(message: message) }
    static func summary(_ value: NiKPlistValue?) -> String {
        guard let value else { return "—" }
        switch value {
        case .string(let value): return String(decoding: value.utf8.prefix(512), as: UTF8.self)
        case .integer(let value): return String(value)
        case .unsigned(let value): return String(value)
        case .real(let value): return String(value)
        case .bool(let value): return value ? "true" : "false"
        case .data(let value): return "Data (\(value.count) bytes)"
        case .date(let value): return "Date (\(value.timeIntervalSinceReferenceDate) s / 2001 UTC)"
        case .array(let value): return "Array (\(value.count))"
        case .dictionary(let value): return "Dictionary (\(value.count))"
        }
    }
}
