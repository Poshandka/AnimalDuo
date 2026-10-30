"""Folder selection must configure independently of modal dismissal."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

REPO=Path(__file__).resolve().parents[3]

@unittest.skipUnless(shutil.which('xcrun'),'Apple Swift toolchain required')
class CloudSaveTests(unittest.TestCase):
    def test_selection_lifecycle(self):
        with tempfile.TemporaryDirectory() as folder:
            obj,exe=Path(folder)/'stub.o',Path(folder)/'check'
            subprocess.run(['xcrun','clang','-fobjc-arc','-c',str(REPO/'dm/ios/tests/cloud_save_stub.m'),'-o',str(obj)],check=True,capture_output=True)
            result=subprocess.run(['xcrun','swiftc','-swift-version','5','-parse-as-library','-import-objc-header',str(REPO/'dm/ios/tests/cloud_save_stub.h'),str(REPO/'dm/ios/Sources/CloudSaves.swift'),str(REPO/'dm/ios/tests/cloud_save_check.swift'),str(obj),'-o',str(exe),'-framework','SwiftUI','-framework','AppKit'],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            result=subprocess.run([str(exe)],capture_output=True,text=True)
            self.assertEqual(result.returncode,0,result.stdout+result.stderr)
            self.assertIn('cloud model: result delivery without dismissal',result.stdout)

if __name__=='__main__':unittest.main()
