"""Plain-assert tests of bake_world.py's pure functions (no pytest here):
    python3 tools/map3d/test_bake_world.py
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(__file__))
import bake_world as bw  # noqa: E402


def test_load_rules_reads_the_table():
    rules = bw.load_rules(os.path.join(bw.ROOT, "data", "map3d_bake.csv"))
    assert rules["sea_y_m"] == 5.0 and rules["coast_supersample"] == 4.0


def test_coverage_of_a_square():
    # A 4x4 pack-px square, k = 1: vertex (1,1) is inside, (6,6) outside,
    # (4,2) on the edge.
    sq = [[(0.0, 0.0), (4.0, 0.0), (4.0, 4.0), (0.0, 4.0)]]
    cov = bw.coverage(sq, [], 8, 8, 1.0, ss=4)
    assert cov[1, 1] > 0.99 and cov[6, 6] < 0.01
    assert 0.3 < cov[2, 4] < 0.7, cov[2, 4]


def test_a_lake_cuts_the_land():
    land = [[(0.0, 0.0), (8.0, 0.0), (8.0, 8.0), (0.0, 8.0)]]
    lake = [[(3.0, 3.0), (5.0, 3.0), (5.0, 5.0), (3.0, 5.0)]]
    cov = bw.coverage(land, lake, 10, 10, 1.0, ss=4)
    assert cov[4, 4] < 0.3 and cov[1, 1] > 0.99


def test_shore_heights_cross_the_water_plane_at_half_coverage():
    h = np.array([[100.0, 100.0, -50.0, -50.0]], dtype=np.float32)
    cov = np.array([[1.0, 0.75, 0.25, 0.0]], dtype=np.float32)
    out = bw.shore_heights(h, cov, 5.0, 4.0)
    assert out[0, 0] == 100.0            # inland keeps its ground
    assert abs(out[0, 1] - 7.0) < 1e-5   # 5 + 4 * (2 * 0.75 - 1)
    assert abs(out[0, 2] - 3.0) < 1e-5   # 5 + 4 * (2 * 0.25 - 1)
    assert out[0, 3] == -50.0            # open sea keeps its depth


def test_sample_bilinear():
    a = np.array([[0.0, 10.0], [20.0, 30.0]], dtype=np.float32)
    got = bw.sample_bilinear(a, np.array([0.5, 1.0]), np.array([0.5, 0.0]))
    assert abs(got[0] - 15.0) < 1e-5 and abs(got[1] - 10.0) < 1e-5


def test_blend_byte():
    w1 = np.array([1.0, 1.0, 1.0, 1.0])
    w2 = np.array([0.0, 1.0, 0.25, 0.5])
    b = bw.blend_byte(w1, w2, np.zeros(4))
    assert b[0] == 0 and b[1] == 128
    assert 0 < b[2] < b[3] < b[1]


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print("ok", name)
