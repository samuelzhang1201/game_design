# Settlement House Clusters (3D map) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 3D map's settlement dots with clusters of real house meshes standing on the Terrain3D ground, sized by population, irregular around a centre landmark, thinning outward into an empty buffer ring of built earth.

**Architecture:** House positions are generated in the bake's Python (`tools/map3d/bake_houses.py`, called by `sow_patchwork`), beside the village footprints that already know the land mask, population and farm mask — so "never in the sea" is structural, not a check. The bake writes `bake/houses.csv` (world metres, no `y`); a pure `Map3DHouses` picks which houses are shown; `Map3DLayerHouses` builds one `MultiMesh` per house type, rebuilt only when the camera moves far enough. Meshes come from a headless Blender generator and are committed as small `.glb` files.

**Tech Stack:** Godot 4.7 + typed GDScript, GUT; Python 3 + numpy/Pillow (the existing bake); Blender 5.2 headless (glTF export); Terrain3D.

**Spec:** `docs/superpowers/specs/2026-09-20-map3d-settlement-houses-design.md`

## Global Constraints

- **Design values live in CSVs, never hardcoded in scripts.** Add columns/rows rather than embedding constants (`CLAUDE.md`).
- **Typed GDScript everywhere:** type hints on vars, params and returns.
- **No script under `scripts/map3d/` may reference the `Game` autoload.** `tests/map3d/test_map3d_preview.gd` scans for `Game.` and fails on a hit; a layer takes what it needs from `Map3DContext`.
- **Determinism:** the bake's placement is seeded from the burg code; two runs must be byte-identical. No `Time.get_*` and no unseeded `randi()` in anything the simulation reads.
- **No base plates, no ground discs, no hard-edged rims.** `.claude/skills/visual-review/taste.md`: the grass disc under the 2026-09-16 3D towns was the first thing rejected.
- **`./run_tests.sh` must report the expected error count** — "Errors 2" while `addons/gdai-mcp-plugin-godot/gdai_mcp_plugin.gdextension` exists, 0 without it. Any other count is a failure.
- **Every `world_*.png` is DATA** — never re-imported as VRAM compressed. Nothing in this plan touches their `.import` files.
- **Branch:** `map3d-settlement-houses` (already created; the spec is committed there as `9b2e2d3`).
- Exact values from the spec that tasks must not invent: `map3d_zoom_min_m` stays **800**; `house_radius_ratio` starts at **0.60**; roof colour is **data** (`data/terrain_palette.csv`), not baked into the mesh; landmark by burg `group` is capital → palace, city → church with tower, town / fort → church, village → chapel.

## Phased order (why the dots come out last)

`marker_px` — the dots' size — is load-bearing beyond the dots: it is the click
reach in `scripts/map3d/map3d_picker.gd:76,81`, the rect in
`scripts/map3d/map3d_context.gd:253`, the obstacle the landmark marks avoid,
and it is asserted in four test files. So:

- **Phase A (Tasks 1–7):** houses are ADDED. The dots stay. Nothing breaks.
- **Task 8:** show the owner.
- **Phase B (Tasks 9–11):** the dots come out and the pick reach is re-homed on the cluster.

## File structure

**Bake (Python)**
| File | Responsibility |
|---|---|
| `tools/map3d/bake_houses.py` *(new)* | Pure placement: candidates, filters, ranking. No I/O, no numpy image loading — takes masks, returns rows. Importable and unit-testable alone. |
| `tools/map3d/bake_world.py` *(modify)* | Calls it from `sow_patchwork`, writes `bake/houses.csv`, fades the block noise inside `r_house`. |
| `tools/map3d/test_bake_houses.py` *(new)* | Unit tests for the placement. |

**Models (Blender)**
| File | Responsibility |
|---|---|
| `tools/map3d/make_houses.py` *(new)* | Headless Blender generator → `assets/map3d_houses/<type>.glb` + `houses.json`. |
| `assets/map3d_houses/*` *(new, committed)* | The meshes. |
| `data/map3d_houses.csv` *(new)* | The type table. |

**Runtime (Godot)**
| File | Responsibility |
|---|---|
| `scripts/map3d/map3d_houses.gd` *(new)* | `Map3DHouses`, pure `RefCounted`: parse `houses.csv`, how many houses a burg shows, which burgs are in range, bucket by type. Headless-testable. |
| `scripts/map3d/map3d_layer_houses.gd` *(new)* | `Map3DLayerHouses`, `Node3D`: one `MultiMesh` per type, height sampling, materials, budget. |
| `scenes/map3d/world_map_3d.tscn` *(modify)* | The authored `Viewport/Houses` node. |
| `scenes/map3d/materials/house_wall.tres`, `house_roof.tres` *(new)* | Shader/texture/priority only — every tuned number bound at load. |
| `scripts/map3d/map3d_context.gd` *(modify)* | `houses()` accessor + `people_of_burg()`. |
| `scripts/map3d/map3d_view.gd` *(modify)* | Wire the layer; rebuild on camera move. |
| `scripts/map3d/map3d_world_loader.gd` *(modify)* | `steps_hash()` += `data/map3d_houses.csv`. |
| `scripts/engine/data_repository.gd` *(modify)* | Load `data/map3d_houses.csv`. |

**Phase B**
`scripts/map3d/map3d_layer_settlements.gd`, `map3d_picker.gd`, `map3d_context.gd`, `map3d_view.gd`, `settlement_ring.gdshader`, `data/map3d_settlements.csv`, `tests/map3d/test_map3d_view.gd`, `test_map3d_layers.gd`, `test_map3d_heights.gd`, `test_map3d_api.gd`.

---

### Task 1: Data tables and repository loading

**Files:**
- Create: `data/map3d_houses.csv`
- Modify: `data/map3d_bake.csv` (append `house_*` rows), `data/balance.csv` (append `map3d_house_*` rows), `data/graphics_quality.csv` (new `house_budget` column), `data/terrain_palette.csv` (roof colours)
- Modify: `scripts/engine/data_repository.gd:45-47` (declare), `:475-477` area (load)
- Test: `tests/map3d/test_map3d_houses_data.gd`

**Interfaces:**
- Consumes: nothing.
- Produces: `DataRepository.map3d_houses: Dictionary` keyed by `type` → the row `Dictionary` (string values, as every other `_load_if_present` sink stores). Balance keys `map3d_house_view_m`, `map3d_house_fade_m`, `map3d_house_rebuild_move_m`, `map3d_house_sink_m`. `data/map3d_bake.csv` keys `house_radius_ratio`, `house_core_ratio`, `house_barn_ratio`, `house_spacing_m`, `house_density_gamma`, `house_foot_min`, `house_max_slope`, `house_shore_min_m`, `house_port_shore_min_m`, `house_min`, `house_edge_scale`, `house_yaw_jitter_deg`, `house_road_align_m`, `house_people_per_house`, `house_max_capital`, `house_max_city`, `house_max_town`, `house_max_fort`, `house_max_village`. `graphics_quality.csv` column `house_budget`.

- [ ] **Step 1: Write the failing test**

Create `tests/map3d/test_map3d_houses_data.gd`:

```gdscript
extends GutTest
## The house type table and its tuning keys (spec 2026-09-20 §5). The meshes
## themselves are asserted by test_map3d_houses_meshes.gd once Task 3 has
## generated them.

const ROLES := ["landmark", "house", "barn"]
const GROUPS := ["capital", "city", "fort", "town", "village"]
const BAKE_KEYS := ["house_radius_ratio", "house_core_ratio", "house_barn_ratio",
	"house_spacing_m", "house_density_gamma", "house_foot_min", "house_max_slope",
	"house_shore_min_m", "house_port_shore_min_m", "house_min", "house_edge_scale",
	"house_yaw_jitter_deg", "house_road_align_m", "house_people_per_house",
	"house_max_capital", "house_max_city", "house_max_town", "house_max_fort",
	"house_max_village"]
const BAL_KEYS := ["map3d_house_view_m", "map3d_house_fade_m",
	"map3d_house_rebuild_move_m", "map3d_house_sink_m"]


func before_all() -> void:
	Game.start_campaign(42)


func test_the_table_loads_and_every_row_is_well_formed() -> void:
	var rows: Dictionary = Game.data.map3d_houses
	assert_gt(rows.size(), 6, "the type table has a usable set of houses")
	for type: String in rows:
		var r: Dictionary = rows[type]
		assert_true(ROLES.has(String(r["role"])), type + " has a known role")
		assert_gt(float(r["weight"]), 0.0, type + " has a positive weight")
		assert_gt(float(r["footprint_m"]), 0.0, type + " has a footprint")
		assert_gt(float(r["height_m"]), 0.0, type + " has a height")
		assert_true(GROUPS.has(String(r["min_group"])), type + " names a settlement group")
		assert_true(Game.data.terrain_palette.has(String(r["roof"])),
			type + "'s roof colour is in terrain_palette.csv")


func test_every_settlement_group_can_be_filled() -> void:
	# a village must find a landmark, a house and a barn, or it draws nothing
	for group: String in GROUPS:
		for role: String in ROLES:
			var found := false
			for type: String in Game.data.map3d_houses:
				var r: Dictionary = Game.data.map3d_houses[type]
				if String(r["role"]) == role and _group_allows(group, String(r["min_group"])):
					found = true
			assert_true(found, group + " can be given a " + role)


func test_the_tuning_keys_exist() -> void:
	for k: String in BAKE_KEYS:
		assert_true(Game.data.map3d_bake.has(k), "map3d_bake.csv has " + k)
	for k: String in BAL_KEYS:
		assert_true(Game.data.balance.has(k), "balance.csv has " + k)
	for tier: String in Game.data.graphics_quality:
		assert_true(Game.data.graphics_quality[tier].has("house_budget"),
			tier + " has a house_budget")


func test_the_buffer_ring_is_not_empty() -> void:
	# the whole point of §4: houses stop well inside the built ground
	var ratio: float = Game.data.map3d_bake["house_radius_ratio"]
	assert_lt(ratio, 0.85, "houses stop well inside the footprint")
	assert_gt(ratio, 0.3, "the cluster is not a dot in the middle of bare earth")


func _group_allows(group: String, min_group: String) -> bool:
	var order := GROUPS.duplicate()
	order.reverse()   # village .. capital, smallest first
	return order.find(group) >= order.find(min_group)
```

- [ ] **Step 2: Run it and watch it fail**

```
./run_tests.sh
```

Expected: failures in `test_map3d_houses_data.gd` — `map3d_houses` is not a property of `DataRepository`, and the keys are missing.

- [ ] **Step 3: Create `data/map3d_houses.csv`**

