# WAR ROOM P2-A — marks on the sheet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ink the map's points of interest (brigands, pirates, mines, battlefields, lighthouses on the sheet; inns, ruins, springs and the rest as fine print) on the WAR ROOM table, read them in the hover slip, and let brigands and pirates take a share of a supply line that passes within their reach.

**Architecture:** Two data tables (`data/war_marks.csv`, `data/war_mark_hazards.csv`) loaded by `DataRepository`; a pure engine module `WarMarks` lists the inked marks and finds the near ones; `SupplySystem.mark_loss` adds the hazard to a line's loss with the marks named (`hazards`); `WarSheetInk` / `WarFinePrint` hand the marks to the painter as `places`; one static glyph drawer `WarMarkGlyph` serves the painter and the key slip; `WarGround` reads the near marks for the slip.

**Tech Stack:** Godot 4.7, typed GDScript, GUT; `tools/snapshot_screen.gd` for real-window shots.

**Spec:** `docs/superpowers/specs/2026-10-07-war-room-p2-tactical-layer-design.md` (sub-project A, §1)

## Global Constraints

- Design values live in `data/*.csv` (`balance.csv` is `key,value,"notes"`); every new `war_*` key goes into the key list of `tests/engine/test_war_room_data.gd`.
- `scripts/engine/` names no `scripts/ui/` or `scripts/llm/` class and never touches `Game`; `scripts/war_room/` never reads `Game` (`WarRoomScreen` is the bridge).
- Determinism: marks are visited in sorted code order; no draw, no wall clock; whole per-mille integers.
- Readable causality: a supply line's added loss names the mark that took it (`hazards`).
- Markers are public geography: inked on every sheet, no intel gate (spec ruling 2).
- Only brigands and pirates have an effect (spec ruling 3). Pirates need no separate water test: their marks stand at sea, so a route within their reach runs along the coast (ruling recorded in Task 2).
- The look lives in the editor: no new scene is needed; glyphs are drawn ink (as the existing marks are), sized by `balance.csv` keys, coloured by `war_palette` keys.
- Tests take data from `tests/suite_data.gd` (`SuiteData.repo()` is a deep copy: a fixture may move a marker in `repo.markers`).
- Every visual change goes through the `visual-review` skill with real-window shots (`--resolution WxH`, never `--headless` for 3D).
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Work in this worktree; never switch the main checkout's branch.

**Commands.** One test file:

```bash
CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_war_marks.gd -gpre_run_script=res://tests/pre_run.gd -gpost_run_script=res://tests/post_run.gd -gexit
```

A new `class_name` is only known after an import pass: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import`. Whole suite: `./run_tests.sh` (0 errors expected in a worktree without the gdai binaries).

**Before Task 1:** `cp -Rc /Users/samuelzhang/game_design/.godot .godot`, then `./run_tests.sh` once for the baseline (green).

## Review Focus

- **A route that passes the same brigand mark twice** (out and back along a valley): the mark counts once — pinned in Task 2.
- **A line already at the loss cap** (a very long road past brigands): the total never exceeds `army_supply_loss_cap_permille` — pinned in Task 2.
- **A stronghold line or a fleet** (no road): no `hazards`, no added loss, the key still present so callers never miss it — pinned in Task 2.
- **A marker type in the export that `war_marks.csv` does not list, or a glyph name the drawer does not know**: never inked, never a crash; the data test fails on an unknown glyph — pinned in Task 1.
- **Two marks within the hover reach of one point**: nearest first, at most `war_mark_hover_max`, the legend only for the nearest — pinned in Task 4.

---

## File Structure

| File | Responsibility |
|---|---|
| `data/war_marks.csv` (create) | which marker types are inked, with which glyph, on which layer, and the slip's words |
| `data/war_mark_hazards.csv` (create) | the marks that bite a supply line: reach and loss |
| `data/balance.csv` (modify) | `war_mark_*` sizes and reaches |
| `scripts/engine/data_repository.gd` (modify) | load the two tables |
| `scripts/engine/war_marks.gd` (create) | the inked marks by layer, the near ones, `GLYPHS` |
| `scripts/engine/supply_system.gd` (modify) | `mark_loss`, `total_loss`, `hazards` on a line |
| `scripts/engine/war_folio.gd` (modify) | the supply row names the hazards |
| `scripts/war_room/war_mark_glyph.gd` (create) | draws one glyph on any CanvasItem |
| `scripts/war_room/war_sheet_ink.gd`, `war_fine_print.gd`, `war_ink_painter.gd` (modify) | `places` strokes and their drawing |
| `scripts/engine/war_ground.gd` (modify) | the slip's near marks |
| `scripts/ui/war_margin_key.gd` (modify) | the key's mark entries |
| `scripts/war_room/CLAUDE.md`, `data/CLAUDE.md` (modify) | the rules as they stand |

---

### Task 1: The marks' data and `WarMarks`

**Files:**
- Create: `data/war_marks.csv`, `data/war_mark_hazards.csv`, `scripts/engine/war_marks.gd`
- Modify: `scripts/engine/data_repository.gd` (vars beside `army_town_reach`, loads beside its load ~line 656), `data/balance.csv`
- Test: `tests/engine/test_war_marks.gd`, `tests/engine/test_war_room_data.gd`

**Interfaces:**
- Produces: `repo.war_marks: Dictionary` type → `{glyph: String, layer: String, note: String}`; `repo.war_mark_hazards: Dictionary` type → `{reach_km: float, permille: int}`; `WarMarks.GLYPHS: Array[String]`; `WarMarks.km_per_px(repo) -> float`; `WarMarks.inked(repo: DataRepository, layer: String) -> Array` of `{code, label, type, at: Vector2, glyph, note, legend}` sorted by code (`layer` "" = both layers); `WarMarks.near(repo, at: Vector2, km: float, max_n: int) -> Array` of the same plus `distance_km: float`, nearest first.

- [ ] **Step 1: Write the failing tests**

Create `tests/engine/test_war_marks.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The marks the WAR ROOM inks (spec 2026-10-07-war-room-p2-tactical-layer §1.1).

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_every_inked_type_is_an_admitted_marker_type_with_a_known_glyph() -> void:
	var admitted := FileAccess.get_file_as_string("res://data/marker_types.csv")
	assert_gt(repo.war_marks.size(), 0)
	for type: String in repo.war_marks:
		assert_true(admitted.contains("\n%s," % type), "%s is not in marker_types.csv" % type)
		var row: Dictionary = repo.war_marks[type]
		assert_true(WarMarks.GLYPHS.has(String(row["glyph"])), "%s's glyph %s is not drawn" % [type, row["glyph"]])
		assert_true(["sheet", "fine"].has(String(row["layer"])), type)
	for type: String in repo.war_mark_hazards:
		assert_true(repo.war_marks.has(type), "a hazard %s that is not inked" % type)


