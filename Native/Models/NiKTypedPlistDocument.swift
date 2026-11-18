import Foundation

enum NiKPlistPathPart: Codable, Hashable, Sendable { case key(String), index(Int) }
struct NiKPlistSemanticChange: Sendable {
    let path: [NiKPlistPathPart]
    let before: NiKPlistValue?
    let after: NiKPlistValue?
}
struct NiKPlistSemanticDiff: Sendable { let preview: [NiKPlistSemanticChange]; let totalChanges: Int }

struct NiKTypedPlistDocument: Sendable {
    enum Format: String, CaseIterable, Sendable { case xml, binary }
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    let snapshot: NiKEditableFileSnapshot
    private let baseline: NiKPlistValue
    private let baselineFormat: Format
    private(set) var value: NiKPlistValue
    var format: Format
    var isDirty: Bool { format != baselineFormat || !Self.same(value, baseline) }
    static let maximumBytes = 4 * 1_048_576

    init(snapshot: NiKEditableFileSnapshot) throws {
        guard snapshot.data.count <= Self.maximumBytes else { throw Failure(message: "Trình sửa plist có kiểu giới hạn 4 MB.") }
        var inputFormat = PropertyListSerialization.PropertyListFormat.binary
        let object = try PropertyListSerialization.propertyList(from: snapshot.data, format: &inputFormat)
        guard inputFormat == .binary || inputFormat == .xml else { throw Failure(message: "OpenStep chưa hỗ trợ trong trình sửa có kiểu; hãy dùng trình sửa văn bản.") }
        // Check expanded Foundation values before creating the Swift tree. Binary
        // plist references may repeat a large Data/String object many times.
        var nodes = 100_000, bytes = 8 * 1_048_576
        try Self.checkFoundation(object, depth: 0, nodes: &nodes, bytes: &bytes)
        let parsed = try NiKPlistValue(object)
        try Self.validate(parsed)
        guard NSDictionary(dictionary: ["root": object]).isEqual(to: ["root": parsed.foundationValue]) else {
            throw Failure(message: "Không biểu diễn đủ dữ liệu gốc bằng cây có kiểu; giữ nguyên tệp.")
        }
        self.snapshot = snapshot; value = parsed; baseline = parsed
        format = inputFormat == .binary ? .binary : .xml; baselineFormat = format
    }
    func node(at path: [NiKPlistPathPart]) throws -> NiKPlistValue {
        guard path.count <= 64 else { throw Failure(message: "Đường dẫn plist quá sâu.") }
        return try path.reduce(value) { node, part in
            switch (node, part) {
            case (.dictionary(let values), .key(let key)):
                guard let value = values[key] else { throw Failure(message: "Khóa plist không tồn tại.") }; return value
            case (.array(let values), .index(let index)):
                guard values.indices.contains(index) else { throw Failure(message: "Chỉ số mảng không tồn tại.") }; return values[index]
            default: throw Failure(message: "Đường dẫn không khớp kiểu dictionary/array.")
            }
        }
    }
    mutating func replace(at path: [NiKPlistPathPart], with newValue: NiKPlistValue) throws {
        try Self.validate(newValue)
        let updated = try Self.changing(value, path: ArraySlice(path), replacement: newValue)
        try Self.validate(updated); value = updated
    }
    mutating func remove(at path: [NiKPlistPathPart]) throws {
        guard !path.isEmpty else { throw Failure(message: "Không thể xóa nút gốc của plist.") }
        let updated = try Self.changing(value, path: ArraySlice(path), replacement: nil)
        try Self.validate(updated); value = updated
    }
    mutating func insert(key: String, value: NiKPlistValue, into path: [NiKPlistPathPart]) throws {
        guard case .dictionary(var values) = try node(at: path) else { throw Failure(message: "Đích không phải dictionary.") }
        guard values[key] == nil else { throw Failure(message: "Khóa đã tồn tại; không ghi đè ngầm.") }
        values[key] = value
        try replace(at: path, with: .dictionary(values))
    }
    mutating func append(_ newValue: NiKPlistValue, to path: [NiKPlistPathPart]) throws {
        guard case .array(var values) = try node(at: path) else { throw Failure(message: "Đích không phải array.") }
        values.append(newValue); try replace(at: path, with: .array(values))
    }
    mutating func moveArrayElement(at path: [NiKPlistPathPart], from: Int, to: Int) throws {
        guard case .array(var values) = try node(at: path), values.indices.contains(from), values.indices.contains(to) else { throw Failure(message: "Chỉ số di chuyển mảng không hợp lệ.") }
        let moved = values.remove(at: from); values.insert(moved, at: to)
        try replace(at: path, with: .array(values))
    }
    private static func changing(_ node: NiKPlistValue, path: ArraySlice<NiKPlistPathPart>, replacement: NiKPlistValue?) throws -> NiKPlistValue {
        guard path.count <= 64 else { throw Failure(message: "Đường dẫn plist quá sâu.") }
        guard let part = path.first else {
            guard let replacement else { throw Failure(message: "Không thể xóa nút gốc.") }; return replacement
        }
        switch (node, part) {
        case (.dictionary(var values), .key(let key)):
            guard let child = values[key] else { throw Failure(message: "Khóa plist không tồn tại.") }
            if path.count == 1 && replacement == nil { values.removeValue(forKey: key) }
            else { values[key] = try changing(child, path: path.dropFirst(), replacement: replacement) }
            return .dictionary(values)
        case (.array(var values), .index(let index)):
            guard values.indices.contains(index) else { throw Failure(message: "Chỉ số mảng không tồn tại.") }
            if path.count == 1 && replacement == nil { values.remove(at: index) }
            else { values[index] = try changing(values[index], path: path.dropFirst(), replacement: replacement) }
            return .array(values)
        default: throw Failure(message: "Đường dẫn không khớp kiểu giá trị.")
        }
    }
    func encoded() throws -> Data {
        guard isDirty else { return snapshot.data }
        try Self.validate(value)
        let data = try PropertyListSerialization.data(fromPropertyList: value.foundationValue, format: format == .binary ? .binary : .xml, options: 0)
        guard data.count <= Self.maximumBytes else { throw Failure(message: "Plist sau sửa vượt 4 MB.") }
        let roundTrip = try NiKPlistValue(PropertyListSerialization.propertyList(from: data, format: nil))
        guard Self.same(value, roundTrip) else { throw Failure(message: "Định dạng được chọn làm thay đổi kiểu/độ chính xác. Hãy chọn nhị phân hoặc sửa lại giá trị; tệp gốc chưa bị thay đổi.") }
        return data
    }
    func diff(limit: Int = 200) -> NiKPlistSemanticDiff {
        var preview: [NiKPlistSemanticChange] = [], total = 0
        let cap = max(0, min(1_000, limit))
        func visit(_ before: NiKPlistValue?, _ after: NiKPlistValue?, path: [NiKPlistPathPart]) {
            if let before, let after, Self.same(before, after) { return }
            switch (before, after) {
            case (.dictionary(let old)?, .dictionary(let new)?):
                for key in old.keys.sorted() {
                    if let index = new.index(forKey: key) {
                        let pair = new[index]
                        if key.utf8.elementsEqual(pair.key.utf8) { visit(old[key], pair.value, path: path + [.key(key)]) }
                        else { visit(old[key], nil, path: path + [.key(key)]); visit(nil, pair.value, path: path + [.key(pair.key)]) }
                    } else { visit(old[key], nil, path: path + [.key(key)]) }
                }
                for key in new.keys.sorted() where old[key] == nil { visit(nil, new[key], path: path + [.key(key)]) }
            case (.array(let old)?, .array(let new)?):
                for index in 0..<max(old.count, new.count) { visit(old.indices.contains(index) ? old[index] : nil, new.indices.contains(index) ? new[index] : nil, path: path + [.index(index)]) }
            default:
                total += 1
                if preview.count < cap { preview.append(.init(path: path, before: before, after: after)) }
            }
        }
        visit(baseline, value, path: [])
        return .init(preview: preview, totalChanges: total)
    }
    static func same(_ lhs: NiKPlistValue, _ rhs: NiKPlistValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let lhs), .string(let rhs)): return lhs.utf8.elementsEqual(rhs.utf8)
        case (.real(let lhs), .real(let rhs)): return lhs.bitPattern == rhs.bitPattern
        case (.array(let lhs), .array(let rhs)): return lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { same($0, $1) }
        case (.dictionary(let lhs), .dictionary(let rhs)):
            return lhs.count == rhs.count && lhs.allSatisfy { key, value in
                guard let index = rhs.index(forKey: key) else { return false }
                let pair = rhs[index]
                return key.utf8.elementsEqual(pair.key.utf8) && same(value, pair.value)
            }
        default: return lhs == rhs
        }
    }
    private static func validate(_ root: NiKPlistValue) throws {
        var nodes = 100_000, bytes = 8 * 1_048_576
        func visit(_ value: NiKPlistValue, depth: Int) throws {
            guard depth <= 64, nodes > 0 else { throw Failure(message: "Plist vượt 64 cấp/100.000 giá trị.") }; nodes -= 1
            switch value {
            case .string(let value): bytes -= value.utf8.count
            case .data(let value): bytes -= value.count
            case .real(let value): guard value.isFinite else { throw Failure(message: "Số thực phải hữu hạn.") }
            case .date(let value): guard value.timeIntervalSince1970.isFinite else { throw Failure(message: "Ngày không hợp lệ.") }
            case .array(let values): for value in values { try visit(value, depth: depth + 1) }
            case .dictionary(let values):
                for (key, value) in values { bytes -= key.utf8.count; guard bytes >= 0 else { throw Failure(message: "Dữ liệu plist mở rộng vượt 8 MB.") }; try visit(value, depth: depth + 1) }
            default: break
            }
            guard bytes >= 0 else { throw Failure(message: "Dữ liệu plist mở rộng vượt 8 MB.") }
        }
        try visit(root, depth: 0)
    }
    private static func checkFoundation(_ value: Any, depth: Int, nodes: inout Int, bytes: inout Int) throws {
        guard depth <= 64, nodes > 0 else { throw Failure(message: "Plist vượt 64 cấp/100.000 giá trị.") }; nodes -= 1
        switch value {
        case let string as NSString:
            guard string.length <= bytes / 2 else { throw Failure(message: "Dữ liệu plist mở rộng vượt 8 MB.") }; bytes -= string.length * 2
        case let data as NSData:
            guard data.length <= bytes else { throw Failure(message: "Dữ liệu plist mở rộng vượt 8 MB.") }; bytes -= data.length
        case let array as NSArray:
            for child in array { try checkFoundation(child, depth: depth + 1, nodes: &nodes, bytes: &bytes) }
        case let dictionary as NSDictionary:
            for (key, child) in dictionary {
                guard let key = key as? NSString, key.length <= bytes / 2 else { throw Failure(message: "Khóa plist quá lớn hoặc không hợp lệ.") }
                bytes -= key.length * 2
                try checkFoundation(child, depth: depth + 1, nodes: &nodes, bytes: &bytes)
            }
        default: break
        }
    }
}
