# WAR ROOM P2-B — hazards that come and go — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the map's zones (plague, rebels, invasion, flood, avalanche, eruption, fault, tsunami, proselytism) into hazards that are STATE — seeded at a new reign, ending by their kind's months — with a monthly toll on the crown's regiments, a share of a supply line through them, a slower march, and a hatched area on the war table, the slip and the province card.

**Architecture:** The importer writes each zone's cell ids; `data/hazard_kinds.csv` gives each kind its months, visibility and effects; a pure engine module `Hazards` owns `GameState.hazards` (seed, ensure for an old save, active, cells, known, settle). `TickEngine` settles the month's toll and the endings into a news list Game hands to GameRoot; `SupplySystem` and `ArmySystem.ground_permille` read the active hazards; `WarGround`, `MapObjects.province_card` and `WarIntelInk` show what is known.

**Tech Stack:** Godot 4.7, typed GDScript, GUT.

**Spec:** `docs/superpowers/specs/2026-10-07-war-room-p2-tactical-layer-design.md` (sub-project B, §2 and §0 rulings 4–8)

## Global Constraints

- Design values in `data/*.csv` (`balance.csv` is `key,value,"notes"`); every new `war_*` key goes into `tests/engine/test_war_room_data.gd`'s key list.
- Determinism: hazards, cells and regiments visited in sorted order; whole numbers only in state (ticks, cell ids); integer per-mille arithmetic with `@warning_ignore("integer_division")`.
- `scripts/engine/` names no `scripts/ui/` class and never touches `Game`; `scripts/war_room/` never reads `Game`.
- Readable causality: every toll is reported with its reason (a news line, a named share of a supply line).
- Save = one JSON file: `GameState.to_dict` / `from_dict` carry `hazards` and `hazards_seeded`; an old save is seeded once on load.
- Known (spec ruling 6): every hazard touching the crown's realm is known; abroad only a `public` kind (disease, flood, avalanche, eruption). An unknown hazard still bites — but is never NAMED (a supply line's share reads "trouble on the road").
- Only crown regiments carry state: foreign regiments take no toll (as with every other monthly rule).
- Every visual change goes through the `visual-review` skill with real-window shots.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Work in this worktree.

**Commands.** One test file:

```bash
CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_hazards.gd -gpre_run_script=res://tests/pre_run.gd -gpost_run_script=res://tests/post_run.gd -gexit
```

Import pass after a new `class_name`: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import`. Whole suite: `./run_tests.sh`.

**Before Task 1:** `cp -Rc /Users/samuelzhang/game_design/.godot .godot`, then `./run_tests.sh` for the baseline.

## Review Focus

- **An old save without `hazards`**: seeded once on load at the save's own tick, never again (a save whose hazards all ended stays empty) — pinned in Task 2.
- **A regiment standing in two hazards** (plague inside a rebel zone): both tolls, each reported once — pinned in Task 3.
- **A wound toll on a regiment with no fit men**: no negative heads, no "loses 0" news — pinned in Task 3.
- **A hazard's end month**: active through the month before `end`, gone at `end`, its ending reported exactly once — pinned in Task 2.
- **A foreign rebel zone a crown supply line crosses**: the loss applies, the slip and folio never name it — pinned in Task 4.

---

## File Structure

| File | Responsibility |
|---|---|
| `tools/import_azgaar.gd` (modify) | write a zone's cell ids |
| `data/maps/beria/society/zones.csv` (regenerated) | the zones with their cells |
| `data/hazard_kinds.csv` (create) | months, public, effects and ink by kind |
| `scripts/engine/data_repository.gd` (modify) | load `hazard_kinds` |
| `scripts/engine/hazards.gd` (create) | the state, its index, knowledge, the monthly toll and endings |
| `scripts/engine/game_state.gd` (modify) | `hazards`, `hazards_seeded`, `hazards_rev`; seed at a new reign; save |
| `scripts/ui/game.gd`, `scripts/engine/tick_engine.gd`, `scripts/ui/game_root.gd` (modify) | ensure on load; the month's hazard news to the bar |
| `scripts/engine/supply_system.gd` (modify) | a hazard's share of a line |
| `scripts/engine/army_system.gd` (modify) | `ground_permille` reads a hazard's pace |
| `scripts/engine/war_ground.gd`, `scripts/engine/map_objects.gd` (modify) | the slip's and the province card's hazard lines |
| `scripts/war_room/war_intel_ink.gd`, `war_ink_painter.gd`, `war_room_ink.gd`, `scripts/ui/war_margin_key.gd` (modify) | hatched areas and their key |
| `scripts/war_room/CLAUDE.md`, `scripts/engine/CLAUDE.md`, `data/CLAUDE.md` (modify) | the rules as they stand |

---

### Task 1: Zone cells and hazard kinds

**Files:**
- Modify: `tools/import_azgaar.gd` (the zones block, ~line 866), `scripts/engine/data_repository.gd` (a `hazard_kinds` var and load beside `war_mark_hazards`)
- Create: `data/hazard_kinds.csv`
- Regenerate: `data/maps/beria/society/zones.csv`
- Test: `tests/engine/test_hazards.gd` (create)

**Interfaces:**
- Produces: `zones.csv`'s `cells` column = `|`-joined, de-duplicated, ascending cell ids; `repo.hazard_kinds: Dictionary` kind → `{label: String, months: int, public: bool, wounds_permille: int, morale: int, supply_loss_permille: int, pace_permille: int, ink: String}`.

- [ ] **Step 1: Write the failing tests**

Create `tests/engine/test_hazards.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Hazards as state (spec 2026-10-07-war-room-p2-tactical-layer §2).

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_every_zone_lists_its_cells() -> void:
	var rows: Dictionary = repo.world_table("society", "zones")
	assert_gt(rows.size(), 0)
	for code: String in rows:
		var ids := String(rows[code]["cells"]).split("|", false)
		assert_gt(ids.size(), 1, "%s lists cells, not a count" % code)
		var seen: Dictionary = {}
		var last := -1
		for s: String in ids:
			assert_true(s.is_valid_int(), code)
			var id := int(s)
			assert_true(repo.cells.has(id), "%s: cell %d" % [code, id])
			assert_false(seen.has(id), "%s repeats %d" % [code, id])
			assert_gt(id, last, "%s ascending" % code)
			seen[id] = true
			last = id


func test_every_zone_type_has_a_kind() -> void:
	for code: String in repo.world_table("society", "zones"):
		var kind := String(repo.world_table("society", "zones")[code]["type"])
		assert_true(repo.hazard_kinds.has(kind), "kind %s" % kind)
	for kind: String in repo.hazard_kinds:
		var k: Dictionary = repo.hazard_kinds[kind]
		assert_true(["plague", "unrest", "water", "rock", "none"].has(String(k["ink"])), kind)
		assert_gte(int(k["months"]), 0, kind)
```

- [ ] **Step 2: Run to see them fail**

Run `tests/engine/test_hazards.gd`. Expected: FAIL (cells are a count; `hazard_kinds` not a member).

- [ ] **Step 3: Implement**

`tools/import_azgaar.gd`, in the zones block, replace `str(zcells.size())` with the de-duplicated ascending ids:

```gdscript
		var ids: Array = []
		for ci in zcells:
			if not ids.has(int(ci)):
				ids.append(int(ci))
		ids.sort()
		out += _csv_line([_take_slug(zone_slugs, String(z.get("name", ""))),
			String(z.get("name", "")), String(z.get("type", "")), "|".join(ids.map(func(i: int) -> String: return str(i))),
			_num2(sx / n), _num2(sy / n), "|".join(provs), "|".join(kings)])
