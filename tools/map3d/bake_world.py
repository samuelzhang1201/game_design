"""Bake a map pack into Terrain3D import maps at campaign scale
(owner 2026-09-18: 50 m per pack px, a 128 x 46 km world, vertex every 20 m).

Writes <map3d_dir>/bake/ (data/maps.csv map3d_dir, default assets/map3d/<map>):
  height.r32    float32 metres, row-major, padded onto whole regions
  control.r32   float32 carrying Terrain3D control bits (base/overlay/blend)
  color.rgba8   Terrain3D colour map: sRGB multiplier on the ground + roughness
  world.json    sizes, vertex spacing, world origin of pack px (0,0)
  rivers.json   each river's water line, source -> mouth, in world metres
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
from packs import default_pack, map3d_dir  # noqa: E402

TEX = os.path.join(ROOT, "assets", "map3d", "textures")
RULES_PATH = os.path.join(ROOT, "data", "map3d_bake.csv")
SEED = 954159497         # a look, never simulation: the same for every pack

M_PER_PX = 50.0          # world metres per pack px
VERTEX_M = 20.0          # Terrain3D vertex_spacing
REGION = 2048            # Terrain3D region_size (vertices)
def _balance(key):
    """A balance.csv value — the engine's Elevation reads the same row."""
    with open(os.path.join(ROOT, "data", "balance.csv"), newline="") as f:
        for row in csv.DictReader(f):
            if row["key"] == key:
                return float(row["value"])
    raise KeyError(key)


SEA_LEVEL = _balance("elevation_sea_level")        # Azgaar height of the waterline
LAND_M_PER_UNIT = _balance("elevation_m_per_unit")  # ~2400 m for the highest cells
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
CLIFF, GRASS, LEAVES, DIRT, ROCKY, SOIL, SAND, FOREST, SNOW = range(9)
NT = 9
TEXTURE_KEYS = ["cliff", "leafy_grass", "dry_decay_leaves", "dirt_floor", "rocky_trail",
                "excavated_soil_wall", "sand_03", "leafy_grass",
                # the snow line (owner 2026-09-19): Poly Haven snow_02 since the
                # same day (snow_field_aerial read blue-grey and blotchy)
                "snow_02"]
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
SLOPE_ROCKY = (0.82, 0.93)   # land slope percentiles
SLOPE_CLIFF = (0.93, 0.99)

# COLOUR MAP: what each texture should read as from far away (sRGB). Terrain3D
# multiplies the ground by the map, so a target is reached by the ratio to the
# texture's own mean colour, in linear light, and can only darken.
FAR_COLOR = {
    CLIFF: "#7E7B77", GRASS: "#6F7A40", LEAVES: "#4E4A2C", DIRT: "#9A7A55",
    ROCKY: "#7C7264", SOIL: "#5E4A30", FOREST: "#3A5026",
}  # SAND's and SNOW's are data/map3d_bake.csv far_color_sand / far_color_snow
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
    """data/map3d_bake.csv as {key: float}; a value that is not a number
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
    """balance.csv map_river_taper_gamma: the 2D river's taper, shared."""
    with open(os.path.join(ROOT, "data", "balance.csv")) as f:
        for r in csv.DictReader(f):
            if r["key"] == "map_river_taper_gamma":
                return float(r["value"])
    return 1.4


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


