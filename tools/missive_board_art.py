#!/usr/bin/env python3
"""Derive the Missive board's wood and aged-paper pieces from art already in
the repo (owner 2026-09-30: 外框和木质我是满意的，但是背景就是平淡整齐的羊皮纸颜色
很突兀，请改的有真实木质的质感；我想要每一个信息框都有边框，做旧的感觉).

No new generation: every output is a refit of an existing picture.

  frame_open.png  the carved frame (frame.png, U-20) with its cream opening made
                  clear, the moulding's inner shadow kept as a dark fade, so the
                  wood below shows through (ScaledNineSlice.hollow).
  board_wood.jpg  the backboard: Poly Haven rough_wood (CC0; the houses'
                  source in assets/3D/buildings/model_wip/polyhaven/ — the
                  critic ranked it over old_planks_02, whose even seams read
                  as ruled lines), its grain laid across, its splits lifted, warmed toward the frame's own oak and darkened
                  so the notes and the frame read on it. Seamless (the source
                  tiles), tiled by ScaledNineSlice at the board's texel density.
  note_aged.png   a note (note.png, U-23) yellowed, foxed, burnt at the edges,
                  its rim frayed, with a faded ink double rule inside the edge.
  note_lit.png    the same slip, its rule in gold: the letter on the desk.
  letter_aged.png the desk's open letter (letter.png, U-24) warmed and foxed
                  to the slips' paper, its edge darkened — the clean white
                  sheet read as a second medium beside the aged slips.

Run from the repo root: python3 tools/missive_board_art.py [--wood planks|rough]
Seeded, so a rerun writes the same files.
"""
import argparse
import os
import random

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BOARD = os.path.join(ROOT, "assets/2D/ui/missive_board")
POLYHAVEN = os.path.join(ROOT, "assets/3D/buildings/model_wip/polyhaven")
WOODS = {"planks": "old_planks_02_Diffuse_1k.jpg", "rough": "rough_wood_Diffuse_1k.jpg"}

# The frame's cream opening starts ~66 px in (measured on frame.png's 512 px).
FRAME_OPEN_FROM = 62
FRAME_OPEN_TO = 74
# The planks' tint: toward the frame's warm oak (#4E2C12 at its darkest).
WOOD_MUL = (1.02, 0.80, 0.58)
WOOD_GAIN = 0.62


def frame_open(out: str) -> None:
    im = Image.open(os.path.join(BOARD, "frame.png")).convert("RGBA")
    w, h = im.size
    px = im.load()
    for y in range(h):
        for x in range(w):
            d = min(x, y, w - 1 - x, h - 1 - y)  # px in from the nearest edge
            if d < FRAME_OPEN_FROM:
                continue
            r, g, b, a = px[x, y]
            if d >= FRAME_OPEN_TO:
                px[x, y] = (0, 0, 0, 0)
                continue
            # the lip: a dark shadow fading onto the wood below
            t = (d - FRAME_OPEN_FROM) / float(FRAME_OPEN_TO - FRAME_OPEN_FROM)
            px[x, y] = (18, 10, 4, int(255 * (1.0 - t) * 0.85))
    im.save(out)


def board_wood(out: str, wood: str, polyhaven: str = POLYHAVEN, tile: int = 2048) -> None:
    src = Image.open(os.path.join(polyhaven, WOODS[wood])).convert("RGB")
    src = src.rotate(90, expand=True)  # planks laid across the board
    # the splits and knots lifted: at full depth they were the darkest marks
    # on the board, louder than the notes' ink
    src = src.point(lambda v: int(38 + v * 0.85))
    r, g, b = src.split()
    r = r.point(lambda v: min(255, int(v * WOOD_MUL[0] * WOOD_GAIN)))
    g = g.point(lambda v: min(255, int(v * WOOD_MUL[1] * WOOD_GAIN)))
    b = b.point(lambda v: min(255, int(v * WOOD_MUL[2] * WOOD_GAIN)))
    im = Image.merge("RGB", (r, g, b))
    # ~680 design px a tile at 3 texture px each: a 256 px tile's knots read
    # as a repeating grid across the board, and 512 still repeated its splits
    im = im.resize((tile, tile), Image.LANCZOS)
    im.save(out, quality=90)  # a photograph: JPEG, not a 4 MB PNG


def _noise(size, seed: int, blur: float) -> Image.Image:
    rnd = random.Random(seed)
    w, h = size
    im = Image.new("L", (w, h))
    im.putdata([rnd.randrange(256) for _ in range(w * h)])
    return im.filter(ImageFilter.GaussianBlur(blur)) if blur > 0 else im


