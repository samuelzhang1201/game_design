#!/usr/bin/env python3
"""Turn the UI frame export (solid-black interior) into a real-alpha PNG.

Counterpart to clean_portrait_art.py for the decorative screen frame: the
generator fills the frame's interior with flat black; this flood-fills that
interior from the image center through near-black pixels and makes it
transparent, feathers the edge, optionally scrubs a watermark region, and
writes an RGBA PNG. The frame art itself (and anything not connected to the
center) is untouched.

Needs Pillow, numpy, scipy. Usage:
  python3 tools/key_frame_interior.py SRC DST [--threshold 40]
  python3 tools/key_frame_interior.py SRC DST --scrub x0,y0,x1,y1
"""
import argparse

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage


def key(src: str, dst: str, threshold: int, scrub: str) -> None:
    img = Image.open(src).convert("RGB")
    rgb = np.asarray(img).astype(np.int16)

    if scrub:
        # Faint grey watermark text on dark ground: within the region, darken
        # neutral mid-greys to the ground color; saturated/gold detail stays.
        x0, y0, x1, y1 = (int(v) for v in scrub.split(","))
        region = rgb[y0:y1, x0:x1]
        value = region.max(axis=2)
        spread = region.max(axis=2) - region.min(axis=2)
        text = (value > threshold) & (value < 150) & (spread < 30)
        region[text] = (13, 11, 9)
        rgb[y0:y1, x0:x1] = region

    # The frame rails have their own dark filigree ground, so an unbounded
    # flood at a permissive threshold escapes through the inner edge and eats
    # them. Instead: flood only through PURE black (the generator's flat
    # interior fill), then grow a few bounded steps into the anti-aliased
    # boundary halo, then fill enclosed JPEG-noise islands.
    pure_black = rgb.max(axis=2) < threshold
    halo = rgb.max(axis=2) < threshold + 27
    h, w = pure_black.shape
    seed = np.zeros_like(pure_black)
    seed[h // 2 - 10:h // 2 + 10, w // 2 - 10:w // 2 + 10] = \
        pure_black[h // 2 - 10:h // 2 + 10, w // 2 - 10:w // 2 + 10]
    interior = ndimage.binary_propagation(seed, mask=pure_black)
    for _ in range(6):
        interior = ndimage.binary_dilation(interior) & halo
    interior = ndimage.binary_fill_holes(interior)

    alpha = Image.fromarray(((~interior) * 255).astype(np.uint8), "L") \
        .filter(ImageFilter.GaussianBlur(1))
    out = Image.fromarray(rgb.astype(np.uint8), "RGB").convert("RGBA")
    out.putalpha(alpha)
    out.save(dst)
    print("wrote %s (interior %.1f%% of pixels keyed)"
          % (dst, 100.0 * interior.mean()))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("src")
    parser.add_argument("dst")
    parser.add_argument("--threshold", type=int, default=40)
    parser.add_argument("--scrub", default="",
        help="x0,y0,x1,y1 region to darken grey watermark text in")
    args = parser.parse_args()
    key(args.src, args.dst, args.threshold, args.scrub)


if __name__ == "__main__":
    main()
