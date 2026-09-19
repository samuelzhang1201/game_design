# HEIGHTS on the 3D Map, and Height in War — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** HEIGHTS draws on the 3D map (a height heat map, named high/low points with their height and a tooltip), and height counts in war (the higher side of a fight gains; standing high burns supplies faster by tier).

**Architecture:** A new pure engine class `Elevation` turns the pack's cell heights into metres, supply tiers and named landmarks. `ArmySystem` reads it for supply use, terrain lines and a height factor in `battle_odds`. On the 3D map, `Map3DGroundTint`'s patched Terrain3D shader gains a height ramp, and `Map3DView` / `Map3DHud` draw the landmarks and a legend and pick them on hover and click.

**Tech Stack:** Godot 4.7, typed GDScript, GUT (`./run_tests.sh`), Terrain3D shader patching, Python (`tools/map3d/bake_world.py`).

**Spec:** `docs/superpowers/specs/2026-09-19-map3d-heights-design.md`

## Global Constraints

- Engine code is `RefCounted`, deterministic: no `Time.*`, no unseeded random; hashes only (`String.hash()`), never the engine RNG stream.
- Every design value in `data/*.csv` (`balance.csv` keys, new tables); none hardcoded.
- Whole numbers and per-mille in the army formulas (`int`), as in `ArmySystem` today.
- The engine and every number shown read CELL height: `metres = (height − elevation_sea_level) × elevation_m_per_unit`, `elevation_sea_level` 20, `elevation_m_per_unit` 30.
- Supply tiers: plains 0/1000, hills 45/1300, mountains 62/1700, peak 72/2200 (`min_height`/`supply_permille`).
- Height factor: `1000 + clamp(Δm × 40 / 100, −300, +300)` per mille (`army_height_bonus_permille_per_100m` 40, `army_height_bonus_cap_permille` 300).
- Authored text never names a kingdom; landmark names come from the pack's town names at runtime.
- Tests run with `./run_tests.sh`; the suite must report the expected error count ("Errors 2" with the gdai plugin installed). A single file: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_elevation.gd -gexit` (use this form for every "run one test" step below; `run_tests.sh` is the gate at each task's end).
- Commit messages end with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`. Stage only the files the task touched (the working tree carries unrelated uncommitted work).
- The 2D map is not modified (its `show_heights` stays as it is; the 2D-deletion spec removes it).

---

### Task 1: The measure — `Elevation.metres_of_cell` and `tier_of`

**Files:**
- Create: `scripts/engine/elevation.gd`
- Create: `data/army_height_supply.csv`
- Modify: `data/balance.csv` (append rows)
- Modify: `scripts/engine/data_repository.gd` (a new table, loaded beside `army_speed.csv`, ~line 469; `Elevation.forget()` in `load_map` beside `HouseArms.forget()`, ~line 516)
- Modify: `tools/map3d/bake_world.py:39-40` (read the two keys from `balance.csv`)
- Test: `tests/engine/test_elevation.gd`

**Interfaces:**
- Produces: `DataRepository.army_height_supply: Array` of `{tier: String, min_height: int, supply_permille: int}` sorted by `min_height` DESCENDING; `Elevation.metres_of_cell(repo, id: int) -> int`; `Elevation.metres_of_height(repo, height: float) -> int`; `Elevation.tier_of(repo, height: float) -> Dictionary` (`{tier, supply_permille}`); `Elevation.forget() -> void`.

- [ ] **Step 1: Write the failing test**

`tests/engine/test_elevation.gd`:

```gdscript
extends GutTest
## Elevation (owner 2026-09-19, spec 2026-09-19-map3d-heights-design §1):
## cell height into metres and supply tiers.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")

func test_metres_from_the_cell_height() -> void:
	assert_eq(Elevation.metres_of_height(repo, 20.0), 0, "the waterline")
	assert_eq(Elevation.metres_of_height(repo, 45.0), 750)
	assert_eq(Elevation.metres_of_height(repo, 100.0), 2400)
	assert_eq(Elevation.metres_of_height(repo, 17.0), -90, "below the waterline")

func test_metres_of_a_cell_reads_its_height() -> void:
	var ids := repo.cells.keys()
	ids.sort()
	var id: int = ids[0]
	assert_eq(Elevation.metres_of_cell(repo, id),
		Elevation.metres_of_height(repo, float(repo.cells[id]["height"])))
	assert_eq(Elevation.metres_of_cell(repo, -1), 0, "no cell is the waterline")

func test_tier_edges() -> void:
	assert_eq(Elevation.tier_of(repo, 44.0)["tier"], "plains")
	assert_eq(Elevation.tier_of(repo, 45.0)["tier"], "hills")
	assert_eq(Elevation.tier_of(repo, 61.0)["tier"], "hills")
	assert_eq(Elevation.tier_of(repo, 62.0)["tier"], "mountains")
	assert_eq(Elevation.tier_of(repo, 71.0)["tier"], "mountains")
	assert_eq(Elevation.tier_of(repo, 72.0)["tier"], "peak")
	assert_eq(int(Elevation.tier_of(repo, 10.0)["supply_permille"]), 1000)
	assert_eq(int(Elevation.tier_of(repo, 50.0)["supply_permille"]), 1300)
	assert_eq(int(Elevation.tier_of(repo, 65.0)["supply_permille"]), 1700)
	assert_eq(int(Elevation.tier_of(repo, 90.0)["supply_permille"]), 2200)

func test_the_table_is_read_highest_first() -> void:
	var mins: Array = repo.army_height_supply.map(func(r: Dictionary) -> int: return int(r["min_height"]))
	assert_eq(mins, [72, 62, 45, 0])
```

- [ ] **Step 2: Run it to verify it fails**

Run the single-file command with `-gtest=res://tests/engine/test_elevation.gd`.
Expected: FAIL / parse error — `Elevation` not declared.

- [ ] **Step 3: Add the data**

`data/army_height_supply.csv`:

```csv
tier,min_height,supply_permille,notes
plains,0,1000,"owner 2026-09-19 (spec 2026-09-19-map3d-heights-design §1): a regiment's monthly supply use by the HEIGHT TIER of its cell, per mille. Read highest first; the lines are the ground's own bands (map_biome_hill/mountain/peak_height) so rock and snow sit where the tiers change"
hills,45,1300,"hills: 30% more to haul up"
mountains,62,1700,"mountains: pack animals, not carts"
peak,72,2200,"above the snow line everything is carried"
```

Append to `data/balance.csv`:

```csv
elevation_sea_level,20,"height (owner 2026-09-19, spec 2026-09-19-map3d-heights-design §1): the Azgaar cell height of the waterline. Elevation.metres_of_cell and tools/map3d/bake_world.py both read it — one measure for the ground and the engine"
elevation_m_per_unit,30,"height: metres per Azgaar height unit above the waterline (100 -> 2400 m). Read by Elevation and bake_world.py"
```

- [ ] **Step 4: Load the table in `DataRepository`**

Near the other army vars (~line 63):

```gdscript
## data/army_height_supply.csv: [{tier, min_height, supply_permille}],
## highest min_height first (Elevation.tier_of reads the first it reaches).
var army_height_supply: Array = []
```

Beside the `army_speed.csv` load (~line 469):

```gdscript
	if not _load_if_present(dir + "/army_height_supply.csv", ["tier", "min_height", "supply_permille"],
			func(r): army_height_supply.append({"tier": String(r["tier"]),
				"min_height": int(r["min_height"]), "supply_permille": int(r["supply_permille"])})):
		return false
	army_height_supply.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a["min_height"]) > int(b["min_height"]))
```

In `load_map`, beside `HouseArms.forget()`:

```gdscript
	Elevation.forget()
```

- [ ] **Step 5: Write `Elevation`**

`scripts/engine/elevation.gd`:

```gdscript
class_name Elevation
extends RefCounted
## Height as numbers (owner 2026-09-19, spec
## docs/superpowers/specs/2026-09-19-map3d-heights-design.md): the pack's
## CELL height in metres, the supply tier it falls in, and (§3) the named
## high and low points. Pure and deterministic; the 3D mesh's synthesized
## ridges are look only and never enter here. Caches are per pack, forgotten
## by DataRepository.load_map.

static var _landmarks: Array = []
static var _landmarks_map := ""


static func forget() -> void:
	_landmarks = []
	_landmarks_map = ""


## Whole metres above the waterline of an Azgaar height (negative under it).
static func metres_of_height(repo: DataRepository, height: float) -> int:
	return int(round((height - repo.bal("elevation_sea_level")) * repo.bal("elevation_m_per_unit")))


## A cell's metres; 0 for no cell.
static func metres_of_cell(repo: DataRepository, id: int) -> int:
	if not repo.cells.has(id):
		return 0
	return metres_of_height(repo, float(repo.cells[id]["height"]))


## {tier, supply_permille}: the first row of army_height_supply.csv, highest
## first, whose min_height the height reaches.
static func tier_of(repo: DataRepository, height: float) -> Dictionary:
	for r: Dictionary in repo.army_height_supply:
		if height >= float(r["min_height"]):
			return {"tier": String(r["tier"]), "supply_permille": int(r["supply_permille"])}
	return {"tier": "plains", "supply_permille": 1000}
```

