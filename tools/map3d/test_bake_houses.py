"""Unit tests for the house placement (spec 2026-09-20 §1, redesign
2026-09-20: lanes, not a jittered grid).

  python3 -m pytest tools/map3d/test_bake_houses.py
"""
import math

import numpy as np
import pytest

import bake_houses
from bake_houses import place, house_count, footprint_radius_m

VW = VH = 64
K = 2.5           # vertices per pack px, as bake_world.py's k
CENTRE = 32.0     # vertex coords of the toy burg
CENTRE_COL = 32   # the column the toy sea stops at

RULES = {
    "footprint_m_per_sqrt_pop": 2.5, "footprint_min_m": 90, "footprint_max_m": 900,
    "house_radius_ratio": 0.60, "house_barn_ratio": 0.75,
    "house_foot_min": 0.55, "house_max_slope": 0.38,
    "house_shore_min_m": 25, "house_port_shore_min_m": 6,
    "house_landmark_search_m": 300, "house_yaw_jitter_deg": 35,
    "house_gap_m": 1.0, "house_height_min": 0.75, "house_height_max": 1.5,
    "house_count_capital": 80, "house_count_city": 60, "house_count_town": 40,
    "house_count_fort": 30, "house_count_village": 20,
    "lane_seeds": 4, "lane_step_m": 20, "lane_wander_deg": 25,
    "lane_branch_chance": 0.15, "lane_max_depth": 3, "lane_half_width_m": 1.75,
    "plot_step_m": 10,
}

TYPES = {
    "cottage_a": {"role": "house", "weight": 1.0, "footprint_m": 7.0, "min_group": "village"},
    "barn":      {"role": "barn",  "weight": 1.0, "footprint_m": 13.0, "min_group": "village"},
    "chapel":    {"role": "landmark", "weight": 1.0, "footprint_m": 10.0, "min_group": "village"},
    "palace":    {"role": "landmark", "weight": 1.0, "footprint_m": 34.0, "min_group": "capital"},
}


def burg(code="toy", pop=4000, group="town", port=0, x=CENTRE / K, y=CENTRE / K):
    return {"burg_code": code, "population": pop, "group": group,
            "is_port": port, "x": x, "y": y}


def flat_world(land_value=1.0):
    foot = np.zeros((VH, VW), np.float32)
    yy, xx = np.mgrid[0:VH, 0:VW].astype(np.float32)
    d = np.hypot(xx - CENTRE, yy - CENTRE)
    foot[:] = np.clip(1.0 - d / 20.0, 0, 1)
    land = np.full((VH, VW), land_value, np.float32)
    height = np.zeros((VH, VW), np.float32)
    return foot, land, height


def _axes(yaw_deg):
    r = math.radians(yaw_deg)
    return (math.sin(r), math.cos(r)), (math.cos(r), -math.sin(r))


def _rects_overlap_independent(ax, az, ahalf, ayaw, bx, bz, bhalf, byaw):
    """A from-scratch separating-axis test (not bake_houses._rects_too_close)
    so the "no overlap" test below does not just re-check the algorithm's
    own bookkeeping against itself."""
    aux, auz = _axes(ayaw)
    bux, buz = _axes(byaw)
    tx, tz = bx - ax, bz - az
    for lx, lz in (aux, auz, bux, buz):
        t = abs(tx * lx + tz * lz)
        ra = ahalf * abs(aux[0] * lx + aux[1] * lz) + ahalf * abs(auz[0] * lx + auz[1] * lz)
        rb = bhalf * abs(bux[0] * lx + bux[1] * lz) + bhalf * abs(buz[0] * lx + buz[1] * lz)
        if t > ra + rb:
            return False
    return True


def test_places_a_landmark_first_at_the_centre():
    foot, land, height = flat_world()
    rows = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    assert rows[0]["rank"] == 0
    assert TYPES[rows[0]["type"]]["role"] == "landmark"
    assert abs(rows[0]["x_m"]) < 1e-6 and abs(rows[0]["z_m"]) < 1e-6


def test_no_house_lands_on_water():
    foot, land, height = flat_world()
    land[:, :CENTRE_COL] = 0.0          # the western half is sea
    rows = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    assert rows, "a half-drowned burg still builds on its dry half"
    for r in rows:
        vx = CENTRE + r["x_m"] / 20.0   # VERTEX_M
        assert vx >= CENTRE_COL - 1e-6, f"{r} stands in the sea"


def test_the_buffer_ring_is_empty():
    foot, land, height = flat_world()
    rows = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    r_foot = 2.5 * np.sqrt(4000)
    r_house = RULES["house_radius_ratio"] * r_foot
    for r in rows:
        assert np.hypot(r["x_m"], r["z_m"]) <= r_house + 1e-6


