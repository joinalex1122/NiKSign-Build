"""Real CMS with synthetic keys: verifies bytes/identity, NOT Apple trust/install.
The synthetic issuer copies a public WWDR subject solely to exercise Zsign's
issuer selector. It has no Apple private key and cannot issue Apple-trusted apps.
"""
import argparse, ast, hashlib, json, math, os, pathlib, plistlib, re, shlex, shutil, struct, subprocess, sys, tempfile
ROOT = pathlib.Path(__file__).resolve().parents[1]
VENDOR = ROOT / 'Vendor/Zsign'

def run(args, **kw):
    return subprocess.run(list(map(str, args)), check=True, **kw)

def signature(binary):
    b = binary.read_bytes(); assert b[:4] == b'\xcf\xfa\xed\xfe'
    count = struct.unpack_from('<I', b, 16)[0]; pos = 32; sig = None
    for _ in range(count):
        cmd, size = struct.unpack_from('<II', b, pos)
        if cmd == 0x1d: sig = struct.unpack_from('<I', b, pos + 8)[0]
        pos += size
    assert sig is not None
    magic, length, count = struct.unpack_from('>III', b, sig)
    assert magic == 0xfade0cc0 and sig + length <= len(b)
    blobs = {}
    for i in range(count):
        kind, off = struct.unpack_from('>II', b, sig + 12 + 8*i)
        size = struct.unpack_from('>I', b, sig + off + 4)[0]
        assert off + size <= length and kind not in blobs
        blobs[kind] = b[sig + off:sig + off + size]
    return b, blobs

