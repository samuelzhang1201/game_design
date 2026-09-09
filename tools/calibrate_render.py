#!/usr/bin/env python3
"""Measure how a map pack's render sits on its own coordinates.

Azgaar's PNG export captures the CURRENT VIEW, so a render exported while the
map was zoomed or panned is a scaled, shifted picture of the same world. The
game corrects that with data/maps.csv's render_scale / render_offset_x /
render_offset_y (render = native * scale + offset, in native units — see
WorldMapView.map_to_screen). This tool measures those three numbers by
registering the pack's coastline (world_biome_index.png: white = water)
against the render's water, first by FFT cross-correlation of the land masks
over a range of scales, then by minimising the distance from every coast
pixel to the render's nearest land/water edge at full resolution.

Requires numpy, pillow, scipy (pip install numpy pillow scipy). Usage:

    python3 tools/calibrate_render.py [--pack beria] [--write]

--write puts the result into data/maps.csv; otherwise it only prints. Run it
after every re-export, then run ./run_tests.sh — test_map_data checks the
calibration against the render.
"""
import argparse, csv, sys
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage, signal

Image.MAX_IMAGE_PIXELS = None
ROOT = Path(__file__).resolve().parent.parent


def load_masks(pack: str):
    render = np.asarray(Image.open(ROOT / "assets/maps" / pack / "world_map.png").convert("RGB"))
    biome = np.asarray(Image.open(ROOT / "assets/maps" / pack / "world_biome_index.png").convert("RGB"))
    land = ~((biome[:, :, 0] == 255) & (biome[:, :, 1] == 255) & (biome[:, :, 2] == 255))
    k = render.shape[1] // land.shape[1]
    if render.shape[0] != land.shape[0] * k or render.shape[1] != land.shape[1] * k:
        sys.exit(f"render {render.shape[1]}x{render.shape[0]} is not an integer multiple of {land.shape[1]}x{land.shape[0]}")
    return render, land, k


def otsu(values: np.ndarray) -> float:
    hist, edges = np.histogram(values, bins=256, range=(0, 255))
    hist = hist.astype(float)
    centres = (edges[:-1] + edges[1:]) / 2
    best, best_t = -1.0, 128.0
    for i in range(1, 255):
        w0, w1 = hist[:i].sum(), hist[i:].sum()
        if w0 == 0 or w1 == 0:
            continue
        m0 = (hist[:i] * centres[:i]).sum() / w0
        m1 = (hist[i:] * centres[i:]).sum() / w1
        v = w0 * w1 * (m0 - m1) ** 2
        if v > best:
            best, best_t = v, centres[i]
    return float(best_t)


def coarse_fit(land: np.ndarray, water_small: np.ndarray, scales):
    """Best (scale, ox, oy) by FFT cross-correlation of land masks at 1x."""
    target = (~water_small).astype(float) - 0.5
    best = (-1e18, None)
    for s in scales:
        scaled = ndimage.zoom(land.astype(float), s, order=0) - 0.5
        corr = signal.fftconvolve(target, scaled[::-1, ::-1], mode="full")
        iy, ix = np.unravel_index(np.argmax(corr), corr.shape)
        oy = iy - (scaled.shape[0] - 1)
        ox = ix - (scaled.shape[1] - 1)
        if corr[iy, ix] > best[0]:
            best = (corr[iy, ix], (float(s), float(ox), float(oy)))
    return best[1]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--pack", default="beria")
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()
    render, land, k = load_masks(args.pack)
    H, W = land.shape
    bright = render.max(axis=2)
    small = bright[: H * k, : W * k].reshape(H, k, W, k).mean(axis=(1, 3))
    threshold = otsu(bright[::7, ::7].ravel())
    water_small = small < threshold
    print(f"render {render.shape[1]}x{render.shape[0]} = {k}x native; water threshold {threshold:.0f}")
    s0, ox0, oy0 = coarse_fit(land, water_small, np.arange(0.90, 1.30, 0.005))
    print(f"coarse fit: scale {s0:.3f} offset ({ox0:.0f}, {oy0:.0f})")
    # Full-resolution refinement on the coastline distance.
    water = bright < threshold
    water = ndimage.binary_opening(water, iterations=3)
    water = ndimage.binary_closing(water, iterations=3)
    edge = water ^ ndimage.binary_erosion(water, iterations=1)
    dist = ndimage.distance_transform_edt(~edge)
    coast = land ^ ndimage.binary_erosion(land, iterations=1)
    cy, cx = np.nonzero(coast)
    cy, cx = cy.astype(float) + 0.5, cx.astype(float) + 0.5

    def metric(s, ox, oy):
        rx = np.round((cx * s + ox) * k).astype(int)
        ry = np.round((cy * s + oy) * k).astype(int)
        ok = (rx >= 0) & (rx < dist.shape[1]) & (ry >= 0) & (ry < dist.shape[0])
        d = dist[ry[ok], rx[ok]] / k
        return float(np.median(d)), float(np.mean(d)), float(np.percentile(d, 90))

    best = (1e9, (s0, ox0, oy0))
    for rng, st in [((0.01, 6.0, 6.0), (0.0025, 1.0, 1.0)), ((0.003, 1.5, 1.5), (0.0005, 0.25, 0.25)),
            ((0.0005, 0.3, 0.3), (0.0001, 0.05, 0.05))]:
        s0, ox0, oy0 = best[1]
        for s in np.arange(s0 - rng[0], s0 + rng[0] + 1e-9, st[0]):
            for ox in np.arange(ox0 - rng[1], ox0 + rng[1] + 1e-9, st[1]):
                for oy in np.arange(oy0 - rng[2], oy0 + rng[2] + 1e-9, st[2]):
                    m = metric(s, ox, oy)[0]
                    if m < best[0]:
                        best = (m, (float(s), float(ox), float(oy)))
    s, ox, oy = best[1]
    med, mean, p90 = metric(s, ox, oy)
    print(f"fit: render_scale {s:.4f} render_offset_x {ox:.2f} render_offset_y {oy:.2f}")
    print(f"coast distance (native px): median {med:.2f}, mean {mean:.2f}, p90 {p90:.2f}")
    print(f"for reference, no calibration: median {metric(1, 0, 0)[0]:.2f}")
    if args.write:
        path = ROOT / "data/maps.csv"
        rows = list(csv.DictReader(open(path, newline="")))
        fields = list(rows[0].keys())
        for r in rows:
            if r["map_id"] == args.pack:
                r["render_scale"] = f"{s:.4f}"
                r["render_offset_x"] = f"{ox:.2f}"
                r["render_offset_y"] = f"{oy:.2f}"
        with open(path, "w", newline="") as f:
            w = csv.DictWriter(f, fieldnames=fields, lineterminator="\n")
            w.writeheader()
            w.writerows(rows)
        print(f"wrote {path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
