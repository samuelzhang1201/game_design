"""House placement for the 3D map's settlements (spec 2026-09-20 §1).

Pure: given a burg, the tuning rules, the type table and the bake's own
vertex-resolution masks, it returns the houses of one cluster with their
offsets from the burg's centre in metres. It never touches the world frame,
never reads a file and never draws — bake_world.py adds the world origin and
writes the CSV.

"never in the sea" is structural here: a candidate is tested against the very
land mask the footprint was multiplied by, so nothing downstream can place a
house the footprint did not claim.
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


def footprint_radius_m(population, rules):
    """The built ground's radius — the same formula bake_world.py uses; kept
    here so this module stands alone, and asserted equal by the bake's test."""
    return float(np.clip(rules["footprint_m_per_sqrt_pop"] * math.sqrt(max(population, 0.0)),
                         rules["footprint_min_m"], rules["footprint_max_m"]))


def max_houses(group, rules):
    """The most houses a settlement of this group ever shows."""
    return int(rules.get("house_max_%s" % group, rules["house_max_village"]))


def house_count(burg, rules):
    """How many of the baked houses a settlement shows: one per
    house_people_per_house souls, at least house_min, capped by its group."""
    people = float(burg.get("population", 0) or 0)
    n = int(round(people / max(rules["house_people_per_house"], 1.0)))
    return int(min(max(n, int(rules["house_min"])), max_houses(burg.get("group", "village"), rules)))


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


def _slope(height, vx, vy, vw, vh):
    """The ground's gradient (rise over run) at a vertex, from the bake's own
    heightmap — the field the rivers are already carved into."""
    x0, x1 = max(int(vx) - 1, 0), min(int(vx) + 1, vw - 1)
    y0, y1 = max(int(vy) - 1, 0), min(int(vy) + 1, vh - 1)
    dx = (float(height[int(vy), x1]) - float(height[int(vy), x0])) / max((x1 - x0) * VERTEX_M, 1e-6)
    dy = (float(height[y1, int(vx)]) - float(height[y0, int(vx)])) / max((y1 - y0) * VERTEX_M, 1e-6)
    return math.hypot(dx, dy)


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


def place(burg, rules, types, foot, land, height, k, vw, vh, routes=None):
    """The houses of one settlement, ranked from the centre outward.

    `foot`, `land`, `height` are the bake's vertex-resolution arrays; `k` is
    vertices per pack px. Offsets come back in metres from the burg's centre,
    +x east and +z south, matching the world frame's axes.
    """
    code = str(burg["burg_code"])
    group = str(burg.get("group", "village"))
    rng = np.random.default_rng(_seed(code))
    cx, cy = float(burg["x"]) * k, float(burg["y"]) * k
    r_foot = footprint_radius_m(float(burg.get("population", 0) or 0), rules)
    r_house = rules["house_radius_ratio"] * r_foot
    shore_m = (rules["house_port_shore_min_m"] if int(burg.get("is_port", 0) or 0)
               else rules["house_shore_min_m"])

    rows = []
    taken = []   # (x_m, z_m, footprint_m)

    landmark = _pick(rng, types, "landmark", group)
    if landmark is not None:
        rows.append({"burg_code": code, "rank": 0, "x_m": 0.0, "z_m": 0.0,
                     "yaw_deg": float(round(rng.uniform(0.0, 360.0), 2)),
                     "type": landmark, "scale": 1.0})
        taken.append((0.0, 0.0, float(types[landmark]["footprint_m"])))

    # candidates on a jittered grid, gathered then sorted by radius so the
    # ranking is "grows outward" and the order never depends on the scan
    step = float(rules["house_spacing_m"])
    reach = int(math.ceil(r_house / step))
    cand = []
    for gy in range(-reach, reach + 1):
        for gx in range(-reach, reach + 1):
            ox = gx * step + rng.uniform(-0.4, 0.4) * step
            oz = gy * step + rng.uniform(-0.4, 0.4) * step
            d = math.hypot(ox, oz)
            if d > r_house or d < 1e-6:
                continue
            cand.append((d, ox, oz, rng.random()))
    cand.sort(key=lambda c: (c[0], c[1], c[2]))

    core = rules["house_core_ratio"] * r_house
    gamma = rules["house_density_gamma"]
    cap = max_houses(group, rules)
    kept = []
    for d, ox, oz, draw in cand:
        if len(rows) + len(kept) >= cap:
            break
        vx, vy = cx + ox / VERTEX_M, cy + oz / VERTEX_M
        if not (0 <= vx < vw and 0 <= vy < vh):
            continue
        if float(foot[int(vy), int(vx)]) < rules["house_foot_min"]:
            continue
        if not _dry(land, vx, vy, vw, vh, shore_m):
            continue
        if _slope(height, vx, vy, vw, vh) > rules["house_max_slope"]:
            continue
        t = 0.0 if d <= core else (d - core) / max(r_house - core, 1e-6)
        density = (1.0 - t) ** gamma
        role = "barn" if d > rules["house_barn_ratio"] * r_house else "house"
        # house_min is met by relaxing the DENSITY draw only, never a mask
        relaxed = len(kept) < int(rules["house_min"])
        if not relaxed and draw > density:
            continue
        pick = _pick(rng, types, role, group)
        if pick is None:
            continue
        fp = float(types[pick]["footprint_m"])
        clash = False
        for tx, tz, tf in taken:
            if math.hypot(ox - tx, oz - tz) < 0.5 * (fp + tf):
                clash = True
                break
        if clash:
            continue
        taper = 1.0 + (rules["house_edge_scale"] - 1.0) * (d / max(r_house, 1e-6))
        jitter = rules["house_yaw_jitter_deg"]
        yaw = math.degrees(math.atan2(-ox, -oz))          # facing the centre
        if routes:
            near = _nearest_route_bearing(routes, cx + ox / VERTEX_M, cy + oz / VERTEX_M,
                                          k, rules["house_road_align_m"])
            if near is not None:
                yaw = near
        yaw += rng.uniform(-jitter, jitter)
        taken.append((ox, oz, fp))
        kept.append({"burg_code": code, "rank": 0,
                     "x_m": float(round(ox, 2)), "z_m": float(round(oz, 2)),
                     "yaw_deg": float(round(yaw % 360.0, 2)), "type": pick,
                     "scale": float(round(taper * rng.uniform(0.92, 1.08), 3))})

    for i, r in enumerate(kept):
        r["rank"] = len(rows) + i
    rows.extend(kept)
    return rows


def _nearest_route_bearing(routes, vx, vy, k, reach_m):
    """The bearing of the nearest route segment within reach_m, in degrees, or
    None. `routes` is a list of point lists in PACK px."""
    best, best_d = None, reach_m / VERTEX_M
    for pts in routes:
        for i in range(len(pts) - 1):
            ax, ay = pts[i][0] * k, pts[i][1] * k
            bx, by = pts[i + 1][0] * k, pts[i + 1][1] * k
            mx, my = 0.5 * (ax + bx), 0.5 * (ay + by)
            d = math.hypot(mx - vx, my - vy)
            if d < best_d:
                best_d, best = d, math.degrees(math.atan2(bx - ax, by - ay))
    return best
