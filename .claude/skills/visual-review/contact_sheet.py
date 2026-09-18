#!/usr/bin/env python3
"""Lay screenshots side by side, labelled, so they can be judged against each other.

  python3 .claude/skills/visual-review/contact_sheet.py OUT.png A.png B.png [C.png ...]
      [--labels before,after,variant-b] [--crop x,y,w,h] [--zoom 2] [--cols 3]

--crop takes the same region from every input (in the input's own pixels) and
--zoom enlarges it with nearest-neighbour, so a 16 px icon or a 1 px edge can
actually be seen. Inputs of different sizes are fitted to the first one's
width. Needs only Pillow.
"""
import argparse
import sys

from PIL import Image, ImageDraw, ImageFont

LABEL_H = 36
GAP = 12
BG = (24, 24, 24)
INK = (235, 225, 200)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("inputs", nargs="+")
    ap.add_argument("--labels", default="")
    ap.add_argument("--crop", default="")
    ap.add_argument("--zoom", type=int, default=1)
    ap.add_argument("--cols", type=int, default=0)
    a = ap.parse_args()

    labels = a.labels.split(",") if a.labels else [p.rsplit("/", 1)[-1] for p in a.inputs]
    tiles = []
    for path in a.inputs:
        im = Image.open(path).convert("RGB")
        if a.crop:
            x, y, w, h = (int(v) for v in a.crop.split(","))
            im = im.crop((x, y, x + w, y + h))
        if a.zoom > 1:
            im = im.resize((im.width * a.zoom, im.height * a.zoom), Image.NEAREST)
        tiles.append(im)
    width = tiles[0].width
    tiles = [t if t.width == width else t.resize((width, round(t.height * width / t.width)), Image.LANCZOS) for t in tiles]

    cols = a.cols or min(len(tiles), 3)
    rows = (len(tiles) + cols - 1) // cols
    cell_h = max(t.height for t in tiles) + LABEL_H
    sheet = Image.new("RGB", (cols * width + (cols + 1) * GAP, rows * cell_h + (rows + 1) * GAP), BG)
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 22)
    except OSError:
        font = ImageFont.load_default()
    for i, t in enumerate(tiles):
        cx = GAP + (i % cols) * (width + GAP)
        cy = GAP + (i // cols) * (cell_h + GAP)
        draw.text((cx + 4, cy + 6), labels[i] if i < len(labels) else "", fill=INK, font=font)
        sheet.paste(t, (cx, cy + LABEL_H))
    sheet.save(a.out)
    print(a.out, sheet.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
