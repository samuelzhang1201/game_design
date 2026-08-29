#!/usr/bin/env python3
"""Convert exported character art into game-ready full-body portrait PNGs.

Art sources (e.g. AI generators) often bake a fake transparency checkerboard
into a JPEG and stamp a watermark. This tool recovers real alpha:

  1. Flood-fills from the image border through bright, colour-neutral pixels
     (both checker tones) to build a background mask.
  2. Removes enclosed checkerboard pockets (e.g. the gap between an arm and
     the torso, unreachable from the border): any enclosed region whose
     pixels overwhelmingly match the two checker tones measured from the
     border background. The exact-tone test keeps bright neutral areas of
     the figure itself (polished armour, parchment) intact.
  3. Keeps only the largest remaining connected component - this drops the
     watermark text and stray specks along with the checkerboard.
  4. Feathers the mask edge one pixel, crops to content, scales to a target
     height, and writes an RGBA PNG.

Needs Pillow, numpy, scipy (not stdlib - run in any venv with those).
Usage:  python3 tools/clean_portrait_art.py SRC DST [--height 660]
e.g.    python3 tools/clean_portrait_art.py assets/portraits/minister_1.jpeg \
            assets/portraits/full/char_chancellor.png
"""
import argparse

import numpy as np
from PIL import Image, ImageFilter
from scipy import ndimage

# Background pixels are colour-neutral checker tones (r==g==b give or take
# JPEG noise) within a brightness band. Defaults fit the common LIGHT
# checkerboard; pass --bg-min/--bg-max for a dark one (e.g. 40..100). The
# flood fill stops at the subject's outline either way.
MIN_BACKGROUND_VALUE = 185
MAX_BACKGROUND_VALUE = 255
MAX_CHANNEL_SPREAD = 20

# Enclosed-pocket test: region counts as checkerboard when this share of its
# pixels sits within TONE_TOLERANCE of either measured checker tone.
MIN_POCKET_PIXELS = 200
TONE_TOLERANCE = 8
MIN_TONE_MATCH_SHARE = 0.8


def clean(src: str, dst: str, height: int,
          bg_min: int = MIN_BACKGROUND_VALUE,
          bg_max: int = MAX_BACKGROUND_VALUE,
          pockets: bool = True) -> None:
    rgb = np.asarray(Image.open(src).convert("RGB")).astype(np.int16)

    candidate = (rgb.min(axis=2) >= bg_min) & (rgb.max(axis=2) <= bg_max) & \
        ((rgb.max(axis=2) - rgb.min(axis=2)) <= MAX_CHANNEL_SPREAD)
    border_seed = np.zeros_like(candidate)
    border_seed[0, :] = candidate[0, :]
    border_seed[-1, :] = candidate[-1, :]
    border_seed[:, 0] = candidate[:, 0]
    border_seed[:, -1] = candidate[:, -1]
    background = ndimage.binary_propagation(border_seed, mask=candidate)

    # Measure the two checker tones from the border-connected background,
    # then knock out enclosed pockets that match them.
    gray = rgb.mean(axis=2)
    bg_values = gray[background]
    light = np.median(bg_values[bg_values >= bg_values.mean()])
    dark = np.median(bg_values[bg_values < bg_values.mean()])
    tone_match = (np.abs(gray - light) <= TONE_TOLERANCE) | \
        (np.abs(gray - dark) <= TONE_TOLERANCE)
    # Convex subjects (a medallion) have no real enclosed pockets; --no-pockets
    # skips this so in-art shadows matching the checker tones are never eaten.
    pocket_labels, pocket_count = ndimage.label(candidate & ~background)
    if not pockets:
        pocket_count = 0
    if pocket_count > 0:
        sizes = np.bincount(pocket_labels.ravel(), minlength=pocket_count + 1)
        shares = ndimage.mean(tone_match, pocket_labels, range(1, pocket_count + 1))
        is_checker = np.zeros(pocket_count + 1, dtype=bool)
        is_checker[1:] = (sizes[1:] >= MIN_POCKET_PIXELS) & \
            (np.asarray(shares) >= MIN_TONE_MATCH_SHARE)
        background |= is_checker[pocket_labels]

    foreground = ~background
    labels, count = ndimage.label(foreground)
    if count == 0:
        raise SystemExit("%s: nothing left after background removal" % src)
    sizes = ndimage.sum_labels(np.ones_like(labels), labels, range(1, count + 1))
    keep = labels == (int(np.argmax(sizes)) + 1)

    alpha = Image.fromarray((keep * 255).astype(np.uint8), "L") \
        .filter(ImageFilter.GaussianBlur(1))
    out = Image.open(src).convert("RGBA")
    out.putalpha(alpha)

    box = out.getbbox()  # alpha-aware bbox after masking
    out = out.crop(box)
    width = round(out.width * height / out.height)
    out = out.resize((width, height), Image.LANCZOS)
    out.save(dst)
    print("wrote %s (%dx%d, kept %.1f%% of pixels)"
          % (dst, width, height, 100.0 * keep.mean()))


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("src")
    parser.add_argument("dst")
    parser.add_argument("--height", type=int, default=660)
    parser.add_argument("--bg-min", type=int, default=MIN_BACKGROUND_VALUE)
    parser.add_argument("--bg-max", type=int, default=MAX_BACKGROUND_VALUE)
    parser.add_argument("--no-pockets", action="store_true")
    args = parser.parse_args()
    clean(args.src, args.dst, args.height, args.bg_min, args.bg_max,
          not args.no_pockets)


if __name__ == "__main__":
    main()
