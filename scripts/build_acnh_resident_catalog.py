#!/usr/bin/env python3
"""Build the optional 3.0.3 resident manager catalog from the user's own RomFS.

No game names, messages or save templates are distributed in this repository.
The output belongs beside the user's game build, outside the repository.
"""
import argparse
import base64
from collections.abc import Sequence
import ctypes
import ctypes.util
import json
from pathlib import Path
import re
import struct
import zlib

SPECIES: Sequence[str] = 'ant bea brd bul cat cbr chn cow crd der dog duk elp flg goa gor ham hip hrs kal kgr lon mnk mus ocp ost pbr pgn pig rbt rhn shp squ tig wol'.split()
PERSONALITIES = ['Boy_normal', 'Boy_active', 'Boy_pride', 'Boy_snobby', 'Girl_normal', 'Girl_active', 'Girl_pride', 'Girl_big_sis']
# S00 localized phrases: eleven char16[22] entries, not fourteen message folders.
# English, Spanish and French share their respective save slots across regions.
PHRASE_LOCALES = ('JPja', 'USen', 'USes', 'USfr', 'EUde', 'EUit', 'EUnl', 'EUru', 'KRko', 'CNzh', 'TWzh')


def decompress(path):
    raw = Path(path).read_bytes()
    library = ctypes.util.find_library('zstd')
    if not library:
        library = next((str(p) for p in [Path('/opt/homebrew/lib/libzstd.dylib'), Path('/usr/local/lib/libzstd.dylib')] if p.exists()), None)
    if not library:
        raise ValueError('libzstd is required to read the game messages')
    lib = ctypes.CDLL(library)
    lib.ZSTD_getFrameContentSize.argtypes = [ctypes.c_void_p, ctypes.c_size_t]
    lib.ZSTD_getFrameContentSize.restype = ctypes.c_ulonglong
    size = lib.ZSTD_getFrameContentSize(raw, len(raw))
    if not 0 < size <= 64 * 1024 * 1024:
        raise ValueError('invalid or oversized message archive')
    output = ctypes.create_string_buffer(size)
    lib.ZSTD_decompress.argtypes = [ctypes.c_void_p, ctypes.c_size_t, ctypes.c_void_p, ctypes.c_size_t]
    lib.ZSTD_decompress.restype = ctypes.c_size_t
    if lib.ZSTD_decompress(output, size, raw, len(raw)) != size:
        raise ValueError('message archive decompression failed')
    return output.raw


def sarc_member(raw, name):
    if raw[:4] != b'SARC' or raw[6:8] != b'\xff\xfe':
        raise ValueError('expected little-endian SARC')
    header = struct.unpack_from('<H', raw, 4)[0]
    data = struct.unpack_from('<I', raw, 12)[0]
    count = struct.unpack_from('<H', raw, header + 6)[0]
    nodes = header + 12
    names = nodes + count * 16 + 8
    for i in range(count):
        _, attr, start, end = struct.unpack_from('<IIII', raw, nodes + 16*i)
        a = names + 4 * (attr & 0xffffff)
        found = raw[a:].split(b'\0', 1)[0].decode('utf-8')
        if found == name and 0 <= start <= end <= len(raw)-data:
            return raw[data+start:data+end]
    raise ValueError(f'message file missing: {name}')


def msbt(raw):
    if raw[:8] != b'MsgStdBn' or raw[8:10] != b'\xff\xfe' or raw[12] != 1:
        raise ValueError('expected little-endian UTF-16 MSBT')
    sections, at = {}, 32
    for _ in range(struct.unpack_from('<H', raw, 14)[0]):
        tag, size = struct.unpack_from('<4sI', raw, at)
        if at+16+size > len(raw):
            raise ValueError('truncated MSBT section')
        sections[tag] = raw[at+16:at+16+size]
        at = (at+16+size+15) & ~15
    labels, text = sections[b'LBL1'], sections[b'TXT2']
    count = struct.unpack_from('<I', text)[0]
    offsets = struct.unpack_from(f'<{count}I', text, 4)
    result = {}
    for i in range(struct.unpack_from('<I', labels)[0]):
        n, at = struct.unpack_from('<II', labels, 4+i*8)
        for _ in range(n):
            length = labels[at]; at += 1
            name = labels[at:at+length].decode('utf-8'); at += length
            index = struct.unpack_from('<I', labels, at)[0]; at += 4
            value = text[offsets[index]:offsets[index+1] if index+1<count else len(text)].decode('utf-16-le').rstrip('\0')
            if any(ord(c) < 32 for c in value):
                raise ValueError('unexpected control sequence in resident name or phrase')
            result[name] = value
    return result


