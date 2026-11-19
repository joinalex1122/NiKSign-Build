# NiKSign 3.4.1 installation audit validation

Base: 83aed63. See [IPA installation audit](docs/IPA-INSTALL-AUDIT.md) for root causes, before/after line references, controls verified correct and test coverage.

Local source/dependency/shell/Swift syntax, minizip and IPA validation checks pass. Focused tests cover real CMS provisioning, exact/wildcard profile matching, certificate membership/expiry, extension ID/version cleanup, archive symlinks/modes, HTTP ranges/manifest generation, native CMS/resource seals, nested failure propagation, queue removal/revocation and leaf TLS extensions.

Full macOS test suite and Xcode validation are pending. The workflow requires two consecutive clean passes on the same source before release; both compiler logs must contain BUILD SUCCEEDED and zero warning/error diagnostics. Only the second IPA is published.

No iPhone installation success is claimed without physical-device validation. The resulting app build is unsigned; signing certificate/provisioning/device eligibility and local CA full trust still apply. Legacy noncompliant local CAs rotate once and require installing/trusting the new public certificate profile.
