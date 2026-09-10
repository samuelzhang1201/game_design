# Terrain From Data Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Azgaar PNG map background with terrain the game draws itself from the JSON's cell geometry: one vertex-coloured mesh (biome tint × relief shading, depth-graded sea, lakes) plus coast, river and route strokes.

**Architecture:** The GDScript importer writes three new geography tables (vertices, cells, coasts) in native map coordinates. A pure `MapTerrain` class turns them into mesh arrays with hand-testable colour formulas; `WorldMapView` builds one `ArrayMesh` from it and draws it with a `Transform2D` per frame under all the existing overlays. The PNG, the render calibration, and the calibration tool are deleted.

**Tech Stack:** Godot 4.x, typed GDScript, GUT (headless), CSV data tables.

**Spec:** `docs/superpowers/specs/2026-09-11-terrain-from-data-design.md`

## Global Constraints

- Typed GDScript everywhere: type hints on vars, params, returns. `snake_case` files/functions/vars, `PascalCase` classes.
- Design values live in CSVs (`data/balance.csv`, `data/terrain_palette.csv`), never hardcoded in scripts.
- Simulation and geometry classes are `RefCounted` (no Node dependencies) so GUT runs them headless.
- Determinism: no `Time.get_*`, no unseeded RNG anywhere in engine code. The importer's output is byte-identical for identical input.
- All pack coordinates stay in the Azgaar JSON's native space (2560×929 for `beria`). No new coordinate system.
- Authored text never names a kingdom; tests derive kingdoms/capitals from `Game.data.resolve_realm("player_realm")`.
- Run the whole suite with `./run_tests.sh` ("Errors 2" in the summary is expected; any other count is a failure). Run one test file with:
  `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gselect=<script name fragment> -gexit`
- Commit messages end with:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01NPb6Y6TWL9FzyDiA6QibdQ
  ```
- The working tree already holds unrelated uncommitted changes (a warning-cleanup pass across many scripts, deleted `.import` sidecars). Stage only the files each task names; never `git add -A`.

## File Structure

| File | Responsibility |
|---|---|
| `tools/import_azgaar.gd` (modify) | Write `geography/vertices.csv`, `cells.csv`, `coasts.csv`; add `discharge` to `rivers.csv`; stop needing a PNG |
| `data/maps/beria/geography/{vertices,cells,coasts,rivers}.csv` (generated) | The pack's terrain geometry |
| `data/terrain_palette.csv` (create) | The game's terrain colours (land tints per biome, sea, lake, lines) |
| `data/balance.csv` (modify) | Relief, light, sea gradient, stroke widths; drop the calibration keys |
| `scripts/engine/data_repository.gd` (modify) | Load the four new tables; drop the render fields |
| `scripts/engine/map_terrain.gd` (create) | Pure mesh builder: colours, shading, fan triangulation, `to_mesh`, shared-mesh cache |
| `scripts/ui/world_map_view.gd` (modify) | Draw the mesh, coasts, rivers, routes; simplified transform; no texture |
| `scripts/ui/map_detail_panel.gd` (modify) | Place preview drawn from the mesh instead of a PNG atlas |
| `data/maps.csv` (modify) | Drop `map_texture`, `render_scale`, `render_offset_x/y` |
| `tests/engine/test_map_terrain.gd` (create) | Hand-computed formula tests on tiny fixture repos |
| `tests/engine/test_map_data.gd`, `test_map_pack.gd`, `tests/ui/test_world_map_view.gd`, `tests/ui/test_map_detail_panel.gd` (modify) | Pack-table integrity for the new tables; drop calibration/PNG tests |
| Deleted: `assets/maps/beria/world_map.png` (+ `.import`), `tools/calibrate_render.py` | |
| `CLAUDE.md` (modify) | Map paragraph rewritten for the data-driven terrain |

---

### Task 1: Importer writes the terrain tables and no longer needs a PNG

**Files:**
- Modify: `tools/import_azgaar.gd`
- Generated: `data/maps/beria/geography/vertices.csv`, `cells.csv`, `coasts.csv`, `rivers.csv`

**Interfaces:**
- Produces `geography/vertices.csv` — `vertex_id,x,y`.
- Produces `geography/cells.csv` — `cell_id,vertex_ids,height,biome_id,water,neighbor_ids` (`vertex_ids`/`neighbor_ids` are `|`-joined ints; `water` is `""`, `ocean`, or `lake`).
- Produces `geography/coasts.csv` — `kind,feature_id,loop,points` (`kind` ∈ {`land`,`lake`}; points `x y|x y|...`).
- `geography/rivers.csv` gains a `discharge` column (Azgaar's `discharge`, an int) after `length`.

- [ ] **Step 1: Add the sea-level constant and a Callable-based loop helper**

In `tools/import_azgaar.gd`, after `const DOMAINS ...` add:

```gdscript
## Azgaar's convention: a cell with h below this is water.
const SEA_LEVEL := 20
```

Replace the whole `_cell_group_loops` function with a thin wrapper plus the general form (keep the existing doc comment above it):

```gdscript
func _cell_group_loops(cells: Array, vertices: Array, field: String,
		id: int) -> Array[PackedVector2Array]:
	return _cell_set_loops(cells, vertices, func(c: Dictionary) -> bool:
		return int(c.get(field, 0)) == id)


## The outline of every cell `member` accepts — the same edge-count walk as
## _cell_group_loops, over an arbitrary set (all land, one lake's cells).
func _cell_set_loops(cells: Array, vertices: Array,
		member: Callable) -> Array[PackedVector2Array]:
	var edge_count: Dictionary = {}
	var edge_order: Array[Vector2i] = []
	for c: Dictionary in cells:
		if not member.call(c):
			continue
		var vs: Array = c["v"]
		for i in vs.size():
			var a := int(vs[i])
			var b := int(vs[(i + 1) % vs.size()])
			var key := Vector2i(mini(a, b), maxi(a, b))
			if edge_count.has(key):
				edge_count[key] = int(edge_count[key]) + 1
			else:
				edge_count[key] = 1
				edge_order.append(key)
	var adjacent: Dictionary = {}
	var boundary: Array[Vector2i] = []
	for key in edge_order:
		if int(edge_count[key]) != 1:
			continue
		boundary.append(key)
		for v in [key.x, key.y]:
			if not adjacent.has(v):
				adjacent[v] = []
			(adjacent[v] as Array).append(key)
	var used: Dictionary = {}
	var loops: Array[PackedVector2Array] = []
	for start in boundary:
		if used.has(start):
			continue
		var loop := PackedVector2Array()
		var edge := start
		var v := start.x
		while true:
			used[edge] = true
			var vp: Array = (vertices[v] as Dictionary)["p"]
			loop.append(Vector2(float(vp[0]), float(vp[1])))
			v = edge.y if edge.x == v else edge.x
			var next_edge := Vector2i(-1, -1)
			for e: Vector2i in (adjacent[v] as Array):
				if not used.has(e):
					next_edge = e
					break
			if next_edge.x < 0:
				break
			edge = next_edge
		loops.append(loop)
	return loops


## A loop as the "x y|x y|..." text the pack tables carry.
func _loop_points(loop: PackedVector2Array) -> String:
	var pts: Array[String] = []
	for p in loop:
		pts.append("%s %s" % [_num2(p.x), _num2(p.y)])
	return "|".join(pts)
```

- [ ] **Step 2: Remove the PNG requirement**

In `_run()`:

1. Delete the `png_path` variable, the `--png` branch in the arg loop, the `pngs` array and its collection loop (keep the `jsons` collection: the loop body becomes only the `Full`/`.json` branch), the block from `var render_scale := 0` through `print("render scale: %dx" % render_scale)`, and change the `print("json: %s\npng:  %s" ...)` line to `print("json: %s" % json_path.get_file())`.
2. In the bitmaps section delete the `DirAccess.copy_absolute(... "/world_map.png")` call.
3. Delete the functions `_newest_render` and `_png_dimensions`, and the constant `GENERATED_PNGS`.
4. In the header doc comment: delete the line `assets/maps/<map-id>/world_map.png byte copy under a stable name`, the whole paragraph beginning `Azgaar's PNG export captures the CURRENT VIEW`, and the `--png PATH` from the usage line. Add after the `geography/biomes.csv` line:

```
##   <pack>/geography/vertices.csv     every Voronoi vertex: vertex_id,x,y
##   <pack>/geography/cells.csv        every cell: its vertex ids, height (0-100),
##       biome, water kind ("" land / ocean / lake), neighbour cell ids —
##       MapTerrain builds the terrain mesh from these; no render PNG exists
##   <pack>/geography/coasts.csv       closed shore loops: the outline of all
##       land ("land") and of each lake ("lake")
```

