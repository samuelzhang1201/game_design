"""Author a glTF metallic-roughness map (G = roughness, B = metallic) for the Tripo knight, whose
export carries only a colour map (metallic 0, roughness 0.9: the armour read as cloth).

python3 metal_map.py BASECOLOR.png OUT.png   (plain Python + numpy + Pillow; no Blender)
Metal = low saturation (plates, mail, helmet; leather, skin and the olive trousers are saturated),
closed so the dark gaps between mail rings stay metal. Smooth bright metal (plates) is glossy, busy
metal (mail, by local contrast) a little rougher, everything else matte.
"""
import sys

import numpy as np
from PIL import Image, ImageFilter

ROUGH_PLATE, ROUGH_MAIL, ROUGH_CLOTH = 0.38, 0.50, 0.78
METAL_PLATE, METAL_MAIL = 0.95, 0.85


def box(a, r):
    """Mean over a (2r+1)^2 box, by summed-area table."""
    p = np.pad(a, r + 1, mode="edge").cumsum(0).cumsum(1)
    k = 2 * r + 1
    return (p[k:, k:] - p[:-k, k:] - p[k:, :-k] + p[:-k, :-k])[: a.shape[0], : a.shape[1]] / k ** 2


def main(src, out):
    rgb = np.asarray(Image.open(src).convert("RGB"), np.float32) / 255
    mx, mn = rgb.max(2), rgb.min(2)
    sat = np.where(mx > 1e-3, (mx - mn) / np.maximum(mx, 1e-3), 0)
    metal = Image.fromarray(((sat < 0.22) & (mx > 0.06)).astype(np.uint8) * 255)
    metal = metal.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.MinFilter(5))   # close the ring gaps
    metal = np.asarray(metal.filter(ImageFilter.GaussianBlur(1.5)), np.float32) / 255
    lum = rgb.mean(2)
    contrast = np.sqrt(np.maximum(box(lum ** 2, 4) - box(lum, 4) ** 2, 0))
    mail = np.clip((contrast - 0.05) / 0.07, 0, 1)                  # 0 smooth plate .. 1 ring mesh
    rough = metal * (ROUGH_PLATE + (ROUGH_MAIL - ROUGH_PLATE) * mail) + (1 - metal) * ROUGH_CLOTH
    met = metal * (METAL_PLATE + (METAL_MAIL - METAL_PLATE) * mail)
    img = np.stack([np.ones_like(rough), rough, met], 2)
    Image.fromarray((img * 255 + 0.5).astype(np.uint8)).save(out)
    print(out, "metal share", round(float(metal.mean()), 3))


if __name__ == "__main__":
    main(*sys.argv[1:3])
