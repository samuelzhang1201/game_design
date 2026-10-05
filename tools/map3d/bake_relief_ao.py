#!/usr/bin/env python3
"""Bake how much of the sky each patch of ground sees (visual review 2026-10-05).

The 3D map's sun rides high (owner 2026-09-28: the sun models the ground, it
never covers it), so slopes facing the camera get little modelling and the
land reads flat at the opening zoom. Sky occlusion is the light the map
lacks: a valley floor, a terrace's foot and a gorge see less of the sky and
read darker; it has no direction, so it never fights the turning sun.

Reads the finished bake's bake/height_war.r16 (float16 metres over the pack's
own vertices, bake_world.py) and world.json, and writes bake/relief_ao.png:
one 8-bit texel per 2 x 2 vertices (40 m, as woods.png and fields.png), 255
where the whole sky is seen. For each texel it walks data/map3d_bake.csv
`relief_ao_dirs` directions out to each `relief_ao_radii_m`, keeps the
steepest rise toward the horizon, and averages sin(horizon angle) over the
directions (horizon-based ambient occlusion). The sea is held at the water
plane, so a coast never darkens toward the sea floor. Deterministic.

  python3 tools/map3d/bake_relief_ao.py [--map ID]
"""
import argparse
import csv
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from packs import default_pack, map3d_dir  # noqa: E402

STEP = 2  # vertices per relief_ao.png texel (40 m), bake_world's FIELD_MAP_STEP


def sky_seen(height: np.ndarray, texel_m: float, dirs: int, radii_m: list) -> np.ndarray:
    """1 - mean over `dirs` directions of sin(the highest horizon angle out
    to each of `radii_m`), on a height grid of `texel_m` spacing."""
    pad = int(max(radii_m) / texel_m) + 2
    hp = np.pad(height, pad, mode="edge")
    rows, cols = height.shape
    occ = np.zeros_like(height)
    for k in range(dirs):
        a = 2.0 * np.pi * k / dirs
        best = np.zeros_like(height)
        for r in radii_m:
            ox, oz = int(round(np.cos(a) * r / texel_m)), int(round(np.sin(a) * r / texel_m))
            if ox == 0 and oz == 0:
                continue
            ahead = hp[pad + oz:pad + oz + rows, pad + ox:pad + ox + cols]
            best = np.maximum(best, (ahead - height) / (np.hypot(ox, oz) * texel_m))
        occ += np.sin(np.arctan(best))
    return 1.0 - occ / dirs


def blur(img: np.ndarray, sigma: float) -> np.ndarray:
    """A separable Gaussian of `sigma` texels, edges held."""
    if sigma <= 0.0:
        return img
    r = int(np.ceil(sigma * 3))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    rows, cols = img.shape
    p = np.pad(img, ((0, 0), (r, r)), mode="edge")
    across = sum(k[i] * p[:, i:i + cols] for i in range(2 * r + 1))
    p = np.pad(across, ((r, r), (0, 0)), mode="edge")
    return sum(k[i] * p[i:i + rows, :] for i in range(2 * r + 1))


def load_rules() -> dict:
    """data/map3d_bake.csv as {key: text} (bake_world.load_rules' table)."""
    with open(os.path.join(ROOT, "data", "map3d_bake.csv")) as f:
        return {r["key"]: r["value"] for r in csv.DictReader(f)}


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--map", default="")
    args = ap.parse_args()
    bake = os.path.join(map3d_dir(args.map or default_pack()), "bake")
    world = json.load(open(os.path.join(bake, "world.json")))
    vx, vz = world["vertices"]
    h = np.fromfile(os.path.join(bake, "height_war.r16"), dtype=np.float16)
    h = np.maximum(h.astype(np.float32).reshape(vz, vx), float(world["sea_y"]))
    h = h[:vz // STEP * STEP, :vx // STEP * STEP]
    h = h.reshape(vz // STEP, STEP, vx // STEP, STEP).mean(axis=(1, 3))
    rules = load_rules()
    radii = [float(r) for r in str(rules["relief_ao_radii_m"]).split("|")]
    ao = sky_seen(h, float(world["vertex_m"]) * STEP, int(rules["relief_ao_dirs"]), radii)
    ao = blur(ao, float(rules["relief_ao_blur_texels"]))
    out = os.path.join(bake, "relief_ao.png")
    Image.fromarray((np.clip(ao, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8), "L").save(out)
    print("bake_relief_ao: %s (%d x %d), sky seen p5 %.2f p50 %.2f"
          % (out, ao.shape[1], ao.shape[0], np.percentile(ao, 5), np.percentile(ao, 50)))


if __name__ == "__main__":
    main()
