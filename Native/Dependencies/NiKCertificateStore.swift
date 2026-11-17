import CryptoKit
import Foundation
import Security
import OpenSSL
struct NiKCertificateProfile: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var certSummary: String
    var teamName: String
    var teamID: String
    var appIDName: String
    var bundleIDPattern: String
    var creationDate: Date?
    var expirationDate: Date?
    var provisionedUDIDs: [String]
    var certMatchesProvision: Bool
    var sha1Fingerprint: String
    var p12Filename: String
    var provisionFilename: String
    var createdAt: Date

    var isExpired: Bool {
        guard let expirationDate else { return false }
        return expirationDate < Date()
    }

    var daysRemaining: Int? {
        guard let expirationDate else { return nil }
        return Calendar.current.dateComponents([.day], from: Date(), to: expirationDate).day
    }
}

struct NiKProvisionMetadata {
    let name: String
    let teamName: String
    let teamID: String
    let appIDName: String
    let bundleIDPattern: String
    let creationDate: Date?
    let expirationDate: Date?
    let provisionedUDIDs: [String]
    let developerCertificatesDER: [Data]
}

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

    private let rootDirectory: URL
    private let indexURL: URL

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let root = appSupport.appendingPathComponent("NiKSign/Certificates", isDirectory: true)
        self.rootDirectory = root
        self.indexURL = root.appendingPathComponent("index.json")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        loadProfiles()
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
            createdAt: Date()
        )
        let updated = [profile] + profiles
        try persist(updated)
        profiles = updated
        selectedProfileID = profile.id
        committed = true
        return profile
    }

    func removeProfile(_ profile: NiKCertificateProfile) throws {
        let updated = profiles.filter { $0.id != profile.id }
        try persist(updated)
        profiles = updated
        if selectedProfileID == profile.id { selectedProfileID = profiles.first?.id }
        NiKCertificateKeychain.deletePassword(for: profile.id)
        let folder = rootDirectory.appendingPathComponent(profile.id.uuidString, isDirectory: true)
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
    }

    private func loadProfiles() {
        guard let data = try? Data(contentsOf: indexURL),
              let decoded = try? JSONDecoder().decode([NiKCertificateProfile].self, from: data) else {
            profiles = []
            return
        }
        profiles = decoded
        selectedProfileID = decoded.first?.id
    }

    private func persist(_ profiles: [NiKCertificateProfile]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(profiles).write(to: indexURL, options: [.atomic, .completeFileProtection])
    }

    nonisolated static func readCertificateFile(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let limit = 16 * 1_048_576
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard !data.isEmpty, data.count <= limit else { throw NiKError("Tệp chứng chỉ trống hoặc vượt 16 MB.") }
        return data
    }

    nonisolated static func inspectP12(data: Data, password: String) throws -> (summary: String, derData: Data, sha1Hex: String) {
    let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
let candidates: [String] = trimmed == password ? [password] : [password, trimmed]
var lastStatus: OSStatus = errSecSuccess

for candidate in candidates {
var imported: CFArray?
let options: [String: Any] = [kSecImportExportPassphrase as String: candidate]
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
return (summary, der, sha1)
}
}
}

let defaultProvider = OSSL_PROVIDER_load(nil, "default")
let legacyProvider = OSSL_PROVIDER_load(nil, "legacy")
defer {
if let legacyProvider { OSSL_PROVIDER_unload(legacyProvider) }
if let defaultProvider { OSSL_PROVIDER_unload(defaultProvider) }
}

let certFromOpenSSL: SecCertificate? = data.withUnsafeBytes { rawBuffer -> SecCertificate? in
guard let baseAddress = rawBuffer.baseAddress, rawBuffer.count > 0 else { return nil }
guard let bio = BIO_new_mem_buf(baseAddress, Int32(rawBuffer.count)) else { return nil }
defer { BIO_free(bio) }
guard let p12 = d2i_PKCS12_bio(bio, nil) else { return nil }
defer { PKCS12_free(p12) }

for candidate in candidates {
var pkey: UnsafeMutablePointer<EVP_PKEY>?
var cert: UnsafeMutablePointer<X509>?
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
return (summary, der, sha1)
}

throw NiKError("Không mở được khóa riêng .p12 (OSStatus: \(lastStatus)). Kiểm tra tệp và mật khẩu.")
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
        let teamIDs = (dict["ApplicationIdentifierPrefix"] as? [String]) ?? (dict["TeamIdentifier"] as? [String]) ?? []
        let teamID = teamIDs.first ?? ""
        let appIDName = (dict["AppIDName"] as? String) ?? ""
        let entitlements = (dict["Entitlements"] as? [String: Any]) ?? [:]
        let rawAppID = (entitlements["application-identifier"] as? String) ?? ""
        let bundleIDPattern: String
        if !teamID.isEmpty && rawAppID.hasPrefix(teamID + ".") {
            bundleIDPattern = String(rawAppID.dropFirst(teamID.count + 1))
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
            developerCertificatesDER: certs
        )
    }
}
