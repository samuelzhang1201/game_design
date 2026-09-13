#!/usr/bin/env python3
"""Turn a chapter's renders into game assets.

    python3 assets/flux/install_map_art.py goods    # G-xx -> assets/goods/
    python3 assets/flux/install_map_art.py cast     # K-xx -> assets/portraits/

MAP SYMBOLS (goods) are cut out LOCALLY — the whole chain is arithmetic on the
blue channel (see sepia_alpha_template.json for the same steps as a ComfyUI
graph), so there is no reason to queue 38 jobs behind a batch of portraits.
They are then GREYED, because the game tints them by category or by realm at
multiply and the art must carry only value, and lightened toward the paper in
the file rather than drawn translucent, because a translucent mark cannot
occlude the one under it (see CLAUDE.md).

PORTRAITS still go through post.py: cutting a person out of a background needs
BiRefNet, which is a model, not arithmetic. They keep their colour — a face is
looked at, not tinted.

Stdlib only.
"""
from __future__ import annotations

import csv
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(HERE))
from post import decode_png, encode_png, INK_BLUE_MAX, TRIM_ALPHA  # noqa: E402


def cut_out(w: int, h: int, ch: int, px: bytes) -> tuple[int, int, bytearray]:
    """Sepia ink on white -> RGBA, trimmed to the drawing. alpha = clamp(2 x
    (1 - blue)): white paper falls to 0, umber ink rises to 1, and the brush's
    soft edges survive as the values in between."""
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        row = px[y * w * ch:(y + 1) * w * ch]
        for x in range(w):
            if row[x * ch + 2] <= INK_BLUE_MAX:
                if x < x0: x0 = x
                if x > x1: x1 = x
                if y < y0: y0 = y
                if y > y1: y1 = y
    if x1 < 0:
        x0, y0, x1, y1 = 0, 0, w - 1, h - 1
    cw, chh = x1 - x0 + 1, y1 - y0 + 1
    out = bytearray(cw * chh * 4)
    for y in range(chh):
        src = ((y0 + y) * w + x0) * ch
        dst = y * cw * 4
        for x in range(cw):
            i = src + x * ch
            a = min(255, int((255 - px[i + 2]) * 2))
            out[dst + x * 4:dst + x * 4 + 4] = bytes((px[i], px[i + 1], px[i + 2], a))
    return cw, chh, out


def resize_rgba(w: int, h: int, px: bytearray, tw: int, th: int) -> bytearray:
    """Box filter. Every one of these assets is DOWNscaled, which is what a box
    filter is good at and what nearest is worst at."""
    out = bytearray(tw * th * 4)
    for y in range(th):
        sy0, sy1 = y * h // th, max(y * h // th + 1, (y + 1) * h // th)
        for x in range(tw):
            sx0, sx1 = x * w // tw, max(x * w // tw + 1, (x + 1) * w // tw)
            acc = [0, 0, 0, 0]
            n = 0
            for sy in range(sy0, sy1):
                base = sy * w * 4
                for sx in range(sx0, sx1):
                    i = base + sx * 4
                    for c in range(4):
                        acc[c] += px[i + c]
                    n += 1
            o = (y * tw + x) * 4
            for c in range(4):
                out[o + c] = acc[c] // n
    return out


def grey_and_lighten(px: bytearray, k: float) -> None:
    for i in range(0, len(px), 4):
        g = int(0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2] + 0.5)
        g = int(g + (255 - g) * k + 0.5)
        px[i] = px[i + 1] = px[i + 2] = g


def install_goods(height: int = 128, lighten: float = 0.45) -> int:
    codes = {r["art_id"]: r["good_code"] for r in csv.DictReader((HERE / "goods_art.csv").open())}
    dest = ROOT / "assets" / "goods"
    dest.mkdir(parents=True, exist_ok=True)
    done = 0
    for art_id, code in sorted(codes.items()):
        hits = sorted((HERE / "out" / "goods").glob("%s_*.png" % art_id))
        if not hits:
            print("  (no render for %s / %s)" % (art_id, code))
            continue
        w, h, ch, px = decode_png(hits[-1])
        cw, chh, rgba = cut_out(w, h, ch, px)
        tw = max(1, round(cw * height / chh))
        small = resize_rgba(cw, chh, rgba, tw, height)
        grey_and_lighten(small, lighten)
        encode_png(dest / ("%s.png" % code), tw, height, 4, bytes(small))
        print("  %-6s %-16s %dx%d" % (art_id, code, tw, height))
        done += 1
    return done


## The game wants two tiers per character (character_portrait.gd): a 96 px
## chip from the [C-BUST] render for the portrait box, and a 660 px tall
## real-alpha figure from the [C-FULL] render for the conversation stage.
CAST_TIERS = [
    ("c-bust", "chip", 96, "assets/portraits"),
    # 1024 rather than the tier's own 660: the conversation stage
    # cover-crops this into a box that is a few hundred DESIGN px tall, and
    # the design viewport is 1280x720 now — the source has to stay above the
    # drawn size or the face is being upscaled.
    ("c-full", "full", 1024, "assets/portraits/full"),
]


def install_cast() -> int:
    codes = {r["art_id"]: r["character_id"] for r in csv.DictReader((HERE / "cast_art.csv").open())}
    done = 0
    for tag, tier, size, out_dir in CAST_TIERS:
        print("-- %s tier" % tier)
        done += _install_cast_tier(codes, tag, tier, size, ROOT / out_dir)
    return done


def _install_cast_tier(codes: dict, tag: str, tier: str, size: int, dest: Path) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    staged = HERE / "out" / "game" / tier
    done = 0
    for art_id, code in sorted(codes.items()):
        hits = sorted((HERE / "out" / "cast").glob("%s_*%s*.png" % (art_id, tag)))
        if not hits:
            print("  (no %s render for %s / %s)" % (tag, art_id, code))
            continue
        # A long timeout and no check: the cutout is queued behind whatever
        # else is generating, and one slow portrait must not abandon the other
        # twenty. Rerun the installer to pick up whatever was missed.
        # --size means "the square" for the chip tier and "the height, aspect
        # kept" for the full tier; post.py reads the tier to know which.
        args = [sys.executable, str(HERE / "post.py"), "--tier", tier,
                "--timeout", "3600", "--size", str(size), str(hits[-1])]
        r = subprocess.run(args, stdout=subprocess.DEVNULL)
        cut = sorted(staged.glob("%s*.png" % art_id))
        if r.returncode != 0 or not cut:
            print("  (cutout failed for %s / %s — rerun to retry)" % (art_id, code))
            continue
        (dest / ("%s.png" % code)).write_bytes(cut[-1].read_bytes())
        print("  %-6s -> %s/%s.png" % (art_id, dest.relative_to(ROOT), code))
        done += 1
    return done


def main() -> int:
    if len(sys.argv) < 2 or sys.argv[1] not in ("goods", "cast"):
        print(__doc__)
        return 2
    n = install_goods() if sys.argv[1] == "goods" else install_cast()
    print("%d asset(s) installed" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
