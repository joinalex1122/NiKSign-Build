import CryptoKit
import Foundation
import Combine
import Security
import Darwin
import OpenSSL
enum NiKCertificateKeychain {
    private static let service = "com.niksign.certificate-passwords"

    static func savePassword(_ password: String, for id: UUID) throws {
        let data = Data(password.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        guard status == errSecItemNotFound else {
            throw NiKError("Không cập nhật được mật khẩu chứng chỉ trong Keychain (\(status)).")
        }
        var newItem = query
        attributes.forEach { newItem[$0.key] = $0.value }
        let addStatus = SecItemAdd(newItem as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw NiKError("Không lưu được mật khẩu chứng chỉ vào Keychain (\(addStatus)).")
        }
    }

    static func loadPassword(for id: UUID) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func deletePassword(for id: UUID) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: id.uuidString
        ]
        SecItemDelete(query as CFDictionary)
    }
}

@MainActor
final class NiKCertificateStore: ObservableObject {
    static let shared = NiKCertificateStore()
    @Published private(set) var profiles: [NiKCertificateProfile] = []
    @Published var selectedProfileID: UUID?
    @Published private(set) var loadFailure: String?
    var recoveryIndexURL: URL { indexURL }

    private let rootDirectory: URL
    private let indexURL: URL

