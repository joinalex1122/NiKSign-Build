"""Exercise the actual C preflight used by Signer.swift against generated ZIPs."""
import ctypes, pathlib, subprocess, sys, tempfile, unittest, zipfile, struct
ROOT = pathlib.Path(__file__).resolve().parents[1]
class ZipPreflightTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory()
        cls.root = pathlib.Path(cls.temp.name)
        lib = cls.root / 'libnikzip.so'
        command = ['cc', '-dynamiclib' if sys.platform == 'darwin' else '-shared', '-fPIC',
                   '-D_LARGEFILE64_SOURCE', '-D_FILE_OFFSET_BITS=64',
                   '-I'+str(ROOT/'Vendor/minizip'), str(ROOT/'Native/Dependencies/NiKZipCheck.c'),
                   str(ROOT/'Vendor/minizip/unzip.c'), str(ROOT/'Vendor/minizip/ioapi.c'), '-lz', '-o', str(lib)]
        subprocess.run(command, check=True)
        cls.fn = ctypes.CDLL(str(lib)).NiKZipCheck
        cls.fn.argtypes = [ctypes.c_char_p, ctypes.POINTER(ctypes.c_uint64), ctypes.POINTER(ctypes.c_uint64)]
        cls.fn.restype = ctypes.c_int
    @classmethod
    def tearDownClass(cls): cls.temp.cleanup()
    def check(self, name):
        count, size = ctypes.c_uint64(), ctypes.c_uint64()
        result = self.fn(str(self.root/name).encode(), ctypes.byref(count), ctypes.byref(size))
        return result, count.value, size.value
    def test_valid_zip_and_counts(self):
        with zipfile.ZipFile(self.root/'valid.zip','w',zipfile.ZIP_DEFLATED) as z:
            z.writestr('Payload/App.app/Info.plist',b'abc')
            z.writestr('Payload/App.app/Binary',b'12345')
        self.assertEqual(self.check('valid.zip'),(0,2,8))
    def test_corrupt_and_missing(self):
        (self.root/'bad.zip').write_bytes(b'not a zip')
        self.assertLess(self.check('bad.zip')[0],0)
        self.assertLess(self.check('missing.zip')[0],0)
    def test_empty_archive_rejected(self):
        with zipfile.ZipFile(self.root/'empty.zip','w'): pass
        self.assertLess(self.check('empty.zip')[0],0)
    def test_oversized_metadata_rejected_without_expansion(self):
        path = self.root/'huge.zip'
        with zipfile.ZipFile(path,'w') as z: z.writestr('a',b'x')
        data = bytearray(path.read_bytes()); start = data.index(b'PK\x01\x02')
        struct.pack_into('<I',data,start+24,1_073_741_825)
        path.write_bytes(data)
        self.assertEqual(self.check('huge.zip')[0],-4)
    def test_many_entries_rejected(self):
        with zipfile.ZipFile(self.root/'many.zip','w') as z:
            for i in range(50001): z.writestr(str(i),b'')
        self.assertEqual(self.check('many.zip')[0],-4)
if __name__ == '__main__': unittest.main()
