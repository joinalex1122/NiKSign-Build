"""Check vendored integrity, source coverage, overlay wiring and iOS metadata.
This is a source-level check, not a substitute for Xcode compilation.
"""
from pathlib import Path
import hashlib, json, plistlib, re
r = Path(__file__).resolve().parents[1]
v = r / 'Vendor/3105'
lock = json.loads((r / 'upstream-lock.json').read_text())
for relative, expected in lock['sha256'].items():
    p = v / relative
    assert p.is_file(), f'Missing upstream file: {relative}'
    assert hashlib.sha256(p.read_bytes()).hexdigest() == expected, f'Upstream changed: {relative}'
source = v / 'ThreeOneOSFive'
# Exact substitutions: every upstream translation unit must still be compiled.
overlays = {key: r/value for key, value in json.loads((r/'upstream-overlays.json').read_text()).items()}
config = (r / 'project.yml').read_text()
assert 'path: Vendor/3105/ThreeOneOSFive' in config
excludes = config.split('path: Vendor/3105/ThreeOneOSFive', 1)[1].split('- path:', 1)[0].split('dependencies:', 1)[0]
assert set(re.findall(r'- ([\w/.]+)', excludes)) == {*overlays, 'Info.plist'}
units = list(source.rglob('*.swift')) + list(source.rglob('*.m')) + list(source.rglob('*.c'))
compiled = [overlays.get(p.relative_to(source).as_posix(), p) for p in units]
compiled += [p for p in (r/'Native').rglob('*.swift') if p not in overlays.values()]
assert all(p.is_file() for p in compiled)
assert sum(len(re.findall(r'^@main\s*$', p.read_text(), re.M)) for p in compiled) == 1
assert len([p for p in compiled if p.name == 'PatchPackageCodec.swift']) == 1
assert len([p for p in compiled if p.name == 'PatchProjectModels.swift']) == 1
# Coverage of the actual upstream Xcode Sources build phase.
project = (v/'ThreeOneOSFive.xcodeproj/project.pbxproj').read_text()
source_names = set(re.findall(r'/\* ([^*]+) in Sources \*/ =', project))
assert source_names <= {p.name for p in compiled}, source_names - {p.name for p in compiled}
assert 'sdk: libz.tbd' in config
assert 'SWIFT_OBJC_BRIDGING_HEADER: Native/NiKSign-Bridging-Header.h' in config
assert '../Vendor/3105/ThreeOneOSFive/ThreeOneOSFive-Bridging-Header.h' in (r/'Native/NiKSign-Bridging-Header.h').read_text()
for language in ['en', 'vi', 'zh-Hans']:
    assert (source/f'{language}.lproj/Localizable.strings').is_file()
info = plistlib.loads((r/'Native/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'com.apple.mobile.MobileHouseArrest'
assert info['CFBundleDisplayName'] == 'NiKSign'
assert set(info['CFBundleURLTypes'][0]['CFBundleURLSchemes']) == {'threeoneosfive','niksign'}
assert info['UTExportedTypeDeclarations'][0]['UTTypeTagSpecification']['public.filename-extension'] == ['3105']
entry = overlays['App.swift'].read_text()
for state in ['appState','patchDraftCoordinator','fileOperationCoordinator','patchStore','repositoryStore']:
    assert f'.environmentObject({state})' in entry
assert 'patchDraftCoordinator.presentImport' in entry and 'NiKToolsSheet(initialURL: request.url)' in entry
assert 'showNiKTools' not in overlays['views/RepositoryHomeView.swift'].read_text()
assert '.navigationTitle("3105")' in overlays['views/RepositoryHomeView.swift'].read_text()
assert 'private func checkForUpdate() {}' in entry
assert not (r/'Native/Vendor/3105').exists()
print(f'PASS: {len(lock["sha256"])} upstream files intact; {len(units)} upstream translation units covered; single app entry, routes, localization, bridge and zlib configured.')
print('Xcode, signing and device results are recorded separately for each source commit.')
