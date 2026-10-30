from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO=Path(__file__).resolve().parents[3]

@unittest.skipUnless(shutil.which('xcrun'),'Apple toolchain required')
class ComfortTests(unittest.TestCase):
    def test_touch_profiles(self):
        with tempfile.TemporaryDirectory() as folder:
            exe=Path(folder)/'touch-check'
            r=subprocess.run(['xcrun','swiftc','-parse-as-library',str(REPO/'dm/ios/Sources/TouchControls.swift'),str(REPO/'dm/ios/tests/touch_controls_check.swift'),'-o',str(exe),'-framework','SwiftUI'],capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            r=subprocess.run([str(exe)],capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
    def test_actual_frame_recorder(self):
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);exe=root/'perf-check'
            r=subprocess.run(['xcrun','clang','-fobjc-arc',str(REPO/'dm/host/tests/t_performance_apple.m'),'-o',str(exe),'-framework','Foundation'],capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            for mode in ['on','off']:
                target=root/mode;target.mkdir()
                r=subprocess.run([str(exe),str(target),mode],capture_output=True,text=True)
                self.assertEqual(r.returncode,0,r.stdout+r.stderr)

if __name__=='__main__':unittest.main()