def build(romfs, templates=None):
    romfs = Path(romfs)
    cn = decompress(romfs / 'Message/String_CNzh.sarc.zs')
    en = decompress(romfs / 'Message/String_USen.sarc.zs')
    names = msbt(sarc_member(cn, 'Npc/STR_NNpcName.msbt'))
    english = msbt(sarc_member(en, 'Npc/STR_NNpcName.msbt'))
    phrases = [msbt(sarc_member(decompress(romfs / f'Message/String_{locale}.sarc.zs'), 'Npc/STR_NNpcPhrase.msbt'))
               for locale in PHRASE_LOCALES]
    raw = (romfs / 'Bcsv/NmlNpcParam.bcsv').read_bytes()
    n, stride, fields = struct.unpack_from('<IIH', raw)
    if n != 417 or stride != 0x120 or raw[12:16] != b'VSCB':
        raise ValueError('resident table does not match the supported 3.0.3 layout')
    columns = dict(struct.unpack_from('<II', raw, 28+8*i) for i in range(fields))
    identity, personality = columns[0x2f1b930d], columns[0x04f52f6a]
    types = {zlib.crc32(p.encode('ascii')): i for i,p in enumerate(PERSONALITIES)}
    animals = []
    for i in range(n):
        at = 28+8*fields+i*stride
        internal = raw[at+identity:at+identity+8].split(b'\0')[0].decode('ascii')
        if not re.fullmatch('[a-z]{3}[0-9]{2}', internal) or internal[:3] not in SPECIES:
            raise ValueError(f'unknown resident identity: {internal}')
        species = SPECIES.index(internal[:3])
        variant = int(internal[3:])
        temperament = types[struct.unpack_from('<I', raw, at+personality)[0]]
        localized_phrases = [p[internal] for p in phrases]
        if any(not p or len(p.encode('utf-16-le')) > 42 for p in localized_phrases):
            raise ValueError(f'incompatible localized phrase: {internal}')
        animal = dict(id=internal, name=names[internal], english=english[internal], phrase=localized_phrases[9],
                      phrases=localized_phrases,
                      species=species, variant=variant, personality=temperament)
        if templates is not None:
            v = (Path(templates)/'Villagers'/f'{internal}V.bin').read_bytes()
            h = (Path(templates)/'Houses'/f'{internal}H.bin').read_bytes()
            if len(v) != 0x13230 or len(h) != 0x12e8 or v[:3] != bytes([species, variant, temperament]):
                raise ValueError(f'incompatible resident/house template: {internal}')
            animal['template'] = base64.b64encode(zlib.compress(v+h, 9)).decode('ascii')
        animals.append(animal)
    if len({a['id'] for a in animals}) != 417 or set(names) != {a['id'] for a in animals}:
        raise ValueError('resident table and localized names disagree')
    return dict(schema='nxnative-acnh-residents/2', version='3.0.3', animals=animals)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('romfs', type=Path)
    parser.add_argument('output', type=Path)
    parser.add_argument('--templates', type=Path, help='NHSE.Villagers/Resources from a local NHSE checkout; distribute its GPL-3.0 license and source with the package')
    args = parser.parse_args()
    try:
        result = build(args.romfs, args.templates)
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(result, ensure_ascii=False, separators=(',', ':'))+'\n')
    except (ValueError, OSError, KeyError, struct.error) as error:
        parser.exit(1, f'resident catalog: {error}\n')
    print(f"resident catalog: {len(result['animals'])} animals -> {args.output}")


if __name__ == '__main__':
    main()
