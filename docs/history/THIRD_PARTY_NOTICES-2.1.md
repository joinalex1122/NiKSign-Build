# NiKSign 2.1: sources and licenses

Modified 2026-11-11. The new NiKSign source is distributed under GPL-3.0;
see LICENSE. The user's original uploaded prototype remains separate and is
not presented as upstream 3105 or ESign code.

## 3105

Author: YangJiii / YangJiiii and contributors.
Source: https://github.com/YangJiiii/3105
Pinned commit: a72617ed4c764a65d8aac1e91aca95231e72a2cb
License: GPL-3.0, reproduced in LICENSE and Native/Licenses/NiKSign-GPL-3.0.txt.

Two files are copied, with an added provenance header only:
- ThreeOneOSFive/helpers/PatchPackageCodec.swift
- ThreeOneOSFive/helpers/PatchProjectModels.swift

They implement the binary `3105PATCH\0` envelope versions 1–3. The
workspace schema versions described in the project guide are a separate
concept. NiKSign does not claim full v9 interoperability. Its original
JSON sample is not the encrypted native format. No sandbox-escape,
MobileHouseArrest, kernel, anti-detection or third-party exploit code is
copied or integrated. Upstream's private-patch contents are not exposed by
NiKSign's editor. Public-format codec operation is local to imported files.

Reference guide: https://github.com/YangJiiii/3105/blob/a72617ed4c764a65d8aac1e91aca95231e72a2cb/docs/PATCH_GUIDE.vi.md

## Feather

Author: Samara / claration and contributors.
Source: https://github.com/claration/feather
License: GPL-3.0.

SigningHandler/ZsignHandler and package configuration were consulted to
understand the signing flow. No Feather application source is copied.
NiKSign uses the Zsign package directly. This is not an ESign source merge;
an authoritative open-source ESign application repository was not verified.
The discovered iOS17/Esign repository contained only a README at review time.

## Zsign Swift package

Source: https://github.com/claration/zsign
Pinned revision: c4ba9da4283031c07efa03bce42c4b8602d22e73
License: MIT. See Native/Licenses/Zsign-LICENSE.txt.
Originally referenced in Feather as khcrysalis/Zsign-Package, now redirected
to claration/zsign. Fetched by Xcode/SwiftPM during the build.

## ZIPFoundation

Source: https://github.com/weichsel/ZIPFoundation
Version: 0.9.20. License: MIT, see Native/Licenses/ZIPFoundation-LICENSE.txt.
Used for IPA extraction and re-packaging. NiKSign rejects symlinks,
noncanonical paths, duplicate entries and excessive expanded size/count.

## OpenSSL package

Source: https://github.com/krzyzanowskim/OpenSSL
Transitive dependency of Zsign. Its package license is included in
Native/Licenses/OpenSSL-LICENSE.txt (from 3.3.3001, Zsign's minimum).
SwiftPM may resolve a newer compatible 3.x release. Preserve the resolved
Package.resolved from a successful build when stabilizing releases, and
review the notices for the exact resolved OpenSSL distribution before
redistributing a binary. The source package has not been resolved or built
with Xcode in this Linux environment.
