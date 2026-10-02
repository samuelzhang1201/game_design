# WAR ROOM v2 — B: the graticule and the scale — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The WAR ROOM's sheets are cells of the pack's own graticule (`mapCoordinates`, 20° each, ~4.7× the old scale), chosen on a gridded index chart by tossing a war marker onto a cell, and the laid sheet shows far more: finer relief from the build's own heightmap, a neat line and a collar, manors, walls and ports, bridges and fords, rivers that widen and are named, woods, hollows — and a second, daily ink layer of what we know (supply lines, couriers, weather, spy reports).

**Architecture:** `MapCoords` (pure) turns pack px into longitude and latitude from `map_info.csv`'s new rows; `WarSheets` cuts the series by it, each sheet a neat-line `cell` and a table `rect` grown by a collar, ids like `D4`. `WarBake` reads the build's `bake/height.r32` and `woods.png` directly (the very heights Terrain3D was built from — no 3D map needed, so it runs headless). `WarSheetInk` gains the new marks; a new `WarIntelInk` gives the intelligence strokes, painted by the same `WarInkPainter` into a second texture the table shader lays over the first. `WarToss` (pure) flies the marker; `WarIndexChart` / `WarRoomWall` draw and pick the graticule chart.

**Tech Stack:** Godot 4.7, typed GDScript, GUT, `tools/snapshot_screen.gd`, `tools/war_room/bench.tscn`.

**Spec:** `docs/superpowers/specs/2026-10-02-war-room-v2-design.md` §2 (rulings 6–8). Plan A (`docs/superpowers/plans/2026-10-02-war-room-v2-a-camera-layout.md`) is merged; read its §-free summary in CLAUDE.md's WAR ROOM paragraph.

## Global Constraints

- Every design value lives in `data/balance.csv` (key,value,notes); notes start `WAR ROOM v2 B (owner 2026-10-02, spec §2…)`. Colours in `data/war_palette.csv`.
- `scripts/war_room/` never names the `Game` autoload (`tests/war_room/test_war_room_isolation.gd`).
- Typed GDScript everywhere.
- No pack is named in code or tests: fixtures derive from `SuiteData.repo()` (beria today); hand-computed values may use beria's `map_info` numbers only where the test says so in a comment.
- Every look is checked through the REAL window: `snapshot_screen ... --resolution WxH` (the default `--scale` misplaces the widened room); never a 3D snapshot headless.
- The suite must end green with the expected error count (`./run_tests.sh`, `Errors 0` in a worktree without the gdai binaries).
- Never switch branches in `/Users/samuelzhang/game_design`. Work in `.claude/worktrees/war-room-v2-b` on `design/war-room-v2-b`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.

## Spec refinement carried by this plan

- **§2.4's relief source:** the spec said "sampled from the built Terrain3D heightmap through a `height_fn` the screen hands the view". The SAME heights are the build's `bake/height.r32` (float metres, 20 m vertices, 2.5 per pack px — `world_relief.png` is 1 per pack px and 8-bit), so `WarBake` reads that file by rows instead: no dependence on the 3D map being loaded, and testable headless. Without a built bake, `world_relief.png` as before. Task 11 writes this into the spec's §12.

## Review Focus

1. **A pack without `mapCoordinates` rows** (an older import) must still lay sheets — the whole globe over the map, one warning — pin: Task 1 test.
2. **A regiment standing in a sheet's COLLAR** must show as a piece on that sheet AND be listed in the margin of no sheet twice — pin: Task 2 test.
3. **Clicking the chart while a toss is in flight or a sheet is rolling** must not start a second toss or lay two sheets — pin: Task 6 test.
4. **A sheet at the map's edge** (its collar off the map) must sample heights and woods without reading outside the files — pin: Task 3 test.
5. **The intelligence layer must never draw what we do not know**: only the crown's own supply lines and couriers, and spy reports that have ARRIVED (in `state.missives`) — pin: Task 9 test with a foreign regiment and a riding spy.

---

### Task 0: Worktree setup and a green baseline

- [ ] **Step 1: Bring the git-ignored assets over** (memory: worktree-needs-ignored-assets)

```bash
cd /Users/samuelzhang/game_design/.claude/worktrees/war-room-v2-b
M=/Users/samuelzhang/game_design
cp -Rc $M/.godot ./.godot
sed -i '' '/gdai-mcp/d' .godot/extension_list.cfg
mkdir -p assets/3D/terrain
for d in beria textures trees; do ln -s $M/assets/3D/terrain/$d assets/3D/terrain/$d; done
(cd $M && git ls-files --others --ignored --exclude-standard assets/3D | grep -v model_wip | grep -v '^assets/3D/terrain/') > /tmp/wrb_ignored.txt
while IFS= read -r f; do mkdir -p "$(dirname "$f")"; [ -e "$f" ] || cp -c "$M/$f" "$f"; done < /tmp/wrb_ignored.txt
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import > /dev/null 2>&1
```

- [ ] **Step 2: A one-file runner** — create the plan's workspace runner (the executing skill's `sdd-workspace` prints the dir; call it `$W`):

```bash
cat > $W/t.sh <<'EOF'
#!/bin/bash
cd /Users/samuelzhang/game_design/.claude/worktrees/war-room-v2-b
OUT=$(dirname "$0")/last.log
ARGS=()
for a in "$@"; do if [[ "$a" == *.gd ]]; then ARGS+=("-gtest=$a"); else ARGS+=("-gdir=$a" "-ginclude_subdirs"); fi; done
CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd "${ARGS[@]}" -gpre_run_script=res://tests/pre_run.gd -gexit > $OUT 2>&1
code=$?
grep -E "Parse Error|\[Failed\]|Passing|Failing" $OUT | head -40
exit $code
EOF
chmod +x $W/t.sh
$W/t.sh res://tests/war_room res://tests/engine/test_war_sheets.gd res://tests/engine/test_war_room.gd res://tests/ui/test_war_room_screen.gd
```
Expected: all pass. A new `class_name` needs `Godot --headless --path . --import` once before its first test run.

---

### Task 1: `MapCoords` and the pack's coordinates

**Files:**
- Create: `scripts/engine/map_coords.gd`
- Modify: `tools/import_azgaar.gd:1104-1111` (map_info rows), `data/maps/beria/map_info.csv` (six rows), `tools/NEW_MAP.md` (one line)
- Test: `tests/engine/test_map_coords.gd`

**Interfaces:**
- Produces: `MapCoords` (static): `bounds(repo) -> Dictionary` `{lat_n, lat_s, lon_w, lon_e, w, h}`; `px_per_deg(repo) -> Vector2`; `lon_lat(repo, px: Vector2) -> Vector2` (x lon, y lat); `px_of(repo, lon: float, lat: float) -> Vector2`; `cell_of(repo, px: Vector2, deg: float) -> Vector2i`; `cell_rect(repo, cell: Vector2i, deg: float) -> Rect2`; `grid_size(repo, deg: float) -> Vector2i`; `format(lon_lat: Vector2) -> String` ("23°N 51°E").

- [ ] **Step 1: Failing tests** — create `tests/engine/test_map_coords.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The pack's own graticule (spec 2026-10-02-war-room-v2 §2.1): pack px to
## longitude and latitude from map_info's mapCoordinates rows.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	repo.map_info["width"] = "2000"
	repo.map_info["height"] = "1000"
	repo.map_info["lat_n"] = "60"
	repo.map_info["lat_s"] = "-40"
	repo.map_info["lon_w"] = "-100"
	repo.map_info["lon_e"] = "100"


func test_the_corners_and_the_middle() -> void:
	assert_eq(MapCoords.px_per_deg(repo), Vector2(10.0, 10.0))
	assert_eq(MapCoords.lon_lat(repo, Vector2.ZERO), Vector2(-100.0, 60.0), "north-west corner")
	assert_eq(MapCoords.lon_lat(repo, Vector2(2000, 1000)), Vector2(100.0, -40.0), "south-east corner")
	assert_eq(MapCoords.px_of(repo, 0.0, 0.0), Vector2(1000.0, 600.0))


func test_cells_count_from_the_north_west_corner() -> void:
	assert_eq(MapCoords.cell_of(repo, Vector2(250, 150), 20.0), Vector2i(1, 0))
	assert_eq(MapCoords.cell_rect(repo, Vector2i(1, 0), 20.0), Rect2(200, 0, 200, 200))
	assert_eq(MapCoords.grid_size(repo, 20.0), Vector2i(10, 5))
	assert_eq(MapCoords.grid_size(repo, 30.0), Vector2i(7, 4), "a part cell at the edge still counts")


func test_format_rounds_to_whole_degrees() -> void:
	assert_eq(MapCoords.format(Vector2(51.4, 23.6)), "24°N 51°E")
	assert_eq(MapCoords.format(Vector2(-12.5, -3.2)), "3°S 13°W")
	assert_eq(MapCoords.format(Vector2(0.2, -0.2)), "0°N 0°E")


func test_a_pack_without_coordinates_spans_the_globe() -> void:
	for k in ["lat_n", "lat_s", "lon_w", "lon_e"]:
		repo.map_info.erase(k)
	var b := MapCoords.bounds(repo)
	assert_eq([b["lat_n"], b["lat_s"], b["lon_w"], b["lon_e"]], [90.0, -90.0, -180.0, 180.0])


func test_the_pack_carries_its_coordinates() -> void:
	var real := SuiteData.repo()
	for k in ["lat_n", "lat_s", "lon_w", "lon_e"]:
		assert_true(real.map_info.has(k), k)
```

- [ ] **Step 2: Run** `$W/t.sh res://tests/engine/test_map_coords.gd` — Expected: parse error, `MapCoords` not declared.

- [ ] **Step 3: Implement** `scripts/engine/map_coords.gd`:

```gdscript
class_name MapCoords
extends RefCounted
## The pack's own graticule (owner 2026-10-02, spec 2026-10-02-war-room-v2
## §2.1): Azgaar's mapCoordinates — the latitudes and longitudes the map's
## edges stand at — imported into map_info.csv as lat_n / lat_s / lon_w /
## lon_e. Pack px run east and SOUTH; latitude north. A pack imported before
## the rows existed spans the whole globe (and warns once). Pure.

static var _warned := false


static func bounds(repo: DataRepository) -> Dictionary:
	var info: Dictionary = repo.map_info
	if not info.has("lat_n") and not _warned:
		_warned = true
		push_warning("map_info.csv has no lat_n / lat_s / lon_w / lon_e: the graticule spans the globe (re-import, tools/NEW_MAP.md)")
	return {"lat_n": float(info.get("lat_n", "90")), "lat_s": float(info.get("lat_s", "-90")),
		"lon_w": float(info.get("lon_w", "-180")), "lon_e": float(info.get("lon_e", "180")),
		"w": float(info.get("width", "1")), "h": float(info.get("height", "1"))}


static func px_per_deg(repo: DataRepository) -> Vector2:
	var b := bounds(repo)
	return Vector2(float(b["w"]) / maxf(float(b["lon_e"]) - float(b["lon_w"]), 0.0001),
		float(b["h"]) / maxf(float(b["lat_n"]) - float(b["lat_s"]), 0.0001))


## (longitude, latitude) of a pack px.
static func lon_lat(repo: DataRepository, px: Vector2) -> Vector2:
	var b := bounds(repo)
	var k := px_per_deg(repo)
	return Vector2(float(b["lon_w"]) + px.x / k.x, float(b["lat_n"]) - px.y / k.y)


static func px_of(repo: DataRepository, lon: float, lat: float) -> Vector2:
	var b := bounds(repo)
	var k := px_per_deg(repo)
	return Vector2((lon - float(b["lon_w"])) * k.x, (float(b["lat_n"]) - lat) * k.y)


## The `deg`-degree cell holding `px`, counted from the map's north-west corner.
static func cell_of(repo: DataRepository, px: Vector2, deg: float) -> Vector2i:
	var s := px_per_deg(repo) * deg
	return Vector2i(floori(px.x / s.x), floori(px.y / s.y))


static func cell_rect(repo: DataRepository, cell: Vector2i, deg: float) -> Rect2:
	var s := px_per_deg(repo) * deg
	return Rect2(Vector2(cell) * s, s)


## Columns and rows of `deg` cells over the map; a part cell at an edge counts.
static func grid_size(repo: DataRepository, deg: float) -> Vector2i:
	var b := bounds(repo)
	var s := px_per_deg(repo) * deg
	return Vector2i(ceili(float(b["w"]) / s.x - 0.0001), ceili(float(b["h"]) / s.y - 0.0001))


## "24°N 51°E": whole degrees, a hemisphere letter each (0 is N and E).
static func format(ll: Vector2) -> String:
	var lat := roundi(ll.y)
	var lon := roundi(ll.x)
	return "%d°%s %d°%s" % [absi(lat), "S" if lat < 0 else "N", absi(lon), "W" if lon < 0 else "E"]
```

Note on `format`: `roundi(-12.5)` is −13 (round half away from zero), `roundi(-0.2)` is 0 → "0°N 0°E". Check the test's expectations against Godot's `roundi` and keep the test's hand values if they hold.

- [ ] **Step 4: The pack's rows** — append to `data/maps/beria/map_info.csv` (beria's export: `latT 180, latN 90, latS -90, lonT 360, lonW -180, lonE 180`):

```csv
lat_n,90
lat_s,-90
lon_w,-180
lon_e,180
```

In `tools/import_azgaar.gd`, after the `population_rate` line of the map_info block, add:

```gdscript
	# mapCoordinates (spec 2026-10-02-war-room-v2 §2.1): the latitudes and
	# longitudes the map's edges stand at — the WAR ROOM's graticule
	var coords: Dictionary = world.get("mapCoordinates", {})
	out += _csv_line(["lat_n", _num2(float(coords.get("latN", 90)))])
	out += _csv_line(["lat_s", _num2(float(coords.get("latS", -90)))])
	out += _csv_line(["lon_w", _num2(float(coords.get("lonW", -180)))])
	out += _csv_line(["lon_e", _num2(float(coords.get("lonE", 180)))])
```

(`world` is the parsed export, as `world["settings"]` above it.) In `tools/NEW_MAP.md`, where `map_info.csv` is described, add: "`lat_n` / `lat_s` / `lon_w` / `lon_e` come from the export's `mapCoordinates` (the WAR ROOM's graticule, `MapCoords`); an older import without them spans the globe and warns."

- [ ] **Step 5: Run** `$W/t.sh res://tests/engine/test_map_coords.gd` — Expected: PASS (after `--import` for the new class).

- [ ] **Step 6: Commit**

