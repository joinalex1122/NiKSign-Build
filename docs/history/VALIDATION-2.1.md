# Validation — 2026-11-11

## Passed in the current Linux workspace

- `node Tests/web.test.js`: four tests passed (JSON preservation/Unicode,
  malformed-input rejection, typed fields, prototype-safe keys, native header
  identification and honest JSON output naming).
- `node --check web/app.js`: passed.
- `bash -n scripts/build-ios.sh`: passed.
- YAML parsing: project and workflow files parse; application dependencies
  reference Zsign and ZIPFoundation.
- `node Tests/browser.cjs` using system Chromium via Playwright at a 390×844
  mobile viewport: JSON/plist import, typed edit, draft restore after reload,
  download event and filename, encrypted 3105 header rejection, retention of
  current document on failed import, and malformed plist dictionary rejection
  all passed, with no browser page errors.
- Screenshot: Tests/web-preview.png. Chromium emulation is not Safari testing.

Browser launch required running outside the process sandbox because the
sandbox blocked Chromium's sockets. Tests intercept all application requests
with local file data at https://niksign.test; no server or remote deployment
was used. The URL is a test origin, not a published site.

## Prepared but not executed here

- `Tests/CodecSmoke.swift`: native codec plain/encrypted round trip, wrong
  password, password protection retained after update, corruption rejection,
  unsafe paths and duplicate targets. Runs with swiftc on macOS in Actions.
- XcodeGen project generation, SwiftPM resolution, iOS SDK compilation,
  `lipo -verify_arch arm64` and packaged IPA verification.
- Actual certificate/profile signing, iOS installation and launch, Files
  integration and iPhone Safari/Web Share behavior.
- GitHub Pages deployment and GitHub Actions runs: no destination repository
  was provided. No upstream repository was modified.

No IPA binary was built. No signing identity, provisioning profile or Apple
account credentials were supplied or bundled. Successful local web checks
must not be represented as a successful native build or installation.

## First native verification

Run the included Build NiKSign workflow. Preserve its logs and Package.resolved
when investigating failures. After a successful build, test import/export on a
real device with a suitable signing profile, and verify any output IPA through
an actual installation before describing the native signer as device-tested.
