#!/usr/bin/env python3
"""Plant the 3D map's woods (look route, owner 2026-09-30: "树木也是可以3d建模吗").

Reads a finished bake (bake_world.py's height.r32, world.json, fields.png,
houses.csv, rivers.json) plus the pack's biome weights and roads, and writes
bake/trees.bin: one tree CLUMP per row, float32 x_m, y_m, z_m, yaw_rad,
scale, kind — world metres in the frame of world.json; kind is the clump's
SPECIES, a row of data/screens/map3d/map3d_tree_species.csv.

A clump stands on a blue-noise (Poisson-disk) set no two of whose points are
nearer than data/screens/map3d/map3d_trees.csv `poisson_r_m` (about a clump's footprint;
owner 2026-10-10: 树木有点太密集了，请使用合理的算法), kept with the chance
its ground is wooded: each biome's own share (`biome_<id>` rows), swung by a
slow grove noise so woods gather and open into clearings (taste: clustered,
not scattered), capped inside a wood (`wood_cap`) and opened by glades, with
a few lone clumps on open land. Each clump's species is picked from the
ground under it (`pick_species`: biome shares, height, a slow noise per
species so a mixed wood holds patches of each). Never in water, on a sown field, a road, a river's bank, a
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
HABITS = {"wood": 0, "lone": 1, "hedge": 2, "bank": 3}
WOOD_MAP_STEP = 2   # vertices per woods.png texel (40 m), bake_world's FIELD_MAP_STEP


def load_rules():
    """data/screens/map3d/map3d_trees.csv: (rules {key: number}, {biome id: woodedness})."""
    rules, biome = {}, {}
    with open(os.path.join(ROOT, "data", "screens", "map3d", "map3d_trees.csv")) as f:
        for r in csv.DictReader(f):
            k = r["key"]
            if k.startswith("biome_"):
                biome[int(k[6:])] = float(r["value"])
            else:
                rules[k] = float(r["value"])
    return rules, biome


def load_species(path=None):
    """data/screens/map3d/map3d_tree_species.csv as a list of dicts: kind, habit (HABITS),
    conifer, cells, crowns, spread_m, size, biome weights (16), h_gain, weight,
    enabled — every row, enabled or waiting for its art."""
    out = []
    with open(path or os.path.join(ROOT, "data", "screens", "map3d", "map3d_tree_species.csv")) as f:
        for r in csv.DictReader(f):
            w = np.zeros(16, np.float32)
            for part in r["biomes"].split("|"):
                if part.strip():
                    b, v = part.split(":")
                    w[int(b) - 1] = float(v)
            cells = [int(c) for c in r["cells"].split("|") if c.strip()]
            out.append({"kind": int(r["kind"]), "name": r["name"], "habit": HABITS[r["habit"]],
                        "conifer": r["form"] == "conifer", "cells": cells,
                        "crowns": int(r["crowns"]), "spread_m": float(r["spread_m"]),
                        "size": float(r["size"]), "biomes": w, "h_gain": float(r["h_gain"]),
                        "weight": float(r["weight"]),
                        "enabled": int(r["enabled"]) == 1 and len(cells) > 0})
    return out


def noise_at(seed, x, z, wave):
    """Smooth value noise in 0..1 at points (x, z) in metres, one lattice cell
    per `wave` metres — value_noise's sampled at the points alone."""
    fx, fz = np.asarray(x, np.float64) / wave, np.asarray(z, np.float64) / wave
    x0, z0 = np.floor(fx).astype(np.int64), np.floor(fz).astype(np.int64)
    gx0, gz0 = int(x0.min()) if len(fx) else 0, int(z0.min()) if len(fz) else 0
    gw = int(x0.max() - gx0) + 2 if len(fx) else 2
    gh = int(z0.max() - gz0) + 2 if len(fz) else 2
    g = np.random.default_rng(seed).random((gh, gw))
    tx, tz = fx - x0, fz - z0
    tx, tz = tx * tx * (3 - 2 * tx), tz * tz * (3 - 2 * tz)
    xi, zi = x0 - gx0, z0 - gz0
    a, b = g[zi, xi], g[zi, xi + 1]
    c, d = g[zi + 1, xi], g[zi + 1, xi + 1]
    top = a + (b - a) * tx
    return top + (c + (d - c) * tx - top) * tz


