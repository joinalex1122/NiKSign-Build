#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUNDLE_ID="${NIKSIGN_BUNDLE_ID:-com.apple.mobile.MobileHouseArrest}"
command -v xcodebuild >/dev/null || { echo 'Cần macOS + Xcode hoặc GitHub Actions macOS.' >&2; exit 1; }
python3 scripts/check-integration.py
python3 scripts/check-dependencies.py
xcodegen generate
mkdir -p build
xcodebuild -project NiKSign.xcodeproj -scheme NiKSign -configuration Release \
  -sdk iphoneos -destination 'generic/platform=iOS' -derivedDataPath build \
  NIKSIGN_BUNDLE_ID="$BUNDLE_ID" PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO ARCHS=arm64 build 2>&1 | tee build/build.log
app=build/Build/Products/Release-iphoneos/NiKSign.app
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$app/Info.plist"
file "$app/NiKSign" | tee build/binary-info.txt
lipo "$app/NiKSign" -verify_arch arm64
rm -rf dist/Payload
rm -f dist/NiKSign-unsigned.ipa
mkdir -p dist/Payload
cp -R "$app" dist/Payload/
(cd dist && /usr/bin/zip -qry NiKSign-unsigned.ipa Payload)
NIKSIGN_EXPECTED_BUNDLE_ID="$BUNDLE_ID" python3 scripts/verify-ipa.py dist/NiKSign-unsigned.ipa