- [ ] **Step 3: Write the three tables and the river discharge**

In `_run()`, directly after the `geography/biomes.csv` block (before `# --- map_info.csv`), add:

```gdscript
	# --- geography/vertices.csv -------------------------------------------
	out = _csv_line(["vertex_id", "x", "y"])
	for v in vertices:
		if not (v is Dictionary):
			continue
		var vp: Array = (v as Dictionary)["p"]
		out += _csv_line([str(int((v as Dictionary)["i"])), _num2(float(vp[0])), _num2(float(vp[1]))])
	if not _write_text(out_data + "/geography/vertices.csv", out):
		return 1

	# --- geography/cells.csv ----------------------------------------------
	# The terrain itself (spec 2026-09-11): MapTerrain fans every cell into a
	# mesh, shades land by its neighbours' heights, and grades the sea by depth.
	var feat_type: Dictionary = {}
	for f in (pack.get("features", []) as Array):
		if f is Dictionary:
			feat_type[int((f as Dictionary).get("i", -1))] = String((f as Dictionary).get("type", ""))
	out = _csv_line(["cell_id", "vertex_ids", "height", "biome_id", "water", "neighbor_ids"])
	for c: Dictionary in cells:
		var h := int(round(float(c.get("h", 0))))
		var water := ""
		if h < SEA_LEVEL:
			water = "lake" if String(feat_type.get(int(c.get("f", 0)), "")) == "lake" else "ocean"
		var vids: Array[String] = []
		for v in (c.get("v", []) as Array):
			vids.append(str(int(v)))
		var nids: Array[String] = []
		for n in (c.get("c", []) as Array):
			nids.append(str(int(n)))
		out += _csv_line([str(int(c["i"])), "|".join(vids), str(h),
			str(int(c.get("biome", 0))), water, "|".join(nids)])
	if not _write_text(out_data + "/geography/cells.csv", out):
		return 1

	# --- geography/coasts.csv ---------------------------------------------
	# Shores as closed loops: the outline of all land (every island, plus an
	# inner loop around any lake inside it) and each lake's own shore.
	out = _csv_line(["kind", "feature_id", "loop", "points"])
	var coast_total := 0
	var land_loops := _cell_set_loops(cells, vertices, func(c: Dictionary) -> bool:
		return float(c.get("h", 0)) >= SEA_LEVEL)
	for li in land_loops.size():
		out += _csv_line(["land", "0", str(li), _loop_points(land_loops[li])])
	coast_total += land_loops.size()
	for f in (pack.get("features", []) as Array):
		if not (f is Dictionary) or String((f as Dictionary).get("type", "")) != "lake":
			continue
		var fid := int((f as Dictionary)["i"])
		var lake_loops := _cell_set_loops(cells, vertices, func(c: Dictionary) -> bool:
			return int(c.get("f", 0)) == fid)
		for li in lake_loops.size():
			out += _csv_line(["lake", str(fid), str(li), _loop_points(lake_loops[li])])
		coast_total += lake_loops.size()
	if not _write_text(out_data + "/geography/coasts.csv", out):
		return 1
```

In the `geography/rivers.csv` block change the header to
`["river_code", "label", "type", "length", "discharge", "kingdom_codes", "points"]`
and the row to

```gdscript
		out += _csv_line([_take_slug(river_slugs, label), label, String(rv.get("type", "River")),
			String.num(length, 1), str(int(rv.get("discharge", 0))), "|".join(through), "|".join(pts)])
```

In the final report `print`, append `, %d coast loops` to the format string and `coast_total` to the argument list (after `markers.size()`).

- [ ] **Step 4: Run the importer and inspect the output**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/import_azgaar.gd
head -3 data/maps/beria/geography/vertices.csv data/maps/beria/geography/cells.csv data/maps/beria/geography/coasts.csv data/maps/beria/geography/rivers.csv | cut -c1-160
wc -l data/maps/beria/geography/vertices.csv data/maps/beria/geography/cells.csv data/maps/beria/geography/coasts.csv
awk -F, 'NR>1{print $1}' data/maps/beria/geography/coasts.csv | sort | uniq -c
git status --short data/maps/beria
```
Expected: the importer prints `json: Game_dev Full 2026-09-09-14-24.json` and no PNG line; ends with `... 16 coast loops` (or close: 12 islands + lake shores, plus lake loops); `vertices.csv` has 9893 lines (header + 9892), `cells.csv` 4834; `coasts.csv` shows `4 lake` and `land` ≥ 12; `rivers.csv` header has `discharge` after `length` and the first row's discharge is `114`; `git status` shows only the four geography tables changed/added (no other pack table differs — the importer is deterministic).

- [ ] **Step 5: Commit**

```bash
git add tools/import_azgaar.gd data/maps/beria/geography/vertices.csv data/maps/beria/geography/cells.csv data/maps/beria/geography/coasts.csv data/maps/beria/geography/rivers.csv
git commit -m "feat(import): terrain tables — vertices, cells, coasts; no PNG needed

The importer now reads only the Azgaar JSON. cells.csv carries each
cell's vertices, height, biome, water kind and neighbours; coasts.csv the
land and lake shores; rivers.csv gains discharge for stroke widths.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NPb6Y6TWL9FzyDiA6QibdQ"
```

---

### Task 2: Terrain palette, balance keys, and the repository loaders

**Files:**
- Create: `data/terrain_palette.csv`
- Modify: `data/balance.csv`
- Modify: `scripts/engine/data_repository.gd`
- Test: `tests/engine/test_map_data.gd`

**Interfaces:**
- Produces on `DataRepository`:
  - `var terrain_palette: Dictionary` — `key -> "#rrggbb"`.
  - `var vertices: Dictionary` — `vertex_id (int) -> Vector2`.
  - `var cells: Dictionary` — `cell_id (int) -> row` where the row has `"vertex_ids": PackedInt32Array`, `"neighbor_ids": PackedInt32Array`, `"height": float`, `"biome_id": int`, `"water": String`.
  - `var coasts: Array[Dictionary]` — rows with `kind`, `feature_id`, `loop`, `points`, plus `polyline: PackedVector2Array` and `bbox: Rect2` set at load.
- Balance keys: `map_relief_strength`, `map_relief_min`, `map_relief_max`, `map_light_x`, `map_light_y`, `map_altitude_gain`, `map_sea_depth_gamma`, `map_coast_width`, `map_river_min_px`, `map_river_discharge_scale`, `map_road_width`, `map_trail_width`, `map_trail_min_scale`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/engine/test_map_data.gd` (it already has `var repo: DataRepository` loaded in `before_all`):

```gdscript
## The terrain tables (spec 2026-09-11): the game draws the map from these,
## so every reference in them must resolve.
func test_terrain_tables_load_and_cross_reference() -> void:
	assert_gt(repo.vertices.size(), 0, "vertices.csv loaded")
	assert_gt(repo.cells.size(), 0, "cells.csv loaded")
	assert_gt(repo.coasts.size(), 0, "coasts.csv loaded")
	var land := 0
	for id: int in repo.cells:
		var c: Dictionary = repo.cells[id]
		var vids: PackedInt32Array = c["vertex_ids"]
		assert_gte(vids.size(), 3, "cell %d has a polygon" % id)
		for v in vids:
			assert_true(repo.vertices.has(v), "cell %d vertex %d exists" % [id, v])
		for n in (c["neighbor_ids"] as PackedInt32Array):
			assert_true(repo.cells.has(n), "cell %d neighbour %d exists" % [id, n])
		var water := String(c["water"])
		if water == "":
			land += 1
			assert_true(repo.biomes.has(int(c["biome_id"])),
				"land cell %d has a named biome" % id)
			assert_gte(float(c["height"]), 20.0, "land is at or above sea level")
		else:
			assert_true(water == "ocean" or water == "lake", "cell %d water kind %s" % [id, water])
			assert_lt(float(c["height"]), 20.0, "water is below sea level")
	assert_gt(land, 0, "some cells are land")

## The committed pack (Game_dev, seed 954159497) has 12 islands and 4 lakes.
func test_coast_loops_match_the_packs_features() -> void:
	var land := 0
	var lakes := 0
	for row: Dictionary in repo.coasts:
		assert_gte((row["polyline"] as PackedVector2Array).size(), 3,
			"%s loop %s has 3+ points" % [row["kind"], row["loop"]])
		match String(row["kind"]):
			"land": land += 1
			"lake": lakes += 1
	assert_eq(lakes, 4, "one shore per lake")
	assert_gte(land, 12, "at least one land loop per island")

func test_terrain_palette_names_every_colour_the_map_draws() -> void:
	for key in ["sea_deep", "sea_shallow", "lake", "coast_line", "river", "road", "trail"]:
		assert_true(repo.terrain_palette.has(key), key)
	for id: int in repo.biomes:
		if id == 0:
			continue
		assert_true(repo.terrain_palette.has("biome_%d" % id),
			"biome %d (%s) has a land tint" % [id, repo.biomes[id]["label"]])

func test_terrain_balance_keys_are_present() -> void:
	for key in ["map_relief_strength", "map_relief_min", "map_relief_max", "map_light_x",
			"map_light_y", "map_altitude_gain", "map_sea_depth_gamma", "map_coast_width",
			"map_river_min_px", "map_river_discharge_scale", "map_road_width",
			"map_trail_width", "map_trail_min_scale"]:
		assert_true(repo.balance.has(key), key)
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gselect=test_map_data -gexit`
Expected: the four new tests fail (`vertices` / `terrain_palette` not found on DataRepository, or 0 rows).

