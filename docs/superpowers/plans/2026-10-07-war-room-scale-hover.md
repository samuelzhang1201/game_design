# WAR ROOM scale and hover — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Lay the WAR ROOM's sheets at twice the scale, add fine print that fades in as the officer leans in, and read the ground under the pointer for the chosen regiment in a parchment slip.

**Architecture:** The scale is data (`war_sheet_deg` 20 → 10) plus sheet ids past Z. Fine print is a second sheet texture (`fine_tex`) painted by the existing `WarInkPainter` and faded in by the table shader with the camera's distance; the shader's contour interval steps down as the camera nears. The slip's facts come from a new pure engine module `WarGround` (on top of `ArmySystem`, `Weather`, `Intel`, `Elevation`); `WarRoomView` only emits dwell / aim signals and `WarRoomScreen` (the one `Game` bridge) builds the slip. The near-zoom detail patch (spec §2) is built only if the gate shots in Task 10 call for it.

**Tech Stack:** Godot 4.7, typed GDScript, GUT; the gdai MCP for every `.tscn` / theme change; `tools/snapshot_screen.gd` for real-window shots.

**Spec:** `docs/superpowers/specs/2026-10-07-war-room-scale-hover-design.md`

## Global Constraints

- Design values live in `data/balance.csv` (`key,value,"notes"`), never as constants in scripts; every new `war_*` key is added to the key list in `tests/engine/test_war_room_data.gd`.
- `scripts/war_room/` and `scripts/map3d/` never read the `Game` autoload; `WarRoomScreen` (`scripts/ui/`) is the only bridge. Nothing under `scripts/engine/` names a `scripts/ui/` or `scripts/llm/` class.
- Determinism: no wall clock, no unseeded random in engine code; `WarGround` is read-only and writes no state.
- The LOOK lives in the editor: the slip's scene and its theme label kinds are made through the gdai MCP (editor running), never by text-editing a `.tscn`/`.tres`; check open script buffers against disk before an editor save. A `_ready` sets no look.
- Integer per-mille arithmetic in the engine (`@warning_ignore("integer_division")` where it divides), as `ArmySystem` does.
- Tests take data from `tests/suite_data.gd` (`SuiteData.repo()`, `SuiteData.campaign(repo, seed)`), never `DataRepository.load_all`; wait with `wait_process_frames`, never `wait_frames`.
- No foreign force or foreign garrison is ever shown by the slip.
- Every visual change goes through the `visual-review` skill with real-window shots (`--resolution WxH`, never `--headless` for 3D).
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Work in this worktree; never switch the main checkout's branch.

**Commands used below.** One test file:

```bash
CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_war_sheets.gd -gpre_run_script=res://tests/pre_run.gd -gpost_run_script=res://tests/post_run.gd -gexit
```

(replace the `-gtest=` path per step). Whole suite: `./run_tests.sh` — expect "Errors 2" when the gdai GDExtension binaries are installed in this checkout, 0 when not.

**Before Task 1:** skip the import pass by copying the main checkout's cache: `cp -Rc /Users/samuelzhang/game_design/.godot .godot` (from this worktree's root), then run the whole suite once to record the baseline (it must be green).

## Review Focus

- **A sheet at the map's west or east edge, or one whose column passes Z**: ids like `AA3` must be unique and the index chart must still pick it — pinned in Task 1 (`id_of(26, 0) == "AA1"`, unique ids over the 10° series).
- **The pointer resting over the sea, over unclaimed wildlands, or off the table**: the slip must say "Open sea" / name the wildland manor with no holder, and off the table show nothing — pinned in Task 4 (`reading` over a sea point and a wildland cell) and Task 7 (no `ground_hovered` off the table).
- **A fleet chosen while the pointer rests on land**: one line "A fleet cannot go ashore", never a land pace — pinned in Task 4.
- **A regiment that cannot move** (`day_step_m` 0: an empty banner) and a chosen regiment whose power on plains is 0: no division by zero, no "0 days away" — pinned in Task 4.
- **The rake released, cancelled or dropped while the slip shows**: the slip must hide — pinned in Task 8 (`rake_dropped` hides it).

---

## File Structure

| File | Responsibility |
|---|---|
| `scripts/engine/war_sheets.gd` (modify) | spreadsheet column letters past Z |
| `scripts/war_room/war_room_wall.gd` (modify) | index chart axis every `war_chart_label_every` cells |
| `data/balance.csv` (modify) | the scale keys and every new key |
| `scripts/engine/army_system.gd` (modify) | `power_on` split out of `power` |
| `scripts/engine/war_ground.gd` (create) | the slip's facts and lines, pure |
| `scripts/war_room/war_fine_print.gd` (create) | what the fine print says and where, in texture px, pure |
| `scripts/war_room/war_near.gd` (create) | the near look by camera distance (contour interval, fine alpha), pure |
| `scripts/war_room/war_ink_painter.gd` (modify) | a "fine" paint mode |
| `scripts/war_room/war_room_ink.gd` (modify) | `fine_for`: the fine texture's draw and cache |
| `scenes/war_room/war_table.gdshader` (modify) | `fine_tex`, `fine_alpha` |
| `scripts/war_room/war_room_view.gd` (modify) | fine texture, near uniforms, dwell and aim signals |
| `scripts/war_room/war_hover_dwell.gd` (create) | the pointer's dwell, pure |
| `scenes/war_room/war_hover_slip.tscn` (create, editor) | the slip's look |
| `scripts/ui/war_hover_slip.gd` (create) | fills the slip's lines, places it beside the pointer |
| `scripts/ui/war_room_screen.gd` (modify) | asks `WarGround`, shows / hides the slip |
| `tools/snapshot_screen.gd` (modify) | `--war-hover fx,fy` |
| `scripts/war_room/CLAUDE.md` (modify) | the rules as they now stand |

---

### Task 1: Sheet ids past Z and the index chart's sparser axis

**Files:**
- Modify: `scripts/engine/war_sheets.gd` (`id_of`, add `column_letters`)
- Modify: `scripts/war_room/war_room_wall.gd:28-50` (`build_chart` axis loops)
- Modify: `data/balance.csv` (add `war_chart_label_every`)
- Test: `tests/engine/test_war_sheets.gd`, `tests/war_room/test_war_room_view.gd`, `tests/engine/test_war_room_data.gd`

**Interfaces:**
- Produces: `WarSheets.column_letters(col: int) -> String` ("A".."Z", "AA".."AZ", …); `WarSheets.id_of(col, row)` uses it. Chart axis `Label3D`s keep metas `axis` ("col"/"row") and `n`, now only every `war_chart_label_every`-th index.

- [ ] **Step 1: Write the failing tests**

In `tests/engine/test_war_sheets.gd` add:

```gdscript
func test_columns_past_z_are_lettered_like_a_ledger() -> void:
	assert_eq(WarSheets.column_letters(0), "A")
	assert_eq(WarSheets.column_letters(25), "Z")
	assert_eq(WarSheets.column_letters(26), "AA")
	assert_eq(WarSheets.column_letters(35), "AJ")
	assert_eq(WarSheets.column_letters(51), "AZ")
	assert_eq(WarSheets.column_letters(52), "BA")
	assert_eq(WarSheets.id_of(26, 0), "AA1")
	assert_eq(WarSheets.id_of(35, 17), "AJ18")
```

In `tests/war_room/test_war_room_view.gd` replace `test_the_chart_letters_its_columns_and_numbers_its_rows` with:

```gdscript
func test_the_chart_letters_every_nth_column_and_numbers_every_nth_row() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var g := MapCoords.grid_size(repo, repo.bal("war_sheet_deg"))
	var every := int(repo.bal("war_chart_label_every"))
	var labels := view.get_node("%IndexChart").get_children()
	var cols := labels.filter(func(l: Node) -> bool: return String(l.get_meta("axis")) == "col")
	var rows := labels.filter(func(l: Node) -> bool: return String(l.get_meta("axis")) == "row")
	assert_eq(cols.size(), ceili(float(g.x) / every))
	assert_eq(rows.size(), ceili(float(g.y) / every))
	assert_eq((cols[0] as Label3D).text, "A")
	if cols.size() > 1:
		assert_eq((cols[1] as Label3D).text, WarSheets.column_letters(every))
```

In `tests/engine/test_war_room_data.gd`, add `"war_chart_label_every"` to the key list in `test_every_balance_key_the_room_reads_is_there`.

- [ ] **Step 2: Run them to see them fail**

Run the single-file command for `tests/engine/test_war_sheets.gd`, then `tests/war_room/test_war_room_view.gd`, then `tests/engine/test_war_room_data.gd`.
Expected: FAIL — `column_letters` not found; `war_chart_label_every` missing.

- [ ] **Step 3: Implement**

`scripts/engine/war_sheets.gd` — replace `id_of` and add above it:

```gdscript
## A column's letters, spreadsheet style: A..Z, then AA..AZ, BA.. (a 10°
## series runs past Z: spec 2026-10-07-war-room-scale-hover §1).
static func column_letters(col: int) -> String:
	var out := ""
	var n := col + 1
	while n > 0:
		@warning_ignore("integer_division")  # whole letters
		var r := (n - 1) % 26
		out = char(65 + r) + out
		@warning_ignore("integer_division")
		n = (n - 1) / 26
	return out


static func id_of(col: int, row: int) -> String:
	return "%s%d" % [column_letters(col), row + 1]
```

`scripts/war_room/war_room_wall.gd` in `build_chart`, change the two axis loops to step by the key and use `column_letters`:

```gdscript
	var every := maxi(1, int(repo.bal("war_chart_label_every")))
	for col in range(0, g.x, every):
		var cx := (minf(MapCoords.cell_rect(repo, Vector2i(col, 0), deg).get_center().x, w) / w - 0.5) * size.x
		var l := _label(WarSheets.column_letters(col), font, repo.war_palette["rubric"], Vector3(cx, size.y * 0.5 + margin, lift),
			font_px, pixel_m, false)
		l.set_meta("axis", "col")
		l.set_meta("n", col)
		chart.add_child(l)
	for row in range(0, g.y, every):
		var cy := (0.5 - minf(MapCoords.cell_rect(repo, Vector2i(0, row), deg).get_center().y, h) / h) * size.y
		var l := _label(str(row + 1), font, repo.war_palette["rubric"], Vector3(-size.x * 0.5 - margin, cy, lift),
			font_px, pixel_m, false)
		l.set_meta("axis", "row")
		l.set_meta("n", row)
		chart.add_child(l)
```

`data/balance.csv` — add after the other `war_chart_*` rows:

```csv
war_chart_label_every,1,"WAR ROOM scale (spec 2026-10-07-war-room-scale-hover §1): the index chart letters a column and numbers a row every this many cells; 1 at 20° sheets, 2 once the series is 36 x 18"
```

- [ ] **Step 4: Run the three files again**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/war_sheets.gd scripts/war_room/war_room_wall.gd data/balance.csv tests/engine/test_war_sheets.gd tests/war_room/test_war_room_view.gd tests/engine/test_war_room_data.gd
git commit -m "feat(war room): sheet ids past Z, the index chart's axis every Nth cell

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Twice the scale

**Files:**
- Modify: `data/balance.csv` (`war_sheet_deg`, `war_grid_deg`, `war_chart_label_every`, `war_ink_wood_step_km`, `war_sheet_collar_km`)
- Test: whatever the full suite shows assumes 20° (see Step 3)

**Interfaces:**
- Consumes: Task 1's `column_letters`.
- Produces: the 10° series every later task lays.

- [ ] **Step 1: Write the failing test**

In `tests/engine/test_war_sheets.gd` add (the pack is beria-shaped but the test names no pack — it reads the grid from the key):

```gdscript
func test_the_series_is_cut_at_ten_degrees_and_its_ids_are_unique() -> void:
	assert_eq(repo.bal("war_sheet_deg"), 10.0)
	var g := MapCoords.grid_size(repo, repo.bal("war_sheet_deg"))
	var seen: Dictionary = {}
	for s: Dictionary in WarSheets.series(repo):
		assert_lt(int(s["col"]), g.x)
		assert_lt(int(s["row"]), g.y)
		assert_false(seen.has(s["id"]), "id %s is unique" % s["id"])
		seen[s["id"]] = true
	assert_gt(g.x, 26, "the series runs past Z")
```

- [ ] **Step 2: Run it to see it fail**

Run `tests/engine/test_war_sheets.gd`. Expected: FAIL (`war_sheet_deg` is 20).

- [ ] **Step 3: Change the keys, then fix what assumed 20°**