def test_steep_ground_is_refused():
    foot, land, height = flat_world()
    height[:] = np.arange(VW, dtype=np.float32) * 40.0   # a 2.0 gradient over 20 m
    rows = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    assert len(rows) == 1, "only the landmark, which is pinned to the burg's own point"


def test_the_same_burg_places_the_same_village_twice():
    foot, land, height = flat_world()
    a = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    b = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    assert a == b


def test_two_burgs_do_not_get_the_same_village():
    foot, land, height = flat_world()
    a = place(burg(code="alpha"), RULES, TYPES, foot, land, height, K, VW, VH)
    b = place(burg(code="beta"), RULES, TYPES, foot, land, height, K, VW, VH)
    assert [(r["x_m"], r["z_m"]) for r in a] != [(r["x_m"], r["z_m"]) for r in b]


def test_rank_is_dense_and_grows_outward():
    foot, land, height = flat_world()
    rows = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    assert [r["rank"] for r in rows] == list(range(len(rows)))
    radii = [np.hypot(r["x_m"], r["z_m"]) for r in rows[1:]]
    assert radii == sorted(radii), "a growing settlement grows outward"


def test_far_houses_lean_towards_barns():
    # role is decided from the lane sample (or grid cell) a candidate grows
    # out of, before its actual footprint -- and so before its exact final
    # offset -- is known, so the boundary allows one house's worth of slack
    # rather than the old algorithm's pixel-exact ring (the old test's
    # premise, that EVERY house past the ring is a barn with no tolerance,
    # no longer holds now that role and final position are decided a step
    # apart). A uniform footprint mask (not flat_world()'s own, which decays
    # to nothing by 400 m) and a count target pushed well past what the
    # cluster can actually hold, so placement is forced to reach all the way
    # out to the barn ring rather than filling up on the near core alone --
    # with a modest target count and a lot of room, it never gets there.
    foot = np.ones((VH, VW), np.float32)
    land = np.ones((VH, VW), np.float32)
    height = np.zeros((VH, VW), np.float32)
    rules = dict(RULES, house_count_town=300)
    rows = place(burg(pop=4000, group="town"), rules, TYPES, foot, land, height, K, VW, VH)
    r_foot = footprint_radius_m(4000, RULES)
    r_house = RULES["house_radius_ratio"] * r_foot
    slack = 5.0
    far = [r for r in rows[1:]
           if math.hypot(r["x_m"], r["z_m"]) > RULES["house_barn_ratio"] * r_house + slack]
    assert far, "expect some houses safely past the barn ring at this size"
    assert all(TYPES[r["type"]]["role"] == "barn" for r in far)


def test_a_village_never_gets_a_palace():
    foot, land, height = flat_world()
    rows = place(burg(group="village", pop=600), RULES, TYPES, foot, land, height, K, VW, VH)
    assert all(r["type"] != "palace" for r in rows)


def test_houses_do_not_overlap():
    """Rectangle-vs-rectangle, not the old circle test: two squares can sit
    corner to corner closer than the sum of their half-widths, so this checks
    the true oriented overlap, inflated by house_gap_m, with a from-scratch
    SAT test independent of the module's own _rects_too_close."""
    foot, land, height = flat_world()
    rows = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    gap = RULES["house_gap_m"]
    for i, a in enumerate(rows):
        ah = 0.5 * TYPES[a["type"]]["footprint_m"] + gap * 0.5
        for b in rows[i + 1:]:
            bh = 0.5 * TYPES[b["type"]]["footprint_m"] + gap * 0.5
            assert not _rects_overlap_independent(
                a["x_m"], a["z_m"], ah, a["yaw_deg"], b["x_m"], b["z_m"], bh, b["yaw_deg"]
            ), f"{a} and {b} come closer than house_gap_m allows"


def test_no_house_stands_where_the_shore_window_runs_off_the_array_edge():
    # An all-land world with no water anywhere: the only way a candidate can
    # be near unmodelled ground is the _dry() shore-buffer window running past
    # the array's own edge. The centre sits only 3 vertices from the west
    # edge, well inside the burg's house radius, so candidates west of it
    # must probe a window straddling x < 0. That must fail closed (never on)
    # rather than pass on a window silently clipped to the array.
    foot = np.ones((VH, VW), np.float32)
    land = np.ones((VH, VW), np.float32)
    height = np.zeros((VH, VW), np.float32)
    edge_vx = 3.0
    rows = place(burg(x=edge_vx / K, y=CENTRE / K), RULES, TYPES, foot, land, height, K, VW, VH)
    assert rows, "an all-land world should still build houses"
    shore_rad = math.ceil(RULES["house_shore_min_m"] / 20.0)   # VERTEX_M
    for r in rows:
        vx = edge_vx + r["x_m"] / 20.0
        assert vx - shore_rad >= 0, f"{r} sits where its shore window runs off the array edge"


