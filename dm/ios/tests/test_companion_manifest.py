from pathlib import Path
import importlib.util
import unittest

BASE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('gen_companion', BASE/'tools/gen_companion.py')
gen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(gen)

class CompanionManifestTests(unittest.TestCase):
    def test_original_pages_and_authored_localizations(self):
        root = gen.generate(BASE.parent/'third_party/eden_duo/acnh')
        self.assertEqual((root['canvas_w'], root['canvas_h']), (1240, 1080))
        self.assertTrue({'map', 'bag', 'critters', 'diy', 'today', 'phone'} <= {p['id'] for p in root['pages']})
        self.assertEqual(len(root['apple_flavor']), 14)
        self.assertEqual(root['apple_flavor']['CNzh']['card.1.t'], '\u65e9\u95f4\u5e7f\u64ad\u8fdb\u884c\u4e2d')
        self.assertTrue(all(len(v) == 60 for v in root['apple_flavor'].values()))
    def test_truncated_flavor_is_rejected(self):
        path = BASE.parent/'third_party/eden_duo/acnh/flavor/USen.msbt'
        with self.assertRaises(ValueError):
            gen.msbt(path.read_bytes()[:-40])
        with self.assertRaises(ValueError):
            gen.msbt(b'not a manifest')
