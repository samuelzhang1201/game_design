"""House placement for the 3D map's settlements (spec 2026-09-20 §1, redesign
2026-09-20: lanes, not a jittered grid — owner's ruling below).

Pure: given a burg, the tuning rules, the type table and the bake's own
vertex-resolution masks, it returns the houses of one cluster with their
offsets from the burg's centre in metres. It never touches the world frame,
never reads a file and never draws — bake_world.py adds the world origin and
writes the CSV.

"never in the sea" is structural here: a candidate is tested against the very
land mask the footprint was multiplied by, so nothing downstream can place a
house the footprint did not claim.

The owner, verbatim, on the first cut (an evenly-spaced jittered grid with a
radial density falloff — even specks, no negative space): "你不需要实时严格的计
算房屋数量，你只需要根据定居点种类不同生成这几种种类的定居点房屋密度即可！房屋的
位置也可以生成在不同的位置，但不需要每次都重新计算。房屋的摆放要凸显中世纪那种风
格，紧凑杂乱，形成巷子，高低层次不齐" — the count is a target per settlement
GROUP now, not derived from population, and the layout GROWS A LANE NETWORK
out from the centre first, then packs house rectangles along its frontage,
then fills whatever block remains between lanes: compact, messy, with real
negative space (the lanes themselves) and uneven roofs (`height_scale`).
"""
import hashlib
import math
import statistics

import numpy as np

VERTEX_M = 20.0          # Terrain3D vertex_spacing, as bake_world.py
GROUP_ORDER = ["village", "fort", "town", "city", "capital"]


def _seed(code):
    """A stable 64-bit seed per burg: the same village every re-bake, and a
    different one per burg. Python's hash() is salted per process, so it
    cannot be used."""
    return int.from_bytes(hashlib.blake2b(code.encode("utf-8"), digest_size=8).digest(), "big")


def house_count(burg, rules):
    """The TARGET number of houses a settlement's cluster shows — fixed by
    its group (village/fort/town/city/capital), never by its population: two
    burgs of the same group get the same target however far apart their
    populations sit. An unknown group falls back to the village count."""
    group = str(burg.get("group", "village"))
    return int(rules.get("house_count_%s" % group, rules["house_count_village"]))


def house_m2_each(burg, rules):
    """The ground a house is given, in square metres — PER GROUP
    (`house_m2_each_<group>`), the village value the fallback (owner
    2026-09-21, density v4). One shared density could not serve both ends:
    a settlement at full fill has exactly this much ground per house BY
    CONSTRUCTION, so the value a small awkward village site needs to fill
    at all (loose) is the very value that would leave a capital — which
    reaches full fill at any value — sitting sparse. Per group, a capital
    is packed tight and a village stays loose enough to fill its site."""
    group = str(burg.get("group", "village"))
    return float(rules.get("house_m2_each_%s" % group, rules["house_m2_each_village"]))


def house_radius_m(burg, rules):
    """The cluster's own radius: derived straight from the group's fixed
    house COUNT and that group's per-house density — never from population,
    and never through the footprint. r = sqrt(count * m2_each / pi), the
    radius of a circle whose area holds `count` houses at that density.

    v1/v2 had this backwards: the house count was already fixed per GROUP
    (the owner's ruling) while the cluster's radius came from a
    population-driven footprint formula via house_radius_ratio. The two are
    unrelated, so the density — count / (ratio * r_foot)^2 — was whatever
    they happened to produce, and shrinking the footprint simply forced the
    ratio up to keep the houses fitting, cancelling the shrink."""
    return math.sqrt(max(house_count(burg, rules), 0) * house_m2_each(burg, rules) / math.pi)


def footprint_radius_m(burg, rules):
    """The built ground's radius — the same formula bake_world.py uses; kept
    here so this module stands alone, and asserted equal by the bake's test.
    The house cluster grown out by a buffer ring, `house_built_share` the
    cluster's own share of it: the footprint is DOWNSTREAM of the houses
    now, not the other way around."""
    return house_radius_m(burg, rules) / rules["house_built_share"]


def _square_reach(types, group, rules, code=""):
    """(half along, half across) of a landmark's open square out to the far
    kerb of the lane round it — the ground no house of this settlement may
    take — or None when the group has no landmark."""
    lm = _pick_landmark(types, group, code)
    if lm is None:
        return None
    hx, hz = half_extents(types[lm])
    e = float(rules["house_plaza_m"]) + 2.0 * float(rules["lane_half_width_m"])
    return hx + e, hz + e


def cluster_radius_m(burg, rules, types):
    """house_radius_m grown by the landmark's open square (house_plaza_m,
    owner 2026-09-25): the houses keep the ground their group's density gives
    them, and the square is added to it rather than taken out of it."""
    r = house_radius_m(burg, rules)
    reach = _square_reach(types, str(burg.get("group", "village")), rules, str(burg.get("burg_code", "")))
    if reach is None:
        return r
    return math.sqrt(r * r + 4.0 * reach[0] * reach[1] / math.pi)


def square_inner_m(burg, rules, types):
    """How near its landmark's centre the first house can stand: the square's
    shorter reach (0 with no landmark). The ring quotas start here."""
    reach = _square_reach(types, str(burg.get("group", "village")), rules, str(burg.get("burg_code", "")))
    return 0.0 if reach is None else min(reach)


def _group_allows(group, min_group):
    try:
        return GROUP_ORDER.index(group) >= GROUP_ORDER.index(min_group)
    except ValueError:
        return min_group == "village"


def landmark_height_scale(row, rules):
    """A landmark stands house_height_max tall — the tallest thing in its
    settlement — unless its row names its own `landmark_height_scale`: a
    Tripo palace is modelled in true proportion, and stretched 1.5x upright
    its towers read thin and false (owner 2026-09-30: 宫殿…太失真了)."""
    own = str(row.get("landmark_height_scale", "") or "").strip()
    return float(own) if own else float(rules["house_height_max"])


def _pick(rng, types, role, group, t=0.0, rules=None):
    """One type of this role by weight. `t` is how far out the house stands
    (0 the core, 1 the rim of the cluster): past `house_rim_frac` a type's
    `rim_mul` scales its weight (cottages crowd the edge, townhouses thin
    out); inside it a type the group does NOT allow may stray in by its
    `stray_weight` (a workshop in a village's core), owner 2026-10-10: more
    house variants. A table without those columns draws as it always did."""
    rim = t >= float((rules or {}).get("house_rim_frac", 1.0))
    keys, ws = [], []
    for k in sorted(types):
        r = types[k]
        if r["role"] != role:
            continue
        if _group_allows(group, r["min_group"]):
            w = float(r["weight"]) * (float(r.get("rim_mul") or 1.0) if rim else 1.0)
        elif not rim and role == "house":
            w = float(r.get("stray_weight") or 0.0)
        else:
            w = 0.0
        if w > 0.0:
            keys.append(k)
            ws.append(w)
    if not keys:
        return None
    w = np.array(ws, dtype=np.float64)
    return keys[int(rng.choice(len(keys), p=w / w.sum()))]


def palette_of(code, salt, palettes):
    """Which of `palettes` colour palettes a settlement wears: a stable hash
    of its code, `salt` apart for the wall and the roof."""
    return _seed("%s|%s" % (code, salt)) % max(int(palettes), 1)


def assign_variants(rows, code, rules, types):
    """Give every row of one settlement its `wall` and `roof` tint index
    (owner 2026-10-10: the houses repeat too much): the settlement wears one
    wall palette and one roof palette (palette_of), each house a colour of
    those, and no house takes the (type, wall, roof) of another within
    `house_variant_clear_m` while another pair of the palette is free.
    Deterministic from the burg's code and the rows' order. Positions are in
    metres in any one frame."""
    pw, sw = int(rules.get("house_wall_palettes", 1)), int(rules.get("house_wall_palette_size", 1))
    pr, sr = int(rules.get("house_roof_palettes", 1)), int(rules.get("house_roof_palette_size", 1))
    if pw * sw <= 1 and pr * sr <= 1:
        return rows
    clear = float(rules.get("house_variant_clear_m", 0.0))
    wall0 = palette_of(code, "wall", pw) * sw
    roof0 = palette_of(code, "roof", pr) * sr
    rng = np.random.default_rng(_seed(code + "|variants"))
    pairs = [(wall0 + a, roof0 + b) for a in range(sw) for b in range(sr)]
    placed = []   # (x, z, type, wall, roof)
    for r in rows:
        if types.get(r["type"], {}).get("role") not in ("house", "barn", "landmark"):
            continue
        near = {(t, w, f) for x, z, t, w, f in placed
                if math.hypot(x - r["x_m"], z - r["z_m"]) < clear}
        free = [p for p in pairs if (r["type"], p[0], p[1]) not in near]
        w, f = (free or pairs)[int(rng.integers(len(free or pairs)))]
        r["wall"], r["roof"] = w, f
        placed.append((r["x_m"], r["z_m"], r["type"], w, f))
    return rows


def identical_neighbours(rows, clear):
    """Pairs of rows of one settlement with the same type, wall and roof
    within `clear` metres (what assign_variants avoids)."""
    out = []
    for i, a in enumerate(rows):
        for b in rows[i + 1:]:
            if a.get("wall") is None or a["type"] != b["type"]:
                continue
            if (a["wall"], a["roof"]) == (b["wall"], b["roof"]) \
                    and math.hypot(a["x_m"] - b["x_m"], a["z_m"] - b["z_m"]) < clear:
                out.append((a, b))
    return out


def _pick_landmark(types, group, code=""):
    """The building at a settlement's centre: a landmark of the HIGHEST rank
    its group allows, never a weighted draw across ranks (owner 2026-09-22,
    要改成按等级固定).

    Since density v5 compressed the per-group house counts to 100/80/50/30/20,
    the centrepiece is the only thing left that tells a capital from a town —
    and a weighted draw among every allowed landmark undid exactly that:
    measured over the pack, 4 of the 7 capitals drew a plain church, which is
    what a TOWN shows, and one drew a chapel, which is what a VILLAGE shows.
    Ranking by `min_group` gives capital → palace, city → church tower,
    town and fort → church, village → chapel.

    Several landmarks of that one rank are VARIANTS (owner 2026-09-30: the
    church and the palace keep every Tripo version, 全部用作variant … 增加多样性):
    the settlement's `code` picks one by weight through its stable _seed, so
    the same burg shows the same building every bake. Without a code, weight
    then name decide, as before."""
    keys = [t for t, r in types.items()
            if r["role"] == "landmark" and _group_allows(group, r["min_group"])]
    if not keys:
        return None

    def rank(t):
        g = types[t]["min_group"]
        return GROUP_ORDER.index(g) if g in GROUP_ORDER else -1
    top = max(rank(t) for t in keys)
    same = sorted((t for t in keys if rank(t) == top), key=lambda t: (float(types[t]["weight"]), t))
    if not code or len(same) == 1:
        return same[-1]
    w = np.array([float(types[t]["weight"]) for t in same], dtype=np.float64)
    u = (_seed("landmark:" + code) % 1_000_003) / 1_000_003.0
    return same[int(np.searchsorted(np.cumsum(w / w.sum()), u, side="right").clip(0, len(same) - 1))]


def _slope(height, vx, vy, vw, vh):
    """The ground's gradient (rise over run) at a vertex, from the bake's own
    heightmap — the field the rivers are already carved into."""
    x0, x1 = max(int(vx) - 1, 0), min(int(vx) + 1, vw - 1)
    y0, y1 = max(int(vy) - 1, 0), min(int(vy) + 1, vh - 1)
    dx = (float(height[int(vy), x1]) - float(height[int(vy), x0])) / max((x1 - x0) * VERTEX_M, 1e-6)
    dy = (float(height[y1, int(vx)]) - float(height[y0, int(vx)])) / max((y1 - y0) * VERTEX_M, 1e-6)
    return math.hypot(dx, dy)


