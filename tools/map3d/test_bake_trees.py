"""The woods' bake (tools/map3d/bake_trees.py) over the BUILT pack: no clump
in the water, on a settlement or up a cliff — the same structural "never"
bake_houses keeps. Skipped where the pack has no build (a fresh clone)."""
import csv
import json
import os

import numpy as np
import pytest

import bake_trees
from packs import default_pack, map3d_dir

BAKE = os.path.join(map3d_dir(default_pack()), "bake")
pytestmark = pytest.mark.skipif(not os.path.exists(os.path.join(BAKE, "trees.bin")),
                                reason="no built pack (tools/map3d/build_pack.sh, then bake_trees.py)")


def _load():
    rows = np.fromfile(os.path.join(BAKE, "trees.bin"), dtype=np.float32).reshape(-1, 6)
    world = json.load(open(os.path.join(BAKE, "world.json")))
    return rows, world


def test_every_clump_stands_on_land():
    rows, world = _load()
    rules, _ = bake_trees.load_rules()
    low = rows[:, 1] < world["sea_y"] + rules["min_above_sea_m"] - 0.5
    assert not low.any(), "%d clumps at or under the water line, first at %s" % (low.sum(), rows[low][:1])


def test_no_clump_stands_among_the_houses():
    rows, _ = _load()
    rules, _ = bake_trees.load_rules()
    clear = rules["house_clear_m"] - 25.0   # the house mask is a square of vertices
    cell = 100.0
    grid = {}
    with open(os.path.join(BAKE, "houses.csv")) as f:
        for r in csv.DictReader(f):
            x, z = float(r["x_m"]), float(r["z_m"])
            grid.setdefault((int(x // cell), int(z // cell)), []).append((x, z))
    bad = 0
    for x, z in rows[:, [0, 2]]:
        gx, gz = int(x // cell), int(z // cell)
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                for hx, hz in grid.get((gx + dx, gz + dz), ()):
                    if (hx - x) ** 2 + (hz - z) ** 2 < clear * clear:
                        bad += 1
    assert bad == 0, "%d clumps inside a settlement" % bad


def test_kinds_are_known():
    # the kind column is a species of data/screens/map3d/map3d_tree_species.csv
    rows, _ = _load()
    assert set(np.unique(rows[:, 5]).astype(int)) <= {s["kind"] for s in bake_trees.load_species()}


def test_bankside_rows_stand_off_the_water_on_both_banks():
    # a straight river along x at z = 500 m, 40 m wide, every offer kept
    rules = {"riparian_spacing_m": 20.0, "riparian_gap_m": 18.0, "riparian_band_m": 14.0,
             "riparian_chance": 1.0}
    ok = np.ones((60, 60), bool)
    run = np.ones((60, 60), np.float32)
    course = ([(100.0, 500.0), (1000.0, 500.0)], np.array([40.0, 40.0]))
    xz = bake_trees.riparian([course], ok, run, np.random.default_rng(1), rules, 20.0)
    off = np.abs(xz[:, 1] - 500.0)
    assert len(xz) == 2 * 45, len(xz)                            # 900 m / 20 m, each bank
    assert off.min() >= 20.0 + 18.0 - 1e-6 and off.max() <= 20.0 + 18.0 + 14.0 + 1e-6
    assert (xz[:, 1] > 500.0).sum() == (xz[:, 1] < 500.0).sum()  # both banks alike


def test_bankside_rows_skip_forbidden_ground():
    rules = {"riparian_spacing_m": 20.0, "riparian_gap_m": 18.0, "riparian_band_m": 14.0,
             "riparian_chance": 1.0}
    ok = np.zeros((60, 60), bool)
    run = np.ones((60, 60), np.float32)
    course = ([(100.0, 500.0), (1000.0, 500.0)], np.array([40.0, 40.0]))
    assert len(bake_trees.riparian([course], ok, run, np.random.default_rng(1), rules, 20.0)) == 0


def test_the_poisson_set_keeps_its_spacing_and_is_the_same_every_run():
    # owner 2026-10-10 (树木有点太密集了): a blue-noise set, no two clumps nearer than r
    a = bake_trees.poisson_disk(600.0, 400.0, 25.0, np.random.default_rng(5), 4)
    b = bake_trees.poisson_disk(600.0, 400.0, 25.0, np.random.default_rng(5), 4)
    assert np.array_equal(a, b), "seeded: the same call plants the same set"
    d = np.hypot(a[:, None, 0] - a[None, :, 0], a[:, None, 1] - a[None, :, 1])
    np.fill_diagonal(d, np.inf)
    assert d.min() >= 25.0 - 1e-3, d.min()
    assert (a[:, 0] >= 0).all() and (a[:, 0] < 600).all() and (a[:, 1] >= 0).all() and (a[:, 1] < 400).all()
    # near the densest packing (~0.7 / r^2): 240 000 m^2 / 625 m^2 * 0.5 at the least
    assert len(a) > 0.5 * 600 * 400 / 625, len(a)
    assert not np.array_equal(a, bake_trees.poisson_disk(600.0, 400.0, 25.0, np.random.default_rng(6), 4))


def test_the_baked_wood_keeps_its_spacing():
    rows, _ = _load()
    rules, _ = bake_trees.load_rules()
    by = {s["kind"]: s for s in bake_trees.load_species()}
    wood = np.array([by[int(k)]["habit"] in (bake_trees.HABITS["wood"], bake_trees.HABITS["lone"])
                     for k in rows[:, 5]])
    xz = rows[wood][:, [0, 2]].astype(np.float64)
    cell = rules["poisson_r_m"]
    keys = np.floor(xz / cell).astype(np.int64)
    order = np.lexsort((keys[:, 1], keys[:, 0]))
    xz, keys = xz[order], keys[order]
    grid = {}
    for i, k in enumerate(map(tuple, keys)):
        grid.setdefault(k, []).append(i)
    near = 0
    for (gx, gz), idx in grid.items():
        pts = xz[idx]
        for dx in (-1, 0, 1):
            for dz in (-1, 0, 1):
                other = grid.get((gx + dx, gz + dz))
                if other is None:
                    continue
                q = xz[other]
                d = np.hypot(pts[:, None, 0] - q[None, :, 0], pts[:, None, 1] - q[None, :, 1])
                near += int(((d > 0) & (d < cell - 0.05)).sum())
    assert near == 0, "%d wood clump pairs nearer than poisson_r_m" % (near // 2)


def _species_rows():
    return bake_trees.load_species()


def test_species_follow_the_ground():
    # owner 2026-10-10 (树木的品种过于单一): the species by the ground under a clump
    sp = _species_rows()
    names = {s["kind"]: s["name"] for s in sp}
    rules, _ = bake_trees.load_rules()
    n = 400
    rng = np.random.default_rng(3)
    x, z = rng.random(n) * 20000.0, rng.random(n) * 20000.0
    wood = np.zeros(n, np.int32)

    def pick(biome, h, habit=wood):
        shares = np.zeros((n, 16), np.float32)
        shares[:, biome - 1] = 1.0
        k = bake_trees.pick_species(sp, habit, shares, np.full(n, h), x, z, rules, 11)
        return [names[int(i)] for i in k]

    taiga_high = pick(9, 0.8)
    assert taiga_high.count("spruce") > n * 0.6, "spruce holds the taiga toward the tree line"
    lowland = pick(6, 0.1)
    mix = {s: lowland.count(s) for s in set(lowland)}
    assert len([s for s in ("oak", "beech", "lime", "hornbeam") if mix.get(s, 0) > n * 0.03]) >= 3, mix
    assert not ({"spruce", "pine"} & set(lowland)), "no conifers in the deciduous lowland"
    wet = pick(12, 0.05)
    assert wet.count("birch") > n * 0.5, "birch carr in the wetland"
    bank = pick(6, 0.1, np.full(n, bake_trees.HABITS["bank"]))
    assert set(bank) == {"bankside"}
    hedge = pick(6, 0.1, np.full(n, bake_trees.HABITS["hedge"]))
    assert set(hedge) <= {"hedge_hornbeam", "hedge_oak"}
    # the same call is the same pick
    assert pick(6, 0.1) == lowland


def test_waiting_species_are_never_planted():
    rows, _ = _load()
    enabled = {s["kind"] for s in bake_trees.load_species() if s["enabled"]}
    assert set(np.unique(rows[:, 5]).astype(int)) <= enabled


def test_lone_clumps_gather_into_patches():
    """lone_chance (critic 2026-10-13): lone clumps on open land keep to
    parkland patches of a slow noise, lone_gain times as dense there, the
    land between them left open; lone_gain 0 is the old even scatter."""
    rules = {"lone_chance": 0.04, "lone_gain": 2.5, "lone_wave_m": 700.0,
             "lone_cut": 0.55, "lone_soft": 0.15}
    open_land = np.ones((120, 160), np.float32)
    c = bake_trees.lone_chance(rules, open_land, 160, 120, 20.0)
    assert c.max() <= 0.04 * 2.5 + 1e-6
    assert (c == 0).mean() > 0.3, "open pasture between the patches"
    assert (c > 0.09).any(), "dense parkland in the patches"
    even = bake_trees.lone_chance(dict(rules, lone_gain=0.0), open_land, 160, 120, 20.0)
    assert np.allclose(even, 0.04)