def verify(app, expected_id, patched, debug, ssl, tmp):
    assert (app/'Demo').stat().st_mode & 0o111 == 0o111
    b, blobs = signature(app/'Demo')
    ent = plistlib.loads(blobs[5][8:])
    # Profile wildcard must become each binary's own concrete ID, including appex.
    assert ent['application-identifier'] == ('SEEDFIX123.' + expected_id if patched else 'SEEDFIX123.*')
    assert ent['com.apple.developer.team-identifier'] == 'TEAMFIX123'
    assert ent['keychain-access-groups'] == (['SEEDFIX123.' + expected_id, 'SEEDFIX123.shared', 'TEAMFIX123.' + expected_id] if patched else ['SEEDFIX123.*','SEEDFIX123.shared','TEAMFIX123.*'])
    assert ent['com.apple.developer.associated-domains'] == ['applinks:*.example.invalid']
    assert ent['com.apple.security.application-groups'] == ['group.example.fixture']
    assert ent['get-task-allow'] is debug
    assert 7 in blobs and len(blobs[7]) > 8 # DER and XML generated from the same adjusted dictionary.
    # CMS verifies the primary CodeDirectory with the actual embedded leaf. We
    # deliberately skip certificate chain trust: this is not an Apple identity.
    cms = tmp/'signature.der'; content = tmp/'directory.bin'
    cms.write_bytes(blobs[0x10000][8:]); content.write_bytes(blobs[0])
    run([ssl,'cms','-verify','-binary','-inform','DER','-in',cms,'-content',content,'-noverify','-out',os.devnull], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    damaged = bytearray(blobs[0]); damaged[-1] ^= 1; content.write_bytes(damaged)
    assert subprocess.run([ssl,'cms','-verify','-binary','-inform','DER','-in',cms,'-content',content,'-noverify','-out',os.devnull],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode != 0
    special = {1:(app/'Info.plist').read_bytes(),2:blobs[2],3:(app/'_CodeSignature/CodeResources').read_bytes(),5:blobs[5],7:blobs[7]}
    for kind in [k for k in blobs if k == 0 or 0x1000 <= k <= 0x1005]:
        cd = blobs[kind]; version, flags, hash_offset, ident_offset, n_special, n_code, code_limit = struct.unpack_from('>7I',cd,8)
        hash_size, hash_type, _, page = struct.unpack_from('4B',cd,36)
        digest = {1:hashlib.sha1,2:hashlib.sha256}[hash_type]
        assert cd[ident_offset:].split(b'\0')[0].decode() == expected_id
        assert n_code == math.ceil(code_limit / (1 << page))
        assert not flags & 2 # No ad-hoc signature in a CMS test.
        for i in range(n_code):
            actual = digest(b[i*(1<<page):min((i+1)*(1<<page),code_limit)]).digest()[:hash_size]
            assert cd[hash_offset+i*hash_size:hash_offset+(i+1)*hash_size] == actual
        for slot, raw in special.items():
            assert slot <= n_special
            assert cd[hash_offset-slot*hash_size:hash_offset-(slot-1)*hash_size] == digest(raw).digest()[:hash_size]
        if version >= 0x20400:
            exec_flags = struct.unpack_from('>Q',cd,80)[0]
            assert exec_flags & 1
            assert bool(exec_flags & 0x10) == (debug if patched else True)
    resources = plistlib.loads((app/'_CodeSignature/CodeResources').read_bytes())
    assert resources['files2']['embedded.mobileprovision']['hash2'] == hashlib.sha256((app/'embedded.mobileprovision').read_bytes()).digest()

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--macho',type=pathlib.Path);args=parser.parse_args()
    with tempfile.TemporaryDirectory(prefix='nik-cms-') as directory:
        tmp=pathlib.Path(directory)
        ssl='openssl'; compiler=shlex.split(os.environ.get('CXX','c++'))
        flags=['-std=c++17','-O1','-Werror','-I'+str(VENDOR/'src'),'-I'+str(VENDOR/'src/common')]
        if sys.platform=='darwin':
            prefix=subprocess.check_output(['brew','--prefix','openssl@3'],text=True).strip();ssl=prefix+'/bin/openssl'
            flags+=['-I'+prefix+'/include'];libs=['-L'+prefix+'/lib','-lssl','-lcrypto']
        else:
            flags+=shlex.split(subprocess.check_output(['pkg-config','--cflags','openssl'],text=True));libs=shlex.split(subprocess.check_output(['pkg-config','--libs','openssl'],text=True))
        if args.macho: executable=args.macho.resolve()
        elif sys.platform=='darwin':
            c=tmp/'toy.c';c.write_text('int main(void){return 0;}\n');executable=tmp/'toy'
            run(['xcrun','--sdk','iphoneos','clang','-arch','arm64','-miphoneos-version-min=17.0','-fno-stack-protector','-Wl,-e,_main','-Wl,-adhoc_codesign',c,'-o',executable])
        else: parser.error('Linux requires an owned --macho fixture')
        text=(VENDOR/'src/openssl.cpp').read_text();section=text.split('const char* ZSignAsset::s_szAppleDevCACertG3 =',1)[1].split(';',1)[0]
        pem=''.join(ast.literal_eval(x) for x in re.findall(r'"(?:[^"\\]|\\.)*"',section));(tmp/'wwdr.pem').write_text(pem)
        subject=subprocess.check_output([ssl,'x509','-in',str(tmp/'wwdr.pem'),'-noout','-subject','-nameopt','compat'],text=True).strip().split('=',1)[1].strip()
        # No Apple secret is used. This CA has a fresh throwaway private key.
        run([ssl,'req','-x509','-newkey','rsa:2048','-noenc','-keyout',tmp/'ca.key','-out',tmp/'ca.pem','-days','2','-subj',subject],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        run([ssl,'req','-new','-newkey','rsa:2048','-noenc','-keyout',tmp/'leaf.key','-out',tmp/'leaf.csr','-subj','/CN=NiKSign Synthetic CMS/OU=TEAMFIX123'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        run([ssl,'x509','-req','-in',tmp/'leaf.csr','-CA',tmp/'ca.pem','-CAkey',tmp/'ca.key','-CAcreateserial','-out',tmp/'leaf.pem','-days','1'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        run([ssl,'pkcs12','-export','-in',tmp/'leaf.pem','-inkey',tmp/'leaf.key','-out',tmp/'key.p12','-passout','pass:fixture password'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        sources=[VENDOR/'src'/n for n in ['bundle.cpp','macho.cpp','openssl.cpp','signing.cpp']]+[VENDOR/'src/common'/n for n in ['base64.cpp','fs.cpp','json.cpp','log.cpp','sha.cpp','timer.cpp','util.cpp']]+[ROOT/'Tests/ZsignCMS/main.cpp']
        objects=[]
        for i,src in enumerate(sources):
            obj=tmp/f'{i}.o';run(compiler+flags+['-c',src,'-o',obj]);objects.append(obj)
        current=(VENDOR/'src/archo.cpp').read_text();provenance=json.loads((VENDOR/'UPSTREAM.json').read_text());patch=provenance['entitlementsPatch'];old=current
        for rep in reversed(provenance['installabilityPatch']['files']['src/archo.cpp']['replacements']): old=old.replace(rep['after'],rep['before'],1)
        for rep in patch['replacements']: old=old.replace(rep['after'],rep['before'],1)
        assert hashlib.sha256(old.encode()).hexdigest()==patch['originalSHA256']
        for label,code in [('before',old),('fixed',current)]:
            src=tmp/f'{label}.cpp';src.write_text(code);obj=tmp/f'{label}.o';binary=tmp/label
            run(compiler+flags+['-c',src,'-o',obj]);run(compiler+[*objects,obj,*libs,'-o',binary])
            for debug in [False,True]:
                ent={'application-identifier':'SEEDFIX123.*','com.apple.developer.team-identifier':'TEAMFIX123','keychain-access-groups':['SEEDFIX123.*','SEEDFIX123.shared','TEAMFIX123.*'],'get-task-allow':debug,'com.apple.developer.associated-domains':['applinks:*.example.invalid'],'com.apple.security.application-groups':['group.example.fixture']}
                profile={'TeamIdentifier':['TEAMFIX123'],'Entitlements':ent}
                (tmp/'profile.plist').write_bytes(plistlib.dumps(profile))
                run([ssl,'cms','-sign','-binary','-nodetach','-in',tmp/'profile.plist','-signer',tmp/'leaf.pem','-inkey',tmp/'leaf.key','-outform','DER','-out',tmp/'profile.mobileprovision'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                app=tmp/f'{label}-{debug}.app';ext=app/'PlugIns/Demo.appex';ext.mkdir(parents=True)
                for folder,bid in [(app,'com.example.fixture'),(ext,'com.example.fixture.extension')]:
                    shutil.copy2(tmp/'profile.mobileprovision',folder/'embedded.mobileprovision')
                    shutil.copy2(executable,folder/'Demo');(folder/'Demo').chmod(0o755);(folder/'Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable':'Demo','CFBundleIdentifier':bid,'CFBundleVersion':'1','CFBundleName':'Fixture'}))
                (app/'resource.o').write_bytes(struct.pack('<8I',0xfeedfacf,0x100000c,0,1,0,0,0,0))
                framework=app/'Frameworks/Fixture.framework';version=framework/'Versions/A';(version/'Resources').mkdir(parents=True)
                lib=bytearray(executable.read_bytes());struct.pack_into('<I',lib,12,6) # Synthetic MH_DYLIB fixture; never executed.
                (version/'Fixture').write_bytes(lib);(version/'Fixture').chmod(0o755)
                (version/'Resources/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.example.library','CFBundleExecutable':'Fixture','CFBundleVersion':'1'}))
                (framework/'Versions/Current').symlink_to('A');(framework/'Fixture').symlink_to('Versions/Current/Fixture')
                (framework/'Resources').symlink_to('Versions/Current/Resources');(framework/'Info.plist').symlink_to('Resources/Info.plist')
                run([binary,app,tmp/'key.p12',tmp/'profile.mobileprovision'])
                verify(app,'com.example.fixture',label=='fixed',debug,ssl,tmp)
                verify(ext,'com.example.fixture.extension',label=='fixed',debug,ssl,tmp)
                assert (framework/'Fixture').is_symlink() and (version/'Fixture').stat().st_mode & 0o111 == 0o111
                _,library_blobs=signature(version/'Fixture')
                assert 5 not in library_blobs or plistlib.loads(library_blobs[5][8:]) == {} # No application entitlements on libraries.
                (tmp/'library.der').write_bytes(library_blobs[0x10000][8:]);(tmp/'library.cd').write_bytes(library_blobs[0])
                run([ssl,'cms','-verify','-binary','-inform','DER','-in',tmp/'library.der','-content',tmp/'library.cd','-noverify','-out',os.devnull],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
                for bundle in [app,ext,framework]:
                    resources=plistlib.loads((bundle/'_CodeSignature/CodeResources').read_bytes())
                    for name,record in resources['files2'].items():
                        file=bundle/name
                        if 'symlink' in record: assert file.is_symlink() and os.readlink(file)==record['symlink']
                        elif 'hash2' in record: assert hashlib.sha256(file.read_bytes()).digest()==record['hash2'],(bundle,name)
                if label=='fixed':
                    (app/'broken.dylib').write_bytes(bytes.fromhex('cffaedfe')+bytes(28))
                    assert subprocess.run([binary,app,tmp/'key.p12',tmp/'profile.mobileprovision'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL).returncode == 4
                    (app/'broken.dylib').unlink()

        print('PASS: real detached CMS/page/special-slot hashes and tamper rejection; before/after wildcard identity, per-extension IDs and actual get-task-allow flags; execute permissions, nested framework CMS and resource/symlink seals, nested failure propagation; synthetic trust only')
if __name__=='__main__':main()