def _height_at(height, vx, vy, vw, vh):
    """The heightmap bilinear at a fractional vertex position, clamped to the grid."""
    vx = min(max(vx, 0.0), vw - 1.001)
    vy = min(max(vy, 0.0), vh - 1.001)
    x0, y0 = int(vx), int(vy)
    ax, ay = vx - x0, vy - y0
    return (float(height[y0, x0]) * (1 - ax) * (1 - ay) + float(height[y0, x0 + 1]) * ax * (1 - ay)
            + float(height[y0 + 1, x0]) * (1 - ax) * ay + float(height[y0 + 1, x0 + 1]) * ax * ay)


def _footprint_drop(height, vx, vy, half, yaw_deg, vw, vh):
    """How far the ground falls across a building's own rotated rectangle
    (`half` = (half_depth, half_width), metres) centred on vertex (vx, vy):
    highest minus lowest of a 3 x 3 grid over it. The runtime stands a house
    on its HIGHEST ground and builds a foundation down to its lowest (owner
    2026-09-24: 不可以被地面遮住部分), so this drop is that foundation's height."""
    (fx, fz), (rx, rz) = _axes(yaw_deg)
    hd, hw = half
    ys = []
    for a in (-1.0, 0.0, 1.0):
        for b in (-1.0, 0.0, 1.0):
            ox = fx * hd * a + rx * hw * b
            oz = fz * hd * a + rz * hw * b
            ys.append(_height_at(height, vx + ox / VERTEX_M, vy + oz / VERTEX_M, vw, vh))
    return max(ys) - min(ys)


def _dry(land, vx, vy, vw, vh, shore_m):
    """True when every vertex within shore_m of this point is land."""
    rad = max(int(math.ceil(shore_m / VERTEX_M)), 0)
    x0, x1 = int(vx) - rad, int(vx) + rad + 1
    y0, y1 = int(vy) - rad, int(vy) + rad + 1
    # an unmodelled edge is not known to be dry: refuse rather than judge a
    # candidate on a window silently shrunk by clamping to the array bounds
    if x0 < 0 or x1 > vw or y0 < 0 or y1 > vh:
        return False
    return bool(np.all(land[y0:y1, x0:x1] > 0.5))


def _find_landmark_spot(cx, cy, land, vw, vh, shore_m, bound_m, on_water=None, drop=None,
                        max_drop=None):
    """The nearest point to the burg's own centre that stands on land with
    its shore buffer clear, searched in rings out to bound_m; None if
    nothing within it passes ("never in the sea" is structural even for the
    landmark).

    `on_water(vx, vy)` refuses a river as well (2026-09-21): Azgaar puts a
    riverside burg's own centre ON its river, so the one building that is
    NOT placed by the house passes — the palace, the church, the chapel a
    settlement is read by — was the one standing in the water.

    `drop(vx, vy)` is how far the ground falls across the landmark's own
    footprint there (owner 2026-09-24: 不可以被地面遮住部分 — the runtime
    stands it on its highest ground over a foundation down to its lowest,
    and a church across a 155 m fall stood on a tower of stone). The nearest
    spot within `max_drop` wins; when none is, the flattest spot searched."""
    def _ok(vx, vy):
        if not (0 <= vx < vw and 0 <= vy < vh):
            return False
        if float(land[int(vy), int(vx)]) < 0.5:
            return False
        if not _dry(land, vx, vy, vw, vh, shore_m):
            return False
        return not (on_water is not None and on_water(vx, vy))

    best = None   # (drop, ox, oz) of the flattest spot that passed _ok
    candidates = [(0.0, 0.0)]
    step = 11.0   # metres: half a house's jittered-grid cell, fine enough to hug the shore
    ring = 1
    while (ring - 1) * step < bound_m:
        rad = min(ring * step, bound_m)
        for a in range(16):
            ang = a * (2.0 * math.pi / 16.0)
            candidates.append((rad * math.cos(ang), rad * math.sin(ang)))
        if rad >= bound_m:
            break
        ring += 1
    for ox, oz in candidates:
        vx, vy = cx + ox / VERTEX_M, cy + oz / VERTEX_M
        if not _ok(vx, vy):
            continue
        if drop is None:
            return ox, oz
        d = drop(vx, vy)
        if max_drop is None or d <= max_drop:
            return ox, oz
        if best is None or d < best[0]:
            best = (d, ox, oz)
    return None if best is None else (best[1], best[2])


def _axes(yaw_deg):
    """The two unit axes of a footprint's own local frame (its "width" and
    "length" directions), for the separating-axis test below."""
    r = math.radians(yaw_deg)
    return (math.sin(r), math.cos(r)), (math.cos(r), -math.sin(r))


def _rects_too_close(ax, az, ahalf, ayaw, bx, bz, bhalf, byaw, gap):
    """Oriented rectangle overlap: true when two footprints (centre, half
    extents, yaw in degrees) come closer than `gap` metres apart, tested by
    the separating axis theorem over each box's own two edge normals — a
    circle-distance bound is not tight enough for rotated rectangles (two
    boxes can sit closer, corner to corner, than the sum of their
    half-widths would suggest along an axis), which is why the "current
    algorithm" this replaces read as gapped: it was really testing circles.

    `ahalf` / `bhalf` are (half_depth, half_width): half extents along the
    building's own FACING axis and across it, the pair `half_extents()`
    returns. A scalar is accepted as a square, which is what this took
    before the types carried a depth (density v5, owner 2026-09-21 —
    a square of the LONG side reserved a 14 x 14 m plot for a 14 x 10 m
    cottage, so a third of every settlement's ground was air the packer
    had already spent and no density could win it back)."""
    aux, auz = _axes(ayaw)
    bux, buz = _axes(byaw)
    ad, aw = (ahalf, ahalf) if np.isscalar(ahalf) else ahalf
    bd, bw = (bhalf, bhalf) if np.isscalar(bhalf) else bhalf
    ad, aw = ad + gap * 0.5, aw + gap * 0.5
    bd, bw = bd + gap * 0.5, bw + gap * 0.5
    tx, tz = bx - ax, bz - az
    for lx, lz in (aux, auz, bux, buz):
        t = abs(tx * lx + tz * lz)
        ra = ad * abs(aux[0] * lx + aux[1] * lz) + aw * abs(auz[0] * lx + auz[1] * lz)
        rb = bd * abs(bux[0] * lx + bux[1] * lz) + bw * abs(buz[0] * lx + buz[1] * lz)
        if t > ra + rb:
            return False   # a separating axis: the two rectangles clear each other
    return True


def half_extents(row):
    """(half along the building's facing axis, half across it) for one type
    of data/screens/map3d/map3d_houses.csv. The mesh faces +Z and Map3DLayerHouses turns
    it about the vertical by the row's yaw, so the mesh's own Z span lies
    along `_axes(yaw)`'s first axis and its X span along the second.

    `width_m` / `depth_m` are MEASURED off the built mesh (they are written
    by tools/map3d/scale_houses.py, like height_m); a table that carries
    neither falls back to the square of footprint_m this used to assume."""
    w = float(row.get("width_m") or 0.0) or float(row["footprint_m"])
    d = float(row.get("depth_m") or 0.0) or float(row["footprint_m"])
    return 0.5 * d, 0.5 * w


def _walk_lane(rng, lanes, x0, z0, bearing, r_house, step, wander,
               branch_chance, max_depth, depth, max_steps):
    """One lane, grown as a random walk from (x0, z0) outward on `bearing`
    (degrees, 0 = +z, 90 = +x — the same convention a house's own facing
    yaw uses), heading perturbed by up to ±wander a step; a child lane may
    fork off at each step while depth allows, with a shorter step budget
    than its parent so the network thins as it branches rather than filling
    the whole cluster with backbone. Appends every lane of at least one
    step (its own and every child's) to `lanes` in place."""
    pts = [(x0, z0, bearing)]
    x, z = x0, z0
    steps = 0
    while math.hypot(x, z) <= r_house and steps < max_steps:
        bearing = bearing + rng.uniform(-wander, wander)
        rad = math.radians(bearing)
        x = x + step * math.sin(rad)
        z = z + step * math.cos(rad)
        pts.append((x, z, bearing))
        steps += 1
        if depth < max_depth and rng.random() < branch_chance:
            side = 1.0 if rng.random() < 0.5 else -1.0
            child_bearing = bearing + side * rng.uniform(40.0, 70.0)
            child_budget = max(int((max_steps - steps) * 0.6), 2)
            _walk_lane(rng, lanes, x, z, child_bearing, r_house, step, wander,
                       branch_chance, max_depth, depth + 1, child_budget)
    if len(pts) > 1:
        lanes.append(pts)


def _grow_lanes(rng, r_house, rules):
    """The settlement's lane network: lane_seeds lanes leave the centre on
    roughly even bearings (each jittered so they are not a spoked wheel),
    each a branching random walk out to r_house. Baked once per burg from
    its own seeded stream, never recomputed at runtime."""
    lanes = []
    n_seeds = max(int(rules["lane_seeds"]), 1)
    step = float(rules["lane_step_m"])
    wander = float(rules["lane_wander_deg"])
    branch_chance = float(rules["lane_branch_chance"])
    max_depth = int(rules["lane_max_depth"])
    # generous: the walk wanders rather than making straight for the rim, so
    # its step BUDGET must outlast the distance test that actually stops it
    max_steps = max(int(math.ceil(r_house / max(step, 1e-6))) * 4 + 4, 4)
    base = rng.uniform(0.0, 360.0)
    for i in range(n_seeds):
        bearing = base + i * (360.0 / n_seeds) + rng.uniform(-15.0, 15.0)
        _walk_lane(rng, lanes, 0.0, 0.0, bearing, r_house, step, wander,
                   branch_chance, max_depth, 0, max_steps)
    return lanes


def _resample_lane(lane, plot_step_m):
    """(x, z, bearing_deg) every plot_step_m of arc length along a lane's
    own polyline — the frontage a house can stand against."""
    if len(lane) < 2:
        return []
    cum = [0.0]
    for i in range(len(lane) - 1):
        x0, z0, _ = lane[i]
        x1, z1, _ = lane[i + 1]
        cum.append(cum[-1] + math.hypot(x1 - x0, z1 - z0))
    total = cum[-1]
    if total < 1e-6:
        return []
    out = []
    d = 0.0
    seg = 0
    n_seg = len(lane) - 1
    while d <= total:
        while seg < n_seg - 1 and cum[seg + 1] < d:
            seg += 1
        x0, z0, _ = lane[seg]
        x1, z1, b1 = lane[seg + 1]
        seg_len = max(cum[seg + 1] - cum[seg], 1e-6)
        t = (d - cum[seg]) / seg_len
        out.append((x0 + (x1 - x0) * t, z0 + (z1 - z0) * t, b1))
        d += plot_step_m
    return out


def _frontage_candidates(lanes, plot_step_m, r_house):
    """(d0, x, z, bearing_deg, side) for every plot offered along every
    lane's own frontage, both sides, sorted nearest-centre first — geometry
    only, before any type is picked or any mask applied (`side` is +1/-1,
    the perpendicular a house at that plot would face: bearing + side*90).
    Pulled out of place() so a test can regenerate the exact same candidates
    it placed against, without re-deriving the RNG's own type/jitter draws."""
    out = []
    for lane in lanes:
        for x, z, bearing in _resample_lane(lane, plot_step_m):
            d0 = math.hypot(x, z)
            if d0 > r_house:
                continue
            for side in (1.0, -1.0):
                out.append((d0, x, z, bearing, side))
    out.sort(key=lambda c: (c[0], c[3], c[4]))
    return out


def _nearest_lane(lanes, x, z):
    """(distance_m, bearing_deg) of the lane point nearest (x, z), or
    (None, 0.0) with no lanes at all — the local street's own direction, for
    a block-fill house that reads as belonging to that street rather than
    spun by its own hash."""
    best_d, best_b = None, 0.0
    for lane in lanes:
        for i in range(len(lane) - 1):
            x0, z0, _ = lane[i]
            x1, z1, b1 = lane[i + 1]
            dx, dz = x1 - x0, z1 - z0
            seg_len2 = dx * dx + dz * dz
            if seg_len2 < 1e-9:
                px, pz = x0, z0
            else:
                # a plain min/max, not np.clip: this runs in _nearest_lane's
                # innermost loop, potentially thousands of times per call
                # once the fix round 1 ring quotas make the fill try far
                # more candidates than the old flat cap ever did, and a
                # scalar np.clip's array-wrapping overhead dominated a
                # profile of that (13M calls, ~14s) for no numeric benefit
                t = min(1.0, max(0.0, ((x - x0) * dx + (z - z0) * dz) / seg_len2))
                px, pz = x0 + t * dx, z0 + t * dz
            d = math.hypot(x - px, z - pz)
            if best_d is None or d < best_d:
                best_d, best_b = d, b1
    return best_d, best_b