```

(keep the centre sums over `zcells` as they are). Then regenerate:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --script res://tools/import_azgaar.gd -- --map-id beria
git status --short data/ assets/maps/
```

Only `data/maps/beria/society/zones.csv` may change. If any other file changed, restore it (`git checkout -- <file>`) and record a ruling: the importer's other outputs are not in this task's scope.

`data/hazard_kinds.csv`:

```csv
kind,label,months,public,wounds_permille,morale,supply_loss_permille,pace_permille,ink,notes
Disease,plague,12,1,15,0,0,1000,plague,"first draft (spec 2026-10-07-war-room-p2-tactical-layer §2.2): months a seeded hazard lasts (0 never ends of itself); public 1 = known abroad; wounds_permille of a crown regiment's fit heads a month while it stands in it; morale a month; supply_loss_permille once on a supply line through it; pace_permille on a march through it; ink the war room's hatch"
Rebels,rebels,24,0,0,-3,50,1000,unrest,
Invasion,raiders,6,0,0,-2,80,1000,unrest,
Flood,flood,3,1,0,0,0,600,water,
Avalanche,avalanche,4,1,0,0,0,500,rock,
Eruption,eruption,6,1,0,0,0,700,rock,
Fault,fault line,0,1,0,0,0,1000,none,"geology: no effect, its name in the fine print"
Tsunami,old tsunami,0,1,0,0,0,1000,none,history: no effect
Proselytism,preaching,0,0,0,0,0,1000,none,"the religion system's (post-MVP): no military effect"
```

`scripts/engine/data_repository.gd` — beside `war_mark_hazards`:

```gdscript
## data/hazard_kinds.csv: zone kind -> {label, months, public, wounds_permille,
## morale, supply_loss_permille, pace_permille, ink} (spec 2026-10-07-war-room-p2 §2.2).
var hazard_kinds: Dictionary = {}
```

and beside its load:

```gdscript
	if not _load_if_present(dir + "/hazard_kinds.csv", ["kind", "label", "months", "public", "wounds_permille",
			"morale", "supply_loss_permille", "pace_permille", "ink"],
			func(r): hazard_kinds[String(r["kind"])] = {"label": String(r["label"]), "months": int(r["months"]),
				"public": String(r["public"]) == "1", "wounds_permille": int(r["wounds_permille"]),
				"morale": int(r["morale"]), "supply_loss_permille": int(r["supply_loss_permille"]),
				"pace_permille": int(r["pace_permille"]), "ink": String(r["ink"])}):
		return false
```

- [ ] **Step 4: Run the tests**