- [ ] **Step 6: Point the bake at the same numbers**

In `tools/map3d/bake_world.py`, replace

```python
SEA_LEVEL = 20.0         # Azgaar height of the waterline
LAND_M_PER_UNIT = 30.0   # ~2400 m for the highest cells
```

with

```python
def _balance(key):
    """A balance.csv value — the engine's Elevation reads the same row."""
    with open(os.path.join(ROOT, "data", "balance.csv"), newline="") as f:
        for row in csv.DictReader(f):
            if row["key"] == key:
                return float(row["value"])
    raise KeyError(key)


SEA_LEVEL = _balance("elevation_sea_level")        # Azgaar height of the waterline
LAND_M_PER_UNIT = _balance("elevation_m_per_unit")  # ~2400 m for the highest cells
```

Add `import csv` at the top if it is not already imported (check with `grep -n "^import" tools/map3d/bake_world.py`), and check that `balance.csv`'s header is `key,value,...` (`head -1 data/balance.csv`). Verify: `python3 -c "import sys; sys.path.insert(0,'tools/map3d'); import bake_world as b; print(b.SEA_LEVEL, b.LAND_M_PER_UNIT)"` prints `20.0 30.0` (if importing runs the bake, instead run `python3 tools/map3d/bake_world.py --help` and check it starts without a KeyError).

- [ ] **Step 7: Run the test to verify it passes**

Run the single-file command. Expected: 4/4 PASS.

- [ ] **Step 8: Run the whole suite, then commit**

Run: `./run_tests.sh`. Expected: all pass, the expected error count.

```bash
git add scripts/engine/elevation.gd scripts/engine/elevation.gd.uid data/army_height_supply.csv data/balance.csv scripts/engine/data_repository.gd tools/map3d/bake_world.py tests/engine/test_elevation.gd tests/engine/test_elevation.gd.uid
git commit -m "feat(height): Elevation — cell height in metres and supply tiers"
```

(`.uid` files appear after Godot first sees the script; add them if present.)

---

### Task 2: Height in war — `ArmySystem`

**Files:**
- Modify: `scripts/engine/army_system.gd` (`supply_use` ~45, `terrain_of` ~78, `battle_odds` ~276, new `elevation_of`, `height_factor`, `height_label`)
- Modify: `scripts/engine/map_objects.gd` (`army_card`, ~line 1505: an `army_height` stat)
- Modify: `data/resource_icons.csv` (an `army_height` row)
- Modify: `data/balance.csv` (two rows)
- Test: `tests/engine/test_army_height.gd` (new); fix `tests/engine/test_army_system.gd:31,43-49`, `tests/engine/test_army_terrain.gd:36-52`

**Interfaces:**
- Consumes: `Elevation.metres_of_cell`, `Elevation.tier_of` (Task 1).
- Produces: `ArmySystem.elevation_of(repo, reg: Dictionary) -> int`; `ArmySystem.height_factor(repo, delta_m: int) -> int`; `ArmySystem.height_tier(repo, reg: Dictionary) -> Dictionary` (`{tier, supply_permille}`, plains/1000 for a fleet); `ArmySystem.supply_use` now tier-scaled.

- [ ] **Step 1: Write the failing test**

`tests/engine/test_army_height.gd`:

```gdscript
extends GutTest
## Height in war (owner 2026-09-19, spec 2026-09-19-map3d-heights-design §2):
## the higher side of a fight gains, the lower loses by as much; a regiment
## uses supplies by its cell's height tier.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")

func _at_cell(id: int, naval := false) -> Dictionary:
	var c := MapTerrain.cell_center(repo, repo.cells[id])
	return {"regiment_code": "t", "kingdom_code": "t", "x": str(c.x), "y": str(c.y),
		"is_naval": "1" if naval else "0", "infantry": "1000"}

func _land_cell(pred: Callable) -> int:
	var ids := repo.cells.keys()
	ids.sort()
	for id: int in ids:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell) or (cell["vertex_ids"] as PackedInt32Array).size() < 3:
			continue
		if pred.call(cell):
			return id
	return -1

func test_height_factor() -> void:
	assert_eq(ArmySystem.height_factor(repo, 0), 1000)
	assert_eq(ArmySystem.height_factor(repo, 500), 1200, "40 per 100 m")
	assert_eq(ArmySystem.height_factor(repo, -500), 800)
	assert_eq(ArmySystem.height_factor(repo, 1000), 1300, "capped")
	assert_eq(ArmySystem.height_factor(repo, -1000), 700, "capped")

func test_elevation_of_reads_the_cell_and_a_fleet_is_at_zero() -> void:
	var id := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= 50.0)
	assert_gte(id, 0)
	assert_eq(ArmySystem.elevation_of(repo, _at_cell(id)), Elevation.metres_of_cell(repo, id))
	assert_eq(ArmySystem.elevation_of(repo, _at_cell(id, true)), 0)

func test_supply_use_goes_up_by_tier() -> void:
	var low := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) < 45.0)
	var high := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= 62.0 and float(c["height"]) < 72.0)
	assert_gte(low, 0)
	assert_gte(high, 0, "the pack has mountains")
	var base := ArmySystem.headcount(repo, _at_cell(low)) * 100 / 1000
	assert_eq(ArmySystem.supply_use(repo, _at_cell(low)), base)
	assert_eq(ArmySystem.supply_use(repo, _at_cell(high)), base * 1700 / 1000)
	assert_eq(ArmySystem.supply_use(repo, _at_cell(high, true)), base, "a fleet is not scaled")

func test_terrain_follows_the_tier_lines() -> void:
	var h := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= 45.0 and float(c["height"]) < 52.0)
	assert_gte(h, 0, "the pack has ground between the old and new hill lines")
	assert_eq(ArmySystem.terrain_of(repo, _at_cell(h)), "hills")
	var p := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= 72.0)
	if p >= 0:
		assert_eq(ArmySystem.terrain_of(repo, _at_cell(p)), "mountains", "a peak fights as a mountain")

func test_battle_odds_swap_symmetrically_with_the_ground() -> void:
	# Two copies of one regiment on different ground: the odds of A on B
	# and of B on A sum to 1 when their powers are equal, and the higher
	# one's odds are above one half.
	var s := GameState.new_campaign(repo, 7)
	var mine := MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))
	var land: Array = mine.filter(func(r: Dictionary) -> bool: return String(r.get("is_naval", "0")) != "1")
	assert_gte(land.size(), 2)
	var a := String(land[0]["regiment_code"])
	var b := String(land[1]["regiment_code"])
	var ea := ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, a))
	var eb := ArmySystem.elevation_of(repo, ArmySystem.regiment(repo, b))
	var pa := ArmySystem.power(repo, s, a, "attack")
	var pd := ArmySystem.power(repo, s, b, "defend")
	var fa := ArmySystem.height_factor(repo, ea - eb)
	var fd := ArmySystem.height_factor(repo, eb - ea)
	var expected := float(pa * fa / 1000) / float(pa * fa / 1000 + pd * fd / 1000)
	assert_almost_eq(ArmySystem.battle_odds(repo, s, a, b), expected, 0.0001)
```

- [ ] **Step 2: Run it to verify it fails**

Expected: FAIL — `height_factor` / `elevation_of` not found.

- [ ] **Step 3: Add the balance rows**

Append to `data/balance.csv`:

```csv
army_height_bonus_permille_per_100m,40,"height in war (owner 2026-09-19, spec 2026-09-19-map3d-heights-design §2): per mille a side gains for every 100 m it stands above the other in a fight, and the lower side loses; ArmySystem.height_factor"
army_height_bonus_cap_permille,300,"height in war: the most a height difference moves a side's power either way, per mille (+-30%, reached at 750 m)"
```

- [ ] **Step 4: Implement in `ArmySystem`**

Replace `supply_use`:

```gdscript
## Supplies a regiment uses in a month: the headcount's use times its cell's
## height tier (data/army_height_supply.csv, spec 2026-09-19-map3d-heights
## §2) — a fleet is not scaled.
static func supply_use(repo: DataRepository, reg: Dictionary) -> int:
	var base := headcount(repo, reg) * int(repo.bal("army_supply_per_head_permille")) / 1000
	return base * int(height_tier(repo, reg)["supply_permille"]) / 1000
```

In `terrain_of`, replace the two height tests

```gdscript
	var h := float(cell["height"])
	if h >= repo.bal("manor_focus_peak_height"):
		return "mountains"
	if h >= repo.bal("manor_focus_high_height"):
		return "hills"
```

with

```gdscript
	# The supply tiers' lines (Elevation.tier_of): a peak fights as a mountain.
	match String(Elevation.tier_of(repo, float(cell["height"]))["tier"]):
		"peak", "mountains":
			return "mountains"
		"hills":
			return "hills"
```

