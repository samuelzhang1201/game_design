"""Bake a map pack into Terrain3D import maps at campaign scale
(owner 2026-09-18: 50 m per pack px, a 128 x 46 km world, vertex every 20 m).

Writes assets/map3d/<map>/bake/:
  height.r32    float32 metres, row-major, padded onto whole regions
  control.r32   float32 carrying Terrain3D control bits (base/overlay/blend)
  color.rgba8   Terrain3D colour map: sRGB multiplier on the ground + roughness
  world.json    sizes, vertex spacing, world origin of pack px (0,0)
Its look rules live in data/map3d_bake.csv and in constants here;
build_terrain.gd only imports.
  python3 tools/map3d/bake_world.py [--map ID]   (default: data/maps.csv is_default)

HEIGHT does NOT read world_relief.png: its synthesized detail was tuned for
the 2D canvas (16 px wavelength, 22 height units), which at 50 m/px is a
660 m bump every 800 m — the "blanket of bubbles". The land is the pack's
own cell heights, smoothed, plus ridges made for this scale.
"""
import argparse
import csv
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from packs import default_pack  # noqa: E402

TEX = os.path.join(ROOT, "assets", "map3d", "textures")
RULES_PATH = os.path.join(ROOT, "data", "map3d_bake.csv")
SEED = 954159497         # a look, never simulation: the same for every pack

M_PER_PX = 50.0          # world metres per pack px
VERTEX_M = 20.0          # Terrain3D vertex_spacing
REGION = 2048            # Terrain3D region_size (vertices)
SEA_LEVEL = 20.0         # Azgaar height of the waterline
LAND_M_PER_UNIT = 30.0   # ~2400 m for the highest cells
SEA_M_PER_UNIT = 15.0    # ~300 m for the deepest sea
BASE_BLUR_PX = 7         # box radius (pack px, twice) turning cells (~26 px) into landforms

# Ridges at campaign scale: ridged value noise, octave wavelengths in metres,
# faded in with the ground's height so plains stay plains, held down near the
# coast so the shoreline keeps the pack's shape.
RIDGE_WAVES_M = (6000.0, 3000.0, 1500.0, 750.0, 380.0)
RIDGE_GAIN = 0.5         # amplitude falloff per octave
RIDGE_M = 520.0          # full amplitude where the ground is highest
RIDGE_FROM_M = 150.0     # below this the ridges fade to nothing...
RIDGE_FULL_M = 1600.0    # ...and reach full strength here
RIDGE_COAST_M = 1200.0   # fade-in distance from the shore

WEIGHT_BLUR_PX = 5       # box radius (pack px) softening biome weights (3 left 50 m stair-steps on forest edges)
BEACH_M = 100.0          # sand reaches this far inland
BEACH_MAX_M = 40.0       # and no higher

# Texture ids = build_terrain.gd TEXTURES order.
CLIFF, GRASS, LEAVES, DIRT, ROCKY, SOIL, SAND, FOREST = range(8)
NT = 8
TEXTURE_KEYS = ["cliff", "leafy_grass", "dry_decay_leaves", "dirt_floor", "rocky_trail",
                "excavated_soil_wall", "sand_03", "leafy_grass"]
BIOME_MIX = {
    1: {SAND: 1.0},
    2: {DIRT: 0.8, ROCKY: 0.2},
    3: {GRASS: 0.5, DIRT: 0.5},
    4: {GRASS: 1.0},
    5: {FOREST: 0.5, GRASS: 0.5},
    6: {FOREST: 0.75, LEAVES: 0.25},
    7: {FOREST: 0.8, GRASS: 0.2},
    8: {FOREST: 0.8, LEAVES: 0.2},
    9: {FOREST: 0.6, LEAVES: 0.2, DIRT: 0.2},
    10: {DIRT: 0.5, ROCKY: 0.5},
    11: {CLIFF: 1.0},
    12: {GRASS: 0.5, DIRT: 0.5},
    13: {GRASS: 0.75, ROCKY: 0.25},
    14: {GRASS: 0.3, ROCKY: 0.4, CLIFF: 0.3},
    15: {CLIFF: 1.0},
}
SLOPE_ROCKY = (0.82, 0.93)   # land slope percentiles
SLOPE_CLIFF = (0.93, 0.99)

