# Map Objects Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the world map's towns, roads, rivers, points of interest, and terrain hoverable and clickable, each opening an info card whose "Ask the council" button pre-fills the order box.

**Architecture:** The Azgaar importer emits more pack data (routes, rivers, markers, biomes, map info, two more index bitmaps); `DataRepository.load_map` loads it; an engine-pure `MapObjects` class hit-tests with pin > line > land > water priority and builds each card's text; `WorldMapView` draws LOD-gated pins and hover highlights and delegates the card to a new `MapInfoCard`, whose Ask button bubbles up as `place_asked` to the court and conversation screens.

**Tech Stack:** Godot 4.x, typed GDScript, GUT. Headless test runner: `./run_tests.sh` (full) or the filtered single-selector runner below.

**Spec:** `docs/superpowers/specs/2026-09-08-map-objects-design.md`

## Global Constraints

- Typed GDScript everywhere (type hints on vars, params, returns). `snake_case` files/functions, `PascalCase` classes, past-tense signals.
- Engine classes (`scripts/engine/`) are `RefCounted`, no Node/scene dependencies, no `Time.get_*`, no unseeded RNG. UI reads `Game.data`, never mutates state.
- Design values live in CSVs (`data/balance.csv` here), not in script constants.
- `data/maps/<id>/*.csv` and `assets/maps/<id>/*.png` are **generated** by `tools/import_azgaar.gd`; never hand-edit them. Re-run the importer after changing it and confirm untouched outputs stay byte-identical (`git status`).
- Godot only registers a new `class_name` after an import pass. After creating any new `.gd` with `class_name`, run `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import` once (exit 134 on macOS is normal) before running GUT directly.
- Test runner for one selector (prints only our failures + summary):
  `/private/tmp/claude-501/-Users-yumengzhang-game-design/2c47ab8e-4e27-4649-a40b-d2698594e1d1/scratchpad/gut.sh <substring>` — or the raw form:
  `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gselect=<substring>`
- `./run_tests.sh` must end with `All tests passed!`, `Errors 2`, and exit 0 before every commit.
- Commit messages end with:
  `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>` and
  `Claude-Session: https://claude.ai/code/session_019HggsFraqfeKGW6RHNys5E`
- Beria facts used by tests (from the export): Kuojarpan is Hetalia's capital at native (1127.87, 686.13), type Naval, port, walls+citadel+temple+plaza, province Onjormaa (Azgaar id 72), biome 6 "Temperate deciduous forest". Route "Ororeanian road" (group roads) runs Cocalomo → Ororeanes with midpoint (560.33, 322.71). Marker "The Orange Jackal" (inns) sits at (1062.82, 727.96) in Hetalia. `settings.distanceUnit` = km, `distanceScale` = 2.

## File Structure

| File | Responsibility |
|---|---|
| `tools/import_azgaar.gd` (modify) | Emit the new columns, tables, and bitmaps; shared rasterizer |
| `data/maps.csv` (modify) | Two new art columns: `province_texture`, `biome_texture` |
| `data/balance.csv` (modify) | Six `map_*` LOD / pick-radius values |
| `scripts/engine/map_index.gd` (modify) | Generic `id_at`, `biome_at` decoders |
| `scripts/engine/map_geometry.gd` (modify) | `bounds`, `polyline_length`, `distance_to_polyline` |
| `scripts/engine/data_repository.gd` (modify) | Load routes/rivers/markers/biomes/map_info; derived polyline+bbox |
| `scripts/engine/map_objects.gd` (create) | Hit-testing (`object_at`), LOD rule, card text (`describe`) |
| `scripts/ui/map_info_card.gd` (create) | The floating card: title, lines, Ask/Close buttons, signals |
| `scripts/ui/world_map_view.gd` (modify) | Pins, hover object + tooltip, selection, `place_asked` |
| `scripts/ui/court_screen.gd`, `scripts/ui/conversation_scene.gd` (modify) | Enable Ask; fill the input box |
| `tests/engine/test_map_data.gd`, `test_map_index.gd`, `test_map_geometry.gd` (modify), `test_map_objects.gd` (create), `tests/ui/test_world_map_view.gd`, `test_court_screen.gd`, `test_conversation_scene.gd` (modify) | Tests |
| `CLAUDE.md`, spec (modify) | Generated-files note; two spec amendments |

---

### Task 1: Importer outputs, repository loading, data tests

**Files:**
- Modify: `tools/import_azgaar.gd`
- Modify: `data/maps.csv`
- Modify: `scripts/engine/map_index.gd`
- Modify: `scripts/engine/map_geometry.gd`
- Modify: `scripts/engine/data_repository.gd`
- Test: `tests/engine/test_map_index.gd`, `tests/engine/test_map_geometry.gd`, `tests/engine/test_map_data.gd`

**Interfaces:**
- Produces: `MapIndex.id_at(img: Image, px: Vector2i) -> int` (R | G<<8, white → -1), `MapIndex.biome_at(img: Image, px: Vector2i) -> int` (R, white → -1); `MapGeometry.bounds(pts: PackedVector2Array) -> Rect2`; on `DataRepository`: `routes: Dictionary`, `rivers: Dictionary` (rows carry `polyline: PackedVector2Array` and `bbox: Rect2`), `markers: Dictionary`, `biomes: Dictionary` (int id → row), `map_info: Dictionary` (String → String), `province_texture_path: String`, `biome_texture_path: String`. Burg rows gain `type`, `features`; province rows gain `province_id`, `center_x`, `center_y`.

- [x] **Step 1: Write the failing decoder and geometry tests**

Append to `tests/engine/test_map_index.gd`:

```gdscript

## The province bitmap reuses the state encoding; the biome bitmap keeps its
## id in the red channel only. Both treat pure white as "nothing here".
func test_id_at_is_the_generic_two_byte_decoder() -> void:
	var img := Image.create(2, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color8(3, 1, 0))
	img.set_pixel(1, 0, Color8(255, 255, 255))
	assert_eq(MapIndex.id_at(img, Vector2i(0, 0)), 259)
	assert_eq(MapIndex.id_at(img, Vector2i(1, 0)), -1)
	assert_eq(MapIndex.id_at(null, Vector2i(0, 0)), -1, "nil image")

func test_biome_at_reads_the_red_channel() -> void:
	var img := Image.create(2, 1, false, Image.FORMAT_RGB8)
	img.set_pixel(0, 0, Color8(6, 0, 0))
	img.set_pixel(1, 0, Color8(255, 255, 255))
	assert_eq(MapIndex.biome_at(img, Vector2i(0, 0)), 6)
	assert_eq(MapIndex.biome_at(img, Vector2i(1, 0)), -1, "white is water/none")
	assert_eq(MapIndex.biome_at(img, Vector2i(5, 0)), -1, "out of bounds")
```

Append to `tests/engine/test_map_geometry.gd`:

```gdscript

func test_bounds_wraps_every_point() -> void:
	var r := MapGeometry.bounds(PackedVector2Array([Vector2(1, 2), Vector2(3, -1), Vector2(2, 0)]))
	assert_eq(r.position, Vector2(1, -1))
	assert_eq(r.end, Vector2(3, 2))

func test_bounds_of_nothing_is_empty() -> void:
	assert_eq(MapGeometry.bounds(PackedVector2Array()), Rect2())
```

- [x] **Step 2: Write the failing data tests**

Append to `tests/engine/test_map_data.gd`:

```gdscript

## Map objects (spec 2026-09-08): routes, rivers, markers, biomes, map info,
## plus the province and biome index bitmaps, all from tools/import_azgaar.gd.
func test_map_object_tables_load() -> void:
	assert_gt(repo.routes.size(), 0, "routes.csv loaded")
	assert_gt(repo.rivers.size(), 0, "rivers.csv loaded")
	assert_gt(repo.markers.size(), 0, "markers.csv loaded")
	assert_gt(repo.biomes.size(), 0, "biomes.csv loaded")
	assert_eq(String(repo.map_info.get("distance_unit", "")), "km", "map_info.csv carries the unit")

func test_burgs_carry_type_and_features() -> void:
	var k: Dictionary = repo.burgs["kuojarpan"]
	assert_eq(String(k["type"]), "Naval")
	assert_eq(String(k["features"]), "walls|citadel|temple|plaza")

func test_route_and_river_references_resolve() -> void:
	for code: String in repo.routes:
		var r: Dictionary = repo.routes[code]
		for end in ["from_burg", "to_burg"]:
			var b := String(r[end])
			assert_true(b == "" or repo.burgs.has(b), "%s %s -> '%s'" % [code, end, b])
		assert_gte((r["polyline"] as PackedVector2Array).size(), 2, "%s is drawable" % code)
		assert_true((r["bbox"] as Rect2).has_area(), "%s has a bounding box" % code)
	for code: String in repo.rivers:
		var rv: Dictionary = repo.rivers[code]
		assert_gte((rv["polyline"] as PackedVector2Array).size(), 2, "%s is drawable" % code)
		for k: String in String(rv["kingdom_codes"]).split("|", false):
			assert_true(repo.kingdoms.has(k), "%s flows through %s" % [code, k])

func test_a_known_road_snaps_to_its_towns() -> void:
	var r: Dictionary = repo.routes["ororeanian_road"]
	assert_eq(String(r["group"]), "roads")
	assert_eq(String(r["from_burg"]), "cocalomo")
	assert_eq(String(r["to_burg"]), "ororeanes")

func test_markers_lie_inside_the_map_and_carry_legends() -> void:
	var w := float(repo.map_info["width"])
	var h := float(repo.map_info["height"])
	for code: String in repo.markers:
		var m: Dictionary = repo.markers[code]
		var x := float(m["x"])
		var y := float(m["y"])
		assert_true(x >= 0.0 and x <= w and y >= 0.0 and y <= h, "%s at (%s, %s)" % [code, x, y])
		assert_false(String(m["legend"]).contains("\n"), "%s legend is one line" % code)
	assert_true(repo.markers.has("the_orange_jackal"), "a named inn imported")

func test_province_bitmap_decodes_each_province_at_its_center() -> void:
	var img: Image = (load(repo.province_texture_path) as Texture2D).get_image()
	var state_img: Image = (load(repo.index_texture_path) as Texture2D).get_image()
	assert_eq(img.get_size(), state_img.get_size(), "province bitmap matches the state bitmap")
	for code: String in repo.provinces:
		var p: Dictionary = repo.provinces[code]
		var px := Vector2i(int(float(p["center_x"])), int(float(p["center_y"])))
		assert_eq(MapIndex.id_at(img, px), int(p["province_id"]),
			"%s center pixel decodes to its province_id" % code)

func test_biome_bitmap_marks_land_with_a_real_biome() -> void:
	var img: Image = (load(repo.biome_texture_path) as Texture2D).get_image()
	var state_img: Image = (load(repo.index_texture_path) as Texture2D).get_image()
	assert_eq(img.get_size(), state_img.get_size(), "biome bitmap matches the state bitmap")
	for code: String in repo.kingdoms:
		var row: Dictionary = repo.kingdoms[code]
		var px := Vector2i(int(float(row["center_x"])), int(float(row["center_y"])))
		var biome := MapIndex.biome_at(img, px)
		assert_true(biome > 0 and repo.biomes.has(biome),
			"%s center is land with a named biome, got %d" % [code, biome])
```