and update its doc comment's "(the manors' own thresholds)" to "(the supply tiers' lines, Elevation.tier_of)".

Add after `terrain_label`:

```gdscript
## --- Height (spec 2026-09-19-map3d-heights §2) ---------------------------

## The cell under a regiment, -1 for a fleet or off the land.
static func _cell_of(repo: DataRepository, reg: Dictionary) -> int:
	if String(reg.get("is_naval", "0")) == "1":
		return -1
	return MapEconomy.cell_at(repo, Vector2(float(reg["x"]), float(reg["y"])))

## Whole metres the regiment stands at; 0 for a fleet or off the land.
static func elevation_of(repo: DataRepository, reg: Dictionary) -> int:
	return Elevation.metres_of_cell(repo, _cell_of(repo, reg))

## {tier, supply_permille} of the regiment's cell; plains / 1000 for a fleet.
static func height_tier(repo: DataRepository, reg: Dictionary) -> Dictionary:
	var id := _cell_of(repo, reg)
	if id < 0:
		return {"tier": "plains", "supply_permille": 1000}
	return Elevation.tier_of(repo, float(repo.cells[id]["height"]))

## Per mille on a side's power for standing delta_m above (or, negative,
## below) the other: army_height_bonus_permille_per_100m, capped either way.
static func height_factor(repo: DataRepository, delta_m: int) -> int:
	var cap := int(repo.bal("army_height_bonus_cap_permille"))
	return 1000 + clampi(delta_m * int(repo.bal("army_height_bonus_permille_per_100m")) / 100, -cap, cap)
```

Replace the body of `battle_odds` (keep its PLACEHOLDER comment, adding a line that height is its first settled factor):

```gdscript
static func battle_odds(repo: DataRepository, state: GameState, attacker_code: String, defender_code: String) -> float:
	var delta := elevation_of(repo, regiment(repo, attacker_code)) \
		- elevation_of(repo, regiment(repo, defender_code))
	var a := power(repo, state, attacker_code, "attack") * height_factor(repo, delta) / 1000
	var d := power(repo, state, defender_code, "defend") * height_factor(repo, -delta) / 1000
	if a + d <= 0:
		return 0.5
	return float(a) / float(a + d)
```

- [ ] **Step 5: The card row**

In `MapObjects.army_card`, right after the `army_terrain` stat line:

```gdscript
		var metres := ArmySystem.elevation_of(repo, r)
		var tier := ArmySystem.height_tier(repo, r)
		var mult := float(int(tier["supply_permille"])) / 1000.0
		stats.append(_stat("army_height", "%d m · ×%.1f" % [metres, mult],
			"Height — %d m, %s: supplies are used ×%.1f here. In a fight each 100 m above the foe is +%d%% (at most +%d%%), and below it as much less" % [
				metres, String(tier["tier"]), mult,
				int(repo.bal("army_height_bonus_permille_per_100m")) / 10,
				int(repo.bal("army_height_bonus_cap_permille")) / 10]))
```

Add to `data/resource_icons.csv` right after the `army_terrain` row (same column shape — `key,label,icon,tooltip,texture`, texture empty until art is installed):

```csv
army_height,Height,tower,"The height the regiment stands at and how much faster it uses supplies there; in a fight the higher side gains (owner 2026-09-19).",
```

- [ ] **Step 6: Fix the tests the tiers move**

`tests/engine/test_army_system.gd`: line 31 becomes

```gdscript
	assert_eq(int(entry["supplies"]), ArmySystem.supply_use(repo, r) * 6)
```

and in `test_the_month_returns_wounded_and_spends_supplies`, `var use := heads * 100 / 1000` becomes `var use := ArmySystem.supply_use(repo, r)` (drop `heads` if unused; keep a separate test holding the base: `assert_eq(ArmySystem.supply_use(repo, r), heads * 100 / 1000 * int(ArmySystem.height_tier(repo, r)["supply_permille"]) / 1000)`).

`tests/engine/test_army_terrain.gd`: in `test_height_makes_mountains_and_hills` and `test_low_ground_takes_its_biomes_terrain`, replace `repo.bal("manor_focus_peak_height")` with `62.0` read from the table and `manor_focus_high_height` with `45.0` from the table:

```gdscript
	var peak := 62.0  # the mountains tier's min_height (army_height_supply.csv)
	var high := 45.0  # the hills tier's
```

Better, read them: `var high := float(repo.army_height_supply.filter(func(r): return r["tier"] == "hills")[0]["min_height"])` and likewise `mountains` — use that form.

Check `tests/engine/test_map_objects.gd:403` still holds (it reads `supply_use`, so it should) and add, in the army-card test there, `assert_true(text.has("army_height"))`, reading how that test builds `text` first.

- [ ] **Step 7: Run the tests**

Run `test_army_height.gd`, `test_army_system.gd`, `test_army_terrain.gd`, `test_army_power.gd`, `test_army_speed.gd`, `test_map_objects.gd` one by one. Expected: PASS. If `test_terrain_follows_the_tier_lines` finds no cell between 45 and 52, change its predicate to any cell in [45, 62) and keep the "hills" assertion.

- [ ] **Step 8: Suite and commit**

`./run_tests.sh`, then:

```bash
git add scripts/engine/army_system.gd scripts/engine/map_objects.gd data/resource_icons.csv data/balance.csv tests/engine/test_army_height.gd tests/engine/test_army_height.gd.uid tests/engine/test_army_system.gd tests/engine/test_army_terrain.gd tests/engine/test_map_objects.gd
git commit -m "feat(army): height in war — the higher side gains, supplies by height tier"
```

---

### Task 3: Landmarks — high and low points, named

**Files:**
- Modify: `scripts/engine/elevation.gd` (`landmarks`, `local_edge_m`, naming)
- Create: `data/landmark_names.csv`
- Modify: `data/balance.csv` (rows)
- Modify: `scripts/engine/data_repository.gd` (`landmark_names`, pack `landmark_name_overrides`)
- Test: `tests/engine/test_elevation.gd` (extend)

**Interfaces:**
- Consumes: Task 1.
- Produces: `Elevation.landmarks(repo) -> Array` of `{cell: int, kind: "high"|"low", metres: int, prominence: int, lod: int (0 far .. 2 near), name: String, pos: Vector2 (pack px)}`, sorted by prominence DESC then cell id ASC; `Elevation.landmark_at(repo, cell: int) -> Dictionary` (`{}` if none); `Elevation.local_edge_m(repo, id: int) -> int`; `Elevation.extremes(cells: Dictionary) -> Dictionary` (`{"high": PackedInt32Array, "low": PackedInt32Array}`, pure on a cells dict — the testable core); `DataRepository.landmark_names: Dictionary` kind → `Array` of `String`; `DataRepository.landmark_name_overrides: Dictionary` cell id → name.

- [ ] **Step 1: Write the failing tests**

Append to `tests/engine/test_elevation.gd`:

```gdscript
## A hand-built strip of land cells 0..4 (heights 30, 50, 40, 25, 35) and
## one sea cell 5 next to cell 4. High: 1, and 4 (above its one land
## neighbour). Low: 0 and 3; 4 touches the sea, so it is never a basin.
func _strip() -> Dictionary:
	var hs := [30.0, 50.0, 40.0, 25.0, 35.0]
	var cells := {}
	for i in hs.size():
		var nb := PackedInt32Array()
		if i > 0:
			nb.append(i - 1)
		if i < hs.size() - 1:
			nb.append(i + 1)
		cells[i] = {"height": hs[i], "water": "", "neighbor_ids": nb,
			"vertex_ids": PackedInt32Array([0, 1, 2])}
	(cells[4]["neighbor_ids"] as PackedInt32Array).append(5)
	cells[5] = {"height": 10.0, "water": "ocean", "neighbor_ids": PackedInt32Array([4]),
		"vertex_ids": PackedInt32Array([0, 1, 2])}
	return cells

func test_extremes_on_a_strip() -> void:
	var e := Elevation.extremes(_strip())
	assert_eq(Array(e["high"]), [1, 4], "4 is above its one land neighbour")
	assert_eq(Array(e["low"]), [0, 3], "4 touches the sea, so it is no basin")

func test_a_plateau_keeps_one_high_point() -> void:
	var cells := _strip()
	cells[2]["height"] = 50.0  # 1 and 2 tie
	var e := Elevation.extremes(cells)
	assert_true(1 in Array(e["high"]), "the lower id wins a tie")
	assert_false(2 in Array(e["high"]))

func test_landmarks_on_the_pack() -> void:
	var marks := Elevation.landmarks(repo)
	assert_gt(marks.size(), 0)
	var prev := 1 << 30
	for m: Dictionary in marks:
		assert_true(int(m["prominence"]) <= prev, "biggest first")
		prev = int(m["prominence"])
		assert_gte(int(m["prominence"]), int(repo.bal("landmark_min_prominence_m")))
		assert_ne(String(m["name"]), "")
		assert_true(int(m["lod"]) in [0, 1, 2])
	var names := {}
	for m: Dictionary in marks:
		assert_false(names.has(m["name"]), "names are unique: " + String(m["name"]))
		names[m["name"]] = true

func test_the_lod_follows_prominence() -> void:
	for m: Dictionary in Elevation.landmarks(repo):
		var p := int(m["prominence"])
		var want := 0 if p >= int(repo.bal("landmark_lod_far_m")) \
			else (1 if p >= int(repo.bal("landmark_lod_mid_m")) else 2)
		assert_eq(int(m["lod"]), want)

func test_a_name_override_wins() -> void:
	var m: Dictionary = Elevation.landmarks(repo)[0]
	repo.landmark_name_overrides[int(m["cell"])] = "The Old Man"
	Elevation.forget()
	assert_eq(Elevation.landmark_at(repo, int(m["cell"]))["name"], "The Old Man")
	repo.landmark_name_overrides.erase(int(m["cell"]))
	Elevation.forget()

func test_local_edge() -> void:
	var m: Dictionary = Elevation.landmarks(repo)[0]
	var edge := Elevation.local_edge_m(repo, int(m["cell"]))
	assert_eq(absi(edge), int(m["prominence"]), "the prominence is the edge's size")
```

- [ ] **Step 2: Run to verify they fail**

Expected: FAIL — `extremes` / `landmarks` not found.

- [ ] **Step 3: Data**

`data/landmark_names.csv`:

```csv
kind,pattern,notes
high,Mount {town},"owner 2026-09-19 (spec 2026-09-19-map3d-heights-design §3): a landmark is named after its nearest town; the pattern is picked by a hash of the cell, the next one on a clash"
high,{town} Fell,
high,{town} Crag,
high,{town} Heights,
low,{town} Vale,
low,{town} Hollow,
low,{town} Basin,
```

Append to `data/balance.csv` (draft values; Step 6 tunes them):

```csv
landmark_ring,2,"landmarks (owner 2026-09-19, spec 2026-09-19-map3d-heights-design §3): rings of neighbours a high or low point is measured against"
landmark_min_prominence_m,60,"landmarks: metres a point must stand above (or below) the mean of its rings to be marked"
landmark_lod_mid_m,150,"landmarks: prominence at/above which a point still shows at the middle zooms (lod 1)"
landmark_lod_far_m,300,"landmarks: prominence at/above which a point shows at every zoom (lod 0)"
```

- [ ] **Step 4: Load the names in `DataRepository`**

Vars:

```gdscript
## data/landmark_names.csv: kind ("high"|"low") -> patterns in file order.
var landmark_names: Dictionary = {}
## maps/<id>/landmark_name_overrides.csv (optional): cell id -> name.
var landmark_name_overrides: Dictionary = {}
```

With the global tables (beside `army_height_supply.csv`):

```gdscript
	if not _load_if_present(dir + "/landmark_names.csv", ["kind", "pattern"],
			func(r):
				var k := String(r["kind"])
				if not landmark_names.has(k):
					landmark_names[k] = []
				(landmark_names[k] as Array).append(String(r["pattern"]))):
		return false
```

(An `Array` in the Dictionary, not a `PackedStringArray`: packed arrays are values, so appending to one read out of a Dictionary would not stick.)

In `load_map`, beside `manor_name_overrides.csv` (~line 618), first `landmark_name_overrides.clear()` then:

```gdscript
	if not _load_if_present(dir + "/landmark_name_overrides.csv", ["cell_id", "name"],
			func(r): landmark_name_overrides[int(r["cell_id"])] = String(r["name"])):
		return false
```

(`_load_if_present` already treats a missing file as fine — confirm by reading it at ~line 790.)

- [ ] **Step 5: Implement in `Elevation`**

```gdscript
## A land cell the landmarks count: not water, a real polygon.
static func _is_land(cell: Dictionary) -> bool:
	return String(cell.get("water", "")) == "" \
		and (cell["vertex_ids"] as PackedInt32Array).size() >= 3


## Whether a outranks b as a high point: higher, or level with a lower id.
static func _above(ha: float, a: int, hb: float, b: int) -> bool:
	return ha > hb or (ha == hb and a < b)


## The high points (land cells above every land neighbour; a tie goes to the
## lower id, so a plateau keeps one) and the low points (land cells below
## every neighbour and touching no water — a basin, not a shore), each in id
## order. Pure on a cells dict so a test can hand-build one.
static func extremes(cells: Dictionary) -> Dictionary:
	var high := PackedInt32Array()
	var low := PackedInt32Array()
	var ids := cells.keys()
	ids.sort()
	for id: int in ids:
		var c: Dictionary = cells[id]
		if not _is_land(c):
			continue
		var h := float(c["height"])
		var is_high := true
		var is_low := true
		var land_nb := 0
		for n: int in c["neighbor_ids"]:
			if not cells.has(n):
				continue
			var nc: Dictionary = cells[n]
			if not _is_land(nc):
				is_low = false
				continue
			land_nb += 1
			var hn := float(nc["height"])
			if not _above(h, id, hn, n):
				is_high = false
			if not _above(hn, n, h, id):
				is_low = false
		if land_nb == 0:
			continue
		if is_high:
			high.append(id)
		elif is_low:
			low.append(id)
	return {"high": high, "low": low}


## The land cells out to `rings` rings round `id` (not `id` itself), in
## breadth-first order.
static func _ring_cells(repo: DataRepository, id: int, rings: int) -> Array:
	var seen := {id: true}
	var frontier := [id]
	var out: Array = []
	for _r in rings:
		var next: Array = []
		for c: int in frontier:
			for n: int in repo.cells[c]["neighbor_ids"]:
				if seen.has(n) or not repo.cells.has(n) or not _is_land(repo.cells[n]):
					continue
				seen[n] = true
				next.append(n)
				out.append(n)
		frontier = next
	return out


## Metres the cell stands above the mean of its landmark_ring rings (negative
## below it); 0 with no land round it.
static func local_edge_m(repo: DataRepository, id: int) -> int:
	var ring := _ring_cells(repo, id, int(repo.bal("landmark_ring")))
	if ring.is_empty():
		return 0
	var sum := 0
	for n: int in ring:
		sum += metres_of_cell(repo, n)
	return metres_of_cell(repo, id) - int(round(float(sum) / ring.size()))


## Every landmark of the pack, biggest prominence first (ties by cell id),
## named; cached per pack.
static func landmarks(repo: DataRepository) -> Array:
	if _landmarks_map == repo.map_id and not _landmarks.is_empty():
		return _landmarks
	var e := extremes(repo.cells)
	var out: Array = []
	var floor_m := int(repo.bal("landmark_min_prominence_m"))
	for kind: String in ["high", "low"]:
		for id: int in e[kind]:
			var edge := local_edge_m(repo, id)
			var prom := absi(edge)
			if prom < floor_m:
				continue
			out.append({"cell": id, "kind": kind, "metres": metres_of_cell(repo, id),
				"prominence": prom, "lod": _lod(repo, prom), "name": "",
				"pos": MapTerrain.cell_center(repo, repo.cells[id])})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["prominence"] == b["prominence"]:
			return int(a["cell"]) < int(b["cell"])
		return a["prominence"] > b["prominence"])
	_name_all(repo, out)
	_landmarks = out
	_landmarks_map = repo.map_id
	return out


static func landmark_at(repo: DataRepository, cell: int) -> Dictionary:
	for m: Dictionary in landmarks(repo):
		if int(m["cell"]) == cell:
			return m
	return {}


static func _lod(repo: DataRepository, prominence: int) -> int:
	if prominence >= int(repo.bal("landmark_lod_far_m")):
		return 0
	if prominence >= int(repo.bal("landmark_lod_mid_m")):
		return 1
	return 2


## Names in prominence order, so the biggest gets its first choice: an
## override, else the patterns from a hash of the cell over the nearest town,
## then the next-nearest; never a name already given.
static func _name_all(repo: DataRepository, marks: Array) -> void:
	var taken := {}
	var towns := repo.burgs.keys()
	towns.sort()
	for m: Dictionary in marks:
		var id := int(m["cell"])
		if repo.landmark_name_overrides.has(id):
			m["name"] = String(repo.landmark_name_overrides[id])
			taken[m["name"]] = true
			continue
		var patterns: Array = repo.landmark_names.get(String(m["kind"]), [])
		if patterns.is_empty():
			continue
		var at: Vector2 = m["pos"]
		var by_dist := towns.duplicate()
		by_dist.sort_custom(func(a: String, b: String) -> bool:
			var da := at.distance_squared_to(Vector2(float(repo.burgs[a]["x"]), float(repo.burgs[a]["y"])))
			var db := at.distance_squared_to(Vector2(float(repo.burgs[b]["x"]), float(repo.burgs[b]["y"])))
			return da < db if da != db else a < b)
		var start := posmod(str(id).hash(), patterns.size())
		for town: String in by_dist:
			var label := String(repo.burgs[town].get("label", town))
			for k in patterns.size():
				var name := String(patterns[(start + k) % patterns.size()]).replace("{town}", label)
				if not taken.has(name):
					m["name"] = name
					break
			if String(m["name"]) != "":
				break
		taken[m["name"]] = true
```

Note: `repo.map_id` — confirm the field name DataRepository uses for the loaded pack (`grep -n "var map_id\|current_map" scripts/engine/data_repository.gd`) and use it.

- [ ] **Step 6: Run the tests, then look at the counts and tune**

Run `test_elevation.gd`. Expected: PASS.

Then print the distribution:

```bash
cat > /tmp/claude-lm.gd <<'EOF'
extends SceneTree
func _init() -> void:
	var repo := DataRepository.load_all("res://data")
	var n := [0, 0, 0]
	var kinds := {"high": 0, "low": 0}
	for m: Dictionary in Elevation.landmarks(repo):
		n[int(m["lod"])] += 1
		kinds[m["kind"]] += 1
	print("lod counts ", n, " kinds ", kinds)
	for m in Elevation.landmarks(repo).slice(0, 8):
		print(m["name"], " ", m["metres"], " m, prom ", m["prominence"])
	quit()
EOF
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s /tmp/claude-lm.gd
```

(put the script in the session scratchpad rather than /tmp if one is listed.) Target: lod 0 about 8–20 (the major peaks and a few basins), lod 0+1 about 30–70, total under ~200. Adjust `landmark_min_prominence_m`, `landmark_lod_mid_m`, `landmark_lod_far_m` in `balance.csv` until it lands there, and record the final counts in the commit message.

- [ ] **Step 7: Suite and commit**

```bash
git add scripts/engine/elevation.gd scripts/engine/data_repository.gd data/landmark_names.csv data/balance.csv tests/engine/test_elevation.gd
git commit -m "feat(height): landmarks — named high and low points by prominence"
```

---

### Task 4: The landmark's words — tooltip and card lines

**Files:**
- Modify: `scripts/engine/map_objects.gd` (`label_of` gains `"landmark"`; new `landmark_lines`)
- Test: `tests/engine/test_elevation.gd` (or a new `tests/engine/test_landmark_card.gd`)

**Interfaces:**
- Consumes: Tasks 1–3.
- Produces: `MapObjects.landmark_lines(repo, state: GameState, cell: int) -> PackedStringArray` — the tooltip's lines after the name; `MapObjects.label_of(repo, {"kind": "landmark", "cell": id})` — the name and lines joined by `"\n"` (the hover tooltip's text).

