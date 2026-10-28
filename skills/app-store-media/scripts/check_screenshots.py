#!/usr/bin/env python3
"""Check a framed App Store screenshot set before upload. Standard library only.

    python3 check_screenshots.py <framed-dir> [--ipad] [--duo] [--self-test]

<framed-dir> holds one folder per set (any names). Every PNG or JPEG in a folder
must be the same accepted size; the size decides its display class. Checks:

  1. every file is an accepted App Store pixel size (exact match), and all files
     in one folder are the same class and orientation;
  2. no alpha: PNG colour types 4 and 6 and any tRNS chunk fail (App Store
     Connect rejects transparency);
  3. 1 to 10 files per folder;
  4. coverage: the required classes are present (iPhone Dynamic Island medium
     6.3"; iPad 13" with --ipad; both iPhone Duo displays with --duo), and the
     classes with no set of their own are listed with what Apple falls back to.

Exit 0 when every check passes, 1 otherwise. --self-test builds known-bad
inputs and confirms each check fails on them. Sizes from Apple's screenshot
specifications page, checked 2026-10-28 (references/apple-specs.md).
"""
import os
import struct
import sys
import tempfile
import zlib

# (class id, label, accepted portrait sizes)
CLASSES = [
    ("iphone_di_large", 'iPhone 6.9" (Dynamic Island, large)', [(1260, 2736), (1290, 2796), (1320, 2868)]),
    ("iphone_faceid_large", 'iPhone 6.5" (Face ID, large)', [(1284, 2778), (1242, 2688)]),
    ("iphone_di_medium", 'iPhone 6.3" (Dynamic Island, medium)', [(1179, 2556), (1206, 2622)]),
    ("iphone_faceid_medium", 'iPhone 6.1" (Face ID, medium)', [(1170, 2532), (1125, 2436), (1080, 2340)]),
    ("iphone_home_large", 'iPhone 5.5" (Home Button, large)', [(1242, 2208)]),
    ("iphone_home_medium", 'iPhone 4.7" (Home Button, medium)', [(750, 1334)]),
    ("iphone_4in", 'iPhone 4"', [(640, 1096), (640, 1136)]),
    ("iphone_35in", 'iPhone 3.5"', [(640, 920), (640, 960)]),
    ("duo_outer", "iPhone Duo outer", [(1398, 2034)]),
    ("duo_inner", "iPhone Duo inner", [(2007, 2853)]),
    ("ipad_13", 'iPad 13"', [(2064, 2752), (2048, 2732)]),
    ("ipad_11", 'iPad 11"', [(1488, 2266), (1668, 2420), (1668, 2388), (1640, 2360)]),
    ("ipad_10_5", 'iPad 10.5"', [(1668, 2224)]),
    ("ipad_9_7", 'iPad 9.7"', [(1536, 2008), (1536, 2048), (768, 1004), (768, 1024)]),
]
FALLBACK = {
    "iphone_di_large": "scaled from 6.5\"", "iphone_faceid_large": "scaled from 6.9\"",
    "iphone_di_medium": "REQUIRED", "iphone_faceid_medium": "scaled from 6.3\"",
    "iphone_home_large": "scaled from 6.1\"", "iphone_home_medium": "scaled from 5.5\"",
    "ipad_11": "scaled from 13\"", "ipad_10_5": "scaled from 12.9\"/13\"",
}
SIZE_TO_CLASS = {}
for cid, label, sizes in CLASSES:
    for w, h in sizes:
        SIZE_TO_CLASS[(w, h)] = (cid, "portrait")
        SIZE_TO_CLASS[(h, w)] = (cid, "landscape")
# 1242 wide appears in two classes; they differ in height, so the table stays unambiguous.
LABEL = {cid: label for cid, label, _ in CLASSES}


def png_info(path):
    """(width, height, has_alpha) from the PNG header and chunk list."""
    with open(path, "rb") as f:
        if f.read(8) != b"\x89PNG\r\n\x1a\n":
            raise ValueError("not a PNG")
        width = height = None
        alpha = False
        while True:
            head = f.read(8)
            if len(head) < 8:
                break
            length, ctype = struct.unpack(">I4s", head)
            data = f.read(length)
            f.read(4)
            if ctype == b"IHDR":
                width, height, _depth, colour = struct.unpack(">IIBB", data[:10])
                alpha = colour in (4, 6)
            elif ctype == b"tRNS":
                alpha = True
            elif ctype == b"IDAT":
                break
        return width, height, alpha