- [ ] **Step 3: Create the palette and the balance keys**

Create `data/terrain_palette.csv`:

```csv
key,color,notes
biome_1,#d6c48f,hot desert: pale sand
biome_2,#c6bfa0,cold desert: grey sand
biome_3,#c7c288,savanna: dry straw
biome_4,#b8c78c,grassland: light green
biome_5,#9fba75,tropical seasonal forest
biome_6,#8fb07a,temperate deciduous forest: the common green
biome_7,#7ea86a,tropical rainforest
biome_8,#7aa274,temperate rainforest
biome_9,#6f8e6a,taiga: dark conifer green
biome_10,#a69f88,tundra: grey brown
biome_11,#dfe5e5,glacier: ice
biome_12,#8aa78a,wetland: dull green
sea_deep,#3f5f78,open sea
sea_shallow,#7fa3b6,shelf water next to the shore
lake,#6f96ad,freshwater
coast_line,#2e3a40,the shore stroke
river,#5b86a3,river strokes
road,#7a6247,roads
trail,#8f7a62,trails and sea routes
```

Append to `data/balance.csv` (after the `map_army_pick_px` row) and delete the three `map_calibration_*` rows:

```csv
map_relief_strength,0.02,terrain: shade change per unit of slope (height units per native px) facing the light
map_relief_min,0.6,terrain: darkest relief factor
map_relief_max,1.35,terrain: brightest relief factor
map_light_x,-0.7,terrain: light direction x (toward the light; negative = from the west)
map_light_y,-0.7,terrain: light direction y (negative = from the north)
map_altitude_gain,0.25,terrain: extra brightening from sea level to the summit
map_sea_depth_gamma,0.6,terrain: exponent on h/20 for the deep-to-shallow sea gradient
map_coast_width,1.0,terrain: shore stroke width in screen px
map_river_min_px,0.8,terrain: thinnest river stroke in screen px
map_river_discharge_scale,0.06,terrain: river stroke width in native px per sqrt(discharge)
map_road_width,1.2,terrain: road stroke width in screen px
map_trail_width,0.8,terrain: trail and sea-route stroke width in screen px
map_trail_min_scale,0.6,terrain: view scale at/above which trails and sea routes draw (roads always draw)
```

- [ ] **Step 4: Add the repository fields and loaders**

In `scripts/engine/data_repository.gd`, after `var settlement_art: Array[Dictionary] = []` add:

```gdscript
## data/terrain_palette.csv: key -> "#rrggbb" for the terrain the game draws
## itself (MapTerrain): land tints per biome, sea, lake, and line colours.
var terrain_palette: Dictionary = {}
```

After `var map_info: Dictionary = {}` add:

```gdscript
## The pack's terrain geometry (spec 2026-09-11, geography/vertices.csv and
## cells.csv): vertex_id -> Vector2, and cell_id -> row with vertex_ids and
## neighbor_ids as PackedInt32Array, height as float, biome_id as int, water
## as "" (land) / "ocean" / "lake". MapTerrain builds the mesh from these.
var vertices: Dictionary = {}
var cells: Dictionary = {}
## geography/coasts.csv rows (kind land|lake, feature_id, loop, points) with
## polyline and bbox set at load, like routes and rivers.
var coasts: Array[Dictionary] = []
```

In `_load`, after the `settlement_art.csv` block add:

```gdscript
	if not _load_if_present(dir + "/terrain_palette.csv", ["key", "color"],
			func(r): terrain_palette[r["key"]] = r["color"]):
		return false
```

In `load_map`, add `vertices.clear()`, `cells.clear()`, `coasts.clear()` after `map_info.clear()`, and after the `geography/biomes.csv` block add:

```gdscript
	if not _load_if_present(dir + "/geography/vertices.csv", ["vertex_id", "x", "y"],
			func(r): vertices[int(r["vertex_id"])] = Vector2(float(r["x"]), float(r["y"]))):
		return false
	if not _load_if_present(dir + "/geography/cells.csv",
			["cell_id", "vertex_ids", "height", "biome_id", "water", "neighbor_ids"],
			func(r): cells[int(r["cell_id"])] = _typed_cell(r)):
		return false
	if not _load_if_present(dir + "/geography/coasts.csv",
			["kind", "feature_id", "loop", "points"],
			func(r): coasts.append(_with_polyline(r))):
		return false
```

Next to `_with_polyline` add:

```gdscript
## A cells.csv row with its id lists and numbers parsed once, so the mesh
## builder never re-splits text.
func _typed_cell(r: Dictionary) -> Dictionary:
	r["vertex_ids"] = _id_list(String(r["vertex_ids"]))
	r["neighbor_ids"] = _id_list(String(r["neighbor_ids"]))
	r["height"] = float(r["height"])
	r["biome_id"] = int(r["biome_id"])
	return r

static func _id_list(text: String) -> PackedInt32Array:
	var out := PackedInt32Array()
	for part in text.split("|", false):
		out.append(int(part))
	return out
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gselect=test_map_data -gexit`
Expected: all tests in the file pass except `test_render_calibration_puts_the_coast_on_the_render_coastline`, which now fails on the missing `map_calibration_*` keys — it is deleted in Task 6. Everything else passes.

- [ ] **Step 6: Commit**

```bash
git add data/terrain_palette.csv data/balance.csv scripts/engine/data_repository.gd tests/engine/test_map_data.gd
git commit -m "feat(data): terrain palette, relief balance keys, and the terrain table loaders

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NPb6Y6TWL9FzyDiA6QibdQ"
```

---

### Task 3: `MapTerrain` — colours, shading, and the mesh arrays

**Files:**
- Create: `scripts/engine/map_terrain.gd`
- Test: `tests/engine/test_map_terrain.gd`

**Interfaces:**
- Consumes `DataRepository.cells / vertices / biomes / terrain_palette / balance` (Task 2 shapes).
- Produces `class_name MapTerrain` (RefCounted) with:
  - `const SEA_LEVEL := 20.0`
  - `static func is_water(cell: Dictionary) -> bool`
  - `static func light_dir(repo: DataRepository) -> Vector2`
  - `static func cell_center(repo: DataRepository, cell: Dictionary) -> Vector2`
  - `static func gradient_of(repo: DataRepository, cell: Dictionary) -> Vector2` — uphill vector over LAND neighbours.
  - `static func shade_of(repo: DataRepository, cell: Dictionary) -> float`
  - `static func palette_color(repo: DataRepository, key: String, fallback: Color) -> Color`
  - `static func cell_color(repo: DataRepository, cell: Dictionary) -> Color`
  - `static func vertex_cells(repo: DataRepository) -> Dictionary` — `vertex_id -> Array[int]`.
  - `static func build(repo: DataRepository) -> Dictionary` — `{vertices: PackedVector2Array, colors: PackedColorArray, indices: PackedInt32Array}`.
  - `static func to_mesh(built: Dictionary) -> ArrayMesh`
  - `static func shared_mesh(repo: DataRepository) -> ArrayMesh` — built once per repo instance, cached.

- [ ] **Step 1: Write the failing tests**

Create `tests/engine/test_map_terrain.gd`:

