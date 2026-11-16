import os, sys, zipfile, plistlib, struct
expected_bundle_id = os.environ.get('NIKSIGN_EXPECTED_BUNDLE_ID', 'com.apple.mobile.MobileHouseArrest')
with zipfile.ZipFile(sys.argv[1]) as z:
    root = 'Payload/NiKSign.app/'
    p = plistlib.loads(z.read(root + 'Info.plist'))
    assert p['CFBundleIdentifier'] == expected_bundle_id, f'Expected Bundle ID {expected_bundle_id}, got {p.get("CFBundleIdentifier")}'
    assert 'threeoneosfive' in p['CFBundleURLTypes'][0]['CFBundleURLSchemes']
    assert 'niksign' in p['CFBundleURLTypes'][0]['CFBundleURLSchemes']
    for language in ['en', 'vi', 'zh-Hans']:
        assert root + language + '.lproj/Localizable.strings' in z.namelist()
    exe = p['CFBundleExecutable']
    assert exe and '/' not in exe and '\\' not in exe and exe not in ('.', '..')
    binary = z.read(root + exe)
    assert len(binary) > 32 and binary[:4] == b'\xcf\xfa\xed\xfe', 'Expected thin 64-bit Mach-O'
    assert struct.unpack('<I', binary[4:8])[0] == 0x100000c, 'Expected arm64'
    assert not any('entitlements.plist' in n for n in z.namelist())
    print(f'Verified arm64 executable, Bundle ID ({expected_bundle_id}) and localized resources. IPA remains unsigned.')
