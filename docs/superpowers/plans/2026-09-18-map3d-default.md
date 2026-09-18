# The 3D Map as the Default Map — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The map panel shows the 3D map whenever it can, and the 2D map only while a 2D-only layer (HEIGHTS, ECONOMY, MANORS, MILITARY) is on or no 3D scene is built; the "3D MAP" tab goes.

**Architecture:** One rule in `GameRoot._sync_map_view()` replaces the 3D toggle and its four exclusion branches; it drives the screens' existing `set_map3d_view(on)` (`Map3DView.toggle_in`, unchanged). A `balance.csv` key `map3d_default` lets the test suite (via a GUT pre-run hook) and `snapshot_screen --map2d` hold the 2D map.

**Tech Stack:** Godot 4.7, typed GDScript, GUT.

**Spec:** `docs/superpowers/specs/2026-09-18-map3d-default-design.md`

## Global Constraints

- Typed GDScript everywhere (hints on vars, params, returns).
- Design values live in CSVs: `map3d_default` is a `balance.csv` row, read with `Game.data.bal("map3d_default")`.
- `./run_tests.sh` must end green with the expected error count (2 with the gdai plugin binaries present, 0 without).
- The built 3D scene (`res://assets/map3d/<map_id>/world.tscn`) is git-ignored: no test may depend on whether it exists — tests force it through the seam.
- Commit messages end with `Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>`.

---

### Task 1: The rule, the bar, and the suite holding 2D