# COLOUR MAP: what each texture should read as from far away (sRGB). Terrain3D
# multiplies the ground by the map, so a target is reached by the ratio to the
# texture's own mean colour, in linear light, and can only darken.
FAR_COLOR = {
    CLIFF: "#7E7B77", GRASS: "#6F7A40", LEAVES: "#4E4A2C", DIRT: "#9A7A55",
    ROCKY: "#7C7264", SOIL: "#5E4A30", SAND: "#6B604E", FOREST: "#3A5026",
}
MACRO_WAVE_M = 9000.0    # large patches of lighter and darker country
# (their depth and the green-yellow drift are data/map3d_bake.csv macro_*)


def box(a, r):
    """Mean over the (2r+1) square, clipped at the edges."""
    if r <= 0:
        return a.astype(np.float32)
    out = a.astype(np.float64)
    for axis in (0, 1):
        pad = [(1, 0) if ax == axis else (0, 0) for ax in (0, 1)]
        c = np.cumsum(np.pad(out, pad), axis=axis)
        n = out.shape[axis]
        idx = np.arange(n)
        hi = np.minimum(idx + r + 1, n)
        lo = np.maximum(idx - r, 0)
        if axis == 0:
            out = (c[hi, :] - c[lo, :]) / (hi - lo)[:, None]
        else:
            out = (c[:, hi] - c[:, lo]) / (hi - lo)[None, :]
    return out.astype(np.float32)


def resize(a, w, h):
    return np.asarray(Image.fromarray(a.astype(np.float32), mode="F").resize((w, h), Image.BICUBIC),
                      dtype=np.float32)


def value_noise(rng, w, h, wave):
    """Smooth noise in 0..1 with features `wave` samples across."""
    gw, gh = int(w / wave) + 4, int(h / wave) + 4
    grid = rng.random((gh, gw), dtype=np.float32)
    big = resize(grid, int(gw * wave), int(gh * wave))
    ox, oy = rng.integers(0, int(wave)), rng.integers(0, int(wave))
    return np.clip(big[oy:oy + h, ox:ox + w], 0, 1)


def distance_steps(mask, steps):
    """For each cell, how many 4-neighbour dilations of `mask` reach it (capped)."""
    dist = np.full(mask.shape, steps, dtype=np.float32)
    m = mask.copy()
    dist[m] = 0
    for s in range(1, steps):
        n = m.copy()
        n[1:, :] |= m[:-1, :]
        n[:-1, :] |= m[1:, :]
        n[:, 1:] |= m[:, :-1]
        n[:, :-1] |= m[:, 1:]
        dist[n & ~m] = s
        m = n
    return dist


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float64), 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def hex_rgb(h):
    return np.array([int(h[i:i + 2], 16) for i in (1, 3, 5)]) / 255.0


def load_rules(path=RULES_PATH):
    """data/map3d_bake.csv as {key: float}."""
    with open(path) as f:
        return {r["key"]: float(r["value"]) for r in csv.DictReader(f)}


def read_loops(path):
    """geography/coasts.csv -> (land loops, lake loops), each a list of (x, y) pack px."""
    land, lakes = [], []
    with open(path) as f:
        for r in csv.DictReader(f):
            pts = [tuple(map(float, p.split())) for p in r["points"].split("|")]
            (land if r["kind"] == "land" else lakes).append(pts)
    return land, lakes


