#!/usr/bin/env python3
"""Generate the pixel-art portraits in assets/portraits/.

Each portrait is a hand-authored 16x16 grid (one letter per pixel, '.' =
transparent) scaled by 3 to 48x48. Pure stdlib PNG writer - no PIL needed.
Run from the repo root:  python3 tools/gen_portraits.py
"""
import os
import struct
import zlib

SCALE = 3
OUT_DIR = os.path.join(os.path.dirname(__file__), "..", "assets", "portraits")

SKIN = (232, 196, 160, 255)
EYE = (40, 32, 44, 255)
MOUTH = (172, 96, 84, 255)
GOLD = (222, 186, 84, 255)

PORTRAITS = {
    # Aldwin Reeve - grey-haired clerk, blue robe (chancellor seat colour)
    "char_chancellor": {
        "palette": {"g": (158, 158, 172, 255), "s": SKIN, "d": EYE, "m": MOUTH,
                    "b": (74, 111, 165, 255), "t": (208, 214, 226, 255)},
        "rows": [
            "................",
            "....ggggggg.....",
            "...gggggggggg...",
            "...ggssssssgg...",
            "...gssssssssg...",
            "...gsdssssdsg...",
            "....ssssssss....",
            "....ssmmmmss....",
            ".....ssssss.....",
            "....bbbbbbbb....",
            "...bbbbbbbbbb...",
            "..bbtbbbbbbtbb..",
            "..bbbbbbbbbbbb..",
            "..bbbbbbbbbbbb..",
            "..bbbbbbbbbbbb..",
            "................",
        ],
    },
    # Ser Brandt - steel helm, red plume, armour (marshal red)
    "char_marshal": {
        "palette": {"r": (165, 74, 74, 255), "h": (176, 180, 192, 255),
                    "d": (30, 28, 38, 255), "s": SKIN, "m": MOUTH,
                    "a": (118, 124, 140, 255)},
        "rows": [
            ".......rr.......",
            "......rrrr......",
            "....hhhhhhhh....",
            "...hhhhhhhhhh...",
            "...hhhhhhhhhh...",
            "...hddddddddh...",
            "...hhhhhhhhhh...",
            "....ssssssss....",
            "....ssmmmmss....",
            ".....ssssss.....",
            "....aaaaaaaa....",
            "...aaaaaaaaaa...",
            "..aaraaaaaaraa..",
            "..aaaaaaaaaaaa..",
            "..aaaaaaaaaaaa..",
            "................",
        ],
    },
    # Mirella - green headscarf, auburn hair, gold-trimmed dress (steward green)
    "char_steward": {
        "palette": {"c": (74, 165, 113, 255), "h": (150, 84, 54, 255), "s": SKIN,
                    "d": EYE, "m": MOUTH, "e": (58, 130, 90, 255), "g": GOLD},
        "rows": [
            "................",
            "....cccccccc....",
            "...cccccccccc...",
            "..ccsssssssscc..",
            "..hcssssssssch..",
            "..hcsdssssdsch..",
            "..hcssssssssch..",
            "..h.ssmmmmss.h..",
            ".....ssssss.....",
            "....eeeeeeee....",
            "...eeeeeeeeee...",
            "..eegeeeeeegee..",
            "..eeeeeeeeeeee..",
            "..eeeeeeeeeeee..",
            "..eeeeeeeeeeee..",
            "................",
        ],
    },
    # Quill - purple hood, face in shadow, pale watching eyes (spymaster purple)
    "char_spymaster": {
        "palette": {"p": (107, 74, 165, 255), "f": (38, 30, 52, 255),
                    "w": (222, 222, 238, 255), "d": (70, 48, 112, 255)},
        "rows": [
            "................",
            ".....pppppp.....",
            "....pppppppp....",
            "...pppppppppp...",
            "...ppffffffpp...",
            "...pffffffffp...",
            "...pfwffffwfp...",
            "...pffffffffp...",
            "....pffffffp....",
            "....pppppppp....",
            "...pppppppppp...",
            "..pppppppppppp..",
            "..ppdpppppppdp..",
            "..pppppppppppp..",
            "..pppppppppppp..",
            "................",
        ],
    },
    # Father Odo - bald crown, brown fringe, robe + gold cross (chaplain ochre)
    "char_chaplain": {
        "palette": {"h": (122, 86, 58, 255), "s": SKIN, "d": EYE, "m": MOUTH,
                    "r": (165, 140, 74, 255), "g": (230, 198, 92, 255)},
        "rows": [
            "................",
            ".....ssssss.....",
            "....ssssssss....",
            "...hssssssssh...",
            "...hssssssssh...",
            "...hsdssssdsh...",
            "...hssssssssh...",
            "....ssmmmmss....",
            ".....ssssss.....",
            "....rrrrrrrr....",
            "...rrrrrrrrrr...",
            "..rrrrggrrrrrr..",
            "..rrrggggggrrr..",
            "..rrrrggrrrrrr..",
            "..rrrrggrrrrrr..",
            "................",
        ],
    },
    # Herald - blond, red tabard with gold badge
    "herald": {
        "palette": {"y": (214, 190, 110, 255), "s": SKIN, "d": EYE, "m": MOUTH,
                    "t": (150, 52, 52, 255), "g": GOLD},
        "rows": [
            "................",
            "....yyyyyyyy....",
            "...yyyyyyyyyy...",
            "...ysssssssyy...",
            "...ssssssssss...",
            "...sdssssssds...",
            "....ssssssss....",
            "....ssmmmmss....",
            ".....ssssss.....",
            "....tttttttt....",
            "...tttttttttt...",
            "..ttgttttttgtt..",
            "..ttttggggtttt..",
            "..ttgttttttgtt..",
            "..tttttttttttt..",
            "................",
        ],
    },
    # You - the ruler: gold crown, royal purple, ermine trim
    "you": {
        "palette": {"g": GOLD, "s": SKIN, "d": EYE, "m": MOUTH,
                    "p": (96, 60, 140, 255), "w": (236, 236, 236, 255)},
        "rows": [
            "...g..g..g..g...",
            "...gggggggggg...",
            "...gggggggggg...",
            "...ssssssssss...",
            "...ssssssssss...",
            "...sdssssssds...",
            "....ssssssss....",
            "....ssmmmmss....",
            ".....ssssss.....",
            "....pppppppp....",
            "...pppppppppp...",
            "..pwpppppppwpp..",
            "..pppppppppppp..",
            "..pppppppppppp..",
            "..pppppppppppp..",
            "................",
        ],
    },
}


def write_png(path, width, height, get_rgba):
    raw = b""
    for y in range(height):
        raw += b"\x00"
        for x in range(width):
            raw += struct.pack("4B", *get_rgba(x, y))

    def chunk(tag, data):
        c = tag + data
        return struct.pack(">I", len(data)) + c + struct.pack(">I", zlib.crc32(c))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    for name, spec in PORTRAITS.items():
        rows, palette = spec["rows"], spec["palette"]
        assert len(rows) == 16, "%s: expected 16 rows, got %d" % (name, len(rows))
        for i, row in enumerate(rows):
            assert len(row) == 16, "%s row %d: len %d != 16 (%r)" % (name, i, len(row), row)
            for ch in row:
                assert ch == "." or ch in palette, "%s row %d: unknown pixel %r" % (name, i, ch)

        def rgba(x, y, rows=rows, palette=palette):
            ch = rows[y // SCALE][x // SCALE]
            return palette[ch] if ch != "." else (0, 0, 0, 0)

        out = os.path.join(OUT_DIR, name + ".png")
        write_png(out, 16 * SCALE, 16 * SCALE, rgba)
        print("wrote", out)


if __name__ == "__main__":
    main()
