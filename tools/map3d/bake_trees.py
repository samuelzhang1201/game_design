#!/usr/bin/env python3
"""Plant the 3D map's woods (look route, owner 2026-09-30: "树木也是可以3d建模吗").

Reads a finished bake (bake_world.py's height.r32, world.json, fields.png,
houses.csv, rivers.json) plus the pack's biome weights and roads, and writes
bake/trees.bin: one tree CLUMP per row, float32 x_m, y_m, z_m, yaw_rad,
scale, kind (see KINDS) — world metres in the frame of world.json.

A clump stands on a jittered grid every data/map3d_trees.csv `spacing_m`,
kept with the chance its ground is wooded: each biome's own share
(`biome_<id>` rows), swung by a slow grove noise so woods gather and open
into clearings (taste: clustered, not scattered), with a few lone clumps on
open land. Never in water, on a sown field, a road, a river's bank, a
settlement, a cliff or above the snow line — the same structural "never"
bake_houses.py keeps for houses. Seeded: a re-run plants the same wood.

  python3 tools/map3d/bake_trees.py [--map ID]
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
SEED = 20260930
KINDS = {"broadleaf": 0, "conifer": 1, "lone": 2}
WOOD_MAP_STEP = 2   # vertices per woods.png texel (40 m), bake_world's FIELD_MAP_STEP


def load_rules():
    rules, biome = {}, {}
    with open(os.path.join(ROOT, "data", "map3d_trees.csv")) as f:
        for r in csv.DictReader(f):
            k = r["key"]
            if k.startswith("biome_"):
                d, c = r["value"].split("|")
                biome[int(k[6:])] = (float(d), float(c))
            else:
                rules[k] = float(r["value"])
    return rules, biome


def value_noise(rng, w, h, wave):
    """Smooth value noise in 0..1 on a w x h grid, one lattice cell per `wave` cells."""
    gw, gh = int(w / wave) + 3, int(h / wave) + 3
    g = rng.random((gh, gw)).astype(np.float32)
    ys = np.arange(h, dtype=np.float32) / wave
    xs = np.arange(w, dtype=np.float32) / wave
    y0, x0 = np.floor(ys).astype(int), np.floor(xs).astype(int)
    fy, fx = ys - y0, xs - x0
    fy, fx = fy * fy * (3 - 2 * fy), fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0]
    b = g[y0][:, x0 + 1]
    c = g[y0 + 1][:, x0]
    d = g[y0 + 1][:, x0 + 1]
    top = a + (b - a) * fx[None, :]
    bot = c + (d - c) * fx[None, :]
    return top + (bot - top) * fy[:, None]


def stamp_lines(mask, lines, radius_cells):
    """Mark every cell within radius_cells of any polyline (cell units)."""
    h, w = mask.shape
    r = int(np.ceil(radius_cells))
    for pts in lines:
        pts = np.asarray(pts, dtype=np.float32)
        for a, b in zip(pts[:-1], pts[1:]):
            n = max(int(np.hypot(*(b - a)) / 0.5) + 1, 2)
            for t in np.linspace(0, 1, n):
                x, y = a + (b - a) * t
                xi, yi = int(round(x)), int(round(y))
                mask[max(yi - r, 0):min(yi + r + 1, h), max(xi - r, 0):min(xi + r + 1, w)] = True


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", default="")
    MAP = ap.parse_args(argv).map or default_pack()
    OUT = os.path.join(map3d_dir(MAP), "bake")
    PACK = os.path.join(ROOT, "assets", "maps", MAP)
    rules, biome = load_rules()
    world = json.load(open(os.path.join(OUT, "world.json")))
    vm = float(world["vertex_m"])
    vw, vh = world["vertices"]
    fw, fh = world["padded"]
    ox, oz = world["pack_origin"]
    cx, cz = world["import_corner"]
    sea_y = float(world["sea_y"])
    m_per_px = float(world["m_per_px"])
    rng = np.random.default_rng(SEED)

    # the ground at vertex resolution, cut back to the pack's own frame
    hp = np.fromfile(os.path.join(OUT, "height.r32"), dtype=np.float32).reshape(fh, fw)
    px0 = int(round((ox - cx) / vm))
    pz0 = int(round((oz - cz) / vm))
    height = hp[pz0:pz0 + vh, px0:px0 + vw]
    del hp
    gy, gx = np.gradient(height, vm)
    slope = np.hypot(gx, gy)
    del gx, gy
    top = float(height.max())

    # each biome's woodedness and conifer share at vertex resolution
    ws = [np.asarray(Image.open(os.path.join(PACK, f"world_biome_weights_{n}.png")).convert("RGBA"),
                     dtype=np.float32) for n in range(4)]
    wts = np.concatenate(ws, axis=2)
    total = wts.sum(axis=2)
    safe = np.where(total > 0, total, 1.0)
    dens = np.zeros(total.shape, np.float32)
    coni = np.zeros(total.shape, np.float32)
    for bid, (d, c) in biome.items():
        share = wts[..., bid - 1] / safe
        dens += share * d
        coni += share * d * c
    coni = np.where(dens > 0, coni / np.maximum(dens, 1e-6), 0)
    open_land = (wts[..., 2] + wts[..., 3]) / safe   # savanna, grassland
    to_v = lambda a: np.asarray(Image.fromarray(a.astype(np.float32)).resize((vw, vh), Image.BILINEAR))
    dens, coni, open_land = to_v(dens), to_v(coni), to_v(open_land)
    del wts, ws

    # never here: water, sown fields, roads, rivers, settlements, cliffs, snow
    bad = height < sea_y + rules["min_above_sea_m"]
    bad |= slope > rules["max_slope"]
    bad |= height > top * rules["max_height_share"]
    fm = np.asarray(Image.open(os.path.join(OUT, "fields.png")).convert("RGB"), dtype=np.uint8)
    step = vw // fm.shape[1] if fm.shape[1] else 2
    sown = fm.min(axis=2) < 250
    sown_v = np.repeat(np.repeat(sown, step, axis=0), step, axis=1)[:vh, :vw]
    sown_mask = np.zeros_like(bad)
    sown_mask[:sown_v.shape[0], :sown_v.shape[1]] = sown_v
    del fm, sown, sown_v
    roads = []
    with open(os.path.join(ROOT, "data", "maps", MAP, "geography", "routes.csv")) as f:
        for r in csv.DictReader(f):
            if r["group"] in ("roads", "trails"):
                roads.append([(float(a) * m_per_px / vm, float(b) * m_per_px / vm)
                              for a, b in (p.split() for p in r["points"].split("|") if p.strip())])
    stamp_lines(bad, roads, rules["road_clear_m"] / vm)
    rv = json.load(open(os.path.join(OUT, "rivers.json")))
    for river in rv["rivers"]:
        pts = [((p[0] - ox) / vm, (p[1] - oz) / vm) for p in river["points"]]
        wmax = max(p[3] for p in river["points"])
        stamp_lines(bad, [pts], (wmax * 0.5 + rules["river_clear_m"]) / vm)
    with open(os.path.join(OUT, "houses.csv")) as f:
        near = rules["house_clear_m"] / vm
        for r in csv.DictReader(f):
            x, z = (float(r["x_m"]) - ox) / vm, (float(r["z_m"]) - oz) / vm
            xi, zi, rr = int(x), int(z), int(np.ceil(near))
            bad[max(zi - rr, 0):zi + rr + 1, max(xi - rr, 0):xi + rr + 1] = True

    # groves: a slow noise swings the woodedness so woods gather and open up
    grove = value_noise(rng, vw, vh, rules["grove_wave_m"] / vm) * 0.65 \
        + value_noise(rng, vw, vh, rules["grove_wave_m"] * 0.3 / vm) * 0.35
    chance = dens * np.clip(1.0 + rules["grove_gain"] * (grove - 0.5) * 2.0, 0, 2)
    # a wood has an edge: squeeze the chance toward 0 or 1 round its middle
    e = rules["edge_sharp"]
    chance = np.clip((chance - 0.5) * e + 0.5, 0, 1) * (dens > 0.02)
    chance = np.maximum(chance, rules["lone_chance"] * open_land)
    chance[bad] = 0.0
    chance[sown_mask & (chance < rules["sown_keep_chance"])] = 0.0

    # candidates on a jittered grid
    sp = rules["spacing_m"]
    gxs = np.arange(sp * 0.5, vw * vm, sp)
    gzs = np.arange(sp * 0.5, vh * vm, sp)
    X, Z = np.meshgrid(gxs, gzs)
    X = X + rng.uniform(-0.5, 0.5, X.shape) * sp * rules["jitter"]
    Z = Z + rng.uniform(-0.5, 0.5, Z.shape) * sp * rules["jitter"]
    X, Z = X.ravel(), Z.ravel()
    xi = np.clip((X / vm).astype(int), 0, vw - 1)
    zi = np.clip((Z / vm).astype(int), 0, vh - 1)
    c = chance[zi, xi]
    keep = rng.random(c.shape) < c
    X, Z, xi, zi = X[keep], Z[keep], xi[keep], zi[keep]
    # the ground's height under the clump, bilinear
    fx, fz = X / vm, Z / vm
    x0 = np.clip(np.floor(fx).astype(int), 0, vw - 2)
    z0 = np.clip(np.floor(fz).astype(int), 0, vh - 2)
    tx, tz = fx - x0, fz - z0
    y = (height[z0, x0] * (1 - tx) * (1 - tz) + height[z0, x0 + 1] * tx * (1 - tz)
         + height[z0 + 1, x0] * (1 - tx) * tz + height[z0 + 1, x0 + 1] * tx * tz)
    species = value_noise(np.random.default_rng(SEED + 7), vw, vh, rules["species_wave_m"] / vm)
    kind = np.where(species[zi, xi] < coni[zi, xi], KINDS["conifer"], KINDS["broadleaf"])
    del species
    kind = np.where(dens[zi, xi] < 0.05, KINDS["lone"], kind)
    # the mask tested the vertex a clump fell in; its own spot, between four
    # vertices, can still dip under the water at a shore — the last word is
    # the ground under the clump itself
    dry = y >= sea_y + rules["min_above_sea_m"]
    X, Z, y, kind, xi, zi = X[dry], Z[dry], y[dry], kind[dry], xi[dry], zi[dry]
    yaw = rng.uniform(0, 2 * np.pi, len(X))
    scale = rng.uniform(rules["scale_min"], rules["scale_max"], len(X))
    rows = np.stack([X + ox, y, Z + oz, yaw, scale, kind.astype(np.float32)], axis=1).astype(np.float32)
    rows.tofile(os.path.join(OUT, "trees.bin"))
    # the woods' canopy for the ground shader (Map3DGroundTint): one texel per
    # WOOD_MAP_STEP vertices from the pack's own corner, R the share of the
    # texel under a clump's crowns, G the conifer share — what carries the
    # wood where no tree is drawn (far out) and darkens the floor under it
    step = WOOD_MAP_STEP
    ww, wh = vw // step, vh // step
    cover = np.zeros((wh, ww), np.float32)
    con = np.zeros((wh, ww), np.float32)
    tx = np.clip(((X / vm) / step).astype(int), 0, ww - 1)
    tz = np.clip(((Z / vm) / step).astype(int), 0, wh - 1)
    area = (rules["crown_reach_m"] * scale) ** 2 * np.pi / (step * vm) ** 2
    np.add.at(cover, (tz, tx), area)
    np.add.at(con, (tz, tx), area * (kind == KINDS["conifer"]))
    blur = max(int(rules["canopy_blur_texels"]), 0)
    if blur:
        k = np.ones(2 * blur + 1, np.float32) / (2 * blur + 1)
        for a in (cover, con):
            a[:] = np.apply_along_axis(lambda r: np.convolve(r, k, "same"), 1, a)
            a[:] = np.apply_along_axis(lambda r: np.convolve(r, k, "same"), 0, a)
    share = np.where(cover > 1e-4, con / np.maximum(cover, 1e-4), 0)
    img = np.zeros((wh, ww, 4), np.uint8)
    img[..., 0] = np.round(np.clip(cover, 0, 1) * 255)
    img[..., 1] = np.round(np.clip(share, 0, 1) * 255)
    img[..., 3] = 255
    Image.fromarray(img, "RGBA").save(os.path.join(OUT, "woods.png"))
    counts = {k: int((kind == v).sum()) for k, v in KINDS.items()}
    print("bake_trees: %d clumps %s" % (len(rows), json.dumps(counts)))


if __name__ == "__main__":
    main()
