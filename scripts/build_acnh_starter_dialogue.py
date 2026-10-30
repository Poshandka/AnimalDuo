#!/usr/bin/env python3
"""Build an ACNH 3.0.3 starter-dialogue overlay from the user's own RomFS.

Identity edits can give the original settlers any personality. Six personalities
have no tent/early-story text. Reuse the original gender-matched starter messages
and their synchronized BDLI cues only where text is empty or missing. Keep save
origins intact: they also control house construction. No game data is included.
"""
import argparse
import ctypes
import ctypes.util
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import zlib

from build_acnh_resident_catalog import decompress

PERSONALITIES = ('B1_Bo', 'B2_Ha', 'B3_Ko', 'B4_Zk', 'G1_Fu', 'G2_Ge', 'G3_Ot', 'G4_An')
FAMILIES = (('Free', 'FreeA_FirstTent'), ('Free', 'FreeH_LifeStart_Hint'),
            ('Free', 'FreeH_Transition'), ('Free', 'FreeH_Progress'), ('React', 'React_1P_LifeStart'))
LOCALES = {'CNzh', 'EUde', 'EUen', 'EUes', 'EUfr', 'EUit', 'EUnl', 'EUru',
           'JPja', 'KRko', 'TWzh', 'USen', 'USes', 'USfr'}


def verify_overlay(romfs):
    report = json.loads((romfs/'resident-dialogue-mod.json').read_text())
    if (report.get('schema') != 'nxnative-acnh-starter-dialogue/1' or report.get('version') != '3.0.3'
            or {row['locale'] for row in report['locales']} != LOCALES):
        raise ValueError('the complete 3.0.3 starter-dialogue overlay is required')
    expected_paths = {f'Message/TalkNNpc_{locale}.sarc.zs' for locale in LOCALES}
    expected_paths.update(f'BDLI/TalkNNpc/{locale}/{personality[3:].upper()}_{family}.bdli.zs'
                          for locale in LOCALES for personality in PERSONALITIES if personality not in {'B2_Ha', 'G4_An'}
                          for _, family in FAMILIES)
    if report['output_files'] != len(expected_paths) or set(report['sha256']) != expected_paths:
        raise ValueError('incomplete starter-dialogue manifest')
    for name, expected in report['sha256'].items():
        path = Path(name)
        if path.is_absolute() or '..' in path.parts or path.parts[0] not in {'Message', 'BDLI'}:
            raise ValueError('invalid starter-dialogue manifest path')
        if hashlib.sha256((romfs/path).read_bytes()).hexdigest() != expected:
            raise ValueError(f'starter-dialogue resource mismatch: {name}')
    return report


def align(n, size=16):
    return (n + size - 1) & -size


def name_hash(name, multiplier):
    value = 0
    for byte in name.encode('utf-8'):
        value = (value * multiplier + byte) & 0xffffffff
    return value


def read_sarc(raw):
    if raw[:8] != b'SARC\x14\x00\xff\xfe' or len(raw) != struct.unpack_from('<I', raw, 8)[0]:
        raise ValueError('unsupported SARC header')
    data_at = struct.unpack_from('<I', raw, 12)[0]
    if raw[20:26] != b'SFAT\x0c\x00':
        raise ValueError('unsupported SARC table')
    count, multiplier = struct.unpack_from('<HI', raw, 26)
    names = 32 + count * 16
    if raw[names:names+6] != b'SFNT\x08\x00':
        raise ValueError('unsupported SARC names')
    names += 8
    files = {}
    for i in range(count):
        key, attr, start, end = struct.unpack_from('<IIII', raw, 32+i*16)
        at = names + (attr & 0xffffff)*4
        if attr >> 24 != 1 or not names <= at < data_at or not 0 <= start <= end <= len(raw)-data_at:
            raise ValueError('invalid SARC member')
        name = raw[at:raw.index(b'\0', at, data_at)].decode('utf-8')
        if name in files or name_hash(name, multiplier) != key:
            raise ValueError('invalid SARC member name/hash')
        files[name] = raw[data_at+start:data_at+end]
    return files, multiplier


