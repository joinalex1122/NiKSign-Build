import Foundation

@main struct CertificateCompatibilitySmoke {
    static func expectFailure(_ action: () throws -> Void) {
        do { try action() } catch { return }
        fatalError("Expected rejection")
    }
    static func main() throws {
        let now = Date()
        var profile = NiKCertificateProfile(id: UUID(), name: "Fixture", certSummary: "Synthetic", teamName: "Example", teamID: "TEAM123", appIDName: "Fixture", bundleIDPattern: "com.example.*", creationDate: now.addingTimeInterval(-3600), expirationDate: now.addingTimeInterval(86400), provisionedUDIDs: ["UDID-ONE"], certMatchesProvision: true, sha1Fingerprint: "fixture", p12Filename: "fixture.p12", provisionFilename: "fixture.mobileprovision", createdAt: now, certificateExpirationDate: now.addingTimeInterval(86400), certificateCreationDate: now.addingTimeInterval(-3600), provisionsAllDevices: false, allowsDebugging: false, entitlements: ["get-task-allow": .bool(false)])
        let assess: (NiKCertificateProfile, String?) -> NiKCertificateAssessment = {
            NiKCertificateCompatibility.assess($0, bundleID: "com.example.demo", deviceUDID: $1, now: now)
        }
        precondition(assess(profile, "udid-one").canSign)
        precondition(assess(profile, nil).issues.contains { $0.code == "device.unknown" })
        precondition(!assess(profile, "other-device").canSign)
        precondition(assess(profile, nil).distribution == .adHoc)
        let differentID = NiKCertificateCompatibility.assess(profile, bundleID: "com.examples.demo", now: now)
        precondition(differentID.canSign)
        precondition(differentID.issues.contains { $0.code == "bundle.mismatch" && $0.severity == .warning })
        var fixedID = profile
        fixedID.bundleIDPattern = "com.example.fixed"
        precondition(NiKCertificateCompatibility.assess(fixedID, bundleID: "com.other.app", now: now).canSign)
        fixedID.certificateExpirationDate = now.addingTimeInterval(-1)
        precondition(!NiKCertificateCompatibility.assess(fixedID, bundleID: "com.other.app", now: now).canSign)
        precondition(!NiKCertificateCompatibility.bundleMatches(pattern: "com.example.*", bundleID: "com.example"))
        precondition(!NiKCertificateCompatibility.bundleMatches(pattern: "*", bundleID: "*"))
        precondition(NiKCertificateCompatibility.bundleMatches(pattern: "*", bundleID: "com.any.app"))
        profile.certificateExpirationDate = now.addingTimeInterval(-1)
        precondition(!assess(profile, nil).canSign)
        profile.certificateExpirationDate = now.addingTimeInterval(86400)
        profile.expirationDate = now.addingTimeInterval(-1)
        precondition(!assess(profile, nil).canSign)
        profile.expirationDate = now.addingTimeInterval(86400)
        profile.certMatchesProvision = false
        precondition(!assess(profile, nil).canSign)
        precondition(NiKCertificateCompatibility.assess(profile, bundleID: "com.example.demo", now: now, allowMismatch: true).canSign)
        profile.certMatchesProvision = true
        profile.provisionsAllDevices = true
        precondition(assess(profile, "other-device").canSign)
        precondition(assess(profile, nil).distribution == .enterprise)
        profile.provisionsAllDevices = false; profile.allowsDebugging = true; profile.provisionedUDIDs = []
        precondition(assess(profile, nil).distribution == .development)
        precondition(!assess(profile, "UDID-ONE").canSign)
        profile.allowsDebugging = false
        precondition(assess(profile, nil).distribution == .appStore)
        profile.certificateCreationDate = now.addingTimeInterval(60)
        precondition(!assess(profile, nil).canSign)
        profile.certificateCreationDate = now.addingTimeInterval(-60)
        var old = try JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as! [String: Any]
        for key in ["certificateExpirationDate", "certificateCreationDate", "provisionsAllDevices", "allowsDebugging", "entitlements"] { old.removeValue(forKey: key) }
        let migrated = try JSONDecoder().decode(NiKCertificateProfile.self, from: JSONSerialization.data(withJSONObject: old))
        precondition(migrated.id == profile.id && migrated.certificateExpirationDate == nil)
        precondition(assess(migrated, nil).issues.contains { $0.code == "certificate.expiry.unknown" })
        let original: [String: Any] = ["bool": true, "zero": 0, "real": 1.5, "date": Date(timeIntervalSince1970: 123), "data": Data([0,1,2]), "nested": ["x", 2] as [Any]]
        let value = try NiKPlistValue(original)
        let binary = try PropertyListSerialization.data(fromPropertyList: value.foundationValue, format: .binary, options: 0)
        let restored = try NiKPlistValue(PropertyListSerialization.propertyList(from: binary, format: nil))
        precondition(value == restored)
        if case .dictionary(let fields) = value { precondition(fields["bool"] == .bool(true) && fields["zero"] == .integer(0)) }
        else { fatalError("Dictionary expected") }
        var deep: Any = "leaf"
        for _ in 0..<70 { deep = [deep] }
        expectFailure { _ = try NiKPlistValue(deep) }
        expectFailure { _ = try NiKPlistValue(NSNull()) }
        print("PASS: exact/wildcard IDs, UDID membership/unknown, distribution, both expiries, mismatch policy, not-before, old-record decoding and typed plist round trip/bounds")
    }
}