def jpeg_size(path):
    with open(path, "rb") as f:
        data = f.read()
    i = 2
    while i < len(data):
        if data[i] != 0xFF:
            i += 1
            continue
        marker = data[i + 1]
        if marker in (0xC0, 0xC1, 0xC2):
            h, w = struct.unpack(">HH", data[i + 5:i + 9])
            return w, h, False
        i += 2 + struct.unpack(">H", data[i + 2:i + 4])[0]
    raise ValueError("no JPEG frame header")


def check(root, ipad=False, duo=False, out=print):
    failures = []
    present = {}
    folders = sorted(d for d in os.listdir(root) if os.path.isdir(os.path.join(root, d)))
    if not folders:
        failures.append(f"{root}: no set folders")
    for folder in folders:
        path = os.path.join(root, folder)
        files = sorted(f for f in os.listdir(path) if f.lower().endswith((".png", ".jpg", ".jpeg")))
        if not 1 <= len(files) <= 10:
            failures.append(f"{folder}: {len(files)} files (App Store Connect takes 1 to 10)")
        kinds = set()
        for name in files:
            fp = os.path.join(path, name)
            try:
                w, h, alpha = png_info(fp) if name.lower().endswith(".png") else jpeg_size(fp)
            except ValueError as e:
                failures.append(f"{folder}/{name}: {e}")
                continue
            kind = SIZE_TO_CLASS.get((w, h))
            if kind is None:
                failures.append(f"{folder}/{name}: {w}x{h} is not an accepted App Store size")
            else:
                kinds.add(kind)
            if alpha:
                failures.append(f"{folder}/{name}: has an alpha channel or transparency")
        if len(kinds) > 1:
            failures.append(f"{folder}: mixes classes or orientations {sorted(kinds)}")
        for cid, orient in kinds:
            present.setdefault(cid, []).append(f"{folder} ({len(files)} {orient})")

    out("Coverage:")
    for cid, label, _ in CLASSES:
        if cid in present:
            out(f"  ok   {label}: {', '.join(present[cid])}")
        elif cid in FALLBACK:
            out(f"  --   {label}: none ({FALLBACK[cid]})")
    required = ["iphone_di_medium"] + (["ipad_13"] if ipad else []) + (["duo_outer", "duo_inner"] if duo else [])
    for cid in required:
        if cid not in present:
            failures.append(f"missing required class: {LABEL[cid]}")
    for f in failures:
        out(f"FAIL {f}")
    out("PASS" if not failures else f"{len(failures)} failure(s)")
    return failures


def write_png(path, w, h, colour_type=2, trns=False):
    channels = {2: 3, 6: 4}[colour_type]
    raw = b"".join(b"\x00" + b"\x80" * (w * channels) for _ in range(h))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, colour_type, 0, 0, 0))
    if trns:
        data += chunk(b"tRNS", b"\x00\x00\x00\x00\x00\x00")
    data += chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(data)


def self_test():
    """Each check must fail on a known-bad input and pass on a known-good one."""
    cases = {
        "good": ([("a", 1206, 2622, 2, False)], True),
        "wrong size": ([("a", 1206, 2600, 2, False)], False),
        "alpha (RGBA)": ([("a", 1206, 2622, 6, False)], False),
        "alpha (tRNS)": ([("a", 1206, 2622, 2, True)], False),
        "missing 6.3": ([("a", 1320, 2868, 2, False)], False),
        "mixed classes": ([("a", 1206, 2622, 2, False), ("a", 1179, 2556, 2, False), ("a", 1170, 2532, 2, False)], None),
        "eleven files": ([("a", 1206, 2622, 2, False)] * 11, False),
    }
    ok = True
    for name, (files, expect_pass) in cases.items():
        with tempfile.TemporaryDirectory() as d:
            for i, (folder, w, h, ct, trns) in enumerate(files):
                os.makedirs(os.path.join(d, folder), exist_ok=True)
                write_png(os.path.join(d, folder, f"{i:02d}.png"), w, h, ct, trns)
            if name == "mixed classes":
                # 1206x2622 and 1179x2556 are the same class; 1170x2532 is not.
                fails = check(d, out=lambda *_: None)
                result = any("mixes classes" in f for f in fails)
                expect, got = True, result
            else:
                fails = check(d, out=lambda *_: None)
                expect, got = expect_pass, not fails
            status = "ok" if expect == got else "WRONG"
            ok &= expect == got
            print(f"  {status:5} {name}: {'passed' if not fails else fails[0]}")
    print("self-test", "PASS" if ok else "FAIL")
    return ok


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--self-test" in args:
        sys.exit(0 if self_test() else 1)
    dirs = [a for a in args if not a.startswith("--")]
    if len(dirs) != 1:
        print(__doc__)
        sys.exit(2)
    sys.exit(1 if check(dirs[0], ipad="--ipad" in args, duo="--duo" in args) else 0)