def coverage(land_loops, lake_loops, vw, vh, k, ss=4):
    """Share (0..1) of each vertex's square that is land: the loops filled at
    `ss` samples per vertex each way, lakes cut out, then averaged. Vertex v
    sits at pack px v / k, the centre of its supersampled block."""
    img = Image.new("L", (vw * ss, vh * ss), 0)
    draw = ImageDraw.Draw(img)
    # PIL fills pixel i when the point i (not its centre i + 0.5) is inside,
    # so shift by half a sample less: an edge through a vertex reads 0.5.
    half = ss * 0.5 - 0.5
    for loops, fill in ((land_loops, 255), (lake_loops, 0)):
        for pts in loops:
            if len(pts) >= 3:
                draw.polygon([(x * k * ss + half, y * k * ss + half) for x, y in pts], fill=fill)
    full = np.asarray(img)
    out = np.empty((vh, vw), dtype=np.float32)
    for y0 in range(0, vh, 256):
        y1 = min(y0 + 256, vh)
        blk = full[y0 * ss:y1 * ss].reshape(y1 - y0, ss, vw, ss).astype(np.uint16)
        out[y0:y1] = blk.sum(axis=(1, 3)) / (255.0 * ss * ss)
    return out


def shore_heights(height, cov, sea_y, shore_m):
    """Land (cov 1) at least shore_m over the water plane, sea (cov 0) at
    least shore_m under it, and the fringe ramped through it so the coast
    crosses the plane where the loop does."""
    out = np.where(cov >= 1.0, np.maximum(height, sea_y + shore_m), height)
    out = np.where(cov <= 0.0, np.minimum(out, sea_y - shore_m), out)
    fringe = (cov > 0.0) & (cov < 1.0)
    return np.where(fringe, sea_y + shore_m * (2.0 * cov - 1.0), out).astype(np.float32)


def sample_bilinear(a, xs, ys):
    """a sampled at fractional (xs, ys), clamped to its edges."""
    h, w = a.shape
    xs = np.clip(xs, 0, w - 1)
    ys = np.clip(ys, 0, h - 1)
    x0 = np.minimum(np.floor(xs).astype(np.int64), w - 2)
    y0 = np.minimum(np.floor(ys).astype(np.int64), h - 2)
    fx, fy = xs - x0, ys - y0
    top = a[y0, x0] * (1 - fx) + a[y0, x0 + 1] * fx
    bot = a[y0 + 1, x0] * (1 - fx) + a[y0 + 1, x0 + 1] * fx
    return top * (1 - fy) + bot * fy