- [x] **Step 3: Run the map tests to verify they fail**

Run: `gut.sh map`
Expected: failures/errors naming `id_at`, `biome_at`, `bounds`, `routes`, `province_texture_path` as missing.

- [x] **Step 4: Add the decoders and `bounds`**

Append to `scripts/engine/map_index.gd`:

```gdscript

## Generic decode for any two-byte index bitmap (states, provinces): the same
## encoding as state_at, which stays as the named alias.
static func id_at(img: Image, px: Vector2i) -> int:
	return state_at(img, px)

## The biome bitmap carries its id in R alone (13 biomes); white = none.
static func biome_at(img: Image, px: Vector2i) -> int:
	if img == null or px.x < 0 or px.y < 0 \
			or px.x >= img.get_width() or px.y >= img.get_height():
		return -1
	var c := img.get_pixelv(px)
	if c.r8 == 255 and c.g8 == 255 and c.b8 == 255:
		return -1
	return c.r8
```

Append to `scripts/engine/map_geometry.gd`:

```gdscript

## Axis-aligned bounds of a polyline (Rect2() for no points).
static func bounds(pts: PackedVector2Array) -> Rect2:
	if pts.is_empty():
		return Rect2()
	var r := Rect2(pts[0], Vector2.ZERO)
	for p in pts:
		r = r.expand(p)
	return r
```

- [x] **Step 5: Extend the importer**

In `tools/import_azgaar.gd`:

5a. Header doc — replace the outputs list (lines 7–16) with:

```gdscript
##   data/maps/<map-id>/kingdoms.csv   one row per state (0 "Neutrals" excluded)
##   data/maps/<map-id>/provinces.csv  one row per province (+ province_id, center)
##   data/maps/<map-id>/burgs.csv      one row per burg (+ type, features)
##   data/maps/<map-id>/borders.csv    one row per closed border loop per kingdom:
##       kingdom_code,loop,points — points as "x y|x y|..." in native map
##       coordinates, so WorldMapView can outline the hovered kingdom
##   data/maps/<map-id>/routes.csv     roads/trails/sea routes as polylines,
##       endpoints snapped to a burg within SNAP_RADIUS px
##   data/maps/<map-id>/rivers.csv     named rivers as polylines through their cells
##   data/maps/<map-id>/markers.csv    points of interest with their legend notes
##   data/maps/<map-id>/biomes.csv     biome id -> label, color, habitability
##   data/maps/<map-id>/map_info.csv   width, height, distance unit/scale, population rate
##   assets/maps/<map-id>/world_map.png byte copy under a stable name
##   assets/maps/<map-id>/world_state_index.png     hit-test bitmap: each cell's
##       polygon filled with R = state_id & 0xFF, G = state_id >> 8, B = 0;
##       untouched pixels stay white (255,255,255) = water / no state
##   assets/maps/<map-id>/world_province_index.png  same encoding, province id
##   assets/maps/<map-id>/world_biome_index.png     R = biome id (land cells only)
```

5b. Constants — replace `GENERATED_PNGS` and add the snap radius and a whitespace regex:

```gdscript
const GENERATED_PNGS: Array[String] = ["world_map.png", "world_state_index.png",
	"world_province_index.png", "world_biome_index.png"]
## A route endpoint this close (native px) to a burg is "at" that burg.
const SNAP_RADIUS := 3.0

var _slug_regex := RegEx.create_from_string("[^a-z0-9]+")
var _ws_regex := RegEx.create_from_string("\\s+")
```

5c. Helpers — add after `_take_slug`:

```gdscript
## "hot-springs" -> "Hot springs" (first letter only; the rest stays as authored).
func _humanize(kind: String) -> String:
	var t := kind.replace("-", " ").replace("_", " ")
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else ""


func _collapse_ws(text: String) -> String:
	return _ws_regex.sub(text, " ", true).strip_edges()


## The nearest burg id within `radius` native px of (x, y), else -1. Ties go
## to the earlier burg, so output is stable.
func _burg_within(burgs: Array[Dictionary], x: float, y: float, radius: float) -> int:
	var best := -1
	var best_d := radius * radius
	for b in burgs:
		var dx := float(b["x"]) - x
		var dy := float(b["y"]) - y
		var d := dx * dx + dy * dy
		if d < best_d or (d == best_d and best < 0):
			best_d = d
			best = int(b["i"])
	return best


## Rasterize every cell whose id_of(cell) >= 0 into an RGB8 image with the
## two-byte encoding (R = id & 0xFF, G = id >> 8); untouched pixels white.
func _rasterize(cells: Array, vertices: Array, width: int, height: int,
		id_of: Callable) -> Image:
	var buf := PackedByteArray()
	buf.resize(width * height * 3)
	buf.fill(255)
	for c: Dictionary in cells:
		var id := int(id_of.call(c))
		if id < 0:
			continue
		var px := PackedFloat64Array()
		var py := PackedFloat64Array()
		for v in (c["v"] as Array):
			var vp: Array = (vertices[int(v)] as Dictionary)["p"]
			px.append(float(vp[0]))
			py.append(float(vp[1]))
		_fill_polygon(buf, width, height, px, py, id)
	return Image.create_from_data(width, height, false, Image.FORMAT_RGB8, buf)


func _save_png(img: Image, path: String) -> bool:
	if img.save_png(ProjectSettings.globalize_path(path)) != OK:
		push_error("error: cannot write %s" % path)
		return false
	return true
```

5d. provinces.csv — replace the header line and row emission:

```gdscript
	out = _csv_line(["province_code", "label", "kingdom_code", "capital_burg",
		"area", "population", "province_id", "center_x", "center_y"])
	for p in provinces:
		var pcenter: Array = (cells[int(p["center"])] as Dictionary)["p"]
		out += _csv_line([String(prov_code[int(p["i"])]), String(p["name"]),
			String(state_code[int(p["state"])]),
			String(burg_code.get(int(p.get("burg", 0)), "")),
			str(int(prov_area[int(p["i"])])),
			str(int(round(float(prov_pop[int(p["i"])]) * rate))),
			str(int(p["i"])), _num2(float(pcenter[0])), _num2(float(pcenter[1]))])
```

5e. burgs.csv — replace header and row emission:

```gdscript
	out = _csv_line(["burg_code", "label", "province_code", "kingdom_code",
		"population", "is_capital", "is_port", "x", "y", "type", "features"])
	for b in burgs:
		var feats: Array[String] = []
		for flag in ["walls", "citadel", "temple", "plaza", "shanty"]:
			if b.get(flag):
				feats.append(flag)
		out += _csv_line([String(burg_code[int(b["i"])]), String(b["name"]),
			String(prov_code[burg_province[int(b["i"])]]),
			String(state_code[int(b["state"])]),
			str(int(round(float(b.get("population", 0)) * rate))),
			"1" if b.get("capital") else "0", "1" if b.get("port") else "0",
			_num2(float(b["x"])), _num2(float(b["y"])),
			String(b.get("type", "Generic")), "|".join(feats)])
```

5f. New tables — insert after the borders.csv block and before `# --- bitmaps`:

```gdscript
	# --- routes.csv -------------------------------------------------------
	out = _csv_line(["route_code", "label", "group", "from_burg", "to_burg", "length", "points"])
	var route_slugs: Dictionary = {}
	var routes := _active(pack.get("routes", []))
	for r in routes:
		var raw: Array = r.get("points", [])
		if raw.size() < 2:
			push_error("error: route %d has fewer than 2 points" % int(r.get("i", -1)))
			return 1
		var pts: Array[String] = []
		var length := 0.0
		var lx := 0.0
		var ly := 0.0
		for i in raw.size():
			var pt: Array = raw[i]
			var x := float(pt[0])
			var y := float(pt[1])
			if i > 0:
				length += sqrt((x - lx) * (x - lx) + (y - ly) * (y - ly))
			lx = x
			ly = y
			pts.append("%s %s" % [_num2(x), _num2(y)])
		var first: Array = raw[0]
		var last: Array = raw[raw.size() - 1]
		var from_id := _burg_within(burgs, float(first[0]), float(first[1]), SNAP_RADIUS)
		var to_id := _burg_within(burgs, float(last[0]), float(last[1]), SNAP_RADIUS)
		var label := String(r.get("name", ""))
		out += _csv_line([_take_slug(route_slugs, label), label, String(r.get("group", "")),
			String(burg_code.get(from_id, "")), String(burg_code.get(to_id, "")),
			String.num(length, 1), "|".join(pts)])
	if not _write_text(out_data + "/routes.csv", out):
		return 1

	# --- rivers.csv -------------------------------------------------------
	out = _csv_line(["river_code", "label", "type", "length", "kingdom_codes", "points"])
	var river_slugs: Dictionary = {}
	var river_count := 0
	for rv in _active(pack.get("rivers", [])):
		var rcells: Array = rv.get("cells", [])
		if rcells.size() < 2:
			continue  # a one-cell river has no line to draw
		var pts: Array[String] = []
		var through: Array[String] = []
		var length := 0.0
		var lx := 0.0
		var ly := 0.0
		for i in rcells.size():
			var c: Dictionary = cells[int(rcells[i])]
			var cp: Array = c["p"]
			var x := float(cp[0])
			var y := float(cp[1])
			if i > 0:
				length += sqrt((x - lx) * (x - lx) + (y - ly) * (y - ly))
			lx = x
			ly = y
			pts.append("%s %s" % [_num2(x), _num2(y)])
			var sid := int(c.get("state", 0))
			if state_code.has(sid) and not through.has(String(state_code[sid])):
				through.append(String(state_code[sid]))
		var label := String(rv.get("name", ""))
		out += _csv_line([_take_slug(river_slugs, label), label, String(rv.get("type", "River")),
			String.num(length, 1), "|".join(through), "|".join(pts)])
		river_count += 1
	if not _write_text(out_data + "/rivers.csv", out):
		return 1

	# --- markers.csv ------------------------------------------------------
	var notes: Dictionary = {}
	for n in (world.get("notes", []) as Array):
		if n is Dictionary:
			notes[String((n as Dictionary).get("id", ""))] = n
	out = _csv_line(["marker_code", "label", "type", "x", "y", "legend"])
	var marker_slugs: Dictionary = {}
	var unnoted := 0
	var markers := _active(pack.get("markers", []))
	for m in markers:
		if not m.has("x") or not m.has("y"):
			push_error("error: marker %d has no coordinates" % int(m.get("i", -1)))
			return 1
		var note: Dictionary = notes.get("marker%d" % int(m["i"]), {})
		if note.is_empty():
			unnoted += 1
		var label := String(note.get("name", _humanize(String(m.get("type", "marker")))))
		out += _csv_line([_take_slug(marker_slugs, label), label, String(m.get("type", "")),
			_num2(float(m["x"])), _num2(float(m["y"])),
			_collapse_ws(String(note.get("legend", "")))])
	if not _write_text(out_data + "/markers.csv", out):
		return 1
	if unnoted > 0:
		print("WARNING: %d markers have no note; their type stands in as the label" % unnoted)

	# --- biomes.csv -------------------------------------------------------
	out = _csv_line(["biome_id", "label", "color", "habitability"])
	for bm in _active(pack.get("biomes", [])):
		out += _csv_line([str(int(bm["i"])), String(bm["name"]), String(bm.get("color", "")),
			str(int(bm.get("habitability", 0)))])
	if not _write_text(out_data + "/biomes.csv", out):
		return 1

	# --- map_info.csv -----------------------------------------------------
	var settings: Dictionary = world["settings"]
	out = _csv_line(["key", "value"])
	out += _csv_line(["width", str(width)])
	out += _csv_line(["height", str(height)])
	out += _csv_line(["distance_unit", String(settings.get("distanceUnit", "km"))])
	out += _csv_line(["distance_scale", _num2(float(settings.get("distanceScale", 1)))])
	out += _csv_line(["population_rate", _num2(rate)])
	if not _write_text(out_data + "/map_info.csv", out):
		return 1
```

