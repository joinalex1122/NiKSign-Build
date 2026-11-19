# NiKSign reliability and build changes — 2026-11-17

Base: `4569c3dc1a1cfafe50eb588da5e14dd76072646f`.

| Issue | Change | Verification |
| --- | --- | --- |
| lipo treats executable path as an architecture | Place input before `-verify_arch arm64` | macOS workflow builds and checks final IPA |
| Reapply overwrites original backup | Refuse reapply while a receipt exists; Restore first | Swift transaction regression |
| Originals persisted after mutation | Precompute outputs; atomically save journal before any write | Journal-write failure leaves originals untouched |
| Partial restore discards backups | Keep failed entries for retry and report partial restoration | Missing-container and write-failure/retry scenarios |
| Repeated container lookup during restore | Cache success/failure by typed container key, once per operation | 100 files resolve their container once per apply/restore |
| Prefix matching allocates array of every match | Scan once, stop at second match, O(1) auxiliary memory | Existing merge smoke tests |
| Duplicate settings/manifest keys crash dictionary initialization | Explicit duplicate validation throws an error | Duplicate-field regression |
| Unbounded IPA binary read and assertions disabled by Python -O | Read only the Mach-O header, stream CRC verification, explicit exceptions | Seven Python IPA validation tests |
| HTTPS scheme points at HTTP-only GCDWebServer | Keep local HTTP export; reject HTTPS host spoofing, remove unavailable OTA action | Source check and native compile |

## Transaction semantics

Apply and restore are serialized inside the service. Validate all outputs and duplicate
canonical paths before mutation. Reject target-path symlinks. A pending journal blocks
reapply, including after interruption. Limits: 10,000 rules, 32 MiB per target/payload,
128 MiB combined originals and outputs. Backup JSON is checked against a 256 MiB limit.
Rollback failures retain the journal. Restore can be retried for unresolved entries.
These safeguards do not coordinate writes by other apps or system processes.

## Build and evidence

The workflow uses one macOS 15 runner instead of four redundant packaging jobs. It
runs the existing codec/merge tests plus nine Swift filesystem transaction scenarios
before the iOS build. Diagnostics and the resolved SwiftPM packages are uploaded even
when a build fails. The main output is an **unsigned** arm64 IPA and matching source ZIP.

Linux checks: upstream/source hashes, dependency wiring, five actual C minizip cases,
six Python merge-reference cases, seven IPA-validator cases, four web cases, shell
syntax and diff whitespace. Python reference tests do not substitute for native tests.
Native CI and final artifact validation must pass before reporting build success.
Real-device patching, certificates and installation remain unverified.

## Scope of integrations

TrollFools, ellekit and optool remain references, not linked engines. No LCSign/ESign
source was added. The local HTTP server exports files; it does not implement TLS or OTA.

## Memory measurement

Single Linux `tracemalloc` run, synthetic IPA with a 32 MiB zero-filled Mach-O:
old validator 77.48 MiB peak / 0.150 s; new validator 2.17 MiB / 0.074 s.
The new run additionally verifies all member CRCs. These are Python allocator
measurements for this fixture, not iPhone app memory or general performance guarantees.
