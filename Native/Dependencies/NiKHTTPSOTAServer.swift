import Foundation
import Network
import Security
import OpenSSL
import UIKit

@MainActor
final class NiKHTTPSOTAServer: ObservableObject {
  enum OTAError: LocalizedError {
case certificateGenerationFailed
case identityImportFailed
case missingIPA

var errorDescription: String? {
switch self {
case .certificateGenerationFailed: return "Failed to generate local HTTPS certificate."
case .identityImportFailed: return "Failed to import local HTTPS identity."
case .missingIPA: return "No IPA file configured."
}
}
}

@Published private(set) var isRunning = false
@Published private(set) var port: UInt16 = 0
@Published private(set) var token: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
@Published private(set) var lastError: String?

private var listener: NWListener?
private var connections: [ObjectIdentifier: NWConnection] = [:]
private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
private let queue = DispatchQueue(label: "com.niksign.https.ota.server", qos: .userInitiated)

private var ipaURL: URL?
private var bundleIdentifier = "com.niksign.app"
private var bundleVersion = "1.0"
private var displayTitle = "NiKSign App"

private var identity: SecIdentity?
private var certificateDER: Data?

var itmsInstallURL: URL? {
guard isRunning, port > 0 else { return nil }
let manifest = "https://127.0.0.1:\(port)/\(token)/manifest.plist"
var components = URLComponents()
components.scheme = "itms-services"
components.queryItems = [
URLQueryItem(name: "action", value: "download-manifest"),
URLQueryItem(name: "url", value: manifest)
]
return components.url
}
  func configure(ipaURL: URL, bundleIdentifier: String, bundleVersion: String, title: String) {
self.ipaURL = ipaURL
self.bundleIdentifier = bundleIdentifier
self.bundleVersion = bundleVersion
self.displayTitle = title
}

func start() throws {
lastError = nil
guard let ipaURL, FileManager.default.fileExists(atPath: ipaURL.path) else { throw OTAError.missingIPA }
stop()
token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
if identity == nil || certificateDER == nil {
    let generated = try Self.generateLocalIdentity()
    identity = generated.0
    certificateDER = generated.1
}
guard let secIdentity = identity else { throw OTAError.identityImportFailed }

let tlsOptions = NWProtocolTLS.Options()
if let secId = sec_identity_create(secIdentity) {
sec_protocol_options_set_local_identity(tlsOptions.securityProtocolOptions, secId)
}
sec_protocol_options_set_min_tls_protocol_version(tlsOptions.securityProtocolOptions, .TLSv12)

let parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
parameters.allowLocalEndpointReuse = true
parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)

let newListener = try NWListener(using: parameters)
newListener.stateUpdateHandler = { [weak self] state in
Task { @MainActor [weak self] in
guard let self, self.listener === newListener else { return }
switch state {
case .ready:
self.port = newListener.port?.rawValue ?? 0
self.isRunning = self.port > 0
self.lastError = nil
case .failed(let error):
self.lastError = error.localizedDescription
self.stop()
case .cancelled:
self.isRunning = false
default:
break
}
}
}
newListener.newConnectionHandler = { [weak self] connection in
Task { @MainActor [weak self] in
self?.handle(connection: connection)
}
}
self.listener = newListener
backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "NiKSign Local OTA") { [weak self] in
    Task { @MainActor in self?.stop() }
}
newListener.start(queue: queue)
}

func stop() {
listener?.stateUpdateHandler = nil
listener?.newConnectionHandler = nil
listener?.cancel()
listener = nil
connections.values.forEach { $0.cancel() }
connections.removeAll()
if backgroundTask != .invalid {
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
}
isRunning = false
port = 0
}

func exportMobileConfig() throws -> Data {
let certData: Data
if let existing = certificateDER {
certData = existing
} else {
let (secIdentity, der) = try Self.generateLocalIdentity()
self.identity = secIdentity
self.certificateDER = der
certData = der
}
let payloadUUID = UUID().uuidString
let rootUUID = UUID().uuidString
let profile: [String: Any] = [
"PayloadContent": [[
"PayloadCertificateFileName": "NiKSign-Local-OTA.cer",
"PayloadContent": certData,
"PayloadDescription": "Local HTTPS OTA Certificate for localhost / 127.0.0.1",
"PayloadDisplayName": "NiKSign Local OTA CA",
"PayloadIdentifier": "com.niksign.ota.cert.\(payloadUUID)",
"PayloadType": "com.apple.security.root",
"PayloadUUID": payloadUUID,
"PayloadVersion": 1
]],
"PayloadDescription": "Install this profile to trust local HTTPS OTA installation.",
"PayloadDisplayName": "NiKSign Local HTTPS OTA",
"PayloadIdentifier": "com.niksign.ota.profile.\(rootUUID)",
"PayloadRemovalDisallowed": false,
"PayloadType": "Configuration",
"PayloadUUID": rootUUID,
"PayloadVersion": 1
]
return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
}
func waitUntilReady() async throws {
    for _ in 0..<200 {
        if isRunning { return }
        if lastError != nil || listener == nil { throw OTAError.identityImportFailed }
        try await Task.sleep(nanoseconds: 50_000_000)
    }
    stop()
    throw OTAError.identityImportFailed
}

