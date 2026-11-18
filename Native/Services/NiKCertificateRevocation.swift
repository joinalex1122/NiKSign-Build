import Foundation
import Security

// Require a positive OCSP response: lack of connectivity must never mean good.
enum NiKCertificateRevocation {
    static func check(der: Data) -> NiKCertificateProfile.RevocationStatus {
        guard let certificate = SecCertificateCreateWithData(nil, der as CFData),
              let revocation = SecPolicyCreateRevocation(kSecRevocationOCSPMethod | kSecRevocationRequirePositiveResponse) else { return .unknown }
        var trust: SecTrust?
        let policies = [SecPolicyCreateBasicX509(), revocation] as CFArray
        guard SecTrustCreateWithCertificates(certificate, policies, &trust) == errSecSuccess,
              let trust else { return .unknown }
        SecTrustSetNetworkFetchAllowed(trust, true)
        var error: CFError?
        if SecTrustEvaluateWithError(trust, &error) { return .good }
        if let error, CFErrorGetDomain(error) as String == NSOSStatusErrorDomain,
           CFErrorGetCode(error) == Int(errSecCertificateRevoked) { return .revoked }
        return .unknown
    }
}
