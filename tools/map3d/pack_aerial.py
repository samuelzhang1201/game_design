#!/usr/bin/env python3
"""Pack a generated AERIAL ground picture into Terrain3D's two maps (look
route 2026-09-30: the Poly Haven sets are ground-level photos of 1-2 m of
ground stretched to 160-320 m tiles, which at map height average to grey
noise; these are pictures of the ground as seen from 200 m up).

    python3 tools/map3d/pack_aerial.py SOURCE.png KEY [--height-gain G] [--rough R]

writes assets/3D/terrain/textures/<KEY>_alb_ht.png (albedo + height in A) and
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
OUT = os.path.join(ROOT, "assets", "3D", "terrain", "textures")
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


def _lin(c):
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def _srgb(c):
    c = np.clip(c, 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def box(a, r):
    if r <= 0:
        return a
    k = np.ones(2 * r + 1, np.float32) / (2 * r + 1)
    pad = np.pad(a, r, mode="wrap")
    pad = np.apply_along_axis(lambda v: np.convolve(v, k, "valid"), 1, pad)
    pad = np.apply_along_axis(lambda v: np.convolve(v, k, "valid"), 0, pad)
    return pad


def fill_spots(a, lum, threshold, radius=100, grow=6, dark_only=False, inner=3):
    """`a` with every spot whose light (over 7 px) is more than `threshold`
    off its neighbourhood's (a box `radius` px each way) painted out from its edge
    inward (OpenCV's Telea inpainting), the spot grown by `grow` px first so
    no rim of it is left. The ground's own grain is far under the threshold."""
    import cv2
    off = box(lum, inner) - box(lum, radius)
    spot = (-off if dark_only else np.abs(off)) > threshold
    spot = cv2.dilate(spot.astype(np.uint8), np.ones((2 * grow + 1, 2 * grow + 1), np.uint8))
    img = np.round(np.clip(a, 0, 1) * 255).astype(np.uint8)
    out = cv2.inpaint(img, spot, 6, cv2.INPAINT_TELEA)
    print("pack_aerial: filled %.2f%% of the picture's spots" % (100.0 * float(spot.mean())))
    return out.astype(np.float32) / 255.0


def tint_greys(a, hex_rgb, amount, lift=0.0):
    """`a` with its grey pixels (chroma under ~0.12, fading out by then: the
    stone, not the grass) turned toward `hex_rgb` at their own light, and
    lightened by `lift` — the colour the rest of the picture keeps."""
    t = np.array([int(hex_rgb[i:i + 2], 16) / 255.0 for i in (1, 3, 5)], np.float32)
    w3 = np.array([0.2126, 0.7152, 0.0722], np.float32)
    lum = a @ w3
    chroma = a.max(axis=2) - a.min(axis=2)
    grey = np.clip(1.0 - chroma / 0.12, 0.0, 1.0) * amount
    toward = np.clip(t[None, None, :] * (lum / max(float(t @ w3), 1e-4))[..., None] * (1.0 + lift), 0, 1)
    return a + (toward - a) * grey[..., None]


IMPORT = """[remap]

importer="texture"
type="CompressedTexture2D"

[deps]

source_file="res://assets/3D/terrain/textures/{name}"

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
    ap.add_argument("--contrast", type=float, default=1.0,
                    help="the picture's contrast about its mean (under 1 calms a busy rock that reads as noise far out)")
    ap.add_argument("--lift-darks", type=float, default=0.0,
                    help="0..1: how far the darkest spots (moss clumps, shadowed holes) rise toward their surroundings")
    ap.add_argument("--lift-radius", type=int, default=12,
                    help="px (at 2048) of the neighbourhood --lift-darks compares with: as big as the dark clumps")
    ap.add_argument("--fill-spots", type=float, default=0.0,
                    help="0..1: a spot this much lighter or darker than its neighbourhood (a bush, a white stone) is "
                         "painted out from its surroundings — on a layer tiled every 140 m it repeats as a row of dots")
    ap.add_argument("--fill-dark-only", action="store_true",
                    help="--fill-spots paints out only spots DARKER than their neighbourhood (an upland's heather, "
                         "not its stones)")
    ap.add_argument("--fill-radius", type=int, default=100, help="--fill-spots: the neighbourhood (px) a spot is measured against")
    ap.add_argument("--fill-inner", type=int, default=3, help="--fill-spots: the spot's own blur (px): larger finds broad patches")
    ap.add_argument("--fill-grow", type=int, default=6, help="--fill-spots: px a found spot is grown by before painting")
    ap.add_argument("--lift-patches", type=float, default=0.0,
                    help="0..1: broad dark patches raised to their surroundings' light at low frequency, the grain kept "
                         "(tiled, an upland's heather read as black pits on the hills)")
    ap.add_argument("--patch-inner", type=int, default=12, help="--lift-patches: the patch's own blur (px)")
    ap.add_argument("--patch-radius", type=int, default=120, help="--lift-patches: the surroundings' reach (px)")
    ap.add_argument("--grey-tint", default="",
                    help="an sRGB #RRGGBB the picture's GREY pixels (stone, scree) are turned toward, keeping their "
                         "light: a cool scree on golden grass reads as a second photograph pasted on")
    ap.add_argument("--grey-tint-amount", type=float, default=0.0, help="--grey-tint: how far, 0..1")
    ap.add_argument("--grey-lift", type=float, default=0.0,
                    help="--grey-tint: the grey pixels lightened by this share, so scree reads as stone, not a stain")
    ap.add_argument("--black", type=float, default=0.0,
                    help="0..1: the black point lifted to this (a rock photo's baked-in shadow fights the scene's sun)")
    ap.add_argument("--warm", type=float, default=0.0,
                    help="how far the picture's hue moves warm (red up, blue down by this share)")
    ap.add_argument("--flatten-keep", type=float, default=0.2,
                    help="the share of the photograph's own slow light kept (flatten)")
    ap.add_argument("--saturation", type=float, default=1.0,
                    help="the picture's saturation (1 = as generated; a rock's ochre fills read loud at map size)")
    ap.add_argument("--match-mean", default="",
                    help="a mean colour (linear light) this picture is scaled to — an sRGB #RRGGBB, or an already "
                         "packed <key>_alb_ht.png to take it from: bake_world.py's colour map is far colour / the "
                         "layer's mean, so a new picture that keeps the old mean needs no rebake to show its true colour")
    args = ap.parse_args()
    a = np.asarray(Image.open(args.source).convert("RGB"), dtype=np.float32) / 255.0
    a = np.clip(seamless(flatten(a, keep=args.flatten_keep)), 0, 1)
    a = np.asarray(Image.fromarray(np.round(a * 255).astype(np.uint8)).resize((SIZE, SIZE), Image.LANCZOS),
                   dtype=np.float32) / 255.0
    lum = a @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    if args.lift_patches > 0.0:
        # a broad dark patch (heather, a shadowed hollow) raised to its
        # surroundings' light at low frequency only: the grain inside it stays
        lo = np.dstack([box(a[..., c], args.patch_inner) for c in range(3)])
        ref = np.dstack([box(a[..., c], args.patch_radius) for c in range(3)])
        w = np.array([0.2126, 0.7152, 0.0722], np.float32)
        dark = np.clip((ref @ w - lo @ w) / 0.04, 0, 1)[..., None]
        a = np.clip(a + (ref - lo) * dark * args.lift_patches, 0, 1)
        lum = a @ w
    if args.fill_spots > 0.0:
        a = fill_spots(a, lum, args.fill_spots, dark_only=args.fill_dark_only,
                       radius=args.fill_radius, inner=args.fill_inner, grow=args.fill_grow)
        lum = a @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    if args.lift_darks > 0.0:
        # a spot darker than its neighbourhood is lifted toward it: holes and
        # dark moss read as black pits on a rock face at map size
        near = np.dstack([box(a[..., c], args.lift_radius) for c in range(3)])
        lum_n = near @ np.array([0.2126, 0.7152, 0.0722], np.float32)
        dark = np.clip((lum_n - lum) / 0.15, 0, 1)[..., None] * args.lift_darks
        a = a + (near - a) * dark
        lum = a @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    if args.contrast != 1.0:
        mean = a.reshape(-1, 3).mean(0)
        a = np.clip(mean + (a - mean) * args.contrast, 0, 1)
        lum = a @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    if args.saturation != 1.0:
        a = np.clip(lum[..., None] + (a - lum[..., None]) * args.saturation, 0, 1)
    if args.warm:
        a = np.clip(a * np.array([1.0 + args.warm, 1.0, 1.0 - args.warm], np.float32), 0, 1)
    if args.grey_tint and args.grey_tint_amount > 0.0:
        a = tint_greys(a, args.grey_tint, args.grey_tint_amount, args.grey_lift)
        lum = a @ np.array([0.2126, 0.7152, 0.0722], np.float32)
    if args.black > 0.0:
        a = args.black + a * (1.0 - args.black)
    if args.match_mean:
        if args.match_mean.startswith("#"):
            ref = np.array([[[int(args.match_mean[i:i + 2], 16) / 255.0 for i in (1, 3, 5)]]], np.float32)
        else:
            ref = np.asarray(Image.open(args.match_mean).convert("RGB").resize((64, 64)), dtype=np.float32) / 255.0
        a_lin = _lin(a)
        gain = _lin(ref).reshape(-1, 3).mean(0) / np.maximum(a_lin.reshape(-1, 3).mean(0), 1e-4)
        a = np.clip(_srgb(a_lin * gain), 0, 1)
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
