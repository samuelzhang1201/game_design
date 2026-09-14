#!/usr/bin/env python3
"""Turn a chapter's renders into game assets.

    python3 assets/flux/install_map_art.py goods    # G-xx -> assets/goods/
    python3 assets/flux/install_map_art.py decor    # D-xx -> assets/decor/ (sea ships, whale)
    python3 assets/flux/install_map_art.py estates  # D-32..D-41 -> assets/manors/ (the manors view's estates)
    python3 assets/flux/install_map_art.py ui       # post.py icon tier -> assets/icons/ (resource strip, realm card)
    python3 assets/flux/install_map_art.py cast     # K-xx -> assets/portraits/
    python3 assets/flux/install_map_art.py biomes   # T-xx -> assets/biomes/ (BIOMES LAYER experiment 2026-09-14)
    python3 assets/flux/install_map_art.py paintings  # B-xx -> assets/manors/paint/ (the manor card's painted estate)

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
    return install_marks(codes, "goods", ROOT / "assets" / "goods", height, lighten)


## The sea's decoration (data/sea_art.csv, owner request 2026-09-13): the
## D- renders named in decor_art.csv, cut out, greyed and lightened like the
## goods — the game prints them on the water in sea_ink at map_sea_decor_alpha
## — at 256 px, the mark tier of post.py.
def install_decor(height: int = 256, lighten: float = 0.45) -> int:
    codes = {r["art_id"]: r["key"] for r in csv.DictReader((HERE / "decor_art.csv").open())}
    return install_marks(codes, "decor", ROOT / "assets" / "decor", height, lighten)


## The manors view's estate drawings (owner 2026-09-13): library D-32..D-41,
## one per population tier (data/manor_estates.csv), cut out, greyed and
## lightened like the settlements so the view can tint them with the
## manor's colour. estate_art.csv may name the seed to install; else the
## newest render wins.
def install_estates(height: int = 256, lighten: float = 0.45) -> int:
    rows = list(csv.DictReader((HERE / "estate_art.csv").open()))
    codes = {r["art_id"]: r["key"] for r in rows}
    seeds = {r["art_id"]: r.get("seed", "").strip() for r in rows}
    return install_marks(codes, "decor", ROOT / "assets" / "manors", height, lighten, seeds)


## The interface's dimension icons (data/resource_icons.csv texture column,
## owner 2026-09-13): library I-40 and I-47..I-61, cut out by post.py
## (--tier icon: a coloured still-life needs BiRefNet, not the blue-channel
## key), trimmed and fitted under their dimension's key. They KEEP
## their colour — an icon is looked at, not tinted.
## The strip and the card draw these at 20-24 design px, so the installed file
## is 64 px (24 x the ~3x largest window scale, rounded to a power of two;
## owner 2026-09-13: an installed file is sized by its use). [C-ICON] leaves a
## generous margin and BiRefNet keeps it, so the cut-out is first TRIMMED to
## its alpha box and only then fitted into the square: the subject fills the
## icon instead of floating small in the middle of it.
UI_ICON_PX = 64
UI_ALPHA_MIN = 8


def install_ui() -> int:
    codes = {r["art_id"]: r["key"] for r in csv.DictReader((HERE / "ui_icon_art.csv").open())}
    dest = ROOT / "assets" / "icons"
    dest.mkdir(parents=True, exist_ok=True)
    done = 0
    for art_id, key in sorted(codes.items()):
        # post.py names its cut-outs <ID>_<model>.png; the newest model wins.
        hits = sorted((HERE / "out" / "game" / "icon").glob("%s_*.png" % art_id))
        if not hits:
            print("  (no cut-out for %s / %s — run post.py --tier icon first)" % (art_id, key))
            continue
        w, h, ch, px = decode_png(hits[-1])
        if ch != 4:
            print("  (%s is not RGBA — post.py --tier icon writes a cut-out)" % hits[-1].name)
            continue
        cw, chh, rgba = trim_alpha(w, h, bytearray(px))
        scale = UI_ICON_PX / max(cw, chh)
        tw, th = max(1, round(cw * scale)), max(1, round(chh * scale))
        small = resize_rgba(cw, chh, rgba, tw, th)
        canvas = pad_square(tw, th, small, UI_ICON_PX)
        encode_png(dest / ("%s.png" % key), UI_ICON_PX, UI_ICON_PX, 4, bytes(canvas))
        print("  %-6s %-20s %dx%d in %d" % (art_id, key, tw, th, UI_ICON_PX))
        done += 1
    return done


def trim_alpha(w: int, h: int, px: bytearray) -> tuple[int, int, bytearray]:
    """RGBA cropped to the pixels whose alpha clears UI_ALPHA_MIN."""
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        row = y * w * 4
        for x in range(w):
            if px[row + x * 4 + 3] > UI_ALPHA_MIN:
                x0, y0 = min(x0, x), min(y0, y)
                x1, y1 = max(x1, x), max(y1, y)
    if x1 < 0:
        return w, h, px
    cw, chh = x1 - x0 + 1, y1 - y0 + 1
    out = bytearray(cw * chh * 4)
    for y in range(chh):
        src = ((y0 + y) * w + x0) * 4
        out[y * cw * 4:(y + 1) * cw * 4] = px[src:src + cw * 4]
    return cw, chh, out


def pad_square(w: int, h: int, px: bytearray, side: int) -> bytearray:
    """The image centred on a transparent side x side canvas."""
    out = bytearray(side * side * 4)
    ox, oy = (side - w) // 2, (side - h) // 2
    for y in range(h):
        dst = ((oy + y) * side + ox) * 4
        out[dst:dst + w * 4] = px[y * w * 4:(y + 1) * w * 4]
    return out


def install_marks(codes: dict, chapter: str, dest, height: int, lighten: float, seeds: dict | None = None) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    done = 0
    for art_id, code in sorted(codes.items()):
        hits = sorted((HERE / "out" / chapter).glob("%s_*.png" % art_id))
        seed = (seeds or {}).get(art_id, "")
        if seed:
            hits = [h for h in hits if h.stem.endswith("_s" + seed)] or hits
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


## BIOMES LAYER (experiment 2026-09-14): the ground tiles the default map
## lays over each biome's land (data/biome_art.csv, MapBiomes). Library §5
## T- renders named in biome_art.csv, KEPT IN COLOUR (the layer is a colour
## wash of its own, drawn at map_biome_alpha over the sheet), boxed down to
## BIOME_TILE_PX and made seamless: the render is rolled by half a tile so
## its four edges meet in the middle, and the original is blended back over
## that cross with a feathered band — the classic offset-and-blend — so the
## sheet repeats without a visible seam. The model is asked for a seamless
## tile and never quite delivers one.
## 512 px: a tile spans map_biome_tile_px (128) native px, and the map is
## drawn up to ~4x native, so 512 keeps the crowns sharp at the closest zoom.
BIOME_TILE_PX = 512
BIOME_FEATHER_PX = 96


def make_seamless(w: int, h: int, px: bytearray, feather: int) -> bytearray:
    """RGBA in, RGBA out: rolled by (w/2, h/2), the original blended back
    over the centre cross within `feather` px of it."""
    hx, hy = w // 2, h // 2
    out = bytearray(w * h * 4)
    for y in range(h):
        sy = (y + hy) % h
        dy = abs(y - hy)
        for x in range(w):
            sx = (x + hx) % w
            d = min(abs(x - hx), dy)
            t = min(1.0, d / float(feather)) if feather > 0 else 1.0  # 0 on the cross: the original
            o = (y * w + x) * 4
            r = (sy * w + sx) * 4
            for c in range(4):
                out[o + c] = int(px[o + c] + (px[r + c] - px[o + c]) * t + 0.5)
    return out


def to_rgba(w: int, h: int, ch: int, px: bytearray) -> bytearray:
    if ch == 4:
        return bytearray(px)
    out = bytearray(w * h * 4)
    for i in range(w * h):
        out[i * 4:i * 4 + 3] = px[i * 3:i * 3 + 3]
        out[i * 4 + 3] = 255
    return out


def install_biomes(size: int = BIOME_TILE_PX, feather: int = BIOME_FEATHER_PX) -> int:
    rows = list(csv.DictReader((HERE / "biome_art.csv").open()))
    dest = ROOT / "assets" / "biomes"
    dest.mkdir(parents=True, exist_ok=True)
    done = 0
    for row in sorted(rows, key=lambda r: r["art_id"]):
        art_id, code, seed = row["art_id"], row["key"], row.get("seed", "").strip()
        hits = sorted((HERE / "out" / "terrain").glob("%s_*.png" % art_id))
        if seed:
            hits = [h for h in hits if h.stem.endswith("_s" + seed)] or hits
        if not hits:
            print("  (no render for %s / %s)" % (art_id, code))
            continue
        w, h, ch, px = decode_png(hits[-1])
        small = resize_rgba(w, h, to_rgba(w, h, ch, px), size, size)
        tile = make_seamless(size, size, small, feather)
        encode_png(dest / ("%s.png" % code), size, size, 4, bytes(tile))
        print("  %-6s %-12s %dx%d seamless" % (art_id, code, size, size))
        done += 1
    return done


## The manor card's painted estates (owner 2026-09-14): library B-01..B-36
## (estate_paint_art.csv; key = the estate's focus_tier, the same key as its
## map drawing), KEPT IN COLOUR — a painting is looked at, not tinted — and
## NOT cut out: the vignette fades into its own cream paper, which the card
## shows as it is. Sized by use (owner 2026-09-13): the card cover-crops it
## into about 216 x 190 design px, drawn at up to ~3x on the largest window,
## so the 1280 x 1024 render is boxed down to 720 x 576 — the same 5:4.
PAINT_SIZE = (720, 576)
## The vignette leaves wide cream paper round the scene, and the card is a
## small box: the render is first cropped to the SCENE — every pixel that is
## not the paper, the paper's colour measured in the four corners — padded by
## PAINT_PAD of its size and widened to 5:4 inside the render, so the holding
## fills the card instead of floating small in its margins (2026-09-14, the
## first pilot put the scene in the middle two thirds).
PAINT_PAD = 0.04
PAINT_PAPER_TOL = 26


def scene_box(w: int, h: int, px: bytearray, aspect: float) -> tuple:
    """The crop (x0, y0, x1, y1) that holds everything not paper, padded and
    widened to `aspect`, clamped to the image."""
    corners = [(4, 4), (w - 5, 4), (4, h - 5), (w - 5, h - 5)]
    ref = [sum(px[(y * w + x) * 4 + c] for x, y in corners) // 4 for c in range(3)]
    x0, y0, x1, y1 = w, h, -1, -1
    step = 2
    for y in range(0, h, step):
        base = y * w * 4
        for x in range(0, w, step):
            i = base + x * 4
            d = abs(px[i] - ref[0]) + abs(px[i + 1] - ref[1]) + abs(px[i + 2] - ref[2])
            if d > PAINT_PAPER_TOL:
                if x < x0: x0 = x
                if x > x1: x1 = x
                if y < y0: y0 = y
                if y > y1: y1 = y
    if x1 < 0:
        return 0, 0, w, h
    pad_x = int((x1 - x0) * PAINT_PAD)
    pad_y = int((y1 - y0) * PAINT_PAD)
    x0, y0, x1, y1 = max(0, x0 - pad_x), max(0, y0 - pad_y), min(w, x1 + pad_x), min(h, y1 + pad_y)
    bw, bh = x1 - x0, y1 - y0
    if bw / bh < aspect:
        grow = int(bh * aspect) - bw
        x0, x1 = x0 - grow // 2, x1 + grow - grow // 2
    else:
        grow = int(bw / aspect) - bh
        y0, y1 = y0 - grow // 2, y1 + grow - grow // 2
    # Slide back inside the render; if the box outgrew it, take the render.
    if x0 < 0: x1, x0 = x1 - x0, 0
    if x1 > w: x0, x1 = max(0, x0 - (x1 - w)), w
    if y0 < 0: y1, y0 = y1 - y0, 0
    if y1 > h: y0, y1 = max(0, y0 - (y1 - h)), h
    return x0, y0, x1, y1


def crop_rgba(w: int, px: bytearray, box: tuple) -> tuple:
    x0, y0, x1, y1 = box
    cw, chh = x1 - x0, y1 - y0
    out = bytearray(cw * chh * 4)
    for y in range(chh):
        src = ((y0 + y) * w + x0) * 4
        out[y * cw * 4:(y + 1) * cw * 4] = px[src:src + cw * 4]
    return cw, chh, out


def install_paintings(size: tuple = PAINT_SIZE) -> int:
    rows = list(csv.DictReader((HERE / "estate_paint_art.csv").open(encoding="utf-8")))
    dest = ROOT / "assets" / "manors" / "paint"
    dest.mkdir(parents=True, exist_ok=True)
    done = 0
    for r in rows:
        art_id, key, seed = r["art_id"], r["key"], r.get("seed", "").strip()
        hits = sorted((HERE / "out" / "estates").glob("%s_*.png" % art_id))
        if seed:
            hits = [h for h in hits if h.stem.endswith("_s" + seed)] or hits
        if not hits:
            print("  (no render for %s / %s)" % (art_id, key))
            continue
        w, h, ch, px = decode_png(hits[-1])
        rgba = to_rgba(w, h, ch, bytearray(px))
        tw, th = size
        box = scene_box(w, h, rgba, tw / th)
        cw, chh, scene = crop_rgba(w, rgba, box)
        small = resize_rgba(cw, chh, scene, tw, th)
        encode_png(dest / ("%s.png" % key), tw, th, 4, bytes(small))
        print("  %-6s %-10s %dx%d" % (art_id, key, tw, th))
        done += 1
    return done


## The map's compass (owner 2026-09-14): library I-73 cut out by post.py
## --tier icon, trimmed to its alpha box and fitted into COMPASS_PX — drawn
## at map_compass_size_px (88 design px) x ~3 on the largest window, so 256.
## COMPASS_SEED picks the variant; the newest cut-out wins when it is empty.
COMPASS_PX = 256
COMPASS_SEED = ""


def install_compass(size: int = COMPASS_PX) -> int:
    hits = sorted((HERE / "out" / "game" / "icon").glob("I-73_*.png"))
    if COMPASS_SEED:
        hits = [h for h in hits if COMPASS_SEED in h.stem] or hits
    if not hits:
        print("  (no cut-out for I-73 — run post.py --tier icon first)")
        return 0
    w, h, ch, px = decode_png(hits[-1])
    if ch != 4:
        print("  (%s is not RGBA)" % hits[-1].name)
        return 0
    cw, chh, rgba = trim_alpha(w, h, bytearray(px))
    scale = size / max(cw, chh)
    tw, th = max(1, round(cw * scale)), max(1, round(chh * scale))
    small = resize_rgba(cw, chh, rgba, tw, th)
    canvas = pad_square(tw, th, small, size)
    dest = ROOT / "assets" / "ui"
    dest.mkdir(parents=True, exist_ok=True)
    encode_png(dest / "compass.png", size, size, 4, bytes(canvas))
    print("  I-73   compass  %dx%d in %d (from %s)" % (tw, th, size, hits[-1].name))
    return 1


def main() -> int:
    chapters = {"goods": install_goods, "decor": install_decor, "cast": install_cast,
                "ui": install_ui, "estates": install_estates, "biomes": install_biomes,
                "paintings": install_paintings, "compass": install_compass}
    if len(sys.argv) < 2 or sys.argv[1] not in chapters:
        print(__doc__)
        return 2
    n = chapters[sys.argv[1]]()
    print("%d asset(s) installed" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
