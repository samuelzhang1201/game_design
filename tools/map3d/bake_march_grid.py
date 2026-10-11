"""Bake a pack's MARCH GRID: how steep the ground is where a column would walk
(owner 2026-10-10, spec 2026-10-10-march-slope-detour).

  python3 tools/map3d/bake_march_grid.py [--map ID]   (default: data/maps.csv is_default)

Reads the heights the Terrain3D world was built from — <map3d_dir>/bake/
height_war.r16 and world.json, written by bake_world.py — so the slope a
column is refused is the slope the 3D map DRAWS (the terrace scarps are in
those heights and in no pack table). Writes data/maps/<id>/geography/
march_grid.png: 8-bit grey, lossless, one pixel per army_march_grid_px pack px,
row-major from the pack's corner:

  0..254  the steepest rise per run in the cell, in hundredths (clamped)
  255     water: fewer than army_march_land_min_permille of the cell's
          vertices stand above the waterline

The engine reads it back (MarchPath) and refuses a cell steeper than
army_max_slope, so a threshold change needs no rebake. Generated: never edit
it by hand; build_pack.sh reruns it after bake_world.py.
"""
import argparse
import csv
import json
import math
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from packs import default_pack, map3d_dir  # noqa: E402

WATER = 255


def balance(key):
    """A data/balance.csv value (the engine's MarchPath reads the same rows)."""
    with open(os.path.join(ROOT, "data", "balance.csv"), newline="") as f:
        for row in csv.DictReader(f):
            if row["key"] == key:
                return float(row["value"])
    raise KeyError(key)


def box(a, r):
    """Box blur of radius r (separable, edges held)."""
    if r <= 0:
        return a
    c = np.cumsum(np.pad(a, ((r + 1, r), (0, 0)), mode="edge"), 0)
    a = (c[2 * r + 1:] - c[:-2 * r - 1]) / (2 * r + 1)
    c = np.cumsum(np.pad(a, ((0, 0), (r + 1, r)), mode="edge"), 1)
    return (c[:, 2 * r + 1:] - c[:, :-2 * r - 1]) / (2 * r + 1)


def slope_field(height, sea_y, vertex_m, smooth_m, run_m):
    """Rise per run at every vertex: the heights (the sea held at the waterline,
    so a shore is no cliff) blurred over smooth_m, differenced across run_m."""
    s = box(np.maximum(height, sea_y), int(round(smooth_m / vertex_m)))
    half = max(1, int(round(run_m / vertex_m / 2.0)))
    gx = np.zeros_like(s)
    gy = np.zeros_like(s)
    gx[:, half:-half] = (s[:, 2 * half:] - s[:, :-2 * half]) / (2 * half * vertex_m)
    gy[half:-half, :] = (s[2 * half:, :] - s[:-2 * half, :]) / (2 * half * vertex_m)
    return np.hypot(gx, gy)


def march_grid(height, sea_y, vertex_m, m_per_px, pack_px, grid_px, smooth_m, run_m, land_min):
    """The grid as uint8 rows x cols (see the module's doc)."""
    k = grid_px * m_per_px / vertex_m
    if abs(k - round(k)) > 1e-6:
        raise SystemExit("army_march_grid_px x m_per_px must be a whole number of vertices")
    k = int(round(k))
    cols = math.ceil(pack_px[0] / grid_px)
    rows = math.ceil(pack_px[1] / grid_px)
    slope = slope_field(height, sea_y, vertex_m, smooth_m, run_m)
    land = (height > sea_y).astype(np.float32)
    vh, vw = height.shape
    pad = ((0, max(0, rows * k - vh)), (0, max(0, cols * k - vw)))
    slope = np.pad(slope, pad, mode="edge")[:rows * k, :cols * k]
    land = np.pad(land, pad, mode="edge")[:rows * k, :cols * k]
    steep = slope.reshape(rows, k, cols, k).max(axis=(1, 3))
    share = land.reshape(rows, k, cols, k).mean(axis=(1, 3))
    out = np.clip(np.round(steep * 100.0), 0, WATER - 1).astype(np.uint8)
    out[share * 1000.0 < land_min] = WATER
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--map", default=None, help="map pack id (default: maps.csv is_default)")
    args = ap.parse_args(argv)
    pack = args.map or default_pack()
    bake = os.path.join(map3d_dir(pack), "bake")
    world = json.load(open(os.path.join(bake, "world.json")))
    vw, vh = world["vertices"]
    height = np.fromfile(os.path.join(bake, "height_war.r16"), dtype=np.float16)
    height = height.astype(np.float32).reshape(vh, vw)
    grid = march_grid(height, float(world["sea_y"]), float(world["vertex_m"]), float(world["m_per_px"]),
                      world["pack_px"], int(balance("army_march_grid_px")),
                      balance("army_march_slope_smooth_m"), balance("army_march_slope_run_m"),
                      balance("army_march_land_min_permille"))
    out = os.path.join(ROOT, "data", "maps", pack, "geography", "march_grid.png")
    Image.fromarray(grid, mode="L").save(out, optimize=True)
    land = grid != WATER
    limit = balance("army_max_slope") / 10.0
    blocked = int((land & (grid > limit)).sum())
    print("bake_march_grid: %s %dx%d cells, %d land, %d steeper than army_max_slope -> %s"
          % (pack, grid.shape[1], grid.shape[0], int(land.sum()), blocked, os.path.relpath(out, ROOT)))


if __name__ == "__main__":
    main()
