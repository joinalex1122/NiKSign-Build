import Foundation
import SwiftUI

// MARK: - 3105 2.0 System Features: Lock Screen Footnote, Supervised Mode & Installable Cleaner Feature

@MainActor
final class NiKSystemFeaturesStore: ObservableObject {
    @Published var isCleanerInstalled: Bool {
        didSet {
            UserDefaults.standard.set(isCleanerInstalled, forKey: Self.cleanerInstalledKey)
        }
    }
    @Published var footnoteText: String = ""
    @Published var isSupervisedEnabled: Bool = false
    @Published var organizationName: String = "3105 Research"
    @Published var lastStatusMessage: String = ""

    static let cleanerInstalledKey = FeatureVisibility.cleanerStorageKey

    private let backupDir: URL

    init() {
        if UserDefaults.standard.object(forKey: Self.cleanerInstalledKey) == nil {
            UserDefaults.standard.set(true, forKey: Self.cleanerInstalledKey)
        }
        self.isCleanerInstalled = UserDefaults.standard.bool(forKey: Self.cleanerInstalledKey)
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = appSupport.appendingPathComponent("NiKSign/SystemFeaturesBackup", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.backupDir = dir
        refreshCurrentDeviceConfig()
    }

    func toggleCleanerInstallation() {
        isCleanerInstalled.toggle()
        lastStatusMessage = isCleanerInstalled
            ? "Đã cài đặt tính năng Dọn dẹp (Cleaner) vào mục Đã cài & Trang chủ."
            : "Đã gỡ tính năng Dọn dẹp (Cleaner) khỏi danh sách đang kích hoạt."
    }

    /// Resolves the target configuration plist path for Lock Screen Footnote & Supervised state
    /// via Shared System Group, App Group, or SpringBoard container.
    private nonisolated static func resolveSharedConfigurationPlistURL() throws -> URL {
        let candidateGroups: [(NiKContainerScope, String, String)] = [
            (.systemAppGroup, "systemgroup.com.apple.configurationprofiles", "Library/ConfigurationProfiles/SharedDeviceConfiguration.plist"),
            (.appGroup, "group.com.apple.configurationprofiles", "Library/ConfigurationProfiles/SharedDeviceConfiguration.plist"),
            (.application, "com.apple.springboard", "Library/ConfigurationProfiles/SharedDeviceConfiguration.plist"),
            (.application, "com.apple.Preferences", "Library/ConfigurationProfiles/SharedDeviceConfiguration.plist")
        ]
        for (scope, id, relPath) in candidateGroups {
            if let root = try? NiKContainerResolver.resolveContainerURL(scope: scope, identifier: id) {
                return try PatchPathValidator.resolveContainedTargetURL(relativePath: relPath, containerRoot: root)
            }
        }
        throw NiKError("Không truy cập được container ConfigurationProfiles/SpringBoard trên thiết bị hiện tại. Hãy xác nhận quyền khai thác thiết bị đã bật.")
    }

    private nonisolated static func resolveCloudConfigurationPlistURL() throws -> URL {
        let candidateGroups: [(NiKContainerScope, String, String)] = [
            (.systemAppGroup, "systemgroup.com.apple.configurationprofiles", "Library/ConfigurationProfiles/CloudConfigurationDetails.plist"),
            (.appGroup, "group.com.apple.configurationprofiles", "Library/ConfigurationProfiles/CloudConfigurationDetails.plist"),
            (.application, "com.apple.Preferences", "Library/ConfigurationProfiles/CloudConfigurationDetails.plist"),
            (.application, "com.apple.springboard", "Library/ConfigurationProfiles/CloudConfigurationDetails.plist")
        ]
        for (scope, id, relPath) in candidateGroups {
            if let root = try? NiKContainerResolver.resolveContainerURL(scope: scope, identifier: id) {
                return try PatchPathValidator.resolveContainedTargetURL(relativePath: relPath, containerRoot: root)
            }
        }
        throw NiKError("Không truy cập được container CloudConfigurationDetails trên thiết bị hiện tại.")
    }

    func refreshCurrentDeviceConfig() {
        if let footnoteURL = try? Self.resolveSharedConfigurationPlistURL(),
           let data = try? Data(contentsOf: footnoteURL),
           let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
           let text = dict["LockScreenFootnote"] as? String {
            footnoteText = text
        }
        if let cloudURL = try? Self.resolveCloudConfigurationPlistURL(),
           let data = try? Data(contentsOf: cloudURL),
           let dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any] {
            isSupervisedEnabled = (dict["IsSupervised"] as? Bool) ?? false
            if let org = dict["OrganizationName"] as? String, !org.isEmpty {
                organizationName = org
            }
        }
    }