def _landmark_site(burg, rules, types, land, height, k, vw, vh, wet, rng, r_house):
    """(landmark type, yaw, (x_m, z_m) from the burg's point) for a
    settlement, drawing its yaw from `rng` right after the lanes; the spot is
    None when no ground within reach takes it, and the type None when the
    group allows no landmark at all."""
    group = str(burg.get("group", "village"))
    landmark = _pick_landmark(types, group, str(burg["burg_code"]))
    if landmark is None:
        return None, 0.0, None
    cx, cy = float(burg["x"]) * k, float(burg["y"]) * k
    shore_m = (rules["house_port_shore_min_m"] if int(burg.get("is_port", 0) or 0)
               else rules["house_shore_min_m"])
    # the landmark's own search never reaches past the cluster it is
    # meant to stand in -- the buffer ring beyond r_house must stay
    # empty (the owner's own requirement), so house_landmark_search_m is
    # an outer bound only; r_house also caps it
    search_m = min(float(rules["house_landmark_search_m"]), r_house)
    # a landmark keeps clear of a river by its own half-size, like every
    # other building (see _try_place): Azgaar puts a riverside burg's
    # centre ON the water, and the landmark is the one building the
    # house passes never vet.
    lm_clear = float(rules.get("house_river_clear_m", 0.0)) + max(half_extents(types[landmark]))

    def _lm_on_water(vx, vy):
        if wet is None:
            return False
        return (1.0 - float(wet[int(vy), int(vx)])) * rules["river_wet_m"] < lm_clear

    # the yaw is drawn BEFORE the spot (the same single draw, so the
    # stream is unchanged) because the footprint's fall depends on it
    yaw0 = float(round(rng.uniform(0.0, 360.0), 2))
    lm_half = half_extents(types[landmark])
    lm_max = float(rules["house_landmark_max_drop_m"])

    def _lm_drop(vx, vy):
        return _footprint_drop(height, vx, vy, lm_half, yaw0, vw, vh)

    spot = _find_landmark_spot(cx, cy, land, vw, vh, shore_m, search_m,
                               on_water=_lm_on_water, drop=_lm_drop, max_drop=lm_max)
    if spot is None:
        # A settlement always shows its landmark. The river clearance is
        # a LOOK rule and the sea gate is the structural one, so when a
        # burg's whole cluster is within a river's reach the clearance
        # gives way rather than the settlement disappearing — measured,
        # the strict rule alone left 3 of the pack's 684 with no
        # building at all, which reads as a named dot standing on empty
        # ground.
        spot = _find_landmark_spot(cx, cy, land, vw, vh, shore_m, search_m,
                                   drop=_lm_drop, max_drop=lm_max)
    if spot is not None:
        spot = (float(round(spot[0], 2)), float(round(spot[1], 2)))
    return landmark, yaw0, spot


def landmark_of(burg, rules, types, land, height, k, vw, vh, wet=None):
    """(type, yaw, spot) of this settlement's landmark exactly as place()
    would choose it — the spot in metres from the burg's own point, None
    when nothing takes it — so the bake can stamp the built ground round it
    and level its terrace BEFORE the houses are placed, then hand it to
    place() as `site`. Replays place()'s own draws."""
    rng = np.random.default_rng(_seed(str(burg["burg_code"])))
    r_house = cluster_radius_m(burg, rules, types)
    _grow_lanes(rng, r_house, rules)
    return _landmark_site(burg, rules, types, land, height, k, vw, vh, wet, rng, r_house)


def landmark_centre(burg, rules, types, land, height, k, vw, vh, wet=None):
    """Where place() will stand this settlement's landmark, in metres from
    the burg's own point ((0, 0) when it has none)."""
    spot = landmark_of(burg, rules, types, land, height, k, vw, vh, wet)[2]
    return spot if spot is not None else (0.0, 0.0)


def level_pad(height, vx, vy, half, yaw_deg, rules, land=None, wet=None):
    """Level the ground under a landmark and its square IN PLACE (owner
    2026-09-25: a palace on a hillside stood on a tower of its own stone
    footing and read as a skyscraper): every vertex inside the landmark's
    rectangle grown by house_plaza_m and one vertex takes the mean height
    there — cut on the uphill side, fill on the downhill — and the ground
    eases back to the hill over house_pad_blend_m. The sea and a river's
    channel and banks (`land`, `wet`) are never touched. `vx`, `vy` are the
    landmark's vertex coordinates, `half` its (along, across) half-extents."""
    vh, vw = height.shape
    a = half[0] + float(rules["house_plaza_m"]) + VERTEX_M
    c = half[1] + float(rules["house_plaza_m"]) + VERTEX_M
    blend = float(rules["house_pad_blend_m"])
    reach = (math.hypot(a, c) + blend) / VERTEX_M + 1
    x0, x1 = max(int(vx - reach), 0), min(int(vx + reach) + 2, vw)
    y0, y1 = max(int(vy - reach), 0), min(int(vy + reach) + 2, vh)
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    dx, dz = (xx - vx) * VERTEX_M, (yy - vy) * VERTEX_M
    (fx, fz), (rx, rz) = _axes(yaw_deg)
    u, v = np.abs(dx * fx + dz * fz), np.abs(dx * rx + dz * rz)
    out = np.hypot(np.maximum(u - a, 0.0), np.maximum(v - c, 0.0))   # metres outside the pad
    sub = height[y0:y1, x0:x1]
    inside = out <= 0.0
    if not inside.any():
        return
    target = float(sub[inside].mean())
    t = np.clip(out / max(blend, 1e-6), 0.0, 1.0)
    w = 1.0 - t * t * (3.0 - 2.0 * t)
    if land is not None:
        w = w * (land[y0:y1, x0:x1] >= 0.5)
    if wet is not None:
        w = w * (1.0 - np.clip(wet[y0:y1, x0:x1], 0.0, 1.0))
    height[y0:y1, x0:x1] = sub + (target - sub) * w


def _port_bearing(vx, vy, rules, height, sea_y, water):
    """The bearing a port's pier would take from its centre (vertex coords
    `vx`, `vy`), walked as harbour() walks it: (rise, shore_m, dx, dz) of the
    NEAREST low shore (pier_max_shore_m or less over the sea, `rise` 0) with
    pier_len_m of open `water` beyond it, else of the nearest high one, or
    None when no bearing within pier_search_m has open water."""
    vh, vw = height.shape
    step, plen = float(rules["pier_step_m"]), float(rules["pier_len_m"])
    reach, max_shore = float(rules["pier_search_m"]), float(rules["pier_max_shore_m"])

    def at(d, dx, dz):
        ix, iy = int(round(vx + dx * d / VERTEX_M)), int(round(vy + dz * d / VERTEX_M))
        if ix < 0 or iy < 0 or ix >= vw or iy >= vh:
            return None
        return bool(water[iy, ix]), float(height[iy, ix])

    low = high = None
    deg = 0.0
    while deg < 360.0:
        a = math.radians(deg)
        dx, dz = math.cos(a), math.sin(a)
        d, shore, last_h = 0.0, None, None
        while d <= reach:
            v = at(d, dx, dz)
            if v is None:
                break
            if v[0]:
                shore = d
                break
            last_h = v[1]
            d += step
        if shore is not None and last_h is not None:
            s, clear = shore, True
            while s <= shore + plen:
                v = at(s, dx, dz)
                if v is None or not v[0]:
                    clear = False
                    break
                s += step
            if clear:
                rise = last_h - sea_y
                if rise <= max_shore:
                    if low is None or shore < low[1]:
                        low = (0.0, shore, dx, dz)
                elif high is None or shore < high[1]:
                    high = (rise, shore, dx, dz)
        deg += float(rules["pier_bearing_step_deg"])
    return low if low is not None else high


def port_plain(burg, height, vx, vy, rules, types, sea_y, water, land=None, wet=None):
    """Lower a cliff port onto a coastal plain IN PLACE (owner 2026-10-12, R9
    and R18: 所有在悬崖边的定居点…改为非悬崖，平原即可 — every cliff-edge
    port stands on plain ground and takes the timber pier).

    A port is lowered when its harbour bearing (_port_bearing) rises over
    pier_max_shore_m, OR when its built ground (cluster_radius_m /
    house_built_share round its landmark at `vx`, `vy`) stands, by its median,
    pier_stair_town_rise_m or more over the sea though a low shore is in reach
    (a town on a cliff top). Its built ground and a corridor from there to the
    shore — port_plain_corridor_m wide, and never narrower than the built
    ground, so the plain opens to the sea as a cove, not a bowl — are cut to
    sea_y + port_plain_rise_m. The ground eases back over a blend of
    max(port_plain_blend_m, 1.5 * cut / port_plain_max_grade) (smoothstep's
    steepest is 1.5 / blend) and the cut there never passes the deepest cut,
    so a hill behind the town is lowered with it, never sliced. Cut only,
    never a fill; the sea and a river's channel (`land`, `wet`) are never
    touched, nor its wet band while port_plain_keep_river_band is 1. A port whose cut would pass port_plain_max_cut_m is left.
    `water` is open water (bake_world's open_water).

    Returns {"cut", "blend", "window", "w"}: the deepest cut in metres (0.0
    nothing to do, None given up — then "need" is the cut it would take), the blend used, the (y0, y1, x0, x1)
    window cut and the cut's weight over it (the texture pass greens the cut
    face by it); window and w are None when nothing was cut."""
    none = {"cut": 0.0, "blend": 0.0, "window": None, "w": None}
    if not int(burg.get("is_port", 0) or 0):
        return none
    bearing = _port_bearing(vx, vy, rules, height, sea_y, water)
    if bearing is None:
        return none
    rise_m, shore, dx, dz = bearing
    target = sea_y + float(rules["port_plain_rise_m"])
    grade = float(rules["port_plain_max_grade"])
    max_cut = float(rules["port_plain_max_cut_m"])
    r_built = cluster_radius_m(burg, rules, types) / float(rules["house_built_share"])
    half_w = max(0.5 * float(rules["port_plain_corridor_m"]), r_built)
    vh, vw = height.shape
    # the widest blend any allowed cut takes, so one window holds every case
    blend_max = max(float(rules["port_plain_blend_m"]), 1.5 * max_cut / grade)
    reach = (max(r_built, shore + half_w) + blend_max) / VERTEX_M + 1
    x0, x1 = max(int(vx - reach), 0), min(int(vx + reach) + 2, vw)
    y0, y1 = max(int(vy - reach), 0), min(int(vy + reach) + 2, vh)
    if x0 >= x1 or y0 >= y1:
        return none
    yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
    px, pz = (xx - vx) * VERTEX_M, (yy - vy) * VERTEX_M
    sub = height[y0:y1, x0:x1]
    keep = np.ones_like(sub)
    if land is not None:
        keep = keep * (land[y0:y1, x0:x1] >= 0.5)
    if wet is not None:
        band = np.clip(wet[y0:y1, x0:x1], 0.0, 1.0)
        # port_plain_keep_river_band 1: a river's channel AND its whole wet
        # band stand untouched; 0: the band takes a cut eased by its wetness
        keep = keep * ((band <= 0.0) if int(rules.get("port_plain_keep_river_band", 1)) else (1.0 - band))
    disc = np.hypot(px, pz) - r_built
    if rise_m <= 0.0:
        # the town's median ground over all its land, the river's band too
        dry = (disc <= 0.0) if land is None else (disc <= 0.0) & (land[y0:y1, x0:x1] >= 0.5)
        ground = sub[dry]
        lofty = ground.size and float(np.median(ground)) - sea_y >= float(rules["pier_stair_town_rise_m"])
        # port_plain_lofty 0: a port with a low shore in reach is never cut
        if not lofty or not int(rules.get("port_plain_lofty", 0)):
            return none
    # metres outside the built disc, and outside the corridor (the segment
    # from the centre to the shore, grown by half its width)
    out_disc = np.maximum(disc, 0.0)
    t_seg = np.clip(px * dx + pz * dz, 0.0, shore)
    out_lane = np.maximum(np.hypot(px - t_seg * dx, pz - t_seg * dz) - half_w, 0.0)
    out = np.minimum(out_disc, out_lane)
    raw = np.maximum(sub - target, 0.0)
    inside = (out <= 0.0) & (keep > 0.0)
    deepest = float(raw[inside].max()) if inside.any() else 0.0
    if deepest <= 0.0:
        return none
    if deepest > max_cut:
        return {"cut": None, "blend": 0.0, "window": None, "w": None, "need": deepest}
    blend = max(float(rules["port_plain_blend_m"]), 1.5 * deepest / grade)
    # the rim's cut is capped at the deepest: a hill behind the town comes
    # down with it, its added slope at most `grade`, never sliced flat
    over = np.minimum(raw, deepest)
    t = np.clip(out / max(blend, 1e-6), 0.0, 1.0)
    w = (1.0 - t * t * (3.0 - 2.0 * t)) * keep
    height[y0:y1, x0:x1] = sub - over * w
    return {"cut": deepest, "blend": blend, "window": (y0, y1, x0, x1), "w": w}


