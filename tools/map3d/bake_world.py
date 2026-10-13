"""Bake a map pack into Terrain3D import maps at campaign scale
(owner 2026-09-18: 50 m per pack px, a 128 x 46 km world, vertex every 20 m).

Writes <map3d_dir>/bake/ (data/world/maps.csv map3d_dir, default assets/3D/terrain/<map>):
  height.r32    float32 metres, row-major, padded onto whole regions
  height_war.r16  float16 metres over the pack's own vertices (no padding):
                the WAR ROOM's heights (WarBake), small enough to commit
  control.r32   float32 carrying Terrain3D control bits (base/overlay/blend)
  color.rgba8   Terrain3D colour map: sRGB multiplier on the ground + roughness
  world.json    sizes, vertex spacing, world origin of pack px (0,0)
  rivers.json   each river's water line, source -> mouth, in world metres
Its look rules live in data/screens/map3d/map3d_bake.csv and in constants here;
build_terrain.gd only imports.
  python3 tools/map3d/bake_world.py [--map ID]   (default: data/world/maps.csv is_default)

HEIGHT does NOT read world_relief.png: its synthesized detail was tuned for
the 2D canvas (16 px wavelength, 22 height units), which at 50 m/px is a
660 m bump every 800 m — the "blanket of bubbles". The land is the pack's
own cell heights, smoothed, plus ridges made for this scale.
"""
import argparse
import csv
import json
import math
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from packs import default_pack, map3d_dir  # noqa: E402
import data_index  # noqa: E402
import bake_houses  # noqa: E402

TEX = os.path.join(ROOT, "assets", "3D", "terrain", "textures")
RULES_PATH = os.path.join(ROOT, "data", "screens", "map3d", "map3d_bake.csv")
SEED = 954159497         # a look, never simulation: the same for every pack

M_PER_PX = 50.0          # world metres per pack px
VERTEX_M = 20.0          # Terrain3D vertex_spacing
REGION = 2048            # Terrain3D region_size (vertices)
def _balance(key):
    """A balance value — the engine's Elevation reads the same row."""
    return data_index.balance()[key]


SEA_LEVEL = _balance("elevation_sea_level")        # Azgaar height of the waterline
LAND_M_PER_UNIT = _balance("elevation_m_per_unit")  # ~2400 m for the highest cells
SEA_M_PER_UNIT = 15.0    # ~300 m for the deepest sea
BASE_BLUR_PX = 7         # box radius (pack px, twice) turning cells (~26 px) into landforms

# Ridges at campaign scale: ridged value noise, values in map3d_bake.csv
# relief_ridge_* (spec 2026-10-13-landform-rework moved them out of code).
def relief_waves(rules):
    """The ridged noise's octave wavelengths in metres (relief_ridge_waves_m,
    a | list), coarse to fine."""
    return tuple(float(w) for w in str(rules["relief_ridge_waves_m"]).split("|") if w.strip())

WEIGHT_BLUR_PX = 5       # box radius (pack px) softening biome weights (3 left 50 m stair-steps on forest edges)
BEACH_M = 100.0          # sand reaches this far inland
BEACH_MAX_M = 40.0       # and no higher

# Texture ids = build_terrain.gd TEXTURES order.
CLIFF, GRASS, LEAVES, DIRT, ROCKY, SOIL, SAND, FOREST, SNOW, CROP = range(10)
# Variant sets (spec 2026-10-12-ground-detail-textures, Phase 1): the grass and the
# crops wear several interchangeable low-feature pictures, mixed by split_variants
# on slow noise so no two neighbouring tiles repeat one picture; the grass on high
# ground takes the upland turfs.
GRASS_B, GRASS_C, UPTURF_A, UPTURF_B, CROP_B = range(10, 15)
# The high ground (spec 2026-10-13-map-art-phase2, B): grey scree under the snow
# caps and broken ridges and gullies on the high plateaus.
SCREE, RIDGE = 15, 16
NT = 17
TEXTURE_KEYS = ["p3_rock_face",   # a FRONTAL rock face (owner-approved 2026-10-13, R-01): Terrain3D projects it on the steep faces, where the aerial crag streaked
                "g2_meadow_a", "dry_decay_leaves", "dirt_floor", "aerial_upland",
                "excavated_soil_wall", "sand_03", "aerial_canopy",
                # the snow line (owner 2026-09-19): Poly Haven snow_02 since the
                # same day (snow_field_aerial read blue-grey and blotchy)
                "p2_snow",   # snow with rock ribs (phase 2 B, T-88)
                # the crops (owner 2026-10-01, open fields): a pale straw ground
                # each field's tint darkens to its crop's colour
                "g2_crop_a",
                # the variant sets (split_variants)
                "g2_meadow_b", "g2_meadow_c", "g2_upturf_a", "g2_upturf_b", "g2_crop_b",
                # the high ground (phase 2 B: T-86 scree, T-87 ridge and gully)
                "p2_scree", "p2_ridge"]
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
    11: {SNOW: 1.0},
    12: {GRASS: 0.5, DIRT: 0.5},
    13: {GRASS: 0.75, ROCKY: 0.25},
    14: {GRASS: 0.3, ROCKY: 0.4, CLIFF: 0.3},
    15: {SNOW: 0.8, CLIFF: 0.2},
}
SLOPE_ROCKY = (0.86, 0.96)   # land slope percentiles (visual review 2026-10-06: the scarps read as one grey ring; rock only on the steepest)
SLOPE_CLIFF = (0.96, 0.995)

# COLOUR MAP: what each texture should read as from far away (sRGB). Terrain3D
# multiplies the ground by the map, so a target is reached by the ratio to the
# texture's own mean colour, in linear light, and can only darken.
FAR_COLOR = {
    CLIFF: "#7E7B77", GRASS: "#747A40", LEAVES: "#4E4A2C", DIRT: "#9A7A55",
    ROCKY: "#7A7656", SOIL: "#5E4A30", FOREST: "#5C6C36",
}
# a variant reaches its class's far colour, so the far view is the same whichever is drawn
FAR_COLOR.update({GRASS_B: FAR_COLOR[GRASS], GRASS_C: FAR_COLOR[GRASS],
                  UPTURF_A: FAR_COLOR[GRASS], UPTURF_B: FAR_COLOR[GRASS],
                  SCREE: "#85827A", RIDGE: FAR_COLOR[ROCKY]})   # the scree a grey margin under the caps (critic 2026-10-13)
CROP_TEXTURES = (CROP, CROP_B)   # the crops wear their own tint (sow_patchwork), never a far colour
# each class's pictures (split_variants), the class the control map ranks
VARIANT_SETS = ((GRASS, GRASS_B, GRASS_C, UPTURF_A, UPTURF_B), CROP_TEXTURES)  # SAND's, SNOW's and CLIFF's are data/screens/map3d/map3d_bake.csv far_color_sand / _snow / _cliff
MACRO_WAVE_M = 9000.0    # large patches of lighter and darker country
# (their depth and the green-yellow drift are data/screens/map3d/map3d_bake.csv macro_*)


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


def variant_shares(noises, sharp):
    """Soft one-hot shares of len(noises) variants: each vertex goes mostly to
    the variant whose noise is highest there, fading into its neighbour over
    a band `sharp` narrows (a softmax of sharp x the noises), so a change of
    picture is a blend across a few vertices, never a 20 m step."""
    e = [np.exp(sharp * (n - 1.0)) for n in noises]
    total = sum(e)
    return [x / total for x in e]


def split_variants(tw, height, rules):
    """Spread the grass and the crops over their variant sets (spec
    2026-10-12-ground-detail-textures): the grass on low ground over
    GRASS / GRASS_B / GRASS_C, on high ground (variant_upland_lo_m ..
    _hi_m) over the two upland turfs; the crops over CROP / CROP_B. Each
    set by its own slow noises (variant_wave_m, crop_variant_wave_m) and
    variant_sharp; weights only move between pictures of one class, so the
    colour map and the far view do not change. In place."""
    vh, vw = tw.shape[:2]
    wave = rules["variant_wave_m"] / VERTEX_M
    sharp = rules["variant_sharp"]
    rngs = [np.random.default_rng(SEED + 61 + i) for i in range(6)]
    up = np.clip((height - rules["variant_upland_lo_m"])
                 / max(rules["variant_upland_hi_m"] - rules["variant_upland_lo_m"], 1e-6), 0, 1)
    grass = tw[..., GRASS].copy()
    low, high = grass * (1.0 - up), grass * up
    del up, grass
    for t, s in zip((GRASS, GRASS_B, GRASS_C),
                    variant_shares([value_noise(rngs[i], vw, vh, wave) for i in range(3)], sharp)):
        tw[..., t] = low * s
    for t, s in zip((UPTURF_A, UPTURF_B),
                    variant_shares([value_noise(rngs[3 + i], vw, vh, wave) for i in range(2)], sharp)):
        tw[..., t] = high * s
    del low, high
    crop = tw[..., CROP].copy()
    cwave = rules["crop_variant_wave_m"] / VERTEX_M
    for t, s in zip(CROP_TEXTURES,
                    variant_shares([value_noise(rngs[5], vw, vh, cwave),
                                    1.0 - value_noise(rngs[5], vw, vh, cwave)], sharp)):
        tw[..., t] = crop * s


def lead_variants(s):
    """The weights the control map ranks: in each variant set the leading
    picture stands for its whole class (the set's total) and the others keep
    their share of it, so a class split over its pictures competes with the
    other layers exactly as it did whole — split thin it lost the vertex to
    dirt, crops or rock (found 2026-10-13: tan patches over the grass). The
    colour map keeps the true weights. A copy."""
    s = s.copy()
    for idx in VARIANT_SETS:
        fam = s[..., list(idx)]
        top = fam.max(axis=2, keepdims=True)
        tot = fam.sum(axis=2, keepdims=True)
        s[..., list(idx)] = np.where(top > 0, fam * (tot / np.maximum(top, 1e-12)), 0.0)
    return s


def value_noise(rng, w, h, wave):
    """Smooth noise in 0..1 with features `wave` samples across."""
    gw, gh = int(w / wave) + 4, int(h / wave) + 4
    grid = rng.random((gh, gw), dtype=np.float32)
    big = resize(grid, int(gw * wave), int(gh * wave))
    ox, oy = rng.integers(0, int(wave)), rng.integers(0, int(wave))
    return np.clip(big[oy:oy + h, ox:ox + w], 0, 1)


def terrace(height, ramp, land, from_coast, rules, vw, vh, courses=()):
    """Fold the high ground into plateaus and escarpments (owner 2026-09-24,
    the look route's Phase 2, spec 2026-09-24-map3d-humankind-look-gap §2.3):
    above terrace_from_m the height is stepped every terrace_step_m, each step
    a flat top and a face that takes terrace_face of the step, the steps'
    edges warped by a slow noise (terrace_warp_*) so a face does not follow a
    contour, and all of it mixed in only where a coarse noise mask allows
    (terrace_mask_*) — not every hill is a mesa. Held off the coast like the
    ridges, and done before the rivers carve, so a river cuts a gorge through
    a step. LOOK only: the engine's heights are the cells' (Elevation), and
    the slope percentiles that pick cliff and scree follow the new faces.
    Its own random stream, so nothing sown after it moves.

    Critic round 1 (2026-09-24): the step height drifts with a slow noise
    (terrace_step_jitter) so the steps are not stair-regular; only ground
    whose local top clears terrace_min_steps steps is terraced (a lone
    hilltop crossing one level became a flat "pill"); and the terraces are
    held off the rivers over terrace_river_fade_m like the ridges, since a
    river carved through a face left a black slot.

    Blind A/B round (2026-09-24): terraced ground won, but read as contour
    lines where every region stepped at the same levels — so the levels
    themselves drift by region (terrace_level_jitter steps, a slow noise),
    and no slope takes more than terrace_max_steps steps above its region's
    first level (above them the ground is its own again, eased over a
    step)."""
    strength = rules.get("terrace_strength", 0.0)
    if strength <= 0.0:
        return height
    trng = np.random.default_rng(int(rules["terrace_seed"]))
    base = rules["terrace_from_m"]
    step = rules["terrace_step_m"] * (1.0 + rules["terrace_step_jitter"]
        * (value_noise(trng, vw, vh, rules["terrace_step_wave_m"] / VERTEX_M) * 2.0 - 1.0))
    warp = (value_noise(trng, vw, vh, rules["terrace_warp_wave_m"] / VERTEX_M) * 2.0 - 1.0) \
        * rules["terrace_warp_m"]
    mask = value_noise(trng, vw, vh, rules["terrace_mask_wave_m"] / VERTEX_M)
    lo, hi = rules["terrace_mask_lo"], rules["terrace_mask_hi"]
    t = np.clip((mask - lo) / max(hi - lo, 1e-6), 0, 1)
    mask = t * t * (3 - 2 * t)
    mask *= np.clip((height - base) / rules["terrace_fade_m"], 0, 1) * from_coast
    mask *= np.clip((local_top(height, rules["terrace_top_reach_m"] / VERTEX_M) - base)
                    / (rules["terrace_min_steps"] * rules["terrace_step_m"]) - 1.0, 0, 1)
    if len(courses):
        mask *= river_fade(courses, vw, vh, rules["terrace_river_fade_m"] / VERTEX_M,
                           rules["river_head_m"] / VERTEX_M, rules["river_head_share"])
    level = (value_noise(trng, vw, vh, rules["terrace_level_wave_m"] / VERTEX_M) * 2.0 - 1.0) \
        * rules["terrace_level_jitter"] * step
    # the rim broken (visual review 2026-10-06: one unbroken scarp ringed the
    # plateau like a crater wall): a finer warp cuts bays and spurs into the
    # edge, and in stretches the face eases into a slope (own stream: the
    # terraces above stay as they were)
    brng = np.random.default_rng(int(rules["terrace_seed"]) + 1)
    if rules.get("terrace_gully_m", 0.0) > 0.0:
        warp = warp + (value_noise(brng, vw, vh, rules["terrace_gully_wave_m"] / VERTEX_M) * 2.0 - 1.0) \
            * rules["terrace_gully_m"]
    soft = np.zeros_like(height)
    if rules.get("terrace_soften", 0.0) > 0.0:
        sn = value_noise(brng, vw, vh, rules["terrace_soften_wave_m"] / VERTEX_M)
        soft = np.clip((sn - 0.45) / 0.25, 0, 1) * rules["terrace_soften"]
    hw = (height - base - level + warp) / step
    mask *= np.clip(rules["terrace_max_steps"] + 1.0 - hw, 0, 1)
    k = np.floor(hw)
    f = hw - k
    w = rules["terrace_face"] + (0.95 - rules["terrace_face"]) * soft
    u = np.clip((f - (1.0 - w)) / w, 0, 1)
    stepped = base + level + (k + u * u * (3 - 2 * u)) * step
    out = height + strength * mask * (stepped - height)
    return np.where(ramp >= 1.0, out, height).astype(np.float32)


