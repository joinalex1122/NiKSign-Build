# UI preview 3.4

First launch selects Signer, 3105 or both; selection persists and can be changed
in Settings. Light/dark/system appearance and the library list/grid selection persist.
Signer-only startup does not call the 3105 automatic activation path. The local
Documents browser uses Foundation and does not request access to other containers.

IPA imports persist in Documents/IPALibrary with plist metadata, saved signing
options, per-IPA certificate selection and the last signed output path. Originals
are retained. Settings manages multiple certificate pairs and a default certificate;
a one-time prompt can be skipped. Signing uses the existing Zsign actor.

This is an installable UI prototype, not the complete ESign feature roadmap:
- Current Info.plist options, extension removal and dylib/deb injection work through
  the existing signer. Advanced file inspection is linked.
- Arbitrary plist/Mach-O/entitlement editing, icon replacement, custom compression,
  customization search, batch signing and full history are still pending.
- The local Files tab supports browsing, search, import, folders and sharing. Batch
  move/rename/delete, grid and archive operations are pending; the upstream 3105
  browser remains available for its own containers.
- 3105 tools retain their existing inner screens. Real-device compatibility is unverified.
- Brand mark inside the UI is a native text treatment; launcher asset is unchanged.

Test on device: complete onboarding in each mode, relaunch, change theme and mode,
import IPA, toggle list/grid, save options, add two certificate/profile pairs, set a
default and a per-IPA override, sign and share. Repeat after relaunch. Confirm signer-only
startup does not initiate 3105 activation. No private signing credentials are supplied.