5g. Bitmaps — replace the whole `# --- bitmaps` block (from `DirAccess.copy_absolute` through the `world_state_index.png` error return) with:

```gdscript
	# --- bitmaps ----------------------------------------------------------
	DirAccess.copy_absolute(ProjectSettings.globalize_path(png_path),
		ProjectSettings.globalize_path(out_art + "/world_map.png"))
	var state_img := _rasterize(cells, vertices, width, height, func(c: Dictionary) -> int:
		var sid := int(c.get("state", 0))
		return sid if state_code.has(sid) else -1)
	if not _save_png(state_img, out_art + "/world_state_index.png"):
		return 1
	var province_img := _rasterize(cells, vertices, width, height, func(c: Dictionary) -> int:
		var pid := int(c.get("province", 0))
		return pid if prov_code.has(pid) else -1)
	if not _save_png(province_img, out_art + "/world_province_index.png"):
		return 1
	var biome_img := _rasterize(cells, vertices, width, height, func(c: Dictionary) -> int:
		var bid := int(c.get("biome", 0))
		return bid if bid > 0 else -1)
	if not _save_png(biome_img, out_art + "/world_biome_index.png"):
		return 1
```

5h. Report — replace the final `print("map '%s': ...` with:

```gdscript
	print("map '%s': wrote %d kingdoms, %d provinces, %d burgs, %d border loops, %d routes, %d rivers, %d markers into %s, art into %s"
		% [map_id, states.size(), provinces.size(), burgs.size(), loop_total,
			routes.size(), river_count, markers.size(), out_data, out_art])
```

- [x] **Step 6: Point maps.csv at the new bitmaps**

Replace `data/maps.csv` with:

```csv
map_id,label,map_texture,index_texture,province_texture,biome_texture,data_dir,is_default,notes
beria,Beria,res://assets/maps/beria/world_map.png,res://assets/maps/beria/world_state_index.png,res://assets/maps/beria/world_province_index.png,res://assets/maps/beria/world_biome_index.png,res://data/maps/beria,1,The founding world. Azgaar export 2026-09-03.
```

- [x] **Step 7: Load the new tables in DataRepository**

In `scripts/engine/data_repository.gd`, after `var borders: Dictionary = {}` add:

```gdscript
## Map objects (spec 2026-09-08), keyed by *_code. Route and river rows carry
## two derived fields set at load: polyline (PackedVector2Array) and bbox
## (Rect2), so hit-testing never re-parses text.
var routes: Dictionary = {}
var rivers: Dictionary = {}
var markers: Dictionary = {}
## biome_id (int) -> row.
var biomes: Dictionary = {}
## width/height/distance_unit/distance_scale/population_rate as strings.
var map_info: Dictionary = {}
```

After `var index_texture_path: String = ""` add:

```gdscript
var province_texture_path: String = ""
var biome_texture_path: String = ""
```

In `load_map`, after `borders.clear()` add:

```gdscript
	routes.clear()
	rivers.clear()
	markers.clear()
	biomes.clear()
	map_info.clear()
```

After the `borders.csv` `_load_if_present` block add:

```gdscript
	if not _load_if_present(dir + "/routes.csv",
			["route_code", "label", "group", "from_burg", "to_burg", "length", "points"],
			func(r): routes[r["route_code"]] = _with_polyline(r)):
		return false
	if not _load_if_present(dir + "/rivers.csv",
			["river_code", "label", "type", "length", "kingdom_codes", "points"],
			func(r): rivers[r["river_code"]] = _with_polyline(r)):
		return false
	if not _load_if_present(dir + "/markers.csv",
			["marker_code", "label", "type", "x", "y", "legend"],
			func(r): markers[r["marker_code"]] = r):
		return false
	if not _load_if_present(dir + "/biomes.csv", ["biome_id", "label"],
			func(r): biomes[int(r["biome_id"])] = r):
		return false
	if not _load_if_present(dir + "/map_info.csv", ["key", "value"],
			func(r): map_info[r["key"]] = r["value"]):
		return false
```

After `index_texture_path = String(m["index_texture"])` add:

```gdscript
	province_texture_path = String(m.get("province_texture", ""))
	biome_texture_path = String(m.get("biome_texture", ""))
```

After `_add_border_loop` add:

```gdscript
func _with_polyline(r: Dictionary) -> Dictionary:
	var pts := MapGeometry.parse_points(String(r["points"]))
	r["polyline"] = pts
	r["bbox"] = MapGeometry.bounds(pts)
	return r
```

- [x] **Step 8: Regenerate the pack and verify byte-identical untouched outputs**

Run:
```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/import_azgaar.gd 2>&1 | grep "map '" 
git status --short data assets
```
Expected: the report line lists 16 kingdoms, 249 provinces, 840 burgs, 33 border loops, 677 routes, ~224 rivers, 66 markers. `git status` shows `world_map.png`, `world_state_index.png`, `kingdoms.csv`, `borders.csv` **unmodified**; `provinces.csv`, `burgs.csv` modified (new columns only); new `routes.csv`, `rivers.csv`, `markers.csv`, `biomes.csv`, `map_info.csv`, `world_province_index.png`, `world_biome_index.png`.

Then run `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import` and confirm the generated `assets/maps/beria/world_province_index.png.import` and `world_biome_index.png.import` contain `compress/mode=0` and `mipmaps/generate=false` (lossless, so `get_image()` returns exact ids). If either differs, copy the `[params]` section from `world_state_index.png.import` into it and re-run `--import`.

- [x] **Step 9: Run the map tests to verify they pass**

Run: `gut.sh map`
Expected: `All tests passed!`.

- [x] **Step 10: Full suite, then commit**

Run: `./run_tests.sh` → `All tests passed!`, exit 0.

```bash
git add tools/import_azgaar.gd data/maps.csv data/maps/beria assets/maps/beria \
  scripts/engine/map_index.gd scripts/engine/map_geometry.gd scripts/engine/data_repository.gd \
  tests/engine/test_map_index.gd tests/engine/test_map_geometry.gd tests/engine/test_map_data.gd
git commit -m "feat(map): import routes, rivers, markers, biomes, and province/biome bitmaps

The importer now emits every layer the map objects need as data: routes.csv
(roads/trails/sea routes as polylines, endpoints snapped to a burg within 3
px), rivers.csv (cell-center polylines with the kingdoms they cross),
markers.csv (Azgaar's points of interest with their legend notes collapsed
to one line), biomes.csv, map_info.csv (distance unit/scale for real
distances on cards), and two more index bitmaps sharing the state bitmap's
rasterizer: province ids and biome ids. burgs.csv gains type and a features
flag list; provinces.csv gains its Azgaar id and center for the bitmap join.
DataRepository loads it all through _load_if_present and parses each
polyline once, with a bounding box, at load.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019HggsFraqfeKGW6RHNys5E"
```

---

### Task 2: MapGeometry line math, MapObjects hit-test and card text

**Files:**
- Modify: `scripts/engine/map_geometry.gd`
- Create: `scripts/engine/map_objects.gd`
- Modify: `data/balance.csv`
- Test: `tests/engine/test_map_geometry.gd`, create `tests/engine/test_map_objects.gd`

**Interfaces:**
- Consumes: Task 1's repository fields and `MapIndex.id_at` / `biome_at`.
- Produces:
  - `MapGeometry.polyline_length(pts: PackedVector2Array) -> float`, `MapGeometry.distance_to_polyline(p: Vector2, pts: PackedVector2Array) -> float` (INF for no points).
  - `MapObjects.CAPITALS_ONLY := -1`
  - `MapObjects.min_burg_pop_for_scale(repo: DataRepository, view_scale: float) -> int`
  - `MapObjects.burg_visible(b: Dictionary, min_pop: int) -> bool`
  - `MapObjects.object_at(repo, state_img: Image, province_img: Image, biome_img: Image, native: Vector2, pick_radius: float, line_radius: float, min_burg_pop: int) -> Dictionary` — returns `{kind: "marker"|"burg"|"route"|"river", code}` or `{kind: "land", state_id, province_id, biome_id, x, y}` or `{kind: "water"}`.
  - `MapObjects.nearest_burg(repo, native: Vector2) -> String`
  - `MapObjects.label_of(repo, obj: Dictionary) -> String`
  - `MapObjects.describe(repo, obj: Dictionary) -> Dictionary` — `{title: String, lines: Array[String], ask: String}`, `{}` for water/unknown.
  - Balance keys: `map_lod_town_scale`, `map_lod_village_scale`, `map_lod_marker_scale`, `map_lod_town_pop`, `map_pick_radius_px`, `map_line_pick_px`.

