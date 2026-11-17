# Validation — 2026-11-17 (NiKSign 3.3-dev)

## Passed

- `python3 scripts/check-integration.py`: 104 upstream files match their recorded
  SHA-256 hashes; all 66 upstream Swift/Objective-C/C translation units are
  represented in the target (two explicit overlays), plus NiKSign 3.2 & 3.3 tools.
- `python3 scripts/check-dependencies.py`: 11 registry entries, exact refs, all
  license texts, vendor hashes, 3.2 Signer modules (`NiKCertificateStore`,
  `NiKDylibInjector`, `NiKAltSourceView`, HTTP export + `manifest.plist`),
  and 3.3 3105-v2.0 modules (`NiKPatchV9Engine`, `NiKDialerService`,
  `NiKSystemFeaturesService`, `NiK3105V2HubView`) source wiring checked.
- `python3 Tests/minizip_test.py`: compiled the actual C preflight with upstream
  minizip and system zlib; all 5 test cases passed.
- `node Tests/web.test.js`: passed all web tool checks.

- `python3 Tests/verify_ipa_test.py`: seven IPA validator regression cases passed,
  including optimized Python and bounded reads for a 16 MiB executable.
- `python3 Tests/patch_v9_test.py`: six Python reference cases passed.
- `bash -n scripts/build-ios.sh` and `git diff --check` passed.

## Native CI

The workflow compiles and executes `CodecSmoke.swift`, `PatchV9Smoke.swift`, and
nine `PatchV9TransactionSmoke.swift` filesystem scenarios before building the app.
Check the run associated with the exact commit for the native result and artifact.

## Not yet verified on a physical device

- Real-device startup, permission/backend behavior, patch apply/restore,
  AppGroup resolution, Dialer `.3105pass`, Footnote/Supervised, signing or OTA installation.