    init(rootDirectory: URL? = nil) {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = rootDirectory ?? appSupport.appendingPathComponent("NiKSign/Certificates", isDirectory: true)
        self.rootDirectory = root
        self.indexURL = root.appendingPathComponent("index.json")
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try loadProfiles()
        } catch { loadFailure = error.localizedDescription }
    }

    var selectedProfile: NiKCertificateProfile? {
        guard let selectedProfileID else { return profiles.first }
        return profiles.first(where: { $0.id == selectedProfileID }) ?? profiles.first
    }

    func credentials(for profile: NiKCertificateProfile) throws -> (p12: URL, provision: URL, password: String) {
        let folder = rootDirectory.appendingPathComponent(profile.id.uuidString, isDirectory: true)
        let p12URL = folder.appendingPathComponent(profile.p12Filename)
        let provisionURL = folder.appendingPathComponent(profile.provisionFilename)
        guard FileManager.default.fileExists(atPath: p12URL.path),
              FileManager.default.fileExists(atPath: provisionURL.path) else {
            throw NiKError("Không tìm thấy tệp chứng chỉ đã lưu. Vui lòng nhập lại.")
        }
        let password = NiKCertificateKeychain.loadPassword(for: profile.id) ?? ""
        return (p12URL, provisionURL, password)
    }

    @discardableResult
    func importProfile(p12URL: URL, provisionURL: URL, password: String, customName: String = "") throws -> NiKCertificateProfile {
        guard loadFailure == nil else { throw NiKError("Kho chứng chỉ chưa đọc được. Không ghi đè index; hãy xuất dữ liệu để kiểm tra/khôi phục.") }
        let p12Data = try Self.readCertificateFile(p12URL)
        let provisionData = try Self.readCertificateFile(provisionURL)
        let certInfo = try Self.inspectP12(data: p12Data, password: password)
        let provInfo = try Self.parseMobileProvision(data: provisionData)

        let matches = provInfo.developerCertificatesDER.contains(certInfo.derData)
        let id = UUID()
        let folder = rootDirectory.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        var committed = false
        defer {
            if !committed {
                try? FileManager.default.removeItem(at: folder)
                NiKCertificateKeychain.deletePassword(for: id)
            }
        }
        let p12Dest = folder.appendingPathComponent("certificate.p12")
        let provDest = folder.appendingPathComponent("embedded.mobileprovision")
        try p12Data.write(to: p12Dest, options: .completeFileProtection)
        try provisionData.write(to: provDest, options: .completeFileProtection)
        try NiKCertificateKeychain.savePassword(password, for: id)

        let displayName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedName = displayName.isEmpty
            ? (provInfo.teamName.isEmpty ? certInfo.summary : "\(provInfo.teamName) · \(provInfo.name)")
            : displayName

        let profile = NiKCertificateProfile(
            id: id,
            name: resolvedName,
            certSummary: certInfo.summary,
            teamName: provInfo.teamName,
            teamID: provInfo.teamID,
            appIDName: provInfo.appIDName,
            bundleIDPattern: provInfo.bundleIDPattern,
            creationDate: provInfo.creationDate,
            expirationDate: provInfo.expirationDate,
            provisionedUDIDs: provInfo.provisionedUDIDs,
            certMatchesProvision: matches,
            sha1Fingerprint: certInfo.sha1Hex,
            p12Filename: "certificate.p12",
            provisionFilename: "embedded.mobileprovision",
            createdAt: Date(),
            certificateExpirationDate: certInfo.expirationDate,
            certificateCreationDate: certInfo.notBeforeDate,
            provisionsAllDevices: provInfo.provisionsAllDevices,
            allowsDebugging: provInfo.allowsDebugging,
            entitlements: provInfo.entitlements
        )
        let updated = [profile] + profiles
        try persist(updated)
        profiles = updated
        selectedProfileID = profile.id
        committed = true
        return profile
    }

    func removeProfile(_ profile: NiKCertificateProfile) throws {
        guard loadFailure == nil else { throw NiKError("Kho chứng chỉ chưa đọc được; giữ nguyên index để khôi phục.") }
        let updated = profiles.filter { $0.id != profile.id }
        try persist(updated)
        profiles = updated
        if selectedProfileID == profile.id { selectedProfileID = profiles.first?.id }
        NiKCertificateKeychain.deletePassword(for: profile.id)
        let folder = rootDirectory.appendingPathComponent(profile.id.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    private func loadProfiles() throws {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return }
        let decoded = try JSONDecoder().decode([NiKCertificateProfile].self, from: Self.readCertificateFile(indexURL))
        guard Set(decoded.map(\.id)).count == decoded.count else { throw NiKError("Index chứng chỉ có ID trùng.") }
        profiles = decoded
        selectedProfileID = decoded.first?.id
    }

    private func persist(_ profiles: [NiKCertificateProfile]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(profiles)
        guard data.count <= 16 * 1_048_576 else { throw NiKError("Index chứng chỉ vượt giới hạn 16 MB.") }
        try data.write(to: indexURL, options: [.atomic, .completeFileProtection])
    }

    nonisolated static func readCertificateFile(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let limit = 16 * 1_048_576
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard !data.isEmpty, data.count <= limit else { throw NiKError("Tệp chứng chỉ trống hoặc vượt 16 MB.") }
        return data
    }

    nonisolated static func inspectP12(data: Data, password: String) throws -> (summary: String, derData: Data, sha1Hex: String, expirationDate: Date?, notBeforeDate: Date?) {
    guard !data.isEmpty, data.count <= 16 * 1_048_576 else { throw NiKError("Tệp chứng chỉ trống hoặc vượt 16 MB.") }
    let candidates = [password] // Password whitespace is significant; signing must use the same value.
var lastStatus: OSStatus = errSecSuccess

for candidate in candidates {
var imported: CFArray?
var options: [String: Any] = [kSecImportExportPassphrase as String: candidate]
#if os(macOS)
if #available(macOS 15.0, *) { options[kSecImportToMemoryOnly as String] = true }
#endif
let status = SecPKCS12Import(data as CFData, options as CFDictionary, &imported)
lastStatus = status
if status == errSecSuccess, let items = imported as? [[String: Any]] {
if let matched = items.first(where: { $0[kSecImportItemIdentity as String] != nil }),
let identityRef = matched[kSecImportItemIdentity as String] {
let identity = identityRef as! SecIdentity
var certRef: SecCertificate?
guard SecIdentityCopyCertificate(identity, &certRef) == errSecSuccess,
let cert = certRef else {
throw NiKError("Không trích xuất được chứng chỉ X.509 từ tệp .p12.")
}
let summary = (SecCertificateCopySubjectSummary(cert) as String?) ?? "Apple Certificate"
let der = SecCertificateCopyData(cert) as Data
let sha1 = Insecure.SHA1.hash(data: der).map { String(format: "%02x", $0) }.joined().uppercased()
return (summary, der, sha1, certificateDate(der: der, expiration: true), certificateDate(der: der, expiration: false))
}
}
}

_ = NiKOpenSSLProviders.loaded

let certFromOpenSSL: SecCertificate? = data.withUnsafeBytes { (rawBuffer: UnsafeRawBufferPointer) -> SecCertificate? in
guard let baseAddress = rawBuffer.baseAddress, rawBuffer.count > 0 else { return nil }
guard let bio = BIO_new_mem_buf(baseAddress, Int32(rawBuffer.count)) else { return nil }
defer { BIO_free(bio) }
guard let p12 = d2i_PKCS12_bio(bio, nil) else { return nil }
defer { PKCS12_free(p12) }

for candidate in candidates {
var pkey: OpaquePointer?
var cert: OpaquePointer?
let parsed = candidate.withCString { cPass in
PKCS12_parse(p12, cPass, &pkey, &cert, nil)
}
if let pkey { EVP_PKEY_free(pkey) }
guard parsed == 1, let cert else {
if let cert { X509_free(cert) }
continue
}
defer { X509_free(cert) }

let len = i2d_X509(cert, nil)
guard len > 0 else { continue }
var derBytes = [UInt8](repeating: 0, count: Int(len))
let written = derBytes.withUnsafeMutableBufferPointer { buf -> Int32 in
var outPtr = buf.baseAddress
return i2d_X509(cert, &outPtr)
}
guard written > 0 else { continue }
let derData = Data(derBytes.prefix(Int(written)))
if let secCert = SecCertificateCreateWithData(nil, derData as CFData) {
return secCert
}
}
return nil
}

if let cert = certFromOpenSSL {
let summary = (SecCertificateCopySubjectSummary(cert) as String?) ?? "Apple Certificate"
let der = SecCertificateCopyData(cert) as Data
let sha1 = Insecure.SHA1.hash(data: der).map { String(format: "%02x", $0) }.joined().uppercased()
return (summary, der, sha1, certificateDate(der: der, expiration: true), certificateDate(der: der, expiration: false))
}

throw NiKError("Không mở được khóa riêng .p12 (OSStatus: \(lastStatus)). Kiểm tra tệp và mật khẩu.")
    }

    nonisolated private static func certificateDate(der: Data, expiration: Bool) -> Date? {
        der.withUnsafeBytes { bytes in
            guard let base = bytes.baseAddress, bytes.count <= Int(Int32.max),
                  let bio = BIO_new_mem_buf(base, Int32(bytes.count)) else { return nil }
            defer { BIO_free(bio) }
            guard let certificate = d2i_X509_bio(bio, nil) else { return nil }
            defer { X509_free(certificate) }
            let time = expiration ? X509_get0_notAfter(certificate) : X509_get0_notBefore(certificate)
            var components = tm()
            guard ASN1_TIME_to_tm(time, &components) == 1 else { return nil }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            return calendar.date(from: DateComponents(year: Int(components.tm_year) + 1900,
                month: Int(components.tm_mon) + 1, day: Int(components.tm_mday),
                hour: Int(components.tm_hour), minute: Int(components.tm_min), second: Int(components.tm_sec)))
        }
    }

    nonisolated static func parseMobileProvision(data: Data) throws -> NiKProvisionMetadata {
        let startMarker = Data("<plist".utf8)
        let endMarker = Data("</plist>".utf8)
        guard let startRange = data.range(of: startMarker),
              let endRange = data.range(of: endMarker, in: startRange.lowerBound..<data.endIndex) else {
            throw NiKError("Tệp .mobileprovision không chứa cấu trúc XML plist hợp lệ.")
        }
        let plistSlice = data.subdata(in: startRange.lowerBound..<endRange.upperBound)
        guard let dict = try PropertyListSerialization.propertyList(from: plistSlice, format: nil) as? [String: Any] else {
            throw NiKError("Không đọc được thuộc tính trong .mobileprovision.")
        }
        let name = (dict["Name"] as? String) ?? "Provisioning Profile"
        let teamName = (dict["TeamName"] as? String) ?? ""
        let prefixes = (dict["ApplicationIdentifierPrefix"] as? [String]) ?? []
        let teamID = (dict["TeamIdentifier"] as? [String])?.first ?? prefixes.first ?? ""
        let appIDName = (dict["AppIDName"] as? String) ?? ""
        let entitlements = (dict["Entitlements"] as? [String: Any]) ?? [:]
        let rawAppID = (entitlements["application-identifier"] as? String) ?? ""
        let bundleIDPattern: String
        let appPrefix = prefixes.first(where: { rawAppID.hasPrefix($0 + ".") })
            ?? (!teamID.isEmpty && rawAppID.hasPrefix(teamID + ".") ? teamID : nil)
        if let appPrefix {
            bundleIDPattern = String(rawAppID.dropFirst(appPrefix.count + 1))
        } else {
            bundleIDPattern = rawAppID
        }
        let creationDate = dict["CreationDate"] as? Date
        let expirationDate = dict["ExpirationDate"] as? Date
        let udids = (dict["ProvisionedDevices"] as? [String]) ?? []
        let certs = (dict["DeveloperCertificates"] as? [Data]) ?? []
        return NiKProvisionMetadata(
            name: name,
            teamName: teamName,
            teamID: teamID,
            appIDName: appIDName,
            bundleIDPattern: bundleIDPattern,
            creationDate: creationDate,
            expirationDate: expirationDate,
            provisionedUDIDs: udids,
            developerCertificatesDER: certs,
            provisionsAllDevices: dict["ProvisionsAllDevices"] as? Bool ?? false,
            allowsDebugging: entitlements["get-task-allow"] as? Bool ?? false,
            entitlements: try entitlements.mapValues(NiKPlistValue.init)
        )
    }
}

// Providers are process-wide and must outlive concurrent signing/TLS operations.
private enum NiKOpenSSLProviders {
    static let loaded: Bool = {
        let defaultProvider = OSSL_PROVIDER_load(nil, "default")
        let legacyProvider = OSSL_PROVIDER_load(nil, "legacy")
        return defaultProvider != nil && legacyProvider != nil
    }()
}
