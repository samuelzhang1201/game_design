"""Build the woods' CROWN ATLAS from the picked crown photographs.

  python3 tools/map3d/build_tree_atlas.py

Owner 2026-10-01 (树木一旦把标尺拉到20km以下就非常丑非常假): every crown on the 3D
map is a camera-facing PHOTO CARD (scripts/map3d/tree_card.gdshader) cut from
an aerial photograph of one real tree on white, rendered by the art pipeline
(assets/imagegen/tree_crown_prompts.csv, Z-Image and Qwen-Image-2512 side by
side). data/map3d_tree_crowns.csv names each atlas cell's kind (0 broadleaf,
1 conifer, 2 lone) and its `source` render under assets/imagegen/out/ (git-
ignored); this tool cuts each one out of its white ground, trims it to the
crown, fits it into its CELL px cell of a COLS x ROWS atlas and floods the
crown's own colour out into the clear texels so no mip bleeds white or black,
then writes assets/3D/vegetation/crowns/crowns_atlas.png (committed).
"""
import csv
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
TABLE = os.path.join(ROOT, "data", "map3d_tree_crowns.csv")
OUT = os.path.join(ROOT, "assets", "3D", "vegetation", "crowns", "crowns_atlas.png")
COLS, ROWS, CELL = 4, 4, 256
ERODE = 1            # px the crown's alpha is pulled in by, past the white ground's fringe
PAD = 6              # px of clear margin inside a cell, so a mip never reaches the neighbour
WHITE_LO, WHITE_HI = 10.0, 48.0   # how far below white a pixel must be to start / finish being crown


def cut_out(path):
    """RGBA of the render with its white ground made clear and the white
    taken back out of the crown's soft rim (un-premultiplied against white)."""
    rgb = np.asarray(Image.open(path).convert("RGB"), dtype=np.float32)
    dark = 255.0 - rgb.min(axis=2)                       # 0 on pure white
    a = np.clip((dark - WHITE_LO) / (WHITE_HI - WHITE_LO), 0.0, 1.0)
    a = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)),
                   dtype=np.float32) / 255.0
    safe = np.maximum(a, 0.05)[..., None]
    col = np.clip((rgb - (1.0 - safe) * 255.0) / safe, 0.0, 255.0)
    return np.dstack([col, a * 255.0]).astype(np.uint8)


def trim_fit(rgba):
    """The crown's own box, fitted (aspect kept) into a CELL - 2*PAD square,
    centred."""
    a = rgba[..., 3]
    ys, xs = np.nonzero(a > 24)
    box = rgba[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    im = Image.fromarray(box, "RGBA")
    side = CELL - 2 * PAD
    k = side / max(im.width, im.height)
    im = im.resize((max(1, round(im.width * k)), max(1, round(im.height * k))), Image.LANCZOS)
    cell = Image.new("RGBA", (CELL, CELL), (0, 0, 0, 0))
    cell.paste(im, ((CELL - im.width) // 2, (CELL - im.height) // 2))
    # the cut-out's rim eroded by ERODE px: what the white ground left in it
    # read as a pale fringe round every crown (a critic, 2026-10-01)
    r, g, b, a = cell.split()
    for _ in range(ERODE):
        a = a.filter(ImageFilter.MinFilter(3))
    return np.asarray(Image.merge("RGBA", (r, g, b, a)))


def flood(rgba, rounds=24):
    """The crown's colour pushed out into the clear texels, alpha untouched:
    mips of a cut-out average its rim with whatever colour the clear pixels
    hold, so they must hold the crown's."""
    rgb = rgba[..., :3].astype(np.float32)
    have = (rgba[..., 3] > 24).astype(np.float32)
    for _ in range(rounds):
        acc = np.zeros_like(rgb)
        n = np.zeros_like(have)
        for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
            acc += np.roll(np.roll(rgb * have[..., None], dy, 0), dx, 1)
            n += np.roll(np.roll(have, dy, 0), dx, 1)
        grow = (have == 0) & (n > 0)
        rgb[grow] = acc[grow] / n[grow][..., None]
        have = np.maximum(have, grow.astype(np.float32))
    out = rgba.copy()
    out[..., :3] = rgb.astype(np.uint8)
    return out


def settle_rim(rgba, solid=200, radius=6):
    """Every texel short of `solid` alpha takes its solid neighbours' colour
    (a box `radius` px each way, weighted by alpha), keeping its own alpha:
    the white render ground left a pale grey between a pine's needles that
    the far mips, raising the alpha, drew as frost (visual review
    2026-10-06)."""
    rgb = rgba[..., :3].astype(np.float32)
    w = np.clip((rgba[..., 3].astype(np.float32) - 128.0) / 127.0, 0, 1)

    def box(a):
        k = np.ones(2 * radius + 1, np.float32)
        a = np.apply_along_axis(lambda v: np.convolve(v, k, "same"), 0, a)
        return np.apply_along_axis(lambda v: np.convolve(v, k, "same"), 1, a)
    ws = box(w)
    near = np.dstack([box(rgb[..., c] * w) for c in range(3)]) / np.maximum(ws, 1e-4)[..., None]
    soft = (rgba[..., 3] < solid) & (ws > 0.5)
    out = rgba.copy()
    out[..., :3][soft] = np.clip(near[soft], 0, 255).astype(np.uint8)
    return out


def main():
    if "--settle-rim" in sys.argv:   # the committed atlas, in place (its sources are not committed)
        Image.fromarray(settle_rim(np.asarray(Image.open(OUT).convert("RGBA"))), "RGBA").save(OUT)
        print("settled", OUT)
        return
    with open(TABLE, newline="") as f:
        rows = list(csv.DictReader(f))
    atlas = np.zeros((ROWS * CELL, COLS * CELL, 4), dtype=np.uint8)
    for r in rows:
        cell = int(r["cell"])
        src = os.path.join(ROOT, r["source"])
        if not os.path.exists(src):
            sys.exit("missing source for cell %d: %s" % (cell, src))
        tile = flood(settle_rim(trim_fit(cut_out(src))))
        y, x = (cell // COLS) * CELL, (cell % COLS) * CELL
        atlas[y:y + CELL, x:x + CELL] = tile
        print("cell %2d  kind %s  %s" % (cell, r["kind"], os.path.basename(src)))
    # the empty cells too hold a colour, never black
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    Image.fromarray(flood(atlas, rounds=4), "RGBA").save(OUT)
    print("wrote", OUT, atlas.shape)


if __name__ == "__main__":
    main()
