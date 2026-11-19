import Foundation
import OpenSSL

/// Keep the user-installed CA stable; present a separate, short-lived server leaf.
/// Pure OpenSSL code so chain/hostname/expiry behavior can also be tested on Linux.
enum NiKTLSServerCertificate {
    struct Failure: LocalizedError {
        var errorDescription: String? { "Không tạo được chứng nhận máy chủ HTTPS. Kiểm tra ngày giờ và hồ sơ tin cậy của máy." }
    }
    struct Identity {
        let p12: Data
        let password: String
        let certificateDER: Data
    }
    static func create(caP12: Data, password: String) throws -> Identity {
        let defaultProvider = OSSL_PROVIDER_load(nil, "default")
        let legacyProvider = OSSL_PROVIDER_load(nil, "legacy")
        defer {
            if let legacyProvider { OSSL_PROVIDER_unload(legacyProvider) }
            if let defaultProvider { OSSL_PROVIDER_unload(defaultProvider) }
        }
        let container: OpaquePointer? = caP12.withUnsafeBytes { bytes in
            var pointer = bytes.bindMemory(to: UInt8.self).baseAddress
            return d2i_PKCS12(nil, &pointer, caP12.count)
        }
        guard let container else { throw Failure() }
        defer { PKCS12_free(container) }
        var caKey: OpaquePointer?
        var caCert: OpaquePointer?
        guard PKCS12_parse(container, password, &caKey, &caCert, nil) == 1,
              let caKey, let caCert else {
            if let caKey { EVP_PKEY_free(caKey) }
            if let caCert { X509_free(caCert) }
            throw Failure()
        }
        defer { EVP_PKEY_free(caKey); X509_free(caCert) }
        var days: Int32 = 0, seconds: Int32 = 0
        guard X509_check_ca(caCert) > 0, X509_check_private_key(caCert, caKey) == 1,
              ASN1_TIME_diff(&days, &seconds, nil, X509_get0_notAfter(caCert)) == 1 else { throw Failure() }
        let remaining = Int(days) * 86400 + Int(seconds)
        guard remaining > 300 else { throw Failure() }
        guard let context = EVP_PKEY_CTX_new_id(EVP_PKEY_RSA, nil) else { throw Failure() }
        defer { EVP_PKEY_CTX_free(context) }
        guard EVP_PKEY_keygen_init(context) > 0,
              EVP_PKEY_CTX_ctrl(context, EVP_PKEY_RSA, EVP_PKEY_OP_KEYGEN, EVP_PKEY_CTRL_RSA_KEYGEN_BITS, 2048, nil) > 0 else { throw Failure() }
        var generated: OpaquePointer?
        guard EVP_PKEY_keygen(context, &generated) > 0, let key = generated else { throw Failure() }
        defer { EVP_PKEY_free(key) }
        guard let cert = X509_new() else { throw Failure() }
        defer { X509_free(cert) }
        guard X509_set_version(cert, 2) == 1,
              ASN1_INTEGER_set(X509_get_serialNumber(cert), Int.random(in: 1...Int.max)) == 1,
              X509_gmtime_adj(X509_getm_notBefore(cert), -300) != nil,
              X509_gmtime_adj(X509_getm_notAfter(cert), min(remaining, 30 * 86400)) != nil,
              X509_set_pubkey(cert, key) == 1,
              let name = X509_get_subject_name(cert),
              X509_NAME_add_entry_by_txt(name, "CN", MBSTRING_ASC, "NiKSign localhost server", -1, -1, 0) == 1,
              X509_set_issuer_name(cert, X509_get_subject_name(caCert)) == 1 else { throw Failure() }
        var extContext = X509V3_CTX()
        X509V3_set_ctx(&extContext, caCert, cert, nil, nil, 0)
        for (nid, value) in [
            (NID_basic_constraints, "critical,CA:FALSE"),
            (NID_key_usage, "critical,digitalSignature,keyEncipherment"),
            (NID_ext_key_usage, "serverAuth"),
            (NID_subject_alt_name, "DNS:localhost,IP:127.0.0.1")
        ] {
            guard let text = strdup(value) else { throw Failure() }
            defer { free(text) }
            guard let ext = X509V3_EXT_conf_nid(nil, &extContext, nid, text) else { throw Failure() }
            defer { X509_EXTENSION_free(ext) }
            guard X509_add_ext(cert, ext, -1) == 1 else { throw Failure() }
        }
        guard X509_sign(cert, caKey, EVP_sha256()) > 0 else { throw Failure() }
        let length = i2d_X509(cert, nil)
        guard length > 0 else { throw Failure() }
        var der = Data(count: Int(length))
        let written = der.withUnsafeMutableBytes { bytes -> Int32 in
            var pointer = bytes.bindMemory(to: UInt8.self).baseAddress
            return i2d_X509(cert, &pointer)
        }
        guard written == length else { throw Failure() }
        // Include the CA chain in the identity; ownership remains with this scope.
        guard let chain = OPENSSL_sk_new_null() else { throw Failure() }
        defer { OPENSSL_sk_free(chain) }
        guard OPENSSL_sk_push(chain, UnsafeRawPointer(caCert)) == 1 else { throw Failure() }
        let leafPassword = UUID().uuidString
        guard let p12 = PKCS12_create(leafPassword, "NiKSign HTTPS Server", key, cert, chain,
            NID_pbe_WithSHA1And3_Key_TripleDES_CBC, NID_pbe_WithSHA1And3_Key_TripleDES_CBC, 2048, 2048, 0) else { throw Failure() }
        defer { PKCS12_free(p12) }
        guard PKCS12_set_mac(p12, leafPassword, -1, nil, 0, 2048, EVP_sha1()) == 1 else { throw Failure() }
        let p12Length = i2d_PKCS12(p12, nil)
        guard p12Length > 0 else { throw Failure() }
        var p12Data = Data(count: Int(p12Length))
        let p12Written = p12Data.withUnsafeMutableBytes { bytes -> Int32 in
            var pointer = bytes.bindMemory(to: UInt8.self).baseAddress
            return i2d_PKCS12(p12, &pointer)
        }
        guard p12Written == p12Length else { throw Failure() }
        return Identity(p12: p12Data, password: leafPassword, certificateDER: der)
    }
}
