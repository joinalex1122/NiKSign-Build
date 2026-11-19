import Foundation
import OpenSSL

/// Authenticate the CMS payload before interpreting provisioning properties.
/// CMS signer-chain trust and the device's installation policy remain Apple's decision.
enum NiKProvisioningValidation {
    struct Failure: LocalizedError { let message: String; var errorDescription: String? { message } }
    static func decode(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= 16 * 1_048_576 else { throw Failure(message: "Provisioning profile rỗng hoặc quá lớn.") }
        let cms = data.withUnsafeBytes { raw -> OpaquePointer? in
            var cursor = raw.bindMemory(to: UInt8.self).baseAddress
            let value = d2i_CMS_ContentInfo(nil, &cursor, data.count)
            guard cursor == raw.bindMemory(to: UInt8.self).baseAddress?.advanced(by: data.count) else { if let value { CMS_ContentInfo_free(value) }; return nil }
            return value
        }
        guard let cms else { throw Failure(message: "Profile không phải CMS hợp lệ; không chấp nhận XML rời hoặc dữ liệu nối thêm.") }
        defer { CMS_ContentInfo_free(cms) }
        guard CMS_is_detached(cms) == 0, let output = BIO_new(BIO_s_mem()) else { throw Failure(message: "Profile CMS thiếu nội dung đính kèm.") }
        defer { BIO_free(output) }
        guard CMS_verify(cms, nil, nil, nil, output, UInt32(CMS_BINARY | CMS_NO_SIGNER_CERT_VERIFY)) == 1 else {
            throw Failure(message: "Chữ ký CMS của provisioning profile không hợp lệ.")
        }
        let count = BIO_ctrl(output, BIO_CTRL_PENDING, 0, nil)
        guard count > 0, count <= 1_048_576 else { throw Failure(message: "Nội dung profile vượt giới hạn.") }
        var bytes = Data(count: count)
        let read = bytes.withUnsafeMutableBytes { BIO_read(output, $0.baseAddress, Int32(count)) }
        guard read == count, let value = try PropertyListSerialization.propertyList(from: bytes, format: nil) as? [String: Any] else {
            throw Failure(message: "Nội dung CMS không phải provisioning plist dictionary.")
        }
        return value
    }
    static func bundleMatches(pattern: String, bundleID: String) -> Bool {
        NiKProvisioningPattern.matches(pattern: pattern, bundleID: bundleID)
    }
    @discardableResult static func validate(_ data: Data, bundleID: String, certificateDER: Data? = nil, now: Date = Date()) throws -> [String: Any] {
        let value = try decode(data)
        guard let expiry = value["ExpirationDate"] as? Date, expiry > now,
              let created = value["CreationDate"] as? Date, created <= now else { throw Failure(message: "Profile hết hạn, chưa có hiệu lực hoặc thiếu thời hạn.") }
        guard let entitlements = value["Entitlements"] as? [String: Any],
              let appID = entitlements["application-identifier"] as? String,
              let prefix = (value["ApplicationIdentifierPrefix"] as? [String])?.first(where: { appID.hasPrefix($0 + ".") }),
              let team = (value["TeamIdentifier"] as? [String])?.first, !team.isEmpty,
              entitlements["com.apple.developer.team-identifier"] as? String == team else { throw Failure(message: "Profile thiếu hoặc mâu thuẫn ApplicationIdentifierPrefix/Team ID/entitlements.") }
        if entitlements["keychain-access-groups"] != nil {
            guard let groups = entitlements["keychain-access-groups"] as? [String], groups.allSatisfy({ !$0.isEmpty && (!$0.contains("*") || ($0.hasSuffix("*") && !$0.dropLast().contains("*"))) }) else { throw Failure(message: "Profile có keychain-access-groups không hợp lệ.") }
        }
        if entitlements["get-task-allow"] != nil, !(entitlements["get-task-allow"] is Bool) { throw Failure(message: "get-task-allow trong profile không phải boolean.") }
        guard bundleMatches(pattern: String(appID.dropFirst(prefix.count + 1)), bundleID: bundleID) else {
            throw Failure(message: "Bundle ID \(bundleID) không được profile \(appID) cho phép. Chọn profile phù hợp hoặc đổi Bundle ID trước khi ký.")
        }
        guard let certificates = value["DeveloperCertificates"] as? [Data], !certificates.isEmpty else { throw Failure(message: "Profile thiếu DeveloperCertificates.") }
        if let certificateDER {
            guard certificates.contains(certificateDER) else { throw Failure(message: "Chứng chỉ .p12 không nằm trong DeveloperCertificates của profile.") }
            try validateCertificate(certificateDER, now: now)
        } else {
            guard certificates.contains(where: { (try? validateCertificate($0, now: now)) != nil }) else { throw Failure(message: "Profile không có chứng chỉ ký còn hiệu lực.") }
        }
        return value
    }
    static func verifyDetachedCMS(_ data: Data, content: Data, certificateDER: Data) throws {
        guard !data.isEmpty, data.count <= 16 * 1_048_576, !content.isEmpty, content.count <= 16 * 1_048_576 else { throw Failure(message: "CMS/CodeDirectory vượt giới hạn.") }
        let cms = data.withUnsafeBytes { raw -> OpaquePointer? in
            var cursor = raw.bindMemory(to: UInt8.self).baseAddress
            let value = d2i_CMS_ContentInfo(nil, &cursor, data.count)
            guard cursor == raw.bindMemory(to: UInt8.self).baseAddress?.advanced(by: data.count) else { if let value { CMS_ContentInfo_free(value) }; return nil }
            return value
        }
        guard let cms else { throw Failure(message: "CMS trong Mach-O không hợp lệ.") }
        defer { CMS_ContentInfo_free(cms) }
        guard let input = BIO_new(BIO_s_mem()) else { throw Failure(message: "Không mở được CodeDirectory.") }
        defer { BIO_free(input) }
        let contentWritten = content.withUnsafeBytes { BIO_write(input, $0.baseAddress, Int32(content.count)) }
        guard contentWritten == content.count else { throw Failure(message: "Không đọc đủ CodeDirectory.") }
        guard CMS_is_detached(cms) == 1, CMS_verify(cms, nil, nil, input, nil, UInt32(CMS_BINARY | CMS_NO_SIGNER_CERT_VERIFY)) == 1,
              let signers = CMS_get0_signers(cms) else { throw Failure(message: "Chữ ký CMS không xác minh được CodeDirectory.") }
        defer { OPENSSL_sk_free(signers) }
        guard OPENSSL_sk_num(signers) == 1, let signer = OPENSSL_sk_value(signers, 0) else { throw Failure(message: "CMS thiếu chứng chỉ ký duy nhất.") }
        let certificate = OpaquePointer(signer)
        let count = i2d_X509(certificate, nil)
        guard count > 0 else { throw Failure(message: "Không đọc được chứng chỉ trong CMS.") }
        var bytes = Data(count: Int(count))
        let written = bytes.withUnsafeMutableBytes { raw -> Int32 in
            var cursor = raw.bindMemory(to: UInt8.self).baseAddress
            return i2d_X509(certificate, &cursor)
        }
        guard written == count, bytes == certificateDER else { throw Failure(message: "Mã lồng nhau còn chữ ký của chứng chỉ khác.") }
    }
    static func validateEntitlements(_ signed: [String: Any], allowed: [String: Any], applicationID: String, teamID: String) throws {
        guard signed["application-identifier"] as? String == applicationID,
              signed["com.apple.developer.team-identifier"] as? String == teamID else { throw Failure(message: "Entitlements sai application-identifier hoặc Team ID.") }
        if let alternate = signed["com.apple.application-identifier"] as? String, alternate != applicationID { throw Failure(message: "Entitlements có hai Application Identifier khác nhau.") }
        if let patterns = allowed["keychain-access-groups"] as? [String] {
            guard let groups = signed["keychain-access-groups"] as? [String], !groups.isEmpty || patterns.isEmpty,
                  groups.allSatisfy({ group in !group.contains("*") && patterns.contains(where: { bundleMatches(pattern: $0, bundleID: group) }) }) else { throw Failure(message: "Keychain access groups không được profile cho phép hoặc còn wildcard.") }
        }
        guard (signed["get-task-allow"] as? Bool ?? false) == (allowed["get-task-allow"] as? Bool ?? false) else { throw Failure(message: "get-task-allow không khớp profile.") }
    }
    static func validateCertificate(_ data: Data, now: Date) throws {
        let certificate = data.withUnsafeBytes { raw -> OpaquePointer? in
            var cursor = raw.bindMemory(to: UInt8.self).baseAddress
            return d2i_X509(nil, &cursor, data.count)
        }
        guard let certificate else { throw Failure(message: "Chứng chỉ DER không hợp lệ.") }
        defer { X509_free(certificate) }
        var time = time_t(now.timeIntervalSince1970)
        guard X509_cmp_time(X509_get0_notBefore(certificate), &time) < 0,
              X509_cmp_time(X509_get0_notAfter(certificate), &time) > 0 else { throw Failure(message: "Chứng chỉ ký hết hạn hoặc chưa có hiệu lực.") }
    }
}