- [x] **Step 1: Write the failing geometry tests**

Append to `tests/engine/test_map_geometry.gd`:

```gdscript

func test_polyline_length_sums_the_segments() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(3, 4), Vector2(3, 10)])
	assert_almost_eq(MapGeometry.polyline_length(pts), 11.0, 0.0001)
	assert_eq(MapGeometry.polyline_length(PackedVector2Array([Vector2(1, 1)])), 0.0)

func test_distance_to_polyline_is_to_the_nearest_segment() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2)])
	assert_almost_eq(MapGeometry.distance_to_polyline(Vector2(1, 1), pts), 1.0, 0.0001,
		"one unit above the first segment (and one left of the second)")
	assert_almost_eq(MapGeometry.distance_to_polyline(Vector2(5, 0), pts), 3.0, 0.0001,
		"past the corner: distance to the corner vertex")
	assert_almost_eq(MapGeometry.distance_to_polyline(Vector2(2, 1), pts), 0.0, 0.0001, "on the line")

func test_distance_to_nothing_is_infinite() -> void:
	assert_eq(MapGeometry.distance_to_polyline(Vector2.ZERO, PackedVector2Array()), INF)
```

- [x] **Step 2: Write the failing MapObjects tests**

Create `tests/engine/test_map_objects.gd`:

```gdscript
extends GutTest
## MapObjects: what lies under a map point (pin > line > land > water), the
## zoom-based LOD rule for town pins, and the text each info card shows.
## Engine-pure: a hand-built repository and 4x4 bitmaps for the unit cases,
## the real Beria pack for the integration cases.

var real: DataRepository

func before_all() -> void:
	real = DataRepository.load_all("res://data")
	assert_not_null(real, DataRepository.last_error)

## A 4x4 world: state 6 / province 72 / biome 6 on the left half, water right.
## Capital "cap" at (0.5, 0.5), village "vil" at (1.5, 2.5) with 300 people,
## road "rd" from cap to vil, marker "inn" exactly on the village.
func _tiny() -> DataRepository:
	var repo := DataRepository.new()
	repo.balance = {"map_lod_town_scale": 0.5, "map_lod_village_scale": 1.0,
		"map_lod_marker_scale": 0.5, "map_lod_town_pop": 5000.0,
		"map_pick_radius_px": 6.0, "map_line_pick_px": 4.0}
	repo.map_info = {"distance_unit": "km", "distance_scale": "2", "width": "4", "height": "4"}
	repo.kingdoms = {"k": {"kingdom_code": "k", "state_id": "6", "label": "Kingdom", "capital_burg": "cap",
		"neighbor_codes": "", "population": "9000", "center_x": "0", "center_y": "0"}}
	repo.provinces = {"p": {"province_code": "p", "label": "Province", "kingdom_code": "k",
		"capital_burg": "cap", "province_id": "72"}}
	repo.burgs = {
		"cap": {"burg_code": "cap", "label": "Capital", "province_code": "p", "kingdom_code": "k",
			"population": "8000", "is_capital": "1", "is_port": "1", "x": "0.5", "y": "0.5",
			"type": "Naval", "features": "walls|citadel"},
		"vil": {"burg_code": "vil", "label": "Village", "province_code": "p", "kingdom_code": "k",
			"population": "300", "is_capital": "0", "is_port": "0", "x": "1.5", "y": "2.5",
			"type": "Generic", "features": ""},
	}
	var road := {"route_code": "rd", "label": "Old Road", "group": "roads", "from_burg": "cap",
		"to_burg": "vil", "length": "2.2", "points": "0.5 0.5|1.5 2.5"}
	road["polyline"] = MapGeometry.parse_points(String(road["points"]))
	road["bbox"] = MapGeometry.bounds(road["polyline"])
	repo.routes = {"rd": road}
	var river := {"river_code": "rv", "label": "Silver", "type": "River", "length": "3",
		"kingdom_codes": "k", "points": "0 3.5|3 3.5"}
	river["polyline"] = MapGeometry.parse_points(String(river["points"]))
	river["bbox"] = MapGeometry.bounds(river["polyline"])
	repo.rivers = {"rv": river}
	repo.markers = {"inn": {"marker_code": "inn", "label": "The Inn", "type": "inns",
		"x": "1.5", "y": "2.5", "legend": "A warm hearth."}}
	repo.biomes = {6: {"biome_id": "6", "label": "Forest", "color": "", "habitability": "50"}}
	return repo

func _bitmap(id: int) -> Image:
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color8(255, 255, 255))
	for y in 4:
		for x in 2:
			img.set_pixel(x, y, Color8(id & 0xFF, (id >> 8) & 0xFF, 0))
	return img

func _at(repo: DataRepository, p: Vector2, min_pop: int) -> Dictionary:
	return MapObjects.object_at(repo, _bitmap(6), _bitmap(72), _bitmap(6), p, 0.3, 0.2, min_pop)

func test_lod_rule_from_balance() -> void:
	var repo := _tiny()
	assert_eq(MapObjects.min_burg_pop_for_scale(repo, 0.3), MapObjects.CAPITALS_ONLY)
	assert_eq(MapObjects.min_burg_pop_for_scale(repo, 0.5), 5000)
	assert_eq(MapObjects.min_burg_pop_for_scale(repo, 1.0), 0)

func test_burg_visible_respects_capitals_and_population() -> void:
	var repo := _tiny()
	assert_true(MapObjects.burg_visible(repo.burgs["cap"], MapObjects.CAPITALS_ONLY))
	assert_false(MapObjects.burg_visible(repo.burgs["vil"], MapObjects.CAPITALS_ONLY))
	assert_false(MapObjects.burg_visible(repo.burgs["vil"], 5000))
	assert_true(MapObjects.burg_visible(repo.burgs["vil"], 0))

func test_marker_beats_a_burg_at_the_same_spot() -> void:
	var hit := _at(_tiny(), Vector2(1.5, 2.5), 0)
	assert_eq(hit["kind"], "marker")
	assert_eq(hit["code"], "inn")

func test_capital_pin_is_picked_within_radius() -> void:
	var hit := _at(_tiny(), Vector2(0.7, 0.5), MapObjects.CAPITALS_ONLY)
	assert_eq(hit["kind"], "burg")
	assert_eq(hit["code"], "cap")

func test_hidden_village_falls_through_to_the_road_under_it() -> void:
	# The marker sits on the village too; pick a road point away from both.
	var hit := _at(_tiny(), Vector2(1.0, 1.5), MapObjects.CAPITALS_ONLY)
	assert_eq(hit["kind"], "route")
	assert_eq(hit["code"], "rd")

func test_river_is_picked_when_no_route_is_closer() -> void:
	var hit := _at(_tiny(), Vector2(1.0, 3.6), 0)
	assert_eq(hit["kind"], "river")
	assert_eq(hit["code"], "rv")

func test_bare_land_reports_its_ids_and_position() -> void:
	var hit := _at(_tiny(), Vector2(0.5, 2.0), 0)
	assert_eq(hit["kind"], "land")
	assert_eq(hit["state_id"], 6)
	assert_eq(hit["province_id"], 72)
	assert_eq(hit["biome_id"], 6)
	assert_almost_eq(float(hit["x"]), 0.5, 0.0001)

func test_water_is_water() -> void:
	assert_eq(_at(_tiny(), Vector2(3.5, 1.0), 0)["kind"], "water")

func test_nearest_burg_ignores_lod() -> void:
	assert_eq(MapObjects.nearest_burg(_tiny(), Vector2(1.4, 2.4)), "vil")

func test_describe_burg() -> void:
	var d := MapObjects.describe(_tiny(), {"kind": "burg", "code": "cap"})
	assert_eq(d["title"], "Capital")
	assert_eq(d["lines"][0], "Capital of Province, Kingdom")
	assert_eq(d["lines"][1], "Population: 8000")
	assert_eq(d["lines"][2], "Port, Walled, Citadel")
	assert_eq(d["lines"][3], "Roads: 1")
	assert_eq(d["ask"], "What do we know of Capital?")

func test_describe_route_and_river_use_real_distances() -> void:
	var road := MapObjects.describe(_tiny(), {"kind": "route", "code": "rd"})
	assert_eq(road["title"], "Old Road")
	assert_eq(road["lines"][0], "Road")
	assert_eq(road["lines"][1], "From Capital to Village")
	assert_eq(road["lines"][2], "Length: 4 km", "2.2 px * scale 2, rounded")
	assert_eq(road["ask"], "What do we know of the Old Road?")
	var river := MapObjects.describe(_tiny(), {"kind": "river", "code": "rv"})
	assert_eq(river["lines"], ["River", "Length: 6 km", "Flows through: Kingdom"])

func test_describe_marker_and_land() -> void:
	var inn := MapObjects.describe(_tiny(), {"kind": "marker", "code": "inn"})
	assert_eq(inn["title"], "The Inn")
	assert_eq(inn["lines"], ["Inns", "A warm hearth."])
	assert_eq(inn["ask"], "What is known of The Inn?")
	var land := MapObjects.describe(_tiny(), {"kind": "land", "state_id": 6, "province_id": 72,
		"biome_id": 6, "x": 1.0, "y": 2.0})
	assert_eq(land["title"], "Province")
	assert_eq(land["lines"][0], "Kingdom")
	assert_eq(land["lines"][1], "Terrain: Forest")
	assert_eq(land["lines"][2], "Nearest town: Village (1 km)")
	assert_eq(land["lines"][3], "Capital: Capital", "the kingdom summary follows the local facts")
	assert_eq(land["ask"], "What do we know of Province?")

func test_describe_water_is_empty() -> void:
	assert_eq(MapObjects.describe(_tiny(), {"kind": "water"}), {})

func test_label_of_each_kind() -> void:
	var repo := _tiny()
	assert_eq(MapObjects.label_of(repo, {"kind": "burg", "code": "vil"}), "Village")
	assert_eq(MapObjects.label_of(repo, {"kind": "route", "code": "rd"}), "Old Road")
	assert_eq(MapObjects.label_of(repo, {"kind": "marker", "code": "inn"}), "The Inn")
	assert_eq(MapObjects.label_of(repo, {"kind": "water"}), "")

## Real pack: the player's capital and a known road resolve where the export
## says they are.
func test_real_capital_and_road_resolve() -> void:
	var state_img: Image = (load(real.index_texture_path) as Texture2D).get_image()
	var prov_img: Image = (load(real.province_texture_path) as Texture2D).get_image()
	var biome_img: Image = (load(real.biome_texture_path) as Texture2D).get_image()
	var k: Dictionary = real.burgs["kuojarpan"]
	var at_capital := MapObjects.object_at(real, state_img, prov_img, biome_img,
		Vector2(float(k["x"]), float(k["y"])), 6.0, 4.0, MapObjects.CAPITALS_ONLY)
	assert_eq(at_capital["kind"], "burg")
	assert_eq(at_capital["code"], "kuojarpan")
	var on_road := MapObjects.object_at(real, state_img, prov_img, biome_img,
		Vector2(560.33, 322.71), 0.5, 4.0, MapObjects.CAPITALS_ONLY)
	assert_eq(on_road["kind"], "route")
	assert_eq(on_road["code"], "ororeanian_road")
	var d := MapObjects.describe(real, at_capital)
	assert_eq(d["title"], "Kuojarpan")
	assert_eq(d["lines"][0], "Capital of Onjormaa, Hetalia")
```