```csv
type,mesh,role,weight,footprint_m,height_m,roof,min_group,notes
cottage_a,res://assets/map3d_houses/cottage_a.glb,house,1.0,7,5.5,house_roof_thatch,village,"a one-room thatched cottage; the commonest building anywhere"
cottage_b,res://assets/map3d_houses/cottage_b.glb,house,0.9,8,5.5,house_roof_thatch,village,a thatched cottage with a lean-to
cottage_c,res://assets/map3d_houses/cottage_c.glb,house,0.7,6,5.0,house_roof_thatch,village,the smallest cottage
townhouse_a,res://assets/map3d_houses/townhouse_a.glb,house,0.8,9,8.5,house_roof_tile,town,"a two-storey tiled house; only from a town upward"
townhouse_b,res://assets/map3d_houses/townhouse_b.glb,house,0.7,10,9.0,house_roof_tile,town,a tiled house with a jettied upper floor
townhouse_c,res://assets/map3d_houses/townhouse_c.glb,house,0.5,11,10.0,house_roof_tile,city,a tall merchant's house
longhouse,res://assets/map3d_houses/longhouse.glb,house,0.4,16,6.0,house_roof_thatch,village,a long hall with byre
workshop,res://assets/map3d_houses/workshop.glb,house,0.35,10,6.5,house_roof_tile,town,"a workshop with an open front"
barn,res://assets/map3d_houses/barn.glb,barn,1.0,13,7.0,house_roof_thatch,village,"the outlying kind: barns and byres sit in the thinning ring"
byre,res://assets/map3d_houses/byre.glb,barn,0.8,9,4.5,house_roof_thatch,village,a low byre
chapel,res://assets/map3d_houses/chapel.glb,landmark,1.0,10,9.0,house_roof_tile,village,a village's centre
church,res://assets/map3d_houses/church.glb,landmark,1.0,18,13.0,house_roof_tile,town,"a town's and a fort's centre"
church_tower,res://assets/map3d_houses/church_tower.glb,landmark,1.0,22,24.0,house_roof_tile,city,"a city's centre: the tower is the silhouette that reads at 9 px"
palace,res://assets/map3d_houses/palace.glb,landmark,1.0,34,22.0,house_roof_tile,capital,"a capital's centre"
```

- [ ] **Step 4: Append the roof colours to `data/terrain_palette.csv`**

Match the file's existing column order (read its header first; it is `key,color,notes` style). Add:

```csv
house_roof_thatch,#9A8459,"3D MAP houses (spec 2026-09-20 §2): weathered thatch. At 9-17 px the roof colour is most of what a house says, so it is data"
house_roof_tile,#8C5A45,3D MAP houses: fired clay tile
house_wall,#C8BCA6,3D MAP houses: limewashed daub and plaster between the timbers
```

- [ ] **Step 5: Append the bake tuning to `data/map3d_bake.csv`**

Match the file's `key,value,notes` shape:

```csv
house_radius_ratio,0.60,"3D bake houses (spec 2026-09-20 §4): houses fill this share of the settlement's footprint radius. The ring from here out to the footprint edge is built ground with NO houses — the buffer the owner asked for (定居点周边和地图上的地形要有一定距离的缓冲过渡). Bracketed for the owner in Task 11"
house_core_ratio,0.35,3D bake houses: the share of the house radius that is the dense core
house_barn_ratio,0.75,3D bake houses: past this share of the house radius only barn-role types are placed
house_spacing_m,22,3D bake houses: metres between candidate slots on the jittered grid
house_density_gamma,1.4,"3D bake houses: density falls as (1 - t) ^ this from the core to the house radius; higher thins the edge faster"
house_foot_min,0.55,3D bake houses: the footprint mask must be at least this for a candidate to be kept
house_max_slope,0.38,"3D bake houses: the largest ground gradient (rise over run) a house may stand on — this is what keeps houses off carved river banks and cliffs"
house_shore_min_m,25,3D bake houses: a house stays this many metres from water
house_port_shore_min_m,6,3D bake houses: a burg with is_port 1 may build this close to the water instead
house_min,4,3D bake houses: the fewest houses a settlement keeps; below it the density draw is relaxed (never the land, water or slope tests)
house_edge_scale,0.82,3D bake houses: the scale the outermost houses taper to, so the cluster ends by getting smaller rather than by stopping
house_yaw_jitter_deg,35,"3D bake houses: a house faces the cluster centre (or the nearest route) plus this much jitter. NEVER uniform random — the owner rejected hash-scattered marks on the 2D estates as unreasonable"
house_road_align_m,40,3D bake houses: a house within this distance of a route point faces the route instead of the centre
house_people_per_house,160,"3D bake houses: how many people one shown house stands for; the runtime shows people / this many houses by rank, so a settlement that grows sprouts more houses with no re-bake"
house_max_capital,220,3D bake houses: the most houses a capital's cluster holds
house_max_city,150,3D bake houses: the most houses a city's cluster holds
house_max_town,80,3D bake houses: the most houses a town's cluster holds
house_max_fort,60,3D bake houses: the most houses a fort's cluster holds
house_max_village,24,3D bake houses: the most houses a village's cluster holds
```

- [ ] **Step 6: Append the runtime tuning to `data/balance.csv`**

```csv
map3d_house_view_m,9000,"3D MAP houses (spec 2026-09-20 §3): a settlement farther than this from the camera is not instanced at all — not culled after the fact"
map3d_house_fade_m,1500,3D MAP houses: the distance over which a cluster fades in before map3d_house_view_m
map3d_house_rebuild_move_m,300,"3D MAP houses: the camera must move this far before the house MultiMeshes are rebuilt — cut once per camera pose, never per frame"
map3d_house_sink_m,0.35,"3D MAP houses: every instance is sunk this far so the wall foot bites into sloped ground. NO base plate, ever (taste.md: the grass disc under the 2026-09-16 3D towns was the first thing rejected)"
```

- [ ] **Step 7: Add the `house_budget` column to `data/graphics_quality.csv`**

Insert the column before `notes` in the header and give every row a value: `low` 1200, `medium` 2500, `high` 5000, `ultra` 8000. Append to each row's `notes` the sentence `Houses: at most <N> instances at once.`

- [ ] **Step 8: Load the table in `DataRepository`**

Beside `map3d_settlements` (`scripts/engine/data_repository.gd:45-47`) declare:

```gdscript
## data/map3d_houses.csv rows keyed by type: the 3D MAP's house meshes,
## their role, weight, size and roof colour (spec 2026-09-20 §2).
var map3d_houses: Dictionary = {}
```

And beside its loader (near `:475`):

```gdscript
	if not _load_if_present("res://data/map3d_houses.csv",
			["type", "mesh", "role", "weight", "footprint_m", "height_m", "roof", "min_group"],
			func(r): map3d_houses[String(r["type"])] = r):
		return false
```

- [ ] **Step 9: Run the tests**

```
./run_tests.sh
```

Expected: `test_map3d_houses_data.gd` passes; the suite reports its expected error count and no new failures.

- [ ] **Step 10: Commit**

```bash
git add data/map3d_houses.csv data/map3d_bake.csv data/balance.csv \
        data/graphics_quality.csv data/terrain_palette.csv \
        scripts/engine/data_repository.gd tests/map3d/test_map3d_houses_data.gd
git commit -m "feat(map3d): the house type table and its tuning keys

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: `tools/map3d/bake_houses.py` — the placement, pure Python

**Files:**
- Create: `tools/map3d/bake_houses.py`
- Test: `tools/map3d/test_bake_houses.py`

**Interfaces:**
- Consumes: `data/map3d_bake.csv` keys from Task 1 (passed in as the `rules` dict the bake already builds).
- Produces:
  ```python
  place(burg, rules, types, foot, land, height, k, vw, vh, routes=None) -> list[dict]
  ```
  Each row: `{"burg_code": str, "rank": int, "x_m": float, "z_m": float, "yaw_deg": float, "type": str, "scale": float}`, `x_m`/`z_m` **relative to the burg centre** (the caller adds the world origin — keeping this function free of world-frame knowledge makes it testable on a 40×40 toy grid). Also `house_count(burg, rules) -> int` and `max_houses(group, rules) -> int`.

- [ ] **Step 1: Write the failing test**

Create `tools/map3d/test_bake_houses.py`:

```python
"""Unit tests for the house placement (spec 2026-09-20 §1).

  python3 -m pytest tools/map3d/test_bake_houses.py
"""
import numpy as np
import pytest

from bake_houses import place, house_count, max_houses

VW = VH = 64
K = 2.5           # vertices per pack px, as bake_world.py's k
CENTRE = 32.0     # vertex coords of the toy burg

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


CENTRE_COL = 32


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
```

- [ ] **Step 2: Run it and watch it fail**

```
cd tools/map3d && python3 -m pytest test_bake_houses.py -v
```

Expected: collection error, `ModuleNotFoundError: No module named 'bake_houses'`.

- [ ] **Step 3: Write `tools/map3d/bake_houses.py`**

```python
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
    x0, x1 = max(int(vx) - rad, 0), min(int(vx) + rad + 1, vw)
    y0, y1 = max(int(vy) - rad, 0), min(int(vy) + rad + 1, vh)
    if x0 >= x1 or y0 >= y1:
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
```

- [ ] **Step 4: Run the tests**

```
cd tools/map3d && python3 -m pytest test_bake_houses.py -v
```

Expected: all pass. If `test_steep_ground_is_refused` fails because the landmark is also refused, note that the landmark is deliberately pinned to the burg's own point and never slope-tested — the assertion `len(rows) == 1` encodes that; do not "fix" it by slope-testing the landmark.

- [ ] **Step 5: Commit**

```bash
git add tools/map3d/bake_houses.py tools/map3d/test_bake_houses.py
git commit -m "feat(map3d): house placement — clustered, ranked, never in the sea

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: `tools/map3d/make_houses.py` — the meshes, committed

**Files:**
- Create: `tools/map3d/make_houses.py`
- Create (generated, committed): `assets/map3d_houses/*.glb`, `assets/map3d_houses/houses.json`
- Test: `tests/map3d/test_map3d_houses_meshes.gd`

**Interfaces:**
- Consumes: `data/map3d_houses.csv` (Task 1) — one `.glb` per `type`, at the path the `mesh` column names.
- Produces: `assets/map3d_houses/<type>.glb`, each mesh **origin at the ground centre of its footprint**, **+Z forward**, **+Y up**, sized in metres to the row's `footprint_m` / `height_m`; `assets/map3d_houses/houses.json` mapping `type` → `{"footprint_m": f, "height_m": h, "tris": n}`.

- [ ] **Step 1: Write the failing test**

Create `tests/map3d/test_map3d_houses_meshes.gd`:

```gdscript
extends GutTest
## Every house type names a mesh that exists and loads, at the size its row
## claims (spec 2026-09-20 §2). The same shape as the existing
## "every named texture exists" tests.

const MANIFEST := "res://assets/map3d_houses/houses.json"


func before_all() -> void:
	Game.start_campaign(42)


func test_every_type_has_a_mesh_on_disk() -> void:
	for type: String in Game.data.map3d_houses:
		var path := String(Game.data.map3d_houses[type]["mesh"])
		assert_true(ResourceLoader.exists(path), type + " has a mesh at " + path)


func test_every_mesh_loads_and_carries_geometry() -> void:
	for type: String in Game.data.map3d_houses:
		var path := String(Game.data.map3d_houses[type]["mesh"])
		var scene := load(path) as PackedScene
		assert_not_null(scene, type + " loads as a PackedScene")
		if scene == null:
			continue
		var node := scene.instantiate()
		var mesh := _first_mesh(node)
		assert_not_null(mesh, type + " holds a mesh")
		if mesh != null:
			assert_gt(mesh.get_surface_count(), 0, type + " has a surface")
		node.free()


func test_every_mesh_stands_on_its_origin_at_the_claimed_size() -> void:
	for type: String in Game.data.map3d_houses:
		var row: Dictionary = Game.data.map3d_houses[type]
		var scene := load(String(row["mesh"])) as PackedScene
		if scene == null:
			continue
		var node := scene.instantiate()
		var mesh := _first_mesh(node)
		if mesh != null:
			var aabb := mesh.get_aabb()
			assert_almost_eq(aabb.position.y, 0.0, 0.05,
				type + " stands ON its origin — no base plate, nothing sunk into the mesh")
			assert_almost_eq(aabb.size.y, float(row["height_m"]), 0.6,
				type + " is as tall as its row claims")
			assert_lt(maxf(aabb.size.x, aabb.size.z), float(row["footprint_m"]) + 0.6,
				type + " fits the footprint its row claims")
		node.free()


func test_the_manifest_covers_every_type() -> void:
	assert_true(FileAccess.file_exists(MANIFEST), "houses.json exists")
	var raw := FileAccess.get_file_as_string(MANIFEST)
	var man: Dictionary = JSON.parse_string(raw)
	assert_not_null(man, "houses.json parses")
	for type: String in Game.data.map3d_houses:
		assert_true(man.has(type), "houses.json knows " + type)


func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for c in node.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null
```