**Files:**
- Modify: `data/balance.csv` (add one row after the `map3d_*` block's first row, `map3d_fov_deg`)
- Modify: `scripts/map3d/map3d_view.gd:139-141` (add `has_scene` after `scene_path_for`)
- Modify: `scripts/ui/game_root.gd` (`_on_bottom_tab`, `set_height_view`, `set_economy_view`, `set_manor_view`, `set_army_view`, `set_map3d_view`, `_switch_to`)
- Modify: `scripts/ui/bottom_bar.gd:4,14,21-24`
- Create: `tests/pre_run.gd`
- Modify: `run_tests.sh` (the GUT command line)
- Rewrite: `tests/map3d/test_map3d_tab.gd`

**Interfaces:**
- Produces: `Map3DView.has_scene(map_id: String) -> bool`; `GameRoot.map3d_available() -> bool`; `GameRoot.force_map3d_scene(has: bool) -> void` (test/tool seam); `GameRoot.map3d_view() -> bool` (unchanged name, now the rule's last result). `GameRoot.set_map3d_view` is REMOVED.

- [ ] **Step 1: Write the failing tests** — replace `tests/map3d/test_map3d_tab.gd` entirely:

```gdscript
extends GutTest
## The 3D map is the default map (owner 2026-09-18, spec
## 2026-09-18-map3d-default-design.md): the map panel shows Map3DView
## whenever the pack has a built scene and no 2D-only layer (HEIGHTS,
## ECONOMY, MANORS, MILITARY) is on, and the 2D WorldMapView otherwise.
## The scene is git-ignored, so every test forces its presence through
## GameRoot.force_map3d_scene; an unbuilt view still swaps in and shows its
## notice. The suite holds 2D (tests/pre_run.gd); these tests lift that.

func before_each() -> void:
	Game.data.balance["map3d_default"] = 1.0


func after_each() -> void:
	Game.data.balance["map3d_default"] = 0.0


func _court(has_scene: bool = true) -> GameRoot:
	Game.start_campaign(42)
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	r.force_map3d_scene(has_scene)
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	return r


func _shows_3d(r: GameRoot) -> bool:
	var v: Map3DView = r.current_screen.map3d_view()
	return v != null and v.visible and not r.current_screen.world_map().visible


func test_there_is_no_3d_tab() -> void:
	assert_false("3D MAP" in BottomBar.TABS)
	assert_false("3D MAP" in BottomBar.TOGGLES)


func test_the_court_opens_on_the_3d_map() -> void:
	var r: GameRoot = await _court()
	assert_true(r.map3d_view())
	assert_true(_shows_3d(r))


func test_each_2d_layer_shows_the_2d_map_and_closing_it_returns_to_3d() -> void:
	var r: GameRoot = await _court()
	for setter: String in ["set_height_view", "set_economy_view", "set_manor_view", "set_army_view"]:
		r.call(setter, true)
		assert_false(r.map3d_view(), setter + " on: 2D")
		assert_true(r.current_screen.world_map().visible, setter + " on: the 2D map shows")
		r.call(setter, false)
		assert_true(_shows_3d(r), setter + " off: back to 3D")


func test_switching_themes_stays_on_2d() -> void:
	var r: GameRoot = await _court()
	r.set_economy_view(true)
	r.set_manor_view(true)
	assert_false(r.economy_view(), "the themes still put each other out")
	assert_false(r.map3d_view(), "and the map stays 2D between them")
	r.set_height_view(true)
	assert_false(r.map3d_view())


func test_the_bottom_tab_routes_through_the_rule() -> void:
	var r: GameRoot = await _court()
	r._on_bottom_tab("MANORS")
	assert_false(r.map3d_view())
	r._on_bottom_tab("MANORS")
	assert_true(_shows_3d(r))


func test_no_built_scene_keeps_the_2d_map() -> void:
	var r: GameRoot = await _court(false)
	assert_false(r.map3d_view())
	assert_null(r.current_screen.map3d_view(), "no 3D view is even made")
	assert_true(r.current_screen.world_map().visible)


func test_map3d_default_zero_keeps_the_2d_map() -> void:
	Game.data.balance["map3d_default"] = 0.0
	var r: GameRoot = await _court()
	assert_false(r.map3d_view())
	assert_true(r.current_screen.world_map().visible)


func test_the_choice_follows_the_player_to_the_next_screen() -> void:
	var r: GameRoot = await _court()
	r._switch_to(GameRoot.State.COURT)
	await wait_frames(2)
	assert_true(_shows_3d(r), "3D on the new screen")
	r.set_manor_view(true)
	r._switch_to(GameRoot.State.COURT)
	await wait_frames(2)
	assert_false(r.map3d_view(), "a layer that is on keeps the new screen 2D")
	assert_true(r.current_screen.world_map().visible)


func test_the_real_scene_check_reads_the_pack() -> void:
	assert_false(Map3DView.has_scene("no_such_pack"))


func test_a_3d_selection_opens_the_card_in_the_left_column() -> void:
	var r: GameRoot = await _court()
	await wait_frames(1)
	var screen: CourtScreen = r.current_screen
	var view := screen.map3d_view()
	var code := String(Game.data.kingdoms[Game.data.resolve_realm("player_realm")]["capital_burg"])
	view.object_selected.emit({"title": "x", "obj": {"kind": "burg", "code": code}})
	await wait_frames(1)
	assert_true(screen.detail_panel().visible, "the town's card, as a 2D click would open")
	assert_false(screen.dashboard().visible, "in place of the dashboard")
	var province := String(Game.data.burgs[code]["province_code"])
	view.province_selected.emit(province)
	await wait_frames(1)
	assert_true(screen.detail_panel().visible, "a province's card too")
```

- [ ] **Step 2: Run to verify they fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/map3d/test_map3d_tab.gd -gexit`
Expected: FAIL — `force_map3d_scene` / `has_scene` not found (parse error or failing asserts).

- [ ] **Step 3: Add the balance row** — insert after the `map3d_fov_deg` line of `data/balance.csv`:

```csv
map3d_default,1,"3D MAP (owner 2026-09-18, spec 2026-09-18-map3d-default-design): 1 = the map panel shows the 3D map whenever the pack has a built scene and no 2D-only layer (HEIGHTS/ECONOMY/MANORS/MILITARY) is on; 0 = always the 2D map (the test suite's pre-run hook and snapshot_screen --map2d set 0)"
```

- [ ] **Step 4: `Map3DView.has_scene`** — after `scene_path_for` in `scripts/map3d/map3d_view.gd`:

```gdscript
## Whether `map_id`'s 3D scene has been built (tools/map3d; git-ignored, so a
## fresh clone has none and GameRoot keeps the 2D map).
static func has_scene(map_id: String) -> bool:
	return ResourceLoader.exists(scene_path_for(map_id))
```

- [ ] **Step 5: GameRoot's rule** — in `scripts/ui/game_root.gd`:

a) Replace the `_map3d_view` declaration comment/var (line ~41-42) with:

```gdscript
## Which map the panel shows (owner 2026-09-18: the 3D map is the default):
## the last result of _sync_map_view, never set by hand.
var _map3d_view := false
## Test/tool seam for "the pack has a built 3D scene": -1 asks the disk.
var _map3d_scene := -1
```

b) In `_on_bottom_tab`, delete the whole `"3D MAP":` branch (3 body lines).

c) In `set_height_view` delete `if on and _map3d_view:` / `set_map3d_view(false)`, and add `_sync_map_view()` as the function's last line. Same for `set_economy_view` (delete its two 3D lines, `_sync_map_view()` last). In `set_manor_view` delete `if _map3d_view:` / `set_map3d_view(false)` inside `if on:` and add `_sync_map_view()` last. In `set_army_view` add `_sync_map_view()` last.

d) Replace the whole `set_map3d_view` function and its doc comment with:

```gdscript
## The one rule for which map the panel shows (spec
## 2026-09-18-map3d-default-design): 3D whenever the pack has a built scene,
## balance map3d_default is on, and no 2D-only layer is — HEIGHTS, ECONOMY
## and MANORS draw on the 2D map, and so do MILITARY's counters. Runs on every
## layer change and every screen swap.
func _sync_map_view() -> void:
	_map3d_view = Game.data.bal("map3d_default") > 0.0 and map3d_available() \
			and not (_height_view or _economy_view or _manor_view or _army_view)
	if current_screen != null and current_screen.has_method("set_map3d_view"):
		current_screen.set_map3d_view(_map3d_view)

func map3d_available() -> bool:
	if _map3d_scene >= 0:
		return _map3d_scene == 1
	return Map3DView.has_scene(Game.data.map_id)

## Test/tool seam: pretend the pack's 3D scene is (or is not) built.
func force_map3d_scene(has: bool) -> void:
	_map3d_scene = 1 if has else 0
	_sync_map_view()
```

(keep `func map3d_view() -> bool: return _map3d_view` as it is.)

e) In `_switch_to`, replace

```gdscript
	if _map3d_view and current_screen != null and current_screen.has_method("set_map3d_view"):
		current_screen.set_map3d_view(true)
```

with `	_sync_map_view()`.

- [ ] **Step 6: The bottom bar** — `scripts/ui/bottom_bar.gd`: `TABS` loses `"3D MAP", `; `TOGGLES` loses `"3D MAP", `; the header comment's first tab line reads `## outside the map: HEIGHTS | ECONOMY | MANORS | REALM | MILITARY |`, and the TOGGLES comment's last sentence becomes: `The 3D map (owner 2026-09-18) is the default and has no tab: GameRoot shows it whenever none of these four is lit.`

- [ ] **Step 7: The suite holds 2D** — create `tests/pre_run.gd`:

```gdscript
extends GutHookScript
## GUT pre-run hook (run_tests.sh -gpre_run_script): the suite holds the 2D
## map. A machine with a built 3D scene would otherwise load Terrain3D into
## every GameRoot a test makes and hide the WorldMapView the UI tests assert
## on; tests/map3d/test_map3d_tab.gd lifts this for itself.

func run() -> void:
	Game.data.balance["map3d_default"] = 0.0
```

In `run_tests.sh`, change the GUT line to:

```sh
  -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gpre_run_script=res://tests/pre_run.gd -gexit > "$TEST_OUTPUT" 2>&1 || code=$?
```

- [ ] **Step 8: Run the tab tests, then the suite**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/map3d/test_map3d_tab.gd -gexit`
Expected: all PASS.
Run: `./run_tests.sh`
Expected: green, expected error count. If another test called `set_map3d_view` or pressed "3D MAP" (grep `tests/` for both), port it to `force_map3d_scene` + `map3d_default` the same way.

- [ ] **Step 9: Commit**

```bash
git add data/balance.csv scripts/map3d/map3d_view.gd scripts/ui/game_root.gd scripts/ui/bottom_bar.gd tests/pre_run.gd run_tests.sh tests/map3d/test_map3d_tab.gd
git commit -m "feat(map3d): the 3D map is the default map; the 3D MAP tab goes

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Tools follow the rule

**Files:**
- Modify: `tools/map3d/bench.gd:61`
- Modify: `tools/snapshot_screen.gd` (header doc lines 43, 60, 64; arg loop ~72-100; after `Game.start_campaign`)

**Interfaces:**
- Consumes: `GameRoot.map3d_view()`, balance `map3d_default` (Task 1).

- [ ] **Step 1: bench** — delete `root.set_map3d_view(true)`; the court opens on 3D by the rule. Its existing `v == null or not v.is_loaded()` check already reports an unbuilt scene.

- [ ] **Step 2: snapshot_screen `--map2d`** — add `var _map2d := false` beside the other option vars; in the arg loop add

```gdscript
		elif args[i] == "--map2d":
			_map2d = true
```

(a flag with no value: it must not skip the next arg — follow how the loop advances, `i += 1` at its end.) Right after `Game.start_campaign(_seed)` add:

```gdscript
	if _map2d:
		Game.data.balance["map3d_default"] = 0.0
```

Doc: replace the `--layer` line's mention of `"3d map"` and the `--click3d` / `--zoom3d` lines' `--layer "3d map"` with `(with --screen root: the court opens on the 3D map when it is built)`, and add `## --map2d holds the 2D map (balance map3d_default 0) — for shooting the plain 2D map with --screen root.`

- [ ] **Step 3: Verify both by running them** (needs the built scene — run in the checkout that has `assets/map3d/beria/world.tscn`):

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_screen.tscn -- --screen root --resolution 1920x1080 --out /tmp/cc_root3d.png
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_screen.tscn -- --screen root --resolution 1920x1080 --map2d --out /tmp/cc_root2d.png
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_screen.tscn -- --screen root --resolution 1920x1080 --layer manors --out /tmp/cc_root_manors.png
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/map3d/bench.tscn
```

Expected: the first shot shows the 3D map, the second and third the 2D map (the third with the MANORS theme), and no "3D MAP" tab in any; the bench prints its rows and exits 0.

- [ ] **Step 4: Commit**

```bash
git add tools/map3d/bench.gd tools/snapshot_screen.gd
git commit -m "chore(map3d): tools follow the default-3D rule; snapshot_screen --map2d

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Documentation

**Files:**
- Modify: `CLAUDE.md` (the "**The 3D MAP tab**" paragraph, the "**Thematic map layers.**" bottom-bar list, the Layout line `scripts/map3d/`)
- Modify: `tools/map3d/README.md` (any "3D MAP tab" usage line)

- [ ] **Step 1: CLAUDE.md** — rename the paragraph's lead to `**The 3D map is the default map** (owner 2026-09-18; tab removed, spec docs/superpowers/specs/2026-09-18-map3d-default-design.md)` and replace its first sentence ("The first bottom-bar tab swaps …") with: `The map panel shows Map3DView (scripts/map3d/) whenever the pack has a built scene, balance map3d_default is 1 and no 2D-only layer — HEIGHTS, ECONOMY, MANORS, MILITARY — is on; otherwise the 2D WorldMapView, which stays only as those layers' ground until the spec's migration list (hover card, kingdom labels, manor picking and MANORS, MILITARY, ECONOMY/HEIGHTS, wash and town art) has moved to 3D, and is then deleted. GameRoot._sync_map_view is the one rule; the suite holds 2D through tests/pre_run.gd, and snapshot_screen --map2d likewise.` Replace "GameRoot owns the state like the other tabs (`set_map3d_view`), it follows the player across screens, and it is exclusive with HEIGHTS / ECONOMY / MANORS, which draw on the 2D map only. Without a built scene the view shows a notice and nothing else changes." with "Without a built scene (a fresh clone) the game shows the 2D map." In the bottom-bar list drop `3D MAP | `. In Layout, `scripts/map3d/   # the 3D map (the default): Map3DView, …`.

- [ ] **Step 2: README** — `grep -n "3D MAP" tools/map3d/README.md`; reword each hit to "the 3D map (the default map)".

- [ ] **Step 3: Commit**

```bash
git add CLAUDE.md tools/map3d/README.md
git commit -m "docs: the 3D map is the default map

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>"
```
