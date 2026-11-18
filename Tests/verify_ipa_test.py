"""Exercise the actual IPA validator, including optimized Python and bounded reads."""
import importlib.util
from pathlib import Path
import plistlib
import struct
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

SCRIPT = Path(__file__).resolve().parents[1] / 'scripts/verify-ipa.py'
spec = importlib.util.spec_from_file_location('verify_ipa', SCRIPT)
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)
BUNDLE = 'com.niksign.app'
ROOT = 'Payload/NiKSign.app/'


class IPAValidationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.ipa = Path(self.temp.name) / 'app.ipa'

    def make_ipa(self, cpu=0x100000c, duplicate=False, binary_bytes=4096):
        info = {'CFBundleIdentifier': BUNDLE, 'CFBundleExecutable': 'NiKSign',
                'CFBundleURLTypes': [{'CFBundleURLSchemes': ['niksign', 'threeoneosfive']}]}
        header = struct.pack('<8I', 0xfeedfacf, cpu, 0, 2, 1, 8, 0, 0)
        with zipfile.ZipFile(self.ipa, 'w', zipfile.ZIP_DEFLATED) as archive:
            archive.writestr(ROOT + 'Info.plist', plistlib.dumps(info))
            archive.writestr(ROOT + 'NiKSign', header + bytes(binary_bytes))
            for language in ['en', 'vi', 'zh-Hans']:
                archive.writestr(ROOT + language + '.lproj/Localizable.strings', '"ok" = "ok";')
            if duplicate:
                with warnings.catch_warnings():
                    warnings.simplefilter('ignore', UserWarning)
                    archive.writestr(ROOT + 'NiKSign', header)

    def test_valid_ipa(self):
        self.make_ipa()
        validator.verify_ipa(self.ipa, BUNDLE)

    def test_wrong_architecture(self):
        self.make_ipa(cpu=7)
        with self.assertRaisesRegex(ValueError, 'arm64'):
            validator.verify_ipa(self.ipa, BUNDLE)

    def test_duplicate_entries(self):
        self.make_ipa(duplicate=True)
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            validator.verify_ipa(self.ipa, BUNDLE)

    def test_checks_survive_python_optimization(self):
        self.make_ipa(cpu=7)
        result = subprocess.run([sys.executable, '-O', str(SCRIPT), str(self.ipa)], capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(b'arm64', result.stderr)

    def test_large_binary_read_is_bounded(self):
        self.make_ipa(binary_bytes=16 * 1024 * 1024)
        original = zipfile.ZipExtFile.read
        reads = []
        def bounded_read(stream, n=-1):
            reads.append(n)
            self.assertGreaterEqual(n, 0, 'Unbounded ZIP read')
            self.assertLessEqual(n, 1_048_577)
            return original(stream, n)
        with patch.object(zipfile.ZipExtFile, 'read', bounded_read):
            validator.verify_ipa(self.ipa, BUNDLE)
        self.assertIn(32, reads)

    def test_truncated_archive(self):
        self.make_ipa()
        self.ipa.write_bytes(self.ipa.read_bytes()[:-22])
        with self.assertRaises(zipfile.BadZipFile):
            validator.verify_ipa(self.ipa, BUNDLE)

    def test_wrong_bundle_id(self):
        self.make_ipa()
        with self.assertRaisesRegex(ValueError, 'Bundle ID'):
            validator.verify_ipa(self.ipa, 'app.wrong')


if __name__ == '__main__':
    unittest.main()
