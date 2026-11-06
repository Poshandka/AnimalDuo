"""Verify the dialogue overlay's binary formats without any game assets."""
import importlib.util
from pathlib import Path
import shutil
import struct
import sys
import tempfile
import unittest
import zlib

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(ROOT/'scripts'))
SPEC = importlib.util.spec_from_file_location('starter_dialogue', ROOT/'scripts/build_acnh_starter_dialogue.py')
assert SPEC is not None and SPEC.loader is not None
MOD = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MOD)


def message(entries):
    header = bytearray(32)
    header[:10] = b'MsgStdBn\xff\xfe'
    header[12:14] = b'\x01\x03'
    struct.pack_into('<H', header, 14, 3)
    return MOD.write_msbt(entries, bytes(header), 5)


def line(text, attribute=0):
    return ((text+'\0').encode('utf-16-le'), bytes([attribute])*8)


class DialogueFormatTests(unittest.TestCase):
    def test_sarc_named_member_lookup_and_alignment(self):
        files = {'a/b.msbt': b'one', 'same/prefix.msbt': bytes(range(256)), 'empty': b''}
        raw = MOD.write_sarc(files, 0x65)
        self.assertEqual(MOD.read_sarc(raw), (files, 0x65))
        # Independently walk the SFAT, as a consumer rather than the writer does.
        start = struct.unpack_from('<I', raw, 12)[0]
        count = struct.unpack_from('<H', raw, 26)[0]
        hashes = []
        for i in range(count):
            hashed, _, begin, end = struct.unpack_from('<IIII', raw, 32+i*16)
            hashes.append(hashed)
            self.assertEqual((start+begin)%16, 0)
            self.assertLessEqual(start+end, len(raw))
        self.assertEqual(hashes, sorted(hashes))
        broken = bytearray(raw)
        broken[32] ^= 1
        with self.assertRaises(ValueError):
            MOD.read_sarc(broken)

    def test_msbt_preserves_utf16_control_bytes_attributes_and_labels(self):
        # A page-control payload may contain zero words and is still nonempty.
        control = b'\x0e\x00\x01\x00\x02\x00\x02\x00\x00\x00'+'\u6d4b\u8bd5\0'.encode('utf-16-le')
        entries = {'001': line('existing', 7), '002': (control, bytes(range(8))), '004': line(''), 'extra': line('more', 3)}
        result, header, groups = MOD.read_msbt(message(entries))
        self.assertEqual(result, entries)
        self.assertEqual(MOD.read_msbt(MOD.write_msbt(result, header, groups))[0], entries)
        self.assertTrue(any(result['002'][0]))
        self.assertFalse(any(result['004'][0]))

    def test_bdli_relative_offsets_keep_cues_bound_to_label_crc(self):
        entries = {zlib.crc32(b'001'): bytes(range(20)), zlib.crc32(b'002'): bytes(range(40)), zlib.crc32(b'003'): b''}
        raw = MOD.write_bdli(entries)
        self.assertEqual(MOD.read_bdli(raw), entries)
        for i, (expected_hash, expected_data) in enumerate(entries.items()):
            tag, count, offset, hashed = struct.unpack_from('<4sIII', raw, 20+i*16)
            self.assertEqual((tag, hashed, count), (b'LBLI', expected_hash, len(expected_data)//20))
            at = 20+i*16+offset
            self.assertEqual(raw[at:at+count*20], expected_data)

    def test_compressed_resources_declare_their_uncompressed_size(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)/'asset.zs'
            expected = b'bounded resource frame'*1024
            path.write_bytes(MOD.compress(expected))
            self.assertEqual(MOD.decompress(path), expected)

    def test_overlay_fills_only_absent_text_and_matching_cues(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            romfs, output = root/'RomFS', root/'overlay'
            archive = romfs/'Message/TalkNNpc_CNzh.sarc.zs'
            archive.parent.mkdir(parents=True)
            files, originals = {'unrelated.bin': b'opaque payload'}, {}
            for category, family in MOD.FAMILIES:
                for personality in MOD.PERSONALITIES:
                    prefix = personality[3:].upper()
                    name = f'{personality}/{category}/{prefix}_{family}.msbt'
                    if personality=='B2_Ha':
                        entries = {'001': line('male starter'), '002': line('male second')}
                    elif personality=='G4_An':
                        entries = {'001': line('female starter'), '003': line('female second')}
                    else:
                        entries = {'001': line('keep exactly', 9), '002': line(''), '009': line('regular dialogue', 5)}
                    if personality=='B4_Zk' and family=='React_1P_LifeStart':
                        continue # A genuinely missing MSBT and BDLI member.
                    files[name] = message(entries)
                    cues = {zlib.crc32(key.encode()): bytes([i+1])*20 for i, key in enumerate(entries)}
                    path = romfs/f'BDLI/TalkNNpc/CNzh/{prefix}_{family}.bdli.zs'
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_bytes(MOD.compress(MOD.write_bdli(cues)))
                    originals[name] = (entries, cues)
            archive.write_bytes(MOD.compress(MOD.write_sarc(files, 0x65)))
            before = archive.read_bytes()
            report = MOD.repair_locale(romfs, archive, output)
            self.assertEqual(archive.read_bytes(), before)
            self.assertEqual(len(report['changed_files']), 30)
            result = MOD.read_sarc(MOD.decompress(output/archive.relative_to(romfs)))[0]
            self.assertEqual(result['unrelated.bin'], files['unrelated.bin'])
            for name, raw in result.items():
                if not name.endswith('.msbt'):
                    continue
                entries = MOD.read_msbt(raw)[0]
                if name.startswith(('B2_Ha/', 'G4_An/')):
                    self.assertEqual(raw, files[name])
                    continue
                self.assertTrue(all(any(value[0]) for value in entries.values()))
                if name in originals:
                    for key, value in originals[name][0].items():
                        if any(value[0]):
                            self.assertEqual(entries[key], value)
                prefix_file = Path(name).name.removesuffix('.msbt')
                cues = MOD.read_bdli(MOD.decompress(output/f'BDLI/TalkNNpc/CNzh/{prefix_file}.bdli.zs'))
                for key in entries:
                    self.assertIn(zlib.crc32(key.encode()), cues)
                if name in originals:
                    for key, value in originals[name][0].items():
                        if any(value[0]):
                            hashed = zlib.crc32(key.encode())
                            self.assertEqual(cues[hashed], originals[name][1][hashed])
            merged = root/'merged'
            shutil.copytree(romfs, merged)
            shutil.copytree(output, merged, dirs_exist_ok=True)
            again = root/'again'
            repeated = MOD.repair_locale(merged, merged/archive.relative_to(romfs), again)
            self.assertEqual(repeated['filled_labels'], 0)
            self.assertEqual((again/archive.relative_to(romfs)).read_bytes(), (output/archive.relative_to(romfs)).read_bytes())


if __name__ == '__main__':
    unittest.main()
