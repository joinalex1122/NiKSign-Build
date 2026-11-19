"""Check signer-only source coverage and iOS metadata; Xcode build is required separately."""
from pathlib import Path
import json, plistlib, re
r = Path(__file__).resolve().parents[1]
config = (r/'project.yml').read_text()
units = list((r/'Native').rglob('*.swift'))
assert sum(len(re.findall(r'^@main\s*$', p.read_text(), re.M)) for p in units) == 1
assert '- path: Native' in config
assert 'sdk: libz.tbd' in config
assert 'SWIFT_OBJC_BRIDGING_HEADER: Native/NiKSign-Bridging-Header.h' in config
bridge = (r/'Native/NiKSign-Bridging-Header.h').read_text()
assert 'NiKZipCheck.h' in bridge and 'NiKLoopbackServer.h' in bridge
for removed in ['Vendor/3105', 'Vendor/WorseQuery', 'Native/UpstreamCompatibility']:
    assert not (r/removed).exists(), removed
    assert removed not in config
for p in (r/'Native').rglob('*'):
    if p.suffix not in {'.swift','.h','.m','.c'}: continue
    assert not re.search(r'\b(AppState|KernelExploit|ExploitSupportPolicy|PatchPackageCodec|ContainerStore|NiKHubPreview|NiKWorseQueryAccess|NiK3105AccessView|FilesTabSession|bad_query|worse_query|MCMActivateContainerPath|MobileHouseArrest|kexploit_opa334)\b', p.read_text()), p
info = plistlib.loads((r/'Native/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.niksign.app'
assert not info['CFBundleIdentifier'].lower().startswith('com.apple.')
assert info['CFBundleDisplayName'] == 'NiKSign'
assert {s for item in info['CFBundleURLTypes'] for s in item['CFBundleURLSchemes']} == {'niksign'}
assert not any(str(ext).lower() in {'3105','3105pass'} for t in info.get('UTExportedTypeDeclarations',[]) for ext in t.get('UTTypeTagSpecification',{}).get('public.filename-extension',[]))
entry = (r/'Native/Integration/App.swift').read_text()
assert 'NiKPreviewRoot()' in entry and 'NiKLibrary.shared.receive' in entry
assert all('"'+ext+'"' in entry for ext in ['ipa','p12','mobileprovision','dylib','deb'])
ui = (r/'Native/NiKPreviewUI.swift').read_text()
assert 'NiKSigningQueueView' in ui and 'NiKSigningJob(' in ui and 'certificateID: cert.id' in ui
assert 'NiKSourceLibraryView' in ui and 'NiKInstallIPAView' in ui
assert not re.search(r'@AppStorage\("nik.mode"\)', '\n'.join(p.read_text() for p in units))
for original, replacement in json.loads((r/'server-overlays.json').read_text()).items():
    assert (r/original).is_file() and (r/replacement).is_file()
    assert original.removeprefix('Vendor/GCDWebServer/') in config
print(f'PASS: {len(units)} Swift units, single signer entry, local file routes, queue, metadata and server overlay coverage.')
