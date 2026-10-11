#!/usr/bin/env python3
"""Turn a chapter's renders into game assets.

    python3 assets/imagegen/install_map_art.py goods    # G-xx -> assets/2D/goods/marks/
    python3 assets/imagegen/install_map_art.py ui       # post.py icon tier -> assets/2D/icons/resources/ (resource strip, realm card)
    python3 assets/imagegen/install_map_art.py cast     # K-xx -> assets/2D/portraits/cast/
    python3 assets/imagegen/install_map_art.py paintings  # B-xx -> assets/2D/paintings/estates/ (the manor card's painted estate)
    python3 assets/imagegen/install_map_art.py buildings  # H-xx -> assets/2D/icons/buildings/bld_<code>.png (slots and the build menu)
    python3 assets/imagegen/install_map_art.py goods_icons  # G-xx colour -> assets/2D/icons/goods/ (the manor card's output rows)
    python3 assets/imagegen/install_map_art.py compass    # I-73 -> assets/2D/ui/compass/compass.png
    python3 assets/imagegen/install_map_art.py arms       # A-xxx -> assets/2D/arms/<pack>/<key>.png (ARMS_PACK=id, default maps.csv) (house and kingdom arms)
    python3 assets/imagegen/install_map_art.py army_paintings  # B-37..42 -> assets/2D/paintings/armies/<piece>.png (army card)
    python3 assets/imagegen/install_map_art.py app_icon   # X-01 -> icon.png (the game's application icon)
    python3 assets/imagegen/install_map_art.py events     # V-35..V-56 (event_art.csv) -> assets/2D/events/illustrations/<event_id>.png (the audience window's event band)
    python3 assets/imagegen/install_map_art.py courier_paintings  # B-43..47 -> assets/2D/paintings/couriers/<key>.png (courier card, the desk's receipt)
    python3 assets/imagegen/install_map_art.py missive  # U-20..26 -> assets/2D/ui/missive_board/<key>.png (the Missive board)

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
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from packs import default_pack  # noqa: E402
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
    return install_marks(codes, "goods", ROOT / "assets" / "2D" / "goods" / "marks", height, lighten)


UI_ICON_PX = 64
UI_ALPHA_MIN = 8


def install_ui() -> int:
    codes = {r["art_id"]: r["key"] for r in csv.DictReader((HERE / "ui_icon_art.csv").open())}
    dest = ROOT / "assets" / "2D" / "icons" / "resources"
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


def install_war_tools() -> int:
    """The WAR ROOM's tool roll glyphs and the resolutions' rolled scroll
    (library W-61..W-68, U-61; prompts in war_tool_prompts.csv): post.py
    --tier icon cut-outs installed by assets/imagegen/war_tool_install.csv
    (art_id, key, px, square) into assets/2D/war_room/tools/<key>.png, the
    ArtTable war_tool_art.tres there mapping each key. Sizes follow the use
    (asset-resolution-per-use): a slot glyph is 36 of a 44 design px slot x
    ~3 window scale -> 128 square; the rolled scroll fills a 115 x 72 design
    px button x 3 -> 384 wide, its aspect kept (square 0)."""
    dest = ROOT / "assets" / "2D" / "war_room" / "tools"
    dest.mkdir(parents=True, exist_ok=True)
    # WAR_TOOLS_CUTOUTS names another folder of cut-outs (a candidate set
    # shot for the visual review) instead of out/game/icon.
    src = Path(os.environ.get("WAR_TOOLS_CUTOUTS", str(HERE / "out" / "game" / "icon")))
    done = 0
    for r in csv.DictReader((HERE / "war_tool_install.csv").open()):
        art_id, key, px, square = r["art_id"], r["key"], int(r["px"]), r["square"] == "1"
        hits = sorted(src.glob("%s*.png" % art_id))
        if not hits:
            print("  (no cut-out for %s / %s — run post.py --tier icon first)" % (art_id, key))
            continue
        w, h, ch, pxs = decode_png(hits[-1])
        if ch != 4:
            print("  (%s is not RGBA — post.py --tier icon writes a cut-out)" % hits[-1].name)
            continue
        cw, chh, rgba = trim_alpha(w, h, bytearray(pxs))
        scale = px / max(cw, chh)
        tw, th = max(1, round(cw * scale)), max(1, round(chh * scale))
        small = resize_rgba(cw, chh, rgba, tw, th)
        if square:
            encode_png(dest / ("%s.png" % key), px, px, 4, bytes(pad_square(tw, th, small, px)))
        else:
            encode_png(dest / ("%s.png" % key), tw, th, 4, bytes(small))
        print("  %-6s %-10s %dx%d%s" % (art_id, key, tw, th, " in %d" % px if square else ""))
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


def pad_to_aspect(w: int, h: int, px: bytearray, aspect: float) -> tuple[int, int, bytearray]:
    """The image centred on a transparent canvas sized to `aspect` (target
    width / height) — the smallest canvas of that aspect that still holds
    w x h. Fix round 1: `install_missive`'s cut path (the envelope, 384x288)
    was padding to a SQUARE (`pad_square`) before resizing to a non-square
    target, composing two different aspect changes and stretching the
    result; this pads toward the target's OWN aspect first, so the later
    resize is a uniform scale. `pad_square` itself is unchanged — a square
    target (`aspect == 1.0`, e.g. the 48x48 pin) produces the same canvas."""
    if w / h > aspect:
        cw, chh = w, max(1, round(w / aspect))
    else:
        chh = h
        cw = max(1, round(h * aspect))
    out = bytearray(cw * chh * 4)
    ox, oy = (cw - w) // 2, (chh - h) // 2
    for y in range(h):
        dst = ((oy + y) * cw + ox) * 4
        out[dst:dst + w * 4] = px[y * w * 4:(y + 1) * w * 4]
    return cw, chh, out


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
    ("c-bust", "chip", 96, "assets/2D/portraits/cast"),
    # 1024 rather than the tier's own 660: the conversation stage
    # cover-crops this into a box that is a few hundred DESIGN px tall, and
    # the design viewport is 1280x720 now — the source has to stay above the
    # drawn size or the face is being upscaled.
    ("c-full", "full", 1024, "assets/2D/portraits/cast/full"),
]


def install_cast() -> int:
    rows = list(csv.DictReader((HERE / "cast_art.csv").open()))
    codes = {r["art_id"]: r["character_id"] for r in rows}
    seeds = {r["art_id"]: r.get("seed", "").strip() for r in rows}
    done = 0
    for tag, tier, size, out_dir in CAST_TIERS:
        print("-- %s tier" % tier)
        done += _install_cast_tier(codes, tag, tier, size, ROOT / out_dir, seeds)
    return done


def _install_cast_tier(codes: dict, tag: str, tier: str, size: int, dest: Path,
                       seeds: dict | None = None) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    staged = HERE / "out" / "game" / tier
    done = 0
    for art_id, code in sorted(codes.items()):
        hits = sorted((HERE / "out" / "cast").glob("%s_*%s*.png" % (art_id, tag)))
        hits = _pick(hits, (seeds or {}).get(art_id, ""))
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


def to_rgba(w: int, h: int, ch: int, px: bytearray) -> bytearray:
    if ch == 4:
        return bytearray(px)
    out = bytearray(w * h * 4)
    for i in range(w * h):
        out[i * 4:i * 4 + 3] = px[i * 3:i * 3 + 3]
        out[i * 4 + 3] = 255
    return out


PAINT_SIZE = (720, 576)
## The vignette leaves wide cream paper round the scene, and the card is a
## small box: the render is first cropped to the SCENE — every pixel that is
## not the paper, the paper's colour measured in the four corners — padded by
## PAINT_PAD of its size and widened to 5:4 inside the render, so the holding
## fills the card instead of floating small in its margins (2026-09-14, the
## first pilot put the scene in the middle two thirds).
PAINT_PAD = 0.04
PAINT_PAPER_TOL = 26


def _paper(px: bytearray, i: int) -> bool:
    """A cream-paper pixel: bright, warm (red over blue), even where the
    paper is vignetted darker toward the corners. A sky is blue or grey."""
    r, g, b = px[i], px[i + 1], px[i + 2]
    return r >= 200 and g >= 185 and 15 <= r - b <= 75 and r >= g >= b


def paper_margins(w: int, h: int, px: bytearray, share: float = 0.9) -> tuple:
    """(x0, y0, x1, y1) inside the rows and columns at the edges that are at
    least `share` paper, for a picture drawn full-bleed with a paper margin."""
    step = 4
    def row_paper(y: int) -> bool:
        n = sum(_paper(px, (y * w + x) * 4) for x in range(0, w, step))
        return n >= share * len(range(0, w, step))
    def col_paper(x: int) -> bool:
        n = sum(_paper(px, (y * w + x) * 4) for y in range(0, h, step))
        return n >= share * len(range(0, h, step))
    y0, y1, x0, x1 = 0, h, 0, w
    while y0 < h // 3 and row_paper(y0): y0 += 1
    while y1 > h - h // 3 and row_paper(y1 - 1): y1 -= 1
    while x0 < w // 3 and col_paper(x0): x0 += 1
    while x1 > w - w // 3 and col_paper(x1 - 1): x1 -= 1
    return x0, y0, x1, y1


def scene_box(w: int, h: int, px: bytearray, aspect: float, cover: bool = False) -> tuple:
    """The crop (x0, y0, x1, y1) that holds everything not paper, padded and
    widened to `aspect`, clamped to the image. With `cover` the box is cut
    INTO the scene instead — no pad, the longer side trimmed to `aspect` —
    so a full-bleed picture drawn with a paper margin loses the margin."""
    if cover:
        # Step inside the paper margin (and a few px past its soft edge),
        # then trim the longer side to `aspect`.
        x0, y0, x1, y1 = paper_margins(w, h, px)
        if (x0, y0, x1, y1) != (0, 0, w, h):
            x0, y0, x1, y1 = x0 + 6, y0 + 6, x1 - 6, y1 - 6
        bw, bh = x1 - x0, y1 - y0
        if bw / bh > aspect:
            cut = bw - int(bh * aspect)
            return x0 + cut // 2, y0, x1 - (cut - cut // 2), y1
        cut = bh - int(bw / aspect)
        return x0, y0 + cut // 2, x1, y1 - (cut - cut // 2)
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


def alpha_box(w: int, h: int, rgba: bytearray) -> tuple:
    """The (x0, y0, x1, y1) box of every pixel with any alpha: the piece a
    flood of its ground left standing (flood_ground)."""
    x0, y0, x1, y1 = w, h, -1, -1
    for y in range(h):
        row = y * w * 4
        for x in range(w):
            if rgba[row + x * 4 + 3]:
                if x < x0: x0 = x
                if x > x1: x1 = x
                if y < y0: y0 = y
                if y > y1: y1 = y
    return (0, 0, w, h) if x1 < 0 else (x0, y0, x1 + 1, y1 + 1)


def trim_box(box: tuple, trim: str) -> tuple:
    """A render's crop narrowed by a table's `trim` cell, "left|top|right|bottom"
    in source px: what the ground floods left behind that is still ground (the
    plaque's lit strip under its edge); empty keeps the box."""
    if not trim.strip():
        return box
    l, t, r, b = (int(v) for v in trim.split("|"))
    x0, y0, x1, y1 = box
    if x1 - x0 <= l + r or y1 - y0 <= t + b:
        return box
    return x0 + l, y0 + t, x1 - r, y1 - b


def guarded_intersection(a: tuple, b: tuple, w: int, h: int, label: str = "") -> tuple:
    """The intersection of two (x0, y0, x1, y1) boxes (install_missive's two
    independent ground floods). `alpha_box` degrades to the whole w x h
    canvas when ITS OWN flood ate everything, but nothing guaranteed the two
    boxes actually overlap — a future render where the shadow-aware flood
    and the gradient-grow flood disagree enough would hand crop_rgba a
    negative-size box (`bytearray(cw * chh * 4)` with cw or chh < 0), which
    raises and aborts the whole batch mid-loop (board art fix round finding
    #2). Falls back to `a` alone, then to the full canvas if `a` is itself
    degenerate, printing a warning instead of crashing."""
    box = (max(a[0], b[0]), max(a[1], b[1]), min(a[2], b[2]), min(a[3], b[3]))
    if box[2] <= box[0] or box[3] <= box[1]:
        tag = (" for " + label) if label else ""
        print("  (WARNING%s: the two ground floods do not overlap; using the shadow-flood box alone)" % tag)
        box = a
        if box[2] <= box[0] or box[3] <= box[1]:
            print("  (WARNING%s: the shadow-flood box is empty too; using the whole render)" % tag)
            box = (0, 0, w, h)
    return box


def crop_rgba(w: int, px: bytearray, box: tuple) -> tuple:
    x0, y0, x1, y1 = box
    cw, chh = x1 - x0, y1 - y0
    out = bytearray(cw * chh * 4)
    for y in range(chh):
        src = ((y0 + y) * w + x0) * 4
        out[y * cw * 4:(y + 1) * cw * 4] = px[src:src + cw * 4]
    return cw, chh, out


def _pick(hits: list, seed: str) -> list:
    """The renders a table's `seed` cell picks: `<model>_s<seed>` (the stem's
    own suffix) or a bare seed number as before; all of them when empty."""
    if not seed:
        return hits
    suffix = "_" + seed if "_" in seed else "_s" + seed
    return [h for h in hits if h.stem.endswith(suffix)] or hits


def install_paintings(size: tuple = PAINT_SIZE, table: str = "estate_paint_art.csv",
                      dest: Path | None = None, key_column: str = "key",
                      src: str = "estates", cover: bool = False) -> int:
    rows = list(csv.DictReader((HERE / table).open(encoding="utf-8")))
    dest = dest or ROOT / "assets" / "2D" / "paintings" / "estates"
    dest.mkdir(parents=True, exist_ok=True)
    done = 0
    for r in rows:
        art_id, key, seed = r["art_id"], r[key_column], r.get("seed", "").strip()
        hits = sorted((HERE / "out" / src).glob("%s_*.png" % art_id))
        hits = _pick(hits, seed)
        if not hits:
            print("  (no render for %s / %s)" % (art_id, key))
            continue
        w, h, ch, px = decode_png(hits[-1])
        rgba = to_rgba(w, h, ch, bytearray(px))
        tw, th = size
        box = scene_box(w, h, rgba, tw / th, cover)
        cw, chh, scene = crop_rgba(w, rgba, box)
        small = resize_rgba(cw, chh, scene, tw, th)
        encode_png(dest / ("%s.png" % key), tw, th, 4, bytes(small))
        print("  %-6s %-10s %dx%d" % (art_id, key, tw, th))
        done += 1
    return done


## The audience window's event band (chapter 0, 2026-09-21): library
## V-35..V-56 on the wide [C-EVENT] canvas, mapped to an event_id by
## event_art.csv. Drawn across the top of the 760-design-px audience window,
## so EVENT_SIZE is that band at roughly 1.8x — the art is a painting, not a
## crisp icon, and the render is only 1536 wide to begin with. They keep
## their colour, like the portraits: an illustration is looked at, not tinted.
EVENT_SIZE = (1280, 533)


def install_events(size: tuple = EVENT_SIZE) -> int:
    return install_paintings(size, "event_art.csv", ROOT / "assets" / "2D" / "events" / "illustrations",
                             key_column="event_id", src="events", cover=True)


## The army card's painting (owner 2026-09-15): library B-37..B-42 on the
## same [C-ESTATE] vignette and the same card box as the manor paintings, so
## the same crop and size, into assets/2D/paintings/armies/<piece>.png.
def install_army_paintings(size: tuple = PAINT_SIZE) -> int:
    return install_paintings(size, "army_paint_art.csv", ROOT / "assets" / "2D" / "paintings" / "armies")


## The courier card's paintings and the desk's receipt painting (owner
## 2026-09-28, spec 2026-09-28-courier-art §4): library B-43..B-47 on the
## [C-COURIER] 5:4 vignette, drawn in the same 240-px column box as the manor
## and army paintings, so the same crop and size.
def install_courier_paintings(size: tuple = PAINT_SIZE) -> int:
    return install_paintings(size, "courier_paint_art.csv", ROOT / "assets" / "2D" / "paintings" / "couriers")


## The Missive board's pieces (owner 2026-09-28, spec 2026-09-28-courier-art
## §5): library U-20..U-26, each sized by its USE (library §9.1). The nine-slice
## pieces are cropped to the piece off its grey ground and resized; the
## envelope and the pin are cut out to alpha (the ground flooded from the edges,
## as the arms are) and fitted. Writes assets/2D/ui/missive_board/<key>.png and fills
## data/missive_art.csv's texture column.
def install_missive() -> int:
    rows = list(csv.DictReader((HERE / "missive_art_install.csv").open(encoding="utf-8")))
    dest = ROOT / "assets" / "2D" / "ui" / "missive_board"
    dest.mkdir(parents=True, exist_ok=True)
    installed = {}
    for r in rows:
        art_id, key, seed = r["art_id"], r["key"], r.get("seed", "").strip()
        if seed == "-":  # not picked yet: keep the flat stand-in rather than any render
            print("  (%s / %s not picked yet)" % (art_id, key))
            continue
        hits = _pick(sorted((HERE / "out" / "ui").glob("%s_*.png" % art_id)), seed)
        if not hits:
            print("  (no render for %s / %s)" % (art_id, key))
            continue
        w, h, ch, px = decode_png(hits[-1])
        tw, th = int(r["width"]), int(r["height"])
        if r["cut"] == "1":
            rgba = flood_ground(w, h, ch, px)
            cw, chh, cut = trim_alpha(w, h, rgba)
            # fix round 1: pad toward the TARGET's own aspect (not a square)
            # so the resize below is a uniform scale — a square target (the
            # pin) behaves exactly as pad_square did.
            pw, ph, padded = pad_to_aspect(cw, chh, cut, tw / th)
            small = resize_rgba(pw, ph, padded, tw, th)
        else:
            # a nine-slice piece stands on a grey ground: crop TIGHT to the
            # piece (the box its ground's flood leaves), not scene_box's padded
            # scene, or the ground shows around every stretched edge; the
            # piece keeps its own opaque pixels
            rgba = to_rgba(w, h, ch, bytearray(px))
            # two floods, each blind to one ground: a SHADOW (the ground's
            # colour, darker) and a GRADIENT (the ground lightening toward
            # the floor, step by small step); the piece is what both leave
            a = alpha_box(w, h, flood_ground(w, h, ch, px, shadows=True))
            b = alpha_box(w, h, grow_ground(w, h, ch, px))
            box = guarded_intersection(a, b, w, h, "%s / %s" % (art_id, key))
            box = trim_box(box, r.get("trim", ""))
            cw, chh, piece = crop_rgba(w, rgba, box)
            small = resize_rgba(cw, chh, piece, tw, th)
        encode_png(dest / ("%s.png" % key), tw, th, 4, bytes(small))
        installed[key] = "res://assets/2D/ui/missive_board/%s.png" % key
        print("  %-6s %-9s %dx%d" % (art_id, key, tw, th))
    table = ROOT / "data" / "missive_art.csv"
    lines = list(csv.DictReader(table.open(encoding="utf-8")))
    for line in lines:
        if line["key"] in installed:
            line["texture"] = installed[line["key"]]
    with table.open("w", newline="", encoding="utf-8") as f:
        # lineterminator="\n": csv.DictWriter defaults to "\r\n", which put
        # CRLF into a working copy the rest of the repo keeps at LF (git then
        # warns "CRLF will be replaced by LF" on every subsequent touch).
        wr = csv.DictWriter(f, fieldnames=list(lines[0].keys()), lineterminator="\n")
        wr.writeheader(); wr.writerows(lines)
    return len(installed)


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
    dest = ROOT / "assets" / "2D" / "ui" / "compass"
    dest.mkdir(parents=True, exist_ok=True)
    encode_png(dest / "compass.png", size, size, 4, bytes(canvas))
    print("  I-73   compass  %dx%d in %d (from %s)" % (tw, th, size, hits[-1].name))
    return 1


## Cut-outs made by post.py --tier icon, trimmed to their alpha box and
## fitted into a `size` square, one per row of a mapping: the building icons
## and the card's colour goods icons (owner 2026-09-14, the painting style).
def _install_icon_cutouts(codes: dict, dest: Path, name: str, size: int) -> int:
    dest.mkdir(parents=True, exist_ok=True)
    done = 0
    for art_id, code in sorted(codes.items()):
        hits = sorted((HERE / "out" / "game" / "icon").glob("%s_*.png" % art_id))
        if not hits:
            print("  (no cut-out for %s / %s — run post.py --tier icon first)" % (art_id, code))
            continue
        w, h, ch, px = decode_png(hits[-1])
        if ch != 4:
            print("  (%s is not RGBA)" % hits[-1].name)
            continue
        cw, chh, rgba = trim_alpha(w, h, bytearray(px))
        scale = size / max(cw, chh)
        tw, th = max(1, round(cw * scale)), max(1, round(chh * scale))
        small = resize_rgba(cw, chh, rgba, tw, th)
        canvas = pad_square(tw, th, small, size)
        encode_png(dest / (name % code), size, size, 4, bytes(canvas))
        print("  %-6s %-22s %dx%d in %d" % (art_id, code, tw, th, size))
        done += 1
    return done


## Building icons (library §6.12 H-): drawn in a 34-design-px slot box and a
## 20-px menu entry, so 34 x ~3 on the largest window -> 128 px.
BUILDING_ICON_PX = 128


def install_buildings(size: int = BUILDING_ICON_PX) -> int:
    codes = {r["art_id"]: r["building_code"] for r in csv.DictReader((HERE / "building_art.csv").open(encoding="utf-8"))}
    return _install_icon_cutouts(codes, ROOT / "assets" / "2D" / "icons" / "buildings", "bld_%s.png", size)


## The card's colour goods icons (library G- rendered on [C-ICON] in the v2
## colour style): drawn at 20 design px, so 64 px like the dimension icons.
GOODS_ICON_PX = 64


def install_goods_icons(size: int = GOODS_ICON_PX) -> int:
    codes = {r["art_id"]: r["good_code"] for r in csv.DictReader((HERE / "goods_art.csv").open(encoding="utf-8"))}
    return _install_icon_cutouts(codes, ROOT / "assets" / "2D" / "icons" / "goods", "%s.png", size)


## House and kingdom arms (A-, owner 2026-09-15; arms_prompts.py, arms_art.csv).
## Cut out LOCALLY: [C-ARMS] asks for a plain ground and every shield is
## closed by its rim, so flooding the ground in from the render's edges stops
## at the rim and a silver field inside survives — no BiRefNet queue. The
## pixels touching the flood fade by how far they are from the ground colour,
## so the rim keeps a soft edge. Trimmed to the shield and fitted into ARMS_PX:
## the largest use is the main menu's preview, 88 design px x ~3 on the
## largest window -> 256. ARMS_STYLE is the style tag of the renders to take
## (generate.py names them ..._<style>_r640_...); ARMS_SEEDS picks a re-rolled
## seed per art id, else the newest render wins.
ARMS_PX = 256
ARMS_STYLE = "arms_matte"  # owner 2026-09-15, after sampling arms / arms_painted / arms_matte
ARMS_GROUND_TOLERANCE = 40
ARMS_SEEDS: dict = {"A-084": "954159498", "A-107": "954159498"}  # re-rolled 2026-09-15: a banner read as a field, a bordure did not show


def grow_ground(w: int, h: int, ch: int, px: bytes, step: int = 6, cap: int = 110) -> bytearray:
    """RGBA with the ground grown in from the edges pixel by pixel — each step
    within `step` of the pixel it grows from and within `cap` of the corners'
    colour — made clear: follows a ground that shades smoothly (a studio
    floor), stops at a piece's crisp edge."""
    rgba = to_rgba(w, h, ch, bytearray(px))
    corners = (0, w - 1, (h - 1) * w, h * w - 1)
    ground = [sum(rgba[i * 4 + c] for i in corners) // 4 for c in range(3)]
    seen = bytearray(w * h)
    stack = []
    for i in list(range(w)) + list(range((h - 1) * w, h * w)) + list(range(0, h * w, w)) + list(range(w - 1, h * w, w)):
        if not seen[i]:
            seen[i] = 1
            stack.append(i)
    while stack:
        i = stack.pop()
        x, y = i % w, i // w
        for n, ok in ((i - 1, x > 0), (i + 1, x < w - 1), (i - w, y > 0), (i + w, y < h - 1)):
            if ok and not seen[n] \
                    and max(abs(rgba[i * 4 + c] - rgba[n * 4 + c]) for c in range(3)) <= step \
                    and max(abs(rgba[n * 4 + c] - ground[c]) for c in range(3)) <= cap:
                seen[n] = 1
                stack.append(n)
    for i in range(w * h):
        if seen[i]:
            rgba[i * 4 + 3] = 0
    return rgba


def flood_ground(w: int, h: int, ch: int, px: bytes, tolerance: int = ARMS_GROUND_TOLERANCE,
                 shadows: bool = False) -> bytearray:
    """RGBA with the render's plain ground, flooded in from the edges, made clear.
    `shadows`: a pixel that is the ground's own colour only DARKER (a cast shadow
    on it) counts as ground too — the Missive board's pieces stand on a ground
    they shade, and a nine-slice must not keep that shadow as its edge."""
    rgba = to_rgba(w, h, ch, bytearray(px))
    corners = (0, w - 1, (h - 1) * w, h * w - 1)
    ground = [sum(rgba[i * 4 + c] for i in corners) // 4 for c in range(3)]
    ground_sum = max(1, sum(ground))

    def distance(i: int) -> int:
        o = i * 4
        d = max(abs(rgba[o] - ground[0]), abs(rgba[o + 1] - ground[1]), abs(rgba[o + 2] - ground[2]))
        if shadows:
            k = ground_sum / max(1, rgba[o] + rgba[o + 1] + rgba[o + 2])
            if 1.0 < k <= 4.0:
                d = min(d, int(max(abs(rgba[o + c] * k - ground[c]) for c in range(3))))
        return d

    seen = bytearray(w * h)
    stack = []
    for i in list(range(w)) + list(range((h - 1) * w, h * w)) + list(range(0, h * w, w)) + list(range(w - 1, h * w, w)):
        if not seen[i] and distance(i) <= tolerance:
            seen[i] = 1
            stack.append(i)
    while stack:
        i = stack.pop()
        rgba[i * 4 + 3] = 0
        x, y = i % w, i // w
        for n, ok in ((i - 1, x > 0), (i + 1, x < w - 1), (i - w, y > 0), (i + w, y < h - 1)):
            if ok and not seen[n] and distance(n) <= tolerance:
                seen[n] = 1
                stack.append(n)
    for i in range(w * h):
        if seen[i]:
            continue
        x, y = i % w, i // w
        if (x > 0 and seen[i - 1]) or (x < w - 1 and seen[i + 1]) or (y > 0 and seen[i - w]) or (y < h - 1 and seen[i + w]):
            rgba[i * 4 + 3] = min(255, distance(i) * 255 // (tolerance * 3))
    return rgba


def install_arms(size: int = ARMS_PX) -> int:
    """Into assets/2D/arms/<pack>/: the pack is ARMS_PACK in the environment,
    else data/maps.csv's default."""
    rows = list(csv.DictReader((HERE / "arms_art.csv").open(encoding="utf-8")))
    dest = ROOT / "assets" / "2D" / "arms" / (os.environ.get("ARMS_PACK", "") or default_pack())
    dest.mkdir(parents=True, exist_ok=True)
    done = 0
    for r in rows:
        art_id, key = r["art_id"], r["key"]
        hits = sorted((HERE / "out" / "arms").glob("%s_*_%s_r*.png" % (art_id, ARMS_STYLE)),
                      key=lambda p: p.stat().st_mtime)
        seed = ARMS_SEEDS.get(art_id, "")
        if seed:
            hits = [h for h in hits if h.stem.endswith("_s" + seed)] or hits
        if not hits:
            print("  (no %s render for %s / %s)" % (ARMS_STYLE, art_id, key))
            continue
        w, h, ch, px = decode_png(hits[-1])
        cw, chh, rgba = trim_alpha(w, h, flood_ground(w, h, ch, px))
        scale = size / max(cw, chh)
        tw, th = max(1, round(cw * scale)), max(1, round(chh * scale))
        canvas = pad_square(tw, th, resize_rgba(cw, chh, rgba, tw, th), size)
        encode_png(dest / ("%s.png" % key), size, size, 4, bytes(canvas))
        print("  %-6s %-24s %dx%d in %d (from %s)" % (art_id, key, tw, th, size, hits[-1].name))
        done += 1
    return done


## The game's application icon (owner 2026-09-18): X-01, a full-bleed square,
## installed as the project's config/icon. Its largest use is the macOS app
## bundle's icns (512 pt @2x = 1024 px); the window, taskbar and Windows ico
## (256 px) are made from it by the export, so it keeps the render's 1024.
## APP_ICON_SEED picks the chosen seed among the variants.
APP_ICON_PX = 1024
APP_ICON_SEED = "954159499"  # owner 2026-09-18: of four seeds, the one that reads at 16 px


## The title screen's frame (owner 2026-09-30): library U-27 on the 16:9
## [C-TITLE] canvas, drawn full-bleed behind the main menu at the render's own
## 1792x1008 (the menu dims it by menu_page.gdshader). TITLE_SEED picks the
## render as `<model>_s<seed>`.
TITLE_SEED = "qwen2512fast_s954159497"


def install_title(seed: str = TITLE_SEED) -> int:
    hits = _pick(sorted((HERE / "out" / "ui").glob("U-27_*.png")), seed)
    if not hits:
        print("  (no U-27 render)")
        return 0
    w, h, ch, px = decode_png(hits[-1])
    dest = ROOT / "assets" / "2D" / "ui" / "panels" / "frame.png"
    encode_png(dest, w, h, ch, bytes(px))
    print("  U-27   %s -> %s %dx%d" % (hits[-1].name, dest.relative_to(ROOT), w, h))
    return 1


def install_app_icon(size: int = APP_ICON_PX) -> int:
    hits = sorted((HERE / "out" / "app_icon").glob("X-01_*.png"), key=lambda p: p.stat().st_mtime)
    if APP_ICON_SEED:
        hits = [h for h in hits if ("_s%s" % APP_ICON_SEED) in h.stem] or hits
    if not hits:
        print("  (no X-01 render — run generate.py --prompts-file app_icon_prompts.csv first)")
        return 0
    w, h, ch, px = decode_png(hits[-1])
    rgba = to_rgba(w, h, ch, bytearray(px))
    for i in range(3, len(rgba), 4):
        rgba[i] = 255  # full-bleed: an app icon has no see-through corners of its own
    if (w, h) != (size, size):
        rgba = resize_rgba(w, h, rgba, size, size)
    encode_png(ROOT / "icon.png", size, size, 4, bytes(rgba))
    print("  X-01   icon.png  %dx%d (from %s)" % (size, size, hits[-1].name))
    return 1


def main() -> int:
    chapters = {"goods": install_goods, "cast": install_cast,
                "ui": install_ui,
                "war_tools": install_war_tools,
                "paintings": install_paintings, "compass": install_compass,
                "buildings": install_buildings, "goods_icons": install_goods_icons,
                "arms": install_arms, "army_paintings": install_army_paintings,
                "app_icon": install_app_icon, "title": install_title, "events": install_events,
                "courier_paintings": install_courier_paintings,
                "missive": install_missive}
    if len(sys.argv) < 2 or sys.argv[1] not in chapters:
        print(__doc__)
        return 2
    n = chapters[sys.argv[1]]()
    print("%d asset(s) installed" % n)
    return 0


if __name__ == "__main__":
    sys.exit(main())
