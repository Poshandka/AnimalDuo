"""Verify the real resident editor's transactions and format guards on macOS."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]

@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun'), 'needs CommonCrypto and the Swift toolchain')
class ResidentSaveTests(unittest.TestCase):
    def test_save_transactions(self):
        with tempfile.TemporaryDirectory() as path:
            tmp = Path(path)
            exe = tmp / 'resident-check'
            r = subprocess.run(['xcrun', '-sdk', 'macosx', 'swiftc', '-O', '-swift-version', '5', '-parse-as-library',
                                str(REPO/'dm/ios/Sources/ACNHResidents.swift'), str(Path(__file__).with_name('resident_save_check.swift')),
                                '-o', str(exe)], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stdout+r.stderr)
            r = subprocess.run([str(exe), str(tmp/'fixture')], capture_output=True, text=True)
            self.assertEqual(r.returncode, 0, r.stdout+r.stderr)
            self.assertIn('0 failed', r.stdout)

if __name__ == '__main__':
    unittest.main()