func test_inked_marks_by_layer_in_code_order() -> void:
	var sheet := WarMarks.inked(repo, "sheet")
	var fine := WarMarks.inked(repo, "fine")
	assert_gt(sheet.size(), 0)
	for m: Dictionary in sheet:
		assert_eq(String(repo.war_marks[m["type"]]["layer"]), "sheet")
	for m: Dictionary in fine:
		assert_eq(String(repo.war_marks[m["type"]]["layer"]), "fine")
	var codes: Array = sheet.map(func(m: Dictionary) -> String: return String(m["code"]))
	var sorted := codes.duplicate()
	sorted.sort()
	assert_eq(codes, sorted)
	assert_eq(WarMarks.inked(repo, "").size(), sheet.size() + fine.size())


func test_a_type_not_in_the_table_is_never_inked() -> void:
	var code: String = repo.markers.keys()[0]
	repo.markers[code]["type"] = "not_a_type"
	for m: Dictionary in WarMarks.inked(repo, ""):
		assert_ne(String(m["code"]), code)


func test_near_is_nearest_first_and_capped() -> void:
	var all := WarMarks.inked(repo, "")
	var m: Dictionary = all[0]
	var at: Vector2 = m["at"]
	var near := WarMarks.near(repo, at + Vector2(0.5, 0.0), 5000.0, 3)
	assert_eq(near.size(), 3)
	assert_eq(String(near[0]["code"]), String(m["code"]))
	assert_lte(float(near[0]["distance_km"]), float(near[1]["distance_km"]))
	assert_lte(float(near[1]["distance_km"]), float(near[2]["distance_km"]))
	assert_eq(WarMarks.near(repo, at, 0.0001, 3).size(), 1, "only the one standing there")
```

In `tests/engine/test_war_room_data.gd`, add to the key list: `"war_mark_px", "war_mark_reach_alpha", "war_mark_hover_km", "war_mark_hover_max", "war_mark_legend_chars"`.

- [ ] **Step 2: Run to see them fail**

Run the single-file command for `tests/engine/test_war_marks.gd`. Expected: FAIL (parse error: `WarMarks` not declared; `war_marks` not a member).

- [ ] **Step 3: Implement**

`data/war_marks.csv`:

```csv
type,glyph,layer,note
brigands,crossed_swords,sheet,"a gang of brigands on the roads (WAR ROOM P2, spec 2026-10-07-war-room-p2-tactical-layer §1.1)"
pirates,sabre_wave,sheet,pirate ships in these waters
mines,pick,sheet,a mine head
battlefields,crossed_flags,sheet,an old battlefield
lighthouses,tower_light,sheet,a lighthouse
inns,tankard,fine,a roadside inn
ruins,broken_column,fine,old ruins
encounters,dot,fine,people on the road
hot-springs,dot,fine,a bathhouse over a hot spring
water-sources,dot,fine,a spring
sacred-forests,dot,fine,a sacred grove
sacred-pineries,dot,fine,a sacred grove
statues,dot,fine,a wayside monument
necropolises,dot,fine,a burial ground
caves,dot,fine,a cave
waterfalls,dot,fine,a waterfall
fairs,dot,fine,a fair
```

`data/war_mark_hazards.csv`:

```csv
type,reach_km,supply_loss_permille,notes
brigands,8,40,"first draft (spec 2026-10-07-war-room-p2-tactical-layer §1.2): a supply line passing within reach_km of the mark loses this much more on the way, once per mark per line"
pirates,12,60,"first draft: their marks stand at sea, so a road within reach runs along the coast they raid"
```

`data/balance.csv` (after the `war_fine_*` rows):

```csv
war_mark_px,16,"WAR ROOM P2 (spec 2026-10-07-war-room-p2-tactical-layer §1.3): a sheet-layer mark's glyph, ink px"
war_mark_reach_alpha,0.35,"WAR ROOM P2 §1.3: a brigand or pirate mark's reach, a dotted rubric ring at this alpha"
war_mark_hover_km,6,"WAR ROOM P2 §1.3: the hover slip names the marks within this many km of the pointer"
war_mark_hover_max,3,"WAR ROOM P2 §1.3: at most this many marks in the slip, nearest first"
war_mark_legend_chars,90,"WAR ROOM P2 §1.3: the nearest mark's legend is cut to this many characters"
```

`scripts/engine/data_repository.gd` — beside `var army_town_reach`:

```gdscript
## data/war_marks.csv: marker type -> {glyph, layer, note} — which marks the
## WAR ROOM inks, how, and on which layer (spec 2026-10-07-war-room-p2 §1.1).
var war_marks: Dictionary = {}
## data/war_mark_hazards.csv: marker type -> {reach_km, permille} — the marks
## that take a share of a supply line passing within their reach (§1.2).
var war_mark_hazards: Dictionary = {}
```

and beside the `army_town_reach.csv` load (clear them where the other tables are cleared, if that function clears its dictionaries before loading):

```gdscript
	if not _load_if_present(dir + "/war_marks.csv", ["type", "glyph", "layer", "note"],
			func(r): war_marks[String(r["type"])] = {"glyph": String(r["glyph"]), "layer": String(r["layer"]),
				"note": String(r["note"])}):
		return false
	if not _load_if_present(dir + "/war_mark_hazards.csv", ["type", "reach_km", "supply_loss_permille"],
			func(r): war_mark_hazards[String(r["type"])] = {"reach_km": float(r["reach_km"]),
				"permille": int(r["supply_loss_permille"])}):
		return false