```bash
git add scripts/engine/map_coords.gd scripts/engine/map_coords.gd.uid tests/engine/test_map_coords.gd tests/engine/test_map_coords.gd.uid tools/import_azgaar.gd data/maps/beria/map_info.csv tools/NEW_MAP.md
git commit -m "feat(map): MapCoords — the pack's graticule from mapCoordinates, imported into map_info

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `WarSheets` cut by the graticule

**Files:**
- Modify: `scripts/engine/war_sheets.gd` (rewrite `series`, `sheet_of` stays, `grid_ref`, `neighbours`; drop `layout`/`_starts`/`roman`)
- Modify: `scripts/ui/war_room_screen.gd:209,247` (`numeral` → `id`), `scripts/war_room/war_room_wall.gd:31,64` (`numeral` → `id`), `scripts/war_room/war_room_material.gd:37` (grid)
- Modify: `data/balance.csv` (remove `war_sheet_w_km`, `war_sheet_h_km`, `war_sheet_overlap_km`, `war_grid_km`; add `war_sheet_deg`, `war_sheet_collar_km`, `war_grid_deg`), `tests/engine/test_war_room_data.gd` (key list)
- Test: `tests/engine/test_war_sheets.gd` (rewrite), `tests/engine/test_war_room.gd` (collar)

**Interfaces:**
- Consumes: Task 1's `MapCoords`.
- Produces: `WarSheets.series(repo) -> Array` of `{index: int, id: String, kingdom: String, name: String, cell: Rect2, rect: Rect2, col: int, row: int}` — `cell` the neat line (the graticule cell), `rect` the TABLE's extent (`cell` grown by the collar; every consumer that maps the table or decides what is on it reads `rect`, unchanged). `sheet_of(repo, px) -> int` (unchanged contract). `grid_ref(repo, sheet: Dictionary, px: Vector2) -> String` — `"D4 · c7 · 24°N 51°E"`. `neighbours(repo, index) -> Dictionary` (unchanged contract). `WarSheets.id_of(col: int, row: int) -> String`.

- [ ] **Step 1: Failing tests** — replace `tests/engine/test_war_sheets.gd` with:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The WAR ROOM's series cut by the pack's graticule (spec 2026-10-02-war-room-v2
## §2.2): a sheet per war_sheet_deg cell with land, id "D4", a neat line and a
## collar, places written "D4 · c7 · 24°N 51°E".

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	WarSheets.forget()


func test_every_sheet_is_a_graticule_cell_grown_by_the_collar() -> void:
	var deg := repo.bal("war_sheet_deg")
	var collar := repo.bal("war_sheet_collar_km") * WarSheets.px_per_unit(repo)
	var all := WarSheets.series(repo)
	assert_gt(all.size(), 0)
	for s: Dictionary in all:
		var cell: Rect2 = s["cell"]
		assert_eq(cell, MapCoords.cell_rect(repo, Vector2i(int(s["col"]), int(s["row"])), deg))
		assert_eq(s["rect"], cell.grow(collar))
		assert_eq(String(s["id"]), WarSheets.id_of(int(s["col"]), int(s["row"])))


func test_ids_are_column_letters_and_row_numbers_from_the_north_west() -> void:
	assert_eq(WarSheets.id_of(0, 0), "A1")
	assert_eq(WarSheets.id_of(3, 3), "D4")
	assert_eq(WarSheets.id_of(17, 8), "R9")


func test_only_cells_with_land_are_sheets_and_every_land_cell_is_on_one() -> void:
	var all := WarSheets.series(repo)
	var ids: Dictionary = {}
	for s: Dictionary in all:
		ids[s["id"]] = true
	assert_eq(ids.size(), all.size(), "ids are unique")
	for id: int in repo.cells:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell) or (cell["vertex_ids"] as PackedInt32Array).size() < 3:
			continue
		var at := MapTerrain.cell_center(repo, cell)
		var si := WarSheets.sheet_of(repo, at)
		assert_gte(si, 0, "land cell %d has a sheet" % id)
		assert_true((all[si]["rect"] as Rect2).has_point(at), "land cell %d lies on the table of its sheet" % id)


func test_a_point_belongs_to_the_cell_it_lies_in_not_a_neighbours_collar() -> void:
	var all := WarSheets.series(repo)
	for s: Dictionary in all:
		var c: Rect2 = s["cell"]
		assert_eq(WarSheets.sheet_of(repo, c.position + Vector2(1, 1)), int(s["index"]), String(s["id"]))


func test_the_place_names_sheet_square_and_degrees() -> void:
	var s: Dictionary = WarSheets.series(repo)[0]
	var c: Rect2 = s["cell"]
	var g := MapCoords.px_per_deg(repo) * repo.bal("war_grid_deg")
	var at := c.position + Vector2(g.x * 2.5, g.y * 6.5)   # the third column, the seventh row
	var ll := MapCoords.lon_lat(repo, at)
	assert_eq(WarSheets.grid_ref(repo, s, at), "%s · c7 · %s" % [s["id"], MapCoords.format(ll)])


func test_neighbours_are_the_grid_cells_beside_it() -> void:
	var cells := {Vector2i(1, 1): 0, Vector2i(2, 1): 1, Vector2i(1, 0): 2}
	assert_eq(WarSheets.grid_neighbours(cells, Vector2i(1, 1)), {"e": 1, "n": 2})
```

In `tests/engine/test_war_room.gd` add (it already builds `repo`/`state` in `before_each`; read its fixture first):

```gdscript
func test_a_regiment_in_a_sheets_collar_is_on_that_sheet_and_off_no_other_twice() -> void:
	var all := WarSheets.series(repo)
	var s: Dictionary = all[0]
	var collar_pt: Vector2 = (s["cell"] as Rect2).position - Vector2(1, 1) * repo.bal("war_sheet_collar_km") * 0.5 * WarSheets.px_per_unit(repo)
	var reg: Dictionary = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0]
	var m := ArmySystem.pack_to_metres(repo, collar_pt)
	state.regiments[String(reg["regiment_code"])]["x_m"] = m.x
	state.regiments[String(reg["regiment_code"])]["y_m"] = m.y
	var on: Array = WarRoom.on_sheet(repo, state, 0).map(func(p: Dictionary) -> String: return String(p["code"]))
	assert_true(String(reg["regiment_code"]) in on, "drawn on the sheet whose collar holds it")
	var listed := 0
	for i in all.size():
		for p: Dictionary in WarRoom.off_sheet(repo, state, i):
			if String(p["code"]) == String(reg["regiment_code"]) and int(p["sheet"]) == i:
				listed += 1
	assert_eq(listed, 0, "never listed as off its own home sheet")
```

