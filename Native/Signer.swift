import Foundation
import Security
import ZIPFoundation
import Zsign

struct NiKError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

// Zsign uses process-global state. Serialize all signing work on one actor.
actor SigningService {
    static let shared = SigningService()

    func sign(ipa: URL, p12: URL, profile: URL, password: String) throws -> URL {
        try signDetailed(
            ipa: ipa,
            p12: p12,
            profile: profile,
            password: password,
            options: NiKSigningOptions(),
            onProgress: nil
        ).ipaURL
    }

    func signDetailed(
        ipa: URL,
        p12: URL,
        profile: URL,
        password: String,
        options: NiKSigningOptions = NiKSigningOptions(),
        onProgress: (@Sendable (NiKSigningProgress) -> Void)? = nil
    ) throws -> NiKSignedArtifact {
        func report(_ step: Int, _ fraction: Double, _ text: String) throws {
            try Task.checkCancellation()
            onProgress?(NiKSigningProgress(step: step, totalSteps: 6, fraction: fraction, description: text))
        }

        let fm = FileManager.default
        let work = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        // Step 1: Check password/private key and provisioning profile before attempting a signing operation.
        try report(1, 0.12, "Đang kiểm tra khóa .p12 và hồ sơ .mobileprovision…")
        let p12Data = try NiKCertificateStore.readCertificateFile(p12)
        let certInfo = try NiKCertificateStore.inspectP12(data: p12Data, password: password)
        guard certInfo.expirationDate != nil, certInfo.notBeforeDate != nil else {
            throw NiKError("Không đọc được thời gian hiệu lực của chứng chỉ ký.")
        }
        let provData = try NiKCertificateStore.readCertificateFile(profile)
        let provInfo = try NiKCertificateStore.parseMobileProvision(data: provData)

        // The native signer must read the same bytes that preflight inspected, even if
        // the certificate store changes while a queued job is running.
        let signingP12 = work.appendingPathComponent("signing-certificate.p12")
        let signingProfile = work.appendingPathComponent("selected.mobileprovision")
        try p12Data.write(to: signingP12, options: [.atomic, .completeFileProtection])
        try provData.write(to: signingProfile, options: [.atomic, .completeFileProtection])

        if let expiry = provInfo.expirationDate, expiry < Date() {
            throw NiKError("Hồ sơ .mobileprovision (\(provInfo.name)) đã hết hạn vào \(expiry.formatted(date: .numeric, time: .omitted)).")
        }
        if !options.allowCertificateMismatch && !provInfo.developerCertificatesDER.isEmpty {
            guard provInfo.developerCertificatesDER.contains(certInfo.derData) else {
                throw NiKError("Chứng chỉ .p12 (\(certInfo.summary)) không khớp với danh sách chứng chỉ trong .mobileprovision (\(provInfo.name)).")
            }
        }

        // Step 2: minizip preflight and CRC-checked extraction.
        try report(2, 0.30, "Đang kiểm tra cấu trúc ZIP và giải nén IPA…")
        var entries: UInt64 = 0, expandedBytes: UInt64 = 0
        let zipStatus = ipa.path.withCString { NiKZipCheck($0, &entries, &expandedBytes) }
        guard zipStatus == 0 else { throw NiKError("minizip từ chối ZIP hỏng hoặc vượt giới hạn (\(zipStatus)).") }
        let archive = try Archive(url: ipa, accessMode: .read)
        var total: UInt64 = 0
        var paths = Set<String>()
        var count = 0
        for entry in archive {
            count += 1
            let path = entry.path.hasSuffix("/") ? String(entry.path.dropLast()) : entry.path
            _ = try PatchPathValidator.canonicalRelativePath(path)
            guard paths.insert(path).inserted, entry.type != .symlink else {
                throw NiKError("IPA có đường dẫn trùng hoặc symbolic link không hỗ trợ.")
            }
            total += entry.uncompressedSize
            guard total <= 1_073_741_824, count <= 50_000 else {
                throw NiKError("IPA vượt giới hạn giải nén 1 GB hoặc 50.000 mục.")
            }
        }
        for entry in archive {
            try Task.checkCancellation()
            let destination = work.appendingPathComponent(entry.path)
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let checksum = try archive.extract(entry, to: destination)
            guard checksum == entry.checksum else { throw NiKError("IPA bị lỗi CRC khi giải nén.") }
        }

        // Step 3: Inspect Payload/*.app and Mach-O binary.
        try report(3, 0.50, "Đang phân tích Info.plist và kiểm tra mã hóa Mach-O…")
        let payload = work.appendingPathComponent("Payload")
        let apps = try fm.contentsOfDirectory(at: payload, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "app" }
        guard apps.count == 1 else { throw NiKError("IPA phải có đúng một Payload/*.app.") }
        let app = apps[0]
        let infoPlistURL = app.appendingPathComponent("Info.plist")
        var plistFormat = PropertyListSerialization.PropertyListFormat.xml
        guard var plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: infoPlistURL),
            options: [],
            format: &plistFormat
        ) as? [String: Any] else {
            throw NiKError("Không đọc được Info.plist của ứng dụng.")
        }

        let originalBundleID = (plist["CFBundleIdentifier"] as? String) ?? ""
        let trimmedCustomBundleID = options.customBundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveBundleID = trimmedCustomBundleID.isEmpty ? originalBundleID : trimmedCustomBundleID

        guard !effectiveBundleID.isEmpty,
              (!effectiveBundleID.hasPrefix("com.apple.") || effectiveBundleID == "com.apple.mobile.MobileHouseArrest"),
              let executable = plist["CFBundleExecutable"] as? String,
              !executable.isEmpty, !executable.contains("/"), !executable.contains("\\"),
              executable != ".", executable != ".." else {
            throw NiKError("Bundle ID hoặc executable không hợp lệ. Chỉ chấp nhận Bundle ID ứng dụng hoặc ID MHA của 3105.")
        }
        if !trimmedCustomBundleID.isEmpty {
            _ = try PatchPathValidator.canonicalBundleIdentifier(trimmedCustomBundleID)
        }

        _ = try PatchPathValidator.canonicalBundleIdentifier(effectiveBundleID)
        let descriptor = NiKCertificateProfile(id: UUID(), name: provInfo.name, certSummary: certInfo.summary,
            teamName: provInfo.teamName, teamID: provInfo.teamID, appIDName: provInfo.appIDName,
            bundleIDPattern: provInfo.bundleIDPattern, creationDate: provInfo.creationDate,
            expirationDate: provInfo.expirationDate, provisionedUDIDs: provInfo.provisionedUDIDs,
            certMatchesProvision: provInfo.developerCertificatesDER.contains(certInfo.derData),
            sha1Fingerprint: certInfo.sha1Hex, p12Filename: p12.lastPathComponent, provisionFilename: profile.lastPathComponent,
            createdAt: Date(), certificateExpirationDate: certInfo.expirationDate,
            certificateCreationDate: certInfo.notBeforeDate, provisionsAllDevices: provInfo.provisionsAllDevices,
            allowsDebugging: provInfo.allowsDebugging, entitlements: provInfo.entitlements)
        let assessment = NiKCertificateCompatibility.assess(descriptor, bundleID: effectiveBundleID,
            deviceUDID: options.targetDeviceUDID, allowMismatch: options.allowCertificateMismatch)
        guard assessment.canSign else {
            throw NiKError(assessment.issues.filter { $0.severity == .blocking }.map(\.vi).joined(separator: "\n"))
        }

        let executableURL = app.appendingPathComponent(executable)
        let binary = try Data(contentsOf: executableURL, options: .mappedIfSafe)
        let headers: [[UInt8]] = [[0xcf,0xfa,0xed,0xfe], [0xfe,0xed,0xfa,0xcf],
                                 [0xca,0xfe,0xba,0xbe], [0xbe,0xba,0xfe,0xca],
                                 [0xca,0xfe,0xba,0xbf], [0xbf,0xba,0xfe,0xca]]
        guard headers.contains(Array(binary.prefix(4))) else { throw NiKError("Thiếu binary Mach-O hợp lệ.") }
        try NiKBinaryInspector.requireUnencrypted(at: executableURL)

        // Step 4: Apply Info.plist modifications, extension cleanup, and dylib/deb injection.
        try report(4, 0.68, "Đang áp dụng tùy biến gói và chèn Tweak…")
        if options.removeExtensions {
            for folderName in ["PlugIns", "Extensions", "Watch"] {
                let targetFolder = app.appendingPathComponent(folderName)
                if fm.fileExists(atPath: targetFolder.path) {
                    try fm.removeItem(at: targetFolder)
                }
            }
        }

        var plistModified = false
        if !trimmedCustomBundleID.isEmpty && trimmedCustomBundleID != originalBundleID {
            plist["CFBundleIdentifier"] = trimmedCustomBundleID
            plistModified = true
            try updateExtensionBundleIdentifiers(in: app, oldPrefix: originalBundleID, newPrefix: trimmedCustomBundleID)
        }

        let trimmedDisplayName = options.customDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDisplayName.isEmpty {
            plist["CFBundleDisplayName"] = trimmedDisplayName
            plist["CFBundleName"] = trimmedDisplayName
            plistModified = true
        }

        let trimmedVersion = options.customVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedVersion.isEmpty {
            plist["CFBundleShortVersionString"] = trimmedVersion
            plistModified = true
        }

        let trimmedMinOS = options.minimumOSVersion.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedMinOS.isEmpty {
            plist["MinimumOSVersion"] = trimmedMinOS
            plistModified = true
        }

        if options.enableFileSharing {
            plist["UIFileSharingEnabled"] = true
            plist["LSSupportsOpeningDocumentsInPlace"] = true
            plistModified = true
        }

        if options.removeSupportedDevicesRestriction {
            plist.removeValue(forKey: "UISupportedDevices")
            plistModified = true
        }

        if plistModified {
            let updatedPlistData = try PropertyListSerialization.data(
                fromPropertyList: plist,
                format: plistFormat,
                options: 0
            )
            try updatedPlistData.write(to: infoPlistURL, options: .atomic)
        }

        let injectedDylibs = try NiKDylibInjector.inject(
            files: options.injectedFiles,
            intoAppBundle: app,
            executableName: executable,
            weakLink: options.weakDylibInjection
        )

        try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executableURL.path)

        // Step 5: Execute Zsign.
        try report(5, 0.84, "Đang ký chữ ký số bằng Zsign…")
        var completed = false
        let accepted = Zsign.sign(
            appPath: app.path,
            provisionPath: signingProfile.path,
            p12Path: signingP12.path,
            p12Password: password,
            // Local native fix embeds and seals the selected profile when removal is false.
            removeProvision: false,
            completion: { completed = $0 }
        )
        guard accepted && completed && Zsign.checkSigned(appExecutable: executableURL.path) else {
            throw NiKError("Zsign báo lỗi. Kiểm tra chứng chỉ, profile, Bundle ID và entitlement.")
        }

        let embeddedProfile = app.appendingPathComponent("embedded.mobileprovision")
        guard fm.fileExists(atPath: embeddedProfile.path),
              try Data(contentsOf: embeddedProfile) == provData else {
            throw NiKError("Zsign chưa giữ đúng embedded.mobileprovision trong app đã ký. Không xuất IPA thiếu profile.")
        }

        // Step 6: Repackage signed IPA.
        try report(6, 0.96, "Đang đóng gói tệp IPA đã ký…")
        let outputDirectory = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Signed", isDirectory: true)
        try fm.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let output = outputDirectory.appendingPathComponent("NiKSign-Signed-\(UUID().uuidString).ipa")
        let staging = work.appendingPathComponent("signed-output.ipa")
        try fm.zipItem(at: payload, to: staging, compressionMethod: .deflate)
        try Task.checkCancellation()
        try NiKSignedOutputValidator.validate(staging, expectedBundleID: effectiveBundleID)
        try Task.checkCancellation()
        try fm.moveItem(at: staging, to: output)

        let finalName = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? app.deletingPathExtension().lastPathComponent
        let finalVersion = (plist["CFBundleShortVersionString"] as? String)
            ?? (plist["CFBundleVersion"] as? String)
            ?? "1.0"

        onProgress?(NiKSigningProgress(step: 6, totalSteps: 6, fraction: 1, description: "Hoàn tất ký và xuất IPA."))
        return NiKSignedArtifact(
            ipaURL: output,
            bundleID: effectiveBundleID,
            displayName: finalName,
            version: finalVersion,
            injectedDylibs: injectedDylibs,
            certificateSummary: certInfo.summary,
            teamName: provInfo.teamName
        )
    }

    private func updateExtensionBundleIdentifiers(in appURL: URL, oldPrefix: String, newPrefix: String) throws {
        guard !oldPrefix.isEmpty else { return }
        let fm = FileManager.default
        for folderName in ["PlugIns", "Extensions"] {
            let dir = appURL.appendingPathComponent(folderName)
            guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for item in items where item.pathExtension == "appex" {
                let plistURL = item.appendingPathComponent("Info.plist")
                guard let data = try? Data(contentsOf: plistURL),
                      var dict = (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any],
                      let extID = dict["CFBundleIdentifier"] as? String,
                      extID.hasPrefix(oldPrefix + ".") else {
                    continue
                }
                let suffix = String(extID.dropFirst(oldPrefix.count))
                dict["CFBundleIdentifier"] = newPrefix + suffix
                if let out = try? PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0) {
                    try? out.write(to: plistURL, options: .atomic)
                }
            }
        }
    }
}
