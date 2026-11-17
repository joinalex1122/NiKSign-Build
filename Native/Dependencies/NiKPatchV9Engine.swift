import CryptoKit
import Foundation

#if NIKSIGN_STANDALONE_TEST
struct NiKError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
#endif

// MARK: - 3105 v2.0 / Schema v9 Workspace & Dynamic Merge Models

enum NiKContainerScope: String, Codable, CaseIterable, Hashable {
    case application = "Application"
    case appGroup = "AppGroup"
    case systemAppGroup = "SystemAppGroup"
}

enum NiKPatchRuleMode: String, Codable, CaseIterable, Hashable {
    case replaceFile = "replace"
    case mergePlist = "merge_plist"
    case mergeJSON = "merge_json"
}

struct NiKPatchSettingOption: Codable, Hashable, Identifiable {
    var id: String { value }
    var label: String
    var value: String
}

struct NiKPatchSettingField: Codable, Hashable, Identifiable {
    var id: String
    var label: String
    var type: String // string, boolean, integer, double, date, data
    var encoding: String? // utf8, base64 (for data)
    var defaultValue: String?
    var multiline: Bool?
    var canRemove: Bool?
    var options: [NiKPatchSettingOption]?

    private enum CodingKeys: String, CodingKey {
        case id, label, type, encoding
        case defaultValue = "default"
        case multiline, canRemove, options
    }

    init(
        id: String,
        label: String,
        type: String = "string",
        encoding: String? = nil,
        defaultValue: String? = "",
        multiline: Bool? = false,
        canRemove: Bool? = false,
        options: [NiKPatchSettingOption]? = nil
    ) {
        self.id = id
        self.label = label
        self.type = type
        self.encoding = encoding
        self.defaultValue = defaultValue
        self.multiline = multiline
        self.canRemove = canRemove
        self.options = options
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        label = try container.decode(String.self, forKey: .label)
        type = try container.decode(String.self, forKey: .type)
        encoding = try container.decodeIfPresent(String.self, forKey: .encoding)
        multiline = try container.decodeIfPresent(Bool.self, forKey: .multiline)
        canRemove = try container.decodeIfPresent(Bool.self, forKey: .canRemove)
        options = try container.decodeIfPresent([NiKPatchSettingOption].self, forKey: .options)
        if let str = try? container.decodeIfPresent(String.self, forKey: .defaultValue) {
            defaultValue = str
        } else if let b = try? container.decodeIfPresent(Bool.self, forKey: .defaultValue) {
            defaultValue = b ? "true" : "false"
        } else if let i = try? container.decodeIfPresent(Int64.self, forKey: .defaultValue) {
            defaultValue = String(i)
        } else if let d = try? container.decodeIfPresent(Double.self, forKey: .defaultValue) {
            defaultValue = String(d)
        } else {
            defaultValue = nil
        }
    }
}

struct NiKPatchSettingsSchema: Codable, Hashable {
    var schemaVersion: Int
    var fields: [NiKPatchSettingField]

    init(schemaVersion: Int = 1, fields: [NiKPatchSettingField] = []) {
        self.schemaVersion = schemaVersion
        self.fields = fields
    }
}

struct NiKPatchFieldUserValue: Codable, Hashable {
    var stringValue: String
    var removeField: Bool
}

struct NiKWorkspaceV9Rule: Codable, Identifiable, Hashable {
    var id: UUID
    var scope: NiKContainerScope
    var identifier: String
    var relativePath: String
    var mode: NiKPatchRuleMode
    var payloadData: Data

    init(
        id: UUID = UUID(),
        scope: NiKContainerScope,
        identifier: String,
        relativePath: String,
        mode: NiKPatchRuleMode,
        payloadData: Data
    ) {
        self.id = id
        self.scope = scope
        self.identifier = identifier
        self.relativePath = relativePath
        self.mode = mode
        self.payloadData = payloadData
    }
}

struct NiKWorkspaceV9Project: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var schemaVersion: Int // up to 9
    var settings: NiKPatchSettingsSchema
    var rules: [NiKWorkspaceV9Rule]
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        schemaVersion: Int = 9,
        settings: NiKPatchSettingsSchema = NiKPatchSettingsSchema(),
        rules: [NiKWorkspaceV9Rule] = [],
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.schemaVersion = schemaVersion
        self.settings = settings
        self.rules = rules
        self.updatedAt = updatedAt
    }
}

struct NiKWorkspaceV9BackupEntry: Codable {
    let scope: NiKContainerScope
    let identifier: String
    let relativePath: String
    let existedBefore: Bool
    let originalBytes: Data?
}

struct NiKWorkspaceV9BackupReceipt: Codable, Identifiable {
    var id: UUID { projectID }
    let projectID: UUID
    let projectName: String
    let appliedAt: Date
    let entries: [NiKWorkspaceV9BackupEntry]
}

// MARK: - Container Resolution (Application + AppGroup + SystemAppGroup)

enum NiKContainerResolver {
    static let appGroupRoot = "/private/var/mobile/Containers/Shared/AppGroup"
    static let systemGroupRoot = "/private/var/containers/Shared/SystemGroup"