def write_sarc(files, multiplier):
    names, nodes, data = bytearray(), bytearray(), bytearray()
    for name in sorted(files, key=lambda n: (name_hash(n, multiplier), n)):
        name_at = len(names)//4
        names.extend(name.encode('utf-8')+b'\0')
        names.extend(bytes(align(len(names), 4)-len(names)))
        data.extend(bytes(align(len(data))-len(data)))
        start = len(data)
        data.extend(files[name])
        nodes.extend(struct.pack('<IIII', name_hash(name, multiplier), 0x1000000 | name_at, start, len(data)))
    table = b'SFAT'+struct.pack('<HHI', 12, len(files), multiplier)+nodes+b'SFNT\x08\x00\x00\x00'+names
    data_at = align(20+len(table), 0x100)
    header = b'SARC\x14\x00\xff\xfe'+struct.pack('<IIHH', data_at+len(data), data_at, 0x100, 0)
    result = header+table+bytes(data_at-20-len(table))+data
    if read_sarc(result) != (files, multiplier):
        raise ValueError('SARC round-trip failed')
    return result


def read_msbt(raw):
    if raw[:10] != b'MsgStdBn\xff\xfe' or raw[12:14] != b'\x01\x03':
        raise ValueError('unsupported MSBT encoding/version')
    if struct.unpack_from('<I', raw, 18)[0] != len(raw):
        raise ValueError('invalid MSBT length')
    sections, at = {}, 32
    for _ in range(struct.unpack_from('<H', raw, 14)[0]):
        tag, size = struct.unpack_from('<4sI', raw, at)
        if at+16+size > len(raw) or tag in sections:
            raise ValueError('invalid MSBT section')
        sections[tag] = raw[at+16:at+16+size]
        at = align(at+16+size)
    if set(sections) != {b'LBL1', b'ATR1', b'TXT2'}:
        raise ValueError('unsupported MSBT sections')
    labels, attributes, text = (sections[k] for k in (b'LBL1', b'ATR1', b'TXT2'))
    count = struct.unpack_from('<I', text)[0]
    attr_count, attr_size = struct.unpack_from('<II', attributes)
    groups = struct.unpack_from('<I', labels)[0]
    if not count or not groups or count != attr_count or attr_size != 8 or len(attributes) != 8+count*8:
        raise ValueError('invalid MSBT counts/attributes')
    offsets = struct.unpack_from(f'<{count}I', text, 4)
    if offsets[0] != 4+4*count or list(offsets) != sorted(offsets):
        raise ValueError('invalid MSBT text offsets')
    indexed = {}
    for bucket in range(groups):
        n, at = struct.unpack_from('<II', labels, 4+8*bucket)
        for _ in range(n):
            length = labels[at]
            key = labels[at+1:at+1+length].decode('utf-8')
            at += 1+length
            index = struct.unpack_from('<I', labels, at)[0]
            at += 4
            if index in indexed or index >= count or name_hash(key, 0x492) % groups != bucket:
                raise ValueError('invalid MSBT label/hash')
            end = offsets[index+1] if index+1<count else len(text)
            value = text[offsets[index]:end]
            if len(value)%2 or not value.endswith(b'\0\0'):
                raise ValueError('invalid UTF-16 message extent')
            indexed[index] = (key, (value, attributes[8+index*8:16+index*8]))
    if len(indexed) != count:
        raise ValueError('unlabelled MSBT text')
    entries = dict(indexed[i] for i in range(count))
    if len(entries) != count:
        raise ValueError('duplicate MSBT label')
    return entries, raw[:32], groups


def write_msbt(entries, header, groups):
    buckets = [[] for _ in range(groups)]
    payload = bytearray()
    text, offsets = bytearray(), []
    for index, (key, (value, attribute)) in enumerate(entries.items()):
        buckets[name_hash(key, 0x492) % groups].append((key, index))
        offsets.append(4+len(entries)*4+len(text))
        text.extend(value)
    label_records = bytearray()
    for bucket in buckets:
        payload.extend(struct.pack('<II', len(bucket), 4+groups*8+len(label_records)))
        for key, index in bucket:
            encoded = key.encode('utf-8')
            if len(encoded)>255:
                raise ValueError('oversized MSBT label')
            label_records.extend(bytes([len(encoded)])+encoded+struct.pack('<I', index))
    sections = [(b'LBL1', struct.pack('<I', groups)+payload+label_records),
                (b'ATR1', struct.pack('<II', len(entries), 8)+b''.join(a for _, a in entries.values())),
                (b'TXT2', struct.pack('<I', len(entries))+struct.pack(f'<{len(entries)}I', *offsets)+text)]
    output = bytearray(header)
    for tag, value in sections:
        output.extend(struct.pack('<4sI8x', tag, len(value))+value)
        output.extend(bytes(align(len(output))-len(output)))
    struct.pack_into('<I', output, 18, len(output))
    result = bytes(output)
    if read_msbt(result)[0] != entries:
        raise ValueError('MSBT round-trip failed')
    return result