def note_aged(out: str, rule: tuple, seed: int = 7) -> None:
    im = Image.open(os.path.join(BOARD, "note.png")).convert("RGBA")
    w, h = im.size
    base = im.convert("RGB")
    # yellowed paper
    r, g, b = base.split()
    base = Image.merge("RGB", (r.point(lambda v: int(v * 0.97)),
                               g.point(lambda v: int(v * 0.88)),
                               b.point(lambda v: int(v * 0.68))))
    # fibres and mottling
    mottle = _noise((w, h), seed, 6).point(lambda v: 232 + (v - 128) // 3)
    fibre = _noise((w, h), seed + 1, 0.6).point(lambda v: 230 + (v - 128) // 10)
    base = ImageChops.multiply(base, Image.merge("RGB", (mottle,) * 3))
    base = ImageChops.multiply(base, Image.merge("RGB", (fibre,) * 3))
    # foxing: a few brown spots
    rnd = random.Random(seed + 2)
    stains = Image.new("L", (w, h), 255)
    sd = ImageDraw.Draw(stains)
    for _ in range(9):
        cx, cy = rnd.randrange(w), rnd.randrange(h)
        rr = rnd.randrange(4, 18)
        sd.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=rnd.randrange(185, 225))
    stains = stains.filter(ImageFilter.GaussianBlur(4))
    tint = Image.new("RGB", (w, h), (120, 80, 40))
    base = Image.composite(base, ImageChops.multiply(base, tint.point(lambda v: min(255, v * 2))), stains)
    # burnt edges: darker toward the rim, broken by noise
    edge = Image.new("L", (w, h), 0)
    ep = edge.load()
    burn_noise = _noise((w, h), seed + 3, 7).load()
    for y in range(h):
        for x in range(w):
            # ragged: the noise (blurred, so ~±20 around 128) moves the burn in and out
            d = min(x, y, w - 1 - x, h - 1 - y) + (burn_noise[x, y] - 128) / 1.5
            ep[x, y] = max(0, min(255, int(255 * (1.0 - d / 18.0) ** 1.6))) if d < 18 else 0
    dark = ImageChops.multiply(base, Image.new("RGB", (w, h), (92, 62, 34)))
    base = Image.composite(dark, base, edge)
    # the ink double rule, faded
    d = ImageDraw.Draw(base)
    for inset, width in ((16, 2), (22, 1)):
        d.rectangle((inset, inset, w - 1 - inset, h - 1 - inset), outline=rule, width=width)
    # a frayed rim: alpha eaten by noise within a few px of the edge
    alpha = Image.new("L", (w, h), 255)
    ap = alpha.load()
    fray = _noise((w, h), seed + 4, 1.2).load()
    for y in range(h):
        for x in range(w):
            dd = min(x, y, w - 1 - x, h - 1 - y)
            if dd < 6:
                ap[x, y] = 255 if fray[x, y] + dd * 30 > 200 else 0
    alpha = alpha.filter(ImageFilter.GaussianBlur(0.8))  # a torn edge, not stair-steps
    alpha = ImageChops.multiply(alpha, im.split()[3])
    base.putalpha(alpha)
    base.save(out)


def letter_aged(out: str, seed: int = 11) -> None:
    im = Image.open(os.path.join(BOARD, "letter.png")).convert("RGBA")
    w, h = im.size
    base = im.convert("RGB")
    r, g, b = base.split()
    base = Image.merge("RGB", (r.point(lambda v: int(v * 0.95)),
                               g.point(lambda v: int(v * 0.88)),
                               b.point(lambda v: int(v * 0.72))))
    mottle = _noise((w, h), seed, 10).point(lambda v: 236 + (v - 128) // 3)
    base = ImageChops.multiply(base, Image.merge("RGB", (mottle,) * 3))
    rnd = random.Random(seed + 1)
    stains = Image.new("L", (w, h), 255)
    sd = ImageDraw.Draw(stains)
    for _ in range(7):
        cx, cy = rnd.randrange(w), rnd.randrange(h)
        rr = rnd.randrange(8, 26)
        sd.ellipse((cx - rr, cy - rr, cx + rr, cy + rr), fill=rnd.randrange(200, 232))
    stains = stains.filter(ImageFilter.GaussianBlur(6))
    brown = ImageChops.multiply(base, Image.new("RGB", (w, h), (220, 170, 110)))
    base = Image.composite(base, brown, stains)
    # the sheet's own edge a little browned, not burnt: it is the letter being read
    edge = Image.new("L", (w, h), 0)
    ep = edge.load()
    for y in range(h):
        for x in range(w):
            d = min(x, y, w - 1 - x, h - 1 - y)
            if d < 40:
                ep[x, y] = int(150 * (1.0 - d / 40.0) ** 2)
    base = Image.composite(ImageChops.multiply(base, Image.new("RGB", (w, h), (150, 110, 70))), base, edge)
    base.putalpha(im.split()[3])
    base.save(out)


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--wood", default="rough", choices=sorted(WOODS))
    p.add_argument("--out", default=BOARD, help="directory to write into")
    p.add_argument("--tile", type=int, default=2048, help="the wood tile's texture px")
    p.add_argument("--polyhaven", default=POLYHAVEN,
                   help="where the Poly Haven sources are (git-ignored; another checkout's in a worktree)")
    a = p.parse_args()
    os.makedirs(a.out, exist_ok=True)
    frame_open(os.path.join(a.out, "frame_open.png"))
    board_wood(os.path.join(a.out, "board_wood.jpg"), a.wood, a.polyhaven, a.tile)
    note_aged(os.path.join(a.out, "note_aged.png"), (96, 64, 36))
    note_aged(os.path.join(a.out, "note_lit.png"), (176, 132, 52))
    letter_aged(os.path.join(a.out, "letter_aged.png"))
    print("wrote", a.out)


if __name__ == "__main__":
    main()