- [ ] **Step 1: Write the failing test**

`tests/engine/test_landmark_card.gd`:

```gdscript
extends GutTest
## A landmark's words (spec 2026-09-19-map3d-heights-design §4): its name,
## height, tier and biome, where it is and who holds it, and what it means
## for a garrison and a fight.

func before_each() -> void:
	Game.start_campaign(42)

func test_the_lines_of_the_highest_landmark() -> void:
	var m: Dictionary = Elevation.landmarks(Game.data)[0]
	var id := int(m["cell"])
	var lines := MapObjects.landmark_lines(Game.data, Game.state, id)
	var tier := Elevation.tier_of(Game.data, float(Game.data.cells[id]["height"]))
	assert_string_contains(lines[0], "%d m" % int(m["metres"]))
	assert_string_contains(lines[0], String(tier["tier"]).capitalize())
	var province := MapManors.province_of(Game.data, id, Game.state)
	assert_string_contains(lines[1], String(Game.data.provinces[province].get("label", province)))
	assert_string_contains(lines[2], "×%.1f" % (float(int(tier["supply_permille"])) / 1000.0))
	var edge := Elevation.local_edge_m(Game.data, id)
	var pct := (ArmySystem.height_factor(Game.data, absi(edge)) - 1000) / 10
	assert_string_contains(lines[3], "%d m" % absi(edge))
	assert_string_contains(lines[3], "%d%%" % pct)

func test_the_hover_text_starts_with_the_name() -> void:
	var m: Dictionary = Elevation.landmarks(Game.data)[0]
	var text := MapObjects.label_of(Game.data, {"kind": "landmark", "cell": int(m["cell"])})
	assert_true(text.begins_with(String(m["name"]) + "\n"))
```