func openInstallURL() async -> Bool {
    guard let url = itmsInstallURL else { return false }
    return await withCheckedContinuation { continuation in
        UIApplication.shared.open(url, options: [:]) { continuation.resume(returning: $0) }
    }
}

private func handle(connection: NWConnection) {
    guard connections.count < 8 else { connection.cancel(); return }
    let id = ObjectIdentifier(connection)
    connections[id] = connection
    connection.stateUpdateHandler = { [weak self, weak connection] state in
        if case .cancelled = state { Task { @MainActor in self?.connections.removeValue(forKey: id) } }
        if case .failed = state { connection?.cancel() }
    }
    connection.start(queue: queue)
    queue.asyncAfter(deadline: .now() + 120) { [weak connection] in connection?.cancel() }
    receiveRequest(connection: connection, buffer: Data())
}

private func receiveRequest(connection: NWConnection, buffer: Data) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384 - buffer.count) { [weak self] data, _, complete, error in
        Task { @MainActor [weak self] in
            guard let self, error == nil, let data, !data.isEmpty else { connection.cancel(); return }
            var request = buffer
            request.append(data)
            guard let end = request.range(of: Data("\r\n\r\n".utf8)) else {
                guard !complete, request.count < 16_384 else { connection.cancel(); return }
                self.receiveRequest(connection: connection, buffer: request)
                return
            }
            guard let header = String(data: request[..<end.lowerBound], encoding: .utf8),
                  let line = header.components(separatedBy: "\r\n").first else { connection.cancel(); return }
            let parts = line.split(separator: " ")
            guard parts.count == 3, ["GET", "HEAD"].contains(parts[0]), parts[2].hasPrefix("HTTP/1.") else {
                self.sendResponse(on: connection, status: "405 Method Not Allowed", contentType: "text/plain", body: Data())
                return
            }
            let path = String(parts[1]), head = parts[0] == "HEAD"
            if path == "/\(self.token)/manifest.plist" {
                do {
                    let plist = try self.manifestPlistData()
                    self.sendResponse(on: connection, status: "200 OK", contentType: "application/xml", body: plist, head: head)
                } catch { connection.cancel() }
            } else if path == "/\(self.token)/app.ipa", let url = self.ipaURL {
                self.sendFile(on: connection, url: url, head: head)
            } else {
                self.sendResponse(on: connection, status: "404 Not Found", contentType: "text/plain", body: Data())
            }
        }
    }
}

private func manifestPlistData() throws -> Data {
let ipaAddress = "https://127.0.0.1:\(port)/\(token)/app.ipa"
let manifest: [String: Any] = [
"items": [[
"assets": [[
"kind": "software-package",
"url": ipaAddress
]],
"metadata": [
"bundle-identifier": bundleIdentifier,
"bundle-version": bundleVersion,
"kind": "software",
"title": displayTitle
]
]]
]
return try PropertyListSerialization.data(fromPropertyList: manifest, format: .xml, options: 0)
}

private func sendFile(on connection: NWConnection, url: URL, head: Bool) {
    do {
        let handle = try FileHandle(forReadingFrom: url)
        let size = try handle.seekToEnd()
        try handle.seek(toOffset: 0)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: \(size)\r\nConnection: close\r\n\r\n"
        connection.send(content: Data(header.utf8), completion: .contentProcessed { error in
            guard error == nil, !head else { try? handle.close(); connection.cancel(); return }
            Self.sendNextChunk(on: connection, handle: handle, remaining: size)
        })
    } catch {
        sendResponse(on: connection, status: "404 Not Found", contentType: "text/plain", body: Data("IPA unavailable".utf8))
    }
}

nonisolated private static func sendNextChunk(on connection: NWConnection, handle: FileHandle, remaining: UInt64) {
    guard remaining > 0 else { try? handle.close(); connection.cancel(); return }
    do {
        guard let data = try handle.read(upToCount: Int(min(remaining, 65536))), !data.isEmpty else {
            try? handle.close(); connection.cancel(); return
        }
        connection.send(content: data, completion: .contentProcessed { error in
            guard error == nil else { try? handle.close(); connection.cancel(); return }
            sendNextChunk(on: connection, handle: handle, remaining: remaining - UInt64(data.count))
        })
    } catch { try? handle.close(); connection.cancel() }
}

private func sendResponse(on connection: NWConnection, status: String, contentType: String, body: Data, head: Bool = false) {
let header = "HTTP/1.1 \(status)\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
var payload = Data(header.utf8)
if !head { payload.append(body) }
connection.send(content: payload, completion: .contentProcessed { _ in
connection.cancel()
})
}