    static func resolveContainerURL(scope: NiKContainerScope, identifier: String) throws -> URL {
        switch scope {
        case .application:
            _ = try PatchPathValidator.canonicalBundleIdentifier(identifier)
            #if !NIKSIGN_STANDALONE_TEST
            if let path = ContainerStore.resolveAppContainerPath(bundleID: identifier) {
                return PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
            }
            #endif
            throw NiKError("Không tìm thấy hoặc chưa cấp quyền Data Container cho ứng dụng \(identifier).")
        case .appGroup:
            guard identifier.hasPrefix("group."),
                  (try? PatchPathValidator.canonicalBundleIdentifier(identifier)) == identifier else {
                throw NiKError("Identifier của AppGroup phải bắt đầu bằng 'group.' (\(identifier)).")
            }
            #if !NIKSIGN_STANDALONE_TEST
            var lookupError: NSString?
            if let path = MCMActivateContainerPath(7, identifier, true, &lookupError), !path.isEmpty {
                return PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
            }
            #endif
            if let scanned = scanGroupContainer(root: appGroupRoot, identifier: identifier) {
                return scanned
            }
            throw NiKError("Không mở được AppGroup '\(identifier)'.")
        case .systemAppGroup:
            guard identifier.hasPrefix("systemgroup.") else {
                throw NiKError("Identifier của SystemAppGroup phải bắt đầu bằng 'systemgroup.'.")
            }
            #if !NIKSIGN_STANDALONE_TEST
            var lookupError: NSString?
            if let path = MCMActivateContainerPath(12, identifier, true, &lookupError), !path.isEmpty {
                return PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
            }
            #endif
            if let scanned = scanGroupContainer(root: systemGroupRoot, identifier: identifier) {
                return scanned
            }
            throw NiKError("Không mở được SystemAppGroup '\(identifier)'.")
        }
    }

    private static func scanGroupContainer(root: String, identifier: String) -> URL? {
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: root) else { return nil }
        for item in items where UUID(uuidString: item) != nil {
            let dirPath = (root as NSString).appendingPathComponent(item)
            let metaPath = (dirPath as NSString).appendingPathComponent(".com.apple.mobile_container_manager.metadata.plist")
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: metaPath)),
                  let plist = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
                  let id = plist["MCMMetadataIdentifier"] as? String,
                  id == identifier else {
                continue
            }
            return PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: dirPath, isDirectory: true))
        }
        return nil
    }
}

// MARK: - Dynamic Plist/JSON Merger (%3105_Overwrite%, %3105_Remove%, %3105_MatchPrefix%, {{placeholder}})

enum NiKDynamicPayloadMerger {
    static let overwriteMarker = "%3105_Overwrite%"
    static let removeMarker = "%3105_Remove%"
    static let matchPrefixMarker = "%3105_MatchPrefix%"

    static func stripOverwritePrefix(fromFilename filename: String) -> (cleanName: String, hasOverwritePrefix: Bool) {
        if filename.hasPrefix(overwriteMarker) {
            let stripped = String(filename.dropFirst(overwriteMarker.count))
            return (stripped.isEmpty ? filename : stripped, true)
        }
        return (filename, false)
    }

    /// Reads the live value of a `%3105_MatchPrefix%` key from an on-device plist or JSON file to pre-populate `settings.json` input fields.
    static func readMatchedPrefixValues(
        fromTargetData targetData: Data,
        payloadData: Data,
        isPlist: Bool,
        schema: NiKPatchSettingsSchema
    ) throws -> [String: String] {
        let targetDict = try decodeRootDictionary(from: targetData, isPlist: isPlist)
        let payloadDict = try decodeRootDictionary(from: payloadData, isPlist: isPlist)
        let fieldsByID = try validatedFields(schema)
        var extracted: [String: String] = [:]

        for (rawKey, rawVal) in payloadDict {
            guard rawKey.hasPrefix(matchPrefixMarker),
                  let strVal = rawVal as? String,
                  let fieldID = exactPlaceholderID(in: strVal),
                  let field = fieldsByID[fieldID] else {
                continue
            }
            let prefix = String(rawKey.dropFirst(matchPrefixMarker.count))
            let matchedKey = try findSingleMatchingKey(in: targetDict, prefix: prefix)
            guard let existingValue = targetDict[matchedKey] else { continue }
            if field.type == "data", let dataVal = existingValue as? Data {
                if field.encoding?.lowercased() == "utf8" {
                    extracted[fieldID] = String(decoding: dataVal, as: UTF8.self)
                } else {
                    extracted[fieldID] = dataVal.base64EncodedString()
                }
            } else {
                extracted[fieldID] = "\(existingValue)"
            }
        }
        return extracted
    }