- [x] **Step 3: Run to verify failure**

Run: `gut.sh map_`
Expected: `test_map_objects.gd` ignored with "MapGeometry.polyline_length"/"MapObjects" parse errors; geometry tests fail on missing functions.

- [x] **Step 4: Add the balance rows**

Append to `data/balance.csv`:

```csv
map_lod_town_scale,0.5,world map: screen px per native map px at/above which towns with map_lod_town_pop+ people get a pin (below: capitals only)
map_lod_village_scale,1.0,world map: scale at/above which every burg gets a pin
map_lod_marker_scale,0.5,world map: scale at/above which points of interest get a pin
map_lod_town_pop,5000,world map: population a non-capital needs for a pin between the town and village scales
map_pick_radius_px,6,world map: screen px within which a click/hover picks a pin
map_line_pick_px,4,world map: screen px within which a click/hover picks a road or river
```

- [x] **Step 5: Add the geometry functions**

Append to `scripts/engine/map_geometry.gd`:

```gdscript

static func polyline_length(pts: PackedVector2Array) -> float:
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	return total

## Shortest distance from p to any segment of the polyline (INF if empty).
static func distance_to_polyline(p: Vector2, pts: PackedVector2Array) -> float:
	if pts.is_empty():
		return INF
	if pts.size() == 1:
		return p.distance_to(pts[0])
	var best := INF
	for i in range(1, pts.size()):
		var q := Geometry2D.get_closest_point_to_segment(p, pts[i - 1], pts[i])
		best = minf(best, p.distance_to(q))
	return best
```

- [x] **Step 6: Create MapObjects**

Create `scripts/engine/map_objects.gd`:

```gdscript
class_name MapObjects
extends RefCounted
## The world map's interactive objects (spec 2026-09-08): what lies under a
## point, which town pins show at a given zoom, and the text on each info
## card. Pure functions over a DataRepository and the pack's index bitmaps —
## no Nodes, no RNG, no game state — so GUT can pin every rule headless.
## Coordinates are native map px; the view converts screen radii by its scale.

## min_burg_pop sentinel: only capitals get pins.
const CAPITALS_ONLY := -1

const GROUP_WORDS := {"roads": "Road", "trails": "Trail", "searoutes": "Sea route"}
const FEATURE_WORDS := {"walls": "Walled", "citadel": "Citadel", "temple": "Temple",
	"plaza": "Plaza", "shanty": "Shanty town"}

## LOD rule from balance.csv. view_scale = screen px per native map px.
static func min_burg_pop_for_scale(repo: DataRepository, view_scale: float) -> int:
	if view_scale >= repo.bal("map_lod_village_scale"):
		return 0
	if view_scale >= repo.bal("map_lod_town_scale"):
		return int(repo.bal("map_lod_town_pop"))
	return CAPITALS_ONLY

static func burg_visible(b: Dictionary, min_pop: int) -> bool:
	if String(b.get("is_capital", "0")) == "1":
		return true
	if min_pop < 0:
		return false
	return int(float(b.get("population", "0"))) >= min_pop

## Priority: nearest pin (markers, then LOD-visible burgs) within pick_radius,
## else nearest line (routes, then rivers) within line_radius, else the land
## under the point (ids from the three bitmaps), else water.
static func object_at(repo: DataRepository, state_img: Image, province_img: Image,
		biome_img: Image, native: Vector2, pick_radius: float, line_radius: float,
		min_burg_pop: int) -> Dictionary:
	var pin := nearest_pin(repo, native, pick_radius, min_burg_pop)
	if not pin.is_empty():
		return pin
	var line := nearest_line(repo, native, line_radius)
	if not line.is_empty():
		return line
	var px := Vector2i(native.floor())
	var sid := MapIndex.state_at(state_img, px)
	if sid < 0:
		return {"kind": "water"}
	return {"kind": "land", "state_id": sid,
		"province_id": MapIndex.id_at(province_img, px),
		"biome_id": MapIndex.biome_at(biome_img, px),
		"x": native.x, "y": native.y}

static func nearest_pin(repo: DataRepository, native: Vector2, radius: float,
		min_burg_pop: int) -> Dictionary:
	var best := {}
	var best_d := radius
	for code: String in repo.markers:
		var m: Dictionary = repo.markers[code]
		var d := native.distance_to(Vector2(float(m["x"]), float(m["y"])))
		if d <= best_d:
			best_d = d
			best = {"kind": "marker", "code": code}
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		if not burg_visible(b, min_burg_pop):
			continue
		var d := native.distance_to(Vector2(float(b["x"]), float(b["y"])))
		if d < best_d:  # strict: a marker on the same spot keeps priority
			best_d = d
			best = {"kind": "burg", "code": code}
	return best

static func nearest_line(repo: DataRepository, native: Vector2, radius: float) -> Dictionary:
	var best := {}
	var best_d := radius
	for code: String in repo.routes:
		var d := _line_distance(repo.routes[code], native, radius)
		if d <= best_d:
			best_d = d
			best = {"kind": "route", "code": code}
	for code: String in repo.rivers:
		var d := _line_distance(repo.rivers[code], native, radius)
		if d < best_d:
			best_d = d
			best = {"kind": "river", "code": code}
	return best

static func _line_distance(row: Dictionary, native: Vector2, radius: float) -> float:
	var bbox: Rect2 = row["bbox"]
	if not bbox.grow(radius).has_point(native):
		return INF
	return MapGeometry.distance_to_polyline(native, row["polyline"])

## Closest burg regardless of LOD ("" if the pack has none).
static func nearest_burg(repo: DataRepository, native: Vector2) -> String:
	var best := ""
	var best_d := INF
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		var d := native.distance_to(Vector2(float(b["x"]), float(b["y"])))
		if d < best_d:
			best_d = d
			best = code
	return best

## Tooltip text: the object's name ("" for land/water, which have no pin).
static func label_of(repo: DataRepository, obj: Dictionary) -> String:
	match String(obj.get("kind", "")):
		"burg":
			return String(repo.burgs.get(obj["code"], {}).get("label", ""))
		"marker":
			return String(repo.markers.get(obj["code"], {}).get("label", ""))
		"route":
			return String(repo.routes.get(obj["code"], {}).get("label", ""))
		"river":
			return String(repo.rivers.get(obj["code"], {}).get("label", ""))
	return ""

## Card text per kind: {title, lines, ask}. {} means "nothing to show".
static func describe(repo: DataRepository, obj: Dictionary) -> Dictionary:
	match String(obj.get("kind", "")):
		"kingdom":
			return _describe_kingdom(repo, _kingdom_by_state(repo, int(obj.get("state_id", -1))))
		"burg":
			return _describe_burg(repo, String(obj["code"]))
		"route":
			return _describe_route(repo, String(obj["code"]))
		"river":
			return _describe_river(repo, String(obj["code"]))
		"marker":
			return _describe_marker(repo, String(obj["code"]))
		"land":
			return _describe_land(repo, obj)
	return {}

static func _kingdom_by_state(repo: DataRepository, sid: int) -> Dictionary:
	for row: Dictionary in repo.kingdoms.values():
		if int(row["state_id"]) == sid:
			return row
	return {}

static func _province_by_id(repo: DataRepository, pid: int) -> Dictionary:
	for row: Dictionary in repo.provinces.values():
		if int(row.get("province_id", -1)) == pid:
			return row
	return {}

static func _label(table: Dictionary, code: String) -> String:
	return String(table.get(code, {}).get("label", code))

## Native px -> "N unit" via map_info.csv (falls back to px when absent).
static func format_distance(repo: DataRepository, native_px: float) -> String:
	var scale := float(repo.map_info.get("distance_scale", "1"))
	var unit := String(repo.map_info.get("distance_unit", "px"))
	return "%d %s" % [roundi(native_px * scale), unit]

## The kingdom overview lines (the pre-2026-09-08 card, unchanged in content).
static func _kingdom_lines(repo: DataRepository, row: Dictionary) -> Array[String]:
	var code := String(row["kingdom_code"])
	var province_count := 0
	for p: Dictionary in repo.provinces.values():
		if String(p["kingdom_code"]) == code:
			province_count += 1
	var town_count := 0
	for b: Dictionary in repo.burgs.values():
		if String(b["kingdom_code"]) == code:
			town_count += 1
	var neighbors: Array[String] = []
	for n: String in String(row.get("neighbor_codes", "")).split("|", false):
		neighbors.append(_label(repo.kingdoms, n))
	var court: Array[String] = []
	for role: Dictionary in repo.roles:
		if String(role.get("kingdom", "")) == code:
			court.append(String(role["display_name"]))
	var lines: Array[String] = [
		"Capital: %s" % _label(repo.burgs, String(row.get("capital_burg", ""))),
		"Provinces: %d" % province_count,
		"Towns: %d" % town_count,
		"Population: %s" % row.get("population", "—"),
		"Neighbors: %s" % (", ".join(neighbors) if not neighbors.is_empty() else "—"),
	]
	if not court.is_empty():
		lines.append("Court: %s" % ", ".join(court))
	return lines

static func _describe_kingdom(repo: DataRepository, row: Dictionary) -> Dictionary:
	if row.is_empty():
		return {}
	var label := String(row["label"])
	return {"title": label, "lines": _kingdom_lines(repo, row),
		"ask": "What do we know of %s?" % label}

static func _describe_burg(repo: DataRepository, code: String) -> Dictionary:
	var b: Dictionary = repo.burgs.get(code, {})
	if b.is_empty():
		return {}
	var label := String(b["label"])
	var where := "%s, %s" % [_label(repo.provinces, String(b["province_code"])),
		_label(repo.kingdoms, String(b["kingdom_code"]))]
	var lines: Array[String] = []
	lines.append(("Capital of %s" if String(b.get("is_capital", "0")) == "1" else "Town in %s") % where)
	lines.append("Population: %s" % b.get("population", "—"))
	var traits: Array[String] = []
	if String(b.get("is_port", "0")) == "1":
		traits.append("Port")
	for f: String in String(b.get("features", "")).split("|", false):
		traits.append(String(FEATURE_WORDS.get(f, f.capitalize())))
	if not traits.is_empty():
		lines.append(", ".join(traits))
	var roads := 0
	for r: Dictionary in repo.routes.values():
		if String(r["from_burg"]) == code or String(r["to_burg"]) == code:
			roads += 1
	if roads > 0:
		lines.append("Roads: %d" % roads)
	return {"title": label, "lines": lines, "ask": "What do we know of %s?" % label}

static func _describe_route(repo: DataRepository, code: String) -> Dictionary:
	var r: Dictionary = repo.routes.get(code, {})
	if r.is_empty():
		return {}
	var label := String(r["label"])
	var lines: Array[String] = [String(GROUP_WORDS.get(String(r["group"]), "Route"))]
	var from := String(r["from_burg"])
	var to := String(r["to_burg"])
	if from != "" and to != "":
		lines.append("From %s to %s" % [_label(repo.burgs, from), _label(repo.burgs, to)])
	elif from != "" or to != "":
		lines.append("Ends at %s" % _label(repo.burgs, from if from != "" else to))
	lines.append("Length: %s" % format_distance(repo, float(r["length"])))
	return {"title": label, "lines": lines, "ask": "What do we know of the %s?" % label}

static func _describe_river(repo: DataRepository, code: String) -> Dictionary:
	var rv: Dictionary = repo.rivers.get(code, {})
	if rv.is_empty():
		return {}
	var label := String(rv["label"])
	var lines: Array[String] = [String(rv.get("type", "River")),
		"Length: %s" % format_distance(repo, float(rv["length"]))]
	var through: Array[String] = []
	for k: String in String(rv.get("kingdom_codes", "")).split("|", false):
		through.append(_label(repo.kingdoms, k))
	if not through.is_empty():
		lines.append("Flows through: %s" % ", ".join(through))
	return {"title": label, "lines": lines, "ask": "What do we know of the %s?" % label}

static func _describe_marker(repo: DataRepository, code: String) -> Dictionary:
	var m: Dictionary = repo.markers.get(code, {})
	if m.is_empty():
		return {}
	var label := String(m["label"])
	var lines: Array[String] = [humanize(String(m.get("type", "")))]
	var legend := String(m.get("legend", ""))
	if legend != "":
		lines.append(legend)
	return {"title": label, "lines": lines, "ask": "What is known of %s?" % label}

## Land: the province first, then terrain and the nearest town, then the
## kingdom overview so the old kingdom card stays one click away.
static func _describe_land(repo: DataRepository, obj: Dictionary) -> Dictionary:
	var kingdom := _kingdom_by_state(repo, int(obj.get("state_id", -1)))
	if kingdom.is_empty():
		return {}
	var province := _province_by_id(repo, int(obj.get("province_id", -1)))
	var title := String(province.get("label", kingdom["label"]))
	var lines: Array[String] = [String(kingdom["label"])]
	var biome: Dictionary = repo.biomes.get(int(obj.get("biome_id", -1)), {})
	if not biome.is_empty():
		lines.append("Terrain: %s" % biome["label"])
	var here := Vector2(float(obj.get("x", 0.0)), float(obj.get("y", 0.0)))
	var near := nearest_burg(repo, here)
	if near != "":
		var b: Dictionary = repo.burgs[near]
		var dist := here.distance_to(Vector2(float(b["x"]), float(b["y"])))
		lines.append("Nearest town: %s (%s)" % [b["label"], format_distance(repo, dist)])
	lines.append_array(_kingdom_lines(repo, kingdom))
	return {"title": title, "lines": lines, "ask": "What do we know of %s?" % title}

## "hot-springs" -> "Hot springs".
static func humanize(kind: String) -> String:
	var t := kind.replace("-", " ").replace("_", " ")
	return t.substr(0, 1).to_upper() + t.substr(1) if t != "" else ""
```