```

`scripts/engine/war_marks.gd`:

```gdscript
class_name WarMarks
extends RefCounted
## The map's points of interest the WAR ROOM inks (spec
## 2026-10-07-war-room-p2-tactical-layer §1): a geography/markers.csv row whose
## type data/war_marks.csv lists, on the layer it names. Public geography: no
## intel gate. Pure; marks in code order.

## Every glyph the WAR ROOM can draw (WarMarkGlyph); data/war_marks.csv may
## name no other.
const GLYPHS := ["crossed_swords", "sabre_wave", "pick", "tankard", "crossed_flags", "broken_column",
	"tower_light", "dot"]


static func km_per_px(repo: DataRepository) -> float:
	return float(ArmySystem.metres_per_pack_px(repo)) / 1000.0


## The inked marks on `layer` ("sheet", "fine", or "" for both), code order.
static func inked(repo: DataRepository, layer: String) -> Array:
	var out: Array = []
	var codes: Array = repo.markers.keys()
	codes.sort()
	for code: String in codes:
		var m: Dictionary = repo.markers[code]
		var row: Dictionary = repo.war_marks.get(String(m.get("type", "")), {})
		if row.is_empty() or (layer != "" and String(row["layer"]) != layer):
			continue
		out.append({"code": code, "label": String(m.get("label", code)), "type": String(m["type"]),
			"at": Vector2(float(m["x"]), float(m["y"])), "glyph": String(row["glyph"]),
			"note": String(row["note"]), "legend": String(m.get("legend", ""))})
	return out


## The inked marks within `km` of `at`, nearest first (ties in code order), at
## most `max_n`, each with its `distance_km`.
static func near(repo: DataRepository, at: Vector2, km: float, max_n: int) -> Array:
	var per_px := km_per_px(repo)
	var out: Array = []
	for m: Dictionary in inked(repo, ""):
		var d := (m["at"] as Vector2).distance_to(at) * per_px
		if d <= km:
			var e := m.duplicate()
			e["distance_km"] = d
			out.append(e)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["distance_km"]) < float(b["distance_km"]) \
			or (float(a["distance_km"]) == float(b["distance_km"]) and String(a["code"]) < String(b["code"])))
	return out.slice(0, max_n)
```

- [ ] **Step 4: Import, then run the tests**

Run the import pass, then `tests/engine/test_war_marks.gd` and `tests/engine/test_war_room_data.gd`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add data/war_marks.csv data/war_mark_hazards.csv data/balance.csv scripts/engine/data_repository.gd scripts/engine/war_marks.gd scripts/engine/war_marks.gd.uid tests/engine/test_war_marks.gd tests/engine/test_war_marks.gd.uid tests/engine/test_war_room_data.gd
git commit -m "feat(war room): the marks the war room inks — data and WarMarks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Brigands and pirates take a share of a supply line

**Files:**
- Modify: `scripts/engine/supply_system.gd` (`mark_loss`, `total_loss`, `_poly_distance`, `_line_of`), `scripts/engine/war_folio.gd` (`_supply`, the "Line" row)
- Test: `tests/engine/test_supply_marks.gd` (create), `tests/engine/test_war_folio.gd`

**Interfaces:**
- Consumes: `repo.war_mark_hazards`, `WarMarks.km_per_px` (Task 1).
- Produces: `SupplySystem.mark_loss(repo: DataRepository, route: PackedVector2Array) -> Dictionary` `{permille: int, hazards: Array}` (each hazard `{code, label, permille}`, code order); `SupplySystem.total_loss(repo, km: int, mark_permille: int) -> int`; every `line_of` dictionary has `hazards: Array` (empty for a stronghold line); its `loss_permille` is `total_loss`.

- [ ] **Step 1: Write the failing tests**

Create `tests/engine/test_supply_marks.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Brigands and pirates on a supply line (spec 2026-10-07-war-room-p2-tactical-layer §1.2).

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func _mark_of(type: String) -> Dictionary:
	var codes: Array = repo.markers.keys()
	codes.sort()
	for code: String in codes:
		if String(repo.markers[code]["type"]) == type:
			var m: Dictionary = repo.markers[code]
			return {"code": code, "label": String(m["label"]), "at": Vector2(float(m["x"]), float(m["y"]))}
	return {}


func test_a_route_through_a_brigand_mark_pays_its_share_once() -> void:
	var m := _mark_of("brigands")
	var at: Vector2 = m["at"]
	var hz: Dictionary = repo.war_mark_hazards["brigands"]
	# past it and back again: one mark, counted once
	var route := PackedVector2Array([at + Vector2(-20, 0.5), at + Vector2(20, 0.5), at + Vector2(-20, 1.0)])
	var got := SupplySystem.mark_loss(repo, route)
	var mine: Array = (got["hazards"] as Array).filter(func(h: Dictionary) -> bool: return String(h["code"]) == String(m["code"]))
	assert_eq(mine.size(), 1)
	assert_eq(int(mine[0]["permille"]), int(hz["permille"]))
	assert_eq(String(mine[0]["label"]), String(m["label"]))


func test_a_route_out_of_reach_pays_nothing() -> void:
	var m := _mark_of("brigands")
	var reach_px := float(repo.war_mark_hazards["brigands"]["reach_km"]) / WarMarks.km_per_px(repo)
	var at: Vector2 = m["at"]
	var route := PackedVector2Array([at + Vector2(-20, reach_px * 1.5), at + Vector2(20, reach_px * 1.5)])
	var got := SupplySystem.mark_loss(repo, route)
	assert_false((got["hazards"] as Array).any(func(h: Dictionary) -> bool: return String(h["code"]) == String(m["code"])))


func test_a_mark_that_is_no_hazard_takes_nothing() -> void:
	var m := _mark_of("mines")
	if m.is_empty():
		pass_test("no mine on this pack")
		return
	var at: Vector2 = m["at"]
	var got := SupplySystem.mark_loss(repo, PackedVector2Array([at + Vector2(-1, 0), at + Vector2(1, 0)]))
	assert_false((got["hazards"] as Array).any(func(h: Dictionary) -> bool: return String(h["code"]) == String(m["code"])))


