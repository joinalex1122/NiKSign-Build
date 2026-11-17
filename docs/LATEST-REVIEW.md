# Review of the Liquid Glass and certificate import update

Base: b3d6e6c73ff18557cac369f6d70c7315e3bfaa18 (main).

The update referenced missing Swift types and model members, passed a String to optional binding, and omitted required file-browser arguments. This review restores those components while retaining the card and translucent-tab design. The large Settings expression is split into small views. Native tab containers retain navigation and in-progress UI state; safe-area layout keeps actions above the custom tab bar.

File operations now report errors, validate names, reject self-transfers and avoid overwriting existing files. ZIP extraction uses a private staging folder, verifies CRC and actual byte counts, and rejects traversal, symlinks, case-insensitive duplicate paths and oversized archives. General limits: 1 GiB expanded / 50,000 entries. Certificate packages: 16 MiB expanded / 256 entries. Failed extraction removes its staging output.

Certificate imports share one store across screens. Imports persist the index atomically before reporting success and clean up new credentials if persistence fails. Imported temporary copies follow the form's lifetime; originals in Documents are retained. Multiple pairs in a ZIP require explicit selection instead of guessing. Only unambiguous password-named TXT files are used, preserving spaces in passwords.

Signing options for file sharing, minimum OS, extensions and dylib/deb injection are restored, together with the persistent list/grid toggle, per-IPA certificate selection and signed output link. IPA icons are loaded when a conventional PNG icon exists; asset-catalog-only icons use a fallback.

Validation: existing Python/C/JavaScript checks plus macOS Swift file-import, Patch v9 and ZIP/file-operation regressions run in GitHub Actions before the arm64 unsigned IPA build. Build success does not prove real-device signing or File Provider behavior. No user certificate has been supplied for an end-to-end signing test.

The upstream 3105 support policy remains unchanged. iOS 27.2 official is not on its supported list. Ordinary sandbox file import works independently; listing protected app containers is not enabled by this update.

Device checks: import an IPA from On My iPhone and iCloud; open it from the Files tab for signing; import separate p12/profile files and a ZIP pair; verify the certificate appears in Settings and the signer; try wrong password, duplicate names, create/rename/copy/move/delete, ZIP extraction, Hex and QuickLook close; switch tabs during work and test both color modes. Signing and installation require a suitable certificate/profile and device testing.
