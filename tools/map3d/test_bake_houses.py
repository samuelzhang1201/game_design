"""Unit tests for the house placement (spec 2026-09-20 §1, redesign
2026-09-20: lanes, not a jittered grid).

  python3 -m pytest tools/map3d/test_bake_houses.py
"""
import csv
import math
import os
from unittest import mock

import numpy as np
import pytest

import bake_houses
from bake_houses import place, house_count, house_radius_m, footprint_radius_m

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))

VW = VH = 64
K = 2.5           # vertices per pack px, as bake_world.py's k
CENTRE = 32.0     # vertex coords of the toy burg
CENTRE_COL = 32   # the column the toy sea stops at

RULES = {
    # density v4 (owner 2026-09-21): the cluster's radius comes from the
    # group's own fixed house count and that group's per-house density,
    # never from population -- see house_radius_m's own note in
    # bake_houses.py. The real data/map3d_bake.csv values, so this
    # fixture's magnitudes stand for something.
    "house_m2_each_capital": 340, "house_m2_each_city": 400, "house_m2_each_town": 480,
    "house_m2_each_fort": 480, "house_m2_each_village": 520,
    "house_built_share": 0.53, "house_barn_ratio": 0.75,
    "house_foot_min": 0.55, "house_max_slope": 0.38,
    "house_max_drop_m": 8.0, "house_landmark_max_drop_m": 10.0,
    "house_shore_min_m": 25, "house_port_shore_min_m": 6,
    "house_landmark_search_m": 300, "house_yaw_jitter_deg": 35, "house_plaza_m": 8, "house_pad_blend_m": 60,
    "house_gap_m": 1.0, "house_height_min": 0.75, "house_height_max": 1.5,
    "house_count_capital": 80, "house_count_city": 60, "house_count_town": 40,
    "house_count_fort": 30, "house_count_village": 20,
    "lane_seeds": 4, "lane_step_m": 20, "lane_wander_deg": 25,
    "lane_branch_chance": 0.15, "lane_max_depth": 3, "lane_half_width_m": 1.75,
    "plot_step_m": 10,
    "house_edge_rings": 8, "house_edge_falloff_gamma": 1.5, "house_edge_scale_min": 0.75,
    "house_frontage_share": 0.45, "house_small_site_grid_ratio": 0.35,
    "house_small_site_foot_min_ratio": 0.7,
}