func test_the_total_never_passes_the_cap() -> void:
	var cap := int(repo.bal("army_supply_loss_cap_permille"))
	assert_eq(SupplySystem.total_loss(repo, 100000, 500), cap)
	assert_eq(SupplySystem.total_loss(repo, 0, 40), mini(40, cap))
	assert_eq(SupplySystem.total_loss(repo, 100, 0), SupplySystem.loss_of(repo, 100))


func test_every_line_names_its_hazards_and_a_stronghold_line_has_none() -> void:
	var state := SuiteData.campaign(repo, 42)
	for code: String in state.regiments:
		var line := SupplySystem.line_of(repo, state, code)
		assert_true(line.has("hazards"), code)
		if String(line["stronghold"]) != "":
			assert_eq(line["hazards"], [])
			assert_eq(int(line["loss_permille"]), 0)


func test_a_brigand_on_a_regiments_road_shows_in_its_line() -> void:
	var state := SuiteData.campaign(repo, 42)
	var target := ""
	for code: String in state.regiments:
		if SupplySystem.route_px(repo, state, code).size() >= 2:
			target = code
			break
	if target == "":
		pass_test("no regiment on a road at the campaign's start")
		return
	var route := SupplySystem.route_px(repo, state, target)
	var mid := route[route.size() / 2]
	var m := _mark_of("brigands")
	repo.markers[m["code"]]["x"] = str(mid.x)
	repo.markers[m["code"]]["y"] = str(mid.y)
	var line := SupplySystem.line_of(repo, state, target)
	var labels: Array = (line["hazards"] as Array).map(func(h: Dictionary) -> String: return String(h["label"]))
	assert_true(labels.has(String(m["label"])))
	assert_eq(int(line["loss_permille"]),
		SupplySystem.total_loss(repo, int(line["length_km"]), int(repo.war_mark_hazards["brigands"]["permille"])))
```

In `tests/engine/test_war_folio.gd` add (the file has `repo`, `state`, `code` and `_rows(key)`; follow its own setup):

```gdscript
func test_the_supply_row_names_a_brigand_on_the_road() -> void:
	var route := SupplySystem.route_px(repo, state, code)
	if route.size() < 2:
		pass_test("this regiment is fed through a stronghold")
		return
	var mid := route[route.size() / 2]
	var codes: Array = repo.markers.keys()
	codes.sort()
	for c: String in codes:
		if String(repo.markers[c]["type"]) == "brigands":
			repo.markers[c]["x"] = str(mid.x)
			repo.markers[c]["y"] = str(mid.y)
			assert_string_contains(_rows("supply")["Line"], "to the %s" % repo.markers[c]["label"])
			return
	pass_test("no brigands on this pack")
```

- [ ] **Step 2: Run to see them fail**

Run `tests/engine/test_supply_marks.gd`. Expected: FAIL (`mark_loss` / `total_loss` not found).

- [ ] **Step 3: Implement**

In `scripts/engine/supply_system.gd`, after `loss_of`:

```gdscript
## A line's whole loss: its length's (loss_of) and its marks' (mark_loss),
## held to army_supply_loss_cap_permille.
static func total_loss(repo: DataRepository, km: int, mark_permille: int) -> int:
	return mini(loss_of(repo, km) + maxi(mark_permille, 0), int(repo.bal("army_supply_loss_cap_permille")))


## What the brigands and pirates along a route take (spec
## 2026-10-07-war-room-p2-tactical-layer §1.2): each hazard mark
## (data/war_mark_hazards.csv) whose reach the route (pack px) passes through,
## once per mark, in code order — {permille, hazards: [{code, label, permille}]}.
## Pirates need no water test: their marks stand at sea, so a road within their
## reach runs along the coast they raid.
static func mark_loss(repo: DataRepository, route: PackedVector2Array) -> Dictionary:
	var hazards: Array = []
	var total := 0
	if route.size() < 2:
		return {"permille": 0, "hazards": hazards}
	var per_px := WarMarks.km_per_px(repo)
	var codes: Array = repo.markers.keys()
	codes.sort()
	for code: String in codes:
		var m: Dictionary = repo.markers[code]
		var hz: Dictionary = repo.war_mark_hazards.get(String(m.get("type", "")), {})
		if hz.is_empty():
			continue
		var at := Vector2(float(m["x"]), float(m["y"]))
		if _poly_distance(route, at) * per_px <= float(hz["reach_km"]):
			total += int(hz["permille"])
			hazards.append({"code": code, "label": String(m.get("label", code)), "permille": int(hz["permille"])})
	return {"permille": total, "hazards": hazards}


## The nearest a polyline comes to a point, pack px.
static func _poly_distance(poly: PackedVector2Array, at: Vector2) -> float:
	var best := INF
	for i in poly.size() - 1:
		best = minf(best, at.distance_to(Geometry2D.get_closest_point_to_segment(at, poly[i], poly[i + 1])))
	return best
```

In `_line_of`, the stronghold branch returns `"hazards": []` as well; the road branch builds the route in pack px from the same waypoints it measures and returns the total:

```gdscript
	if town != "":
		var held := garrisoned_in(repo, state, code)
		return {"length_km": 0, "loss_permille": 0, "stronghold": town,
			"garrison": held != "", "garrison_town": held, "hazards": []}
```

and, replacing the last two statements of `_line_of` (`var km := …` and its `return`):

```gdscript
	var km := int(metres / 1000.0)
	var route := PackedVector2Array([ArmySystem.metres_to_pack(repo, origin_m)])
	for p: Array in path:
		route.append(ArmySystem.metres_to_pack(repo, Vector2i(int(p[0]), int(p[1]))))
	if path.is_empty():
		route.append(to)
	var marks := mark_loss(repo, route)
	return {"length_km": km, "loss_permille": total_loss(repo, km, int(marks["permille"])),
		"garrison": false, "garrison_town": "", "stronghold": "", "hazards": marks["hazards"]}