def river_fade(courses, vw, vh, reach):
    """0 on every course (vertex-unit polylines), easing up to 1 at `reach`
    vertices (4-neighbour steps, smoothstep): the ridges are multiplied by
    it, so no ridge is thrown across a river's valley for the carve to cut a
    gorge through (the 2D relief detail holds itself down near rivers too,
    docs/superpowers/specs/2026-09-17-relief-detail-design.md)."""
    img = Image.new("L", (vw, vh), 0)
    draw = ImageDraw.Draw(img)
    for c in courses:
        draw.line([(float(x), float(y)) for x, y in c], fill=255, width=1)
    t = distance_steps(np.asarray(img) > 0, int(reach)) / float(reach)
    return (t * t * (3.0 - 2.0 * t)).astype(np.float32)


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
    `wet` takes the band beside the water (0..1)."""
    H, W = height.shape
    slope_v = rules["river_bank_slope"] * VERTEX_M      # metres per vertex
    bank_max_v = rules["river_bank_max_m"] / VERTEX_M
    wet_v = rules["river_wet_m"] / VERTEX_M
    # every centre's ground read BEFORE any stamp: each sample lies inside
    # the last one's water, and read after it, the depth is one step's drop
    # and the valley collapses to a wall a vertex wide
    ci = np.clip(np.round(np.asarray(pts)).astype(np.int64), 0, [W - 1, H - 1]) if len(pts) else None
    grounds = height[ci[:, 1], ci[:, 0]].copy() if len(pts) else []
    for (x, y), b, w, g in zip(pts, bed, widths_v, grounds):
        xi, yi = int(round(x)), int(round(y))
        ease = min(max(g - b, 0.0) / slope_v + 1.0, bank_max_v)
        r = int(np.ceil(w * 0.5 + max(ease, wet_v))) + 1
        x0, x1 = max(xi - r, 0), min(xi + r + 1, W)
        y0, y1 = max(yi - r, 0), min(yi + r + 1, H)
        if x0 >= x1 or y0 >= y1:
            continue
        yy, xx = np.mgrid[y0:y1, x0:x1]
        s = np.maximum(np.hypot(xx - x, yy - y) - w * 0.5, 0.0)   # out from the water's edge
        sub = height[y0:y1, x0:x1]
        eased = sub - np.maximum(sub - b, 0.0) * np.clip(1.0 - s / ease, 0.0, 1.0)
        np.minimum(sub, np.maximum(b + s * slope_v, eased), out=sub)
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


def field_cells(xs, ys, cell_v, stretch, angle):
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
    key = np.where(far & (hash01(key, 11) < 0.5), key + 1, key)
    du = np.minimum(fu, 1.0 - fu) * ls
    dv = np.minimum(v - row, 1.0 - (v - row)) * ws
    return key, np.minimum(du, dv)


def load_fields(path, texture_keys):
    """data/map3d_fields.csv as {focus: {"reach": m, "crops": [(share, tex, tint)]}};
    a crop's texture by its bake key (the first layer of that name)."""
    out = {}
    with open(path) as f:
        for r in csv.DictReader(f):
            e = out.setdefault(r["focus"], {"reach": 0.0, "crops": []})
            e["reach"] = max(e["reach"], float(r["reach_m"]))
            e["crops"].append((float(r["share"]), texture_keys.index(r["texture"]),
                               srgb_to_lin(hex_rgb(r["tint"]))))
    return out


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


def footprint_radius_m(population, rules):
    """A settlement's built ground: footprint_m_per_sqrt_pop x sqrt(people),
    within footprint_min_m..footprint_max_m."""
    return float(np.clip(rules["footprint_m_per_sqrt_pop"] * np.sqrt(max(population, 0.0)),
                         rules["footprint_min_m"], rules["footprint_max_m"]))