- [ ] **Step 2: Run it and watch it fail**

```
./run_tests.sh
```

Expected: `test_map3d_houses_meshes.gd` fails — no `.glb` exists.

- [ ] **Step 3: Write `tools/map3d/make_houses.py`**

A headless Blender generator. Follow the MCP server's rules that apply to any Blender script: look shader nodes up by **type**, never by name (`nodes["Principled BSDF"]` is None on a localized UI); never hardcode enum identifiers — read them from RNA first.

```python
"""Generate the 3D map's house meshes (spec 2026-09-20 §2).

  blender -b --factory-startup --python tools/map3d/make_houses.py

Reads data/map3d_houses.csv and writes one glTF per type into
assets/map3d_houses/, plus houses.json. Every mesh stands ON its origin
(min y = 0, centred on its footprint) and faces +Z, because
Map3DLayerHouses places it with a yaw and sinks it by map3d_house_sink_m —
a mesh that carries its own base plate or offset would defeat both.

Low poly on purpose: at the owner's 800 m closest zoom a house is 9-17 px,
where the silhouette and the roof colour are all that read.
"""
import csv
import json
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
TABLE = os.path.join(ROOT, "data", "map3d_houses.csv")
OUT = os.path.join(ROOT, "assets", "map3d_houses")
PALETTE = os.path.join(ROOT, "data", "terrain_palette.csv")


def hex_rgb(s):
    s = s.lstrip("#")
    return tuple(int(s[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def load_palette():
    out = {}
    with open(PALETTE) as f:
        for r in csv.DictReader(f):
            key = r.get("key") or r.get("name")
            col = r.get("color") or r.get("colour") or r.get("hex")
            if key and col and col.startswith("#"):
                out[key] = hex_rgb(col)
    return out


def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = next(n for n in mat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.85
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.2
    elif "Specular" in bsdf.inputs:
        bsdf.inputs["Specular"].default_value = 0.2
    return mat


def box(name, w, d, h, z=0.0):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, z + h / 2))
    ob = bpy.context.active_object
    ob.name = name
    ob.scale = (w / 2, d / 2, h / 2)
    bpy.ops.object.transform_apply(scale=True)
    return ob


def gable_roof(name, w, d, h, z, overhang=0.5):
    """A ridged roof as a 6-vertex prism: the silhouette that separates a
    house from a box at 12 px."""
    w2, d2 = w / 2 + overhang, d / 2 + overhang
    verts = [(-w2, -d2, z), (w2, -d2, z), (w2, d2, z), (-w2, d2, z),
             (0, -d2, z + h), (0, d2, z + h)]
    faces = [(0, 1, 4), (2, 3, 5), (1, 2, 5, 4), (3, 0, 4, 5), (0, 3, 2, 1)]
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    ob = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(ob)
    return ob


def hip_tower(name, w, h, z):
    """A square tower with a spire — a church or a palace's landmark mass."""
    body = box(name + "_body", w, w, h, z)
    spire_h = h * 0.55
    verts = [(-w / 2, -w / 2, z + h), (w / 2, -w / 2, z + h),
             (w / 2, w / 2, z + h), (-w / 2, w / 2, z + h), (0, 0, z + h + spire_h)]
    faces = [(0, 1, 4), (1, 2, 4), (2, 3, 4), (3, 0, 4)]
    mesh = bpy.data.meshes.new(name + "_spire")
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    spire = bpy.data.objects.new(name + "_spire", mesh)
    bpy.context.collection.objects.link(spire)
    return body, spire


# type -> a builder returning (wall objects, roof objects)
def build(type_name, fp, ht):
    """One house. `fp` is the footprint's longest side in metres, `ht` the
    total height including the roof."""
    walls, roofs = [], []
    if type_name.startswith("cottage") or type_name == "byre":
        wall_h = ht * 0.55
        w, d = fp * 0.8, fp * 0.6
        walls.append(box("wall", w, d, wall_h))
        roofs.append(gable_roof("roof", w, d, ht - wall_h, wall_h, overhang=0.35))
        if type_name == "cottage_b":
            walls.append(box("lean", w * 0.45, d * 0.5, wall_h * 0.7))
            walls[-1].location.x = w * 0.6
    elif type_name.startswith("townhouse") or type_name == "workshop":
        wall_h = ht * 0.68
        w, d = fp * 0.7, fp * 0.65
        walls.append(box("wall", w, d, wall_h))
        if type_name == "townhouse_b":
            jetty = box("jetty", w * 1.12, d * 1.12, wall_h * 0.35, wall_h * 0.6)
            walls.append(jetty)
        roofs.append(gable_roof("roof", w, d, ht - wall_h, wall_h, overhang=0.4))
    elif type_name == "longhouse":
        wall_h = ht * 0.5
        w, d = fp * 0.95, fp * 0.34
        walls.append(box("wall", w, d, wall_h))
        roofs.append(gable_roof("roof", w, d, ht - wall_h, wall_h, overhang=0.5))
    elif type_name == "barn":
        wall_h = ht * 0.45
        w, d = fp * 0.9, fp * 0.5
        walls.append(box("wall", w, d, wall_h))
        roofs.append(gable_roof("roof", w, d, ht - wall_h, wall_h, overhang=0.6))
    elif type_name in ("chapel", "church", "church_tower"):
        nave_h = ht * (0.32 if type_name == "church_tower" else 0.5)
        w, d = fp * 0.78, fp * 0.42
        walls.append(box("nave", w, d, nave_h))
        roofs.append(gable_roof("nave_roof", w, d, nave_h * 0.55, nave_h, overhang=0.35))
        tower_w = d * 0.72
        tower_h = ht * (0.82 if type_name == "church_tower" else 0.62)
        body, spire = hip_tower("tower", tower_w, tower_h, 0.0)
        body.location.x = -w * 0.5
        spire.location.x = -w * 0.5
        walls.append(body)
        roofs.append(spire)
    elif type_name == "palace":
        w, d = fp * 0.85, fp * 0.5
        wall_h = ht * 0.55
        walls.append(box("hall", w, d, wall_h))
        roofs.append(gable_roof("hall_roof", w, d, ht * 0.2, wall_h, overhang=0.6))
        for sx in (-1, 1):
            body, spire = hip_tower("wing%d" % sx, d * 0.5, ht * 0.72, 0.0)
            body.location.x = sx * w * 0.5
            spire.location.x = sx * w * 0.5
            walls.append(body)
            roofs.append(spire)
    else:
        raise SystemExit("make_houses: no builder for type %r" % type_name)
    return walls, roofs


def join_and_normalise(name, objs, fp, ht):
    """One object at the origin, min z = 0, no bigger than its claims."""
    for o in bpy.context.selected_objects:
        o.select_set(False)
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.active_object
    ob.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    lo = Vector((math.inf,) * 3)
    hi = Vector((-math.inf,) * 3)
    for v in ob.data.vertices:
        lo = Vector((min(lo[i], v.co[i]) for i in range(3)))
        hi = Vector((max(hi[i], v.co[i]) for i in range(3)))
    mid = Vector(((lo.x + hi.x) / 2, (lo.y + hi.y) / 2, lo.z))
    for v in ob.data.vertices:
        v.co -= mid
    span = max(hi.x - lo.x, hi.y - lo.y)
    tall = hi.z - lo.z
    s = min(fp / span if span > 0 else 1.0, ht / tall if tall > 0 else 1.0)
    for v in ob.data.vertices:
        v.co *= s
    return ob


def export(ob, path):
    for o in bpy.context.selected_objects:
        o.select_set(False)
    ob.select_set(True)
    bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB",
                              use_selection=True, export_yup=True,
                              export_apply=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    palette = load_palette()
    wall_rgb = palette.get("house_wall", (0.78, 0.74, 0.65))
    manifest = {}
    with open(TABLE) as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        t = r["type"]
        fp, ht = float(r["footprint_m"]), float(r["height_m"])
        clear()
        walls, roofs = build(t, fp, ht)
        wall_mat = material("wall", wall_rgb)
        roof_mat = material("roof", palette.get(r["roof"], (0.55, 0.35, 0.27)))
        for o in walls:
            o.data.materials.append(wall_mat)
        for o in roofs:
            o.data.materials.append(roof_mat)
        ob = join_and_normalise(t, walls + roofs, fp, ht)
        path = os.path.join(OUT, t + ".glb")
        export(ob, path)
        manifest[t] = {"footprint_m": fp, "height_m": ht, "tris": len(ob.data.polygons)}
        print("make_houses: %s -> %s (%d faces)" % (t, path, len(ob.data.polygons)))
    with open(os.path.join(OUT, "houses.json"), "w") as f:
        json.dump(manifest, f, indent=1, sort_keys=True)
    print("make_houses: %d types" % len(manifest))


main()
```

- [ ] **Step 4: Generate the meshes**

```
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
  --python tools/map3d/make_houses.py
```

If Blender is not at that path, find it (`ls /Applications | grep -i blender`) and use the real one. Expected: 14 lines of `make_houses: <type> -> ...`, then `make_houses: 14 types`.

- [ ] **Step 5: Let Godot import the new `.glb` files**

```
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit --editor 2>&1 | tail -5
```

This writes the `.import` sidecars. Verify: `ls assets/map3d_houses/*.glb.import | wc -l` prints 14.

- [ ] **Step 6: Run the tests**

```
./run_tests.sh
```

Expected: `test_map3d_houses_meshes.gd` passes. If a mesh trips the size assertion, adjust that type's `build()` proportions — **not** the test's tolerance.

- [ ] **Step 7: Commit (the meshes go in — see the spec §2)**

```bash
git add tools/map3d/make_houses.py assets/map3d_houses \
        tests/map3d/test_map3d_houses_meshes.gd
git commit -m "feat(map3d): generate and commit the house meshes

Committed rather than left under the git-ignored assets/map3d/ so a fresh
clone draws settlements without installing Blender — the precedent is
assets/map3d_preview/.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Wire the bake — `houses.csv` and the block-noise fade

**Files:**
- Modify: `tools/map3d/bake_world.py` (`sow_patchwork`, ~`:568-676`; `main`'s output section, ~`:1007`)
- Modify: `tools/map3d/test_bake_world.py`
- Test: `tests/map3d/test_map3d_houses_bake.gd`

**Interfaces:**
- Consumes: `bake_houses.place`, `house_count`, `footprint_radius_m` (Task 2).
- Produces: `<map3d_dir>/bake/houses.csv` with header `burg_code,rank,x_m,z_m,yaw_deg,type,scale` — `x_m`/`z_m` in **world metres** (the burg's world position plus the offset), no `y`.

- [ ] **Step 1: Write the failing test**

Create `tests/map3d/test_map3d_houses_bake.gd`. This is the owner's hard requirement, asserted over the whole real bake:

```gdscript
extends GutTest
## The baked houses of the default pack (spec 2026-09-20 §7). The headline
## assertion is the owner's: NO HOUSE STANDS IN THE SEA
## ("定居点的房屋模型不可以出现在海上"). A checkout with no 3D build skips.

