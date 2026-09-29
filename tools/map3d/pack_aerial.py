#!/usr/bin/env python3
"""Pack a generated AERIAL ground picture into Terrain3D's two maps (look
route 2026-09-30: the Poly Haven sets are ground-level photos of 1-2 m of
ground stretched to 160-320 m tiles, which at map height average to grey
noise; these are pictures of the ground as seen from 200 m up).

    python3 tools/map3d/pack_aerial.py SOURCE.png KEY [--height-gain G] [--rough R]

writes assets/map3d/textures/<KEY>_alb_ht.png (albedo + height in A) and
<KEY>_nrm_rgh.png (OpenGL normal + roughness in A) at 2048 px, the size every
layer of Terrain3D's texture array shares (pack_textures.py's SIZE).

The picture is made SEAMLESS by a four-way crossfade of itself and its copies
rolled half a tile along x, y and both: each is weighted by sin^2 windows
that are zero at its own seam, so every seam falls where its copy's weight
is zero (Heitz & Neyret's variance-preserving blend: the weighted sum is
divided by the root of the summed squared weights about the mean, so the
middle of the tile keeps the picture's contrast instead of greying).
"""
import argparse
import os

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "map3d", "textures")
SIZE = 2048


def _wrap(a, m, axis):
    """Make `a` wrap along `axis`: the first m samples cross-fade into the m
    past the kept width (their neighbours in the picture), so the last kept
    sample runs on into the first. The result is m shorter. The fade keeps
    the picture's contrast (divided by the root of the summed squared
    weights about the mean), so the band does not grey out."""
    a = np.moveaxis(a, axis, 0)
    n = a.shape[0] - m
    r = ((np.arange(m) + 0.5) / m).reshape((m,) + (1,) * (a.ndim - 1))
    mean = a.reshape(-1, a.shape[-1]).mean(0)
    head = ((a[:m] - mean) * r + (a[n:n + m] - mean) * (1 - r)) / np.sqrt(r ** 2 + (1 - r) ** 2) + mean
    out = np.concatenate([head, a[m:n]], axis=0)
    return np.moveaxis(out, 0, axis)


def flatten(a, keep=0.2, cells=10):
    """Take out the photograph's own slow light (a vignette, one lit side):
    the picture minus its blur at `cells` across, all but `keep` of it, about
    its mean — the terrain's macro variation and colour map carry the slow
    changes, and a lit side repeats as a stripe every tile."""
    h, w = a.shape[:2]
    small = Image.fromarray(np.round(np.clip(a, 0, 1) * 255).astype(np.uint8)).resize((cells, cells), Image.BOX)
    low = np.asarray(small.resize((w, h), Image.BICUBIC), dtype=np.float32) / 255.0
    mean = a.reshape(-1, a.shape[2]).mean(0)
    return a - (low - mean) * (1.0 - keep)


def seamless(a, share=0.15):
    """The picture made to tile, both ways, losing `share` of each side."""
    m = int(a.shape[1] * share)
    return _wrap(_wrap(a, m, 1), int(a.shape[0] * share), 0)


def box(a, r):
    if r <= 0:
        return a
    k = np.ones(2 * r + 1, np.float32) / (2 * r + 1)
    pad = np.pad(a, r, mode="wrap")
    pad = np.apply_along_axis(lambda v: np.convolve(v, k, "valid"), 1, pad)
    pad = np.apply_along_axis(lambda v: np.convolve(v, k, "valid"), 0, pad)
    return pad


IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/map3d/textures/{name}"

[params]

compress/mode=2
compress/high_quality=false
compress/lossy_quality=0.7
compress/uastc_level=0
compress/rdo_quality_loss=0.0
compress/hdr_compression=1
compress/normal_map=2
compress/channel_pack=0
mipmaps/generate=true
mipmaps/limit=-1
roughness/mode=0
roughness/src_normal=""
process/channel_remap/red=0
process/channel_remap/green=1
process/channel_remap/blue=2
process/channel_remap/alpha=3
process/fix_alpha_border=true
process/premult_alpha=false
process/normal_map_invert_y=false
process/hdr_as_srgb=false
process/hdr_clamp_exposure=false
process/size_limit=0
detect_3d/compress_to=0
"""


def write_import(png):
    """Terrain3D's texture array wants every layer in ONE format: the Poly
    Haven sets import VRAM-compressed (compress/mode=2), and the project's
    default is lossless, so a new layer is given the sets' own import
    settings before Godot first sees it (else: "Texture ID n albedo format
    doesn't match the first texture" and a grey ground)."""
    path = png + ".import"
    if not os.path.exists(path):
        with open(path, "w") as f:
            f.write(IMPORT.format(name=os.path.basename(png)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("source")
    ap.add_argument("key")
    ap.add_argument("--height-gain", type=float, default=1.0,
                    help="how far the picture's light and dark become height (bumps, height blending)")
    ap.add_argument("--normal-strength", type=float, default=2.0)
    ap.add_argument("--rough", type=float, default=0.92)
    args = ap.parse_args()
    a = np.asarray(Image.open(args.source).convert("RGB"), dtype=np.float32) / 255.0
    a = np.clip(seamless(flatten(a)), 0, 1)
    a = np.asarray(Image.fromarray(np.round(a * 255).astype(np.uint8)).resize((SIZE, SIZE), Image.LANCZOS),
                   dtype=np.float32) / 255.0
    lum = a @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    # height: the local light against its neighbourhood (a crown stands, a
    # gap sinks), not the tile's overall brightness
    local = lum - box(lum, 24)
    height = box(local, 2)
    height = (height - height.min()) / max(float(np.ptp(height)), 1e-6)
    height = np.clip(0.5 + (height - 0.5) * args.height_gain, 0, 1)
    gy, gx = np.gradient(box(height, 1))
    s = args.normal_strength
    n = np.dstack([-gx * s * 8, gy * s * 8, np.ones_like(height)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    alb = np.dstack([a, height])
    nrm = np.dstack([n * 0.5 + 0.5, np.full_like(height, args.rough)])
    os.makedirs(OUT, exist_ok=True)
    Image.fromarray(np.round(alb * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, f"{args.key}_alb_ht.png"))
    Image.fromarray(np.round(np.clip(nrm, 0, 1) * 255).astype(np.uint8), "RGBA").save(
        os.path.join(OUT, f"{args.key}_nrm_rgh.png"))
    for suffix in ("alb_ht", "nrm_rgh"):
        write_import(os.path.join(OUT, f"{args.key}_{suffix}.png"))
    print(f"pack_aerial: {args.key} <- {os.path.basename(args.source)}")


if __name__ == "__main__":
    main()