def sow_patchwork(tw, rules, MAP, OUT, PACK, has_cell, cell_id, land, height, hn, t_rock,
                  beach, k, vw, vh, pw, ph):
    """Village footprints, the fields round them and each manor's own shade
    (owner 2026-09-19). Adds the fields' and footprints' grounds to `tw` in
    place and returns the colour map's multiplier per vertex (vh, vw, 3, in
    linear light). Its own random stream, so the rest of the look is
    unchanged."""
    prng = np.random.default_rng(SEED + 1)
    fields = load_fields(os.path.join(ROOT, "data", "map3d_fields.csv"), TEXTURE_KEYS)
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
    crop_tex_of = [np.array([c[1] for c in fields[f]["crops"]]) for f in focus_keys]
    crop_tint_of = [np.array([c[2] for c in fields[f]["crops"]], dtype=np.float32) for f in focus_keys]
    # distance to the nearest settlement: the pack's own bake, a unit per pack px
    sd = np.asarray(Image.open(os.path.join(PACK, "world_settlement_distance.png")).convert("L"),
                    dtype=np.float32) * M_PER_PX
    settle_m = resize(sd, vw, vh)
    del sd
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
    foot = np.zeros((vh, vw), dtype=np.float32)
    with open(os.path.join(ROOT, "data", "maps", MAP, "political", "burgs.csv")) as f:
        for b in csv.DictReader(f):
            cx, cy = float(b["x"]) * k, float(b["y"]) * k
            r = footprint_radius_m(float(b["population"] or 0), rules) / VERTEX_M
            reach = r * (1.0 + rules["footprint_edge_noise"]) + 2
            x0, x1 = max(int(cx - reach), 0), min(int(cx + reach) + 1, vw)
            y0, y1 = max(int(cy - reach), 0), min(int(cy + reach) + 1, vh)
            if x0 >= x1 or y0 >= y1:
                continue
            yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
            d = np.hypot(xx - cx, yy - cy) / r
            edge = 1.0 + rules["footprint_edge_noise"] * (2.0 * fray_n[y0:y1, x0:x1] - 1.0)
            # the built ground thins outward over footprint_fade of its
            # radius: no disc, no rim (taste: nothing ends on a hard cut)
            mf = np.clip((edge - d) / rules["footprint_fade"], 0, 1) ** 1.5 * land[y0:y1, x0:x1]
            foot[y0:y1, x0:x1] = np.maximum(foot[y0:y1, x0:x1], mf)
    del fray_n

    tint = np.ones((vh, vw, 3), dtype=np.float32)
    # the field-only part of the tint, and each estate's strip direction
    # (0..1 of a half turn): the terrain shader's field map (furrows up
    # close, the crops' colour eased back far out)
    ftint = np.ones((vh, vw, 3), dtype=np.float16)
    fangle = np.zeros((vh, vw), dtype=np.float16)
    farm = np.zeros((vh, vw), dtype=np.float32)
    crop = np.zeros((vh, vw), dtype=np.int8)
    cell_v = rules["field_cell_m"] / VERTEX_M
    hedge_v = rules["hedge_m"] / VERTEX_M
    for y0 in range(0, vh, 256):
        y1 = min(y0 + 256, vh)
        ys, xs = np.mgrid[y0:y1, 0:vw].astype(np.float64)
        pxi = np.clip((xs / k).astype(np.int64), 0, pw - 1)
        pyi = np.clip((ys / k).astype(np.int64), 0, ph - 1)
        cid = np.where(has_cell[pyi, pxi], cell_id[pyi, pxi], -1)
        cz = np.maximum(cid, 0)
        fi = cell_focus[cz]
        reach = reach_of[fi]
        # farmland: within reach of a settlement, its edge frayed, on land that
        # is neither steep, snowed, shore nor built on
        r_eff = reach * (1.0 + rules["field_edge_noise"] * (2.0 * edge_n[y0:y1] - 1.0))
        near = np.clip((r_eff - settle_m[y0:y1]) / (0.25 * reach), 0, 1)
        # fields thin outward (critic round 2: an even carpet read as
        # scattered): near the village nearly every field is sown, toward
        # the reach fewer, the rest left to the ground under them — decided
        # per field below, once its id is known
        closeness = np.clip(1.0 - settle_m[y0:y1] / np.maximum(r_eff, 1.0), 0, 1)
        m = (near * (land[y0:y1] & (cid >= 0))
             * np.clip(1.0 - t_rock[y0:y1] / rules["field_slope_max"], 0, 1)
             * (1.0 - snow[y0:y1]) * (1.0 - np.clip(2.0 * beach[y0:y1], 0, 1))
             * (1.0 - foot[y0:y1]))
        # each manor its own field layout and orientation: a field never
        # spans two manors, and the strips turn from estate to estate
        fid, edge_d = field_cells(xs + warp_x[y0:y1], ys + warp_y[y0:y1], cell_v,
                                  rules["field_stretch"], hash01(cz, 3) * np.pi)
        hf = hash01(fid ^ (cz.astype(np.int64) << 40), 4)
        sown = hash01(fid ^ (cz.astype(np.int64) << 40), 8) < closeness ** rules["field_thin_power"] * rules["field_thin_gain"]
        m = m * sown
        tex = np.zeros(m.shape, dtype=np.int8)
        tt = np.ones(m.shape + (3,), dtype=np.float32)
        for f in range(len(focus_keys)):
            sel = fi == f
            if sel.any():
                ci = pick_crop(hf[sel], fields[focus_keys[f]]["crops"])
                tex[sel] = crop_tex_of[f][ci]
                tt[sel] = crop_tint_of[f][ci]
        hedge = 1.0 - rules["hedge_depth"] * np.clip(1.0 - edge_d / hedge_v, 0, 1) ** 2
        # each field its own shade, and a fine grain inside it (critic: one
        # flat colour per field read as a sticker up close)
        own = 1.0 + rules["field_shade"] * (2.0 * hash01(fid ^ (cz.astype(np.int64) << 40), 7) - 1.0)
        grain = 1.0 + rules["field_grain"] * (2.0 * grain_n[y0:y1] - 1.0)
        tt *= (hedge * own * grain)[..., None].astype(np.float32)
        # The crop gives way to the natural ground over the last
        # field_edge_soft_m before its edge: Terrain3D switches a vertex's
        # texture whole, so two crops meeting head on drew a 20 m staircase;
        # through the ground between them the control map blends.
        soft = np.clip(edge_d / (rules["field_edge_soft_m"] / VERTEX_M), 0, 1)
        farm[y0:y1] = m * soft
        crop[y0:y1] = tex
        tint[y0:y1] = 1.0 + (tt - 1.0) * m[..., None]
        ftint[y0:y1] = tint[y0:y1]
        fangle[y0:y1] = hash01(cz, 3)
        # each manor's own shade: a patchwork even where nothing is sown
        jv = (2.0 * hash01(cz, 5) - 1.0) * rules["manor_jitter_value"] * (cid >= 0)
        jh = (2.0 * hash01(cz, 6) - 1.0) * rules["manor_jitter_hue"] * (cid >= 0)
        tint[y0:y1] *= (1.0 + jv)[..., None].astype(np.float32)
        tint[y0:y1, :, 0] *= (1.0 + jh).astype(np.float32)
        tint[y0:y1, :, 2] *= (1.0 - jh).astype(np.float32)
    del settle_m, edge_n, snow, warp_x, warp_y, grain_n

    # the grounds: a field's crop over what grew there, the footprint's
    # trodden earth over both
    tw *= (1.0 - 0.85 * farm)[..., None]
    for t in range(NT):
        tw[..., t] += rules["field_strength"] * farm * (crop == t)
    tw *= (1.0 - 0.9 * foot)[..., None]
    tw[..., DIRT] += 2.0 * foot
    built = srgb_to_lin(hex_rgb(rules["footprint_tint"])).astype(np.float32)
    blocks = (1.0 - rules["footprint_block_depth"] * block_n)[..., None] * built
    tint = tint * (1.0 - foot[..., None]) + blocks * foot[..., None]
    print("bake_world: patchwork %.1f%% of the land sown, %.2f%% built" % (
        100.0 * float(farm[land].mean()), 100.0 * float(foot[land].mean())))
    return tint, field_map(ftint, fangle)


