"""Unit tests for the house placement (spec 2026-09-20 §1).

  python3 -m pytest tools/map3d/test_bake_houses.py
"""
import math

import numpy as np
import pytest

from bake_houses import place, house_count, max_houses

VW = VH = 64
K = 2.5           # vertices per pack px, as bake_world.py's k
CENTRE = 32.0     # vertex coords of the toy burg
CENTRE_COL = 32   # the column the toy sea stops at

RULES = {
    "footprint_m_per_sqrt_pop": 2.5, "footprint_min_m": 90, "footprint_max_m": 900,
    "house_radius_ratio": 0.60, "house_core_ratio": 0.35, "house_barn_ratio": 0.75,
    "house_spacing_m": 22, "house_density_gamma": 1.4, "house_foot_min": 0.55,
    "house_max_slope": 0.38, "house_shore_min_m": 25, "house_port_shore_min_m": 6,
    "house_min": 4, "house_edge_scale": 0.82, "house_yaw_jitter_deg": 35,
    "house_road_align_m": 40, "house_people_per_house": 160,
    "house_max_capital": 220, "house_max_city": 150, "house_max_town": 80,
    "house_max_fort": 60, "house_max_village": 24,
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


def test_only_barns_stand_in_the_outer_ring():
    foot, land, height = flat_world()
    rows = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    r_house = RULES["house_radius_ratio"] * 2.5 * np.sqrt(4000)
    for r in rows[1:]:
        if np.hypot(r["x_m"], r["z_m"]) > RULES["house_barn_ratio"] * r_house:
            assert TYPES[r["type"]]["role"] == "barn"


def test_a_village_never_gets_a_palace():
    foot, land, height = flat_world()
    rows = place(burg(group="village", pop=600), RULES, TYPES, foot, land, height, K, VW, VH)
    assert all(r["type"] != "palace" for r in rows)


def test_houses_do_not_overlap():
    foot, land, height = flat_world()
    rows = place(burg(), RULES, TYPES, foot, land, height, K, VW, VH)
    for i, a in enumerate(rows):
        for b in rows[i + 1:]:
            gap = np.hypot(a["x_m"] - b["x_m"], a["z_m"] - b["z_m"])
            want = 0.5 * (TYPES[a["type"]]["footprint_m"] + TYPES[b["type"]]["footprint_m"])
            assert gap >= want - 1e-6


def test_the_cluster_is_capped_by_group():
    assert max_houses("village", RULES) == 24
    assert max_houses("capital", RULES) == 220


def test_house_count_follows_people():
    assert house_count({"population": 1600, "group": "town"}, RULES) == 10
    assert house_count({"population": 999999, "group": "village"}, RULES) == 24
    assert house_count({"population": 1, "group": "village"}, RULES) == RULES["house_min"]


def test_no_house_stands_where_the_shore_window_runs_off_the_array_edge():
    # An all-land world with no water anywhere: the only way a candidate can
    # be near unmodelled ground is the _dry() shore-buffer window running past
    # the array's own edge. The centre sits only 3 vertices from the west
    # edge, well inside the burg's ~4.7-vertex house radius, so candidates
    # west of it must probe a window straddling x < 0. That must fail closed
    # (never on) rather than pass on a window silently clipped to the array.
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