```gdscript
extends GutTest
## The terrain the game draws itself (spec 2026-09-11): hand-computed colour
## and shading formulas over tiny fixture repos, no map pack needed.

## Two 10x10 land squares side by side: cell 1 at (0..10, 0..10) height 50,
## cell 2 at (10..20, 0..10) height 60. Light from the west by default.
func _two_cells(light: Vector2 = Vector2(-1, 0), strength := 0.02,
		altitude_gain := 0.0) -> DataRepository:
	var r := DataRepository.new()
	r.balance = {"map_relief_strength": strength, "map_relief_min": 0.5,
		"map_relief_max": 1.5, "map_light_x": light.x, "map_light_y": light.y,
		"map_altitude_gain": altitude_gain, "map_sea_depth_gamma": 1.0}
	r.terrain_palette = {"biome_1": "#808080", "sea_deep": "#000000",
		"sea_shallow": "#ffffff", "lake": "#0000ff"}
	r.biomes = {1: {"biome_id": "1", "label": "Test", "color": "#ff0000"}}
	r.vertices = {0: Vector2(0, 0), 1: Vector2(10, 0), 2: Vector2(10, 10),
		3: Vector2(0, 10), 4: Vector2(20, 0), 5: Vector2(20, 10)}
	r.cells = {
		1: {"vertex_ids": PackedInt32Array([0, 1, 2, 3]), "height": 50.0,
			"biome_id": 1, "water": "", "neighbor_ids": PackedInt32Array([2])},
		2: {"vertex_ids": PackedInt32Array([1, 4, 5, 2]), "height": 60.0,
			"biome_id": 1, "water": "", "neighbor_ids": PackedInt32Array([1])},
	}
	return r

func test_cell_center_is_the_mean_of_its_vertices() -> void:
	var r := _two_cells()
	assert_eq(MapTerrain.cell_center(r, r.cells[1]), Vector2(5, 5))
	assert_eq(MapTerrain.cell_center(r, r.cells[2]), Vector2(15, 5))

## gradient = sum over land neighbours of (h_n - h_c) * unit(p_n - p_c) / N.
## Cell 1: (60 - 50) * (1, 0) / 1 = (10, 0). Cell 2: (50 - 60) * (-1, 0) = (10, 0).
func test_gradient_points_uphill() -> void:
	var r := _two_cells()
	assert_eq(MapTerrain.gradient_of(r, r.cells[1]), Vector2(10, 0))
	assert_eq(MapTerrain.gradient_of(r, r.cells[2]), Vector2(10, 0))

## shade = 1 - strength * dot(gradient, light): a slope rising toward the
## east faces a light in the west, so it brightens: 1 - 0.02 * ((10,0).(-1,0))
## = 1 + 0.2 = 1.2. With the light in the east the same slope darkens to 0.8.
func test_slopes_facing_the_light_brighten_and_those_facing_away_darken() -> void:
	var west := _two_cells(Vector2(-1, 0))
	assert_almost_eq(MapTerrain.shade_of(west, west.cells[1]), 1.2, 0.0001)
	var east := _two_cells(Vector2(1, 0))
	assert_almost_eq(MapTerrain.shade_of(east, east.cells[1]), 0.8, 0.0001)

func test_the_light_direction_is_normalised() -> void:
	var r := _two_cells(Vector2(-3, 0))
	assert_almost_eq(MapTerrain.light_dir(r).x, -1.0, 0.0001)
	assert_almost_eq(MapTerrain.shade_of(r, r.cells[1]), 1.2, 0.0001,
		"a longer light vector does not shade harder")

## strength 0.1 gives 1 + 1.0 = 2.0, clamped to map_relief_max 1.5; the
## light from the east gives 0.0, clamped to map_relief_min 0.5.
func test_shade_clamps_to_the_relief_bounds() -> void:
	var bright := _two_cells(Vector2(-1, 0), 0.1)
	assert_almost_eq(MapTerrain.shade_of(bright, bright.cells[1]), 1.5, 0.0001)
	var dark := _two_cells(Vector2(1, 0), 0.1)
	assert_almost_eq(MapTerrain.shade_of(dark, dark.cells[1]), 0.5, 0.0001)

## A cell with no land neighbours is flat: shade 1, times the altitude term
## 1 + gain * (h - 20) / 80. At h 60 and gain 0.5 that is 1.25.
func test_altitude_brightens_a_flat_cell() -> void:
	var r := _two_cells(Vector2(-1, 0), 0.02, 0.5)
	r.cells[2]["neighbor_ids"] = PackedInt32Array()
	assert_eq(MapTerrain.gradient_of(r, r.cells[2]), Vector2.ZERO)
	assert_almost_eq(MapTerrain.shade_of(r, r.cells[2]), 1.25, 0.0001)

## Land colour = the palette tint for its biome times the shade. A flat
## cell with tint #808080 is exactly #808080.
func test_land_colour_is_the_biome_tint_times_the_shade() -> void:
	var r := _two_cells()
	r.cells[1]["neighbor_ids"] = PackedInt32Array()
	var c := MapTerrain.cell_color(r, r.cells[1])
	assert_almost_eq(c.r, Color("#808080").r, 0.0001)
	assert_almost_eq(c.g, Color("#808080").g, 0.0001)
	assert_almost_eq(c.b, Color("#808080").b, 0.0001)
	# With the west light the shade is 1.2, so every channel is 1.2x.
	var lit := MapTerrain.cell_color(_two_cells(), _two_cells().cells[1])
	assert_almost_eq(lit.r, Color("#808080").r * 1.2, 0.0001)

## A biome without a palette row falls back to the pack's own biome colour.
func test_unlisted_biome_falls_back_to_the_pack_colour() -> void:
	var r := _two_cells()
	r.cells[1]["neighbor_ids"] = PackedInt32Array()
	r.terrain_palette.erase("biome_1")
	var c := MapTerrain.cell_color(r, r.cells[1])
	assert_almost_eq(c.r, 1.0, 0.0001)
	assert_almost_eq(c.g, 0.0, 0.0001)

## Ocean grades from sea_deep at h 0 to sea_shallow at h 20 (gamma 1 here);
## a lake is the lake colour whatever its height.
func test_water_colours() -> void:
	var r := _two_cells()
	var deep := {"vertex_ids": PackedInt32Array([0, 1, 2]), "height": 0.0,
		"biome_id": 0, "water": "ocean", "neighbor_ids": PackedInt32Array()}
	var half := deep.duplicate()
	half["height"] = 10.0
	var shelf := deep.duplicate()
	shelf["height"] = 20.0
	var lake := deep.duplicate()
	lake["water"] = "lake"
	lake["height"] = 15.0
	assert_almost_eq(MapTerrain.cell_color(r, deep).r, 0.0, 0.0001)
	assert_almost_eq(MapTerrain.cell_color(r, half).r, 0.5, 0.0001)
	assert_almost_eq(MapTerrain.cell_color(r, shelf).r, 1.0, 0.0001)
	assert_eq(MapTerrain.cell_color(r, lake), Color("#0000ff"))
	assert_true(MapTerrain.is_water(lake))
	assert_false(MapTerrain.is_water(r.cells[1]))

## Three triangles sharing vertex 0: land A (tint white), land B (tint
## black), ocean C (h 0, sea_deep blue). All flat. A ring vertex blends only
## the cells of its own class: on A's fan vertex 0 is the mean of A and B =
## grey; on C's fan it is C alone = blue. C is listed as a neighbour of A
## and B but, being water, does not tilt them.
func _shore() -> DataRepository:
	var r := DataRepository.new()
	r.balance = {"map_relief_strength": 0.02, "map_relief_min": 0.5,
		"map_relief_max": 1.5, "map_light_x": -1.0, "map_light_y": 0.0,
		"map_altitude_gain": 0.0, "map_sea_depth_gamma": 1.0}
	r.terrain_palette = {"biome_1": "#ffffff", "biome_2": "#000000",
		"sea_deep": "#0000ff", "sea_shallow": "#ffffff", "lake": "#00ff00"}
	r.biomes = {1: {"color": "#ff0000"}, 2: {"color": "#ff0000"}}
	r.vertices = {0: Vector2(0, 0), 1: Vector2(10, 0), 2: Vector2(0, 10),
		3: Vector2(-10, 0), 4: Vector2(0, -10)}
	r.cells = {
		1: {"vertex_ids": PackedInt32Array([0, 1, 2]), "height": 50.0, "biome_id": 1,
			"water": "", "neighbor_ids": PackedInt32Array([2, 3])},
		2: {"vertex_ids": PackedInt32Array([0, 2, 3]), "height": 50.0, "biome_id": 2,
			"water": "", "neighbor_ids": PackedInt32Array([1, 3])},
		3: {"vertex_ids": PackedInt32Array([0, 4, 1]), "height": 0.0, "biome_id": 0,
			"water": "ocean", "neighbor_ids": PackedInt32Array([1, 2])},
	}
	return r

func test_vertex_cells_lists_every_cell_touching_a_vertex() -> void:
	var adj := MapTerrain.vertex_cells(_shore())
	assert_eq(adj[0], [1, 2, 3])
	assert_eq(adj[3], [2])

func test_build_fans_each_cell_and_blends_ring_vertices_within_their_class() -> void:
	var built := MapTerrain.build(_shore())
	var verts: PackedVector2Array = built["vertices"]
	var cols: PackedColorArray = built["colors"]
	var idx: PackedInt32Array = built["indices"]
	# 3 cells x (1 centre + 3 ring) vertices; 3 triangles x 3 indices each.
	assert_eq(verts.size(), 12)
	assert_eq(cols.size(), 12)
	assert_eq(idx.size(), 27)
	assert_eq(idx.size() % 3, 0)
	# Cell 1 first: centre at index 0, its ring vertex 0 at index 1.
	assert_eq(verts[0], Vector2(10, 10) / 3.0)
	assert_eq(cols[0], Color(1, 1, 1, 1), "A's centre is white")
	assert_eq(verts[1], Vector2(0, 0))
	assert_almost_eq(cols[1].r, 0.5, 0.0001, "vertex 0 on A blends A and B")
	assert_almost_eq(cols[1].b, 0.5, 0.0001)
	# Cell 3 (ocean) is third: centre at 8, its ring vertex 0 at 9.
	assert_eq(verts[9], Vector2(0, 0))
	assert_eq(cols[9], Color(0, 0, 1, 1), "vertex 0 on C is water only")
	# Every triangle of a cell starts at that cell's centre.
	assert_eq(idx[0], 0)
	assert_eq(idx[3], 0)
	assert_eq(idx[9], 4, "cell 2's fan starts at its own centre")

func test_to_mesh_builds_a_triangle_surface() -> void:
	var mesh := MapTerrain.to_mesh(MapTerrain.build(_shore()))
	assert_not_null(mesh)
	assert_eq(mesh.get_surface_count(), 1)
	assert_eq(mesh.surface_get_primitive_type(0), Mesh.PRIMITIVE_TRIANGLES)

func test_shared_mesh_is_built_once_per_repo() -> void:
	var r := _shore()
	var a := MapTerrain.shared_mesh(r)
	assert_true(a == MapTerrain.shared_mesh(r), "the same repo gets the same mesh")
	assert_false(a == MapTerrain.shared_mesh(_shore()), "another repo gets its own")

## The committed pack builds, in native coordinates, covering the map.
func test_the_pack_builds_a_mesh_that_spans_the_map() -> void:
	var repo := DataRepository.load_all("res://data")
	assert_not_null(repo, DataRepository.last_error)
	var built := MapTerrain.build(repo)
	var b := MapGeometry.bounds(built["vertices"])
	assert_lte(b.position.x, 1.0)
	assert_lte(b.position.y, 1.0)
	assert_gte(b.end.x, float(repo.map_info["width"]) - 1.0)
	assert_gte(b.end.y, float(repo.map_info["height"]) - 1.0)
	assert_eq((built["colors"] as PackedColorArray).size(),
		(built["vertices"] as PackedVector2Array).size())
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gselect=test_map_terrain -gexit`
Expected: the script fails to parse (`MapTerrain` not declared). Note `run_tests.sh` treats an ignored script as fatal, so do not leave the suite in this state between steps.