def read_bdli(raw):
    if raw[:6] != b'BDLI\x02\x00' or struct.unpack_from('<I', raw, 12)[0] != 20:
        raise ValueError('unsupported BDLI header')
    count = struct.unpack_from('<H', raw, 6)[0]
    if struct.unpack_from('<I', raw, 16)[0] != 20+16*count:
        raise ValueError('invalid BDLI table extent')
    result = {}
    for i in range(count):
        at = 20+16*i
        tag, commands, offset, key = struct.unpack_from('<4sIII', raw, at)
        start, size = at+offset, commands*20
        if tag != b'LBLI' or start < 20+count*16 or start+size > len(raw) or key in result:
            raise ValueError('invalid BDLI cue extent/hash')
        result[key] = raw[start:start+size]
    return result


def write_bdli(entries):
    table, payload = bytearray(), bytearray()
    start = 20+16*len(entries)
    for i, (key, commands) in enumerate(entries.items()):
        if len(commands)%20:
            raise ValueError('invalid BDLI command width')
        table.extend(struct.pack('<4sIII', b'LBLI', len(commands)//20, start+len(payload)-(20+16*i), key))
        payload.extend(commands)
    result = b'BDLI\x02\x00'+struct.pack('<HIII', len(entries), 0, 20, start)+table+payload
    if read_bdli(result) != entries:
        raise ValueError('BDLI round-trip failed')
    return result


def compress(raw):
    # The game allocates from the frame's declared content size. A CLI pipe
    # creates an unknown-size frame, which the resource loader cannot open.
    library = ctypes.util.find_library('zstd') or next(
        (str(p) for p in (Path('/opt/homebrew/lib/libzstd.dylib'), Path('/usr/local/lib/libzstd.dylib')) if p.exists()), None)
    if not library:
        raise ValueError('libzstd is required to build the dialogue overlay')
    lib = ctypes.CDLL(library)
    lib.ZSTD_compressBound.argtypes = [ctypes.c_size_t]
    lib.ZSTD_compressBound.restype = ctypes.c_size_t
    size = lib.ZSTD_compressBound(len(raw))
    output = ctypes.create_string_buffer(size)
    lib.ZSTD_compress.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t, ctypes.c_int]
    lib.ZSTD_compress.restype = ctypes.c_size_t
    written = lib.ZSTD_compress(output, size, raw, len(raw), 10)
    if written > size:
        raise ValueError('message compression failed')
    lib.ZSTD_getFrameContentSize.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    lib.ZSTD_getFrameContentSize.restype = ctypes.c_ulonglong
    if lib.ZSTD_getFrameContentSize(output, written) != len(raw):
        raise ValueError('compressed message frame has no declared size')
    return output.raw[:written]


def repair_locale(romfs, archive, output):
    locale = archive.name.removeprefix('TalkNNpc_').removesuffix('.sarc.zs')
    files, multiplier = read_sarc(decompress(archive))
    changed, added_labels = [], 0
    def paths(personality, category, family):
        prefix = personality[3:].upper()
        return f'{personality}/{category}/{prefix}_{family}.msbt', romfs/'BDLI/TalkNNpc'/locale/f'{prefix}_{family}.bdli.zs'
    for category, family in FAMILIES:
        donors = {}
        for donor in ('B2_Ha', 'G4_An'):
            name, cues = paths(donor, category, family)
            entries, header, groups = read_msbt(files[name])
            bdli = read_bdli(decompress(cues))
            for key in entries:
                if zlib.crc32(key.encode()) not in bdli:
                    raise ValueError('starter text has no matching cue')
            donors[donor] = (entries, header, groups, bdli)
        for personality in PERSONALITIES:
            if personality in donors:
                continue
            name, cue_path = paths(personality, category, family)
            preferred = 'B2_Ha' if personality[0]=='B' else 'G4_An'
            ordered = [preferred, 'G4_An' if preferred=='B2_Ha' else 'B2_Ha']
            existed = name in files
            entries, header, groups = read_msbt(files[name]) if existed else ({}, donors[preferred][1], donors[preferred][2])
            cues = read_bdli(decompress(cue_path)) if cue_path.exists() else {}
            before = dict(entries)
            filled = []
            for donor in ordered:
                for key, value in donors[donor][0].items():
                    # An all-zero UTF-16 string is absent. Preserve every original
                    # nonempty message byte and its existing attributes/cues.
                    if key not in entries or not any(entries[key][0]):
                        if not any(value[0]):
                            raise ValueError('starter donor contains empty dialogue')
                        entries[key] = value
                        hashed = zlib.crc32(key.encode())
                        cues[hashed] = donors[donor][3][hashed]
                        filled.append(key)
            if not filled:
                continue
            for key, value in before.items():
                if any(value[0]) and entries[key] != value:
                    raise ValueError('original nonempty dialogue changed')
            files[name] = write_msbt(entries, header, groups)
            target = output/cue_path.relative_to(romfs)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(compress(write_bdli(cues)))
            changed.append({'file': name, 'filled_labels': filled, 'new_file': not existed})
            added_labels += len(filled)
    target = output/archive.relative_to(romfs)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(compress(write_sarc(files, multiplier)))
    return {'locale': locale, 'changed_files': changed, 'filled_labels': added_labels}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('romfs', type=Path)
    parser.add_argument('output', type=Path, nargs='?', help='new overlay directory outside the checkout')
    parser.add_argument('--control', type=Path, help='3.0.3 control.nacp (default: beside RomFS)')
    parser.add_argument('--locale', action='append', help='optional locale filter, e.g. CNzh')
    parser.add_argument('--report', type=Path)
    parser.add_argument('--merged-romfs', type=Path, help='optional new full RomFS, cloned on APFS')
    parser.add_argument('--verify', action='store_true', help='verify an already merged complete overlay')
    args = parser.parse_args()
    if args.verify:
        verify_overlay(args.romfs)
        print('Starter dialogue: complete overlay SHA-256 verification passed')
        return
    if args.output is None or args.report is None:
        parser.error('output and --report are required when building')
    if (args.romfs/'resident-dialogue-mod.json').exists():
        parser.error('this RomFS already has a dialogue overlay; use --verify')
    control = args.control or args.romfs.parent/'control.nacp'
    if control.read_bytes()[0x3060:0x3070].split(b'\0', 1)[0] != b'3.0.3':
        parser.error('this overlay supports only game version 3.0.3')
    if args.output.exists() or args.romfs.resolve() in args.output.resolve().parents:
        parser.error('choose a new output directory outside the source RomFS')
    if args.merged_romfs and (args.merged_romfs.exists() or args.romfs.resolve() in args.merged_romfs.resolve().parents):
        parser.error('choose a new merged RomFS outside the source directory')
    archives = sorted((args.romfs/'Message').glob('TalkNNpc_*.sarc.zs'))
    if args.locale:
        archives = [p for p in archives if p.name in {f'TalkNNpc_{locale}.sarc.zs' for locale in args.locale}]
    if not archives:
        parser.error('no matching message archives')
    args.output.mkdir(parents=True)
    result = [repair_locale(args.romfs, path, args.output) for path in archives]
    files = sorted(p for p in args.output.rglob('*') if p.is_file())
    report = {'schema':'nxnative-acnh-starter-dialogue/1', 'version':'3.0.3', 'locales':result,
              'output_files':len(files), 'sha256':{str(p.relative_to(args.output)):hashlib.sha256(p.read_bytes()).hexdigest() for p in files}}
    args.report.write_text(json.dumps(report, indent=2)+'\n')
    if args.merged_romfs:
        # macOS cp clones complete trees on APFS; another filesystem can use the
        # ordinary copy fallback without ever opening the original for writing.
        if subprocess.run(['cp', '-cR', str(args.romfs), str(args.merged_romfs)], capture_output=True).returncode:
            if args.merged_romfs.exists():
                raise ValueError('RomFS cloning was incomplete; choose a new destination')
            shutil.copytree(args.romfs, args.merged_romfs)
        shutil.copytree(args.output, args.merged_romfs, dirs_exist_ok=True)
        (args.merged_romfs/'resident-dialogue-mod.json').write_text(json.dumps(report, indent=2)+'\n')
        if not args.locale:
            verify_overlay(args.merged_romfs)
    print(f'Starter dialogue: {len(result)} locales, {sum(row["filled_labels"] for row in result)} messages, {len(files)} overlay files')


if __name__ == '__main__':
    main()
