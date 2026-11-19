import Foundation
import ZIPFoundation

func runSigningInstallabilitySmoke(root: URL, fixture: NiKProvisionFixture) throws {
    func rejects(_ action: () throws -> Void) {
        do { try action() } catch { return }
        fatalError("Expected installability rejection")
    }
    let codeDirectory = Data("owned CodeDirectory fixture".utf8)
    let cms = try fixture.detached(codeDirectory)
    try NiKProvisioningValidation.verifyDetachedCMS(cms, content: codeDirectory, certificateDER: fixture.der)
    rejects { try NiKProvisioningValidation.verifyDetachedCMS(cms, content: Data("tampered".utf8), certificateDER: fixture.der) }
    rejects { try NiKProvisioningValidation.verifyDetachedCMS(cms, content: codeDirectory, certificateDER: Data([1,2])) }
    let wildcard = try fixture.profile(), exact = try fixture.profile(pattern: "com.example.demo")
    try NiKProvisioningValidation.validate(wildcard, bundleID: "com.example.demo", certificateDER: fixture.der)
    try NiKProvisioningValidation.validate(exact, bundleID: "com.example.demo", certificateDER: fixture.der)
    rejects { try NiKProvisioningValidation.validate(exact, bundleID: "com.other.demo") }
    rejects { try NiKProvisioningValidation.validate(wildcard, bundleID: "com.examples.demo") }
    rejects { try NiKProvisioningValidation.validate(wildcard, bundleID: "com.example.demo", certificateDER: Data([1,2])) }
    let expired = try fixture.profile(expiration: Date().addingTimeInterval(-1))
    rejects { try NiKProvisioningValidation.validate(expired, bundleID: "com.example.demo") }
    rejects { _ = try NiKProvisioningValidation.decode(Data("<plist><dict/></plist>".utf8)) }
    var corrupted = wildcard
    let payload = Data("com.example.*".utf8)
    if let range = corrupted.range(of: payload) { corrupted[range.lowerBound] ^= 1 }
    else { fatalError("CMS fixture must contain its attached content") }
    rejects { _ = try NiKProvisioningValidation.decode(corrupted) }
    try NiKProvisioningValidation.validateCertificate(fixture.der, now: Date())
    rejects { try NiKProvisioningValidation.validateCertificate(fixture.der, now: Date().addingTimeInterval(3 * 86400)) }
    precondition(NiKProvisioningPattern.matches(pattern: "com.example.pre*", bundleID: "com.example.prefix"))
    precondition(!NiKProvisioningPattern.matches(pattern: "com.*.bad*", bundleID: "com.example.bad"))
    let signed: [String: Any] = ["application-identifier": "SEEDFIX123.com.example.demo", "com.apple.developer.team-identifier": "TEAMFIX123", "keychain-access-groups": ["TEAMFIX123.com.example.demo"]]
    let allowed: [String: Any] = ["keychain-access-groups": ["TEAMFIX123.*"]]
    try NiKProvisioningValidation.validateEntitlements(signed, allowed: allowed, applicationID: "SEEDFIX123.com.example.demo", teamID: "TEAMFIX123")
    rejects { try NiKProvisioningValidation.validateEntitlements(signed, allowed: ["keychain-access-groups": ["OTHER.*"]], applicationID: "SEEDFIX123.com.example.demo", teamID: "TEAMFIX123") }
    print("PASS: real CMS provisioning content/tamper rejection, exact/suffix wildcard IDs, profile expiry and certificate DER membership/expiry")

    let bytes = Data([0xcf,0xfa,0xed,0xfe] + [UInt8](repeating: 0,count: 28))
    let wrongProfile = try signedFixture("output-wrong-profile", bundleID: "com.example.demo", signature: true, executable: bytes, profileData: fixture.profile(pattern: "com.other.app"))
    rejects { try NiKSignedOutputValidator.validate(wrongProfile, expectedBundleID: "com.example.demo") }
    let wrongMode = try signedFixture("output-wrong-mode", bundleID: "com.example.demo", signature: true, executable: bytes, executableMode: 0o644)
    rejects { try NiKSignedOutputValidator.validate(wrongMode, expectedBundleID: "com.example.demo") }
    let missingBuild = try signedFixture("output-no-build", bundleID: "com.example.demo", signature: true, executable: bytes, buildVersion: nil)
    rejects { _ = try NiKInstallMetadata.read(missingBuild) }
    print("PASS: post-package validator rejects profile/Bundle ID mismatch, missing execute permission and missing CFBundleVersion")
    let fm = FileManager.default
    let app = root.appendingPathComponent("prepare/Demo.app")
    func extensionBundle(_ name: String, _ id: String) throws -> URL {
        let path = app.appendingPathComponent("PlugIns/" + name + ".appex")
        try fm.createDirectory(at: path, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": id, "CFBundleExecutable": name], format: .xml, options: 0).write(to: path.appendingPathComponent("Info.plist"))
        return path
    }
    let kept = try extensionBundle("Good", "com.old.app.good"), removed = try extensionBundle("Foreign", "com.foreign.extension")
    try fm.createDirectory(at: app.appendingPathComponent("Watch/Watch.app"), withIntermediateDirectories: true)
    let notes = try NiKSigningBundlePreparation.prepare(app: app, oldID: "com.old.app", newID: "com.example.app", profilePattern: "com.example.*", removeAll: false, buildVersion: "42", shortVersion: "2.0")
    let edited = try PropertyListSerialization.propertyList(from: Data(contentsOf: kept.appendingPathComponent("Info.plist")), format: nil) as! [String: Any]
    precondition(edited["CFBundleIdentifier"] as? String == "com.example.app.good")
    precondition(edited["CFBundleVersion"] as? String == "42" && edited["CFBundleShortVersionString"] as? String == "2.0")
    precondition(!fm.fileExists(atPath: removed.path) && !fm.fileExists(atPath: app.appendingPathComponent("Watch").path) && notes.count == 2)
    let singleNotes = try NiKSigningBundlePreparation.prepare(app: app, oldID: "com.example.app", newID: "com.example.app", profilePattern: "com.example.app", removeAll: false)
    precondition(!fm.fileExists(atPath: kept.path) && singleNotes.count == 1)
    _ = try extensionBundle("Explicit", "com.example.app.ext")
    _ = try NiKSigningBundlePreparation.prepare(app: app, oldID: "com.example.app", newID: "com.example.app", profilePattern: "*", removeAll: true)
    precondition(!fm.fileExists(atPath: app.appendingPathComponent("PlugIns").path))
    print("PASS: compatible extension ID rewrite, incompatible/exact-profile extension removal, explicit removal and Watch cleanup before signing")

    let manifest = try NiKOTAHTTP.manifest(ipaURL: URL(string: "https://127.0.0.1:123/token/app.ipa")!, bundleID: "com.example.demo", buildVersion: "42", title: "Demo & <Test>")
    let dict = try PropertyListSerialization.propertyList(from: manifest, format: nil) as! [String: Any]
    let metadata = (dict["items"] as! [[String: Any]])[0]["metadata"] as! [String: Any]
    precondition(metadata["bundle-version"] as? String == "42" && metadata["title"] as? String == "Demo & <Test>" && metadata["bundle-identifier"] as? String == "com.example.demo")
    for (range, start, length) in [("bytes=0-9",0,10),("bytes=10-",10,90),("bytes=-5",95,5),("bytes=90-999",90,10)] {
        let response = NiKOTAHTTP.FileResponse.make(size: 100, range: range)
        precondition(response.status.hasPrefix("206") && response.offset == start && response.length == length)
    }
    for range in ["bytes=100-", "bytes=9-3", "bytes=0-1,3-4", "bytes=-0", "bytes=18446744073709551616-", "else=0-1"] {
        let response = NiKOTAHTTP.FileResponse.make(size: 100, range: range)
        precondition(response.status.hasPrefix("416") && response.contentRange == "bytes */100")
    }
    let request = try NiKOTAHTTP.Request("HEAD /token/app.ipa HTTP/1.1\r\nHost: 127.0.0.1\r\nRange: bytes=0-9")
    precondition(request.method == "HEAD" && request.headers["range"] == "bytes=0-9")
    rejects { _ = try NiKOTAHTTP.Request("GET / HTTP/1.1\r\nRange: bytes=0-1\r\nRange: bytes=1-2") }
    print("PASS: OTA manifest metadata/build version and GET/HEAD parsing, exact/open/suffix/clamped byte ranges, overflow/multipart/duplicate-header rejection")

    let zipSource = root.appendingPathComponent("links/Payload/Demo.app")
    try fm.createDirectory(at: zipSource.appendingPathComponent("Frameworks/F.framework/Versions/A"), withIntermediateDirectories: true)
    let code = zipSource.appendingPathComponent("Frameworks/F.framework/Versions/A/F")
    try Data("owned-code-fixture".utf8).write(to: code)
    try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: code.path)
    try fm.createSymbolicLink(atPath: zipSource.appendingPathComponent("Frameworks/F.framework/Versions/Current").path, withDestinationPath: "A")
    try fm.createSymbolicLink(atPath: zipSource.appendingPathComponent("Frameworks/F.framework/F").path, withDestinationPath: "Versions/Current/F")
    try Data("root-code-fixture".utf8).write(to: zipSource.appendingPathComponent("Demo"))
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":"com.example.demo", "CFBundleExecutable":"Demo"], format: .xml, options: 0).write(to: zipSource.appendingPathComponent("Info.plist"))
    let frameInfo = zipSource.appendingPathComponent("Frameworks/F.framework/Versions/A/Info.plist")
    let frameProperties: [String: Any] = ["CFBundleIdentifier":"com.example.library", "CFBundleExecutable":"F"]
    try PropertyListSerialization.data(fromPropertyList: frameProperties, format: .xml, options: 0).write(to: frameInfo)
    try fm.createSymbolicLink(atPath: zipSource.appendingPathComponent("Frameworks/F.framework/Info.plist").path, withDestinationPath: "Versions/Current/Info.plist")
    let bundles = try NiKSigningBundlePreparation.codeBundles(in: zipSource)
    precondition(bundles.count == 2)
    try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier":"com.example.library", "CFBundleExecutable":"../../Demo"], format: .xml, options: 0).write(to: frameInfo)
    rejects { _ = try NiKSigningBundlePreparation.codeBundles(in: zipSource) }
    try PropertyListSerialization.data(fromPropertyList: frameProperties, format: .xml, options: 0).write(to: frameInfo)
    let archiveURL = root.appendingPathComponent("safe-links.ipa")
    try fm.zipItem(at: root.appendingPathComponent("links/Payload"), to: archiveURL)
    let archive = try Archive(url: archiveURL, accessMode: .read)
    let extraction = root.appendingPathComponent("safe-links-out")
    try fm.createDirectory(at: extraction, withIntermediateDirectories: true)
    try NiKIPAArchive.extract(archive, to: extraction)
    let restored = extraction.appendingPathComponent("Payload/Demo.app/Frameworks/F.framework/F")
    let restoredTarget = try fm.destinationOfSymbolicLink(atPath: restored.path)
    precondition(restoredTarget == "Versions/Current/F")
    let mode = try fm.attributesOfItem(atPath: restored.resolvingSymlinksInPath().path)[.posixPermissions] as! NSNumber
    precondition(mode.intValue & 0o111 == 0o111)
    for (name, target) in [("outside", "../../../outside"),("absolute", "/private/var"),("cycle", "Link")] {
        let url = root.appendingPathComponent(name + ".ipa"), zip = try Archive(url: url, accessMode: .create)
        let data = Data(target.utf8)
        try zip.addEntry(with: "Payload/Demo.app/Link", type: .symlink, uncompressedSize: Int64(data.count)) { _, _ in data }
        rejects { _ = try NiKIPAArchive.paths(zip) }
    }
    print("PASS: IPA Payload root, executable mode and versioned-framework symlink round trip; escaping, absolute and cyclic links rejected")
}
