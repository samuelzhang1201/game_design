#!/usr/bin/env python3
"""Turns the LEDGER's generated art (assets/flux/out/ledger, the L- prompts)
into the textures the galaxy's shaders sample.

    python3 tools/ledger/ledger_art_prep.py orb    SRC.png DEST.png [--size 256]
    python3 tools/ledger/ledger_art_prep.py strand SRC.png DEST.png [--width 512 --height 64]

orb: a star's MATCAP. The sphere is found on its black ground (the brightest
pixels' bounding circle), cropped to exactly its disc so a view-space normal
maps onto it (uv = n.xy * 0.5 + 0.5), and turned to VALUE: the shader tints
it with the cluster's colour (taste: greyscale art takes the realm's hue).
Size: a star is drawn at most ledger_star_max_px (14 design px) in radius,
× 3 window scale = 84 px across, so 256 px is ample and mipmaps cover the
rest (asset-resolution-per-use).

strand: a link's texture. The strand's band is found (rows whose brightness
rises above the ground), cropped to it with its glow, turned to value and
made to tile along its length by a cross-fade of its two ends. A link is 1-3
screen px wide (ledger_link_*_px), drawn wider for its glow, so 64 px across
is plenty; 512 along keeps the glints sharp where it repeats.

Stdlib + Pillow + numpy.
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image


def _value(img: Image.Image) -> np.ndarray:
    a = np.asarray(img.convert("RGB"), dtype=np.float32) / 255.0
    # perceived value (Rec. 709 luma on the sRGB values)
    return a[..., 0] * 0.2126 + a[..., 1] * 0.7152 + a[..., 2] * 0.0722


def orb(src: Path, dest: Path, size: int) -> None:
    v = _value(Image.open(src))
    ground = float(np.percentile(v, 5))
    # a fifth of the way up to the sphere's light: above a floor's faint glow
    mask = v > ground + 0.2 * (float(np.percentile(v, 99)) - ground)
    ys, xs = np.nonzero(mask)
    if xs.size == 0:
        sys.exit(f"{src}: no sphere found")
    # the disc: a least-squares circle through the left and right edges of
    # the lit rows in the upper part of the mask, where no floor glow reaches
    top, bottom = int(ys.min()), int(ys.max())
    pts = []
    for y in range(top, top + max(4, int(0.45 * (bottom - top)))):
        row = np.nonzero(mask[y])[0]
        if row.size:
            pts += [(row.min(), y), (row.max(), y)]
    p = np.asarray(pts, dtype=np.float64)
    a = np.c_[2.0 * p[:, 0], 2.0 * p[:, 1], np.ones(len(p))]
    sol = np.linalg.lstsq(a, (p ** 2).sum(axis=1), rcond=None)[0]
    cx, cy = float(sol[0]), float(sol[1])
    r = float(np.sqrt(sol[2] + cx * cx + cy * cy))
    box = (int(round(cx - r)), int(round(cy - r)), int(round(cx + r)), int(round(cy + r)))
    out = Image.fromarray(np.clip((v - ground) / max(1e-3, 1.0 - ground), 0, 1) * 255.0).convert("L")
    out = out.crop(box).resize((size, size), Image.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest)
    print(f"orb {src.name}: disc centre ({cx:.0f},{cy:.0f}) r {r:.0f} -> {dest} {size}px")


def strand(src: Path, dest: Path, width: int, height: int) -> None:
    v = _value(Image.open(src))
    ground = float(np.percentile(v, 5))
    # the core reaches full strength: the link's opacity is the texture's
    peak_v = float(np.percentile(v, 99.8))
    v = np.clip((v - ground) / max(1e-3, peak_v - ground), 0, 1)
    h, w = v.shape
    # trim the ends, where a model often lets a strand fray or fade
    v = v[:, int(w * 0.06): int(w * 0.94)]
    rows = v.mean(axis=1)
    peak = int(np.argmax(rows))
    lit = np.nonzero(rows > rows.max() * 0.2)[0]
    half = max(peak - lit.min(), lit.max() - peak, 8)
    band = v[max(0, peak - half): min(h, peak + half + 1), :]
    # tile along the length: cross-fade the last quarter into the first
    n = band.shape[1]
    k = n // 4
    t = np.linspace(0.0, 1.0, k)[None, :]
    body = band[:, : n - k].copy()
    body[:, :k] = band[:, n - k:] * (1.0 - t) + band[:, :k] * t
    out = Image.fromarray(body * 255.0).convert("L").resize((width, height), Image.LANCZOS)
    dest.parent.mkdir(parents=True, exist_ok=True)
    out.save(dest)
    print(f"strand {src.name}: band rows {peak - half}..{peak + half} -> {dest} {width}x{height}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["orb", "strand"])
    ap.add_argument("src", type=Path)
    ap.add_argument("dest", type=Path)
    ap.add_argument("--size", type=int, default=256)
    ap.add_argument("--width", type=int, default=512)
    ap.add_argument("--height", type=int, default=64)
    a = ap.parse_args()
    if a.kind == "orb":
        orb(a.src, a.dest, a.size)
    else:
        strand(a.src, a.dest, a.width, a.height)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
