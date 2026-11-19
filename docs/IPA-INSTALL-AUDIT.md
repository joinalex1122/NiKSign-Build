# IPA installation audit — NiKSign 3.4.1 (341)

Base reviewed: `83aed63f168324f64bec0873f110b496f3f5c30a`. This report distinguishes deterministic invalid-output defects, validation gaps and transport risks. No device installation success is claimed without an iPhone test.

## Findings and exact references

| Finding | Before | After | Fix / verification |
|---|---|---|---|
| Generated chain omitted SKI/AKI extensions; strict TLS handshake failed | [Native/Services/NiKTLSServerCertificate.swift:62](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Services/NiKTLSServerCertificate.swift#L62) | [Native/Services/NiKTLSServerCertificate.swift:88](../Native/Services/NiKTLSServerCertificate.swift#L88) | Generate Subject Key Identifier and Authority Key Identifier on CA and leaf. Rotate legacy local roots without these extensions; require strict X.509 verification. The actual TLS listener failed with Missing Authority Key Identifier before this correction. |
| Provisioning mismatch could report success | [Native/Models/NiKCertificateCompatibility.swift:55](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Models/NiKCertificateCompatibility.swift#L55) | [Native/Services/NiKProvisioningValidation.swift:35](../Native/Services/NiKProvisioningValidation.swift#L35) | Exact or terminal-wildcard App ID, matching p12 DER, certificate/profile dates and coherent team/seed are mandatory. Legacy mismatch override no longer bypasses validation. |
| Profile parser accepted XML fragments outside a CMS signature | [Native/Dependencies/NiKCertificateStore.swift:325](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Dependencies/NiKCertificateStore.swift#L325) | [Native/Services/NiKProvisioningValidation.swift:8](../Native/Services/NiKProvisioningValidation.swift#L8) | Decode complete attached CMS, verify its cryptographic content signature, then parse the bounded plist. Bare XML, tampered content and trailing data fail. |
| Incompatible extensions retained; rewrites swallowed errors | [Native/Signer.swift:300](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Signer.swift#L300) | [Native/Services/NiKSigningBundlePreparation.swift:30](../Native/Services/NiKSigningBundlePreparation.swift#L30) | Keep only extensions whose final IDs share the parent prefix and match the single profile. Rewrite retained IDs/versions before sealing; remove incompatible extensions, Watch companions/App Clips with persisted warnings. Throw on IO errors. |
| Native reallocation discarded executable permissions | [Vendor/Zsign/src/macho.cpp:164](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Vendor/Zsign/src/macho.cpp#L164) | [Vendor/Zsign/src/macho.cpp:168](../Vendor/Zsign/src/macho.cpp#L168) | Preserve mode on replacement for thin and fat binaries. Set all runtime code executable before signing; validate ZIP execute bits. Native tests cover app, extension and framework reallocation. |
| Nested native signing errors were ignored | [Vendor/Zsign/src/bundle.cpp:305](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Vendor/Zsign/src/bundle.cpp#L305) | [Vendor/Zsign/src/bundle.cpp:339](../Vendor/Zsign/src/bundle.cpp#L339) | Propagate raw-code signing/parse failures and invalid nested metadata. Remove iOS-only return-success on a bundle parse failure. Object/debug resources are not runtime code. |
| CMS generation failure was discarded | [Vendor/Zsign/src/archo.cpp:474](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Vendor/Zsign/src/archo.cpp#L474) | [Vendor/Zsign/src/archo.cpp:477](../Vendor/Zsign/src/archo.cpp#L477) | Fail the code-signature builder and its caller when CMS generation fails; no successful Mach-O with a missing CMS slot. |
| Valid framework links were rejected; native aliases were unsafe to re-sign | [Native/Signer.swift:84](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Signer.swift#L84) | [Native/Services/NiKIPAArchive.swift:6](../Native/Services/NiKIPAArchive.swift#L6) | Preserve links only within the same app; reject cycles, dangling/absolute/escaping links and archive writes through link ancestors. Native signer signs canonical framework executables and seals link targets as symlinks. |
| Canonical framework executable could be sealed as an ordinary resource | [Vendor/Zsign/src/bundle.cpp:177](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Vendor/Zsign/src/bundle.cpp#L177) | [Vendor/Zsign/src/bundle.cpp:195](../Vendor/Zsign/src/bundle.cpp#L195) | Exclude both the framework executable alias and its canonical target from its own resource seal. Seal parent resources after nested signatures are finalized; check resource hash failures. |
| Keychain wildcard with a different authorized seed was dropped | [Vendor/Zsign/src/archo.cpp:373](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Vendor/Zsign/src/archo.cpp#L373) | [Vendor/Zsign/src/archo.cpp:376](../Vendor/Zsign/src/archo.cpp#L376) | Concretize each authorized terminal wildcard without assuming Keychain seed equals App ID seed. Check signed app/team/keychain/get-task-allow against the profile; preserve unrelated entitlements. |
| Post-sign validation checked profile presence only | [Native/Services/NiKSignedOutputValidator.swift:65](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Services/NiKSignedOutputValidator.swift#L65) | [Native/Services/NiKSignedOutputValidator.swift:74](../Native/Services/NiKSignedOutputValidator.swift#L74) | Reparse/verify embedded CMS and enforce profile membership, selected certificate/profile byte identity, execute permission, nested metadata/profile/resource presence, build-version consistency and ZIP CRCs. |
| Nested CMS presence did not bind the selected signer | [Native/Dependencies/NiKBinaryInspector.swift:17](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Dependencies/NiKBinaryInspector.swift#L17) | [Native/Services/NiKProvisioningValidation.swift:60](../Native/Services/NiKProvisioningValidation.swift#L60) | Verify each runtime slice CMS over its primary CodeDirectory, require its signer DER to match the selected p12 and its directories to have the selected Team ID. Unsupported FAT64 is rejected before signing rather than silently skipped. |
| Unsafe nested executable metadata | [Vendor/Zsign/src/bundle.cpp:56](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Vendor/Zsign/src/bundle.cpp#L56) | [Native/Services/NiKSigningBundlePreparation.swift:6](../Native/Services/NiKSigningBundlePreparation.swift#L6) | Validate every native code-bundle executable name and canonical target within its own bundle before native code runs; framework version links stay within their framework. |
| Magic-only input check missed invalid/wrong-platform code | [Native/Signer.swift:153](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Signer.swift#L153) | [Native/Dependencies/NiKBinaryInspector.swift:22](../Native/Dependencies/NiKBinaryInspector.swift#L22) | Require an unencrypted arm64 MH_EXECUTE app, arm64 MH_DYLIB framework, code directory/CMS after signing, safe bundle-local CFBundleExecutable paths and an iPhoneOS build. |
| Known revoked credentials could still enter the signer | [Native/Services/NiKSigningQueue.swift:122](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Services/NiKSigningQueue.swift#L122) | [Native/Services/NiKSigningQueue.swift:124](../Native/Services/NiKSigningQueue.swift#L124) | Fail the job before invoking the signer. A definitive revoked result no longer ages into unknown; good status still expires normally. |
| HTTPS download ignored Range requests | [Native/Dependencies/NiKHTTPSOTAServer.swift:263](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Dependencies/NiKHTTPSOTAServer.swift#L263) | [Native/Models/NiKOTAHTTP.swift:29](../Native/Models/NiKOTAHTTP.swift#L29) | GET supports closed/open/suffix ranges, clamps ends, returns 206/Content-Range or 416, with accurate Content-Length/Content-Type and HEAD semantics. Tests exercise the actual Network.framework TLS listener. |
| Transport could cancel queued bytes; active downloads had an absolute timeout | [Native/Dependencies/NiKHTTPSOTAServer.swift:198](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Dependencies/NiKHTTPSOTAServer.swift#L198) | [Native/Dependencies/NiKHTTPSOTAServer.swift:323](../Native/Dependencies/NiKHTTPSOTAServer.swift#L323) | Finish the write stream before draining/closing; restrict the short timeout to incomplete request headers. Clean connection slots by identity. This is a transport reliability defect/risk, not a claim that every prior request was truncated. |
| Cached leaf could expire; invalid persistent CA had no recovery | [Native/Dependencies/NiKHTTPSOTAServer.swift:86](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Dependencies/NiKHTTPSOTAServer.swift#L86) | [Native/Dependencies/NiKHTTPSOTAServer.swift:163](../Native/Dependencies/NiKHTTPSOTAServer.swift#L163) | Renew expired/near-expiry leaf identities and replace expired/noncompliant local roots once. Keep compliant installed CAs stable. A rotated root requires the user to install/trust the new profile. |
| New CA did not meet the requested cRLSign/name policy | [Native/Dependencies/NiKLocalTLSIdentity.swift:123](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Dependencies/NiKLocalTLSIdentity.swift#L123) | [Native/Dependencies/NiKLocalTLSIdentity.swift:130](../Native/Dependencies/NiKLocalTLSIdentity.swift#L130) | Generate NiKSign Local OTA CA with explicit CA:TRUE, keyCertSign/cRLSign, RSA2048 and SHA256. Leaf remains CA:FALSE, serverAuth, localhost+127.0.0.1 SAN and <=30 days. Missing cRLSign alone is not asserted to explain every old TLS failure. |
| Manifest preflight only compared Bundle ID; missing build fell back to marketing version | [Native/Services/NiKInstallationController.swift:89](https://github.com/joinalex1122/NiKSign-Build/blob/83aed63f168324f64bec0873f110b496f3f5c30a/Native/Services/NiKInstallationController.swift#L89) | [Native/Services/NiKInstallationController.swift:90](../Native/Services/NiKInstallationController.swift#L90) | Require CFBundleVersion and compare manifest build version, title and exact asset URL. The existing producer already used build metadata; extraction into a shared generator enables direct tests. |

## Controls confirmed correct

- All Swift Info.plist edits, extension/Watch cleanup and injection precede Zsign. No signed content is edited afterward. Native profile staging precedes resource generation for this single-asset pipeline. ZIP packaging preserves `Payload/<App>.app` and tested link/mode metadata.
- Empty `entitlementsPath` correctly selects the profile entitlements. `adhoc=false`, native `force=true`, and `weak=false` in the wrapper are appropriate; tweak weak linking is applied before signing by the Swift injector. Native signer cache writes are disabled for the fresh staging tree; optional completion is nil-safe.
- The leaf already used RSA2048/SHA256, serverAuth, CA:FALSE, localhost/IP SANs and short validity. Root/leaf tests now assert these X.509 properties explicitly.
- The listener already acquired a UIApplication background task and ended it on stop/expiration. That behavior remains. iOS controls the finite background budget; the app cannot promise an unlimited server lifetime after Home/lock. The immutable installation snapshot and mutation lease remain in use.
- Zsign signing.cpp/openssl.cpp generate real detached CMS and return failure; the missing propagation was in their callers. Native regression verifies CMS/page/special-slot/resource hashes and rejects tampering with synthetic keys; it does not assert Apple trust.

## Tests and verification

Local: source/dependency checks, shell syntax, Swift syntax, minizip/IPA validator, actual native CMS/provisioning harnesses, archive/profile/range/extension models, queue revocation/removal and TLS certificate generator. Full macOS test suite, actual HTTPS listener and Xcode are pending CI.

CI is configured to run the entire clean suite and arm64 unsigned build twice consecutively on the same source. Both logs must contain BUILD SUCCEEDED and no compiler warning/error diagnostics. Only the second IPA is published. A failing pass prevents release and restarts the two-pass requirement after a source correction.

## Device/credential limits

The profile CMS check authenticates its signed content, not its Apple issuer-chain trust. Certificate DER membership/date checks cannot grant provisioning permissions, reverse revocation or register an absent device. Actual Apple trust, UDID membership when not supplied, Developer Mode/MDM restrictions and iOS installation outcome still need the user's device/credentials. TLS bootstrap still requires installing the public CA profile and enabling full trust manually. No user p12 or private signing keys were supplied for an on-device install reproduction.

## Changed files

- `.github/workflows/build.yml`
- `FEATURES.md`
- `Native/Dependencies/NiKBinaryInspector.swift`
- `Native/Dependencies/NiKCertificateStore.swift`
- `Native/Dependencies/NiKHTTPSOTAServer.swift`
- `Native/Dependencies/NiKLocalTLSIdentity.swift`
- `Native/Info.plist`
- `Native/Models/NiKCertificateCompatibility.swift`
- `Native/Models/NiKCertificateModels.swift`
- `Native/Models/NiKOTAHTTP.swift`
- `Native/Models/NiKProvisioningPattern.swift`
- `Native/Models/NiKSigningModels.swift`
- `Native/NiKPreviewUI.swift`
- `Native/NiKSettingsView.swift`
- `Native/NiKSignToolsView.swift`
- `Native/Services/NiKIPAArchive.swift`
- `Native/Services/NiKInstallMetadata.swift`
- `Native/Services/NiKInstallationController.swift`
- `Native/Services/NiKProvisioningValidation.swift`
- `Native/Services/NiKSignedOutputValidator.swift`
- `Native/Services/NiKSigningBundlePreparation.swift`
- `Native/Services/NiKSigningQueue.swift`
- `Native/Services/NiKTLSServerCertificate.swift`
- `Native/Signer.swift`
- `Native/Views/NiKTrustSetupView.swift`
- `README.md`
- `Tests/CertificateCompatibilitySmoke.swift`
- `Tests/Certificates/OpenSSL/shim.h`
- `Tests/Certificates/main.swift`
- `Tests/FileTools/Package.swift`
- `Tests/FileTools/main.swift`
- `Tests/HTTPSOTA/Package.swift`
- `Tests/HTTPSOTA/Server.swift`
- `Tests/QueueRemovalSmoke.swift`
- `Tests/SigningInstallabilitySmoke.swift`
- `Tests/Support/NiKProvisionFixture.swift`
- `Tests/TLSServerCertificateSmoke.swift`
- `Tests/https_ota_test.py`
- `Tests/zsign_cms_test.py`
- `Tests/zsign_provisioning_test.py`
- `VALIDATION.md`
- `Vendor/Zsign/UPSTREAM.json`
- `Vendor/Zsign/src/archo.cpp`
- `Vendor/Zsign/src/bundle.cpp`
- `Vendor/Zsign/src/common/fs.cpp`
- `Vendor/Zsign/src/macho.cpp`
- `Vendor/Zsign/swift/zsign.mm`
- `dependencies-vendor-lock.json`
- `docs/IPA-INSTALL-AUDIT.md`
- `project.yml`
- `scripts/audit-ios.sh`
- `scripts/check-dependencies.py`
- `scripts/github-package.sh`
- `scripts/test-certificates.sh`
- `scripts/test-file-tools.sh`
- `scripts/test-https-ota.sh`
- `scripts/test-local-tls.sh`
