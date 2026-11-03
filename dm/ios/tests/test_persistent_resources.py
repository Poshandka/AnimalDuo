"""Persistent resource lifecycle uses owned fixture bytes, never player assets."""
import importlib.util
from pathlib import Path
import shutil
import subprocess
import platform
import plistlib
import re
import tempfile
import unittest
import zipfile

REPO=Path(__file__).resolve().parents[3]
spec=importlib.util.spec_from_file_location('persistent_resource_index',REPO/'dm/ios/tools/persistent_resources.py')
resources=importlib.util.module_from_spec(spec);spec.loader.exec_module(resources)

def fixture(path,chain='fixture'):
    with zipfile.ZipFile(path,'w',zipfile.ZIP_DEFLATED)as z:
        for name in ['romfs/System/marker','romfs/Model/a.bin','msl/b-'+chain+'/a.metallib','aoc/0/marker','dm/font/standard.ttf']:
            z.writestr(resources.PREFIX+name,(name+'\n').encode()*300)
        z.writestr(resources.PREFIX+'romfs/Empty/',b'')

class PersistentResourceTests(unittest.TestCase):
    def test_deterministic_index_and_small_descriptor(self):
        with tempfile.TemporaryDirectory()as d:
            p=Path(d);ipa=p/'full.ipa';fixture(ipa)
            a=resources.index_ipa(ipa,p/'index','01006F8002326000','3.0.3','fixture','System/marker')
            b=resources.index_ipa(ipa,p/'again','01006F8002326000','3.0.3','fixture','System/marker')
            self.assertEqual(a,b);self.assertEqual(a['files'],5);self.assertLess((p/'index/resource-set.plist').stat().st_size,4096)
            self.assertEqual((p/'index/resource-files.plist').read_bytes(),(p/'again/resource-files.plist').read_bytes())

    def test_rejects_unsafe_or_duplicate_resource_paths(self):
        with tempfile.TemporaryDirectory()as d:
            p=Path(d)
            for name in ['romfs/../save/main.dat','romfs//file','romfs/./file']:
                ipa=p/'bad.ipa'
                with zipfile.ZipFile(ipa,'w')as z:z.writestr(resources.PREFIX+name,b'toy')
                with self.assertRaises(ValueError):resources.index_ipa(ipa,p/'out','01006F8002326000','3.0.3','fixture','System/marker')

    @unittest.skipUnless(shutil.which('xcrun'),'Apple Foundation required')
    def test_real_install_pause_and_bundle_replacement(self):
        with tempfile.TemporaryDirectory()as d:
            p=Path(d);ipa=p/'full.ipa';fixture(ipa);full=p/'full';thin=p/'thin'
            with zipfile.ZipFile(ipa)as z:z.extractall(full)
            full=full/'Payload/DmIOS.app';index=full/'dm';index.mkdir(exist_ok=True)
            resources.index_ipa(ipa,index,'01006F8002326000','3.0.3','fixture','System/marker')
            (thin/'dm').mkdir(parents=True);shutil.copy2(index/'resource-set.plist',thin/'dm/resource-set.plist')
            exe=p/'resource-check';cmd=['xcrun','clang','-fobjc-arc','-Wno-deprecated-declarations','-Wno-incompatible-pointer-types','-Wno-nullability-completeness',str(REPO/'dm/ios/tests/resource_store_check.m'),'-framework','Foundation','-o',str(exe)]
            v=subprocess.run(cmd,capture_output=True,text=True);self.assertEqual(v.returncode,0,v.stdout+v.stderr)
            v=subprocess.run([str(exe),str(full),str(thin),str(p/'Application Support')],capture_output=True,text=True);self.assertEqual(v.returncode,0,v.stdout+v.stderr);self.assertIn('small update reuse',v.stdout)

    @unittest.skipUnless(shutil.which('xcrun'),'Apple UIKit required')
    def test_production_startup_after_thin_replacement(self):
        with tempfile.TemporaryDirectory()as d:
            p=Path(d);chain=re.search(r'#define DMSH_CHAIN "([^"]+)"',(REPO/'dm/gfx/nvn/dmsh_chain.h').read_text())[1]
            ipa=p/'full.ipa';fixture(ipa,chain)
            with zipfile.ZipFile(ipa)as z:z.extractall(p/'unpacked')
            full=p/'unpacked/Payload/DmIOS.app';thin=p/'Thin.app';(thin/'dm').mkdir(parents=True)
            resources.index_ipa(ipa,full/'dm','01006F8002326000','3.0.3',chain,'System/marker')
            shutil.copy2(full/'dm/resource-set.plist',thin/'dm/resource-set.plist')
            for bundle in [full,thin]:(bundle/'Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.nxnative.validation.owned-resources','CFBundleShortVersionString':'3.0.3'}))
            (p/'game_profile.h').write_text('#define DM_GAME_PROGRAM_ID 0x01006F8002326000ull\n#define DM_GAME_ROMFS_MARKER "System/marker"\n')
            sdk=subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip();support=Path(sdk)/'System/iOSSupport';exe=p/'boot-check'
            cmd=['xcrun','clang','-target',platform.machine()+'-apple-ios26.0-macabi','-isysroot',sdk,'-F',str(support/'System/Library/Frameworks'),'-isystem',str(support/'usr/include'),'-I',str(p),'-I',str(REPO/'dm/host'),'-fobjc-arc','-Wno-deprecated-declarations',str(REPO/'dm/ios/tests/resource_boot_check.m'),'-o',str(exe),'-framework','UIKit','-framework','Foundation']
            v=subprocess.run(cmd,capture_output=True,text=True);self.assertEqual(v.returncode,0,v.stdout+v.stderr)
            v=subprocess.run([str(exe),str(full),str(thin),str(p/'device')],capture_output=True,text=True)
            log=p/'device/Documents/log.txt';self.assertEqual(v.returncode,0,v.stdout+v.stderr+(log.read_text()if log.exists()else''));self.assertIn('cold thin replacement',v.stdout)

if __name__=='__main__':unittest.main()