    /// Merges a payload plist or JSON dictionary into the target file data according to 3105 v2.0 / schema v9 rules.
    static func merge(
        targetData: Data?,
        payloadData: Data,
        isPlist: Bool,
        schema: NiKPatchSettingsSchema,
        userValues: [String: NiKPatchFieldUserValue]
    ) throws -> Data {
        let targetDict: [String: Any]
        if let targetData, !targetData.isEmpty {
            targetDict = try decodeRootDictionary(from: targetData, isPlist: isPlist)
        } else {
            targetDict = [:]
        }
        let payloadDict = try decodeRootDictionary(from: payloadData, isPlist: isPlist)
        let fieldsByID = try validatedFields(schema)

        let merged = try mergeDictionaries(
            target: targetDict,
            payload: payloadDict,
            fieldsByID: fieldsByID,
            userValues: userValues,
            isPlist: isPlist
        )

        if isPlist {
            // Write deterministic XML plist so hash checks and resets remain stable across binary plist key ordering.
            return try PropertyListSerialization.data(fromPropertyList: merged, format: .xml, options: 0)
        } else {
            return try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys])
        }
    }

    private static func mergeDictionaries(
        target: [String: Any],
        payload: [String: Any],
        fieldsByID: [String: NiKPatchSettingField],
        userValues: [String: NiKPatchFieldUserValue],
        isPlist: Bool
    ) throws -> [String: Any] {
        var result: [String: Any]
        if let overwriteFlag = payload[overwriteMarker] as? Bool, overwriteFlag {
            result = [:]
        } else {
            result = target
        }

        for (rawKey, rawValue) in payload {
            if rawKey == overwriteMarker { continue }

            let resolvedKey: String
            if rawKey.hasPrefix(matchPrefixMarker) {
                let prefix = String(rawKey.dropFirst(matchPrefixMarker.count))
                resolvedKey = try findSingleMatchingKey(in: result, prefix: prefix)
            } else {
                resolvedKey = rawKey
            }

            if let strValue = rawValue as? String {
                if strValue == removeMarker {
                    result.removeValue(forKey: resolvedKey)
                    continue
                }
                if let exactID = exactPlaceholderID(in: strValue),
                   let field = fieldsByID[exactID] {
                    let userEntry = userValues[exactID]
                    if field.canRemove == true && userEntry?.removeField == true {
                        result.removeValue(forKey: resolvedKey)
                        continue
                    }
                    let rawInput = userEntry?.stringValue ?? field.defaultValue ?? ""
                    result[resolvedKey] = try coerceTypedValue(rawInput, field: field, isPlist: isPlist)
                    continue
                }
                // Check if any removable placeholder is embedded mid-string
                try ensureNoEmbeddedRemovablePlaceholder(in: strValue, fieldsByID: fieldsByID, userValues: userValues)
                result[resolvedKey] = interpolateString(strValue, fieldsByID: fieldsByID, userValues: userValues)
            } else if let nestedPayload = rawValue as? [String: Any] {
                let nestedTarget = (result[resolvedKey] as? [String: Any]) ?? [:]
                result[resolvedKey] = try mergeDictionaries(
                    target: nestedTarget,
                    payload: nestedPayload,
                    fieldsByID: fieldsByID,
                    userValues: userValues,
                    isPlist: isPlist
                )
            } else if let arrayPayload = rawValue as? [Any] {
                result[resolvedKey] = try resolveArray(
                    arrayPayload,
                    fieldsByID: fieldsByID,
                    userValues: userValues,
                    isPlist: isPlist
                )
            } else {
                result[resolvedKey] = rawValue
            }
        }
        return result
    }

    private static func resolveArray(
        _ array: [Any],
        fieldsByID: [String: NiKPatchSettingField],
        userValues: [String: NiKPatchFieldUserValue],
        isPlist: Bool
    ) throws -> [Any] {
        var output: [Any] = []
        for element in array {
            if let str = element as? String {
                // Placeholders inside an Array cannot be used for field removal; stop safely if requested.
                try ensureNoRemovablePlaceholderInArrayElement(str, fieldsByID: fieldsByID, userValues: userValues)
                if let exactID = exactPlaceholderID(in: str),
                   let field = fieldsByID[exactID] {
                    let rawInput = userValues[exactID]?.stringValue ?? field.defaultValue ?? ""
                    output.append(try coerceTypedValue(rawInput, field: field, isPlist: isPlist))
                } else {
                    output.append(interpolateString(str, fieldsByID: fieldsByID, userValues: userValues))
                }
            } else if let dict = element as? [String: Any] {
                output.append(try mergeDictionaries(
                    target: [:],
                    payload: dict,
                    fieldsByID: fieldsByID,
                    userValues: userValues,
                    isPlist: isPlist
                ))
            } else {
                output.append(element)
            }
        }
        return output
    }

    // Validate before indexing: Dictionary(uniqueKeysWithValues:) traps on duplicate IDs.
    private static func validatedFields(_ schema: NiKPatchSettingsSchema) throws -> [String: NiKPatchSettingField] {
        guard schema.fields.count <= 64 else { throw NiKError("Tối đa 64 trường settings.") }
        var fields: [String: NiKPatchSettingField] = [:]
        for field in schema.fields {
            guard !field.id.isEmpty, fields.updateValue(field, forKey: field.id) == nil else {
                throw NiKError("Trường settings có ID rỗng hoặc trùng: \(field.id).")
            }
        }
        return fields
    }

    /// Finds exactly one key in `dict` starting with `prefix` whose remaining suffix is a single segment without `/`.
    static func findSingleMatchingKey(in dict: [String: Any], prefix: String) throws -> String {
        guard !prefix.isEmpty else {
            throw NiKError("Selector %3105_MatchPrefix% không được để trống prefix.")
        }
        // O(n) worst case, O(1) auxiliary space; stop once ambiguity is established.
        var match: String?
        for key in dict.keys where key.hasPrefix(prefix) {
            let suffix = key.dropFirst(prefix.count)
            guard !suffix.isEmpty, !suffix.contains("/") else { continue }
            guard match == nil else {
                throw NiKError("Selector %3105_MatchPrefix% (\(prefix)) khớp nhiều key; yêu cầu đúng 1 key.")
            }
            match = key
        }
        guard let match else {
            throw NiKError("Selector %3105_MatchPrefix% (\(prefix)) không khớp key nào.")
        }
        return match
    }

    private static func exactPlaceholderID(in text: String) -> String? {
        guard text.hasPrefix("{{"), text.hasSuffix("}}"), text.count > 4 else { return nil }
        let inner = String(text.dropFirst(2).dropLast(2))
        guard !inner.contains("{{"), !inner.contains("}}") else { return nil }
        return inner.trimmingCharacters(in: .whitespaces)
    }

    private static func ensureNoEmbeddedRemovablePlaceholder(
        in text: String,
        fieldsByID: [String: NiKPatchSettingField],
        userValues: [String: NiKPatchFieldUserValue]
    ) throws {
        for (id, field) in fieldsByID where field.canRemove == true && userValues[id]?.removeField == true {
            if text.contains("{{\(id)}}") {
                throw NiKError("Trường '{{\(id)}}' đang bật xoá nhưng nằm giữa một chuỗi ghép; dừng an toàn theo quy tắc 3105.")
            }
        }
    }

    private static func ensureNoRemovablePlaceholderInArrayElement(
        _ text: String,
        fieldsByID: [String: NiKPatchSettingField],
        userValues: [String: NiKPatchFieldUserValue]
    ) throws {
        for (id, field) in fieldsByID where field.canRemove == true && userValues[id]?.removeField == true {
            if text.contains("{{\(id)}}") {
                throw NiKError("Trường '{{\(id)}}' nằm trong phần tử Array nên không thể dùng chức năng xoá trường; dừng an toàn.")
            }
        }
    }

    private static func interpolateString(
        _ template: String,
        fieldsByID: [String: NiKPatchSettingField],
        userValues: [String: NiKPatchFieldUserValue]
    ) -> String {
        var output = template
        for (id, field) in fieldsByID {
            let val = userValues[id]?.stringValue ?? field.defaultValue ?? ""
            output = output.replacingOccurrences(of: "{{\(id)}}", with: val)
        }
        return output
    }

    private static func coerceTypedValue(
        _ raw: String,
        field: NiKPatchSettingField,
        isPlist: Bool
    ) throws -> Any {
        switch field.type.lowercased() {
        case "string":
            return raw
        case "boolean", "bool":
            let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if normalized == "true" || normalized == "1" { return true }
            if normalized == "false" || normalized == "0" { return false }
            throw NiKError("Giá trị '\(raw)' không hợp lệ cho trường boolean '\(field.label)'.")
        case "integer", "int":
            guard let v = Int64(raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw NiKError("Giá trị '\(raw)' không hợp lệ cho trường số nguyên '\(field.label)'.")
            }
            return NSNumber(value: v)
        case "double", "float", "number":
            guard let v = Double(raw.trimmingCharacters(in: .whitespacesAndNewlines)), v.isFinite else {
                throw NiKError("Giá trị '\(raw)' không hợp lệ cho trường số thực '\(field.label)'.")
            }
            return NSNumber(value: v)
        case "date":
            let iso = ISO8601DateFormatter()
            guard let d = iso.date(from: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw NiKError("Giá trị '\(raw)' cần theo chuẩn ngày ISO-8601 (VD: 2026-09-05T08:26:04Z).")
            }
            return isPlist ? d : iso.string(from: d)
        case "data":
            let mode = (field.encoding ?? "base64").lowercased()
            let data: Data
            if mode == "utf8" {
                data = Data(raw.utf8)
            } else {
                guard let decoded = Data(base64Encoded: raw.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                    throw NiKError("Dữ liệu Base64 không hợp lệ cho trường '\(field.label)'.")
                }
                data = decoded
            }
            return isPlist ? data : data.base64EncodedString()
        default:
            return raw
        }
    }

    private static func decodeRootDictionary(from data: Data, isPlist: Bool) throws -> [String: Any] {
        guard data.count <= 8 * 1_024 * 1_024 else {
            throw NiKError("Payload plist/JSON vượt giới hạn an toàn 8 MB.")
        }
        if isPlist {
            guard let dict = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
                throw NiKError("Gốc của tệp plist phải là một Dictionary.")
            }
            return dict
        } else {
            guard let dict = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] else {
                throw NiKError("Gốc của tệp JSON phải là một Object.")
            }
            return dict
        }
    }
}