    func applyFootnote() {
        do {
            let trimmed = footnoteText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.utf8.count <= 256 else {
                throw NiKError("Footnote màn hình khóa tối đa 256 byte.")
            }
            let targetURL = try Self.resolveSharedConfigurationPlistURL()
            try backupIfNeeded(targetURL: targetURL, backupName: "SharedDeviceConfiguration.plist")

            var dict: [String: Any] = [:]
            if let existing = try? Data(contentsOf: targetURL),
               let parsed = (try? PropertyListSerialization.propertyList(from: existing, options: [], format: nil)) as? [String: Any] {
                dict = parsed
            }
            if trimmed.isEmpty {
                dict.removeValue(forKey: "LockScreenFootnote")
            } else {
                dict["LockScreenFootnote"] = trimmed
            }
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let outData = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try outData.write(to: targetURL, options: .atomic)
            lastStatusMessage = "Đã ghi Footnote màn hình khóa vào \(targetURL.lastPathComponent)."
        } catch {
            lastStatusMessage = error.localizedDescription
        }
    }

    func applySupervisedState() {
        do {
            let targetURL = try Self.resolveCloudConfigurationPlistURL()
            try backupIfNeeded(targetURL: targetURL, backupName: "CloudConfigurationDetails.plist")

            var dict: [String: Any] = [:]
            if let existing = try? Data(contentsOf: targetURL),
               let parsed = (try? PropertyListSerialization.propertyList(from: existing, options: [], format: nil)) as? [String: Any] {
                dict = parsed
            }
            dict["IsSupervised"] = isSupervisedEnabled
            dict["AllowPairing"] = true
            dict["ConfigurationWasApplied"] = true
            let cleanOrg = organizationName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanOrg.isEmpty {
                dict["OrganizationName"] = cleanOrg
            }
            try FileManager.default.createDirectory(at: targetURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let outData = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
            try outData.write(to: targetURL, options: .atomic)
            lastStatusMessage = "Đã cập nhật trạng thái Supervised = \(isSupervisedEnabled ? "Bật" : "Tắt")."
        } catch {
            lastStatusMessage = error.localizedDescription
        }
    }

    func restoreOriginalSystemConfigs() {
        do {
            var count = 0
            if let footnoteURL = try? Self.resolveSharedConfigurationPlistURL(),
               try restoreBackup(backupName: "SharedDeviceConfiguration.plist", to: footnoteURL) {
                count += 1
            }
            if let cloudURL = try? Self.resolveCloudConfigurationPlistURL(),
               try restoreBackup(backupName: "CloudConfigurationDetails.plist", to: cloudURL) {
                count += 1
            }
            refreshCurrentDeviceConfig()
            lastStatusMessage = count > 0
                ? "Đã khôi phục \(count) tệp cấu hình Footnote/Supervised về bản gốc."
                : "Chưa có bản sao lưu Footnote/Supervised nào cần khôi phục."
        } catch {
            lastStatusMessage = error.localizedDescription
        }
    }

    private func backupIfNeeded(targetURL: URL, backupName: String) throws {
        let backupFile = backupDir.appendingPathComponent(backupName)
        let markerFile = backupDir.appendingPathComponent(backupName + ".existed")
        guard !FileManager.default.fileExists(atPath: markerFile.path) else { return }
        if FileManager.default.fileExists(atPath: targetURL.path) {
            let orig = try Data(contentsOf: targetURL)
            try orig.write(to: backupFile, options: [.atomic, .completeFileProtection])
            try Data("1".utf8).write(to: markerFile, options: .atomic)
        } else {
            try Data("0".utf8).write(to: markerFile, options: .atomic)
        }
    }

    private func restoreBackup(backupName: String, to targetURL: URL) throws -> Bool {
        let backupFile = backupDir.appendingPathComponent(backupName)
        let markerFile = backupDir.appendingPathComponent(backupName + ".existed")
        guard FileManager.default.fileExists(atPath: markerFile.path),
              let marker = try? String(contentsOf: markerFile, encoding: .utf8) else {
            return false
        }
        if marker == "1", FileManager.default.fileExists(atPath: backupFile.path) {
            let orig = try Data(contentsOf: backupFile)
            try orig.write(to: targetURL, options: .atomic)
        } else if FileManager.default.fileExists(atPath: targetURL.path) {
            try FileManager.default.removeItem(at: targetURL)
        }
        try? FileManager.default.removeItem(at: backupFile)
        try? FileManager.default.removeItem(at: markerFile)
        return true
    }
}
