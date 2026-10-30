#!/usr/bin/env python3
"""Use DEFLATE framing for every file so streamed IPA repacks are unambiguous.

Sideloadly preserves the input compression methods, then writes unknown-size
local headers followed by data descriptors. Apple's BOM extractor scans stored
members for the descriptor signature and can mistake the same bytes in a game
resource for its end. DEFLATE provides an explicit stream end independently of
those bytes. File contents, executable and resource paths remain unchanged.
"""
import argparse
import concurrent.futures
import importlib.util
import itertools
import json
import os
from pathlib import Path
import stat
import struct
import subprocess
import time
from types import SimpleNamespace
import zipfile
import zlib

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("pack_ipa", ROOT / "dm/ios/tools/pack_ipa.py")
pack = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pack)


def entry(info):
    mode = info.external_attr >> 16
    if not mode:
        mode = (stat.S_IFDIR | 0o755) if info.is_dir() else (stat.S_IFREG | 0o644)
    modified = time.mktime((*info.date_time, 0, 0, -1))
    return pack.Entry(info.filename, None, SimpleNamespace(st_mode=mode, st_mtime=modified), None)


def repack(src, dst):
    part = dst.with_suffix(dst.suffix + ".partial")
    started = time.monotonic()
    with zipfile.ZipFile(src) as original:
        infos = original.infolist()
        writer = pack.Zip(str(part))
        def compress(info):
            if info.is_dir():
                return info, 0, 0, b"", 0
            raw = original.read(info)
            compressor = zlib.compressobj(1, zlib.DEFLATED, -15)
            data = compressor.compress(raw) + compressor.flush()
            return info, 8, info.CRC, data, len(raw)
        done = 0
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
                for batch in itertools.batched(infos, 512):
                    for info, method, crc, data, size in pool.map(compress, batch):
                        writer.put(entry(info), method, crc, data, size)
                        done += 1
                    if done % 8192 == 0:
                        print(f"repack {done}/{len(infos)} entries", flush=True)
            writer.close()
        except BaseException:
            writer.f.close()
            raise
    with zipfile.ZipFile(src) as original, zipfile.ZipFile(part) as result:
        before, after = original.infolist(), result.infolist()
        assert [(i.filename, i.CRC, i.file_size, i.external_attr) for i in before] == [
            (i.filename, i.CRC, i.file_size, i.external_attr) for i in after
        ], "Resource or executable contents/permissions changed"
        assert all(i.is_dir() or i.compress_type == zipfile.ZIP_DEFLATED for i in after)
        assert result.testzip() is None, "Output CRC check failed"
    os.replace(part, dst)
    print(json.dumps({"entries": len(infos), "size": dst.stat().st_size,
                      "elapsed_seconds": round(time.monotonic() - started, 1),
                      "payload_crc_and_permissions_unchanged": True,
                      "full_output_crc": "PASS"}), flush=True)


def streamed_copy(src, dst):
    """Model Sideloadly's streaming ZIP headers, without signing or installing."""
    with zipfile.ZipFile(src) as archive, src.open("rb") as raw:
        writer = pack.Zip(str(dst))
        for info in archive.infolist():
            if info.is_dir():
                continue
            e = entry(info)
            h = writer.local(e, info.compress_type, 0, 0, 0)
            offset, name, flags, dos_time, dos_date = h
            writer.patch(offset + 6, struct.pack("<H", flags | 8))
            writer.f.seek(writer.pos)
            raw.seek(info.header_offset)
            header = raw.read(30)
            name_len, extra_len = struct.unpack_from("<HH", header, 26)
            raw.seek(name_len + extra_len, 1)
            remaining = info.compress_size
            while remaining:
                chunk = raw.read(min(16 << 20, remaining))
                if not chunk:
                    raise RuntimeError("Unexpected end of source archive")
                writer.w(chunk)
                remaining -= len(chunk)
            writer.w(struct.pack("<IIII", 0x08074B50, info.CRC, info.compress_size, info.file_size))
            writer.central(e, (offset, name, flags | 8, dos_time, dos_date),
                           info.compress_type, info.CRC, info.compress_size, info.file_size)
        writer.close()
    print(f"Wrote streaming ZIP fixture: {dst.stat().st_size} bytes", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("source", type=Path)
    parser.add_argument("destination", type=Path)
    parser.add_argument("--streamed-fixture", action="store_true")
    args = parser.parse_args()
    if args.destination.exists():
        raise SystemExit("Destination exists; choose a new filename")
    if args.streamed_fixture:
        streamed_copy(args.source, args.destination)
    else:
        repack(args.source, args.destination)


if __name__ == "__main__":
    main()