var _rows: Array = []
var _meta: Dictionary = {}
var _picker: Map3DPicker


func before_all() -> void:
	Game.start_campaign(42)
	var dir := Game.data.map3d_dir()
	var path := dir + "/bake/houses.csv"
	if not FileAccess.file_exists(path):
		return
	_rows = DataRepository.parse_csv(path,
		["burg_code", "rank", "x_m", "z_m", "yaw_deg", "type", "scale"])
	var manifest := dir + "/manifest.json"
	if FileAccess.file_exists(manifest):
		var m: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(manifest))
		_meta = m.get("meta", {})
	var ctx := Map3DContext.new(Game.data, _meta)
	_picker = Map3DPicker.new(ctx)


func _skip() -> bool:
	if _rows.is_empty() or _meta.is_empty():
		pass_test("no 3D build in this checkout (tools/map3d/build_pack.sh) — skipped")
		return true
	return false


func test_no_house_stands_in_the_sea() -> void:
	if _skip():
		return
	var wet := 0
	var worst := ""
	for r: Dictionary in _rows:
		var pack := Map3DGeometry.world_to_pack(_meta,
			Vector2(float(r["x_m"]), float(r["z_m"])))
		if _picker.cell_at(pack) < 0:
			wet += 1
			if worst == "":
				worst = "%s rank %s at pack %s" % [r["burg_code"], r["rank"], pack]
	assert_eq(wet, 0, "every one of %d houses is on land; first wet: %s" % [_rows.size(), worst])


func test_every_house_is_inside_its_own_cluster() -> void:
	if _skip():
		return
	var ratio: float = Game.data.map3d_bake["house_radius_ratio"]
	for r: Dictionary in _rows:
		var code := String(r["burg_code"])
		assert_true(Game.data.burgs.has(code), code + " is a burg of this pack")
		if not Game.data.burgs.has(code):
			continue
		var b: Dictionary = Game.data.burgs[code]
		var centre := Map3DGeometry.pack_to_world(_meta,
			Vector2(float(b["x"]), float(b["y"])))
		var at := Vector2(float(r["x_m"]), float(r["z_m"]))
		var r_foot := Map3DHouses.footprint_radius_m(float(b.get("population", 0)), Game.data)
		assert_lte(at.distance_to(centre), ratio * r_foot + 0.5,
			code + " rank " + String(r["rank"]) + " is inside the house radius")


func test_rank_is_dense_and_starts_at_a_landmark() -> void:
	if _skip():
		return
	var by_burg: Dictionary = {}
	for r: Dictionary in _rows:
		var code := String(r["burg_code"])
		if not by_burg.has(code):
			by_burg[code] = []
		(by_burg[code] as Array).append(r)
	for code: String in by_burg:
		var rows: Array = by_burg[code]
		rows.sort_custom(func(a, b): return int(a["rank"]) < int(b["rank"]))
		for i in rows.size():
			assert_eq(int(rows[i]["rank"]), i, code + "'s ranks are dense")
		var first := String(rows[0]["type"])
		assert_eq(String(Game.data.map3d_houses[first]["role"]), "landmark",
			code + " starts with its landmark")


func test_every_type_used_is_in_the_table() -> void:
	if _skip():
		return
	for r: Dictionary in _rows:
		assert_true(Game.data.map3d_houses.has(String(r["type"])),
			String(r["type"]) + " is a known house type")
```

- [ ] **Step 2: Run it and watch it fail**

```
./run_tests.sh
```

Expected: the tests report the skip (no `houses.csv` yet) — or, once `Map3DHouses` is missing, a parse error naming it. `Map3DHouses.footprint_radius_m` arrives in Task 5; if the file will not parse, comment that one assertion out, finish this task, and restore it in Task 5. Note that in the commit message.

- [ ] **Step 3: Add the Python-side parity test**

Append to `tools/map3d/test_bake_world.py`:

```python
def test_footprint_radius_agrees_between_the_two_modules():
    """bake_houses keeps its own copy so it can stand alone; the two must
    never drift."""
    import bake_houses
    import bake_world
    rules = {"footprint_m_per_sqrt_pop": 2.5, "footprint_min_m": 90, "footprint_max_m": 900}
    for pop in (0, 1, 600, 4900, 52000, 10**7):
        assert bake_houses.footprint_radius_m(pop, rules) == \
               bake_world.footprint_radius_m(pop, rules)
```

Run: `cd tools/map3d && python3 -m pytest test_bake_world.py -v`. Expected: PASS.

- [ ] **Step 4: Call the placement from `sow_patchwork`**

In `tools/map3d/bake_world.py`, at the top add `import bake_houses`.

`sow_patchwork` currently builds `foot` in one loop over `burgs.csv` (the block that starts `# village footprints first: fields never cover the houses`). **After** that loop — `foot` must be complete first, because a candidate is tested against the finished mask — add a second pass that collects the houses and the per-burg house radius:

```python
    # the houses that stand on that built ground (spec 2026-09-20 §1). The
    # footprint mask is finished, so "inside the built ground" and "never in
    # the sea" are the same test the footprint already passed.
    house_rows = []
    r_house_mask = np.zeros((vh, vw), dtype=np.float32)
    types = {}
    with open(os.path.join(ROOT, "data", "map3d_houses.csv")) as f:
        for r in csv.DictReader(f):
            types[r["type"]] = {"role": r["role"], "weight": float(r["weight"]),
                                "footprint_m": float(r["footprint_m"]),
                                "min_group": r["min_group"]}
    with open(os.path.join(ROOT, "data", "maps", MAP, "political", "burgs.csv")) as f:
        for b in csv.DictReader(f):
            b = dict(b)
            b["population"] = float(b["population"] or 0)
            rows = bake_houses.place(b, rules, types, foot, land, height, k, vw, vh)
            cx, cy = float(b["x"]) * k, float(b["y"]) * k
            r_house = rules["house_radius_ratio"] * bake_houses.footprint_radius_m(
                b["population"], rules) / VERTEX_M
            # the block noise stops where the real roofs begin (§1): roofs
            # painted on the ground beside real roofs read as a mistake
            x0, x1 = max(int(cx - r_house) - 1, 0), min(int(cx + r_house) + 2, vw)
            y0, y1 = max(int(cy - r_house) - 1, 0), min(int(cy + r_house) + 2, vh)
            if x0 < x1 and y0 < y1:
                yy, xx = np.mgrid[y0:y1, x0:x1].astype(np.float32)
                d = np.hypot(xx - cx, yy - cy) / max(r_house, 1e-6)
                r_house_mask[y0:y1, x0:x1] = np.maximum(
                    r_house_mask[y0:y1, x0:x1], np.clip(1.5 - 1.5 * d, 0, 1))
            for r in rows:
                r["x_m"] = ORIGIN_X + float(b["x"]) * M_PER_PX + r["x_m"]
                r["z_m"] = ORIGIN_Y + float(b["y"]) * M_PER_PX + r["z_m"]
            house_rows.extend(rows)
```

`ORIGIN_X` / `ORIGIN_Y` are the world origin of pack px (0,0) — the same pair `main()` writes into `world.json` as `pack_origin`. Read that value where it is computed in `main()` and pass it into `sow_patchwork` as a new parameter `origin` rather than recomputing it; add `origin` to the call site and to the docstring.

Then, where the block tint is applied (`blocks = (1.0 - rules["footprint_block_depth"] * block_n)[..., None] * built`), fade the noise out under the houses:

```python
    block_amt = rules["footprint_block_depth"] * (1.0 - r_house_mask)
    blocks = (1.0 - block_amt * block_n)[..., None] * built
```

Return `house_rows` alongside what `sow_patchwork` already returns (`return tint, field_map(ftint, fangle), house_rows`), and update its docstring and its call site in `main()`.

- [ ] **Step 5: Write `bake/houses.csv` in `main()`**

Where `main()` writes `world.json` (~`:1007`), add:

```python
    with open(os.path.join(OUT, "houses.csv"), "w", newline="") as f:
        w = csv.DictWriter(f, ["burg_code", "rank", "x_m", "z_m", "yaw_deg", "type", "scale"])
        w.writeheader()
        for r in sorted(house_rows, key=lambda r: (r["burg_code"], r["rank"])):
            w.writerow(r)
    print("bake_world: %d houses over %d settlements" % (
        len(house_rows), len({r["burg_code"] for r in house_rows})))
```

- [ ] **Step 6: Run the bake on the default pack**

```
python3 tools/map3d/bake_world.py
```

Expected: the existing summary lines, plus `bake_world: NNNNN houses over 684 settlements`. Check the file:

```
head -3 assets/map3d/beria/bake/houses.csv && wc -l assets/map3d/beria/bake/houses.csv
```

- [ ] **Step 7: Confirm the bake is deterministic**

```
cp assets/map3d/beria/bake/houses.csv /tmp/houses_a.csv
python3 tools/map3d/bake_world.py >/dev/null
diff -q /tmp/houses_a.csv assets/map3d/beria/bake/houses.csv && echo DETERMINISTIC
```

Expected: `DETERMINISTIC`. If it differs, the placement is drawing from a shared RNG stream — `place()` must use only its own `default_rng(_seed(code))`.

- [ ] **Step 8: Run the tests**

```
./run_tests.sh
```

Expected: `test_map3d_houses_bake.gd` passes, `test_no_house_stands_in_the_sea` in particular. If any house is wet, do **not** loosen the test: raise `house_foot_min` or `house_shore_min_m`, or fix the mask indexing, and re-bake.

- [ ] **Step 9: Commit**

```bash
git add tools/map3d/bake_world.py tools/map3d/test_bake_world.py \
        tests/map3d/test_map3d_houses_bake.gd
git commit -m "feat(map3d): the bake writes houses.csv and clears the block noise under the roofs

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 5: `Map3DHouses` — the pure runtime selection

**Files:**
- Create: `scripts/map3d/map3d_houses.gd`
- Modify: `scripts/map3d/map3d_context.gd` (add `houses()`, `people_of_burg()`)
- Test: `tests/map3d/test_map3d_houses.gd`

**Interfaces:**
- Consumes: `DataRepository.map3d_houses` (Task 1), `bake/houses.csv` (Task 4).
- Produces, all `static`:
  - `Map3DHouses.load_csv(path: String) -> Dictionary` — `{burg_code: Array[Dictionary]}`, each row `{rank: int, at: Vector2 (world XZ), yaw_deg: float, type: String, scale: float}`, sorted by rank.
  - `Map3DHouses.footprint_radius_m(population: float, repo: DataRepository) -> float`
  - `Map3DHouses.shown_count(burg: Dictionary, people: float, repo: DataRepository) -> int`
  - `Map3DHouses.visible_set(houses: Dictionary, repo: DataRepository, burg_pos: Dictionary, people_of: Callable, camera_xz: Vector2, view_m: float, budget: int) -> Dictionary` — `{type: Array[Dictionary]}` buckets, farthest settlements dropped first when over budget.

- [ ] **Step 1: Write the failing test**

Create `tests/map3d/test_map3d_houses.gd`:

```gdscript
extends GutTest
## Map3DHouses: which baked houses are shown, and where (spec 2026-09-20 §3).
## Pure — no world, no terrain, no Game beyond the data repository.