def poisson_disk(width_m, height_m, r, rng, trials):
    """A blue-noise set over [0, width_m) x [0, height_m): no two points
    nearer than r. Dart throwing on a grid of r/sqrt(2) cells (one point a
    cell at most) in nine phases, the cells of one phase three apart so their
    darts cannot meet; each phase throws one dart per empty cell, `trials`
    rounds. Vectorised, and seeded by `rng`: the same call is the same set.
    Returns (N, 2) metres."""
    cell = r / np.sqrt(2.0)
    gw, gh = int(np.ceil(width_m / cell)), int(np.ceil(height_m / cell))
    pad = 3
    px = np.full((gh + 2 * pad, gw + 2 * pad), np.nan, np.float32)
    pz = np.full_like(px, np.nan)
    r2 = np.float32(r * r)
    offs = [(dy, dx) for dy in range(-2, 3) for dx in range(-2, 3)
            if (dy, dx) != (0, 0) and not (abs(dy) == 2 and abs(dx) == 2)]
    for _t in range(int(trials)):
        for oy in range(3):
            for ox in range(3):
                ys = np.arange(oy, gh, 3)
                xs = np.arange(ox, gw, 3)
                if len(ys) == 0 or len(xs) == 0:
                    continue
                sy = slice(oy + pad, oy + pad + 3 * len(ys), 3)
                sx = slice(ox + pad, ox + pad + 3 * len(xs), 3)
                empty = np.isnan(px[sy, sx])
                cx = ((xs[None, :] + rng.random((len(ys), len(xs)))) * cell).astype(np.float32)
                cz = ((ys[:, None] + rng.random((len(ys), len(xs)))) * cell).astype(np.float32)
                ok = empty & (cx < width_m) & (cz < height_m)
                for dy, dx in offs:
                    ny = slice(sy.start + dy, sy.stop + dy, 3)
                    nx = slice(sx.start + dx, sx.stop + dx, 3)
                    d2 = (px[ny, nx] - cx) ** 2 + (pz[ny, nx] - cz) ** 2
                    ok &= ~(d2 < r2)   # NaN (an empty neighbour) compares False
                px[sy, sx] = np.where(ok, cx, px[sy, sx])
                pz[sy, sx] = np.where(ok, cz, pz[sy, sx])
    got = ~np.isnan(px)
    return np.stack([px[got], pz[got]], axis=1).astype(np.float64)


def pick_species(species, habit, shares, hshare, x, z, rules, seed):
    """Each clump's species kind (owner 2026-10-10: 树木的品种过于单一，请根据
    不同的地理环境生成不同树木的模型). Among the enabled rows of the clump's
    habit, the best score wins: the biome shares under it (n x 16) weighed by
    the row's biome weights, times (1 + h_gain x its height as a share of the
    tree line), times the row's weight, times a slow noise of the row's own
    (`species_wave_m`, swing `species_noise`: patches of one species inside a
    mixed wood), times a per-clump dither (`species_dither`) so a patch's
    edge blurs over a few clumps. A habit with no enabled row takes the wood's."""
    habit = np.asarray(habit)
    kinds = np.full(len(habit), -1, np.int32)
    wood = [s for s in species if s["enabled"] and s["habit"] == HABITS["wood"]]
    amp, dith = rules["species_noise"], rules["species_dither"]
    drng = np.random.default_rng(seed + 3)
    for h in HABITS.values():
        rows = [s for s in species if s["enabled"] and s["habit"] == h] or wood
        idx = np.nonzero(habit == h)[0]
        if len(idx) == 0 or not rows:
            continue
        w = np.stack([s["biomes"] for s in rows], axis=1)          # 16 x k
        score = shares[idx] @ w + 0.02
        score *= np.maximum(1.0 + np.outer(hshare[idx], [s["h_gain"] for s in rows]), 0.05)
        score *= np.array([s["weight"] for s in rows])[None, :]
        for j, s in enumerate(rows):
            n = noise_at(seed + 100 + s["kind"], x[idx], z[idx], rules["species_wave_m"])
            score[:, j] *= 1.0 - amp * 0.5 + amp * n
        score *= 1.0 + dith * (drng.random(score.shape) - 0.5)
        kinds[idx] = np.array([s["kind"] for s in rows])[np.argmax(score, axis=1)]
    return kinds


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