- [ ] **Step 2: Run to verify it fails**

- [ ] **Step 3: Implement**

`MapObjects` is engine code and must not reach for the `Game` autoload, so give `label_of` an optional state — `static func label_of(repo: DataRepository, obj: Dictionary, state: GameState = null) -> String:` (existing callers keep working) — and add to its `match`:

```gdscript
		"landmark":
			var id := int(obj.get("cell", -1))
			var m := Elevation.landmark_at(repo, id)
			if m.is_empty():
				return ""
			return String(m["name"]) + "\n" + "\n".join(landmark_lines(repo, state, id))
```

`Map3DView.hover_pick` passes the state in Task 6.

Add:

```gdscript
## A landmark's facts, one per line (spec 2026-09-19-map3d-heights §4):
## height · tier · biome; province — holder; the garrison's supply; the
## edge over the land round it and what it is worth in a fight.
static func landmark_lines(repo: DataRepository, state: GameState, cell: int) -> PackedStringArray:
	var c: Dictionary = repo.cells[cell]
	var tier := Elevation.tier_of(repo, float(c["height"]))
	var biome := String((repo.biomes.get(int(c["biome_id"]), {}) as Dictionary).get("label", ""))
	var province := MapManors.province_of(repo, cell, state)
	var where := _label(repo.provinces, province) if province != "" else ""
	var holder := MapManors.owner_of(repo, state, cell)
	var mult := float(int(tier["supply_permille"])) / 1000.0
	var edge := Elevation.local_edge_m(repo, cell)
	var pct := (ArmySystem.height_factor(repo, absi(edge)) - 1000) / 10
	var out := PackedStringArray()
	out.append("%d m · %s · %s" % [Elevation.metres_of_cell(repo, cell), String(tier["tier"]).capitalize(), biome])
	out.append("%s — %s" % [where, holder] if holder != "" else where)
	out.append("Garrison: supplies ×%.1f (%s)" % [mult, String(tier["tier"])])
	if edge >= 0:
		out.append("%d m above the land around — +%d%% in a fight against it" % [edge, pct])
	else:
		out.append("%d m below the land around — −%d%% fighting up out of it" % [-edge, pct])
	return out
```