// MARK: - Workspace v9 File System & Transaction Service

enum NiKWorkspaceV9Service {
    private static let metadataFilename = ".3105-v9-manifest.json"
    private static let settingsFilename = "settings.json"

    static func patchesRootURL() throws -> URL {
        try PatchWorkspaceService.patchesRootURL()
    }

    static func backupsRootURL() throws -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("NiKSign/V9Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Creates a 3105 2.0 workspace directory with `settings.json`, `Application/`, and `AppGroup/`.
    static func createWorkspace(named rawName: String, includeSampleLocketRule: Bool = false) throws -> (workspaceURL: URL, project: NiKWorkspaceV9Project) {
        let fm = FileManager.default
        let root = try patchesRootURL()
        let cleanName = rawName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "PatchV9" : rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        var folder = root.appendingPathComponent(cleanName, isDirectory: true)
        var suffix = 2
        while fm.fileExists(atPath: folder.path) {
            folder = root.appendingPathComponent("\(cleanName) \(suffix)", isDirectory: true)
            suffix += 1
        }

        let appDir = folder.appendingPathComponent(NiKContainerScope.application.rawValue, isDirectory: true)
        let groupDir = folder.appendingPathComponent(NiKContainerScope.appGroup.rawValue, isDirectory: true)
        try fm.createDirectory(at: appDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: groupDir, withIntermediateDirectories: true)

        var defaultFields: [NiKPatchSettingField] = [
            NiKPatchSettingField(
                id: "display_name",
                label: "Tên hiển thị",
                type: "string",
                defaultValue: "3105",
                multiline: false,
                canRemove: true
            ),
            NiKPatchSettingField(
                id: "enabled",
                label: "Bật tính năng",
                type: "boolean",
                defaultValue: "true"
            )
        ]

        if includeSampleLocketRule {
            defaultFields.append(
                NiKPatchSettingField(
                    id: "subscriber_cache",
                    label: "Subscriber cache",
                    type: "data",
                    encoding: "utf8",
                    defaultValue: "{\"entitlements\":{\"pro\":true}}",
                    multiline: true
                )
            )
            let sampleAppFolder = appDir.appendingPathComponent("com.example.demo/Library/Preferences", isDirectory: true)
            try fm.createDirectory(at: sampleAppFolder, withIntermediateDirectories: true)
            let samplePlist: [String: Any] = [
                "DisplayName": "{{display_name}}",
                "Enabled": "{{enabled}}",
                "%3105_MatchPrefix%https://api.revenuecat.com/v1/subscribers/": "{{subscriber_cache}}"
            ]
            let plistData = try PropertyListSerialization.data(fromPropertyList: samplePlist, format: .xml, options: 0)
            let sampleFile = sampleAppFolder.appendingPathComponent("%3105_Overwrite%com.example.demo.plist")
            try plistData.write(to: sampleFile, options: .atomic)

            let sampleGroupFolder = groupDir.appendingPathComponent("group.com.example.shared/Library/Preferences", isDirectory: true)
            try fm.createDirectory(at: sampleGroupFolder, withIntermediateDirectories: true)
            let groupPlist: [String: Any] = [
                "SharedDisplayName": "{{display_name}}"
            ]
            let groupData = try PropertyListSerialization.data(fromPropertyList: groupPlist, format: .xml, options: 0)
            try groupData.write(to: sampleGroupFolder.appendingPathComponent("%3105_Overwrite%shared.plist"), options: .atomic)
        }

        let schema = NiKPatchSettingsSchema(schemaVersion: 1, fields: defaultFields)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let settingsData = try encoder.encode(schema)
        try settingsData.write(to: folder.appendingPathComponent(settingsFilename), options: .atomic)

        let baseProject = NiKWorkspaceV9Project(name: folder.lastPathComponent, schemaVersion: 9, settings: schema)
        try saveManifest(baseProject, at: folder)
        let synced = try synchronizeWorkspace(at: folder)
        return (folder, synced)
    }

    static func listWorkspaces() -> [(url: URL, project: NiKWorkspaceV9Project)] {
        guard let root = try? patchesRootURL(),
              let items = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }
        var result: [(url: URL, project: NiKWorkspaceV9Project)] = []
        for url in items {
            let appSub = url.appendingPathComponent(NiKContainerScope.application.rawValue)
            let groupSub = url.appendingPathComponent(NiKContainerScope.appGroup.rawValue)
            let settingsSub = url.appendingPathComponent(settingsFilename)
            if FileManager.default.fileExists(atPath: appSub.path)
                || FileManager.default.fileExists(atPath: groupSub.path)
                || FileManager.default.fileExists(atPath: settingsSub.path) {
                if let synced = try? synchronizeWorkspace(at: url) {
                    result.append((url, synced))
                }
            }
        }
        return result.sorted { $0.project.name.localizedCaseInsensitiveCompare($1.project.name) == .orderedAscending }
    }

