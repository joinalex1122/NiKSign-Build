import Foundation
import ZIPFoundation

// MARK: - 3105 2.0 Dialer (.3105pass) Package Models & Installer

enum NiKDialerKeyStyle: String, Codable, CaseIterable, Hashable {
    case light = "Sáng (Light)"
    case dark = "Tối (Dark)"
    case bold = "Chữ đậm (Bold)"
}

struct NiKDialerPackageItem: Codable, Identifiable, Hashable {
    var id: String { "\(digit)-\(style.rawValue)" }
    let digit: String
    let style: NiKDialerKeyStyle
    let filename: String
    let data: Data
}

struct NiKDialerPackage: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var author: String
    var createdAt: Date
    var items: [NiKDialerPackageItem]

    var detectedStyles: [NiKDialerKeyStyle] {
        var styles = Set<NiKDialerKeyStyle>()
        for item in items { styles.insert(item.style) }
        return NiKDialerKeyStyle.allCases.filter { styles.contains($0) }
    }
}

enum NiKDialerService {
    static let targetBundleCandidates = [
        "com.apple.mobilephone",
        "com.apple.InCallService",
        "com.apple.springboard"
    ]

    private static var storageRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = appSupport.appendingPathComponent("NiKSign/DialerPackages", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static var backupRoot: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = appSupport.appendingPathComponent("NiKSign/DialerBackup", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func loadInstalledPackages() -> [NiKDialerPackage] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: storageRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls
            .filter { $0.pathExtension == "json" }
            .compactMap { try? Data(contentsOf: $0) }
            .compactMap { try? JSONDecoder().decode(NiKDialerPackage.self, from: $0) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Imports a `.3105pass` package (either JSON/plist envelope or ZIP archive containing keypad PNGs)
    /// and automatically detects Light, Dark, and Bold keypad asset variants.
    @discardableResult
    static func importPackage(from url: URL) throws -> NiKDialerPackage {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size > 0, size <= 64 * 1_024 * 1_024 else {
            throw NiKError("Gói .3105pass rỗng hoặc vượt giới hạn 64 MB.")
        }

        let data = try Data(contentsOf: url)
        let pkg: NiKDialerPackage
        if let decoded = try? JSONDecoder().decode(NiKDialerPackage.self, from: data) {
            pkg = decoded
        } else {
            // Parse ZIP-based .3105pass package
            let archive = try Archive(url: url, accessMode: .read)
            var items: [NiKDialerPackageItem] = []
            for entry in archive where entry.type == .file {
                let path = entry.path
                guard !path.contains(".."),
                      path.lowercased().hasSuffix(".png") else { continue }
                var entryData = Data()
                _ = try archive.extract(entry) { chunk in
                    entryData.append(chunk)
                }
                guard !entryData.isEmpty, entryData.count <= 8 * 1_024 * 1_024 else { continue }
                let filename = (path as NSString).lastPathComponent
                let style = classifyStyle(forFilename: filename)
                let digit = classifyDigit(forFilename: filename)
                items.append(NiKDialerPackageItem(digit: digit, style: style, filename: filename, data: entryData))
            }
            guard !items.isEmpty else {
                throw NiKError("Gói .3105pass không chứa tài nguyên phím bấm (.png) hợp lệ.")
            }
            pkg = NiKDialerPackage(
                id: UUID(),
                name: url.deletingPathExtension().lastPathComponent,
                author: "3105 Dialer",
                createdAt: Date(),
                items: items
            )
        }

        let savedURL = storageRoot.appendingPathComponent("\(pkg.id.uuidString).json")
        let encoded = try JSONEncoder().encode(pkg)
        try encoded.write(to: savedURL, options: [.atomic, .completeFileProtection])
        return pkg
    }

    @discardableResult
    static func createSamplePackage() throws -> NiKDialerPackage {
        // Minimal 1x1 PNG header bytes for sample Light, Dark, and Bold keypad entries
        let pngBytes = Data([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
            0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
            0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
            0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4,
            0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41,
            0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
            0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00,
            0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE,
            0x42, 0x60, 0x82
        ])
        var items: [NiKDialerPackageItem] = []
        for digit in ["0", "1", "2", "3", "4", "5", "6", "7", "8", "9"] {
            items.append(NiKDialerPackageItem(digit: digit, style: .light, filename: "keypad-\(digit)-white.png", data: pngBytes))
            items.append(NiKDialerPackageItem(digit: digit, style: .dark, filename: "keypad-\(digit)-dark.png", data: pngBytes))
            items.append(NiKDialerPackageItem(digit: digit, style: .bold, filename: "keypad-\(digit)-bold.png", data: pngBytes))
        }
        let sample = NiKDialerPackage(
            id: UUID(),
            name: "SampleDialer",
            author: "NiKSign 3.3",
            createdAt: Date(),
            items: items
        )
        let savedURL = storageRoot.appendingPathComponent("\(sample.id.uuidString).json")
        try JSONEncoder().encode(sample).write(to: savedURL, options: [.atomic, .completeFileProtection])
        return sample
    }

    static func classifyStyle(forFilename filename: String) -> NiKDialerKeyStyle {
        let lower = filename.lowercased()
        if lower.contains("bold") {
            return .bold
        } else if lower.contains("dark") || lower.contains("black") {
            return .dark
        } else {
            return .light
        }
    }

    static func classifyDigit(forFilename filename: String) -> String {
        for ch in filename where ch.isNumber || ch == "*" || ch == "#" {
            return String(ch)
        }
        return "?"
    }

    /// Applies the `.3105pass` keypad assets to the active TelephonyUI / MobilePhone cache container on device, backing up originals.
    static func apply(_ pkg: NiKDialerPackage) throws -> String {
        var resolvedRoot: URL?
        var resolvedBundle = ""
        for candidate in targetBundleCandidates {
            if let path = ContainerStore.resolveAppContainerPath(bundleID: candidate) {
                resolvedRoot = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
                resolvedBundle = candidate
                break
            }
        }
        guard let containerURL = resolvedRoot else {
            throw NiKError("Chưa truy cập được container Điện thoại/SpringBoard (\(targetBundleCandidates.joined(separator: ", "))). Hãy kiểm tra quyền khai thác thiết bị.")
        }

        let cachesDir = containerURL.appendingPathComponent("Library/Caches/TelephonyUI", isDirectory: true)
        try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)

        let pkgBackupDir = backupRoot.appendingPathComponent(pkg.id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: pkgBackupDir, withIntermediateDirectories: true)

        // Scan existing TelephonyUI cache files to match Light/Dark/Bold variants if present
        let existingFiles = (try? FileManager.default.contentsOfDirectory(at: cachesDir, includingPropertiesForKeys: nil)) ?? []
        var replacedCount = 0

        for item in pkg.items {
            let safeName = (item.filename as NSString).lastPathComponent
            let matchingExisting = existingFiles.first {
                classifyDigit(forFilename: $0.lastPathComponent) == item.digit
                    && classifyStyle(forFilename: $0.lastPathComponent) == item.style
            }
            let targetURL = matchingExisting ?? cachesDir.appendingPathComponent(safeName)
            if FileManager.default.fileExists(atPath: targetURL.path) {
                let backupFile = pkgBackupDir.appendingPathComponent(targetURL.lastPathComponent)
                if !FileManager.default.fileExists(atPath: backupFile.path),
                   let origData = try? Data(contentsOf: targetURL) {
                    try? origData.write(to: backupFile, options: [.atomic, .completeFileProtection])
                }
            }
            try item.data.write(to: targetURL, options: .atomic)
            replacedCount += 1
        }
        return "Đã áp dụng \(replacedCount) phím (\(pkg.detectedStyles.map(\.rawValue).joined(separator: ", "))) vào \(resolvedBundle)."
    }

    static func restore(_ pkg: NiKDialerPackage) throws -> String {
        let pkgBackupDir = backupRoot.appendingPathComponent(pkg.id.uuidString, isDirectory: true)
        var resolvedRoot: URL?
        for candidate in targetBundleCandidates {
            if let path = ContainerStore.resolveAppContainerPath(bundleID: candidate) {
                resolvedRoot = PatchPathValidator.canonicalFileURL(URL(fileURLWithPath: path, isDirectory: true))
                break
            }
        }
        guard let containerURL = resolvedRoot else {
            throw NiKError("Không mở được container Điện thoại/SpringBoard để khôi phục Dialer.")
        }
        let cachesDir = containerURL.appendingPathComponent("Library/Caches/TelephonyUI", isDirectory: true)
        var restored = 0
        if let backups = try? FileManager.default.contentsOfDirectory(at: pkgBackupDir, includingPropertiesForKeys: nil) {
            for b in backups {
                let dest = cachesDir.appendingPathComponent(b.lastPathComponent)
                if let data = try? Data(contentsOf: b) {
                    try? data.write(to: dest, options: .atomic)
                    restored += 1
                }
            }
        }
        for item in pkg.items {
            let candidate = cachesDir.appendingPathComponent((item.filename as NSString).lastPathComponent)
            let backupCandidate = pkgBackupDir.appendingPathComponent(candidate.lastPathComponent)
            if !FileManager.default.fileExists(atPath: backupCandidate.path),
               FileManager.default.fileExists(atPath: candidate.path) {
                try? FileManager.default.removeItem(at: candidate)
                restored += 1
            }
        }
        try? FileManager.default.removeItem(at: pkgBackupDir)
        return "Đã khôi phục \(restored) mục bàn phím Dialer về nguyên gốc."
    }

    static func deletePackage(_ pkg: NiKDialerPackage) {
        let savedURL = storageRoot.appendingPathComponent("\(pkg.id.uuidString).json")
        try? FileManager.default.removeItem(at: savedURL)
    }
}
