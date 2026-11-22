"""Bake the TUNIC MASK of the land arms whose art has no exported one, for the
3D map's realm-coloured tunics (Map3DUnitDress, scenes/map3d/materials/
unit_realm_tint*.tres). The infantry's mask comes from its export
(tools/units3d/infantry_arp/tunic_mask.py); these Tripo atlases have no cloth
material, so the dyed cloth is picked by an HSV window per atlas (RECIPES),
median-cleaned and feathered so seams do not alias.

Writes `<model>_tunic_mask.png` (L: 1 = tunic) beside each atlas and prints
the dye's mean linear luminance, the material's `tunic_luminance`. Run from
the repo root:

    python3 tools/units3d/cloth_mask.py [--preview DIR]
"""
import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

UNITS = Path("assets/3D/units")
# model -> atlas, hue window (degrees; lo > hi wraps through red), min saturation, value window (0..1)
RECIPES = {
    "cavalry": dict(atlas="cavalry/cavalry_cavalry_atlas.jpg", hue=(330, 12), sat=0.40, val=(0.15, 1.0)),
    "royal": dict(atlas="royal/royal_royal_atlas.jpg", hue=(100, 180), sat=0.30, val=(0.06, 1.0)),
    "archers": dict(atlas="archers/archers_tripo_image_cb7177bc-87a5-4437-85a0-cadbd2ce3d64_0.jpg",
                    hue=(28, 52), sat=0.55, val=(0.35, 1.0)),
}


def linear_luminance(rgb: np.ndarray) -> np.ndarray:
    c = rgb / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    return lin @ np.array([0.2126, 0.7152, 0.0722])


def mask_of(rgb: Image.Image, hue, sat, val):
    hsv = np.asarray(rgb.convert("HSV")).astype(np.float32) / 255.0
    h, s, v = hsv[..., 0] * 360.0, hsv[..., 1], hsv[..., 2]
    in_hue = (h >= hue[0]) & (h <= hue[1]) if hue[0] <= hue[1] else (h >= hue[0]) | (h <= hue[1])
    m = in_hue & (s >= sat) & (v >= val[0]) & (v <= val[1])
    img = Image.fromarray((m * 255).astype(np.uint8), "L")
    img = img.filter(ImageFilter.MedianFilter(3)).filter(ImageFilter.GaussianBlur(1.0))
    lum = float(linear_luminance(np.asarray(rgb).astype(np.float32))[m].mean())
    return img, lum


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--preview", type=Path)
    args = ap.parse_args()
    for model, r in RECIPES.items():
        src = UNITS / r["atlas"]
        rgb = Image.open(src).convert("RGB")
        m, lum = mask_of(rgb, r["hue"], r["sat"], r["val"])
        out = src.parent / f"{model}_tunic_mask.png"
        m.save(out)
        print(f"{out}  coverage {np.asarray(m).mean() / 255:.3f}  tunic_luminance {lum:.3f}")
        if args.preview:
            args.preview.mkdir(parents=True, exist_ok=True)
            red = Image.new("RGB", rgb.size, (255, 0, 0))
            Image.composite(red, rgb, m).resize((1024, 1024)).save(args.preview / f"{model}.png")


if __name__ == "__main__":
    main()
