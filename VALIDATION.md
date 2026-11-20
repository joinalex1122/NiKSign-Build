# NiKSign 3.4.1 (341) installation audit validation

Tested commit: `00536006ae5c9ab2a367b8fff24c6b98ff4f9d04`. [CI run](https://github.com/joinalex1122/NiKSign-Build/actions/runs/44557836533) completed successfully on macos-15-intel / Xcode 16.4 on 19 November 2026.

Two consecutive clean full-suite and Release iphoneos arm64 builds passed. Each pass produced 55 PASS groups, one BUILD SUCCEEDED marker and zero compiler warning/error diagnostics. The actual Network.framework HTTPS server passed strict generated-root TLS, manifest metadata, full/HEAD/Range transfers, 416, route isolation and connection cleanup in both passes.

Source/dependency/provenance checks, XcodeGen and the full signing/CMS/profile/extension/archive/queue/certificate regressions passed in both suites. Additional local shell and Swift syntax checks passed. The published source archive matches all 259 packaged tracked files at the tested commit. The final unsigned IPA passes CRC, Bundle ID, executable mode and arm64 checks.

See the [full audit with before/after line references](docs/IPA-INSTALL-AUDIT.md), [machine-readable verification](docs/verification/ipa-install-3.4.1.json) and [handoff](docs/IPA-INSTALL-HANDOFF.md).

Physical iPhone installation remains unverified. The app IPA is unsigned; real signing certificate/profile trust, UDID eligibility, revocation and iOS policy still apply. Legacy local HTTPS CAs rotate once and require installing/trusting the new public CA profile. Background service time remains subject to iOS limits.