    /// Scans `settings.json`, `Application/`, `AppGroup/`, and legacy `SystemAppGroup/` inside a workspace directory.
    static func synchronizeWorkspace(at workspaceURL: URL) throws -> NiKWorkspaceV9Project {
        let fm = FileManager.default
        let existingManifest = try? loadManifest(at: workspaceURL)
        let settingsURL = workspaceURL.appendingPathComponent(settingsFilename)
        let schema: NiKPatchSettingsSchema
        if fm.fileExists(atPath: settingsURL.path) {
            let raw = try Data(contentsOf: settingsURL)
            guard raw.count <= 256 * 1_024 else {
                throw NiKError("settings.json vượt giới hạn 256 KB.")
            }
            schema = try JSONDecoder().decode(NiKPatchSettingsSchema.self, from: raw)
            guard schema.fields.count <= 64 else {
                throw NiKError("settings.json vượt giới hạn 64 trường nhập.")
            }
            var seenIDs = Set<String>()
            for f in schema.fields {
                guard !f.id.isEmpty, seenIDs.insert(f.id).inserted else {
                    throw NiKError("settings.json có trường id rỗng hoặc bị trùng lặp ('\(f.id)').")
                }
            }
        } else {
            schema = existingManifest?.settings ?? NiKPatchSettingsSchema()
        }

        var previousModes: [String: NiKPatchRuleMode] = [:]
        for rule in existingManifest?.rules ?? [] {
            let key = "\(rule.scope.rawValue):\(rule.identifier):\(rule.relativePath)"
            guard previousModes.updateValue(rule.mode, forKey: key) == nil else {
                throw NiKError("Manifest chứa đường dẫn trùng lặp: \(rule.relativePath).")
            }
        }

        var discoveredRules: [NiKWorkspaceV9Rule] = []
        for scope in NiKContainerScope.allCases {
            let scopeDir = workspaceURL.appendingPathComponent(scope.rawValue, isDirectory: true)
            guard fm.fileExists(atPath: scopeDir.path) else { continue }
            let identifierFolders = try fm.contentsOfDirectory(
                at: scopeDir,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            )
            for idURL in identifierFolders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let vals = try idURL.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                guard vals.isSymbolicLink != true else {
                    throw NiKError("Workspace không hỗ trợ symbolic link.")
                }
                guard vals.isDirectory == true else { continue }
                let identifier = idURL.lastPathComponent
                if scope == .appGroup && !identifier.hasPrefix("group.") {
                    throw NiKError("Thư mục trong vùng AppGroup phải bắt đầu bằng 'group.' (\(identifier)).")
                }
                if scope == .systemAppGroup && !identifier.hasPrefix("systemgroup.") {
                    throw NiKError("Thư mục trong vùng SystemAppGroup phải bắt đầu bằng 'systemgroup.' (\(identifier)).")
                }
                _ = try PatchPathValidator.canonicalBundleIdentifier(identifier)

                guard let enumerator = fm.enumerator(
                    at: idURL,
                    includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                for case let itemURL as URL in enumerator {
                    let itemVals = try itemURL.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
                    if itemVals.isSymbolicLink == true {
                        throw NiKError("Workspace không chấp nhận symbolic link (\(itemURL.lastPathComponent)).")
                    }
                    guard itemVals.isRegularFile == true else { continue }

                    let rootPrefix = idURL.standardizedFileURL.path + "/"
                    let itemPath = itemURL.standardizedFileURL.path
                    guard itemPath.hasPrefix(rootPrefix) else {
                        throw NiKError("Đường dẫn tệp vượt ra ngoài thư mục identifier.")
                    }
                    let rawRelPath = String(itemPath.dropFirst(rootPrefix.count))
                    let dirComponents = (rawRelPath as NSString).deletingLastPathComponent
                    let rawFilename = (rawRelPath as NSString).lastPathComponent
                    let (cleanFilename, hasOverwritePrefix) = NiKDynamicPayloadMerger.stripOverwritePrefix(fromFilename: rawFilename)
                    let finalRelPath = dirComponents.isEmpty ? cleanFilename : "\(dirComponents)/\(cleanFilename)"
                    let canonicalRelPath = try PatchPathValidator.canonicalRelativePath(finalRelPath)

                    let lookupKey = "\(scope.rawValue):\(identifier):\(canonicalRelPath)"
                    let ext = (cleanFilename as NSString).pathExtension.lowercased()
                    let defaultMode: NiKPatchRuleMode
                    if hasOverwritePrefix {
                        defaultMode = (ext == "json") ? .mergeJSON : .mergePlist
                    } else if let prev = previousModes[lookupKey] {
                        defaultMode = prev
                    } else {
                        defaultMode = .replaceFile
                    }

                    let payload = try Data(contentsOf: itemURL)
                    discoveredRules.append(
                        NiKWorkspaceV9Rule(
                            scope: scope,
                            identifier: identifier,
                            relativePath: canonicalRelPath,
                            mode: defaultMode,
                            payloadData: payload
                        )
                    )
                }
            }
        }

        // Reject duplicate targets within the same scope + identifier
        var uniqueTargets = Set<String>()
        for rule in discoveredRules {
            let key = "\(rule.scope.rawValue):\(rule.identifier):\(rule.relativePath)"
            guard uniqueTargets.insert(key).inserted else {
                throw NiKError("Trùng lặp đường dẫn đích '\(rule.relativePath)' trong \(rule.scope.rawValue)/\(rule.identifier).")
            }
        }

        let updated = NiKWorkspaceV9Project(
            id: existingManifest?.id ?? UUID(),
            name: existingManifest?.name ?? workspaceURL.lastPathComponent,
            schemaVersion: 9,
            settings: schema,
            rules: discoveredRules,
            updatedAt: Date()
        )
        try saveManifest(updated, at: workspaceURL)
        return updated
    }

