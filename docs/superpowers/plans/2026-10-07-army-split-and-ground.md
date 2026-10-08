# Army split and ground — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split every kingdom's opening army into pure-arm units (≤ 600 men, one royal artillery train each), store them in the save, and give every standing land unit its own ground — one unit per town holds the seat, the rest camp in hex rings — with one piece per unit on the map, nothing overlapping, and orders to a multi-selection.

**Architecture:** A pure `ArmySplit` turns the pack's `regiments.csv` into a roster (same row shape plus `parent_code`, `is_royal`, `camp_town`), which `GameState.new_campaign` writes into `state.army_roster` with `state.town_seat`; every reader goes through `ArmySystem.roster` / `regiment`. A pure `ArmyGround` owns slots, seats, settling on arrival and the seat-swap order. The map drops the garrison counter, spreads counters and chips with a pure `Map3DDeclutter`, and gains Shift-click / Shift-drag selection.

**Tech Stack:** Godot 4.7, typed GDScript, GUT (`./run_tests.sh`, `./run_tests.sh --fast`), CSV data under `data/`.

**Spec:** `docs/superpowers/specs/2026-10-07-army-split-and-ground-design.md` — read it before any task. Section numbers below (§n) are the spec's.

## Global Constraints

- Work only in the worktree `/Users/samuelzhang/game_design/.claude/worktrees/army-split` on branch `feat/army-split`. Never switch branches or stash in `/Users/samuelzhang/game_design` (the shared main checkout).
- Every commit ends with the line `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Typed GDScript everywhere (vars, params, returns). Engine classes are `RefCounted`, never touch `Game`, `scripts/ui/` or `scripts/llm/` (`test_engine_isolation.gd`). `scripts/map3d/` and `scripts/war_room/` never read `Game`.
- Determinism: no wall clock, no unseeded random; iterate dictionaries in sorted key order wherever the order can change an outcome. Engine state holds whole numbers; positions in state are whole metres.
- Design values live in `data/*.csv` (scalars in `data/balance.csv`), never as constants in scripts.
- No code, tool or test names a map pack or a kingdom: tests derive the realm with `repo.resolve_realm("player_realm")` and every expected count from the pack's own rows.
- A test takes its data from `SuiteData.repo()` / `SuiteData.campaign(repo, seed)` (`tests/suite_data.gd`), never `DataRepository.load_all`.
- Full suite before each task's commit: `./run_tests.sh` must end with the expected error count — "Errors 2" when `addons/gdai-mcp-plugin-godot/bin/gdai_mcp_plugin.gdextension` exists in the worktree, else 0 (the script prints which it expects). `./run_tests.sh --fast` is the edit loop.
- `scripts/map3d/map3d_view.gd` stays ≤ 582 lines and every other `scripts/map3d/*.gd` ≤ 300 lines (`tests/map3d/test_map3d_shape.gd`). `scripts/map3d/map3d_layer_units.gd` is at 299 now.
- The LOOK is editor-owned: a new colour or width on a drawn HUD piece is an `@export` with its default in the script; never a style built from CSV paths. Never run a 3D snapshot with `--headless`.
- Nested `CLAUDE.md` files are capped by `tests/engine/test_claude_md_size.gd`; write current rules only, no history.

## Plan rulings (where the plan settles what the spec leaves open)

- **R1 — argument order.** The spec writes `regiment(repo, state, code)`; the plan keeps the existing order and appends an optional state: `ArmySystem.regiment(repo, code, state := null)`, `ArmySystem.roster(repo, state := null)`, `MapObjects.regiments_of(repo, kingdom, state := null)`. This avoids touching ~90 call sites at once; every engine call site that has a `state` in scope passes it (Task 3).
- **R2 — data layout.** The spec's single `data/army_split.csv` key/value table becomes: per-arm rows in `data/army_split.csv` (`arm,start_ring,code_word,label_word,pooled,notes`), the scalars in `data/balance.csv` (`army_split_cap_men`, `army_slot_spacing_m`, `army_slot_max_rings`, `map3d_declutter_step_px`, `map3d_declutter_max_px`, `war_spread_step_m`, `war_spread_max_m`), and the camp-blocked terrains in `data/army_camp_blocked.csv` (`terrain,notes`). Same values, the repository's existing shapes.
- **R3 — camped means settled around the town.** `camped_by` reads the town a unit SETTLED around (`camp_town`, written by `ArmyGround.settle` and by the split), not the distance to the town. The hex rings can reach past a village's 1 km reach; a unit settled around its town must still be fed from it (the owner's option A for the suburbs). `camp_town` is a roster column (the start) and a `state.regiments` entry field (the player's live units).
- **R4 — Shift for the box.** A plain left drag already pans the camera (`Map3DInput`), so the selection box is a Shift + left drag; a Shift + left click toggles one unit. A plain left click stays as it is.
- **R5 — lists.** The war folio shows one unit at a time (no list to group). Grouping applies to the MILITARY panel's regiment rows and the marshal's monthly report, through one ordering function, `ArmySystem.ordered`.
- **R6 — seat menu rows.** The seat rows are `data/army_route_orders.csv` keys `seat` ("Take the seat") and `seat_empty` ("Garrison the town"), added by `ArmyOrderMenu._open_for` only for a camped unit that is not seated; `data/army_orders.csv` is unchanged.
- **R7 — split cache.** `ArmySplit` caches the pack's split per repository instance and keeps at most four entries (the suite makes a repository copy per test).

## Review Focus

- A march ordered into the ring of a town the unit's kingdom does NOT hold: the town is ignored — no seat, the slots are laid around the ordered point (Task 4 test `test_a_foreign_town_is_the_field`).
- Every slot blocked (sent onto a spit of land between water): the unit stands where it arrived, nothing crashes, and it still holds that ground (Task 1 test `test_no_free_slot_returns_none`, Task 4 test `test_a_unit_with_no_free_slot_stands_where_it_arrived`).
- An `ARMY_SEAT` whose courier arrives after the seat emptied: the unit simply takes the empty seat (Task 5 test `test_seat_order_on_an_empty_seat_takes_it`).
- A mixed selection — a fleet, a unit already marching, a unit the chest cannot pay for — given one order: each unit is judged alone; the ones that can go, go; each refusal is said (Task 8 test `test_mixed_selection_sends_what_it_can`).
- A save made after the split survives the round trip: the roster, the seats and `camp_town` load bit-exact (`SaveLoad.state_hash` equal) (Task 2 test `test_roster_and_seats_round_trip`).

---

## File structure

| File | Responsibility |
|---|---|
| `scripts/engine/army_ground.gd` (new) | Hex slots, the taken-ground grid, free slots, seats, `camped_by`, settling, the seat refill, the seat swap, reconcile |
| `scripts/engine/army_split.gd` (new) | The pure split of the pack into a roster and seats; the cache; `shares`, codes, labels |
| `scripts/map3d/map3d_declutter.gd` (new) | Pure screen/table spreading of boxes so none overlaps |
| `data/army_split.csv`, `data/army_camp_blocked.csv` (new) | Per-arm split rows; camp-blocked terrains |
| `data/balance.csv` | New scalar keys (R2) |
| `scripts/engine/data_repository.gd` | Load the two tables; `ArmySplit.forget()` on `load_map` |
| `scripts/engine/game_state.gd` | `army_roster`, `town_seat`, `SAVE_VERSION` 6, `MIN_SAVE_VERSION` 6, encode/decode, `new_campaign` |
| `scripts/engine/save_load.gd`, `scripts/ui/game.gd`, `scripts/ui/game_root.gd`, `scripts/ui/main_menu.gd` | Refuse old saves with a reason |
| `scripts/engine/army_system.gd` | `roster`, `regiment(…, state)`, `ordered`; works/morale/terrain on `ArmyGround`; settle on arrival; leave on march; delete `quartered_in` |
| `scripts/engine/map_objects.gd` | `regiments_of(…, state)`; delete `garrisons`, `garrison_of`, `garrison_label`, `royal_regiment`; `army_piece` by `is_royal` |
| `scripts/engine/supply_system.gd`, `supply_lines.gd`, `ledger_resolvers.gd`, `war_folio.gd`, `war_room.gd`, `war_ground.gd`, `spy_system.gd`, `hazards.gd`, `tick_engine.gd`, `courier_system.gd`, `action_system.gd`, `missive_writer.gd` | Read the roster; seat/camp readers; `ARMY_SEAT` |
| `data/action_signatures.csv`, `order_costs.csv`, `policy_actions_court_additions.csv`, `army_route_orders.csv` | `ARMY_SEAT` rows; seat menu rows |
| `scripts/ui/army_counters.gd`, `scripts/map3d/map3d_hud_armies.gd`, `map3d_layer_units.gd`, `map3d_picker.gd`, `map3d_selection.gd`, `map3d_view.gd`, `map3d_input.gd`, `map3d_context.gd`, `scripts/ui/army_order_menu.gd`, `scripts/ui/military_panel.gd`, `scripts/war_room/war_pieces.gd`, `war_room_view.gd`, `war_intel_ink.gd`, `tools/snapshot_screen.gd` | Pieces per unit, no garrison counter, declutter, multi-select, grouped lists |
| `tests/engine/test_army_split.gd`, `test_army_ground.gd`, `test_army_seat.gd`, `test_roster_guard.gd`, `tests/map3d/test_map3d_declutter.gd`, `tests/ui/test_army_multi_select.gd` (new) | The new behaviour |
| `scripts/engine/CLAUDE.md`, `scripts/map3d/CLAUDE.md`, `data/CLAUDE.md`, `.claude/skills/visual-review/taste.md`, the spec | Guidance |

---

### Task 1: Data tables and the hex ground (`ArmyGround`, pure half)

**Files:**
- Create: `data/army_split.csv`, `data/army_camp_blocked.csv`, `scripts/engine/army_ground.gd`, `tests/engine/test_army_ground.gd`
- Modify: `data/balance.csv` (append rows), `scripts/engine/data_repository.gd` (vars near `army_formations` ~line 125; loads after `army_formations.csv` ~line 812)

**Interfaces:**
- Produces:
  - `repo.army_split: Array` of `{arm: String, start_ring: int, code_word: String, label_word: String, pooled: bool}` in file order
  - `repo.army_camp_blocked: Dictionary` (terrain → true)
  - `ArmyGround.NONE := Vector2i(-1, -1)`
  - `ArmyGround.ring(k: int) -> Array` (axial `Vector2i`s)
  - `ArmyGround.slot_m(centre_m: Vector2i, axial: Vector2i, spacing: int) -> Vector2i`
  - `ArmyGround.start_ring(repo, arm: String) -> int`
  - `ArmyGround.new_taken(repo) -> Dictionary`
  - `ArmyGround.take(taken: Dictionary, p_m: Vector2i) -> void`
  - `ArmyGround.is_free(repo, taken: Dictionary, p_m: Vector2i) -> bool`
  - `ArmyGround.free_slot(repo, centre_m: Vector2i, arm: String, taken: Dictionary, town: bool) -> Vector2i`
  - `ArmyGround.town_point_m(repo, town: String) -> Vector2i`

- [ ] **Step 1: Add the data**

`data/army_split.csv`:

```csv
arm,start_ring,code_word,label_word,pooled,notes
infantry,1,foot,Foot,0,"owner 2026-10-07 (spec 2026-10-07-army-split-and-ground §3): file order is the split's arm order; a unit of this arm takes its first slot at this ring or further out (§4.2)"
archers,2,archers,Archers,0,
cavalry,3,horse,Horse,0,
artillery,1,royal_train,Royal Train of {kingdom},1,"pooled (owner choice B): every gun of a kingdom is ONE unit at its capital; {kingdom} is the kingdom's label"
```

`data/army_camp_blocked.csv`:

```csv
terrain,notes
mountains,"owner 2026-10-07 (spec 2026-10-07-army-split-and-ground §4.2): no unit makes camp on a mountain or a peak (ArmySystem.terrain_at)"
```

Append to `data/balance.csv`:

```csv
army_split_cap_men,600,"owner 2026-10-07 (spec 2026-10-07-army-split-and-ground §3): the most men of one arm in one unit; an arm over it splits into ceil(men / cap) even units"
army_slot_spacing_m,400,"spec 2026-10-07-army-split-and-ground §4.2: the hex lattice's pitch in whole metres between two units' camps; set in the visual review from the piece's footprint"
army_slot_max_rings,8,"spec §4.2: the farthest ring searched for a free slot; past it the unit stands where it arrived"
```

- [ ] **Step 2: Load the tables**

In `scripts/engine/data_repository.gd`, after the `army_formations` var block:

```gdscript
## data/army_split.csv (spec 2026-10-07-army-split-and-ground §3): the arms a
## regiment splits into, in file order: [{arm, start_ring, code_word,
## label_word, pooled}]; a POOLED arm is one unit a kingdom, at its capital.
var army_split: Array = []
## data/army_camp_blocked.csv: terrain -> true where no unit makes camp (ArmyGround).
var army_camp_blocked: Dictionary = {}
```

After the `army_formations.sort_custom(...)` call:

```gdscript
	if not _load_if_present(dir + "/army_split.csv", ["arm", "start_ring", "code_word", "label_word", "pooled"],
			func(r): army_split.append({"arm": String(r["arm"]), "start_ring": int(r["start_ring"]),
				"code_word": String(r["code_word"]), "label_word": String(r["label_word"]),
				"pooled": String(r["pooled"]) == "1"})):
		return false
	if not _load_if_present(dir + "/army_camp_blocked.csv", ["terrain"],
			func(r): army_camp_blocked[String(r["terrain"])] = true):
		return false
```

If the load function clears its tables at the top (search for `army_formations.clear()` or the reset block), clear these two there as well.

- [ ] **Step 3: Write the failing tests**

`tests/engine/test_army_ground.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The hex ground (spec 2026-10-07-army-split-and-ground §4.2).

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


func test_rings_have_six_k_slots_starting_east_counter_clockwise() -> void:
	assert_eq(ArmyGround.ring(0), [Vector2i.ZERO])
	assert_eq(ArmyGround.ring(1), [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)])
	for k in range(1, 6):
		assert_eq(ArmyGround.ring(k).size(), 6 * k)


func test_slot_metres_on_the_lattice() -> void:
	# pitch 400: east (400, 0); north-east (200, -346) — y grows down the map
	assert_eq(ArmyGround.slot_m(Vector2i(1000, 1000), Vector2i(1, 0), 400), Vector2i(1400, 1000))
	assert_eq(ArmyGround.slot_m(Vector2i(1000, 1000), Vector2i(1, -1), 400), Vector2i(1200, 654))
	assert_eq(ArmyGround.slot_m(Vector2i(1000, 1000), Vector2i(0, 1), 400), Vector2i(1200, 1346))


func test_start_rings_are_the_tables() -> void:
	for row: Dictionary in repo.army_split:
		assert_eq(ArmyGround.start_ring(repo, String(row["arm"])), int(row["start_ring"]))


## A land point well inside the player's capital province, in metres.
func _land_m() -> Vector2i:
	var cap: Dictionary = repo.burgs[String(repo.kingdoms[repo.resolve_realm("player_realm")]["capital_burg"])]
	return ArmySystem.pack_to_metres(repo, Vector2(float(cap["x"]), float(cap["y"])))


func test_a_taken_point_blocks_half_a_pitch_round_it() -> void:
	var taken := ArmyGround.new_taken(repo)
	var p := _land_m()
	assert_true(ArmyGround.is_free(repo, taken, p))
	ArmyGround.take(taken, p)
	var half := int(repo.bal("army_slot_spacing_m")) / 2
	assert_false(ArmyGround.is_free(repo, taken, p + Vector2i(half - 1, 0)))
	assert_true(ArmyGround.is_free(repo, taken, p + Vector2i(half, 0)) \
		or not ArmyGround.is_free(repo, ArmyGround.new_taken(repo), p + Vector2i(half, 0)),
		"free unless that ground is itself water or blocked")


func test_the_sea_is_never_free() -> void:
	assert_false(ArmyGround.is_free(repo, ArmyGround.new_taken(repo), Vector2i(-5000, -5000)))


func test_free_slot_starts_at_the_arms_ring() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	var spacing := int(repo.bal("army_slot_spacing_m"))
	for row: Dictionary in repo.army_split:
		var arm := String(row["arm"])
		var got := ArmyGround.free_slot(repo, c, arm, taken, true)
		assert_ne(got, ArmyGround.NONE)
		# its ring: the lattice distance from the centre, never inside start_ring
		var d := Vector2(got - c).length()
		assert_gte(d, float(spacing * int(row["start_ring"])) * 0.85, arm)


func test_the_field_centre_goes_to_the_first() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	assert_eq(ArmyGround.free_slot(repo, c, "cavalry", taken, false), c, "an empty field: the centre")
	ArmyGround.take(taken, c)
	assert_ne(ArmyGround.free_slot(repo, c, "cavalry", taken, false), c)


func test_a_town_centre_is_never_a_camp_slot() -> void:
	var c := _land_m()
	assert_ne(ArmyGround.free_slot(repo, c, "infantry", ArmyGround.new_taken(repo), true), c)


func test_no_free_slot_returns_none() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	var spacing := int(repo.bal("army_slot_spacing_m"))
	for k in range(0, int(repo.bal("army_slot_max_rings")) + 1):
		for ax: Vector2i in ArmyGround.ring(k):
			ArmyGround.take(taken, ArmyGround.slot_m(c, ax, spacing))
	assert_eq(ArmyGround.free_slot(repo, c, "infantry", taken, true), ArmyGround.NONE)


func test_two_slots_in_order_are_distinct() -> void:
	var c := _land_m()
	var taken := ArmyGround.new_taken(repo)
	var a := ArmyGround.free_slot(repo, c, "infantry", taken, true)
	ArmyGround.take(taken, a)
	var b := ArmyGround.free_slot(repo, c, "infantry", taken, true)
	assert_ne(a, b)
	assert_gte(Vector2(a - b).length(), float(int(repo.bal("army_slot_spacing_m")) / 2))
```

- [ ] **Step 4: Run them, expect failure**

Run: `./run_tests.sh --fast` — expect parse errors / failures naming `ArmyGround`.

- [ ] **Step 5: Write `scripts/engine/army_ground.gd` (pure half)**

```gdscript
class_name ArmyGround
extends RefCounted
## The ground a unit holds (owner 2026-10-07, spec docs/superpowers/specs/
## 2026-10-07-army-split-and-ground-design.md §4): only a STANDING land unit
## holds ground — a column on the march holds none, so columns pass through
## each other, and a fleet never does. Around a centre the camps lie on a hex
## lattice of army_slot_spacing_m, ring by ring (ring k has 6k slots, taken
## from the east counter-clockwise); a unit takes the first free slot at its
## arm's ring (data/army_split.csv start_ring) or further out. Ring 0 is a
## town's SEAT, never a camp; in the field it goes to whoever comes first.

## No slot (none free within army_slot_max_rings).
const NONE := Vector2i(-1, -1)
## The walk round a ring from its east corner: to NE, NW, W, SW, SE, E corners.
const _WALK := [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
	Vector2i(1, 0), Vector2i(1, -1)]


## Ring k's axial cells, east first, counter-clockwise on the map (y down).
static func ring(k: int) -> Array:
	if k <= 0:
		return [Vector2i.ZERO]
	var out: Array = []
	var at := Vector2i(k, 0)
	for side in 6:
		for i in k:
			out.append(at)
			at += _WALK[side]
	return out


## An axial cell's camp in whole metres around `centre_m`.
static func slot_m(centre_m: Vector2i, axial: Vector2i, spacing: int) -> Vector2i:
	return centre_m + Vector2i(int(round(spacing * (axial.x + axial.y * 0.5))),
		int(round(spacing * axial.y * sqrt(3.0) / 2.0)))


## The first ring an arm camps on (data/army_split.csv); 1 for an arm with no row.
static func start_ring(repo: DataRepository, arm: String) -> int:
	for row: Dictionary in repo.army_split:
		if String(row["arm"]) == arm:
			return int(row["start_ring"])
	return 1


## An empty record of held ground: points bucketed by the pitch.
static func new_taken(repo: DataRepository) -> Dictionary:
	return {"cell": maxi(int(repo.bal("army_slot_spacing_m")), 1), "grid": {}}


static func take(taken: Dictionary, p_m: Vector2i) -> void:
	var key := _bucket(taken, p_m)
	if not (taken["grid"] as Dictionary).has(key):
		taken["grid"][key] = []
	(taken["grid"][key] as Array).append(p_m)


static func _bucket(taken: Dictionary, p_m: Vector2i) -> Vector2i:
	var cell := int(taken["cell"])
	return Vector2i(floori(float(p_m.x) / cell), floori(float(p_m.y) / cell))


## Ground a unit may camp on: land, not a blocked terrain, and no standing
## unit within half a pitch.
static func is_free(repo: DataRepository, taken: Dictionary, p_m: Vector2i) -> bool:
	var px := ArmySystem.metres_to_pack(repo, p_m)
	if MapEconomy.cell_at(repo, px) < 0:
		return false
	if repo.army_camp_blocked.has(ArmySystem.terrain_at(repo, px)):
		return false
	var half := float(int(taken["cell"])) / 2.0
	var home := _bucket(taken, p_m)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for q: Vector2i in (taken["grid"] as Dictionary).get(home + Vector2i(dx, dy), []):
				if Vector2(q - p_m).length() < half:
					return false
	return true


## The slot a unit of `arm` takes around `centre_m`: in the FIELD (`town`
## false) the centre itself while it is free; else the first free slot at the
## arm's ring or further out, ring by ring; NONE past army_slot_max_rings.
static func free_slot(repo: DataRepository, centre_m: Vector2i, arm: String, taken: Dictionary,
		town: bool) -> Vector2i:
	if not town and is_free(repo, taken, centre_m):
		return centre_m
	var spacing := int(repo.bal("army_slot_spacing_m"))
	for k in range(maxi(start_ring(repo, arm), 1), int(repo.bal("army_slot_max_rings")) + 1):
		for ax: Vector2i in ring(k):
			var p := slot_m(centre_m, ax, spacing)
			if is_free(repo, taken, p):
				return p
	return NONE


## A town's own point (its seat) in whole metres.
static func town_point_m(repo: DataRepository, town: String) -> Vector2i:
	var b: Dictionary = repo.burgs[town]
	return ArmySystem.pack_to_metres(repo, Vector2(float(b["x"]), float(b["y"])))
```

If `test_slot_metres_on_the_lattice` disagrees by one metre on a rounding, the test is right about the formula (`round(400 * -0.5) = -200`, `round(400 * -0.866) = -346`); fix the code, not the expectation.

- [ ] **Step 6: Run the tests, expect pass**

Run: `./run_tests.sh --fast` — `test_army_ground.gd` passes; nothing else changed.

- [ ] **Step 7: Commit**

```bash
git add data/army_split.csv data/army_camp_blocked.csv data/balance.csv scripts/engine/data_repository.gd scripts/engine/army_ground.gd tests/engine/test_army_ground.gd
git commit -m "feat(army): the hex ground a unit camps on

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The split, the roster in the save, old saves refused

**Files:**
- Create: `scripts/engine/army_split.gd`, `tests/engine/test_army_split.gd`
- Modify:
  - `scripts/engine/game_state.gd`: vars near `regiments` ~line 292; `SAVE_VERSION` ~line 331; `to_dict` / `from_dict`; `new_campaign` ~line 76
  - `scripts/engine/save_load.gd`
  - `scripts/engine/data_repository.gd`: `load_map` forgets ~line 914
  - `scripts/ui/game.gd`: `load_campaign` ~line 287
  - `scripts/ui/game_root.gd`: lines ~948 and ~1104
  - `scripts/ui/main_menu.gd`: `show_load_failed` ~line 220
  - `tests/engine/test_save_load.gd`

**Interfaces:**
- Consumes: Task 1's `ArmyGround.free_slot`, `new_taken`, `take`, `town_point_m`, `NONE`; `repo.army_split`.
- Produces:
  - `ArmySplit.split(repo) -> Dictionary` `{roster, seats}`, a deep copy
  - `ArmySplit.roster_of(repo) -> Dictionary`
  - `ArmySplit.seats_of(repo) -> Dictionary` (read-only cached)
  - `ArmySplit.shares(men: int, cap: int) -> Array`
  - `ArmySplit.forget() -> void`
  - Roster row: the pack row's keys plus `parent_code`, `is_royal`, `camp_town`.
  - `GameState.army_roster: Dictionary`, `GameState.town_seat: Dictionary`, `GameState.MIN_SAVE_VERSION := 6`
  - `SaveLoad.last_error: String` (`""`, `"missing"`, `"corrupt"`, `"outdated"`)
  - `Game.load_error: String`

- [ ] **Step 1: Write the failing tests**

`tests/engine/test_army_split.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The opening army as units (spec 2026-10-07-army-split-and-ground §3).

var repo: DataRepository
var split: Dictionary
var roster: Dictionary


func before_all() -> void:
	repo = SuiteData.repo()
	split = ArmySplit.split(repo)
	roster = split["roster"]


func _pack_rows() -> Array:
	var rows: Array = repo.world_table("military", "regiments").values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["regiment_code"]) < String(b["regiment_code"]))
	return rows


func _arms() -> Array:
	return repo.army_split.filter(func(r: Dictionary) -> bool: return not bool(r["pooled"])) \
		.map(func(r: Dictionary) -> String: return String(r["arm"]))


func test_shares_are_even_and_larger_first() -> void:
	assert_eq(ArmySplit.shares(1268, 600), [423, 423, 422])
	assert_eq(ArmySplit.shares(1200, 600), [600, 600])
	assert_eq(ArmySplit.shares(1201, 600), [401, 400, 400])
	assert_eq(ArmySplit.shares(500, 600), [500])
	assert_eq(ArmySplit.shares(37, 600), [37], "fewer than 300 is still a unit")
	assert_eq(ArmySplit.shares(0, 600), [])


func test_every_unit_is_one_arm_and_within_the_cap() -> void:
	var cap := int(repo.bal("army_split_cap_men"))
	for code: String in roster:
		var r: Dictionary = roster[code]
		if String(r["is_naval"]) == "1" or String(r["parent_code"]) == "":
			continue
		var armed := 0
		for arm: String in repo.world_table("military", "unit_types"):
			if int(float(r.get(arm, 0))) > 0:
				armed += 1
		assert_eq(armed, 1, code)
		assert_lte(int(MapObjects.regiment_size(repo, r)), cap, code)


func test_the_count_is_the_packs_own() -> void:
	var cap := int(repo.bal("army_split_cap_men"))
	var want := 0
	var gunned: Dictionary = {}
	for r: Dictionary in _pack_rows():
		if String(r["is_naval"]) == "1":
			want += 1
			continue
		for arm: String in _arms():
			want += ArmySplit.shares(int(float(r.get(arm, 0))), cap).size()
		if int(float(r.get("artillery", 0))) > 0:
			gunned[String(r["kingdom_code"])] = true
	assert_eq(roster.size(), want + gunned.size())


func test_men_are_conserved_per_arm_and_kingdom() -> void:
	var before: Dictionary = {}
	var after: Dictionary = {}
	for r: Dictionary in _pack_rows():
		for arm: String in repo.world_table("military", "unit_types"):
			var k := "%s|%s" % [r["kingdom_code"], arm]
			before[k] = int(before.get(k, 0)) + int(float(r.get(arm, 0)))
	for code: String in roster:
		var r: Dictionary = roster[code]
		for arm: String in repo.world_table("military", "unit_types"):
			var k := "%s|%s" % [r["kingdom_code"], arm]
			after[k] = int(after.get(k, 0)) + int(float(r.get(arm, 0)))
	for k: String in before:
		assert_eq(int(after.get(k, 0)), int(before[k]), k)


func test_codes_and_labels() -> void:
	for r: Dictionary in _pack_rows():
		if String(r["is_naval"]) == "1":
			assert_true(roster.has(String(r["regiment_code"])), "a fleet keeps its code")
			continue
		var armed: Array = _arms().filter(func(a: String) -> bool: return int(float(r.get(a, 0))) > 0)
		for row: Dictionary in repo.army_split:
			if bool(row["pooled"]) or not armed.has(String(row["arm"])):
				continue
			var n := ArmySplit.shares(int(float(r[String(row["arm"])])), int(repo.bal("army_split_cap_men"))).size()
			var base := "%s_%s" % [r["regiment_code"], row["code_word"]]
			var code := base if n == 1 else base + "_1"
			assert_true(roster.has(code), code)
			var label := String(roster[code]["label"])
			if armed.size() == 1:
				assert_true(label.begins_with(String(r["label"])), "a one-arm regiment keeps its label: " + label)
			else:
				assert_true(label.contains(String(row["label_word"])), label)
			if n > 1:
				assert_true(label.ends_with(" I"), label)
				assert_true(String(roster[base + "_2"]["label"]).ends_with(" II"))


func test_one_royal_train_a_gunned_kingdom_at_its_capital() -> void:
	var guns: Dictionary = {}
	for r: Dictionary in _pack_rows():
		guns[String(r["kingdom_code"])] = int(guns.get(String(r["kingdom_code"]), 0)) + int(float(r.get("artillery", 0)))
	var word := ""
	for row: Dictionary in repo.army_split:
		if bool(row["pooled"]):
			word = String(row["code_word"])
	for k: String in guns:
		var code := "%s_%s" % [k, word]
		if int(guns[k]) == 0:
			assert_false(roster.has(code))
			continue
		var t: Dictionary = roster[code]
		assert_eq(int(t["artillery"]), int(guns[k]))
		assert_eq(String(t["parent_code"]), "")
		assert_eq(String(t["camp_town"]), String(repo.kingdoms[k]["capital_burg"]))


func test_one_royal_household_a_kingdom_from_the_regiment_nearest_the_capital() -> void:
	var realm := repo.resolve_realm("player_realm")
	var royals: Array = roster.values().filter(func(r: Dictionary) -> bool:
		return String(r["kingdom_code"]) == realm and String(r["is_royal"]) == "1")
	assert_eq(royals.size(), 1)
	var cap: Dictionary = repo.burgs[String(repo.kingdoms[realm]["capital_burg"])]
	var seat := Vector2(float(cap["x"]), float(cap["y"]))
	var nearest := ""
	var best := INF
	for r: Dictionary in _pack_rows():
		if String(r["kingdom_code"]) != realm or String(r["is_naval"]) == "1":
			continue
		var d := seat.distance_to(Vector2(float(r["x"]), float(r["y"])))
		if d < best:
			best = d
			nearest = String(r["regiment_code"])
	assert_eq(String(royals[0]["parent_code"]), nearest)
	if int(float(repo.world_table("military", "regiments")[nearest].get("cavalry", 0))) > 0:
		assert_gt(int(royals[0]["cavalry"]), 0, "the household is horse when the regiment has any")


func test_no_two_standing_units_share_ground() -> void:
	var half := float(int(repo.bal("army_slot_spacing_m"))) / 2.0
	var pts: Array = []
	for code: String in roster:
		var r: Dictionary = roster[code]
		if String(r["is_naval"]) == "1":
			continue
		pts.append(ArmySystem.pack_to_metres(repo, Vector2(float(r["x"]), float(r["y"]))))
	for i in pts.size():
		for j in range(i + 1, pts.size()):
			assert_gte(Vector2(pts[i] - pts[j]).length(), half - 2.0,
				"units %d and %d overlap" % [i, j])


func test_at_most_one_seat_a_town_held_by_its_holder() -> void:
	var seats: Dictionary = split["seats"]
	var seen: Dictionary = {}
	for town: String in seats:
		var code := String(seats[town])
		assert_false(seen.has(code), "one unit holds one seat")
		seen[code] = true
		var b: Dictionary = repo.burgs[town]
		assert_eq(String(roster[code]["kingdom_code"]),
			MapOwnership.owner_of(repo, null, String(b["province_code"])))
		assert_eq(ArmySystem.pack_to_metres(repo, Vector2(float(roster[code]["x"]), float(roster[code]["y"]))),
			ArmyGround.town_point_m(repo, town), "the seat stands on the town's point")


func test_the_seat_goes_to_the_most_infantry() -> void:
	var seats: Dictionary = split["seats"]
	for town: String in seats:
		var held: Dictionary = roster[String(seats[town])]
		for code: String in roster:
			var r: Dictionary = roster[code]
			if String(r["camp_town"]) == town and String(r["kingdom_code"]) == String(held["kingdom_code"]):
				assert_lte(int(r["infantry"]), int(held["infantry"]), "%s at %s" % [code, town])


func test_deterministic_and_copied() -> void:
	var again := ArmySplit.split(repo)
	assert_eq(JSON.stringify(again, "", true), JSON.stringify(split, "", true))
	(again["roster"] as Dictionary).clear()
	assert_false(ArmySplit.roster_of(repo).is_empty(), "split() hands out a copy")


func test_a_new_campaign_carries_the_roster_and_seats() -> void:
	var s := SuiteData.campaign(repo, 7)
	assert_eq(s.army_roster.size(), roster.size())
	assert_eq(s.town_seat, split["seats"])
```

Append to `tests/engine/test_save_load.gd`:

```gdscript
func test_roster_and_seats_round_trip() -> void:
	var data := SuiteData.repo()
	var s := SuiteData.campaign(data, 11)
	var path := "user://test_roster_round_trip.json"
	assert_true(SaveLoad.save_game(s, path))
	var back := SaveLoad.load_game(path)
	assert_not_null(back)
	assert_eq(SaveLoad.state_hash(back), SaveLoad.state_hash(s))
	assert_eq(back.army_roster, s.army_roster)
	assert_eq(back.town_seat, s.town_seat)


func test_a_save_from_before_the_split_is_refused() -> void:
	var data := SuiteData.repo()
	var d := SuiteData.campaign(data, 11).to_dict()
	d["version"] = GameState.MIN_SAVE_VERSION - 1
	var path := "user://test_old_save.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	assert_null(SaveLoad.load_game(path))
	assert_eq(SaveLoad.last_error, "outdated")
```

(If `test_save_load.gd` writes into a `RunDir`-style folder rather than `user://`, copy its own path pattern; see memory "user:// shared by worktrees".)

- [ ] **Step 2: Run, expect failures**

Run: `./run_tests.sh --fast`. Expect failures naming `ArmySplit`, `army_roster` and `MIN_SAVE_VERSION`.

- [ ] **Step 3: Write `scripts/engine/army_split.gd`**

```gdscript
class_name ArmySplit
extends RefCounted
## The opening army as UNITS (owner 2026-10-07, spec docs/superpowers/specs/
## 2026-10-07-army-split-and-ground-design.md §3): every pack regiment split
## into pure-arm units of at most army_split_cap_men, as even as can be; a
## kingdom's guns pooled into ONE royal train at its capital; fleets as they
## are. Every unit is placed on its own camp (ArmyGround) around its
## regiment's town (or its own point in the field) and every held town's seat
## is filled by the camp's most infantry. Pure and deterministic — the same
## pack, the same roster. GameState.new_campaign writes it into the save;
## ArmySystem.roster falls back to it where there is no campaign.

static var _cache: Dictionary = {}


## Forget the per-pack splits (DataRepository.load_map, as the town grid is).
static func forget() -> void:
	_cache.clear()


## The pack's split, made once a repository; never edited — split() copies.
## Four at most are kept: the suite makes a repository copy per test.
static func _of(repo: DataRepository) -> Dictionary:
	var key := repo.get_instance_id()
	if not _cache.has(key):
		if _cache.size() >= 4:
			_cache.erase(_cache.keys()[0])
		_cache[key] = _make(repo)
	return _cache[key]


## The roster where there is no campaign (the editor's previews, a reader
## with no state). Read-only.
static func roster_of(repo: DataRepository) -> Dictionary:
	return _of(repo)["roster"]


## The opening seats, town -> unit. Read-only.
static func seats_of(repo: DataRepository) -> Dictionary:
	return _of(repo)["seats"]


## A new campaign's own copy: {roster: code -> row, seats: town -> code}.
static func split(repo: DataRepository) -> Dictionary:
	return _of(repo).duplicate(true)


## `men` as ceil(men / cap) shares, the sizes at most one apart, the larger
## first: 1268 by 600 is [423, 423, 422]. [] for none.
@warning_ignore("integer_division")  # whole men
static func shares(men: int, cap: int) -> Array:
	if men <= 0 or cap <= 0:
		return []
	var n := (men + cap - 1) / cap
	var out: Array = []
	for i in n:
		out.append(men / n + (1 if i < men % n else 0))
	return out


static func _make(repo: DataRepository) -> Dictionary:
	var cap := int(repo.bal("army_split_cap_men"))
	var rows: Array = repo.world_table("military", "regiments").values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return "%s|%s" % [a["kingdom_code"], a["regiment_code"]] < "%s|%s" % [b["kingdom_code"], b["regiment_code"]])
	var roster: Dictionary = {}
	var taken := ArmyGround.new_taken(repo)
	var guns: Dictionary = {}
	for row: Dictionary in rows:
		var code := String(row["regiment_code"])
		if String(row.get("is_naval", "0")) == "1":
			var fleet := row.duplicate()
			fleet["parent_code"] = ""
			fleet["is_royal"] = "0"
			fleet["camp_town"] = ""
			roster[code] = fleet
			continue
		var k := String(row["kingdom_code"])
		guns[k] = int(guns.get(k, 0)) + int(float(row.get("artillery", 0)))
		var at := Vector2(float(row["x"]), float(row["y"]))
		var town := _held(repo, ArmySystem.town_at(repo, at), k)
		var centre := ArmyGround.town_point_m(repo, town) if town != "" else ArmySystem.pack_to_metres(repo, at)
		var armed := 0
		for arm_row: Dictionary in repo.army_split:
			if not bool(arm_row["pooled"]) and int(float(row.get(String(arm_row["arm"]), 0))) > 0:
				armed += 1
		for arm_row: Dictionary in repo.army_split:
			if bool(arm_row["pooled"]):
				continue
			var arm := String(arm_row["arm"])
			var parts := shares(int(float(row.get(arm, 0))), cap)
			for i in parts.size():
				var unit := _unit(repo, row, arm_row, i, parts.size(), int(parts[i]), armed == 1)
				unit["camp_town"] = town
				_place(repo, unit, centre, arm, taken, town != "")
				roster[String(unit["regiment_code"])] = unit
	var ks := guns.keys()
	ks.sort()
	for k: String in ks:
		if int(guns[k]) > 0:
			var train := _train(repo, k, int(guns[k]))
			if not train.is_empty():
				var t_town := String(train["camp_town"])
				_place(repo, train, ArmyGround.town_point_m(repo, t_town), String(train["_arm"]), taken, true)
				train.erase("_arm")
				roster[String(train["regiment_code"])] = train
	_crown(repo, rows, roster)
	return {"roster": roster, "seats": _seat(repo, roster)}


## `town` when kingdom `k` holds it at the start, else "".
static func _held(repo: DataRepository, town: String, k: String) -> String:
	if town == "":
		return ""
	var b: Dictionary = repo.burgs[town]
	return town if MapOwnership.owner_of(repo, null, String(b.get("province_code", ""))) == k else ""


## Put `unit` on the first free slot round `centre` (its centre when none is free).
static func _place(repo: DataRepository, unit: Dictionary, centre: Vector2i, arm: String,
		taken: Dictionary, town: bool) -> void:
	var slot := ArmyGround.free_slot(repo, centre, arm, taken, town)
	if slot == ArmyGround.NONE:
		slot = centre
	ArmyGround.take(taken, slot)
	_put(repo, unit, slot)


static func _put(repo: DataRepository, unit: Dictionary, p_m: Vector2i) -> void:
	var px := ArmySystem.metres_to_pack(repo, p_m)
	unit["x"] = "%.3f" % px.x
	unit["y"] = "%.3f" % px.y


static func _unit(repo: DataRepository, parent: Dictionary, arm_row: Dictionary, i: int, n: int,
		men: int, one_arm: bool) -> Dictionary:
	var out := parent.duplicate()
	for arm: String in repo.world_table("military", "unit_types"):
		out[arm] = "0"
	out[String(arm_row["arm"])] = str(men)
	var code := "%s_%s" % [parent["regiment_code"], arm_row["code_word"]]
	if n > 1:
		code += "_%d" % (i + 1)
	out["regiment_code"] = code
	var label := String(parent["label"])
	if not one_arm:
		label = "%s %s" % [label.trim_suffix(" Regiment"), arm_row["label_word"]]
	if n > 1:
		label += " " + roman(i + 1)
	out["label"] = label
	out["parent_code"] = String(parent["regiment_code"])
	out["is_royal"] = "0"
	return out


## A kingdom's royal train: every gun it has, quartered on its capital. {} for
## a kingdom with no capital. `_arm` (the pooled arm) is the caller's to drop.
static func _train(repo: DataRepository, k: String, men: int) -> Dictionary:
	var cap_code := String((repo.kingdoms.get(k, {}) as Dictionary).get("capital_burg", ""))
	if not repo.burgs.has(cap_code):
		return {}
	var pooled: Dictionary = {}
	for row: Dictionary in repo.army_split:
		if bool(row["pooled"]):
			pooled = row
	var out: Dictionary = {"regiment_code": "%s_%s" % [k, pooled["code_word"]], "kingdom_code": k,
		"province_code": String(repo.burgs[cap_code].get("province_code", "")),
		"label": String(pooled["label_word"]).replace("{kingdom}", String(repo.kingdoms[k].get("label", k))),
		"is_naval": "0", "parent_code": "", "is_royal": "0", "camp_town": cap_code, "_arm": String(pooled["arm"])}
	for arm: String in repo.world_table("military", "unit_types"):
		out[arm] = "0"
	out[String(pooled["arm"])] = str(men)
	return out


## The royal household (§3.1 step 5): in each kingdom, the land regiment
## nearest its capital (ties to the earlier code) gives its largest horse
## unit — else its largest foot, else its largest unit — the crown.
static func _crown(repo: DataRepository, rows: Array, roster: Dictionary) -> void:
	var codes := roster.keys()
	codes.sort()
	var ks: Dictionary = {}
	for row: Dictionary in rows:
		ks[String(row["kingdom_code"])] = true
	var sorted_ks := ks.keys()
	sorted_ks.sort()
	for k: String in sorted_ks:
		var cap: Dictionary = repo.burgs.get(String((repo.kingdoms.get(k, {}) as Dictionary).get("capital_burg", "")), {})
		if cap.is_empty():
			continue
		var seat := Vector2(float(cap["x"]), float(cap["y"]))
		var nearest := ""
		var best := INF
		for row: Dictionary in rows:
			if String(row["kingdom_code"]) != k or String(row.get("is_naval", "0")) == "1":
				continue
			var d := seat.distance_to(Vector2(float(row["x"]), float(row["y"])))
			if d < best:
				best = d
				nearest = String(row["regiment_code"])
		if nearest == "":
			continue
		var pick := ""
		for arm: String in ["cavalry", "infantry", ""]:
			var most := 0
			for c: String in codes:
				var r: Dictionary = roster[c]
				if String(r["parent_code"]) != nearest:
					continue
				var men := int(MapObjects.regiment_size(repo, r)) if arm == "" else int(float(r.get(arm, 0)))
				if men > most:
					most = men
					pick = c
			if pick != "":
				break
		if pick != "":
			roster[pick]["is_royal"] = "1"


## Every held town's seat (§4.4): among the holder's land units camped
## around it, the most infantry (ties to the earlier code), else the largest;
## that unit steps onto the town's point.
static func _seat(repo: DataRepository, roster: Dictionary) -> Dictionary:
	var by_town: Dictionary = {}
	var codes := roster.keys()
	codes.sort()
	for c: String in codes:
		var town := String(roster[c].get("camp_town", ""))
		if town != "":
			if not by_town.has(town):
				by_town[town] = []
			(by_town[town] as Array).append(c)
	var seats: Dictionary = {}
	var towns := by_town.keys()
	towns.sort()
	for town: String in towns:
		var pick := ""
		var best := 0
		for c: String in by_town[town]:
			var foot := int(float(roster[c].get("infantry", 0)))
			if foot > best:
				best = foot
				pick = c
		if pick == "":
			for c: String in by_town[town]:
				var size := int(MapObjects.regiment_size(repo, roster[c]))
				if size > best:
					best = size
					pick = c
		if pick != "":
			seats[town] = pick
			_put(repo, roster[pick], ArmyGround.town_point_m(repo, town))
	return seats


## 1 -> I, 4 -> IV, 12 -> XII.
static func roman(n: int) -> String:
	var vals := [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
	var syms := ["M", "CM", "D", "CD", "C", "XC", "L", "XL", "X", "IX", "V", "IV", "I"]
	var out := ""
	for i in vals.size():
		while n >= int(vals[i]):
			out += String(syms[i])
			n -= int(vals[i])
	return out
```

- [ ] **Step 4: State, save version, campaign start**

In `scripts/engine/game_state.gd`, beside `var regiments`:

```gdscript
## Every kingdom's army as UNITS (owner 2026-10-07, spec
## 2026-10-07-army-split-and-ground §2.1): unit code -> a row shaped as
## military/regiments.csv's, + parent_code, is_royal, camp_town. Split from
## the pack once, as the campaign starts (ArmySplit); read through
## ArmySystem.roster / regiment, never directly.
var army_roster: Dictionary = {}
## town code -> the one unit holding its seat (ArmyGround, spec §4.4).
var town_seat: Dictionary = {}
```

- Set `const SAVE_VERSION := 6`, and add below it:

  ```gdscript
  ## The oldest save this build loads (spec 2026-10-07-army-split-and-ground
  ## §2.3): a save from before the split names regiments that no longer exist.
  const MIN_SAVE_VERSION := 6
  ```

- In `to_dict()`, next to `"regiments"`, add `"army_roster": army_roster.duplicate(true), "town_seat": town_seat.duplicate(true),`.
- In `from_dict()`, next to `s.regiments = …`, add:

  ```gdscript
  s.army_roster = d.get("army_roster", {})
  s.town_seat = d.get("town_seat", {})
  ```

  The rows are strings, so they need no `_decode_values`. Leave `from_dict` permissive: only `SaveLoad` refuses.
- In `new_campaign`, before `ArmySystem.ensure(data, s)`:

```gdscript
	# The army as its units (spec 2026-10-07-army-split-and-ground §3).
	var split := ArmySplit.split(data)
	s.army_roster = split["roster"]
	s.town_seat = split["seats"]
```

In `scripts/engine/save_load.gd`:

```gdscript
## Why the last load_game returned null: "missing", "corrupt" or "outdated"
## (a save older than GameState.MIN_SAVE_VERSION); "" after a good load.
static var last_error := ""
```

Set it in `load_game`:

- `"missing"` on the open failure;
- `"corrupt"` on the parse failure;
- before `return GameState.from_dict(parsed)`:

  ```gdscript
  	if int((parsed as Dictionary).get("version", 1)) < GameState.MIN_SAVE_VERSION:
  		last_error = "outdated"
  		return null
  	last_error = ""
  ```

In `DataRepository.load_map`, beside `ArmySystem.forget_grids()`, add `ArmySplit.forget()`.

In `scripts/ui/game.gd`:

```gdscript
## Why the last load_campaign failed, in the player's words ("" after a good one).
var load_error := ""
```

In `load_campaign`, on `loaded == null`:

```gdscript
		load_error = "The army's organisation has changed since this realm was saved; begin a new reign." \
			if SaveLoad.last_error == "outdated" else "No saved realm found."
		return false
```

Set `load_error = ""` on success.

In `scripts/ui/game_root.gd`:

- `_on_menu_load` failure: `_pause_status.text = Game.load_error`;
- `_on_menu_load_from_title`: `current_screen.show_load_failed(Game.load_error)`.

In `scripts/ui/main_menu.gd`:

```gdscript
func show_load_failed(why := "No saved realm found.") -> void:
	_status.text = why
```

- [ ] **Step 5: Run the tests**

Run: `./run_tests.sh --fast`.

- `test_army_split.gd` and the two save tests pass.
- Other suites may now fail where a test saved and reloaded a hand-made dictionary with a low version through `SaveLoad.load_game`, such as `test_determinism.gd` and `test_float_precision.gd`. Make each such test write its save from a fresh campaign, which already carries version 6. Do not lower `MIN_SAVE_VERSION`.

Then run `./run_tests.sh`. Expect the error count to be the expected one.

- [ ] **Step 6: Commit**

```bash
git add -A scripts/engine/army_split.gd scripts/engine/game_state.gd scripts/engine/save_load.gd scripts/engine/data_repository.gd scripts/ui/game.gd scripts/ui/game_root.gd scripts/ui/main_menu.gd tests/
git commit -m "feat(army): split the opening army into units kept in the save (v6)

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: One way in — every reader on the roster

**Files:**
- Modify (scripts):
  - `scripts/engine/army_system.gd:12-13`
  - `scripts/engine/map_objects.gd`: lines 92, 410, 855-861, 968
  - `scripts/engine/supply_lines.gd:89`
  - `scripts/engine/spy_system.gd:140-143`
  - `scripts/engine/war_room.gd:39`
  - `scripts/engine/war_ground.gd:24`
  - `scripts/engine/ledger_resolvers.gd`: lines 472, 1012
  - `scripts/map3d/map3d_context.gd:129-131`
  - `scripts/war_room/war_intel_ink.gd:22`
  - `scripts/ui/military_panel.gd:128-129`
  - `tools/snapshot_screen.gd:1144`
  - every `ArmySystem.regiment(repo, code)` / `regiment(repo, code)` call with a `state` in scope
- Modify (tests): the ~46 files that read `world_table("military", "regiments")`, `repo.regiments` or `regiments_of(`
- Create: `tests/engine/test_roster_guard.gd`

**Interfaces:**
- Consumes: `ArmySplit.roster_of`, `GameState.army_roster`.
- Produces:
  - `ArmySystem.roster(repo, state: GameState = null) -> Dictionary`
  - `ArmySystem.regiment(repo, code: String, state: GameState = null) -> Dictionary`
  - `MapObjects.regiments_of(repo, kingdom_code: String, state: GameState = null) -> Array`, sorted by code
  - `Map3DContext.regiments()` reads the roster through `ctx.state()`.

- [ ] **Step 1: Write the guard test (fails now)**

`tests/engine/test_roster_guard.gd`:

```gdscript
extends GutTest
## The army is read through ArmySystem.roster / regiment only (spec
## 2026-10-07-army-split-and-ground §2.4): the pack's regiments table is the
## split's input, never the live army.

const ALLOWED := ["res://scripts/engine/army_split.gd", "res://scripts/engine/data_repository.gd"]
const NEEDLES := ["world_table(\"military\", \"regiments\")", "repo.regiments", "data.regiments"]


func _scan(dir: String, out: Array) -> void:
	for f: String in DirAccess.get_files_at(dir):
		var path := dir.path_join(f)
		if f.ends_with(".gd") and not path in ALLOWED:
			var text := FileAccess.get_file_as_string(path)
			for n: String in NEEDLES:
				if text.contains(n):
					out.append("%s reads %s" % [path, n])
	for d: String in DirAccess.get_directories_at(dir):
		_scan(dir.path_join(d), out)


func test_no_reader_of_the_pack_regiments() -> void:
	var out: Array = []
	_scan("res://scripts", out)
	_scan("res://tools", out)
	assert_eq(out, [], "\n".join(out))
```

- [ ] **Step 2: Run it, expect failure listing the readers**

Run: `./run_tests.sh --fast`.

- [ ] **Step 3: The one way in**

Replace `ArmySystem.regiment` at `scripts/engine/army_system.gd:11-13`:

```gdscript
## The army as it stands (spec 2026-10-07-army-split-and-ground §2.4): the
## campaign's roster, else — no state, or a state with none — the pack's split.
static func roster(repo: DataRepository, state: GameState = null) -> Dictionary:
	if state != null and not state.army_roster.is_empty():
		return state.army_roster
	return ArmySplit.roster_of(repo)

## A unit's row, {} when there is none.
static func regiment(repo: DataRepository, code: String, state: GameState = null) -> Dictionary:
	return roster(repo, state).get(code, {})
```

Replace `MapObjects.regiments_of`:

```gdscript
## Every unit of a kingdom (ArmySystem.roster), in code order.
static func regiments_of(repo: DataRepository, kingdom_code: String, state: GameState = null) -> Array:
	var out: Array = []
	var all := ArmySystem.roster(repo, state)
	var codes := all.keys()
	codes.sort()
	for c: String in codes:
		if String(all[c]["kingdom_code"]) == kingdom_code:
			out.append(all[c])
	return out
```

Replace `Map3DContext.regiments()`:

```gdscript
## The units the map draws: the player's, or every realm's in DEV MODE.
func regiments() -> Array:
	return ArmySystem.roster(repo, state()).values() if dev \
		else MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state())
```

- [ ] **Step 4: Move every other reader**

Mechanical rules:

- `repo.world_table("military", "regiments")` becomes `ArmySystem.roster(repo, state)` when a `state` is in scope, else `ArmySystem.roster(repo)`. Change the call sites in:
  - `map_objects.gd` lines 92, 410 and 968 (`army_card` has `state`);
  - `supply_lines.gd:89`;
  - `spy_system.gd:140-143`.
- `MapObjects.regiments_of(X, k)` gains `, state` wherever a state is in scope. In `scripts/ui/` that is `Game.state`, and in war-room code it is `state()` or the function's `state` parameter.
- `ArmySystem.regiment(repo, code)` gains `, state` wherever a state is in scope. Find the calls with:

  ```bash
  grep -rn 'regiment(repo, \|regiment(data, \|regiment(_repo, \|regiment(Game.data, \|regiment(ctx.repo, ' scripts tools
  ```

  Inside `army_system.gd`, the bare `regiment(repo, code)` calls count too. Do not add `state` where none is in scope.
- `ArmySystem.ensure` (`army_system.gd:56`) and `:530` already have a state, so pass it to `regiments_of`.
- `military_panel.gd:129`: `MapObjects.regiments_of(Game.data, kingdom_code, Game.state)`.
- `tools/snapshot_screen.gd:1144`: `MapObjects.regiments_of(Game.data, …, Game.state)`.
- `ArmySystem.starting_state` also seeds `"camp_town": String(reg.get("camp_town", ""))`. Task 4 reads it.

- [ ] **Step 5: Move the tests**

Run `./run_tests.sh --fast` and work through the failures with these rules:

- A test that took a regiment code from `world_table("military", "regiments")` or `regiments_of(repo, realm)` and then handed it to an engine call should take it from `MapObjects.regiments_of(repo, realm, state)` or `ArmySystem.roster(repo, state)`.
- A test that EDITED a pack row to steer a regiment's numbers should edit the row that the code under test reads:
  - `state.army_roster[code]` when it passes a state;
  - `ArmySystem.roster(repo)[code]` when it does not. That is the cached split of that repository copy.
- A test that asserted a count of the pack's regiments should assert the roster's count, derived from the pack (see `test_the_count_is_the_packs_own`).
- A test that names a code literally, such as `tests/ledger3d/test_ledger_view_galaxy.gd:794`, should derive it instead: the first unit of `MapObjects.regiments_of(repo, realm, state)`.
- A test about the old garrison counter (`garrisons`, `garrison_of`, `quartered_in`) stays as it is for now. Task 6 removes those features and their tests.

Run until `./run_tests.sh` reports the expected error count and the guard passes.

- [ ] **Step 6: Commit**

```bash
git add -A scripts tools tests
git commit -m "refactor(army): read the army through the roster, one way in

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Seats, camps and settling (`ArmyGround`, live half)

**Files:**
- Modify:
  - `scripts/engine/army_ground.gd` (append)
  - `scripts/engine/army_system.gd`: `set_march` ~837; `march_day` ~863; `works_of` ~363; `terrain_label` ~386; `settle_month` ~131; delete `quartered_in` ~354 only after Task 6 removes its map readers, so keep it here
  - `scripts/engine/supply_system.gd`: delete `garrisoned_in` ~109; edit `line_of`
  - `scripts/engine/supply_lines.gd:256-262` (`home_town`)
  - `scripts/engine/ledger_resolvers.gd`: lines ~694, ~820-835
  - `scripts/engine/war_folio.gd`: lines ~151, ~248
  - `scripts/engine/tick_engine.gd:35` (after `march_day`)
- Test: `tests/engine/test_army_ground.gd` (append), plus the tests that called `SupplySystem.garrisoned_in`

**Interfaces:**
- Consumes: Task 1, `ArmySystem.roster/regiment/position_of/metres_to_pack/pack_to_metres/town_at/order_of`, `MapOwnership.owner_of`.
- Produces:
  - `ArmyGround.seat_of(repo, state, town: String) -> String`
  - `ArmyGround.seated_in(repo, state, code: String) -> String`
  - `ArmyGround.camped_by(repo, state, code: String) -> String`
  - `ArmyGround.standing_taken(repo, state, except_code: String) -> Dictionary`
  - `ArmyGround.settle(repo, state, code: String) -> void`
  - `ArmyGround.leave(repo, state, code: String) -> void`
  - `ArmyGround.refill(repo, state, town: String) -> String`
  - `ArmyGround.take_seat(repo, state, code: String) -> bool`
  - `ArmyGround.reconcile(repo, state) -> void`

- [ ] **Step 1: Write the failing tests** (append to `tests/engine/test_army_ground.gd`)

```gdscript
func _state() -> GameState:
	return SuiteData.campaign(repo, 3)


func _realm() -> String:
	return repo.resolve_realm("player_realm")


## The player's seated unit at its capital, the capital, and the units camped there.
func _capital(s: GameState) -> Dictionary:
	var town := String(repo.kingdoms[_realm()]["capital_burg"])
	var camped: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, _realm(), s):
		var c := String(r["regiment_code"])
		if ArmyGround.camped_by(repo, s, c) == town and ArmyGround.seated_in(repo, s, c) == "":
			camped.append(c)
	return {"town": town, "seat": ArmyGround.seat_of(repo, s, town), "camped": camped}


func test_the_seat_and_the_camp_at_the_start() -> void:
	var s := _state()
	var cap := _capital(s)
	assert_ne(String(cap["seat"]), "")
	assert_eq(ArmyGround.seated_in(repo, s, String(cap["seat"])), String(cap["town"]))
	assert_eq(ArmyGround.camped_by(repo, s, String(cap["seat"])), String(cap["town"]), "the seat is camped too")
	assert_false((cap["camped"] as Array).is_empty(), "the capital has a camp round it")


func test_works_and_morale_go_to_the_seat_supply_to_the_camp() -> void:
	var s := _state()
	var cap := _capital(s)
	var seat := ArmySystem.regiment(repo, String(cap["seat"]), s)
	var camper := ArmySystem.regiment(repo, String((cap["camped"] as Array)[0]), s)
	assert_ne(ArmySystem.works_of(repo, seat, s), "")
	assert_eq(ArmySystem.works_of(repo, camper, s), "", "a camp fights on the field's terrain")
	assert_eq(SupplyLines.home_town(repo, s, String(camper["regiment_code"])), String(cap["town"]))


func test_marching_out_empties_the_seat_and_the_camp_refills_it() -> void:
	var s := _state()
	var cap := _capital(s)
	var old := String(cap["seat"])
	var here := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, old, s))
	ArmySystem.set_march(repo, s, old, here + Vector2(5.0, 0.0))
	var now := ArmyGround.seat_of(repo, s, String(cap["town"]))
	assert_ne(now, old)
	assert_ne(now, "", "a camped unit steps in the same day")
	assert_eq(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, now, s)),
		ArmySystem.metres_to_pack(repo, ArmyGround.town_point_m(repo, String(cap["town"]))))
	assert_eq(ArmyGround.camped_by(repo, s, old), "", "on the march it camps nowhere")


## March `code` to pack point `to` and run days until it arrives.
func _arrive(s: GameState, code: String, to: Vector2) -> void:
	ArmySystem.set_march(repo, s, code, to)
	for i in 400:
		if code in ArmySystem.march_day(repo, s):
			return
	fail_test("never arrived")


func test_first_come_first_in() -> void:
	var s := _state()
	var cap := _capital(s)
	var town := String(cap["town"])
	var a := String(cap["seat"])
	var b := String((cap["camped"] as Array)[0])
	# nobody left in the camp to refill the seat: it stays empty when `a` leaves
	for c: String in cap["camped"]:
		s.regiments[c]["camp_town"] = ""
	var away := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, a, s)) + Vector2(40.0, 0.0)
	_arrive(s, a, away)
	assert_eq(ArmyGround.seat_of(repo, s, town), "")
	var tp := ArmySystem.metres_to_pack(repo, ArmyGround.town_point_m(repo, town))
	_arrive(s, a, tp)
	assert_eq(ArmyGround.seat_of(repo, s, town), a, "the first to arrive takes the empty seat")
	_arrive(s, b, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, b, s)) + Vector2(40.0, 0.0))
	_arrive(s, b, tp)
	assert_eq(ArmyGround.seat_of(repo, s, town), a)
	assert_eq(ArmyGround.camped_by(repo, s, b), town, "the later one camps round the town")
	assert_ne(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, b, s)), tp)


func test_a_foreign_town_is_the_field() -> void:
	var s := _state()
	var code := String(_capital(s)["seat"])
	var foreign := ""
	var codes := repo.burgs.keys()
	codes.sort()
	for t: String in codes:
		if MapOwnership.owner_of(repo, s, String(repo.burgs[t]["province_code"])) != _realm():
			foreign = t
			break
	var tp := ArmySystem.metres_to_pack(repo, ArmyGround.town_point_m(repo, foreign))
	_arrive(s, code, tp)
	assert_eq(ArmyGround.seated_in(repo, s, code), "")
	assert_eq(ArmyGround.camped_by(repo, s, code), "")
	assert_false(s.town_seat.has(foreign) and String(s.town_seat[foreign]) == code)


func test_a_unit_with_no_free_slot_stands_where_it_arrived() -> void:
	var s := _state()
	var code := String(_capital(s)["seat"])
	var dest := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code, s)) + Vector2(60.0, 0.0)
	var saved := repo.balance["army_slot_max_rings"]
	repo.balance["army_slot_max_rings"] = 0.0
	# the field centre is taken by a stand-in: the only slot left is none
	_arrive(s, code, dest)
	var at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code, s))
	repo.balance["army_slot_max_rings"] = saved
	assert_eq(at.distance_to(dest) < 2.0, true, "it holds the ground it reached")


func test_a_lost_town_loses_its_seat() -> void:
	var s := _state()
	var cap := _capital(s)
	var town := String(cap["town"])
	var foe := ""
	for k: String in repo.kingdoms:
		if k != _realm():
			foe = k
			break
	MapOwnership.set_owner(repo, s, String(repo.burgs[town]["province_code"]), foe, "test: the town falls")
	ArmyGround.reconcile(repo, s)
	assert_false(s.town_seat.has(town))
```

`test_a_unit_with_no_free_slot_stands_where_it_arrived` sets `army_slot_max_rings` to 0. A field arrival then gets the centre only when it is free. If the centre lands on water and the unit has no slot, it must still keep its arrival point, and that is the assertion. If `MapOwnership.set_owner` has a different signature, match it (`scripts/engine/map_ownership.gd`).

- [ ] **Step 2: Run, expect failures**

Run: `./run_tests.sh --fast`.

- [ ] **Step 3: Append the live half to `scripts/engine/army_ground.gd`**

```gdscript
## --- Seats and camps (spec §4.1, §4.3–4.4) -----------------------------

## The seats in play: the campaign's, else the pack's opening ones.
static func _seats(repo: DataRepository, state: GameState) -> Dictionary:
	return state.town_seat if state != null else ArmySplit.seats_of(repo)


## Whether kingdom `k` holds `town` now (its province's owner).
static func holds(repo: DataRepository, state: GameState, k: String, town: String) -> bool:
	var b: Dictionary = repo.burgs.get(town, {})
	return not b.is_empty() and MapOwnership.owner_of(repo, state, String(b.get("province_code", ""))) == k


## The unit holding `town`'s seat, "" for an empty one.
static func seat_of(repo: DataRepository, state: GameState, town: String) -> String:
	return String(_seats(repo, state).get(town, ""))


## The town whose seat `code` holds — one its own kingdom holds — else "".
## What earns the works and the garrison's morale.
static func seated_in(repo: DataRepository, state: GameState, code: String) -> String:
	var seats := _seats(repo, state)
	var towns := seats.keys()
	towns.sort()
	for town: String in towns:
		if String(seats[town]) == code:
			var reg := ArmySystem.regiment(repo, code, state)
			return town if not reg.is_empty() and holds(repo, state, String(reg["kingdom_code"]), town) else ""
	return ""


## The held town a STANDING land unit settled around (R3: the town it camped
## by, `camp_town`), the seat's own town included; "" on the march, in the
## field, afloat, or round a town its kingdom no longer holds. What feeds it.
static func camped_by(repo: DataRepository, state: GameState, code: String) -> String:
	var reg := ArmySystem.regiment(repo, code, state)
	if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
		return ""
	var town := String(reg.get("camp_town", ""))
	if state != null and state.regiments.has(code):
		var entry: Dictionary = state.regiments[code]
		if String(entry.get("order", "")) == ArmySystem.ORDER_MARCH:
			return ""
		town = String(entry.get("camp_town", ""))
	return town if town != "" and holds(repo, state, String(reg["kingdom_code"]), town) else ""


## The ground every OTHER standing land unit holds now, metres.
static func standing_taken(repo: DataRepository, state: GameState, except_code: String) -> Dictionary:
	var taken := new_taken(repo)
	var all := ArmySystem.roster(repo, state)
	var codes := all.keys()
	codes.sort()
	for c: String in codes:
		var r: Dictionary = all[c]
		if c == except_code or String(r.get("is_naval", "0")) == "1":
			continue
		if state != null and ArmySystem.order_of(repo, state, c) == ArmySystem.ORDER_MARCH:
			continue
		take(taken, ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, r)))
	return taken


static func _put(entry: Dictionary, p_m: Vector2i) -> void:
	entry["x_m"] = p_m.x
	entry["y_m"] = p_m.y
	entry["dest_x_m"] = p_m.x
	entry["dest_y_m"] = p_m.y


## A unit has ARRIVED (ArmySystem.march_day): it takes an empty seat of a
## held town it was sent into, else the first free slot round the town, or
## round the point it reached in the field; with none free it holds the
## point it reached (§4.3). Its camp_town is the town, "" in the field.
static func settle(repo: DataRepository, state: GameState, code: String) -> void:
	var entry: Dictionary = state.regiments.get(code, {})
	var reg := ArmySystem.regiment(repo, code, state)
	if entry.is_empty() or reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
		return
	var here := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	var town := ArmySystem.town_at(repo, ArmySystem.metres_to_pack(repo, here))
	if town != "" and not holds(repo, state, String(reg["kingdom_code"]), town):
		town = ""
	entry["camp_town"] = town
	var centre := town_point_m(repo, town) if town != "" else here
	if town != "" and seat_of(repo, state, town) == "":
		state.town_seat[town] = code
		_put(entry, centre)
		return
	var slot := free_slot(repo, centre, MapObjects.regiment_arm(repo, reg),
		standing_taken(repo, state, code), town != "")
	if slot != NONE:
		_put(entry, slot)


## A unit's march order has taken effect (ArmySystem.set_march): it leaves
## its camp and, holding a seat, empties it — refilled the same day from the
## camp (§4.4).
static func leave(repo: DataRepository, state: GameState, code: String) -> void:
	if state.regiments.has(code):
		state.regiments[code]["camp_town"] = ""
	var towns := state.town_seat.keys()
	towns.sort()
	for town: String in towns:
		if String(state.town_seat[town]) == code:
			state.town_seat.erase(town)
			refill(repo, state, town)


## Fill `town`'s empty seat from the units camped round it that are not on
## the march: the most infantry (ties to the earlier code), else the largest.
## The one chosen steps onto the town's point. Returns it, "" for none.
static func refill(repo: DataRepository, state: GameState, town: String) -> String:
	if seat_of(repo, state, town) != "":
		return seat_of(repo, state, town)
	var pick := ""
	var best := 0
	for pass_foot in [true, false]:
		for r: Dictionary in ArmySystem.roster(repo, state).values():
			var c := String(r["regiment_code"])
			if camped_by(repo, state, c) != town:
				continue
			var n := int(float(r.get("infantry", 0))) if pass_foot else int(MapObjects.regiment_size(repo, r))
			if n > best or (n == best and n > 0 and c < pick):
				best = n
				pick = c
		if pick != "":
			break
	if pick == "":
		return ""
	state.town_seat[town] = pick
	if state.regiments.has(pick):
		_put(state.regiments[pick], town_point_m(repo, town))
	return pick


## ARMY_SEAT delivered (§4.5): `code`, camped by a held town, takes its
## seat; the unit that held it takes the newcomer's camp. False when `code`
## no longer camps by a town — the order lapses.
static func take_seat(repo: DataRepository, state: GameState, code: String) -> bool:
	var town := camped_by(repo, state, code)
	if town == "" or not state.regiments.has(code):
		return false
	var held := seat_of(repo, state, town)
	if held == code:
		return true
	var entry: Dictionary = state.regiments[code]
	var mine := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	state.town_seat[town] = code
	_put(entry, town_point_m(repo, town))
	if held != "" and state.regiments.has(held):
		_put(state.regiments[held], mine)
		state.regiments[held]["camp_town"] = town
	return true


## A seat whose town its holder's kingdom no longer holds is cleared (a day,
## after the march; spec §4.4).
static func reconcile(repo: DataRepository, state: GameState) -> void:
	var towns := state.town_seat.keys()
	towns.sort()
	for town: String in towns:
		var reg := ArmySystem.regiment(repo, String(state.town_seat[town]), state)
		if reg.is_empty() or not holds(repo, state, String(reg["kingdom_code"]), town):
			state.town_seat.erase(town)
```

- [ ] **Step 4: Wire it in**

`army_system.gd`:

- In `set_march`, after `entry["order"] = ORDER_MARCH`, add `ArmyGround.leave(repo, state, code)`.
- In `march_day`, inside `if _march_one(...)`, add `ArmyGround.settle(repo, state, code)` before `arrived.append(code)`.
- `works_of`:

  ```gdscript
  static func works_of(repo: DataRepository, reg: Dictionary, state: GameState = null) -> String:
  	var town := ArmyGround.seated_in(repo, state, String(reg.get("regiment_code", "")))
  	if town == "":
  		return ""
  	var feats := String((repo.burgs[town] as Dictionary).get("features", "")).split("|")
  	...  # the rest unchanged
  ```

- In `terrain_label`, replace the `held_town_of(repo, reg, state)` lookup with `ArmyGround.seated_in(repo, state, String(reg.get("regiment_code", "")))`.
- In `settle_month:131-132`, replace `SupplySystem.garrisoned_in(repo, state, code) != ""` with `ArmyGround.seated_in(repo, state, code) != ""`.
- Update the doc comments that name "garrisoned_in" or "a GARRISON order" to say "the seat".

`supply_lines.gd`:

```gdscript
## The realm town a land unit camps by (ArmyGround.camped_by), which tops it
## up each day; "" on the march, in the field or afloat.
static func home_town(repo: DataRepository, state: GameState, code: String) -> String:
	var held := ArmyGround.camped_by(repo, state, code)
	return held if held != "" and TownStores.is_realm_town(repo, state, held) else ""
```

`supply_system.gd`:

- Delete `garrisoned_in` and its comment.
- In `line_of`, replace `var held := garrisoned_in(repo, state, code)` with `var held := ArmyGround.seated_in(repo, state, code)`.

`ledger_resolvers.gd`:

- At ~694, replace `ArmySystem.held_town_of(repo, ArmySystem.regiment(repo, code, state), state)` with `ArmyGround.camped_by(repo, state, code)`.
- At ~827, use `ArmyGround.seated_in(repo, state, String(c))`.
- Update the `_garrisons` comment to "the unit holding a town's seat".

`war_folio.gd`:

- At :151, use `ArmyGround.seated_in(repo, state, code) != ""`.
- At :248, replace `SupplySystem.garrisoned_in(repo, state, code) == ""` with `ArmyGround.camped_by(repo, state, code) == ""`, so a camp by a town is not "in the open".

`tick_engine.gd`: after `day_arrivals = ArmySystem.march_day(data, state)`, add `ArmyGround.reconcile(data, state)`.

Fix the tests that called `SupplySystem.garrisoned_in`, using `grep -rn garrisoned_in tests`:

- use `ArmyGround.seated_in` where the test means the walls or morale;
- use `ArmyGround.camped_by` where it means the supply.

- [ ] **Step 5: Run the tests**

Run: `./run_tests.sh --fast`, then `./run_tests.sh`. Expect the expected error count.

- [ ] **Step 6: Commit**

```bash
git add -A scripts tests
git commit -m "feat(army): one unit holds a town's seat, the rest camp round it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The seat order `ARMY_SEAT`

**Files:**
- Modify:
  - `data/action_signatures.csv`, `data/order_costs.csv`, `data/policy_actions_court_additions.csv`, `data/army_route_orders.csv`
  - `scripts/engine/action_system.gd`: line 80, `_validate_army` ~186, execute ~600
  - `scripts/engine/courier_system.gd`: `_deliver` ~491, the event wording ~571, `pending_for` ~532
  - `scripts/ui/army_order_menu.gd`: `_open_for` ~91, `_on_chosen` ~248, the `_run` courier news ~400
- Create: `tests/engine/test_army_seat.gd`

**Interfaces:**
- Consumes:
  - `ArmyGround.take_seat`, `camped_by`, `seated_in`, `seat_of`
  - `CourierSystem.carries_orders`, `_send_courier` (ActionSystem)
- Produces:
  - action code `ARMY_SEAT` with params `{regiment}`
  - courier event type `"lapsed"`
  - menu ids `SEAT` (a new const in `ArmyOrderMenu`)

- [ ] **Step 1: Data rows**

```csv
# data/action_signatures.csv
ARMY_SEAT,,3,3,0,0,0,the watch is changed at the gate
# data/order_costs.csv
ARMY_SEAT,gold:-1:the change of the watch,1,"spec 2026-10-07-army-split-and-ground §4.5"
# data/policy_actions_court_additions.csv
ARMY_SEAT,military,Put a unit into its town's seat,none,0.5,none,0,0,,army_seat,12,yes,no,"params: regiment (a land unit of the player's realm camped by a town of the realm). Rides by courier from the capital; when it arrives the unit takes the town's seat and the unit that held it takes its camp (spec 2026-10-07-army-split-and-ground §4.5)."
# data/army_route_orders.csv
seat,Take the seat,"Send a courier: this unit enters the town, the one inside takes its camp","owner 2026-10-07 (spec 2026-10-07-army-split-and-ground §4.5): 入城换防"
seat_empty,Garrison the town,"Send a courier: this unit enters the empty town","owner 2026-10-07: 入城驻守"
```

(Copy the column order of each file's header exactly; the lines above follow them.)

- [ ] **Step 2: Write the failing tests**

`tests/engine/test_army_seat.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## ARMY_SEAT (spec 2026-10-07-army-split-and-ground §4.5).

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func _setup() -> Dictionary:
	var s := SuiteData.campaign(repo, 5)
	s.metrics["treasury"] = 10000.0
	var town := String(repo.kingdoms[repo.resolve_realm("player_realm")]["capital_burg"])
	var camper := ""
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), s):
		var c := String(r["regiment_code"])
		if ArmyGround.camped_by(repo, s, c) == town and ArmyGround.seated_in(repo, s, c) == "":
			camper = c
			break
	return {"s": s, "town": town, "camper": camper, "seat": ArmyGround.seat_of(repo, s, town)}


## Ride every courier home: days until none is left on the road.
func _ride_all(s: GameState) -> void:
	for i in 200:
		if s.couriers.is_empty():
			return
		CourierSystem.ride_day(repo, s)


func test_a_camped_unit_may_take_the_seat() -> void:
	var x := _setup()
	var actions := ActionSystem.new(repo)
	assert_eq(actions.validate(ActionRequest.make("ARMY_SEAT", {"regiment": x["camper"]}), x["s"]), "")


func test_the_seated_unit_and_a_field_unit_are_refused() -> void:
	var x := _setup()
	var actions := ActionSystem.new(repo)
	assert_ne(actions.validate(ActionRequest.make("ARMY_SEAT", {"regiment": x["seat"]}), x["s"]), "")
	var s: GameState = x["s"]
	s.regiments[String(x["camper"])]["camp_town"] = ""
	assert_ne(actions.validate(ActionRequest.make("ARMY_SEAT", {"regiment": x["camper"]}), s), "")


func test_the_courier_swaps_the_two() -> void:
	var x := _setup()
	var s: GameState = x["s"]
	var camp_at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, String(x["camper"]), s))
	var out := ActionSystem.new(repo).execute(ActionRequest.make("ARMY_SEAT", {"regiment": x["camper"]}), s)
	assert_true(bool(out.get("ok", true)))
	_ride_all(s)
	assert_eq(ArmyGround.seat_of(repo, s, String(x["town"])), String(x["camper"]))
	assert_eq(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, String(x["seat"]), s)), camp_at)
	assert_eq(ArmyGround.camped_by(repo, s, String(x["seat"])), String(x["town"]))


func test_seat_order_on_an_empty_seat_takes_it() -> void:
	var x := _setup()
	var s: GameState = x["s"]
	ActionSystem.new(repo).execute(ActionRequest.make("ARMY_SEAT", {"regiment": x["camper"]}), s)
	s.town_seat.erase(String(x["town"]))
	_ride_all(s)
	assert_eq(ArmyGround.seat_of(repo, s, String(x["town"])), String(x["camper"]))


func test_it_lapses_when_the_unit_has_left() -> void:
	var x := _setup()
	var s: GameState = x["s"]
	ActionSystem.new(repo).execute(ActionRequest.make("ARMY_SEAT", {"regiment": x["camper"]}), s)
	s.regiments[String(x["camper"])]["camp_town"] = ""
	var events: Array = []
	for i in 200:
		if s.couriers.is_empty():
			break
		events.append_array(CourierSystem.ride_day(repo, s))
	assert_true(events.any(func(e: Dictionary) -> bool: return String(e["type"]) == "lapsed"))
	assert_eq(ArmyGround.seat_of(repo, s, String(x["town"])), String(x["seat"]))
```

Match how existing tests construct and run actions. See `tests/engine/test_army_march.gd` for the `ActionSystem` construction (its `new()` argument and `execute` / `validate` names) and how it advances couriers. Use exactly those names: the code above assumes `ActionSystem.new(repo)`, `validate(req, state) -> String`, `execute(req, state) -> Dictionary`, and `CourierSystem.ride_day(repo, state) -> Array`.

- [ ] **Step 3: Run, expect failures**

Run: `./run_tests.sh --fast`.

- [ ] **Step 4: Implement**

In `action_system.gd`:

- At :80, make the case `"ARMY_MARCH", "ARMY_GARRISON", "ARMY_SEAT":`.
- In `_validate_army`, after the purse check and before `if req.action_code == "ARMY_GARRISON":`:

```gdscript
	if req.action_code == "ARMY_SEAT":
		if not CourierSystem.carries_orders(reg):
			return "%s has no town to enter" % String(reg["label"])
		var town := ArmyGround.camped_by(data, state, code)
		if town == "":
			return "%s does not camp by a town of the realm" % String(reg["label"])
		if ArmyGround.seat_of(data, state, town) == code:
			return "%s already holds %s" % [String(reg["label"]), String(data.burgs[town].get("label", town))]
		return ""
```

- In execute, after the `"ARMY_GARRISON":` branch:

```gdscript
		"ARMY_SEAT":
			var code := String(req.params["regiment"])
			_send_courier(state, effects, code, {"action_code": "ARMY_SEAT"}, "with orders to take the seat")
```

In `courier_system.gd`:

- In `_deliver`'s `match`:

```gdscript
		"ARMY_SEAT":
			if not ArmyGround.take_seat(repo, state, code):
				if state.regiments.has(code):
					state.regiments[code]["order_id"] = int(c["id"])
				return _event("lapsed", c)
```

- In the wording `match`, beside `"stale"`:

```gdscript
		"lapsed":
			return "Orders for %s to take the seat lapsed: it no longer camps by the town." % label
```

- In `pending_for` (the newest MARCH / HALT courier), skip `ARMY_SEAT` exactly as it skips `SUPPLY_*`. A seat order never moves a column's arrival.

In `army_order_menu.gd`:

- Add `const SEAT := <next free id after the existing consts>`.
- In `_open_for`, after the `army_orders` loop and before `_add_supply_rows(code)`:

```gdscript
	# the seat (spec 2026-10-07-army-split-and-ground §4.5): only a unit camped
	# by a town of the realm and not inside it; the map's orders, never a draft
	if not drafting:
		var town := ArmyGround.camped_by(Game.data, Game.state, code)
		if town != "" and ArmyGround.seat_of(Game.data, Game.state, town) != code:
			var empty := ArmyGround.seat_of(Game.data, Game.state, town) == ""
			_add_row("seat_empty" if empty else "seat", SEAT, _refusal("ARMY_SEAT", code))
```

- In `_on_chosen`'s `match id`:

```gdscript
		SEAT:
			if _code != "":
				_run(ActionRequest.make("ARMY_SEAT", {"regiment": _code}))
			return
```

- In `_run`, add `"ARMY_SEAT"` to the `req.action_code in ["ARMY_MARCH", "ARMY_GARRISON"]` list.

- [ ] **Step 5: Run the tests**

Run `./run_tests.sh --fast`. Any existing test that lists every action code will flag the new row. Typical places are the LLM's action lists, `test_order_costs`, `test_action_system`, and a test asserting the policy actions count. Update each one to include `ARMY_SEAT`, following how it treats `ARMY_GARRISON`. Then run `./run_tests.sh`.

- [ ] **Step 6: Commit**

```bash
git add -A data scripts tests
git commit -m "feat(army): ARMY_SEAT — a camped unit takes its town's seat by courier

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: One piece per unit — the garrison counter goes, the crown follows `is_royal`

**Files:**
- Modify:
  - `scripts/engine/map_objects.gd`:
    - `label_of` ~92;
    - delete `garrisons` ~866, `garrison_of` ~892, `garrison_label` ~900, `royal_regiment` ~934;
    - `army_piece` ~955.
  - `scripts/engine/army_system.gd`: delete `quartered_in` ~350-360.
  - `scripts/engine/war_room.gd`: ~34-56 (`on_sheet`) and ~147.
  - `scripts/ui/army_counters.gd`: `layout` ~27-73, `draw` ~142.
  - `scripts/map3d/`:
    - `map3d_hud_armies.gd`: `_cut` ~60-118, `_draw` ~146;
    - `map3d_layer_units.gd`: ~116-118;
    - `map3d_picker.gd`: `_army_pick` ~132;
    - `map3d_selection.gd`: `click` ~34;
    - `map3d_view.gd`: signal ~28-30, `right_click` ~509-511.
  - `scripts/ui/army_order_menu.gd`:
    - `follow` ~84;
    - delete `_open_garrison`, `GARRISON_ROW`, `_garrison`, `_garrison_at`;
    - the `_on_chosen` garrison branch.
  - `scripts/war_room/war_room_view.gd`: ~16-18 signal, ~756-772, ~831-832.
  - `scripts/war_room/war_pieces.gd`: doc comment only.
  - `.claude/skills/visual-review/taste.md`: about lines 518–524.
- Tests: those that test the garrison counter, the garrison menu or `royal_regiment`:

  ```bash
  grep -rln 'garrisons(\|garrison_of\|garrison_menu\|royal_regiment\|quartered_in\|garrison_label\|"garrison"' tests
  ```

**Interfaces:**
- Consumes: the roster's `is_royal`.
- Produces:
  - `MapObjects.army_piece(repo, row)` returns `"royal"` for `is_royal == "1"`;
  - `ArmyCounters.draw(ci, repo, markers, selected: Array = [])`;
  - a marker `{…, "royal": bool}` with no `garrison` / `codes` keys.

- [ ] **Step 1: Rewrite the tests that pinned the old rule**

Change each garrison-counter test into its new form; do not just delete it:

- **Map counters:** in a campaign, every one of the player's land units has its own marker or piece, and `markers()` returns no entry with a `garrison` key.
- **War room:** `WarRoom.on_sheet` gives one entry per unit (`entry["code"]`), with no `garrison` key.
- **Royal:** `MapObjects.army_piece(repo, r) == "royal"` exactly for the roster row with `is_royal == "1"`, and `ArmyCounters.layout(…)` marks only that one `royal`.

Add to `tests/engine/test_map_objects.gd`:

```gdscript
func test_the_crown_is_the_household() -> void:
	var data := SuiteData.repo()
	var s := SuiteData.campaign(data, 1)
	var crowned: Array = []
	for r: Dictionary in MapObjects.regiments_of(data, data.resolve_realm("player_realm"), s):
		if MapObjects.army_piece(data, r) == "royal":
			crowned.append(String(r["regiment_code"]))
	assert_eq(crowned.size(), 1)
	assert_eq(String(ArmySystem.regiment(data, String(crowned[0]), s)["is_royal"]), "1")
```

- [ ] **Step 2: Run, expect failures**

Run: `./run_tests.sh --fast`.

- [ ] **Step 3: Remove the garrison path, crown by `is_royal`**

`MapObjects.army_piece`:

```gdscript
static func army_piece(repo: DataRepository, regiment: Dictionary) -> String:
	if String(regiment.get("is_naval", "0")) == "1":
		return "fleet"
	if String(regiment.get("is_royal", "0")) == "1":
		return "royal"
	return regiment_arm(repo, regiment)
```

Delete `garrisons`, `garrison_of`, `garrison_label`, `royal_regiment`, `ArmySystem.quartered_in`, and `label_of`'s `"garrison"` branch. Fix every compile error the deletions surface, following these rules:

- **`ArmyCounters.layout`**
  - Drop the `royal` lookup and use `String(r.get("is_royal", "0")) == "1"`.
  - Drop the `garrison` / `codes` / `tower` handling, so `text` is always the headcount.
  - The glyph is `"waves"` if naval, `"crown"` if royal, else `"swords"`.
  - `piece`: `MapObjects.army_piece(repo, r)`.
- **`ArmyCounters.draw`**: the selected param becomes `selected: Array = []`, and the selection test is `selected.has(String(m["code"]))`.
- **`Map3DHudArmies._cut`**: delete the `quartered` / garrison block (its loop over `MapObjects.garrisons`). The `for r in regs` loop no longer skips anything.
- **`Map3DHudArmies._draw`**: `ArmyCounters.draw(self, ctx.repo, list, view.selected_armies())`. Add to `map3d_view.gd`:

  ```gdscript
  func selected_armies() -> Array: return _selection.armies if _loaded else []
  ```

  Add to `map3d_selection.gd`:

  ```gdscript
  ## The units selected together (spec §5.6); [army] after a plain click.
  var armies: Array = []
  ```

  Set `armies = [code]` in `select()`'s `"army"` branch and `armies = []` wherever `army = ""`. Task 8 builds on it.
- **`Map3DLayerUnits._place`**: the condition loses its `quartered_in` clause and its comment's second half.
- **`Map3DPicker._army_pick`**: `return {"kind": "army", "code": String(m["code"])}`.
- **`Map3DSelection.click`**: delete the `"garrison"` branch.
- **`Map3DView`**: delete `signal garrison_menu_requested` with its two-line comment, and `right_click`'s garrison branch.
- **`ArmyOrderMenu`**:
  - delete `_open_garrison`, the `GARRISON_ROW` const with its comment, and `_garrison` / `_garrison_at`;
  - delete the `garrison_menu_requested` connection in `follow`;
  - delete the first branch of `_on_chosen`.
- **`WarRoom.on_sheet`**: each unit is its own entry `{code, at, naval, sheet}`, with no garrison grouping. At ~147, the piece's codes are `[code]`.
- **`WarRoomView`**: delete `garrison_menu_requested`, `garrison_of`, and the click branch that emitted it. A click on a piece selects that piece's unit.
- **`war_pieces.gd`**: its header says a land unit is ONE piece. Remove any garrison wording.

`.claude/skills/visual-review/taste.md`: replace the 2026-10-06 rule "A garrison is its town's counter" (≈ lines 518–524) with:

```markdown
- **Every unit holds its own ground** (owner 2026-10-07, overturning 2026-10-06's garrison counter): one unit per town holds the seat, on the town's point; the rest camp outside it in hex rings, infantry innermost, then archers, then horse. Nothing is merged into a counter, and no counter or headcount chip ever covers another — they spread, they never stack into one (spec `2026-10-07-army-split-and-ground-design.md`).
```

- [ ] **Step 4: Line caps**

Run `wc -l scripts/map3d/map3d_view.gd scripts/map3d/map3d_layer_units.gd` and confirm ≤ 582 and ≤ 300.

- [ ] **Step 5: Run the tests**

Run: `./run_tests.sh`. Expect the expected error count.

- [ ] **Step 6: Commit**

```bash
git add -A scripts tests .claude/skills/visual-review/taste.md
git commit -m "feat(map): one piece per unit — the garrison counter goes, the crown follows the household

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Nothing overlaps — `Map3DDeclutter` for counters, chips and the war room

**Files:**
- Create: `scripts/map3d/map3d_declutter.gd`, `tests/map3d/test_map3d_declutter.gd`
- Modify:
  - `data/balance.csv`: add `map3d_declutter_step_px`, `map3d_declutter_max_px`, `war_spread_step_m`, `war_spread_max_m`
  - `scripts/ui/army_counters.gd`: `layout`'s placement loop, about lines 74–100
  - `scripts/map3d/map3d_hud_armies.gd`: pass the selection to `layout`
  - `scripts/war_room/war_pieces.gd`: `rebuild` and `update`, about lines 56–88

**Interfaces:**
- Consumes: Task 6's markers and `view.selected_armies()`.
- Produces:
  - `Map3DDeclutter.spiral(step: float, reach: float) -> Array` (Vector2 offsets, `ZERO` first)
  - `Map3DDeclutter.place(boxes: Array, hideable: Array, obstacles: Array, step: float, reach: float) -> Array`. Each entry is a `Vector2` offset, or `null` for a hidden box.
  - `ArmyCounters.layout(repo, points, h, obstacles, with_piece := {}, first: Array = [])`.

- [ ] **Step 1: Write the failing tests**

`tests/map3d/test_map3d_declutter.gd`:

```gdscript
extends GutTest
## Spreading boxes so none overlaps (spec 2026-10-07-army-split-and-ground §5.2).


func test_the_spiral_starts_at_home_and_grows() -> void:
	var s := Map3DDeclutter.spiral(4.0, 12.0)
	assert_eq(s[0], Vector2.ZERO)
	for i in range(1, s.size()):
		assert_gte((s[i] as Vector2).length(), (s[i - 1] as Vector2).length() - 0.001)
	assert_true(s.all(func(v: Vector2) -> bool: return maxf(absf(v.x), absf(v.y)) <= 12.0 + 0.001))


func test_no_two_placed_boxes_overlap() -> void:
	var boxes: Array = []
	for i in 12:
		boxes.append(Rect2(Vector2(100.0, 100.0) + Vector2(i, i), Vector2(20.0, 10.0)))
	var offs := Map3DDeclutter.place(boxes, boxes.map(func(_b: Rect2) -> bool: return false), [], 4.0, 400.0)
	var placed: Array = []
	for i in boxes.size():
		assert_not_null(offs[i])
		placed.append(Rect2((boxes[i] as Rect2).position + (offs[i] as Vector2), (boxes[i] as Rect2).size))
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			assert_false((placed[i] as Rect2).intersects(placed[j]), "%d and %d" % [i, j])


func test_the_first_never_moves() -> void:
	var boxes := [Rect2(0, 0, 10, 10), Rect2(2, 2, 10, 10)]
	var offs := Map3DDeclutter.place(boxes, [false, false], [], 2.0, 50.0)
	assert_eq(offs[0], Vector2.ZERO)
	assert_ne(offs[1], Vector2.ZERO)


func test_obstacles_are_kept_clear() -> void:
	var offs := Map3DDeclutter.place([Rect2(0, 0, 10, 10)], [false], [Rect2(0, 0, 10, 10)], 2.0, 50.0)
	assert_false(Rect2(Vector2.ZERO + (offs[0] as Vector2), Vector2(10, 10)).intersects(Rect2(0, 0, 10, 10)))


func test_a_hideable_box_with_no_room_hides_a_counter_never() -> void:
	var wall := [Rect2(-100, -100, 200, 200)]
	var offs := Map3DDeclutter.place([Rect2(0, 0, 10, 10), Rect2(0, 0, 10, 10)], [true, false], wall, 2.0, 20.0)
	assert_null(offs[0], "a chip hides")
	assert_not_null(offs[1], "a counter takes the clearest place it found")


func test_deterministic() -> void:
	var boxes := [Rect2(0, 0, 10, 10), Rect2(1, 0, 10, 10), Rect2(0, 1, 10, 10)]
	assert_eq(Map3DDeclutter.place(boxes, [false, false, false], [], 3.0, 60.0),
		Map3DDeclutter.place(boxes, [false, false, false], [], 3.0, 60.0))
```

- [ ] **Step 2: Run, expect failures**

Run: `./run_tests.sh --fast`, then `./run_tests.sh` for `tests/map3d`.

- [ ] **Step 3: Write `scripts/map3d/map3d_declutter.gd`**

```gdscript
class_name Map3DDeclutter
extends RefCounted
## Spread boxes so none covers another (owner 2026-10-07: 所有单位在地图上不要
## 重叠 … 数量marker也不要重叠; spec 2026-10-07-army-split-and-ground §5.2).
## Pure: boxes in any one plane (design px on the map's HUD, table metres in
## the war room), placed in the order given — the first never moves — each at
## the first offset of a fixed outward spiral that touches nothing placed and
## no obstacle. A HIDEABLE box (a headcount chip) with no clear offset within
## reach hides (null); any other (a counter) takes the least-covered offset
## it tried, so a unit is never lost from the map.

static var _spirals: Dictionary = {}


## Offsets on a grid of `step`, out to `reach` either way, nearest first
## (ties by angle from straight up, clockwise): ZERO first.
static func spiral(step: float, reach: float) -> Array:
	var key := Vector2(step, reach)
	if _spirals.has(key):
		return _spirals[key]
	var n := int(floor(reach / maxf(step, 0.001)))
	var out: Array = []
	for j in range(-n, n + 1):
		for i in range(-n, n + 1):
			out.append(Vector2(i * step, j * step))
	out.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		var la := a.length()
		var lb := b.length()
		if absf(la - lb) > 0.0001:
			return la < lb
		return fposmod(atan2(a.x, -a.y), TAU) < fposmod(atan2(b.x, -b.y), TAU))
	_spirals[key] = out
	return out


## One offset per box (Vector2), or null for a hideable box with no room.
static func place(boxes: Array, hideable: Array, obstacles: Array, step: float, reach: float) -> Array:
	var placed: Array = obstacles.duplicate()
	var out: Array = []
	var offs := spiral(step, reach)
	for i in boxes.size():
		var b: Rect2 = boxes[i]
		var best := Vector2.ZERO
		var best_hit := INF
		for off: Vector2 in offs:
			var hit := _covered(Rect2(b.position + off, b.size), placed)
			if hit < best_hit:
				best_hit = hit
				best = off
			if hit <= 0.0:
				break
		if best_hit > 0.0 and bool(hideable[i]):
			out.append(null)
			continue
		out.append(best)
		placed.append(Rect2(b.position + best, b.size))
	return out


static func _covered(r: Rect2, placed: Array) -> float:
	var area := 0.0
	for p: Rect2 in placed:
		if r.intersects(p):
			area += r.intersection(p).get_area()
	return area
```

- [ ] **Step 4: Use it**

Add to `data/balance.csv`:

```csv
map3d_declutter_step_px,4,"spec 2026-10-07-army-split-and-ground §5.2: the spiral's grid, design px, that spreads the army counters and chips"
map3d_declutter_max_px,160,"spec §5.2: how far a counter or chip may be pushed from its unit before a chip hides"
war_spread_step_m,0.004,"spec §5.4: the war room's spread of the pieces on the table, metres"
war_spread_max_m,0.12,"spec §5.4: how far a piece may be pushed on the table"
```

In `ArmyCounters.layout`:

- Add the param `first: Array = []`, the selected codes.
- Replace the sort and the downward-push loop with a priority sort and one `Map3DDeclutter.place` call.

```gdscript
	# Priority (spec §5.2): the selected, the royal household, then by men, then code.
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var sa := first.has(a["code"])
		var sb := first.has(b["code"])
		if sa != sb:
			return sa
		if bool(a["royal"]) != bool(b["royal"]):
			return bool(a["royal"])
		if float(a["size"]) != float(b["size"]):
			return float(a["size"]) > float(b["size"])
		return String(a["code"]) < String(b["code"]))
	var boxes: Array = out.map(func(m: Dictionary) -> Rect2: return m["rect"])
	var hide: Array = out.map(func(m: Dictionary) -> bool: return bool(m["solo"]))
	var offs := Map3DDeclutter.place(boxes, hide, obstacles, repo.bal("map3d_declutter_step_px"),
		repo.bal("map3d_declutter_max_px"))
	var kept: Array = []
	for i in out.size():
		if offs[i] == null:
			continue
		var m: Dictionary = out[i]
		m["rect"] = Rect2((m["rect"] as Rect2).position + (offs[i] as Vector2), (m["rect"] as Rect2).size)
		m["pos"] = (m["pos"] as Vector2) + (offs[i] as Vector2)
		kept.append(m)
	return kept
```

Keep whatever the old loop did to the marker AFTER placing it, such as recomputing a derived key from `rect`; read the old loop's tail first.

Then update the other callers of the layout and placement:

- In `Map3DHudArmies._cut`, pass `view.selected_armies()` as `first`.
- Grep for other callers of `ArmyCounters.layout`, for example the war table, and pass `[]` there.
- In `WarPieces.rebuild` and `update`, collect `on_sheet` entries first. Build each piece's table box from `_seated(p["at"], half)`:

  ```gdscript
  Rect2(Vector2(at.x, at.z) - half, half * 2.0)
  ```

  Order the boxes by the same priority: royal, then by men, then by code, with no selection here. Get the offsets from `Map3DDeclutter.place(boxes, all false, [], _repo.bal("war_spread_step_m"), _repo.bal("war_spread_max_m"))`. Each piece's `want` becomes `_seated(table→pack of (at.xz + off))`.
  - If `_view` has no table→pack inverse, add the offset to the seated point and re-seat its height with `_seat_y(Vector2(x, z), half)`.
  - Keep the code in a private `_spread(state, entries) -> Dictionary` (code → Vector3) used by both `rebuild` and `update`.
  - Add a `tests/war_room/test_war_pieces.gd` case: two units whose `at` are within a plinth apart get piece positions whose plinth squares do not overlap.

- [ ] **Step 5: Run the tests**

Run: `./run_tests.sh`. Expect the expected error count.

- [ ] **Step 6: Commit**

```bash
git add -A data/balance.csv scripts tests
git commit -m "feat(map): counters, chips and war-room pieces spread, never overlap

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Multi-select and orders to the selection

**Files:**
- Modify:
  - `scripts/map3d/map3d_selection.gd`: add `toggle_pick`, `select_box`
  - `scripts/map3d/map3d_input.gd`: `_button`, `_motion`
  - `scripts/map3d/map3d_view.gd`: `box_rect`, `toggle_at`, `select_box`; stays ≤ 582 lines
  - `scripts/map3d/map3d_hud_armies.gd`: draw the box, `@export var box_color`, `box_width_px`
  - `scripts/ui/army_order_menu.gd`: `_codes`, `_selected_with`, loops in `_on_chosen`, `_commit`, `_send_supply`, carry and seat
- Create: `tests/ui/test_army_multi_select.gd`

**Interfaces:**
- Consumes: Task 6's `Map3DSelection.armies`, `Map3DView.selected_armies()`.
- Produces:
  - `Map3DView.toggle_at(pos: Vector2) -> void`
  - `Map3DView.select_box(r: Rect2) -> void`
  - `Map3DView.box_rect: Rect2`
  - `Map3DSelection.toggle_pick(picked: Dictionary)`
  - `Map3DSelection.select_box(r: Rect2)`
  - `ArmyOrderMenu.selected_codes() -> Array` (test seam)

- [ ] **Step 1: Write the failing UI tests (real input)**

`tests/ui/test_army_multi_select.gd`. First copy the harness of an existing real-input menu test: `tests/ui/test_supply_load.gd` or the army order menu tests. Copy how it:

- starts a campaign through `Game`;
- opens the court screen with the 3D map;
- finds a unit's screen point (`view.unit_rects()` / `army_markers()`);
- sends `InputEventMouseButton` events with `shift_pressed`, through `Input.parse_input_event` or the view's `_gui_input`, the way those tests do;
- waits with `wait_process_frames`.

The cases:

```gdscript
func test_shift_click_adds_and_removes() -> void:
	# two of the player's units on screen: shift-click A, shift-click B -> [A, B];
	# shift-click A again -> [B]; a plain click on A -> [A]
	...


func test_shift_drag_box_selects_the_units_inside() -> void:
	# Shift + left press at a corner, motion beyond CLICK_SLOP, release at the
	# other corner round two units: selected_armies() is exactly those units,
	# sorted; the camera did not pan (rig target unchanged)
	...


func test_one_march_sends_a_courier_to_each() -> void:
	# select two units, right-click one, choose March…, click the ground,
	# COMMIT: Game.state.couriers has one ARMY_MARCH courier per unit, each with
	# the same dest_x_m / dest_y_m, and the treasury fell by two orders' cost
	...


func test_mixed_selection_sends_what_it_can() -> void:
	# select a land unit and a fleet (DEV MODE off: pick a fleet from the
	# roster and add it with Map3DSelection.select_box over its marker, or
	# toggle it in); Add supply point is offered (the land unit can take it);
	# after picking a town and a rate, exactly one SUPPLY_POINT_SET courier
	# rides (the land unit's) and the news bar said the fleet was refused
	...
```

Write each `...` in full, using the harness's own helpers. Keep each case's literal steps and assertions as described in its comment.

- [ ] **Step 2: Run, expect failures**

Run: `./run_tests.sh`. The `tests/ui` cases fail.

- [ ] **Step 3: Selection**

`map3d_selection.gd`:

```gdscript
## Shift-click (spec 2026-10-07-army-split-and-ground §5.6): one of the
## player's units in or out of the selection; anything else is ignored.
func toggle_pick(picked: Dictionary) -> void:
	if String(picked.get("kind", "")) != "army" or not _mine(String(picked["code"])):
		return
	var code := String(picked["code"])
	if armies.has(code):
		armies.erase(code)
	else:
		armies.append(code)
	_select_armies(armies.duplicate())


## A Shift-drag box (design px): every unit of the player's whose piece or
## counter it touches.
func select_box(r: Rect2) -> void:
	var codes: Array = []
	var rects: Dictionary = view.unit_rects()
	for code: String in rects:
		if (rects[code] as Rect2).intersects(r) and _mine(code) and not codes.has(code):
			codes.append(code)
	for m: Dictionary in view.army_markers():
		var code := String(m["code"])
		if (m["rect"] as Rect2).intersects(r) and _mine(code) and not codes.has(code):
			codes.append(code)
	codes.sort()
	_select_armies(codes)


func _mine(code: String) -> bool:
	return String(ArmySystem.regiment(ctx.repo, code, ctx.state()).get("kingdom_code", "")) \
		== ctx.repo.resolve_realm("player_realm")


func _select_armies(codes: Array) -> void:
	armies = codes
	army = String(armies[0]) if not armies.is_empty() else ""
	burg = ""
	_show_ring("")
	_set_province("")
	_refresh_hud()
	if army != "":
		object_selected.emit({"title": MapObjects.label_of(ctx.repo, {"kind": "army", "code": army}),
			"obj": {"kind": "army", "code": army}})
```

`map3d_view.gd` stays at ≤ 582 lines; these are one-liners:

```gdscript
var box_rect := Rect2():  # the Shift-drag box being drawn (spec §5.6), design px
	set(v): box_rect = v; if _loaded: _hud.refresh()
func toggle_at(pos: Vector2) -> void: if _loaded: _selection.toggle_pick(pick_at(pos))
func select_box(r: Rect2) -> void: if _loaded: _selection.select_box(r)
```

`map3d_input.gd`:

- Add `var _boxing := false`.
- In `_button`'s LEFT branch, before `if mb.pressed:` (the ordinary press):

```gdscript
		if mb.pressed and mb.shift_pressed:
			_boxing = true
			_press_pos = mb.position
			_dragging = false
			return true
		if not mb.pressed and _boxing:
			_boxing = false
			view.box_rect = Rect2()
			if _dragging:
				view.select_box(Rect2(_press_pos, Vector2.ZERO).expand(mb.position))
			else:
				view.toggle_at(mb.position)
			_dragging = false
			return true
```

- In `_motion`, inside `if mm.button_mask & MOUSE_BUTTON_MASK_LEFT:` after the `_press_on_hud` check:

```gdscript
		if _boxing:
			if not _dragging and _press_pos.distance_to(mm.position) > CLICK_SLOP:
				_dragging = true
			if _dragging:
				view.box_rect = Rect2(_press_pos, Vector2.ZERO).expand(mm.position)
			return true
```

- Update the header comment: Shift + left click toggles a unit, and Shift + left drag draws the selection box (R4).

`map3d_hud_armies.gd`:

```gdscript
## The Shift-drag selection box's line (spec §5.6); edited on the node.
@export var box_color := Color(1.0, 0.92, 0.6, 0.9)
@export var box_width_px := 1.5
```

At the end of `_draw()`:

```gdscript
	if view.box_rect.has_area():
		draw_rect(view.box_rect, box_color, false, box_width_px)
```

- [ ] **Step 4: Orders to the selection**

In `army_order_menu.gd`, add `var _codes: Array = []` beside `_code`, and the helpers:

```gdscript
## The units this menu's orders go to: the map's selection when the unit the
## menu opened over is in it (spec §5.6), else that unit alone.
func _selected_with(code: String) -> Array:
	if _map != null and _map.has_method("selected_armies"):
		var sel: Array = _map.call("selected_armies")
		if sel.has(code):
			return sel.duplicate()
	return [code]


## Test seam: the units the open menu orders.
func selected_codes() -> Array:
	return _codes


## "" when any of the units would take the order, else the first refusal.
func _refusal_any(action_code: String) -> String:
	var first := ""
	for c: String in _codes:
		var why := _refusal(action_code, c)
		if why == "":
			return ""
		if first == "":
			first = why
	return first


## Run an order for every unit in the menu's charge, each judged alone.
func _run_each(action_code: String, extra: Dictionary) -> void:
	for c: String in _codes:
		var params := extra.duplicate()
		params["regiment"] = c
		_run(ActionRequest.make(action_code, params))
```

Then:

- **`_open_for`**: after `_code = code`, add `_codes = _selected_with(code)`. The rows' refusals use `_refusal_any(String(row["action_code"]))` instead of `_refusal(..., code)`.
- **`_add_supply_rows`**: keep the row logic keyed on `code`. It is shown when the clicked unit is a land unit of the realm.
- **`_on_chosen`**:
  - CARRY → `_run_each("SUPPLY_CARRY_SET", {"days": …})`;
  - SUPPLY_WITHDRAW → `_run_each("SUPPLY_POINT_CLEAR", {})`;
  - SEAT stays `_code` only, since seats are per unit;
  - the generic last line → `_run_each(String(row["action_code"]), {})`.
- **`_commit`**: when not drafting, replace the single `_run` with `_run_each("ARMY_MARCH", {"x": to.x, "y": to.y})`.
- **`_send_supply`**: replace the single request with:

  ```gdscript
  var town := _supply_town; _end_supply_pick(); _run_each("SUPPLY_POINT_SET", {"town": town, "rate": rate})
  ```

- **`_open_route`**, the war room (`drafting`) and the seat: set `_codes = [code]`.

`_run` already publishes each refusal to the news bar, so a fleet in the selection is refused aloud while the others ride.

- [ ] **Step 5: Run the tests**

Run: `./run_tests.sh`. Also run `wc -l scripts/map3d/*.gd` and check the caps.

- [ ] **Step 6: Commit**

```bash
git add -A scripts tests
git commit -m "feat(map): Shift-click and Shift-drag select several units; one order rides to each

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Grouped lists, the bench, guidance

**Files:**
- Modify:
  - `scripts/engine/army_system.gd`: add `ordered`
  - `scripts/ui/military_panel.gd` (~79-90)
  - `scripts/engine/supply_lines.gd`: the marshal rows' sort, ~587-591
  - `scripts/engine/CLAUDE.md`, `scripts/map3d/CLAUDE.md`, `data/CLAUDE.md`
  - `docs/superpowers/specs/2026-10-07-army-split-and-ground-design.md`: the Status line, and §2.4 for R1–R5
- Test: `tests/engine/test_army_split.gd` (append)

**Interfaces:**
- Produces: `ArmySystem.ordered(repo, state, codes: Array) -> Array`.

- [ ] **Step 1: Write the failing test** (append to `tests/engine/test_army_split.gd`)

```gdscript
func test_lists_put_the_crown_first_then_group_by_regiment() -> void:
	var s := SuiteData.campaign(repo, 2)
	var codes: Array = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), s) \
		.map(func(r: Dictionary) -> String: return String(r["regiment_code"]))
	codes.reverse()
	var out := ArmySystem.ordered(repo, s, codes)
	assert_eq(out.size(), codes.size())
	assert_eq(String(ArmySystem.regiment(repo, String(out[0]), s)["is_royal"]), "1", "the household first")
	var trains: Array = out.filter(func(c: String) -> bool:
		return String(ArmySystem.regiment(repo, c, s)["parent_code"]) == "" \
			and String(ArmySystem.regiment(repo, c, s)["is_naval"]) == "0")
	if not trains.is_empty():
		assert_eq(out[1], trains[0], "then the royal train")
	# every regiment's units stand together
	var seen: Dictionary = {}
	var last := ""
	for c: String in out:
		var p := String(ArmySystem.regiment(repo, c, s)["parent_code"])
		if p != last and p != "":
			assert_false(seen.has(p), "%s's units are split up" % p)
			seen[p] = true
		last = p
```

- [ ] **Step 2: Run, expect failure**

Run: `./run_tests.sh --fast`.

- [ ] **Step 3: Implement `ordered` and use it**

```gdscript
## Units in the order the lists show them (spec 2026-10-07-army-split-and-
## ground §5.5): the royal household, the royal train, then each regiment's
## units together (by the regiment's code) in arm order, then the rest (the
## fleets) by code.
static func ordered(repo: DataRepository, state: GameState, codes: Array) -> Array:
	var arm_at: Dictionary = {}
	for i in repo.army_split.size():
		arm_at[String(repo.army_split[i]["arm"])] = i
	var key := func(c: String) -> String:
		var r := regiment(repo, c, state)
		var rank := 3
		if String(r.get("is_royal", "0")) == "1":
			rank = 0
		elif String(r.get("parent_code", "")) == "" and String(r.get("is_naval", "0")) == "0":
			rank = 1
		elif String(r.get("parent_code", "")) != "":
			rank = 2
		return "%d|%s|%02d|%s" % [rank, r.get("parent_code", ""),
			int(arm_at.get(MapObjects.regiment_arm(repo, r), 99)), c]
	var out := codes.duplicate()
	out.sort_custom(func(a: String, b: String) -> bool: return key.call(a) < key.call(b))
	return out
```

Then:

- **`military_panel.gd`**: build `reg_rows` in `ArmySystem.ordered(data, Game.state, codes)` order, using the full unit label. Drop the sort by value. The summary's count still reads `_regiments_of(mine).size()` and now says "units": change `"in %d regiments"` to `"in %d units"`.
- **`supply_lines.gd`**, the marshal's rows: replace `codes.sort()` with `codes = ArmySystem.ordered(repo, state, codes)`.

- [ ] **Step 4: The bench**

On this branch, run the 3D bench at the military layer. It needs a real window, never `--headless`:

```bash
GDAI_MCP_SERVER_PORT=3999 /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/tools/map3d/bench.tscn -- --size 3024x1964 --quality high --layer military --out /tmp/claude-501/army-split-bench.csv
```

Run the same command in a `main` worktree, or ask the controller for a main baseline. Compare median and p95 against the tier's `bench_budget_ms`.

- **Under budget:** record both numbers in the commit message.
- **Over budget:** STOP and report to the controller with both numbers. Do not invent a mitigation. Off-screen pieces already pause their animation in `Map3DUnits.show_piece`.

- [ ] **Step 5: Guidance**

**`scripts/engine/CLAUDE.md`:**
1. Replace the **Towns** bullet (line ~51) with a current-rule bullet:
   > **Units and ground** (spec `2026-10-07-army-split-and-ground-design.md`): the army is `state.army_roster` (`ArmySplit` at campaign start; read via `ArmySystem.roster` / `regiment`, never the pack table — `test_roster_guard.gd`). ONE unit per held town holds its seat (`state.town_seat`, `ArmyGround.seated_in`: works and garrison morale); the others camp round it (`camped_by`, the town they settled by: free supply); a unit settles on arrival into the hex rings (`ArmyGround.settle`, `data/army_split.csv` start rings, `army_slot_*`); `ARMY_SEAT` swaps by courier.
2. Fix the **Morale** bullet's `SupplySystem.garrisoned_in` → `ArmyGround.seated_in`.
3. Keep the file under its cap. If it is over, move the oldest detailed paragraph about towns/garrisons (the 2026-10-06 town-defence detail) into that spec's own text and leave one line pointing there.

**`scripts/map3d/CLAUDE.md`:** replace line ~71's sentences about the garrison counter with:
> Every unit is its own piece; the crown is the roster's `is_royal`; counters and chips are spread by `Map3DDeclutter` (never stacked, never merged); Shift + left click toggles a unit and Shift + left drag boxes several (`Map3DInput`, `Map3DSelection.armies`).

Keep it under its cap the same way.

**`data/CLAUDE.md`:** name `army_split.csv`, `army_camp_blocked.csv` and the new balance keys. Say that `military/regiments.csv` is the split's input, not the live army.

**The spec:**
- Status line: `**Status: BUILT 2026-10-07 on feat/army-split (not yet merged).**`
- Add a §10 "Implementation rulings" that lists R1–R7 from this plan, one line each.

- [ ] **Step 6: Run the full suite, commit**

Run: `./run_tests.sh`. Expect the expected error count.

```bash
git add -A scripts data docs tests
git commit -m "feat(army): lists grouped by regiment; guidance for units and ground

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Visual review and the slot pitch (controller, real window)

This task is the controller's. It needs real-window shots and the owner's eye.

- [ ] **Step 1:** Load the `visual-review` skill (`.claude/skills/visual-review/`) and follow its loop.
- [ ] **Step 2:** Shoot the new campaign's capital with `tools/snapshot_screen.gd --resolution 1920x1080`, never `--headless`, at three zooms:
  - the opening zoom;
  - close in, where pieces stand;
  - far out, where counters show.

  Measure a piece's footprint at the opening zoom: `Map3DUnits` `half_w_m × k`, or the screen box of `view.unit_rects()` converted back to metres.
- [ ] **Step 3:** Set `army_slot_spacing_m` in `data/balance.csv` to just over a piece's footprint, so neighbouring pieces do not touch. Re-run `./run_tests.sh`, since the split's tests read the key. Re-shoot.
- [ ] **Step 4:** Have an independent critic (a fresh subagent, per the skill) compare the shots against the taste rule written in Task 6. Then show the owner the sheet:
  - the capital's camp;
  - far-out counters;
  - chips at the middle zoom.
- [ ] **Step 5:** Commit the tuned value, with the shots' paths in the message. Then use `superpowers:finishing-a-development-branch` to land the branch: ff-only into main from the worktree, then push.
