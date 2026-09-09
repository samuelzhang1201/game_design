#!/usr/bin/env python3
"""Cut the settlements sheet into one keyed PNG per tier.

The owner supplies assets/maps/beria/settlements_test.png (or any sheet
given with --sheet): six settlement drawings on a transparent ground, laid
out hamlet / village / town on the top row and walled town / city / capital
on the bottom row. This finds the six largest opaque blobs, trims each to
its bounds, and writes assets/settlements/<tier>.png, which
data/settlement_art.csv maps onto the pack's burg groups and WorldMapView
draws at each town.

Requires numpy, pillow, scipy (pip install numpy pillow scipy). Usage:

    python3 tools/split_settlements.py [--sheet PATH]
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = Path(__file__).resolve().parent.parent
TIERS = ["hamlet", "village", "town", "walled_town", "city", "capital"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--sheet", default=str(ROOT / "assets/maps/beria/settlements_test.png"))
    args = ap.parse_args()
    im = np.asarray(Image.open(args.sheet).convert("RGBA"))
    mask = im[:, :, 3] > 24
    mask = ndimage.binary_closing(mask, iterations=8)
    labels, n = ndimage.label(mask)
    sizes = ndimage.sum(mask, labels, range(1, n + 1))
    biggest = np.argsort(sizes)[::-1][:6]
    boxes = []
    for i in biggest:
        sl = ndimage.find_objects(labels)[i]
        boxes.append((sl[0].start, sl[0].stop, sl[1].start, sl[1].stop))
    # Rows by centre y, then left to right.
    boxes.sort(key=lambda b: ((b[0] + b[1]) / 2 // (im.shape[0] / 2), (b[2] + b[3]) / 2))
    if len(boxes) != 6:
        raise SystemExit(f"expected 6 settlements, found {len(boxes)}")
    out_dir = ROOT / "assets/settlements"
    out_dir.mkdir(exist_ok=True)
    for tier, (y0, y1, x0, x1) in zip(TIERS, boxes):
        tile = im[y0:y1, x0:x1].copy()
        tile[:, :, 3] = np.where(tile[:, :, 3] > 24, tile[:, :, 3], 0)
        Image.fromarray(tile).save(out_dir / f"{tier}.png")
        print(f"{tier}: {x1 - x0}x{y1 - y0} at ({x0}, {y0})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