def _square_lane(a, c, yaw_deg, step):
    """A closed lane round a landmark's square: a rectangle `a` out along
    the landmark's facing axis and `c` across it, turned with it, as
    (x, z, bearing_deg) points no more than `step` apart."""
    (fx, fz), (rx, rz) = _axes(yaw_deg)
    corners = [(a, c), (-a, c), (-a, -c), (a, -c), (a, c)]
    pts = []
    for (u0, v0), (u1, v1) in zip(corners, corners[1:]):
        x0, z0 = fx * u0 + rx * v0, fz * u0 + rz * v0
        x1, z1 = fx * u1 + rx * v1, fz * u1 + rz * v1
        bearing = math.degrees(math.atan2(x1 - x0, z1 - z0))
        n = max(int(math.ceil(math.hypot(x1 - x0, z1 - z0) / max(step, 1e-6))), 1)
        for i in range(n):
            t = i / n
            pts.append((x0 + (x1 - x0) * t, z0 + (z1 - z0) * t, bearing))
    pts.append((pts[0][0], pts[0][1], pts[-1][2]))
    return pts


def place(burg, rules, types, foot, land, height, k, vw, vh, debug_counts=None, wet=None, site=None):
    """The houses of one settlement, ranked from the centre outward.

    `foot`, `land`, `height` are the bake's vertex-resolution arrays; `k` is
    vertices per pack px. Offsets come back in metres from the burg's centre,
    +x east and +z south, matching the world frame's axes.

    A settlement whose own centre, and everything within
    min(house_landmark_search_m, r_house) of it, is water gets no landmark
    and no houses: an empty list. The landmark's own search never reaches
    past r_house, so it can never land in the buffer ring beyond the
    cluster's own houses.

    The layout, centred on the landmark's own spot (which moves off water
    or a slope; the houses move with it): an open square round the
    landmark (house_plaza_m) ringed by a lane, a branching lane network
    grown out from the centre, and houses packed
    house rectangles along its frontage (both sides, oriented to face the
    lane), then fill whatever block is left between lanes with a jittered
    close-spaced grid — oriented to the nearest lane, not spun independently
    — until the group's target count is reached or candidates run out.

    `debug_counts`, if a dict is passed, is updated in place with
    {"frontage": n, "infill": n} — how many non-landmark houses each pass
    actually placed (test-only introspection; the returned rows are
    unchanged either way, so a caller that never passes it sees no
    difference).
    """
    code = str(burg["burg_code"])
    group = str(burg.get("group", "village"))
    rng = np.random.default_rng(_seed(code))
    cx, cy = float(burg["x"]) * k, float(burg["y"]) * k
    r_house = cluster_radius_m(burg, rules, types)
    r_inner = square_inner_m(burg, rules, types)
    shore_m = (rules["house_port_shore_min_m"] if int(burg.get("is_port", 0) or 0)
               else rules["house_shore_min_m"])

    rows = []
    taken = []   # (x_m, z_m, half_footprint_m, yaw_deg) of every accepted rectangle
    pass_counts = {"frontage": 0, "infill": 0}   # for debug_counts only

    # lanes are grown FIRST, before anything else draws from `rng` — a test
    # (or a future caller) can reproduce them exactly from a freshly seeded
    # rng and this same call, with no need to replay the landmark's own draws
    lanes = _grow_lanes(rng, r_house, rules)

    landmark, yaw0, spot = _landmark_site(burg, rules, types, land, height, k, vw, vh, wet, rng, r_house)
    if site is not None:
        # the bake chose the site (landmark_of) before it levelled the
        # ground there; the search above only keeps the stream in step
        landmark, yaw0, spot = site
    if landmark is not None and spot is None:
        return []
    # THE SETTLEMENT STANDS ROUND ITS LANDMARK (owner 2026-09-25: "标志性建筑要
    # 在中间附近" — the capital's palace had been moved 59 m off its burg's
    # point onto level ground and every house was still packed round the
    # point, all to one side of it). Everything below is laid out in a frame
    # centred on the landmark's own spot, and shifted back at the end.
    lx, lz = spot if spot is not None else (0.0, 0.0)
    cx, cy = cx + lx / VERTEX_M, cy + lz / VERTEX_M
    half_w = float(rules["lane_half_width_m"])
    if landmark is not None:
        rows.append({"burg_code": code, "rank": 0, "x_m": 0.0, "z_m": 0.0, "yaw_deg": yaw0,
                     "type": landmark, "scale": 1.0,
                     "height_scale": landmark_height_scale(types[landmark], rules)})
        # an open square round it, and a lane round the square: the first
        # houses face the landmark from every side rather than all turning
        # to whichever radial lane happens to pass
        hx, hz = half_extents(types[landmark])
        plaza = float(rules["house_plaza_m"])
        taken.append((0.0, 0.0, (hx + plaza, hz + plaza), yaw0))
        lanes = lanes + [_square_lane(hx + plaza + half_w, hz + plaza + half_w, yaw0,
                                      float(rules["lane_step_m"]))]

    n_target = house_count(burg, rules)
    gap = float(rules["house_gap_m"])
    jitter = float(rules["house_yaw_jitter_deg"])
    barn_r = rules["house_barn_ratio"] * r_house
    hmin, hmax = float(rules["house_height_min"]), float(rules["house_height_max"])
    span = hmax - hmin
    scale_min = float(rules["house_edge_scale_min"])
    sj = float(rules.get("house_scale_jitter", 0.08))
    vrng = np.random.default_rng(_seed(code + "|stretch"))

    # fix round 1, finding 2: filling greedily nearest-first up to a flat
    # n_target and then stopping cuts a hard circle -- full density right up
    # to whatever radius the count happens to run out at, then NOTHING,
    # however far short of r_house that falls (measured: a capital's fill
    # stopped at 220 m of its own 342 m r_house). A budget this much smaller
    # than the disc it's spent in was never going to reach the rim at max
    # density anyway, so instead of one flat budget the target is split into
    # house_edge_rings concentric quotas, richest at the centre and thinning
    # by house_edge_falloff_gamma toward the rim -- even where the outer
    # rings' own quotas round down to a handful or to zero (a village's 8
    # rings at gamma 1.5 round to [8,6,4,3,2,1,1,0]), the uncapped top-up
    # (see the "3b. TOP UP" comment below) still spends there, so the
    # cluster is designed to reach close to r_house rather than stopping
    # wherever a single dense core exhausts the count.
    n_rings = max(int(rules["house_edge_rings"]), 1)
    gamma = float(rules["house_edge_falloff_gamma"])
    weights = [(1.0 - (i + 0.5) / n_rings) ** gamma for i in range(n_rings)]
    wsum = sum(weights) or 1.0
    quotas = [int(round(n_target * w / wsum)) for w in weights]
    diff = n_target - sum(quotas)
    guard = 0
    while diff != 0 and guard < 10 * n_rings:
        idx = guard % n_rings
        if diff > 0:
            quotas[idx] += 1
            diff -= 1
        elif quotas[idx] > 0:
            quotas[idx] -= 1
            diff += 1
        guard += 1
    ring_counts = [0] * n_rings

    # fix round 2, finding 1: lane frontage alone was supplying essentially
    # the WHOLE target (measured: 399 of a capital's 400) before block fill
    # ever got a slot, so the blocks between lanes stayed empty and the town
    # read as a starburst of strings rather than a compact, messy mass.
    # house_frontage_share caps what frontage may take of EACH ring's own
    # quota (not a single flat share of the total), so the cap works WITH
    # the edge-feathering rings rather than against them -- a ring's leftover
    # share is always available to block fill (frontage is gated on this
    # smaller share; infill is still gated on the ring's FULL quota, so it
    # picks up whatever frontage did not spend, including all of it if
    # frontage's own lanes never reached that ring at all).
    frontage_share = float(rules["house_frontage_share"])
    frontage_cap = [int(round(q * frontage_share)) for q in quotas]

    def _ring_of(d):
        # the rings span the ground OUTSIDE the landmark's square, so the
        # richest quota is the first row of houses round it, not the square
        idx = int((d - r_inner) / max(r_house - r_inner, 1e-6) * n_rings)
        return min(max(idx, 0), n_rings - 1)

    def _try_place(ox, oz, yaw, pick, ring, foot_min=None):
        d = math.hypot(ox, oz)
        # the type's own width stretch (owner 2026-10-10): drawn from its own
        # stream so the layout's rng is untouched; the rectangle reserved is
        # the stretched one
        st = float(types[pick].get("stretch") or 0.0)
        stretch = 1.0 + float(vrng.uniform(-st, st)) if st > 0.0 else 1.0
        if d > r_house or d < 1e-6:
            return False
        vx, vy = cx + ox / VERTEX_M, cy + oz / VERTEX_M
        if not (0 <= vx < vw and 0 <= vy < vh):
            return False
        if float(foot[int(vy), int(vx)]) < (rules["house_foot_min"] if foot_min is None else foot_min):
            return False
        if not _dry(land, vx, vy, vw, vh, shore_m):
            return False
        if _slope(height, vx, vy, vw, vh) > rules["house_max_slope"]:
            return False
        half = half_extents(types[pick])
        half = (half[0], half[1] * stretch)
        # owner 2026-09-24 (不可以被地面遮住部分): the runtime stands a house on
        # its highest ground over a foundation down to its lowest, so a plot
        # the ground falls across by more than this would stand on a tower
        # of stone -- the house is placed elsewhere instead
        if _footprint_drop(height, vx, vy, half, yaw, vw, vh) > rules["house_max_drop_m"]:
            return False
        # a river is water too (2026-09-21): `wet` is 1 inside the drawn
        # channel and fades to 0 over river_wet_m beyond it, so
        # (1 - wet) * river_wet_m is this point's distance from the water's
        # EDGE. A house needs its own reach plus house_river_clear_m of it —
        # the clearance covers the runtime's bank wobble
        # (map3d_river_bank_wobble_amp of the local width), and adding the
        # house's own half-size is what stops a building standing clear at
        # its centre and hanging over the water at its corner. NOT the sea's
        # house_shore_min_m: a town stands ON its river, which is what its
        # bridge is for.
        if wet is not None:
            edge_m = (1.0 - float(wet[int(vy), int(vx)])) * rules["river_wet_m"]
            if edge_m < rules["house_river_clear_m"] + max(half):
                return False
        for tx, tz, thalf, tyaw in taken:
            if _rects_too_close(ox, oz, half, yaw, tx, tz, thalf, tyaw, gap):
                return False
        # taper size AND height into the rim (fix round 1, finding 2's second
        # half: "visibly smaller and lower", not merely sparser) -- against
        # the nominal r_house, which the ring quotas now genuinely reach
        t = float(np.clip(d / max(r_house, 1e-6), 0.0, 1.0))
        base_h = hmax - span * t
        hj = float(rules.get("house_height_jitter", 0.3))
        h_jitter = rng.uniform(-hj * span, hj * span) if span > 0 else 0.0
        height_scale = float(np.clip(base_h + h_jitter, hmin, hmax))
        base_scale = 1.0 - (1.0 - scale_min) * t
        taken.append((ox, oz, half, yaw))
        rows.append({"burg_code": code, "rank": 0, "x_m": float(round(ox, 2)),
                     "z_m": float(round(oz, 2)), "yaw_deg": float(round(yaw % 360.0, 2)),
                     "type": pick, "stretch": float(round(stretch, 3)),
                     "scale": float(round(base_scale * rng.uniform(1.0 - sj, 1.0 + sj), 3)),
                     "height_scale": float(round(height_scale, 3))})
        ring_counts[ring] += 1
        return True

    # 2. pack houses along their frontage, both sides, nearest to the centre
    # first, gated by each candidate's own ring quota rather than a flat cap
    plot_step = float(rules["plot_step_m"])
    frontage = _frontage_candidates(lanes, plot_step, r_house)

    def _frontage_pass(enforce_quota):
        for d0, x, z, bearing, side in frontage:
            if sum(ring_counts) >= n_target:
                break
            ring = _ring_of(d0)
            # capped by its OWN share of the ring's quota, not the ring's
            # full quota -- the rest is reserved for block fill (fix round
            # 2, finding 1); the leftover pass below (enforce_quota=False)
            # is what lets frontage claim more if infill can't spend it
            if enforce_quota and ring_counts[ring] >= frontage_cap[ring]:
                continue   # frontage's own share of this band is spent
            role = "barn" if d0 > barn_r else "house"
            pick = _pick(rng, types, role, group, d0 / max(r_house, 1e-6), rules)
            if pick is None:
                continue
            half = 0.5 * float(types[pick]["footprint_m"])
            offset = half_w + half
            perp = math.radians(bearing + side * 90.0)
            ox, oz = x + offset * math.sin(perp), z + offset * math.cos(perp)
            # face the lane, not away from it: forward is (sin(yaw), cos(yaw))
            # (_axes' own convention), and the lane sits back along -side*90
            # from the outward perpendicular the plot was offset along --
            # fix round 1 finding 1, a house was turning its back on its
            # own street
            yaw = bearing - side * 90.0 + rng.uniform(-jitter, jitter)
            if _try_place(ox, oz, yaw, pick, ring):
                pass_counts["frontage"] += 1

    _frontage_pass(enforce_quota=True)

    # 3. fill the leftover block between lanes with a jittered close-spaced
    # grid, oriented to the nearest lane rather than spun on its own, same
    # per-ring quota gate topping up whatever frontage left short
    def _build_grid(step):
        out = []
        reach_g = int(math.ceil(r_house / step))
        for gy in range(-reach_g, reach_g + 1):
            for gx in range(-reach_g, reach_g + 1):
                ox = gx * step + rng.uniform(-0.4, 0.4) * step
                oz = gy * step + rng.uniform(-0.4, 0.4) * step
                d = math.hypot(ox, oz)
                if d > r_house or d < 1e-6:
                    continue
                out.append((d, ox, oz))
        out.sort(key=lambda c: c[0])
        return out

    grid = _build_grid(plot_step)

    def _infill_pass(enforce_quota, candidates=None, foot_min=None):
        for d, ox, oz in (grid if candidates is None else candidates):
            if sum(ring_counts) >= n_target:
                break
            ring = _ring_of(d)
            if enforce_quota and ring_counts[ring] >= quotas[ring]:
                continue
            role = "barn" if d > barn_r else "house"
            pick = _pick(rng, types, role, group, d / max(r_house, 1e-6), rules)
            if pick is None:
                continue
            half = 0.5 * float(types[pick]["footprint_m"])
            lane_d, lane_bearing = _nearest_lane(lanes, ox, oz)
            if lane_d is not None and lane_d < half_w + half:
                continue   # sits over a lane's own clear strip: leave it be
            base_yaw = lane_bearing if lane_d is not None else float(rng.uniform(0.0, 360.0))
            yaw = base_yaw + rng.uniform(-jitter, jitter)
            if _try_place(ox, oz, yaw, pick, ring, foot_min=foot_min):
                pass_counts["infill"] += 1

    if sum(ring_counts) < n_target:
        _infill_pass(enforce_quota=True)

    # 3b. TOP UP: real terrain (shore, slope, a small island) can leave a
    # ring's own band without enough valid ground to meet its quota, and
    # unlike a single flat budget that shortfall is not automatically spent
    # elsewhere -- so if there is still room after both quota-gated passes,
    # spend it on whatever ring still has candidates, favouring the nearest
    # (frontage) then whatever is left (infill), same as the very first
    # design before ring quotas existed. This only ever runs once the
    # quota-respecting passes above have genuinely exhausted every ring's
    # own allowance or its own ground -- a settlement with room to spare
    # never reaches here (both loops break out via sum(ring_counts) >=
    # n_target on their very first check, no different from before)
    # infill runs first here: frontage already had first pick of every ring
    # in pass 2 above, so handing the quota-respecting shortfall to infill
    # FIRST means frontage's uncapped top-up (next) only ever receives what
    # infill genuinely could not place (a block too small, ground infill
    # refuses) -- reversed, frontage's untried candidates soaked up nearly
    # every leftover slot before infill got a turn, measured at 60-72% real
    # frontage share against a 0.45 target
    if sum(ring_counts) < n_target:
        _infill_pass(enforce_quota=False)
    if sum(ring_counts) < n_target:
        _frontage_pass(enforce_quota=False)

    # 3c. FINE-GRID TOP UP: fix round 2, finding 2 -- a small or awkwardly
    # shaped site (a harbour village whose buildable land is a narrow wedge,
    # most of its nominal r_house being open water) can leave the whole
    # settlement stuck at the landmark plus one house, not because it has no
    # room, but because the 10 m infill grid never happens to land a
    # candidate in the sliver of land that IS buildable (measured on one
    # such village: the coarse grid found 4 valid spots out of 96 candidates;
    # a grid a third as coarse found 49 out of ~1500). Only runs when the
    # settlement is still short after every pass above -- a normal
    # settlement never reaches here, so this changes nothing for the vast
    # majority that already meet their target
    if sum(ring_counts) < n_target:
        fine_step = plot_step * float(rules["house_small_site_grid_ratio"])
        if fine_step > 1e-6:
            _infill_pass(enforce_quota=False, candidates=_build_grid(fine_step))

    # 3d. LAST-RESORT RELAXED FOOTPRINT: fix round 2, finding 2 -- diagnosed
    # a second, DIFFERENT cause on a real settlement (chawbigdon, a city):
    # not water, not slope (both fine everywhere in its disc), but the
    # footprint/built-ground mask itself sat at ~0.48 at the settlement's OWN
    # centre and only fell further outward -- the built-ground fray
    # (bake_world.py's own footprint_edge_noise, out of this module's scope)
    # landed low across this settlement's whole disc, on land that is
    # otherwise flat, dry and unremarkable. No amount of denser sampling
    # helps here (100% of even the fine grid failed on foot_min alone), so
    # this is the one hard-coded relaxation: only in this absolute last
    # resort, only after every other pass and the fine grid have all failed,
    # house_foot_min is scaled down by house_small_site_foot_min_ratio. A
    # settlement whose disc is genuinely too steep (verified separately:
    # apton, aringham -- 100% slope failures well past the threshold, not a
    # foot_min problem) is correctly left at its landmark: this never
    # touches the slope or shore tests, so a real cliff or a real sea still
    # refuses a house exactly as before.
    if sum(ring_counts) < n_target:
        relaxed_foot_min = rules["house_foot_min"] * float(rules["house_small_site_foot_min_ratio"])
        fine_step = plot_step * float(rules["house_small_site_grid_ratio"])
        if fine_step > 1e-6:
            _infill_pass(enforce_quota=False, candidates=_build_grid(fine_step), foot_min=relaxed_foot_min)

    # 4. rank dense from the centre out, the landmark pinned at 0
    if landmark is not None:
        rest = rows[1:]
        rest.sort(key=lambda r: math.hypot(r["x_m"], r["z_m"]))
        for i, r in enumerate(rest):
            r["rank"] = i + 1
        rows = [rows[0]] + rest
    else:
        rows.sort(key=lambda r: math.hypot(r["x_m"], r["z_m"]))
        for i, r in enumerate(rows):
            r["rank"] = i

    assign_variants(rows, code, rules, types)
    for r in rows:   # back from the landmark's frame to the burg's own point
        r["x_m"] = float(round(r["x_m"] + lx, 2))
        r["z_m"] = float(round(r["z_m"] + lz, 2))
    if debug_counts is not None:
        debug_counts.update(pass_counts)
    return rows