private static func generateLocalIdentity() throws -> (SecIdentity, Data) {
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.niksign.local-ota-identity",
    kSecAttrAccount as String: "identity-v1"
]
var result: CFTypeRef?
var readQuery = query
readQuery[kSecReturnData as String] = true
readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
let readStatus = SecItemCopyMatching(readQuery as CFDictionary, &result)
if readStatus == errSecSuccess, let stored = result as? Data {
    var imported: CFArray?
    let status = SecPKCS12Import(stored as CFData, [kSecImportExportPassphrase as String: ""] as CFDictionary, &imported)
    if status == errSecSuccess, let values = imported as? [[String: Any]],
       let value = values.first?[kSecImportItemIdentity as String] {
        let identity = value as! SecIdentity
        var cert: SecCertificate?
        if SecIdentityCopyCertificate(identity, &cert) == errSecSuccess, let cert {
            return (identity, SecCertificateCopyData(cert) as Data)
        }
    }
    throw OTAError.identityImportFailed
}
guard readStatus == errSecItemNotFound else { throw OTAError.identityImportFailed }

guard let ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, nil) else {
throw OTAError.certificateGenerationFailed
}
defer { EVP_PKEY_CTX_free(ctx) }

guard EVP_PKEY_keygen_init(ctx) > 0,
EVP_PKEY_CTX_ctrl(ctx, EVP_PKEY_RSA, EVP_PKEY_OP_KEYGEN, EVP_PKEY_CTRL_RSA_KEYGEN_BITS, 2048, nil) > 0 else {
throw OTAError.certificateGenerationFailed
}

var pkey: OpaquePointer?
guard EVP_PKEY_keygen(ctx, &pkey) > 0, let key = pkey else {
throw OTAError.certificateGenerationFailed
}
defer { EVP_PKEY_free(key) }

guard let x509 = X509_new() else {
throw OTAError.certificateGenerationFailed
}
defer { X509_free(x509) }

X509_set_version(x509, 2)
ASN1_INTEGER_set(X509_get_serialNumber(x509), Int.random(in: 1...Int.max))
X509_gmtime_adj(X509_getm_notBefore(x509), 0)
X509_gmtime_adj(X509_getm_notAfter(x509), 60 * 60 * 24 * 365)
X509_set_pubkey(x509, key)

if let name = X509_get_subject_name(x509) {
X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, "localhost", -1, -1, 0)
X509_set_issuer_name(x509, name)
}

var extCtx = X509V3_CTX()
// X509V3_set_ctx initializes a context without a configuration database.
X509V3_set_ctx(&extCtx, x509, x509, nil, nil, 0)

let extensions: [(Int32, String)] = [
(NID_basic_constraints, "critical,CA:TRUE"),
(NID_key_usage, "critical,digitalSignature,keyEncipherment,keyCertSign"),
(NID_ext_key_usage, "serverAuth"),
(NID_subject_alt_name, "DNS:localhost,IP:127.0.0.1")
]
for (nid, value) in extensions {
let cValue = strdup(value)
defer { free(cValue) }
if let ext = X509V3_EXT_conf_nid(nil, &extCtx, nid, cValue) {
X509_add_ext(x509, ext, -1)
X509_EXTENSION_free(ext)
}
}

guard X509_sign(x509, key, EVP_sha256()) > 0 else {
throw OTAError.certificateGenerationFailed
}

let certLen = i2d_X509(x509, nil)
guard certLen > 0 else { throw OTAError.certificateGenerationFailed }
var certBytes = [UInt8](repeating: 0, count: Int(certLen))
var certSuccess = false
certBytes.withUnsafeMutableBufferPointer { buf in
var ptr = buf.baseAddress
certSuccess = i2d_X509(x509, &ptr) > 0
}
guard certSuccess else { throw OTAError.certificateGenerationFailed }
let certDER = Data(certBytes)

let pass = strdup("")
let label = strdup("NiKSign Local OTA")
defer {
free(pass)
free(label)
}
guard let p12 = PKCS12_create(pass, label, key, x509, nil, 0, 0, 0, 0, 0) else {
throw OTAError.certificateGenerationFailed
}
defer { PKCS12_free(p12) }

let p12Len = i2d_PKCS12(p12, nil)
guard p12Len > 0 else { throw OTAError.certificateGenerationFailed }
var p12Bytes = [UInt8](repeating: 0, count: Int(p12Len))
var p12Success = false
p12Bytes.withUnsafeMutableBufferPointer { buf in
var ptr = buf.baseAddress
p12Success = i2d_PKCS12(p12, &ptr) > 0
}
guard p12Success else { throw OTAError.certificateGenerationFailed }

var items: CFArray?
let options = [kSecImportExportPassphrase as String: ""] as CFDictionary
let status = SecPKCS12Import(Data(p12Bytes) as CFData, options, &items)
guard status == errSecSuccess,
let array = items as? [[String: Any]],
let first = array.first,
let secIdentity = first[kSecImportItemIdentity as String] else {
throw OTAError.identityImportFailed
}

var saved = query
saved[kSecValueData as String] = Data(p12Bytes)
saved[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
guard SecItemAdd(saved as CFDictionary, nil) == errSecSuccess else { throw OTAError.identityImportFailed }
return (secIdentity as! SecIdentity, certDER)
}
}