- [ ] **Step 3: Write `MapTerrain`**

Create `scripts/engine/map_terrain.gd`:

```gdscript
class_name MapTerrain
extends RefCounted
## The terrain the game draws itself (spec 2026-09-11): the pack's Voronoi
## cells (DataRepository.cells / vertices) fanned into one vertex-coloured
## mesh. Land is its biome's palette tint times a relief shade computed from
## the neighbours' heights; the sea grades from deep to shallow by height;
## lakes are flat. Ring vertices blend the cells around them, but only within
## their own class (land with land, water with water), so the shore stays a
## crisp edge while everything inland is smooth. Pure functions over the
## repository — no Nodes, no RNG — so GUT pins every formula headless.

## Azgaar's convention: cells below this height are water.
const SEA_LEVEL := 20.0
const FALLBACK := Color(0.6, 0.6, 0.6)

## Built meshes, one per repository instance (the pack does not change
## while a repo lives, so the view and every panel share one mesh).
static var _mesh_cache: Dictionary = {}

static func is_water(cell: Dictionary) -> bool:
	return String(cell.get("water", "")) != ""

## Toward the light, unit length (ZERO when balance gives no direction).
static func light_dir(repo: DataRepository) -> Vector2:
	var l := Vector2(repo.bal("map_light_x"), repo.bal("map_light_y"))
	return l.normalized() if l.length_squared() > 0.0 else Vector2.ZERO

## The fan's hub: the mean of the cell's vertices (Voronoi cells are convex,
## so it lies inside).
static func cell_center(repo: DataRepository, cell: Dictionary) -> Vector2:
	var ids: PackedInt32Array = cell["vertex_ids"]
	if ids.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for id in ids:
		sum += repo.vertices[id] as Vector2
	return sum / float(ids.size())

## The uphill vector: sum over LAND neighbours of (h_n - h_c) * unit(p_n - p_c),
## divided by their count. Water neighbours are left out so a coast is not a
## cliff on every shore. ZERO for a cell with no land neighbours.
static func gradient_of(repo: DataRepository, cell: Dictionary) -> Vector2:
	var here := cell_center(repo, cell)
	var h := float(cell["height"])
	var g := Vector2.ZERO
	var n := 0
	for id in (cell["neighbor_ids"] as PackedInt32Array):
		var other: Dictionary = repo.cells.get(id, {})
		if other.is_empty() or is_water(other):
			continue
		var dir := cell_center(repo, other) - here
		if dir.length_squared() == 0.0:
			continue
		g += (float(other["height"]) - h) * dir.normalized()
		n += 1
	return g / float(n) if n > 0 else Vector2.ZERO

## Relief times altitude: a slope whose downhill side faces the light is
## lit (1 - strength * dot(uphill, light)), clamped to the balance bounds,
## then brightened with height from sea level to the summit.
static func shade_of(repo: DataRepository, cell: Dictionary) -> float:
	var relief := clampf(
		1.0 - repo.bal("map_relief_strength") * gradient_of(repo, cell).dot(light_dir(repo)),
		repo.bal("map_relief_min"), repo.bal("map_relief_max"))
	var altitude := 1.0 + repo.bal("map_altitude_gain") \
		* (float(cell["height"]) - SEA_LEVEL) / (100.0 - SEA_LEVEL)
	return relief * altitude

## A terrain_palette colour, or `fallback` when the key is not authored.
static func palette_color(repo: DataRepository, key: String, fallback: Color) -> Color:
	var hex := String(repo.terrain_palette.get(key, ""))
	return Color(hex) if hex != "" else fallback

static func _land_tint(repo: DataRepository, cell: Dictionary) -> Color:
	var bid := int(cell["biome_id"])
	var pack_hex := String((repo.biomes.get(bid, {}) as Dictionary).get("color", ""))
	return palette_color(repo, "biome_%d" % bid, Color(pack_hex) if pack_hex != "" else FALLBACK)

static func cell_color(repo: DataRepository, cell: Dictionary) -> Color:
	var kind := String(cell.get("water", ""))
	if kind == "lake":
		return palette_color(repo, "lake", FALLBACK)
	if kind != "":
		var t := pow(clampf(float(cell["height"]) / SEA_LEVEL, 0.0, 1.0),
			repo.bal("map_sea_depth_gamma"))
		return palette_color(repo, "sea_deep", FALLBACK).lerp(
			palette_color(repo, "sea_shallow", FALLBACK), t)
	var s := shade_of(repo, cell)
	var tint := _land_tint(repo, cell)
	return Color(tint.r * s, tint.g * s, tint.b * s, 1.0)

static func _sorted_ids(repo: DataRepository) -> Array:
	var ids: Array = repo.cells.keys()
	ids.sort()
	return ids

## vertex_id -> the cells (ids, in cell order) whose polygon touches it.
static func vertex_cells(repo: DataRepository) -> Dictionary:
	var out: Dictionary = {}
	for id in _sorted_ids(repo):
		for v in ((repo.cells[id] as Dictionary)["vertex_ids"] as PackedInt32Array):
			if not out.has(v):
				out[v] = []
			(out[v] as Array).append(id)
	return out

## The mean colour of the cells around a vertex that share `water` with the
## fan being built; the fan's own colour when none does.
static func _ring_color(touching: Array, colors: Dictionary, cells: Dictionary,
		water: bool, own: Color) -> Color:
	var sum := Color(0, 0, 0, 0)
	var n := 0
	for id in touching:
		if is_water(cells[id]) != water:
			continue
		sum += colors[id] as Color
		n += 1
	return sum / float(n) if n > 0 else own

## The mesh arrays in native map coordinates: per cell (in id order) one
## centre vertex then one ring vertex per polygon vertex, and a triangle
## (centre, ring[i], ring[i + 1]) per edge.
static func build(repo: DataRepository) -> Dictionary:
	var ids := _sorted_ids(repo)
	var colors: Dictionary = {}
	for id in ids:
		colors[id] = cell_color(repo, repo.cells[id])
	var touching := vertex_cells(repo)
	var verts := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	for id in ids:
		var cell: Dictionary = repo.cells[id]
		var ring: PackedInt32Array = cell["vertex_ids"]
		if ring.size() < 3:
			continue
		var water := is_water(cell)
		var own: Color = colors[id]
		var base := verts.size()
		verts.append(cell_center(repo, cell))
		cols.append(own)
		for v in ring:
			verts.append(repo.vertices[v] as Vector2)
			cols.append(_ring_color(touching[v], colors, repo.cells, water, own))
		var n := ring.size()
		for i in n:
			idx.append(base)
			idx.append(base + 1 + i)
			idx.append(base + 1 + (i + 1) % n)
	return {"vertices": verts, "colors": cols, "indices": idx}

static func to_mesh(built: Dictionary) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = built["vertices"]
	arrays[Mesh.ARRAY_COLOR] = built["colors"]
	arrays[Mesh.ARRAY_INDEX] = built["indices"]
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh

## The mesh for this repository, built on first use. null when the pack
## carries no cells (an older pack): the view then stays hidden.
static func shared_mesh(repo: DataRepository) -> ArrayMesh:
	if repo.cells.is_empty():
		return null
	var key := repo.get_instance_id()
	if not _mesh_cache.has(key):
		_mesh_cache[key] = to_mesh(build(repo))
	return _mesh_cache[key]
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gselect=test_map_terrain -gexit`
Expected: all 14 tests pass. If `test_build_fans...` reports `cols[1].r` as 0.5 but `cols[1].a` differs, check `_ring_color`'s sum starts at alpha 0 and divides — alpha ends at 1.0 for two opaque cells; the test only reads `r` and `b`.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/map_terrain.gd tests/engine/test_map_terrain.gd
git commit -m "feat(map): MapTerrain — cells to a vertex-coloured relief mesh

