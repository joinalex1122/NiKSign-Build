"""Validate the packaged NiKSign app with bounded reads, including ZIP CRCs."""
import argparse
import os
from pathlib import PurePosixPath
import plistlib
import struct
import zipfile


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def verify_ipa(path: str, expected_bundle_id: str) -> None:
    with zipfile.ZipFile(path) as archive:
        entries = archive.infolist()
        names = {entry.filename for entry in entries}
        require(len(names) == len(entries), 'Duplicate ZIP entry paths')
        require(len(entries) <= 50_000, 'Too many ZIP entries')
        require(sum(e.file_size for e in entries) <= 1_073_741_824, 'IPA exceeds 1 GB expanded')
        for name in names:
            require(not name.startswith('/') and '\\' not in name and
                    '..' not in name.split('/'), 'Unsafe ZIP entry path')
        root = 'Payload/NiKSign.app/'
        metadata = archive.getinfo(root + 'Info.plist')
        require(metadata.file_size <= 1_048_576, 'Info.plist exceeds 1 MB')
        with archive.open(metadata) as stream:
            info = plistlib.loads(stream.read(1_048_577))
        require(isinstance(info, dict), 'Invalid Info.plist root')
        require(info.get('CFBundleIdentifier') == expected_bundle_id,
                f'Expected Bundle ID {expected_bundle_id}')
        schemes = {scheme for item in info.get('CFBundleURLTypes', [])
                   for scheme in item.get('CFBundleURLSchemes', [])}
        require(schemes == {'niksign'}, 'Unexpected or missing URL schemes')
        exe = info.get('CFBundleExecutable')
        require(isinstance(exe, str) and bool(exe) and '/' not in exe and
                '\\' not in exe and exe not in ('.', '..'), 'Invalid executable name')
        executable = archive.getinfo(root + exe)
        with archive.open(executable) as stream:
            header = stream.read(32)  # Do not load the whole Mach-O into memory.
        require(len(header) == 32 and header[:4] == b'\xcf\xfa\xed\xfe',
                'Expected thin 64-bit Mach-O')
        _, cpu, _, file_type, ncmds, sizeofcmds, _, _ = struct.unpack('<8I', header)
        require(cpu == 0x100000c and file_type == 2, 'Expected arm64 MH_EXECUTE')
        require(ncmds > 0 and sizeofcmds >= ncmds * 8 and
                32 + sizeofcmds <= executable.file_size, 'Invalid Mach-O command bounds')
        require(not any(PurePosixPath(n).name == 'entitlements.plist' for n in names),
                'Unexpected entitlements.plist packaged in IPA')
        # testzip streams each member in chunks and checks CRC without retaining binaries.
        corrupt = archive.testzip()
        require(corrupt is None, f'Corrupt ZIP member: {corrupt}')


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('ipa')
    args = parser.parse_args()
    bundle_id = os.environ.get('NIKSIGN_EXPECTED_BUNDLE_ID', 'com.niksign.app')
    try:
        verify_ipa(args.ipa, bundle_id)
    except (ValueError, KeyError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        parser.exit(1, f'IPA validation failed: {error}\n')
    print(f'Verified arm64 executable, ZIP CRCs, Bundle ID ({bundle_id}) and signer URL scheme. IPA remains unsigned.')


if __name__ == '__main__':
    main()