Run `tests/engine/test_hazards.gd` and `tests/engine/test_map_objects.gd` (the province card still reads the zones' provinces). Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add tools/import_azgaar.gd data/maps/beria/society/zones.csv data/hazard_kinds.csv scripts/engine/data_repository.gd tests/engine/test_hazards.gd tests/engine/test_hazards.gd.uid
git commit -m "feat(hazards): zones carry their cells; hazard kinds as data

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: `Hazards` and the state

**Files:**
- Create: `scripts/engine/hazards.gd`
- Modify: `scripts/engine/game_state.gd` (vars, `new_campaign`, `to_dict`, `from_dict`), `scripts/ui/game.gd` (`load_campaign`)
- Test: `tests/engine/test_hazards.gd`

**Interfaces:**
- Consumes: `repo.hazard_kinds`, zones' `cells` (Task 1).
- Produces: `GameState.hazards: Dictionary` id → `{kind, label, cells: Array[int], start: int, end: int (-1 never), source: String}`; `GameState.hazards_seeded: bool` (saved); `GameState.hazards_rev: int` (not saved). `Hazards`: `kind_of(repo, kind) -> Dictionary`, `seed(repo, state, start_tick)`, `ensure(repo, state)`, `add(state, id, kind, label, cells, start, end, source)`, `end_now(state, id)`, `is_active(state, id) -> bool`, `active_ids(state) -> Array`, `months_left(state, id) -> int` (-1 never), `at_cell(state, cell) -> Array`, `at_point(repo, state, at: Vector2) -> Array`, `known(repo, state, id) -> bool`, `touches_province(repo, state, id, province) -> bool`, `settle_month(repo, state) -> Array[String]` (endings, run AFTER the tick turns).

- [ ] **Step 1: Write the failing tests**

Add to `tests/engine/test_hazards.gd`:

```gdscript
func test_a_new_reign_seeds_every_zone_with_its_end() -> void:
	var state := SuiteData.campaign(repo, 42)
	assert_true(state.hazards_seeded)
	for code: String in repo.world_table("society", "zones"):
		var row: Dictionary = repo.world_table("society", "zones")[code]
		var k := Hazards.kind_of(repo, String(row["type"]))
		assert_true(state.hazards.has(code), code)
		var h: Dictionary = state.hazards[code]
		assert_eq(int(h["start"]), 0)
		assert_eq(int(h["end"]), int(k["months"]) if int(k["months"]) > 0 else -1, code)
		assert_eq(h["cells"].size(), String(row["cells"]).split("|", false).size())


func test_the_hazards_survive_the_save() -> void:
	var state := SuiteData.campaign(repo, 42)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(back.hazards, state.hazards)
	assert_true(back.hazards_seeded)


func test_an_old_save_is_seeded_once_at_its_own_tick() -> void:
	var state := SuiteData.campaign(repo, 42)
	var d := state.to_dict()
	d.erase("hazards")
	d.erase("hazards_seeded")
	var old := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_false(old.hazards_seeded)
	assert_eq(old.hazards, {})
	old.tick = 7
	Hazards.ensure(repo, old)
	assert_true(old.hazards_seeded)
	for id: String in old.hazards:
		assert_eq(int(old.hazards[id]["start"]), 7)
	# all ended and the save re-loaded: never seeded again
	for id: String in old.hazards.keys():
		old.hazards.erase(id)
	Hazards.ensure(repo, old)
	assert_eq(old.hazards, {})


func test_a_hazard_is_active_until_its_end_and_its_ending_is_news_once() -> void:
	var state := SuiteData.campaign(repo, 42)
	Hazards.add(state, "t", "Flood", "Test Flood", [repo.cells.keys()[0]], state.tick, state.tick + 2, "test")
	assert_true(Hazards.is_active(state, "t"))
	assert_eq(Hazards.months_left(state, "t"), 2)
	state.tick += 1
	assert_eq(Hazards.settle_month(repo, state).filter(func(n: String) -> bool: return n.contains("Test Flood")), [])
	state.tick += 1
	assert_false(Hazards.is_active(state, "t"))
	var news := Hazards.settle_month(repo, state).filter(func(n: String) -> bool: return n.contains("Test Flood"))
	assert_eq(news.size(), 1)
	state.tick += 1
	assert_eq(Hazards.settle_month(repo, state).filter(func(n: String) -> bool: return n.contains("Test Flood")), [])


func test_at_cell_finds_only_the_active() -> void:
	var state := SuiteData.campaign(repo, 42)
	var cell: int = repo.cells.keys()[3]
	Hazards.add(state, "a", "Flood", "A", [cell], state.tick, -1, "test")
	Hazards.add(state, "b", "Flood", "B", [cell], state.tick, state.tick, "test")   # already over
	assert_true(Hazards.at_cell(state, cell).has("a"))
	assert_false(Hazards.at_cell(state, cell).has("b"))


func test_known_abroad_only_if_public() -> void:
	var state := SuiteData.campaign(repo, 42)
	var mine := repo.resolve_realm("player_realm")
	var foreign_cell := -1
	var home_cell := -1
	var ids: Array = repo.cells.keys()
	ids.sort()
	for c: int in ids:
		var prov := MapManors.province_of(repo, c, state)
		if prov == "":
			continue
		var owner := MapOwnership.owner_of(repo, state, prov)
		if owner == mine and home_cell < 0:
			home_cell = c
		elif owner != mine and owner != "" and foreign_cell < 0:
			foreign_cell = c
	Hazards.add(state, "r_abroad", "Rebels", "Far rebels", [foreign_cell], state.tick, -1, "test")
	Hazards.add(state, "p_abroad", "Disease", "Far plague", [foreign_cell], state.tick, -1, "test")
	Hazards.add(state, "r_home", "Rebels", "Home rebels", [home_cell], state.tick, -1, "test")
	assert_false(Hazards.known(repo, state, "r_abroad"))
	assert_true(Hazards.known(repo, state, "p_abroad"))
	assert_true(Hazards.known(repo, state, "r_home"))
```

- [ ] **Step 2: Run to see them fail**

Expected: FAIL (`Hazards` not declared; `hazards_seeded` not a member).

- [ ] **Step 3: Implement**

`scripts/engine/game_state.gd` — beside `wealth_tiers`:

```gdscript
## The hazards that come and go (spec 2026-10-07-war-room-p2-tactical-layer §2,
## Hazards): id -> {kind, label, cells, start, end, source}, whole numbers;
## an ended one stays (end <= tick) as the record.
var hazards: Dictionary = {}
## True once the pack's zones were seeded (a new reign, or once for an old save).
var hazards_seeded := false
## Bumped by every change to `hazards` (Hazards' cell index); not saved.
var hazards_rev := 0
```

In `new_campaign`, before `Intel.settle_wealth_tiers(data, s)`:

```gdscript
	# The pack's zones are the reign's opening hazards (spec 2026-10-07-war-room-p2 §2.2).
	Hazards.seed(data, s, 0)
```

In `to_dict` after `"wealth_tiers"`:

```gdscript
		"hazards": _encode_values(hazards.duplicate(true)),
		"hazards_seeded": hazards_seeded,
```

In `from_dict` after the `wealth_tiers` line:

```gdscript
	# Saves from before the hazards were state carry neither key: Game.load_campaign
	# seeds them once at the save's own tick (Hazards.ensure).
	s.hazards = _decode_values(d.get("hazards", {}))
	s.hazards_seeded = bool(d.get("hazards_seeded", false))
```

`scripts/ui/game.gd` `load_campaign`, after `Intel.ensure_wealth_tiers(data, state)`:

```gdscript
	Hazards.ensure(data, state)
```

`scripts/engine/hazards.gd`:

```gdscript
class_name Hazards
extends RefCounted
## Hazards as STATE (spec 2026-10-07-war-room-p2-tactical-layer §2): the pack's
## zones seeded at a new reign, each ending by its kind's months
## (data/hazard_kinds.csv); what is known of one abroad (ruling 6); their
## endings as news. Pure; ids and cells in sorted order.

static var _index_key: Array = []
static var _index: Dictionary = {}   # cell -> [hazard id] (active or not)


static func kind_of(repo: DataRepository, kind: String) -> Dictionary:
	return repo.hazard_kinds.get(kind, {})


## One hazard per pack zone whose kind data/hazard_kinds.csv lists, from
## `start_tick` for its kind's months (0: no end of itself).
static func seed(repo: DataRepository, state: GameState, start_tick: int) -> void:
	var rows: Dictionary = repo.world_table("society", "zones")
	var codes: Array = rows.keys()
	codes.sort()
	for code: String in codes:
		var row: Dictionary = rows[code]
		var k := kind_of(repo, String(row.get("type", "")))
		if k.is_empty():
			continue
		var cells: Array = []
		for c: String in String(row.get("cells", "")).split("|", false):
			if c.is_valid_int() and repo.cells.has(int(c)) and not cells.has(int(c)):
				cells.append(int(c))
		cells.sort()
		if cells.is_empty():
			continue
		var months := int(k["months"])
		add(state, code, String(row["type"]), String(row.get("label", code)), cells, start_tick,
			start_tick + months if months > 0 else -1, "pack")
	state.hazards_seeded = true


## A save written before the hazards were state: seeded once, at its own tick.
static func ensure(repo: DataRepository, state: GameState) -> void:
	if state != null and not state.hazards_seeded:
		seed(repo, state, state.tick)


static func add(state: GameState, id: String, kind: String, label: String, cells: Array, start: int, end: int,
		source: String) -> void:
	state.hazards[id] = {"kind": kind, "label": label, "cells": cells.duplicate(), "start": start, "end": end,
		"source": source}
	state.hazards_rev += 1


## Ends a hazard now (an event's hook); its record stays.
static func end_now(state: GameState, id: String) -> void:
	if state.hazards.has(id):
		state.hazards[id]["end"] = state.tick
		state.hazards_rev += 1


static func is_active(state: GameState, id: String) -> bool:
	var h: Dictionary = state.hazards.get(id, {})
	if h.is_empty():
		return false
	var e := int(h["end"])
	return int(h["start"]) <= state.tick and (e < 0 or state.tick < e)


static func active_ids(state: GameState) -> Array:
	var out: Array = state.hazards.keys().filter(func(id: String) -> bool: return is_active(state, id))
	out.sort()
	return out


static func months_left(state: GameState, id: String) -> int:
	var e := int(state.hazards[id]["end"])
	return -1 if e < 0 else maxi(e - state.tick, 0)


## The active hazards holding a cell, id order.
static func at_cell(state: GameState, cell: int) -> Array:
	var key := [state.get_instance_id(), state.hazards_rev]
	if key != _index_key:
		_index = {}
		var ids: Array = state.hazards.keys()
		ids.sort()
		for id: String in ids:
			for c in state.hazards[id]["cells"]:
				if not _index.has(int(c)):
					_index[int(c)] = []
				(_index[int(c)] as Array).append(id)
		_index_key = key
	return (_index.get(cell, []) as Array).filter(func(id: String) -> bool: return is_active(state, id))


static func at_point(repo: DataRepository, state: GameState, at: Vector2) -> Array:
	var cell := MapEconomy.cell_at(repo, at)
	return [] if cell < 0 else at_cell(state, cell)


## Ruling 6: in the crown's realm every hazard is known; abroad only a public kind.
static func known(repo: DataRepository, state: GameState, id: String) -> bool:
	if Intel.dev_all:
		return true
	var h: Dictionary = state.hazards[id]
	if bool(kind_of(repo, String(h["kind"])).get("public", false)):
		return true
	var realm := repo.resolve_realm("player_realm")
	for c in h["cells"]:
		if MapOwnership.owner_of(repo, state, MapManors.province_of(repo, int(c), state)) == realm:
			return true
	return false


static func touches_province(repo: DataRepository, state: GameState, id: String, province: String) -> bool:
	for c in state.hazards[id]["cells"]:
		if MapManors.province_of(repo, int(c), state) == province:
			return true
	return false


## After the tick turns: the hazards ending this tick, as news, id order.
static func settle_month(repo: DataRepository, state: GameState) -> Array[String]:
	var news: Array[String] = []
	var ids: Array = state.hazards.keys()
	ids.sort()
	for id: String in ids:
		var h: Dictionary = state.hazards[id]
		if int(h["end"]) == state.tick and known(repo, state, id):
			news.append("The %s is over." % String(h["label"]))
	return news
```

- [ ] **Step 4: Import, run the tests**

Import pass; run `tests/engine/test_hazards.gd`, `tests/engine/test_game_state.gd` (or the save test file the repo has — `ls tests/engine | grep -i save`), `tests/engine/test_engine_isolation.gd`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/hazards.gd scripts/engine/hazards.gd.uid scripts/engine/game_state.gd scripts/ui/game.gd tests/engine/test_hazards.gd
git commit -m "feat(hazards): hazards are state — seeded, saved, ending by their kind

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The month's toll and its news

**Files:**
- Modify: `scripts/engine/hazards.gd` (`settle_regiments`), `scripts/engine/tick_engine.gd` (`month_hazard_news`), `scripts/ui/game.gd` (`advance_day` packs it), `scripts/ui/game_root.gd` (publishes it)
- Test: `tests/engine/test_hazards.gd`, `tests/engine/test_tick_engine.gd`

**Interfaces:**
- Consumes: `Hazards.at_point`, `kind_of`, `settle_month` (Task 2).
- Produces: `Hazards.settle_regiments(repo, state) -> Array[String]`; `TickEngine.month_hazard_news: Array` (the toll's news then the endings, set in `advance`); `Game.advance_day()` returns key `"hazards"` on a ticked day.

- [ ] **Step 1: Write the failing tests**

Add to `tests/engine/test_hazards.gd`:

```gdscript
func _crown_land_code(state: GameState) -> String:
	var codes: Array = state.regiments.keys()
	codes.sort()
	for code: String in codes:
		if String(ArmySystem.regiment(repo, code).get("is_naval", "0")) != "1":
			return code
	return ""


func _cell_of(state: GameState, code: String) -> int:
	return MapEconomy.cell_at(repo, ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code)))


func test_a_plague_wounds_a_regiment_standing_in_it_and_says_so() -> void:
	var state := SuiteData.campaign(repo, 42)
	for id: String in state.hazards.keys():
		state.hazards.erase(id)   # a clean field
	state.hazards_rev += 1
	var code := _crown_land_code(state)
	Hazards.add(state, "p", "Disease", "Test Plague", [_cell_of(state, code)], state.tick, -1, "test")
	var heads := ArmySystem.headcount(repo, ArmySystem.regiment(repo, code))
	var before := int(state.regiments[code]["wounded"])
	var fit := heads - before
	@warning_ignore("integer_division")
	var lost := fit * int(Hazards.kind_of(repo, "Disease")["wounds_permille"]) / 1000
	var news := Hazards.settle_regiments(repo, state)
	assert_eq(int(state.regiments[code]["wounded"]), before + lost)
	assert_true(news.any(func(n: String) -> bool: return n.contains("Test Plague") and n.contains(str(lost))))


func test_two_hazards_both_take_their_toll_once() -> void:
	var state := SuiteData.campaign(repo, 42)
	for id: String in state.hazards.keys():
		state.hazards.erase(id)
	state.hazards_rev += 1
	var code := _crown_land_code(state)
	var cell := _cell_of(state, code)
	Hazards.add(state, "p", "Disease", "Test Plague", [cell], state.tick, -1, "test")
	Hazards.add(state, "r", "Rebels", "Test Rebels", [cell], state.tick, -1, "test")
	var morale := int(state.regiments[code]["morale"])
	var news := Hazards.settle_regiments(repo, state)
	assert_eq(news.filter(func(n: String) -> bool: return n.contains("Test Plague")).size(), 1)
	assert_eq(news.filter(func(n: String) -> bool: return n.contains("Test Rebels")).size(), 1)
	assert_eq(int(state.regiments[code]["morale"]), clampi(morale + int(Hazards.kind_of(repo, "Rebels")["morale"]), 0, 100))


func test_no_fit_men_no_toll_and_no_news() -> void:
	var state := SuiteData.campaign(repo, 42)
	for id: String in state.hazards.keys():
		state.hazards.erase(id)
	state.hazards_rev += 1
	var code := _crown_land_code(state)
	state.regiments[code]["wounded"] = ArmySystem.headcount(repo, ArmySystem.regiment(repo, code))
	Hazards.add(state, "p", "Disease", "Test Plague", [_cell_of(state, code)], state.tick, -1, "test")
	var news := Hazards.settle_regiments(repo, state)
	assert_eq(int(state.regiments[code]["wounded"]), ArmySystem.headcount(repo, ArmySystem.regiment(repo, code)))
	assert_eq(news.filter(func(n: String) -> bool: return n.contains("Test Plague")), [])


func test_the_month_is_deterministic() -> void:
	var a := SuiteData.campaign(repo, 9)
	var b := SuiteData.campaign(repo, 9)
	for i in 24:
		Hazards.settle_regiments(repo, a)
		Hazards.settle_regiments(repo, b)
		a.tick += 1
		b.tick += 1
	assert_eq(a.regiments, b.regiments)
```

In `tests/engine/test_tick_engine.gd` add (follow that file's own setup for an engine and a state; the names `engine` / `state` / `data` below are its usual ones — adjust to the file):

```gdscript
func test_the_month_reports_its_hazard_news() -> void:
	var code := ""
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c: String in codes:
		if String(ArmySystem.regiment(data, c).get("is_naval", "0")) != "1":
			code = c
			break
	var cell := MapEconomy.cell_at(data, ArmySystem.position_of(data, state, ArmySystem.regiment(data, code)))
	Hazards.add(state, "p", "Disease", "Test Plague", [cell], state.tick, -1, "test")
	engine.advance(state)
	assert_true(engine.month_hazard_news.any(func(n: String) -> bool: return n.contains("Test Plague")))
```

- [ ] **Step 2: Run to see them fail**

Expected: FAIL (`settle_regiments` / `month_hazard_news` missing).

- [ ] **Step 3: Implement**

`scripts/engine/hazards.gd`:

```gdscript
## The month's toll on the crown's land regiments standing in an active hazard
## (spec §2.3): its kind's wounds_permille of the fit heads (whole, never past
## the headcount) and its morale, each reported with its reason. Code order.
static func settle_regiments(repo: DataRepository, state: GameState) -> Array[String]:
	var news: Array[String] = []
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		var entry: Dictionary = state.regiments[code]
		var heads := ArmySystem.headcount(repo, reg)
		var name := String(reg.get("label", code))
		for id: String in at_point(repo, state, ArmySystem.position_of(repo, state, reg)):
			var h: Dictionary = state.hazards[id]
			var k := kind_of(repo, String(h["kind"]))
			var fit := heads - clampi(int(entry["wounded"]), 0, heads)
			@warning_ignore("integer_division")  # whole heads
			var lost := fit * int(k.get("wounds_permille", 0)) / 1000
			if lost > 0:
				entry["wounded"] = clampi(int(entry["wounded"]) + lost, 0, heads)
				news.append("The %s loses %d to the %s." % [name, lost, String(h["label"])])
			var m := int(k.get("morale", 0))
			if m != 0:
				var was := int(entry["morale"])
				entry["morale"] = clampi(was + m, 0, 100)
				if int(entry["morale"]) != was:
					news.append("The %s's morale %s under the %s." % [name, "falls" if m < 0 else "rises", String(h["label"])])
	return news
```

`scripts/engine/tick_engine.gd`: a var beside `newly_idle`:

```gdscript
## The month's hazard news (Hazards: the toll, then the endings), for the news bar.
var month_hazard_news: Array = []
```

and in `advance`, right after `ArmySystem.settle_month(data, state)`:

```gdscript
	# The hazards take their month's toll (spec 2026-10-07-war-room-p2 §2.3).
	month_hazard_news = Hazards.settle_regiments(data, state)
```

and right after `state.day = 1` (the tick has turned):

```gdscript
	month_hazard_news.append_array(Hazards.settle_month(data, state))
```

`scripts/ui/game.gd` `advance_day`, in the ticked return: add `"hazards": engine.month_hazard_news`.

`scripts/ui/game_root.gd`, after the `idled` loop:

```gdscript
		for line: String in out.get("hazards", []):   # a plague's toll, a flood's end (spec 2026-10-07-war-room-p2 §2.3)
			Game.publish_news(line)
```

- [ ] **Step 4: Run the tests**

Run `tests/engine/test_hazards.gd`, `tests/engine/test_tick_engine.gd`. Then the whole suite: `./run_tests.sh`. A test that advanced months with a crown regiment standing in a pack zone may now see the toll; bring such an expectation to the hazard's figure from `hazard_kinds.csv` (never a literal), and record each as a ruling.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/hazards.gd scripts/engine/tick_engine.gd scripts/ui/game.gd scripts/ui/game_root.gd tests/engine/test_hazards.gd tests/engine/test_tick_engine.gd
git commit -m "feat(hazards): the month's toll on the crown's regiments, and the news of it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: A supply line through a hazard

**Files:**
- Modify: `scripts/engine/supply_system.gd` (`hazard_loss`, `_line_of`)
- Test: `tests/engine/test_supply_marks.gd`

**Interfaces:**
- Consumes: `Hazards.at_point`, `known`, `kind_of` (Task 2); the line's `hazards` list and `total_loss` (P2-A).
- Produces: `SupplySystem.hazard_loss(repo, state, route: PackedVector2Array) -> Dictionary` `{permille, hazards}`, each hazard `{code, label, permille}` — the label "trouble on the road" for one not `known`; `_line_of` adds it to the marks' share (never for a fleet).

- [ ] **Step 1: Write the failing tests**

Add to `tests/engine/test_supply_marks.gd`:

```gdscript
func _road_regiment(state: GameState) -> String:
	for code: String in state.regiments:
		if SupplySystem.route_px(repo, state, code).size() >= 2:
			return code
	return ""


func test_a_line_through_rebels_pays_and_names_them_when_known() -> void:
	var state := SuiteData.campaign(repo, 42)
	var code := _road_regiment(state)
	if code == "":
		pass_test("no regiment on a road")
		return
	var route := SupplySystem.route_px(repo, state, code)
	var cell := MapEconomy.cell_at(repo, route[route.size() / 2])
	Hazards.add(state, "rb", "Rebels", "Road Rebels", [cell], state.tick, -1, "test")
	var line := SupplySystem.line_of(repo, state, code)
	var hz: Array = (line["hazards"] as Array).filter(func(h: Dictionary) -> bool: return String(h["code"]) == "rb")
	assert_eq(hz.size(), 1)
	assert_eq(int(hz[0]["permille"]), int(Hazards.kind_of(repo, "Rebels")["supply_loss_permille"]))
	var label := "Road Rebels" if Hazards.known(repo, state, "rb") else "trouble on the road"
	assert_eq(String(hz[0]["label"]), label)


func test_an_unknown_hazard_is_never_named() -> void:
	var state := SuiteData.campaign(repo, 42)
	var route := PackedVector2Array()
	var mine := repo.resolve_realm("player_realm")
	var foreign := -1
	var ids: Array = repo.cells.keys()
	ids.sort()
	for c: int in ids:
		var owner := MapOwnership.owner_of(repo, state, MapManors.province_of(repo, c, state))
		if owner != "" and owner != mine and not MapTerrain.is_water(repo.cells[c]):
			foreign = c
			break
	var at := MapTerrain.cell_center(repo, repo.cells[foreign])
	route.append(at + Vector2(-0.2, 0))
	route.append(at + Vector2(0.2, 0))
	Hazards.add(state, "far", "Rebels", "Secret Rebels", [foreign], state.tick, -1, "test")
	var got := SupplySystem.hazard_loss(repo, state, route)
	assert_eq(int(got["permille"]), int(Hazards.kind_of(repo, "Rebels")["supply_loss_permille"]))
	assert_eq(String(got["hazards"][0]["label"]), "trouble on the road")
```

- [ ] **Step 2: Run to see them fail**

Expected: FAIL.

- [ ] **Step 3: Implement**

In `scripts/engine/supply_system.gd`, after `mark_loss`:

```gdscript
## What the active hazards a route crosses take (spec 2026-10-07-war-room-p2
## §2.3): each hazard with a supply_loss_permille once, id order, sampled along
## the route every war_hazard_sample_km; a hazard the crown does not know is
## not named ("trouble on the road").
static func hazard_loss(repo: DataRepository, state: GameState, route: PackedVector2Array) -> Dictionary:
	var hazards: Array = []
	var total := 0
	if state == null or route.size() < 2:
		return {"permille": 0, "hazards": hazards}
	var step := repo.bal("war_hazard_sample_km") / WarMarks.km_per_px(repo)
	var hit: Dictionary = {}
	for i in route.size() - 1:
		var a := route[i]
		var b := route[i + 1]
		var n := maxi(1, ceili(a.distance_to(b) / step))
		for j in n + 1:
			for id: String in Hazards.at_point(repo, state, a.lerp(b, float(j) / float(n))):
				hit[id] = true
	var ids: Array = hit.keys()
	ids.sort()
	for id: String in ids:
		var h: Dictionary = state.hazards[id]
		var p := int(Hazards.kind_of(repo, String(h["kind"])).get("supply_loss_permille", 0))
		if p <= 0:
			continue
		total += p
		hazards.append({"code": id, "permille": p,
			"label": String(h["label"]) if Hazards.known(repo, state, id) else "trouble on the road"})
	return {"permille": total, "hazards": hazards}
```

In `_line_of`, where `marks` is computed (the naval guard stays):

```gdscript
	var marks := {"permille": 0, "hazards": []} \
		if String(ArmySystem.regiment(repo, code).get("is_naval", "0")) == "1" else mark_loss(repo, route)
	if String(ArmySystem.regiment(repo, code).get("is_naval", "0")) != "1":
		var through := hazard_loss(repo, state, route)
		marks["permille"] = int(marks["permille"]) + int(through["permille"])
		(marks["hazards"] as Array).append_array(through["hazards"])
```

`data/balance.csv`:

```csv
war_hazard_sample_km,2,"WAR ROOM P2-B (spec 2026-10-07-war-room-p2 §2.3): a supply route is sampled every this many km for the hazards it crosses (a cell is ~20 km)"
```

and add `"war_hazard_sample_km"` to the data test's key list.

- [ ] **Step 4: Run the tests**

Run `tests/engine/test_supply_marks.gd`, `tests/engine/test_supply_system.gd`, `tests/engine/test_ledger_supply.gd`, `tests/engine/test_war_folio.gd`. Expected: PASS (a crown line crossing a pack hazard at the campaign's start would change a figure — bring it to the data and record a ruling).

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/supply_system.gd data/balance.csv tests/engine/test_supply_marks.gd tests/engine/test_war_room_data.gd
git commit -m "feat(hazards): a supply line through rebels or raiders pays, named when known

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: A march through a flood, an avalanche, an eruption

**Files:**
- Modify: `scripts/engine/hazards.gd` (`pace_permille`), `scripts/engine/army_system.gd` (`ground_permille` gains `state`; its three state-holding callers pass it), `scripts/engine/war_ground.gd` (passes state)
- Test: `tests/engine/test_hazards.gd`

**Interfaces:**
- Produces: `Hazards.pace_permille(repo, state, at: Vector2) -> int`; `ArmySystem.ground_permille(repo, reg, at, state: GameState = null) -> int` (state null: as before).

- [ ] **Step 1: Write the failing test**

```gdscript
func test_a_flood_slows_the_march_through_it() -> void:
	var state := SuiteData.campaign(repo, 42)
	for id: String in state.hazards.keys():
		state.hazards.erase(id)
	state.hazards_rev += 1
	var code := _crown_land_code(state)
	var reg := ArmySystem.regiment(repo, code)
	var at := ArmySystem.position_of(repo, state, reg)
	var dry := ArmySystem.ground_permille(repo, reg, at, state)
	Hazards.add(state, "f", "Flood", "Test Flood", [MapEconomy.cell_at(repo, at)], state.tick, -1, "test")
	var pace := int(Hazards.kind_of(repo, "Flood")["pace_permille"])
	@warning_ignore("integer_division")
	assert_eq(ArmySystem.ground_permille(repo, reg, at, state), maxi(1, dry * pace / 1000))
	assert_eq(ArmySystem.ground_permille(repo, reg, at), dry, "no state, no hazard")
```

- [ ] **Step 2: Run to see it fail.** Expected: FAIL (too many arguments).

- [ ] **Step 3: Implement**

`scripts/engine/hazards.gd`:

```gdscript
## A march's pace through the active hazards at a point, per mille (1000 none).
static func pace_permille(repo: DataRepository, state: GameState, at: Vector2) -> int:
	var p := 1000
	for id: String in at_point(repo, state, at):
		var f := int(kind_of(repo, String(state.hazards[id]["kind"])).get("pace_permille", 1000))
		@warning_ignore("integer_division")  # whole per mille
		p = p * f / 1000
	return p
```

`scripts/engine/army_system.gd` — `ground_permille` takes `state: GameState = null` and, for a land regiment, scales its result: rename the body's two `return`s to assign `var base := …`, then:

```gdscript
static func ground_permille(repo: DataRepository, reg: Dictionary, at: Vector2, state: GameState = null) -> int:
	if String(reg.get("is_naval", "0")) == "1":
		return 1000
	var base := 1000
	var road := road_at(repo, at)
	if road != "":
		var id := MapEconomy.cell_at(repo, at)
		var tier := "plains"
		if id >= 0:
			tier = String(Elevation.tier_of(repo, float(repo.cells[id]["height"]))["tier"])
		@warning_ignore("integer_division")  # whole per-mille
		base = maxi(1, int(repo.army_ground_speed.get(road, 1000))
			* int(repo.army_ground_speed.get("tier_" + tier, 1000)) / 1000)
	else:
		base = maxi(1, int(repo.army_ground_speed.get(terrain_at(repo, at), 1000)))
	if state == null:
		return base
	@warning_ignore("integer_division")  # whole per-mille: a flood, an avalanche (spec 2026-10-07-war-room-p2 §2.3)
	return maxi(1, base * Hazards.pace_permille(repo, state, at) / 1000)
```

and pass `state` at its callers that have one: `speed_km_per_day` (~line 576: `ground_permille(repo, reg, position_of(repo, state, reg), state)`), `ground_word` (~654: `ground_permille(repo, reg, at, state)`), `day_march_at` (~774: `ground_permille(repo, regiment(repo, code), at, state)`); and `WarGround._for_regiment`: `ArmySystem.ground_permille(repo, reg, at, state)`.

- [ ] **Step 4: Run** `tests/engine/test_hazards.gd`, `tests/engine/test_army_towns.gd`, `tests/engine/test_army_speed.gd`, `tests/engine/test_war_ground.gd`, `tests/engine/test_army_system.gd`. Expected: PASS (`test_war_ground`'s `g["ground"]` expectation calls `ground_permille` without state — pass `state` there too if the point is in a pack hazard, and record it).

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/hazards.gd scripts/engine/army_system.gd scripts/engine/war_ground.gd tests/engine/test_hazards.gd tests/engine/test_war_ground.gd
git commit -m "feat(hazards): a flood, an avalanche or an eruption slows the march through it

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The slip and the province card

**Files:**
- Modify: `scripts/engine/war_ground.gd` (`reading` → `hazards`; `_hazard_lines`), `scripts/engine/map_objects.gd` (`province_card`'s Hazard line)
- Test: `tests/engine/test_war_ground.gd`, `tests/engine/test_map_objects.gd`

**Interfaces:**
- Produces: `WarGround.reading(...)["hazards"]`: known active hazards at the point, `{id, label, kind, months_left}`; `WarGround.hazard_words(repo, kind: String) -> String` (the effects in words); the province card lists known active hazards touching it: `["Hazard", "<label> (<kind label>, <n> months left | lasting)"]`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/engine/test_war_ground.gd`:

```gdscript
func test_the_slip_names_a_known_hazard_with_its_months_and_effect() -> void:
	var at := _land_point()
	var cell := MapEconomy.cell_at(repo, at)
	Hazards.add(state, "pl", "Disease", "Test Plague", [cell], state.tick, state.tick + 7, "test")
	var r := WarGround.reading(repo, state, at, "")
	assert_true((r["hazards"] as Array).any(func(h: Dictionary) -> bool: return String(h["id"]) == "pl"))
	var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
	assert_true(texts.any(func(t: String) -> bool:
		return t.begins_with("Test Plague") and t.contains("7 months left") and t.contains(WarGround.hazard_words(repo, "Disease"))))


func test_the_slip_never_names_an_unknown_hazard() -> void:
	var mine := repo.resolve_realm("player_realm")
	var ids: Array = repo.cells.keys()
	ids.sort()
	for c: int in ids:
		var owner := MapOwnership.owner_of(repo, state, MapManors.province_of(repo, c, state))
		if owner != "" and owner != mine and not MapTerrain.is_water(repo.cells[c]):
			Hazards.add(state, "sr", "Rebels", "Secret Rebels", [c], state.tick, -1, "test")
			var r := WarGround.reading(repo, state, MapTerrain.cell_center(repo, repo.cells[c]), "")
			var texts := WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))
			assert_false(texts.any(func(t: String) -> bool: return t.contains("Secret Rebels")))
			return
	pass_test("no foreign land")


func test_hazard_words_by_kind() -> void:
	assert_string_contains(WarGround.hazard_words(repo, "Disease"), "a month")
	assert_string_contains(WarGround.hazard_words(repo, "Flood"), "×")
	assert_eq(WarGround.hazard_words(repo, "Fault"), "no effect on a march")
```

In `tests/engine/test_map_objects.gd` add (its own `repo` / `state` names):

```gdscript
func test_the_province_card_lists_only_active_known_hazards() -> void:
	var cell := -1
	var prov := ""
	var ids: Array = repo.cells.keys()
	ids.sort()
	for c: int in ids:
		prov = MapManors.province_of(repo, c, state)
		if prov != "" and MapOwnership.owner_of(repo, state, prov) == repo.resolve_realm("player_realm"):
			cell = c
			break
	Hazards.add(state, "on", "Flood", "Live Flood", [cell], state.tick, state.tick + 2, "test")
	Hazards.add(state, "off", "Flood", "Old Flood", [cell], state.tick - 3, state.tick - 1, "test")
	var card := MapObjects.province_card(repo, state, prov)
	var lines: Array = (card["fields"] as Array).filter(func(f: Array) -> bool: return String(f[0]) == "Hazard").map(
		func(f: Array) -> String: return String(f[1]))
	assert_true(lines.any(func(t: String) -> bool: return t.begins_with("Live Flood") and t.contains("2 months left")))
	assert_false(lines.any(func(t: String) -> bool: return t.contains("Old Flood")))
```

(If `province_card` takes its arguments in another order or returns its rows under another key, follow the existing call in that test file.)

- [ ] **Step 2: Run to see them fail.** Expected: FAIL.

- [ ] **Step 3: Implement**

`scripts/engine/war_ground.gd` — in `reading`'s dictionary:

```gdscript
		"hazards": Hazards.at_point(repo, state, at).filter(func(id: String) -> bool: return Hazards.known(repo, state, id)).map(
			func(id: String) -> Dictionary: return {"id": id, "label": String(state.hazards[id]["label"]),
				"kind": String(state.hazards[id]["kind"]), "months_left": Hazards.months_left(state, id)}) \
			if state != null else [],
```

and, in `lines`, right after the weather line of BOTH branches (sea and land), `_hazard_lines(repo, r, out)`, with:

```gdscript
## A known hazard at the point: its name, months left and what it does.
static func _hazard_lines(repo: DataRepository, r: Dictionary, out: Array) -> void:
	for h: Dictionary in r.get("hazards", []):
		var left := int(h["months_left"])
		var when := "" if left < 0 else " — %d month%s left" % [left, "" if left == 1 else "s"]
		_add(out, "%s%s: %s" % [String(h["label"]), when, hazard_words(repo, String(h["kind"]))])


## A kind's effects in words (data/hazard_kinds.csv).
static func hazard_words(repo: DataRepository, kind: String) -> String:
	var k := Hazards.kind_of(repo, kind)
	var parts: Array[String] = []
	if int(k.get("wounds_permille", 0)) > 0:
		parts.append("regiments here lose about %s%% a month" % String.num(float(k["wounds_permille"]) / 10.0, 1))
	if int(k.get("morale", 0)) < 0:
		parts.append("morale falls %d a month" % -int(k["morale"]))
	if int(k.get("supply_loss_permille", 0)) > 0:
		@warning_ignore("integer_division")
		parts.append("supply lines through it lose %d%%" % (int(k["supply_loss_permille"]) / 10))
	if int(k.get("pace_permille", 1000)) < 1000:
		parts.append("marches here go at ×%.2f" % (float(k["pace_permille"]) / 1000.0))
	return "; ".join(parts) if not parts.is_empty() else "no effect on a march"
```

`scripts/engine/map_objects.gd` `province_card` — replace the static zones loop:

```gdscript
	if state != null:   # the hazards in play there that the crown knows (spec 2026-10-07-war-room-p2 ruling 7)
		for id: String in Hazards.active_ids(state):
			if Hazards.known(repo, state, id) and Hazards.touches_province(repo, state, id, code):
				var h: Dictionary = state.hazards[id]
				var left := Hazards.months_left(state, id)
				fields.append(["Hazard", "%s (%s, %s)" % [String(h["label"]),
					String(Hazards.kind_of(repo, String(h["kind"])).get("label", h["kind"])),
					"lasting" if left < 0 else "%d month%s left" % [left, "" if left == 1 else "s"]]])
```

- [ ] **Step 4: Run** `tests/engine/test_war_ground.gd`, `tests/engine/test_map_objects.gd`, `tests/engine/test_engine_isolation.gd`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/war_ground.gd scripts/engine/map_objects.gd tests/engine/test_war_ground.gd tests/engine/test_map_objects.gd
git commit -m "feat(hazards): the slip and the province card read the known hazards

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Hatched areas on the war table and their key

**Files:**
- Modify: `scripts/war_room/war_intel_ink.gd` (`strokes` → `hazards`; `cache_key`), `scripts/war_room/war_ink_painter.gd` (`_draw_intel`), `scripts/war_room/war_room_ink.gd` (`INTEL_PX` gains `hazard`, `INTEL_RATIOS` gains `hazard_alpha`), `scripts/ui/war_margin_key.gd` (four entries), `data/balance.csv`
- Test: `tests/war_room/test_war_intel_ink.gd`, `tests/ui/test_war_margin_key.gd`, `tests/engine/test_war_room_data.gd`

**Interfaces:**
- Consumes: `Hazards.active_ids`, `known`, `kind_of`, `months_left` (Task 2).
- Produces: `WarIntelInk.strokes(...)["hazards"]`: `{ink: String, lines: Array[PackedVector2Array], dots: PackedVector2Array, edges: Array[PackedVector2Array], at: Vector2, text: String}` (tex px) for each known active hazard whose kind's ink is not `none`; legend keys `hazard_plague`, `hazard_unrest`, `hazard_water`, `hazard_rock`.

- [ ] **Step 1: Write the failing tests**

Add to `tests/war_room/test_war_intel_ink.gd` (its `repo` / `state`):

```gdscript
func test_a_known_hazard_is_hatched_and_named_and_an_unknown_is_not() -> void:
	var codes: Array = state.regiments.keys()
	codes.sort()
	var home := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, String(codes[0])))
	var s: Dictionary = WarSheets.series(repo)[WarSheets.sheet_of(repo, home)]
	var r: Rect2 = s["rect"]
	var cells: Array = []
	for c: int in repo.cells:
		if not MapTerrain.is_water(repo.cells[c]) and r.has_point(MapTerrain.cell_center(repo, repo.cells[c])):
			cells.append(c)
		if cells.size() >= 3:
			break
	Hazards.add(state, "hz", "Flood", "Sheet Flood", cells, state.tick, state.tick + 2, "test")
	var ink := WarIntelInk.strokes(repo, state, s, int(repo.bal("war_intel_texture_px")))
	var mine: Array = (ink["hazards"] as Array).filter(func(h: Dictionary) -> bool: return String(h["text"]).begins_with("Sheet Flood"))
	assert_eq(mine.size(), 1)
	assert_gt((mine[0]["lines"] as Array).size(), 0, "hatched")
	assert_gt((mine[0]["edges"] as Array).size(), 0, "outlined")
	assert_eq(String(mine[0]["ink"]), "water")
	var before := WarIntelInk.cache_key(state, int(s["index"]))
	Hazards.end_now(state, "hz")
	assert_ne(WarIntelInk.cache_key(state, int(s["index"])), before, "an ending redraws the layer")
```

In `tests/ui/test_war_margin_key.gd`, extend `test_the_legend_lists_the_sheets_inks`' expected list with `"hazard_plague", "hazard_unrest", "hazard_water", "hazard_rock"`. Add `"war_intel_hazard_px", "war_intel_hazard_alpha", "war_hazard_hatch_km"` to the data test's key list.

- [ ] **Step 2: Run to see them fail.** Expected: FAIL.

- [ ] **Step 3: Implement**

`data/balance.csv`:

```csv
war_intel_hazard_px,3,"WAR ROOM P2-B (spec 2026-10-07-war-room-p2 §2.4): a hazard's hatch lines and dots, intel px (the 4096 intel texture)"
war_intel_hazard_alpha,0.5,"WAR ROOM P2-B §2.4: the hatching's alpha in the intel ink"
war_hazard_hatch_km,3,"WAR ROOM P2-B §2.4: the hatch's spacing, in the pack's measure"
```

`scripts/war_room/war_room_ink.gd`: `INTEL_PX` gains `"hazard"`, `INTEL_RATIOS` gains `"hazard_alpha"`.

`scripts/war_room/war_intel_ink.gd` — `cache_key` gains `state.hazards_rev` in its hashed array; in `strokes`, add `"hazards": []` to `out` and, before the spies:

```gdscript
	# the known hazards in play (spec 2026-10-07-war-room-p2 §2.4): hatched by kind, outlined, named
	var gap := repo.bal("war_hazard_hatch_km") / WarMarks.km_per_px(repo) * k
	for id: String in Hazards.active_ids(state):
		if not Hazards.known(repo, state, id):
			continue
		var h: Dictionary = state.hazards[id]
		var ink := String(Hazards.kind_of(repo, String(h["kind"])).get("ink", "none"))
		if ink == "none":
			continue
		var polys: Array = []
		var centre := Vector2.ZERO
		for c in h["cells"]:
			var cell: Dictionary = repo.cells[int(c)]
			var poly := PackedVector2Array()
			for v in (cell["vertex_ids"] as PackedInt32Array):
				poly.append(((repo.vertices[v] as Vector2) - r.position) * k)
			polys.append(poly)
			centre += (MapTerrain.cell_center(repo, cell) - r.position) * k
		centre /= float(maxi(polys.size(), 1))
		var tex_rect := Rect2(Vector2.ZERO, r.size * k)
		if not polys.any(func(p: PackedVector2Array) -> bool: return Geometry2D.intersect_polygons(p,
				PackedVector2Array([tex_rect.position, Vector2(tex_rect.end.x, 0), tex_rect.end, Vector2(0, tex_rect.end.y)])).size() > 0):
			continue
		var left := Hazards.months_left(state, id)
		(out["hazards"] as Array).append({"ink": ink, "lines": hatch_lines(polys, ink, gap),
			"dots": hatch_dots(polys, ink, gap), "edges": outline(polys), "at": centre,
			"text": String(h["label"]) + ("" if left < 0 else " · %d mo" % left)})
```

and the pure helpers:

```gdscript
## Hatch lines through each polygon at the kind's angles: unrest crossed (±45°),
## water level (0°), rock one diagonal (painted dashed), plague none (dots).
static func hatch_lines(polys: Array, ink: String, gap: float) -> Array:
	var angles: Array = {"unrest": [PI * 0.25, -PI * 0.25], "water": [0.0], "rock": [PI * 0.25]}.get(ink, [])
	var out: Array = []
	for poly: PackedVector2Array in polys:
		var box := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			box = box.expand(p)
		var c := box.get_center()
		var reach := box.size.length() * 0.5 + gap
		for a: float in angles:
			var along := Vector2.from_angle(a)
			var across := along.orthogonal()
			var t := -reach
			while t <= reach:
				var line := PackedVector2Array([c + across * t - along * reach, c + across * t + along * reach])
				out.append_array(Geometry2D.intersect_polyline_with_polygon(line, poly))
				t += gap
	return out


## A plague's dots: a grid inside each polygon.
static func hatch_dots(polys: Array, ink: String, gap: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	if ink != "plague":
		return out
	for poly: PackedVector2Array in polys:
		var box := Rect2(poly[0], Vector2.ZERO)
		for p in poly:
			box = box.expand(p)
		var y := ceilf(box.position.y / gap) * gap
		while y < box.end.y:
			var x := ceilf(box.position.x / gap) * gap
			while x < box.end.x:
				if Geometry2D.is_point_in_polygon(Vector2(x, y), poly):
					out.append(Vector2(x, y))
				x += gap
			y += gap
	return out


## The edges no two of the polygons share: the hazard's outline.
static func outline(polys: Array) -> Array:
	var count: Dictionary = {}
	var seg: Dictionary = {}
	for poly: PackedVector2Array in polys:
		for i in poly.size():
			var a := poly[i]
			var b := poly[(i + 1) % poly.size()]
			var key := [Vector2i((a * 4.0).round()), Vector2i((b * 4.0).round())]
			key.sort()
			count[key] = int(count.get(key, 0)) + 1
			seg[key] = PackedVector2Array([a, b])
	var out: Array = []
	for key in count:
		if int(count[key]) == 1:
			out.append(seg[key])
	return out
```

`scripts/war_room/war_ink_painter.gd` `_draw_intel()` — first (under the supply roads):

```gdscript
	var hz_c: Color = pal["intel_ink"]
	hz_c.a *= float(px.get("hazard_alpha", 0.5))
	for h: Dictionary in ink.get("hazards", []):
		var w := float(px.get("hazard", 3.0))
		for l: PackedVector2Array in h["lines"]:
			if String(h["ink"]) == "rock":
				for d: PackedVector2Array in WarSheetInk.dashed(l, w * 4.0, w * 3.0):
					draw_polyline(d, hz_c, w, true)
			else:
				draw_polyline(l, hz_c, w, true)
		for p: Vector2 in h["dots"]:
			draw_circle(p, w * 0.8, hz_c)
		for e: PackedVector2Array in h["edges"]:
			for d: PackedVector2Array in WarSheetInk.dashed(e, float(px["supply_dash"]), float(px["supply_gap"])):
				draw_polyline(d, pal["intel_ink"], w, true)
		draw_string(font, (h["at"] as Vector2), String(h["text"]), HORIZONTAL_ALIGNMENT_CENTER, -1,
			int(px["intel_label"]), pal["intel_ink"])
```

`scripts/ui/war_margin_key.gd` — `LEGEND` gains `{"key": "hazard_plague", "label": "Plague"}, {"key": "hazard_unrest", "label": "Unrest"}, {"key": "hazard_water", "label": "Flood"}, {"key": "hazard_rock", "label": "Rockfall"}`; `_draw_mark` before the `match`:

```gdscript
	if key.begins_with("hazard_"):   # a hazard's hatch in the intel ink (spec 2026-10-07-war-room-p2 §2.4)
		var hc: Color = pal.get("intel_ink", ink)
		var box := r.grow(-r.size.y * 0.1)
		var kind := key.trim_prefix("hazard_")
		var poly := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
		for l: PackedVector2Array in WarIntelInk.hatch_lines([poly], kind, box.size.y * 0.35):
			draw_polyline(l, hc, line * 0.8, true)
		for p: Vector2 in WarIntelInk.hatch_dots([poly], kind, box.size.y * 0.35):
			draw_circle(p, line * 0.7, hc)
		draw_rect(box, hc, false, line * 0.6, true)
		return
```

- [ ] **Step 4: Run** `tests/war_room/test_war_intel_ink.gd`, `tests/ui/test_war_margin_key.gd`, `tests/engine/test_war_room_data.gd`, `tests/war_room/test_war_room_view.gd`. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/war_room/war_intel_ink.gd scripts/war_room/war_ink_painter.gd scripts/war_room/war_room_ink.gd scripts/ui/war_margin_key.gd data/balance.csv tests/war_room/test_war_intel_ink.gd tests/ui/test_war_margin_key.gd tests/engine/test_war_room_data.gd
git commit -m "feat(war room): known hazards hatched on the table, and their key

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: Visual review, documents, the whole suite

- [ ] **Step 1: Visual review** — `visual-review` skill; real-window shots at 2560x1600 of the crown's own Wighamnian Revolters (rothin) and the Botfordan Avalanche at 1.6 / 0.5 m (`--war-focus-px` on their centres from `zones.csv`), a public plague abroad (the Unknown Plague), the slip resting inside one, the key. Bracket `war_intel_hazard_alpha` (0.35 / 0.5 / 0.7) and `war_hazard_hatch_km` (2 / 3 / 4); an independent critic against `taste.md` ("A map mark is ink, not a badge", the flat parchment chart; the hatches must not drown the sheet's ink). Tune; note each reason in its key.
- [ ] **Step 2: Documents** — `scripts/engine/CLAUDE.md`: a bullet **Hazards are STATE** (`GameState.hazards`, `Hazards`, `data/hazard_kinds.csv`, seeded at a new reign / once for an old save, the monthly toll in `TickEngine` after the regiments' month, endings after the tick turns, a supply share named only when known, the pace in `ground_permille` with a state). `scripts/war_room/CLAUDE.md` "A second texture of what we KNOW": the hatched hazards. `data/CLAUDE.md`: `hazard_kinds`. Keep each under its size cap.
- [ ] **Step 3: Whole suite** — `./run_tests.sh`: green.
- [ ] **Step 4: Commit**

```bash
git add data/balance.csv scripts/engine/CLAUDE.md scripts/war_room/CLAUDE.md data/CLAUDE.md
git commit -m "docs(hazards): the rules as they stand; values tuned at visual review

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

## Landing

`./run_tests.sh` green; merge main in and rerun; check the owner's editor has none of these scripts open with an unsaved buffer (`data_repository.gd` was stale after P2-A — warn the owner again); `git merge --ff-only spec/war-room-p2b` in the main checkout and push.