- [x] **Step 7: Import (new class), run, verify pass**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import` then `gut.sh map_`
Expected: `All tests passed!`. If `test_real_capital_and_road_resolve` fails on the route code, print `repo.routes.keys()` filtered for "ororeanian" and use the actual code in both the test and Task 1's `test_a_known_road_snaps_to_its_towns`.

- [x] **Step 8: Full suite, then commit**

Run: `./run_tests.sh` → green.

```bash
git add scripts/engine/map_geometry.gd scripts/engine/map_objects.gd scripts/engine/map_objects.gd.uid \
  data/balance.csv tests/engine/test_map_geometry.gd tests/engine/test_map_objects.gd tests/engine/test_map_objects.gd.uid
git commit -m "feat(map): MapObjects — hit-testing, LOD rule, and card text for map objects

Engine-pure: object_at picks the nearest pin (markers, then LOD-visible
burgs) within a radius, else the nearest road/river line, else the land
under the point from the state/province/biome bitmaps, else water. The LOD
rule and pick radii come from balance.csv. describe() builds every card's
title, lines, and Ask question, including the kingdom overview that used to
live in WorldMapView; a land click leads with province and terrain and
appends that overview so the kingdom card stays one click away.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019HggsFraqfeKGW6RHNys5E"
```

---

### Task 3: Pins, hover object, tooltip in WorldMapView

**Files:**
- Modify: `scripts/ui/world_map_view.gd`
- Test: `tests/ui/test_world_map_view.gd`

**Interfaces:**
- Consumes: `MapObjects.object_at/min_burg_pop_for_scale/burg_visible/label_of`, repository fields from Task 1.
- Produces on `WorldMapView`: `view_scale() -> float`, `hover_at(pos: Vector2) -> void` (screen coords; runs the same path as mouse motion), `hovered_object() -> Dictionary`, `hover_tooltip() -> String`, `visible_burg_count() -> int`.

- [x] **Step 1: Write the failing view tests**

Append to `tests/ui/test_world_map_view.gd`:

```gdscript

## Pins: capitals always; towns and villages appear as the player zooms in
## (thresholds in balance.csv, rule in MapObjects).
func test_town_pins_appear_as_the_view_zooms_in() -> void:
	var v := _view()
	await wait_frames(2)
	v._zoom_at(v.size / 2.0, 0.0001)
	var far := v.visible_burg_count()
	assert_eq(far, 16, "zoomed all the way out: one pin per capital")
	v._zoom_at(v.size / 2.0, 1000.0)
	assert_gt(v.view_scale(), Game.data.bal("map_lod_village_scale"))
	assert_eq(v.visible_burg_count(), Game.data.burgs.size(), "zoomed in: every burg")

func test_hovering_a_capital_names_it() -> void:
	var v := _view()
	await wait_frames(2)
	var k: Dictionary = Game.data.burgs["kuojarpan"]
	v.hover_at(v.map_to_screen(Vector2(float(k["x"]), float(k["y"]))))
	assert_eq(v.hovered_object().get("kind", ""), "burg")
	assert_eq(v.hovered_object().get("code", ""), "kuojarpan")
	assert_eq(v.tooltip_text(), "Kuojarpan")
	assert_eq(v.hovered_state(), int(Game.data.kingdoms["hetalia"]["state_id"]),
		"the kingdom outline stays on under a pin")

func test_hovering_open_sea_clears_the_tooltip() -> void:
	var v := _view()
	await wait_frames(2)
	var k: Dictionary = Game.data.burgs["kuojarpan"]
	v.hover_at(v.map_to_screen(Vector2(float(k["x"]), float(k["y"]))))
	v.hover_at(v.map_to_screen(Vector2(5.0, 5.0)))  # top-left ocean corner
	assert_eq(v.hovered_object().get("kind", ""), "water")
	assert_eq(v.tooltip_text(), "")
```

- [x] **Step 2: Run to verify failure**

Run: `gut.sh world_map`
Expected: errors for missing `visible_burg_count`, `hover_at`, `hovered_object`, `tooltip_text`, `view_scale`.

- [x] **Step 3: Implement pins, hover object, tooltip**

In `scripts/ui/world_map_view.gd`:

3a. Constants — after `HOVER_HALO` add:

```gdscript
## Pin sizes in screen px (constant at any zoom; LOD hides the small ones).
const PIN_CAPITAL := 4.0
const PIN_TOWN := 2.5
const PIN_VILLAGE := 1.5
const PIN_MARKER := 3.0
const PIN_OUTLINE := Color(0.05, 0.04, 0.02, 0.9)
const TOOLTIP_OFFSET := Vector2(10.0, 12.0)
```

3b. Fields — after `var _hover_sid := -1` add:

```gdscript
var _province_image: Image
var _biome_image: Image
## The pin/line/land under the mouse (MapObjects.object_at); {} before any hover.
var _hover_obj: Dictionary = {}
var _tooltip: Label
```

3c. `_ready` — after the `_index_image` load add:

```gdscript
	_province_image = _load_image(Game.data.province_texture_path)
	_biome_image = _load_image(Game.data.biome_texture_path)
```

and after `_build_card()` add `_build_tooltip()`. Add the helpers:

```gdscript
func _load_image(path: String) -> Image:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return (load(path) as Texture2D).get_image()

func _build_tooltip() -> void:
	_tooltip = Label.new()
	_tooltip.name = "Tooltip"
	_tooltip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip.add_theme_stylebox_override("normal", UiPalette.chip_style())
	_tooltip.add_theme_font_size_override("font_size", 8)
	_tooltip.add_theme_color_override("font_color", UiPalette.TEXT_SOFT)
	_tooltip.hide()
	add_child(_tooltip)
```

3d. `_draw` — after the hover-loop block add `_draw_pins()` and `_draw_hover()`, and add:

```gdscript
## Screen px per native map px — the LOD and pick radii are defined on it.
func view_scale() -> float:
	return _zoom * _render_scale

func _pin_radius(b: Dictionary) -> float:
	if String(b["is_capital"]) == "1":
		return PIN_CAPITAL
	return PIN_TOWN if int(float(b["population"])) >= int(Game.data.bal("map_lod_town_pop")) else PIN_VILLAGE