# -- walls and piers ------------------------------------------------------------------
# Owner 2026-10-01: 城镇里的feature如果有城墙我希望城镇的外围能增加城墙；城镇的feature里
# 如果有码头，我希望城镇能够延伸出去一个码头到海里. Both are extra rows of the
# settlement's houses.csv (roles `wall` / `pier` in data/screens/map3d/map3d_houses.csv), so the
# runtime's houses layer draws them with no new layer; every number is
# data/screens/map3d/map3d_bake.csv's wall_* / pier_*.

def smooth_open(pts, steps):
    """MapGeometry.smooth_open, the runtime's road smoothing, in Python: a
    uniform cubic B-spline through the polyline, the ends clamped, so a gate
    stands where the DRAWN road crosses the wall."""
    n = len(pts)
    if n < 3 or steps < 1:
        return list(pts)
    out = []
    for i in range(-2, n - 1):
        p0 = pts[min(max(i, 0), n - 1)]
        p1 = pts[min(max(i + 1, 0), n - 1)]
        p2 = pts[min(max(i + 2, 0), n - 1)]
        p3 = pts[min(max(i + 3, 0), n - 1)]
        for j in range(steps):
            t = j / steps
            t2, t3 = t * t, t * t * t
            a, b = 1 - 3 * t + 3 * t2 - t3, 4 - 6 * t2 + 3 * t3
            c, d = 1 + 3 * t + 3 * t2 - 3 * t3, t3
            out.append(((p0[0] * a + p1[0] * b + p2[0] * c + p3[0] * d) / 6.0,
                        (p0[1] * a + p1[1] * b + p2[1] * c + p3[1] * d) / 6.0))
    out.append(pts[-1])
    return out


def _seg_cross(a, b, c, d):
    """The point where segment ab crosses segment cd, or None."""
    r = (b[0] - a[0], b[1] - a[1])
    s = (d[0] - c[0], d[1] - c[1])
    den = r[0] * s[1] - r[1] * s[0]
    if abs(den) < 1e-9:
        return None
    t = ((c[0] - a[0]) * s[1] - (c[1] - a[1]) * s[0]) / den
    u = ((c[0] - a[0]) * r[1] - (c[1] - a[1]) * r[0]) / den
    if 0.0 <= t <= 1.0 and 0.0 <= u <= 1.0:
        return (a[0] + t * r[0], a[1] + t * r[1])
    return None


def _half_reach(t):
    """Half a building's diagonal, metres: how far its corners reach."""
    w = float(t.get("width_m") or t["footprint_m"])
    d = float(t.get("depth_m") or t["footprint_m"])
    return 0.5 * math.hypot(w, d)


def _on_land(land, wet, vx, vy, vw, vh):
    ix, iy = int(round(vx)), int(round(vy))
    if ix < 0 or iy < 0 or ix >= vw or iy >= vh:
        return False
    if land[iy, ix] < 0.5:
        return False
    return wet is None or wet[iy, ix] < 0.5