def blend_byte(w1, w2, dither):
    """Terrain3D's blend (0 base only .. 255 overlay only) from the top two
    weights: the overlay's share (0..0.5) through a smoothstep, so thin
    traces vanish and the crossing is steep, plus dither against banding."""
    r = np.where(w1 + w2 > 0, w2 / np.maximum(w1 + w2, 1e-6), 0.0)
    t = np.clip(r * 2.0 + dither, 0.0, 1.0)
    return np.round(255.0 * 0.5 * t * t * (3.0 - 2.0 * t)).astype(np.uint32)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", default="")
    MAP = ap.parse_args(argv).map or default_pack()
    PACK = os.path.join(ROOT, "assets", "maps", MAP)
    CELLS = os.path.join(ROOT, "data", "maps", MAP, "geography", "cells.csv")
    OUT = os.path.join(ROOT, "assets", "map3d", MAP, "bake")
    rules = load_rules()
    SEA_Y = rules["sea_y_m"]
    os.makedirs(OUT, exist_ok=True)
    # raw bake files and previews are read by build_terrain.gd, never imported
    open(os.path.join(OUT, ".gdignore"), "w").close()
    rng = np.random.default_rng(SEED)

    # --- base height at pack resolution ------------------------------------------
    relief = np.asarray(Image.open(os.path.join(PACK, "world_relief.png")).convert("L"), dtype=np.float32)
    ph, pw = relief.shape
    idx = np.asarray(Image.open(os.path.join(PACK, "world_cell_index.png")).convert("RGB")).astype(np.int64)
    has_cell = ~((idx[..., 0] == 255) & (idx[..., 1] == 255) & (idx[..., 2] == 255))
    cell_id = idx[..., 0] | (idx[..., 1] << 8)
    heights = np.zeros(cell_id.max() + 1, dtype=np.float32)
    water = np.zeros(cell_id.max() + 1, dtype=bool)
    for r in csv.DictReader(open(CELLS)):
        i = int(r["cell_id"])
        if i < len(heights):
            heights[i] = float(r["height"])
            water[i] = r["water"] != ""
    # Cells for land and lakes; the relief (detail and all) only for open sea,
    # which lies under an opaque water plane.
    units = np.where(has_cell, heights[cell_id], relief * 100.0 / 255.0) - SEA_LEVEL
    metres = np.where(units >= 0, units * LAND_M_PER_UNIT, units * SEA_M_PER_UNIT)
    metres = box(box(metres, BASE_BLUR_PX), BASE_BLUR_PX)

    k = M_PER_PX / VERTEX_M
    vw, vh = round(pw * k), round(ph * k)
    height = resize(metres, vw, vh)
    # The shoreline is the pack's own shore loops, not its 50 m pixels: their
    # coverage per vertex ramps the fringe through the water plane, so the
    # coast crosses it where the loop does (no staircase), and the blur can
    # neither sink a coast nor raise a shoal.
    land_loops, lake_loops = read_loops(os.path.join(ROOT, "data", "maps", MAP, "geography", "coasts.csv"))
    cov = coverage(land_loops, lake_loops, vw, vh, k, int(rules["coast_supersample"]))
    land = cov >= 0.5
    # The heights ramp through the plane over coast_ramp_m, not one vertex:
    # a one-vertex ramp stair-stepped again wherever the mesh LOD skipped it.
    # A symmetric blur keeps the half-coverage line where it was.
    ramp = box(cov, int(round(rules["coast_ramp_m"] / VERTEX_M)))
    height = shore_heights(height, ramp, SEA_Y, rules["shore_m"])

    # --- ridges -------------------------------------------------------------------
    ridge = np.zeros((vh, vw), dtype=np.float32)
    amp, norm = 1.0, 0.0
    for wave_m in RIDGE_WAVES_M:
        n = value_noise(rng, vw, vh, wave_m / VERTEX_M)
        ridge += amp * (1.0 - np.abs(2.0 * n - 1.0)) ** 2
        norm += amp
        amp *= RIDGE_GAIN
    ridge /= norm
    ridge -= ridge[land].mean()
    coast_steps = int(RIDGE_COAST_M / VERTEX_M)
    from_coast = distance_steps(~land, coast_steps) / coast_steps
    lift = np.clip((height - RIDGE_FROM_M) / (RIDGE_FULL_M - RIDGE_FROM_M), 0, 1)
    # the fringe (0 < ramp < 1) keeps its ramp through the water plane
    height = np.where(ramp >= 1.0, np.maximum(height + RIDGE_M * lift * from_coast * ridge * 2.0,
                                             SEA_Y + rules["shore_m"]), height)
    del ridge, lift

    # --- texture weights ------------------------------------------------------------
    wts = np.zeros((ph, pw, 16), dtype=np.float32)
    for n in range(4):
        img = Image.open(os.path.join(PACK, f"world_biome_weights_{n}.png")).convert("RGBA").resize((pw, ph), Image.BILINEAR)
        wts[..., n * 4:n * 4 + 4] = np.asarray(img, dtype=np.float32)
    total = wts.sum(axis=2)
    safe = np.where(total > 0, total, 1.0)
    tw = np.zeros((vh, vw, NT), dtype=np.float32)
    biome_tw = np.zeros((ph, pw, NT), dtype=np.float32)
    for biome, mix in BIOME_MIX.items():
        share = wts[..., biome - 1] / safe
        for t, f in mix.items():
            biome_tw[..., t] += share * f
    biome_tw[total <= 0, GRASS] = 1.0
    # Interlocking edges: each vertex samples the (blurred) weights at a
    # point pushed off by a smooth noise field, so a boundary between two
    # grounds meanders and tongues into its neighbour instead of blurring.
    wave_v = rules["edge_warp_wave_m"] / VERTEX_M
    amp_v = rules["edge_warp_m"] / VERTEX_M
    dx = (value_noise(rng, vw, vh, wave_v) - 0.5) * 2.0 * amp_v
    dy = (value_noise(rng, vw, vh, wave_v) - 0.5) * 2.0 * amp_v
    for t in range(NT):
        smooth = resize(box(biome_tw[..., t], WEIGHT_BLUR_PX), vw, vh)
        for y0 in range(0, vh, 512):
            y1 = min(y0 + 512, vh)
            ys, xs = np.mgrid[y0:y1, 0:vw].astype(np.float32)
            tw[y0:y1, :, t] = np.maximum(sample_bilinear(smooth, xs + dx[y0:y1], ys + dy[y0:y1]), 0)
    del dx, dy, smooth
    del wts, biome_tw

    gy, gx = np.gradient(height, VERTEX_M)
    slope = np.hypot(gx, gy)
    ls = np.sort(slope[land][::7])
    pct = lambda p: float(ls[min(int(p * len(ls)), len(ls) - 1)])
    t_rock = np.clip((slope - pct(SLOPE_ROCKY[0])) / max(pct(SLOPE_ROCKY[1]) - pct(SLOPE_ROCKY[0]), 1e-6), 0, 1)
    t_cliff = np.clip((slope - pct(SLOPE_CLIFF[0])) / max(pct(SLOPE_CLIFF[1]) - pct(SLOPE_CLIFF[0]), 1e-6), 0, 1)
    del gx, gy, slope
    hn = np.clip(height / max(float(height.max()), 1.0), 0, 1)
    keep = 1.0 - 0.85 * t_rock
    for t in (GRASS, LEAVES, DIRT, SAND, FOREST):
        tw[..., t] *= keep
    tw[..., ROCKY] += 1.2 * t_rock * (1 - t_cliff)
    tw[..., SOIL] += 0.9 * t_rock * (1 - hn) * (1 - t_cliff)
    tw[..., CLIFF] += 2.5 * t_cliff * np.maximum(hn, 0.35)
    # The beach fades out by the share of land around a vertex (a box of
    # BEACH_M): a 4-neighbour step count cut it on a diamond staircase.
    inland = box(land.astype(np.float32), int(BEACH_M / VERTEX_M))
    beach = land * np.clip((1.0 - inland) / 0.2, 0, 1) * np.clip((BEACH_MAX_M - height) / 15.0, 0, 1)
    tw[..., SAND] += 2.0 * beach
    del t_rock, t_cliff, keep, beach
    depth = np.clip(-height / 150.0, 0, 1)
    tw[~land] = 0.0
    tw[..., SAND] += np.where(land, 0.0, 1.0 - depth)
    tw[..., SOIL] += np.where(land, 0.0, depth)
    del depth, hn

    # Outcrops, not blobs: after normalising, cliff and scree are raised to a
    # power, which narrows their soft edge where the grass stays wide. What
    # the cliff loses becomes scree (an outcrop fringed by scree), and the
    # soil slope takes the scree's power: left alone it overtook both at the
    # rim and put a one-vertex brown speckle round every outcrop.
    tw /= np.maximum(tw.sum(axis=2, keepdims=True), 1e-6)
    cliff = tw[..., CLIFF] ** rules["sharp_cliff"]
    tw[..., ROCKY] += tw[..., CLIFF] - cliff
    tw[..., CLIFF] = cliff
    tw[..., ROCKY] **= rules["sharp_rocky_trail"]
    tw[..., SOIL] **= rules["sharp_rocky_trail"]
    del cliff

    # --- control: top two per vertex --------------------------------------------------
    control = np.zeros((vh, vw), dtype=np.uint32)
    for y0 in range(0, vh, 256):
        s = tw[y0:y0 + 256]
        order = np.argsort(-s, axis=2)
        b1, b2 = order[..., 0], order[..., 1]
        w1 = np.take_along_axis(s, b1[..., None], 2)[..., 0]
        w2 = np.take_along_axis(s, b2[..., None], 2)[..., 0]
        blend = blend_byte(w1, w2, rng.uniform(-rules["blend_dither"], rules["blend_dither"], w1.shape))
        control[y0:y0 + 256] = (b1.astype(np.uint32) << 27) | (b2.astype(np.uint32) << 22) | (blend << 14)

    # --- colour map ----------------------------------------------------------------------
    mult_lin = np.zeros((NT, 3))
    for t, key in enumerate(TEXTURE_KEYS):
        a = np.asarray(Image.open(os.path.join(TEX, f"{key}_alb_ht.png")).convert("RGB").resize((64, 64)), dtype=np.float64) / 255.0
        mean_lin = srgb_to_lin(a).reshape(-1, 3).mean(0)
        mult_lin[t] = np.clip(srgb_to_lin(hex_rgb(FAR_COLOR[t])) / np.maximum(mean_lin, 1e-4), 0, 1)
    color_lin = np.zeros((vh, vw, 3), dtype=np.float32)
    wsum = np.maximum(tw.sum(axis=2), 1e-6)
    for t in range(NT):
        color_lin += (tw[..., t] / wsum)[..., None] * mult_lin[t].astype(np.float32)
    del tw, wsum
    macro = value_noise(rng, vw, vh, MACRO_WAVE_M / VERTEX_M)
    hue = value_noise(rng, vw, vh, MACRO_WAVE_M * 0.7 / VERTEX_M)
    color_lin *= (1.0 - rules["macro_depth"] * macro)[..., None]
    color_lin[..., 0] *= 1.0 - rules["macro_hue_depth"] * hue
    color_lin[..., 2] *= 1.0 - rules["macro_hue_depth"] * (1.0 - hue)
    rgba = np.empty((vh, vw, 4), dtype=np.uint8)
    for y0 in range(0, vh, 512):
        rgba[y0:y0 + 512, :, :3] = np.round(lin_to_srgb(color_lin[y0:y0 + 512]) * 255).astype(np.uint8)
    rgba[..., 3] = 128  # neutral roughness
    del color_lin

    # --- pad onto whole regions, the pack centred --------------------------------------------
    cols = -(-vw // REGION)
    cols += cols % 2
    rows = -(-vh // REGION)
    rows += rows % 2
    fw, fh = cols * REGION, rows * REGION
    ox, oy = (fw - vw) // 2, (fh - vh) // 2
    hp = np.full((fh, fw), -SEA_LEVEL * SEA_M_PER_UNIT, dtype=np.float32)
    hp[oy:oy + vh, ox:ox + vw] = height
    cp = np.full((fh, fw), (SOIL << 27) | (SOIL << 22), dtype=np.uint32)
    cp[oy:oy + vh, ox:ox + vw] = control
    colp = np.full((fh, fw, 4), 255, dtype=np.uint8)
    colp[..., 3] = 128
    colp[oy:oy + vh, ox:ox + vw] = rgba
    hp.tofile(os.path.join(OUT, "height.r32"))
    cp.view(np.float32).tofile(os.path.join(OUT, "control.r32"))
    colp.tofile(os.path.join(OUT, "color.rgba8"))
    Image.fromarray(rgba[::6, ::6, :3]).save(os.path.join(OUT, "color_preview.png"))
    Image.fromarray(np.clip((height[::6, ::6] + 300) / 3000 * 255, 0, 255).astype(np.uint8)).save(
        os.path.join(OUT, "height_preview.png"))

    world = {
        "m_per_px": M_PER_PX, "vertex_m": VERTEX_M, "region_size": REGION,
        "pack_px": [pw, ph], "vertices": [vw, vh], "padded": [fw, fh],
        # world position of the padded image's corner, and of pack px (0,0)
        "import_corner": [-fw * VERTEX_M / 2, -fh * VERTEX_M / 2],
        "pack_origin": [(-fw / 2 + ox) * VERTEX_M, (-fh / 2 + oy) * VERTEX_M],
        "sea_y": SEA_Y,
        "height_range": [float(height.min()), float(height.max())],
        "slope_percentiles": [pct(SLOPE_ROCKY[0]), pct(SLOPE_ROCKY[1]), pct(SLOPE_CLIFF[1])],
        "far_multipliers_lin": mult_lin.round(3).tolist(),
    }
    json.dump(world, open(os.path.join(OUT, "world.json"), "w"), indent=1)
    print(json.dumps({k: v for k, v in world.items() if k != "far_multipliers_lin"}))


if __name__ == "__main__":
    main()