def local_top(a, reach):
    """The highest value within about `reach` samples of each sample: a block
    maximum over reach-sized blocks, dilated one block, upsampled — coarse,
    which is all a mask needs."""
    b = max(int(reach), 1)
    h, w = a.shape
    ph, pw = -(-h // b) * b, -(-w // b) * b
    pad = np.full((ph, pw), -1e9, dtype=np.float32)
    pad[:h, :w] = a
    blk = pad.reshape(ph // b, b, pw // b, b).max(axis=(1, 3))
    d = blk.copy()
    d[1:] = np.maximum(d[1:], blk[:-1]); d[:-1] = np.maximum(d[:-1], blk[1:])
    e = d.copy()
    e[:, 1:] = np.maximum(e[:, 1:], d[:, :-1]); e[:, :-1] = np.maximum(e[:, :-1], d[:, 1:])
    return resize(e, pw, ph)[:h, :w]


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
    """data/screens/map3d/map3d_bake.csv as {key: float}; a value that is not a number
    (a "#RRGGBB" colour) stays text."""
    def value(v):
        try:
            return float(v)
        except ValueError:
            return v
    with open(path) as f:
        return {r["key"]: value(r["value"]) for r in csv.DictReader(f)}


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
    least shore_m under it. Across the fringe the ground crosses the plane
    at cov 0.5, where the loop is: seaward it ramps down to shore_m under it
    (a drop to the sea's real depth there made a coarse far mesh LOD cross
    the plane in steps), landward it rises to the land's own height (a flat
    ramp there left a shelf the width of the fringe before every high coast,
    then a one-vertex wall).
    """
    land = np.maximum(height, sea_y + shore_m)
    sea = np.minimum(height, sea_y - shore_m)
    out = np.where(cov >= 1.0, land, np.where(cov <= 0.0, sea, height))
    up = np.clip(2.0 * cov - 1.0, 0.0, 1.0)
    down = np.clip(1.0 - 2.0 * cov, 0.0, 1.0)
    fringe = np.where(cov >= 0.5, sea_y + up * (land - sea_y), sea_y - down * shore_m)
    return np.where((cov > 0.0) & (cov < 1.0), fringe, out).astype(np.float32)


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


def sharpen_weights(tw, rules):
    """Outcrops, not blobs: the weights (h, w, NT) normalised per vertex,
    then cliff and scree raised to a power, which narrows their soft edge
    where the grass stays wide. What the cliff loses becomes scree (an
    outcrop fringed by scree), and the soil slope takes the scree's power:
    left alone it overtook both at the rim and put a one-vertex brown
    speckle round every outcrop. Works in place and returns tw."""
    tw /= np.maximum(tw.sum(axis=2, keepdims=True), 1e-6)
    cliff = tw[..., CLIFF] ** rules["sharp_cliff"]
    tw[..., ROCKY] += tw[..., CLIFF] - cliff
    tw[..., CLIFF] = cliff
    tw[..., ROCKY] **= rules["sharp_rocky_trail"]
    tw[..., SOIL] **= rules["sharp_rocky_trail"]
    return tw


def blend_byte(w1, w2, dither):
    """Terrain3D's blend (0 base only .. 255 overlay only) from the top two
    weights: the overlay's share (0..0.5) through a smoothstep, so thin
    traces vanish and the crossing is steep, plus dither against banding."""
    r = np.where(w1 + w2 > 0, w2 / np.maximum(w1 + w2, 1e-6), 0.0)
    t = np.clip(r * 2.0 + dither, 0.0, 1.0)
    return np.round(255.0 * 0.5 * t * t * (3.0 - 2.0 * t)).astype(np.uint32)


def taper_gamma():
    """screens/map3d/balance.csv map_river_taper_gamma: the 2D river's taper, shared."""
    return data_index.balance().get("map_river_taper_gamma", 1.4)


def smooth_open(pts, steps):
    """The 2D map's river curve (MapGeometry.smooth_open): a clamped uniform
    cubic B-spline, `steps` points per segment, the last point kept. The
    pack stores a river as a raw polyline whose corners read as kinks."""
    p = np.asarray(pts, dtype=np.float64)
    n = len(p)
    if n < 3 or steps < 1:
        return p
    t = np.arange(steps) / steps
    t2, t3 = t * t, t * t * t
    basis = np.stack([1 - 3 * t + 3 * t2 - t3, 4 - 6 * t2 + 3 * t3,
                      1 + 3 * t + 3 * t2 - 3 * t3, t3], axis=1) / 6.0   # (steps, 4)
    idx = np.clip(np.arange(-2, n - 1)[:, None] + np.arange(4)[None, :], 0, n - 1)  # (n+1, 4)
    out = np.einsum("sk,ikd->isd", basis, p[idx]).reshape(-1, 2)
    return np.vstack([out, p[-1:]])


def meander(course, amp_v, wave_v, salt, end_v, hold=None, hold_v=0.0):
    """`course` (vertex units) pushed sideways by a slow noise along its
    length — two octaves, `wave_v` and a third of it — up to `amp_v`, tapered
    to nothing over `end_v` at either end so a source, a join and a mouth stay
    where they were (visual review 2026-10-06: rivers ran ruler-straight for
    kilometres between the pack's sparse points)."""
    pts = np.asarray(resample_line(course, 1.0), dtype=np.float64)
    if len(pts) < 4 or amp_v <= 0.0:
        return course
    d = np.gradient(pts, axis=0)
    d /= np.maximum(np.hypot(d[:, 0], d[:, 1]), 1e-9)[:, None]
    nrm = np.stack([-d[:, 1], d[:, 0]], axis=1)
    s = np.arange(len(pts), dtype=np.float64)
    rng = np.random.default_rng(SEED + 41 + salt)

    def noise1(wave):
        n = int(len(pts) / wave) + 3
        knots = rng.uniform(-1.0, 1.0, n)
        x = s / wave
        i = np.floor(x).astype(np.int64)
        f = x - i
        f = f * f * (3.0 - 2.0 * f)
        return knots[i] * (1.0 - f) + knots[i + 1] * f
    off = noise1(wave_v) * 0.75 + noise1(wave_v / 3.0) * 0.25
    taper = np.clip(np.minimum(s, s[-1] - s) / max(end_v, 1.0), 0.0, 1.0)
    if hold is not None and len(hold) and hold_v > 0.0:
        # a settlement keeps its river where the pack drew it (its houses,
        # walls and bridge were laid round that line)
        from scipy.spatial import cKDTree
        dist, _ = cKDTree(hold).query(pts)
        taper *= np.clip(dist / hold_v - 1.0, 0.0, 1.0)
    out = pts + nrm * (off * amp_v * taper)[:, None]
    return [tuple(p) for p in out]


def resample_line(pts, step):
    """Points every `step` (same units) along a polyline, ends kept."""
    pts = np.asarray(pts, dtype=np.float64)
    seg = np.hypot(*np.diff(pts, axis=0).T)
    s = np.concatenate([[0.0], np.cumsum(seg)])
    if s[-1] <= 0:
        return pts[:1]
    t = np.append(np.arange(0.0, s[-1], step), s[-1])
    return np.column_stack([np.interp(t, s, pts[:, 0]), np.interp(t, s, pts[:, 1])])


def river_span(cov_along):
    """The slice (start, end) of a course's samples worth drawing: from its
    first land sample (cov >= 0.5) to the first open-sea sample (cov 0)
    past its last land one, so the mouth runs through the fringe into the
    sea but never on across it; None when it never touches land. The pack
    writes a river source -> mouth and the 2D map clips it to the land the
    same way (WorldMapView._trim_to_land)."""
    on = np.flatnonzero(cov_along >= 0.5)
    if len(on) == 0:
        return None
    end = int(on[-1]) + 1
    while end < len(cov_along) and cov_along[end - 1] > 0.0:
        end += 1
    return int(on[0]), end


def join_point(end_xy, others, max_dist):
    """The nearest point on any of `others` (polylines) to `end_xy`, if it
    lies within max_dist, else None. The pack's tributaries stop 60-290 m
    short of the river they feed; appending this point carries them in."""
    e = np.asarray(end_xy, dtype=np.float64)
    best, best_d = None, max_dist
    for o in others:
        o = np.asarray(o, dtype=np.float64)
        if len(o) == 1:
            a, ab = o, np.zeros((1, 2))
        else:
            a, ab = o[:-1], np.diff(o, axis=0)
        t = np.clip(((e - a) * ab).sum(1) / np.maximum((ab * ab).sum(1), 1e-12), 0.0, 1.0)
        foot = a + ab * t[:, None]
        d = np.hypot(*(foot - e).T)
        i = int(np.argmin(d))
        if d[i] <= best_d:
            best, best_d = foot[i], float(d[i])
    return best


def river_mouth(n, n_mouth, to_sea):
    """0 -> 1 over a course's last n_mouth samples when it ends in the sea
    (it widens x2 and the water shades toward the sea there); an inland end,
    a lake or a confluence, keeps 0 and its taper."""
    if not to_sea:
        return np.zeros(n)
    return np.clip((np.arange(n) - (n - n_mouth)) / n_mouth, 0.0, 1.0)


def join_water(water, start):
    """The water line from sample `start` on (a tributary's joined stretch)
    never rises above the one before: it may meet its river a little over
    that river's water, which the runtime draws over."""
    w = np.array(water, dtype=np.float64)
    if 0 < start < len(w):
        w[start:] = np.minimum.accumulate(w[start - 1:])[1:]
    return w


# --- stream-power erosion (spec 2026-10-13-landform-rework, option A) ------------
# On a coarse grid: flow is routed down the steepest of the 8 neighbours (D8),
# each cell's drained area accumulated, and the ground cut by an implicit
# Braun-Willett stream-power step (n = 1), then slopes over the repose angle
# shed half their excess downhill. No randomness: the same heights always give
# the same valleys.

_D8 = ((-1, -1), (-1, 0), (-1, 1), (0, -1), (0, 1), (1, -1), (1, 0), (1, 1))


def fill_pits(h, outlet):
    """Priority-flood (Barnes 2014): every cell raised to the lowest spill
    height reachable from an `outlet` cell (bool mask), plus a hair per step so
    the filled flats still drain. A copy."""
    import heapq
    H, W = h.shape
    out = h.astype(np.float64).copy()
    done = outlet.copy()
    heap = [(float(out[y, x]), int(y), int(x)) for y, x in zip(*np.nonzero(outlet))]
    heapq.heapify(heap)
    while heap:
        z, y, x = heapq.heappop(heap)
        for dy, dx in _D8:
            ny, nx = y + dy, x + dx
            if 0 <= ny < H and 0 <= nx < W and not done[ny, nx]:
                done[ny, nx] = True
                if out[ny, nx] <= z:
                    out[ny, nx] = z + 1e-3
                heapq.heappush(heap, (float(out[ny, nx]), ny, nx))
    return out


def d8_receivers(h, dx):
    """Each cell's receiver (flat index) down its steepest drop over the 8
    neighbours (a diagonal is dx*sqrt2 away); a cell with no lower neighbour
    receives itself."""
    H, W = h.shape
    idx = np.arange(H * W).reshape(H, W)
    best = np.zeros((H, W))
    rcv = idx.copy()
    pad = np.pad(h, 1, mode="edge")
    pidx = np.pad(idx, 1, mode="edge")
    for dy, dx_ in _D8:
        nb = pad[1 + dy:1 + dy + H, 1 + dx_:1 + dx_ + W]
        drop = (h - nb) / (dx * (1.4142135623730951 if dy and dx_ else 1.0))
        take = drop > best
        best = np.where(take, drop, best)
        rcv = np.where(take, pidx[1 + dy:1 + dy + H, 1 + dx_:1 + dx_ + W], rcv)
    return rcv.ravel()


def drainage_area(h, rcv):
    """Cells drained through each cell (itself included), accumulated from the
    highest down; the order is a STABLE sort of the heights, so ties fall the
    same way on every run. Returns (area, order low -> high)."""
    order = np.argsort(h.ravel(), kind="stable")
    area = np.ones(h.size)
    for i in order[::-1]:
        r = rcv[i]
        if r != i:
            area[r] += area[i]
    return area, order


def stream_power(h, rcv, order, area, k, dx, m):
    """One implicit stream-power step (n = 1), worked from the outlets up:
    h_i <- (h_i + F h_rcv) / (1 + F), F = k * area^m / dx. A copy."""
    z = h.ravel().astype(np.float64).copy()
    f = k * area ** m / dx
    for i in order:
        r = rcv[i]
        if r != i:
            z[i] = (z[i] + f[i] * z[r]) / (1.0 + f[i])
    return z.reshape(h.shape)


def thermal(h, dx, talus):
    """Slopes steeper than `talus` (rise over run) toward their lowest of the
    4 neighbours shed half the excess onto it — once, all cells at once."""
    z = h.astype(np.float64)
    out = z.copy()
    pad = np.pad(z, 1, mode="edge")
    low = np.full(z.shape, np.inf)
    arg = np.zeros(z.shape, np.int8)
    for n, (dy, dx_) in enumerate(((-1, 0), (1, 0), (0, -1), (0, 1))):
        nb = pad[1 + dy:1 + dy + z.shape[0], 1 + dx_:1 + dx_ + z.shape[1]]
        take = nb < low
        low = np.where(take, nb, low)
        arg = np.where(take, n, arg)
    move = np.maximum(z - low - talus * dx, 0.0) * 0.5
    out -= move
    for n, (dy, dx_) in enumerate(((-1, 0), (1, 0), (0, -1), (0, 1))):
        part = np.where(arg == n, move, 0.0)
        out += _shift(part, dy, dx_)
    return out


def _shift(a, dy, dx):
    """`a` moved by (dy, dx) cells, edges dropped (the mass lands on the
    neighbour each cell sent it to)."""
    out = np.zeros_like(a)
    H, W = a.shape
    yd = slice(max(dy, 0), H + min(dy, 0))
    ys = slice(max(-dy, 0), H + min(-dy, 0))
    xd = slice(max(dx, 0), W + min(dx, 0))
    xs = slice(max(-dx, 0), W + min(-dx, 0))
    out[yd, xd] = a[ys, xs]
    return out


def erode(height, land, rules):
    """The landform carved by running water (option A): the vertex heights
    averaged onto an erosion_cell_m grid, pits filled to the sea, then
    erosion_iters rounds of D8 routing + stream power + talus; only the
    CHANGE is brought back to the vertices (bilinear), capped by
    erosion_max_cut_m, faded in from erosion_from_m to erosion_full_m, times
    erosion_strength. Returns the new heights."""
    if rules.get("erosion_strength", 0.0) <= 0.0:
        return height
    vh, vw = height.shape
    f = max(int(round(rules["erosion_cell_m"] / VERTEX_M)), 1)
    ch, cw = vh // f, vw // f
    dx = f * VERTEX_M
    coarse = height[:ch * f, :cw * f].reshape(ch, f, cw, f).mean(axis=(1, 3)).astype(np.float64)
    wet = ~(land[:ch * f, :cw * f].reshape(ch, f, cw, f).mean(axis=(1, 3)) > 0.5)
    edge = np.zeros_like(wet)
    edge[0, :] = edge[-1, :] = True
    edge[:, 0] = edge[:, -1] = True
    z0 = fill_pits(coarse, wet | edge)
    z = z0.copy()
    for _ in range(int(rules["erosion_iters"])):
        rcv = d8_receivers(z, dx)
        area, order = drainage_area(z, rcv)
        z = stream_power(z, rcv, order, area, rules["erosion_k"], dx, rules["erosion_m_exp"])
        z = thermal(z, dx, rules["erosion_talus"])
        z[wet] = z0[wet]
    # saturated softly, never clipped flat (a clipped cut leaves a level floor)
    cap = rules["erosion_max_cut_m"]
    delta = z - z0
    delta = np.where(delta < 0, -cap * np.tanh(-delta / cap), cap * 0.3 * np.tanh(delta / (cap * 0.3)))
    up = np.asarray(Image.fromarray(delta.astype(np.float32)).resize((cw * f, ch * f), Image.BILINEAR))
    full = np.zeros((vh, vw), np.float32)
    full[:ch * f, :cw * f] = up
    lift = np.clip((height - rules["erosion_from_m"])
                   / max(rules["erosion_full_m"] - rules["erosion_from_m"], 1.0), 0, 1)
    return np.where(land, height + rules["erosion_strength"] * lift * full, height).astype(np.float32)


def river_fade(courses, vw, vh, reach, head_v=0.0, head_share=1.0):
    """0 on every course (vertex-unit polylines, source -> mouth), easing up to
    1 at `reach` vertices (4-neighbour steps, smoothstep): the ridges are
    multiplied by it, so no ridge is thrown across a river's valley for the
    carve to cut a gorge through (the 2D relief detail holds itself down near
    rivers too, docs/superpowers/specs/2026-09-17-relief-detail-design.md).
    The first `head_v` vertices of each course hold only `head_share` of the
    reach (spec 2026-10-13-landform-rework, phase 0): a valley starts in a
    narrow notch, never a round bowl cleared round its source."""
    body = Image.new("L", (vw, vh), 0)
    head = Image.new("L", (vw, vh), 0)
    db, dh = ImageDraw.Draw(body), ImageDraw.Draw(head)
    for c in courses:
        pts = [(float(x), float(y)) for x, y in c]
        if len(pts) < 2:
            continue
        if head_v <= 0.0 or head_share >= 1.0:
            db.line(pts, fill=255, width=1)
            continue
        run, split = 0.0, None
        for i in range(1, len(pts)):
            seg = float(np.hypot(pts[i][0] - pts[i - 1][0], pts[i][1] - pts[i - 1][1]))
            if run + seg >= head_v:
                f = (head_v - run) / max(seg, 1e-9)
                at = (pts[i - 1][0] + (pts[i][0] - pts[i - 1][0]) * f,
                      pts[i - 1][1] + (pts[i][1] - pts[i - 1][1]) * f)
                split = (i, at)
                break
            run += seg
        if split is None:
            dh.line(pts, fill=255, width=1)
            continue
        i, at = split
        dh.line(pts[:i] + [at], fill=255, width=1)
        db.line([at] + pts[i:], fill=255, width=1)

    def eased(img, r):
        m = np.asarray(img) > 0
        if not m.any():
            return np.ones((vh, vw), np.float32)
        r = max(int(r), 1)
        t = distance_steps(m, r) / float(r)
        return (t * t * (3.0 - 2.0 * t)).astype(np.float32)
    return np.minimum(eased(body, reach), eased(head, reach * head_share))


def river_bed(ground, depth, drop, floor, restart=None):
    """Bed heights source -> mouth: `depth` under the ground, but always at
    least `drop` below the step before, never under `floor`. With `restart`
    (a mask, True inland) the fall begins afresh where each inland stretch
    begins, and the shore or lake samples before one only follow their own
    ground: a course rising on a lake shore or crossing a lake would
    otherwise hold its whole length down at the water's depth, a trench.
    The last stretch, the mouth, keeps falling into the sea."""
    bed = np.empty(len(ground), dtype=np.float64)
    prev = np.inf
    inland = np.flatnonzero(restart) if restart is not None else []
    last = int(inland[-1]) if len(inland) else -1
    for i, g in enumerate(ground):
        if i <= last and (not restart[i] or (i > 0 and not restart[i - 1])):
            prev = np.inf
        prev = max(min(g - depth, prev - drop), floor)
        bed[i] = prev
    return bed


def river_widths(n, w_mouth, gamma, w_source):
    """n widths growing from w_source to w_mouth as t^gamma (the 2D taper)."""
    t = np.linspace(0.0, 1.0, n) if n > 1 else np.ones(1)
    return np.maximum(w_mouth * t ** gamma, w_source)


def town_hold(pts, towns, hold_v):
    """Per sample of a course (vertex units): 0 within hold_v of a settlement,
    rising to 1 at twice that — near a town a river keeps the width its
    houses, quays and bridge were laid against (the full estuary displaced
    ~330 houses)."""
    if hold_v <= 0.0 or towns is None or not len(towns):
        return np.ones(len(pts))
    from scipy.spatial import cKDTree
    dist, _ = cKDTree(towns).query(np.asarray(pts, dtype=np.float64))
    return np.clip(dist / hold_v - 1.0, 0.0, 1.0)


def estuary(n, n_est, to_sea, widen, power, wobble=0.0, wave=1.0, salt=0):
    """Each sample's width factor over a true mouth's last n_est samples: 1
    upstream, opening as s^power to 1 + widen at the sea (s 0 -> 1 down the
    stretch) — a funnel, where a river's last stretch read as a ribbon
    stopped abruptly by the sea (critic 2026-10-06). `wobble` swings the
    opening by up to that share with a slow noise every `wave` samples, so
    the funnel's banks wander instead of ruling a wedge. An inland end
    keeps 1."""
    if not to_sea or n_est <= 0 or widen <= 0.0:
        return np.ones(n)
    s = np.clip((np.arange(n) - (n - 1 - n_est)) / float(n_est), 0.0, 1.0)
    swing = np.ones(n)
    if wobble > 0.0:
        rng = np.random.default_rng(SEED + 59 + salt)
        x = np.arange(n) / max(wave, 1.0)
        knots = rng.uniform(-1.0, 1.0, int(x[-1]) + 3)
        i = np.floor(x).astype(np.int64)
        f = x - i
        f = f * f * (3.0 - 2.0 * f)
        swing = 1.0 + wobble * (knots[i] * (1.0 - f) + knots[i + 1] * f)
    return 1.0 + widen * s ** power * swing


def bank_jitter(i, wave, amount, salt=0):
    """1 +- `amount`: a slow wave along a course, sample `i` of it, `wave`
    samples between its knots (hash01 at each knot, smoothstep between), so
    a bank is steeper in one reach and gentler in the next; the same course
    always draws the same wave."""
    if amount <= 0.0:
        return 1.0
    k = int(i // wave)
    t = (i - k * wave) / wave
    t = t * t * (3.0 - 2.0 * t)
    a, b = hash01(np.array([k, k + 1]) + salt * 7919, 31)
    return 1.0 + amount * ((a * (1.0 - t) + b * t) - 0.5) * 2.0


def carve(height, wet, pts, bed, widths_v, rules):
    """Cut each sample's valley into `height` (vertex units, in place): a flat
    bed across the water, then banks easing out over the valley's width
    L = (ground - bed) / river_bank_slope + 1 (at most river_bank_max_m),
    the ground at centre fixing it. A bank vertex s out from the water sinks
    by its OWN height over the bed times (1 - s / L), never under the slope
    rising from the bed: on flat ground that is the slope, where the ground
    rises to one side the bank climbs with it (a slope sized from the centre
    alone stopped short of it and left a wall), and nothing past L is
    touched (a slope out to where it met the ground planed whole hillsides).
    `wet` takes the band beside the water (0..1).
    Spec 2026-10-13-landform-rework, phase 0: the bank is CONCAVE
    (river_bank_profile p: the floor rises as slope * s^p / L^(p-1), gentle by
    the water and steepening out to the same height at L), and its slope swings
    along the course by river_bank_slope_jitter on a slow wave of
    river_bank_jitter_m — one even 0.35 trench everywhere read as smooth
    gutters (a third of the land at that one slope)."""
    H, W = height.shape
    slope0_v = rules["river_bank_slope"] * VERTEX_M      # metres per vertex
    prof = max(rules.get("river_bank_profile", 1.0), 1.0)
    jit = rules.get("river_bank_slope_jitter", 0.0)
    jwave = max(rules.get("river_bank_jitter_m", 1.0) / VERTEX_M, 1.0)
    salt = int(abs(sum(float(x) for x, _ in pts[:4])) * 1000) if len(pts) else 0
    bank_max_v = rules["river_bank_max_m"] / VERTEX_M
    wet_v = rules["river_wet_m"] / VERTEX_M
    # every centre's ground read BEFORE any stamp: each sample lies inside
    # the last one's water, and read after it, the depth is one step's drop
    # and the valley collapses to a wall a vertex wide
    ci = np.clip(np.round(np.asarray(pts)).astype(np.int64), 0, [W - 1, H - 1]) if len(pts) else None
    grounds = height[ci[:, 1], ci[:, 0]].copy() if len(pts) else []
    for i, ((x, y), b, w, g) in enumerate(zip(pts, bed, widths_v, grounds)):
        xi, yi = int(round(x)), int(round(y))
        slope_v = slope0_v * bank_jitter(i, jwave, jit, salt)
        ease = min(max(g - b, 0.0) / slope_v + 1.0, bank_max_v)
        r = int(np.ceil(w * 0.5 + max(ease, wet_v))) + 1
        x0, x1 = max(xi - r, 0), min(xi + r + 1, W)
        y0, y1 = max(yi - r, 0), min(yi + r + 1, H)
        if x0 >= x1 or y0 >= y1:
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1]
        s = np.maximum(np.hypot(xx - x, yy - y) - w * 0.5, 0.0)   # out from the water's edge
        sub = height[y0:y1, x0:x1]
        eased = sub - np.maximum(sub - b, 0.0) * (1.0 - np.clip(s / ease, 0.0, 1.0) ** prof)
        floor_s = b + slope_v * s ** prof / max(ease, 1.0) ** (prof - 1.0)
        np.minimum(sub, np.maximum(floor_s, eased), out=sub)
        wsub = wet[y0:y1, x0:x1]
        np.maximum(wsub, np.clip(1.0 - s / wet_v, 0.0, 1.0), out=wsub)

# --- the patchwork (owner 2026-09-19: the ground between villages was one flat
# plain; make it read like a satellite map) -----------------------------------------

def hash01(a, salt=0):
    """A fixed pseudo-random number in [0, 1) per integer in `a` (any shape):
    the same integer always gives the same number — a look, never simulation."""
    with np.errstate(over="ignore"):   # splitmix64: the wrap-around is the point
        x = (np.asarray(a, dtype=np.uint64) + np.uint64(salt) * np.uint64(0x9E3779B97F4A7C15))
        x = (x ^ (x >> np.uint64(30))) * np.uint64(0xBF58476D1CE4E5B9)
        x = (x ^ (x >> np.uint64(27))) * np.uint64(0x94D049BB133111EB)
        x = x ^ (x >> np.uint64(31))
    return (x >> np.uint64(11)).astype(np.float64) / float(1 << 53)


def field_cells(xs, ys, cell_v, stretch, angle, centres=False):
    """Strip fields (critic 2026-09-19: Voronoi outlines read as cells, not
    fields): rows of long strips, `cell_v` across on average and `stretch`
    times as long as wide, laid in a frame turned by `angle` (per point),
    each row's strips staggered like brickwork and each strip's length
    varied by hash. Returns (field id, the distance to the nearest field
    edge in the same units as xs/ys)."""
    ca, sa = np.cos(angle), np.sin(angle)
    ls = cell_v * np.sqrt(stretch)       # along the strip
    ws = cell_v / np.sqrt(stretch)       # across it
    u = (xs * ca + ys * sa) / ls
    v = (-xs * sa + ys * ca) / ws
    row = np.floor(v).astype(np.int64)
    # each row's strips start at their own offset: no crossroads grid
    uu = u + hash01(row & 0xFFFFFF, 9)
    col = np.floor(uu).astype(np.int64)
    key = (col & 0xFFFFF) | ((row & 0xFFFFF) << 20)
    # a strip's far end moves by up to a third of its length (merged with
    # the next one when it runs short), so the strips are not all one size
    cut = 0.35 + 0.3 * hash01(key, 10)
    fu = uu - col
    far = fu > cut + 0.5
    merged = far & (hash01(key, 11) < 0.5)
    key = np.where(merged, key + 1, key)
    du = np.minimum(fu, 1.0 - fu) * ls
    dv = np.minimum(v - row, 1.0 - (v - row)) * ws
    if not centres:
        return key, np.minimum(du, dv)
    # each field's middle (`centres`: a close decided WHOLE at it) — a merged
    # far end takes the middle of the strip it joined, so one key, one middle
    uc = (col + merged + 0.5 - hash01(row & 0xFFFFFF, 9)) * ls
    vc = (row + 0.5) * ws
    return key, np.minimum(du, dv), uc * ca - vc * sa, uc * sa + vc * ca


FARM_ZONES = ("croft", "arable", "meadow", "pasture", "bare")


def load_fields(path, texture_keys, zones_path=None):
    """The open fields (owner 2026-10-01): data/screens/map3d/map3d_farm_zones.csv (each
    focus's reach, croft ring and arable share) with data/screens/map3d/map3d_fields.csv
    (its crops, zone by zone) as {focus: {"reach": m, "croft": m, "arable":
    share, "zones": {zone: [(share, tex, tint, bare_share)]}}}; a crop's
    texture by its bake key (the first layer of that name)."""
    zones_path = zones_path or os.path.join(os.path.dirname(path), "map3d_farm_zones.csv")
    out = {}
    with open(zones_path) as f:
        for r in csv.DictReader(f):
            out[r["focus"]] = {"reach": float(r["reach_m"]), "croft": float(r["croft_m"]),
                               "arable": float(r["arable_share"]), "zones": {z: [] for z in FARM_ZONES}}
    with open(path) as f:
        for r in csv.DictReader(f):
            if r["focus"] not in out:
                raise ValueError("map3d_fields.csv: focus %r has no row in map3d_farm_zones.csv" % r["focus"])
            if r["zone"] not in FARM_ZONES:
                raise ValueError("map3d_fields.csv: unknown zone %r" % r["zone"])
            out[r["focus"]]["zones"][r["zone"]].append(
                (float(r["share"]), texture_keys.index(r["texture"]),
                 srgb_to_lin(hex_rgb(r["tint"])), float(r["bare_share"] or 0)))
    return out


def jitter_cells(xs, ys, cell, salt=0):
    """A jittered-grid Voronoi of `cell` (units of xs/ys): for each point the
    id of its nearest seed, that seed's position, and the distance to the
    cell's edge (half the gap between the nearest and second-nearest seed).
    The FURLONGS of the open fields: blocks of a few hundred metres, each one
    whole (one crop, one strip direction)."""
    fx = np.floor(xs / cell).astype(np.int64)
    fy = np.floor(ys / cell).astype(np.int64)
    d1 = np.full(xs.shape, np.inf)
    d2 = np.full(xs.shape, np.inf)
    best = np.zeros(xs.shape, dtype=np.int64)
    bx = np.zeros(xs.shape)
    by = np.zeros(xs.shape)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            gx, gy = fx + ox, fy + oy
            key = (gx & 0xFFFFFF) | ((gy & 0xFFFFFF) << 24)
            sx = (gx + 0.15 + 0.7 * hash01(key, 30 + salt)) * cell
            sy = (gy + 0.15 + 0.7 * hash01(key, 31 + salt)) * cell
            d = np.hypot(xs - sx, ys - sy)
            closer = d < d1
            d2 = np.where(closer, d1, np.minimum(d2, d))
            d1 = np.where(closer, d, d1)
            best = np.where(closer, key, best)
            bx = np.where(closer, sx, bx)
            by = np.where(closer, sy, by)
    return best, bx, by, 0.5 * (d2 - d1)


def pick_crop(h, crops):
    """The crop a field with hash `h` (0..1) sows: by the crops' shares."""
    total = sum(c[0] for c in crops)
    idx = np.zeros(np.shape(h), dtype=np.int64)
    edge = 0.0
    for i, c in enumerate(crops[:-1]):
        edge += c[0] / total
        idx = np.where(np.asarray(h) >= edge, i + 1, idx)
    return idx


FIELD_MAP_STEP = 2   # vertices per field-map texel (40 m)


def field_map(ftint, fangle, step=FIELD_MAP_STEP):
    """The terrain shader's field map, RGBA8 at one texel per `step`
    vertices: RGB the fields' own colour multiplier (1 = no field, raw
    bytes, not sRGB), A a field's strip direction as a share of a half turn.
    The colour is averaged over the texel; the direction is sampled, not
    averaged — an average across two estates' directions is neither."""
    h, w = fangle.shape
    hh, ww = h // step, w // step
    rgb = ftint[:hh * step, :ww * step].astype(np.float32).reshape(hh, step, ww, step, 3).mean(axis=(1, 3))
    out = np.empty((hh, ww, 4), dtype=np.uint8)
    out[..., :3] = np.round(np.clip(rgb, 0, 1) * 255).astype(np.uint8)
    out[..., 3] = np.round(np.clip(fangle[:hh * step:step, :ww * step:step].astype(np.float32), 0, 1) * 255).astype(np.uint8)
    return out


def house_radius_m(burg, rules):
    """A settlement's house-cluster radius: sqrt(count * m2_each / pi), both
    the count (house_count_<group>) and the density (house_m2_each_<group>)
    fixed by the burg's own GROUP, never by its population. Duplicated from
    bake_houses.house_radius_m — kept independent, not a call-through, so a
    slip between the two shows up as a test failure
    (test_footprint_radius_agrees_between_the_two_modules) rather than
    silently agreeing with itself. See that function's own note, and
    house_m2_each_capital's in data/screens/map3d/map3d_bake.csv, for why this replaced
    the population-driven footprint formula (owner 2026-09-21, density v4)."""
    group = str(burg.get("group", "village"))
    n = float(rules.get("house_count_%s" % group, rules["house_count_village"]))
    m2 = float(rules.get("house_m2_each_%s" % group, rules["house_m2_each_village"]))
    return float(np.sqrt(max(n, 0.0) * m2 / np.pi))


def footprint_radius_m(burg, rules):
    """A settlement's built ground: the house cluster grown out by a buffer
    ring, house_built_share the cluster's own share of it."""
    return house_radius_m(burg, rules) / rules["house_built_share"]


def house_types(path=None):
    """data/screens/map3d/map3d_houses.csv as the house bake reads it: each type's role,
    weight, footprint, measured rectangle, least group and — for a landmark
    that stands in true proportion (owner 2026-09-30, the palaces) — its own
    `landmark_height_scale` ("" takes house_height_max)."""
    types = {}
    with open(path or os.path.join(ROOT, "data", "screens", "map3d", "map3d_houses.csv")) as f:
        for r in csv.DictReader(f):
            types[r["type"]] = {"role": r["role"], "weight": float(r["weight"]),
                                "footprint_m": float(r["footprint_m"]),
                                # measured off the built mesh: the packer
                                # reserves the building's real rectangle, not
                                # a square of its long side (density v5)
                                "width_m": float(r.get("width_m") or 0.0),
                                "depth_m": float(r.get("depth_m") or 0.0),
                                "min_group": r["min_group"],
                                "height_m": float(r.get("height_m") or 0.0),
                                "landmark_height_scale": r.get("landmark_height_scale", "") or "",
                                # owner 2026-10-10: the type's own width stretch,
                                # its rim weight multiplier and the weight with
                                # which it strays into a group below its own
                                "stretch": float(r.get("stretch") or 0.0),
                                "rim_mul": float(r.get("rim_mul") or 1.0),
                                "stray_weight": float(r.get("stray_weight") or 0.0)}
    return types


def green_cut(tw, t_rock, window, w):
    """A port plain's cut ground is grass, not the cliff it was (owner
    2026-10-12, R18): the ground weights were read from the slope BEFORE
    bake_houses.port_plain cut it, so over its `window` (y0, y1, x0, x1) the
    CLIFF, ROCKY and SOIL weight moves to GRASS by the cut's weight `w`, and
    `t_rock` (the fields' slope test) falls with it. In place."""
    y0, y1, x0, x1 = window
    sub = tw[y0:y1, x0:x1]
    for t in (CLIFF, ROCKY, SOIL):
        moved = sub[..., t] * w
        sub[..., t] -= moved
        sub[..., GRASS] += moved
    t_rock[y0:y1, x0:x1] *= 1.0 - w


def sow_patchwork(tw, rules, MAP, OUT, PACK, has_cell, cell_id, land, height, hn, t_rock,
                  beach, wet, k, vw, vh, pw, ph, origin):
    """Village footprints, the fields round them, each manor's own shade
    (owner 2026-09-19) and the houses that stand on that built ground (spec
    2026-09-20 §1). Adds the fields' and footprints' grounds to `tw` in
    place and returns the colour map's multiplier per vertex (vh, vw, 3, in
    linear light), the terrain shader's field map, and the houses of every
    settlement in world metres (`origin` is the world position of pack px
    (0,0), the same pair `main()` writes into world.json as `pack_origin`).
    Its own random stream, so the rest of the look is unchanged."""
    ORIGIN_X, ORIGIN_Y = origin
    prng = np.random.default_rng(SEED + 1)
    fields = load_fields(os.path.join(ROOT, "data", "screens", "map3d", "map3d_fields.csv"), TEXTURE_KEYS)
    focus_keys = sorted(fields)
    other = focus_keys.index("*")
    max_cell = int(cell_id.max()) + 1
    cell_focus = np.full(max_cell, other, dtype=np.int64)
    land_csv = os.path.join(OUT, "manor_land.csv")
    if os.path.exists(land_csv):
        with open(land_csv) as f:
            for r in csv.DictReader(f):
                c = int(r["cell_id"])
                if c < max_cell:
                    cell_focus[c] = focus_keys.index(r["focus"]) if r["focus"] in fields else other
    else:
        print("bake_world: no manor_land.csv (tools/map3d/export_manor_land.gd) — every manor sown as '*'")
    reach_of = np.array([fields[f]["reach"] for f in focus_keys], dtype=np.float32)
    croft_of = np.array([fields[f]["croft"] for f in focus_keys], dtype=np.float32)
    arable_of = np.array([fields[f]["arable"] for f in focus_keys], dtype=np.float32)
    edge_n = value_noise(prng, vw, vh, rules["field_edge_noise_m"] / VERTEX_M)
    block_n = value_noise(prng, vw, vh, rules["footprint_block_m"] / VERTEX_M)
    fray_n = value_noise(prng, vw, vh, 3.0 * rules["footprint_block_m"] / VERTEX_M)
    # the fields' own warp (critic 2026-09-19: straight Voronoi edges and
    # ruled hedges read as polygons): the layout is sampled through a noise
    # displacement, so the hedges wander like a real field's
    warp_v = rules["field_warp_m"] / VERTEX_M
    warp_x = (2.0 * value_noise(prng, vw, vh, rules["field_warp_wave_m"] / VERTEX_M) - 1.0) * warp_v
    warp_y = (2.0 * value_noise(prng, vw, vh, rules["field_warp_wave_m"] / VERTEX_M) - 1.0) * warp_v
    grain_n = value_noise(prng, vw, vh, rules["field_grain_m"] / VERTEX_M)
    snow = np.clip((hn - rules["snow_line_lo"]) / max(rules["snow_line_hi"] - rules["snow_line_lo"], 1e-6), 0, 1)

    # village footprints first: fields never cover the houses
    def stamp_foot(foot, cx, cy, r):
        reach = r * (1.0 + rules["footprint_edge_noise"]) + 2
        x0, x1 = max(int(cx - reach), 0), min(int(cx + reach) + 1, vw)
        y0, y1 = max(int(cy - reach), 0), min(int(cy + reach) + 1, vh)
        if x0 >= x1 or y0 >= y1:
            return
        yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
        d = np.hypot(xx - cx, yy - cy) / max(r, 1e-6)
        edge = 1.0 + rules["footprint_edge_noise"] * (2.0 * fray_n[y0:y1, x0:x1] - 1.0)
        # the built ground thins outward over footprint_fade of its
        # radius: no disc, no rim (taste: nothing ends on a hard cut)
        mf = np.clip((edge - d) / rules["footprint_fade"], 0, 1) ** 1.5 * land[y0:y1, x0:x1]
        foot[y0:y1, x0:x1] = np.maximum(foot[y0:y1, x0:x1], mf)

    types = house_types()
    # the drawn roads, smoothed as the runtime smooths them, in world metres:
    # a walled town's gates stand where they cross its wall (owner 2026-10-01)
    road_lines = []
    with open(os.path.join(ROOT, "data", "maps", MAP, "geography", "routes.csv")) as f:
        steps = int(data_index.balance()["map_route_smoothing_steps"])
        for r in csv.DictReader(f):
            pts = [tuple(float(v) for v in p.split()) for p in r["points"].split("|") if p.strip()]
            line = bake_houses.smooth_open(pts, steps)
            road_lines.append([(ORIGIN_X + x * M_PER_PX, ORIGIN_Y + y * M_PER_PX) for x, y in line])
    # world_cell_index.png is the GAME's own land test (MapManors.cell_at,
    # what test_no_house_stands_in_the_sea checks against): a pack-px raster,
    # coarser than this bake's own fine coastline coverage (`land`). A house
    # must stand on land in BOTH, or a port's quay -- where the burg's own
    # (x, y) can sit on a "no cell" pack pixel a metre or two off true land
    # -- reads as land here and sea there. `land` itself (the fine mask that
    # `foot`/the fields already used above) is left untouched, so the
    # patchwork's own percentages do not move; this stricter mask is only
    # for placing houses.
    pxi_g = np.clip((np.arange(vw) / k).astype(np.int64), 0, pw - 1)
    pyi_g = np.clip((np.arange(vh) / k).astype(np.int64), 0, ph - 1)
    land_gate = land & has_cell[pyi_g][:, pxi_g]
    # open water by BOTH tests: a pier's head must stand where the game's
    # cell index is sea too (owner 2026-10-01, 码头延伸到海里)
    open_water = ~(land.astype(bool) | has_cell[pyi_g][:, pxi_g])
    del pxi_g, pyi_g
    # every settlement is laid out round its LANDMARK's own spot (owner
    # 2026-09-25: 标志性建筑要在中间附近), which moves off water or a slope,
    # so its built ground is stamped round that spot and not the burg's point
    burgs = []
    with open(os.path.join(ROOT, "data", "maps", MAP, "political", "burgs.csv")) as f:
        for b in csv.DictReader(f):
            b = dict(b)
            b["population"] = float(b["population"] or 0)
            site = bake_houses.landmark_of(b, rules, types, land_gate, height, k, vw, vh, wet=wet)
            lx, lz = site[2] if site[2] is not None else (0.0, 0.0)
            cx, cy = float(b["x"]) * k + lx / VERTEX_M, float(b["y"]) * k + lz / VERTEX_M
            if site[0] is not None and site[2] is not None:
                # the landmark stands on a levelled terrace, not on a tower
                # of its own footing (owner 2026-09-25)
                bake_houses.level_pad(height, cx, cy, bake_houses.half_extents(types[site[0]]), site[1],
                                      rules, land=land, wet=wet)
                # a cliff port is lowered onto a plain landing so it takes the
                # timber pier (owner 2026-10-12, R9: 不要使用带有悬崖高的码头)
                # (R18: a cliff-top town too, though a low shore is in reach)
                plain = bake_houses.port_plain(b, height, cx, cy, rules, types, rules["sea_y_m"],
                                               open_water, land=land, wet=wet)
                if plain["cut"] is None:
                    print("bake_world: port %s left on its cliff — its landing needs %.0f m cut, more than "
                          "port_plain_max_cut_m (%g m); it still takes a pier by pier_search_fallback_m" % (b["burg_code"], plain["need"],
                                                          rules["port_plain_max_cut_m"]))
                elif plain["window"] is not None:
                    print("bake_world: port %s lowered onto a plain landing (cut %.1f m, blend %.0f m)"
                          % (b["burg_code"], plain["cut"], plain["blend"]))
                    green_cut(tw, t_rock, plain["window"], plain["w"])
            burgs.append((b, cx, cy, site))
    foot = np.zeros((vh, vw), dtype=np.float32)
    for b, cx, cy, _site in burgs:
        stamp_foot(foot, cx, cy, bake_houses.cluster_radius_m(b, rules, types)
                   / rules["house_built_share"] / VERTEX_M)

    # the houses that stand on that built ground (spec 2026-09-20 §1). The
    # footprint mask is finished, so "inside the built ground" and "never in
    # the sea" are the same test the footprint already passed.
    house_rows = []
    built = []          # (cx, cy, r) per settlement that actually built something
    built_r = np.zeros(len(burgs), dtype=np.float32)   # the same r, by burg (0: none)
    r_house_mask = np.zeros((vh, vw), dtype=np.float32)
    # A RIVER IS WATER TOO (2026-09-21). `land` is the COASTLINE's mask, so a
    # carved river ran straight through the gate and a riverside town put a
    # third of its houses in the water — Carden, a capital, was half afloat
    # with barns drifting on the blue. `wet` is 1 inside the drawn channel
    # and fades to 0 over river_wet_m beyond it, so it reads as a DISTANCE
    # from the water's edge and bake_houses tests each candidate against it
    # by that house's own half-width.
    #
    # It is deliberately NOT folded into `land_gate`: _dry() applies
    # house_shore_min_m (25 m) around everything in that mask, and a town
    # does not stand 25 m back from its own river — it stands ON it, which
    # is what the bridge is for. Tried: Shole, a town of 50, came out with
    # four buildings and its bridge crossing an empty bank.
    for bi, (b, cx, cy, site) in enumerate(burgs):
        rows = bake_houses.place(b, rules, types, foot, land_gate, height, k, vw, vh,
                                 wet=wet, site=site)
        lx, lz = (cx - float(b["x"]) * k) * VERTEX_M, (cy - float(b["y"]) * k) * VERTEX_M
        r_house = bake_houses.cluster_radius_m(b, rules, types) / VERTEX_M
        # the block noise stops where the real roofs begin (§1): roofs
        # painted on the ground beside real roofs read as a mistake --
        # but only where there ARE roofs; a settlement place() gave
        # nothing to (no dry land within its search) keeps its painted
        # blocks, which is what the fade is for
        if rows:
            x0, x1 = max(int(cx - r_house) - 1, 0), min(int(cx + r_house) + 2, vw)
            y0, y1 = max(int(cy - r_house) - 1, 0), min(int(cy + r_house) + 2, vh)
            if x0 < x1 and y0 < y1:
                yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
                d = np.hypot(xx - cx, yy - cy) / max(r_house, 1e-6)
                r_house_mask[y0:y1, x0:x1] = np.maximum(
                    r_house_mask[y0:y1, x0:x1], np.clip(1.5 - 1.5 * d, 0, 1))
        # the built ground this settlement ACTUALLY earned: the cluster
        # that got placed, grown back out by house_built_share into the
        # buffer ring the owner asked for (2026-09-20: 定居点周边和地图
        # 上的地形要有一定距离的缓冲过渡). The nominal radius is what the
        # group would fill on open, level ground; a site that is half
        # water or too steep to build on fills less of it, and stamping
        # the nominal disc there left a bare brown pancake with nothing
        # standing on it — worst on the 24 settlements whose ground
        # refuses every house, which drew a disc and not one roof.
        spread = max((math.hypot(r["x_m"] - lx, r["z_m"] - lz) for r in rows), default=0.0)
        if spread > 0.0:
            built.append((cx, cy, min(spread / VERTEX_M / rules["house_built_share"],
                                      r_house / rules["house_built_share"])))
            built_r[bi] = built[-1][2]
        # a walled town's wall and a port's pier (owner 2026-10-01), as more
        # rows of its own, laid round the houses that just got placed
        if rows:
            ox, oz = ORIGIN_X + float(b["x"]) * M_PER_PX, ORIGIN_Y + float(b["y"]) * M_PER_PX
            near = (bake_houses.cluster_radius_m(b, rules, types) + rules["wall_margin_m"]) * 3.0
            roads = [[(x - ox, z - oz) for x, z in line] for line in road_lines
                     if any(abs(x - ox) < near and abs(z - oz) < near for x, z in line)]
            laid = bake_houses.harbour(b, rows, rules, land_gate, height, k, vw, vh, rules["sea_y_m"],
                                       water=open_water, types=types, sea_cells=~has_cell)
            rows = rows + bake_houses.fortify(b, rows, rules, types, land_gate, wet, k, vw, vh, roads,
                                              height=height)
            rows = bake_houses.clear_under(rows, laid, types, rules)
        for r in rows:
            r["x_m"] = ORIGIN_X + float(b["x"]) * M_PER_PX + r["x_m"]
            r["z_m"] = ORIGIN_Y + float(b["y"]) * M_PER_PX + r["z_m"]
        house_rows.extend(rows)

    # second pass: the disc each settlement earned replaces the one it was
    # offered. It can only ever shrink (the placement was gated on the first
    # pass's own mask), so no house can fall outside its own built ground.
    foot = np.zeros((vh, vw), dtype=np.float32)
    for cx, cy, r in built:
        stamp_foot(foot, cx, cy, r)
    del fray_n

    tint = np.ones((vh, vw, 3), dtype=np.float32)
    # the field-only part of the tint, and each furlong's strip direction
    # (0..1 of a half turn): the terrain shader's field map (furrows and
    # strips up close, the crops' colour eased back far out)
    ftint = np.ones((vh, vw, 3), dtype=np.float16)
    fangle = np.zeros((vh, vw), dtype=np.float16)
    farm = np.zeros((vh, vw), dtype=np.float32)
    crop = np.zeros((vh, vw), dtype=np.int8)
    # the settled ground round each village (visual review 2026-10-05: the
    # fields read scattered in the woods, not round the towns): crofts, arable
    # and meadow open, the common pasture partly — bake_trees thins the woods by it
    settled = np.zeros((vh, vw), dtype=np.float32)
    reach = np.zeros((vh, vw), dtype=np.float32)    # within a village's reach at all
    # each field's distance (m) to its own edge, at the vertices: the shader
    # draws the balks and hedges along it, smooth where the ground's own
    # texture change can only step from vertex to vertex
    edge_in = np.full((vh, vw), -1.0, dtype=np.float32)   # metres to a field's edge inside it, -1 outside
    # each vertex's HEDGE RANK (spec 2026-10-13-open-field-layout §3): a hedge
    # stands where two ranks meet, never between two furlongs of one rank
    hrank = np.zeros((vh, vw), dtype=np.uint8)
    # THE OPEN FIELDS (owner 2026-10-01: 田地的布局要更合理真实). Each
    # vertex belongs to its NEAREST settlement (a Voronoi of their centres,
    # cut at a coarse step and read back), and lies in one of its zones:
    # the crofts behind the houses, the arable — two or three great fields
    # in rotation, split into furlongs, each furlong whole (one crop, one
    # strip direction, decided at its SEED so no furlong is cut in two) — the
    # meadow on wet ground, the common pasture to the edge of reach.
    nb = len(burgs)
    bcx = np.array([c[1] for c in burgs], dtype=np.float64)
    bcy = np.array([c[2] for c in burgs], dtype=np.float64)
    step = 4
    seedmask = np.ones(((vh + step - 1) // step, (vw + step - 1) // step), dtype=bool)
    gix = np.clip((bcx / step).astype(np.int64), 0, seedmask.shape[1] - 1)
    giy = np.clip((bcy / step).astype(np.int64), 0, seedmask.shape[0] - 1)
    owner = np.full(seedmask.shape, -1, dtype=np.int64)
    seedmask[giy, gix] = False
    owner[giy, gix] = np.arange(nb)
    from scipy import ndimage
    _, (iy, ix) = ndimage.distance_transform_edt(seedmask, return_indices=True)
    near_burg = owner[iy, ix].astype(np.int32)
    del seedmask, owner, iy, ix
    meadow_n = np.clip(box(wet.astype(np.float32), int(rules["meadow_reach_m"] / VERTEX_M))
                       * rules["meadow_gain"], 0, 1)
    great_warp = rules["great_warp_m"] / VERTEX_M
    gwx = (2.0 * value_noise(prng, vw, vh, rules["great_warp_wave_m"] / VERTEX_M) - 1.0) * great_warp
    gwy = (2.0 * value_noise(prng, vw, vh, rules["great_warp_wave_m"] / VERTEX_M) - 1.0) * great_warp
    fray2 = value_noise(prng, vw, vh, rules["croft_edge_wave_m"] / VERTEX_M)
    furlong_v = rules["furlong_m"] / VERTEX_M
    croft_v = rules["croft_close_m"] / VERTEX_M
    zone_rows = [{z: fields[f]["zones"][z] for z in FARM_ZONES} for f in focus_keys]

    def great_field(px, py, b, nrot, reach_v):
        """Which great field of settlement `b` the point (px, py) lies in: the
        Voronoi of `nrot` seeds set round it at half its reach, each turned
        by its own hash — the fields' shapes vary village to village."""
        best = np.full(px.shape, np.inf)
        g = np.zeros(px.shape, dtype=np.int64)
        off = hash01(b, 21) * 2.0 * np.pi
        for j in range(3):
            a = off + j * 2.0 * np.pi / np.maximum(nrot, 1) + (hash01(b * 8 + j, 22) - 0.5) * 0.8
            rr = reach_v * (0.4 + 0.25 * hash01(b * 8 + j, 23))
            d = np.hypot(px - (bcx[b] + rr * np.cos(a)), py - (bcy[b] + rr * np.sin(a)))
            d = np.where(j < nrot, d, np.inf)
            closer = d < best
            best = np.where(closer, d, best)
            g = np.where(closer, j, g)
        return g

    for y0 in range(0, vh, 256):
        y1 = min(y0 + 256, vh)
        ys, xs = np.mgrid[y0:y1, 0:vw].astype(np.float64)
        pxi = np.clip((xs / k).astype(np.int64), 0, pw - 1)
        pyi = np.clip((ys / k).astype(np.int64), 0, ph - 1)
        cid = np.where(has_cell[pyi, pxi], cell_id[pyi, pxi], -1)
        cz = np.maximum(cid, 0)
        fi = cell_focus[cz]
        bid = near_burg[(ys / step).astype(np.int64), (xs / step).astype(np.int64)].astype(np.int64)
        if nb == 0:
            bid = np.zeros_like(bid)
        reach_v = reach_of[fi] / VERTEX_M * (1.0 + rules["field_edge_noise"] * (2.0 * edge_n[y0:y1] - 1.0))
        r_v = np.hypot(xs - bcx[bid], ys - bcy[bid]) if nb else np.full(xs.shape, np.inf)
        # what may be farmed at all: land, not steep, snowed, shore or built on
        ok = ((land[y0:y1] & (cid >= 0)) * np.clip(1.0 - t_rock[y0:y1] / rules["field_slope_max"], 0, 1)
              * (1.0 - snow[y0:y1]) * (1.0 - np.clip(2.0 * beach[y0:y1], 0, 1)) * (1.0 - foot[y0:y1]))
        within = np.clip((reach_v - r_v) / (0.2 * reach_v), 0, 1)
        # the furlongs, through the hedges' own warp
        wxs, wys = xs + warp_x[y0:y1], ys + warp_y[y0:y1]
        fid, fsx, fsy, fedge = jitter_cells(wxs, wys, furlong_v)
        # each furlong decided at its seed: in the arable or not, which great field
        seed_r = np.hypot(fsx - bcx[bid], fsy - bcy[bid]) if nb else np.full(xs.shape, np.inf)
        sxi = np.clip(fsx.astype(np.int64), 0, vw - 1)
        syi = np.clip(fsy.astype(np.int64), 0, vh - 1)
        seed_reach = reach_of[fi] / VERTEX_M * (1.0 + rules["field_edge_noise"] * (2.0 * edge_n[syi, sxi] - 1.0))
        # croft closes: small hedged plots behind the houses, each decided
        # WHOLE at its middle (spec 2026-10-13-open-field-layout §3: a croft
        # cut at a radius drew its hedge as a circle round every village); the
        # crofts' reach frays like the farmland's: never a ring round the village
        cfid, cedge, ccx, ccy = field_cells(wxs, wys, croft_v, 1.3, hash01(bid, 27) * np.pi, centres=True)
        cxi = np.clip(ccx.astype(np.int64), 0, vw - 1)
        cyi = np.clip(ccy.astype(np.int64), 0, vh - 1)
        croft_r = built_r[bid] + croft_of[fi] / VERTEX_M * (1.0 + rules["croft_edge_noise"] * (2.0 * fray2[cyi, cxi] - 1.0))
        in_croft = np.hypot(ccx - bcx[bid], ccy - bcy[bid]) <= croft_r if nb else np.zeros(xs.shape, bool)
        arable = (seed_r < seed_reach * arable_of[fi]) & ~in_croft
        nrot = np.array([len(zr["arable"]) for zr in zone_rows])[fi]
        g = great_field(fsx + gwx[syi, sxi], fsy + gwy[syi, sxi], bid, nrot, seed_reach)
        state = (g + (hash01(bid, 24) * np.maximum(nrot, 1)).astype(np.int64)) % np.maximum(nrot, 1)
        fh = hash01(fid ^ (bid << 48), 25)
        waste = hash01(fid ^ (bid << 48), 26) < rules["furlong_waste_share"]
        croft = in_croft & ~arable
        # its edge frays with the crofts' noise: the blurred river drew it as a
        # straight smooth band either side of the water
        meadow = (meadow_n[y0:y1] + rules["meadow_fray"] * (fray2[y0:y1] - 0.5) > 0.35) & ~croft
        open_field = arable & ~meadow          # the waste furlongs lie inside the open field, unhedged
        arable &= ~meadow & ~waste
        tex = np.full(xs.shape, GRASS, dtype=np.int8)
        tt = np.ones(xs.shape + (3,), dtype=np.float32)
        sown = np.zeros(xs.shape, dtype=bool)          # arable: strips and furrows, far-fade
        weight = np.zeros(xs.shape, dtype=np.float32)  # the zone's texture strength
        edge = np.where(croft, cedge, fedge) * VERTEX_M
        for f in range(len(focus_keys)):
            zr = zone_rows[f]
            sel_f = fi == f
            if not sel_f.any():
                continue
            # the arable: the great field's crop, but some furlongs bare
            if zr["arable"]:
                for si, (_, t_, tn, bare) in enumerate(zr["arable"]):
                    sel = sel_f & arable & (state == si)
                    if not sel.any():
                        continue
                    is_bare = fh[sel] < bare
                    tex_s = np.full(is_bare.shape, t_, dtype=np.int8)
                    tint_s = np.broadcast_to(tn, is_bare.shape + (3,)).copy()
                    if zr["bare"] and is_bare.any():
                        tex_s[is_bare] = zr["bare"][0][1]
                        tint_s[is_bare] = zr["bare"][0][2]
                    tex[sel] = tex_s
                    tt[sel] = tint_s
                    sown[sel] = True
                    weight[sel] = 1.0
            for zone, mask in (("croft", croft), ("meadow", meadow), ("pasture", ~croft & ~arable & ~meadow)):
                rows = zr[zone]
                sel = sel_f & mask
                if not rows or not sel.any():
                    continue
                key = (cfid if zone == "croft" else fid) ^ (bid << 48)
                ci = pick_crop(hash01(key[sel], 28), rows)
                tex[sel] = np.array([r_[1] for r_ in rows])[ci]
                tt[sel] = np.array([r_[2] for r_ in rows], dtype=np.float32)[ci]
                weight[sel] = rules["zone_weight_" + zone]
        m = ok * within * (weight > 0)
        pasture = ~croft & ~arable & ~meadow
        reach[y0:y1] = within * land[y0:y1]
        drawn = (sown | croft) & (m > 0)
        edge_in[y0:y1] = np.where(drawn, edge, -1.0)
        # the village's own ground is the crofts' (no hedge rings the houses)
        farmed = ok * within > 0
        hrank[y0:y1] = np.where(croft & land[y0:y1] & (cid >= 0), HEDGE_CROFT,
                                np.where(meadow & (m > 0), HEDGE_MEADOW,
                                         np.where(open_field & farmed, HEDGE_ARABLE, HEDGE_NONE)))
        settled[y0:y1] = reach[y0:y1] * np.where(pasture, rules["pasture_open"], 1.0)
        # a hedge round each croft close; a grass balk between furlongs
        hedge = np.where(croft, 1.0 - rules["croft_hedge_depth"] * np.clip(1.0 - edge / rules["croft_hedge_m"], 0, 1) ** 2, 1.0)
        own = 1.0 + rules["field_shade"] * (2.0 * hash01(np.where(croft, cfid, fid) ^ (bid << 48), 7) - 1.0)
        grain = 1.0 + rules["field_grain"] * (2.0 * grain_n[y0:y1] - 1.0)
        tt *= (hedge * own * grain)[..., None].astype(np.float32)
        soft = np.where(sown, np.clip(edge / rules["field_edge_soft_m"], 0, 1), 1.0)
        farm[y0:y1] = m * soft * weight
        crop[y0:y1] = tex
        # the crop's colour reaches its full tint well before its texture
        # does (field_tint_gain): diluted with the share, a field's rim showed
        # the crop layer's own pale straw as cream patches (visual review
        # 2026-10-05)
        tint[y0:y1] = 1.0 + (tt - 1.0) * np.clip(m * rules["field_tint_gain"], 0, 1)[..., None]
        # the field map: only the arable's colour (far-fade, furrows, strips)
        ftint[y0:y1] = np.where((sown & (m > 0))[..., None], tint[y0:y1], 1.0)
        # each furlong's strips run along or across the line to its village
        ang = np.arctan2(fsy - bcy[bid], fsx - bcx[bid]) + np.where(hash01(fid, 29) < 0.5, 0.0, np.pi / 2) \
            + (hash01(fid, 32) - 0.5) * 0.6
        fangle[y0:y1] = np.mod(ang, np.pi) / np.pi
        # each manor's own shade: a patchwork even where nothing is sown
        jv = (2.0 * hash01(cz, 5) - 1.0) * rules["manor_jitter_value"] * (cid >= 0)
        jh = (2.0 * hash01(cz, 6) - 1.0) * rules["manor_jitter_hue"] * (cid >= 0)
        tint[y0:y1] *= (1.0 + jv)[..., None].astype(np.float32)
        tint[y0:y1, :, 0] *= (1.0 + jh).astype(np.float32)
        tint[y0:y1, :, 2] *= (1.0 - jh).astype(np.float32)
    del edge_n, snow, warp_x, warp_y, grain_n, gwx, gwy, near_burg, meadow_n, fray2

    # the grounds: a field's crop over what grew there, the footprint's
    # trodden earth over both
    tw *= (1.0 - 0.85 * farm)[..., None]
    for t in range(NT):
        tw[..., t] += rules["field_strength"] * farm * (crop == t)
    # the settled ground's woods are thinned (bake_trees settled_clear): within
    # a village's reach the forest floor gives way to grass, or cleared land
    # would read as a dark wood with no trees on it (the woods left standing
    # darken their own floor, woods.png)
    for t in (FOREST, LEAVES):
        moved = tw[..., t] * (rules["settled_grass"] * reach)
        tw[..., t] -= moved
        tw[..., GRASS] += moved
    # the built ground: trodden earth among the yards' grass (look route
    # 2026-09-30: all dirt under a light tint read as a brown pad)
    tw *= (1.0 - rules["footprint_ground_cut"] * foot)[..., None]
    tw[..., DIRT] += rules["footprint_dirt"] * foot
    built = srgb_to_lin(hex_rgb(rules["footprint_tint"])).astype(np.float32)
    block_amt = rules["footprint_block_depth"] * (1.0 - r_house_mask)
    blocks = (1.0 - block_amt * block_n)[..., None] * built
    tint = tint * (1.0 - foot[..., None]) + blocks * foot[..., None]
    print("bake_world: patchwork %.1f%% of the land sown, %.2f%% built" % (
        100.0 * float(farm[land].mean()), 100.0 * float(foot[land].mean())))
    return tint, field_map(ftint, fangle), house_rows, settled_map(settled), edge_map(edge_in), \
        hedge_map(hrank, rules["hedge_line_smooth_m"] / VERTEX_M, rules["hedge_infield_close_m"] / VERTEX_M,
                  rules["hedge_infield_min_km2"] * 1e6 / VERTEX_M ** 2)


EDGE_MAP_ZERO = 128    # bake/field_edges.png: the byte of a field's edge...
EDGE_MAP_PER_M = 2.0   # ...and bytes per metre: inside a field above it, outside below


def edge_map(edge_in):
    """bake/field_edges.png from each vertex's metres to its field's edge
    (-1 outside every field): a SIGNED distance — outside, minus the metres
    to the nearest field — so a bilinear sample runs smooth across a field's
    rim (an unsigned map with a "no field" byte drew the balk along the
    20 m grid, visual review 2026-10-06)."""
    from scipy import ndimage
    inside = edge_in >= 0.0
    out_m = (ndimage.distance_transform_edt(~inside) - 0.5) * VERTEX_M
    d = np.where(inside, edge_in, -np.maximum(out_m, 0.0))
    return np.clip(np.round(EDGE_MAP_ZERO + d * EDGE_MAP_PER_M), 0, 255).astype(np.uint8)


HEDGE_NONE, HEDGE_ARABLE, HEDGE_MEADOW, HEDGE_CROFT = 0, 1, 2, 3
HEDGE_RANK_BYTE = 85   # bake/hedge_lines.png A: the rank x this


def infield(hrank, close_v, min_v):
    """The township's IN-FIELD (its open field, meadows and crofts) as one
    hedged whole: closed over `close_v` vertices, its holes filled and
    islands under `min_v` vertices dropped — the ring fence of the township,
    not the outline of every patch of meadow (a hedge round each wet blob
    snaked along the rivers)."""
    from scipy import ndimage
    region = hrank >= HEDGE_ARABLE
    r = int(round(close_v))
    if r > 0:
        yy, xx = np.mgrid[-r:r + 1, -r:r + 1]
        disk = xx * xx + yy * yy <= r * r
        region = ndimage.binary_closing(np.pad(region, r), structure=disk)[r:-r, r:-r] | region
    region = ndimage.binary_fill_holes(region)
    lab, n = ndimage.label(region)
    if n:
        size = ndimage.sum(np.ones_like(lab), lab, np.arange(1, n + 1))
        region &= (size >= min_v)[np.maximum(lab - 1, 0)] & (lab > 0)
    return region


def hedge_map(hrank, smooth_v, close_v=0.0, min_v=0.0):
    """bake/hedge_lines.png (spec 2026-10-13-open-field-layout §3a), RGBA8 at
    the vertices. The hedges stand where history put them (owner 2026-10-13,
    按历史): round the township's in-field — its open field, meadows and
    crofts against the common pasture and the woods (`infield`) — and round
    the crofts; inside the open field no hedge parts two furlongs, and the
    meadows, shared and mown like the open field, are open too.

    R the in-field, G the crofts: each region's SIGNED metres to its own edge
    (inside positive), encoded as field_edges.png (EDGE_MAP_ZERO,
    EDGE_MAP_PER_M), taken on the vertex grid and blurred over `smooth_v`
    vertices so the line runs as a soft curve through the 20 m staircase. B is
    unused (far). A hedge is where ANY channel crosses zero: the reader takes
    the least |distance| AFTER each channel's bilinear sample (one channel
    holding the nearest line's distance would cross zero midway between two
    lines, and an unsigned one never reaches zero between two vertices).
    A: the vertex's rank x HEDGE_RANK_BYTE."""
    from scipy import ndimage
    out = np.empty(hrank.shape + (4,), dtype=np.uint8)
    far = min(EDGE_MAP_ZERO + 64.0 * EDGE_MAP_PER_M, 255)
    out[..., 2] = np.uint8(far)
    for c, region in enumerate((infield(hrank, close_v, min_v), hrank >= HEDGE_CROFT)):
        if not region.any() or region.all():
            out[..., c] = np.uint8(far if region.all() else 0)
            continue
        sd = np.where(region, ndimage.distance_transform_edt(region) - 0.5,
                      -(ndimage.distance_transform_edt(~region) - 0.5)).astype(np.float32) * VERTEX_M
        if smooth_v > 0:
            sd = ndimage.gaussian_filter(sd, smooth_v)
        out[..., c] = np.clip(np.round(EDGE_MAP_ZERO + sd * EDGE_MAP_PER_M), 0, 255)
    out[..., 3] = np.minimum(hrank.astype(np.int32) * HEDGE_RANK_BYTE, 255)
    return out


def hedge_distance(hmap):
    """Metres to the nearest hedge line per texel of a hedge_map (the least
    |distance| of its three levels)."""
    d = (hmap[..., :3].astype(np.float32) - EDGE_MAP_ZERO) / EDGE_MAP_PER_M
    return np.abs(d).min(axis=-1)


def settled_map(settled, step=FIELD_MAP_STEP):
    """The settled ground (0..1 per vertex) as bake_trees reads it: L8 at
    one texel per `step` vertices, averaged over the texel."""
    h, w = settled.shape
    hh, ww = h // step, w // step
    a = settled[:hh * step, :ww * step].astype(np.float32).reshape(hh, step, ww, step).mean(axis=(1, 3))
    return np.round(np.clip(a, 0, 1) * 255).astype(np.uint8)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", default="")
    MAP = ap.parse_args(argv).map or default_pack()
    PACK = os.path.join(ROOT, "assets", "maps", MAP)
    CELLS = os.path.join(ROOT, "data", "maps", MAP, "geography", "cells.csv")
    OUT = os.path.join(map3d_dir(MAP), "bake")
    rules = load_rules()
    # a pier's deck height is the runtime's (Map3DLayerHouses seats a pier
    # this far over the sea): harbour keeps the ground under it lower
    rules["map3d_pier_deck_m"] = float(data_index.balance()["map3d_pier_deck_m"])
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
    # The padding onto whole regions (an even count each way, the pack
    # centred) fixes the world origin, which the rivers' water lines need.
    cols = -(-vw // REGION)
    cols += cols % 2
    rows = -(-vh // REGION)
    rows += rows % 2
    fw_pad, fh_pad = cols * REGION, rows * REGION
    ox_pad, oy_pad = (fw_pad - vw) // 2, (fh_pad - vh) // 2
    # world position of pack px (0,0), computed here ONCE and reused for the
    # houses below, the rivers' water lines, and world.json's own pack_origin
    # — a drift between those three would silently misplace every house with
    # no test catching it
    origin = ((-fw_pad / 2 + ox_pad) * VERTEX_M, (-fh_pad / 2 + oy_pad) * VERTEX_M)
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

    # The rivers' courses, source -> mouth, smoothed like the 2D map's and in
    # vertex units: the ridges fade out along them, and they are carved below.
    # A course ending inland (a tributary: the pack stops them short of the
    # river they feed) is carried on to the nearest point of another course
    # within river_join_m, found on the others' smoothed curves and appended
    # before its own smoothing, which keeps the last point: the two meet.
    steps = int(rules["river_smooth_steps"])
    with open(os.path.join(ROOT, "data", "maps", MAP, "geography", "rivers.csv")) as f:
        raws = []
        for r in sorted(csv.DictReader(f), key=lambda r: float(r["discharge"] or 0)):
            raw = [(x * k, y * k) for x, y in
                   (tuple(map(float, p.split())) for p in r["points"].split("|") if p.strip())]
            if len(raw) >= 2:
                raws.append((r, raw))
    with open(os.path.join(ROOT, "data", "maps", MAP, "political", "burgs.csv")) as f:
        towns = np.array([(float(b["x"]) * k, float(b["y"]) * k) for b in csv.DictReader(f)])

    def bend(course, n):
        if rules.get("river_meander_m", 0.0) <= 0.0:
            return course
        return meander(course, rules["river_meander_m"] / VERTEX_M, rules["river_meander_wave_m"] / VERTEX_M,
                       n, rules["river_meander_end_m"] / VERTEX_M, towns, rules["river_meander_town_m"] / VERTEX_M)
    # joins are found on the bent courses: a tributary ends ON its river
    smooth = [bend(smooth_open(raw, steps), n) for n, (_, raw) in enumerate(raws)]
    courses, joins, unjoined = [], {}, 0
    for n, (r, raw) in enumerate(raws):
        ex, ey = raw[-1]
        if cov[min(max(int(round(ey)), 0), vh - 1), min(max(int(round(ex)), 0), vw - 1)] >= 0.5:
            at = join_point((ex, ey), [c for m, c in enumerate(smooth) if m != n],
                            rules["river_join_m"] / VERTEX_M)
            if at is None:
                unjoined += 1
            else:
                joins[r["river_code"]] = float(np.hypot(at[0] - ex, at[1] - ey))
                raw = raw + [(float(at[0]), float(at[1]))]
        courses.append((r, bend(smooth_open(raw, steps), n)))

    # --- ridges -------------------------------------------------------------------
    ridge = np.zeros((vh, vw), dtype=np.float32)
    amp, norm = 1.0, 0.0
    for wave_m in relief_waves(rules):
        n = value_noise(rng, vw, vh, wave_m / VERTEX_M)
        ridge += amp * (1.0 - np.abs(2.0 * n - 1.0)) ** 2
        norm += amp
        amp *= rules["relief_ridge_gain"]
    ridge /= norm
    ridge -= ridge[land].mean()
    ridge *= river_fade([c for _, c in courses], vw, vh, rules["river_ridge_fade_m"] / VERTEX_M,
                        rules["river_head_m"] / VERTEX_M, rules["river_head_share"])
    coast_steps = int(rules["relief_ridge_coast_m"] / VERTEX_M)
    from_coast = distance_steps(~land, coast_steps) / coast_steps
    lift = np.clip((height - rules["relief_ridge_from_m"])
                   / (rules["relief_ridge_full_m"] - rules["relief_ridge_from_m"]), 0, 1)
    # the fringe (0 < ramp < 1) keeps its ramp through the water plane
    height = np.where(ramp >= 1.0, np.maximum(height + rules["relief_ridge_m"] * lift * from_coast * ridge * 2.0,
                                             SEA_Y + rules["shore_m"]), height)
    del ridge, lift
    height = terrace(height, ramp, land, from_coast, rules, vw, vh, [c for _, c in courses])
    # the landform carved by running water (spec 2026-10-13-landform-rework,
    # option A), before the rivers cut their own beds into it
    height = erode(height, land, rules)

    # --- rivers -------------------------------------------------------------------
    # Carved after the ridges and the shore (so a bed is measured from the
    # final ground) and before the slope (so the banks read as slope). Each
    # course, source -> mouth, is resampled every vertex, trimmed to the land
    # (river_span), and its bed falls every step to the sea. The LARGEST
    # rivers carve first: a tributary then reads the valley its river has
    # already cut and its bed falls into the confluence (carved first, it
    # measured the uncut ground and ended up to 110 m over its river).
    wet = np.zeros((vh, vw), dtype=np.float32)
    rivers_out = []
    gamma = taper_gamma()   # screens/map3d/balance.csv map_river_taper_gamma, the 2D rule
    floor = SEA_Y - rules["shore_m"] - rules["river_depth_m"]
    ox_m, oz_m = origin
    for r, course in reversed(courses):
        pts = resample_line(course, 1.0)   # vertex units, 20 m apart
        gi = np.clip(np.round(pts).astype(np.int64), 0, [vw - 1, vh - 1])
        span = river_span(cov[gi[:, 1], gi[:, 0]])
        if span is None or span[1] - span[0] < 2:
            continue
        pts, gi = pts[span[0]:span[1]], gi[span[0]:span[1]]
        c = cov[gi[:, 1], gi[:, 0]]
        ground = height[gi[:, 1], gi[:, 0]]
        # inland = past the shore's ramp (ramp 1), where land holds its height
        bed = river_bed(ground, rules["river_depth_m"], rules["river_min_drop_m"], floor,
                        restart=ramp[gi[:, 1], gi[:, 0]] >= 1.0)
        if c[-1] < 0.5 and rules.get("river_mouth_grade", 0.0) > 0.0:
            # a true mouth comes down to the sea on a gentle grade, cutting
            # its own valley through a cliff coast — it never falls off one
            # (visual review 2026-10-06: a white curtain into the sea)
            to_end = (len(bed) - 1 - np.arange(len(bed))) * VERTEX_M
            bed = np.minimum(bed, SEA_Y - rules["river_depth_m"] + rules["river_mouth_grade"] * to_end)
        w_mouth = float(np.clip(rules["river_k"] * np.sqrt(max(float(r["discharge"] or 0), 0.0)),
                                rules["river_min_w_m"], rules["river_max_w_m"]))
        widths = river_widths(len(pts), w_mouth, gamma, rules["river_source_w_m"])
        n_mouth = max(int(rules["river_mouth_m"] / VERTEX_M), 1)
        mouth = river_mouth(len(pts), n_mouth, bool(c[-1] < 0.5))
        widths = widths * (1.0 + rules.get("river_mouth_widen", 1.0) * mouth)
        # a port at the mouth keeps the river its quays were laid along
        e_hold = town_hold(pts, towns, rules.get("river_estuary_town_m", 0.0) / VERTEX_M)
        widths = widths * (1.0 + (estuary(len(pts), int(rules.get("river_estuary_m", 0.0) / VERTEX_M),
                                          bool(c[-1] < 0.5), rules.get("river_estuary_widen", 0.0),
                                          rules.get("river_estuary_power", 2.0),
                                          rules.get("river_estuary_wobble", 0.0),
                                          rules.get("river_estuary_wobble_m", 400.0) / VERTEX_M,
                                          len(rivers_out)) - 1.0) * e_hold)
        # open sea (cov 0) is never dug: the water line still reaches it
        cut = c > 0.0
        carve(height, wet, pts[cut], bed[cut], widths[cut] / VERTEX_M, rules)
        # the water never stands under the sea it runs to (river_over_sea_m
        # over it, as over the fringe and at the mouth), so the line keeps falling
        water = np.maximum(bed + rules["river_depth_m"] * rules["river_fill"],
                           SEA_Y + rules["river_over_sea_m"])
        if r["river_code"] in joins:   # the joined stretch: the last few samples
            water = join_water(water, len(pts) - int(np.ceil(joins[r["river_code"]])) - 1)
        keep = list(range(0, len(pts), 3)) + ([len(pts) - 1] if (len(pts) - 1) % 3 else [])
        rivers_out.append({"code": r["river_code"], "points": [
            [round(ox_m + pts[i, 0] * VERTEX_M, 1), round(oz_m + pts[i, 1] * VERTEX_M, 1),
             round(float(water[i]), 2), round(float(widths[i]), 1), round(float(mouth[i]), 3)]
            for i in keep]})
    wet *= land

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
    del smooth
    del wts, biome_tw

    gy, gx = np.gradient(height, VERTEX_M)
    slope = np.hypot(gx, gy)
    ls = np.sort(slope[land][::7])
    pct = lambda p: float(ls[min(int(p * len(ls)), len(ls) - 1)])
    t_rock = np.clip((slope - pct(SLOPE_ROCKY[0])) / max(pct(SLOPE_ROCKY[1]) - pct(SLOPE_ROCKY[0]), 1e-6), 0, 1)
    t_cliff = np.clip((slope - pct(SLOPE_CLIFF[0])) / max(pct(SLOPE_CLIFF[1]) - pct(SLOPE_CLIFF[0]), 1e-6), 0, 1)
    del gx, gy, slope
    # A carved river's banks are steep by construction, not rock: without
    # this the cliff texture drew a pixelated blue-grey scar where a river
    # meets the sea (owner review 2026-09-19, at the capital).
    # (widened to river_bank_rock_reach_m: the carve's walls stand beyond
    # the wet band itself)
    bank = np.clip(rules["river_bank_rock_hold"]
                   * box(wet, int(rules["river_bank_rock_reach_m"] / VERTEX_M)), 0, 1)
    # ...nor is a low coast where a carved mouth meets the shore ramp (the
    # band there is already 0: `wet` only counts on land)
    bank = np.maximum(bank, np.clip((rules["low_rock_free_m"] - (height - SEA_Y)) / 30.0, 0, 1))
    t_cliff *= 1.0 - bank
    t_rock *= 1.0 - bank
    del bank
    # scree and bare soil belong to the uplands (look route 2026-09-30): on a
    # lowland slope -- a valley side, a coastal bank -- they drew pale grey
    # blotches that read as mould on the grass
    up = np.clip((height - SEA_Y - rules["rock_from_m"]) / max(rules["rock_full_m"] - rules["rock_from_m"], 1.0), 0, 1)
    t_rock *= rules["rock_low_share"] + (1.0 - rules["rock_low_share"]) * up
    # the scree broken by tongues of grass (visual review 2026-10-06: an even
    # grey band below every scarp read as a pasted strip); its own stream
    if rules.get("rock_break", 0.0) > 0.0:
        rb = value_noise(np.random.default_rng(SEED + 51), vw, vh, rules["rock_break_wave_m"] / VERTEX_M) * 0.6 \
            + value_noise(np.random.default_rng(SEED + 52), vw, vh, rules["rock_break_wave_m"] * 0.35 / VERTEX_M) * 0.4
        # read through a warp: thresholded, a value noise traces its square
        # grid as straight edges (the critic: rectangles of rubble)
        brng = np.random.default_rng(SEED + 53)
        wv, wa = rules["rock_break_wave_m"] * 0.6 / VERTEX_M, rules["rock_break_wave_m"] * 0.3 / VERTEX_M
        bdx = (value_noise(brng, vw, vh, wv) * 2.0 - 1.0) * wa
        bdy = (value_noise(brng, vw, vh, wv) * 2.0 - 1.0) * wa
        for y0 in range(0, vh, 512):
            y1 = min(y0 + 512, vh)
            ys, xs = np.mgrid[y0:y1, 0:vw].astype(np.float32)
            t_rock[y0:y1] *= 1.0 - rules["rock_break"] * np.clip(
                (0.55 - sample_bilinear(rb, xs + bdx[y0:y1], ys + bdy[y0:y1])) / 0.3, 0, 1)
        del rb, bdx, bdy
    del up
    hn = np.clip(height / max(float(height.max()), 1.0), 0, 1)
    keep = 1.0 - 0.85 * t_rock
    for t in (GRASS, LEAVES, DIRT, SAND, FOREST):
        tw[..., t] *= keep
    tw[..., ROCKY] += 1.2 * t_rock * (1 - t_cliff)
    tw[..., SOIL] += 0.9 * t_rock * (1 - hn) * (1 - t_cliff)
    tw[..., CLIFF] += 2.5 * t_cliff * np.maximum(hn, 0.35)
    # The snow line (owner 2026-09-19): above snow_line_lo of the highest
    # ground snow comes in, full by snow_line_hi — on the 3D map's own ridges
    # as well as the 2D map's peak band — thinner on the steepest faces,
    # where rock shows through.
    # The line itself (look route 2026-09-30, owner: 山顶雪帽 read as pale plaster
    # with a ruled rim): broken by its own noise — its own stream, so nothing
    # sown after it moves — into tongues and patches, and thinned on the steep
    # rock, where snow does not lie, so ribs of crag show through the cap.
    snow_rng = np.random.default_rng(SEED + 13)
    snow_n = (value_noise(snow_rng, vw, vh, rules["snow_edge_wave_m"] / VERTEX_M) * 0.65
              + value_noise(snow_rng, vw, vh, rules["snow_edge_wave_m"] * 0.3 / VERTEX_M) * 0.35)
    hn_snow = hn + (snow_n - 0.5) * 2.0 * rules["snow_edge_noise"]
    # snow lies longer on the slopes turned from the sun: the north faces take
    # the line lower, so a cap runs down its shaded side instead of ruling an arc
    # (the pack's rows run south, so ground rising toward the south faces north)
    # (one-sided: a south face keeps the height's own line — lowering it bared
    # a scree tongue across the glacier)
    north = np.maximum(np.tanh(np.gradient(height, VERTEX_M, axis=0) / 0.3), 0.0)
    hn_snow += rules["snow_north_gain"] * north
    del north
    snow = np.clip((hn_snow - rules["snow_line_lo"]) / max(rules["snow_line_hi"] - rules["snow_line_lo"], 1e-6), 0, 1)
    # under the snow a band of scree and bare rock, not grass up to its rim —
    # a mountain's snow ends above a grey margin, not on a lawn
    band = np.clip((hn_snow - (rules["snow_line_lo"] - rules["snow_scree_band"]))
                   / max(rules["snow_scree_band"], 1e-6), 0, 1) * (1.0 - snow)
    tw[..., SCREE] += rules["snow_scree_weight"] * band
    # the high plateaus break into ridges and gullies below the snow (phase 2 B):
    # a band of height share ridge_lo..ridge_hi, frayed by the snow edge noise
    ridge = np.clip((hn_snow - rules["ridge_lo"]) / max(rules["ridge_hi"] - rules["ridge_lo"], 1e-6), 0, 1) \
        * (1.0 - snow) * (1.0 - t_cliff)
    tw[..., RIDGE] += rules["ridge_weight"] * ridge
    del ridge
    del snow_n, hn_snow, band
    tw[..., SNOW] += rules["snow_weight"] * snow * (1.0 - rules["snow_steep_cut"] * t_cliff) \
        * (1.0 - rules["snow_scree_cut"] * t_rock)
    del snow
    # The beach fades out by the share of land around a vertex (a box of
    # BEACH_M: a 4-neighbour step count cut it on a diamond staircase) and
    # under BEACH_MAX_M; the whole mask is then sampled along the grounds'
    # warp, so both its edges fray like theirs (the height fade alone drew a
    # straight line across a steep coast).
    inland = box(land.astype(np.float32), int(BEACH_M / VERTEX_M))
    flat = (np.clip((1.0 - inland) / rules["beach_fade_share"], 0, 1)
            * np.clip((BEACH_MAX_M - height) / rules["beach_fade_height_m"], 0, 1))
    del inland
    beach = np.empty_like(flat)
    for y0 in range(0, vh, 512):
        y1 = min(y0 + 512, vh)
        ys, xs = np.mgrid[y0:y1, 0:vw].astype(np.float32)
        beach[y0:y1] = sample_bilinear(flat, xs + dx[y0:y1], ys + dy[y0:y1])
    # The warp may carry it up to edge_warp_m: never onto a cliff, nor above
    # twice BEACH_MAX_M (that cap falls on the steep ground, where it hides).
    beach *= land * (1.0 - t_cliff) * np.clip((2.0 * BEACH_MAX_M - height) / rules["beach_fade_height_m"], 0, 1)
    # beaches come and go along the shore (visual review 2026-10-05: an even
    # sand rim outlined every coast): a slow noise of its own stream widens
    # some reaches and leaves others grass to the water
    if rules.get("beach_break", 0.0) > 0.0:
        bn = value_noise(np.random.default_rng(SEED + 23), vw, vh, rules["beach_break_wave_m"] / VERTEX_M)
        beach *= np.clip((bn - rules["beach_break"]) / 0.25, 0, 1.3)
        beach = np.clip(beach, 0, 1)
    del dx, dy, flat
    # The shore is dirt_floor (lighter, warmer and grainier than sand_03,
    # whose own tone the colour map cannot lighten) with sand as its second
    # texture at a share that varies on a short wave but stays under a half:
    # were the two to trade first place, the vertex's base would flip and
    # Terrain3D would draw 20 m blocks.
    grain = rules["beach_sand_share"] * value_noise(rng, vw, vh, rules["beach_grain_wave_m"] / VERTEX_M)
    tw[..., DIRT] += 2.0 * beach * (1.0 - grain)
    tw[..., SAND] += 2.0 * beach * grain
    del grain
    tint, fmap, house_rows, smap, emap, hmap = sow_patchwork(tw, rules, MAP, OUT, PACK, has_cell, cell_id, land, height, hn,
                               t_rock, beach, wet, k, vw, vh, pw, ph, origin)
    # read by Map3DView for the patched terrain shader (Map3DGroundTint):
    # FIELD_MAP_STEP vertices to a texel, from the pack's own corner
    Image.fromarray(fmap, "RGBA").save(os.path.join(OUT, "fields.png"))
    Image.fromarray(smap, "L").save(os.path.join(OUT, "settled.png"))
    Image.fromarray(emap, "L").save(os.path.join(OUT, "field_edges.png"))
    Image.fromarray(hmap, "RGBA").save(os.path.join(OUT, "hedge_lines.png"))
    print("bake_world: %.2f%% of the vertices within 10 m of a hedge line" % (
        100.0 * float((hedge_distance(hmap) < 10.0).mean())))
    del fmap, smap, emap, hmap
    del t_rock, t_cliff, keep, beach
    depth = np.clip(-height / 150.0, 0, 1)
    tw[~land] = 0.0
    tw[..., SAND] += np.where(land, 0.0, 1.0 - depth)
    tw[..., SOIL] += np.where(land, 0.0, depth)
    del depth, hn

    # the wet soil beside the water is dirt_floor (land only)
    tw[..., DIRT] += rules["river_wet_weight"] * wet
    tw = sharpen_weights(tw, rules)
    split_variants(tw, height, rules)

    # --- control: top two per vertex --------------------------------------------------
    control = np.zeros((vh, vw), dtype=np.uint32)
    for y0 in range(0, vh, 256):
        s = lead_variants(tw[y0:y0 + 256])
        order = np.argsort(-s, axis=2)
        b1, b2 = order[..., 0], order[..., 1]
        w1 = np.take_along_axis(s, b1[..., None], 2)[..., 0]
        w2 = np.take_along_axis(s, b2[..., None], 2)[..., 0]
        blend = blend_byte(w1, w2, rng.uniform(-rules["blend_dither"], rules["blend_dither"], w1.shape))
        # a faint overlay is cut (visual review 2026-10-06, perf): each one makes
        # Terrain3D sample a second texture at four vertices for a trace no
        # one sees — a fifth of the land blended, half of it under 8%
        blend = np.where(blend < int(round(255 * rules["blend_floor"])), 0, blend).astype(np.uint32)
        control[y0:y0 + 256] = (b1.astype(np.uint32) << 27) | (b2.astype(np.uint32) << 22) | (blend << 14)

    # --- colour map ----------------------------------------------------------------------
    mult_lin = np.zeros((NT, 3))
    for t, key in enumerate(TEXTURE_KEYS):
        a = np.asarray(Image.open(os.path.join(TEX, f"{key}_alb_ht.png")).convert("RGB").resize((64, 64)), dtype=np.float64) / 255.0
        mean_lin = srgb_to_lin(a).reshape(-1, 3).mean(0)
        if t in CROP_TEXTURES:
            mult_lin[t] = 1.0   # the crops wear their own tint (sow_patchwork)
            continue
        far = rules["far_color_sand"] if t == SAND else rules["far_color_snow"] if t == SNOW \
            else rules["far_color_cliff"] if t == CLIFF else FAR_COLOR[t]
        mult_lin[t] = np.clip(srgb_to_lin(hex_rgb(far)) / np.maximum(mean_lin, 1e-4), 0, 1)
    color_lin = np.zeros((vh, vw, 3), dtype=np.float32)
    wsum = np.maximum(tw.sum(axis=2), 1e-6)
    for t in range(NT):
        color_lin += (tw[..., t] / wsum)[..., None] * mult_lin[t].astype(np.float32)
    # Snow wears none of the country's drift (2026-09-19): the macro hue, the
    # manors' own shades and the fields turned the snow line mint-green.
    snow_share = (tw[..., SNOW] / wsum).astype(np.float32)
    del tw, wsum
    macro = value_noise(rng, vw, vh, MACRO_WAVE_M / VERTEX_M)
    hue = value_noise(rng, vw, vh, MACRO_WAVE_M * 0.7 / VERTEX_M)
    color_lin *= (1.0 - rules["macro_depth"] * macro)[..., None]
    color_lin[..., 0] *= 1.0 - rules["macro_hue_depth"] * hue
    color_lin[..., 2] *= 1.0 - rules["macro_hue_depth"] * (1.0 - hue)
    color_lin *= (1.0 - rules["river_wet_darken"] * wet)[..., None]
    # moisture (look route 2026-09-30, critic: one yellow-olive note from
    # coast to hill): the country by its rivers and its coast greener and
    # cooler, the dry high ground golden — a warm/cool split under the macro
    # drift. Reads no random stream, so nothing after it moves.
    river_near = np.clip(box(wet, int(rules["moist_river_m"] / VERTEX_M)) * rules["moist_river_gain"], 0, 1)
    coast_near = 1.0 - box(land.astype(np.float32), int(rules["moist_coast_m"] / VERTEX_M))
    moist = np.clip(river_near + coast_near * rules["moist_coast_gain"], 0, 1)
    dry = (1.0 - moist) * np.clip((height - SEA_Y - rules["dry_from_m"]) / max(rules["dry_full_m"] - rules["dry_from_m"], 1.0), 0, 1)
    color_lin[..., 0] *= 1.0 - rules["moist_green"] * moist
    color_lin[..., 2] *= 1.0 - 0.4 * rules["moist_green"] * moist
    color_lin[..., 1] *= 1.0 - 0.35 * rules["dry_gold"] * dry
    color_lin[..., 2] *= 1.0 - rules["dry_gold"] * dry
    del river_near, coast_near, moist, dry
    # the patchwork's fields, hedges, villages and each manor's own shade
    color_lin *= tint
    del tint
    color_lin += (mult_lin[SNOW].astype(np.float32) - color_lin) * snow_share[..., None]
    del snow_share
    del wet
    rgba = np.empty((vh, vw, 4), dtype=np.uint8)
    for y0 in range(0, vh, 512):
        rgba[y0:y0 + 512, :, :3] = np.round(lin_to_srgb(color_lin[y0:y0 + 512]) * 255).astype(np.uint8)
    rgba[..., 3] = 128  # neutral roughness
    del color_lin

    # --- pad onto whole regions, the pack centred (sizes above) ------------------------------
    fw, fh, ox, oy = fw_pad, fh_pad, ox_pad, oy_pad
    hp = np.full((fh, fw), -SEA_LEVEL * SEA_M_PER_UNIT, dtype=np.float32)
    hp[oy:oy + vh, ox:ox + vw] = height
    cp = np.full((fh, fw), (SOIL << 27) | (SOIL << 22), dtype=np.uint32)
    cp[oy:oy + vh, ox:ox + vw] = control
    colp = np.full((fh, fw, 4), 255, dtype=np.uint8)
    colp[..., 3] = 128
    colp[oy:oy + vh, ox:ox + vw] = rgba
    hp.tofile(os.path.join(OUT, "height.r32"))
    # the WAR ROOM reads the heights directly (WarBake): the pack's own vertices
    # as half floats (~1 m at these heights, its contours are 100 m) — the
    # padded float32 grid is 128 MB, past what a git host takes in one file
    height.astype(np.float16).tofile(os.path.join(OUT, "height_war.r16"))
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
        "pack_origin": list(origin),
        "sea_y": SEA_Y,
        "height_range": [float(height.min()), float(height.max())],
        "slope_percentiles": [pct(SLOPE_ROCKY[0]), pct(SLOPE_ROCKY[1]), pct(SLOPE_CLIFF[1])],
        "far_multipliers_lin": mult_lin.round(3).tolist(),
    }
    json.dump(world, open(os.path.join(OUT, "world.json"), "w"), indent=1)
    # each river's water line, source -> mouth, in world metres (the frame of
    # pack_origin): [x, z, water_y, width_m, mouth 0..1]; build_terrain.gd
    # copies it beside the scene for the water mesh
    with open(os.path.join(OUT, "rivers.json"), "w") as f:
        json.dump({"rivers": rivers_out}, f)
    with open(os.path.join(OUT, "houses.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, ["burg_code", "rank", "x_m", "z_m", "yaw_deg", "type", "scale", "height_scale",
                              "stretch", "wall", "roof"])
        w.writeheader()
        for r in sorted(house_rows, key=lambda r: (r["burg_code"], r["rank"])):
            w.writerow(r)
    print("bake_world: %d houses over %d settlements" % (
        len(house_rows), len({r["burg_code"] for r in house_rows})))
    summary = {k: v for k, v in world.items() if k != "far_multipliers_lin"}
    summary["rivers"] = len(rivers_out)
    summary["rivers_joined"] = len(joins)
    summary["rivers_left_short"] = unjoined
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