func _draw_pins() -> void:
	var s := view_scale()
	var min_pop := MapObjects.min_burg_pop_for_scale(Game.data, s)
	var on_screen := Rect2(Vector2.ZERO, size).grow(PIN_CAPITAL * 2.0)
	for code: String in Game.data.burgs:
		var b: Dictionary = Game.data.burgs[code]
		if not MapObjects.burg_visible(b, min_pop):
			continue
		var sp := map_to_screen(Vector2(float(b["x"]), float(b["y"])))
		if not on_screen.has_point(sp):
			continue
		var r := _pin_radius(b)
		draw_circle(sp, r + 1.0, PIN_OUTLINE)
		draw_circle(sp, r, UiPalette.GOLD)
		if String(b["is_capital"]) == "1":
			draw_arc(sp, r + 2.5, 0.0, TAU, 24, UiPalette.GOLD, 1.0, true)
	if s >= Game.data.bal("map_lod_marker_scale"):
		for code: String in Game.data.markers:
			var m: Dictionary = Game.data.markers[code]
			var sp := map_to_screen(Vector2(float(m["x"]), float(m["y"])))
			if on_screen.has_point(sp):
				_draw_diamond(sp, PIN_MARKER + 1.0, PIN_OUTLINE)
				_draw_diamond(sp, PIN_MARKER, UiPalette.TOOL_PERSONAL)

func _draw_diamond(center: Vector2, r: float, color: Color) -> void:
	draw_colored_polygon(PackedVector2Array([center + Vector2(0, -r), center + Vector2(r, 0),
		center + Vector2(0, r), center + Vector2(-r, 0)]), color)

## Ring around the hovered pin; halo + gold line along the hovered road/river.
func _draw_hover() -> void:
	_draw_object_highlight(_hover_obj)

func _draw_object_highlight(obj: Dictionary) -> void:
	match String(obj.get("kind", "")):
		"burg":
			var b: Dictionary = Game.data.burgs[obj["code"]]
			var sp := map_to_screen(Vector2(float(b["x"]), float(b["y"])))
			draw_arc(sp, _pin_radius(b) + 4.0, 0.0, TAU, 32, UiPalette.GOLD, 1.5, true)
		"marker":
			var m: Dictionary = Game.data.markers[obj["code"]]
			var sp := map_to_screen(Vector2(float(m["x"]), float(m["y"])))
			draw_arc(sp, PIN_MARKER + 4.0, 0.0, TAU, 32, UiPalette.GOLD, 1.5, true)
		"route", "river":
			var table: Dictionary = Game.data.routes if obj["kind"] == "route" else Game.data.rivers
			var pts: PackedVector2Array = table[obj["code"]]["polyline"]
			var screen := PackedVector2Array()
			screen.resize(pts.size())
			for i in pts.size():
				screen[i] = map_to_screen(pts[i])
			draw_polyline(screen, HOVER_HALO, HOVER_HALO_WIDTH, true)
			draw_polyline(screen, UiPalette.GOLD, HOVER_WIDTH, true)
```

3e. Hover plumbing — replace `_update_hover` with:

```gdscript
func _object_under(pos: Vector2) -> Dictionary:
	var s := view_scale()
	return MapObjects.object_at(Game.data, _index_image, _province_image, _biome_image,
		screen_to_map(pos), Game.data.bal("map_pick_radius_px") / s,
		Game.data.bal("map_line_pick_px") / s, MapObjects.min_burg_pop_for_scale(Game.data, s))

func _update_hover(pos: Vector2) -> void:
	hover_state(_state_under(pos))
	hover_object(_object_under(pos))
	_tooltip.position = pos + TOOLTIP_OFFSET

## Public for tests: the same path a mouse-motion event takes.
func hover_at(pos: Vector2) -> void:
	_update_hover(pos)

func hover_object(obj: Dictionary) -> void:
	if obj == _hover_obj:
		return
	_hover_obj = obj
	var label := MapObjects.label_of(Game.data, obj)
	_tooltip.text = label
	_tooltip.visible = label != ""
	queue_redraw()

func hovered_object() -> Dictionary:
	return _hover_obj

func hover_tooltip() -> String:
	return _tooltip.text if _tooltip.visible else ""

## Test seam: how many burgs pass the LOD rule at the current zoom.
func visible_burg_count() -> int:
	var min_pop := MapObjects.min_burg_pop_for_scale(Game.data, view_scale())
	var n := 0
	for b: Dictionary in Game.data.burgs.values():
		if MapObjects.burg_visible(b, min_pop):
			n += 1
	return n
```

3f. In the `mouse_exited` lambda also call `hover_object({})`.

3g. Update the class doc comment: after "gets its border outlined (borders.csv)," add "towns and points of interest show as pins (LOD by zoom, MapObjects), hovering a pin or road names it,".

- [x] **Step 4: Run to verify pass**

Run: `gut.sh world_map`
Expected: `All tests passed!` (the existing hover/select tests still pass).

- [x] **Step 5: Full suite, then commit**

```bash
git add scripts/ui/world_map_view.gd tests/ui/test_world_map_view.gd
git commit -m "feat(map): town and point-of-interest pins with zoom LOD, hover tooltip

The render labels towns but paints no icons, so the view draws its own:
gold circles sized by tier (ringed for capitals), teal diamonds for
markers, all in screen px so they stay legible at any zoom. balance.csv
decides which show — capitals always, towns above a population from the
town scale, everything from the village scale. Mouse motion now resolves
the object under the cursor through MapObjects; a pin or line gets a ring
or gold glow and a small tooltip with its name, alongside the kingdom
outline that was already there.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019HggsFraqfeKGW6RHNys5E"
```

---

### Task 4: MapInfoCard and per-kind cards

**Files:**
- Create: `scripts/ui/map_info_card.gd`
- Modify: `scripts/ui/world_map_view.gd`
- Test: `tests/ui/test_world_map_view.gd`

**Interfaces:**
- Consumes: `MapObjects.describe`.
- Produces: `MapInfoCard` (`PanelContainer`) with `show_entry(entry: Dictionary) -> void`, `ask_enabled: bool`, `title_label() -> Label`, `body_label() -> Label`, `ask_button() -> Button`, signals `ask_requested(text: String)`, `closed`. On `WorldMapView`: `select_object(obj: Dictionary) -> void`, `selected_object() -> Dictionary`, `set_ask_enabled(on: bool) -> void`, `signal place_asked(text: String)`; existing `select_state(sid)`, `card() -> MapInfoCard`, `card_title() -> Label` keep working.

- [x] **Step 1: Write the failing tests**

Append to `tests/ui/test_world_map_view.gd`:

```gdscript

## Cards per object kind (MapInfoCard renders what MapObjects.describe says).
func test_selecting_a_town_opens_its_card() -> void:
	var v := _view()
	await wait_frames(1)
	v.select_object({"kind": "burg", "code": "kuojarpan"})
	assert_true(v.card().visible)
	assert_eq(v.card_title().text, "Kuojarpan")
	assert_true(v.card().body_label().text.begins_with("Capital of Onjormaa, Hetalia"))

func test_selecting_land_leads_with_province_and_terrain() -> void:
	var v := _view()
	await wait_frames(1)
	var k: Dictionary = Game.data.burgs["kuojarpan"]
	v.select_object({"kind": "land", "state_id": int(Game.data.kingdoms["hetalia"]["state_id"]),
		"province_id": 72, "biome_id": 6, "x": float(k["x"]), "y": float(k["y"])})
	assert_eq(v.card_title().text, "Onjormaa")
	var body := v.card().body_label().text
	assert_true(body.begins_with("Hetalia\nTerrain: Temperate deciduous forest"), body)
	assert_true(body.contains("Capital: Kuojarpan"), "kingdom overview follows")

func test_selecting_water_closes_the_card() -> void:
	var v := _view()
	await wait_frames(1)
	v.select_object({"kind": "burg", "code": "kuojarpan"})
	v.select_object({"kind": "water"})
	assert_false(v.card().visible)

func test_ask_button_is_off_until_a_screen_enables_it() -> void:
	var v := _view()
	await wait_frames(1)
	v.select_object({"kind": "burg", "code": "kuojarpan"})
	assert_false(v.card().ask_button().visible, "no input box wired: no Ask")
	v.set_ask_enabled(true)
	v.select_object({"kind": "burg", "code": "kuojarpan"})
	assert_true(v.card().ask_button().visible)

var _asked := ""

func test_ask_emits_the_question_for_the_selected_place() -> void:
	var v := _view()
	await wait_frames(1)
	v.set_ask_enabled(true)
	v.place_asked.connect(func(text: String) -> void: _asked = text)
	v.select_object({"kind": "burg", "code": "kuojarpan"})
	v.card().ask_button().pressed.emit()
	assert_eq(_asked, "What do we know of Kuojarpan?")
```

- [x] **Step 2: Run to verify failure**

Run: `gut.sh world_map`
Expected: errors for missing `select_object`, `body_label`, `ask_button`, `set_ask_enabled`, `place_asked`.

- [x] **Step 3: Create MapInfoCard**

Create `scripts/ui/map_info_card.gd`:

```gdscript
class_name MapInfoCard
extends PanelContainer
## The world map's floating info card (spec 2026-09-08): a title, a few
## lines, and two buttons — ASK THE COUNCIL (only when a screen with an
## order/talk box enabled it; it pre-fills that box and never sends) and
## CLOSE. Content comes from MapObjects.describe; this node only renders.

signal ask_requested(text: String)
signal closed

const WIDTH := 150.0

## Screens with an input box turn this on (WorldMapView.set_ask_enabled).
var ask_enabled := false:
	set(on):
		ask_enabled = on
		_ask.visible = on and _ask_text != ""

var _title: Label
var _body: Label
var _ask: Button
var _ask_text := ""

func _init() -> void:
	name = "InfoCard"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.GOLD, 1, 8))
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -(WIDTH + 4.0)
	offset_top = 4.0
	offset_right = -4.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	add_child(col)
	_title = Label.new()
	_title.name = "CardTitle"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	UiPalette.style_header(_title, 10)
	col.add_child(_title)
	col.add_child(HSeparator.new())
	_body = Label.new()
	_body.name = "CardBody"
	_body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body.add_theme_font_size_override("font_size", 8)
	_body.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
	col.add_child(_body)
	_ask = Button.new()
	_ask.name = "CardAsk"
	_ask.text = "ASK THE COUNCIL"
	_ask.focus_mode = Control.FOCUS_NONE
	_ask.add_theme_font_size_override("font_size", 8)
	_ask.pressed.connect(func() -> void: ask_requested.emit(_ask_text))
	_ask.visible = false
	col.add_child(_ask)
	var close := Button.new()
	close.name = "CardClose"
	close.text = "CLOSE"
	close.focus_mode = Control.FOCUS_NONE
	close.add_theme_font_size_override("font_size", 8)
	close.pressed.connect(func() -> void:
		hide()
		closed.emit())
	col.add_child(close)
	hide()