Biome tint times a slope shade from land neighbours, depth-graded sea,
flat lakes; ring vertices blend within their land/water class so the
shore stays crisp. Hand-computed GUT tests.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NPb6Y6TWL9FzyDiA6QibdQ"
```

---

### Task 4: `WorldMapView` draws the mesh, coasts, rivers and routes

**Files:**
- Modify: `scripts/ui/world_map_view.gd`
- Test: `tests/ui/test_world_map_view.gd`

**Interfaces:**
- Consumes `MapTerrain.shared_mesh(repo)`, `MapTerrain.palette_color(repo, key, fallback)`, `repo.coasts`, `repo.rivers[code]["discharge"]`, `repo.routes`.
- Produces on `WorldMapView`: `func map_size() -> Vector2`, `func terrain_mesh() -> ArrayMesh`, `func visible_rivers() -> Array`, `func visible_river_count() -> int`. `view_scale()` now equals `_zoom`; `map_to_screen` / `screen_to_map` are `_offset + p * _zoom` and its inverse.

- [ ] **Step 1: Update the tests**

In `tests/ui/test_world_map_view.gd`:

Replace the three tests `test_screen_and_map_coordinates_round_trip_through_the_calibration`, `test_the_calibration_is_applied_to_the_render_mapping`, and `test_the_index_bitmap_agrees_with_the_calibrated_mapping` (and the comment block above the first) with:

```gdscript
## The map is drawn from the pack's own cells (spec 2026-09-11), so native
## coordinates go to the screen through the pan and zoom alone.
func test_screen_and_map_coordinates_round_trip() -> void:
	var v := _view()
	await wait_frames(2)
	for native in [Vector2(0, 0), Vector2(1216.79, 601.05), Vector2(2559, 928)]:
		var back := v.screen_to_map(v.map_to_screen(native))
		assert_almost_eq(back.x, native.x, 0.01, "x round-trips at %s" % native)
		assert_almost_eq(back.y, native.y, 0.01, "y round-trips at %s" % native)
	var native := Vector2(1000, 400)
	var want := v.map_to_screen(Vector2.ZERO) + native * v.view_scale()
	assert_almost_eq(v.map_to_screen(native).x, want.x, 0.01, "x is offset + native * zoom")
	assert_almost_eq(v.map_to_screen(native).y, want.y, 0.01, "y is offset + native * zoom")

func test_the_terrain_is_a_mesh_built_from_the_pack() -> void:
	var v := _view()
	await wait_frames(2)
	assert_not_null(v.terrain_mesh(), "the terrain mesh is built from cells.csv")
	assert_eq(v.map_size(), Vector2(float(Game.data.map_info["width"]),
		float(Game.data.map_info["height"])), "the map's size is the pack's canvas")
	assert_true(v.visible)

## Hit-testing samples the index bitmaps, which are in native coordinates:
## the capital's own pixel must resolve to the capital's own kingdom.
func test_the_index_bitmap_agrees_with_the_mapping() -> void:
	var v := _view()
	await wait_frames(2)
	var k: Dictionary = _capital()
	var native := Vector2(float(k["x"]), float(k["y"]))
	var back := v.screen_to_map(v.map_to_screen(native))
	assert_almost_eq(back.x, native.x, 0.01, "capital survives the round trip")
	assert_almost_eq(back.y, native.y, 0.01, "capital survives the round trip")

## Rivers are drawn by the game now that no render prints them: every river
## is in view with the whole world; none is when the view is zoomed into the
## open sea at the map's corner.
func test_rivers_draw_where_the_view_is() -> void:
	var v := _view()
	await wait_frames(2)
	v._zoom_at(v.size / 2.0, 0.0001)
	assert_eq(v.visible_river_count(), Game.data.rivers.size(), "the whole world shows every river")
	v._zoom_at(Vector2.ZERO, 1000.0)
	assert_eq(v.visible_river_count(), 0, "open sea in the corner shows none")
```

In `test_opens_filling_the_frame` and `test_zooming_out_reaches_the_whole_map` replace `v._map_texture.get_size()` with `v.map_size()`.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gselect=test_world_map_view -gexit`
Expected: parse failure on `map_size` / `terrain_mesh` / `visible_river_count` (nonexistent methods) — the file is ignored. Proceed straight to Step 3.

- [ ] **Step 3: Switch the view from the texture to the mesh**

In `scripts/ui/world_map_view.gd`:

1. Replace the block from `var _map_texture: Texture2D` through `var _cal_offset := Vector2.ZERO` (keep `var _index_image: Image` — it sits between them; move it below) with:

```gdscript
## The terrain (spec 2026-09-11): one vertex-coloured mesh of every cell,
## built once from the pack (MapTerrain) and drawn with the view transform.
## No render PNG exists; the map's extent is the pack's canvas.
var _terrain_mesh: ArrayMesh
var _map_size := Vector2.ZERO
## Shore loops (coasts.csv) smoothed once, drawn over the mesh.
var _coast_rings: Array = []
var _index_image: Image
```

2. In `_ready` replace the block from `var map_path := Game.data.map_texture_path` through `_cal_offset = Game.data.render_offset` with:

```gdscript
	_map_size = Vector2(float(Game.data.map_info.get("width", "0")),
		float(Game.data.map_info.get("height", "0")))
	if _map_size.x > 0.0 and _map_size.y > 0.0:
		_terrain_mesh = MapTerrain.shared_mesh(Game.data)
	var index_path := Game.data.index_texture_path
	if index_path != "" and ResourceLoader.exists(index_path):
		var idx: Texture2D = load(index_path)
		_index_image = idx.get_image()
	_province_image = _load_image(Game.data.province_texture_path)
	_biome_image = _load_image(Game.data.biome_texture_path)
	_build_coast_rings()
```
and change the last line of `_ready` to `visible = _terrain_mesh != null`. Update the class doc comment's `(the render is terrain only)` to `(the terrain is a mesh built from the pack's cells, MapTerrain)`.

3. Replace every remaining `_map_texture == null` with `_terrain_mesh == null` and every `_map_texture.get_size()` with `_map_size` (in `_go_home`, `_zoom_cover`, `settlement_sprites`, `army_markers`, `political_fills`, `_process`, `_gui_input`, `_zoom_min`, `_clamp_offset`, `_visible_seams`).

4. Replace `_draw` up to `_draw_political_wash()` with:

```gdscript
func _draw() -> void:
	if _terrain_mesh == null:
		return
	if not _homed and size.y > 0.0:
		_go_home()
	draw_rect(Rect2(Vector2.ZERO, size),
		MapTerrain.palette_color(Game.data, "sea_deep", MapTerrain.FALLBACK))
	draw_mesh(_terrain_mesh, null, Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, _offset))
	_draw_coasts()
	_draw_rivers()
	_draw_routes()
	_draw_political_wash()
```

5. Replace `view_scale`, `map_to_screen`, `screen_to_map` (and their comments) with:

```gdscript
## Screen px per native map px — the LOD and pick radii are defined on it.
func view_scale() -> float:
	return _zoom

## Native map coordinates (pack tables, index bitmaps) -> screen.
func map_to_screen(native: Vector2) -> Vector2:
	return _offset + native * _zoom

## The exact inverse — hit-testing samples the index bitmaps in native space.
func screen_to_map(pos: Vector2) -> Vector2:
	return (pos - _offset) / _zoom

func map_size() -> Vector2:
	return _map_size

func terrain_mesh() -> ArrayMesh:
	return _terrain_mesh
```

6. After `_ring_touches` add the terrain strokes:

```gdscript
func _build_coast_rings() -> void:
	_coast_rings.clear()
	var steps := int(Game.data.bal("map_border_smoothing_steps"))
	for row: Dictionary in Game.data.coasts:
		_coast_rings.append(MapGeometry.smooth_closed(row["polyline"], steps))

## Every shore (islands and lakes) as a smooth stroke in the palette's
## coast colour — the same B-spline as the kingdom borders, so a border
## along a coast sits on the drawn shore.
func _draw_coasts() -> void:
	var color := MapTerrain.palette_color(Game.data, "coast_line", MapTerrain.FALLBACK)
	var width := Game.data.bal("map_coast_width")
	var frame := Rect2(Vector2.ZERO, size).grow(width * 2.0)
	for ring: PackedVector2Array in _coast_rings:
		var pts := _closed_screen_ring(ring)
		if _ring_touches(pts, frame):
			draw_polyline(pts, color, width, true)