def main(argv=None):
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", default="")
    MAP = ap.parse_args(argv).map or default_pack()
    PACK = os.path.join(ROOT, "assets", "maps", MAP)
    CELLS = os.path.join(ROOT, "data", "maps", MAP, "geography", "cells.csv")
    OUT = os.path.join(map3d_dir(MAP), "bake")
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
    # The padding onto whole regions (an even count each way, the pack
    # centred) fixes the world origin, which the rivers' water lines need.
    cols = -(-vw // REGION)
    cols += cols % 2
    rows = -(-vh // REGION)
    rows += rows % 2
    fw_pad, fh_pad = cols * REGION, rows * REGION
    ox_pad, oy_pad = (fw_pad - vw) // 2, (fh_pad - vh) // 2
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
    smooth = [smooth_open(raw, steps) for _, raw in raws]
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
        courses.append((r, smooth_open(raw, steps)))

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
    ridge *= river_fade([c for _, c in courses], vw, vh, rules["river_ridge_fade_m"] / VERTEX_M)
    coast_steps = int(RIDGE_COAST_M / VERTEX_M)
    from_coast = distance_steps(~land, coast_steps) / coast_steps
    lift = np.clip((height - RIDGE_FROM_M) / (RIDGE_FULL_M - RIDGE_FROM_M), 0, 1)
    # the fringe (0 < ramp < 1) keeps its ramp through the water plane
    height = np.where(ramp >= 1.0, np.maximum(height + RIDGE_M * lift * from_coast * ridge * 2.0,
                                             SEA_Y + rules["shore_m"]), height)
    del ridge, lift

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
    gamma = taper_gamma()   # balance.csv map_river_taper_gamma, the 2D rule
    floor = SEA_Y - rules["shore_m"] - rules["river_depth_m"]
    ox_m, oz_m = (-fw_pad / 2 + ox_pad) * VERTEX_M, (-fh_pad / 2 + oy_pad) * VERTEX_M
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
        w_mouth = float(np.clip(rules["river_k"] * np.sqrt(max(float(r["discharge"] or 0), 0.0)),
                                rules["river_min_w_m"], rules["river_max_w_m"]))
        widths = river_widths(len(pts), w_mouth, gamma, rules["river_source_w_m"])
        n_mouth = max(int(rules["river_mouth_m"] / VERTEX_M), 1)
        mouth = river_mouth(len(pts), n_mouth, bool(c[-1] < 0.5))
        widths = widths * (1.0 + mouth)
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
    snow = np.clip((hn - rules["snow_line_lo"]) / max(rules["snow_line_hi"] - rules["snow_line_lo"], 1e-6), 0, 1)
    tw[..., SNOW] += rules["snow_weight"] * snow * (1.0 - 0.6 * t_cliff)
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
    tint, fmap = sow_patchwork(tw, rules, MAP, OUT, PACK, has_cell, cell_id, land, height, hn,
                               t_rock, beach, k, vw, vh, pw, ph)
    # read by Map3DView for the patched terrain shader (Map3DGroundTint):
    # FIELD_MAP_STEP vertices to a texel, from the pack's own corner
    Image.fromarray(fmap, "RGBA").save(os.path.join(OUT, "fields.png"))
    del fmap
    del t_rock, t_cliff, keep, beach
    depth = np.clip(-height / 150.0, 0, 1)
    tw[~land] = 0.0
    tw[..., SAND] += np.where(land, 0.0, 1.0 - depth)
    tw[..., SOIL] += np.where(land, 0.0, depth)
    del depth, hn

    # the wet soil beside the water is dirt_floor (land only)
    tw[..., DIRT] += rules["river_wet_weight"] * wet
    tw = sharpen_weights(tw, rules)

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
        far = rules["far_color_sand"] if t == SAND else rules["far_color_snow"] if t == SNOW else FAR_COLOR[t]
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
    # each river's water line, source -> mouth, in world metres (the frame of
    # pack_origin): [x, z, water_y, width_m, mouth 0..1]; build_terrain.gd
    # copies it beside the scene for the water mesh
    with open(os.path.join(OUT, "rivers.json"), "w") as f:
        json.dump({"rivers": rivers_out}, f)
    summary = {k: v for k, v in world.items() if k != "far_multipliers_lin"}
    summary["rivers"] = len(rivers_out)
    summary["rivers_joined"] = len(joins)
    summary["rivers_left_short"] = unjoined
    print(json.dumps(summary))


if __name__ == "__main__":
    main()