TYPES = {
    "cottage_a": {"role": "house", "weight": 1.0, "footprint_m": 7.0, "min_group": "village"},
    # a big house-role type, mirroring the real map3d_houses.csv's longhouse
    # (16 m) -- without one, this fixture is too small to ever expose fix
    # round 1 finding 4 (the frontage offset can push a house-role candidate
    # well past the barn ring before its role, decided from a SMALLER
    # assumed size, is even chosen)
    "longhouse": {"role": "house", "weight": 0.4, "footprint_m": 16.0, "min_group": "village"},
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


# bake_houses.place() rounds x_m/z_m/yaw_deg to 2 decimals before returning
# a row (the CSV's own precision) -- that rounding can, at most, shift a
# stored position by ~0.01 m per axis, which for a pair sitting EXACTLY at
# the SAT boundary can turn a real (pre-rounding) clearance into an
# apparent overlap of a similar, sub-centimetre size once reconstructed
# from the rounded output. Deflating each half-width by this much when
# testing the OUTPUT rows absorbs that storage rounding without hiding a
# real overlap (house_gap_m is 1.0 m, two orders of magnitude bigger).
ROUNDING_SLACK_M = 0.02


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
    b = burg()
    rows = place(b, RULES, TYPES, foot, land, height, K, VW, VH)
    r_house = bake_houses.cluster_radius_m(b, RULES, TYPES)
    for r in rows:
        assert np.hypot(r["x_m"], r["z_m"]) <= r_house + 1e-6


def test_steep_ground_is_refused():
    foot, land, height = flat_world()
    height[:] = np.arange(VW, dtype=np.float32) * 40.0   # a 2.0 gradient over 20 m
    rows = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    assert len(rows) == 1, "only the landmark, which is pinned to the burg's own point"


def test_no_house_needs_a_foundation_taller_than_the_limit():
    """Owner 2026-09-24 (不可以被地面遮住部分): the runtime stands a house on
    its highest ground over a foundation down to its lowest, so the bake
    refuses a plot the ground falls across by more than house_max_drop_m.
    A slope gentle enough for house_max_slope still falls ~4 m across a
    house here; with the limit at 2 m some plots fit and none exceed it."""
    foot, land, height = flat_world()
    yy, xx = np.mgrid[0:VH, 0:VW].astype(np.float32)
    height[:] = np.sin(xx * 0.35) * 6.0 + xx * 0.5    # rolling ground: steep and flat bands
    rules = dict(RULES, house_max_drop_m=2.0, house_max_slope=5.0)
    rows = place(burg(), rules, TYPES, foot, land, height, K, VW, VH)
    houses = [r for r in rows if r["rank"] > 0]
    assert houses, "the flat bands still take houses"
    for r in houses:
        vx = CENTRE + r["x_m"] / bake_houses.VERTEX_M
        vy = CENTRE + r["z_m"] / bake_houses.VERTEX_M
        d = bake_houses._footprint_drop(height, vx, vy, bake_houses.half_extents(TYPES[r["type"]]),
                                        r["yaw_deg"], VW, VH)
        assert d <= 2.0 + 1e-6, "%s at (%.0f, %.0f) needs a %.1f m foundation" % (r["type"], r["x_m"], r["z_m"], d)


def test_the_landmark_moves_off_a_cliff_to_the_nearest_level_spot():
    """A settlement's own centre on a cliff edge: its landmark goes to the
    nearest spot whose footprint falls no more than house_landmark_max_drop_m."""
    foot, land, height = flat_world()
    yy, xx = np.mgrid[0:VH, 0:VW].astype(np.float32)
    height[:] = np.where(xx < CENTRE + 1, 0.0, 60.0)    # a 60 m cliff just east of the centre
    rows = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    lm = rows[0]
    assert lm["rank"] == 0
    vx = CENTRE + lm["x_m"] / bake_houses.VERTEX_M
    vy = CENTRE + lm["z_m"] / bake_houses.VERTEX_M
    d = bake_houses._footprint_drop(height, vx, vy, bake_houses.half_extents(TYPES[lm["type"]]),
                                    lm["yaw_deg"], VW, VH)
    assert d <= RULES["house_landmark_max_drop_m"] + 1e-6


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
    # offset -- is known, so the boundary allows slack rather than the old
    # algorithm's pixel-exact ring (the old test's premise, that EVERY house
    # past the ring is a barn with no tolerance, no longer holds now that
    # role and final position are decided a step apart). A uniform footprint
    # mask (not flat_world()'s own, which decays to nothing by 400 m) and a
    # count target pushed well past what the cluster can actually hold, so
    # placement is forced to reach all the way out to the barn ring rather
    # than filling up on the near core alone -- with a modest target count
    # and a lot of room, it never gets there.
    #
    # Fix round 1, finding 4: the slack is DERIVED from the geometry, not a
    # picked number -- the frontage offset can push a house-role candidate
    # outward by lane_half_width_m plus the largest half-depth any
    # house-role type in this run's own `types` table can have (here,
    # "longhouse"'s 8 m half), which is exactly the worst case a real
    # candidate can overshoot the ring its role was decided against.
    foot = np.ones((VH, VW), np.float32)
    land = np.ones((VH, VW), np.float32)
    height = np.zeros((VH, VW), np.float32)
    rules = dict(RULES, house_count_town=300)
    b = burg(pop=4000, group="town")
    rows = place(b, rules, TYPES, foot, land, height, K, VW, VH)
    r_house = bake_houses.cluster_radius_m(b, rules, TYPES)
    max_house_half = max(0.5 * t["footprint_m"] for t in TYPES.values() if t["role"] == "house")
    slack = RULES["lane_half_width_m"] + max_house_half
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
        ah = 0.5 * TYPES[a["type"]]["footprint_m"] + gap * 0.5 - ROUNDING_SLACK_M
        for b in rows[i + 1:]:
            bh = 0.5 * TYPES[b["type"]]["footprint_m"] + gap * 0.5 - ROUNDING_SLACK_M
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
    # house_landmark_search_m (300 m) is an outer bound only: a village's
    # own r_house is far smaller (density v4: sqrt(house_count_village *
    # house_m2_each_village / pi), fixed by group, never by this burg's
    # population of 1).
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
    r_house = house_radius_m(b, RULES)
    assert r_house < 4.0 * 20.0, "the sea must reach past this tiny cluster's own radius"
    rows = place(b, RULES, TYPES, foot, land, height, K, VW, VH)
    assert rows == [], "the only dry ground lies outside the cluster: no landmark, no houses"


# ---- the redesign's own behaviour (spec 2026-09-20, "lanes not a grid") ----

def test_the_cluster_radius_comes_from_the_count_and_the_group_density():
    """density v4 (owner 2026-09-21): a cluster's radius is the radius of a
    circle whose area holds the group's fixed house COUNT at that group's
    own per-house density — never population, never the footprint."""
    for group in ("village", "fort", "town", "city", "capital"):
        b = burg(group=group)
        want = math.sqrt(RULES["house_count_%s" % group]
                         * RULES["house_m2_each_%s" % group] / math.pi)
        assert house_radius_m(b, RULES) == pytest.approx(want)
        # population plays no part: only the GROUP does
        assert house_radius_m(dict(b, population=1), RULES) == \
            house_radius_m(dict(b, population=10 ** 7), RULES)
    # an unknown group falls back to the village count AND the village density
    assert house_radius_m({"group": "nonesuch"}, RULES) == \
        pytest.approx(house_radius_m(burg(group="village"), RULES))


def test_the_density_is_per_group_so_a_capital_packs_tighter_than_a_village():
    """The whole point of the per-group split (owner 2026-09-21): one shared
    density could not serve both ends, because a settlement at full fill has
    exactly its density's ground per house BY CONSTRUCTION — the loose value
    a small awkward village site needs to fill at all is the very value that
    would leave a capital sparse."""
    ground = {}
    for group in ("village", "town", "capital"):
        b = burg(group=group)
        ground[group] = (math.pi * house_radius_m(b, RULES) ** 2
                         / RULES["house_count_%s" % group])
        assert ground[group] == pytest.approx(RULES["house_m2_each_%s" % group])
    assert ground["capital"] < ground["village"], \
        "a capital is the group that reaches full fill anywhere: it is packed tight"


def test_footprint_radius_is_the_house_radius_over_the_built_share():
    """density v4: the footprint (the built ground the terrain bake stamps)
    is DOWNSTREAM of the house cluster now, not the other way around — the
    buffer ring the owner asked for is house_built_share of it, and it never
    moves with population."""
    for group in ("village", "town", "capital"):
        b = burg(group=group)
        assert footprint_radius_m(b, RULES) == pytest.approx(
            house_radius_m(b, RULES) / RULES["house_built_share"])
        assert footprint_radius_m(dict(b, population=1), RULES) == \
            footprint_radius_m(dict(b, population=10 ** 7), RULES)


def test_house_count_tracks_group_not_population():
    small = house_count({"population": 50, "group": "city"}, RULES)
    large = house_count({"population": 5_000_000, "group": "city"}, RULES)
    assert small == large == RULES["house_count_city"]
    assert house_count({"population": 1, "group": "some_unlisted_group"}, RULES) \
        == RULES["house_count_village"]


def test_lanes_exist_as_negative_space():
    # Fix round 1, finding 3: the previous version sampled points along the
    # lane centreline and checked how many were free of a building -- true
    # by construction, since EVERY placement rule already keeps rectangles
    # off the centrelines (proven: deleting the block-fill lane guard
    # entirely and re-running still passed, free fraction ~0.93-0.95 against
    # a > 0.5 bar -- with such a sparse cluster relative to its own area,
    # almost any point reads "free" whether the guard does anything or not).
    #
    # This asserts the actual MECHANISM instead: every accepted block-fill
    # house must clear its nearest lane by at least lane_half_width_m plus
    # its own half-footprint -- precisely what the guard (bake_houses.py,
    # "sits over a lane's own clear strip") exists to enforce.
    #
    # Lane-frontage houses are deliberately excluded by DISABLING that phase
    # entirely (mocking _frontage_candidates to return nothing), rather than
    # trying to tell frontage and block-fill houses apart in a normal run:
    # a first attempt at this test left frontage active and found it kept
    # accidentally supplying the clearance around every lane before
    # block-fill ever got a candidate close enough to matter, so the guard's
    # own effect was invisible either way. With frontage disabled, EVERY
    # non-landmark house here is block-fill, and the guard is the only thing
    # keeping any of them off the lanes.
    #
    # Verified both directions by hand: with bake_houses.py's guard deleted,
    # this exact test setup produces a minimum margin of -5.99 m (a house
    # sitting on top of a lane); with the guard restored, +0.15 m (never
    # negative).
    foot, land, height = flat_world()
    code = "toy"
    b = burg(code=code, pop=20000, group="city")
    with mock.patch.object(bake_houses, "_frontage_candidates", return_value=[]):
        rows = place(b, RULES, TYPES, foot, land, height, K, VW, VH)
    r_house = bake_houses.cluster_radius_m(b, RULES, TYPES)
    rng = np.random.default_rng(bake_houses._seed(code))
    lanes = bake_houses._grow_lanes(rng, r_house, RULES)
    half_w = RULES["lane_half_width_m"]
    checked = 0
    for r in rows[1:]:
        half = 0.5 * TYPES[r["type"]]["footprint_m"]
        d, _ = bake_houses._nearest_lane(lanes, r["x_m"], r["z_m"])
        if d is None:
            continue
        checked += 1
        assert d >= half_w + half - 1e-6, \
            f"{r} sits over a lane's own clear strip (distance {d:.2f}, needs {half_w + half:.2f})"
    assert checked > 0, "expected at least one block-fill house near a lane to test the guard against"


def test_frontage_houses_face_their_lane():
    # Fix round 1, finding 1: the old version asserted
    # `want = bearing + side*90`, which is the SAME expression place() itself
    # used to compute the (broken) yaw -- a test that restates the formula it
    # is checking can only ever agree with it, broken or not. This asserts
    # the actual GEOMETRIC property instead: a frontage house's forward
    # vector must point back toward the lane point it was plotted from, i.e.
    # dot(forward, lane_point - house_point) > 0. Under this module's own
    # convention (_axes: forward = (sin(yaw), cos(yaw))), turning the house
    # around flips that dot negative, so this catches the bug the old test
    # could not.
    #
    # Candidates are matched to accepted rows by exact predicted position
    # (not a nearest-lane distance heuristic, which is unreliable here: a
    # house can legitimately sit closer to a DIFFERENT branch of the lane
    # network than the one it was actually plotted against, once branching
    # is dense).
    foot, land, height = flat_world()
    code = "toy"
    b = burg(code=code, pop=4000, group="town")
    rows = place(b, RULES, TYPES, foot, land, height, K, VW, VH)
    r_house = bake_houses.cluster_radius_m(b, RULES, TYPES)
    rng = np.random.default_rng(bake_houses._seed(code))
    lanes = bake_houses._grow_lanes(rng, r_house, RULES)
    frontage = bake_houses._frontage_candidates(lanes, RULES["plot_step_m"], r_house)
    half_w = RULES["lane_half_width_m"]
    checked = 0
    for r in rows[1:]:
        half = 0.5 * TYPES[r["type"]]["footprint_m"]
        for d0, x, z, bearing, side in frontage:
            offset = half_w + half
            perp = math.radians(bearing + side * 90.0)
            px, pz = x + offset * math.sin(perp), z + offset * math.cos(perp)
            if abs(px - r["x_m"]) < 0.02 and abs(pz - r["z_m"]) < 0.02:
                checked += 1
                yaw_r = math.radians(r["yaw_deg"])
                forward = (math.sin(yaw_r), math.cos(yaw_r))
                toward_lane = (x - r["x_m"], z - r["z_m"])
                dot = forward[0] * toward_lane[0] + forward[1] * toward_lane[1]
                assert dot > 0, \
                    f"{r} turns its back to its lane (bearing {bearing}, side {side}, dot {dot})"
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
        ah = 0.5 * TYPES[a["type"]]["footprint_m"] + gap * 0.5 - ROUNDING_SLACK_M
        for b in rows[i + 1:]:
            bh = 0.5 * TYPES[b["type"]]["footprint_m"] + gap * 0.5 - ROUNDING_SLACK_M
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


def test_edge_density_feathers_not_a_cliff():
    """Fix round 1, finding 2: a greedy nearest-first fill against a flat
    per-group count target cuts a hard CIRCLE where the count runs out --
    full density right up to some radius, then nothing, however far short
    of r_house that radius falls. Divide the settlement's own r_house into
    shells and look at the density (count per unit area) in each: the
    occupied shells must taper down toward the edge, and the cluster's own
    reach must not stop far short of r_house either."""
    foot = np.ones((VH, VW), np.float32)
    land = np.ones((VH, VW), np.float32)
    height = np.zeros((VH, VW), np.float32)
    rules = dict(RULES, house_count_capital=400)
    b = burg(pop=90000, group="capital")
    rows = place(b, rules, TYPES, foot, land, height, K, VW, VH)
    r_house = bake_houses.cluster_radius_m(b, rules, TYPES)
    n_shells = 16
    shell_w = r_house / n_shells
    counts = [0] * n_shells
    for r in rows[1:]:
        d = math.hypot(r["x_m"], r["z_m"])
        i = min(int(d // shell_w), n_shells - 1)
        counts[i] += 1
    areas = [math.pi * ((i + 1) * shell_w) ** 2 - math.pi * (i * shell_w) ** 2 for i in range(n_shells)]
    density = [counts[i] / areas[i] for i in range(n_shells)]
    print("shell counts:", counts)
    print("shell density (per sqm):", [round(v, 6) for v in density])
    last_occupied = max(i for i, c in enumerate(counts) if c > 0)
    # the core starts outside the landmark's open square (house_plaza_m,
    # owner 2026-09-25), which is empty by design
    first = int(bake_houses.square_inner_m(b, rules, TYPES) // shell_w) + 1
    core = sum(density[first: first + n_shells // 3]) / (n_shells // 3)
    assert last_occupied >= n_shells - 3, (
        f"the cluster stops at shell {last_occupied}/{n_shells - 1} "
        f"({(last_occupied + 1) * shell_w:.1f} m of {r_house:.1f} m r_house) -- "
        "it should reach near r_house, not cliff off well short of it"
    )
    rim = sum(density[last_occupied - 2: last_occupied + 1]) / 3
    assert rim < 0.6 * core, (
        f"the rim (shells {last_occupied - 2}..{last_occupied}, density {rim:.6f}) "
        f"should be visibly thinner than the core (density {core:.6f}), not full "
        "density right up to the edge"
    )


def test_the_blocks_between_lanes_are_not_empty():
    """Fix round 2, finding 1: lane frontage alone was supplying essentially
    the whole per-group target (measured on the real pack: 399 of a
    capital's 400) before block fill ever got a slot -- the town rendered as
    a starburst of strings radiating from the centre, with the wedges
    between them bare. house_frontage_share caps what frontage may spend of
    EACH ring's own quota, reserving the rest for block fill.

    This measures the fraction of non-landmark houses that stand well away
    from every lane (more than 5x lane_half_width_m from the nearest one) --
    a starburst puts almost nothing out there, since only frontage-adjacent
    positions get built; a compact, messy town puts a real share of its
    houses deep in the blocks. Verified against the pre-fix behaviour
    (house_frontage_share=1.0, no cap): 8.75% of houses fall in the blocks
    -- this test's own threshold (25%) fails against it. With the fix
    (0.45): 48.75%."""
    foot = np.ones((VH, VW), np.float32)
    land = np.ones((VH, VW), np.float32)
    height = np.zeros((VH, VW), np.float32)
    code = "toy"
    b = burg(code=code, pop=90000, group="capital")
    rows = place(b, RULES, TYPES, foot, land, height, K, VW, VH)
    r_house = bake_houses.cluster_radius_m(b, RULES, TYPES)
    rng = np.random.default_rng(bake_houses._seed(code))
    lanes = bake_houses._grow_lanes(rng, r_house, RULES)
    half_w = RULES["lane_half_width_m"]
    non_landmark = rows[1:]
    assert len(non_landmark) > 20, "need a real cluster to measure a block fraction"
    far = 0
    for r in non_landmark:
        d, _ = bake_houses._nearest_lane(lanes, r["x_m"], r["z_m"])
        if d is not None and d > 5.0 * half_w:
            far += 1
    frac = far / len(non_landmark)
    print("fraction of houses away from every lane:", round(frac, 4))
    assert frac > 0.25, (
        f"only {frac:.1%} of houses stand away from the lanes -- the blocks "
        "between them are reading empty (a starburst), not compact and messy"
    )


def test_a_village_on_a_narrow_wedge_site_still_gets_more_houses():
    """Fix round 2, finding 2, cause 1 of 2 (diagnosed on the real pack,
    burg "savehorough", a port village): a harbour village whose buildable
    land is a narrow wedge -- most of its nominal r_house being open water
    -- can be left with almost nothing built, not from lack of room, but
    because the ordinary plot_step_m infill grid never happens to land a
    candidate in the sliver that IS buildable (measured there: 4 of 96
    candidates passed at the normal 10 m step, 49 of ~1500 at a third of
    it). Reproduces that shape with a toy world (land only in a narrow
    wedge) and confirms the fine-grid last resort (house_small_site_grid_ratio)
    recovers more than the ordinary passes alone do.

    house_count_village is overridden well above its real value here: at a
    24-degree wedge and the real house_shore_min_m (25 m), a candidate's own
    shore-buffer window only clears the water past roughly 118 m out
    (25 / tan(12 deg)) -- and under density v4 a village's cluster radius no
    longer grows with population (RULES's own 57 m never reaches that ring
    at all, landmark included). The override stands in for a populous
    coastal town, the scale this mechanism was written to cover, and lands
    the cluster radius (182 m) close to what this test's pop=12000 village
    used to get from the retired population formula (164 m)."""
    vw = vh = 64
    centre = 32.0
    yy, xx = np.mgrid[0:vh, 0:vw].astype(np.float32)
    ang = np.degrees(np.arctan2(xx - centre, yy - centre)) % 360.0   # bearing from centre
    wedge = (ang < 12.0) | (ang > 348.0)   # a narrow 24-degree wedge is "good land"
    land = np.where(wedge, 1.0, 0.0).astype(np.float32)
    foot = np.ones((vh, vw), np.float32)
    height = np.zeros((vh, vw), np.float32)
    b = burg(code="narrowsite", pop=12000, group="village", port=1,
             x=centre / K, y=centre / K)
    rules = dict(RULES, house_count_village=200)
    rows = place(b, rules, TYPES, foot, land, height, K, vw, vh)
    assert rows, "the wedge has dry land; the village should still build"
    assert TYPES[rows[0]["type"]]["role"] == "landmark"
    rows_without_fine_grid = place(b, dict(rules, house_small_site_grid_ratio=0.0),
                                    TYPES, foot, land, height, K, vw, vh)
    print("wedge site: with fine-grid fallback", len(rows), "without", len(rows_without_fine_grid))
    assert len(rows) > len(rows_without_fine_grid), \
        "the fine-grid fallback should recover more houses on a narrow site than the ordinary grid alone"
    assert len(rows) >= 4, (
        f"only {len(rows)} row(s) (landmark plus {len(rows) - 1}) on a site with a real, "
        "if narrow, buildable wedge -- a village should read as a handful of "
        "buildings around its chapel, not as one"
    )


def test_a_settlement_with_a_weak_footprint_mask_still_gets_a_handful_of_houses():
    """Fix round 2, finding 2, cause 2 of 2 (diagnosed on the real pack,
    burg "chawbigdon", a city): NOT water (land everywhere), NOT slope (flat
    everywhere), but the footprint/built-ground mask itself sat at ~0.48 at
    the settlement's own centre and only fell further outward --
    bake_world.py's own footprint_edge_noise frayed low across that whole
    disc, on land that is otherwise unremarkable. No amount of denser
    sampling helps this (the diagnosis found 100% of even a fine grid
    failing on house_foot_min alone), so this checks the one hard-coded
    last resort (house_small_site_foot_min_ratio) recovers a legible
    cluster where the ordinary threshold leaves only the landmark."""
    vw = vh = 64
    land = np.ones((vh, vw), np.float32)
    height = np.zeros((vh, vw), np.float32)
    foot = np.full((vh, vw), 0.50, np.float32)   # below house_foot_min (0.55) everywhere
    b = burg(code="weakfoot", pop=8000, group="village", port=0)
    rows = place(b, RULES, TYPES, foot, land, height, K, vw, vh)
    rows_without_relax = place(b, dict(RULES, house_small_site_foot_min_ratio=1.0),
                                TYPES, foot, land, height, K, vw, vh)
    print("weak-footprint site: with relaxed foot_min", len(rows), "without", len(rows_without_relax))
    assert len(rows_without_relax) == 1, \
        "sanity check: house_foot_min (0.55) against a flat 0.50 mask should leave only the landmark"
    assert len(rows) >= 4, (
        f"only {len(rows)} row(s) on land that is flat, dry and unremarkable everywhere -- "
        "a settlement should not vanish to its landmark over a fraying footprint mask alone"
    )


def _load_real_rules():
    """The production bake table, not the toy fixture -- the leak below
    only shows up at real house_count_*/footprint_* scale (see the test's
    own docstring)."""
    rules = {}
    with open(os.path.join(ROOT, "data", "map3d_bake.csv")) as f:
        for row in csv.DictReader(f):
            try:
                rules[row["key"]] = float(row["value"])
            except ValueError:
                pass   # a text value (a colour, a path) -- not a bake number
    return rules


def _load_real_house_types():
    types = {}
    with open(os.path.join(ROOT, "data", "map3d_houses.csv")) as f:
        for row in csv.DictReader(f):
            types[row["type"]] = {
                "role": row["role"], "weight": float(row["weight"]),
                "footprint_m": float(row["footprint_m"]), "min_group": row["min_group"],
            }
    return types


def test_the_frontage_share_matches_its_target_on_ample_open_ground():
    """Reviewer finding: house_frontage_share is 0.45, but the real pack
    measured 60-72% (stotreso 61.3%, carden 67.7%, shole 60.0%, staptonsey
    72.0%; only shorough, whose own lanes already ran infill-heavy, at
    28.5%). The cause was precise: the uncapped top-up (run only once the
    quota-respecting passes above have genuinely exhausted a ring's own
    allowance -- see the "3b. TOP UP" comment in place()) tried
    `_frontage_pass(enforce_quota=False)` before
    `_infill_pass(enforce_quota=False)`. Since frontage places first and
    already holds the near-lane ground, infill's own grid routinely cannot
    spend its full share of a ring -- and with the old order, that
    shortfall went straight back to frontage's own untried candidates
    instead of infill's, which is what leaked the share upward.

    This reproduces the leak with the REAL production rules and house
    types (map3d_bake.csv / map3d_houses.csv, not the toy fixture, whose
    target counts are too small relative to its footprint to ever reach
    the uncapped top-up at all -- see test_the_blocks_between_lanes_are_not_empty's
    own toy-fixture capital, which never exercises it either) on a flat,
    entirely buildable canvas: foot=land=1 everywhere, no shore or slope
    refusals anywhere. "Ample ground" is exactly this -- nothing about the
    TERRAIN is short; the current house_m2_each_<group> simply packs each
    group's target count densely enough that the ordinary ring-quota
    passes alone routinely fall a little short even here, which is what
    exercises the fallback on every group without needing to manufacture
    scarcity.
    """
    rules = _load_real_rules()
    types = _load_real_house_types()
    vw = vh = 128
    k = 2.5
    foot = np.ones((vh, vw), np.float32)
    land = np.ones((vh, vw), np.float32)
    height = np.zeros((vh, vw), np.float32)
    cap = rules["house_frontage_share"]
    leak_slack = 0.05
    floor = 0.20
    # Density v4 (owner 2026-09-21) moved this measurement, and the
    # assertion with it. house_frontage_share is a CAP on what frontage may
    # take of each ring's own quota, never a promise of what is achieved:
    # the achieved share also depends on how much LANE frontage a cluster
    # grows relative to the count it has to seat, and v4 fixed the cluster's
    # radius per group instead of letting it grow with population -- which
    # for these deliberately huge test populations shrinks the lane network
    # far faster than the target count it must seat. Measured here with the
    # real production values: capital 26.3%, city 31.5%, town 31.4%, fort
    # 36.4%, village 28.0% -- every group comfortably BELOW the cap, the
    # opposite direction from the leak this test exists to catch (frontage
    # spending past its own share of a ring; the real pack measured 60-72%
    # before that fix). So this asserts the two things that still mean
    # something: never past the cap, and never collapsed to a sliver that
    # would read as an all-infill town with no street frontage at all.
    cases = (("capital", 180000), ("city", 200000), ("town", 50000), ("village", 8000))
    for group, pop in cases:
        b = {"burg_code": "ample_%s" % group, "population": pop, "group": group,
             "is_port": 0, "x": vw / 2.0 / k, "y": vh / 2.0 / k}
        debug = {}
        rows = place(b, rules, types, foot, land, height, k, vw, vh, debug_counts=debug)
        assert len(rows) - 1 >= house_count(b, rules), (
            f"{group}: ample, fully buildable ground should still seat the full target "
            f"({len(rows) - 1} of {house_count(b, rules)})"
        )
        total = debug["frontage"] + debug["infill"]
        # a flat "> 20" was really "the village's own target, which was 25";
        # density v5 set it to 20 and the guard started failing on a cluster
        # that had seated every house it was asked for. What it is actually
        # guarding is that the split is measured over essentially the whole
        # cluster, so say that instead of a number.
        assert total >= 0.8 * house_count(b, rules), \
            "need a real cluster to measure a frontage/infill split"
        share = debug["frontage"] / total
        print(group, "frontage share", round(share, 4), "cap", cap)
        assert share <= cap + leak_slack, (
            f"{group}: achieved frontage share {share:.1%} strayed past the "
            f"house_frontage_share cap ({cap:.0%}) plus slack on ample, fully "
            "buildable ground -- the uncapped top-up's fallback order is leaking "
            "frontage share again"
        )
        assert share >= floor, (
            f"{group}: achieved frontage share {share:.1%} fell under {floor:.0%} on "
            "ample, fully buildable ground -- frontage has collapsed to almost "
            "nothing, reading as an all-infill town with no street frontage"
        )


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print("ok", name)


def test_the_houses_stand_round_a_moved_landmark():
    """Owner 2026-09-25 (标志性建筑要在中间附近): when the landmark has to move
    off its burg's own point (water, a slope), the houses are laid round
    where it stands, not round the point it left."""
    foot = np.ones((VH, VW), np.float32)
    land = np.ones((VH, VW), np.float32)
    height = np.zeros((VH, VW), np.float32)
    b = burg(pop=20000, group="city")
    with mock.patch.object(bake_houses, "_find_landmark_spot", return_value=(120.0, -40.0)):
        rows = place(b, RULES, TYPES, foot, land, height, K, VW, VH)
    assert (rows[0]["x_m"], rows[0]["z_m"]) == (120.0, -40.0)
    houses = rows[1:]
    assert len(houses) > 10
    mx = sum(r["x_m"] for r in houses) / len(houses)
    mz = sum(r["z_m"] for r in houses) / len(houses)
    assert math.hypot(mx - 120.0, mz + 40.0) < 20.0, \
        "the houses' centre (%.0f, %.0f) is not round the landmark" % (mx, mz)


def test_no_house_stands_in_the_landmark_square():
    """The landmark keeps an open square of house_plaza_m on every side,
    the houses round it facing in across it."""
    foot = np.ones((VH, VW), np.float32)
    land = np.ones((VH, VW), np.float32)
    height = np.zeros((VH, VW), np.float32)
    b = burg(pop=90000, group="capital")
    rows = place(b, RULES, TYPES, foot, land, height, K, VW, VH)
    lm = rows[0]
    hx, hz = bake_houses.half_extents(TYPES[lm["type"]])
    reach_a, reach_c = hx + RULES["house_plaza_m"], hz + RULES["house_plaza_m"]
    (fx, fz), (rx, rz) = _axes(lm["yaw_deg"])
    facing_in = 0
    for r in rows[1:]:
        dx, dz = r["x_m"] - lm["x_m"], r["z_m"] - lm["z_m"]
        u, v = dx * fx + dz * fz, dx * rx + dz * rz
        assert abs(u) > reach_a or abs(v) > reach_c, "%s stands in the square" % r
        yaw = math.radians(r["yaw_deg"])
        if math.hypot(dx, dz) < max(reach_a, reach_c) + 25.0 \
                and math.sin(yaw) * -dx + math.cos(yaw) * -dz > 0.5 * math.hypot(dx, dz):
            facing_in += 1
    assert facing_in >= 4, "the first row round the square should face the landmark"


def test_a_landmark_stands_on_a_levelled_terrace():
    """Owner 2026-09-25: a palace on a hillside stood on a tower of its own
    footing. level_pad cuts and fills the ground under the landmark and its
    square to one height and eases back to the hill; the sea is untouched."""
    height = np.tile(np.arange(VW, dtype=np.float32) * 6.0, (VH, 1))   # a 0.3 slope
    land = np.ones((VH, VW), np.float32)
    land[:, :4] = 0.0
    before = height.copy()
    half = bake_houses.half_extents(TYPES["palace"])
    bake_houses.level_pad(height, CENTRE, CENTRE, half, 0.0, RULES, land=land)
    pad = height[int(CENTRE) - 1:int(CENTRE) + 2, int(CENTRE) - 1:int(CENTRE) + 2]
    assert pad.max() - pad.min() < 1e-3, "the ground under the landmark is level"
    assert abs(float(pad.mean()) - float(before[int(CENTRE), int(CENTRE)])) < 6.0, "cut and fill, not a mound"
    assert np.array_equal(height[:, :4], before[:, :4]), "the sea is never touched"
    far = int(CENTRE + (max(half) + RULES["house_plaza_m"] + 20 + RULES["house_pad_blend_m"]) / 20) + 2
    assert np.array_equal(height[:, far:], before[:, far:]), "past the blend the hill is as it was"
