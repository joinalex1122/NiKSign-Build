import Foundation
import CoreFoundation

/// A lossless property-list value for display, diffs and future validated editors.
indirect enum NiKPlistValue: Codable, Equatable, Sendable {
    case string(String), integer(Int64), unsigned(UInt64), real(Double), bool(Bool)
    case data(Data), date(Date), array([NiKPlistValue]), dictionary([String: NiKPlistValue])

    init(_ value: Any) throws {
        var remaining = 100_000
        self = try Self.decode(value, depth: 0, remaining: &remaining)
    }
    private static func decode(_ value: Any, depth: Int, remaining: inout Int) throws -> NiKPlistValue {
        guard depth <= 64, remaining > 0 else { throw Failure.tooComplex }
        remaining -= 1
        switch value {
        case let value as String: return .string(value)
        case let value as Data: return .data(value)
        case let value as Date: return .date(value)
        case let value as NSNumber:
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool(value.boolValue) }
            if ["f", "d"].contains(String(cString: value.objCType)) { return .real(value.doubleValue) }
            if String(cString: value.objCType) == "Q", value.uint64Value > UInt64(Int64.max) { return .unsigned(value.uint64Value) }
            return .integer(value.int64Value)
        case let value as [Any]: return .array(try value.map { try decode($0, depth: depth + 1, remaining: &remaining) })
        case let value as [String: Any]: return .dictionary(try value.mapValues { try decode($0, depth: depth + 1, remaining: &remaining) })
        default: throw Failure.unsupportedValue
        }
    }
    var foundationValue: Any {
        switch self {
        case .string(let v): return v
        case .integer(let v): return NSNumber(value: v)
        case .unsigned(let v): return NSNumber(value: v)
        case .real(let v): return NSNumber(value: v)
        case .bool(let v): return NSNumber(value: v)
        case .data(let v): return v
        case .date(let v): return v
        case .array(let v): return v.map(\.foundationValue)
        case .dictionary(let v): return v.mapValues(\.foundationValue)
        }
    }
    var displayText: String {
        switch self {
        case .string(let v): return v
        case .integer(let v): return String(v)
        case .unsigned(let v): return String(v)
        case .real(let v): return String(v)
        case .bool(let v): return v ? "true" : "false"
        case .data(let v): return "Data (\(v.count) bytes)"
        case .date(let v): return ISO8601DateFormatter().string(from: v)
        case .array(let v): return "[" + v.map(\.displayText).joined(separator: ", ") + "]"
        case .dictionary(let v): return v.keys.sorted().map { $0 + ": " + (v[$0]?.displayText ?? "") }.joined(separator: "\n")
        }
    }
    enum Failure: LocalizedError {
        case unsupportedValue, tooComplex
        var errorDescription: String? {
            switch self {
            case .unsupportedValue: return "Kiểu dữ liệu không thuộc định dạng property list."
            case .tooComplex: return "Dữ liệu plist vượt 64 cấp hoặc 100.000 mục."
            }
        }
    }
}
