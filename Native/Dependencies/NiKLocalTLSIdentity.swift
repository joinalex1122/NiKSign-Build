import Foundation
import Security
import OpenSSL

/// Shared by the iOS server and macOS certificate regression tests.
enum NiKLocalTLSIdentity {
    enum Failure: LocalizedError {
        case certificateGenerationFailed
        case identityImportFailed
        var errorDescription: String? {
            switch self {
            case .certificateGenerationFailed: return "Failed to generate local HTTPS certificate."
            case .identityImportFailed: return "Failed to import local HTTPS identity."
            }
        }
    }
static func loadOrCreate(service: String = "com.niksign.local-ota-identity") throws -> (SecIdentity, Data) {
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: service,
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
    throw NiKLocalTLSIdentity.Failure.identityImportFailed
}
guard readStatus == errSecItemNotFound else { throw NiKLocalTLSIdentity.Failure.identityImportFailed }

guard let ctx = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, nil) else {
throw NiKLocalTLSIdentity.Failure.certificateGenerationFailed
}
defer { EVP_PKEY_CTX_free(ctx) }

guard EVP_PKEY_keygen_init(ctx) > 0,
EVP_PKEY_CTX_ctrl(ctx, EVP_PKEY_RSA, EVP_PKEY_OP_KEYGEN, EVP_PKEY_CTRL_RSA_KEYGEN_BITS, 2048, nil) > 0 else {
throw NiKLocalTLSIdentity.Failure.certificateGenerationFailed
}

var pkey: OpaquePointer?
guard EVP_PKEY_keygen(ctx, &pkey) > 0, let key = pkey else {
throw NiKLocalTLSIdentity.Failure.certificateGenerationFailed
}
defer { EVP_PKEY_free(key) }

guard let x509 = X509_new() else {
throw NiKLocalTLSIdentity.Failure.certificateGenerationFailed
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
throw NiKLocalTLSIdentity.Failure.certificateGenerationFailed
}

let certLen = i2d_X509(x509, nil)
guard certLen > 0 else { throw NiKLocalTLSIdentity.Failure.certificateGenerationFailed }
var certBytes = [UInt8](repeating: 0, count: Int(certLen))
var certSuccess = false
certBytes.withUnsafeMutableBufferPointer { buf in
var ptr = buf.baseAddress
certSuccess = i2d_X509(x509, &ptr) > 0
}
guard certSuccess else { throw NiKLocalTLSIdentity.Failure.certificateGenerationFailed }
let certDER = Data(certBytes)

let pass = strdup("")
let label = strdup("NiKSign Local OTA")
defer {
free(pass)
free(label)
}
guard let p12 = PKCS12_create(pass, label, key, x509, nil, 0, 0, 0, 0, 0) else {
throw NiKLocalTLSIdentity.Failure.certificateGenerationFailed
}
defer { PKCS12_free(p12) }

let p12Len = i2d_PKCS12(p12, nil)
guard p12Len > 0 else { throw NiKLocalTLSIdentity.Failure.certificateGenerationFailed }
var p12Bytes = [UInt8](repeating: 0, count: Int(p12Len))
var p12Success = false
p12Bytes.withUnsafeMutableBufferPointer { buf in
var ptr = buf.baseAddress
p12Success = i2d_PKCS12(p12, &ptr) > 0
}
guard p12Success else { throw NiKLocalTLSIdentity.Failure.certificateGenerationFailed }

var items: CFArray?
let options = [kSecImportExportPassphrase as String: ""] as CFDictionary
let status = SecPKCS12Import(Data(p12Bytes) as CFData, options, &items)
guard status == errSecSuccess,
let array = items as? [[String: Any]],
let first = array.first,
let secIdentity = first[kSecImportItemIdentity as String] else {
throw NiKLocalTLSIdentity.Failure.identityImportFailed
}

var saved = query
saved[kSecValueData as String] = Data(p12Bytes)
saved[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
guard SecItemAdd(saved as CFDictionary, nil) == errSecSuccess else { throw NiKLocalTLSIdentity.Failure.identityImportFailed }
return (secIdentity as! SecIdentity, certDER)
}
}
