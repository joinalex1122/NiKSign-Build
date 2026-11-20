# NiKSign 3.4.1 (341) installation audit handoff

Repository: https://github.com/joinalex1122/NiKSign-Build

Tested commit: `00536006ae5c9ab2a367b8fff24c6b98ff4f9d04`. Reviewed base: `83aed63f168324f64bec0873f110b496f3f5c30a`.

[CI run](https://github.com/joinalex1122/NiKSign-Build/actions/runs/44557836533): both consecutive clean full suites and arm64 Release device builds passed, 55 PASS groups per pass, zero compiler warnings/errors. Strict TLS listener tests passed twice. Only the pass2 IPA is published.

[IPA + tested source artifact](https://github.com/joinalex1122/NiKSign-Build/actions/runs/44557836533/artifacts/14550288984) contains one unsigned IPA and its source snapshot. [Both complete logs / diagnostics](https://github.com/joinalex1122/NiKSign-Build/actions/runs/44557836533/artifacts/14550859061) contain pass1.log, pass2.log and build metadata. Final verification documents accompany the source snapshot and are recorded in the repository after CI; runtime source is unchanged from the tested commit.

| File | SHA-256 |
|---|---|
| NiKSign-3.4.1-0053600-unsigned.ipa | `998b331536d0bcc5c0aea80e97fb440e9f1619ded135245a32bef07f0e69e06f` |
| NiKSign-3.4.1-0053600-source.zip | `acae238d67e78ab5d0b496b68457963cf3e9017346ddd3fd2872b12743b7dde6` |

IPA: 5,533,056 bytes, Bundle ID `com.niksign.app`, version 3.4.1, build 341, arm64. ZIP integrity and executable mode passed. The source snapshot was verified against all 259 packaged tracked files at the tested commit.

The [audit](IPA-INSTALL-AUDIT.md) lists each defect or validation/transport risk with exact before/after file and line references. Changes cover authenticated profile CMS and selected certificate matching, profile/Bundle ID/expiry checks, pre-sign extension cleanup and version alignment, executable permissions across native reallocation, fail-closed nested and CMS signing, versioned-framework symlink/resource seals, selected signer validation, final ZIP validation, strict CA/leaf key identifiers and renewal, HTTP byte ranges and graceful close, and exact manifest preflight. Existing finite UIApplication background task ownership is preserved.

Earlier attempts found and corrected a strict TLS Missing Authority Key Identifier failure and an obsolete unsigned-XML test fixture. Those attempts were excluded from the two final successful passes.

## Device test to complete

1. Sign this unsigned NiKSign build using your valid certificate/profile and install it.
2. In NiKSign, download the new HTTPS trust profile, install it and enable full trust for **NiKSign Local OTA CA** in iOS Settings. Older roots are replaced once to satisfy the corrected policy.
3. Import a decrypted iPhone IPA and a matching valid p12/profile. With a single exact profile, incompatible extensions are removed and named in the result. Use a compatible wildcard/profile if those extensions are needed.
4. Sign, open the signed-app installation view, run the HTTPS connection check, then install while NiKSign stays available. Compare the same signed IPA in another installer if iOS rejects it and retain the exact installd error for diagnosis.

Physical installation is not claimed as verified. No user p12, private signing keys, or failing signed Garena IPA/device installd log were provided. Apple issuer trust, UDID eligibility, revocation, Developer Mode/MDM restrictions and finite background time still apply. The prior removal of system-container/exploit functionality remains intact.