const CSV := "user://test_map3d_houses.csv"

var _houses: Dictionary = {}


func before_all() -> void:
	Game.start_campaign(42)
	var f := FileAccess.open(CSV, FileAccess.WRITE)
	f.store_line("burg_code,rank,x_m,z_m,yaw_deg,type,scale")
	f.store_line("alpha,0,100,200,10,chapel,1.0")
	f.store_line("alpha,1,120,200,90,cottage_a,0.95")
	f.store_line("alpha,2,140,220,180,barn,0.9")
	f.store_line("beta,0,5000,200,0,chapel,1.0")
	f.store_line("beta,1,5020,200,45,cottage_a,1.0")
	f.close()
	_houses = Map3DHouses.load_csv(CSV)


func test_the_csv_loads_grouped_by_burg_and_sorted_by_rank() -> void:
	assert_eq(_houses.size(), 2)
	var alpha: Array = _houses["alpha"]
	assert_eq(alpha.size(), 3)
	assert_eq(int(alpha[0]["rank"]), 0)
	assert_eq(alpha[0]["at"], Vector2(100, 200))
	assert_eq(String(alpha[2]["type"]), "barn")


func test_a_missing_file_is_empty_not_an_error() -> void:
	assert_eq(Map3DHouses.load_csv("user://no_such_houses.csv"), {})


func test_shown_count_follows_people_and_its_cap() -> void:
	var town := {"group": "town"}
	var per: float = Game.data.map3d_bake["house_people_per_house"]
	assert_eq(Map3DHouses.shown_count(town, per * 10.0, Game.data), 10)
	assert_eq(Map3DHouses.shown_count(town, 1.0, Game.data),
		int(Game.data.map3d_bake["house_min"]), "never fewer than house_min")
	assert_eq(Map3DHouses.shown_count({"group": "village"}, 1.0e9, Game.data),
		int(Game.data.map3d_bake["house_max_village"]), "capped by its group")


func test_a_settlement_out_of_range_is_not_instanced_at_all() -> void:
	var pos := {"alpha": Vector2(100, 200), "beta": Vector2(5000, 200)}
	var people := func(_c: String) -> float: return 100000.0
	var out := Map3DHouses.visible_set(_houses, Game.data, pos, people,
		Vector2(100, 200), 1000.0, 9999)
	var seen := _codes(out)
	assert_true(seen.has("alpha"), "the near settlement is built")
	assert_false(seen.has("beta"), "the far one is not built at all, not culled after")


func test_the_budget_drops_the_farthest_settlements_first() -> void:
	var pos := {"alpha": Vector2(100, 200), "beta": Vector2(5000, 200)}
	var people := func(_c: String) -> float: return 100000.0
	var out := Map3DHouses.visible_set(_houses, Game.data, pos, people,
		Vector2(100, 200), 100000.0, 3)
	var seen := _codes(out)
	assert_true(seen.has("alpha"), "the near settlement keeps its houses")
	assert_false(seen.has("beta"), "the far one is dropped whole, never half-built")


func test_the_result_is_bucketed_by_type() -> void:
	var pos := {"alpha": Vector2(100, 200)}
	var people := func(_c: String) -> float: return 100000.0
	var out := Map3DHouses.visible_set(_houses, Game.data, pos, people,
		Vector2(100, 200), 100000.0, 9999)
	for type: String in out:
		for h: Dictionary in out[type]:
			assert_eq(String(h["type"]), type, "every row is in its own bucket")


func test_footprint_radius_matches_the_bake_table() -> void:
	var r := Map3DHouses.footprint_radius_m(4900.0, Game.data)
	var want: float = clampf(
		Game.data.map3d_bake["footprint_m_per_sqrt_pop"] * sqrt(4900.0),
		Game.data.map3d_bake["footprint_min_m"], Game.data.map3d_bake["footprint_max_m"])
	assert_almost_eq(r, want, 0.001)