def stamp_course(mask, pts, radii):
    """Mark every cell within each sample's own radius (cell units) of a
    river's course: a river is narrow at its source and broad at its mouth,
    and one radius for the whole course (its widest) cleared its whole
    valley of trees."""
    h, w = mask.shape
    pts = np.asarray(pts, dtype=np.float32)
    for a, b, ra, rb in zip(pts[:-1], pts[1:], radii[:-1], radii[1:]):
        n = max(int(np.hypot(*(b - a)) / 0.5) + 1, 2)
        for t in np.linspace(0, 1, n):
            x, y = a + (b - a) * t
            r = ra + (rb - ra) * t
            ri = int(np.ceil(r))
            xi, yi = int(round(x)), int(round(y))
            y0, y1, x0, x1 = max(yi - ri, 0), min(yi + ri + 1, h), max(xi - ri, 0), min(xi + ri + 1, w)
            if y0 >= y1 or x0 >= x1:
                continue
            yy, xx = np.mgrid[y0:y1, x0:x1]
            mask[y0:y1, x0:x1] |= (xx - x) ** 2 + (yy - y) ** 2 <= r * r


def riparian(courses, ok, run, rng, rules, vm):
    """BANKSIDE trees (critic 2026-10-06: the rivers read as ribbons laid on
    the land): a row of clumps along each bank, `riparian_gap_m` out from the
    water's edge and scattered over `riparian_band_m`, offered every
    `riparian_spacing_m` along the course and kept with `riparian_chance` in
    runs (a slow noise, as the hedgerows) — the line of alders and willows
    that shows a river from the air long before its water does. `courses`
    is [(points in metres of the pack frame, widths)], `ok` the cells a
    clump may stand on. Returns the clumps' (x, z) in metres."""
    sp, gap, band = rules["riparian_spacing_m"], rules["riparian_gap_m"], rules["riparian_band_m"]
    out = []
    h, w = ok.shape
    for pts, widths in courses:
        pts = np.asarray(pts, np.float64)
        seg = np.hypot(*np.diff(pts, axis=0).T)
        s = np.concatenate([[0.0], np.cumsum(seg)])
        if s[-1] <= sp:
            continue
        t = np.arange(sp * 0.5, s[-1], sp)
        px, pz = np.interp(t, s, pts[:, 0]), np.interp(t, s, pts[:, 1])
        wl = np.interp(t, s, widths)
        dx, dz = np.gradient(px), np.gradient(pz)
        ln = np.maximum(np.hypot(dx, dz), 1e-6)
        nx, nz = -dz / ln, dx / ln
        for side in (-1.0, 1.0):
            off = wl * 0.5 + gap + rng.random(len(t)) * band
            along = (rng.random(len(t)) - 0.5) * sp * 0.6
            x = px + side * nx * off + dx / ln * along
            z = pz + side * nz * off + dz / ln * along
            xi = np.clip((x / vm).astype(int), 0, w - 1)
            zi = np.clip((z / vm).astype(int), 0, h - 1)
            keep = ok[zi, xi] & (rng.random(len(t)) < rules["riparian_chance"]
                                 * np.clip((run[zi, xi] - 0.3) / 0.3, 0, 1))
            out.append(np.stack([x[keep], z[keep]], axis=1))
    return np.concatenate(out) if out else np.zeros((0, 2))


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", default="")
    MAP = ap.parse_args(argv).map or default_pack()
    OUT = os.path.join(map3d_dir(MAP), "bake")
    PACK = os.path.join(ROOT, "assets", "maps", MAP)
    rules, biome = load_rules()
    species = load_species()
    world = json.load(open(os.path.join(OUT, "world.json")))
    vm = float(world["vertex_m"])
    vw, vh = world["vertices"]
    fw, fh = world["padded"]
    ox, oz = world["pack_origin"]
    cx, cz = world["import_corner"]
    sea_y = float(world["sea_y"])
    m_per_px = float(world["m_per_px"])
    rng = np.random.default_rng(SEED)

    # the ground at vertex resolution, cut back to the pack's own frame: the
    # raw float32 grid when it is as new as the committed half-float copy
    # (bake_world writes both; only the copy is committed, so a checkout that
    # did not bake the world reads the copy, ~1 m)
    raw, half = os.path.join(OUT, "height.r32"), os.path.join(OUT, "height_war.r16")
    if os.path.exists(raw) and (not os.path.exists(half) or os.path.getmtime(raw) >= os.path.getmtime(half)):
        hp = np.fromfile(raw, dtype=np.float32).reshape(fh, fw)
        px0 = int(round((ox - cx) / vm))
        pz0 = int(round((oz - cz) / vm))
        height = np.array(hp[pz0:pz0 + vh, px0:px0 + vw])
        del hp
    else:
        height = np.fromfile(half, dtype=np.float16).reshape(vh, vw).astype(np.float32)
    gy, gx = np.gradient(height, vm)
    slope = np.hypot(gx, gy)
    del gx, gy
    top = float(height.max())

    # each biome's woodedness at vertex resolution; the shares themselves are
    # kept at their own resolution for the species pick
    ws = [np.asarray(Image.open(os.path.join(PACK, f"world_biome_weights_{n}.png")).convert("RGBA"),
                     dtype=np.float32) for n in range(4)]
    wts = np.concatenate(ws, axis=2)
    total = wts.sum(axis=2)
    safe = np.where(total > 0, total, 1.0)
    shares = wts / safe[..., None]
    dens = np.zeros(total.shape, np.float32)
    for bid, d in biome.items():
        dens += shares[..., bid - 1] * d
    open_land = shares[..., 2] + shares[..., 3]   # savanna, grassland
    to_v = lambda a: np.asarray(Image.fromarray(a.astype(np.float32)).resize((vw, vh), Image.BILINEAR))
    dens, open_land = to_v(dens), to_v(open_land)
    del wts, ws, total, safe

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
    # the settled ground round each village (bake_world's settled.png): the
    # woods give way to its crofts, fields and meadows, and thin on its pasture
    settled = np.zeros(bad.shape, np.float32)
    sp_path = os.path.join(OUT, "settled.png")
    if os.path.exists(sp_path):
        sm = np.asarray(Image.open(sp_path).convert("L"), dtype=np.float32) / 255.0
        sv = np.repeat(np.repeat(sm, step, axis=0), step, axis=1)[:vh, :vw]
        settled[:sv.shape[0], :sv.shape[1]] = sv
        del sm, sv
    roads = []
    with open(os.path.join(ROOT, "data", "maps", MAP, "geography", "routes.csv")) as f:
        for r in csv.DictReader(f):
            if r["group"] in ("roads", "trails"):
                roads.append([(float(a) * m_per_px / vm, float(b) * m_per_px / vm)
                              for a, b in (p.split() for p in r["points"].split("|") if p.strip())])
    stamp_lines(bad, roads, rules["road_clear_m"] / vm)
    rv = json.load(open(os.path.join(OUT, "rivers.json")))
    courses = []
    water = np.zeros_like(bad)   # the water itself and a hair beyond it
    for river in rv["rivers"]:
        pts = [((p[0] - ox) / vm, (p[1] - oz) / vm) for p in river["points"]]
        wd = np.array([p[3] for p in river["points"]], np.float64)
        courses.append(([(x * vm, z * vm) for x, z in pts], wd))
        stamp_course(water, pts, (wd * 0.5 + rules["riparian_gap_m"] * 0.5) / vm)
    river_clear = np.zeros_like(bad)   # the woods' clearance; the bankside rows ignore it
    for (pts_m, wd) in courses:
        stamp_course(river_clear, [(x / vm, z / vm) for x, z in pts_m], (wd * 0.5 + rules["river_clear_m"]) / vm)
    with open(os.path.join(OUT, "houses.csv")) as f:
        near = rules["house_clear_m"] / vm
        for r in csv.DictReader(f):
            x, z = (float(r["x_m"]) - ox) / vm, (float(r["z_m"]) - oz) / vm
            xi, zi, rr = int(x), int(z), int(np.ceil(near))
            bad[max(zi - rr, 0):zi + rr + 1, max(xi - rr, 0):xi + rr + 1] = True
    bank_ok = ~bad & ~water   # the bankside rows' ground: everything else's "never" holds
    bad |= river_clear
    del water, river_clear

    # groves: a slow noise swings the woodedness so woods gather and open up
    grove = value_noise(rng, vw, vh, rules["grove_wave_m"] / vm) * 0.65 \
        + value_noise(rng, vw, vh, rules["grove_wave_m"] * 0.3 / vm) * 0.35
    chance = dens * np.clip(1.0 + rules["grove_gain"] * (grove - 0.5) * 2.0, 0, 2)
    chance *= 1.0 + rules["fray_gain"] * (value_noise(np.random.default_rng(SEED + 11), vw, vh,
                                                     rules["fray_wave_m"] / vm) - 0.5) * 2.0
    # the settled ground thins the woods BEFORE the edge squeeze, so what is
    # left still gathers into woods with edges, never a scatter
    chance *= 1.0 - rules["settled_clear"] * settled
    # a wood has an edge: squeeze the chance toward 0 or 1 round its middle
    e = rules["edge_sharp"]
    chance = np.clip((chance - 0.5) * e + 0.5, 0, 1) * (dens > 0.02)
    # ...never a carpet inside it: capped, and opened by glades (a finer
    # noise; owner 2026-10-10: 树木有点太密集了)
    glade = value_noise(np.random.default_rng(SEED + 13), vw, vh, rules["glade_wave_m"] / vm)
    chance *= rules["wood_cap"] * (1.0 - rules["glade_depth"] * np.clip(
        (glade - rules["glade_cut"]) / max(rules["glade_soft"], 1e-3), 0, 1))
    del glade
    chance = np.maximum(chance, rules["lone_chance"] * open_land)
    chance[bad] = 0.0
    chance[sown_mask & (chance < rules["sown_keep_chance"])] = 0.0

    # candidates: a blue-noise set, no two nearer than a clump's footprint
    pts = poisson_disk(vw * vm, vh * vm, rules["poisson_r_m"], rng, rules["poisson_trials"])
    X, Z = pts[:, 0], pts[:, 1]
    del pts
    xi = np.clip((X / vm).astype(int), 0, vw - 1)
    zi = np.clip((Z / vm).astype(int), 0, vh - 1)
    c = chance[zi, xi]
    keep = rng.random(c.shape) < c
    X, Z, xi, zi = X[keep], Z[keep], xi[keep], zi[keep]
    # HEDGEROW trees (visual review 2026-10-06: the fields read as flat fills
    # laid on the land): along the balks and croft hedges of bake_world's
    # field_edges.png, in runs (a slow noise) — their own stream, so the woods
    # above are unchanged
    hedge = np.zeros(len(X), bool)
    bank = np.zeros(len(X), bool)
    ep = os.path.join(OUT, "field_edges.png")
    if rules.get("hedge_chance", 0.0) > 0.0 and os.path.exists(ep):
        hrng = np.random.default_rng(SEED + 31)
        em = np.asarray(Image.open(ep).convert("L"), dtype=np.float32)
        hsp = rules["hedge_spacing_m"]
        hx, hz = np.meshgrid(np.arange(hsp * 0.5, vw * vm, hsp), np.arange(hsp * 0.5, vh * vm, hsp))
        hx = (hx + hrng.uniform(-0.5, 0.5, hx.shape) * hsp).ravel()
        hz = (hz + hrng.uniform(-0.5, 0.5, hz.shape) * hsp).ravel()
        hxi = np.clip((hx / vm).astype(int), 0, vw - 1)
        hzi = np.clip((hz / vm).astype(int), 0, vh - 1)
        eb = em[hzi, hxi]
        runs = value_noise(np.random.default_rng(SEED + 32), vw, vh, rules["hedge_run_m"] / vm)[hzi, hxi]
        dm = (eb - 128.0) / 2.0   # bake_world EDGE_MAP_ZERO / _PER_M: metres inside a field's edge
        take = (dm >= 0.0) & (dm < rules["hedge_band_m"]) & ~bad[hzi, hxi] \
            & (hrng.random(hx.shape) < rules["hedge_chance"] * np.clip((runs - 0.35) / 0.3, 0, 1))
        X, Z = np.concatenate([X, hx[take]]), np.concatenate([Z, hz[take]])
        xi, zi = np.concatenate([xi, hxi[take]]), np.concatenate([zi, hzi[take]])
        hedge = np.concatenate([hedge, np.ones(int(take.sum()), bool)])
        bank = np.concatenate([bank, np.zeros(int(take.sum()), bool)])
        del em, hx, hz, hxi, hzi, eb, runs, take
    # BANKSIDE rows along every river (their own stream)
    if rules.get("riparian_chance", 0.0) > 0.0:
        rrun = value_noise(np.random.default_rng(SEED + 42), vw, vh, rules["riparian_run_m"] / vm)
        rip = riparian(courses, bank_ok, rrun, np.random.default_rng(SEED + 41), rules, vm)
        del rrun
        rxi = np.clip((rip[:, 0] / vm).astype(int), 0, vw - 1)
        rzi = np.clip((rip[:, 1] / vm).astype(int), 0, vh - 1)
        X, Z = np.concatenate([X, rip[:, 0]]), np.concatenate([Z, rip[:, 1]])
        xi, zi = np.concatenate([xi, rxi]), np.concatenate([zi, rzi])
        hedge = np.concatenate([hedge, np.ones(len(rip), bool)])
        bank = np.concatenate([bank, np.ones(len(rip), bool)])
        print("bake_trees: %d bankside clumps" % len(rip))
    # the ground's height under the clump, bilinear
    fx, fz = X / vm, Z / vm
    x0 = np.clip(np.floor(fx).astype(int), 0, vw - 2)
    z0 = np.clip(np.floor(fz).astype(int), 0, vh - 2)
    tx, tz = fx - x0, fz - z0
    y = (height[z0, x0] * (1 - tx) * (1 - tz) + height[z0, x0 + 1] * tx * (1 - tz)
         + height[z0 + 1, x0] * (1 - tx) * tz + height[z0 + 1, x0 + 1] * tx * tz)
    # the species by the ground under each clump: its habit first (a bank
    # row, a hedgerow, a lone clump on open land, else a wood)
    habit = np.where(bank, HABITS["bank"], np.where(hedge, HABITS["hedge"],
                     np.where(dens[zi, xi] < 0.05, HABITS["lone"], HABITS["wood"])))
    sh_h, sh_w = shares.shape[:2]
    bx = np.clip((X / (vw * vm) * sh_w).astype(int), 0, sh_w - 1)
    bz = np.clip((Z / (vh * vm) * sh_h).astype(int), 0, sh_h - 1)
    line = top * rules["max_height_share"]
    hshare = np.clip((y - sea_y) / max(line - sea_y, 1.0), 0, 1)
    kind = pick_species(species, habit, shares[bz, bx].reshape(len(X), 16), hshare, X, Z, rules, SEED + 7)
    del shares
    # the mask tested the vertex a clump fell in; its own spot, between four
    # vertices, can still dip under the water at a shore — the last word is
    # the ground under the clump itself
    dry = y >= sea_y + rules["min_above_sea_m"]
    X, Z, y, kind, xi, zi, hedge, bank = X[dry], Z[dry], y[dry], kind[dry], xi[dry], zi[dry], hedge[dry], bank[dry]
    yaw = rng.uniform(0, 2 * np.pi, len(X))
    scale = rng.uniform(rules["scale_min"], rules["scale_max"], len(X))
    scale = np.where(hedge, scale * np.where(bank, rules["riparian_scale"], rules["hedge_scale"]), scale)
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
    # a clump's crowns cover its crowns' discs, at most its footprint's
    by_kind = {s["kind"]: s for s in species}
    cr = rules["crown_r_m"]
    reach = np.array([np.sqrt(min(by_kind[k]["crowns"] * cr * cr, (by_kind[k]["spread_m"] + cr) ** 2))
                      * by_kind[k]["size"] for k in range(max(by_kind) + 1)])
    conifer = np.array([by_kind[k]["conifer"] for k in range(max(by_kind) + 1)])
    area = (reach[kind] * scale) ** 2 * np.pi / (step * vm) ** 2
    np.add.at(cover, (tz, tx), area)
    np.add.at(con, (tz, tx), area * conifer[kind])
    blur = max(int(rules["canopy_blur_texels"]), 0)
    if blur:
        k = np.ones(2 * blur + 1, np.float32) / (2 * blur + 1)
        for a in (cover, con):
            a[:] = np.apply_along_axis(lambda r: np.convolve(r, k, "same"), 1, a)
            a[:] = np.apply_along_axis(lambda r: np.convolve(r, k, "same"), 0, a)
    share = np.where(cover > 1e-4, con / np.maximum(cover, 1e-4), 0)
    # the canopy as seen from above closes over the gaps between crowns:
    # what carries the wood once no tree is drawn (the height gate)
    cover *= rules.get("canopy_gain", 1.0)
    img = np.zeros((wh, ww, 4), np.uint8)
    img[..., 0] = np.round(np.clip(cover, 0, 1) * 255)
    img[..., 1] = np.round(np.clip(share, 0, 1) * 255)
    img[..., 3] = 255
    Image.fromarray(img, "RGBA").save(os.path.join(OUT, "woods.png"))
    counts = {s["name"]: int((kind == s["kind"]).sum()) for s in species if s["enabled"]}
    crowns = int(sum(by_kind[k]["crowns"] * n for k, n in zip(*np.unique(kind, return_counts=True))))
    print("bake_trees: %d clumps, %d crowns %s" % (len(rows), crowns, json.dumps(counts)))


if __name__ == "__main__":
    main()
