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


def _pick(rng, types, role, group):
    """One type of this role that the group allows, by weight."""
    keys = sorted(t for t, r in types.items()
                  if r["role"] == role and _group_allows(group, r["min_group"]))
    if not keys:
        return None
    w = np.array([float(types[t]["weight"]) for t in keys], dtype=np.float64)
    return keys[int(rng.choice(len(keys), p=w / w.sum()))]


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
    of data/map3d_houses.csv. The mesh faces +Z and Map3DLayerHouses turns
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
                     "height_scale": float(rules["house_height_max"])})
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
        h_jitter = rng.uniform(-0.3 * span, 0.3 * span) if span > 0 else 0.0
        height_scale = float(np.clip(base_h + h_jitter, hmin, hmax))
        base_scale = 1.0 - (1.0 - scale_min) * t
        taken.append((ox, oz, half, yaw))
        rows.append({"burg_code": code, "rank": 0, "x_m": float(round(ox, 2)),
                     "z_m": float(round(oz, 2)), "yaw_deg": float(round(yaw % 360.0, 2)),
                     "type": pick, "scale": float(round(base_scale * rng.uniform(0.92, 1.08), 3)),
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
            pick = _pick(rng, types, role, group)
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
            pick = _pick(rng, types, role, group)
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

    for r in rows:   # back from the landmark's frame to the burg's own point
        r["x_m"] = float(round(r["x_m"] + lx, 2))
        r["z_m"] = float(round(r["z_m"] + lz, 2))
    if debug_counts is not None:
        debug_counts.update(pass_counts)
    return rows
