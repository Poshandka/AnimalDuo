"""Check the real finite diagnostic pattern without controller hardware."""
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[3]


@unittest.skipUnless(sys.platform == 'darwin' and shutil.which('xcrun'), 'requires Apple haptics frameworks')
class ControllerHapticsTests(unittest.TestCase):
    def test_finite_hardware_probe(self):
        with tempfile.TemporaryDirectory() as path:
            binary = str(Path(path) / 'controller-haptics-check')
            result = subprocess.run([
                'xcrun', '-sdk', 'macosx', 'swiftc', '-O', '-swift-version', '5', '-parse-as-library',
                str(REPO / 'dm/ios/Sources/ControllerHapticsTest.swift'),
                str(Path(__file__).with_name('controller_haptics_check.swift')), '-o', binary,
            ], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            result = subprocess.run([binary], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS', result.stdout)


if __name__ == '__main__':
    unittest.main()