    // Serialize apply/restore so two callers cannot overwrite the same journal.
    private static let transactionLock = NSLock()
    private static let maxFileBytes = 32 * 1_024 * 1_024
    private static let maxTransactionBytes = 128 * 1_024 * 1_024

    private struct ContainerKey: Hashable {
        let scope: NiKContainerScope
        let identifier: String
    }

    private struct PreparedWrite {
        let target: URL
        let backup: NiKWorkspaceV9BackupEntry
        let output: Data
    }

    /// Reject symlinks in target paths, including dangling links and parent directory links.
    private static func checkedTarget(path: String, root: URL) throws -> URL {
        let root = root.resolvingSymlinksInPath()
        let target = try PatchPathValidator.resolveContainedTargetURL(relativePath: path, containerRoot: root)
        var current = root
        for component in try PatchPathValidator.canonicalRelativePath(path).split(separator: "/") {
            current.appendPathComponent(String(component))
            if let attributes = try? FileManager.default.attributesOfItem(atPath: current.path),
               attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                throw NiKError("Patch không hỗ trợ symbolic link: \(path).")
            }
        }
        return target
    }

    private static func receiptURL(projectID: UUID, directory: URL?) throws -> URL {
        let root = try directory ?? backupsRootURL()
        return root.appendingPathComponent("\(projectID.uuidString).json")
    }

    private static func saveReceipt(_ receipt: NiKWorkspaceV9BackupReceipt, to url: URL) throws {
        try JSONEncoder().encode(receipt).write(to: url, options: [.atomic, .completeFileProtection])
    }

    /// Prepare all outputs, persist originals, then mutate targets. A pending receipt must
    /// be restored before reapplying, preserving the first original across crashes/retries.
    static func apply(
        project: NiKWorkspaceV9Project,
        userValues: [String: NiKPatchFieldUserValue],
        customContainerResolver: ((NiKContainerScope, String) throws -> URL)? = nil,
        backupDirectory: URL? = nil
    ) throws -> (receipt: NiKWorkspaceV9BackupReceipt, appliedCount: Int, skippedIdentifiers: [String]) {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let fm = FileManager.default
        let journal = try receiptURL(projectID: project.id, directory: backupDirectory)
        guard !fm.fileExists(atPath: journal.path) else {
            throw NiKError("Patch này có bản sao lưu chưa khôi phục. Hãy Restore trước khi áp dụng lại.")
        }
        guard !project.rules.isEmpty, project.rules.count <= 10_000 else {
            throw NiKError("Dự án cần từ 1 đến 10.000 quy tắc.")
        }
        let resolver = customContainerResolver ?? NiKContainerResolver.resolveContainerURL
        var resolved: [ContainerKey: URL] = [:]
        var unavailable = Set<ContainerKey>()
        var skipped: [String] = []
        var targets = Set<String>()
        var prepared: [PreparedWrite] = []
        var byteCount = 0

        for rule in project.rules {
            let key = ContainerKey(scope: rule.scope, identifier: rule.identifier)
            if unavailable.contains(key) { continue }
            if resolved[key] == nil {
                do { resolved[key] = try resolver(rule.scope, rule.identifier) }
                catch {
                    unavailable.insert(key)
                    skipped.append("\(rule.scope.rawValue)/\(rule.identifier)")
                    continue
                }
            }
            guard let root = resolved[key] else { continue }
            let target = try checkedTarget(path: rule.relativePath, root: root)
            guard targets.insert(target.path).inserted else {
                throw NiKError("Nhiều quy tắc cùng ghi một tệp: \(rule.relativePath).")
            }
            guard rule.payloadData.count <= maxFileBytes else { throw NiKError("Payload vượt 32 MB.") }
            let existed = fm.fileExists(atPath: target.path)
            var original: Data?
            if existed {
                let attrs = try fm.attributesOfItem(atPath: target.path)
                guard attrs[.type] as? FileAttributeType == .typeRegular,
                      let size = attrs[.size] as? NSNumber, size.int64Value <= Int64(maxFileBytes) else {
                    throw NiKError("Tệp gốc không hợp lệ hoặc vượt 32 MB: \(rule.relativePath).")
                }
                original = try Data(contentsOf: target)
                guard original!.count <= maxFileBytes else { throw NiKError("Tệp gốc vượt 32 MB.") }
            }
            let output: Data
            switch rule.mode {
            case .replaceFile: output = rule.payloadData
            case .mergePlist, .mergeJSON:
                output = try NiKDynamicPayloadMerger.merge(
                    targetData: original, payloadData: rule.payloadData,
                    isPlist: rule.mode == .mergePlist, schema: project.settings, userValues: userValues)
            }
            byteCount += (original?.count ?? 0) + output.count
            guard output.count <= maxFileBytes, byteCount <= maxTransactionBytes else {
                throw NiKError("Patch vượt giới hạn 32 MB/tệp hoặc 128 MB dữ liệu giao dịch.")
            }
            prepared.append(PreparedWrite(target: target, backup: NiKWorkspaceV9BackupEntry(
                scope: rule.scope, identifier: rule.identifier, relativePath: rule.relativePath,
                existedBefore: existed, originalBytes: original), output: output))
        }
        guard !prepared.isEmpty else { throw NiKError("Không truy cập được container mục tiêu nào.") }
        let receipt = NiKWorkspaceV9BackupReceipt(projectID: project.id, projectName: project.name,
            appliedAt: Date(), entries: prepared.map { $0.backup })
        // Persist before any target write. Failure here leaves all targets untouched.
        try saveReceipt(receipt, to: journal)
        var written: [PreparedWrite] = []
        do {
            for item in prepared {
                try fm.createDirectory(at: item.target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try item.output.write(to: item.target, options: .atomic)
                written.append(item)
            }
        } catch {
            let applyError = error
            var rollbackFailed = false
            for item in written.reversed() {
                do { try restoreEntry(item.backup, to: item.target) }
                catch { rollbackFailed = true }
            }
            if !rollbackFailed {
                do { try fm.removeItem(at: journal) }
                catch { rollbackFailed = true }
            }
            if rollbackFailed {
                throw NiKError("Áp dụng thất bại: \(applyError.localizedDescription). Đã giữ bản sao lưu; hãy Restore để khôi phục các tệp.")
            }
            throw applyError
        }
        return (receipt, prepared.count, skipped)
    }

    private static func restoreEntry(_ entry: NiKWorkspaceV9BackupEntry, to target: URL) throws {
        let fm = FileManager.default
        if entry.existedBefore {
            guard let original = entry.originalBytes else { throw NiKError("Bản sao lưu thiếu dữ liệu gốc.") }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try original.write(to: target, options: .atomic)
        } else if fm.fileExists(atPath: target.path) {
            try fm.removeItem(at: target)
        }
    }

    /// Retain unresolved entries on disk for a later retry; never delete a partial backup.
    static func restore(
        projectID: UUID,
        customContainerResolver: ((NiKContainerScope, String) throws -> URL)? = nil,
        backupDirectory: URL? = nil
    ) throws -> Int {
        transactionLock.lock()
        defer { transactionLock.unlock() }
        let journal = try receiptURL(projectID: projectID, directory: backupDirectory)
        let attrs = try FileManager.default.attributesOfItem(atPath: journal.path)
        guard let size = attrs[.size] as? NSNumber, size.int64Value <= 256 * 1_024 * 1_024 else {
            throw NiKError("Hồ sơ sao lưu vượt giới hạn 256 MB.")
        }
        let receipt = try JSONDecoder().decode(NiKWorkspaceV9BackupReceipt.self, from: Data(contentsOf: journal))
        guard receipt.projectID == projectID, receipt.entries.count <= 10_000,
              receipt.entries.allSatisfy({ $0.existedBefore == ($0.originalBytes != nil) }) else {
            throw NiKError("Hồ sơ sao lưu không hợp lệ; đã giữ lại để kiểm tra.")
        }
        let resolver = customContainerResolver ?? NiKContainerResolver.resolveContainerURL
        var roots: [ContainerKey: URL] = [:]
        var unavailable = Set<ContainerKey>()
        var pending: [NiKWorkspaceV9BackupEntry] = []
        var count = 0
        for entry in receipt.entries.reversed() {
            let key = ContainerKey(scope: entry.scope, identifier: entry.identifier)
            do {
                if unavailable.contains(key) { throw NiKError("Container chưa truy cập được.") }
                if roots[key] == nil {
                    do { roots[key] = try resolver(entry.scope, entry.identifier) }
                    catch { unavailable.insert(key); throw error }
                }
                guard let root = roots[key] else { throw NiKError("Thiếu container.") }
                let target = try checkedTarget(path: entry.relativePath, root: root)
                try restoreEntry(entry, to: target)
                count += 1
            } catch { pending.append(entry) }
        }
        if !pending.isEmpty {
            try saveReceipt(NiKWorkspaceV9BackupReceipt(projectID: projectID,
                projectName: receipt.projectName, appliedAt: receipt.appliedAt,
                entries: Array(pending.reversed())), to: journal)
            throw NiKError("Đã khôi phục \(count) tệp; còn \(pending.count) mục chưa khôi phục. Bản sao lưu được giữ để thử lại.")
        }
        try FileManager.default.removeItem(at: journal)
        return count
    }

    static func hasBackupReceipt(projectID: UUID) -> Bool {
        guard let url = try? backupsRootURL().appendingPathComponent("\(projectID.uuidString).json") else {
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    static func saveManifest(_ project: NiKWorkspaceV9Project, at workspaceURL: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(project)
        try data.write(to: workspaceURL.appendingPathComponent(metadataFilename), options: [.atomic, .completeFileProtection])
    }

    static func loadManifest(at workspaceURL: URL) throws -> NiKWorkspaceV9Project {
        let data = try Data(contentsOf: workspaceURL.appendingPathComponent(metadataFilename))
        return try JSONDecoder().decode(NiKWorkspaceV9Project.self, from: data)
    }
}