def wall_ring(rows, types, rules, centre, dry_at=None, river_at=None):
    """The wall's line round a settlement's houses: for each of wall_bins
    bearings from `centre` the farthest corner of any building, spread over wall_dilate_bins either way and smoothed (a circular
    [1, 2, 1] pass, wall_smooth_passes times) — never pulled back inside that
    spread, so never inside a building — plus wall_margin_m, never under
    wall_min_r_m. Then each bearing's line is pulled back to the last point
    walking out that `dry_at` ((x, z) -> bool: the coast's land with its shore
    buffer) holds, from its own buildings out — and, when that is no more than
    wall_river_pull_m back, short of where `river_at` (a river's channel)
    begins, past the spread — so the wall runs along the shore and a river's
    near bank, crosses a river that runs through the town (fortify's water
    gate), and CLOSES (owner 2026-10-05: 有城墙必须要合拢), never inside a
    building's own corner; the pulled-back line is eased, only inwards.
    Returns the ring's points, offsets in metres."""
    n = max(int(rules["wall_bins"]), 8)
    raw = np.zeros(n)
    cx, cz = centre
    pts = [(r["x_m"], r["z_m"], _half_reach(types[r["type"]])) for r in rows if r["type"] in types]
    for x, z, half in pts:
        dx, dz = x - cx, z - cz
        reach = math.hypot(dx, dz) + half
        b = int(round(math.atan2(dz, dx) / (2 * math.pi) * n)) % n
        raw[b] = max(raw[b], reach)
    k = int(rules["wall_dilate_bins"])
    env = np.max(np.stack([np.roll(raw, i) for i in range(-k, k + 1)]), axis=0)
    r = env.copy()
    for _ in range(int(rules["wall_smooth_passes"])):
        r = 0.25 * np.roll(r, 1) + 0.5 * r + 0.25 * np.roll(r, -1)
    r = np.maximum(r, env)   # never pulled back inside a building's spread bearings
    r = np.maximum(r + float(rules["wall_margin_m"]), float(rules["wall_min_r_m"]))
    step = 0.25 * VERTEX_M
    floor = np.max(np.stack([np.roll(raw, i) for i in range(-2, 3)]), axis=0) + step

    def walk(i, d, ok):
        ca, sa = math.cos(2 * math.pi * i / n), math.sin(2 * math.pi * i / n)
        while d + step <= r[i] and ok(cx + (d + step) * ca, cz + (d + step) * sa):
            d += step
        return d
    for i in range(n):
        lim = r[i]
        if dry_at is not None:
            lim = min(lim, walk(i, floor[i], dry_at))
        if river_at is not None:
            bank = walk(i, env[i] + step, lambda x, z: not river_at(x, z))
            if bank >= r[i] - float(rules["wall_river_pull_m"]):
                lim = min(lim, bank)
        r[i] = max(lim, floor[i])
    for _ in range(int(rules["wall_smooth_passes"])):
        # the pulled-back line eased, only ever further in (never out over
        # the water it was pulled back from), never inside a building
        r = np.maximum(np.minimum(r, 0.25 * np.roll(r, 1) + 0.5 * r + 0.25 * np.roll(r, -1)), floor)
    return [(cx + r[i] * math.cos(2 * math.pi * i / n), cz + r[i] * math.sin(2 * math.pi * i / n))
            for i in range(n)]


