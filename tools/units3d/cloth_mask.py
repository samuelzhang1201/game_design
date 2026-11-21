"""Bake each unit atlas's CLOTH MASK, `<atlas>_cloth.png`, for the 3D map's
realm-coloured cloth (scripts/map3d/unit_cloth.gdshader): R is the dyed cloth
(1) or not (0); G is the texel's SHADE, its luminance over the dye's mean
luminance, halved (0.5 = the mean), so the realm colour keeps the folds.

The dye is picked by an HSV window per atlas (RECIPES); the mask is feathered
by a small blur so seams do not alias. Run from the repo root:

    python3 tools/units3d/cloth_mask.py            # every recipe
    python3 tools/units3d/cloth_mask.py --preview DIR   # also a red overlay per atlas
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

UNITS = Path("assets/3D/units")
# atlas -> hue window (degrees; lo > hi wraps through red), min saturation, value window (0..1)
RECIPES = {
    "infantry/infantry_infantry_atlas.jpg": dict(hue=(70, 140), sat=0.28, val=(0.12, 1.0)),
    "cavalry/cavalry_cavalry_atlas.jpg": dict(hue=(330, 12), sat=0.40, val=(0.15, 1.0)),
    "royal/royal_royal_atlas.jpg": dict(hue=(100, 180), sat=0.30, val=(0.06, 1.0)),
    "archers/archers_tripo_image_cb7177bc-87a5-4437-85a0-cadbd2ce3d64_0.jpg":
        dict(hue=(28, 52), sat=0.55, val=(0.35, 1.0)),
}


def mask_of(path: Path, hue, sat, val) -> Image.Image:
    rgb = Image.open(path).convert("RGB")
    hsv = np.asarray(rgb.convert("HSV")).astype(np.float32) / 255.0
    h, s, v = hsv[..., 0] * 360.0, hsv[..., 1], hsv[..., 2]
    in_hue = (h >= hue[0]) & (h <= hue[1]) if hue[0] <= hue[1] else (h >= hue[0]) | (h <= hue[1])
    m = in_hue & (s >= sat) & (v >= val[0]) & (v <= val[1])
    r = Image.fromarray((m * 255).astype(np.uint8), "L")
    r = r.filter(ImageFilter.MedianFilter(3)).filter(ImageFilter.GaussianBlur(1.0))
    lum = np.asarray(rgb.convert("L")).astype(np.float32)
    shade = np.clip(lum / max(lum[m].mean(), 1.0) * 0.5, 0.0, 1.0)
    g = Image.fromarray((shade * 255).astype(np.uint8), "L")
    return Image.merge("RGB", (r, g, Image.new("L", r.size, 0)))


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", type=Path)
    args = ap.parse_args()
    for rel, r in RECIPES.items():
        src = UNITS / rel
        out = src.with_name(src.stem + "_cloth.png")
        m = mask_of(src, **r)
        m.save(out)
        print(out, f"{np.asarray(m)[..., 0].mean() / 255:.3f}")
        if args.preview:
            args.preview.mkdir(parents=True, exist_ok=True)
            base = Image.open(src).convert("RGB")
            red = Image.new("RGB", base.size, (255, 0, 0))
            Image.composite(red, base, m.getchannel("R")).resize((1024, 1024)).save(args.preview / (src.parent.name + ".png"))


if __name__ == "__main__":
    main()