```

In `scripts/engine/war_folio.gd` `_supply`, the road branch's row:

```gdscript
		else:
			@warning_ignore("integer_division")
			var lost := int(line["loss_permille"]) / 10
			var text := "%d km from %s, %d%% lost" % [int(line["length_km"]), depot_name(repo, state), lost]
			var named: Array = (line.get("hazards", []) as Array).map(func(h: Dictionary) -> String:
				@warning_ignore("integer_division")
				return "%d%% to the %s" % [int(h["permille"]) / 10, String(h["label"])])
			if not named.is_empty():
				text += " (%s)" % ", ".join(named)
			rows.append(_row("Line", text))
```

- [ ] **Step 4: Run the tests**

Run `tests/engine/test_supply_marks.gd`, `tests/engine/test_supply_system.gd`, `tests/engine/test_ledger_supply.gd`, `tests/engine/test_war_folio.gd`. Expected: PASS (the crown's lines at the campaign's start pass no hazard mark on beria, so existing figures hold; if one does, the existing test's expectation is brought to `total_loss` and the case recorded as a ruling).

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/supply_system.gd scripts/engine/war_folio.gd tests/engine/test_supply_marks.gd tests/engine/test_supply_marks.gd.uid tests/engine/test_war_folio.gd
git commit -m "feat(supply): brigands and pirates take a named share of a supply line

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The marks on the sheet and in the fine print

**Files:**
- Create: `scripts/war_room/war_mark_glyph.gd`
- Modify: `scripts/war_room/war_sheet_ink.gd` (`strokes` → `places`), `scripts/war_room/war_fine_print.gd` (`strokes` → `places`), `scripts/war_room/war_ink_painter.gd` (draw `places` in both modes), `scripts/war_room/war_room_ink.gd` and `scripts/war_room/war_room_view.gd` (the painter's `mark` widths)
- Test: `tests/war_room/test_war_sheet_ink.gd`, `tests/war_room/test_war_fine_print.gd`, `tests/war_room/test_war_mark_glyph.gd`

**Interfaces:**
- Consumes: `WarMarks.inked`, `WarMarks.GLYPHS`, `repo.war_mark_hazards` (Task 1).
- Produces: `WarSheetInk.strokes(...)["places"]`: `{at: Vector2 (tex px), glyph, hazard_r: float (tex px, 0 for none)}` for sheet-layer marks touching the window/sheet (`keep`); `WarFinePrint.strokes(...)["places"]`: `{at, glyph, label, label_at}` for fine-layer marks, plus `{at, glyph: "", label, label_at}` name entries for sheet-layer marks (the name beside the sheet glyph); `WarMarkGlyph.draw(ci: CanvasItem, glyph: String, at: Vector2, size: float, color: Color) -> void`.

- [ ] **Step 1: Write the failing tests**

Create `tests/war_room/test_war_mark_glyph.gd`:

```gdscript
extends GutTest
## Every glyph the data may name draws without error (spec 2026-10-07-war-room-p2 §1.3).


class Probe:
	extends Node2D
	var glyph := ""
	func _draw() -> void:
		WarMarkGlyph.draw(self, glyph, Vector2(20, 20), 16.0, Color.BLACK)


func test_every_glyph_draws() -> void:
	for g: String in WarMarks.GLYPHS:
		var p := Probe.new()
		p.glyph = g
		add_child_autofree(p)
		p.queue_redraw()
		await wait_process_frames(1)
		assert_true(WarMarkGlyph.knows(g), g)
	assert_false(WarMarkGlyph.knows("dragon"))
```

In `tests/war_room/test_war_sheet_ink.gd` add:

```gdscript
func test_sheet_marks_are_inked_with_their_reach() -> void:
	var placed := 0
	for s: Dictionary in WarSheets.series(repo):
		var r: Rect2 = s["rect"]
		var tex := int(repo.bal("war_sheet_texture_px"))
		var k := float(tex) / r.size.x
		var ink := WarSheetInk.strokes(repo, state, s, tex)
		for m: Dictionary in WarMarks.inked(repo, "sheet"):
			if not r.has_point(m["at"]):
				continue
			var hit := (ink["places"] as Array).filter(func(p: Dictionary) -> bool:
				return (p["at"] as Vector2).distance_to(((m["at"] as Vector2) - r.position) * k) < 0.01)
			assert_eq(hit.size(), 1, String(m["code"]))
			var hz: Dictionary = repo.war_mark_hazards.get(String(m["type"]), {})
			var want := 0.0 if hz.is_empty() else float(hz["reach_km"]) / WarMarks.km_per_px(repo) * k
			assert_almost_eq(float(hit[0]["hazard_r"]), want, 0.01)
			placed += 1
	assert_gt(placed, 0, "some sheet holds a mark")
```

In `tests/war_room/test_war_fine_print.gd` add:

```gdscript
func test_fine_marks_and_the_names_of_sheet_marks_are_fine_print() -> void:
	var tex := int(repo.bal("war_sheet_texture_px"))
	var found_fine := false
	var found_name := false
	for s: Dictionary in WarSheets.series(repo):
		var r: Rect2 = s["rect"]
		var fine := WarFinePrint.strokes(repo, state, s, tex, null)
		var labels: Array = (fine["places"] as Array).map(func(p: Dictionary) -> String: return String(p["label"]))
		for m: Dictionary in WarMarks.inked(repo, ""):
			if not r.grow(-r.size.x * 0.1).has_point(m["at"]):
				continue
			if labels.has(String(m["label"])):
				if String(repo.war_marks[m["type"]]["layer"]) == "fine":
					found_fine = true
				else:
					found_name = true
		if found_fine and found_name:
			return
	assert_true(found_fine, "a fine-layer mark is inked as fine print")
	assert_true(found_name, "a sheet mark's name is fine print")
```

- [ ] **Step 2: Run to see them fail**

Run the three files. Expected: FAIL (`WarMarkGlyph` not declared; `places` missing).

- [ ] **Step 3: Implement**

`scripts/war_room/war_mark_glyph.gd`:

```gdscript
class_name WarMarkGlyph
extends RefCounted
## One map mark's glyph, drawn in ink on any CanvasItem (the sheet's painter,
## the key slip) — spec 2026-10-07-war-room-p2-tactical-layer §1.3. `size` is
## the glyph's height; every stroke scales with it. WarMarks.GLYPHS lists the
## names the data may use.