In `data/balance.csv` set (keep each row's notes and append the new reason):

| key | old | new | note to append |
|---|---|---|---|
| `war_sheet_deg` | 20 | 10 | `(2026-10-07, spec 2026-10-07-war-room-scale-hover §1: twice the scale — a sheet ~71 x 52 km, 36 x 18 cells)` |
| `war_grid_deg` | 2 | 1 | `(2026-10-07 §1: ~7 x 5 km squares, 10 x 10 a sheet; set at the visual review)` |
| `war_chart_label_every` | 1 | 2 | `(2026-10-07 §1)` |
| `war_ink_wood_step_km` | 2.2 | 1.1 | `(2026-10-07 §1: half the ground per table metre keeps the glyphs' density on the table)` |
| `war_sheet_collar_km` | 12 | 6 | `(2026-10-07 §1: the same collar on the table at twice the scale)` |

Then run `./run_tests.sh`. For each failure, read the test: if its expectation was derived from 20° sheets (a hard-coded sheet id, a count of sheets, a grid row past the 10° sheet's 10 rows, a sheet holding two places now on two sheets), change the expectation to derive from `WarSheets.series(repo)` / the keys; if it fails for any other reason, stop and report it. Known ones to check first: `tests/engine/test_war_room.gd` (partition / on_sheet), `tests/war_room/test_war_index_chart.gd`, `tests/war_room/test_war_sheet_ink.gd`, `tests/ui/test_war_room_screen.gd`, `tests/ui/test_war_margin_key.gd`, `tests/engine/test_war_folio.gd`.

- [ ] **Step 4: Run the whole suite**

Run: `./run_tests.sh`. Expected: green, with the expected error count.

- [ ] **Step 5: Shoot the new scale (no tuning yet)**

```bash
S=$(mktemp -d); /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/tools/snapshot_screen.tscn -- --out $S/scale_1.6.png --resolution 1920x1200 --screen root --quiet --war-room --war-zoom 1.6
```

Repeat for `--war-zoom 0.5` and `0.12` (each run quits after its shot; kill it if it has not written the file in 4 minutes). Read each shot: the sheet must lay, the chart must show letters every second column, pieces must stand. Record anything broken as a failure of this task; looks are tuned in Task 9.

- [ ] **Step 6: Commit**

```bash
git add data/balance.csv tests
git commit -m "feat(war room): sheets at 10 degrees — twice the scale (spec 2026-10-07 §1)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: `ArmySystem.power_on` — power on a given ground

**Files:**
- Modify: `scripts/engine/army_system.gd` (`power`, new `power_on`)
- Test: `tests/engine/test_army_power.gd`

**Interfaces:**
- Produces: `ArmySystem.power_on(repo: DataRepository, state: GameState, code: String, stance: String, terrain: String, works: String) -> int`. `power(repo, state, code, stance)` returns `power_on(repo, state, code, stance, terrain_of(...), works_of(...))`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/engine/test_army_power.gd`:

```gdscript
func test_power_is_power_on_its_own_ground() -> void:
	var s := SuiteData.campaign(repo, 7)
	for code: String in _land_codes():
		var reg := ArmySystem.regiment(repo, code)
		for stance in ["defend", "attack"]:
			assert_eq(ArmySystem.power(repo, s, code, stance),
				ArmySystem.power_on(repo, s, code, stance, ArmySystem.terrain_of(repo, reg, s), ArmySystem.works_of(repo, reg, s)),
				"%s %s" % [code, stance])


func test_archers_alone_on_hills_by_the_terrain_table() -> void:
	var r := SuiteData.repo()
	var s := SuiteData.campaign(r, 7)
	var code: String = _land_codes()[0]
	var row: Dictionary = r.world_table("military", "regiments")[code]
	for arm in ["infantry", "cavalry", "artillery", "fleet"]:
		row[arm] = "0"
	row["archers"] = "800"
	var plains_d := ArmySystem.power_on(r, s, code, "defend", "plains", "")
	var plains_a := ArmySystem.power_on(r, s, code, "attack", "plains", "")
	# army_terrain.csv: hills,archers,1150,1050
	assert_almost_eq(float(ArmySystem.power_on(r, s, code, "defend", "hills", "")) / plains_d, 1.15, 0.01)
	assert_almost_eq(float(ArmySystem.power_on(r, s, code, "attack", "hills", "")) / plains_a, 1.05, 0.01)
	# army_town_defence.csv: walls,archers defend 1250, attack untouched
	assert_almost_eq(float(ArmySystem.power_on(r, s, code, "defend", "plains", "walls")) / plains_d, 1.25, 0.01)
	assert_eq(ArmySystem.power_on(r, s, code, "attack", "plains", "walls"), plains_a)
```

(The expected ratios are the CSV rows: `hills,archers,1150,1050` in `data/army_terrain.csv`, `walls,archers,1250,1000` in `data/army_town_defence.csv`. If either row has changed, update the figure from the CSV, not from the code.)

- [ ] **Step 2: Run to see them fail**

Run `tests/engine/test_army_power.gd`. Expected: FAIL — `power_on` not found.

- [ ] **Step 3: Implement**

In `scripts/engine/army_system.gd`, rename the body of `power` into `power_on` and make `power` call it:

```gdscript
static func power(repo: DataRepository, state: GameState, code: String, stance: String) -> int:
	var reg := regiment(repo, code)
	if reg.is_empty():
		return 0
	return power_on(repo, state, code, stance, terrain_of(repo, reg, state), works_of(repo, reg, state))


## power(), on a given ground: `terrain` (terrain_at's words) and `works`
## ("citadel", "walls", "town" or ""). The WAR ROOM's slip reads a regiment
## on ground it does not stand on (spec 2026-10-07-war-room-scale-hover §4.1).
static func power_on(repo: DataRepository, state: GameState, code: String, stance: String,
		terrain: String, works: String) -> int:
	var reg := regiment(repo, code)
	var st := state_of(repo, state, code)
	if reg.is_empty() or st.is_empty():
		return 0
	var heads := headcount(repo, reg)
	if heads <= 0:
		return 0
	# … the existing body of power() from `var fit := …` to `return total`,
	# unchanged, minus its two lines `var terrain := terrain_of(...)` and
	# `var works := works_of(...)` (now parameters) …
```

Move the existing body verbatim (the long precision comment included); only the two `var terrain` / `var works` lines go.

- [ ] **Step 4: Run the power and system tests**

Run `tests/engine/test_army_power.gd` and `tests/engine/test_army_system.gd`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/army_system.gd tests/engine/test_army_power.gd
git commit -m "refactor(armies): power_on — a regiment's power on a given ground

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: `WarGround` — what the ground under the pointer means

**Files:**
- Create: `scripts/engine/war_ground.gd`
- Test: `tests/engine/test_war_ground.gd`

**Interfaces:**
- Consumes: `ArmySystem.power_on` (Task 3).
- Produces:
  - `WarGround.reading(repo: DataRepository, state: GameState, at: Vector2, code: String) -> Dictionary` with keys `place: String`, `holder: String` (kingdom code or ""), `sea: bool`, `terrain: String`, `metres: int`, `road: String`, `town: String` (burg code or ""), `works: String`, `town_holder: String`, `garrison: Array[String]` (regiment labels; only in a town the player's realm holds), `weather: String` (a `Weather` kind), `regiment: Dictionary` ({} when `code` is ""; else `code`, `label`, `ashore: bool` and, when not ashore, `defend: int`, `attack: int` (per mille vs open plains), `delta_m: int`, `height: int` (per mille), `ground: int` (per mille), `km_day: float`, `days: int`).
  - `WarGround.lines(repo: DataRepository, reading: Dictionary, raking := false) -> Array` of `{"text": String, "kind": String}`, kinds `title`, `sub`, `line`, `rule`, `rubric`.

- [ ] **Step 1: Write the failing tests**

Create `tests/engine/test_war_ground.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The WAR ROOM slip's facts (spec 2026-10-07-war-room-scale-hover §4.1): the
## ground under the pointer, read for the chosen regiment; never a foreign force.

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)


func _land_code() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


func _naval_code() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) == "1":
			return String(r["regiment_code"])
	return ""


func _land_point() -> Vector2:
	var code := _land_code()
	return ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code))


func _sea_point() -> Vector2:
	for id: int in repo.cells:
		if MapTerrain.is_sea(repo.cells[id]):
			return MapTerrain.cell_center(repo, repo.cells[id])
	return Vector2(-1, -1)


func test_the_ground_alone_with_no_regiment_chosen() -> void:
	var at := _land_point()
	var r := WarGround.reading(repo, state, at, "")
	assert_false(bool(r["sea"]))
	assert_eq(r["terrain"], ArmySystem.terrain_at(repo, at))
	assert_eq(r["road"], ArmySystem.road_at(repo, at))
	assert_eq(r["metres"], Elevation.metres_of_cell(repo, MapEconomy.cell_at(repo, at)))
	assert_eq(r["place"], Intel.place_label(repo, state, at))
	assert_eq(r["regiment"], {})
	var kinds := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["kind"]))
	assert_false(kinds.has("rubric"), "no regiment section without a choice")


func test_the_sea_reads_as_open_sea() -> void:
	var at := _sea_point()
	var r := WarGround.reading(repo, state, at, "")
	assert_true(bool(r["sea"]))
	assert_eq(String(WarGround.lines(repo, r)[0]["text"]), "the open sea")


func test_a_chosen_regiment_reads_its_factors_against_open_plains() -> void:
	var code := _land_code()
	var at := _land_point() + Vector2(3, 3)
	var r := WarGround.reading(repo, state, at, code)
	var g: Dictionary = r["regiment"]
	var town := String(r["town"])
	var works := String(r["works"]) if town != "" and String(r["town_holder"]) == String(ArmySystem.regiment(repo, code)["kingdom_code"]) else ""
	var plains := ArmySystem.power_on(repo, state, code, "defend", "plains", "")
	@warning_ignore("integer_division")
	assert_eq(g["defend"], ArmySystem.power_on(repo, state, code, "defend", String(r["terrain"]), works) * 1000 / plains)
	assert_eq(g["ground"], ArmySystem.ground_permille(repo, ArmySystem.regiment(repo, code), at))
	assert_eq(g["height"], ArmySystem.height_factor(repo, int(g["delta_m"])))
	assert_gte(int(g["days"]), 1)


func test_a_fleet_cannot_go_ashore() -> void:
	var code := _naval_code()
	if code == "":
		pass_test("the realm has no fleet")
		return
	var r := WarGround.reading(repo, state, _land_point(), code)
	assert_true(bool(r["regiment"]["ashore"]))
	var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_true(texts.has("A fleet cannot go ashore"))


func test_an_empty_banner_reads_no_power_no_pace_and_no_days() -> void:
	var code := _land_code()
	var at := _land_point() + Vector2(3, 3)
	var row: Dictionary = repo.world_table("military", "regiments")[code]
	for arm in ["infantry", "archers", "cavalry", "artillery", "fleet"]:
		row[arm] = "0"   # day_step_m is 0 only for an empty banner (base_pace_km 0)
	var r := WarGround.reading(repo, state, at, code)
	var g: Dictionary = r["regiment"]
	assert_eq(int(g["defend"]), 0)
	assert_eq(int(g["days"]), 0)
	var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_true(texts.any(func(t: String) -> bool: return t.contains("cannot march")))


func test_a_foreign_town_never_shows_a_garrison() -> void:
	var mine := repo.resolve_realm("player_realm")
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		var at := Vector2(float(b["x"]), float(b["y"]))
		var holder := MapOwnership.owner_of(repo, state, String(b.get("province_code", "")))
		if holder == mine or holder == "":
			continue
		var r := WarGround.reading(repo, state, at, "")
		assert_eq(r["garrison"], [], "foreign town %s" % code)
		return
	pass_test("no foreign town on this pack")


func test_raking_leaves_the_days_out() -> void:
	var r := WarGround.reading(repo, state, _land_point() + Vector2(3, 3), _land_code())
	var texts := WarGround.lines(repo, r, true).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_false(texts.any(func(t: String) -> bool: return t.contains("away")))
```

- [ ] **Step 2: Run to see them fail**

Run `tests/engine/test_war_ground.gd`. Expected: FAIL — `WarGround` not found.

- [ ] **Step 3: Implement**

Create `scripts/engine/war_ground.gd`:

```gdscript
class_name WarGround
extends RefCounted
## What the ground under the WAR ROOM's pointer means (spec
## 2026-10-07-war-room-scale-hover §4.1): the place, the ground, the town and
## the weather; with a regiment chosen, its defend and attack against open
## plains, its height against where it stands, its pace and the days to get
## there. Read-only; never a foreign force or a foreign garrison.


static func reading(repo: DataRepository, state: GameState, at: Vector2, code: String) -> Dictionary:
	var cell := MapEconomy.cell_at(repo, at)
	var sea := cell < 0 or MapTerrain.is_water(repo.cells[cell])
	var prov := MapManors.province_of(repo, cell, state) if cell >= 0 else ""
	var town := "" if sea else ArmySystem.town_at(repo, at)
	var town_holder := ""
	var works := ""
	var garrison: Array[String] = []
	if town != "":
		var b: Dictionary = repo.burgs[town]
		town_holder = MapOwnership.owner_of(repo, state, String(b.get("province_code", "")))
		var feats := String(b.get("features", "")).split("|")
		works = "citadel" if "citadel" in feats else ("walls" if "walls" in feats else "town")
		if town_holder == repo.resolve_realm("player_realm"):
			for r: Dictionary in MapObjects.regiments_of(repo, town_holder):
				if ArmySystem.town_of(repo, r, state) == town:
					garrison.append(String(r.get("label", r["regiment_code"])))
	var out := {
		"place": Intel.place_label(repo, state, at),
		"holder": MapOwnership.owner_of(repo, state, prov) if prov != "" else "",
		"sea": sea,
		"terrain": "sea" if sea else ArmySystem.terrain_at(repo, at),
		"metres": Elevation.metres_of_cell(repo, cell),
		"road": "" if sea else ArmySystem.road_at(repo, at),
		"town": town, "works": works, "town_holder": town_holder, "garrison": garrison,
		"weather": Weather.at(repo, state, at, state.absolute_day()) if state != null else Weather.CLEAR,
		"regiment": {},
	}
	if code != "":
		out["regiment"] = _for_regiment(repo, state, at, code, out)
	return out


static func _for_regiment(repo: DataRepository, state: GameState, at: Vector2, code: String, g: Dictionary) -> Dictionary:
	var reg := ArmySystem.regiment(repo, code)
	var naval := String(reg.get("is_naval", "0")) == "1"
	var out := {"code": code, "label": String(reg.get("label", code)), "ashore": naval and not bool(g["sea"])}
	if bool(out["ashore"]):
		return out
	var works := String(g["works"]) if String(g["town"]) != "" and String(g["town_holder"]) == String(reg.get("kingdom_code", "")) else ""
	out["defend"] = _factor(repo, state, code, "defend", String(g["terrain"]), works)
	out["attack"] = _factor(repo, state, code, "attack", String(g["terrain"]), "")
	out["delta_m"] = int(g["metres"]) - ArmySystem.elevation_of(repo, reg, state)
	out["height"] = ArmySystem.height_factor(repo, int(out["delta_m"]))
	out["ground"] = ArmySystem.ground_permille(repo, reg, at)
	var step := ArmySystem.day_march_at(repo, state, code, at)
	out["km_day"] = float(maxi(step, 0)) / 1000.0
	out["days"] = ArmySystem.march_days_between(repo, state, code, ArmySystem.position_of(repo, state, reg), at) if step > 0 else 0
	return out


## Power on this ground over power on open plains with no works, per mille;
## 0 for a regiment with no power.
static func _factor(repo: DataRepository, state: GameState, code: String, stance: String, terrain: String, works: String) -> int:
	var base := ArmySystem.power_on(repo, state, code, stance, "plains", "")
	if base <= 0:
		return 0
	@warning_ignore("integer_division")  # whole per mille
	return ArmySystem.power_on(repo, state, code, stance, terrain, works) * 1000 / base


## The slip's lines, in order. `raking`: the arrow's reading already carries
## the days, so they are left out.
static func lines(repo: DataRepository, r: Dictionary, raking := false) -> Array:
	var out: Array = []
	out.append({"text": String(r["place"]), "kind": "title"})
	if bool(r["sea"]):
		_add(out, "Weather: " + Weather.describe_kind(repo, String(r["weather"])))
		_regiment_lines(repo, r, raking, out)
		return out
	if String(r["holder"]) != "":
		out.append({"text": String((repo.kingdoms.get(r["holder"], {}) as Dictionary).get("label", r["holder"])), "kind": "sub"})
	_add(out, "%s · %s m" % [String(r["terrain"]).capitalize(), Intel.num(int(r["metres"]))])
	match String(r["road"]):
		"road":
			_add(out, "On a road")
		"trail":
			_add(out, "On a trail")
		_:
			_add(out, "Open field — no road within %s km" % String.num(repo.bal("army_road_reach_m") / 1000.0, 1))
	if String(r["town"]) != "":
		var b: Dictionary = repo.burgs[r["town"]]
		var name := String(b.get("label", r["town"]))
		var text: String = {"citadel": "In the citadel of %s", "walls": "Behind the walls of %s"}.get(String(r["works"]), "In %s") % name
		if String(r["town_holder"]) != "" and String(r["town_holder"]) != repo.resolve_realm("player_realm"):
			text += " — held by " + String((repo.kingdoms.get(r["town_holder"], {}) as Dictionary).get("label", r["town_holder"]))
		_add(out, text)
		if not (r["garrison"] as Array).is_empty():
			_add(out, "Garrison: " + ", ".join(r["garrison"]))
	_add(out, "Weather: " + Weather.describe_kind(repo, String(r["weather"])))
	_regiment_lines(repo, r, raking, out)
	return out


static func _regiment_lines(_repo: DataRepository, r: Dictionary, raking: bool, out: Array) -> void:
	var g: Dictionary = r["regiment"]
	if g.is_empty():
		return
	out.append({"text": "", "kind": "rule"})
	out.append({"text": "%s here" % g["label"], "kind": "rubric"})
	if bool(g["ashore"]):
		_add(out, "A fleet cannot go ashore")
		return
	_add(out, "Defend ×%.2f · Attack ×%.2f" % [float(g["defend"]) / 1000.0, float(g["attack"]) / 1000.0])
	var d := int(g["delta_m"])
	if d == 0:
		_add(out, "Level with its ground now")
	else:
		_add(out, "%d m %s its ground now (×%.2f)" % [absi(d), "above" if d > 0 else "below", float(g["height"]) / 1000.0])
	if float(g["km_day"]) <= 0.0:
		_add(out, "It cannot march")
		return
	var pace := "Pace ×%.2f · about %d km a day" % [float(g["ground"]) / 1000.0, roundi(float(g["km_day"]))]
	if not raking:
		pace += " · %d day%s away" % [int(g["days"]), "" if int(g["days"]) == 1 else "s"]
	_add(out, pace)


static func _add(out: Array, text: String) -> void:
	out.append({"text": text, "kind": "line"})
```

- [ ] **Step 4: Run the test file**

Expected: PASS. Then run `tests/engine/test_engine_isolation.gd` (or the isolation test under `tests/engine/`) — expected PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/war_ground.gd tests/engine/test_war_ground.gd
git commit -m "feat(war room): WarGround — the ground under the pointer, read for the chosen regiment

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The fine print's content (pure)

**Files:**
- Create: `scripts/war_room/war_fine_print.gd`
- Modify: `data/balance.csv` (fine print keys)
- Test: `tests/war_room/test_war_fine_print.gd`, `tests/engine/test_war_room_data.gd`

**Interfaces:**
- Consumes: `WarSheetInk.town_label_box`, `WarSheetInk.manor_label_box`, `WarSheetInk.TOWN_TIERS`, `Elevation.landmarks`, `WarBake.heights(rect, nx, nz)`.
- Produces: `WarFinePrint.strokes(repo, state, sheet: Dictionary, tex_px: int, bake: WarBake) -> Dictionary` with arrays `notes` (`{at: Vector2, text: String}`), `routes` (`{at, angle: float, text}`), `marks` (`{at, kind: "high"|"low", metres: int}`), `figures` (`{at, angle, text}`), all in the sheet's ink texture px. `WarFinePrint.contour_figures(heights: PackedFloat32Array, nx: int, nz: int, size_px: Vector2, level_m: float, spacing_px: float) -> Array` (`{at, angle, metres: int}`), pure.

- [ ] **Step 1: Write the failing tests**

Create `tests/war_room/test_war_fine_print.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The fine print a leaning officer reads (spec 2026-10-07-war-room-scale-hover §3).

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	WarSheets.forget()


func test_figures_lie_on_their_contour_and_keep_apart() -> void:
	# a ramp rising 100 m a column over 21 columns: the 500 m contour at x = 5,
	# the 1000 m at x = 10, the 1500 m at 15, the 2000 m at 20
	var nx := 21
	var nz := 11
	var h := PackedFloat32Array()
	for z in nz:
		for x in nx:
			h.append(float(x) * 100.0)
	var size := Vector2(2000, 1000)   # 100 px a column
	var figs := WarFinePrint.contour_figures(h, nx, nz, size, 500.0, 400.0)
	assert_gt(figs.size(), 0)
	for f: Dictionary in figs:
		var m := int(f["metres"])
		assert_eq(m % 500, 0)
		assert_almost_eq((f["at"] as Vector2).x, float(m) / 100.0 * 100.0, 1.0, "on its contour")
		assert_almost_eq(absf(float(f["angle"])), PI * 0.5, 0.01, "turned along a north-south contour")
	for i in figs.size():
		for j in range(i + 1, figs.size()):
			if int(figs[i]["metres"]) == int(figs[j]["metres"]):
				assert_gte((figs[i]["at"] as Vector2).distance_to(figs[j]["at"]), 400.0)


func test_flat_ground_has_no_figures() -> void:
	var h := PackedFloat32Array()
	h.resize(100)
	h.fill(120.0)
	assert_eq(WarFinePrint.contour_figures(h, 10, 10, Vector2(1000, 1000), 500.0, 100.0), [])


func test_a_town_note_says_size_works_souls_and_height() -> void:
	var sheet: Dictionary = WarSheets.series(repo)[WarSheets.sheet_of(repo, ArmySystem.position_of(repo, state,
		ArmySystem.regiment(repo, MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0]["regiment_code"])))]
	var fine := WarFinePrint.strokes(repo, state, sheet, int(repo.bal("war_sheet_texture_px")), null)
	var r: Rect2 = sheet["rect"]
	var expected: Array = []
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		if r.has_point(Vector2(float(b["x"]), float(b["y"]))):
			expected.append(WarFinePrint.town_note(b))
	var notes: Array = (fine["notes"] as Array).map(func(n: Dictionary) -> String: return String(n["text"]))
	for t: String in notes:
		assert_true(expected.has(t))
	assert_eq(WarFinePrint.town_note({"group": "city", "features": "walls|citadel", "population": "14061", "elevation_m": "961"}),
		"city · citadel · 14,061 souls · 961 m")
	assert_eq(WarFinePrint.town_note({"group": "village", "features": "", "population": "1644", "elevation_m": "729"}),
		"village · open · 1,644 souls · 729 m")


func test_route_names_are_never_upside_down() -> void:
	for s: Dictionary in WarSheets.series(repo):
		var fine := WarFinePrint.strokes(repo, state, s, int(repo.bal("war_sheet_texture_px")), null)
		for rt: Dictionary in fine["routes"]:
			assert_between(float(rt["angle"]), -PI * 0.5 - 0.001, PI * 0.5 + 0.001, String(rt["text"]))
		if not (fine["routes"] as Array).is_empty():
			return
	fail_test("no sheet has a named route")


func test_fine_boxes_never_touch_a_town_name() -> void:
	for s: Dictionary in WarSheets.series(repo).slice(0, 12):
		var k := float(int(repo.bal("war_sheet_texture_px"))) / (s["rect"] as Rect2).size.x
		var ink := WarSheetInk.strokes(repo, state, s, int(repo.bal("war_sheet_texture_px")))
		var fine := WarFinePrint.strokes(repo, state, s, int(repo.bal("war_sheet_texture_px")), null)
		var towns: Array = (ink["towns"] as Array).map(func(t: Dictionary) -> Rect2: return WarSheetInk.town_label_box(repo, t))
		for m: Dictionary in fine["marks"]:
			for box: Rect2 in towns:
				assert_false(box.has_point(m["at"]), "a mark sits in a town's name box")
		assert_gt(k, 0.0)
```

Add to `tests/engine/test_war_room_data.gd`'s key list: `"war_fine_note_px", "war_fine_route_px", "war_fine_mark_px", "war_fine_figure_px", "war_fine_contour_level_m", "war_fine_contour_label_km", "war_fine_contour_grid"`.

- [ ] **Step 2: Run to see them fail**

Run `tests/war_room/test_war_fine_print.gd`. Expected: FAIL — `WarFinePrint` not found.

- [ ] **Step 3: Implement**

Add to `data/balance.csv` (after the `war_ink_*` rows):

```csv
war_fine_note_px,16,"WAR ROOM fine print (spec 2026-10-07-war-room-scale-hover §3): a town's second line (size · works · souls · height), ink px"
war_fine_route_px,16,"WAR ROOM fine print §3: a route's name along its middle run, ink px"
war_fine_mark_px,6,"WAR ROOM fine print §3: a minor peak's / hollow's mark, ink px (the major ones are war_ink_town_px)"
war_fine_figure_px,15,"WAR ROOM fine print §3: an index contour's figure, ink px, in rubric"
war_fine_contour_level_m,500,"WAR ROOM fine print §3: the contours whose height is written — a multiple of the near contours (war_contour_near_m x war_contour_index_every) and of the middle step's index (100 x 5), so a figure always sits on a drawn line"
war_fine_contour_label_km,8,"WAR ROOM fine print §3: no two figures of one height nearer than this, in the pack's measure"
war_fine_contour_grid,256,"WAR ROOM fine print §3: the heights' grid across a sheet for finding the figures (a 71 km sheet: ~280 m a sample, near the bake's 400 m)"
```

Create `scripts/war_room/war_fine_print.gd`:

```gdscript
class_name WarFinePrint
extends RefCounted
## What a leaning officer reads that the overview never shows (spec
## 2026-10-07-war-room-scale-hover §3), in the sheet's ink texture px: each
## town's second line, the routes' names, the minor peaks and hollows, and the
## heights written on the contours. Only public, static facts of the map. A
## box that would touch a town's or a manor's name is left out. Pure.


## "city · citadel · 14,061 souls · 961 m".
static func town_note(b: Dictionary) -> String:
	var feats := String(b.get("features", "")).split("|")
	var works := "citadel" if "citadel" in feats else ("walls" if "walls" in feats else "open")
	return "%s · %s · %s souls · %s m" % [String(b.get("group", "")), works,
		Intel.num(int(float(b.get("population", "0")))), String(b.get("elevation_m", "0"))]


static func strokes(repo: DataRepository, state: GameState, sheet: Dictionary, tex_px: int, bake: WarBake) -> Dictionary:
	var r: Rect2 = sheet["rect"]
	var k := float(tex_px) / r.size.x
	var ink := WarSheetInk.strokes(repo, state, sheet, tex_px)
	var taken: Array = []   # Rect2 boxes, ink px: the names already on the sheet
	for t: Dictionary in ink["towns"]:
		taken.append(WarSheetInk.town_label_box(repo, t))
	for m: Dictionary in ink.get("manors", []):
		taken.append(WarSheetInk.manor_label_box(repo, m))
	var out := {"notes": [], "routes": [], "marks": [], "figures": []}
	var note_px := repo.bal("war_fine_note_px")
	var char_w := repo.bal("war_ink_char_w")
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var b: Dictionary = repo.burgs[code]
		var at := Vector2(float(b["x"]), float(b["y"]))
		if not r.has_point(at):
			continue
		var tier := 3 if String(b.get("is_capital", "0")) == "1" else int(WarSheetInk.TOWN_TIERS.get(String(b.get("group", "")), 0))
		var box := WarSheetInk.town_label_box(repo, {"at": (at - r.position) * k, "tier": tier, "label": String(b["label"])})
		var text := town_note(b)
		# under the name, left-aligned with it
		var pos := Vector2(box.position.x + box.size.y, box.end.y + note_px * 0.9)
		var nb := Rect2(pos - Vector2(0, note_px), Vector2(float(text.length()) * note_px * char_w, note_px * 1.2))
		if _clear(nb, taken):
			taken.append(nb)
			(out["notes"] as Array).append({"at": pos, "text": text})
	var route_px := repo.bal("war_fine_route_px")
	var tex_rect := Rect2(Vector2.ZERO, r.size * k)
	var rcodes: Array = repo.routes.keys()
	rcodes.sort()
	for code: String in rcodes:
		var row: Dictionary = repo.routes[code]
		var label := String(row.get("label", ""))
		if label == "" or not ["roads", "trails"].has(String(row.get("group", ""))):
			continue
		var poly: PackedVector2Array = row["polyline"]
		var best := -1
		var best_len := 0.0
		for i in poly.size() - 1:
			var a := (poly[i] - r.position) * k
			var b2 := (poly[i + 1] - r.position) * k
			if tex_rect.has_point(a) and tex_rect.has_point(b2) and a.distance_to(b2) > best_len:
				best_len = a.distance_to(b2)
				best = i
		if best < 0 or best_len < float(label.length()) * route_px * char_w:
			continue
		var p0 := (poly[best] - r.position) * k
		var p1 := (poly[best + 1] - r.position) * k
		var ang := (p1 - p0).angle()
		if ang > PI * 0.5:
			ang -= PI
		elif ang < -PI * 0.5:
			ang += PI
		var mid := (p0 + p1) * 0.5
		var w := float(label.length()) * route_px * char_w
		var rb := Rect2(mid - Vector2(w * 0.5, route_px), Vector2(w, route_px * 1.2))
		if _clear(rb, taken):
			taken.append(rb)
			(out["routes"] as Array).append({"at": mid, "angle": ang, "text": label})
	var mark_px := repo.bal("war_fine_mark_px")
	for m: Dictionary in Elevation.landmarks(repo):
		if int(m["lod"]) == 0 or not r.has_point(m["pos"]):
			continue
		var at := ((m["pos"] as Vector2) - r.position) * k
		var mb := Rect2(at - Vector2(mark_px, mark_px), Vector2(mark_px * 2.0 + note_px * 4.0, mark_px * 2.0))
		if _clear(mb, taken):
			taken.append(mb)
			(out["marks"] as Array).append({"at": at, "kind": String(m["kind"]), "metres": int(m["metres"])})
	if bake != null:
		var nx := int(repo.bal("war_fine_contour_grid"))
		var nz := WarRoomTable.rows_for(r, nx)
		var heights := bake.heights(r, nx, nz)
		var spacing := repo.bal("war_fine_contour_label_km") * WarSheets.px_per_unit(repo) * k
		for f: Dictionary in contour_figures(heights, nx, nz, r.size * k, repo.bal("war_fine_contour_level_m"), spacing):
			var fb := Rect2((f["at"] as Vector2) - Vector2(note_px, note_px * 0.6), Vector2(note_px * 2.0, note_px * 1.2))
			if _clear(fb, taken):
				taken.append(fb)
				(out["figures"] as Array).append({"at": f["at"], "angle": f["angle"], "text": str(int(f["metres"]))})
	return out


static func _clear(box: Rect2, taken: Array) -> bool:
	for t: Rect2 in taken:
		if t.intersects(box):
			return false
	return true


## Where the `level_m` multiples cross the grid's edges, each with its
## contour's direction (normalised so the figure is never upside down), no
## two of one height nearer than `spacing_px`. `heights` is nx x nz, row-major
## z outer, spanning `size_px`. Pure.
static func contour_figures(heights: PackedFloat32Array, nx: int, nz: int, size_px: Vector2,
		level_m: float, spacing_px: float) -> Array:
	var out: Array = []
	if nx < 2 or nz < 2 or level_m <= 0.0 or heights.size() < nx * nz:
		return out
	var cell := Vector2(size_px.x / float(nx - 1), size_px.y / float(nz - 1))
	for z in nz:
		for x in nx - 1:
			var h0 := heights[z * nx + x]
			var h1 := heights[z * nx + x + 1]
			var lo := minf(h0, h1)
			var hi := maxf(h0, h1)
			var level := ceilf(lo / level_m) * level_m
			if level <= 0.0 or level > hi or hi == lo:
				continue
			var t := (level - h0) / (h1 - h0)
			var at := Vector2((float(x) + t) * cell.x, float(z) * cell.y)
			# the gradient from the neighbouring rows; the contour runs across it
			var zu := maxi(z - 1, 0)
			var zd := mini(z + 1, nz - 1)
			var gy := (heights[zd * nx + x] - heights[zu * nx + x]) / maxf(float(zd - zu) * cell.y, 1e-3)
			var gx := (h1 - h0) / cell.x
			var ang := Vector2(gx, gy).orthogonal().angle()
			if ang > PI * 0.5:
				ang -= PI
			elif ang < -PI * 0.5:
				ang += PI
			var ok := true
			for f: Dictionary in out:
				if int(f["metres"]) == int(level) and (f["at"] as Vector2).distance_to(at) < spacing_px:
					ok = false
					break
			if ok:
				out.append({"at": at, "angle": ang, "metres": int(level)})
	return out
```

Note: `contour_figures` scans the row edges only (x direction); contours that run east–west cross row edges rarely but cross column edges often — if the visual review (Task 9) finds east–west contours unfigured, add the same scan over column edges. `test_figures_lie_on_their_contour` pins the row scan.

- [ ] **Step 4: Run the test file and the data test**

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/war_room/war_fine_print.gd data/balance.csv tests/war_room/test_war_fine_print.gd tests/engine/test_war_room_data.gd
git commit -m "feat(war room): the fine print's content — town notes, route names, minor heights, contour figures

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Painting the fine print and the near look

**Files:**
- Create: `scripts/war_room/war_near.gd`
- Modify: `scripts/war_room/war_ink_painter.gd` (a fine mode)
- Modify: `scripts/war_room/war_room_ink.gd` (`fine_for`, `fine` cache, `trim`)
- Modify: `scenes/war_room/war_table.gdshader` (`fine_tex`, `fine_alpha`)
- Modify: `scripts/war_room/war_room_view.gd` (`_paint_ink`, `_apply_camera`, `lay_sheet`)
- Modify: `data/balance.csv` (`war_contour_near_m`, `war_fine_far_m`, `war_fine_near_m`)
- Test: `tests/war_room/test_war_near.gd`, `tests/war_room/test_war_room_view.gd`, `tests/engine/test_war_room_data.gd`

**Interfaces:**
- Consumes: `WarFinePrint.strokes` (Task 5).
- Produces: `WarNear.contour_m(repo, distance_m: float) -> float`, `WarNear.fine_alpha(repo, distance_m: float) -> float`. `WarInkPainter.paint(p_ink, p_pal, p_px, p_font, as_intel := false, as_fine := false)`. `WarRoomInk.fine_for(repo, state, sheet, viewport, painter, font, still_wanted) -> Texture2D`. Shader uniforms `fine_tex`, `fine_alpha`.

- [ ] **Step 1: Write the failing tests**

Create `tests/war_room/test_war_near.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The near look by the camera's distance (spec 2026-10-07-war-room-scale-hover §3).

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


func test_the_contours_halve_as_the_camera_halves_its_distance_past_far() -> void:
	var far := repo.bal("war_fine_far_m")
	var full := repo.bal("war_contour_m")
	var near := repo.bal("war_contour_near_m")
	assert_eq(WarNear.contour_m(repo, far * 2.0), full)
	assert_eq(WarNear.contour_m(repo, far), full)
	assert_eq(WarNear.contour_m(repo, far * 0.99), full * 0.5)
	assert_eq(WarNear.contour_m(repo, far * 0.49), full * 0.25)
	assert_eq(WarNear.contour_m(repo, 0.01), near, "never finer than the near contours")


func test_a_figure_level_is_always_on_a_drawn_index_line_while_fine_print_shows() -> void:
	var level := repo.bal("war_fine_contour_level_m")
	var every := repo.bal("war_contour_index_every")
	var d := repo.bal("war_fine_far_m") * 0.99
	while d > repo.bal("war_cam_min_m"):
		if WarNear.fine_alpha(repo, d) > 0.0:
			assert_almost_eq(fmod(level, WarNear.contour_m(repo, d) * every), 0.0, 0.001, "at %.2f m" % d)
		d *= 0.8


func test_fine_print_fades_in_from_far_to_near() -> void:
	assert_eq(WarNear.fine_alpha(repo, repo.bal("war_fine_far_m")), 0.0)
	assert_eq(WarNear.fine_alpha(repo, repo.bal("war_fine_near_m")), 1.0)
	assert_eq(WarNear.fine_alpha(repo, repo.bal("war_cam_min_m")), 1.0)
	var mid := (repo.bal("war_fine_far_m") + repo.bal("war_fine_near_m")) * 0.5
	assert_between(WarNear.fine_alpha(repo, mid), 0.01, 0.99)
```

In `tests/war_room/test_war_room_view.gd` add:

```gdscript
func test_leaning_in_writes_the_near_look_into_the_table() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	var mat := (view.get_node("%Table") as MeshInstance3D).get_active_material(0) as ShaderMaterial
	view.lean_to(repo.bal("war_cam_max_m"))
	assert_eq(float(mat.get_shader_parameter("fine_alpha")), 0.0)
	assert_eq(float(mat.get_shader_parameter("contour_m")), repo.bal("war_contour_m"))
	view.lean_to(repo.bal("war_cam_min_m"))
	assert_eq(float(mat.get_shader_parameter("fine_alpha")), 1.0)
	assert_eq(float(mat.get_shader_parameter("contour_m")), WarNear.contour_m(repo, repo.bal("war_cam_min_m")))
```

Add to `test_war_room_data.gd`'s list: `"war_contour_near_m", "war_fine_far_m", "war_fine_near_m"`.

- [ ] **Step 2: Run to see them fail**

Run `tests/war_room/test_war_near.gd` and `tests/war_room/test_war_room_view.gd`. Expected: FAIL — `WarNear` not found.

- [ ] **Step 3: Implement**

`data/balance.csv`:

```csv
war_contour_near_m,50,"WAR ROOM near look (spec 2026-10-07-war-room-scale-hover §3): the finest contour interval, metres, at the closest lean; the interval halves from war_contour_m each time the camera halves its distance past war_fine_far_m"
war_fine_far_m,0.8,"WAR ROOM near look §3: the camera distance at which the fine print begins to show and the contours first step down; set at the visual review"
war_fine_near_m,0.35,"WAR ROOM near look §3: the camera distance at which the fine print is whole; set at the visual review"
```

Create `scripts/war_room/war_near.gd`:

```gdscript
class_name WarNear
extends RefCounted
## The near look by the camera's distance (spec 2026-10-07-war-room-scale-hover
## §3): the contour interval steps down a nice number at a time (200, 100,
## 50 m) and the fine print fades in. Pure.


## war_contour_m at war_fine_far_m and beyond; halved for each halving of the
## distance past it; never below war_contour_near_m.
static func contour_m(repo: DataRepository, distance_m: float) -> float:
	var far := repo.bal("war_fine_far_m")
	var full := repo.bal("war_contour_m")
	if distance_m >= far:
		return full
	var halvings := floori(log(far / maxf(distance_m, 1e-4)) / log(2.0)) + 1
	return maxf(full / pow(2.0, float(halvings)), repo.bal("war_contour_near_m"))


## 0 at war_fine_far_m and beyond, 1 at war_fine_near_m and nearer, smooth between.
static func fine_alpha(repo: DataRepository, distance_m: float) -> float:
	var far := repo.bal("war_fine_far_m")
	var near := repo.bal("war_fine_near_m")
	return smoothstep(far, near, distance_m) if far > near else (1.0 if distance_m <= near else 0.0)
```

Check: at `far * 0.99`, `log(1/0.99)/log2 ≈ 0.0145`, floor 0, +1 → one halving (100). At `far * 0.49`: `log2(2.04) ≈ 1.03`, floor 1, +1 → two halvings (50). Matches the tests.

`scripts/war_room/war_ink_painter.gd` — add `var fine := false`, take it in `paint`, branch in `_draw`:

```gdscript
var fine := false    # the fine print (WarFinePrint), not the sheet's ink


func paint(p_ink: Dictionary, p_pal: Dictionary, p_px: Dictionary, p_font: Font, as_intel := false, as_fine := false) -> void:
	intel = as_intel
	fine = as_fine
	ink = p_ink
	pal = p_pal
	px = p_px
	font = p_font
	queue_redraw()


func _draw() -> void:
	if ink.is_empty():
		return
	if intel:
		_draw_intel()
		return
	if fine:
		_draw_fine()
		return
	# … the existing ink drawing, unchanged …


## The fine print (WarFinePrint): notes and route names in faint ink, minor
## heights as small marks, contour figures in rubric, each turned to its angle.
func _draw_fine() -> void:
	var c_ink: Color = pal["ink"]
	var c_faint: Color = pal["ink_faint"]
	var c_fig: Color = pal["rubric"]
	for n: Dictionary in ink["notes"]:
		draw_string(font, n["at"], String(n["text"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(px["note"]), c_ink)
	for r: Dictionary in ink["routes"]:
		_turned_text(r["at"], float(r["angle"]), String(r["text"]), int(px["route"]), c_ink)
	for m: Dictionary in ink["marks"]:
		var at: Vector2 = m["at"]
		var s := float(px["mark"])
		var pts := PackedVector2Array([at + Vector2(0, -s), at + Vector2(s * 0.9, s * 0.6), at + Vector2(-s * 0.9, s * 0.6)])
		if String(m["kind"]) == "high":
			draw_colored_polygon(pts, c_faint)
		else:
			pts = PackedVector2Array([at + Vector2(-s * 0.9, -s * 0.6), at + Vector2(s * 0.9, -s * 0.6), at + Vector2(0, s), at + Vector2(-s * 0.9, -s * 0.6)])
			draw_polyline(pts, c_faint, maxf(s * 0.2, 1.0), true)
		draw_string(font, at + Vector2(s * 1.4, s * 0.5), "%d m" % int(m["metres"]), HORIZONTAL_ALIGNMENT_LEFT, -1, int(px["note"]), c_faint)
	for f: Dictionary in ink["figures"]:
		_turned_text(f["at"], float(f["angle"]), String(f["text"]), int(px["figure"]), c_fig)


## Text centred on `at`, turned by `angle`, on a parchment knock-out so the
## line under it does not run through the figure.
func _turned_text(at: Vector2, angle: float, text: String, size: int, color: Color) -> void:
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	draw_set_transform(at, angle, Vector2.ONE)
	var ground: Color = pal.get("parchment", pal.get("paper", Color.WHITE))
	ground.a = 0.6
	draw_rect(Rect2(Vector2(-w * 0.5 - 2.0, -float(size) * 0.8), Vector2(w + 4.0, float(size))), ground)
	draw_string(font, Vector2(-w * 0.5, float(size) * 0.1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
```

`scripts/war_room/war_room_ink.gd` — add a fine cache and `fine_for`, and trim it with the ink:

```gdscript
## The fine print's widths (war_fine_<k>_px), by short key.
const FINE_PX := ["note", "route", "mark", "figure"]

var fine: Dictionary = {}    # sheet index -> {key, tex}: the fine print (WarFinePrint)


## The sheet's fine print as a texture, the ink's size, drawn when the same
## key turns as the ink's; null headless or when a later draw took over.
func fine_for(repo: DataRepository, state: GameState, sheet: int, viewport: SubViewport,
		painter: WarInkPainter, font: Font, still_wanted: Callable) -> Texture2D:
	var key := WarSheetInk.cache_key(state, sheet)
	var held: Dictionary = fine.get(sheet, {})
	if held.get("key", -1) == key:
		return held.get("tex") as Texture2D
	var row: Dictionary = WarSheets.series(repo)[sheet]
	var size := tex_size(repo, row["rect"])
	_gen += 1
	var gen := _gen
	viewport.size = size
	var widths := {}
	for k: String in FINE_PX:
		widths[k] = repo.bal("war_fine_%s_px" % k)
	painter.paint(WarFinePrint.strokes(repo, state, row, size.x, WarBake.of(repo)), repo.war_palette, widths, font, false, true)
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
	fine[sheet] = {"key": key, "tex": ImageTexture.create_from_image(img)}
	return fine[sheet]["tex"]
```

and in `trim(count)`, after the loop, drop fine entries whose sheet is no longer cached:

```gdscript
	for s: int in fine.keys():
		if not cache.has(s):
			fine.erase(s)
```

`scenes/war_room/war_table.gdshader` — after the `intel_tex` uniform add:

```glsl
// the fine print (spec 2026-10-07-war-room-scale-hover §3): premultiplied sRGB
// bytes as ink_tex, faded in by the camera's distance (WarNear.fine_alpha)
uniform sampler2D fine_tex : filter_linear_mipmap_anisotropic, hint_default_transparent;
uniform float fine_alpha = 0.0;
```

and right after the `ink_tex` compositing line `col = col * (1.0 - ink_a) + straight * ink_a;` add:

```glsl
	vec4 fined = texture(fine_tex, vec2(UV.x, UV.y * tex_aspect));
	vec3 fine_straight = srgb_to_linear(fined.rgb / max(fined.a, 1e-4));
	float fine_a = fined.a * collar_k * fine_alpha;
	col = col * (1.0 - fine_a) + fine_straight * fine_a;
```

`scripts/war_room/war_room_view.gd`:
- in `lay_sheet`, next to `mat.set_shader_parameter("intel_tex", null)`, add `mat.set_shader_parameter("fine_tex", null)`;
- in `_paint_ink`, after `mat.set_shader_parameter("ink_tex", tex)` (still inside the `_ink_busy` window — move the decrement below):

```gdscript
func _paint_ink(mat: ShaderMaterial) -> void:
	var sheet := _sheet
	_ink_busy += 1
	var tex := await _inks.texture_for(_repo, state(), sheet, _ink_viewport, _ink, lettering(),
		func() -> bool: return is_inside_tree() and sheet == _sheet)
	if tex != null:
		mat.set_shader_parameter("ink_tex", tex)
	var fine := await _inks.fine_for(_repo, state(), sheet, _ink_viewport, _ink, lettering(),
		func() -> bool: return is_inside_tree() and sheet == _sheet)
	_ink_busy -= 1
	if fine != null and sheet == _sheet:
		mat.set_shader_parameter("fine_tex", fine)
	if _intel_again and _ink_busy == 0:
		_intel_again = false
		_paint_intel(_table.get_active_material(0) as ShaderMaterial)
```

- in `_apply_camera`, inside `if _repo != null:`, write the near look:

```gdscript
		var mat := _table.get_active_material(0) as ShaderMaterial
		if mat != null:
			mat.set_shader_parameter("contour_m", WarNear.contour_m(_repo, _rig.distance))
			mat.set_shader_parameter("fine_alpha", WarNear.fine_alpha(_repo, _rig.distance))
```

`WarRoomMaterial.bind` sets `contour_m` from `war_contour_m` at lay; `lay_sheet` calls `_apply_camera()` after `bind`, so the camera's value wins.

- [ ] **Step 4: Run the tests**

Run `tests/war_room/test_war_near.gd`, `tests/war_room/test_war_room_view.gd`, `tests/war_room/test_war_sheet_ink.gd`, `tests/engine/test_war_room_data.gd`. Expected: PASS.

- [ ] **Step 5: Shoot the near look**

Real-window shots at `--war-zoom 1.6`, `0.5`, `0.25`, `0.12` (Task 2 Step 5's command). Read them: at 1.6 no fine print; at 0.25 and 0.12 town notes, route names and figures readable, contours finer. Breakage fails the task; looks are tuned in Task 9.

- [ ] **Step 6: Commit**

```bash
git add scripts/war_room/war_near.gd scripts/war_room/war_ink_painter.gd scripts/war_room/war_room_ink.gd scenes/war_room/war_table.gdshader scripts/war_room/war_room_view.gd data/balance.csv tests/war_room/test_war_near.gd tests/war_room/test_war_room_view.gd tests/engine/test_war_room_data.gd
git commit -m "feat(war room): fine print fades in and the contours step down as the officer leans in

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: The pointer's dwell and the rake's aim, as signals

**Files:**
- Create: `scripts/war_room/war_hover_dwell.gd`
- Modify: `scripts/war_room/war_room_view.gd` (signals, `_gui_input`, `_process`, `hover_allowed`)
- Modify: `data/balance.csv` (`war_hover_delay_s`, `war_hover_still_px`)
- Test: `tests/war_room/test_war_hover_dwell.gd`, `tests/war_room/test_war_room_view.gd`, `tests/engine/test_war_room_data.gd`

**Interfaces:**
- Produces: `WarHoverDwell` with `at: Vector2`, `moved(p: Vector2, still_px: float) -> bool` (true when a shown dwell was cleared), `step(delta: float, delay_s: float) -> bool` (true the frame the dwell completes), `clear() -> bool`. On `WarRoomView`: `signal ground_hovered(pack_px: Vector2, screen_px: Vector2)`, `signal rake_aimed(code: String, pack_px: Vector2, screen_px: Vector2)`, `signal hover_cleared`, `func hover_allowed() -> bool`.

- [ ] **Step 1: Write the failing tests**

Create `tests/war_room/test_war_hover_dwell.gd`:

```gdscript
extends GutTest
## The pointer's dwell (spec 2026-10-07-war-room-scale-hover §4.2): still for
## the delay within the still radius shows; any move beyond it clears.


func test_a_still_pointer_dwells_once_after_the_delay() -> void:
	var d := WarHoverDwell.new()
	assert_false(d.moved(Vector2(100, 100), 4.0))
	assert_false(d.step(0.2, 0.35))
	assert_true(d.step(0.2, 0.35), "the delay is over")
	assert_false(d.step(0.2, 0.35), "only once")


func test_a_small_jitter_does_not_restart_the_dwell() -> void:
	var d := WarHoverDwell.new()
	d.moved(Vector2(100, 100), 4.0)
	d.step(0.3, 0.35)
	assert_false(d.moved(Vector2(102, 101), 4.0))
	assert_true(d.step(0.1, 0.35))


func test_a_move_beyond_the_radius_clears_a_shown_dwell() -> void:
	var d := WarHoverDwell.new()
	d.moved(Vector2(100, 100), 4.0)
	d.step(1.0, 0.35)
	assert_true(d.moved(Vector2(140, 100), 4.0), "it was showing: cleared")
	assert_false(d.moved(Vector2(180, 100), 4.0), "nothing showing to clear")
	assert_false(d.step(0.1, 0.35))
	assert_true(d.step(0.3, 0.35))
```

In `tests/war_room/test_war_room_view.gd` add:

```gdscript
func _hover(at: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = at
	view._gui_input(e)


func test_resting_on_open_table_reads_the_ground_once() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	watch_signals(view)
	var r: Rect2 = WarSheets.series(repo)[0]["cell"]
	var at: Vector2 = view.screen_pos_of_px(r.get_center())
	if view.piece_under(at) != "":
		at += Vector2(40, 40)
	_hover(at)
	view._process(repo.bal("war_hover_delay_s") + 0.01)
	assert_signal_emit_count(view, "ground_hovered", 1)
	view._process(1.0)
	assert_signal_emit_count(view, "ground_hovered", 1, "once per rest")
	_hover(at + Vector2(repo.bal("war_hover_still_px") * 4.0, 0))
	assert_signal_emitted(view, "hover_cleared")


func test_no_reading_off_the_table() -> void:
	view.lay_sheet(0)
	await wait_process_frames(2)
	watch_signals(view)
	_hover(Vector2(2, 2))   # the room's corner, past the table at the opening view
	view._process(repo.bal("war_hover_delay_s") + 0.01)
	if view.pack_at(Vector2(2, 2)).x < 0.0:
		assert_signal_not_emitted(view, "ground_hovered")
```

Add `"war_hover_delay_s", "war_hover_still_px"` to `test_war_room_data.gd`'s list.

- [ ] **Step 2: Run to see them fail**

Expected: FAIL — `WarHoverDwell` not found; no signal `ground_hovered`.

- [ ] **Step 3: Implement**

`data/balance.csv`:

```csv
war_hover_delay_s,0.35,"WAR ROOM slip (spec 2026-10-07-war-room-scale-hover §4.2): seconds the pointer rests on open table before the ground is read"
war_hover_still_px,4,"WAR ROOM slip §4.2: a pointer moving less than this many design px is still resting"
```

Create `scripts/war_room/war_hover_dwell.gd`:

```gdscript
class_name WarHoverDwell
extends RefCounted
## The pointer's dwell on the WAR ROOM's table (spec
## 2026-10-07-war-room-scale-hover §4.2): resting `delay_s` within `still_px`
## completes once; a move past the radius clears what was showing. Pure.

var at := Vector2(-1, -1)
var _still_s := 0.0
var _shown := false


## The pointer is at `p`; true when this clears a completed dwell.
func moved(p: Vector2, still_px: float) -> bool:
	if at.x >= 0.0 and p.distance_to(at) <= still_px:
		return false
	at = p
	_still_s = 0.0
	var was := _shown
	_shown = false
	return was


## Time passes; true on the frame the dwell completes.
func step(delta: float, delay_s: float) -> bool:
	if at.x < 0.0 or _shown:
		return false
	_still_s += delta
	if _still_s >= delay_s:
		_shown = true
		return true
	return false


## Forget the pointer (it left, or the room is busy); true when this clears a
## completed dwell.
func clear() -> bool:
	at = Vector2(-1, -1)
	_still_s = 0.0
	var was := _shown
	_shown = false
	return was
```

`scripts/war_room/war_room_view.gd`:

Signals, beside the others:

```gdscript
## The pointer has rested on open table (spec 2026-10-07-war-room-scale-hover
## §4.2): the screen reads the ground there.
signal ground_hovered(pack_px: Vector2, screen_px: Vector2)
## A rake is aimed at `pack_px`: the screen reads the destination for `code`.
signal rake_aimed(code: String, pack_px: Vector2, screen_px: Vector2)
## The slip goes: the pointer moved, the rake ended, the room got busy.
signal hover_cleared
```

A member and a guard:

```gdscript
var _dwell := WarHoverDwell.new()


## No slip while the camera or the sheet moves, in board mode, or while a
## popup or a text box has the input (spec §4.2).
func hover_allowed() -> bool:
	if _sheet < 0 or _board_mode != "table" or rolling() or tossing():
		return false
	var owner := get_viewport().gui_get_focus_owner()
	return not (owner is LineEdit or owner is TextEdit)
```

In `_gui_input`, inside the `if event is InputEventMouseMotion:` branch (where the board tooltip is set), add after it:

```gdscript
		var hm := event as InputEventMouseMotion
		if hm.button_mask != 0:
			if _dwell.clear():
				hover_cleared.emit()
		elif _dwell.moved(hm.position, _repo.bal("war_hover_still_px")):
			hover_cleared.emit()
```

After `_rake.on_motion(mm)` in `_gui_input`:

```gdscript
		if _rake.code != "" and aiming and aim_dest.x < 0.0:
			var pk := pack_at(mm.position)
			if pk.x >= 0.0:
				rake_aimed.emit(_rake.code, pk, mm.position)
```

In `_process`, at its top (after `_step_toss(delta)`):

```gdscript
	if not hover_allowed():
		if _dwell.clear():
			hover_cleared.emit()
	elif _rake.code == "" and _dwell.step(delta, _repo.bal("war_hover_delay_s")):
		var at := _dwell.at
		var pk := pack_at(at)
		var on_mark := piece_under(at) != "" or WarRoomPicks.nearest(_pennants.screen_hits(_camera, window_scale()), at, _repo.bal("war_pick_px")) != ""
		if pk.x >= 0.0 and not on_mark:
			ground_hovered.emit(pk, at)
```

Also emit `hover_cleared` where the view emits `rake_dropped` and in `set_active(false)`: add `hover_cleared.emit()` next to each `rake_dropped.emit()` in `war_room_view.gd` / `war_room_rake.gd` (rake calls `_view.rake_dropped.emit()`; add `_view.hover_cleared.emit()` beside it), and in `set_active` when `on` is false add `_dwell.clear()` and `hover_cleared.emit()`.

Note: when the camera turns or pans, the drag's motion carries a button mask, which already clears the dwell above.

- [ ] **Step 4: Run the tests**

Run `tests/war_room/test_war_hover_dwell.gd`, `tests/war_room/test_war_room_view.gd`, `tests/war_room/test_war_room_isolation.gd`, `tests/engine/test_war_room_data.gd`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/war_room/war_hover_dwell.gd scripts/war_room/war_room_view.gd scripts/war_room/war_room_rake.gd data/balance.csv tests/war_room/test_war_hover_dwell.gd tests/war_room/test_war_room_view.gd tests/engine/test_war_room_data.gd
git commit -m "feat(war room): the pointer's dwell and the rake's aim as signals

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The slip

**Files:**
- Create (editor): `scenes/war_room/war_hover_slip.tscn`; theme kinds `WarHoverTitle`, `WarHoverSub`, `WarHoverLine`, `WarHoverRubric`, `WarHoverRule` in `assets/2D/ui/theme/paper_theme.tres`
- Create: `scripts/ui/war_hover_slip.gd`
- Modify (editor): `scenes/screens/war_room_screen.tscn` (instance the slip as `%HoverSlip`, above `%Folio` in draw order so the folio covers it)
- Modify: `scripts/ui/war_room_screen.gd` (wiring)
- Modify: `data/balance.csv` (`war_hover_width_px`, `war_hover_gap_px`)
- Modify: `tests/ui/test_editor_owned_look.gd` (add the slip's script to `SCRIPTS`)
- Test: `tests/ui/test_war_hover_slip.gd`, `tests/ui/test_war_room_screen.gd`, `tests/engine/test_war_room_data.gd`

**Interfaces:**
- Consumes: `WarGround.reading/lines` (Task 4), the view's `ground_hovered`, `rake_aimed`, `hover_cleared`, `rake_dropped` (Task 7), `WarRoomView.selected_army()`.
- Produces: `WarHoverSlip.show_lines(lines: Array, pointer: Vector2, bounds: Rect2) -> void`, `WarHoverSlip.hide_slip() -> void`, static `WarHoverSlip.place(pointer: Vector2, size: Vector2, bounds: Rect2, gap: float) -> Vector2`.

- [ ] **Step 1: Make the scene and the theme kinds in the editor**

With the editor running (gdai MCP), check `get_open_scripts` against disk first, then:
1. In `paper_theme.tres` add label kinds (base type `Label`): `WarHoverTitle` (the folio header's small caps font role, rubric-free ink, size 18), `WarHoverSub` (italic, faint ink, 14), `WarHoverLine` (body, ink, 16), `WarHoverRubric` (small caps, rubric colour, 15); and `WarHoverRule` (base `HSeparator`, a thin rubric line at 0.6 alpha). Take the colours from `war_palette` values (`ink` #2B2118, `ink_faint`, `rubric` #9B2C1F).
2. Create `scenes/war_room/war_hover_slip.tscn`: root `PanelContainer` named `WarHoverSlip`, `mouse_filter` Ignore, `theme` = `paper_theme.tres`, panel style `assets/2D/ui/war_table/styles/war_slip.tres` (the key slip's), `visible` false, `top_level` false; child `MarginContainer` (`Margin`, 14/10 px), child `VBoxContainer` `%Lines` (separation 2), `mouse_filter` Ignore on every node. Attach `scripts/ui/war_hover_slip.gd` (Step 3).
3. In `scenes/screens/war_room_screen.tscn` instance it as `HoverSlip` (`unique_name_in_owner`), ordered just before `Folio` so the folio and the prompts draw over it.

Save, then `git status` and `git diff --stat` to confirm only these files changed.

- [ ] **Step 2: Write the failing tests**

Create `tests/ui/test_war_hover_slip.gd`:

```gdscript
extends GutTest
## The WAR ROOM's hover slip (spec 2026-10-07-war-room-scale-hover §4.2).


func test_the_slip_sits_below_right_and_flips_at_the_edges() -> void:
	var bounds := Rect2(0, 0, 1000, 600)
	var size := Vector2(300, 200)
	assert_eq(WarHoverSlip.place(Vector2(100, 100), size, bounds, 20.0), Vector2(120, 120))
	assert_eq(WarHoverSlip.place(Vector2(900, 100), size, bounds, 20.0), Vector2(580, 120), "flipped left")
	assert_eq(WarHoverSlip.place(Vector2(100, 550), size, bounds, 20.0), Vector2(120, 330), "flipped up")


func test_the_lines_become_labels_of_their_kinds() -> void:
	var slip: WarHoverSlip = load("res://scenes/war_room/war_hover_slip.tscn").instantiate()
	add_child_autofree(slip)
	slip.show_lines([{"text": "Knutham (Axbrigh)", "kind": "title"}, {"text": "", "kind": "rule"},
		{"text": "Hills · 780 m", "kind": "line"}], Vector2(10, 10), Rect2(0, 0, 800, 600))
	await wait_process_frames(1)
	assert_true(slip.visible)
	var kids := slip.get_node("%Lines").get_children()
	assert_eq(kids.size(), 3)
	assert_eq((kids[0] as Label).theme_type_variation, &"WarHoverTitle")
	assert_true(kids[1] is HSeparator)
	assert_eq((kids[2] as Label).text, "Hills · 780 m")
	slip.hide_slip()
	assert_false(slip.visible)
```

In `tests/ui/test_war_room_screen.gd` add (follow that file's existing setup for an opened screen; `screen` and `view` below are the names that file already uses — rename to match):

```gdscript
func test_a_rest_on_the_table_shows_the_slip_and_a_move_hides_it() -> void:
	var slip := screen.get_node("%HoverSlip") as WarHoverSlip
	var at := Vector2(view.size) * 0.5
	var pk: Vector2 = view.pack_at(at)
	view.ground_hovered.emit(pk, at)
	await wait_process_frames(1)
	assert_true(slip.visible)
	var first := ((slip.get_node("%Lines") as Node).get_child(0) as Label).text
	assert_eq(first, Intel.place_label(Game.data, Game.state, pk))
	view.hover_cleared.emit()
	assert_false(slip.visible)


func test_a_dropped_rake_hides_the_slip() -> void:
	var slip := screen.get_node("%HoverSlip") as WarHoverSlip
	var at := Vector2(view.size) * 0.5
	view.ground_hovered.emit(view.pack_at(at), at)
	await wait_process_frames(1)
	view.rake_dropped.emit()
	assert_false(slip.visible)
```

Add `"res://scripts/ui/war_hover_slip.gd"` to `SCRIPTS` in `tests/ui/test_editor_owned_look.gd`. Add `"war_hover_width_px", "war_hover_gap_px"` to `test_war_room_data.gd`'s list.

- [ ] **Step 3: Implement**

`data/balance.csv`:

```csv
war_hover_width_px,340,"WAR ROOM slip (spec 2026-10-07-war-room-scale-hover §4.2): the slip's width, design px; its lines wrap"
war_hover_gap_px,18,"WAR ROOM slip §4.2: the slip stands this far right of and below the pointer (or flipped to its other side at an edge)"
```

Create `scripts/ui/war_hover_slip.gd`:

```gdscript
class_name WarHoverSlip
extends PanelContainer
## The WAR ROOM's hover slip (spec 2026-10-07-war-room-scale-hover §4.2): the
## ground under the pointer as WarGround.lines sets it, beside the pointer and
## flipped to stay in the view. Its look is the scene's; it only fills lines
## and places itself. Never takes the mouse.

const KINDS := {"title": &"WarHoverTitle", "sub": &"WarHoverSub", "line": &"WarHoverLine", "rubric": &"WarHoverRubric"}

@onready var _lines: VBoxContainer = %Lines
var _width := 340.0
var _gap := 18.0


func setup(repo: DataRepository) -> void:
	_width = repo.bal("war_hover_width_px")
	_gap = repo.bal("war_hover_gap_px")


## Below and right of the pointer by `gap`; flipped left or up where it would
## leave `bounds`.
static func place(pointer: Vector2, size: Vector2, bounds: Rect2, gap: float) -> Vector2:
	var at := pointer + Vector2(gap, gap)
	if at.x + size.x > bounds.end.x:
		at.x = pointer.x - gap - size.x
	if at.y + size.y > bounds.end.y:
		at.y = pointer.y - gap - size.y
	return Vector2(maxf(at.x, bounds.position.x), maxf(at.y, bounds.position.y))


func show_lines(lines: Array, pointer: Vector2, bounds: Rect2) -> void:
	for c in _lines.get_children():
		_lines.remove_child(c)
		c.queue_free()
	for l: Dictionary in lines:
		if String(l["kind"]) == "rule":
			var sep := HSeparator.new()
			sep.theme_type_variation = &"WarHoverRule"
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_lines.add_child(sep)
			continue
		var label := Label.new()
		label.text = String(l["text"])
		label.theme_type_variation = KINDS.get(String(l["kind"]), &"WarHoverLine")
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.custom_minimum_size.x = _width
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_lines.add_child(label)
	reset_size()
	visible = true
	position = place(pointer, get_combined_minimum_size(), bounds, _gap)


func hide_slip() -> void:
	visible = false
```

(The labels' width is content layout set per row, the same as `_fill_margin`'s rows — not the static look; `_ready` is not defined, so the look guard has nothing to flag.)

`scripts/ui/war_room_screen.gd` — in `open()` inside `if not _bound:` after the key's wiring:

```gdscript
		var slip := %HoverSlip as WarHoverSlip
		slip.setup(Game.data)
		_view.ground_hovered.connect(_on_ground_hovered)
		_view.rake_aimed.connect(_on_rake_aimed)
		_view.hover_cleared.connect(slip.hide_slip)
		_view.rake_dropped.connect(slip.hide_slip)
```

and add:

```gdscript
## The pointer rested on the table: read the ground for the chosen regiment
## (spec 2026-10-07-war-room-scale-hover §4).
func _on_ground_hovered(pack_px: Vector2, screen_px: Vector2) -> void:
	var r := WarGround.reading(Game.data, Game.state, pack_px, _view.selected_army())
	_show_slip(WarGround.lines(Game.data, r), screen_px)


## A rake aimed: read its destination for the raked regiment, the days left to
## the arrow's own reading.
func _on_rake_aimed(code: String, pack_px: Vector2, screen_px: Vector2) -> void:
	var r := WarGround.reading(Game.data, Game.state, pack_px, code)
	_show_slip(WarGround.lines(Game.data, r, true), screen_px)


func _show_slip(lines: Array, view_px: Vector2) -> void:
	var slip := %HoverSlip as WarHoverSlip
	var origin := _view.get_global_rect().position - get_global_rect().position
	slip.show_lines(lines, origin + view_px, Rect2(origin, _view.size))
```

Also hide the slip in `close()` / wherever the folio opens: in `_on_piece` add `(%HoverSlip as WarHoverSlip).hide_slip()` at its top, and in the screen's close path add the same.

- [ ] **Step 4: Run the tests**

Run `tests/ui/test_war_hover_slip.gd`, `tests/ui/test_war_room_screen.gd`, `tests/ui/test_editor_owned_look.gd`, `tests/engine/test_war_room_data.gd`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scenes/war_room/war_hover_slip.tscn scripts/ui/war_hover_slip.gd scenes/screens/war_room_screen.tscn scripts/ui/war_room_screen.gd assets/2D/ui/theme/paper_theme.tres data/balance.csv tests/ui/test_war_hover_slip.gd tests/ui/test_war_room_screen.gd tests/ui/test_editor_owned_look.gd tests/engine/test_war_room_data.gd
git commit -m "feat(war room): the hover slip — the ground under the pointer, for the chosen regiment

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Real-input shots, visual review, bench, documents

**Files:**
- Modify: `tools/snapshot_screen.gd` (`--war-hover fx,fy`)
- Modify: `data/balance.csv` (tuned values only, each with its reason)
- Modify: `scripts/war_room/CLAUDE.md`
- Modify: `data/balance.csv` (`war_hover_budget_ms`)
- Test: `tests/engine/test_war_ground.gd` (budget), `tests/engine/test_war_room_data.gd`

**Interfaces:**
- Consumes: everything above.

- [ ] **Step 1: The hover flag**

In `tools/snapshot_screen.gd`: add `var _war_hover := Vector2(-1, -1)` beside `_war_drag`; parse it beside `--war-drag`:

```gdscript
		elif args[i] == "--war-hover":
			var hparts := args[i + 1].split(",")
			_war_hover = Vector2(float(hparts[0]), float(hparts[1]))
```

In the war phase 3 block, after the `_war_piece` handling and before `_war_to(4)`:

```gdscript
		if _war_hover.x >= 0.0:
			_real_move(view, Vector2(view.size) * _war_hover)
			print("war: hover at %s" % (Vector2(view.size) * _war_hover))
```

In phase 4, before its other steps, wait out the dwell:

```gdscript
		if _war_hover.x >= 0.0 and _frames - _war_at < ceili(Game.data.bal("war_hover_delay_s") * 120.0) + 10:
			return   # a 120 Hz display's frames: the slip has come up
```

and add `--war-hover fx,fy` to the doc comment above `_war_room` options (line ~197) and to `scripts/war_room/CLAUDE.md`'s "Shots and bench" list.

- [ ] **Step 2: The reading's budget**

Add `war_hover_budget_ms,4,"WAR ROOM slip (spec 2026-10-07-war-room-scale-hover §5): the most one WarGround.reading may take, its worst case a march walked to army_march_days_cap"` to `balance.csv` and the key to the data test, and in `tests/engine/test_war_ground.gd`:

```gdscript
func test_a_reading_stays_inside_its_budget() -> void:
	var code := _land_code()
	var far := _land_point() + Vector2(60, 40)   # a long march
	WarGround.reading(repo, state, far, code)   # warm the grids
	var t0 := Time.get_ticks_usec()
	WarGround.reading(repo, state, far, code)
	var ms := float(Time.get_ticks_usec() - t0) / 1000.0
	assert_lt(ms, repo.bal("war_hover_budget_ms"), "%.2f ms" % ms)
```

(`Time` is allowed in a test; it never enters engine code.) Run it. If it fails, profile `march_days_between` first; do not raise the budget without saying why in the key's note.

- [ ] **Step 3: Visual review**

Invoke the `visual-review` skill. Shots (real window, `--resolution 1920x1200` and `2560x1600`), each before (main) and after (this branch):
- `--war-room --war-zoom 1.6`, `0.5`, `0.25`, `0.12` with `--war-focus <a player land regiment>`
- `--war-room --war-zoom 0.35 --war-piece <code> --war-hover 0.62,0.58` (a chosen regiment, the slip up)
- `--war-room --war-zoom 0.35 --war-piece <code> --war-drag 0.62,0.58` (the rake's slip)
Judge and tune, each change a `balance.csv` value with its reason in the note: `war_ink_wood_step_km`, `war_sea_hatch_reach_m`, `war_sheet_collar_km`, `war_grid_deg` (1 or 2), `war_chart_label_every`, `war_fine_far_m` / `war_fine_near_m`, `war_fine_*_px`, `war_hover_width_px`. The slip's colours and fonts are tuned in the editor (theme kinds), not in code. Get the independent critic's verdict before moving on.

- [ ] **Step 4: The bench**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/tools/war_room/bench.tscn -- --size 1920x1200 --quality high
```

Run on main and on this branch, each tier (`low`, `medium`, `high` — as `graphics_quality.csv` names them). Record the opening frame time and the sheet-lay spike in the commit message; a frame-time regression over 1 ms at any tier is a failure to report, not to ship.

- [ ] **Step 5: Documents**

In `scripts/war_room/CLAUDE.md`:
- "The sheets": `war_sheet_deg` 10° (~71 × 52 km), ids past Z (`AA3`), the chart's axis every `war_chart_label_every`.
- "Ink": add a bullet — **Fine print** (`WarFinePrint`, a second texture `fine_tex` cached with the ink): town notes, route names, minor heights, contour figures; faded in by `WarNear.fine_alpha`; the contour interval steps down by `WarNear.contour_m`.
- New section "## The hover slip": the dwell (`WarHoverDwell`, `war_hover_*`), the signals, `WarGround` in the engine (read-only, no foreign force), the slip scene, the rake's slip, where it does not show.
- "Shots and bench": `--war-hover fx,fy`.
Keep the file under its size cap (`tests/engine/test_claude_md_size.gd`).

- [ ] **Step 6: Whole suite and commit**

Run `./run_tests.sh`. Expected: green with the expected error count.

```bash
git add tools/snapshot_screen.gd data/balance.csv scripts/war_room/CLAUDE.md tests/engine/test_war_ground.gd tests/engine/test_war_room_data.gd
git commit -m "tool(snapshot): --war-hover; war room scale and hover tuned at review; docs

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: The gate — does the near view still need the patch?

**Files:**
- Modify: `docs/superpowers/specs/2026-10-07-war-room-scale-hover-design.md` (record the ruling under §2)

- [ ] **Step 1: Shoot the closest lean**

`--war-room --war-zoom 0.12 --war-focus <a player land regiment>` at `--resolution 1920x1200` and `2560x1600`. Crop 400 × 300 px around a town name and a road in each (`visual-review`'s crop step).

- [ ] **Step 2: Measure**

Compute the texels per screen px at 0.12 m with `WarRoomView.units_per_px_at(0.12, 40.0, H, sheet_w_px, war_table_w_m, 1.0)` against the ink's `war_sheet_texture_px / sheet_w_px` (a GDScript one-liner via the gdai MCP `execute_editor_script`, or by hand: texels per screen px = `war_sheet_texture_px / sheet_w_px × units_per_px`). If it is ≥ 1 at both resolutions and the crops read crisp to the critic, the patch is not built.

- [ ] **Step 3: Record and stop or go on**

Write the result under the spec's §2 as "Gate result (date): texels per px at 0.12 m = X (1920×1200), Y (2560×1600); patch built / not built". Commit:

```bash
git add docs/superpowers/specs/2026-10-07-war-room-scale-hover-design.md
git commit -m "spec(war room): the near-view gate's result

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

If the patch is not built, the plan ends here. Otherwise go on to Task 11.

---

### Task 11 (only if Task 10 calls for it): The near-zoom detail patch

**Files:**
- Create: `scripts/war_room/war_detail_ink.gd`
- Modify: `scripts/war_room/war_room_view.gd`, `scenes/war_room/war_room.tscn` (editor: add `%DetailViewport` SubViewport with a `WarInkPainter` child `%DetailInk`, `render_target_update_mode` Disabled, size 2 × 2), `scenes/war_room/war_table.gdshader`, `scripts/war_room/war_sheet_ink.gd` (`strokes` window), `scripts/war_room/war_fine_print.gd` (window)
- Modify: `data/balance.csv` (`war_detail_level_m`, `war_detail_cover`, `war_detail_inner`, `war_detail_texture_px`, `war_detail_feather`)
- Test: `tests/war_room/test_war_detail_ink.gd`, `tests/war_room/test_war_sheet_ink.gd`

**Interfaces:**
- Produces: `WarDetailInk.level(repo, distance_m: float) -> int` (0..3); `WarDetailInk.patch_rect(repo, sheet_rect: Rect2, centre_px: Vector2, view_px: Vector2) -> Rect2` (pack px, snapped to a grid of `view_px * war_detail_inner`); `WarDetailInk.needs_redraw(old: Dictionary, now: Dictionary) -> bool` over `{level, rect, key, centre}`. `WarSheetInk.strokes(repo, state, sheet, tex_px, bake, window := Rect2())` — a non-empty `window` (pack px) keeps only strokes touching it, in the window's texture px (`k = tex_px / window.size.x`), widths scaled by `window.size.x / sheet rect width`'s inverse (the painter's `px` dict multiplied by `rect.size.x / window.size.x`).

- [ ] **Step 1: Write the failing tests**

Create `tests/war_room/test_war_detail_ink.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The near-zoom detail patch (spec 2026-10-07-war-room-scale-hover §2).

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


func test_levels_by_distance() -> void:
	var t := repo.bal("war_detail_level_m")
	assert_eq(WarDetailInk.level(repo, t * 1.01), 0)
	assert_eq(WarDetailInk.level(repo, t * 0.99), 1)
	assert_eq(WarDetailInk.level(repo, t * 0.49), 2)
	assert_eq(WarDetailInk.level(repo, t * 0.24), 3)
	assert_eq(WarDetailInk.level(repo, 0.001), 3)


func test_the_patch_covers_the_view_and_snaps() -> void:
	var sheet := Rect2(0, 0, 71, 52)
	var view := Vector2(10, 6)
	var a := WarDetailInk.patch_rect(repo, sheet, Vector2(30, 20), view)
	assert_true(a.has_point(Vector2(30, 20)))
	assert_gte(a.size.x, view.x * repo.bal("war_detail_cover") - 0.001)
	var b := WarDetailInk.patch_rect(repo, sheet, Vector2(30.2, 20.1), view)
	assert_eq(a, b, "a small pan keeps the same patch")


func test_a_redraw_only_when_level_rect_or_key_changes() -> void:
	var s := {"level": 1, "rect": Rect2(0, 0, 10, 10), "key": 5}
	assert_false(WarDetailInk.needs_redraw(s, s.duplicate()))
	var t := s.duplicate()
	t["level"] = 2
	assert_true(WarDetailInk.needs_redraw(s, t))
	t = s.duplicate()
	t["key"] = 6
	assert_true(WarDetailInk.needs_redraw(s, t))
```

In `tests/war_room/test_war_sheet_ink.gd` add:

```gdscript
func test_a_window_keeps_only_its_strokes_in_its_own_px() -> void:
	var s: Dictionary = WarSheets.series(repo)[0]
	var r: Rect2 = s["rect"]
	var win := Rect2(r.position + r.size * 0.25, r.size * 0.5)
	var whole := WarSheetInk.strokes(repo, state, s, 4096)
	var part := WarSheetInk.strokes(repo, state, s, 2048, null, win)
	assert_lte((part["towns"] as Array).size(), (whole["towns"] as Array).size())
	for t: Dictionary in part["towns"]:
		assert_true(Rect2(Vector2.ZERO, win.size * (2048.0 / win.size.x)).has_point(t["at"]))
```

(`state` — add `var state: GameState` and `state = SuiteData.campaign(repo, 42)` to that file's `before_each` if it has none.)

- [ ] **Step 2: Run to see them fail**

Expected: FAIL — `WarDetailInk` not found; `strokes` has no window parameter.

- [ ] **Step 3: Implement**

`data/balance.csv`:

```csv
war_detail_level_m,0.3,"WAR ROOM detail patch (spec 2026-10-07-war-room-scale-hover §2): nearer than this the patch draws at x2, at half of it x4, at a quarter x8; set from the gate's measure"
war_detail_cover,1.8,"WAR ROOM detail patch §2: the patch spans the view times this"
war_detail_inner,0.25,"WAR ROOM detail patch §2: the patch's grid, as a share of the view: a pan smaller than this keeps the patch"
war_detail_texture_px,2048,"WAR ROOM detail patch §2: the patch viewport's width, px (~16 MB, resident while the room is open)"
war_detail_feather,0.04,"WAR ROOM detail patch §2: the patch's edge cross-fade, as a share of its width"
```

Create `scripts/war_room/war_detail_ink.gd`:

```gdscript
class_name WarDetailInk
extends RefCounted
## The near-zoom detail patch's rules (spec 2026-10-07-war-room-scale-hover §2):
## its level by the camera's distance, the rect it covers, when it is redrawn.
## Pure; the view owns the viewport.


static func level(repo: DataRepository, distance_m: float) -> int:
	var t := repo.bal("war_detail_level_m")
	if distance_m >= t:
		return 0
	if distance_m >= t * 0.5:
		return 1
	if distance_m >= t * 0.25:
		return 2
	return 3


## The patch round `centre_px` over a view `view_px` wide (pack px), the view
## times war_detail_cover, its corner snapped to a grid of view x
## war_detail_inner so a small pan keeps it; held inside the sheet's rect.
static func patch_rect(repo: DataRepository, sheet_rect: Rect2, centre_px: Vector2, view_px: Vector2) -> Rect2:
	var size := view_px * repo.bal("war_detail_cover")
	var grid := view_px * repo.bal("war_detail_inner")
	var corner := centre_px - size * 0.5
	corner = Vector2(floorf(corner.x / grid.x) * grid.x, floorf(corner.y / grid.y) * grid.y)
	var r := Rect2(corner, size + grid)   # one grid step of slack so the centre stays inside after the snap
	r.position = r.position.clamp(sheet_rect.position, sheet_rect.end - r.size)
	return r


static func needs_redraw(old: Dictionary, now: Dictionary) -> bool:
	return int(old.get("level", -1)) != int(now.get("level", -1)) or old.get("rect") != now.get("rect") \
		or int(old.get("key", -1)) != int(now.get("key", -1))
```

`scripts/war_room/war_sheet_ink.gd` — give `strokes` a window: change the signature to `strokes(repo, state, sheet, tex_px, bake: WarBake = null, window := Rect2())`; at its top replace `var r: Rect2 = sheet["rect"]` with:

```gdscript
	var r: Rect2 = sheet["rect"] if window.size.x <= 0.0 else window
```

Everything below already works in `r`'s frame (`_to_tex(r, k, …)`, `r.has_point`), so a window clips and rescales the strokes; the graticule's `sheet` stays the sheet. Do the same in `WarFinePrint.strokes` (add `window := Rect2()`, pass it to `WarSheetInk.strokes`, and use the window as `r`).

`scenes/war_room/war_table.gdshader` — add:

```glsl
// the near-zoom detail patch (spec 2026-10-07-war-room-scale-hover §2): ink and
// fine print over detail_uv, replacing both there, cross-faded at its edge
uniform sampler2D detail_tex : filter_linear_mipmap, hint_default_transparent;
uniform vec4 detail_uv = vec4(0.0);
uniform float detail_on = 0.0;
uniform float detail_feather = 0.04;
```

and wrap the ink + fine compositing:

```glsl
	vec2 du = (UV - detail_uv.xy) / max(detail_uv.zw - detail_uv.xy, vec2(1e-5));
	vec2 dedge = min(du, 1.0 - du);
	float dmix = detail_on * smoothstep(0.0, detail_feather, min(dedge.x, dedge.y));
	vec4 dk = texture(detail_tex, du);
	vec3 dk_straight = srgb_to_linear(dk.rgb / max(dk.a, 1e-4));
	// … existing ink_tex and fine_tex compositing, each scaled by (1.0 - dmix) …
	float dk_a = dk.a * collar_k * dmix;
	col = col * (1.0 - dk_a) + dk_straight * dk_a;
```

(multiply `ink_a` by `(1.0 - dmix)` where it is computed; `fine_a` is left alone — see below.)

`scripts/war_room/war_room_view.gd` — keep `_detail_state := {}`, and in `_apply_camera` (after the near look) call `_update_detail()`:

```gdscript
func _update_detail() -> void:
	var mat := _table.get_active_material(0) as ShaderMaterial
	var lvl := WarDetailInk.level(_repo, _rig.distance)
	if lvl == 0 or _sheet < 0:
		mat.set_shader_parameter("detail_on", 0.0)
		_detail_state = {}
		return
	var view_px := Vector2(size) * units_per_px()   # pack px the view spans
	var centre := WarRoomTable.from_table(_rect, _table_w, Vector2(_rig.target.x, _rig.target.z))
	var now := {"level": lvl, "rect": WarDetailInk.patch_rect(_repo, _rect, centre, view_px),
		"key": WarSheetInk.cache_key(state(), _sheet)}
	if not WarDetailInk.needs_redraw(_detail_state, now):
		return
	_detail_state = now
	var r: Rect2 = now["rect"]
	var vp: SubViewport = %DetailViewport
	var w := int(_repo.bal("war_detail_texture_px"))
	vp.size = Vector2i(w, maxi(1, ceili(w * r.size.y / r.size.x)))
	var scale := _rect.size.x / r.size.x * float(w) / float(WarRoomInk.tex_size(_repo, _rect).x)
	var widths := {}
	for k: String in WarRoomInk.INK_PX:
		widths[k] = _repo.bal("war_ink_%s_px" % k) * scale
	for k: String in WarRoomInk.INK_RATIOS:
		widths[k] = _repo.bal("war_ink_%s" % k)
	var row: Dictionary = WarSheets.series(_repo)[_sheet]
	(%DetailInk as WarInkPainter).paint(WarSheetInk.strokes(_repo, state(), row, w, WarBake.of(_repo), r),
		_repo.war_palette, widths, lettering())
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	mat.set_shader_parameter("detail_tex", vp.get_texture())
	mat.set_shader_parameter("detail_uv", Vector4((r.position.x - _rect.position.x) / _rect.size.x,
		(r.position.y - _rect.position.y) / _rect.size.y, (r.end.x - _rect.position.x) / _rect.size.x,
		(r.end.y - _rect.position.y) / _rect.size.y))
	mat.set_shader_parameter("detail_feather", _repo.bal("war_detail_feather"))
	mat.set_shader_parameter("detail_on", 1.0)
```

and in `set_active(false)` set `%DetailViewport.size = Vector2i(2, 2)` and `_detail_state = {}`.

The patch carries the INK only; the fine texture keeps showing over the whole sheet (its lettering is larger than the ink's lines, so it softens later). If Task 10's crops showed the fine print soft as well, add a second viewport `%DetailFine` the same way, painted with `WarFinePrint.strokes(_repo, state(), row, w, WarBake.of(_repo), r)` in fine mode, bound as `detail_fine_tex`, and in the shader scale `fine_a` by `(1.0 - dmix)` and composite it like `detail_tex`. Record which was done in the spec's §2 gate note.

- [ ] **Step 4: Run the tests, shoot, bench**

Run `tests/war_room/test_war_detail_ink.gd`, `tests/war_room/test_war_sheet_ink.gd`, `tests/war_room/test_war_room_view.gd`. Expected: PASS. Then repeat Task 10's shots (the crops must now read crisp) and Task 9 Step 4's bench, adding a pan at 0.12 m (WASD for 2 s) — the worst frame must stay under the tier's frame budget plus 4 ms.

- [ ] **Step 5: Commit**

```bash
git add scripts/war_room/war_detail_ink.gd scripts/war_room/war_room_view.gd scenes/war_room/war_room.tscn scenes/war_room/war_table.gdshader scripts/war_room/war_sheet_ink.gd scripts/war_room/war_fine_print.gd data/balance.csv tests/war_room/test_war_detail_ink.gd tests/war_room/test_war_sheet_ink.gd
git commit -m "feat(war room): the near-zoom detail patch (spec 2026-10-07 §2, the gate called for it)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

## Landing

After the last task: `./run_tests.sh` green; merge main into this branch (`git merge main` here), rerun the suite, then in the main checkout `git merge --ff-only spec/war-room-scale-hover` and push — only with the owner's go-ahead, and per the shared-checkout rule (never switch its branch; stage only these files).