def fortify(burg, rows, rules, types, land, wet, k, vw, vh, roads, height=None):
    """A walled settlement's wall as house rows: its modules round wall_ring,
    each `wall` module wall_len_m along
    the line (the ring cut into whole modules, so they meet), a `wall_gate`
    where a drawn road crosses the line (at least one, on the side facing the
    nearest road) and one where it crosses a river (a water gate), a `wall_tower`
    at every joint the line turns by wall_tower_turn_deg or more and every
    wall_tower_every modules, never within wall_tower_gap_m of another tower
    or a gate. The line keeps wall_shore_m back from the sea,
    off a river's water and, given `height`, back from ground steeper than
    wall_max_slope — a cliff's edge, where a module sheared over the drop
    stood as a stretched screen (wall_ring) — so the circuit is whole: no
    module is ever left out. Every row faces OUT
    (yaw puts the module's front, +Z, along its outward normal). `roads` are
    polylines of offsets in metres from the burg's point. [] for a settlement
    without walls or with too few houses to ring."""
    feats = str(burg.get("features", "")).split("|")
    if "walls" not in feats or len(rows) < int(rules["wall_min_houses"]):
        return []
    centre = (rows[0]["x_m"], rows[0]["z_m"])
    bx, bz = float(burg["x"]) * k, float(burg["y"]) * k
    shore = float(rules["wall_shore_m"])

    def river(p, edge=0.5):
        # `wet` is 1 in a river's drawn channel and fades out over its bank
        if wet is None:
            return False
        ix, iy = int(round(bx + p[0] / VERTEX_M)), int(round(bz + p[1] / VERTEX_M))
        return 0 <= ix < vw and 0 <= iy < vh and wet[iy, ix] >= edge

    def dry(x, z):
        # the coast's land with a shore buffer, as a house's own test (_dry):
        # at the bare point a module on the shore's last vertex stood in a
        # cell the game counts as sea (the cell index is 50 m a pixel, the
        # bake 20)
        vx, vy = bx + x / VERTEX_M, bz + z / VERTEX_M
        return _on_land(land, None, vx, vy, vw, vh) and _dry(land, vx, vy, vw, vh, shore) and \
            (height is None or _slope(height, vx, vy, vw, vh) <= float(rules["wall_max_slope"]))
    ring = wall_ring(rows, types, rules, centre, dry,
                     None if wet is None else (lambda x, z: river((x, z), 0.95)))
    seg_len = float(types["wall"]["footprint_m"]) if "wall" in types else float(rules["wall_len_m"])
    per = [math.hypot(ring[(i + 1) % len(ring)][0] - ring[i][0], ring[(i + 1) % len(ring)][1] - ring[i][1])
           for i in range(len(ring))]
    total = sum(per)
    m = max(int(math.ceil(total / seg_len)), 6)

    def at(s):
        s %= total
        for i, L in enumerate(per):
            if s <= L:
                a, b = ring[i], ring[(i + 1) % len(ring)]
                f = s / max(L, 1e-9)
                return (a[0] + f * (b[0] - a[0]), a[1] + f * (b[1] - a[1]))
            s -= L
        return ring[0]
    joints = [at(total * j / m) for j in range(m)]
    segs = []
    for j in range(m):
        a, b = joints[j], joints[(j + 1) % m]
        mid = ((a[0] + b[0]) / 2, (a[1] + b[1]) / 2)
        tx, tz = b[0] - a[0], b[1] - a[1]
        tl = math.hypot(tx, tz) or 1.0
        ox, oz = tz / tl, -tx / tl
        if (mid[0] - centre[0]) * ox + (mid[1] - centre[1]) * oz < 0:
            ox, oz = -ox, -oz
        segs.append({"a": a, "b": b, "mid": mid, "out": (ox, oz), "wet": river(mid, 0.95), "gate": False})
    # a water gate in the middle of each run the line crosses a river's channel by
    for j, sg in enumerate(segs):
        if sg["wet"] and not segs[j - 1]["wet"]:
            run = 1
            while run < m and segs[(j + run) % m]["wet"]:
                run += 1
            segs[(j + run // 2) % m]["gate"] = True
    # gates where a drawn road crosses the line
    for line in roads:
        for p, q in zip(line, line[1:]):
            for s in segs:
                if _seg_cross(p, q, s["a"], s["b"]) is not None:
                    s["gate"] = True
    if not any(s["gate"] for s in segs):
        best, bd = None, None
        for line in roads:
            for p in line:
                for s in segs:
                    d = math.hypot(p[0] - s["mid"][0], p[1] - s["mid"][1])
                    if bd is None or d < bd:
                        best, bd = s, d
        (best or segs[0])["gate"] = True
    out = []
    rank = max((int(r["rank"]) for r in rows), default=0) + 1
    code = str(burg["burg_code"])

    def add(kind, p, out_dir):
        nonlocal rank
        out.append({"burg_code": code, "rank": rank, "x_m": float(round(p[0], 2)),
                    "z_m": float(round(p[1], 2)),
                    "yaw_deg": float(round(math.degrees(math.atan2(out_dir[0], out_dir[1])), 2)),
                    "type": kind, "scale": 1.0, "height_scale": 1.0})
        rank += 1
    for s in segs:
        add("wall_gate" if s["gate"] else "wall", s["mid"], s["out"])
    turn_min = math.radians(float(rules["wall_tower_turn_deg"]))
    every = max(int(rules["wall_tower_every"]), 1)
    gap_min = float(rules.get("wall_tower_gap_m", 0.0))
    for j in range(m):
        prev, nxt = segs[j - 1], segs[j]
        if prev["gate"] or nxt["gate"]:
            continue
        t0 = math.atan2(prev["b"][1] - prev["a"][1], prev["b"][0] - prev["a"][0])
        t1 = math.atan2(nxt["b"][1] - nxt["a"][1], nxt["b"][0] - nxt["a"][0])
        turn = abs((t1 - t0 + math.pi) % (2 * math.pi) - math.pi)
        if turn >= turn_min or j % every == 0:
            p = joints[j]
            if any(r["type"] != "wall" and math.hypot(r["x_m"] - p[0], r["z_m"] - p[1]) < gap_min for r in out):
                continue
            o = ((prev["out"][0] + nxt["out"][0]) / 2, (prev["out"][1] + nxt["out"][1]) / 2)
            add("wall_tower", p, o)
    return out


# Owner 2026-10-04: a cliff harbour (pier_cliff) where a port's shore is a
# cliff — the capital's first (适合那种我的首都建在悬崖边上的那种风格) — and SHIPS moored
# in every port (港口城市停留在港口的船舶装饰 … 每个不同港口根据其城市大小放置不同的船舶，
# 根据大小1-2艘即可), rows of role `ship` the runtime floats and rocks on the sea.
# Then, on seeing them (港口和城市脱节的太远了 … 港口的结构应当和城市融为一体 … 船要规整的
# 贴着码头停留): a pier stands on the shore NEAREST THE HOUSES and a ship lies
# alongside it. A cliff harbour keeps its own proportions (2026-10-05: 这岩堡大小
# 太不合理了) and a walled town's wall closes round its houses (有城墙必须要合拢:
# fortify), a pier's quay gate in it (clear_under). Every number is
# data/screens/map3d/map3d_bake.csv's pier_*, pier_cliff_* / ship_*.

# A ship's berths in its pier's own frame — the model's Blender metres at
# scale 1, +X out to sea, +Y the model's left: (point on the quay's face,
# the face's outward normal, the hull's long axis). A plain pier's two sides
# of the deck (6.2 m either side of its axis); the small landing's jetty (y
# -2 to 15.5, x 0 to 30); the cliff harbour's timber arm
# (x 66) and its slanting quay. Measured off the models (tripo_harbour).
_BERTHS = {"pier": [((-2.0, 6.2), (0.0, 1.0), (1.0, 0.0)), ((-2.0, -6.2), (0.0, -1.0), (1.0, 0.0))],
           "pier_stair": [((20.0, 15.5), (0.0, 1.0), (1.0, 0.0)), ((20.0, -2.0), (0.0, -1.0), (1.0, 0.0))],
           "pier_cliff": [((66.0, 21.0), (1.0, 0.0), (0.0, 1.0)),
                          ((48.5, -10.0), (0.845, -0.535), (0.535, 0.845))]}


def _local(d, x, y):
    """A pier-frame (Blender x, y) offset as world (x, z) metres, the pier's
    +X along the unit bearing `d`: Blender +Y is Godot -Z, which the yaw turns
    onto (d.z, -d.x)."""
    return (x * d[0] + y * d[1], x * d[1] - y * d[0])


def _ship_types(types, group):
    """The ship types a group allows, the grandest first: the highest
    min_group, then the heaviest weight (a town's merchant cog before its
    longship)."""
    def rank(t):
        g = types[t]["min_group"]
        return GROUP_ORDER.index(g) if g in GROUP_ORDER else -1
    return sorted((t for t, r in types.items() if r["role"] == "ship" and _group_allows(group, r["min_group"])),
                  key=lambda t: (-rank(t), -float(types[t]["weight"]), t))


def _yaw_onto(v):
    """The yaw turning a mesh's +X onto world (x, z) direction `v`."""
    return math.degrees(math.atan2(-v[1], v[0]))


def _moor(burg, types, rules, rank, water_at, origin, d, kind, scale):
    """1-2 ship rows (ship_count_<group>): the grandest type the group allows
    first, then one of its allowed types by weight. Beside a pier each takes a
    berth (_BERTHS, scaled with its pier) and lies ALONGSIDE it, its hull
    ship_gap_m off the quay's face; a berth whose hull is not all water (or
    would cross a ship already moored) slides along the quay by ship_step_m
    (at most ship_tries each way), then tries the pier's other berths, and is
    otherwise given up. At a port with no pier (kind None) the ships ride side
    by side ship_anchor_m off the open shore, walked out by ship_step_m. Water
    is a 5 x 3 grid over the hull grown ship_margin_m all round."""
    group = str(burg.get("group", "village"))
    allowed = _ship_types(types, group)
    n = int(rules.get("ship_count_" + group, 0))
    if not allowed or n <= 0:
        return []
    rng = np.random.default_rng(_seed(str(burg["burg_code"]) + ":ships"))
    picks = [allowed[0]]
    while len(picks) < n:
        w = np.array([float(types[t]["weight"]) for t in allowed])
        picks.append(allowed[int(rng.choice(len(allowed), p=w / w.sum()))])
    gap, step = float(rules["ship_gap_m"]), float(rules["ship_step_m"])
    margin = float(rules.get("ship_margin_m", 0.0))
    out = []
    placed = []   # (x, z, half length, half beam) of each ship moored so far

    def fits(cx, cz, t_ax, n_ax, half_l, half_b):
        hl, hb = half_l + margin, half_b + margin
        return all(water_at(cx + t_ax[0] * a * hl + n_ax[0] * b * hb, cz + t_ax[1] * a * hl + n_ax[1] * b * hb)
                   for a in (-1.0, -0.5, 0.0, 0.5, 1.0) for b in (-1.0, 0.0, 1.0))
    for i, t in enumerate(picks):
        half_l = 0.5 * float(types[t]["width_m"] or types[t]["footprint_m"])
        half_b = 0.5 * float(types[t]["depth_m"] or types[t]["footprint_m"])
        flip = 180.0 if rng.random() < 0.5 else 0.0
        tries = []
        if kind is None:
            side = 1.0 if i % 2 == 0 else -1.0
            n_ax = (-d[1], d[0])
            for k in range(int(rules["ship_tries"]) + 1):
                a_m = float(rules["ship_anchor_m"]) + half_l + k * step
                o = side * (half_b + gap)
                tries.append(((origin[0] + d[0] * a_m + n_ax[0] * o, origin[1] + d[1] * a_m + n_ax[1] * o), d, n_ax))
        else:
            # its own berth first, then the others (a quay whose one side
            # runs too close to the shore still takes its ship on the other)
            berths = _BERTHS[kind]
            for b in range(len(berths)):
                (px, py), (nx, ny), (tx, ty) = berths[(i + b) % len(berths)]
                p = _local(d, px * scale, py * scale)
                n_ax, t_ax = _local(d, nx, ny), _local(d, tx, ty)
                c0 = (origin[0] + p[0] + n_ax[0] * (gap + half_b), origin[1] + p[1] + n_ax[1] * (gap + half_b))
                for k in [0] + [j * sgn for j in range(1, int(rules["ship_tries"]) + 1) for sgn in (1, -1)]:
                    tries.append(((c0[0] + t_ax[0] * k * step, c0[1] + t_ax[1] * k * step), t_ax, n_ax))
        for (cx, cz), t_ax, n_ax in tries:
            if fits(cx, cz, t_ax, n_ax, half_l, half_b) and not any(
                    abs((cx - qx) * t_ax[0] + (cz - qz) * t_ax[1]) < half_l + ql
                    and abs((cx - qx) * n_ax[0] + (cz - qz) * n_ax[1]) < half_b + qb + gap
                    for qx, qz, ql, qb in placed):
                placed.append((cx, cz, half_l, half_b))
                out.append({"burg_code": str(burg["burg_code"]), "rank": rank + len(out),
                            "x_m": float(round(cx, 2)), "z_m": float(round(cz, 2)),
                            "yaw_deg": float(round((_yaw_onto(t_ax) + flip + 180.0) % 360.0 - 180.0, 2)),
                            "type": t, "scale": 1.0, "height_scale": 1.0})
                break
    return out


def _houses_of(rows, types):
    """The (x, z) of a settlement's own buildings — houses, barns, its landmark."""
    return [(r["x_m"], r["z_m"]) for r in rows
            if types.get(r["type"], {}).get("role") in ("house", "barn", "landmark")]


# A cliff landing's HEAD — the masonry the stair climbs to: the cliff
# harbour's castle, the small landing's gate — in the model's own frame
# (Blender metres at scale 1, as _BERTHS): x0, x1, y0, y1 and the height its
# lowest course stands at over the deck. Measured off the models
# (tripo_harbour); re-measure them if one changes.
_HEADS = {"pier_cliff": (-50.0, 15.0, -45.0, 45.0, 38.0),
          "pier_stair": (-28.0, -5.0, -21.0, 21.0, 19.0)}
_CASTLE = _HEADS["pier_cliff"]


def _head_corners(kind, at, d, sc):
    x0, x1, y0, y1 = (v * sc for v in _HEADS[kind][:4])
    return [(at[0] + o[0], at[1] + o[1]) for o in
            (_local(d, x, y) for x in (x0, 0.5 * (x0 + x1), x1) for y in (y0, 0.0, y1))]


def _head_mid(kind, at, d, sc):
    """The middle of a cliff landing's head, world (x, z) offsets."""
    x0, x1 = _HEADS[kind][0] * sc, _HEADS[kind][1] * sc
    return (at[0] + d[0] * 0.5 * (x0 + x1), at[1] + d[1] * 0.5 * (x0 + x1))


def harbour(burg, rows, rules, land, height, k, vw, vh, sea_y, water=None, types=None, sea_cells=None):
    """A port's pier and its moored ships as house rows. From the
    settlement's centre every bearing (pier_bearing_step_deg) is walked to
    its shore within pier_search_m. A LOW shore — its ground no more than
    pier_max_shore_m over the sea, the next pier_len_m out all water — takes
    the timber `pier`, its landward end pier_root_m inland. A CLIFF shore —
    pier_cliff_min_shore_m or more over the sea — takes `pier_cliff` (when
    `types` has it and the group allows it): a capital takes the cliff when it
    has one (pier_cliff_capital_first), any other port only when it has no low
    shore. A cliff harbour keeps its own proportions (pier_cliff_scale,
    pier_cliff_height_scale — owner 2026-10-05: 这岩堡大小太不合理了, a castle
    grown to the plateau stood three houses tall): its rock stands out from
    the shore, its centre pier_cliff_root_m inland (negative: out to sea),
    walked further out by pier_cliff_root_step_m (at most pier_cliff_root_max_m)
    until no ground behind it rises over its castle's lowest course (the
    terrain's own cliff would bury it). Of each kind the one NEAREST THE
    SETTLEMENT'S HOUSES wins — a pier by its shore, a cliff harbour by its
    castle (the nearest shore without `types`). A port whose houses stand
    pier_stair_town_rise_m or more over the sea — a town on a cliff top (owner
    2026-10-05: 建在崖顶的小城…配一个更小的崖边码头) — takes the small cliff
    landing `pier_stair` off its cliff instead of a timber pier below it,
    placed the same way (pier_stair_root_*), its gate nearest the houses.
    pier_cliff_landings 0 turns both cliff landings off (a cliff port is
    lowered first by port_plain and takes the timber pier). Then 1-2 ships (_moor) alongside the pier
    or, for a port that found none, off its nearest open shore. `water`, when
    given, is where BOTH the coastline and the game's cell index say water;
    without it, water is wherever `land` is not. `sea_cells`, when given, is
    the game's own cell index at pack resolution (True: no cell, the sea),
    which a timber pier's head must stand over; without it, `water`. [] for a
    settlement that is not a port."""
    if not int(burg.get("is_port", 0) or 0) or not rows:
        return []
    types = types or {}
    cx, cz = rows[0]["x_m"], rows[0]["z_m"]
    bx, bz = float(burg["x"]) * k, float(burg["y"]) * k
    step = float(rules["pier_step_m"])
    plen = float(rules["pier_len_m"])
    reach = float(rules["pier_search_m"])
    max_shore = float(rules["pier_max_shore_m"])
    group = str(burg.get("group", "village"))
    cliff_min = float(rules.get("pier_cliff_min_shore_m", 1e9))
    sc = float(rules.get("pier_cliff_scale", 1.0))
    hs = float(rules.get("pier_cliff_height_scale", 1.0))
    # each cliff landing the group allows: its scale, height scale, the roots
    # walked out to sea, its half length, its head's lowest course
    landings = {}
    # pier_cliff_landings 0 (owner 2026-10-12, R9: 全部使用普通版码头): never a
    # cliff landing — bake_world's port_plain pass lowers a cliff port instead
    cliff_kinds = (("pier_cliff", (sc, hs)), ("pier_stair", (1.0, 1.0))) \
        if int(rules.get("pier_cliff_landings", 1)) else ()
    for kind, (s_k, h_k) in cliff_kinds:
        if kind not in types or not _group_allows(group, types[kind]["min_group"]):
            continue
        r0 = float(rules.get(kind + "_root_m", 0.0))
        roots = np.arange(r0, float(rules.get(kind + "_root_max_m", r0)) - 1e-6,
                          -abs(float(rules.get(kind + "_root_step_m", 10.0))))
        landings[kind] = (s_k, h_k, roots, 0.5 * float(types[kind].get("width_m") or 140.0),
                          sea_y + _HEADS[kind][4] * s_k * h_k)
    open_reach = float(rules.get("ship_anchor_m", 0.0)) + 2.0 * float(rules.get("ship_step_m", 0.0))
    homes = _houses_of(rows, types)
    root_m = float(rules["pier_root_m"])
    scan = float(rules.get("pier_root_scan_m", step))
    back = float(rules.get("pier_root_back_m", 0.0))
    out_max = float(rules.get("pier_root_out_max_m", 0.0))
    side = float(rules.get("pier_side_clear_m", 0.0))
    skew_max = float(rules.get("pier_max_skew_deg", 180.0))
    # the highest ground a pier's deck may meet: none without the deck's height
    deck_top = sea_y + float(rules["map3d_pier_deck_m"]) + float(rules.get("pier_root_rise_m", 0.0)) \
        if "map3d_pier_deck_m" in rules else None

    def land_at(x, z):
        ix, iy = int(round(bx + x / VERTEX_M)), int(round(bz + z / VERTEX_M))
        if ix < 0 or iy < 0 or ix >= vw or iy >= vh:
            return None
        is_land = (not water[iy, ix]) if water is not None else land[iy, ix] >= 0.5
        return is_land, float(height[iy, ix])

    def water_at(x, z):
        v = land_at(x, z)
        return v is not None and not v[0]

    def head_at_sea(x, z):
        """A pier's head stands where the game's cell index has no cell (what
        MapManors.cell_at reads), else where `water` is."""
        if sea_cells is None:
            return water_at(x, z)
        px, py = int(math.floor(bx / k + x / (VERTEX_M * k))), int(math.floor(bz / k + z / (VERTEX_M * k)))
        return 0 <= py < sea_cells.shape[0] and 0 <= px < sea_cells.shape[1] and bool(sea_cells[py, px])

    def clear(dx, dz, shore, length):
        s = shore
        while s <= shore + length:
            if not water_at(cx + dx * s, cz + dz * s):
                return False
            s += step
        return True

    def near_houses(x, z):
        return min((math.hypot(x - hx, z - hz) for hx, hz in homes), default=0.0)

    def shores_along(dx, dz, limit):
        """(distance, ground height of the last land cell, where that run of
        land began) at each land-to-water change along a bearing from the
        centre, out to `limit`, nearest first."""
        d, last_h, run = 0.0, None, 0.0
        while d <= limit:
            v = land_at(cx + dx * d, cz + dz * d)
            if v is None:
                return
            if v[0]:
                if last_h is None:
                    run = d
                last_h = v[1]
            elif last_h is not None:
                yield d, last_h, run
                last_h = None
            d += step

    def ground(x, z):
        """The ground's height at (x, z), bilinear between the vertices (what
        the terrain draws), or None off the map."""
        fx, fz = bx + x / VERTEX_M, bz + z / VERTEX_M
        i, j = int(math.floor(fx)), int(math.floor(fz))
        if i < 0 or j < 0 or i + 1 >= vw or j + 1 >= vh:
            return None
        a, b = fx - i, fz - j
        return float(height[j, i] * (1 - a) * (1 - b) + height[j, i + 1] * a * (1 - b)
                     + height[j + 1, i] * (1 - a) * b + height[j + 1, i + 1] * a * b)

    def pier_root(dx, dz, shore, run):
        """Where a timber pier found on a bearing stands: (landward end x,
        z, deck direction ux, uz), or None. The masks' shore is a cell edge,
        not the drawn waterline: walking landward from it (no further than
        the run of land it ends, `run`), the first ground at or over the sea
        IS the waterline — a run of "land" that never rises out of the sea
        (a shoal the coarse cell index calls land) has none and is no shore.
        The end stands pier_root_m inland of it. The deck runs on the bearing
        unless that is more than pier_max_skew_deg off the ground's fall
        there (the bearing met the shore obliquely: a deck along the beach),
        when it is turned down the fall. Then the end walks out along the
        deck by pier_root_scan_m (at most pier_root_m + pier_root_out_max_m)
        until no ground from pier_root_back_m behind it to its head stands
        over its deck (map3d_pier_deck_m over the sea) by more than
        pier_root_rise_m — the deck never runs into the bank — and the
        ground pier_side_clear_m either side of its outer half is under the
        sea."""
        s, s_w = shore, None
        while s >= run - 1e-6:
            g = ground(cx + dx * s, cz + dz * s)
            if g is None:
                return None
            if g >= sea_y:
                s_w = s
                break
            s -= scan
        if s_w is None:
            return None
        px, pz = cx + dx * (s_w - root_m), cz + dz * (s_w - root_m)
        if deck_top is None:
            return px, pz, dx, dz
        ux, uz = dx, dz
        if skew_max < 180.0:
            e = max(back, scan)
            g = [ground(px + e, pz), ground(px - e, pz), ground(px, pz + e), ground(px, pz - e)]
            if None in g:
                return None
            fx, fz = g[1] - g[0], g[3] - g[2]   # the fall: minus the gradient
            n = math.hypot(fx, fz)
            if n > 1e-6 and (fx * dx + fz * dz) / n < math.cos(math.radians(skew_max)):
                ux, uz = fx / n, fz / n

        def under_deck(x, z):
            t = -back
            while t <= plen + 1e-6:
                g = ground(x + ux * t, z + uz * t)
                if g is None or g > deck_top:
                    return False
                t += scan
            # its head over the game's own open water (both masks: the cell
            # index calls it sea), its outer half over the drawn water, with
            # water either side (pier_side_clear_m off its axis)
            if not head_at_sea(x + ux * (plen - scan), z + uz * (plen - scan)):
                return False
            t = plen / 2
            while t <= plen + 1e-6:
                g = ground(x + ux * t, z + uz * t)
                if g is None or g >= sea_y:
                    return False
                for sgn in ((-1.0, 1.0) if side > 0.0 else ()):
                    g = ground(x + ux * t - uz * sgn * side, z + uz * t + ux * sgn * side)
                    if g is None or g >= sea_y:
                        return False
                t += scan
            return True
        k = 0.0
        while not under_deck(px + ux * k, pz + uz * k):
            k += scan
            if k > root_m + out_max + 1e-6:
                return None
        return px + ux * k, pz + uz * k, ux, uz

    def head_clear(kind, at, d):
        # no ground under the head's footprint over its lowest course
        for x, z in _head_corners(kind, at, d, landings[kind][0]):
            v = land_at(x, z)
            if v is None or v[1] > landings[kind][4]:
                return False
        return True
    low = anywhere = None
    best = {}
    deg = 0.0
    while deg < 360.0:
        a = math.radians(deg)
        dx, dz = math.cos(a), math.sin(a)
        d = 0.0
        shore = None
        last_h = None
        while d <= reach:
            v = land_at(cx + dx * d, cz + dz * d)
            if v is None:
                break
            if not v[0]:
                shore = d
                break
            last_h = v[1]
            d += step
        if shore is not None and last_h is not None:
            rise = last_h - sea_y
            gap = near_houses(cx + dx * shore, cz + dz * shore) if types else shore
            if rise <= max_shore and clear(dx, dz, shore, plen):
                root = pier_root(dx, dz, shore, 0.0)
                if root is not None and (low is None or (gap, shore) < low[0]):
                    low = ((gap, shore), (root[0] + root[2] * plen / 2, root[1] + root[3] * plen / 2)) + root[2:]
            for kind, (s_k, _h, roots, front, _f) in landings.items() if rise >= cliff_min else ():
                for root in roots:
                    mid = shore - root * s_k
                    at = (cx + dx * mid, cz + dz * mid)
                    if head_clear(kind, at, (dx, dz)) and clear(dx, dz, shore, (front - root) * s_k):
                        cg = near_houses(*_head_mid(kind, at, (dx, dz), s_k))
                        if kind not in best or (cg, shore) < best[kind][0]:
                            best[kind] = ((cg, shore), mid, dx, dz)
                        break
            if (anywhere is None or shore < anywhere[1]) and clear(dx, dz, shore, open_reach):
                anywhere = ((gap, shore), shore, dx, dz)
        deg += float(rules["pier_bearing_step_deg"])
    fallback = float(rules.get("pier_search_fallback_m", 0.0))
    if low is None and fallback > reach:
        # no low shore within pier_search_m: look further out for one, so the
        # port still takes the normal timber pier (never a cliff landing)
        deg = 0.0
        while deg < 360.0:
            a = math.radians(deg)
            dx, dz = math.cos(a), math.sin(a)
            # every shore on the bearing, nearest first: a river or a lake
            # edge with high banks is walked PAST (it is no sea), and the
            # first shore that is low and open for the pier's length wins
            for shore, last_h, run in shores_along(dx, dz, fallback):
                root = pier_root(dx, dz, shore, run) \
                    if last_h - sea_y <= max_shore and clear(dx, dz, shore, plen) else None
                if root is not None:
                    gap = near_houses(cx + dx * shore, cz + dz * shore) if types else shore
                    if low is None or (gap, shore) < low[0]:
                        low = ((gap, shore), (root[0] + root[2] * plen / 2, root[1] + root[3] * plen / 2)) + root[2:]
                    break
            deg += float(rules["pier_bearing_step_deg"])
    lofty = statistics.median([land_at(x, z)[1] if land_at(x, z) else sea_y for x, z in homes] or [sea_y]) \
        - sea_y >= float(rules.get("pier_stair_town_rise_m", 1e9))
    pick = None
    cliff, stair = best.get("pier_cliff"), best.get("pier_stair")
    if cliff is not None and group == "capital" and int(rules.get("pier_cliff_capital_first", 0)):
        pick = ("pier_cliff", sc, hs) + cliff[1:]
    elif stair is not None and (lofty or low is None):
        pick = ("pier_stair", 1.0, 1.0) + stair[1:]
    elif low is not None:
        pick = ("pier", 1.0, 1.0) + low[1:]
    elif cliff is not None:
        pick = ("pier_cliff", sc, hs) + cliff[1:]
    rank = max((int(r["rank"]) for r in rows), default=0) + 1
    out = []
    if pick is not None:
        kind, s, h, mid, dx, dz = pick
        # a timber pier's spot is its own (pier_root); a cliff landing's a
        # distance on its bearing
        at = mid if isinstance(mid, tuple) else (cx + dx * mid, cz + dz * mid)
        out.append({"burg_code": str(burg["burg_code"]), "rank": rank,
                    "x_m": float(round(at[0], 2)), "z_m": float(round(at[1], 2)),
                    # the pier runs along the mesh's +X: yaw turns +X onto (dx, dz)
                    "yaw_deg": float(round(_yaw_onto((dx, dz)), 2)),
                    "type": kind, "scale": float(round(s, 3)), "height_scale": float(round(h, 3))})
        out += _moor(burg, types, rules, rank + 1, water_at, at, (dx, dz), kind, s)
    elif anywhere is not None:
        shore, dx, dz = anywhere[1:4]
        out += _moor(burg, types, rules, rank, water_at, (cx + dx * shore, cz + dz * shore), (dx, dz), None, 1.0)
    return out


def _frame(p):
    """A laid row's mesh +X as a world (x, z) unit bearing."""
    yaw = math.radians(float(p["yaw_deg"]))
    return (math.cos(yaw), -math.sin(yaw))


def _pier_root(p, types):
    """Where a pier meets the land, world (x, z) offsets: a timber pier's
    landward end, a small cliff landing's gate (its stair's head)."""
    d = _frame(p)
    if p["type"] in _HEADS:
        return _head_mid(p["type"], (p["x_m"], p["z_m"]), d, float(p["scale"]))
    half = 0.5 * float(types[p["type"]]["width_m"] or types[p["type"]]["footprint_m"]) * float(p["scale"])
    return (p["x_m"] - d[0] * half, p["z_m"] - d[1] * half)


def clear_under(rows, laid, types, rules=None):
    """`rows` less every building and wall module whose centre stands under a
    laid pier — a timber pier's own rectangle (its table width x depth at its
    scale), a cliff landing's head (_HEADS; its rock stands against the
    land's own cliff) — never the landmark; a tower set where the wall it cut now ends; the wall module
    nearest a pier's landward end made a gate (the quay gate, within
    pier_gate_reach_m); then the
    ranks renumbered densely, `laid` after them."""
    keep = []
    piers = [r for r in laid if types.get(r["type"], {}).get("role") == "pier"]

    def box(p):
        sc = float(p["scale"])
        if p["type"] in _HEADS:
            return tuple(v * sc for v in _HEADS[p["type"]][:4])
        t = types[p["type"]]
        hw = 0.5 * float(t["width_m"] or t["footprint_m"]) * sc
        hd = 0.5 * float(t["depth_m"] or t["footprint_m"]) * sc
        return (-hw, hw, -hd, hd)
    for r in rows:
        under = False
        if int(r["rank"]) != 0:
            for p in piers:
                d = _frame(p)
                ox, oz = r["x_m"] - p["x_m"], r["z_m"] - p["z_m"]
                u = ox * d[0] + oz * d[1]
                v = ox * d[1] - oz * d[0]
                x0, x1, y0, y1 = box(p)
                if x0 <= u <= x1 and y0 <= v <= y1:
                    under = True
                    break
        if not under:
            keep.append(r)
    # a wall the harbour cut ends on a tower, as a wall stopping at the water does
    cut = [r for r in rows if r not in keep and r["type"] == "wall"]
    ends = []
    for r in keep:
        if r["type"] != "wall" or not cut:
            continue
        yaw = math.radians(float(r["yaw_deg"]))
        half = 0.5 * float(types["wall"]["width_m"] or types["wall"]["footprint_m"])
        for sgn in (-1.0, 1.0):
            e = (r["x_m"] + sgn * half * math.cos(yaw), r["z_m"] - sgn * half * math.sin(yaw))
            if any(math.hypot(c["x_m"] - e[0], c["z_m"] - e[1]) < half + 2.0 for c in cut):
                ends.append(dict(r, type="wall_tower", x_m=float(round(e[0], 2)), z_m=float(round(e[1], 2))))
    keep += ends
    # the quay gate: the wall module nearest each pier's landward end (a
    # small landing's stair head), within pier_gate_reach_m of it
    for p in piers:
        walls = [r for r in keep if r["type"] in ("wall", "wall_gate")]
        if p["type"] == "pier_cliff" or not walls:   # the capital's castle is its own gate
            continue
        a = _pier_root(p, types)
        w = min(walls, key=lambda r: math.hypot(r["x_m"] - a[0], r["z_m"] - a[1]))
        if math.hypot(w["x_m"] - a[0], w["z_m"] - a[1]) <= float((rules or {}).get("pier_gate_reach_m", 0.0)):
            w["type"] = "wall_gate"
    out = sorted(keep, key=lambda r: int(r["rank"])) + sorted(laid, key=lambda r: int(r["rank"]))
    for i, r in enumerate(out):
        r["rank"] = i
    return out
