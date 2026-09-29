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
    rows, _ = _load()
    assert set(np.unique(rows[:, 5]).astype(int)) <= set(bake_trees.KINDS.values())
