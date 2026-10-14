#!/usr/bin/env python3
"""Gives a unit's atlas its plate definition, at no cost at run time.

Owner 2026-10-14: 步兵的游戏中的建模有点模糊，不够精细 — at play size a figure covers
~150 px, and its armour read as one flat mid-grey band. Two texture edits, both
from the export's OWN embedded maps (so a rerun is idempotent):

* albedo x CAVITY, on the STEEL only (the shield's paint, its rim and the
  cloth keep their colour): the tangent normal map's divergence at two scales (fine:
  mail and rivets; broad: the gaps between plates) darkens the creases and lifts
  the ridges a little, clamped to [--min, --max];
* the steel's ROUGHNESS (metallic channel above --metal) x --rough, so the
  plates catch the sun in small highlights (metallic itself stays as it is — a
  higher one read black on the map).

Godot draws the EXTRACTED `.jpg`s beside the `.glb` (it never overwrites them on
reimport), so this writes those; rerun it after every re-export:
    python3 tools/units3d/crisp_atlas.py assets/3D/units/infantry/infantry.glb
"""
import argparse
import io
import os

import numpy as np
from PIL import Image
from pygltflib import GLTF2
from scipy.ndimage import gaussian_filter

# (blur px, gain) per scale: fine detail, then the plate gaps
SCALES = [(1.2, 6.0), (4.0, 14.0)]


def embedded(g: GLTF2, blob: bytes, suffix: str) -> Image.Image:
    for img in g.images:
        if img.name.endswith(suffix):
            view = g.bufferViews[img.bufferView]
            start = view.byteOffset or 0
            return Image.open(io.BytesIO(blob[start:start + view.byteLength])).convert("RGB")
    raise SystemExit("no embedded image ending in %s" % suffix)


def cavity(normal: np.ndarray, lo: float, hi: float) -> np.ndarray:
    n = normal * 2.0 - 1.0
    cav = np.ones(n.shape[:2], np.float32)
    for blur, gain in SCALES:
        nx = gaussian_filter(n[..., 0], blur)
        ny = gaussian_filter(n[..., 1], blur)
        div = np.gradient(nx, axis=1) - np.gradient(ny, axis=0)  # > 0 a ridge, < 0 a crease (green up)
        cav *= np.clip(1.0 + gain * div, 0.5, 1.2)
    return np.clip(cav, lo, hi)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("glb")
    ap.add_argument("--atlas", default="", help="image name stem (default <glb stem>_atlas)")
    ap.add_argument("--min", type=float, default=0.6)
    ap.add_argument("--max", type=float, default=1.15)
    ap.add_argument("--metal", type=int, default=30, help="metallic (0-255) above which a texel is steel")
    ap.add_argument("--rough", type=float, default=0.7)
    args = ap.parse_args()
    stem = os.path.splitext(os.path.basename(args.glb))[0]
    atlas = args.atlas or stem + "_atlas"
    g = GLTF2().load(args.glb)
    blob = g.binary_blob()
    albedo = np.asarray(embedded(g, blob, atlas), np.float32) / 255.0
    normal = np.asarray(embedded(g, blob, atlas + "_n"), np.float32) / 255.0
    mr = np.asarray(embedded(g, blob, atlas + "_mr"), np.float32)
    steel = mr[..., 2] > args.metal
    # on the steel only: the shield's paint, its rim and the cloth keep their colour (critic 2026-10-14)
    cav = np.where(gaussian_filter(steel.astype(np.float32), 2.0) > 0.5, cavity(normal, args.min, args.max), 1.0)
    out = np.clip(albedo * cav[..., None], 0.0, 1.0)
    mr[..., 1] = np.where(steel, mr[..., 1] * args.rough, mr[..., 1])
    base = os.path.join(os.path.dirname(args.glb), "%s_%s" % (stem, atlas))
    Image.fromarray((out * 255.0 + 0.5).astype(np.uint8)).save(base + ".jpg", quality=95)
    Image.fromarray(np.clip(mr + 0.5, 0, 255).astype(np.uint8)).save(base + "_mr.jpg", quality=95)
    print("wrote %s.jpg (cavity %.2f..%.2f) and %s_mr.jpg (steel %.0f%% of texels, roughness x %.2f)" % (
        base, args.min, args.max, base, 100.0 * steel.mean(), args.rough))


if __name__ == "__main__":
    main()