static func knows(glyph: String) -> bool:
	return WarMarks.GLYPHS.has(glyph)


static func draw(ci: CanvasItem, glyph: String, at: Vector2, size: float, color: Color) -> void:
	var s := size * 0.5
	var w := maxf(size * 0.09, 1.0)
	match glyph:
		"crossed_swords":
			ci.draw_line(at + Vector2(-s, s), at + Vector2(s, -s), color, w, true)
			ci.draw_line(at + Vector2(s, s), at + Vector2(-s, -s), color, w, true)
			ci.draw_line(at + Vector2(-s * 0.75, s * 0.35), at + Vector2(-s * 0.35, s * 0.75), color, w, true)
			ci.draw_line(at + Vector2(s * 0.75, s * 0.35), at + Vector2(s * 0.35, s * 0.75), color, w, true)
		"sabre_wave":
			ci.draw_arc(at + Vector2(s * 0.6, -s * 0.1), s * 0.9, PI * 0.95, PI * 1.6, 10, color, w, true)
			var wave := PackedVector2Array()
			for i in 9:
				var x := -s + float(i) * s * 0.25
				wave.append(at + Vector2(x, s * 0.75 + sin(float(i) * PI * 0.5) * s * 0.15))
			ci.draw_polyline(wave, color, w, true)
		"pick":
			ci.draw_arc(at + Vector2(0, s * 0.2), s * 0.9, PI * 1.15, PI * 1.85, 10, color, w * 1.2, true)
			ci.draw_line(at + Vector2(0, -s * 0.7), at + Vector2(0, s), color, w, true)
		"tankard":
			ci.draw_rect(Rect2(at + Vector2(-s * 0.55, -s * 0.6), Vector2(s * 0.9, s * 1.5)), color, false, w, true)
			ci.draw_arc(at + Vector2(s * 0.35, s * 0.1), s * 0.35, -PI * 0.5, PI * 0.5, 8, color, w, true)
		"crossed_flags":
			ci.draw_line(at + Vector2(-s * 0.7, s), at + Vector2(s * 0.5, -s), color, w, true)
			ci.draw_line(at + Vector2(s * 0.7, s), at + Vector2(-s * 0.5, -s), color, w, true)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(s * 0.5, -s), at + Vector2(s, -s * 0.75),
				at + Vector2(s * 0.35, -s * 0.5)]), color)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.5, -s), at + Vector2(-s, -s * 0.75),
				at + Vector2(-s * 0.35, -s * 0.5)]), color)
		"broken_column":
			ci.draw_rect(Rect2(at + Vector2(-s * 0.3, -s * 0.4), Vector2(s * 0.6, s * 1.4)), color, false, w, true)
			ci.draw_polyline(PackedVector2Array([at + Vector2(-s * 0.3, -s * 0.4), at + Vector2(-s * 0.05, -s * 0.8),
				at + Vector2(s * 0.1, -s * 0.5), at + Vector2(s * 0.3, -s * 0.7)]), color, w, true)
			ci.draw_line(at + Vector2(-s * 0.6, s), at + Vector2(s * 0.6, s), color, w, true)
		"tower_light":
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.35, s), at + Vector2(s * 0.35, s),
				at + Vector2(s * 0.2, -s * 0.4), at + Vector2(-s * 0.2, -s * 0.4)]), color)
			for a in [-0.35, 0.0, 0.35]:
				var d := Vector2.from_angle(-PI * 0.5 + a)
				ci.draw_line(at + Vector2(0, -s * 0.6) + d * s * 0.2, at + Vector2(0, -s * 0.6) + d * s * 0.55, color, w * 0.8, true)
		_:
			ci.draw_circle(at, s * 0.3, color)
```

`scripts/war_room/war_sheet_ink.gd` — in `strokes`, after the hollows and before the woods (use the `keep` rect the town loop uses; `px_k` scales the reach ring's px only through `k`, which already carries the window's scale):

```gdscript
	# the map's marks (spec 2026-10-07-war-room-p2 §1.3): sheet-layer glyphs, a
	# brigand's or pirate's reach as a ring
	out["places"] = []
	var per_px := WarMarks.km_per_px(repo)
	for m: Dictionary in WarMarks.inked(repo, "sheet"):
		var at: Vector2 = m["at"]
		if not keep.has_point(at):
			continue
		var hz: Dictionary = repo.war_mark_hazards.get(String(m["type"]), {})
		(out["places"] as Array).append({"at": (at - r.position) * k, "glyph": String(m["glyph"]),
			"hazard_r": 0.0 if hz.is_empty() else float(hz["reach_km"]) / per_px * k})
```

`scripts/war_room/war_fine_print.gd` — in `strokes`, after the minor marks (`marks`) loop:

```gdscript
	# the map's marks as fine print: the fine layer's glyph and name, and a
	# sheet-layer mark's name beside its glyph (spec 2026-10-07-war-room-p2 §1.3)
	out["places"] = []
	var place_px := repo.bal("war_fine_note_px")
	for m: Dictionary in WarMarks.inked(repo, ""):
		var at: Vector2 = m["at"]
		if not r.has_point(at):
			continue
		var fine_layer := String(repo.war_marks[m["type"]]["layer"]) == "fine"
		var pos := (at - r.position) * k + Vector2(repo.bal("war_mark_px") * 0.8, place_px * 0.35)
		var label := String(m["label"])
		var pb := Rect2(pos - Vector2(0, place_px), Vector2(float(label.length()) * place_px * char_w, place_px * 1.2))
		if _clear(pb, taken):
			taken.append(pb)
			(out["places"] as Array).append({"at": (at - r.position) * k, "glyph": String(m["glyph"]) if fine_layer else "",
				"label": label, "label_at": pos})