func _codes(buckets: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for type: String in buckets:
		for h: Dictionary in buckets[type]:
			out[String(h["burg_code"])] = true
	return out
```

- [ ] **Step 2: Run it and watch it fail**

```
./run_tests.sh
```

Expected: `Map3DHouses` is not a known class.

- [ ] **Step 3: Write `scripts/map3d/map3d_houses.gd`**

```gdscript
class_name Map3DHouses
extends RefCounted
## Which of a settlement's baked houses are shown, and where (spec
## 2026-09-20 §3). Pure and static: the bake decided WHERE every house
## stands; this decides HOW MANY of them a settlement shows right now (its
## people) and WHICH settlements are near enough to build at all.
##
## Never reaches for the Game autoload — tests/map3d/test_map3d_preview.gd
## scans this directory for it.

const COLUMNS := ["burg_code", "rank", "x_m", "z_m", "yaw_deg", "type", "scale"]


## The bake's houses.csv, grouped by burg and sorted by rank. A missing file
## is {} — a build without houses draws none, as the other optional bake
## inputs do.
static func load_csv(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var rows := DataRepository.parse_csv(path, COLUMNS)
	if DataRepository.last_error != "":
		return {}
	var out: Dictionary = {}
	for r: Dictionary in rows:
		var code := String(r["burg_code"])
		if not out.has(code):
			out[code] = []
		(out[code] as Array).append({
			"burg_code": code,
			"rank": int(r["rank"]),
			"at": Vector2(float(r["x_m"]), float(r["z_m"])),
			"yaw_deg": float(r["yaw_deg"]),
			"type": String(r["type"]),
			"scale": float(r["scale"]),
		})
	for code: String in out:
		(out[code] as Array).sort_custom(func(a, b): return int(a["rank"]) < int(b["rank"]))
	return out


## The built ground's radius in metres — the bake's own formula, so the
## runtime and the bake agree on where a cluster ends.
static func footprint_radius_m(population: float, repo: DataRepository) -> float:
	var t: Dictionary = repo.map3d_bake
	return clampf(float(t["footprint_m_per_sqrt_pop"]) * sqrt(maxf(population, 0.0)),
		float(t["footprint_min_m"]), float(t["footprint_max_m"]))


## The most houses this settlement's group ever shows.
static func max_houses(group: String, repo: DataRepository) -> int:
	var t: Dictionary = repo.map3d_bake
	var key := "house_max_" + group
	return int(t[key]) if t.has(key) else int(t["house_max_village"])


## How many of the baked houses a settlement shows: one per
## house_people_per_house souls, at least house_min, capped by its group. A
## settlement that grows sprouts more houses with no re-bake.
static func shown_count(burg: Dictionary, people: float, repo: DataRepository) -> int:
	var t: Dictionary = repo.map3d_bake
	var n := int(round(people / maxf(float(t["house_people_per_house"]), 1.0)))
	return mini(maxi(n, int(t["house_min"])),
		max_houses(String(burg.get("group", "village")), repo))


## The houses to instance now, bucketed by type.
## `burg_pos` is {code: world XZ}, `people_of` a Callable(String) -> float.
## A settlement past `view_m` is not built at all; over `budget`, whole
## settlements are dropped farthest first — never half a village.
static func visible_set(houses: Dictionary, repo: DataRepository, burg_pos: Dictionary,
		people_of: Callable, camera_xz: Vector2, view_m: float, budget: int) -> Dictionary:
	var near: Array = []
	for code: String in houses:
		if not burg_pos.has(code):
			continue
		var d: float = (burg_pos[code] as Vector2).distance_to(camera_xz)
		if d > view_m:
			continue
		near.append({"code": code, "d": d})
	near.sort_custom(func(a, b): return a["d"] < b["d"] if a["d"] != b["d"] else a["code"] < b["code"])
	var out: Dictionary = {}
	var used := 0
	for e: Dictionary in near:
		var code: String = e["code"]
		var burg: Dictionary = repo.burgs.get(code, {})
		var rows: Array = houses[code]
		var want := mini(shown_count(burg, float(people_of.call(code)), repo), rows.size())
		if used + want > budget:
			break
		for i in want:
			var h: Dictionary = rows[i]
			var type: String = h["type"]
			if not out.has(type):
				out[type] = []
			(out[type] as Array).append(h)
		used += want
	return out
```

- [ ] **Step 4: Add the context accessors**

In `scripts/map3d/map3d_context.gd`, beside `burg_ground` / `marked_burgs`, add:

```gdscript
var _houses: Dictionary = {}
var _houses_loaded := false


## The build's baked houses, grouped by burg (spec 2026-09-20 §3). Loaded
## once; a build without them is {} and no houses are drawn.
func houses() -> Dictionary:
	if not _houses_loaded:
		_houses_loaded = true
		_houses = Map3DHouses.load_csv(repo.map3d_dir() + "/bake/houses.csv")
	return _houses


## A burg's people now: the manor ledger where there is a live state, the
## pack's own population otherwise (a preview, a test).
func people_of_burg(code: String) -> float:
	var burg: Dictionary = repo.burgs.get(code, {})
	return float(burg.get("population", 0))
```

Note for the implementer: wiring `people_of_burg` to the live manor ledger is deliberately **not** done here — `Map3DContext` must not reach for `Game`, and the pack's population is correct for every settlement that has not grown. Task 7 passes the live figure in through the view if it is available; leave this as the fallback.

- [ ] **Step 5: Restore the Task 4 assertion if it was commented out**

If `tests/map3d/test_map3d_houses_bake.gd:test_every_house_is_inside_its_own_cluster` had its `Map3DHouses.footprint_radius_m` line commented out, uncomment it now.

- [ ] **Step 6: Run the tests**

```
./run_tests.sh
```

Expected: `test_map3d_houses.gd` passes; `test_map3d_houses_bake.gd` fully passes.

- [ ] **Step 7: Commit**

```bash
git add scripts/map3d/map3d_houses.gd scripts/map3d/map3d_context.gd \
        tests/map3d/test_map3d_houses.gd tests/map3d/test_map3d_houses_bake.gd
git commit -m "feat(map3d): Map3DHouses — which baked houses a settlement shows

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 6: `Map3DLayerHouses` — the MultiMeshes, the materials, the scene node

**Files:**
- Create: `scripts/map3d/map3d_layer_houses.gd`
- Create: `scenes/map3d/materials/house.tres`
- Modify: `scenes/map3d/world_map_3d.tscn` (add `Viewport/Houses`)
- Test: `tests/map3d/test_map3d_layer_houses.gd`

**Interfaces:**
- Consumes: `Map3DHouses.visible_set` (Task 5), `Map3DContext.height_at` / `houses()` / `people_of_burg()`, `DataRepository.map3d_houses`.
- Produces: `Map3DLayerHouses.bind(ctx)`, `.build()`, `.refresh(camera_xz: Vector2) -> bool` (true when it rebuilt), `.counts() -> Dictionary` (`{type: instance_count}`), `.preview_build(ctx)`, `@export var preview: bool`.

- [ ] **Step 1: Write the failing test**

Create `tests/map3d/test_map3d_layer_houses.gd`:

```gdscript
extends GutTest
## Map3DLayerHouses: one MultiMesh per type, rebuilt only when the camera
## moves far enough (spec 2026-09-20 §3).

const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}
const CSV := "user://test_map3d_layer_houses.csv"

var _layer: Map3DLayerHouses
var _ctx: Map3DContext


func before_each() -> void:
	Game.start_campaign(42)
	var codes: Array = Game.data.burgs.keys()
	codes.sort()
	var a := String(codes[0])
	var f := FileAccess.open(CSV, FileAccess.WRITE)
	f.store_line("burg_code,rank,x_m,z_m,yaw_deg,type,scale")
	var b: Dictionary = Game.data.burgs[a]
	var at := Map3DGeometry.pack_to_world(WORLD, Vector2(float(b["x"]), float(b["y"])))
	f.store_line("%s,0,%f,%f,0,chapel,1.0" % [a, at.x, at.y])
	f.store_line("%s,1,%f,%f,90,cottage_a,1.0" % [a, at.x + 20.0, at.y])
	f.close()
	_ctx = Map3DContext.new(Game.data, WORLD)
	_ctx.height_fn = func(_xz: Vector2) -> float: return 100.0
	_layer = Map3DLayerHouses.new()
	_layer.houses_override = Map3DHouses.load_csv(CSV)
	add_child_autofree(_layer)
	_layer.bind(_ctx)


func test_one_multimesh_per_type_present() -> void:
	_layer.refresh(_home())
	var counts := _layer.counts()
	assert_eq(counts.get("chapel", 0), 1)
	assert_eq(counts.get("cottage_a", 0), 1)


func test_every_instance_sits_on_the_ground_minus_the_sink() -> void:
	_layer.refresh(_home())
	var sink: float = Game.data.bal("map3d_house_sink_m")
	for mmi: MultiMeshInstance3D in _layer.get_children():
		for i in mmi.multimesh.instance_count:
			var y := mmi.multimesh.get_instance_transform(i).origin.y
			assert_almost_eq(y, 100.0 - sink, 0.001,
				"a house stands on the ground, sunk so its foot bites in")


func test_a_small_camera_move_does_not_rebuild() -> void:
	assert_true(_layer.refresh(_home()), "the first call builds")
	var step: float = Game.data.bal("map3d_house_rebuild_move_m")
	assert_false(_layer.refresh(_home() + Vector2(step * 0.4, 0.0)),
		"cut once per camera pose, never per frame")
	assert_true(_layer.refresh(_home() + Vector2(step * 1.5, 0.0)),
		"a real move rebuilds")


func test_nothing_is_built_far_from_every_settlement() -> void:
	_layer.refresh(Vector2(500000.0, 500000.0))
	for type: String in _layer.counts():
		assert_eq(int(_layer.counts()[type]), 0, type + " has no instances out at sea")


func test_instances_carry_their_yaw_and_scale() -> void:
	_layer.refresh(_home())
	var mmi := _layer.get_node_or_null("Cottage_a") as MultiMeshInstance3D
	assert_not_null(mmi)
	if mmi != null and mmi.multimesh.instance_count > 0:
		var basis := mmi.multimesh.get_instance_transform(0).basis
		assert_almost_eq(basis.get_euler().y, deg_to_rad(90.0), 0.01)


func _home() -> Vector2:
	var codes: Array = Game.data.burgs.keys()
	codes.sort()
	var b: Dictionary = Game.data.burgs[String(codes[0])]
	return Map3DGeometry.pack_to_world(WORLD, Vector2(float(b["x"]), float(b["y"])))
```

- [ ] **Step 2: Run it and watch it fail**

```
./run_tests.sh
```

Expected: `Map3DLayerHouses` is not a known class.

- [ ] **Step 3: Create the material `scenes/map3d/materials/house.tres`**

A `StandardMaterial3D` holding **only** what §"The look is .tres" allows — the texture and render settings, no tuned numbers:

```
[gd_resource type="StandardMaterial3D" load_steps=2 format=3]

[ext_resource type="Texture2D" path="res://assets/map3d_preview/medieval_blocks_03_alb_ht.png" id="1"]

[resource]
resource_name = "house"
vertex_color_use_as_albedo = true
albedo_texture = ExtResource("1")
roughness = 0.9
specular_mode = 1
texture_filter = 4
uv1_triplanar = true
```

Note: `vertex_color_use_as_albedo = true` is what lets ONE material serve every type — the per-type roof and wall colours ride in as the `MultiMesh`'s instance colours. Check the exact `.tres` header/`load_steps` against a sibling (`scenes/map3d/materials/bridge_stone.tres`) and match its style; if `assets/map3d_preview/medieval_blocks_03_alb_ht.png` does not exist in this checkout, point at whichever stone preview does and note it in the commit.

- [ ] **Step 4: Write `scripts/map3d/map3d_layer_houses.gd`**

```gdscript
@tool
class_name Map3DLayerHouses
extends Node3D
## The settlements' house clusters (spec 2026-09-20 §3, node
## Viewport/Houses): one MultiMesh per house type, every instance standing on
## the terrain under it, rebuilt only when the camera has moved
## map3d_house_rebuild_move_m — cut once per camera pose, never per frame.
##
## The bake decided where every house stands (tools/map3d/bake_houses.py);
## this only instances them. Takes everything from Map3DContext — never the
## Game autoload.

const MAT := preload("res://scenes/map3d/materials/house.tres")

## Editor preview: the clusters from the pack and its build alone.
@export var preview := false: set = set_preview

## Test seam: the baked houses, in place of the build's own houses.csv.
var houses_override: Dictionary = {}

var ctx: Map3DContext
var _meshes: Dictionary = {}          # type -> Mesh
var _built_at := Vector2.INF
var _instances: Dictionary = {}       # type -> MultiMeshInstance3D


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx


func set_preview(on: bool) -> void:
	preview = on
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	if on:
		preview_build(Map3DPreview.context_for(self))
	else:
		_instances.clear()
		_built_at = Vector2.INF
		Map3DPreview.clear_generated(self)
	Map3DPreview.sync_viewport(self)


func preview_build(p_ctx: Map3DContext) -> void:
	bind(p_ctx)
	Map3DPreview.prepare(self, p_ctx)
	if p_ctx.meta.is_empty():
		return
	build()


## Build the empty per-type MultiMeshes; refresh() fills them.
func build() -> void:
	Map3DPreview.clear_generated(self)
	_instances.clear()
	_meshes.clear()
	_built_at = Vector2.INF
	for type: String in ctx.repo.map3d_houses:
		var mesh := _mesh_of(type)
		if mesh == null:
			continue
		_meshes[type] = mesh
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = 0
		var mmi := MultiMeshInstance3D.new()
		mmi.name = type.capitalize()
		mmi.multimesh = mm
		mmi.material_override = MAT
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		add_child(mmi)
		_instances[type] = mmi


## Rebuild the instances for this camera position; true when it did. A move
## under map3d_house_rebuild_move_m is ignored.
func refresh(camera_xz: Vector2) -> bool:
	if ctx == null or _instances.is_empty():
		return false
	var step := ctx.repo.bal("map3d_house_rebuild_move_m")
	if _built_at.is_finite() and _built_at.distance_to(camera_xz) < step:
		return false
	_built_at = camera_xz
	var houses := houses_override if not houses_override.is_empty() else ctx.houses()
	var pos: Dictionary = {}
	for code: String in houses:
		if ctx.repo.burgs.has(code):
			var b: Dictionary = ctx.repo.burgs[code]
			pos[code] = ctx.to_world(Vector2(float(b["x"]), float(b["y"])))
	var buckets := Map3DHouses.visible_set(houses, ctx.repo, pos,
		func(c: String) -> float: return ctx.people_of_burg(c),
		camera_xz, ctx.repo.bal("map3d_house_view_m"), _budget())
	var sink := ctx.repo.bal("map3d_house_sink_m")
	for type: String in _instances:
		var mmi: MultiMeshInstance3D = _instances[type]
		var rows: Array = buckets.get(type, [])
		mmi.multimesh.instance_count = rows.size()
		if rows.is_empty():
			continue
		var roof := _roof_colour(type)
		for i in rows.size():
			var h: Dictionary = rows[i]
			var at: Vector2 = h["at"]
			var basis := Basis(Vector3.UP, deg_to_rad(float(h["yaw_deg"])))
			basis = basis.scaled(Vector3.ONE * float(h["scale"]))
			mmi.multimesh.set_instance_transform(i,
				Transform3D(basis, Vector3(at.x, ctx.height_at(at) - sink, at.y)))
			mmi.multimesh.set_instance_color(i, roof)
	return true


## Instances per type, for the tests and the bench.
func counts() -> Dictionary:
	var out: Dictionary = {}
	for type: String in _instances:
		out[type] = (_instances[type] as MultiMeshInstance3D).multimesh.instance_count
	return out


func _budget() -> int:
	return int(Map3DQuality.num(ctx.q(), "house_budget"))


func _roof_colour(type: String) -> Color:
	return MapPalette.named(ctx.repo, String(ctx.repo.map3d_houses[type]["roof"]))


func _mesh_of(type: String) -> Mesh:
	var path := String(ctx.repo.map3d_houses[type]["mesh"])
	if not ResourceLoader.exists(path):
		Map3DWorldLoader.warn_once("map3d houses: no mesh at " + path)
		return null
	var scene := load(path) as PackedScene
	if scene == null:
		return null
	var node := scene.instantiate()
	var mesh := _first_mesh(node)
	node.free()
	return mesh


func _first_mesh(node: Node) -> Mesh:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		return (node as MeshInstance3D).mesh
	for c in node.get_children():
		var m := _first_mesh(c)
		if m != null:
			return m
	return null
```

Both helper spellings are verified against the repository: `Map3DQuality.num(r: Dictionary, key: String, fallback: float = 1.0) -> float` (`scripts/map3d/map3d_quality.gd:23`) and `static func Map3DWorldLoader.warn_once(key: String, message: String) -> void` (`scripts/map3d/map3d_world_loader.gd:107`). Use them as written.

- [ ] **Step 5: Add the `Houses` node to the authored scene**

Open `scenes/map3d/world_map_3d.tscn` in the Godot editor (or edit the `.tscn` text) and add, as a child of `Viewport` beside `Markers`, a `Node3D` named `Houses` with `script = ExtResource(<map3d_layer_houses.gd>)`. Follow the file's existing pattern for `Markers` exactly — same parent, same `ExtResource` style. Nothing the layer builds is given an `owner`, so a save can never write instances into the scene.

- [ ] **Step 6: Run the tests**

```
./run_tests.sh
```

Expected: `test_map3d_layer_houses.gd` passes.

- [ ] **Step 7: Commit**

```bash
git add scripts/map3d/map3d_layer_houses.gd scenes/map3d/materials/house.tres \
        scenes/map3d/world_map_3d.tscn tests/map3d/test_map3d_layer_houses.gd
git commit -m "feat(map3d): Map3DLayerHouses — one MultiMesh per house type

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 7: Wire the view, the staleness hash and the bench

**Files:**
- Modify: `scripts/map3d/map3d_view.gd` (bind the layer; refresh on `camera_moved`)
- Modify: `scripts/map3d/map3d_world_loader.gd:34-60` area (`steps_hash`)
- Modify: `tools/map3d/bench.gd` (a `--layer houses` row)
- Test: `tests/map3d/test_map3d_layers.gd` (the view names the layer), `tests/map3d/test_map3d_loader.gd` (the hash)

**Interfaces:**
- Consumes: `Map3DLayerHouses.refresh` (Task 6).
- Produces: `Map3DView.houses` (the layer node), refreshed from the rig's `camera_moved`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/map3d/test_map3d_layers.gd`:

```gdscript
func test_the_view_owns_a_houses_layer() -> void:
	var view := Map3DView.create()
	add_child_autofree(view)
	var node := view.get_node_or_null("Viewport/Houses")
	assert_not_null(node, "the authored scene has Viewport/Houses")
	assert_true(node is Map3DLayerHouses, "it is the houses layer")


func test_a_camera_move_refreshes_the_houses() -> void:
	var view := Map3DView.create()
	add_child_autofree(view)
	var layer := view.get_node_or_null("Viewport/Houses") as Map3DLayerHouses
	assert_not_null(layer)
	if layer == null:
		return
	assert_true(view.has_method("_on_camera_moved") or view.has_signal("camera_moved")
		or layer.has_method("refresh"), "the view has a seam that refreshes the layer")
```

Append to `tests/map3d/test_map3d_loader.gd` (it exists — match its neighbours' style):

```gdscript
func test_the_house_table_is_in_the_steps_hash() -> void:
	# a changed house table must report the build stale, not draw the old one
	var before := Map3DWorldLoader.steps_hash()
	var path := "res://data/map3d_houses.csv"
	var original := FileAccess.get_file_as_string(path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(original + "\n# probe\n")
	f.close()
	var after := Map3DWorldLoader.steps_hash()
	var g := FileAccess.open(path, FileAccess.WRITE)
	g.store_string(original)
	g.close()
	assert_ne(before, after, "map3d_houses.csv is part of the build's steps hash")
```

- [ ] **Step 2: Run them and watch them fail**

```
./run_tests.sh
```

Expected: no `Viewport/Houses` seam in the view, and `steps_hash` unchanged by the probe.

- [ ] **Step 3: Add `map3d_houses.csv` to the steps hash**

In `scripts/map3d/map3d_world_loader.gd`, find the list `steps_hash()` md5s (`data/map3d_bake.csv`, `data/map3d_fields.csv`) and add `"res://data/map3d_houses.csv"` to it. Leave `FORMAT_VERSION` alone — the build's *format* has not changed, only its inputs, which is exactly what `steps_hash` is for.

- [ ] **Step 4: Wire the layer in `Map3DView`**

Follow whatever `Map3DView` already does for `Viewport/Markers` — the same `@onready`/`get_node` style, the same `bind(ctx)` + `build()` at load. Then, wherever the view already responds to the rig's `camera_moved` (the HUD redraw does), add:

```gdscript
	if houses != null:
		houses.refresh(ctx.target)
```

`ctx.target` is the rig's ground target in world XZ, which is the right thing to measure "which settlements are near" from — not the camera's own eye position, which swings with the pitch.

- [ ] **Step 5: Add the bench row**

In `tools/map3d/bench.gd`, extend the `--layer` argument's accepted values (`manors|heights|military`) with `houses`, and make that mode frame the view at a zoom where a cluster is on screen (the closest bench zoom). Follow exactly how `manors` is implemented there.

- [ ] **Step 6: Run the tests and the bench**

```
./run_tests.sh
/Applications/Godot.app/Contents/MacOS/Godot --path . -s res://tools/map3d/bench.tscn -- --layer houses --pan
```

Expected: tests pass. Record the bench's `high` row median against its 8 ms budget and put the number in the commit message — **do not retune anything to hide it**; `tools/map3d/README.md`'s Open items already record that `high` is over budget under `--pan`, and an honest new number belongs beside it.

- [ ] **Step 7: Commit**

```bash
git add scripts/map3d/map3d_view.gd scripts/map3d/map3d_world_loader.gd \
        tools/map3d/bench.gd tests/map3d/test_map3d_layers.gd \
        tests/map3d/test_map3d_loader.gd
git commit -m "feat(map3d): the view builds and refreshes the house layer

Bench (--layer houses --pan, high): <median> ms against an 8 ms budget.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 8: Show the owner — the first look

**Files:**
- Create: screenshots under the scratchpad directory (not committed)
- Modify: nothing

**Interfaces:**
- Consumes: everything from Tasks 1–7.
- Produces: a decision from the owner on `house_radius_ratio`, `house_density_gamma` and the per-group caps before Phase B tears the dots out.

- [ ] **Step 1: Invoke the visual-review skill**

This is a visual change, so the project's own loop applies: `.claude/skills/visual-review/`. Read `taste.md` first.

- [ ] **Step 2: Shoot a village, a town and the capital at the closest zoom**

```
/Applications/Godot.app/Contents/MacOS/Godot --path . -s res://tools/snapshot_screen.tscn -- \
  --screen court --resolution 2560x1440 --out <scratchpad>/houses_capital.png
```

Use `--click3d fx,fy` / the view's framing controls to put each settlement on screen at `map3d_zoom_min_m`. Shoot at 800 m, 2 500 m and 8 000 m for each.

- [ ] **Step 3: Bracket the two values the owner must choose**

`snapshot_screen --bal key=value` brackets one look value per shot. Shoot `house_radius_ratio` at 0.45 / 0.60 / 0.75 and `house_density_gamma` at 1.0 / 1.4 / 2.0, on the same settlement and the same camera pose.

- [ ] **Step 4: Crop and run the independent critic**

Per the skill: crop each variant to the settlement and its surroundings so the buffer ring is visible, then run the critic pass. Check specifically against taste.md: no base plate, no hard rim, nothing scattered, the cluster ends by thinning.

- [ ] **Step 5: Present the sheets to the owner and record the rulings**

Ask for: the two bracketed values, and whether the cluster reads as one place. Write whatever is ruled into `.claude/skills/visual-review/taste.md` as a principle with its why, and set the chosen values in `data/map3d_bake.csv`.

- [ ] **Step 6: Re-bake with the chosen values and commit**

```bash
python3 tools/map3d/bake_world.py
./run_tests.sh
git add data/map3d_bake.csv .claude/skills/visual-review/taste.md
git commit -m "feat(map3d): the owner's house radius and density

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 9: Remove the dots; the pick reach comes from the cluster

**Files:**
- Modify: `data/map3d_settlements.csv` (drop `dot_px`, `ring_px`, `line_px`; keep `group`, `color`, `max_view_m`)
- Modify: `scripts/engine/data_repository.gd:475-477` (required columns)
- Modify: `scripts/map3d/map3d_layer_settlements.gd` (tier `MultiMesh`es go; the selection ring stays)
- Modify: `scripts/map3d/map3d_picker.gd:76,81`, `scripts/map3d/map3d_context.gd:253`, `scripts/map3d/map3d_view.gd:293`
- Modify: `scripts/map3d/settlement_ring.gdshader` (a world-metre ring with a screen-px floor)
- Modify: `tests/map3d/test_map3d_view.gd:94-135`, `test_map3d_layers.gd:111-112`, `test_map3d_heights.gd:201-208`, `test_map3d_api.gd:15,34`
- Test: `tests/map3d/test_map3d_settlement_pick.gd`

**Interfaces:**
- Consumes: `Map3DHouses.footprint_radius_m` (Task 5).
- Produces: `Map3DView.pick_reach_px(code: String, spec: Dictionary, dist_m: float) -> float` replacing `Map3DView.marker_px(spec)` / `Map3DLayerSettlements.marker_px(spec)` — the cluster's projected radius in screen px, floored at `map3d_pick_px`.

- [ ] **Step 1: Write the failing test**

Create `tests/map3d/test_map3d_settlement_pick.gd`:

```gdscript
extends GutTest
## With the dots gone (owner 2026-09-20: "黑点/黑点+圆圈本就是暂时的
## placeholder，给我完全替换掉"), a click anywhere on the town picks the town:
## the reach is the cluster's projected radius, floored at map3d_pick_px.

const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}


func before_all() -> void:
	Game.start_campaign(42)


func test_the_table_no_longer_carries_a_dot() -> void:
	for group: String in Game.data.map3d_settlements:
		var spec: Dictionary = Game.data.map3d_settlements[group]
		assert_false(spec.has("dot_px"), group + " has no dot")
		assert_false(spec.has("ring_px"), group + " has no ring")


func test_a_big_settlement_has_a_wider_reach_than_a_small_one() -> void:
	var view := Map3DView.create()
	add_child_autofree(view)
	var cap := _biggest("capital")
	var vil := _biggest("village")
	if cap == "" or vil == "":
		pass_test("this pack has no capital or no village")
		return
	assert_gt(view.pick_reach_px(cap, Game.data.map3d_settlements["capital"], 5000.0),
		view.pick_reach_px(vil, Game.data.map3d_settlements["village"], 5000.0),
		"a click anywhere on the city picks the city")


func test_the_reach_never_falls_below_the_floor() -> void:
	var view := Map3DView.create()
	add_child_autofree(view)
	var vil := _biggest("village")
	if vil == "":
		pass_test("this pack has no village")
		return
	assert_gte(view.pick_reach_px(vil, Game.data.map3d_settlements["village"], 140000.0),
		Game.data.bal("map3d_pick_px"),
		"a hamlet at campaign zoom is still clickable")


func _biggest(group: String) -> String:
	var best := ""
	var best_pop := -1.0
	for code: String in Game.data.burgs:
		var b: Dictionary = Game.data.burgs[code]
		if String(b.get("group", "")) != group:
			continue
		var pop := float(b.get("population", 0))
		if pop > best_pop:
			best_pop = pop
			best = code
	return best
```

- [ ] **Step 2: Run it and watch it fail**

```
./run_tests.sh
```

Expected: `dot_px` is still in the table, and `pick_reach_px` does not exist.

- [ ] **Step 3: Cut the columns from the data and the loader**

`data/map3d_settlements.csv` becomes:

```csv
group,color,max_view_m,notes
capital,#141414,1000000,"3D MAP: the settlement's colour (the selection ring and the HUD read it) and the camera distance past which it stops being drawn. The solid black DOTS of 2026-09-19 were removed on 2026-09-20 (owner: '黑点/黑点+圆圈本就是暂时的placeholder，给我完全替换掉') — a settlement is now its house cluster (spec 2026-09-20)"
city,#141414,150000,
fort,#141414,60000,
town,#141414,60000,
village,#141414,25000,"max_view_m: the camera-to-settlement distance beyond which it is gone"
```

And in `scripts/engine/data_repository.gd` drop the three names from the required-column list:

```gdscript
	if not _load_if_present("res://data/map3d_settlements.csv",
			["group", "color", "max_view_m"],
			func(r): map3d_settlements[String(r["group"])] = r):
		return false
```

- [ ] **Step 4: Re-home the pick reach**

Add to `scripts/map3d/map3d_view.gd`, replacing `static func marker_px`:

```gdscript
## A settlement's click reach in screen px: its cluster's projected radius,
## never below map3d_pick_px. The dots it replaced were a fixed size (owner
## 2026-09-20), so a big city was no easier to hit than a hamlet.
func pick_reach_px(code: String, spec: Dictionary, dist_m: float) -> float:
	var floor_px := ctx.repo.bal("map3d_pick_px")
	if dist_m > float(spec.get("max_view_m", 0.0)):
		return floor_px
	var burg: Dictionary = ctx.repo.burgs.get(code, {})
	var r_m := Map3DHouses.footprint_radius_m(float(burg.get("population", 0)), ctx.repo)
	# px_per_dist() is METRES PER PX per metre of distance (map3d_context.gd:146
	# — 2*tan(fov/2)/viewport_height), so metres-per-px at `dist_m` is
	# dist_m * px_per_dist(), and a radius in metres divides by it.
	var m_per_px := maxf(dist_m * ctx.px_per_dist(), 1e-6)
	return maxf(r_m / m_per_px, floor_px)
```

Note the units: `px_per_dist()` is named for the ratio it feeds the shaders, but it returns **metres per pixel per metre of distance** — dividing by `dist_m * px_per_dist()` is what turns a world radius into screen px. The test (`a big settlement has a wider reach`) is what proves you got it right.

Then update the three call sites — `map3d_picker.gd:76,81` and `map3d_context.gd:253` — to call it with the burg code and its distance, and delete `Map3DLayerSettlements.marker_px` and `Map3DView.marker_px`.

- [ ] **Step 5: Cut the tier MultiMeshes from the settlements layer**

In `scripts/map3d/map3d_layer_settlements.gd`, `build()` keeps only the `Selected` ring. Delete the `by_group` / `by_size` / per-group loop and the `dot_px` meta. In `show_selected`, size the ring from the cluster instead:

```gdscript
	var burg: Dictionary = ctx.repo.burgs[code]
	var r_m := Map3DHouses.footprint_radius_m(float(burg.get("population", 0)), ctx.repo)
	mat.set_meta("ring_m", r_m * ctx.repo.bal("map3d_select_ring_ratio"))
	mat.set_meta("line_px", 2.0)
```

Add `map3d_select_ring_ratio` (1.08) to `data/balance.csv` with a note saying it rings the settlement's built ground, just outside it.

- [ ] **Step 6: Give the shader a world-metre ring**

In `scripts/map3d/settlement_ring.gdshader`, drop the `dot_px` uniform and its `disc` term, and add:

```glsl
uniform float ring_m = 0.0;    // the ring's diameter in world metres; 0 = screen-sized
```

In the vertex stage, when `ring_m > 0.0` size the quad in metres (`ring_m` plus the keyline's screen px) instead of by `dist * px_per_dist`; in the fragment stage compute `r` against that same size. Keep the screen-px floor so a far village's gold ring does not vanish. Update `scenes/map3d/materials/settlement_ring.tres` / `selection_ring.tres` only if they set `dot_px` — the `.tres` files hold no tuned numbers, so most likely nothing changes there.

- [ ] **Step 7: Migrate the four affected test files**

- `tests/map3d/test_map3d_view.gd:94-135` — the assertions on `dot_px` / `ring_px` become assertions on `pick_reach_px` and on the ring material's `ring_m`.
- `tests/map3d/test_map3d_layers.gd:111-112` — the `marker_px` parity test goes; replace it with one that the settlements layer builds only the `Selected` child.
- `tests/map3d/test_map3d_heights.gd:201-208` — the landmark-avoidance obstacles take `pick_reach_px` in place of `marker_px(spec) * 0.5`.
- `tests/map3d/test_map3d_api.gd:15,34` — `marker_px` leaves `STATICS` and the arity map; `pick_reach_px` is an instance method, so add it wherever that file lists those.

- [ ] **Step 8: Run the tests**

```
./run_tests.sh
```

Expected: everything passes and the suite reports its expected error count.

- [ ] **Step 9: Shoot the map to confirm nothing is left of the dots**

```
/Applications/Godot.app/Contents/MacOS/Godot --path . -s res://tools/snapshot_screen.tscn -- \
  --screen court --resolution 2560x1440 --out <scratchpad>/no_dots.png
```

Look at it. Confirm: no black dots at any zoom, the gold ring still appears on a clicked settlement, and clicking a town still opens its card.

- [ ] **Step 10: Commit**

```bash
git add data/map3d_settlements.csv data/balance.csv scripts/engine/data_repository.gd \
        scripts/map3d/map3d_layer_settlements.gd scripts/map3d/map3d_picker.gd \
        scripts/map3d/map3d_context.gd scripts/map3d/map3d_view.gd \
        scripts/map3d/settlement_ring.gdshader scenes/map3d/materials \
        tests/map3d
git commit -m "feat(map3d): the settlement dots go; a click picks the cluster

Owner 2026-09-20: the dots and the capital's ring were a placeholder.
The click reach, which was the dot's size, is now the cluster's projected
radius floored at map3d_pick_px — so a city is easier to hit than a hamlet.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 10: Documentation

**Files:**
- Modify: `tools/map3d/README.md`, `CLAUDE.md`, `.claude/skills/visual-review/taste.md`

**Interfaces:**
- Consumes: everything built.
- Produces: nothing code depends on.

- [ ] **Step 1: `tools/map3d/README.md`**

Add `make_houses.py` as its own step beside `fetch_polyhaven.py`, with the exact Blender command and the note that its output is committed. Add to the pipeline description that `bake_world.py` now also writes `bake/houses.csv`. Add the new bench row to the Open items with the number Task 7 measured.

- [ ] **Step 2: `CLAUDE.md`**

In the 3D map section, after the settlements sentence ("**Settlements** are screen-constant SOLID BLACK DOTS..."), replace it with the new truth. Keep the file's voice — one dense sentence with the owner's date and the data keys:

> **Settlements are CLUSTERS OF HOUSES** (owner 2026-09-20, "黑点/黑点+圆圈本就是暂时的placeholder，给我完全替换掉"; spec `docs/superpowers/specs/2026-09-20-map3d-settlement-houses-design.md`): the bake places them (`tools/map3d/bake_houses.py`, called from `sow_patchwork` where the land mask, the population and the footprint already are — so "never in the sea" is structural, and a test asserts it over the whole pack) into `bake/houses.csv` in world metres with no `y`, a `rank` per house so a settlement that GROWS sprouts more with no re-bake; `Map3DHouses` picks which are shown and `Map3DLayerHouses` builds ONE `MultiMesh` per type, cut once per camera pose (`map3d_house_rebuild_move_m`), nothing past `map3d_house_view_m` instanced at all, capped by `graphics_quality.csv`'s `house_budget`. A centre landmark by tier, density falling outward (`house_density_gamma`), and — the owner's own requirement — an EMPTY BUFFER RING between `house_radius_ratio × r_foot` and the footprint's own edge, where the built earth carries on with no houses on it. The meshes are generated by `tools/map3d/make_houses.py` (headless Blender) and COMMITTED to `assets/map3d_houses/`, since `assets/map3d/` is git-ignored and a fresh clone must still draw a town. Roof colour is `terrain_palette.csv` data carried in as the instance colour, so ONE material serves every type. The 2026-09-16 "procedural Blender towns; do not retry" ruling was OVERRULED for the 3D map (it was about the 2D-sprite route); **no base plates** still holds.

- [ ] **Step 3: `.claude/skills/visual-review/taste.md`**

Amend the existing line (currently "That is why procedural Blender towns were abandoned after five rounds; do not retry.") to record the overrule rather than deleting the history:

> **Geometry density beats texture relief** at small draw sizes: at ~80 px per house, what reads is silhouette, not material. That is why procedural Blender towns were abandoned after five rounds *as 2D sprites pasted onto the 2D map*. *Overruled for the 3D map on 2026-09-20 ("推翻它，这次是真3D地图"): meshes standing on Terrain3D under the scene's own sun are a different thing.* What survives unchanged: **no base plates**.

And add, under "Whole-picture coherence":

> **A settlement ends in a buffer, not at its last house** (owner 2026-09-20): between the houses and the fields there is a ring of built earth with nothing on it. A cluster that stops where its buildings stop reads as a sticker.

- [ ] **Step 4: Verify the docs match the code**

Re-read each claim in the CLAUDE.md paragraph against the files. Every name it uses (`bake_houses.py`, `Map3DHouses`, `Map3DLayerHouses`, `map3d_house_rebuild_move_m`, `map3d_house_view_m`, `house_budget`, `house_radius_ratio`, `assets/map3d_houses/`) must exist exactly as spelled.

- [ ] **Step 5: Run the tests and commit**

```bash
./run_tests.sh
git add tools/map3d/README.md CLAUDE.md .claude/skills/visual-review/taste.md
git commit -m "docs(map3d): settlements are house clusters

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 11: The campaign-zoom comparison the owner asked for (spec §8.1)

**Files:**
- Create: three throwaway variant branches or bracketed builds; screenshots under the scratchpad
- Modify: whichever variant the owner picks becomes real code in a follow-up

**Interfaces:**
- Consumes: the working clusters from Tasks 1–9.
- Produces: an owner ruling on what a settlement looks like at 20–150 km.

- [ ] **Step 1: State the problem with its numbers**

At `map3d_zoom_max_m` 150 000 a screen px is ~172 m, so a capital's 1.1 km footprint is 6.6 px and a village is 1 px. With the dots gone there is currently **nothing** there. The owner asked to see all three candidates ("以上每一种你给我个sample看看").

- [ ] **Step 2: Build variant (a) — the cluster as an impostor card**

Render each tier's cluster from straight above to a transparent card, exactly as `tools/map3d/render_impostors.py` already does for trees, and draw the card in place of the meshes past a crossfade distance, with a minimum screen size so a city stays findable.

- [ ] **Step 3: Build variant (b) — names only**

Settlement names on the HUD like the kingdom names (`MapLettering`, `Map3DGeometry.label_px`), sized and gated per tier, nothing else drawn.

- [ ] **Step 4: Build variant (c) — an art symbol per tier**

A tier symbol (not a dot) that fades out as the meshes fade in.

- [ ] **Step 5: Shoot all three at the same pose and crop**

Same settlement, same camera, at 20 km, 60 km and 150 km. Per `.claude/skills/visual-review/`: the three side by side, plus crops. Run the independent critic pass before showing the owner.

- [ ] **Step 6: Present, get the ruling, record it**

Write the ruling into `taste.md` as a principle with its why, into the spec's §8 as resolved, and into `CLAUDE.md`. Then implement the chosen variant properly (the other two are throwaway) and delete the throwaway code.

---

## Self-review

**Spec coverage.** §1 → Tasks 2 and 4 (incl. the blocky-noise conflict, Task 4 Step 4). §2 → Tasks 1 and 3. §3 → Tasks 5, 6, 7; "what is removed" → Task 9. §4 → Task 2's `place()` and Task 1's keys, with the empty ring asserted in both the Python and Godot tests. §5 → Task 1 (all five tables). §6 → Task 7 Step 3, plus `warn_once` on a missing file in Task 5's `load_csv`. §7 → the test files created in Tasks 1–7 and migrated in Task 9; the bench row in Task 7. §8.1 → Task 11; §8.2 → Task 8; §8.3 → left unimplemented by design, noted in Task 10's taste.md entry as still-open history.

**Known soft spots the executor must resolve rather than guess.**
1. Task 9 Step 4's `pick_reach_px` body is explicitly flagged as a placeholder for the real `px_per_dist` conversion — the test is the contract, not the expression.
2. Task 5's `Map3DContext.houses()` uses `repo.map3d_dir()` (`scripts/engine/data_repository.gd:283`), which defaults to the `maps.csv` default pack — correct here, since the context is always built for the loaded pack.
3. Task 4 Step 2 warns that `Map3DHouses` does not exist yet, and says exactly what to do about it.
4. Task 3's Blender path and Task 6's stone preview filename both say "check the real one".

**Type consistency.** `footprint_radius_m(population, rules)` in Python and `Map3DHouses.footprint_radius_m(population, repo)` in GDScript — deliberately different second parameters, with a parity test in Task 4 Step 3 holding the Python pair equal. `place()` returns offsets from the burg centre; `bake_world.py` adds the origin (Task 4 Step 4); `Map3DHouses.load_csv` reads world metres into `at: Vector2`. `visible_set` returns `{type: Array}` and `counts()` returns `{type: int}` — both keyed by the CSV's `type`, which is also the `MultiMeshInstance3D`'s `name.capitalize()`.
