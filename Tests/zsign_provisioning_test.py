"""Compile the exact native source used by the app and reproduce the old provisioning bug.
Uses an ad-hoc-signed synthetic Mach-O; does not assert Apple trust/device installation.
"""
import argparse, hashlib, json, os, pathlib, plistlib, shlex, shutil, subprocess, sys, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'Vendor/Zsign'

def run(args):
    subprocess.run(list(map(str, args)), check=True)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--macho', type=pathlib.Path, help='Existing owned Mach-O for a Linux host; never executed')
    args = parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='nik-zsign-provision-') as directory:
        tmp = pathlib.Path(directory)
        if args.macho:
            executable = args.macho.resolve()
        elif sys.platform == 'darwin':
            source = tmp / 'toy.c'; source.write_text('int main(void) { return 0; }\n')
            executable = tmp / 'toy'
            run(['xcrun', '--sdk', 'iphoneos', 'clang', '-arch', 'arm64', '-miphoneos-version-min=17.0',
                 '-fno-stack-protector', '-Wl,-e,_main', '-Wl,-adhoc_codesign', source, '-o', executable])
        else:
            parser.error('Linux requires --macho pointing to an owned fixture')
        profile = tmp / 'selected.mobileprovision'
        # Binary NULs guard against accidental C-string truncation or rewriting the source bytes.
        profile.write_bytes(b'SYNTHETIC_PROFILE\x00\xff' + bytes(range(256)) * 8)
        original = profile.read_bytes()
        compiler = shlex.split(os.environ.get('CXX', 'c++'))
        flags = ['-std=c++17', '-O1', '-Werror', '-I' + str(VENDOR/'src'), '-I' + str(VENDOR/'src/common')]
        if sys.platform == 'darwin':
            prefix = subprocess.check_output(['brew', '--prefix', 'openssl@3'], text=True).strip()
            flags += ['-I' + prefix + '/include']
            libraries = ['-L' + prefix + '/lib', '-lssl', '-lcrypto']
        else:
            flags += shlex.split(subprocess.check_output(['pkg-config', '--cflags', 'openssl'], text=True))
            libraries = shlex.split(subprocess.check_output(['pkg-config', '--libs', 'openssl'], text=True))
        sources = [VENDOR/'src'/name for name in ['archo.cpp','macho.cpp','openssl.cpp','signing.cpp']]
        sources += [VENDOR/'src/common'/name for name in ['base64.cpp','fs.cpp','json.cpp','log.cpp','sha.cpp','timer.cpp','util.cpp']]
        sources += [ROOT/'Tests/ZsignProvisioning/main.cpp']
        objects = []
        for index, source in enumerate(sources):
            obj = tmp / f'{index}.o'; run(compiler + flags + ['-c', source, '-o', obj]); objects.append(obj)
        patched = (VENDOR/'src/bundle.cpp').read_text()
        old = patched.replace('if (!bRemoveProvision) {\n\t\t\tif (!ZFile::WriteFileV(pSignAsset->m_strProvData',
                              'if (bRemoveProvision) {\n\t\t\tif (!ZFile::WriteFileV(pSignAsset->m_strProvData', 1)
        expected = json.loads((VENDOR/'UPSTREAM.json').read_text())['patch']['originalSHA256']
        assert hashlib.sha256(old.encode()).hexdigest() == expected
        for version, source in [('upstream', old), ('fixed', patched)]:
            cpp = tmp / (version + '.cpp'); cpp.write_text(source)
            obj = tmp / (version + '.o'); binary = tmp / version
            run(compiler + flags + ['-c', cpp, '-o', obj])
            run(compiler + [*objects, obj, *libraries, '-o', binary])
            for mode in ['keep', 'remove']:
                # Also show that a wildcard/mismatched profile pattern never forces a different app ID.
                for pattern in ['TEAMFIXTURE.com.example.app', 'TEAMFIXTURE.*', 'TEAMFIXTURE.com.other.app']:
                    app = tmp / f'{version}-{mode}-{pattern}.app'; app.mkdir()
                    shutil.copy2(executable, app/'Demo')
                    (app/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.example.app',
                        'CFBundleExecutable':'Demo','CFBundleName':'Fixture','CFBundleVersion':'1.0'}))
                    (app/'embedded.mobileprovision').write_bytes(b'OLD_PROFILE')
                    run([binary, app, profile, mode, pattern])
                    embedded = app/'embedded.mobileprovision'
                    present = version == 'fixed' and mode == 'keep'
                    assert embedded.exists() == present, (version, mode, pattern)
                    resources = plistlib.loads((app/'_CodeSignature/CodeResources').read_bytes())
                    if present:
                        assert embedded.read_bytes() == original
                        assert resources['files2']['embedded.mobileprovision']['hash2'] == hashlib.sha256(original).digest()
                    else:
                        assert 'embedded.mobileprovision' not in resources['files2']
                    assert plistlib.loads((app/'Info.plist').read_bytes())['CFBundleIdentifier'] == 'com.example.app'
                    assert profile.read_bytes() == original
        print('PASS: reproduced upstream loss for both flags; native fix keeps selected profile AND sealed SHA256 with false, removes it with true; exact/wildcard/mismatched IDs unchanged')
if __name__ == '__main__':
    main()