(`_label` is MapObjects' existing helper taking a table and a code — confirm its signature with `grep -n "static func _label" scripts/engine/map_objects.gd`.)

- [ ] **Step 4: Run, suite, commit**

```bash
git add scripts/engine/map_objects.gd tests/engine/test_landmark_card.gd tests/engine/test_landmark_card.gd.uid
git commit -m "feat(height): a landmark's tooltip and card lines"
```

---

### Task 5: The heat on the 3D ground, and HEIGHTS staying on 3D

**Files:**
- Modify: `scripts/map3d/map3d_ground_tint.gd` (uniforms, the ALBEDO mix)
- Modify: `scripts/map3d/map3d_view.gd` (`_prepare_ground_tint`, `_refresh_theme`, `pick_at` ~1701)
- Modify: `scripts/ui/game_root.gd` (`_sync_map_view` ~438)
- Modify: `data/balance.csv` (`map3d_heat_tint`)
- Test: `tests/map3d/test_map3d_ground_tint.gd`, `tests/map3d/test_map3d_tab.gd`, `tests/map3d/test_map3d_heights.gd` (new)

**Interfaces:**
- Consumes: `Elevation` metres constants via `balance.csv`.
- Produces: `Map3DView.set_manor_theme("heights")` (the theme string, now one of `""`, `"manors"`, `"heights"`); `Map3DView.heat_on() -> bool` (test seam: true when the heat mix is set); GameRoot hands `"heights"` down.

- [ ] **Step 1: Write the failing tests**

In `tests/map3d/test_map3d_ground_tint.gd`, add (read the file first; follow how it calls `patch` on a sample code string):

```gdscript
func test_the_patch_carries_the_heat_ramp() -> void:
	var code := "shader_type spatial;\nrender_mode blend_mix;\nvoid fragment() {\n\t" \
		+ Map3DGroundTint.ALBEDO_LINE + "\n}\n"
	var out := Map3DGroundTint.patch(code)
	assert_string_contains(out, "uniform float heat_mix")
	assert_string_contains(out, "uniform vec4 heat_c5")
	assert_string_contains(out, "heat_mix > 0.0")
```

`tests/map3d/test_map3d_heights.gd` (fixture as in `test_map3d_manor_themes.gd`):

```gdscript
extends GutTest
## HEIGHTS on the 3D map (owner 2026-09-19, spec 2026-09-19-map3d-heights).

const FIXTURE := "user://test_map3d_heights_world.tscn"
const WORLD := {"m_per_px": 50.0, "pack_origin": [-64000.0, -23220.0],
	"pack_px": [2560, 929], "sea_y": 5.0}

func before_all() -> void:
	var root := Node3D.new()
	root.name = "Fixture"
	root.set_meta("map3d_world", WORLD)
	var packed := PackedScene.new()
	packed.pack(root)
	ResourceSaver.save(packed, FIXTURE)
	root.free()

func before_each() -> void:
	Game.start_campaign(42)

func _view() -> Map3DView:
	var v := Map3DView.create(Game.data, FIXTURE)
	v.size = Vector2(800, 450)
	add_child_autofree(v)
	v.activate()
	return v

func test_heights_is_a_theme_of_its_own() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	assert_eq(v.manor_theme(), "heights")
	assert_true(v.heat_on())
	assert_null(v.cell_lut(), "no manor colours under HEIGHTS")
	v.set_manor_theme("manors")
	assert_false(v.heat_on())
	v.set_manor_theme("")
	assert_false(v.heat_on())

func test_under_heights_land_still_means_its_province() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	var picked := v.pick_at(v.size * 0.5)
	assert_ne(String(picked.get("kind", "")), "manor", "manors are picked only under MANORS")
```

`heat_on()` must work without a Terrain3D (the fixture has none): keep a `_heat` bool in the view that `_refresh_theme` sets, and return it.

In `tests/map3d/test_map3d_tab.gd`:
- Delete `test_each_2d_only_layer_shows_the_2d_map_and_closing_it_returns_to_3d`, replacing it with:

```gdscript
## HEIGHTS draws on the 3D map (owner 2026-09-19, spec 2026-09-19-map3d-heights).
func test_heights_stays_on_the_3d_map_and_reaches_it() -> void:
	var r: GameRoot = await _court()
	r.set_height_view(true)
	assert_true(_shows_3d(r))
	assert_eq(r.current_screen.map3d_view().manor_theme(), "heights")
	r.set_manor_view(true)
	assert_eq(r.current_screen.map3d_view().manor_theme(), "manors", "MANORS put HEIGHTS out")
	assert_false(r.height_view())
	r.set_manor_view(false)
	assert_eq(r.current_screen.map3d_view().manor_theme(), "")
```

- In `test_the_manors_theme_stays_on_the_3d_map_and_reaches_it`, the last two lines become `r.set_height_view(true)` / `assert_true(_shows_3d(r), "HEIGHTS stays on 3D")` / `assert_eq(r.current_screen.map3d_view().manor_theme(), "heights")`.
- In `test_the_bottom_tab_routes_through_the_rule`: `r._on_bottom_tab("HEIGHTS")` then `assert_true(_shows_3d(r))` both times.
- In `test_the_choice_follows_the_player_to_the_next_screen`: after `r.set_height_view(true)` and the switch, `assert_true(_shows_3d(r), "HEIGHTS keeps the new screen 3D")` and `assert_eq(r.current_screen.map3d_view().manor_theme(), "heights")`; drop the `world_map().visible` assertion.
- Update the file's header comment (line 4) to say no 2D-only layer is left.

Check `set_manor_view` puts HEIGHTS out (it should mirror `set_height_view`; read it at game_root.gd ~376). If it does not, add `if on and _height_view: set_height_view(false)` there.

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: The shader**

In `Map3DGroundTint.UNIFORMS`, append:

```glsl
// The HEIGHTS heat (owner 2026-09-19): the ground's world height ramped
// through terrain_palette heat_1..6 (sRGB, turned linear below).
uniform float heat_mix = 0.0;
uniform float heat_sea_y = 0.0;
uniform float heat_top_m = 2400.0;
uniform vec4 heat_c0 : source_color = vec4(1.0);
uniform vec4 heat_c1 : source_color = vec4(1.0);
uniform vec4 heat_c2 : source_color = vec4(1.0);
uniform vec4 heat_c3 : source_color = vec4(1.0);
uniform vec4 heat_c4 : source_color = vec4(1.0);
uniform vec4 heat_c5 : source_color = vec4(1.0);
```

(`source_color` makes Godot convert the sRGB `Color` to linear for the albedo; the CLAUDE.md "raw hex" note is about emission/unshaded water, not albedo. Verify visually in Task 7: the lowland should read the `heat_1` green of the 2D map, not darker.)

In `TINTED_ALBEDO`, replace the final line

```glsl
	ALBEDO = mix(base_albedo, tint_linear, tint_mix * tint.a);"""
```

with

```glsl
	vec3 tinted = mix(base_albedo, tint_linear, tint_mix * tint.a);
	if (heat_mix > 0.0) {
		float t = clamp((v_vertex.y - heat_sea_y) / heat_top_m, 0.0, 1.0) * 5.0;
		vec3 heat = mix(heat_c0.rgb, heat_c1.rgb, clamp(t, 0.0, 1.0));
		heat = mix(heat, heat_c2.rgb, clamp(t - 1.0, 0.0, 1.0));
		heat = mix(heat, heat_c3.rgb, clamp(t - 2.0, 0.0, 1.0));
		heat = mix(heat, heat_c4.rgb, clamp(t - 3.0, 0.0, 1.0));
		heat = mix(heat, heat_c5.rgb, clamp(t - 4.0, 0.0, 1.0));
		tinted = mix(tinted, heat, heat_mix);
	}
	ALBEDO = tinted;"""
```

Check `v_vertex` is the world-space vertex in Terrain3D's generated shader (the existing field-map code already uses `v_vertex.xz` as world metres, so `.y` is world height).

- [ ] **Step 4: The view**

Add `var _heat := false` beside `_theme`. In `_prepare_ground_tint`, after `tint_mix` is set to 0:

```gdscript
	mat.call("set_shader_param", "heat_mix", 0.0)
	mat.call("set_shader_param", "heat_sea_y", float(_meta.get("sea_y", 0.0)))
	mat.call("set_shader_param", "heat_top_m",
		_repo.bal("elevation_m_per_unit") * (100.0 - _repo.bal("elevation_sea_level")))
	for i in 6:
		mat.call("set_shader_param", "heat_c%d" % i,
			MapTerrain.palette_color(_repo, "heat_%d" % (i + 1), MapTerrain.FALLBACK))
```

Replace `_refresh_theme`:

```gdscript
## The theme on the ground: MANORS' LUT (rebuilt when an owner turns), its
## tint and cell edges; HEIGHTS' heat mix. One theme at a time.
func _refresh_theme() -> void:
	_heat = _theme == "heights"
	if not _loaded:
		return
	var manors := _theme == "manors"
	if manors:
		var st := _state()
		var sig := hash([_theme, 0 if st == null else st.province_owner.hash(),
			0 if st == null else st.manor_owner.hash(),
			0 if st == null else st.manor_province.hash()])
		if sig != _theme_sig or _cell_lut == null:
			_theme_sig = sig
			_build_lut()
		if not _edges_built:
			_build_manor_edges()
	if _tint_mat != null:
		_tint_mat.call("set_shader_param", "tint_mix",
			_repo.bal("map3d_manor_tint") if manors else 0.0)
		_tint_mat.call("set_shader_param", "heat_mix",
			_repo.bal("map3d_heat_tint") if _heat else 0.0)
	var edges := _lines.get_node_or_null("ManorEdges") as MeshInstance3D
	if edges != null:
		edges.visible = manors
	if _hud != null:
		_hud.refresh()


## Test seam: whether the HEIGHTS heat is on the ground.
func heat_on() -> bool:
	return _heat
```

In `pick_at` (~1701), `if _theme != "":` becomes `if _theme == "manors":`. Search the file once more for `_theme != ""` and make each a `== "manors"` test (the only other one is in `_refresh_theme`, now replaced). Update `set_manor_theme`'s doc comment: `"manors"`, `"heights"` or `""`.

Append to `data/balance.csv`:

```csv
map3d_heat_tint,0.85,"3D MAP HEIGHTS (owner 2026-09-19, spec 2026-09-19-map3d-heights-design §4): how far the ground's albedo mixes toward the height ramp (terrain_palette heat_1..6 over 0..elevation_m_per_unit x (100 - elevation_sea_level) m) — lit by the relief like the ground"
```

- [ ] **Step 5: GameRoot**

In `_sync_map_view`:

```gdscript
	_map3d_view = Game.data.bal("map3d_default") > 0.0 and map3d_available()
	if current_screen != null and current_screen.has_method("set_map3d_theme"):
		var theme_name := "manors" if _manor_view else ("heights" if _height_view else "")
		current_screen.set_map3d_theme(theme_name, _army_view)
```

and rewrite its doc comment: every layer draws on the 3D map now (HEIGHTS since 2026-09-19); 2D only without a built scene or with `map3d_default` 0.

- [ ] **Step 6: Run the map3d and ui tests**

Run `test_map3d_ground_tint.gd`, `test_map3d_heights.gd`, `test_map3d_tab.gd`, `test_map3d_manor_themes.gd`, `tests/ui/test_game_root.gd`, `tests/ui/test_ui_rework.gd`. Expected: PASS. (`test_game_root.gd:140-154` and `test_ui_rework.gd:473-489` test the toggle state and exclusivity, which stay; fix any assertion that expects the 2D map to show.)

- [ ] **Step 7: Suite and commit**

```bash
git add scripts/map3d/map3d_ground_tint.gd scripts/map3d/map3d_view.gd scripts/ui/game_root.gd data/balance.csv tests/map3d/test_map3d_ground_tint.gd tests/map3d/test_map3d_heights.gd tests/map3d/test_map3d_heights.gd.uid tests/map3d/test_map3d_tab.gd
git commit -m "feat(map3d): HEIGHTS on the 3D map — the ground's height heat"
```

---

### Task 6: Landmarks on the 3D map — marks, legend, hover, click

**Files:**
- Modify: `scripts/map3d/map3d_view.gd` (`landmark_marks`, `draw_landmarks`, `draw_heat_legend`, `pick_at`, `hover_pick`, `select_at`, `kingdom_of_pick`)
- Modify: `scripts/map3d/map3d_hud.gd` (`_draw`)
- Modify: `data/balance.csv` (`map3d_landmark_*`, `map3d_heat_legend_*`)
- Modify: `data/political_palette.csv` (`landmark_high`, `landmark_low`, `landmark_text` ink — read the file's column shape first)
- Test: `tests/map3d/test_map3d_heights.gd` (extend)

**Interfaces:**
- Consumes: `Elevation.landmarks`, `MapObjects.label_of(..., state)`, `MapObjects.landmark_lines` (Tasks 3–4); `_heat` (Task 5).
- Produces: `Map3DView.landmark_marks() -> Array` of `{cell, kind, pos: Vector2, rect: Rect2, text: String}` in design px, `[]` off HEIGHTS; pick result `{"kind": "landmark", "cell": id}`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/map3d/test_map3d_heights.gd`:

```gdscript
func _frame_on(v: Map3DView, m: Dictionary, distance: float) -> void:
	# Point the camera at a landmark from a given distance (read Map3DView
	# for its framing seam — e.g. frame_pack(pos, distance) or set_target /
	# set_distance used by test_map3d_view.gd — and use that).
	v.frame_pack(m["pos"], distance)

func test_no_marks_off_heights() -> void:
	var v := _view()
	assert_eq(v.landmark_marks(), [])

func test_far_out_only_the_big_ones_show() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	var top: Dictionary = Elevation.landmarks(Game.data)[0]
	_frame_on(v, top, Game.data.bal("map3d_landmark_lod_far_view_m") * 1.5)
	var marks := v.landmark_marks()
	assert_gt(marks.size(), 0)
	for mk: Dictionary in marks:
		assert_eq(int(Elevation.landmark_at(Game.data, int(mk["cell"]))["lod"]), 0)

func test_close_in_smaller_ones_join() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	var small: Dictionary = {}
	for m: Dictionary in Elevation.landmarks(Game.data):
		if int(m["lod"]) == 2:
			small = m
			break
	assert_false(small.is_empty(), "the pack has near-only landmarks")
	_frame_on(v, small, Game.data.bal("map3d_zoom_min_m") * 2.0)
	var cells: Array = v.landmark_marks().map(func(mk: Dictionary) -> int: return int(mk["cell"]))
	assert_true(int(small["cell"]) in cells)

func test_marks_never_overlap() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	_frame_on(v, Elevation.landmarks(Game.data)[0], 40000.0)
	var marks := v.landmark_marks()
	for i in marks.size():
		for j in range(i + 1, marks.size()):
			assert_false((marks[i]["rect"] as Rect2).intersects(marks[j]["rect"]))

func test_hovering_a_mark_shows_its_tooltip_and_a_click_opens_its_card() -> void:
	var v := _view()
	v.set_manor_theme("heights")
	var top: Dictionary = Elevation.landmarks(Game.data)[0]
	_frame_on(v, top, 20000.0)
	var mk: Dictionary = {}
	for m: Dictionary in v.landmark_marks():
		if int(m["cell"]) == int(top["cell"]):
			mk = m
	assert_false(mk.is_empty())
	var picked := v.pick_at(mk["pos"])
	assert_eq(picked, {"kind": "landmark", "cell": int(top["cell"])})
	v.hover_pick(picked, mk["pos"])
	assert_true(v.hover_tooltip().begins_with(String(top["name"])))
	watch_signals(v)
	v.select_at(mk["pos"])
	assert_signal_emitted(v, "object_selected")
	var entry: Dictionary = get_signal_parameters(v, "object_selected")[0]
	assert_eq(String(entry["title"]), String(top["name"]))
	assert_eq(Array(entry["lines"]), Array(MapObjects.landmark_lines(Game.data, Game.state, int(top["cell"]))))
```

Before writing `_frame_on`, read `tests/map3d/test_map3d_view.gd` / `test_map3d_hover.gd` for how tests point the camera; if the view has no public seam taking a pack position and a distance, add one to `Map3DView`:

```gdscript
## Test and tool seam: look at a pack point from `distance` metres.
func frame_pack(pack_px: Vector2, distance: float) -> void:
	_target = Map3DGeometry.pack_to_world(_meta, pack_px)
	_distance = clampf(distance, _repo.bal("map3d_zoom_min_m"), _repo.bal("map3d_zoom_max_m"))
	_apply_camera()
```

(use whatever the view calls its camera update — the function holding `_camera.transform = Map3DGeometry.pose(...)` ~line 1219.)

- [ ] **Step 2: Run to verify they fail**

- [ ] **Step 3: Data**

Append to `data/balance.csv`:

```csv
map3d_landmark_lod_far_view_m,60000,"3D MAP HEIGHTS (owner 2026-09-19, spec 2026-09-19-map3d-heights §4): camera distance at/above which only lod-0 landmarks (landmark_lod_far_m) are marked"
map3d_landmark_lod_mid_view_m,20000,"3D MAP HEIGHTS: camera distance at/above which lod-2 landmarks are left off"
map3d_landmark_px,11,"3D MAP HEIGHTS: a landmark triangle's height in design px (constant on screen)"
map3d_landmark_font_px,14,"3D MAP HEIGHTS: the height beside a landmark, design px"
map3d_heat_legend_w_px,14,"3D MAP HEIGHTS: the legend ramp's width, design px (bottom-left)"
map3d_heat_legend_h_px,160,"3D MAP HEIGHTS: the legend ramp's height, design px"
```

Add the three inks to `political_palette.csv` (`landmark_high` a dark brown-black `#2B1D14`, `landmark_low` a deep blue `#1E4257` — the coast line's, `landmark_text` `#1A1410`), in its existing column shape.

- [ ] **Step 4: The marks**

In `Map3DView`:

```gdscript
# --- HEIGHTS landmarks (owner 2026-09-19, spec 2026-09-19-map3d-heights §4) ---

## The high and low points shown now, in design px, biggest first: those
## whose lod the camera's distance allows, before the camera and on screen,
## none overlapping a settlement dot, a regiment counter or a bigger mark.
## [] off HEIGHTS.
func landmark_marks() -> Array:
	if not _heat or _camera == null:
		return []
	var max_lod := 2
	if _distance >= _repo.bal("map3d_landmark_lod_far_view_m"):
		max_lod = 0
	elif _distance >= _repo.bal("map3d_landmark_lod_mid_view_m"):
		max_lod = 1
	var s := _render_scale()
	var px := _repo.bal("map3d_landmark_px")
	var font := UiPalette.display_font()
	var font_px := int(_repo.bal("map3d_landmark_font_px"))
	var frame := Rect2(Vector2.ZERO, size)
	var taken: Array = _settlement_marks()
	for a: Dictionary in army_markers():
		taken.append(a["rect"])
	var out: Array = []
	for m: Dictionary in Elevation.landmarks(_repo):
		if int(m["lod"]) > max_lod:
			continue
		var xz := Map3DGeometry.pack_to_world(_meta, m["pos"])
		var ground := Vector3(xz.x, _height_at(xz), xz.y)
		if _camera.is_position_behind(ground):
			continue
		var p := _camera.unproject_position(ground) / s
		if not frame.has_point(p):
			continue
		var text := "%d m" % int(m["metres"])
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px).x if font != null else 0.0
		var rect := Rect2(p - Vector2(px * 0.5, px * 0.5), Vector2(px + 4.0 + tw, px))
		var clear := true
		for r: Rect2 in taken:
			if r.intersects(rect):
				clear = false
				break
		if not clear:
			continue
		taken.append(rect)
		out.append({"cell": int(m["cell"]), "kind": String(m["kind"]), "pos": p,
			"rect": rect, "text": text})
	return out


## Draw the landmarks on the HUD: ▲ / ▽ on a pale halo, the height beside.
func draw_landmarks(ci: CanvasItem) -> void:
	var px := _repo.bal("map3d_landmark_px")
	var font := UiPalette.display_font()
	var font_px := int(_repo.bal("map3d_landmark_font_px"))
	var halo := MapTerrain.palette_color(_repo, "map3d_hud_halo", MapTerrain.FALLBACK)
	var text_ink := MapPalette.named(_repo, "landmark_text")
	for mk: Dictionary in landmark_marks():
		var p: Vector2 = mk["pos"]
		var h := px * 0.5
		var tri := PackedVector2Array([p + Vector2(0, -h), p + Vector2(h, h), p + Vector2(-h, h)]) \
			if mk["kind"] == "high" else PackedVector2Array([p + Vector2(0, h), p + Vector2(-h, -h), p + Vector2(h, -h)])
		var ink := MapPalette.named(_repo, "landmark_high" if mk["kind"] == "high" else "landmark_low")
		ci.draw_colored_polygon(tri, ink)
		ci.draw_polyline(tri + PackedVector2Array([tri[0]]), halo, 1.5, true)
		if font != null:
			var at := p + Vector2(h + 3.0, font_px * 0.35)
			ci.draw_string_outline(font, at, String(mk["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, 3, halo)
			ci.draw_string(font, at, String(mk["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, text_ink)
```

(`MapPalette.named` and `MapTerrain.palette_color` — check which reads `political_palette.csv` vs `terrain_palette.csv` by grepping their definitions, and use the right one for each key.)

- [ ] **Step 5: The legend**

```gdscript
## The HEIGHTS legend, bottom-left: the heat ramp (terrain_palette heat_1..6)
## bottom to top, the tier lines ticked and named with their metres.
func draw_heat_legend(ci: CanvasItem) -> void:
	if not _heat:
		return
	var w := _repo.bal("map3d_heat_legend_w_px")
	var h := _repo.bal("map3d_heat_legend_h_px")
	var m := _repo.bal("map_compass_margin_px")
	var origin := Vector2(m, size.y - m - h)
	var top_m := _repo.bal("elevation_m_per_unit") * (100.0 - _repo.bal("elevation_sea_level"))
	for i in 5:
		var y0 := origin.y + h - h * float(i) / 5.0
		var y1 := origin.y + h - h * float(i + 1) / 5.0
		var c0 := MapTerrain.palette_color(_repo, "heat_%d" % (i + 1), MapTerrain.FALLBACK)
		var c1 := MapTerrain.palette_color(_repo, "heat_%d" % (i + 2), MapTerrain.FALLBACK)
		ci.draw_polygon(PackedVector2Array([Vector2(origin.x, y0), Vector2(origin.x + w, y0),
			Vector2(origin.x + w, y1), Vector2(origin.x, y1)]), PackedColorArray([c0, c0, c1, c1]))
	var font := UiPalette.display_font()
	var font_px := int(_repo.bal("map3d_landmark_font_px"))
	var ink := MapPalette.named(_repo, "landmark_text")
	var halo := MapTerrain.palette_color(_repo, "map3d_hud_halo", MapTerrain.FALLBACK)
	for r: Dictionary in _repo.army_height_supply:
		var metres := Elevation.metres_of_height(_repo, float(r["min_height"]))
		if metres <= 0:
			continue
		var y := origin.y + h - h * clampf(float(metres) / top_m, 0.0, 1.0)
		ci.draw_line(Vector2(origin.x, y), Vector2(origin.x + w + 4.0, y), ink, 1.5)
		if font != null:
			var label := "%s %d m" % [String(r["tier"]).capitalize(), metres]
			var at := Vector2(origin.x + w + 7.0, y + font_px * 0.35)
			ci.draw_string_outline(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, 3, halo)
			ci.draw_string(font, at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, font_px, ink)
```

In `Map3DHud._draw`, after `view.draw_labels(self)`:

```gdscript
	# HEIGHTS' landmarks and legend (owner 2026-09-19), over the names.
	view.draw_landmarks(self)
	view.draw_heat_legend(self)
```

- [ ] **Step 6: Pick, hover, click**

In `pick_at`, after the badges loop and before the burgs loop:

```gdscript
	# Under HEIGHTS a high or low point, on its mark (spec 2026-09-19-map3d-heights).
	for mk: Dictionary in landmark_marks():
		if (mk["rect"] as Rect2).grow(_repo.bal("map3d_pick_px") * 0.5).has_point(pos):
			return {"kind": "landmark", "cell": int(mk["cell"])}
```

In `hover_pick`: the kinds list becomes `["burg", "manor", "army", "landmark"]`, and `MapObjects.label_of(_repo, obj)` becomes `MapObjects.label_of(_repo, obj, _state())`.

In `kingdom_of_pick`'s `match`, add `"landmark": province = MapManors.province_of(repo, int(picked["cell"]), state)`.

In `select_at`'s `match`, add (read the `"manor"` branch first and clear the same selection state it clears):

```gdscript
		"landmark":
			var cell := int(picked["cell"])
			_selected_army = ""
			_selected_burg = ""
			_set_selected_province("")
			var m := Elevation.landmark_at(_repo, cell)
			object_selected.emit({"title": String(m["name"]),
				"lines": MapObjects.landmark_lines(_repo, _state(), cell),
				"ask": "", "obj": {"kind": "landmark", "cell": cell}})
```

`MapDetailPanel.show_entry` shows an entry with `lines` for any kind it has no card for — no change there (confirm by reading `show_entry` ~248).

- [ ] **Step 7: Run tests, suite, commit**

Run `test_map3d_heights.gd`, `test_map3d_hover.gd`, `test_map3d_hud.gd`, `test_map3d_military.gd`, then `./run_tests.sh`.

```bash
git add scripts/map3d/map3d_view.gd scripts/map3d/map3d_hud.gd data/balance.csv data/political_palette.csv tests/map3d/test_map3d_heights.gd
git commit -m "feat(map3d): HEIGHTS landmarks — marks, legend, hover and card"
```

---

### Task 7: Look, speed, and the record

**Files:**
- Modify: `CLAUDE.md`, `docs/superpowers/specs/2026-09-17-regiment-state-design.md` (a pointer), `.claude/skills/visual-review/taste.md` (only if the owner rules on the look)
- Possibly modify: `data/balance.csv`, `data/terrain_palette.csv` (look values found by the review)

- [ ] **Step 1: Shoot it**

Read `.claude/skills/visual-review/SKILL.md` and follow its loop. Shots (check `tools/snapshot_screen.gd`'s header for the exact flags, and whether `--layer heights` takes the 3D view once Task 5 lands):

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_screen.tscn -- --screen court --layer heights --out <scratchpad>/heights_far.png
```

plus a mid and a near zoom, and `--hover3d fx,fy` on a peak. Check: lowland reads the heat_1 green (not muddy/dark — if it does, the `source_color` conversion is wrong: drop `source_color` and convert in the shader as the LUT does); the tier lines on the legend sit where the colour steps; marks readable, no pile-ups; tooltip complete. Tune `map3d_heat_tint`, `map3d_landmark_*`, the heat stops only through data.

- [ ] **Step 2: Bench**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/map3d/bench.tscn
```

with HEIGHTS on if the bench takes a layer flag (read `tools/map3d/bench.gd`; if it has none, add `--layer heights` the way `snapshot_screen` takes it). Expected: exit 0, every row within 8 ms. If `landmark_marks()` costs too much (it runs on every HUD redraw), cache it per camera pose (key on `_camera.transform` and `size`).

- [ ] **Step 3: The record**

CLAUDE.md:
- The 3D-map paragraph: "HEIGHTS — the one 2D-only layer left" and "HEIGHTS alone is 2D" go; add a **HEIGHTS** sentence: the patched shader's heat ramp (`map3d_heat_tint`, `heat_1..6` over `elevation_*`), the landmarks (`Elevation.landmarks`: local extremes by prominence over `landmark_ring` rings, `lod` by `landmark_lod_*_m`, named after the nearest town from `data/landmark_names.csv`, pack overrides `landmark_name_overrides.csv`), marks thinned by `map3d_landmark_lod_*_view_m`, the legend, the tooltip/card (`MapObjects.landmark_lines`). The migration list's one remaining step: deleting the 2D map.
- The regiment sentence: height in war — `ArmySystem.height_factor` (`army_height_bonus_*`) in `battle_odds` by the height DIFFERENCE, supply use × the tier of `data/army_height_supply.csv`, the terrain's hill/mountain lines are the tiers', one measure `Elevation.metres_of_cell` shared with `bake_world.py` through `elevation_sea_level` / `elevation_m_per_unit`.
- `_sync_map_view`'s rule: 3D whenever the pack has a built scene and `map3d_default` is 1.

Regiment spec: one line under §4 pointing at `2026-09-19-map3d-heights-design.md` for the height factor and the tiers.

- [ ] **Step 4: Suite and commit**

```bash
./run_tests.sh
git add CLAUDE.md docs/superpowers/specs/2026-09-17-regiment-state-design.md data/balance.csv data/terrain_palette.csv
git commit -m "docs: HEIGHTS on the 3D map and height in war"
```
