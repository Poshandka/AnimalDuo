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
            for mode in ['on','off','missing','blocked']:
                target=root/mode;target.mkdir()
                r=subprocess.run([str(exe),str(target),mode],capture_output=True,text=True)
                self.assertEqual(r.returncode,0,r.stdout+r.stderr)
                if mode in ['missing','blocked']:self.assertIn('[RED] performance:',r.stderr)

    def test_ios_boot_initializes_performance_directory(self):
        import platform
        with tempfile.TemporaryDirectory() as folder:
            root=Path(folder);exe=root/'ios-boot-check'
            (root/'game_profile.h').write_text('#define DM_GAME_ROMFS_MARKER "fixture.marker"\n')
            sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()
            support=Path(sdk)/'System/iOSSupport'
            r=subprocess.run(['xcrun','clang','-target',platform.machine()+'-apple-ios26.0-macabi','-isysroot',sdk,'-F',str(support/'System/Library/Frameworks'),'-isystem',str(support/'usr/include'),'-I',str(root),'-I',str(REPO/'dm/host'),'-fobjc-arc',str(REPO/'dm/ios/tests/performance_boot_check.m'),'-o',str(exe),'-framework','UIKit','-framework','Foundation'],capture_output=True,text=True)
            self.assertEqual(r.returncode,0,r.stdout+r.stderr)
            for mode in ['on','off','override']:
                target=root/mode;target.mkdir()
                r=subprocess.run([str(exe),str(target),mode],capture_output=True,text=True)
                log=target/'Documents/log.txt'
                self.assertEqual(r.returncode,0,r.stdout+r.stderr+(log.read_text() if log.exists() else ''))

if __name__=='__main__':unittest.main()