```

and add `"places": []` to the `out` dictionary's literal at the top of `strokes` (so a sheet with no marks still has the key).

`scripts/war_room/war_ink_painter.gd`:
- in `_draw()`'s sheet branch, before `_draw_hollows(c_ink)`:

```gdscript
	for p: Dictionary in ink.get("places", []):   # the map's marks; a brigand's reach a dotted rubric ring
		var hr := float(p["hazard_r"])
		var glyph_c: Color = pal["rubric"] if hr > 0.0 else c_ink
		if hr > 0.0:
			var ring_c: Color = pal["rubric"]
			ring_c.a = float(px["mark_reach_alpha"])
			var ring := PackedVector2Array()
			for i in 65:
				ring.append((p["at"] as Vector2) + Vector2.from_angle(TAU * float(i) / 64.0) * hr)
			for d: PackedVector2Array in WarSheetInk.dashed(ring, float(px["dash"]) * 0.3, float(px["gap"])):
				draw_polyline(d, ring_c, float(px["seam"]), true)
		WarMarkGlyph.draw(self, String(p["glyph"]), p["at"], float(px["mark"]), glyph_c)
```

- in `_draw_fine()`, after the figures loop:

```gdscript
	for p: Dictionary in ink.get("places", []):
		if String(p["glyph"]) != "":
			WarMarkGlyph.draw(self, String(p["glyph"]), p["at"], float(px["mark"]), c_faint)
		draw_string(font, p["label_at"], String(p["label"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(px["note"]), c_faint)
```

`scripts/war_room/war_room_ink.gd`: the painter's `mark` size and the ring's alpha are not `war_ink_*` keys, so set them after the width loops (leave `INK_PX` alone):

```gdscript
		for k: String in INK_PX:
			widths[k] = repo.bal("war_ink_%s_px" % k)
		for k: String in INK_RATIOS:
			widths[k] = repo.bal("war_ink_%s" % k)
		widths["mark"] = repo.bal("war_mark_px")
		widths["mark_reach_alpha"] = repo.bal("war_mark_reach_alpha")
```

in `texture_for`, and in `fine_for` add `widths["mark"] = repo.bal("war_fine_mark_px")` after its loop. In `WarRoomView._update_detail` (the near-zoom patch) add, after its `INK_RATIOS` loop: `widths["mark"] = _repo.bal("war_mark_px") * scale` and `widths["mark_reach_alpha"] = _repo.bal("war_mark_reach_alpha")`.

- [ ] **Step 4: Import, run the tests**

Import pass; run `tests/war_room/test_war_mark_glyph.gd`, `tests/war_room/test_war_sheet_ink.gd`, `tests/war_room/test_war_fine_print.gd`, `tests/war_room/test_war_room_view.gd`. Expected: PASS.

- [ ] **Step 5: Shoot it**

Real-window shots on the sheet holding the Clifnaltash brigands (find its id with `WarSheets.sheet_of` in a quick headless probe, or try the sheets north of Irongate's capital) at `--war-zoom 1.6` and `0.35`, `--resolution 2560x1600`:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/tools/snapshot_screen.tscn -- --out <scratch>/marks_1.6.png --resolution 2560x1600 --screen root --quiet --war-room --war-cell <ID> --war-zoom 1.6
```

Read them: the crossed swords and their dotted ring at 1.6 m, the brigands' name in fine print at 0.35 m. Breakage fails the task; looks are tuned in Task 6.

- [ ] **Step 6: Commit**

```bash
git add scripts/war_room/war_mark_glyph.gd scripts/war_room/war_mark_glyph.gd.uid scripts/war_room/war_sheet_ink.gd scripts/war_room/war_fine_print.gd scripts/war_room/war_ink_painter.gd scripts/war_room/war_room_ink.gd scripts/war_room/war_room_view.gd tests/war_room/test_war_mark_glyph.gd tests/war_room/test_war_mark_glyph.gd.uid tests/war_room/test_war_sheet_ink.gd tests/war_room/test_war_fine_print.gd
git commit -m "feat(war room): the map's marks inked on the sheet and in the fine print

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The marks in the hover slip

**Files:**
- Modify: `scripts/engine/war_ground.gd` (`reading` → `places`; `lines`)
- Test: `tests/engine/test_war_ground.gd`

**Interfaces:**
- Consumes: `WarMarks.near`, `repo.war_mark_hazards` (Tasks 1-2).
- Produces: `WarGround.reading(...)["places"]: Array` (`WarMarks.near` entries within `war_mark_hover_km`, at most `war_mark_hover_max`); `lines` writes, after the weather line and before the regiment section, one `line` per place — `"<label>, <n> km — <note>"`, plus `"; supply lines within <reach> km lose <p>%"` for a hazard type — then the nearest place's legend cut to `war_mark_legend_chars` as a `sub` line.

- [ ] **Step 1: Write the failing tests**

Add to `tests/engine/test_war_ground.gd`:

```gdscript
func test_the_slip_names_the_marks_near_the_pointer_nearest_first() -> void:
	var all := WarMarks.inked(repo, "")
	var m: Dictionary = all[0]
	var at: Vector2 = (m["at"] as Vector2) + Vector2(0.3, 0.0)
	var r := WarGround.reading(repo, state, at, "")
	var places: Array = r["places"]
	assert_gt(places.size(), 0)
	assert_lte(places.size(), int(repo.bal("war_mark_hover_max")))
	assert_eq(String(places[0]["code"]), String(m["code"]))
	var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_true(texts.any(func(t: String) -> bool: return t.begins_with(String(m["label"]) + ",")))
	var legend := String(m["legend"]).substr(0, int(repo.bal("war_mark_legend_chars")))
	if legend != "":
		assert_true(texts.has(legend))


func test_a_brigand_mark_states_its_toll() -> void:
	for m: Dictionary in WarMarks.inked(repo, "sheet"):
		if String(m["type"]) != "brigands":
			continue
		var r := WarGround.reading(repo, state, m["at"], "")
		var hz: Dictionary = repo.war_mark_hazards["brigands"]
		var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
		@warning_ignore("integer_division")
		var toll := "supply lines within %d km lose %d%%" % [int(hz["reach_km"]), int(hz["permille"]) / 10]
		assert_true(texts.any(func(t: String) -> bool: return t.contains(toll)), toll)
		return
	pass_test("no brigands on this pack")


func test_no_marks_far_from_everything() -> void:
	var r := WarGround.reading(repo, state, _sea_point(), "")
	for p: Dictionary in r["places"]:
		assert_lte(float(p["distance_km"]), repo.bal("war_mark_hover_km"))
```

- [ ] **Step 2: Run to see them fail**

Run `tests/engine/test_war_ground.gd`. Expected: FAIL (`places` missing).

- [ ] **Step 3: Implement**

In `WarGround.reading`, add to the `out` dictionary literal:

```gdscript
		"places": WarMarks.near(repo, at, repo.bal("war_mark_hover_km"), int(repo.bal("war_mark_hover_max"))),
```

In `WarGround.lines`, call `_place_lines(repo, r, out)` on the line before EACH of its two `_regiment_lines(repo, r, raking, out)` calls (the sea branch and the land branch), and add the helper:

```gdscript
## The marks near the pointer (spec 2026-10-07-war-room-p2 §1.3): one line
## each, nearest first, a hazard's toll on supply; the nearest one's legend.
static func _place_lines(repo: DataRepository, r: Dictionary, out: Array) -> void:
	var places: Array = r.get("places", [])
	for p: Dictionary in places:
		var text := "%s, %d km — %s" % [String(p["label"]), roundi(float(p["distance_km"])), String(p["note"])]
		var hz: Dictionary = repo.war_mark_hazards.get(String(p["type"]), {})
		if not hz.is_empty():
			@warning_ignore("integer_division")
			text += "; supply lines within %d km lose %d%%" % [int(hz["reach_km"]), int(hz["permille"]) / 10]
		_add(out, text)
	if not places.is_empty():
		var legend := String(places[0]["legend"]).substr(0, int(repo.bal("war_mark_legend_chars")))
		if legend != "":
			out.append({"text": legend, "kind": "sub"})
```

- [ ] **Step 4: Run the tests**

Run `tests/engine/test_war_ground.gd` and `tests/engine/test_engine_isolation.gd`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/war_ground.gd tests/engine/test_war_ground.gd
git commit -m "feat(war room): the hover slip names the marks near the pointer

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The key slip's marks

**Files:**
- Modify: `scripts/ui/war_margin_key.gd` (`LEGEND`, `_draw_mark`)
- Test: `tests/ui/test_war_margin_key.gd`

**Interfaces:**
- Consumes: `WarMarkGlyph.draw` (Task 3), `repo.war_marks` (Task 1).
- Produces: legend keys `mark_brigands`, `mark_pirates`, `mark_mines`, `mark_battlefields`, `mark_lighthouses` (one per sheet-layer type of `war_marks.csv`, in its file order).

- [ ] **Step 1: Write the failing test**

Add to `tests/ui/test_war_margin_key.gd`:

```gdscript
func test_the_key_lists_every_sheet_mark() -> void:
	var keys := WarMarginKey.legend_keys()
	for type: String in repo.war_marks:
		if String(repo.war_marks[type]["layer"]) == "sheet":
			assert_true(keys.has("mark_" + type), type)
```

(If the file names its repository differently, use its name.)

- [ ] **Step 2: Run to see it fail**

Run `tests/ui/test_war_margin_key.gd`. Expected: FAIL.

- [ ] **Step 3: Implement**

Append to `LEGEND` (after `spy`):

```gdscript
	{"key": "mark_brigands", "label": "Brigands"}, {"key": "mark_pirates", "label": "Pirates"},
	{"key": "mark_mines", "label": "Mine"}, {"key": "mark_battlefields", "label": "Battlefield"},
	{"key": "mark_lighthouses", "label": "Lighthouse"},
```

In `_draw_mark`, before the `match`:

```gdscript
	if key.begins_with("mark_"):
		var row: Dictionary = _repo.war_marks.get(key.trim_prefix("mark_"), {})
		var hazard := _repo.war_mark_hazards.has(key.trim_prefix("mark_"))
		WarMarkGlyph.draw(self, String(row.get("glyph", "dot")), r.get_center(), r.size.y * 0.9,
			pal["rubric"] if hazard else ink)
		return
```

- [ ] **Step 4: Run the tests**

Run `tests/ui/test_war_margin_key.gd` and `tests/ui/test_war_room_screen.gd`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/war_margin_key.gd tests/ui/test_war_margin_key.gd
git commit -m "feat(war room): the key slip shows the marks

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Visual review, documents, the whole suite

**Files:**
- Modify: `data/balance.csv` / `data/war_marks.csv` (tuned values, each with its reason), `scripts/war_room/CLAUDE.md`, `data/CLAUDE.md`

- [ ] **Step 1: Visual review** — invoke the `visual-review` skill. Shots at `--resolution 2560x1600`, before (main) and after: the brigands' sheet at 1.6 / 0.5 / 0.15 m; `--war-hover` resting on the brigands; a coastal sheet with pirates; the key slip. Bracket `war_mark_px` (12 / 16 / 20) and `war_mark_reach_alpha` (0.2 / 0.35 / 0.5). An independent critic ranks them against `taste.md` ("A map mark is ink, not a badge"; the flat parchment chart). Tune; record each tuned value's reason in its note.
- [ ] **Step 2: Documents** — `scripts/war_room/CLAUDE.md` "Ink": a bullet **Marks** (`WarMarks`, `data/war_marks.csv`: sheet / fine layers, `WarMarkGlyph`, a hazard's reach ring); "The hover slip": the near marks. `data/CLAUDE.md`: the two new tables in its list. Keep both under their size caps.
- [ ] **Step 3: Whole suite** — `./run_tests.sh`: green.
- [ ] **Step 4: Commit**

```bash
git add data/balance.csv data/war_marks.csv scripts/war_room/CLAUDE.md data/CLAUDE.md
git commit -m "docs(war room): marks; values tuned at visual review

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Landing

`./run_tests.sh` green; merge main into this branch, rerun; then in the main checkout `git merge --ff-only spec/war-room-p2` and push — per the shared-checkout rule (never switch its branch; check the owner's editor has none of these scripts open first).
