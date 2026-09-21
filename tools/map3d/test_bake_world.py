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
    assert rules["river_over_sea_m"] == 0.3
    assert rules["far_color_sand"].startswith("#")   # a colour stays text


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
    # High coast: the fringe crosses the plane at cov 0.5 and rises to the
    # land's own height (no flat shelf); seaward it ramps to shore_m under.
    h = np.array([[100.0, 100.0, 100.0, -50.0, -50.0]], dtype=np.float32)
    cov = np.array([[1.0, 0.75, 0.5, 0.25, 0.0]], dtype=np.float32)
    out = bw.shore_heights(h, cov, 5.0, 4.0)
    assert out[0, 0] == 100.0                 # inland keeps its ground
    assert abs(out[0, 1] - 52.5) < 1e-4       # 5 + 0.5 * (100 - 5)
    assert abs(out[0, 2] - 5.0) < 1e-4        # on the plane
    assert abs(out[0, 3] - 3.0) < 1e-4        # 5 - 0.5 * 4: seaward only to shore_m under
    assert out[0, 4] == -50.0                 # open sea keeps its depth
    # Low coast: land held shore_m over the plane, sea shore_m under it.
    low = bw.shore_heights(np.zeros((1, 4), np.float32),
                           np.array([[1.0, 0.75, 0.25, 0.0]], np.float32), 5.0, 4.0)
    assert np.allclose(low, [[9.0, 7.0, 3.0, 0.0]])  # 9, 5 + 0.5 * 4, 5 - 0.5 * 4, 0


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


def test_sharpen_weights():
    # One vertex: cliff 0.5, scree 0.3, soil 0.2 (already normalised), powers 2.
    tw = np.zeros((1, 1, bw.NT), dtype=np.float32)
    tw[0, 0, bw.CLIFF], tw[0, 0, bw.ROCKY], tw[0, 0, bw.SOIL] = 0.5, 0.3, 0.2
    out = bw.sharpen_weights(tw, {"sharp_cliff": 2.0, "sharp_rocky_trail": 2.0})
    assert abs(out[0, 0, bw.CLIFF] - 0.25) < 1e-6    # 0.5^2
    assert abs(out[0, 0, bw.ROCKY] - 0.3025) < 1e-6  # (0.3 + 0.25)^2: the cliff's loss is scree
    assert abs(out[0, 0, bw.SOIL] - 0.04) < 1e-6     # 0.2^2
    assert out[0, 0, bw.ROCKY] > out[0, 0, bw.SOIL]  # soil never overtakes the rim


def test_resample_line_keeps_both_ends():
    pts = bw.resample_line([(0.0, 0.0), (2.5, 0.0)], 1.0)
    assert np.allclose(pts, [[0, 0], [1, 0], [2, 0], [2.5, 0]]), pts


def test_river_bed_always_falls():
    bed = bw.river_bed(np.array([100.0, 90.0, 95.0, 80.0]), 2.0, 0.5, -10.0)
    assert np.allclose(bed, [98.0, 88.0, 87.5, 78.0]), bed


def test_river_bed_stops_at_its_floor():
    bed = bw.river_bed(np.array([1.0, -20.0, -30.0]), 2.0, 0.5, -10.0)
    assert np.allclose(bed, [-1.0, -10.0, -10.0]), bed


def test_river_widths_grow_from_source_to_mouth():
    w = bw.river_widths(5, 100.0, 1.4, 6.0)
    assert w[0] == 6.0 and abs(w[-1] - 100.0) < 1e-6
    assert all(w[i] <= w[i + 1] for i in range(4))


def test_carve_cuts_a_valley():
    h = np.full((41, 41), 100.0, dtype=np.float32)
    wet = np.zeros_like(h)
    rules = {"river_bank_slope": 0.35, "river_bank_max_m": 1500.0, "river_wet_m": 120.0}
    bw.carve(h, wet, np.array([[20.0, 20.0]]), np.array([90.0]), np.array([4.0]), rules)
    assert h[20, 20] == 90.0                         # the bed
    assert abs(h[20, 22] - 90.0) < 1e-4              # still in the water (half width 2)
    assert abs(h[20, 23] - (90.0 + 1 * 20 * 0.35)) < 1e-3  # one vertex up the bank: 97
    # reach = 2 + (100 - 90) / 7 + 1 = 4.43 vertices: 5 out is untouched ground
    assert h[20, 25] == 100.0 and h[0, 0] == 100.0
    assert wet[20, 20] == 1.0 and wet[0, 0] == 0.0


def test_river_span_trims_to_land_and_runs_into_the_sea():
    # coverage along a course: starts at sea, crosses land, ends through the
    # fringe into open sea. The span begins on the first land sample and ends
    # on the first open-sea sample after the last land one (the mouth).
    cov = np.array([0.0, 0.2, 0.6, 1.0, 1.0, 0.7, 0.3, 0.0, 0.0, 0.0])
    assert bw.river_span(cov) == (2, 8)
    assert bw.river_span(np.array([1.0, 1.0, 1.0])) == (0, 3)     # an inland course
    assert bw.river_span(np.array([0.0, 0.1])) is None            # never on land