(If `ArmySystem.position_of` reads other keys than `x_m`/`y_m`, read it first and set what it reads. If the point falls off the map for sheet 0, pick the first sheet whose collar point is inside the map's rect.)


- [ ] **Step 2: Run** `$W/t.sh res://tests/engine/test_war_sheets.gd res://tests/engine/test_war_room.gd` — Expected: FAIL (`id_of`, `cell` missing).

- [ ] **Step 3: Rewrite the series** in `scripts/engine/war_sheets.gd` — replace the header comment, `layout`, `_starts`, `series`, `roman` and `grid_ref` (keep `forget`, `px_per_unit`, `_land_centres`, `sheet_of`, `_rect_gap`, `neighbours`, `grid_neighbours`):

```gdscript
## The WAR ROOM's map series (owner 2026-10-01; v2 2026-10-02, spec
## 2026-10-02-war-room-v2 §2.2): the pack cut by its own graticule
## (MapCoords) into war_sheet_deg cells, a sheet for every cell with land,
## named "D4" — the column letter and row number from the north-west — and
## after the kingdom with the most land on it by the STARTING border. A
## sheet's `cell` is its neat line; its `rect`, what the table shows, is the
## cell grown by a war_sheet_collar_km collar of the neighbouring ground. A
## place is written "D4 · c7 · 24°N 51°E". Generated from the pack alone; no
## pack is named. Pure and cached per repository.


static func id_of(col: int, row: int) -> String:
	return "%s%d" % [char(65 + col), row + 1]


static func series(repo: DataRepository) -> Array:
	var key := repo.get_instance_id()
	if _cache.has(key):
		return _cache[key]
	var deg := repo.bal("war_sheet_deg")
	var collar := repo.bal("war_sheet_collar_km") * px_per_unit(repo)
	var tallies: Dictionary = {}   # Vector2i cell -> {kingdom: count}
	for c: Dictionary in _land_centres(repo):
		var at := MapCoords.cell_of(repo, c["at"], deg)
		if not tallies.has(at):
			tallies[at] = {}
		var t: Dictionary = tallies[at]
		t[c["kingdom"]] = int(t.get(c["kingdom"], 0)) + 1
	var keys: Array = tallies.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.y < b.y or (a.y == b.y and a.x < b.x))
	var out: Array = []
	for at: Vector2i in keys:
		var tally: Dictionary = tallies[at]
		var best := ""
		for kd: String in tally:
			if best == "" or int(tally[kd]) > int(tally[best]) or (int(tally[kd]) == int(tally[best]) and kd < best):
				best = kd
		var cell := MapCoords.cell_rect(repo, at, deg)
		out.append({"index": out.size(), "id": id_of(at.x, at.y), "kingdom": best,
			"name": String((repo.kingdoms.get(best, {}) as Dictionary).get("label", best)),
			"cell": cell, "rect": cell.grow(collar), "col": at.x, "row": at.y})
	_cache[key] = out
	return out


## "D4 · c7 · 24°N 51°E": the sheet's id, the war_grid_deg square inside its
## neat line (a lower-case column letter from the west, a row number from the
## north) and the place's own whole degrees.
static func grid_ref(repo: DataRepository, sheet: Dictionary, px: Vector2) -> String:
	var c: Rect2 = sheet.get("cell", sheet["rect"])
	var g := MapCoords.px_per_deg(repo) * repo.bal("war_grid_deg")
	var col := clampi(floori((px.x - c.position.x) / g.x), 0, 25)
	var row := maxi(floori((px.y - c.position.y) / g.y), 0) + 1
	return "%s · %s%d · %s" % [sheet["id"], char(97 + col), row, MapCoords.format(MapCoords.lon_lat(repo, px))]
```

`sheet_of` stays as it is (a point in two sheets' `rect`s — a collar — goes to the nearer centre, which for equal cells is the cell it lies in). Update the doc of `sheet_of` to say "rect" holds the collar.

- [ ] **Step 4: Balance** — in `data/balance.csv` delete `war_sheet_w_km`, `war_sheet_h_km`, `war_sheet_overlap_km`, `war_grid_km`; add:

```csv
war_sheet_deg,20,"WAR ROOM v2 B (owner 2026-10-02, spec §2.2, ruling 6): a sheet's side in degrees of the pack's own graticule (MapCoords); every whole-degree cell is ~1.376:1 on beria, the table's 1.4:1 — 20 is 142 x 103 km, 18 x 9 cells"
war_sheet_collar_km,12,"WAR ROOM v2 B (spec §2.2): the faint collar of neighbouring ground beyond a sheet's neat line, in the pack's measure; a march over the edge stays in view (the old overlap's job)"
war_grid_deg,2,"WAR ROOM v2 B (spec §2.2): the lettered grid inside a sheet, degrees a square (~14 x 10 km); places read D4 · c7"
```

Update `tests/engine/test_war_room_data.gd`'s list: drop the four, add the three.

- [ ] **Step 5: Consumers** —
  - `scripts/ui/war_room_screen.gd`: `%Title.text = "Sheet %s · %s" % [s["id"], s["name"]]`; the margin row `"%s → %s" % [reg.get("label", p["code"]), series[to]["id"]]`.
  - `scripts/war_room/war_room_wall.gd`: the arrow label `series[to]["id"]` (the chart's numerals are Task 5's).
  - `scripts/war_room/war_room_material.gd` `bind`: replace the two `grid` lines with
    ```gdscript
    	var g := MapCoords.px_per_deg(repo) * repo.bal("war_grid_deg")
    	mat.set_shader_parameter("grid_cells", sheet_rect.size / g)
    	mat.set_shader_parameter("grid_phase", Vector2(fposmod(sheet_rect.position.x, g.x), fposmod(sheet_rect.position.y, g.y)) / g)
    ```
    and in `scenes/war_room/war_table.gdshader` add `uniform vec2 grid_phase = vec2(0.0);` and change `vec2 g = UV * grid_cells;` to `vec2 g = UV * grid_cells + grid_phase;` — the grid stays on whole degrees whatever the collar.
  - `grep -rn '"numeral"' scripts tests` must return nothing when done: change each test reading `["numeral"]` to `["id"]` (`tests/war_room/test_war_room_view.gd:144`).

- [ ] **Step 6: Run** `$W/t.sh res://tests/engine res://tests/war_room res://tests/ui/test_war_room_screen.gd res://tests/ui/test_war_margin_key.gd`. Expected: the new tests PASS. Tests that assumed the old series may fail: `test_war_room_view.gd`'s chart-numeral test (Task 5 replaces it — mark it `pending("graticule chart: Task 5")` for now, ledger the ruling), `test_war_pieces.gd` / `test_war_room_screen.gd` that pick "another sheet" by index (they still work: any index). Fix any other by reading what it asserts; never weaken an assertion about behaviour that should hold.

- [ ] **Step 7: Commit**

```bash
git add -A scripts tests data
git commit -m "feat(war-room): sheets are graticule cells (war_sheet_deg) with a neat line and a collar, ids D4, places D4 · c7 · 24°N 51°E

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `WarBake` — the build's own heights and woods

**Files:**
- Create: `scripts/war_room/war_bake.gd`
- Modify: `scripts/war_room/war_room_view.gd` (`bind`, `lay_sheet`), `scripts/war_room/war_room_table.gd` (a `clamp_sea` helper)
- Modify: `data/balance.csv` (`war_relief_grid` 384, `war_relief_exaggeration` 3, `war_contour_m` 100)
- Test: `tests/war_room/test_war_bake.gd`

**Interfaces:**
- Produces: `WarBake` (RefCounted): `static func open(dir: String) -> WarBake` (null without `world.json` and `height.r32`); `static func of(repo: DataRepository) -> WarBake` (opens `repo.map3d_dir() + "/bake"`, cached per map id); `func heights(rect: Rect2, nx: int, nz: int) -> PackedFloat32Array` — RAW metres above the sea line (`height − sea_y`, negative at sea) on an nx × nz grid over the pack rect, row-major z outer, the rect clamped to the bake; `func woods(rect: Rect2, step_px: float) -> Array` of `{at: Vector2 (pack px), cover: float, conifer: float}` where `cover > 0`. `WarRoomTable.clamp_sea(raw: PackedFloat32Array) -> PackedFloat32Array`.

- [ ] **Step 1: Failing tests** — create `tests/war_room/test_war_bake.gd` (it writes a tiny fake bake under the run dir):

```gdscript
extends GutTest
const RunDir := preload("res://tests/run_dir.gd")
## The build's own heightmap and woods, read by rows (spec 2026-10-02-war-room-v2
## §2.4, plan B's refinement): the heights Terrain3D was built from.

var dir := ""


## A 16 x 8 padded bake whose pack frame starts at vertex column 2: height =
## column * 10 + row, sea_y 5, 20 m vertices, 50 m per pack px (2.5 vertices a px).
func before_each() -> void:
	dir = RunDir.path("war_bake")
	DirAccess.make_dir_recursive_absolute(dir)
	var world := {"m_per_px": 50.0, "vertex_m": 20.0, "vertices": [10, 8], "padded": [16, 8],
		"import_corner": [-40.0, 0.0], "pack_origin": [0.0, 0.0], "sea_y": 5.0}
	var f := FileAccess.open(dir + "/world.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(world))
	f.close()
	var h := FileAccess.open(dir + "/height.r32", FileAccess.WRITE)
	for row in 8:
		for col in 16:
			h.store_float(float(col * 10 + row))
	h.close()


func test_a_pack_point_reads_its_vertex_less_the_sea_line() -> void:
	var b := WarBake.open(dir)
	assert_not_null(b)
	var g := b.heights(Rect2(0, 0, 2, 0.8), 2, 2)   # pack px (0,0) .. (2,0.8)
	# (0,0): vertex col 2, row 0 -> 20 - 5; (2,0): col 2 + 5 = 7 -> 70 - 5
	assert_almost_eq(g[0], 15.0, 0.001)
	assert_almost_eq(g[1], 65.0, 0.001)
	# (0, 0.8): row 0.8 * 2.5 = 2 -> 22 - 5
	assert_almost_eq(g[2], 17.0, 0.001)


func test_a_rect_off_the_bake_is_held_to_its_edge() -> void:
	var g := WarBake.open(dir).heights(Rect2(-10, -10, 100, 100), 3, 3)
	for v in g:
		assert_true(v >= 15.0 - 0.001 and v <= 15.0 + 70.0 + 7.0 + 0.001, "read inside the file: %f" % v)


func test_no_bake_no_reader() -> void:
	assert_null(WarBake.open(dir + "/nothing"))
```

(Use `tests/run_dir.gd`'s actual API — read it first; memory: user-dir-shared-across-worktrees — tests write under it.)

- [ ] **Step 2: Run** `$W/t.sh res://tests/war_room/test_war_bake.gd` — Expected: FAIL (`WarBake` missing).

- [ ] **Step 3: Implement** `scripts/war_room/war_bake.gd`:

```gdscript
class_name WarBake
extends RefCounted
## The 3D build's own bake for the WAR ROOM's table (spec 2026-10-02-war-room-v2
## §2.4; plan B: the heights Terrain3D was built from, read here directly so the
## room needs no 3D map loaded and runs headless): bake/height.r32 — float32
## metres, row-major over the PADDED grid of `vertex_m` vertices — read only
## the rows a sheet needs, and bake/woods.png — R the canopy's share, G the
## conifers', one texel per two vertices from the pack's corner. Pure reads;
## nothing is written. Null when the bake is not built (a fresh clone).

static var _opened: Dictionary = {}   # map id -> WarBake (or null)

var _dir := ""
var _vm := 20.0
var _m_per_px := 50.0
var _sea_y := 0.0
var _vw := 0
var _vh := 0
var _fw := 0
var _fh := 0
var _px0 := 0
var _pz0 := 0
var _woods: Image


static func open(dir: String) -> WarBake:
	var path := dir + "/world.json"
	if not FileAccess.file_exists(path) or not FileAccess.file_exists(dir + "/height.r32"):
		return null
	var world: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not world is Dictionary:
		return null
	var b := WarBake.new()
	b._dir = dir
	b._vm = float(world["vertex_m"])
	b._m_per_px = float(world["m_per_px"])
	b._sea_y = float(world["sea_y"])
	b._vw = int(world["vertices"][0])
	b._vh = int(world["vertices"][1])
	b._fw = int(world["padded"][0])
	b._fh = int(world["padded"][1])
	b._px0 = roundi((float(world["pack_origin"][0]) - float(world["import_corner"][0])) / b._vm)
	b._pz0 = roundi((float(world["pack_origin"][1]) - float(world["import_corner"][1])) / b._vm)
	return b


static func of(repo: DataRepository) -> WarBake:
	if not _opened.has(repo.map_id):
		_opened[repo.map_id] = open(repo.map3d_dir() + "/bake")
	return _opened[repo.map_id]


static func forget() -> void:
	_opened.clear()


## Vertex coordinates (padded grid) of a pack px.
func _vertex(px: Vector2) -> Vector2:
	var k := _m_per_px / _vm
	return Vector2(float(_px0) + px.x * k, float(_pz0) + px.y * k)


func heights(rect: Rect2, nx: int, nz: int) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(nx * nz)
	var a := _vertex(rect.position)
	var b := _vertex(rect.end)
	var lo_x := clampi(floori(minf(a.x, b.x)), 0, _fw - 1)
	var hi_x := clampi(ceili(maxf(a.x, b.x)) + 1, 0, _fw - 1)
	var lo_z := clampi(floori(minf(a.y, b.y)), 0, _fh - 1)
	var hi_z := clampi(ceili(maxf(a.y, b.y)) + 1, 0, _fh - 1)
	var cols := hi_x - lo_x + 1
	var rows := hi_z - lo_z + 1
	var f := FileAccess.open(_dir + "/height.r32", FileAccess.READ)
	if f == null:
		return out
	var block := PackedFloat32Array()
	block.resize(cols * rows)
	for r in rows:
		f.seek(((lo_z + r) * _fw + lo_x) * 4)
		var bytes := f.get_buffer(cols * 4)
		var row := bytes.to_float32_array()
		for c in mini(row.size(), cols):
			block[r * cols + c] = row[c]
	f.close()
	for j in nz:
		for i in nx:
			var px := rect.position + rect.size * Vector2(float(i) / float(maxi(nx - 1, 1)), float(j) / float(maxi(nz - 1, 1)))
			var v := _vertex(px)
			var u := clampf(v.x - float(lo_x), 0.0, float(cols - 1))
			var w := clampf(v.y - float(lo_z), 0.0, float(rows - 1))
			var i0 := mini(int(u), maxi(cols - 2, 0))
			var j0 := mini(int(w), maxi(rows - 2, 0))
			var i1 := mini(i0 + 1, cols - 1)
			var j1 := mini(j0 + 1, rows - 1)
			var fu := u - float(i0)
			var fw := w - float(j0)
			var top := lerpf(block[j0 * cols + i0], block[j0 * cols + i1], fu)
			var bot := lerpf(block[j1 * cols + i0], block[j1 * cols + i1], fu)
			out[j * nx + i] = lerpf(top, bot, fw) - _sea_y
	return out


## The woods over a pack rect, every `step_px` pack px: where the canopy is.
func woods(rect: Rect2, step_px: float) -> Array:
	var out: Array = []
	if _woods == null:
		var path := _dir + "/woods.png"
		if not FileAccess.file_exists(path):
			return out
		_woods = Image.load_from_file(ProjectSettings.globalize_path(path))
		if _woods == null:
			return out
	var k := _m_per_px / (_vm * 2.0)   # woods texels per pack px
	var y := rect.position.y
	while y < rect.end.y:
		var x := rect.position.x
		while x < rect.end.x:
			var tx := int(x * k)
			var ty := int(y * k)
			if tx >= 0 and ty >= 0 and tx < _woods.get_width() and ty < _woods.get_height():
				var c := _woods.get_pixel(tx, ty)
				if c.r > 0.0:
					out.append({"at": Vector2(x, y), "cover": c.r, "conifer": c.g})
			x += step_px
		y += step_px
	return out
```

Add to `scripts/war_room/war_room_table.gd`:

```gdscript
## Raw metres held at the sea line (the relief and the contours stand on land).
static func clamp_sea(raw: PackedFloat32Array) -> PackedFloat32Array:
	var out := raw.duplicate()
	for i in out.size():
		out[i] = maxf(out[i], 0.0)
	return out
```

- [ ] **Step 4: The view lays the bake's relief** — in `scripts/war_room/war_room_view.gd` `lay_sheet`, replace the two lines that set `_heights` and `raw` with:

```gdscript
	var bake := WarBake.of(_repo)
	var raw := bake.heights(_rect, _nx, _nz) if bake != null \
		else (WarRoomTable.raw_heights(_repo, _relief, _rect, _nx, _nz) if _relief != null else WarRoomTable.flat(_nx, _nz))
	_heights = WarRoomTable.clamp_sea(raw)
```

(keep the order: `_y_scale` before `raw` is fine; `shore` reads `raw`). Add `WarBake.forget()` next to `WarSheets.forget()` in `DataRepository` (`scripts/engine/data_repository.gd:846`) — a pack reload forgets the reader. Since `scripts/engine/` must not depend on `scripts/war_room/`? It already calls `WarSheets.forget()` (an engine class); `WarBake` is in `scripts/war_room/` — instead call `WarBake.forget()` from `WarRoomView.bind()` when the repository's map id differs from the cached one (`_opened` is keyed by map id already, so a different pack reads its own; no change to DataRepository is needed). Ledger this.

- [ ] **Step 5: Balance retune** — set `war_relief_grid` 384 (notes: "v2 B: the 142 km sheet at 2.5 bake vertices a pack px — 384 is ~370 m a vertex"), `war_relief_exaggeration` 3 (notes: "v2 B: at 4.7x the scale, 12 stood a 2.4 km peak 0.28 m over the table; 3 keeps the old height (bracketed in Task 10)"), `war_contour_m` 100 (notes: "v2 B: a finer interval for the finer scale").

- [ ] **Step 6: Run** `$W/t.sh res://tests/war_room res://tests/engine/test_war_room_data.gd` — Expected: PASS. The table tests (`test_war_room_table.gd`) still test the relief path; the view tests lay sheets through the bake in a worktree whose `assets/3D/terrain/beria` link exists (Task 0) — and through the relief where it does not.

- [ ] **Step 7: Commit**

```bash
git add -A scripts tests data
git commit -m "feat(war-room): the table's relief from the build's own heightmap (WarBake), finer grid and contours

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The neat line and the collar on the table

**Files:**
- Modify: `scenes/war_room/war_table.gdshader`, `scripts/war_room/war_room_material.gd`, `data/balance.csv`
- Test: `tests/war_room/test_war_room_view.gd`

**Interfaces:**
- Consumes: Task 2's sheet `cell` / `rect`.
- Produces: shader uniforms `neat_uv` (vec4: x0, y0, x1, y1 of the cell in the table's UV), `collar_ink` (float), `collar_shade` (float), `neat_px` (float), `intel_tex` (sampler2D, Task 9 fills it). `WarRoomMaterial.bind(mat, repo, sheet: Dictionary, table_w, depth)` — takes the SHEET (its `cell` and `rect`), not a rect.

- [ ] **Step 1: Failing test** — append to `tests/war_room/test_war_room_view.gd`:

```gdscript
func test_the_table_knows_its_neat_line() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var mat := (view.get_node("%Table") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	var s: Dictionary = WarSheets.series(repo)[0]
	var r: Rect2 = s["rect"]
	var c: Rect2 = s["cell"]
	var want := Vector4((c.position.x - r.position.x) / r.size.x, (c.position.y - r.position.y) / r.size.y,
		(c.end.x - r.position.x) / r.size.x, (c.end.y - r.position.y) / r.size.y)
	var got: Vector4 = mat.get_shader_parameter("neat_uv")
	assert_almost_eq(got.x, want.x, 0.0001)
	assert_almost_eq(got.w, want.w, 0.0001)
	assert_almost_eq(float(mat.get_shader_parameter("collar_ink")), repo.bal("war_collar_ink"), 0.0001)
```

- [ ] **Step 2: Run** it — Expected: FAIL (`neat_uv` null).

- [ ] **Step 3: Implement** — `WarRoomMaterial.bind` signature becomes `bind(mat: ShaderMaterial, repo: DataRepository, sheet: Dictionary, table_w: float, depth: float)`; inside, `var sheet_rect: Rect2 = sheet["rect"]` and add:

```gdscript
	var c: Rect2 = sheet.get("cell", sheet_rect)
	mat.set_shader_parameter("neat_uv", Vector4((c.position.x - sheet_rect.position.x) / sheet_rect.size.x,
		(c.position.y - sheet_rect.position.y) / sheet_rect.size.y,
		(c.end.x - sheet_rect.position.x) / sheet_rect.size.x, (c.end.y - sheet_rect.position.y) / sheet_rect.size.y))
```

Add to `SHADER_KEYS`: `"collar_ink": "war_collar_ink", "collar_shade": "war_collar_shade", "neat_px": "war_neat_px", "neat_gap_px": "war_neat_gap_px"`. Update the caller in `war_room_view.gd` (`WarRoomMaterial.bind(mat, _repo, all[index], _table_w, _depth)`) and any test calling `bind`.

In `scenes/war_room/war_table.gdshader` add the uniforms

```glsl
uniform vec4 neat_uv = vec4(0.0, 0.0, 1.0, 1.0); // the sheet's neat line in the table's UV
uniform float collar_ink = 0.35;   // ink strength beyond the neat line
uniform float collar_shade = 0.12; // the collar's paper a touch darker
uniform float neat_px = 1.6;       // the neat line's width, screen px
uniform float neat_gap_px = 4.0;   // the gap to its inner hairline
uniform sampler2D intel_tex : filter_linear_mipmap_anisotropic, hint_default_transparent;
```

and in `fragment()`, after `col` is first set and before the contours:

```glsl
	// beyond the neat line: the collar — the neighbouring ground, faint (spec §2.2)
	vec2 inside2 = step(neat_uv.xy, UV) * step(UV, neat_uv.zw);
	float inside = inside2.x * inside2.y;
	float collar = 1.0 - inside;
	col *= 1.0 - collar * collar_shade;
```

then multiply the contour weight and the inked alpha by `mix(1.0, collar_ink, collar)`:

```glsl
	float contour = max(c * contour_alpha, idx * contour_index_alpha) * land * mix(1.0, collar_ink, collar);
	...
	vec4 inked = texture(ink_tex, vec2(UV.x, UV.y * tex_aspect));
	inked.a *= mix(1.0, collar_ink, collar);
	inked.rgb *= mix(1.0, collar_ink, collar);   // premultiplied: scale both
```

and after the ink, the neat line — a heavy rule on the line and a hairline `neat_gap_px` inside it, measured in screen px with `fwidth` OUTSIDE any branch:

```glsl
	vec2 nu = (UV - neat_uv.xy) / max(neat_uv.zw - neat_uv.xy, vec2(1e-5));   // 0..1 across the cell
	vec2 fw = max(fwidth(nu), vec2(1e-6));
	vec2 d0 = min(abs(nu), abs(nu - 1.0)) / fw;                   // px from the line, each axis
	vec2 inb = step(vec2(0.0), nu) * step(nu, vec2(1.0));         // within the cell's span on the other axis
	float rule = max((1.0 - clamp(d0.x - neat_px * 0.5, 0.0, 1.0)) * inb.y, (1.0 - clamp(d0.y - neat_px * 0.5, 0.0, 1.0)) * inb.x);
	vec2 d1 = abs(d0 - neat_gap_px);
	float hair = max((1.0 - clamp(d1.x - 0.4, 0.0, 1.0)) * inb.y, (1.0 - clamp(d1.y - 0.4, 0.0, 1.0)) * inb.x) * inside;
	col = mix(col, ink.rgb, max(rule, hair * 0.6));
	vec4 intel = texture(intel_tex, vec2(UV.x, UV.y * tex_aspect));
	vec3 intel_straight = srgb_to_linear(intel.rgb / max(intel.a, 1e-4));
	col = col * (1.0 - intel.a) + intel_straight * intel.a;
```

Balance rows:

```csv
war_collar_ink,0.35,"WAR ROOM v2 B (spec §2.2): ink and contours beyond the neat line, as a share of their strength inside"
war_collar_shade,0.12,"WAR ROOM v2 B (spec §2.2): the collar's paper darkened by this share"
war_neat_px,1.6,"WAR ROOM v2 B (spec §2.2): the neat line's rule, screen px"
war_neat_gap_px,4,"WAR ROOM v2 B (spec §2.2): the hairline inside the neat line, screen px from it"
```

and add the four to `test_war_room_data.gd`.

- [ ] **Step 4: Run** `$W/t.sh res://tests/war_room res://tests/engine/test_war_room_data.gd` — PASS.

- [ ] **Step 5: Commit** `feat(war-room): the sheet's neat line and its faint collar; the intel layer's sampler`.

---

### Task 5: The graticule index chart

**Files:**
- Modify: `scripts/war_room/war_index_chart.gd`, `scripts/war_room/war_room_wall.gd` (`build_chart`, `pick_chart`, a `chart_uv`), `data/balance.csv`
- Test: `tests/war_room/test_war_index_chart.gd`, `tests/war_room/test_war_room_view.gd` (replace the numeral test)

**Interfaces:**
- Produces: `WarIndexChart.image(repo, px) -> Image` (land dots, sea cells washed, the graticule in faint ink, land cells' frames in rubric); `WarIndexChart.sheet_at_uv(repo, uv) -> int` (the sheet whose CELL holds the point, −1 on a sea cell or off the map); `WarIndexChart.uv_of_cell(repo, sheet: Dictionary) -> Rect2` (the sheet's cell in chart UV); `WarRoomWall.chart_uv(chart, camera, screen_px) -> Vector2` ((−1,−1) off the chart); `WarRoomWall.chart_point(chart, uv: Vector2) -> Vector3` (a chart UV as a world point on its face). The chart's Label3D children are now the column letters along its north edge and the row numbers down its west edge (meta `axis` "col"/"row", `n` the index).

- [ ] **Step 1: Failing tests** — in `tests/war_room/test_war_index_chart.gd` replace `test_a_uv_on_a_sheet_picks_it` with:

```gdscript
func test_a_uv_in_a_land_cell_picks_its_sheet_and_a_sea_cell_nothing() -> void:
	var w := float(repo.map_info["width"])
	var h := float(repo.map_info["height"])
	for s: Dictionary in WarSheets.series(repo):
		var c := (s["cell"] as Rect2).get_center() / Vector2(w, h)
		assert_eq(WarIndexChart.sheet_at_uv(repo, c), int(s["index"]), String(s["id"]))
	var g := MapCoords.grid_size(repo, repo.bal("war_sheet_deg"))
	var taken: Dictionary = {}
	for s: Dictionary in WarSheets.series(repo):
		taken[Vector2i(int(s["col"]), int(s["row"]))] = true
	for row in g.y:
		for col in g.x:
			if not taken.has(Vector2i(col, row)):
				var c := MapCoords.cell_rect(repo, Vector2i(col, row), repo.bal("war_sheet_deg")).get_center() / Vector2(w, h)
				if c.x < 1.0 and c.y < 1.0:
					assert_eq(WarIndexChart.sheet_at_uv(repo, c), -1, "sea cell %d,%d" % [col, row])
				return   # one sea cell is enough
	assert_eq(WarIndexChart.sheet_at_uv(repo, Vector2(-0.1, 0.5)), -1)


func test_uv_of_cell_is_the_cell_over_the_map() -> void:
	var s: Dictionary = WarSheets.series(repo)[0]
	var r := WarIndexChart.uv_of_cell(repo, s)
	var c: Rect2 = s["cell"]
	var size := Vector2(float(repo.map_info["width"]), float(repo.map_info["height"]))
	assert_eq(r, Rect2(c.position / size, c.size / size))
```

In `tests/war_room/test_war_room_view.gd` replace `test_every_numeral_on_the_wall_chart_is_in_the_opening_view_and_picks_its_sheet` with:

```gdscript
func test_the_chart_letters_its_columns_and_numbers_its_rows() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var g := MapCoords.grid_size(repo, repo.bal("war_sheet_deg"))
	var labels := view.get_node("%IndexChart").get_children()
	assert_eq(labels.size(), g.x + g.y)
	var cols := labels.filter(func(l: Node) -> bool: return String(l.get_meta("axis")) == "col")
	assert_eq((cols[0] as Label3D).text, "A")


func test_a_click_on_a_land_cell_of_the_chart_asks_for_its_sheet() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var cam: Camera3D = view.get_node("%Camera")
	var chart: MeshInstance3D = view.get_node("%IndexChart")
	for s: Dictionary in WarSheets.series(repo):
		var uv := WarIndexChart.uv_of_cell(repo, s).get_center()
		var p := WarRoomWall.chart_point(chart, uv)
		var at := cam.unproject_position(p) / view.window_scale()
		if not Rect2(Vector2.ZERO, view.size).has_point(at):
			continue
		assert_eq(WarRoomWall.pick_chart(chart, cam, repo, at * view.window_scale()), int(s["index"]), String(s["id"]))
```

- [ ] **Step 2: Run** — Expected: FAIL (`uv_of_cell`, `chart_point` missing; label counts).

- [ ] **Step 3: Implement**

`scripts/war_room/war_index_chart.gd` — replace `image` and `sheet_at_uv`, add `uv_of_cell`:

```gdscript
## The graticule index (owner 2026-10-02, spec 2026-10-02-war-room-v2 §2.3):
## the island as inked dots, every war_sheet_deg cell ruled faint, the sea's
## cells washed, the land's framed in rubric; a click on a land cell lays its
## sheet (after the marker is tossed onto it).
static func image(repo: DataRepository, px: int) -> Image:
	var w := float(repo.map_info.get("width", "1"))
	var h := float(repo.map_info.get("height", "1"))
	var ih := int(round(float(px) * h / w))
	var img := Image.create(px, ih, true, Image.FORMAT_RGBA8)
	var paper: Color = repo.war_palette["paper"]
	img.fill(paper)
	var k := float(px) / w
	var deg := repo.bal("war_sheet_deg")
	var g := MapCoords.grid_size(repo, deg)
	var sea := paper.darkened(repo.bal("war_chart_sea_shade"))
	var land_cells: Dictionary = {}
	for s: Dictionary in WarSheets.series(repo):
		land_cells[Vector2i(int(s["col"]), int(s["row"]))] = true
	for row in g.y:
		for col in g.x:
			if not land_cells.has(Vector2i(col, row)):
				var r := MapCoords.cell_rect(repo, Vector2i(col, row), deg)
				img.fill_rect(Rect2i(Vector2i(r.position * k), Vector2i(r.size * k) + Vector2i.ONE).intersection(Rect2i(0, 0, px, ih)), sea)
	var ink: Color = repo.war_palette["ink"]
	for id: int in repo.cells:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell) or (cell["vertex_ids"] as PackedInt32Array).size() < 3:
			continue
		var c := MapTerrain.cell_center(repo, cell) * k
		img.fill_rect(Rect2i(int(c.x), int(c.y), 2, 2), ink)
	var faint: Color = repo.war_palette["ink_faint"]
	for col in g.x + 1:
		var x := clampi(int(MapCoords.cell_rect(repo, Vector2i(col, 0), deg).position.x * k), 0, px - 1)
		img.fill_rect(Rect2i(x, 0, 1, ih), faint)
	for row in g.y + 1:
		var y := clampi(int(MapCoords.cell_rect(repo, Vector2i(0, row), deg).position.y * k), 0, ih - 1)
		img.fill_rect(Rect2i(0, y, px, 1), faint)
	var rubric: Color = repo.war_palette["rubric"]
	for s: Dictionary in WarSheets.series(repo):
		var r: Rect2 = s["cell"]
		var a := Vector2i(r.position * k)
		var b := (Vector2i(r.end * k) - Vector2i(1, 1)).min(Vector2i(px - 1, ih - 1))
		img.fill_rect(Rect2i(a.x, a.y, b.x - a.x, 1), rubric)
		img.fill_rect(Rect2i(a.x, b.y, b.x - a.x, 1), rubric)
		img.fill_rect(Rect2i(a.x, a.y, 1, b.y - a.y), rubric)
		img.fill_rect(Rect2i(b.x, a.y, 1, b.y - a.y), rubric)
	img.generate_mipmaps()
	return img


## The sheet whose cell holds a chart UV (0..1 across the map), -1 on a sea
## cell or off the map.
static func sheet_at_uv(repo: DataRepository, uv: Vector2) -> int:
	if uv.x < 0.0 or uv.y < 0.0 or uv.x >= 1.0 or uv.y >= 1.0:
		return -1
	var p := uv * Vector2(float(repo.map_info.get("width", "1")), float(repo.map_info.get("height", "1")))
	var at := MapCoords.cell_of(repo, p, repo.bal("war_sheet_deg"))
	for s: Dictionary in WarSheets.series(repo):
		if int(s["col"]) == at.x and int(s["row"]) == at.y:
			return int(s["index"])
	return -1


static func uv_of_cell(repo: DataRepository, sheet: Dictionary) -> Rect2:
	var size := Vector2(float(repo.map_info.get("width", "1")), float(repo.map_info.get("height", "1")))
	var c: Rect2 = sheet["cell"]
	return Rect2(c.position / size, c.size / size)
```

`scripts/war_room/war_room_wall.gd` — in `build_chart`, replace the per-sheet numeral loop with column letters along the north edge and row numbers down the west edge:

```gdscript
	var deg := repo.bal("war_sheet_deg")
	var g := MapCoords.grid_size(repo, deg)
	var lift := repo.bal("war_chart_numeral_lift_m")
	var margin := repo.bal("war_chart_axis_margin_m")
	for col in g.x:
		var cx := (MapCoords.cell_rect(repo, Vector2i(col, 0), deg).get_center().x / w - 0.5) * size.x
		var l := _label(char(65 + col), font, repo.war_palette["rubric"], Vector3(cx, size.y * 0.5 + margin, lift),
			int(repo.bal("war_chart_numeral_font_px")), repo.bal("war_chart_numeral_pixel_m"), false)
		l.set_meta("axis", "col")
		l.set_meta("n", col)
		chart.add_child(l)
	for row in g.y:
		var cy := (0.5 - MapCoords.cell_rect(repo, Vector2i(0, row), deg).get_center().y / h) * size.y
		var l := _label(str(row + 1), font, repo.war_palette["rubric"], Vector3(-size.x * 0.5 - margin, cy, lift),
			int(repo.bal("war_chart_numeral_font_px")), repo.bal("war_chart_numeral_pixel_m"), false)
		l.set_meta("axis", "row")
		l.set_meta("n", row)
		chart.add_child(l)
```

(Keep the existing `_label` call shape the old loop used — read it; the old numerals were Label3Ds lying on the chart, non-billboard.) Split `pick_chart` into `chart_uv` + the lookup, and add `chart_point`:

```gdscript
static func chart_uv(chart: MeshInstance3D, camera: Camera3D, screen_px: Vector2) -> Vector2:
	var inv := chart.global_transform.affine_inverse()
	var lo := inv * camera.project_ray_origin(screen_px)
	var ld := (inv.basis * camera.project_ray_normal(screen_px)).normalized()
	if absf(ld.z) < 0.00001:
		return Vector2(-1, -1)
	var t := -lo.z / ld.z
	if t < 0.0:
		return Vector2(-1, -1)
	var hit := lo + ld * t
	var size := (chart.mesh as QuadMesh).size
	return Vector2(hit.x / size.x + 0.5, 0.5 - hit.y / size.y)


static func pick_chart(chart: MeshInstance3D, camera: Camera3D, repo: DataRepository, screen_px: Vector2) -> int:
	var uv := chart_uv(chart, camera, screen_px)
	return -1 if uv.x < 0.0 else WarIndexChart.sheet_at_uv(repo, uv)


## A chart UV as a world point on the chart's face (the marker lands here).
static func chart_point(chart: MeshInstance3D, uv: Vector2) -> Vector3:
	var size := (chart.mesh as QuadMesh).size
	return chart.global_transform * Vector3((uv.x - 0.5) * size.x, (0.5 - uv.y) * size.y, 0.0)
```

Balance:

```csv
war_chart_sea_shade,0.08,"WAR ROOM v2 B (spec §2.3): a sea cell of the index chart washed this much darker than the paper; only land cells can be chosen"
war_chart_axis_margin_m,0.012,"WAR ROOM v2 B (spec §2.3): the chart's column letters and row numbers stand this far outside its edge, metres"
```

If the 18 columns' letters crowd at `war_chart_w_m` 0.8, raise `war_chart_w_m` (the north band of the oak top is ~0.3 m deep — keep the chart's height `war_chart_w_m × 929/2560` under it) and ledger the value.

- [ ] **Step 4: Run** `$W/t.sh res://tests/war_room res://tests/engine/test_war_room_data.gd` — PASS.

- [ ] **Step 5: Commit** `feat(war-room): the index chart is the graticule — land cells framed, sea washed, columns lettered and rows numbered`.

---

### Task 6: `WarToss` — the marker thrown onto the chart

**Files:**
- Create: `scripts/war_room/war_toss.gd`
- Modify: `scenes/war_room/war_room.tscn` (a `%Marker` stand-in), `scripts/war_room/war_room_view.gd` (toss on a chart pick), `scripts/war_room/war_room_rake.gd` (chart picks go to the toss), `data/balance.csv`
- Test: `tests/war_room/test_war_toss.gd`, `tests/war_room/test_war_room_view.gd`

**Interfaces:**
- Consumes: Task 5's `chart_uv`, `chart_point`, `WarIndexChart.uv_of_cell`, `sheet_at_uv`.
- Produces: `WarToss` (static): `plan(from: Vector3, to: Vector3, seed: int, rules: Dictionary) -> Dictionary` (`{from, to, apex, axis: Vector3, turns, yaw, fly_s, bounces: Array[{h, s}], settle_s, duration}`); `pose(plan: Dictionary, t: float) -> Transform3D`; `landing(rect_uv: Rect2, seed: int, margin: float) -> Vector2` (a point inside the cell, `margin` of its size in from each edge); `rules(repo) -> Dictionary` (the `war_toss_*` keys). `WarRoomView.toss_to(index: int) -> void`, `WarRoomView.tossing() -> bool`.

- [ ] **Step 1: Failing tests** — create `tests/war_room/test_war_toss.gd`:

```gdscript
extends GutTest
## The war marker tossed onto the index chart (spec 2026-10-02-war-room-v2 §2.3):
## an arc, a tumble, a bounce or two, and it stands upright where it landed.

var rules := {"apex_m": 0.2, "fly_s": 0.6, "turns_min": 1.0, "turns_max": 2.0, "bounces": 2,
	"bounce_ratio": 0.3, "settle_s": 0.2}


func test_it_starts_in_the_hand_and_ends_standing_on_its_point() -> void:
	var from := Vector3(0.0, 1.0, 1.0)
	var to := Vector3(0.3, 0.0, -0.5)
	var p := WarToss.plan(from, to, 7, rules)
	assert_almost_eq(WarToss.pose(p, 0.0).origin.distance_to(from), 0.0, 0.0001)
	var end := WarToss.pose(p, float(p["duration"]))
	assert_almost_eq(end.origin.distance_to(to), 0.0, 0.0001)
	assert_almost_eq(end.basis.y.normalized().dot(Vector3.UP), 1.0, 0.0001, "upright")
	assert_almost_eq(WarToss.pose(p, float(p["duration"]) + 5.0).origin.distance_to(to), 0.0, 0.0001, "held after")


func test_the_flight_is_an_arc_over_the_straight_line() -> void:
	var from := Vector3(0.0, 0.0, 1.0)
	var to := Vector3(0.0, 0.0, -1.0)
	var p := WarToss.plan(from, to, 3, rules)
	var mid := WarToss.pose(p, float(p["fly_s"]) * 0.5).origin
	assert_almost_eq(mid.y, 0.2, 0.0001, "the apex at the middle: 4 * apex * 0.5 * 0.5")


func test_it_bounces_lower_each_time() -> void:
	var p := WarToss.plan(Vector3.ZERO, Vector3(1, 0, 0), 5, rules)
	var b: Array = p["bounces"]
	assert_eq(b.size(), 2)
	assert_almost_eq(float(b[0]["h"]), 0.2 * 0.3, 0.0001)
	assert_almost_eq(float(b[1]["h"]), 0.2 * 0.09, 0.0001)


func test_the_same_seed_throws_the_same_and_another_differs() -> void:
	var a := WarToss.plan(Vector3.ZERO, Vector3(1, 0, 0), 11, rules)
	var b := WarToss.plan(Vector3.ZERO, Vector3(1, 0, 0), 11, rules)
	var c := WarToss.plan(Vector3.ZERO, Vector3(1, 0, 0), 12, rules)
	assert_eq(a["turns"], b["turns"])
	assert_ne([a["turns"], a["yaw"]], [c["turns"], c["yaw"]])


func test_the_landing_lies_inside_the_cell_off_its_edges() -> void:
	var r := Rect2(0.2, 0.3, 0.1, 0.05)
	for s in 30:
		var at := WarToss.landing(r, s, 0.2)
		assert_true(r.grow_individual(-0.02, -0.01, -0.02, -0.01).has_point(at), str(at))
```

Append to `tests/war_room/test_war_room_view.gd`:

```gdscript
func test_a_chart_pick_tosses_then_lays_and_a_second_pick_mid_toss_is_ignored() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	watch_signals(view)
	var other := 1 if WarSheets.series(repo).size() > 1 else 0
	view.toss_to(other)
	assert_true(view.tossing())
	view.toss_to(0)   # ignored while the marker flies
	assert_signal_not_emitted(view, "sheet_requested", "not laid before it lands")
	await wait_seconds(float(WarToss.plan(Vector3.ZERO, Vector3.ONE, 1, WarToss.rules(repo))["duration"]) + 0.3)
	assert_false(view.tossing())
	assert_signal_emit_count(view, "sheet_requested", 1)
	assert_signal_emitted_with_parameters(view, "sheet_requested", [other])
	var marker := view.get_node("%Marker") as Node3D
	var cell := WarIndexChart.uv_of_cell(repo, WarSheets.series(repo)[other])
	var uv := WarRoomWall.chart_uv(view.get_node("%IndexChart"), view.get_node("%Camera"),
		(view.get_node("%Camera") as Camera3D).unproject_position(marker.global_position))
	assert_true(cell.grow(0.001).has_point(uv), "the marker stands on the chosen cell")
```

- [ ] **Step 2: Run** — Expected: FAIL (`WarToss` missing).

- [ ] **Step 3: Implement** `scripts/war_room/war_toss.gd`:

```gdscript
class_name WarToss
extends RefCounted
## The war marker tossed onto the index chart (owner 2026-10-02: 随意的丢上去
## 一个代表战争的3D棋子; spec 2026-10-02-war-room-v2 §2.3), pure: thrown from
## the officer's side in a parabola, tumbling about a random axis, it lands,
## bounces lower each time (war_toss_bounce_ratio), and turns upright over the
## settle at a random yaw. Presentation only: its seed is the room's own, never
## GameState.rng, and nothing is saved.


static func rules(repo: DataRepository) -> Dictionary:
	return {"apex_m": repo.bal("war_toss_apex_m"), "fly_s": repo.bal("war_toss_fly_s"),
		"turns_min": repo.bal("war_toss_turns_min"), "turns_max": repo.bal("war_toss_turns_max"),
		"bounces": int(repo.bal("war_toss_bounces")), "bounce_ratio": repo.bal("war_toss_bounce_ratio"),
		"settle_s": repo.bal("war_toss_settle_s")}


static func plan(from: Vector3, to: Vector3, seed: int, r: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var axis := Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-0.3, 0.3), rng.randf_range(-1.0, 1.0)).normalized()
	if axis.length() < 0.5:
		axis = Vector3.RIGHT
	var bounces: Array = []
	var h := float(r["apex_m"])
	var s := float(r["fly_s"])
	for i in int(r["bounces"]):
		h *= float(r["bounce_ratio"])
		s *= sqrt(float(r["bounce_ratio"]))
		bounces.append({"h": h, "s": s})
	var total := float(r["fly_s"]) + float(r["settle_s"])
	for b: Dictionary in bounces:
		total += float(b["s"])
	return {"from": from, "to": to, "apex": float(r["apex_m"]), "axis": axis,
		"turns": rng.randf_range(float(r["turns_min"]), float(r["turns_max"])), "yaw": rng.randf_range(0.0, TAU),
		"fly_s": float(r["fly_s"]), "bounces": bounces, "settle_s": float(r["settle_s"]), "duration": total}


static func pose(p: Dictionary, t: float) -> Transform3D:
	var from: Vector3 = p["from"]
	var to: Vector3 = p["to"]
	var fly := float(p["fly_s"])
	var upright := Basis(Vector3.UP, float(p["yaw"]))
	if t <= fly:
		var u := clampf(t / maxf(fly, 0.0001), 0.0, 1.0)
		var at := from.lerp(to, u) + Vector3.UP * 4.0 * float(p["apex"]) * u * (1.0 - u)
		var spin := Basis(p["axis"] as Vector3, float(p["turns"]) * TAU * u)
		return Transform3D(spin * upright, at)
	var left := t - fly
	var tumbled := Basis(p["axis"] as Vector3, float(p["turns"]) * TAU)
	for b: Dictionary in p["bounces"]:
		var s := float(b["s"])
		if left <= s:
			var u := left / maxf(s, 0.0001)
			var at := to + Vector3.UP * 4.0 * float(b["h"]) * u * (1.0 - u)
			return Transform3D(tumbled.slerp(upright, 0.5).orthonormalized() * Basis.IDENTITY, at)
		left -= s
	var k := smoothstep(0.0, 1.0, clampf(left / maxf(float(p["settle_s"]), 0.0001), 0.0, 1.0))
	var q := tumbled.get_rotation_quaternion().slerp(upright.get_rotation_quaternion(), k)
	return Transform3D(Basis(q), to)


## A point in `rect_uv`, `margin` of its size in from every edge.
static func landing(rect_uv: Rect2, seed: int, margin: float) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var m := rect_uv.size * margin
	return rect_uv.position + m + Vector2(rng.randf(), rng.randf()) * (rect_uv.size - m * 2.0)
```

(The bounce pose's `slerp(upright, 0.5)` gives the tumbling marker a half-righted look on its hops; if `Basis.slerp` is not available in 4.7, use the quaternion slerp as the settle does.)

Balance:

```csv
war_toss_apex_m,0.18,"WAR ROOM v2 B (spec §2.3): the marker's arc, metres over the straight line at its middle"
war_toss_fly_s,0.55,"WAR ROOM v2 B (spec §2.3): seconds from the hand to the chart"
war_toss_turns_min,0.8,"WAR ROOM v2 B (spec §2.3): fewest tumbles in flight"
war_toss_turns_max,1.8,"WAR ROOM v2 B (spec §2.3): most tumbles in flight"
war_toss_bounces,2,"WAR ROOM v2 B (spec §2.3): hops after the landing"
war_toss_bounce_ratio,0.28,"WAR ROOM v2 B (spec §2.3): each hop this share of the one before (its time by the root)"
war_toss_settle_s,0.25,"WAR ROOM v2 B (spec §2.3): seconds to stand upright after the last hop"
war_toss_margin,0.2,"WAR ROOM v2 B (spec §2.3): the landing keeps this share of the cell's size in from its edges"
war_toss_hand_m,0.45,"WAR ROOM v2 B (spec §2.3): the toss starts this far from the chart toward the camera"
war_marker_h_m,0.026,"WAR ROOM v2 B (spec §2.3): the stand-in marker's height (D replaces it with the owner's pick)"
```

- [ ] **Step 4: The marker in the scene** — in `scenes/war_room/war_room.tscn` add a stand-in under `Viewport/Room` (a turned piece: a cylinder body and a wider base, the rubric colour), hidden until the first toss:

```
[sub_resource type="CylinderMesh" id="Marker_body"]
top_radius = 0.006
bottom_radius = 0.008
height = 0.02

[sub_resource type="CylinderMesh" id="Marker_base"]
top_radius = 0.01
bottom_radius = 0.011
height = 0.006

[sub_resource type="StandardMaterial3D" id="Mat_marker"]
albedo_color = Color(0.608, 0.173, 0.122, 1)
roughness = 0.55
```

```
[node name="Marker" type="Node3D" parent="Viewport/Room"]
unique_name_in_owner = true
visible = false

[node name="Body" type="MeshInstance3D" parent="Viewport/Room/Marker"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.016, 0)
mesh = SubResource("Marker_body")
material_override = SubResource("Mat_marker")

[node name="Base" type="MeshInstance3D" parent="Viewport/Room/Marker"]
transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0.003, 0)
mesh = SubResource("Marker_base")
material_override = SubResource("Mat_marker")
```

(Bump `load_steps` by 3.)

- [ ] **Step 5: The view tosses** — in `scripts/war_room/war_room_view.gd`:

```gdscript
@onready var _marker: Node3D = %Marker

var _toss: Dictionary = {}
var _toss_t := 0.0
var _toss_to := -1
var _toss_n := 0


func tossing() -> bool:
	return not _toss.is_empty()


## Toss the war marker onto sheet `index`'s cell of the index chart, then lay it
## (spec 2026-10-02-war-room-v2 §2.3). Ignored mid-toss or mid-roll.
func toss_to(index: int) -> void:
	if tossing() or rolling() or index < 0:
		return
	var all := WarSheets.series(_repo)
	_toss_n += 1
	var uv := WarToss.landing(WarIndexChart.uv_of_cell(_repo, all[index]), hash([index, _toss_n]), _repo.bal("war_toss_margin"))
	var to := WarRoomWall.chart_point(_chart, uv)
	var hand := to + (_camera.global_position - to).normalized() * _repo.bal("war_toss_hand_m")
	_toss = WarToss.plan(hand, to, hash([index, _toss_n, "toss"]), WarToss.rules(_repo))
	_toss_t = 0.0
	_toss_to = index
	_marker.visible = true
	_marker.global_transform = WarToss.pose(_toss, 0.0)


func _step_toss(delta: float) -> void:
	if not tossing():
		return
	_toss_t += delta
	_marker.global_transform = WarToss.pose(_toss, _toss_t)
	if _toss_t >= float(_toss["duration"]):
		var to := _toss_to
		_toss = {}
		sheet_requested.emit(to)
```

Call `_step_toss(delta)` first in `_process`. In `scripts/war_room/war_room_rake.gd` `on_left`, replace `var i := WarRoomPicks.sheet_target(...)` and its `if i >= 0: _view.sheet_requested.emit(i)` with two picks: an edge arrow lays at once, a chart cell is tossed:

```gdscript
	var arrow := WarRoomWall.pick_arrow(_arrows, _camera, mb.position, scale, _repo.bal("war_pick_px"))
	var chart := -1 if arrow >= 0 else WarRoomWall.pick_chart(_chart, _camera, _repo, mb.position * scale)
	...
	if arrow >= 0:
		_view.sheet_requested.emit(arrow)
	elif chart >= 0:
		_view.toss_to(chart)
	elif pennant != "":
```

(keep the rest of the chain). `WarRoomPicks.sheet_target` stays for its tests and the snapshot tool. At the first lay, put the marker on the laid sheet's cell without a toss (`_marker.visible = true`, upright at the cell's centre) so the chart always shows where the room is: in `lay_sheet`, if `not tossing()`, set `_marker.global_transform = Transform3D(Basis.IDENTITY, WarRoomWall.chart_point(_chart, WarIndexChart.uv_of_cell(_repo, all[index]).get_center()))` and show it (after the chart is built).

- [ ] **Step 6: Run** `$W/t.sh res://tests/war_room res://tests/engine/test_war_room_data.gd res://tests/ui/test_war_room_screen.gd` — PASS.

- [ ] **Step 7: Commit** `feat(war-room): a chart pick tosses the war marker onto the cell, then lays its sheet`.

---

### Task 7: More ink — hollows, woods, manors, walls and ports

**Files:**
- Modify: `scripts/war_room/war_sheet_ink.gd` (`strokes` gains keys), `scripts/war_room/war_ink_painter.gd` (draws them), `scripts/war_room/war_room_ink.gd` (`INK_PX` / `INK_RATIOS`), `scripts/war_room/war_room_view.gd` (hands the bake to the ink), `data/balance.csv`
- Test: `tests/war_room/test_war_sheet_ink.gd`

**Interfaces:**
- Consumes: Task 3's `WarBake.woods`, Task 2's sheet `cell`.
- Produces: `WarSheetInk.strokes(repo, state, sheet, tex_px, bake: WarBake = null) -> Dictionary` with new keys `"hollows"` (`[{at, metres, lod}]`), `"woods"` (`[{at, conifer}]` in texture px, one per tree glyph), `"manor_edges"` (`Array[PackedVector2Array]`, two points each), `"manors"` (`[{at, label}]`), and each `"towns"` entry gains `"walls": bool`, `"port": bool`.

- [ ] **Step 1: Failing tests** — append to `tests/war_room/test_war_sheet_ink.gd` (read its `before_each`: it lays `sheet` = series[0] and a `tex_px`):

```gdscript
func _richest_sheet() -> Dictionary:
	var best: Dictionary = {}
	var most := -1
	for s: Dictionary in WarSheets.series(repo):
		var n := 0
		for code: String in repo.burgs:
			var b: Dictionary = repo.burgs[code]
			if (s["rect"] as Rect2).has_point(Vector2(float(b["x"]), float(b["y"]))):
				n += 1
		if n > most:
			most = n
			best = s
	return best


func test_towns_say_whether_they_are_walled_and_ports() -> void:
	var s := _richest_sheet()
	var ink := WarSheetInk.strokes(repo, state, s, 1024)
	var walled := 0
	for t: Dictionary in ink["towns"]:
		assert_true(t.has("walls") and t.has("port"))
		walled += 1 if bool(t["walls"]) else 0
	var want := 0
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		if (s["rect"] as Rect2).has_point(Vector2(float(b["x"]), float(b["y"]))) and String(b.get("features", "")).split("|").has("walls"):
			want += 1
	assert_eq(walled, want)


func test_manor_edges_run_between_land_cells_of_one_province_only() -> void:
	var s := _richest_sheet()
	var ink := WarSheetInk.strokes(repo, state, s, 1024)
	assert_gt((ink["manor_edges"] as Array).size(), 0)
	for e: PackedVector2Array in ink["manor_edges"]:
		assert_eq(e.size(), 2)
	assert_gt((ink["manors"] as Array).size(), 0, "manors are named")


func test_hollows_are_the_low_landmarks_on_the_sheet() -> void:
	var s := _richest_sheet()
	var ink := WarSheetInk.strokes(repo, state, s, 1024)
	var want := 0
	for m: Dictionary in Elevation.landmarks(repo):
		if String(m["kind"]) == "low" and (s["rect"] as Rect2).has_point(m["pos"]):
			want += 1
	assert_eq((ink["hollows"] as Array).size(), want)


func test_no_bake_no_woods_and_nothing_breaks() -> void:
	var ink := WarSheetInk.strokes(repo, state, WarSheets.series(repo)[0], 1024, null)
	assert_eq((ink["woods"] as Array).size(), 0)
```

- [ ] **Step 2: Run** — FAIL (missing keys).

- [ ] **Step 3: Implement** — in `WarSheetInk.strokes` (signature gains `bake: WarBake = null`), add `"hollows": [], "woods": [], "manor_edges": [], "manors": []` to `out`, set each town's `"walls": String(b.get("features", "")).split("|").has("walls"), "port": String(b.get("is_port", "0")) == "1"`, and add before `return out`:

```gdscript
	for m: Dictionary in Elevation.landmarks(repo):
		if String(m["kind"]) == "low" and r.has_point(m["pos"]):
			(out["hollows"] as Array).append({"at": ((m["pos"] as Vector2) - r.position) * k,
				"metres": int(m["metres"]), "lod": int(m["lod"])})
	if bake != null:
		var step := repo.bal("war_ink_wood_step_km") * WarSheets.px_per_unit(repo)
		for w: Dictionary in bake.woods(r, step):
			var at: Vector2 = w["at"]
			# a glyph where the canopy is thick enough; its share decides by a fixed hash, so the
			# same sheet always draws the same woods
			if float(w["cover"]) >= repo.bal("war_ink_wood_min_cover") \
					and float(hash(Vector2i(at.round())) % 1000) / 1000.0 < float(w["cover"]):
				var jitter := Vector2(float(hash([at.x, 1]) % 100) - 50.0, float(hash([at.y, 2]) % 100) - 50.0) / 100.0 * step
				(out["woods"] as Array).append({"at": (at + jitter - r.position) * k, "conifer": float(w["conifer"]) > 0.5})
	_manors(repo, state, r, k, out)
```

and the helper:

```gdscript
## The manors' own edges — a cell edge between two land cells of ONE province
## (a province seam or the coast is drawn already) — and each manor's name at
## its centre unless a town stands within war_ink_manor_clear_px of it.
static func _manors(repo: DataRepository, state: GameState, r: Rect2, k: float, out: Dictionary) -> void:
	var owner_of: Dictionary = {}   # edge key -> first cell id
	var ids: Array = repo.cells.keys()
	ids.sort()
	var clear := repo.bal("war_ink_manor_clear_px")
	for id: int in ids:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell):
			continue
		var vids: PackedInt32Array = cell["vertex_ids"]
		if vids.size() < 3:
			continue
		var centre := MapTerrain.cell_center(repo, cell)
		if not r.grow(r.size.x * 0.05).has_point(centre):
			continue
		var prov := MapManors.province_of(repo, state, id)
		for i in vids.size():
			var a := vids[i]
			var b := vids[(i + 1) % vids.size()]
			var key := Vector2i(mini(a, b), maxi(a, b))
			if owner_of.has(key):
				var other := int(owner_of[key])
				if MapManors.province_of(repo, state, other) == prov:
					(out["manor_edges"] as Array).append(PackedVector2Array([
						((repo.vertices[a] as Vector2) - r.position) * k, ((repo.vertices[b] as Vector2) - r.position) * k]))
			else:
				owner_of[key] = id
		if r.has_point(centre):
			var at := (centre - r.position) * k
			var near_town := false
			for t: Dictionary in out["towns"]:
				if (t["at"] as Vector2).distance_to(at) < clear:
					near_town = true
					break
			if not near_town:
				(out["manors"] as Array).append({"at": at, "label": MapManors.label_of(repo, id)})
```

(`MapManors.province_of(repo, state, cell)` — read its real signature in `scripts/engine/map_manors.gd`; CLAUDE.md says province_of takes the state. `out["towns"]` must be filled BEFORE `_manors` runs — it is, the towns loop comes first.)

Painter — in `WarInkPainter._draw`, before the towns, add the woods and manors; after the peaks, the hollows; and give a walled town its wall and a port its anchor:

```gdscript
	var c_wood: Color = pal["wood_ink"]
	for wd: Dictionary in ink.get("woods", []):
		var at: Vector2 = wd["at"]
		var s := float(px["wood"])
		if bool(wd["conifer"]):
			draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s), at + Vector2(s * 0.55, s * 0.35), at + Vector2(-s * 0.55, s * 0.35)]), c_wood)
		else:
			draw_circle(at + Vector2(0, -s * 0.25), s * 0.5, c_wood)
		draw_line(at + Vector2(0, s * 0.2), at + Vector2(0, s * 0.6), c_wood, maxf(s * 0.15, 1.0), true)
	for e: PackedVector2Array in ink.get("manor_edges", []):
		for d: PackedVector2Array in WarSheetInk.dashed(e, float(px["manor_dash"]), float(px["manor_gap"])):
			draw_polyline(d, c_faint, float(px["manor"]), true)
	for mn: Dictionary in ink.get("manors", []):
		draw_string(font, (mn["at"] as Vector2) - Vector2(0, float(px["manor_label"]) * 0.2), String(mn["label"]),
			HORIZONTAL_ALIGNMENT_CENTER, -1, int(px["manor_label"]), c_faint)
```

In the towns loop, after the ring:

```gdscript
		if bool(t.get("walls", false)):
			var wr := r * float(px["wall_ratio"])
			draw_rect(Rect2((t["at"] as Vector2) - Vector2(wr, wr), Vector2(wr, wr) * 2.0), c_ink, false, float(px["town"]) * float(px["town_ring_ratio"]), true)
			for q in 4:   # a tower at each corner
				var corner := (t["at"] as Vector2) + Vector2(wr if q % 2 == 0 else -wr, wr if q < 2 else -wr)
				draw_rect(Rect2(corner - Vector2.ONE * wr * 0.22, Vector2.ONE * wr * 0.44), c_ink)
		if bool(t.get("port", false)):
			var an := (t["at"] as Vector2) + Vector2(-r * 1.9, 0.0)
			var a := r * float(px["anchor_ratio"])
			draw_line(an + Vector2(0, -a), an + Vector2(0, a), c_ink, maxf(a * 0.18, 1.0), true)
			draw_line(an + Vector2(-a * 0.45, -a * 0.55), an + Vector2(a * 0.45, -a * 0.55), c_ink, maxf(a * 0.15, 1.0), true)
			draw_arc(an + Vector2(0, a * 0.2), a * 0.75, 0.15 * PI, 0.85 * PI, 10, c_ink, maxf(a * 0.15, 1.0), true)
```

and after the peaks, the hollows (▽ with the depth):

```gdscript
	for p: Dictionary in ink.get("hollows", []):
		if int(p.get("lod", 0)) != 0:
			continue
		var at: Vector2 = p["at"]
		var s := float(px["town"])
		var hw := s * float(px["peak_half_w"])
		var drop := s * float(px["peak_drop"])
		draw_polyline(PackedVector2Array([at + Vector2(-hw, -drop), at + Vector2(hw, -drop), at + Vector2(0, s), at + Vector2(-hw, -drop)]), c_ink, maxf(s * 0.12, 1.0), true)
		draw_string(font, at + Vector2(hw + s * float(px["label_gap_ratio"]), drop), "%d m" % int(p["metres"]),
			HORIZONTAL_ALIGNMENT_LEFT, -1, int(float(px["label"]) * float(px["peak_label_ratio"])), c_ink)
```

`WarRoomInk`: add `"wood", "manor", "manor_label", "manor_dash", "manor_gap"` to `INK_PX` and `"wall_ratio", "anchor_ratio"` to `INK_RATIOS`; pass `WarBake.of(repo)` into `WarSheetInk.strokes` in `texture_for`. Palette row in `data/war_palette.csv`: `wood_ink,#3E4A2C99,"WAR ROOM v2 B: the woods' little trees, a green-black ink"`. Balance:

```csv
war_ink_wood_px,9,"WAR ROOM v2 B (spec §2.4): a tree glyph's size in ink-texture px"
war_ink_wood_step_km,1.6,"WAR ROOM v2 B (spec §2.4): woods are sampled every this much of the pack's measure; a glyph where the canopy is"
war_ink_wood_min_cover,0.25,"WAR ROOM v2 B (spec §2.4): the canopy share under which no tree is inked"
war_ink_manor_px,1.2,"WAR ROOM v2 B (spec §2.4): a manor edge's width, ink px (dashed, faint)"
war_ink_manor_dash_px,6,"WAR ROOM v2 B: a manor edge's dash, ink px"
war_ink_manor_gap_px,5,"WAR ROOM v2 B: a manor edge's gap, ink px"
war_ink_manor_label_px,20,"WAR ROOM v2 B (spec §2.4): a manor's name, ink px"
war_ink_manor_clear_px,60,"WAR ROOM v2 B: a manor's name is left out within this many ink px of a town (the town's name wins)"
war_ink_wall_ratio,1.35,"WAR ROOM v2 B (spec §2.4): a walled town's wall square, as a share of its ring's radius"
war_ink_anchor_ratio,0.9,"WAR ROOM v2 B (spec §2.4): a port's anchor, as a share of its ring's radius"
```

Add every new key to `test_war_room_data.gd`'s list. The new ink keys `"woods"` etc. must also appear in `WarMarginKey.LEGEND` only if the legend lists them — extend the LEGEND with `{"key": "wood", "label": "Woods"}`, `{"key": "manor", "label": "Manor"}`, `{"key": "walls", "label": "Walled town"}`, `{"key": "port", "label": "Port"}` and draw each in `_draw_mark` the way the painter does (read `_draw_mark`'s pattern); update `test_war_margin_key.gd`'s legend list.

- [ ] **Step 4: Run** `$W/t.sh res://tests/war_room res://tests/ui/test_war_margin_key.gd res://tests/engine/test_war_room_data.gd` — PASS.

- [ ] **Step 5: Commit** `feat(war-room): the sheet inks hollows, woods, manors and their names, walls and ports`.

---

### Task 8: Roads and water — bridges, fords, rivers that widen and are named

**Files:**
- Modify: `scripts/war_room/war_sheet_ink.gd`, `scripts/war_room/war_ink_painter.gd`, `scripts/war_room/war_room_ink.gd`, `data/balance.csv`
- Test: `tests/war_room/test_war_sheet_ink.gd`

**Interfaces:**
- Produces: `WarSheetInk.crossings(lines: Array, rivers: Array) -> Array` of `{at: Vector2, dir: Vector2}` (a line's direction at the crossing, unit) — pure, any space; `strokes` keys `"bridges"`, `"fords"` (`[{at, dir}]` in ink px), and `"rivers"` becomes `Array` of `{poly: PackedVector2Array, w0: float, w1: float, label: String}`.

- [ ] **Step 1: Failing tests** — append:

```gdscript
func test_a_crossing_is_where_a_line_meets_a_river() -> void:
	var road := PackedVector2Array([Vector2(0, 0), Vector2(10, 0)])
	var river := PackedVector2Array([Vector2(4, -5), Vector2(4, 5)])
	var hits := WarSheetInk.crossings([road], [river])
	assert_eq(hits.size(), 1)
	assert_almost_eq((hits[0]["at"] as Vector2).distance_to(Vector2(4, 0)), 0.0, 0.0001)
	assert_almost_eq((hits[0]["dir"] as Vector2).dot(Vector2.RIGHT), 1.0, 0.0001)
	assert_eq(WarSheetInk.crossings([road], [PackedVector2Array([Vector2(20, -5), Vector2(20, 5)])]).size(), 0)


func test_rivers_widen_toward_the_mouth_and_carry_their_names() -> void:
	var s := _richest_sheet()
	var ink := WarSheetInk.strokes(repo, state, s, 1024)
	assert_gt((ink["rivers"] as Array).size(), 0)
	for rv: Dictionary in ink["rivers"]:
		assert_gte(float(rv["w1"]), float(rv["w0"]), "a river is never narrower at its mouth")
		assert_true(rv.has("label"))


func test_roads_over_rivers_are_bridges_and_trails_fords() -> void:
	var s := _richest_sheet()
	var ink := WarSheetInk.strokes(repo, state, s, 1024)
	assert_true(ink.has("bridges") and ink.has("fords"))
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** in `WarSheetInk`:

```gdscript
## Where any of `lines` crosses any of `rivers` (both lists of polylines in one
## space): the point and the LINE's direction there. Segment against segment;
## the sheet's few hundred segments make the plain double loop cheap enough.
static func crossings(lines: Array, rivers: Array) -> Array:
	var out: Array = []
	for line: PackedVector2Array in lines:
		for i in line.size() - 1:
			var a := line[i]
			var b := line[i + 1]
			for rv: PackedVector2Array in rivers:
				for j in rv.size() - 1:
					var hit: Variant = Geometry2D.segment_intersects_segment(a, b, rv[j], rv[j + 1])
					if hit != null:
						out.append({"at": hit as Vector2, "dir": (b - a).normalized()})
	return out
```

In `strokes`: the rivers loop becomes

```gdscript
	var base_w := repo.bal("war_ink_river_px")
	for code: String in river_codes:
		var row: Dictionary = repo.rivers[code]
		var poly: PackedVector2Array = row["polyline"]
		if _touches(r, poly):
			var mouth := minf(base_w * (1.0 + repo.bal("war_ink_river_discharge_k") * sqrt(maxf(float(row.get("discharge", "0")), 0.0))),
				repo.bal("war_ink_river_max_px"))
			(out["rivers"] as Array).append({"poly": _to_tex(r, k, poly), "w0": base_w, "w1": maxf(mouth, base_w),
				"label": String(row.get("label", ""))})
```

and after rivers and routes are gathered:

```gdscript
	var river_polys: Array = (out["rivers"] as Array).map(func(rv: Dictionary) -> PackedVector2Array: return rv["poly"])
	out["bridges"] = crossings(out["roads"], river_polys)
	out["fords"] = crossings(out["trails"], river_polys)
```

Painter — the rivers loop draws each segment at its width along the course, then the name at its middle, then the crossings:

```gdscript
	for rv: Dictionary in ink["rivers"]:
		var poly: PackedVector2Array = rv["poly"]
		var n := poly.size()
		for i in n - 1:
			var w := lerpf(float(rv["w0"]), float(rv["w1"]), float(i) / float(maxi(n - 2, 1)))
			draw_line(poly[i], poly[i + 1], pal["river_ink"], w, true)
		if String(rv["label"]) != "" and n >= 2:
			var mid := poly[n / 2]
			draw_string(font, mid + Vector2(float(px["river_label"]) * 0.4, -float(px["river_label"]) * 0.3), String(rv["label"]),
				HORIZONTAL_ALIGNMENT_LEFT, -1, int(px["river_label"]), pal["river_ink"])
	for b: Dictionary in ink.get("bridges", []):
		var at: Vector2 = b["at"]
		var along: Vector2 = b["dir"]
		var across := along.orthogonal()
		var s := float(px["bridge"])
		for side in [-1.0, 1.0]:   # two parapets either side of the road
			draw_line(at + across * s * 0.5 * side - along * s, at + across * s * 0.5 * side + along * s, c_ink, maxf(s * 0.25, 1.0), true)
	for f: Dictionary in ink.get("fords", []):
		var at: Vector2 = f["at"]
		var across := (f["dir"] as Vector2).orthogonal()
		for d: PackedVector2Array in WarSheetInk.dashed(PackedVector2Array([at - across * float(px["bridge"]), at + across * float(px["bridge"])]), 2.0, 2.0):
			draw_polyline(d, c_ink, maxf(float(px["bridge"]) * 0.2, 1.0), true)
```

(Integer division `n / 2` needs `@warning_ignore("integer_division")` above it.) `WarRoomInk.INK_PX` gains `"river_label", "bridge"`. Balance:

```csv
war_ink_river_discharge_k,0.06,"WAR ROOM v2 B (spec §2.4): a river's mouth width: war_ink_river_px x (1 + this x sqrt(discharge))"
war_ink_river_max_px,9,"WAR ROOM v2 B (spec §2.4): no river is inked wider than this at its mouth, ink px"
war_ink_river_label_px,22,"WAR ROOM v2 B (spec §2.4): a river's name, ink px, in the river's blue"
war_ink_bridge_px,7,"WAR ROOM v2 B (spec §2.4): a bridge's parapets / a ford's dashes, ink px"
```

Add the legend entries `bridge` / `ford` to `WarMarginKey.LEGEND` with their drawings, and the keys to the data test.

- [ ] **Step 4: Run** `$W/t.sh res://tests/war_room res://tests/ui/test_war_margin_key.gd res://tests/engine/test_war_room_data.gd` — PASS.

- [ ] **Step 5: Commit** `feat(war-room): bridges and fords where roads and trails cross rivers; rivers widen to the mouth and are named`.

---

### Task 9: The intelligence layer

**Files:**
- Create: `scripts/war_room/war_intel_ink.gd`
- Modify: `scripts/engine/supply_system.gd` (a public `route_px`), `scripts/war_room/war_ink_painter.gd` (an intel mode), `scripts/war_room/war_room_ink.gd` (`intel_for`), `scripts/war_room/war_room_view.gd` (`_paint_intel` on lay and refresh), `data/balance.csv`, `data/war_palette.csv`
- Test: `tests/war_room/test_war_intel_ink.gd`, `tests/engine/test_supply_system.gd` (route_px)

**Interfaces:**
- Consumes: `SupplySystem` road context, `CourierSystem` couriers (`state.couriers`: `x_m`, `y_m`, `path` of `[x_m, y_m]`, `kind`), `Weather.of(repo, state, province, abs_day)` and `data/weather.csv` look columns (`repo.weather` — read how DataRepository exposes it), `MissiveLog` (`state.missives`, kind `"spy"`, `subject` `{x, y}`, `facts` with `lo`/`hi`).
- Produces: `SupplySystem.route_px(repo, state, code) -> PackedVector2Array` (depot → road → the regiment, pack px; empty for a stronghold or naval regiment); `WarIntelInk.strokes(repo, state, sheet, tex_px) -> Dictionary` `{"supply": [{poly, loss_permille}], "couriers": [{poly, at, spy: bool}], "weather": [{at, rain, snow, overcast, label}], "spies": [{at, radius, text}]}` (ink px); `WarIntelInk.cache_key(state, sheet) -> int`; `WarInkPainter.paint_intel(ink, pal, px, font)`; `WarRoomInk.intel_for(repo, state, sheet, viewport, painter, font, still_wanted) -> Texture2D`.

- [ ] **Step 1: Failing tests** — create `tests/war_room/test_war_intel_ink.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## What we KNOW, inked over the laid sheet once a day (spec 2026-10-02-war-room-v2
## §2.4): our supply lines, our couriers, the weather, spy reports that came in.

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()


func _sheet_of_first_regiment() -> Dictionary:
	var p: Dictionary = WarRoom.pieces(repo, state)[0]
	return WarSheets.series(repo)[int(p["sheet"])]


func test_only_our_own_supply_lines_are_inked() -> void:
	var ink := WarIntelInk.strokes(repo, state, _sheet_of_first_regiment(), 1024)
	var ours: Array = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")).map(
		func(r: Dictionary) -> String: return String(r["regiment_code"]))
	for line: Dictionary in ink["supply"]:
		assert_true(String(line["code"]) in ours, "a foreign regiment's supply line is not ours to know")
		assert_gte((line["poly"] as PackedVector2Array).size(), 2)


func test_a_spy_still_riding_is_a_courier_and_files_no_report_yet() -> void:
	var s := _sheet_of_first_regiment()
	var at: Vector2 = (s["cell"] as Rect2).get_center()
	CourierSystem.dispatch_spy(repo, state, at)
	var ink := WarIntelInk.strokes(repo, state, s, 1024)
	assert_eq((ink["spies"] as Array).size(), 0, "no report until it has come in")
	var riding: Array = (ink["couriers"] as Array).filter(func(x: Dictionary) -> bool: return bool(x["spy"]))
	assert_lte(riding.size(), 1, "the spy rides as a courier, once")


func test_an_arrived_spy_report_is_a_ring_with_its_estimate() -> void:
	var s := _sheet_of_first_regiment()
	var at: Vector2 = (s["cell"] as Rect2).get_center()
	MissiveLog.add(repo, state, MissiveLog.make("spy", "credible", state.absolute_day(),
		MissiveLog.subject("point", "", -1, at), "A report", [MissiveLog.span("people", "People", 2800, 3200)]))
	var ink := WarIntelInk.strokes(repo, state, s, 1024)
	assert_eq((ink["spies"] as Array).size(), 1)
	assert_string_contains(String(ink["spies"][0]["text"]), "2,800")


func test_the_key_turns_with_the_day_and_the_couriers() -> void:
	var a := WarIntelInk.cache_key(state, 0)
	state.day += 1
	assert_ne(WarIntelInk.cache_key(state, 0), a)
```

`MissiveLog.add`'s signature is `add(repo, state, m)` (read in plan A).

In `tests/engine/test_supply_system.gd` (read its fixture) add:

```gdscript
func test_a_route_runs_from_the_depot_to_the_regiment() -> void:
	for code: String in state.regiments:
		var reg := ArmySystem.regiment(repo, code)
		if String(reg.get("is_naval", "0")) == "1" or SupplySystem.stronghold_of(repo, state, code) != "":
			continue
		var route := SupplySystem.route_px(repo, state, code)
		assert_gte(route.size(), 2)
		assert_almost_eq(route[route.size() - 1].distance_to(ArmySystem.position_of(repo, state, reg)), 0.0, 0.01)
		return
	pending("no regiment stands away from a stronghold in this fixture")
```

- [ ] **Step 2: Run** — FAIL.

- [ ] **Step 3: Implement** — `SupplySystem.route_px`:

```gdscript
## The supply road a regiment is fed along, pack px from the depot to where it
## stands (spec 2026-10-02-war-room-v2 §2.4, the WAR ROOM's intel ink); empty
## for a regiment supplied through a stronghold (no road) or at sea.
static func route_px(repo: DataRepository, state: GameState, code: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var reg := ArmySystem.regiment(repo, code)
	if reg.is_empty() or String(reg.get("is_naval", "0")) == "1" or stronghold_of(repo, state, code) != "":
		return out
	var ctx := _road_context(repo, state)
	var to := ArmySystem.position_of(repo, state, reg)
	out.append(ArmySystem.metres_to_pack(repo, ctx["a"]))
	for p: Array in _path_from_ctx(repo, ctx, to):
		out.append(ArmySystem.metres_to_pack(repo, Vector2i(int(p[0]), int(p[1]))))
	if out[out.size() - 1].distance_to(to) > 0.001:
		out.append(to)
	return out
```

(Read `_road_context`'s `"a"`: the depot in metres as a Vector2i — confirm and adapt.)

`scripts/war_room/war_intel_ink.gd`:

```gdscript
class_name WarIntelInk
extends RefCounted
## What we KNOW, inked over the laid sheet (owner 2026-10-02, spec
## 2026-10-02-war-room-v2 §2.4): our regiments' supply roads (fainter for what
## they lose), our couriers on the road and the road ahead, this spell's
## weather by province, and every spy report that has COME IN (a missive) as a
## ring of its estimate. Never a foreign regiment's line, never a spy still
## riding as a report. In ink-texture px like WarSheetInk; drawn into its own
## texture once a day (cache_key).


static func cache_key(state: GameState, sheet_index: int) -> int:
	var couriers: Array = state.couriers.map(func(c: Dictionary) -> Array: return [c["id"], c["x_m"], c["y_m"]])
	return hash([sheet_index, state.absolute_day(), couriers, state.missives.size(), state.regiments.hash()])


static func strokes(repo: DataRepository, state: GameState, sheet: Dictionary, tex_px: int) -> Dictionary:
	var r: Rect2 = sheet["rect"]
	var k := float(tex_px) / r.size.x
	var out := {"supply": [], "couriers": [], "weather": [], "spies": []}
	var ours: Array = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")).map(
		func(x: Dictionary) -> String: return String(x["regiment_code"]))
	ours.sort()
	for code: String in ours:
		var route := SupplySystem.route_px(repo, state, code)
		if route.size() >= 2 and WarSheetInk._touches(r, route):
			var line := SupplySystem.line_of(repo, state, code)
			(out["supply"] as Array).append({"code": code, "poly": WarSheetInk._to_tex(r, k, route),
				"loss_permille": int(line["loss_permille"])})
	for c: Dictionary in state.couriers:
		var pts := PackedVector2Array([ArmySystem.metres_to_pack(repo, Vector2i(int(c["x_m"]), int(c["y_m"])))])
		for p: Array in c.get("path", []):
			pts.append(ArmySystem.metres_to_pack(repo, Vector2i(int(p[0]), int(p[1]))))
		if WarSheetInk._touches(r, pts):
			(out["couriers"] as Array).append({"poly": WarSheetInk._to_tex(r, k, pts), "at": (pts[0] - r.position) * k,
				"spy": String(c.get("kind", "")) == CourierSystem.SPY})
	var day := state.absolute_day()
	var codes: Array = repo.provinces.keys()
	codes.sort()
	for code: String in codes:
		var row: Dictionary = repo.provinces[code]
		var at := Vector2(float(row.get("center_x", 0)), float(row.get("center_y", 0)))
		if not r.has_point(at):
			continue
		var kind := Weather.of(repo, state, code, day)
		var look: Dictionary = repo.weather.get(kind, {})
		if float(look.get("rainfall", "0")) <= 0.0 and float(look.get("snowfall", "0")) <= 0.0 and float(look.get("overcast", "0")) < 0.5:
			continue   # fair weather is not news
		(out["weather"] as Array).append({"at": (at - r.position) * k, "rain": float(look.get("rainfall", "0")),
			"snow": float(look.get("snowfall", "0")), "overcast": float(look.get("overcast", "0")),
			"label": Weather.label_of(repo, kind)})
	var seen: Dictionary = {}
	var spies: Array = state.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "spy")
	spies.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) > int(b["id"]))
	for m: Dictionary in spies:
		var subj: Dictionary = m["subject"]
		var at := Vector2(float(subj.get("x", 0)), float(subj.get("y", 0)))
		var key := Vector2i(at.round())
		if seen.has(key) or not r.has_point(at):
			continue
		seen[key] = true
		var spread := 0.0
		var text := String(m["title"])
		for f: Dictionary in m["facts"]:
			if f.has("lo"):
				spread = float(int(f["hi"]) - int(f["lo"])) / maxf(float(f["hi"]), 1.0)
				text = "%s ≈ %s–%s" % [String(f["label"]), UiPalette.format_int(int(f["lo"])), UiPalette.format_int(int(f["hi"]))]
				break
		text += " · " + CourierCard.date_of(int(m["day"]))
		(out["spies"] as Array).append({"at": (at - r.position) * k,
			"radius": repo.bal("war_intel_spy_ring_px") * (1.0 + spread * repo.bal("war_intel_spy_spread_k")), "text": text})
	return out
```

`UiPalette` and `CourierCard` live in `scripts/ui/`; `scripts/war_room/` may call static helpers of scripts/ui (it must not reach `Game`): if either reaches `Game` inside the function used, write a local thousands grouper (`WarRoom.group` already exists — use `WarRoom.group(int)`) and a local date (`Calendar` in scripts/engine has the date words — read `CourierCard.date_of` and call what it calls). Check `repo.weather`'s real name in `DataRepository` and `Weather.label_of`'s signature.

Painter — add `var intel := false` and

```gdscript
func paint_intel(p_ink: Dictionary, p_pal: Dictionary, p_px: Dictionary, p_font: Font) -> void:
	intel = true
	paint(p_ink, p_pal, p_px, p_font)
```

and make `paint` set `intel = false` unless called through `paint_intel` (set the flag after `paint` resets it, or give `paint` an `as_intel := false` parameter). At the top of `_draw`, `if intel: _draw_intel(); return`, with:

```gdscript
func _draw_intel() -> void:
	var c: Color = pal["intel_ink"]
	for s: Dictionary in ink["supply"]:
		var col := c
		col.a *= clampf(1.0 - float(s["loss_permille"]) / 1000.0 * float(px["supply_loss_fade"]), 0.25, 1.0)
		for d: PackedVector2Array in WarSheetInk.dashed(s["poly"], float(px["supply_dash"]), float(px["supply_gap"])):
			draw_polyline(d, col, float(px["supply"]), true)
	for cr: Dictionary in ink["couriers"]:
		for d: PackedVector2Array in WarSheetInk.dashed(cr["poly"], 2.0, float(px["supply_gap"])):
			draw_polyline(d, c, float(px["supply"]) * 0.7, true)
		var at: Vector2 = cr["at"]
		var s := float(px["courier"])
		draw_circle(at, s * 0.5, c)
		draw_line(at, at + Vector2(0, -s * 1.3), c, maxf(s * 0.15, 1.0), true)        # the pennon's staff
		draw_colored_polygon(PackedVector2Array([at + Vector2(0, -s * 1.3), at + Vector2(s * 0.8, -s * 1.1), at + Vector2(0, -s * 0.9)]), pal["rubric"] if bool(cr["spy"]) else c)
	for w: Dictionary in ink["weather"]:
		var at: Vector2 = w["at"]
		var s := float(px["weather"])
		if float(w["overcast"]) >= 0.5:
			draw_arc(at + Vector2(-s * 0.3, 0), s * 0.45, PI, TAU, 10, c, maxf(s * 0.12, 1.0), true)
			draw_arc(at + Vector2(s * 0.3, -s * 0.1), s * 0.55, PI, TAU, 10, c, maxf(s * 0.12, 1.0), true)
		for i in int(round(float(w["rain"]) * 3.0)):
			var x := -s * 0.4 + float(i) * s * 0.4
			draw_line(at + Vector2(x, s * 0.2), at + Vector2(x - s * 0.15, s * 0.7), c, maxf(s * 0.1, 1.0), true)
		if float(w["snow"]) > 0.0:
			for a in 3:
				var dir := Vector2.from_angle(float(a) * PI / 3.0) * s * 0.35
				draw_line(at + Vector2(0, s * 0.45) - dir, at + Vector2(0, s * 0.45) + dir, c, maxf(s * 0.1, 1.0), true)
	for sp: Dictionary in ink["spies"]:
		var at: Vector2 = sp["at"]
		var ring := PackedVector2Array()
		for i in 49:
			ring.append(at + Vector2.from_angle(TAU * float(i) / 48.0) * float(sp["radius"]))
		for d: PackedVector2Array in WarSheetInk.dashed(ring, float(px["supply_dash"]), float(px["supply_gap"])):
			draw_polyline(d, pal["rubric"], float(px["supply"]), true)
		draw_string(font, at + Vector2(float(sp["radius"]) + 4.0, 0), String(sp["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(px["intel_label"]), pal["rubric"])
```

`WarRoomInk`: `const INTEL_PX := ["supply", "supply_dash", "supply_gap", "courier", "weather", "intel_label"]`, `const INTEL_RATIOS := ["supply_loss_fade"]`; `var intel: Dictionary = {}` (one entry `{sheet, key, tex}`); and

```gdscript
func intel_for(repo: DataRepository, state: GameState, sheet: int, viewport: SubViewport,
		painter: WarInkPainter, font: Font, still_wanted: Callable) -> Texture2D:
	var key := WarIntelInk.cache_key(state, sheet)
	if intel.get("key", -1) == key and int(intel.get("sheet", -1)) == sheet:
		return intel.get("tex") as Texture2D
	var row: Dictionary = WarSheets.series(repo)[sheet]
	var w := int(repo.bal("war_intel_texture_px"))
	var size := Vector2i(w, maxi(1, ceili(w * (row["rect"] as Rect2).size.y / (row["rect"] as Rect2).size.x)))
	_gen += 1
	var gen := _gen
	viewport.size = size
	var widths := {}
	for k: String in INTEL_PX:
		widths[k] = repo.bal("war_intel_%s_px" % k)
	for k: String in INTEL_RATIOS:
		widths[k] = repo.bal("war_intel_%s" % k)
	painter.paint_intel(WarIntelInk.strokes(repo, state, row, size.x), repo.war_palette, widths, font)
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	await frame_done
	if gen != _gen:
		return null
	var img: Image = viewport.get_texture().get_image() if bool(still_wanted.call()) else null
	if is_instance_valid(viewport):
		viewport.size = REST
	if img == null or img.is_empty():
		return null
	img.generate_mipmaps()
	intel = {"sheet": sheet, "key": key, "tex": ImageTexture.create_from_image(img)}
	return intel["tex"]
```

The intel texture is drawn at the same aspect as the ink texture (`tex_aspect` holds for both: `war_intel_texture_px` keeps `used_share` the same — check `used_share`; if the two widths round differently, pass a second `intel_aspect` uniform). In `WarRoomView`: after `await _paint_ink(mat)` in `lay_sheet`, `await _paint_intel(mat)`; in `refresh()`, `_paint_intel(_table.get_active_material(0))` (it returns at once when the key is unchanged); `_paint_intel` mirrors `_paint_ink` with `_inks.intel_for` and `mat.set_shader_parameter("intel_tex", tex)`. A draw in progress (the ink's) must not be stomped: `_gen` already guards a superseded draw — keep the ink's await before the intel's.

Palette: `intel_ink,#3B2F6E,"WAR ROOM v2 B: the intelligence layer's ink — a dark violet, apart from the sheet's sepia"`. Balance:

```csv
war_intel_texture_px,2048,"WAR ROOM v2 B (spec §2.4): the intelligence layer's texture width — redrawn once a day, so smaller than the sheet's ink"
war_intel_supply_px,2.4,"WAR ROOM v2 B: a supply road's width, intel px"
war_intel_supply_dash_px,10,"WAR ROOM v2 B: a supply road's dash, intel px"
war_intel_supply_gap_px,6,"WAR ROOM v2 B: a supply road's gap, intel px"
war_intel_supply_loss_fade,1.5,"WAR ROOM v2 B: a supply road fades by its loss x this (never below a quarter)"
war_intel_courier_px,14,"WAR ROOM v2 B: a courier's mark, intel px"
war_intel_weather_px,18,"WAR ROOM v2 B: a weather mark, intel px"
war_intel_label_px,15,"WAR ROOM v2 B: a spy report's words, intel px"
war_intel_spy_ring_px,26,"WAR ROOM v2 B: a spy report's ring, intel px, before its spread"
war_intel_spy_spread_k,2,"WAR ROOM v2 B: the ring grows by the estimate's spread (hi-lo)/hi x this"
```

(The intel px are in INTEL texture px — 2048 wide — about half the ink texture's 4096; size them so they read on the table. Task 10 checks.) Add the keys to the data test.

- [ ] **Step 4: Run** `$W/t.sh res://tests/war_room res://tests/engine/test_supply_system.gd res://tests/engine/test_war_room_data.gd res://tests/war_room/test_war_room_isolation.gd` — PASS.

- [ ] **Step 5: Commit** `feat(war-room): the intelligence layer — our supply roads, couriers, the weather and spy reports, redrawn daily`.

---

### Task 10: Shots, the visual review, the bench

**Files:**
- Modify: `tools/snapshot_screen.gd` (`--war-cell ID`: a real click on that cell of the chart), possibly `data/balance.csv` (tuned values)

- [ ] **Step 1: `--war-cell ID`** — parse it beside `--war-sheet`; in `_war_room_step` phase 1, instead of `view.swap_to`, find the series row whose `id` is ID, project its chart cell centre (`WarRoomWall.chart_point(chart, WarIndexChart.uv_of_cell(...).get_center())` through `%Camera`, ÷ `view.window_scale()`) and `_real_click(view, at)`; phase 2 waits while `view.tossing() or view.rolling()`. Document it in the `--war-room` comment block.

- [ ] **Step 2: Shoot** (real window, NOT headless; `$S` the scratchpad):

```bash
G=/Applications/Godot.app/Contents/MacOS/Godot
S0="--path . res://tools/snapshot_screen.tscn -- --screen root --quiet --war-room --resolution 2560x1600"
$G $S0 --out $S/b_open.png
$G $S0 --war-zoom 0.5 --war-focus <a regiment code printed by war: pieces=> --out $S/b_near.png
$G $S0 --war-zoom 3.0 --out $S/b_far.png
$G $S0 --war-cell <another land id> --out $S/b_toss.png
for x in 2 3 4; do $G $S0 --bal war_relief_exaggeration=$x --war-zoom 0.6 --out $S/b_relief$x.png; done
```

- [ ] **Step 3: The visual review** — invoke the `visual-review` skill: contact sheets of the relief bracket (2/3/4) and of open/near/far/toss, crops at 3× of a town with walls and a port, a bridge, a manor's name, a wood, the neat line and collar, a supply road and a weather mark; an independent critic subagent with `taste.md` and the rubric. Fix what breaks a principle (sizes, alphas — all `balance.csv`), re-shoot, ledger the values.

- [ ] **Step 4: The bench** — `tools/war_room/bench.tscn --size 3024x1964 --quality high` and `--size 1920x1080 --quality medium`: each row under its tier's `bench_budget_ms` (the relief mesh is 384 wide now). If over, lower `war_relief_grid` to 320 and re-run; ledger the numbers.

- [ ] **Step 5: Commit** `tools(war-room): --war-cell; B's look tuned by review`.

---

### Task 11: Documents and the full suite

**Files:**
- Modify: `CLAUDE.md` (the WAR ROOM paragraph's series sentence), `docs/superpowers/specs/2026-10-02-war-room-v2-design.md` (§12 "Changed while building"), `assets/3D/war_room/README.md` (no change unless the marker stand-in is listed — add it as "stand-in until D")

- [ ] **Step 1: CLAUDE.md** — replace the sentence beginning `**The series** is \`WarSheets\`` (sheets of `war_sheet_w_km` … Roman numerals … `III · C7` on a `war_grid_km` grid) with: "**The series** is `WarSheets` (pure, `scripts/engine/`): since v2's plan B (spec `2026-10-02-war-room-v2-design.md` §2) the pack's own graticule — `MapCoords` from `map_info.csv`'s `lat_n`/`lat_s`/`lon_w`/`lon_e` (Azgaar's `mapCoordinates`, written by the importer) — cut into `war_sheet_deg` 20° cells (18 × 9 on beria), a sheet per cell with land named `D4` and after the kingdom with the most land on it, its `cell` the neat line and its `rect` (the table) grown by a `war_sheet_collar_km` collar inked faint (`war_collar_*`), places written `D4 · c7 · 24°N 51°E` on a `war_grid_deg` grid; the index chart is the graticule (land cells framed in rubric, sea washed, columns lettered, rows numbered) and a click on a land cell TOSSES the war marker onto it (`WarToss`, pure, `war_toss_*`; a stand-in until D) before the sheet is laid. The relief is the build's own `bake/height.r32` (`WarBake`, read by rows; `world_relief.png` without a build), `war_relief_grid` 384; the sheet also inks hollows, woods (`bake/woods.png`), manors and their names, walled towns and ports, bridges and fords, rivers widening to the mouth and named; and a second texture, redrawn daily, inks what we KNOW (`WarIntelInk`: our supply roads by `SupplySystem.route_px`, our couriers, the weather, spy reports that came in)." Remove the stale `III · C7` mention in the margin sentence ("3rd Regiment → IV" → "3rd Regiment → D4").

- [ ] **Step 2: The spec** — add to `docs/superpowers/specs/2026-10-02-war-room-v2-design.md` a `## 12. Changed while building` with plan A's three-point pitch ruling (from the merged ledger: near 30 / mid 52 / far 24, max 3.0 m, the easel at x −1.5) and plan B's relief-source refinement (`bake/height.r32` read directly rather than a screen-handed Terrain3D `height_fn`).

- [ ] **Step 3: The full suite** — `./run_tests.sh > $W/full.log 2>&1; echo $?; grep -E "Passing|Failing" $W/full.log | tail -2`. Expected: all pass, exit 0.

- [ ] **Step 4: Commit** `docs: the WAR ROOM's graticule series, its bake relief and its intelligence ink`.

- [ ] **Step 5: Show the owner** — send the open / near / toss / far shots (SendUserFile) and wait for the look before plan C.