def test_a_water_centre_relocates_the_landmark_onto_land():
    # A burg's own registered point can sit on the water (a port's quay):
    # a small drowned patch right at the burg's centre, land beyond it but
    # still well inside the burg's own r_house (94.87 m for the default
    # town-sized burg here), so the fix round 2 clamp does not swallow it.
    # The landmark must move onto the nearest dry land it finds, not stay
    # pinned to the water at (0, 0) -- spec 2026-09-20 fix round 1, finding 2.
    foot, land, height = flat_world()
    yy, xx = np.mgrid[0:VH, 0:VW].astype(np.float32)
    d = np.hypot(xx - CENTRE, yy - CENTRE)
    land[d < 2.0] = 0.0
    rows = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    assert rows, "land is close by; the settlement should still build"
    assert rows[0]["rank"] == 0
    assert TYPES[rows[0]["type"]]["role"] == "landmark"
    assert math.hypot(rows[0]["x_m"], rows[0]["z_m"]) > 1e-6, \
        "the burg's own point is water; the landmark must move off it"
    vx = CENTRE + rows[0]["x_m"] / 20.0   # VERTEX_M
    vy = CENTRE + rows[0]["z_m"] / 20.0
    assert land[int(vy), int(vx)] > 0.5, "relocated onto land"


def test_a_burg_with_no_land_within_the_search_bound_gets_nothing():
    # Nothing but sea within house_landmark_search_m of the burg: no
    # landmark can be planted anywhere near it, so it gets no houses either
    # -- an empty list, never a landmark left standing in the water.
    foot = np.zeros((VH, VW), np.float32)
    land = np.zeros((VH, VW), np.float32)
    height = np.zeros((VH, VW), np.float32)
    rows = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    assert rows == [], "no land anywhere near the burg: no landmark, no houses"


def test_a_small_burg_never_gets_a_landmark_outside_its_own_cluster():
    # house_landmark_search_m (300 m) is an outer bound only: a minimum-size
    # burg's own r_house is far smaller (54 m for the smallest footprint).
    # Water at the burg's own centre with the only dry ground well past its
    # tiny cluster radius -- the search must be capped at r_house too, so
    # this settlement gets no landmark and no houses, never a landmark
    # standing in the buffer ring beyond its own cluster (spec 2026-09-20
    # fix round 2, finding 1).
    foot, land, height = flat_world()
    yy, xx = np.mgrid[0:VH, 0:VW].astype(np.float32)
    d = np.hypot(xx - CENTRE, yy - CENTRE)
    land[d < 4.0] = 0.0             # an 80 m drowned disc at the centre
    b = burg(pop=1, group="village")
    r_foot = max(2.5 * math.sqrt(1.0), RULES["footprint_min_m"])
    r_house = RULES["house_radius_ratio"] * r_foot
    assert r_house < 4.0 * 20.0, "the sea must reach past this tiny cluster's own radius"
    rows = place(b, RULES, TYPES, foot, land, height, K, VW, VH)
    assert rows == [], "the only dry ground lies outside the cluster: no landmark, no houses"


# ---- the redesign's own behaviour (spec 2026-09-20, "lanes not a grid") ----

def test_house_count_tracks_group_not_population():
    small = house_count({"population": 50, "group": "city"}, RULES)
    large = house_count({"population": 5_000_000, "group": "city"}, RULES)
    assert small == large == RULES["house_count_city"]
    assert house_count({"population": 1, "group": "some_unlisted_group"}, RULES) \
        == RULES["house_count_village"]


def test_lanes_exist_as_negative_space():
    # A big, generous cluster (a lot of candidates, both frontage and
    # block-fill) should still leave most of its OWN lane centrelines free
    # of any building rectangle -- the lanes are the negative space the
    # owner asked for, not just leftover gaps from running out of houses.
    foot, land, height = flat_world()
    code = "toy"
    b = burg(code=code, pop=200000, group="capital")
    rows = place(b, RULES, TYPES, foot, land, height, K, VW, VH)
    r_foot = footprint_radius_m(200000, RULES)
    r_house = RULES["house_radius_ratio"] * r_foot
    rng = np.random.default_rng(bake_houses._seed(code))
    lanes = bake_houses._grow_lanes(rng, r_house, RULES)
    samples = []
    for lane in lanes:
        samples.extend((x, z) for x, z, _ in bake_houses._resample_lane(lane, RULES["plot_step_m"]))
    assert samples, "the lane network should produce sample points to test"

    def covered(x, z):
        for r in rows:
            half = 0.5 * TYPES[r["type"]]["footprint_m"]
            if math.hypot(x - r["x_m"], z - r["z_m"]) < half:
                return True
        return False

    free = sum(1 for x, z in samples if not covered(x, z))
    assert free / len(samples) > 0.5, "most of a lane's own centreline should stay clear of buildings"