def test_river_bed_restarts_after_a_lake():
    # A course rising from a lake shore (7 m), then a lake mid-way: the bed
    # restarts at each inland stretch instead of staying at the lake's depth.
    ground = np.array([7.0, 100.0, 90.0, 0.0, 0.0, 80.0, 70.0])
    inland = np.array([False, True, True, False, False, True, True])
    bed = bw.river_bed(ground, 2.0, 0.5, -10.0, restart=inland)
    assert np.allclose(bed, [5.0, 98.0, 88.0, -2.0, -2.0, 78.0, 68.0]), bed
    # a high far shore after the lake is not held at the lake's depth...
    bed = bw.river_bed(np.array([100.0, 0.0, 108.0, 80.0]), 2.0, 0.5, -10.0,
                       restart=np.array([True, False, False, True]))
    assert np.allclose(bed, [98.0, -2.0, 106.0, 78.0]), bed
    # ...but the last stretch, the mouth, keeps falling into the sea
    bed = bw.river_bed(np.array([100.0, 90.0, 0.0, 50.0]), 2.0, 0.5, -10.0,
                       restart=np.array([True, True, False, False]))
    assert np.allclose(bed, [98.0, 88.0, -2.0, -2.5]), bed


def test_smooth_open_is_the_2d_b_spline():
    # MapGeometry.smooth_open: clamped uniform cubic B-spline, ends kept
    out = bw.smooth_open([(0.0, 0.0), (3.0, 0.0), (3.0, 3.0)], 1)
    assert np.allclose(out, [[0, 0], [0.5, 0], [2.5, 0.5], [3, 2.5], [3, 3]]), out
    assert len(bw.smooth_open([(0.0, 0.0), (1.0, 1.0)], 4)) == 2   # too short: as is


def test_carve_eases_into_ground_rising_to_one_side():
    # The ground rises 3 m a vertex east of the river. The bank eases each
    # vertex's own height down to the bed over the valley's width L =
    # (100 - 90) / 7 + 1 = 2.43 vertices (s out from the water's edge), never
    # under the bank's slope: no wall where the flat cone stopped short, and
    # nothing shaved past L (a cone planed whole hillsides to 0.35).
    xs = np.arange(41, dtype=np.float32)
    h = np.tile(100.0 + 3.0 * np.maximum(xs - 20.0, 0.0), (41, 1)).astype(np.float32)
    wet = np.zeros_like(h)
    rules = {"river_bank_slope": 0.35, "river_bank_max_m": 1500.0, "river_wet_m": 120.0}
    bw.carve(h, wet, np.array([[20.0, 20.0]]), np.array([90.0]), np.array([4.0]), rules)
    L = 10.0 / 7.0 + 1.0
    assert abs(h[20, 22] - 90.0) < 1e-4                        # the water's edge: the bed
    assert abs(h[20, 23] - (90.0 + 19.0 * 1 / L)) < 1e-3, h[20, 23]   # 109 eased: 97.82
    assert abs(h[20, 24] - (90.0 + 22.0 * 2 / L)) < 1e-3, h[20, 24]   # 112 eased: 108.1
    assert h[20, 25] == 115.0                                  # past L: untouched
    assert abs(h[20, 17] - 97.0) < 1e-3                        # the flat side keeps the cone


def test_river_fade_holds_the_ridges_down_along_a_course():
    # 0 on the course, rising to 1 at `reach` vertices away (smoothstep)
    fade = bw.river_fade([np.array([[2.0, 5.0], [8.0, 5.0]])], 11, 11, 4)
    assert fade[5, 5] == 0.0 and fade[0, 0] == 1.0
    assert 0.0 < fade[3, 5] < fade[2, 5] < 1.0          # 2 then 3 vertices off
    assert fade[1, 5] == 1.0                             # 4 off: full ridges


def test_carve_sizes_each_valley_from_the_uncut_ground():
    # Two samples a vertex apart on flat ground: the second must size its
    # valley from the 100 m ground, not from the first sample's fresh bed
    # (a 0.04 m depth and a one-vertex valley: a wall at the water's edge).
    h = np.full((41, 41), 100.0, dtype=np.float32)
    rules = {"river_bank_slope": 0.35, "river_bank_max_m": 1500.0, "river_wet_m": 120.0}
    bw.carve(h, np.zeros_like(h), np.array([[20.0, 20.0], [21.0, 20.0]]),
             np.array([90.0, 89.96]), np.array([4.0, 4.0]), rules)
    assert abs(h[23, 21] - (89.96 + 7.0)) < 1e-3, h[23, 21]   # one vertex up its bank


