import Foundation
import CryptoKit

enum NiKOTAProfile {
    static func encode(certificateDER certData: Data) throws -> Data {
let certificateID = SHA256.hash(data: certData).map { String(format: "%02x", $0) }.joined()
let payloadUUID = UUID().uuidString
let rootUUID = UUID().uuidString
let profile: [String: Any] = [
"PayloadContent": [[
"PayloadCertificateFileName": "NiKSign-Local-OTA.cer",
"PayloadContent": certData,
"PayloadDescription": "Local HTTPS OTA Certificate for localhost / 127.0.0.1",
"PayloadDisplayName": "NiKSign Local OTA CA",
"PayloadIdentifier": "com.niksign.ota.cert.\(certificateID)",
"PayloadType": "com.apple.security.root",
"PayloadUUID": payloadUUID,
"PayloadVersion": 1
]],
"PayloadDescription": "Install this profile to trust local HTTPS OTA installation.",
"PayloadDisplayName": "NiKSign Local HTTPS OTA",
"PayloadIdentifier": "com.niksign.ota.profile.\(certificateID)",
"PayloadRemovalDisallowed": false,
"PayloadType": "Configuration",
"PayloadUUID": rootUUID,
"PayloadVersion": 1
]
return try PropertyListSerialization.data(fromPropertyList: profile, format: .xml, options: 0)
    }
}