## entry = {title, lines: Array[String], ask} from MapObjects.describe.
func show_entry(entry: Dictionary) -> void:
	_title.text = String(entry.get("title", ""))
	_body.text = "\n".join(PackedStringArray(entry.get("lines", [])))
	_ask_text = String(entry.get("ask", ""))
	_ask.visible = ask_enabled and _ask_text != ""
	show()

func title_label() -> Label:
	return _title

func body_label() -> Label:
	return _body

func ask_button() -> Button:
	return _ask
```

- [x] **Step 4: Move WorldMapView onto the card**

In `scripts/ui/world_map_view.gd`:

4a. Add the signal after the class doc comment:

```gdscript
## A card's ASK THE COUNCIL button: the screen owning an input box puts this
## text in it (nothing is sent until the player presses Enter).
signal place_asked(text: String)
```

4b. Replace the fields `var _card: PanelContainer`, `var _card_title: Label`, `var _card_body: Label` with:

```gdscript
var _card: MapInfoCard
## What the open card describes ({} when closed); drawn highlighted.
var _selected_obj: Dictionary = {}
```

4c. Delete `_build_card()` and `_show_kingdom()` entirely. Replace the `_build_card()` call in `_ready` with:

```gdscript
	_card = MapInfoCard.new()
	_card.ask_requested.connect(func(text: String) -> void: place_asked.emit(text))
	_card.closed.connect(func() -> void:
		_selected_obj = {}
		queue_redraw())
	add_child(_card)
```

4d. Replace `_select_at`, `select_state`, and the test seams `card`/`card_title` with:

```gdscript
func _select_at(pos: Vector2) -> void:
	select_object(_object_under(pos))

## Public for tests: open the kingdom card for this Azgaar state id; -1 /
## unknown ids (water, stale bitmap) close the card.
func select_state(sid: int) -> void:
	select_object({"kind": "kingdom", "state_id": sid})

## Open the card for any map object (MapObjects.object_at shape). Water or
## an unknown object closes it.
func select_object(obj: Dictionary) -> void:
	var entry := MapObjects.describe(Game.data, obj)
	if entry.is_empty():
		_selected_obj = {}
		_card.hide()
	else:
		_selected_obj = obj
		_card.show_entry(entry)
	queue_redraw()

func selected_object() -> Dictionary:
	return _selected_obj

func set_ask_enabled(on: bool) -> void:
	_card.ask_enabled = on

## Test seams.
func card() -> MapInfoCard:
	return _card

func card_title() -> Label:
	return _card.title_label()
```

4e. In `_draw`, after `_draw_hover()` add `_draw_object_highlight(_selected_obj)` so the selected pin/line stays marked while its card is open.

- [x] **Step 5: Import (new class), run, verify pass**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import` then `gut.sh world_map`
Expected: `All tests passed!` including the pre-existing `test_selecting_a_kingdom_opens_the_card` and `test_water_click_closes_the_card`.

- [x] **Step 6: Full suite, then commit**

```bash
git add scripts/ui/map_info_card.gd scripts/ui/map_info_card.gd.uid scripts/ui/world_map_view.gd tests/ui/test_world_map_view.gd
git commit -m "feat(map): per-object info cards with an Ask the council button

The card moves out of WorldMapView into MapInfoCard, which renders
whatever MapObjects.describe returns: a town, road, river, point of
interest, patch of land, or kingdom. Clicking resolves the object under
the cursor the same way hovering does. The Ask button stays hidden until
a screen that owns an input box enables it; pressing it emits place_asked
with the card's question and sends nothing itself.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019HggsFraqfeKGW6RHNys5E"
```

---

### Task 5: Wire Ask into the court and conversation screens; docs

**Files:**
- Modify: `scripts/ui/court_screen.gd`, `scripts/ui/conversation_scene.gd`
- Modify: `CLAUDE.md`, `docs/superpowers/specs/2026-09-08-map-objects-design.md`
- Test: `tests/ui/test_court_screen.gd`, `tests/ui/test_conversation_scene.gd`

**Interfaces:**
- Consumes: `WorldMapView.set_ask_enabled`, `place_asked`, `select_object`, `card().ask_button()`.

- [x] **Step 1: Write the failing screen tests**

Append to `tests/ui/test_court_screen.gd`:

```gdscript

## The map's ASK THE COUNCIL button fills the order box with the card's
## question; nothing is submitted until the player presses Enter.
func test_map_ask_fills_the_order_box_without_sending() -> void:
	var screen := _screen()
	await wait_frames(1)
	var map := screen.world_map()
	map.select_object({"kind": "burg", "code": "kuojarpan"})
	assert_true(map.card().ask_button().visible, "court owns an order box, so Ask shows")
	map.card().ask_button().pressed.emit()
	assert_eq(screen.free_text.text, "What do we know of Kuojarpan?")
	assert_eq(screen.log_box.get_child_count(), 0, "nothing was sent")
```

Append to `tests/ui/test_conversation_scene.gd`:

```gdscript

## Same Ask hook on the conversation stage: the card's question lands in the
## talk box for the player to send or edit.
func test_map_ask_fills_the_talk_box() -> void:
	var c := _scene_with([], null)
	await wait_frames(1)
	var map: WorldMapView = c.get_node("%MapPanel/WorldMap")
	map.select_object({"kind": "burg", "code": "kuojarpan"})
	assert_true(map.card().ask_button().visible)
	map.card().ask_button().pressed.emit()
	assert_eq(c.free_text_field().text, "What do we know of Kuojarpan?")
```

(If `_scene_with([], null)` cannot take a null report in this file's helper, look at how its first test builds a scene and copy that call exactly.)

- [x] **Step 2: Run to verify failure**

Run: `gut.sh court_screen` and `gut.sh conversation_scene`
Expected: `assert_true(... ask_button().visible)` fails (Ask not enabled), and the text assertions fail with "".

- [x] **Step 3: Wire the screens**

In `scripts/ui/court_screen.gd`, right after `%MapPanel.add_child(_world_map)` add:

```gdscript
	# The map's Ask button drops its question into the order box (spec
	# 2026-09-08); the player still presses Enter, so no order or API call
	# happens without them.
	_world_map.set_ask_enabled(true)
	_world_map.place_asked.connect(_on_place_asked)
```

and add the handler after `_on_free_text_submitted`:

```gdscript
func _on_place_asked(text: String) -> void:
	free_text.text = text
	free_text.caret_column = text.length()
	free_text.grab_focus()
```

In `scripts/ui/conversation_scene.gd`, change the local `var world_map := WorldMapView.new()` block in `_ready` to keep a member and wire it. Add a field near `var _free_text: LineEdit`:

```gdscript
var _world_map: WorldMapView
```

and replace the three lines that create and add the map with:

```gdscript
	_world_map = WorldMapView.new()
	_world_map.name = "WorldMap"
	%MapPanel.add_child(_world_map)
	# Ask on a map card pre-fills the talk box (spec 2026-09-08); never sends.
	_world_map.set_ask_enabled(true)
	_world_map.place_asked.connect(func(text: String) -> void:
		_free_text.text = text
		_free_text.caret_column = text.length()
		_free_text.grab_focus())
```

Check `_free_text` is assigned before the map is created in `_ready` (it is assigned at line ~85; the map at ~51). If the map comes first, the lambda still works because it dereferences `_free_text` only when fired — but confirm `_free_text` is non-null at fire time by keeping the assignment in `_ready`.

- [x] **Step 4: Run to verify pass**

Run: `gut.sh court_screen` and `gut.sh conversation_scene` → `All tests passed!`.

- [x] **Step 5: Docs**

In `CLAUDE.md`, replace the generated-files parenthetical `(\`kingdoms.csv\`, \`provinces.csv\`, \`burgs.csv\`, \`borders.csv\`)` with `(\`kingdoms.csv\`, \`provinces.csv\`, \`burgs.csv\`, \`borders.csv\`, \`routes.csv\`, \`rivers.csv\`, \`markers.csv\`, \`biomes.csv\`, \`map_info.csv\`)` and `and the \`world_state_index.png\` hit-test bitmap` with `and the \`world_state_index.png\` / \`world_province_index.png\` / \`world_biome_index.png\` hit-test bitmaps`.

In the spec, add under "Owner rulings" a fifth item:

```markdown
5. **Implementation amendments (2026-09-08):** the two new bitmaps are named in `data/maps.csv` (`province_texture`, `biome_texture` columns) rather than derived from the index path; `provinces.csv` also gains `center_x`/`center_y` so the province bitmap can be verified at each province's center; the land card appends the kingdom overview after its local lines so the old kingdom card stays one click away.
```

- [x] **Step 6: Full suite, then commit**

Run: `./run_tests.sh` → green.

```bash
git add scripts/ui/court_screen.gd scripts/ui/conversation_scene.gd tests/ui/test_court_screen.gd \
  tests/ui/test_conversation_scene.gd CLAUDE.md docs/superpowers/specs/2026-09-08-map-objects-design.md
git commit -m "feat(map): Ask the council from a map card fills the order or talk box

Court and conversation screens enable the card's Ask button and drop its
question into their input box with focus; the player still presses Enter,
so the LLM path stays the existing free-text one and nothing is sent by a
click. The day run has no input box and leaves Ask off. CLAUDE.md lists
the new generated pack files; the spec records the three implementation
amendments.

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_019HggsFraqfeKGW6RHNys5E"
```

---

## Self-review

- **Spec coverage:** importer outputs (T1), repository (T1), MapIndex/MapGeometry (T1, T2), MapObjects hit-test/LOD/describe (T2), pins + hover + tooltip (T3), MapInfoCard + per-kind cards + place_asked signal (T4), screen wiring + docs (T5), balance values (T2), tests per spec §6 spread across T1–T5. Error handling: absent tables load as empty via `_load_if_present` (T1); stale ids → water/closed card via `describe` returning `{}` (T2/T4); importer hard-fails on short routes and coordinate-less markers, warns on unnoted markers (T1).
- **Amendments vs spec** (recorded in T5 step 5): maps.csv columns for the bitmaps; province center columns; land card appends the kingdom overview.
- **Type consistency:** `object_at` shape `{kind, code}` / `{kind:"land", state_id, province_id, biome_id, x, y}` / `{kind:"water"}` is used identically in T2 tests, T3 view, T4 `select_object`. `describe` returns `{title, lines, ask}`; `MapInfoCard.show_entry` consumes exactly those keys. `view_scale()` (not `scale`, which Control already owns) is used in T3 and T4. `CAPITALS_ONLY` is `-1` everywhere; `burg_visible` treats any negative as capitals-only.