def test_join_point_finds_the_nearest_point_on_another_course():
    others = [np.array([[0.0, 10.0], [10.0, 10.0]]),       # a segment 3 below the end
              np.array([[20.0, 0.0], [20.0, 20.0]])]       # a segment 15 away
    got = bw.join_point((4.0, 7.0), others, 5.0)
    assert np.allclose(got, [4.0, 10.0]), got                 # the foot of the perpendicular
    got = bw.join_point((12.0, 13.0), others, 5.0)
    assert np.allclose(got, [10.0, 10.0]), got                # past the segment's end: its end
    assert bw.join_point((4.0, 7.0), others, 2.9) is None      # out of reach


def test_river_mouth_only_widens_into_the_sea():
    m = bw.river_mouth(10, 4, True)
    assert np.allclose(m, [0, 0, 0, 0, 0, 0, 0, 0.25, 0.5, 0.75]), m
    assert not bw.river_mouth(10, 4, False).any()              # an inland end: 0 everywhere


def test_water_line_never_rises_over_the_joined_stretch():
    w = bw.join_water(np.array([10.0, 9.0, 8.0, 8.5, 9.5]), 3)
    assert np.allclose(w, [10.0, 9.0, 8.0, 8.0, 8.0]), w


# --- the patchwork (owner 2026-09-19) ------------------------------------------------

def test_hash01_is_fixed_and_in_range():
    a = bw.hash01(np.arange(1000), 7)
    assert np.array_equal(a, bw.hash01(np.arange(1000), 7))
    assert a.min() >= 0.0 and a.max() < 1.0
    assert not np.array_equal(a, bw.hash01(np.arange(1000), 8)), "the salt changes the draw"
    assert 0.4 < a.mean() < 0.6


def test_field_cells_are_strips_with_hedged_edges():
    ys, xs = np.mgrid[0:200, 0:200].astype(np.float64)
    fid, edge = bw.field_cells(xs, ys, 20.0, 2.2, np.zeros(xs.shape))
    n = len(np.unique(fid))
    # 200x200 over cells ~20 across: about 100 fields
    assert 50 < n < 160, n
    # a field is longer (along x, angle 0) than wide
    one = fid == fid[100, 100]
    yy, xx = np.nonzero(one)
    assert (xx.max() - xx.min()) > (yy.max() - yy.min()), "stretched along its strip"
    # the edge distance is 0 on a border and grows inside
    assert edge.min() < 0.5 and edge.max() > 3.0
    border = fid[:, 1:] != fid[:, :-1]
    assert edge[:, 1:][border].mean() < 1.5


def test_pick_crop_follows_the_shares():
    crops = [(35.0, 3, None), (30.0, 1, None), (20.0, 5, None), (15.0, 1, None)]
    idx = bw.pick_crop(np.linspace(0, 0.999, 1000), crops)
    counts = np.bincount(idx, minlength=4)
    assert np.allclose(counts, [350, 300, 200, 150], atol=2), counts


def test_the_footprint_grows_with_the_square_root_of_the_people():
    rules = {"footprint_m_per_sqrt_pop": 2.5, "footprint_min_m": 90.0, "footprint_max_m": 900.0}
    assert bw.footprint_radius_m(10000, rules) == 250.0
    assert bw.footprint_radius_m(10, rules) == 90.0, "the floor"
    assert bw.footprint_radius_m(1e7, rules) == 900.0, "the ceiling"


def test_the_fields_table_loads_with_its_textures():
    f = bw.load_fields(os.path.join(bw.ROOT, "data", "map3d_fields.csv"), bw.TEXTURE_KEYS)
    assert "*" in f and "grain" in f, sorted(f)
    for focus, e in f.items():
        assert e["reach"] > 0, focus
        for share, tex, tint in e["crops"]:
            assert share > 0 and 0 <= tex < bw.NT
            assert np.all(tint <= 1.0), "a tint can only darken the colour map"


def test_the_field_map_packs_colour_and_direction():
    ftint = np.ones((4, 6, 3), dtype=np.float16)
    ftint[0:2, 0:2] = 0.5          # one field texel, a half-dark crop
    fangle = np.zeros((4, 6), dtype=np.float16)
    fangle[:, 3:] = 0.75           # the second estate's direction
    m = bw.field_map(ftint, fangle, 2)
    assert m.shape == (2, 3, 4) and m.dtype == np.uint8
    assert tuple(m[0, 0, :3]) == (128, 128, 128)
    assert tuple(m[1, 2, :3]) == (255, 255, 255), "no field: the colour untouched"
    assert m[0, 0, 3] == 0 and m[0, 2, 3] == 191, "the direction sampled, not averaged"


def test_footprint_radius_agrees_between_the_two_modules():
    """bake_houses keeps its own copy so it can stand alone; the two must
    never drift."""
    import bake_houses
    import bake_world
    rules = {"footprint_m_per_sqrt_pop": 2.5, "footprint_min_m": 90, "footprint_max_m": 900}
    for pop in (0, 1, 600, 4900, 52000, 10**7):
        assert bake_houses.footprint_radius_m(pop, rules) == \
               bake_world.footprint_radius_m(pop, rules)


if __name__ == "__main__":
    for name, fn in sorted(globals().items()):
        if name.startswith("test_") and callable(fn):
            fn()
            print("ok", name)