func _screen_polyline(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(pts.size())
	for i in pts.size():
		out[i] = map_to_screen(pts[i])
	return out

func _line_in_frame(row: Dictionary) -> bool:
	var b: Rect2 = row["bbox"]
	var on_screen := Rect2(map_to_screen(b.position), b.size * view_scale()).grow(2.0)
	return Rect2(Vector2.ZERO, size).intersects(on_screen)

## The river rows whose extent touches the frame. Public for tests.
func visible_rivers() -> Array:
	if _terrain_mesh == null:
		return []
	var out: Array = []
	for code: String in Game.data.rivers:
		if _line_in_frame(Game.data.rivers[code]):
			out.append(Game.data.rivers[code])
	return out

func visible_river_count() -> int:
	return visible_rivers().size()

## Rivers widen with their discharge (native px per sqrt(discharge), so a
## great river is a few px across at native scale) and never thinner than
## map_river_min_px on screen.
func _draw_rivers() -> void:
	var rivers := visible_rivers()
	if rivers.is_empty():
		return
	var color := MapTerrain.palette_color(Game.data, "river", MapTerrain.FALLBACK)
	var min_px := Game.data.bal("map_river_min_px")
	var k := Game.data.bal("map_river_discharge_scale")
	for r: Dictionary in rivers:
		var width := maxf(min_px, k * sqrt(float(r.get("discharge", "0"))) * view_scale())
		draw_polyline(_screen_polyline(r["polyline"]), color, width, true)

## Roads always; trails and sea routes once the view is close enough.
func _draw_routes() -> void:
	if _terrain_mesh == null:
		return
	var show_trails := view_scale() >= Game.data.bal("map_trail_min_scale")
	var road := MapTerrain.palette_color(Game.data, "road", MapTerrain.FALLBACK)
	var trail := MapTerrain.palette_color(Game.data, "trail", MapTerrain.FALLBACK)
	var road_w := Game.data.bal("map_road_width")
	var trail_w := Game.data.bal("map_trail_width")
	for code: String in Game.data.routes:
		var r: Dictionary = Game.data.routes[code]
		var is_road := String(r["group"]) == "roads"
		if not is_road and not show_trails:
			continue
		if not _line_in_frame(r):
			continue
		draw_polyline(_screen_polyline(r["polyline"]), road if is_road else trail,
			road_w if is_road else trail_w, true)
```

7. Update the `_draw_hover` comment: replace `Roads and rivers are named by the tooltip and the card but are NOT traced (user ruling 2026-09-09): the render already draws them, and a gold line over the top only obscured them.` with `Roads and rivers are drawn by the terrain layer in their own colours and are not re-traced on hover: the tooltip and the card name them.`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gselect=test_world_map_view -gexit`
Expected: every test in the file passes (the existing hover, card, province, sprite, and army tests are untouched and still pass). `grep -n "_map_texture\|_cal_scale\|_cal_offset\|_render_scale" scripts/ui/world_map_view.gd` prints nothing.

- [ ] **Step 5: Look at it**

Run the game (`/Applications/Godot.app/Contents/MacOS/Godot --path .`), start a campaign, and check: the sea is a blue gradient, land is tinted and shaded, coasts are stroked, rivers and roads are visible, the political wash and borders sit on the shore, zooming in stays sharp. Fix any glaring palette/balance value in the CSVs (not in code) before committing.

- [ ] **Step 6: Commit**

```bash
git add scripts/ui/world_map_view.gd tests/ui/test_world_map_view.gd
git commit -m "feat(map): draw the terrain from the pack's cells — no PNG background

One vertex-coloured mesh under the political layer, plus coast, river
and route strokes. The view transform is pan and zoom alone.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NPb6Y6TWL9FzyDiA6QibdQ"
```

---

### Task 5: The detail panel's place preview draws the mesh

**Files:**
- Modify: `scripts/ui/map_detail_panel.gd`
- Test: `tests/ui/test_map_detail_panel.gd`

**Interfaces:**
- Consumes `MapTerrain.shared_mesh(repo)`, `MapTerrain.palette_color`, `repo.coasts`.
- Produces `MapDetailPanel.TerrainPreview` (inner `Control` class) with `var mesh: ArrayMesh`, `func show_place(center: Vector2) -> void`; `MapDetailPanel.preview()` now returns `TerrainPreview`.

- [ ] **Step 1: Update the test**

In `tests/ui/test_map_detail_panel.gd`, in `test_a_town_gets_a_card` replace
`assert_not_null(p.preview().texture)` with
`assert_not_null(p.preview().mesh, "drawn from the terrain mesh, not a picture")`.

- [ ] **Step 2: Run the test to verify it fails**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gselect=test_map_detail_panel -gexit`
Expected: `test_a_town_gets_a_card` errors (`mesh` is not a property of TextureRect); the other tests still pass.

- [ ] **Step 3: Replace the atlas preview with a mesh preview**

In `scripts/ui/map_detail_panel.gd`:

1. Change `var _preview: TextureRect` to `var _preview: TerrainPreview`.

2. In `_ready` replace the `_preview = TextureRect.new()` block (through `body.add_child(_preview)`) with:

```gdscript
	_preview = TerrainPreview.new()
	_preview.name = "Preview"
	_preview.custom_minimum_size = PREVIEW_SIZE
	_preview.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	body.add_child(_preview)
```

3. Replace `_set_preview` (and its doc comment) with:

```gdscript
## A window onto the world map around a place, PREVIEW_SPAN native px
## across, drawn from the same terrain mesh as the map (no render exists).
func _set_preview(center: Vector2) -> void:
	_preview.show_place(center)
```

4. Change `func preview() -> TextureRect:` to `func preview() -> TerrainPreview:`.

5. At the end of the file add the inner class:

```gdscript
## The card's map window: the terrain mesh and the shores, scaled so
## `span` native px cover the rect (cover fit, like the old atlas) and
## centred on the place. Reads Game.data only.
class TerrainPreview extends Control:
	var mesh: ArrayMesh
	var span: Vector2 = MapDetailPanel.PREVIEW_SPAN
	var _center := Vector2.ZERO

	func _init() -> void:
		clip_contents = true
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func show_place(center: Vector2) -> void:
		mesh = MapTerrain.shared_mesh(Game.data)
		_center = center
		visible = mesh != null
		queue_redraw()

	func _draw() -> void:
		if mesh == null:
			return
		var k := maxf(size.x / span.x, size.y / span.y)
		var origin := size / 2.0 - _center * k
		draw_rect(Rect2(Vector2.ZERO, size),
			MapTerrain.palette_color(Game.data, "sea_deep", MapTerrain.FALLBACK))
		draw_mesh(mesh, null, Transform2D(0.0, Vector2(k, k), 0.0, origin))
		var coast := MapTerrain.palette_color(Game.data, "coast_line", MapTerrain.FALLBACK)
		var frame := Rect2(Vector2.ZERO, size).grow(2.0)
		for row: Dictionary in Game.data.coasts:
			var b: Rect2 = row["bbox"]
			if not frame.intersects(Rect2(origin + b.position * k, b.size * k)):
				continue
			var loop: PackedVector2Array = row["polyline"]
			var pts := PackedVector2Array()
			pts.resize(loop.size() + 1)
			for i in loop.size():
				pts[i] = origin + loop[i] * k
			pts[loop.size()] = pts[0]
			draw_polyline(pts, coast, 1.0, true)
```

`_clear()` already sets `_preview.visible = false`; leave it.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gselect=test_map_detail_panel -gexit`
Expected: all pass. `grep -n "map_texture_path\|render_scale\|render_offset" scripts/ui/map_detail_panel.gd` prints nothing.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/map_detail_panel.gd tests/ui/test_map_detail_panel.gd
git commit -m "feat(ui): the place preview draws the terrain mesh instead of a PNG atlas

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NPb6Y6TWL9FzyDiA6QibdQ"
```

---

### Task 6: Remove the PNG, the calibration, and their tests; update CLAUDE.md

**Files:**
- Delete: `assets/maps/beria/world_map.png`, `assets/maps/beria/world_map.png.import`, `tools/calibrate_render.py`
- Modify: `data/maps.csv`, `scripts/engine/data_repository.gd`, `tests/engine/test_map_data.gd`, `tests/engine/test_map_pack.gd`, `CLAUDE.md`

**Interfaces:**
- `DataRepository` loses `map_texture_path`, `render_scale`, `render_offset`; `maps.csv` loses `map_texture`, `render_scale`, `render_offset_x`, `render_offset_y`.

- [ ] **Step 1: Update the tests**

`tests/engine/test_map_data.gd`:
- In `test_index_bitmap_matches_map_and_kingdoms`, rename it `test_index_bitmap_decodes_each_kingdom_at_its_center` and delete the `map_tex` lines: remove `var map_tex ...`, `assert_not_null(map_tex)`, the `k` computation and its two asserts, and the two comment lines about the render. Keep `idx_tex`, `img`, and the loop.
- Delete `test_render_calibration_puts_the_coast_on_the_render_coastline` with its doc comment and the helpers `_is_coast` and `_is_land`.

`tests/engine/test_map_pack.gd`:
- In `test_default_pack_loads_with_its_world_and_art` delete the two-line `assert_true(ResourceLoader.exists(repo.map_texture_path), ...)`.
- Delete `test_render_calibration_is_usable` with its doc comment.
- In the doc comment above `test_maps_csv_rows_parse_to_the_full_header` change `silently reading the notes tail as the render calibration` to `silently reading the notes tail as the next column`.

- [ ] **Step 2: Delete the files and the columns**

```bash
git rm -q assets/maps/beria/world_map.png assets/maps/beria/world_map.png.import tools/calibrate_render.py
```

Rewrite `data/maps.csv` as:

```csv
map_id,label,index_texture,province_texture,biome_texture,data_dir,is_default,notes
beria,Beria,res://assets/maps/beria/world_state_index.png,res://assets/maps/beria/world_province_index.png,res://assets/maps/beria/world_biome_index.png,res://data/maps/beria,1,"The founding world. Azgaar export 2026-09-09 (Game_dev, seed 954159497). The terrain is drawn from the pack's cells (geography/cells.csv, MapTerrain); no render PNG exists. The game paints the political layer over it."
```

In `scripts/engine/data_repository.gd`:
- Delete `var map_texture_path: String = ""`.
- Delete the comment block beginning `## How the map render sits on the pack's coordinates` and the two vars `render_scale` and `render_offset`.
- In `_load`, the `maps.csv` required columns become `["map_id", "label", "index_texture", "data_dir"]`.
- In `load_map`, delete the `render_scale = ...`, `render_offset = Vector2(...)` (three lines), and `map_texture_path = String(m["map_texture"])`.

- [ ] **Step 3: Rewrite the CLAUDE.md map paragraph**

In `CLAUDE.md`, in the long `- council_seats.csv, ...` bullet, replace the text from `plus \`assets/maps/<id>/world_map.png\` and the` up to the end of that bullet (`... every drawn border sat beside the printed one).`) with:

```
plus the `world_state_index.png` / `world_province_index.png` / `world_biome_index.png` hit-test bitmaps are **generated** by `tools/import_azgaar.gd` from the Azgaar JSON export in `assets/maps/<id>/` — hand-edits are overwritten on re-import; lasting changes belong in Azgaar. **There is no map render PNG** (owner ruling 2026-09-11): the terrain is drawn by the game from the pack's cells — `geography/vertices.csv`, `cells.csv` (vertex ids, height, biome, water kind, neighbours) and `coasts.csv` (land and lake shores) — through `MapTerrain`, one vertex-coloured mesh whose colours come from `data/terrain_palette.csv` (a land tint per biome, sea, lake, and line colours) and whose relief and stroke widths come from `balance.csv` (`map_relief_*`, `map_light_*`, `map_river_*`, ...). The game paints every province in its live owner's colour from `data/political_palette.csv` via `MapPalette`, and `WorldMapView` draws the coasts, rivers, routes, every kingdom's border, the province seams, and the labels itself, so conquest repaints and redraws with no new art. All pack coordinates are the JSON's own (2560×929 for `beria`); nothing is calibrated or scaled at import. The importer needs only the `*Full*.json`; it never reads a PNG.
```

Also in the `Test:` bullet of the Stack section nothing changes. In the "Architecture invariants" item 6, leave as is (it already says hit-testing reads the province bitmap).

- [ ] **Step 4: Run the full suite**

Run: `./run_tests.sh`
Expected: all scripts run, no "Ignoring script", `Errors 2`, zero failures. Also `grep -rn "map_texture\|render_scale\|render_offset\|calibrate_render\|world_map.png" --include='*.gd' --include='*.csv' --include='*.py' --include='*.sh' scripts tests tools data run_tests.sh` prints nothing (the spec and plan under `docs/` may still mention them).

- [ ] **Step 5: Commit**

```bash
git add data/maps.csv scripts/engine/data_repository.gd tests/engine/test_map_data.gd tests/engine/test_map_pack.gd CLAUDE.md
git commit -m "chore(map): remove the render PNG, the calibration, and their tests

The terrain is drawn from data now, so the 41 MB export, maps.csv's
render columns, calibrate_render.py and the coastline-fit test go.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01NPb6Y6TWL9FzyDiA6QibdQ"
```

---

## Self-review notes

- Spec §1 (three tables, no PNG, discharge) → Task 1. §2 (palette, balance keys, calibration keys removed) → Task 2 (adds) and Task 2 Step 3 (removes). §3 (`MapTerrain`) → Task 3. §4 (loaders, field removals) → Tasks 2 and 6. §5 (view) → Task 4. §6 (preview) → Task 5. §7 (removals, CLAUDE.md) → Task 6. §8 tests → each task's Step 1. §9 migration order → task order.
- The spec's shade formula reads `1 + strength × dot(slope, light)`; the plan uses `1 − strength × dot(uphill, light)` so a slope whose downhill side faces the light brightens (the spec is amended alongside this plan). The spec's river width reads the river row's `width`; the plan uses `sqrt(discharge)` (Azgaar's `width` is a mouth width of 0.02–0.86, too flat to grade strokes by), also amended.
- Cells/vertices/coasts are not registered in `world_tables` (int keys; they are geometry, not ledger data). The spec is amended to say so.
