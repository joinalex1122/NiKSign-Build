# NiKSign 3.1-dev — source and attribution

Integration changes dated 2026-11-16. New NiKSign integration source is GPL-3.0.
Preserve the complete corresponding source and applicable notices when
redistributing binaries.

## 3105 — YangJiii / YangJiiii and contributors

https://github.com/YangJiiii/3105
Commit: a72617ed4c764a65d8aac1e91aca95231e72a2cb

The full published application source, Xcode project, resources, documentation,
LICENSE and THIRD_PARTY_NOTICES.md are retained under Vendor/3105, unchanged.
`upstream-lock.json` records the SHA-256 of every vendored file.

The compiled integration substitutes two files, with notices in their headers:
- Native/Integration/App.swift: NiKSign entry name, file URL routing, signer
  sheet, and disabling upstream-app update offers in this independently named app.
- Native/Integration/RepositoryHomeView.swift: NiKSign title and tool button.

The remaining 64 upstream translation units are included without modifications.
Upstream display attribution and credits remain in the app. Its current icon
is retained as an upstream asset; this build has not been given a new icon.

The upstream GPL-3.0 license applies to original 3105 portions. Third-party
material retains its own terms. Read Vendor/3105/THIRD_PARTY_NOTICES.md,
including its note that a repository license for FilzaSlop was not exposed
when the upstream notice was prepared. This integration does not establish
additional rights over those third-party portions or remove their notices.

## Zsign — MIT

https://github.com/claration/zsign
Revision: c4ba9da4283031c07efa03bce42c4b8602d22e73
Fetched by SwiftPM. Native/Licenses/Zsign-LICENSE.txt contains the notice.
Feather (https://github.com/claration/feather, GPL-3.0) was consulted for the
signing flow; no ESign source was verified or copied.

## ZIPFoundation — MIT

https://github.com/weichsel/ZIPFoundation, exact version 0.9.20.
Notice: Native/Licenses/ZIPFoundation-LICENSE.txt.

## OpenSSL

https://github.com/krzyzanowskim/OpenSSL, transitive Zsign dependency.
OpenSSL is now pinned to 3.6.5000; Native/Licenses/OpenSSL-LICENSE.txt was fetched from that tag.
Preserve the actual Package.resolved and exact distribution notices from a
successful macOS build; the build-evidence workflow artifact captures that
resolved dependency list when available. SwiftPM resolution has not run here.

## Historical notices

`docs/history/` records the narrower 2.1 integration and validation. Claims in
those files about the absence of backend code no longer describe 3.0-dev;
FEATURES.md and this notice describe the current integration.

## Additional components in 3.1

See Native/Licenses/components.json for all 11 requested components, canonical
URLs, exact revisions and full license text filenames. MachOKit, ArArchiveKit
and SWCompression are SwiftPM dependencies. Original minizip reader/ioapi
source and GCDWebServer Core/Requests/Responses are vendored unchanged, with
hashes in dependencies-vendor-lock.json. NiKSign wrappers are original
integration code. minizip retains its zlib license; GCDWebServer retains BSD-3.

TrollFools, ellekit and optool license notices are included as references;
their engines have not been linked or executed. The optional source-fetch
script checks out the named snapshots without running them. Their presence
in the license screen must not be interpreted as operational features.

New source additions and build wiring are not yet Xcode/device validated.
