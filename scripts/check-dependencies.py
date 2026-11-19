"""Validate actual signer dependencies, vendored provenance and licenses."""
from pathlib import Path
import hashlib, json
r = Path(__file__).resolve().parents[1]
items = json.loads((r/'Native/Licenses/components.json').read_text())
expected = {'OpenSSL','minizip','MachOKit','ArArchiveKit','ZIPFoundation','SWCompression','GCDWebServer','Zsign'}
assert {x['name'] for x in items} == expected
config = (r/'project.yml').read_text()
for e in items:
    assert len(e['revision']) == 40 and all(c in '0123456789abcdef' for c in e['revision'])
    assert (r/'Native/Licenses'/e['licenseFile']).stat().st_size > 200
    if e['status'] == 'linked':
        assert 'package: '+e['name'] in config
        if e['name'] == 'Zsign':
            provenance = json.loads((r/'Vendor/Zsign/UPSTREAM.json').read_text())
            assert 'path: Vendor/Zsign' in config and provenance['revision'] == e['revision']
            for name, digest in provenance['originalSHA256'].items():
                value = (r/'Vendor/Zsign'/name).read_bytes()
                if name == 'src/bundle.cpp':
                    value = value.replace(b'if (!bRemoveProvision) {\n\t\t\tif (!ZFile::WriteFileV(pSignAsset->m_strProvData', b'if (bRemoveProvision) {\n\t\t\tif (!ZFile::WriteFileV(pSignAsset->m_strProvData', 1)
                if name == 'src/archo.cpp':
                    for replacement in provenance['entitlementsPatch']['replacements']:
                        after, before = replacement['after'].encode(), replacement['before'].encode()
                        assert value.count(after) == 1
                        value = value.replace(after, before, 1)
                if name == 'src/common/mach-o.h':
                    prefix = b'// Use SDK CPU/VM definitions on Apple; portable definitions remain for other hosts.\n#if defined(__APPLE__)\n#include <mach/machine.h>\n#include <mach/vm_prot.h>\n#else\n'
                    value = value.replace(prefix, b'', 1).replace(b'#endif // NiKSign portable CPU/VM definitions\n\n', b'', 1)
                assert hashlib.sha256(value).hexdigest() == digest, name
        else:
            assert e['revision'] in config or 'exactVersion: '+e['ref'] in config
for p, digest in json.loads((r/'dependencies-vendor-lock.json').read_text()).items():
    assert hashlib.sha256((r/p).read_bytes()).hexdigest() == digest, p
for name in ['MachOKit','ArArchiveKit','SWCompression']:
    assert any('import '+name in p.read_text() for p in (r/'Native').rglob('*.swift'))
server = (r/'Native/Dependencies/NiKLoopbackServer.m').read_text()
assert 'GCDWebServerOption_BindToLocalhost:@YES' in server
assert 'GCDWebServerOption_Port:@(port)' in server and 'NiKLoopbackOptions(0)' in server
assert 'manifest.plist' in server and 'self.itmsInstallURL = nil;' in server
assert 'https://%@:%lu' not in server
assert 'beginBackgroundTaskWithName' in server
signer = (r/'Native/Signer.swift').read_text()
assert 'NiKZipCheck(' in signer
assert 'NiKBinaryInspector.requireUnencrypted' in signer
assert 'NiKSigningOptions' in signer and 'NiKSigningProgress' in signer and 'NiKDylibInjector.inject' in signer
cert_store = (r/'Native/Dependencies/NiKCertificateStore.swift').read_text()
assert 'SecPKCS12Import' in cert_store and 'parseMobileProvision' in cert_store and 'kSecClassGenericPassword' in cert_store
injector = (r/'Native/Dependencies/NiKDylibInjector.swift').read_text()
assert 'lcLoadDylib' in injector and 'extractDylibsFromDeb' in injector
altsource = (r/'Native/Dependencies/NiKAltSourceView.swift').read_text()
assert 'NiKAltSourceStore' in altsource and 'NiKSourceDownloadService' in altsource
assert 'struct NiKAltSourceFeed' in (r/'Native/Models/NiKAltSourceModels.swift').read_text()
for original, replacement in json.loads((r/'server-overlays.json').read_text()).items():
    assert (r/original).is_file() and (r/replacement).is_file()
    assert original.removeprefix('Vendor/GCDWebServer/') in config

print('PASS: 8 signer components, licenses, pinned native hashes, reversible Zsign patches and server overlays.')
