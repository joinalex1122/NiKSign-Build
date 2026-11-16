# Validation — 2026-11-16 (NiKSign 3.3-dev)

## Passed

- `python3 scripts/check-integration.py`: 104 upstream files match their recorded
  SHA-256 hashes; all 66 upstream Swift/Objective-C/C translation units are
  represented in the target (two explicit overlays), plus NiKSign 3.2 & 3.3 tools.
- `python3 scripts/check-dependencies.py`: 11 registry entries, exact refs, all
  license texts, vendor hashes, 3.2 Signer modules (`NiKCertificateStore`,
  `NiKDylibInjector`, `NiKAltSourceView`, OTA `manifest.plist` + `itms-services://`),
  and 3.3 3105-v2.0 modules (`NiKPatchV9Engine`, `NiKDialerService`,
  `NiKSystemFeaturesService`, `NiK3105V2HubView`) verified.
- `python3 Tests/minizip_test.py`: compiled the actual C preflight with upstream
  minizip and system zlib; all 5 test cases passed.
- `node Tests/web.test.js`: passed all web tool checks.

## Not yet verified

- XcodeGen execution, SwiftPM package resolution, Swift/Objective-C/C compilation
  with the iOS SDK, linking, and packaging an arm64 binary on macOS.
- Real-device startup, permission/backend behavior, patch apply/restore,
  AppGroup resolution, Dialer `.3105pass`, Footnote/Supervised, signing or OTA installation.
