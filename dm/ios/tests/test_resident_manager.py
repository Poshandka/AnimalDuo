"""Verify resident document/backup publication through the real SwiftUI model."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]
TESTS = Path(__file__).resolve().parent
SOURCES = REPO / 'dm/ios/Sources'


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun'),
                     'needs CommonCrypto, SwiftUI and the Swift toolchain')
class ResidentManagerTests(unittest.TestCase):
    def test_document_and_backup_snapshots(self):
        with tempfile.TemporaryDirectory() as path:
            tmp = Path(path)
            for name, files in [
                ('prepare', [SOURCES/'ACNHResidents.swift', TESTS/'resident_save_check.swift']),
                ('model', [SOURCES/'ACNHResidents.swift', SOURCES/'ResidentManager.swift',
                           TESTS/'resident_manager_check.swift']),
            ]:
                result = subprocess.run(
                    ['xcrun', '-sdk', 'macosx', 'swiftc', '-O', '-swift-version', '5',
                     '-parse-as-library', *map(str, files), '-o', str(tmp/name)],
                    capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            result = subprocess.run([str(tmp/'prepare'), str(tmp/'fixture'), '--prepare-only'],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            result = subprocess.run([str(tmp/'model'), str(tmp/'fixture')],
                                    capture_output=True, text=True, timeout=120)
            self.assertEqual(result.returncode, 0, result.stdout+result.stderr)
            self.assertIn('0 failed', result.stdout)


if __name__ == '__main__':
    unittest.main()