def test_frontage_houses_face_their_lane():
    # Regenerate the exact candidate list place() packed against (same rng,
    # same _frontage_candidates geometry helper) and match each one to an
    # accepted row by its exact predicted position -- not a nearest-lane
    # distance heuristic, which is unreliable here: a house can legitimately
    # sit close to a DIFFERENT branch of the lane network than the one it
    # was actually plotted against, once branching is dense.
    foot, land, height = flat_world()
    code = "toy"
    b = burg(code=code, pop=4000, group="town")
    rows = place(b, RULES, TYPES, foot, land, height, K, VW, VH)
    r_foot = footprint_radius_m(4000, RULES)
    r_house = RULES["house_radius_ratio"] * r_foot
    rng = np.random.default_rng(bake_houses._seed(code))
    lanes = bake_houses._grow_lanes(rng, r_house, RULES)
    frontage = bake_houses._frontage_candidates(lanes, RULES["plot_step_m"], r_house)
    half_w = RULES["lane_half_width_m"]
    jitter = RULES["house_yaw_jitter_deg"] + 0.5   # rounding slack
    checked = 0
    for r in rows[1:]:
        half = 0.5 * TYPES[r["type"]]["footprint_m"]
        for d0, x, z, bearing, side in frontage:
            offset = half_w + half
            perp = math.radians(bearing + side * 90.0)
            px, pz = x + offset * math.sin(perp), z + offset * math.cos(perp)
            if abs(px - r["x_m"]) < 0.02 and abs(pz - r["z_m"]) < 0.02:
                checked += 1
                want = (bearing + side * 90.0) % 360.0
                diff = abs((r["yaw_deg"] - want + 180) % 360 - 180)
                assert diff <= jitter, f"{r} does not face its lane (bearing {bearing}, side {side})"
                break
    assert checked > 0, "expected at least one house placed at a lane-frontage plot to test facing"


def test_rectangles_never_overlap_even_at_high_target_counts():
    # Push the count target far above what the toy world can actually fit,
    # so both the frontage pass and the block-fill pass run to exhaustion --
    # the overlap test must still hold under maximum packing pressure.
    foot, land, height = flat_world()
    rules = dict(RULES, house_count_town=400)
    rows = place(burg(pop=4000, group="town"), rules, TYPES, foot, land, height, K, VW, VH)
    assert len(rows) > 10, "a lot of candidates should still get placed"
    gap = rules["house_gap_m"]
    for i, a in enumerate(rows):
        ah = 0.5 * TYPES[a["type"]]["footprint_m"] + gap * 0.5
        for b in rows[i + 1:]:
            bh = 0.5 * TYPES[b["type"]]["footprint_m"] + gap * 0.5
            assert not _rects_overlap_independent(
                a["x_m"], a["z_m"], ah, a["yaw_deg"], b["x_m"], b["z_m"], bh, b["yaw_deg"]
            )


def test_height_scale_varies_and_is_higher_near_the_centre():
    foot, land, height = flat_world()
    rows = place(burg(pop=20000, group="city"), RULES, TYPES, foot, land, height, K, VW, VH)
    non_landmark = [r for r in rows if TYPES[r["type"]]["role"] != "landmark"]
    assert len(non_landmark) >= 6, "need enough houses to compare near vs far"
    by_d = sorted(non_landmark, key=lambda r: math.hypot(r["x_m"], r["z_m"]))
    third = max(len(by_d) // 3, 1)
    near, far = by_d[:third], by_d[-third:]
    near_avg = sum(r["height_scale"] for r in near) / len(near)
    far_avg = sum(r["height_scale"] for r in far) / len(far)
    assert near_avg > far_avg, "the core should read taller than the rim"
    assert len({r["height_scale"] for r in non_landmark}) > 1, \
        "neighbours should not all share exactly the same height"
    for r in rows:
        assert RULES["house_height_min"] <= r["height_scale"] <= RULES["house_height_max"]


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print("ok", name)
