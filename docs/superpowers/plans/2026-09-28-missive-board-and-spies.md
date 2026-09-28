# Missive Board and Spy Couriers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Information becomes a resource. Land the crown does not control sits under a fog of knowledge; spy couriers ride out to any point and report honest estimates; every letter the crown receives is pinned on the Missive board in four credibility columns.

**Architecture:**
- **Engine** (pure `RefCounted`):
  - `MissiveLog` owns `GameState.missives`, the saved letters.
  - `MissiveWriter` writes the two routine letters: the courier's delivery receipt and the steward's monthly report.
  - `SpySystem` turns a spy's arrival into a report, with a seeded quality roll.
  - `Intel` is the single knowledge gate that every card and panel asks.
- **UI**:
  - an authored `MissiveScreen` (board plus reading desk);
  - a `MissiveReportPopup`;
  - a reusable `EnvelopeFlight` tween;
  - a `SpyOrderMenu` on right-click.

**Tech Stack:** Godot 4.7, typed GDScript, GUT (`./run_tests.sh`), CSV data under `data/`.

**Spec:** `docs/superpowers/specs/2026-09-28-missive-board-and-spies-design.md` (builds on `docs/superpowers/specs/2026-09-27-courier-core-design.md`)

## Global Constraints

**Engine rules**
- Typed GDScript everywhere.
- Engine classes are `RefCounted`: no Node, no `Time.*`, no unseeded random.
- The only randomness is `GameState.rng`, drawn in a fixed order: a spy's quality roll, then his bias roll, at his arrival, with couriers in id order.
- State holds whole numbers only. Missive subjects carry whole pack px; facts carry ints or strings.
- Design values live in CSVs (`data/*.csv`, `balance.csv`). Nothing is tuned in code.
- **Four columns, in this order:** `truth` (ground truth), `credible` (highly credible), `consult` (worth consulting — empty in B), `rumour`.
- **Receipt** → `credible`; **monthly report** → `truth`; **spy report** → `credible` when `q >= spy_credible_threshold` (500), else `rumour`.
- **Intel levels:**
  - `full`: provinces the crown controls, and the player's regiments;
  - `general`: the rest of the player's realm;
  - `basic`: foreign.
  - DEV MODE reads `full` everywhere.

**UI rules**
- **A spy report pauses the clock and opens a dialog; nothing ever restarts the clock.** Receipts and monthly reports never interrupt.
- Nothing under `scripts/map3d/` may reference the `Game` autoload, except `map3d_view.gd`.
- Every `scripts/map3d/*.gd` stays ≤ 300 lines.
- `map3d_view.gd` is AT its cap: 560 in `tests/map3d/test_map3d_shape.gd`, which counts `split("\n").size()`. It may grow only by forwarders, guards and signals, and the cap moves with a comment.
- `.tscn` files: no Godot editor is open on the worktree, so author scenes as TEXT, matching each file's existing format.

**Commits and tests**
- Commit only the files a task names, plus the `.uid` sidecars of new scripts. Never `git add -A`.
- `./run_tests.sh` must end with the expected error count: 0 in a worktree without the gdai binaries, 2 with them.

## Review Focus

1. **Two spies arrive in the same stepped frame at 4x.** Expected: the clock stops at the first, both reports open one after the other, and no day runs past a pending report. Pinned in Task 8, `test_two_spy_reports_in_one_frame_open_in_turn`.
2. **An old save with no `missives` key.** Expected: it loads with an empty board and zero unread. Pinned in Task 1, `test_an_old_save_has_an_empty_board`.
3. **A spy sent to the open sea.** Expected: a report of troops only, with no manor facts and no crash. Pinned in Task 4, `test_a_spy_at_sea_reports_troops_only`.
4. **A spy report about land the crown controls.** Expected: the card still shows the exact figure, because `full` beats any estimate. Pinned in Task 3, `test_full_knowledge_beats_a_report`.
5. **The letter open on the desk is capped away** by a new arrival in its column. Expected: the desk goes back to "Choose a letter" with no error. Pinned in Task 7, `test_a_capped_away_letter_empties_the_desk`.

---

### Task 1: Missive log and B's tables

**Files:**
- Create: `scripts/engine/missive_log.gd`, `data/intel_facts.csv`, `data/spy_difficulty.csv`, `data/missive_art.csv`
- Modify:
  - `data/balance.csv` (append rows)
  - `data/political_palette.csv` (append rows)
  - `data/courier_kinds.csv` and `data/courier_art.csv` (add a `spy` row each)
  - `scripts/engine/data_repository.gd` (vars and loaders beside `courier_kinds`)
  - `scripts/engine/game_state.gd` (`missives`, `next_missive_id`, with save and load beside `couriers` :285–287 / :323–324 / :384–385)
- Test: `tests/engine/test_missive_log.gd`

**Interfaces:**
- Produces:
  - `MissiveLog.COLUMNS := ["truth", "credible", "consult", "rumour"]`
  - `MissiveLog.make(kind: String, column: String, day: int, subject: Dictionary, title: String, facts: Array) -> Dictionary`
  - `MissiveLog.subject(kind: String, code: String, cell: int, px: Vector2) -> Dictionary`, which returns `{kind, code, cell, x: int, y: int}`
  - `MissiveLog.exact(key, label, value: int)`, `MissiveLog.span(key, label, lo: int, hi: int)`, `MissiveLog.words(key, label, text: String)` → fact Dictionaries
  - `MissiveLog.add(repo, state, m: Dictionary) -> int`, which assigns `id` and `read = false` and applies the per-column cap
  - `MissiveLog.column(state, column: String) -> Array`, newest first
  - `MissiveLog.find(state, id: int) -> Dictionary`
  - `MissiveLog.unread(state) -> int`
  - `MissiveLog.mark_read(state, id: int) -> void`
  - `DataRepository.intel_facts`: key → `{label, round_to: int, tiers: PackedStringArray}`
  - `DataRepository.spy_difficulty`: key → int ‰
  - `DataRepository.missive_art`: key → texture path
  - `GameState.missives: Array`, `GameState.next_missive_id: int`

- [ ] **Step 1: Write the failing test** — `tests/engine/test_missive_log.gd`

```gdscript
extends GutTest
## The Missive log (spec 2026-09-28-missive-board-and-spies §1).

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")


func _m(column: String, day: int) -> Dictionary:
	return MissiveLog.make("spy", column, day, MissiveLog.subject("point", "", -1, Vector2(10.4, 20.6)),
		"A letter", [MissiveLog.exact("people", "People", 3000)])


func test_add_gives_ids_and_starts_unread() -> void:
	var s := GameState.new_campaign(repo, 7)
	assert_eq(MissiveLog.add(repo, s, _m("credible", 3)), 1)
	assert_eq(MissiveLog.add(repo, s, _m("rumour", 4)), 2)
	assert_eq(MissiveLog.unread(s), 2)
	var one := MissiveLog.find(s, 1)
	assert_eq(String(one["column"]), "credible")
	assert_eq(int(one["subject"]["x"]), 10, "pack px are whole")
	assert_eq(int(one["subject"]["y"]), 21)
	MissiveLog.mark_read(s, 1)
	assert_eq(MissiveLog.unread(s), 1)


func test_a_column_lists_newest_first() -> void:
	var s := GameState.new_campaign(repo, 7)
	for d in [1, 2, 3]:
		MissiveLog.add(repo, s, _m("credible", d))
	MissiveLog.add(repo, s, _m("truth", 9))
	var ids: Array = MissiveLog.column(s, "credible").map(func(m: Dictionary) -> int: return int(m["id"]))
	assert_eq(ids, [3, 2, 1])


func test_each_column_is_capped_on_its_own() -> void:
	var s := GameState.new_campaign(repo, 7)
	repo.balance["missive_keep_per_column"] = 2.0
	MissiveLog.add(repo, s, _m("truth", 1))
	for d in [1, 2, 3]:
		MissiveLog.add(repo, s, _m("credible", d))
	assert_eq(MissiveLog.column(s, "credible").size(), 2)
	assert_eq(MissiveLog.find(s, 2), {}, "the oldest credible letter left")
	assert_eq(MissiveLog.column(s, "truth").size(), 1, "another column is untouched")


func test_the_log_survives_a_save() -> void:
	var s := GameState.new_campaign(repo, 7)
	MissiveLog.add(repo, s, _m("rumour", 5))
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(copy.next_missive_id, 1)
	assert_eq(JSON.stringify(copy.missives), JSON.stringify(s.missives))


func test_an_old_save_has_an_empty_board() -> void:
	var s := GameState.new_campaign(repo, 7)
	var d: Dictionary = s.to_dict()
	d.erase("missives")
	d.erase("next_missive_id")
	var old := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_eq(old.missives, [])
	assert_eq(MissiveLog.unread(old), 0)


func test_the_tables() -> void:
	for key in ["people", "tax", "output", "wealth", "troops_own", "troops_foreign", "holder", "stance"]:
		assert_true(repo.intel_facts.has(key), key)
	assert_eq(Array(repo.intel_facts["wealth"]["tiers"]), ["poor", "middling", "rich"])
	assert_eq(int(repo.spy_difficulty["foreign"]), -150)
	assert_eq(int(repo.courier_kinds["spy"]["speed_permille"]), 900)
	assert_true(repo.courier_art.has("spy"))
	for c: String in MissiveLog.COLUMNS:
		assert_true(repo.palette.has("intel_" + c), c)
```

- [ ] **Step 2: Run it to verify it fails.** Run `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_missive_log.gd -gpre_run_script=res://tests/pre_run.gd -gexit`. The first time, run `Godot --headless --path . --import` so the new file is seen. Expected: FAIL (`MissiveLog` not declared).

- [ ] **Step 3: The data.**

`data/intel_facts.csv`:
```
key,label,round_to,tiers,notes
people,People,100,,"spec 2026-09-28-missive-board-and-spies §1: a spy's estimate is rounded out to this, so a range reads 2,800–3,200"
tax,Tax a month,10,,gold a month
output,Goods a month,5,,units of the manor's chief good a month
wealth,Wealth,1,poor|middling|rich,"the province's tax per person against every province's terciles (Intel.wealth_tier); always given in words"
troops_own,Our troops nearby,100,,headcount within spy_radius_km
troops_foreign,Foreign troops nearby,100,,headcount within spy_radius_km
holder,Held by,1,,always given
stance,Stance,1,,"the player realm's stance toward the holder (the pack's diplomacy.csv), always given"
```

`data/spy_difficulty.csv`:
```
key,permille,notes
foreign,-150,"spec §1: added to a spy's quality roll (0..999) when the point lies outside the player's realm"
home,150,inside the player's realm
walled,-100,"a town with walls or a citadel in the point's cell (burg features)"
weather_rain,-50,the weather at the point on the day he arrives
weather_mud,-50,
weather_snow,-100,
weather_blizzard,-200,
```

`data/missive_art.csv`:
```
key,texture,notes
frame,,"spec §3: the board's wooden frame (nine-sliced); empty until the Flux art is installed — UiPalette's flat style stands in"
board,,the cork ground behind the columns
note,,a pinned parchment slip
letter,,the reading desk's parchment
envelope,,the wax-sealed envelope that flies to the tab
pin,,the pin on a note
plaque,,a column header plaque
```

Append these to `data/courier_kinds.csv`:
```
spy,900,8,1,"spec 2026-09-28 §1: a spy rides A's roads at 900‰ to a POINT, not a regiment; offered by SPY_SEND"
```

Append these to `data/courier_art.csv`:
```
spy,res://assets/units3d/cavalry.glb,,0.7,the same INTERIM stand-in until sub-project D
```

Append these to `data/balance.csv`:
```
missive_keep_per_column,40,"spec 2026-09-28 §1: letters kept per board column; the oldest leaves when one more arrives"
spy_radius_km,25,a spy counts the troops within this distance of his point
spy_credible_threshold,500,a quality roll (0..999 after spy_difficulty) at or above this files the report as highly credible; below is rumour
spy_text_threshold,300,below this the holder / stance / wealth read "unclear"
spy_width_best,100,"per mille half-width of an estimate at the best quality"
spy_width_worst,450,per mille half-width at the worst quality
spy_bias_max,300,"per mille: a rumour's whole report is shifted by up to this much, one sign for every fact"
intel_match_km,10,a report about a point counts for a subject within this distance
intel_magnitude_hundreds,100,"Intel.magnitude: under this a figure reads 'a handful'"
intel_magnitude_thousands,1000,under this 'hundreds'
intel_magnitude_many,5000,"under this 'thousands', else 'many thousands'"
missive_seal_s,0.5,the report dialog's shrink into its envelope (EnvelopeFlight)
missive_fly_s,0.9,the envelope's flight to the Missive tab
missive_fly_turns,2,whole turns the envelope spins in flight
```

Append these to `data/political_palette.csv`:
```
intel_truth,#D8C27A,"Missive board (spec 2026-09-28): ground truth — the column plaque and a card's intel tag"
intel_credible,#7FB069,highly credible
intel_consult,#6FA3C8,worth consulting (sub-project C)
intel_rumour,#B07A5A,rumour
```

- [ ] **Step 4: The loaders and state.**

In `scripts/engine/data_repository.gd`, beside `var courier_kinds`:
```gdscript
## data/intel_facts.csv: key -> {label, round_to, tiers} (spec 2026-09-28 §1).
var intel_facts: Dictionary = {}
## data/spy_difficulty.csv: key -> per mille added to a spy's quality roll.
var spy_difficulty: Dictionary = {}
## data/missive_art.csv: key -> texture path ("" until installed).
var missive_art: Dictionary = {}
```

After the `weather_odds.csv` loader:
```gdscript
	if not _load_if_present(dir + "/intel_facts.csv", ["key", "label", "round_to", "tiers"],
			func(r): intel_facts[String(r["key"])] = {"label": String(r["label"]),
				"round_to": maxi(1, int(r["round_to"])),
				"tiers": String(r["tiers"]).split("|", false)}):
		return false
	if not _load_if_present(dir + "/spy_difficulty.csv", ["key", "permille"],
			func(r): spy_difficulty[String(r["key"])] = int(r["permille"])):
		return false
	if not _load_if_present(dir + "/missive_art.csv", ["key", "texture"],
			func(r): missive_art[String(r["key"])] = String(r["texture"])):
		return false
```

In `scripts/engine/game_state.gd`, beside `couriers` / `next_courier_id`:
```gdscript
## The letters the crown has received (owner 2026-09-28, MissiveLog): an Array
## of Dictionaries, whole numbers and strings only.
var missives: Array = []
var next_missive_id := 0
```

In `to_dict`, beside `"couriers"`:
```gdscript
		"missives": _encode_values(missives.duplicate(true)),
		"next_missive_id": _encode_values(next_missive_id),
```

In `from_dict`, beside `s.couriers`:
```gdscript
	# Saves from before the Missive board carry neither key: an empty board.
	s.missives = _decode_values(d.get("missives", []))
	s.next_missive_id = int(_decode_values(d.get("next_missive_id", 0)))
```

- [ ] **Step 5: Write `scripts/engine/missive_log.gd`**

```gdscript
class_name MissiveLog
extends RefCounted
## The crown's letters (owner 2026-09-28, spec docs/superpowers/specs/2026-09-28-missive-board-and-spies-design.md):
## GameState.missives, the one writer. Each column keeps missive_keep_per_column
## letters; the oldest leaves when one more arrives. Whole numbers and strings only.

const COLUMNS := ["truth", "credible", "consult", "rumour"]


static func subject(kind: String, code: String, cell: int, px: Vector2) -> Dictionary:
	return {"kind": kind, "code": code, "cell": cell, "x": roundi(px.x), "y": roundi(px.y)}


static func exact(key: String, label: String, value: int) -> Dictionary:
	return {"key": key, "label": label, "exact": value}


static func span(key: String, label: String, lo: int, hi: int) -> Dictionary:
	return {"key": key, "label": label, "lo": lo, "hi": hi}


static func words(key: String, label: String, text: String) -> Dictionary:
	return {"key": key, "label": label, "text": text}


static func make(kind: String, column: String, day: int, subj: Dictionary, title: String,
		facts: Array) -> Dictionary:
	return {"kind": kind, "column": column, "day": day, "subject": subj, "title": title,
		"facts": facts.duplicate(true)}


## File a letter: a fresh id, unread, then the column's cap. Returns the id.
static func add(repo: DataRepository, state: GameState, m: Dictionary) -> int:
	state.next_missive_id += 1
	var entry := m.duplicate(true)
	entry["id"] = state.next_missive_id
	entry["read"] = false
	state.missives.append(entry)
	var keep := maxi(1, int(repo.bal("missive_keep_per_column")))
	var mine := column(state, String(entry["column"]))
	for i in range(keep, mine.size()):
		state.missives.erase(mine[i])
	return state.next_missive_id


## A column's letters, newest (highest id) first.
static func column(state: GameState, col: String) -> Array:
	var out: Array = state.missives.filter(func(m: Dictionary) -> bool: return String(m["column"]) == col)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) > int(b["id"]))
	return out


static func find(state: GameState, id: int) -> Dictionary:
	for m: Dictionary in state.missives:
		if int(m["id"]) == id:
			return m
	return {}


static func unread(state: GameState) -> int:
	var n := 0
	for m: Dictionary in state.missives:
		if not bool(m.get("read", false)):
			n += 1
	return n


static func mark_read(state: GameState, id: int) -> void:
	var m := find(state, id)
	if not m.is_empty():
		m["read"] = true
```

- [ ] **Step 6: Run the test and then the whole suite.** Expected: PASS.
- [ ] **Step 7: Commit**

```bash
git add scripts/engine/missive_log.gd scripts/engine/missive_log.gd.uid data/intel_facts.csv data/spy_difficulty.csv data/missive_art.csv data/balance.csv data/political_palette.csv data/courier_kinds.csv data/courier_art.csv scripts/engine/data_repository.gd scripts/engine/game_state.gd tests/engine/test_missive_log.gd tests/engine/test_missive_log.gd.uid
git commit -m "feat(missives): the crown's letters, saved and capped per column, and B's tables"
```

---

### Task 2: Receipts and the steward's monthly report

**Files:**
- Create: `scripts/engine/missive_writer.gd`
- Modify:
  - `scripts/engine/courier_system.gd` (`_deliver` ~:272 writes a receipt for a delivered or stale order)
  - `scripts/engine/tick_engine.gd` (`advance`, right after `_settle_economy(state, r)` ~:47)
- Test: `tests/engine/test_missive_writer.gd`

**Interfaces:**
- Consumes:
  - `MissiveLog.*` (Task 1)
  - `ArmySystem.state_of/terrain_of/position_of/regiment`
  - `Weather.at/label_of`
  - `RealmEconomy.province(repo, state, code) -> {tax, strategic, civil}`
  - `RealmEconomy._figure(repo, state, path) -> int`
  - `MapManors.controlled_provinces/home_province`
  - `Calendar.season_name/year_of`
- Produces:
  - `MissiveWriter.receipt(repo, state, c: Dictionary, stale: bool) -> Dictionary` (a missive, not yet filed)
  - `MissiveWriter.monthly(repo, state, tick: int) -> Dictionary`
  - Every delivery files one receipt, and every month's settlement files one monthly report.

- [ ] **Step 1: Write the failing test** — `tests/engine/test_missive_writer.gd`

```gdscript
extends GutTest
## Receipts and the steward's report (spec 2026-09-28 §1).

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	RoadGraph.forget()
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _marcher() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(repo, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


func _fact(m: Dictionary, key: String) -> Dictionary:
	for f: Dictionary in m["facts"]:
		if String(f["key"]) == key:
			return f
	return {}


func test_a_delivery_files_one_credible_receipt_with_the_regiments_state() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	for day in int(repo.bal("courier_max_days")):
		CourierSystem.ride_day(repo, s)
		if s.couriers.is_empty():
			break
	assert_eq(s.missives.size(), 1)
	var m: Dictionary = s.missives[0]
	assert_eq(String(m["kind"]), "receipt")
	assert_eq(String(m["column"]), "credible")
	assert_eq(String(m["subject"]["code"]), code)
	var st := ArmySystem.state_of(repo, s, code)
	assert_eq(int(_fact(m, "morale")["exact"]), int(st["morale"]))
	assert_eq(int(_fact(m, "supplies")["exact"]), int(st["supplies"]))
	assert_eq(String(_fact(m, "orders")["text"]), "Stand")


func test_a_stale_order_writes_a_receipt_that_says_so() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	s.regiments[code]["order_id"] = 99
	var m := MissiveWriter.receipt(repo, s, {"id": 3, "target": code, "order": {"action_code": "ARMY_GARRISON"},
		"x_m": 0, "y_m": 0}, true)
	assert_string_contains(String(_fact(m, "orders")["text"]), "set aside")


func test_every_settled_month_files_one_steward_report_exact_to_the_economy() -> void:
	var s := GameState.new_campaign(repo, 7)
	var engine := TickEngine.new(repo)
	var tick := s.tick
	var expect := 0
	for code: String in MapManors.controlled_provinces(repo, s):
		expect += int(RealmEconomy.province(repo, s, code)["tax"])
	engine.advance(s)
	var reports: Array = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "monthly")
	assert_eq(reports.size(), 1)
	var m: Dictionary = reports[0]
	assert_eq(String(m["column"]), "truth")
	assert_eq(int(_fact(m, "tax_total")["exact"]), expect, "exact against RealmEconomy for the settled month")
	assert_string_contains(String(m["title"]), Calendar.season_name(tick))
```

**Before relying on the expectation:** check `_settle_economy`. If it changes a province's `tax` figure before the report is written (for example by moving the economy cache on), compute the expectation the same way the report does, at the same point in `advance`. The report must be written right after `_settle_economy`, from the same `RealmEconomy.province` numbers.

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL (`MissiveWriter` not declared; no missive filed).

- [ ] **Step 3: Write `scripts/engine/missive_writer.gd`**

```gdscript
class_name MissiveWriter
extends RefCounted
## The two routine letters (spec 2026-09-28 §1): a courier's delivery receipt
## (highly credible — the regiment's state that day, exact) and the steward's
## monthly report on the provinces the crown controls (ground truth, exact).
## Builds missives; MissiveLog files them.

static func receipt(repo: DataRepository, state: GameState, c: Dictionary, stale: bool) -> Dictionary:
	var code := String(c["target"])
	var reg := ArmySystem.regiment(repo, code)
	var label := String(reg.get("label", code))
	var at := ArmySystem.position_of(repo, state, reg) if not reg.is_empty() else Vector2.ZERO
	var st := ArmySystem.state_of(repo, state, code)
	var order := String((c["order"] as Dictionary).get("action_code", ""))
	var said := "Set aside: newer orders stand" if stale else ("March" if order == "ARMY_MARCH" else "Stand")
	var facts: Array = [MissiveLog.words("orders", "Orders", said)]
	if not st.is_empty():
		facts.append(MissiveLog.exact("morale", "Morale", int(st["morale"])))
		facts.append(MissiveLog.exact("supplies", "Supplies", int(st["supplies"])))
		facts.append(MissiveLog.exact("wounded", "Wounded", int(st["wounded"])))
		facts.append(MissiveLog.words("ground", "Ground", ArmySystem.terrain_of(repo, reg, state).capitalize()))
		facts.append(MissiveLog.words("weather", "Weather",
			Weather.label_of(repo, Weather.at(repo, state, at, state.absolute_day()))))
	return MissiveLog.make("receipt", "credible", state.absolute_day(),
		MissiveLog.subject("regiment", code, -1, at), "Receipt — " + label, facts)


## The settled month's report: each controlled province's tax, goods and
## people, their totals, and the change in tax against the last report.
static func monthly(repo: DataRepository, state: GameState, tick: int) -> Dictionary:
	var facts: Array = []
	var total := 0
	for code: String in MapManors.controlled_provinces(repo, state):
		var p: Dictionary = RealmEconomy.province(repo, state, code)
		var label := String(repo.provinces.get(code, {}).get("label", code))
		var people := RealmEconomy._figure(repo, state, "economy.provinces.%s.rural_population" % code) \
			+ RealmEconomy._figure(repo, state, "economy.provinces.%s.urban_population" % code)
		total += int(p["tax"])
		facts.append(MissiveLog.exact("tax@" + code, "%s — tax" % label, int(p["tax"])))
		facts.append(MissiveLog.exact("strategic@" + code, "%s — strategic goods" % label, int(p["strategic"])))
		facts.append(MissiveLog.exact("civil@" + code, "%s — civil goods" % label, int(p["civil"])))
		facts.append(MissiveLog.exact("people@" + code, "%s — people" % label, people))
	facts.push_front(MissiveLog.exact("tax_total", "Tax, all your provinces", total))
	var last := _last_total(state)
	if last >= 0:
		facts.insert(1, MissiveLog.words("tax_change", "Against last month", "%+d gold" % (total - last)))
	var home := MapManors.home_province(repo, state)
	var prov: Dictionary = repo.provinces.get(home, {})
	var centre := Vector2(float(prov.get("center_x", 0)), float(prov.get("center_y", 0)))
	return MissiveLog.make("monthly", "truth", state.absolute_day(),
		MissiveLog.subject("province", home, -1, centre),
		"Steward's report — %s, Year %d" % [Calendar.season_name(tick), Calendar.year_of(tick)], facts)


static func _last_total(state: GameState) -> int:
	var best := -1
	var best_id := -1
	for m: Dictionary in state.missives:
		if String(m["kind"]) != "monthly" or int(m["id"]) < best_id:
			continue
		for f: Dictionary in m["facts"]:
			if String(f["key"]) == "tax_total":
				best = int(f["exact"])
				best_id = int(m["id"])
	return best
```

- [ ] **Step 4: File them.**
  - In `CourierSystem._deliver`, on BOTH the stale return and the delivered return, file a receipt before returning:

    ```gdscript
    	MissiveLog.add(repo, state, MissiveWriter.receipt(repo, state, c, <true for stale | false>))
    ```

    Put the stale call just before `return _event("stale", c)` and the delivered call just before `return _event("delivered", c)`. Keep every existing line.
  - In `TickEngine.advance`, immediately after `_settle_economy(state, r)`:

    ```gdscript
    	# The steward's report on the month just settled (owner 2026-09-28): ground truth.
    	MissiveLog.add(data, state, MissiveWriter.monthly(data, state, state.tick))
    ```

- [ ] **Step 5: Run the tests.** Run this file, then `tests/engine/test_courier_ride.gd` and `test_courier_orders.gd`: A's tests must still pass, and none of them asserts `missives`. Then run the whole suite. `test_determinism.gd` compares whole-state hashes: if it now differs only because missives exist, both runs still match each other, so it should pass; if not, investigate — do not weaken it.
- [ ] **Step 6: Commit**

```bash
git add scripts/engine/missive_writer.gd scripts/engine/missive_writer.gd.uid scripts/engine/courier_system.gd scripts/engine/tick_engine.gd tests/engine/test_missive_writer.gd tests/engine/test_missive_writer.gd.uid
git commit -m "feat(missives): delivery receipts and the steward's monthly report"
```

---

### Task 3: The `Intel` gate

**Files:**
- Create: `scripts/engine/intel.gd`
- Test: `tests/engine/test_intel.gd`

**Interfaces:**
- Consumes:
  - `MissiveLog` (Task 1)
  - `MapManors.controlled_provinces/province_of/label_of`
  - `MapOwnership.owner_of`
  - `MapEconomy.cell_at`
  - `ArmySystem.metres_per_pack_px`
  - `RealmEconomy.province/_figure`
  - `repo.world_table("political", "diplomacy")`, keyed `"<a>><b>"` with a `stance` field
- Produces:
  - `Intel.dev_all: static bool`, set by GameRoot from DEV MODE
  - `Intel.level(repo, state, subj: Dictionary) -> String` (`full` | `general` | `basic`)
  - `Intel.province_of(repo, state, subj) -> String`
  - `Intel.stance_of(repo, kingdom: String) -> String`
  - `Intel.wealth_tier(repo, state, province: String) -> int` (0 poor, 1 middling, 2 rich)
  - `Intel.wealth_word(repo, tier: int) -> String`
  - `Intel.magnitude(repo, n: int) -> String`
  - `Intel.num(n: int) -> String` ("2,800")
  - `Intel.place_label(repo, state, px: Vector2) -> String`
  - `Intel.fact(repo, state, subj, key: String, exact: Variant) -> Dictionary` `{text, source, day, column}`. Here `exact` is the true value (int, or String for holder / stance / output), and `wealth` is passed as the tier int.

- [ ] **Step 1: Write the failing test** — `tests/engine/test_intel.gd`

```gdscript
extends GutTest
## The knowledge gate (spec 2026-09-28 §1).

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	Intel.dev_all = false


func after_each() -> void:
	Intel.dev_all = false


func _province_where(pred: Callable, s: GameState) -> String:
	var codes := repo.provinces.keys()
	codes.sort()
	for c: String in codes:
		if pred.call(c, s):
			return c
	return ""


func _foreign(s: GameState) -> String:
	return _province_where(func(c: String, st: GameState) -> bool:
		return MapOwnership.owner_of(repo, st, c) != repo.resolve_realm("player_realm"), s)


func _ours_uncontrolled(s: GameState) -> String:
	return _province_where(func(c: String, st: GameState) -> bool:
		return MapOwnership.owner_of(repo, st, c) == repo.resolve_realm("player_realm") \
			and not c in MapManors.controlled_provinces(repo, st), s)


func _subj(code: String) -> Dictionary:
	var p: Dictionary = repo.provinces[code]
	return MissiveLog.subject("province", code, -1, Vector2(float(p["center_x"]), float(p["center_y"])))


func test_three_levels() -> void:
	var s := GameState.new_campaign(repo, 7)
	var home := MapManors.home_province(repo, s)
	assert_eq(Intel.level(repo, s, _subj(home)), "full")
	var ours := _ours_uncontrolled(s)
	if ours != "":
		assert_eq(Intel.level(repo, s, _subj(ours)), "general")
	assert_eq(Intel.level(repo, s, _subj(_foreign(s))), "basic")
	Intel.dev_all = true
	assert_eq(Intel.level(repo, s, _subj(_foreign(s))), "full", "DEV MODE sees everything")


func test_basic_says_little_and_general_says_words() -> void:
	var s := GameState.new_campaign(repo, 7)
	var f := _subj(_foreign(s))
	assert_eq(String(Intel.fact(repo, s, f, "people", 2837)["text"]), "—")
	assert_eq(String(Intel.fact(repo, s, f, "holder", "House Vane")["text"]), "House Vane")
	assert_eq(String(Intel.fact(repo, s, f, "wealth", 2)["text"]), "rich")
	var ours := _ours_uncontrolled(s)
	if ours != "":
		assert_eq(String(Intel.fact(repo, s, _subj(ours), "people", 2837)["text"]), "thousands")


func test_the_newest_report_wins_and_says_where_it_came_from() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _foreign(s)
	var f := _subj(code)
	MissiveLog.add(repo, s, MissiveLog.make("spy", "rumour", 5, f, "old", [MissiveLog.span("people", "People", 1000, 2000)]))
	MissiveLog.add(repo, s, MissiveLog.make("spy", "credible", 9, f, "new", [MissiveLog.span("people", "People", 2800, 3200)]))
	var got := Intel.fact(repo, s, f, "people", 2837)
	assert_eq(String(got["text"]), "≈ 2,800–3,200")
	assert_eq(String(got["column"]), "credible")
	assert_eq(int(got["day"]), 9)
	assert_eq(String(got["source"]), "spy")


func test_a_report_counts_by_distance_for_a_nearby_point() -> void:
	var s := GameState.new_campaign(repo, 7)
	var f := _subj(_foreign(s))
	var near := MissiveLog.subject("point", "", -1, Vector2(float(f["x"]) + 3.0, float(f["y"])))
	MissiveLog.add(repo, s, MissiveLog.make("spy", "credible", 4, near, "near", [MissiveLog.span("people", "People", 500, 700)]))
	assert_eq(String(Intel.fact(repo, s, f, "people", 600)["text"]), "≈ 500–700")


func test_full_knowledge_beats_a_report() -> void:
	var s := GameState.new_campaign(repo, 7)
	var h := _subj(MapManors.home_province(repo, s))
	MissiveLog.add(repo, s, MissiveLog.make("spy", "rumour", 4, h, "x", [MissiveLog.span("people", "People", 1, 2)]))
	var got := Intel.fact(repo, s, h, "people", 2837)
	assert_eq(String(got["text"]), "2,837")
	assert_eq(String(got["column"]), "truth")


func test_words_and_numbers() -> void:
	assert_eq(Intel.num(2837), "2,837")
	assert_eq(Intel.num(512), "512")
	assert_eq(Intel.magnitude(repo, 50), "a handful")
	assert_eq(Intel.magnitude(repo, 500), "hundreds")
	assert_eq(Intel.magnitude(repo, 2500), "thousands")
	assert_eq(Intel.magnitude(repo, 9000), "many thousands")
	assert_eq(Intel.wealth_word(repo, 0), "poor")


func test_the_stance_comes_from_the_packs_diplomacy() -> void:
	var realm := repo.resolve_realm("player_realm")
	assert_eq(Intel.stance_of(repo, realm), "Our realm")
	for key: String in repo.world_table("political", "diplomacy"):
		if key.begins_with(realm + ">"):
			var row: Dictionary = repo.world_table("political", "diplomacy")[key]
			assert_eq(Intel.stance_of(repo, String(row["other_code"])), String(row["stance"]))
			return
```

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL (`Intel` not declared).

- [ ] **Step 3: Write `scripts/engine/intel.gd`**

```gdscript
class_name Intel
extends RefCounted
## The one place that decides what the player knows (owner 2026-09-28, spec
## 2026-09-28-missive-board-and-spies §1). A caller hands over the TRUE value
## and gets back what may be shown: exact for land the crown controls; else
## the newest report's estimate; else, in the player's own realm, a word; else
## (abroad) only who holds it, the stance and a wealth word. DEV MODE
## (dev_all, set by GameRoot) sees everything.

static var dev_all := false

static var _tiers: Dictionary = {}
static var _tiers_key := ""


static func province_of(repo: DataRepository, state: GameState, subj: Dictionary) -> String:
	match String(subj.get("kind", "")):
		"province":
			return String(subj["code"])
		"manor":
			return MapManors.province_of(repo, int(subj["cell"]), state)
		"burg":
			return String((repo.burgs.get(String(subj["code"]), {}) as Dictionary).get("province_code", ""))
	var cell := MapEconomy.cell_at(repo, Vector2(float(subj.get("x", 0)), float(subj.get("y", 0))))
	return MapManors.province_of(repo, cell, state) if cell >= 0 else ""


static func level(repo: DataRepository, state: GameState, subj: Dictionary) -> String:
	if dev_all:
		return "full"
	var realm := repo.resolve_realm("player_realm")
	if String(subj.get("kind", "")) == "regiment":
		var reg := ArmySystem.regiment(repo, String(subj["code"]))
		return "full" if String(reg.get("kingdom_code", "")) == realm else "basic"
	var prov := province_of(repo, state, subj)
	if prov == "":
		return "basic"
	if prov in MapManors.controlled_provinces(repo, state):
		return "full"
	return "general" if MapOwnership.owner_of(repo, state, prov) == realm else "basic"


static func stance_of(repo: DataRepository, kingdom: String) -> String:
	var realm := repo.resolve_realm("player_realm")
	if kingdom == realm:
		return "Our realm"
	var row: Dictionary = repo.world_table("political", "diplomacy").get("%s>%s" % [realm, kingdom], {})
	return String(row.get("stance", "Unknown"))


## 0 poor, 1 middling, 2 rich: the province's tax per person against every
## province's terciles. Cached per pack and month.
static func wealth_tier(repo: DataRepository, state: GameState, province: String) -> int:
	var key := "%s|%d" % [repo.map_id, state.tick if state != null else 0]
	if key != _tiers_key:
		_tiers = {}
		_tiers_key = key
		var rates: Array = []
		var per: Dictionary = {}
		var codes := repo.provinces.keys()
		codes.sort()
		for c: String in codes:
			var people := RealmEconomy._figure(repo, state, "economy.provinces.%s.rural_population" % c) \
				+ RealmEconomy._figure(repo, state, "economy.provinces.%s.urban_population" % c)
			if people <= 0:
				continue
			@warning_ignore("integer_division")  # gold per 1000 people, whole
			var rate := int(RealmEconomy.province(repo, state, c)["tax"]) * 1000 / people
			per[c] = rate
			rates.append(rate)
		rates.sort()
		for c: String in per:
			var i := rates.find(per[c])
			@warning_ignore("integer_division")  # terciles
			_tiers[c] = clampi(i * 3 / maxi(1, rates.size()), 0, 2)
	return int(_tiers.get(province, 1))


static func wealth_word(repo: DataRepository, tier: int) -> String:
	var tiers: PackedStringArray = (repo.intel_facts.get("wealth", {}) as Dictionary).get("tiers", PackedStringArray())
	return tiers[clampi(tier, 0, tiers.size() - 1)] if not tiers.is_empty() else str(tier)


static func magnitude(repo: DataRepository, n: int) -> String:
	if n < int(repo.bal("intel_magnitude_hundreds")):
		return "a handful"
	if n < int(repo.bal("intel_magnitude_thousands")):
		return "hundreds"
	if n < int(repo.bal("intel_magnitude_many")):
		return "thousands"
	return "many thousands"


static func num(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	while s.length() > 3:
		out = "," + s.substr(s.length() - 3) + out
		s = s.substr(0, s.length() - 3)
	return ("-" if n < 0 else "") + s + out


static func place_label(repo: DataRepository, state: GameState, px: Vector2) -> String:
	var cell := MapEconomy.cell_at(repo, px)
	if cell < 0 or not MapManors.is_manor(repo, cell):
		return "the open sea"
	var prov := MapManors.province_of(repo, cell, state)
	return "%s (%s)" % [MapManors.label_of(repo, cell), String(repo.provinces.get(prov, {}).get("label", prov))]


## What may be shown of one fact about a subject.
static func fact(repo: DataRepository, state: GameState, subj: Dictionary, key: String,
		exact: Variant) -> Dictionary:
	var lvl := level(repo, state, subj)
	var today := state.absolute_day() if state != null else 0
	if lvl == "full":
		return {"text": _show(repo, key, exact), "source": "own records", "day": today, "column": "truth"}
	var m := _latest(repo, state, subj, key)
	if not m.is_empty():
		return {"text": _from_fact(m["fact"]), "source": String(m["kind"]), "day": int(m["day"]),
			"column": String(m["column"])}
	if key in ["holder", "stance", "wealth"]:
		return {"text": _show(repo, key, exact), "source": "common knowledge", "day": today, "column": ""}
	if lvl == "general" and exact is int:
		return {"text": magnitude(repo, int(exact)), "source": "common knowledge", "day": today, "column": ""}
	return {"text": "—", "source": "", "day": today, "column": ""}


static func _show(repo: DataRepository, key: String, v: Variant) -> String:
	if key == "wealth":
		return wealth_word(repo, int(v))
	return num(int(v)) if v is int else String(v)


static func _from_fact(f: Dictionary) -> String:
	if f.has("exact"):
		return num(int(f["exact"]))
	if f.has("lo"):
		return "≈ %s–%s" % [num(int(f["lo"])), num(int(f["hi"]))]
	return String(f.get("text", "—"))


## The newest letter carrying `key` about this subject: the same manor cell,
## else the same province, else a point within intel_match_km.
static func _latest(repo: DataRepository, state: GameState, subj: Dictionary, key: String) -> Dictionary:
	if state == null:
		return {}
	var prov := province_of(repo, state, subj)
	var reach := repo.bal("intel_match_km") * 1000.0 / float(ArmySystem.metres_per_pack_px(repo))
	var here := Vector2(float(subj.get("x", 0)), float(subj.get("y", 0)))
	var best: Dictionary = {}
	for m: Dictionary in state.missives:
		if not best.is_empty() and int(m["id"]) < int(best["id"]):
			continue
		var f: Dictionary = {}
		for x: Dictionary in m["facts"]:
			if String(x["key"]) == key:
				f = x
		if f.is_empty():
			continue
		var ms: Dictionary = m["subject"]
		var hit := false
		if String(subj.get("kind", "")) == "manor" and int(ms.get("cell", -1)) == int(subj.get("cell", -2)):
			hit = true
		elif prov != "" and province_of(repo, state, ms) == prov and String(subj.get("kind", "")) == "province":
			hit = true
		elif here.distance_to(Vector2(float(ms.get("x", 0)), float(ms.get("y", 0)))) <= reach:
			hit = true
		if hit:
			best = {"id": int(m["id"]), "kind": String(m["kind"]), "day": int(m["day"]),
				"column": String(m["column"]), "fact": f}
	return best
```

- [ ] **Step 4: Run the test.** Expected: PASS. If `_ours_uncontrolled` finds no province on this pack (the crown controls the whole realm), the `general` asserts are skipped by the guards; say so in the report.
- [ ] **Step 5: Commit**

```bash
git add scripts/engine/intel.gd scripts/engine/intel.gd.uid tests/engine/test_intel.gd tests/engine/test_intel.gd.uid
git commit -m "feat(intel): the knowledge gate — full, general, basic, and the newest report"
```

---

### Task 4: Spy couriers, their reports, and `SPY_SEND`

**Files:**
- Create: `scripts/engine/spy_system.gd`
- Modify:
  - `scripts/engine/courier_system.gd` (`dispatch_spy`; `_ride` handles a spy; `headline` for spy events)
  - `scripts/engine/courier_card.gd` (a spy's card)
  - `scripts/engine/action_system.gd` (validate and execute `SPY_SEND`)
  - `data/policy_actions_court_additions.csv`, `data/action_signatures.csv`, `data/order_costs.csv` (a `SPY_SEND` row each)
- Test: `tests/engine/test_spy_system.gd`

**Interfaces:**
- Consumes: Tasks 1–3; A's `CourierSystem.path_between/origin/day_budget`; `ArmySystem.position_of/headcount/metres_per_pack_px/pack_to_metres/metres_to_pack`; `MapEconomy.burg_cells`.
- Produces:
  - `CourierSystem.SPY := "spy"`
  - `CourierSystem.dispatch_spy(repo, state, to_px: Vector2) -> Dictionary`. The courier has `kind "spy"`, `target ""`, and `order {action_code: "SPY_SEND", x_m, y_m}`.
  - `SpySystem.quality(repo, state, at: Vector2, roll: int) -> int` (0..999)
  - `SpySystem.estimate(repo, v: int, q: int, bias: int, round_to: int) -> Array` `[lo, hi]`
  - `SpySystem.report(repo, state, at: Vector2, q: int, bias: int) -> Dictionary` (the missive; pure)
  - `SpySystem.observe(repo, state, c) -> Dictionary`, which draws the rolls, files the report, and returns the event `{type: "spy_report", courier, missive, regiment: "", place}`
  - `ActionSystem` `SPY_SEND {x, y}`

- [ ] **Step 1: Write the failing test** — `tests/engine/test_spy_system.gd`

```gdscript
extends GutTest
## Spies (spec 2026-09-28 §1). Rolls are forced through SpySystem.report's
## q and bias; observe's own draw is checked for determinism only.

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	RoadGraph.forget()
	Weather.forget()
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}


func after_all() -> void:
	RoadGraph.forget()


## A foreign manor with people and no town in it (no walls to shift the roll).
func _foreign_manor(s: GameState) -> int:
	var realm := repo.resolve_realm("player_realm")
	var towns := MapEconomy.burg_cells(repo)
	var ids := repo.manors.keys()
	ids.sort()
	for id: int in ids:
		if MapOwnership.owner_of(repo, s, MapManors.province_of(repo, id, s)) != realm \
				and not towns.has(id) and int(RealmEconomy.line_of(repo, s, id)["people"]) >= 500:
			return id
	return -1


## A manor of the crown's home province with no town in it.
func _home_plain(s: GameState) -> int:
	var towns := MapEconomy.burg_cells(repo)
	for id in MapManors.manors_of_province(repo, MapManors.home_province(repo, s)):
		if not towns.has(int(id)):
			return int(id)
	return -1


func _at(id: int) -> Vector2:
	return MapTerrain.cell_center(repo, repo.cells[id])


func _fact(m: Dictionary, key: String) -> Dictionary:
	for f: Dictionary in m["facts"]:
		if String(f["key"]) == key:
			return f
	return {}


func test_an_estimate_by_hand() -> void:
	# q 1000 -> half-width 100‰; q 0 -> 450‰ (spy_width_best/worst).
	assert_eq(SpySystem.estimate(repo, 3000, 1000, 0, 100), [2700, 3300])
	assert_eq(SpySystem.estimate(repo, 3000, 0, 0, 100), [1600, 4400], "450‰ of 3000 = 1350, rounded out")
	# q 500 -> 100 + 350*500/1000 = 275‰ -> half 825; bias +200‰ -> centre 3600;
	# 2775 floors to 2700, 4425 ceils to 4500.
	assert_eq(SpySystem.estimate(repo, 3000, 500, 200, 100), [2700, 4500])
	# q 0 -> 450‰ of 100 = 45; bias −300‰ -> centre 70; 25 floors to 0, 115 ceils to 200.
	assert_eq(SpySystem.estimate(repo, 100, 0, -300, 100), [0, 200], "never below zero")


func test_quality_follows_the_place() -> void:
	var s := GameState.new_campaign(repo, 7)
	var f := _foreign_manor(s)
	assert_eq(SpySystem.quality(repo, s, _at(f), 600), 450, "foreign −150, clear weather")
	assert_eq(SpySystem.quality(repo, s, _at(_home_plain(s)), 600), 750, "home +150")
	assert_eq(SpySystem.quality(repo, s, _at(f), 10), 0, "clamped at 0")


func test_the_column_and_the_facts() -> void:
	var s := GameState.new_campaign(repo, 7)
	var f := _foreign_manor(s)
	var line := RealmEconomy.line_of(repo, s, f)
	var good := SpySystem.report(repo, s, _at(f), 800, 0)
	assert_eq(String(good["column"]), "credible")
	assert_eq(String(good["subject"]["kind"]), "manor")
	var p := _fact(good, "people")
	assert_true(int(p["lo"]) <= int(line["people"]) and int(line["people"]) <= int(p["hi"]), "true value inside")
	assert_eq(String(_fact(good, "holder")["text"]), "House " + MapManors.owner_of(repo, s, f))
	var bad := SpySystem.report(repo, s, _at(f), 200, 300)
	assert_eq(String(bad["column"]), "rumour")
	assert_eq(String(_fact(bad, "holder")["text"]), "unclear", "below spy_text_threshold")


func test_troops_near_the_point_split_own_and_foreign() -> void:
	var s := GameState.new_campaign(repo, 7)
	var reg: Dictionary = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))[0]
	var at := ArmySystem.position_of(repo, s, reg)
	var m := SpySystem.report(repo, s, at, 1000, 0)
	var own := _fact(m, "troops_own")
	assert_true(int(own["hi"]) >= ArmySystem.headcount(repo, reg), "our own regiment is counted")


func test_a_spy_at_sea_reports_troops_only() -> void:
	var s := GameState.new_campaign(repo, 7)
	var wet := Vector2(1.0, 1.0)
	if MapEconomy.cell_at(repo, wet) >= 0:
		return
	var m := SpySystem.report(repo, s, wet, 700, 0)
	assert_eq(_fact(m, "people"), {})
	assert_false(_fact(m, "troops_foreign").is_empty())
	assert_string_contains(String(m["title"]), "open sea")


func test_two_spies_can_disagree() -> void:
	var s := GameState.new_campaign(repo, 7)
	var f := _foreign_manor(s)
	assert_ne(JSON.stringify(SpySystem.report(repo, s, _at(f), 900, 0)["facts"]),
		JSON.stringify(SpySystem.report(repo, s, _at(f), 150, -250)["facts"]))


func test_send_ride_arrive_file() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var f := _foreign_manor(s)
	var req := ActionRequest.make("SPY_SEND", {"x": _at(f).x, "y": _at(f).y})
	assert_eq(actions.validate(req, s), "")
	var before: float = s.metrics["treasury"]
	actions.execute(req, s)
	assert_eq(s.couriers.size(), 1)
	assert_eq(String(s.couriers[0]["kind"]), "spy")
	assert_lt(float(s.metrics["treasury"]), before)
	var got: Array = []
	for day in int(repo.bal("courier_max_days")):
		got.append_array(CourierSystem.ride_day(repo, s))
		if s.couriers.is_empty():
			break
	var reports := got.filter(func(e: Dictionary) -> bool: return String(e["type"]) == "spy_report")
	assert_eq(reports.size(), 1)
	var m := MissiveLog.find(s, int(reports[0]["missive"]))
	assert_eq(String(m["kind"]), "spy")
	assert_true(String(m["column"]) in ["credible", "rumour"])
	assert_string_contains(CourierSystem.headline(repo, reports[0]), "spy")


func test_a_thin_chest_cannot_send_a_spy() -> void:
	var s := GameState.new_campaign(repo, 7)
	var f := _foreign_manor(s)
	s.metrics["treasury"] = float(CourierSystem.fee_gold(repo, CourierSystem.SPY)) - 0.5
	assert_ne(ActionSystem.new(repo).validate(ActionRequest.make("SPY_SEND", {"x": _at(f).x, "y": _at(f).y}), s), "")
```

The hand values follow the formula in Step 3 exactly. The formula is the contract: if a value disagrees with it, recompute and correct the value; never bend the formula to fit.

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL (`SpySystem` not declared).

- [ ] **Step 3: Write `scripts/engine/spy_system.gd`**

```gdscript
class_name SpySystem
extends RefCounted
## Spies (owner 2026-09-28, spec 2026-09-28-missive-board-and-spies §1): a
## spy courier's arrival becomes a report. One quality roll per mission from
## GameState.rng, shifted by the place (data/spy_difficulty.csv), decides the
## column — highly credible or rumour — and how wide and how biased every
## estimate is. Two spies to one place draw different rolls: their reports differ.

static func quality(repo: DataRepository, state: GameState, at: Vector2, roll: int) -> int:
	var q := roll
	var realm := repo.resolve_realm("player_realm")
	var cell := MapEconomy.cell_at(repo, at)
	var prov := MapManors.province_of(repo, cell, state) if cell >= 0 else ""
	if prov != "" and MapOwnership.owner_of(repo, state, prov) == realm:
		q += int(repo.spy_difficulty.get("home", 0))
	else:
		q += int(repo.spy_difficulty.get("foreign", 0))
	if cell >= 0 and _walled(repo, cell):
		q += int(repo.spy_difficulty.get("walled", 0))
	q += int(repo.spy_difficulty.get("weather_" + Weather.at(repo, state, at, state.absolute_day()), 0))
	return clampi(q, 0, 999)


static func _walled(repo: DataRepository, cell: int) -> bool:
	var burg := String(MapEconomy.burg_cells(repo).get(cell, ""))
	if burg == "":
		return false
	var feats := String((repo.burgs.get(burg, {}) as Dictionary).get("features", "")).split("|")
	return "walls" in feats or "citadel" in feats


## [lo, hi] around the true value v: half-width by quality, centre moved by
## bias (per mille of v), rounded OUT to round_to, lo never below zero.
static func estimate(repo: DataRepository, v: int, q: int, bias: int, round_to: int) -> Array:
	var best := int(repo.bal("spy_width_best"))
	var worst := int(repo.bal("spy_width_worst"))
	@warning_ignore("integer_division")  # whole per mille
	var width := best + (worst - best) * (1000 - clampi(q, 0, 1000)) / 1000
	@warning_ignore("integer_division")  # whole heads / gold
	var half := v * width / 1000
	@warning_ignore("integer_division")
	var centre := v + v * bias / 1000
	var r := maxi(1, round_to)
	var lo := maxi(0, int(floor(float(centre - half) / float(r))) * r)
	var hi := int(ceil(float(centre + half) / float(r))) * r
	return [lo, maxi(lo, hi)]


static func _round_to(repo: DataRepository, key: String) -> int:
	return int((repo.intel_facts.get(key, {}) as Dictionary).get("round_to", 1))


static func _label(repo: DataRepository, key: String) -> String:
	return String((repo.intel_facts.get(key, {}) as Dictionary).get("label", key))


## The report a spy at `at` files for quality q and bias (per mille). Pure.
static func report(repo: DataRepository, state: GameState, at: Vector2, q: int, bias: int) -> Dictionary:
	var credible := q >= int(repo.bal("spy_credible_threshold"))
	var sees_words := q >= int(repo.bal("spy_text_threshold"))
	var facts: Array = []
	var cell := MapEconomy.cell_at(repo, at)
	var subj := MissiveLog.subject("point", "", -1, at)
	if cell >= 0 and MapManors.is_manor(repo, cell):
		subj = MissiveLog.subject("manor", MapManors.code_of(repo, cell), cell, at)
		var line := RealmEconomy.line_of(repo, state, cell)
		for key in ["people", "tax"]:
			var lh := estimate(repo, int(line[key]), q, bias, _round_to(repo, key))
			facts.append(MissiveLog.span(key, _label(repo, key), int(lh[0]), int(lh[1])))
		var units := estimate(repo, int(line.get("units", 0)), q, bias, _round_to(repo, "output"))
		facts.append(MissiveLog.span("output", _label(repo, "output"), int(units[0]), int(units[1])))
		var prov := MapManors.province_of(repo, cell, state)
		var holder := MapManors.owner_of(repo, state, cell)
		facts.append(MissiveLog.words("holder", _label(repo, "holder"),
			("House " + holder) if sees_words and holder != "" else "unclear"))
		facts.append(MissiveLog.words("stance", _label(repo, "stance"),
			Intel.stance_of(repo, MapOwnership.owner_of(repo, state, prov)) if sees_words else "unclear"))
		facts.append(MissiveLog.words("wealth", _label(repo, "wealth"),
			Intel.wealth_word(repo, Intel.wealth_tier(repo, state, prov)) if sees_words else "unclear"))
	var troops := _troops(repo, state, at)
	for key in ["troops_own", "troops_foreign"]:
		var tl := estimate(repo, int(troops[key]), q, bias, _round_to(repo, key))
		facts.append(MissiveLog.span(key, _label(repo, key), int(tl[0]), int(tl[1])))
	return MissiveLog.make("spy", "credible" if credible else "rumour", state.absolute_day(), subj,
		"Spy report — " + Intel.place_label(repo, state, at), facts)


## Heads within spy_radius_km of a point: ours (live positions) and foreign
## (the pack's rows, which stand still until enemy AI exists).
static func _troops(repo: DataRepository, state: GameState, at: Vector2) -> Dictionary:
	var reach := repo.bal("spy_radius_km") * 1000.0 / float(ArmySystem.metres_per_pack_px(repo))
	var realm := repo.resolve_realm("player_realm")
	var own := 0
	var foreign := 0
	var codes := repo.world_table("military", "regiments").keys()
	codes.sort()
	for code: String in codes:
		var reg: Dictionary = repo.world_table("military", "regiments")[code]
		if ArmySystem.position_of(repo, state, reg).distance_to(at) > reach:
			continue
		if String(reg.get("kingdom_code", "")) == realm:
			own += ArmySystem.headcount(repo, reg)
		else:
			foreign += ArmySystem.headcount(repo, reg)
	return {"troops_own": own, "troops_foreign": foreign}


## A spy has arrived: draw his rolls (quality, then — for a rumour — the
## bias), file the report, and say so for the news bar and GameRoot.
static func observe(repo: DataRepository, state: GameState, c: Dictionary) -> Dictionary:
	var at := ArmySystem.metres_to_pack(repo, Vector2i(int(c["x_m"]), int(c["y_m"])))
	var q := quality(repo, state, at, state.rng.randi_range(0, 999))
	var bias := 0
	if q < int(repo.bal("spy_credible_threshold")):
		var most := int(repo.bal("spy_bias_max"))
		bias = state.rng.randi_range(-most, most)
	var id := MissiveLog.add(repo, state, report(repo, state, at, q, bias))
	return {"type": "spy_report", "courier": int(c["id"]), "missive": id, "regiment": "",
		"place": Intel.place_label(repo, state, at), "weather": ""}
```

**Verify two assumptions:**
- `MapEconomy.burg_cells(repo)` returns cell → burg code; `ArmySystem.is_fortified` uses it the same way. Mirror its exact use.
- `MapManors.code_of` exists (map_manors.gd ~:45).

- [ ] **Step 4: Spies in `CourierSystem`.** Add:

```gdscript
const SPY := "spy"


## A spy bound for a point (spec 2026-09-28 §1): A's courier, whose target is
## the point itself; his road is set once and never re-aimed.
static func dispatch_spy(repo: DataRepository, state: GameState, to_px: Vector2) -> Dictionary:
	var from := origin(repo, state)
	var home := ArmySystem.pack_to_metres(repo, from)
	var aim := ArmySystem.pack_to_metres(repo, to_px)
	state.next_courier_id += 1
	var c := {
		"id": state.next_courier_id, "kind": SPY, "x_m": home.x, "y_m": home.y,
		"path": path_between(repo, from, to_px), "target": "",
		"order": {"action_code": "SPY_SEND", "x_m": aim.x, "y_m": aim.y},
		"issued": state.absolute_day(), "aim_x_m": aim.x, "aim_y_m": aim.y,
		"days": 0, "day_m": 0, "slow_spell": -1,
	}
	state.couriers.append(c)
	return c
```

In `_ride`:
- Guard the lost check and `_reaim` so they run only for non-spies:
  - `if String(c["kind"]) != SPY and (reg.is_empty() or …)`;
  - `if String(c["kind"]) != SPY: _reaim(...)`.
- Add `e["place"] = Intel.place_label(repo, ArmySystem.metres_to_pack(repo, Vector2i(int(c["aim_x_m"]), int(c["aim_y_m"]))))` to a spy's `set_out` event. Pass `state` too, since `place_label` takes `(repo, state, px)`.
- Where the path empties, file the spy's report instead of delivering:

  ```gdscript
  	if path.is_empty():
  		events.append(SpySystem.observe(repo, state, c) if String(c["kind"]) == SPY else _deliver(repo, state, c))
  		return false
  ```

In `headline`:
```gdscript
		"spy_report":
			return "The spy at %s reports." % String(e.get("place", "the place"))
```
And in the `set_out` arm, when `String(e.get("place", "")) != ""`, return `"A spy leaves the capital for %s." % e["place"]` (or `"A spy rides for %s."` when `capital` is 0).

`CourierCard.card` / `title` for a spy:
- title `"Spy bound for " + Intel.place_label(...)` at the aim point;
- the "Carrying" field `"A spy's errand"`;
- the subtitle `"Spy of <realm>"`.

Branch on `String(c["kind"]) == CourierSystem.SPY` at the top of `title` and in `card`. Keep the other fields: Ordered, Arrives, Ground, Weather.

- [ ] **Step 5: The order.** Add data rows:
  - `data/policy_actions_court_additions.csv`: copy the `ARMY_MARCH` row's columns with
    - `SPY_SEND,military,Send a spy,none,1.0,none,0,0,,spy_send,12,no,no,"params: x, y (pack px of any point on the map). A spy rides from the capital by the road network (CourierSystem.dispatch_spy) and on arrival files a report on the Missive board — highly credible or rumour by his quality roll (SpySystem)."`
  - `data/action_signatures.csv`: `SPY_SEND,,0,5,0,0,0,eyes on another's land`
  - `data/order_costs.csv`: `SPY_SEND,gold:-1:the spy's purse for the road,1,his fee is the courier_kinds spy row`

In `ActionSystem.validate`'s match, add:
```gdscript
		"SPY_SEND":
			var to := Vector2(float(req.params.get("x", -1.0)), float(req.params.get("y", -1.0)))
			var w := float(data.map_info.get("width", "0"))
			var h := float(data.map_info.get("height", "0"))
			if to.x < 0.0 or to.y < 0.0 or (w > 0.0 and to.x > w) or (h > 0.0 and to.y > h):
				return "That is off the map"
			if float(state.metrics["treasury"]) < needs + float(CourierSystem.fee_gold(data, CourierSystem.SPY)):
				return "The chancery cannot pay a spy to ride"
```

In `execute`:
```gdscript
		"SPY_SEND":
			var to := Vector2(float(req.params["x"]), float(req.params["y"]))
			var place := Intel.place_label(data, state, to)
			var c := CourierSystem.dispatch_spy(data, state, to)
			_apply(state, effects, "treasury", -float(CourierSystem.fee_gold(data, CourierSystem.SPY)),
				"a spy rides for " + place)
			var days := CourierSystem.days_left(data, state, c)
			effects.append({"metric": "intel", "delta": 0.0,
				"reason": "A spy rides for %s; about %d day%s" % [place, days, "" if days == 1 else "s"]})
```

Check how `needs` is named in `validate` and use that variable. Check whether `effects` entries with a metric not in `state.metrics` are fine: the `army` entries already do this with `delta 0.0`.

- [ ] **Step 6: Run the tests.** Run `test_spy_system.gd`, `test_courier_ride.gd`, `test_courier_dispatch.gd`, `test_courier_card.gd` and `test_action_system.gd`, then the whole suite. If the suite has a test that every action code has a signature, cost and catalog row, it now covers `SPY_SEND` — keep it green.
- [ ] **Step 7: Commit**

```bash
git add scripts/engine/spy_system.gd scripts/engine/spy_system.gd.uid scripts/engine/courier_system.gd scripts/engine/courier_card.gd scripts/engine/action_system.gd data/policy_actions_court_additions.csv data/action_signatures.csv data/order_costs.csv tests/engine/test_spy_system.gd tests/engine/test_spy_system.gd.uid
git commit -m "feat(spies): spy couriers ride to a point and file a report of honest uncertainty"
```

---

### Task 5: The fog on the cards

**Files:**
- Modify:
  - `scripts/engine/map_objects.gd` (`province_card` ~:421, `manor_card` ~:510, `burg_card` ~:386, `_kingdom_lines` ~:197, `army_card` ~:940)
  - `scripts/ui/map_detail_panel.gd` (`show_card`: the `known` switch ~:348, and render `card["intel"]` rows)
- Test: `tests/engine/test_fog_cards.gd`; update `tests/engine/test_map_objects.gd` and `tests/ui/test_map_detail_panel.gd` where they pin foreign cards

**Interfaces:**
- Consumes: `Intel.level/fact/stance_of/wealth_tier/magnitude/num` (Task 3).
- Produces:
  - Every land card's `known` becomes `Intel.level(...)`.
  - A card that is not `full` carries `card["intel"] = Array of {label, text, tag, column}`. Its tag is `"<source> · <date>"`, or `""` for common knowledge.
  - Foreign and general cards never carry exact people, tax, wealth or treasury.

- [ ] **Step 1: Write the failing test** — `tests/engine/test_fog_cards.gd`

```gdscript
extends GutTest
## The fog on the cards (spec 2026-09-28 §1 "Closing the leaks").

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	Intel.dev_all = false


func _foreign_manor(s: GameState) -> int:
	var realm := repo.resolve_realm("player_realm")
	var ids := repo.manors.keys()
	ids.sort()
	for id: int in ids:
		if MapOwnership.owner_of(repo, s, MapManors.province_of(repo, id, s)) != realm \
				and int(RealmEconomy.line_of(repo, s, id)["people"]) >= 500:
			return id
	return -1


## Every string anywhere in a card, flattened.
func _texts(v: Variant) -> String:
	if v is Dictionary:
		var out := ""
		for k in v:
			out += " " + _texts(v[k])
		return out
	if v is Array:
		var out := ""
		for x in v:
			out += " " + _texts(x)
		return out
	return str(v)


func _leaks(text: String, n: int) -> bool:
	return n >= 100 and (text.contains(str(n)) or text.contains(Intel.num(n)))


func test_a_foreign_manor_card_shows_no_true_figures() -> void:
	var s := GameState.new_campaign(repo, 7)
	var cell := _foreign_manor(s)
	var line := RealmEconomy.line_of(repo, s, cell)
	var card := MapObjects.manor_card(repo, s, cell)
	assert_eq(String(card["known"]), "basic")
	var t := _texts(card)
	assert_false(_leaks(t, int(line["people"])), "people")
	assert_false(card.has("intel") and _leaks(_texts(card["intel"]), int(line["tax"])), "tax")
	assert_true(card.has("intel"))


func test_a_foreign_burg_card_is_fogged() -> void:
	var s := GameState.new_campaign(repo, 7)
	var realm := repo.resolve_realm("player_realm")
	for code: String in repo.burgs:
		var b: Dictionary = repo.burgs[code]
		if MapOwnership.owner_of(repo, s, String(b["province_code"])) == realm:
			continue
		var card := MapObjects.burg_card(repo, s, code)
		assert_ne(String(card["known"]), "full")
		assert_false(_leaks(_texts(card), int(float(b.get("population", 0)))), "population of " + code)
		assert_eq(float(card.get("wealth", 0.0)), 0.0)
		assert_eq(float(card.get("treasury", 0.0)), 0.0)
		return


func test_a_report_shows_up_on_the_card_with_its_tag() -> void:
	var s := GameState.new_campaign(repo, 7)
	var cell := _foreign_manor(s)
	var at := MapTerrain.cell_center(repo, repo.cells[cell])
	MissiveLog.add(repo, s, SpySystem.report(repo, s, at, 900, 0))
	var card := MapObjects.manor_card(repo, s, cell)
	var people: Dictionary = (card["intel"] as Array).filter(
		func(r: Dictionary) -> bool: return String(r["label"]) == "People")[0]
	assert_string_contains(String(people["text"]), "≈")
	assert_string_contains(String(people["tag"]), "spy")
	assert_eq(String(people["column"]), "credible")


func test_our_own_land_is_still_exact() -> void:
	var s := GameState.new_campaign(repo, 7)
	var home := MapManors.home_province(repo, s)
	var cell := int(MapManors.manors_of_province(repo, home)[0])
	assert_eq(String(MapObjects.manor_card(repo, s, cell)["known"]), "full")
	assert_eq(String(MapObjects.province_card(repo, s, home)["known"]), "full")


func test_a_foreign_kingdoms_population_is_a_word() -> void:
	var s := GameState.new_campaign(repo, 7)
	var realm := repo.resolve_realm("player_realm")
	for k: String in repo.kingdoms:
		if k == realm:
			continue
		var lines := "\n".join(MapObjects._kingdom_lines(repo, k, s))
		var pop := int(float(repo.kingdoms[k].get("population", 0)))
		assert_false(_leaks(lines, pop), k)
		return


func test_dev_mode_lifts_the_fog() -> void:
	var s := GameState.new_campaign(repo, 7)
	Intel.dev_all = true
	assert_eq(String(MapObjects.manor_card(repo, s, _foreign_manor(s))["known"]), "full")
	Intel.dev_all = false
```

Check `_kingdom_lines`' real signature (map_objects.gd ~:197) and call it as it is. If it is `(repo, code)` without state, give it an optional `state: GameState = null` and pass state here.

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL (cards still leak and have no `intel` key).

- [ ] **Step 3: Implement.** In `map_objects.gd`, add a helper beside `_stat`:

```gdscript
## The rows a fogged card shows (spec 2026-09-28): each fact through Intel,
## tagged with where it came from.
static func _intel_rows(repo: DataRepository, state: GameState, subj: Dictionary, facts: Array) -> Array:
	var rows: Array = []
	for f: Array in facts:  # [key, label, true value]
		var got := Intel.fact(repo, state, subj, String(f[0]), f[2])
		var tag := ""
		if String(got["column"]) != "" and String(got["source"]) != "own records":
			tag = "%s · %s" % [String(got["source"]), CourierCard.date_of(int(got["day"]))]
		rows.append({"label": String(f[1]), "text": String(got["text"]), "tag": tag,
			"column": String(got["column"])})
	return rows
```

**`province_card`:**
- Set `"known": Intel.level(repo, state, MissiveLog.subject("province", code, -1, centre))`, where `centre` is the card's `center`.
- Where it now does `if card["known"] == "basic": return card`, make it `if card["known"] != "full":`.
- Before returning, set `card["intel"] = _intel_rows(repo, state, subj, facts)` with these facts:

  ```gdscript
  [["people", "People", <urban + rural as int, or int(prov.population)>],
   ["wealth", "Wealth", Intel.wealth_tier(repo, state, code)],
   ["stance", "Stance", Intel.stance_of(repo, owner)]]
  ```

**`manor_card`:**
- Use the same `known` rule, with subject `MissiveLog.subject("manor", code, cell, center)`.
- In the non-`full` branch (keeping its BUY action), before `return card`, add the intel rows:
  - people and tax from `ManorEconomy.line_of(repo, state, cell, state.tick)`;
  - output from the line's `units`;
  - wealth from the province tier;
  - stance.

**`burg_card`:**
- Set `known` from `Intel.level` of its province (subject `burg`).
- When it is not `full`:
  - drop `production`, and set `wealth` and `treasury` to 0.0;
  - replace the Population field text with `Intel.fact(...)["text"]`;
  - add the intel rows (people, wealth, stance).

**`_kingdom_lines`:** for a kingdom that is not the player's realm, and when `Intel.dev_all` is false:
- `"Population: %s" % Intel.magnitude(repo, pop)`;
- add `"Stance: %s" % Intel.stance_of(repo, code)`.

Keep the province and town counts: the borders and towns are drawn on the map for all to see. That is a deliberate deviation from spec §1's "magnitude words"; list it in the report.

**`army_card`:** for a regiment `Intel.level` gives `basic` (a foreign one, seen only in dev mode, which reads `full` anyway), replace the per-arm stats with one stat `_stat("army_total", Intel.magnitude(repo, total), "Headcount — " + Intel.magnitude(repo, total))`.

**`map_detail_panel.gd` `show_card`:**
- `var basic := known == "basic"` becomes `var basic := known in ["basic", "general"]`.
- After the fields and stats, render intel rows:

  ```gdscript
  	for row: Dictionary in card.get("intel", []):
  		_fields.add_child(_line(String(row["label"]), UiPalette.TEXT_MUTED))
  		var value := _line(String(row["text"]), UiPalette.TEXT_SOFT)
  		if String(row["tag"]) != "":
  			value.text += "  (%s)" % String(row["tag"])
  			value.add_theme_color_override("font_color",
  				MapPalette.named(Game.data, "intel_" + String(row["column"])))
  		_fields.add_child(value)
  ```

- In the basic branch, set the hint only when `card.get("intel", []).is_empty()`.

- [ ] **Step 4: Run.** Run `test_fog_cards.gd`, `test_map_objects.gd`, `test_map_detail_panel.gd` and `test_country_panel.gd` (if it exists), then the whole suite. Where an existing test pinned a foreign card's exact fields or a burg's full knowledge, update it to the fogged truth and list every such change in the report with its reason.
- [ ] **Step 5: Commit**

```bash
git add scripts/engine/map_objects.gd scripts/ui/map_detail_panel.gd tests/engine/test_fog_cards.gd tests/engine/test_fog_cards.gd.uid <every test file you updated>
git commit -m "feat(intel): the fog on the cards — foreign and unheld land shows what is known"
```

---

### Task 6: The fog on the panels, and a behavioural leak test

**Files:**
- Modify:
  - `scripts/ui/military_panel.gd` (neighbours ~:129–141)
  - `scripts/ui/manor_master_panel.gd` (`refresh` ~:173)
  - `scripts/map3d/map3d_hud_badges.gd` (`_cut` ~:43)
- Test: `tests/ui/test_fog_panels.gd`

**Interfaces:**
- Consumes: `Intel` (Task 3).
- Produces: none new.

- [ ] **Step 1: Write the failing test** — `tests/ui/test_fog_panels.gd`

```gdscript
extends GutTest
## No panel shows a true figure about land the crown does not control
## (spec 2026-09-28 §1 "Closing the leaks").

func before_each() -> void:
	Game.start_campaign(42)
	Intel.dev_all = false


func _all_text(n: Node) -> String:
	var out := ""
	if n is Label:
		out += " " + (n as Label).text
	if n is Button:
		out += " " + (n as Button).text
	if "tooltip_text" in n:
		out += " " + String(n.get("tooltip_text"))
	for c in n.get_children():
		out += _all_text(c)
	return out


func test_the_neighbours_are_not_counted_for_you() -> void:
	var p := MilitaryPanel.new()
	add_child_autofree(p)
	p.refresh()
	await wait_frames(1)
	var text := _all_text(p)
	var realm := Game.data.resolve_realm("player_realm")
	for code: String in String(Game.data.kingdoms[realm].get("neighbor_codes", "")).split("|", false):
		var total := 0
		for u: String in Game.data.world_table("military", "unit_types"):
			var v: Variant = WorldLedger.value_of(Game.data, Game.state, "military.kingdoms.%s.%s" % [code, u])
			total += int(float(v)) if v != null else 0
		if total >= 100:
			assert_false(text.contains(str(total)) or text.contains(Intel.num(total)), code)


func test_the_manor_master_shows_no_foreign_figures() -> void:
	var p := ManorMasterPanel.new()
	add_child_autofree(p)
	p.set_scope(true)
	p.refresh()
	await wait_frames(1)
	var text := _all_text(p)
	var realm := Game.data.resolve_realm("player_realm")
	var ids := Game.data.manors.keys()
	ids.sort()
	var checked := 0
	for id: int in ids:
		if MapOwnership.owner_of(Game.data, Game.state, MapManors.province_of(Game.data, id, Game.state)) == realm:
			continue
		var people := int(RealmEconomy.line_of(Game.data, Game.state, id)["people"])
		if people >= 1000:
			assert_false(text.contains(str(people)) or text.contains(Intel.num(people)), str(id))
			checked += 1
		if checked >= 5:
			break
```

Construct the two panels the way their existing tests do (look for `tests/ui/test_military_panel.gd` / `test_manor_master*.gd`: some are scenes, some are code-built, and some need `follow()` or a `refresh(state)` argument). Adapt the construction, not the assertions.

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL (true totals present).

- [ ] **Step 3: Implement.**
  - **`military_panel.gd` neighbours:** show each neighbour as a row of text instead of a numeric bar: `"<Kingdom> — <words>"`.
    - `<words>` is the newest `troops_foreign` estimate from any spy missive whose subject point lies in a province that kingdom holds, rendered by `Intel._from_fact`.
    - Otherwise it is `Intel.magnitude(repo, total) + " (common talk)"`.
    - If the chart widget cannot take text rows, replace it for this block with a VBox of Labels.
    - Keep the player's own bars exact.
  - **`manor_master_panel.gd`:** for each row, `var lvl := Intel.level(repo, state, MissiveLog.subject("manor", code, cell, centre))`.
    - When it is not `full`: people shows `Intel.fact(... "people", people)["text"]`, rent and value show `"—"` (or the latest estimate's text for `tax`), and the row sorts after every `full` row.
    - Build the subject's `centre` with `MapTerrain.cell_center`.
  - **`map3d_hud_badges.gd` `_cut`:** skip a manor unless `Intel.level(ctx.repo, ctx.state(), {"kind": "manor", "cell": <its cell>, "code": "", "x": 0, "y": 0}) == "full"`. Use the manor entry's cell field; check `MapEconomy.manors` for its name. No `Game` here.

- [ ] **Step 4: Run** this test and each panel's existing tests (update pinned foreign figures and list them), then the whole suite.
- [ ] **Step 5: Commit**

```bash
git add scripts/ui/military_panel.gd scripts/ui/manor_master_panel.gd scripts/map3d/map3d_hud_badges.gd tests/ui/test_fog_panels.gd tests/ui/test_fog_panels.gd.uid <every test file you updated>
git commit -m "feat(intel): panels read the gate — no true foreign figures anywhere"
```

---

### Task 7: The Missive screen, the tab and Show on map

**Files:**
- Create: `scenes/missive_screen.tscn`, `scripts/ui/missive_screen.gd`
- Modify:
  - `scripts/ui/bottom_bar.gd` (TABS gains `"MISSIVE"` after `"RELATIONSHIP"`; `set_badge(tab, n)`)
  - `scripts/ui/game_root.gd` (create, toggle and stack the screen; `_on_bottom_tab` arm; refresh the badge; handle `show_requested`; set `Intel.dev_all` in `_apply_dev_mode` and on load)
- Test: `tests/ui/test_missive_screen.gd`

**Interfaces:**
- Consumes: `MissiveLog` (Task 1), `Map3DView.look_at_pack(pack_px, at_distance := -1.0)`, and the view's `object_selected` / `province_selected` signals (the left column's card follows them).
- Produces:
  - `MissiveScreen`: `refresh() -> void`, `select(id: int) -> void`, `selected() -> int`, `signal show_requested(subject: Dictionary)`, `signal closed`
  - `BottomBar.set_badge(tab: String, n: int) -> void`
  - `GameRoot.missive_screen() -> MissiveScreen`, `GameRoot.toggle_missives() -> void`, `GameRoot.refresh_missive_badge() -> void`

- [ ] **Step 1: Write the failing test** — `tests/ui/test_missive_screen.gd`

```gdscript
extends GutTest

func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	return r


func _letter(column: String) -> int:
	return MissiveLog.add(Game.data, Game.state, MissiveLog.make("spy", column, 3,
		MissiveLog.subject("point", "", -1, Vector2(500, 300)), "A letter",
		[MissiveLog.span("people", "People", 2800, 3200)]))


func _enter(r: GameRoot) -> void:
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)


func test_the_tab_opens_the_board_with_its_letters() -> void:
	Game.start_campaign(42)
	_letter("credible")
	_letter("rumour")
	var r := _root()
	await _enter(r)
	r.bottom_bar().button("MISSIVE").pressed.emit()
	await wait_frames(1)
	var ms := r.missive_screen()
	assert_true(ms.visible)
	assert_eq(ms.notes_in("credible"), 1)
	assert_eq(ms.notes_in("rumour"), 1)
	assert_eq(ms.notes_in("truth"), 0)


func test_selecting_a_letter_reads_it_and_the_badge_follows() -> void:
	Game.start_campaign(42)
	var id := _letter("credible")
	var r := _root()
	await _enter(r)
	r.refresh_missive_badge()
	assert_eq(r.bottom_bar().badge("MISSIVE"), 1)
	r.toggle_missives()
	r.missive_screen().select(id)
	assert_true(bool(MissiveLog.find(Game.state, id)["read"]))
	assert_eq(r.bottom_bar().badge("MISSIVE"), 0)
	assert_string_contains(r.missive_screen().desk_text(), "2,800–3,200")


func test_show_on_map_closes_the_board() -> void:
	Game.start_campaign(42)
	var id := _letter("credible")
	var r := _root()
	await _enter(r)
	r.toggle_missives()
	var ms := r.missive_screen()
	ms.select(id)
	watch_signals(ms)
	ms.show_on_map_button().pressed.emit()
	assert_signal_emitted(ms, "show_requested")
	await wait_frames(1)
	assert_false(ms.visible)


func test_a_capped_away_letter_empties_the_desk() -> void:
	Game.start_campaign(42)
	Game.data.balance["missive_keep_per_column"] = 1.0
	var id := _letter("credible")
	var r := _root()
	await _enter(r)
	r.toggle_missives()
	var ms := r.missive_screen()
	ms.select(id)
	_letter("credible")
	ms.refresh()
	assert_eq(ms.selected(), -1)
	assert_string_contains(ms.desk_text(), "Choose a letter")
```

Match `_enter` to how `tests/ui/test_game_root.gd` gets into the court; copy it if it differs. Restore `missive_keep_per_column` in `after_each` if `Game.data` is shared across tests.

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL (no MISSIVE tab).

- [ ] **Step 3: `BottomBar`.**
  - Append `"MISSIVE"` to `TABS` after `"RELATIONSHIP"`.
  - Add:

    ```gdscript
    var _badges: Dictionary = {}

    ## An unread count drawn on a tab (the Missive board, spec 2026-09-28 §2); 0 hides it.
    func set_badge(tab: String, n: int) -> void:
    	_badges[tab] = n
    	var b := button(tab)
    	if b == null:
    		return
    	var base := String(b.get_meta("label", b.text))
    	b.set_meta("label", base)
    	b.text = base if n <= 0 else "%s (%d)" % [base, n]

    func badge(tab: String) -> int:
    	return int(_badges.get(tab, 0))
    ```

  A drawn gold dot can replace the "(n)" suffix during Task 10's look pass. Check any bottom-bar test that pins `TABS` and add `MISSIVE` there.

- [ ] **Step 4: The scene and script.**

`scripts/ui/missive_screen.gd`:
```gdscript
class_name MissiveScreen
extends Control
## The Missive board (owner 2026-09-28, spec 2026-09-28-missive-board-and-spies
## §2, layout B): four credibility columns on the left two-thirds, the reading
## desk on the right third. Letters come from MissiveLog; selecting one reads
## it; Show on map hands the subject to GameRoot. Columns are the letters' own
## — nothing is dragged.

signal show_requested(subject: Dictionary)
signal closed

const HEADERS := {"truth": "Ground truth", "credible": "Highly credible",
	"consult": "Worth consulting", "rumour": "Rumour"}
const EMPTY := {"truth": "The steward's monthly reports", "credible": "Receipts and clear-eyed spies",
	"consult": "Letters taken from others' couriers", "rumour": "What a spy only heard"}

var _selected := -1

@onready var _columns: Dictionary = {
	"truth": %TruthNotes, "credible": %CredibleNotes, "consult": %ConsultNotes, "rumour": %RumourNotes}


func _ready() -> void:
	%Close.pressed.connect(func() -> void:
		visible = false
		closed.emit())
	%ShowOnMap.pressed.connect(_show_on_map)
	for col: String in HEADERS:
		(get_node("%" + col.capitalize() + "Plaque") as Label).text = HEADERS[col]
		(get_node("%" + col.capitalize() + "Plaque") as Label).add_theme_color_override("font_color",
			MapPalette.named(Game.data, "intel_" + col))
	%Frame.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 16))
	UiPalette.style_header(%Title, 22)
	visibility_changed.connect(func() -> void:
		if visible:
			refresh())


func refresh() -> void:
	if MissiveLog.find(Game.state, _selected).is_empty():
		_selected = -1
	for col: String in _columns:
		var box: VBoxContainer = _columns[col]
		for c in box.get_children():
			c.queue_free()
		var list := MissiveLog.column(Game.state, col)
		if list.is_empty():
			var hint := Label.new()
			hint.text = EMPTY[col]
			hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hint.add_theme_color_override("font_color", UiPalette.TEXT_MUTED)
			box.add_child(hint)
		for m: Dictionary in list:
			box.add_child(_note(m))
	_fill_desk()


func notes_in(col: String) -> int:
	return MissiveLog.column(Game.state, col).size()


func select(id: int) -> void:
	_selected = id
	MissiveLog.mark_read(Game.state, id)
	refresh()
	var root := get_parent() as GameRoot
	if root != null:
		root.refresh_missive_badge()


func selected() -> int:
	return _selected


func desk_text() -> String:
	var out := String(%LetterTitle.text) + "\n" + String(%LetterMeta.text)
	for c in %LetterFacts.get_children():
		out += "\n" + String((c as Label).text)
	return out


func show_on_map_button() -> Button:
	return %ShowOnMap


func _note(m: Dictionary) -> Button:
	var b := Button.new()
	b.name = "Note%d" % int(m["id"])
	b.text = "%s\n%s" % [String(m["title"]), CourierCard.date_of(int(m["day"]))]
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_stylebox_override("normal", UiPalette.chip_style(UiPalette.CHIP_BG,
		UiPalette.GOLD if not bool(m.get("read", false)) else UiPalette.EDGE))
	var id := int(m["id"])
	b.pressed.connect(func() -> void: select(id))
	return b


func _fill_desk() -> void:
	for c in %LetterFacts.get_children():
		c.queue_free()
	var m := MissiveLog.find(Game.state, _selected)
	%ShowOnMap.visible = not m.is_empty()
	if m.is_empty():
		%LetterTitle.text = "Choose a letter"
		%LetterMeta.text = ""
		return
	%LetterTitle.text = String(m["title"])
	%LetterMeta.text = "%s · %s" % [CourierCard.date_of(int(m["day"])), HEADERS[String(m["column"])]]
	for f: Dictionary in m["facts"]:
		var l := Label.new()
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text = "%s: %s" % [String(f["label"]), Intel._from_fact(f)]
		%LetterFacts.add_child(l)


func _show_on_map() -> void:
	var m := MissiveLog.find(Game.state, _selected)
	if m.is_empty():
		return
	visible = false
	show_requested.emit(m["subject"])
```

Check that `UiPalette.chip_style(bg, border)` exists with that signature, and that `GOLD` / `EDGE` / `CHIP_BG` / `TEXT_MUTED` / `BORDER_GOLD` are its constant names. Adapt to the real names.

`scenes/missive_screen.tscn`, authored as text. Keep this tree and these unique names; the exact offsets are yours:

```
MissiveScreen (Control, full rect, mouse_filter STOP, script missive_screen.gd)
├── Dim (ColorRect, full rect, color 0,0,0,0.55)
└── %Frame (PanelContainer, full rect with 48 px margins)
    └── Col (VBoxContainer)
        ├── Head (HBoxContainer)
        │   ├── %Title (Label "Missives", size_flags_horizontal EXPAND_FILL)
        │   └── %Close (Button "CLOSE")
        └── Body (HBoxContainer, size_flags_vertical EXPAND_FILL)
            ├── Board (HBoxContainer, size_flags_horizontal EXPAND_FILL, stretch_ratio 2)
            │   ├── Truth (VBoxContainer, EXPAND_FILL) → %TruthPlaque (Label), Scroll (ScrollContainer, EXPAND_FILL) → %TruthNotes (VBoxContainer, EXPAND_FILL)
            │   ├── Credible → %CrediblePlaque, Scroll → %CredibleNotes
            │   ├── Consult → %ConsultPlaque, Scroll → %ConsultNotes
            │   └── Rumour → %RumourPlaque, Scroll → %RumourNotes
            └── Desk (PanelContainer, EXPAND_FILL, stretch_ratio 1)
                └── Letter (VBoxContainer)
                    ├── %LetterTitle (Label, autowrap)
                    ├── %LetterMeta (Label)
                    ├── %LetterFacts (VBoxContainer)
                    └── %ShowOnMap (Button "Show on map")
```

Every `%` node carries `unique_name_in_owner = true`.

- [ ] **Step 5: GameRoot.**
  - Mirror `_relations_screen` exactly:
    - `var _missive_screen: MissiveScreen`;
    - in `_ready`, `_missive_screen = load("res://scenes/missive_screen.tscn").instantiate()`, `visible = false`, `add_child`, and connect `show_requested` to `_on_missive_show`;
    - in `_switch_to`, re-stack it right after the relations screen.
  - Add these functions:

    ```gdscript
    func missive_screen() -> MissiveScreen:
    	return _missive_screen


    func toggle_missives() -> void:
    	if state == State.MENU:
    		return
    	_relations_screen.visible = false
    	_info_screen.hide()
    	_missive_screen.visible = not _missive_screen.visible


    func refresh_missive_badge() -> void:
    	if _bottom_bar != null and Game.state != null:
    		_bottom_bar.set_badge("MISSIVE", MissiveLog.unread(Game.state))


    ## Show on map (spec 2026-09-28 §2): the view looks at the letter's place and
    ## the left column opens its card, through the view's own signals.
    func _on_missive_show(subject: Dictionary) -> void:
    	var view: Map3DView = current_screen.map3d_view() if current_screen != null and current_screen.has_method("map3d_view") else null
    	if view == null:
    		return
    	view.look_at_pack(Vector2(float(subject["x"]), float(subject["y"])))
    	match String(subject["kind"]):
    		"manor":
    			view.object_selected.emit({"title": MapManors.label_of(Game.data, int(subject["cell"])),
    				"obj": {"kind": "manor", "cell": int(subject["cell"])}})
    		"province":
    			view.province_selected.emit(String(subject["code"]))
    		"burg":
    			view.object_selected.emit({"title": String(Game.data.burgs[String(subject["code"])]["label"]),
    				"obj": {"kind": "burg", "code": String(subject["code"])}})
    ```

  - `_on_bottom_tab` gains `"MISSIVE": toggle_missives()`, and the other arms also hide `_missive_screen`, as they hide `_relations_screen`.
  - Call `refresh_missive_badge()` at the end of every `_process` day step (where the courier news loop is) and after a load.
  - In `_apply_dev_mode()`, add `Intel.dev_all = _dev_mode`, and set it once in `_ready` after settings load.
  - Use the real names of `_bottom_bar`, `state` and `current_screen.map3d_view()` in `game_root.gd`.

- [ ] **Step 6: Run** this test, `tests/ui/test_game_root.gd`, `test_ui_rework.gd` and any bottom-bar test, then the whole suite.
- [ ] **Step 7: Commit**

```bash
git add scenes/missive_screen.tscn scripts/ui/missive_screen.gd scripts/ui/missive_screen.gd.uid scripts/ui/bottom_bar.gd scripts/ui/game_root.gd tests/ui/test_missive_screen.gd tests/ui/test_missive_screen.gd.uid <any test you updated>
git commit -m "feat(missives): the Missive board — four columns, the reading desk, Show on map"
```

---

### Task 8: The spy report dialog, the envelope flight, and the pause

**Files:**
- Create: `scenes/missive_report_popup.tscn`, `scripts/ui/missive_report_popup.gd`, `scripts/ui/envelope_flight.gd`
- Modify: `scripts/ui/game_root.gd` (the day loop in `_process`: new missives → popup or small flight; stop stepping while a report waits)
- Test: `tests/ui/test_missive_flight.gd`

**Interfaces:**
- Consumes: `MissiveLog`, `BottomBar.button/set_badge`, `GameRoot.refresh_missive_badge` (Task 7), and `NewsTicker`'s global rect.
- Produces:
  - `EnvelopeFlight.fly(host: Control, from: Rect2, to: Rect2, big: bool, repo: DataRepository) -> EnvelopeFlight`, with `signal landed`
  - `MissiveReportPopup.open(m: Dictionary) -> void`, with `signal sealed(from: Rect2)`
  - `GameRoot.report_popup() -> MissiveReportPopup`, `GameRoot.pending_reports() -> Array`

- [ ] **Step 1: Write the failing test** — `tests/ui/test_missive_flight.gd`

```gdscript
extends GutTest

func before_each() -> void:
	Game.start_campaign(42)
	Game.data.balance["missive_seal_s"] = 0.05
	Game.data.balance["missive_fly_s"] = 0.05


func _root() -> GameRoot:
	var r: GameRoot = load("res://scenes/game_root.tscn").instantiate()
	add_child_autofree(r)
	await wait_frames(2)
	r._switch_to(GameRoot.State.COURT)
	r.current_screen.enter_court(null)
	await wait_frames(2)
	return r


func _spy_letter() -> int:
	return MissiveLog.add(Game.data, Game.state, MissiveLog.make("spy", "credible", 3,
		MissiveLog.subject("point", "", -1, Vector2(500, 300)), "Spy report — X",
		[MissiveLog.span("people", "People", 2800, 3200)]))


func test_an_envelope_lands_on_the_tab() -> void:
	var r: GameRoot = await _root()
	var tab := r.bottom_bar().button("MISSIVE")
	var f := EnvelopeFlight.fly(r, Rect2(400, 300, 300, 200), tab.get_global_rect(), true, Game.data)
	watch_signals(f)
	await wait_for_signal(f.landed, 2.0)
	assert_signal_emitted(f, "landed")


func test_a_spy_report_stops_the_clock_and_opens_the_dialog() -> void:
	var r: GameRoot = await _root()
	Game.set_clock_speed(1)
	var id := _spy_letter()
	r.on_new_missives([id])
	assert_eq(Game.clock_speed, 0, "the clock stopped")
	assert_true(r.report_popup().visible)
	r.report_popup().seal_button().pressed.emit()
	await wait_frames(30)
	assert_false(r.report_popup().visible)
	assert_eq(Game.clock_speed, 0, "nothing restarts the clock")


func test_two_spy_reports_in_one_frame_open_in_turn() -> void:
	var r: GameRoot = await _root()
	var a := _spy_letter()
	var b := _spy_letter()
	r.on_new_missives([a, b])
	assert_eq(r.pending_reports(), [b])
	r.report_popup().seal_button().pressed.emit()
	await wait_frames(30)
	assert_true(r.report_popup().visible, "the second opens after the first is sealed")
	assert_eq(r.pending_reports(), [])


func test_a_receipt_flies_without_stopping_the_clock() -> void:
	var r: GameRoot = await _root()
	Game.set_clock_speed(1)
	var id := MissiveLog.add(Game.data, Game.state, MissiveLog.make("receipt", "credible", 3,
		MissiveLog.subject("regiment", "x", -1, Vector2(500, 300)), "Receipt — X", []))
	r.on_new_missives([id])
	assert_eq(Game.clock_speed, 1)
	assert_false(r.report_popup().visible)
	Game.set_clock_speed(0)
```

- [ ] **Step 2: Run it to verify it fails.**

- [ ] **Step 3: `scripts/ui/envelope_flight.gd`**

```gdscript
class_name EnvelopeFlight
extends Control
## A wax-sealed envelope flying to the Missive tab (owner 2026-09-28, spec
## 2026-09-28 §2): it shrinks from `from` toward an envelope over
## missive_seal_s, then rides a quadratic arc to `to` over missive_fly_s,
## turning missive_fly_turns times, and frees itself. The project's first Tween.

signal landed

const ENVELOPE_PX := Vector2(36, 26)
const SMALL_PX := Vector2(22, 16)

var _from: Vector2
var _to: Vector2
var _lift: Vector2


static func fly(host: Control, from: Rect2, to: Rect2, big: bool, repo: DataRepository) -> EnvelopeFlight:
	var f := EnvelopeFlight.new()
	f.mouse_filter = Control.MOUSE_FILTER_IGNORE
	f.top_level = true
	host.add_child(f)
	f._start(from, to, big, repo)
	return f


func _start(from: Rect2, to: Rect2, big: bool, repo: DataRepository) -> void:
	var env := ENVELOPE_PX if big else SMALL_PX
	size = from.size if big else env
	position = from.position if big else from.get_center() - env * 0.5
	pivot_offset = size * 0.5
	_from = position
	_to = to.get_center() - env * 0.5
	_lift = (_from + _to) * 0.5 + Vector2(0, -160)
	var t := create_tween()
	if big:
		t.tween_property(self, "size", env, repo.bal("missive_seal_s"))
		t.parallel().tween_property(self, "position", from.get_center() - env * 0.5, repo.bal("missive_seal_s"))
		t.tween_callback(func() -> void:
			_from = position
			pivot_offset = env * 0.5)
	t.tween_method(_arc, 0.0, 1.0, repo.bal("missive_fly_s"))
	t.parallel().tween_property(self, "rotation", TAU * repo.bal("missive_fly_turns"), repo.bal("missive_fly_s"))
	t.tween_callback(func() -> void:
		landed.emit()
		queue_free())


func _arc(k: float) -> void:
	position = _from.lerp(_lift, k).lerp(_lift.lerp(_to, k), k)


func _draw() -> void:
	var tex: Texture2D = UiPalette.load_art(String(Game.data.missive_art.get("envelope", "")))
	if tex != null:
		draw_texture_rect(tex, Rect2(Vector2.ZERO, size), false)
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color("#E9DCC0"))
	draw_polyline(PackedVector2Array([Vector2.ZERO, size * Vector2(0.5, 0.55), Vector2(size.x, 0)]),
		Color("#7A5A30"), 1.5)
	draw_circle(size * Vector2(0.5, 0.55), minf(size.x, size.y) * 0.18, Color("#8B1E1E"))
```

Redraw every frame while flying (`queue_redraw()` in `_process`, or since `size` changes). Check that `UiPalette.load_art(path)` returns null for "". The three fallback colours are drawn only until the art is installed: add them as `political_palette.csv` rows (`envelope_paper`, `envelope_ink`, `envelope_wax`) and read them with `MapPalette.named`, so no colour is hard-coded.

- [ ] **Step 4: The popup.**

`scripts/ui/missive_report_popup.gd`:
```gdscript
class_name MissiveReportPopup
extends Control
## A spy's report (owner 2026-09-28, spec 2026-09-28 §2): centred over the
## map, the spy's painting (sub-project D; hidden until installed) and his
## report; Seal closes it and hands its rect to the envelope flight.

signal sealed(from: Rect2)


func _ready() -> void:
	%Window.add_theme_stylebox_override("panel", UiPalette.panel_style(UiPalette.BORDER_GOLD, 2, 20))
	UiPalette.style_header(%ReportTitle, 20)
	%Seal.pressed.connect(func() -> void:
		var r: Rect2 = %Window.get_global_rect()
		visible = false
		sealed.emit(r))


func open(m: Dictionary) -> void:
	%ReportTitle.text = String(m["title"])
	%ReportMeta.text = "%s · %s" % [CourierCard.date_of(int(m["day"])), MissiveScreen.HEADERS[String(m["column"])]]
	for c in %ReportFacts.get_children():
		c.queue_free()
	for f: Dictionary in m["facts"]:
		var l := Label.new()
		l.text = "%s: %s" % [String(f["label"]), Intel._from_fact(f)]
		%ReportFacts.add_child(l)
	var art := String((Game.data.courier_art.get("spy", {}) as Dictionary).get("painting", ""))
	var tex: Texture2D = UiPalette.load_art(art) if art != "" else null
	%Painting.texture = tex
	%Painting.visible = tex != null
	visible = true


func seal_button() -> Button:
	return %Seal
```

`scenes/missive_report_popup.tscn`, authored as text:

```
MissiveReportPopup (Control, full rect, mouse_filter STOP, visible false, script)
├── Dim (ColorRect, full rect, color 0,0,0,0.35)
└── Center (CenterContainer, full rect)
    └── %Window (PanelContainer, custom_minimum_size 640x360)
        └── Row (HBoxContainer)
            ├── %Painting (TextureRect, 220x280, expand_mode fit, stretch keep aspect covered)
            └── Col (VBoxContainer, EXPAND_FILL)
                ├── %ReportTitle (Label, autowrap)
                ├── %ReportMeta (Label)
                ├── %ReportFacts (VBoxContainer)
                └── %Seal (Button "Seal")
```

- [ ] **Step 5: GameRoot.**

```gdscript
var _report_popup: MissiveReportPopup
var _pending_reports: Array = []


func report_popup() -> MissiveReportPopup:
	return _report_popup


func pending_reports() -> Array:
	return _pending_reports


## New letters from a day's step (spec 2026-09-28 §2): a spy's report stops the
## clock and opens the dialog (one at a time, in id order); a receipt or a
## monthly report flies a small envelope from the news bar and interrupts nothing.
func on_new_missives(ids: Array) -> void:
	for id: int in ids:
		var m := MissiveLog.find(Game.state, id)
		if m.is_empty():
			continue
		if String(m["kind"]) == "spy":
			Game.set_clock_speed(0)
			_pending_reports.append(id)
		else:
			var from: Rect2 = _news_ticker.get_global_rect() if _news_ticker != null else Rect2(get_viewport_rect().size * 0.5, Vector2.ZERO)
			EnvelopeFlight.fly(self, from, _bottom_bar.button("MISSIVE").get_global_rect(), false, Game.data) \
				.landed.connect(refresh_missive_badge)
	if not _report_popup.visible:
		_next_report()


func _next_report() -> void:
	if _pending_reports.is_empty():
		return
	_report_popup.open(MissiveLog.find(Game.state, int(_pending_reports.pop_front())))


func _on_report_sealed(from: Rect2) -> void:
	var f := EnvelopeFlight.fly(self, from, _bottom_bar.button("MISSIVE").get_global_rect(), true, Game.data)
	f.landed.connect(func() -> void:
		refresh_missive_badge()
		_next_report())
```

- In `_ready`, instantiate `res://scenes/missive_report_popup.tscn` into `_report_popup`, hidden, add it, and connect `sealed` to `_on_report_sealed`.
- Re-stack it in `_switch_to` above the Missive screen and below the pause menu.
- **In `_process`'s day loop:**
  - record `var before := Game.state.next_missive_id` before `Game.advance_day()`;
  - afterwards, collect `range(before + 1, Game.state.next_missive_id + 1)` and pass it to `on_new_missives`;
  - make the loop's `while` condition also require `Game.clock_speed > 0 and _pending_reports.is_empty() and not _report_popup.visible`, so no further day runs in that frame once a report is waiting.
- Remove the per-day `refresh_missive_badge()` call from Task 7 wherever the flight now does it; keep the one after a load.

- [ ] **Step 6: Run** this test, the Task 7 test and `tests/ui/test_game_root.gd`, then the whole suite.
- [ ] **Step 7: Commit**

```bash
git add scenes/missive_report_popup.tscn scripts/ui/missive_report_popup.gd scripts/ui/missive_report_popup.gd.uid scripts/ui/envelope_flight.gd scripts/ui/envelope_flight.gd.uid scripts/ui/game_root.gd data/political_palette.csv tests/ui/test_missive_flight.gd tests/ui/test_missive_flight.gd.uid
git commit -m "feat(missives): a spy's report pauses, seals and flies to the board; receipts fly quietly"
```

---

### Task 9: Sending spies — right click on the ground, and the card button

**Files:**
- Create: `scripts/ui/spy_order_menu.gd`
- Modify:
  - `scripts/map3d/map3d_view.gd` (signal `ground_menu_requested(pack_px: Vector2, at: Vector2)`; `right_click` emits it when nothing is picked); `tests/map3d/test_map3d_shape.gd` (the cap and its comment)
  - `scenes/court.tscn` and `scenes/conversation.tscn` (a `SpyOrders` PopupMenu, unique `%SpyOrders`)
  - `scripts/ui/court_screen.gd` and `scripts/ui/conversation_scene.gd` (`%SpyOrders.follow(view)` after `Map3DView.attach`)
  - `scripts/engine/map_objects.gd` (a `SPY_SEND` action on manor, province and burg cards)
  - `scripts/ui/map_detail_panel.gd` (`_give_order` does not reopen a manor after `SPY_SEND`)
- Test: `tests/ui/test_spy_orders.gd`

**Interfaces:**
- Consumes: `SPY_SEND` (Task 4), `Intel.place_label`, `CourierSystem.fee_gold/SPY/day_budget/need_along/path_between/origin/days_for`.
- Produces: `SpyOrderMenu.follow(map: Node)`, `SpyOrderMenu.SEND := 0`.

- [ ] **Step 1: Write the failing test** — `tests/ui/test_spy_orders.gd`

```gdscript
extends GutTest

class FakeMap extends Node:
	signal ground_menu_requested(pack_px: Vector2, at: Vector2)

var _menu: SpyOrderMenu
var _map: FakeMap


func before_each() -> void:
	Game.start_campaign(42)
	Game.set_clock_speed(0)
	_menu = SpyOrderMenu.new()
	add_child_autofree(_menu)
	_map = FakeMap.new()
	add_child_autofree(_map)
	_menu.follow(_map)


func _land() -> Vector2:
	var ids := Game.data.manors.keys()
	ids.sort()
	return MapTerrain.cell_center(Game.data, Game.data.cells[int(ids[ids.size() / 2])])


func test_a_right_click_on_the_ground_offers_a_spy_and_sends_him() -> void:
	var at := _land()
	_map.ground_menu_requested.emit(at, Vector2(20, 20))
	assert_true(_menu.visible)
	assert_string_contains(_menu.get_item_text(0), "spy")
	_menu.hide()
	_menu.id_pressed.emit(SpyOrderMenu.SEND)
	assert_eq(Game.state.couriers.size(), 1)
	assert_eq(String(Game.state.couriers[0]["kind"]), "spy")


func test_every_land_card_offers_a_spy() -> void:
	var s := Game.state
	var cell := int(Game.data.manors.keys()[0])
	for card: Dictionary in [MapObjects.manor_card(Game.data, s, cell),
			MapObjects.province_card(Game.data, s, MapManors.province_of(Game.data, cell, s))]:
		var codes: Array = (card.get("actions", []) as Array).map(func(a: Dictionary) -> String: return String(a["action_code"]))
		assert_has(codes, "SPY_SEND", String(card["kind"]))
```

- [ ] **Step 2: Run it to verify it fails.**

- [ ] **Step 3: `scripts/ui/spy_order_menu.gd`**

```gdscript
class_name SpyOrderMenu
extends PopupMenu
## "Send a spy here…" (owner 2026-09-28, spec 2026-09-28 §2): a right click on
## open ground offers one row — the fee and the estimated days — and runs
## SPY_SEND there. Lives in court.tscn / conversation.tscn as %SpyOrders.

const SEND := 0

var _target := Vector2(-1, -1)


func follow(map: Node) -> void:
	map.connect("ground_menu_requested", _open_at)
	id_pressed.connect(_on_id)


func _open_at(pack_px: Vector2, at: Vector2) -> void:
	_target = pack_px
	clear()
	var fee := CourierSystem.fee_gold(Game.data, CourierSystem.SPY)
	var from := CourierSystem.origin(Game.data, Game.state)
	var days := CourierSystem.days_for(Game.data, CourierSystem.SPY, CourierSystem.need_along(Game.data,
		Game.state, ArmySystem.pack_to_metres(Game.data, from),
		CourierSystem.path_between(Game.data, from, pack_px), Game.state.absolute_day()))
	add_item("Send a spy here — ≈%d day%s · %d gold" % [days, "" if days == 1 else "s", fee], SEND)
	set_item_tooltip(0, Intel.place_label(Game.data, Game.state, pack_px))
	position = Vector2i(at)
	popup()


func _on_id(id: int) -> void:
	if id != SEND or _target.x < 0.0:
		return
	var out := Game.try_execute(ActionRequest.make("SPY_SEND", {"x": _target.x, "y": _target.y}))
	if not bool(out.get("ok", false)):
		Game.publish_news(String(out.get("error", "That spy cannot be sent.")))
		return
	for e: Dictionary in (out.get("outcome", {}) as Dictionary).get("effects", []):
		if String(e.get("metric", "")) == "intel":
			Game.publish_news(String(e["reason"]))
	_target = Vector2(-1, -1)
```

`position` is in the viewport's coordinates. Mirror how `ArmyOrderMenu` places itself (`_open_for`) and copy that conversion.

- [ ] **Step 4: The view.** In `map3d_view.gd`:
  - Add the signal beside `route_clicked`:

    ```gdscript
    ## A right click on open ground (owner 2026-09-28): SpyOrderMenu's "Send a spy here".
    signal ground_menu_requested(pack_px: Vector2, at: Vector2)
    ```

  - In `right_click`, before `return false` for a non-army pick: if `pick_at(pos)` is not an army and the ground under `pos` is hit, emit `ground_menu_requested(<pack px of that ground point>, pos)` and return true. Use the same ground-to-pack conversion `select_at` uses for `ground_clicked`, and copy it.
  - Raise `tests/map3d/test_map3d_shape.gd`'s cap to the new `split("\n").size()`. Add one comment line: "the spy's right-click on the ground: a signal and its emit — SpyOrderMenu does the work (2026-09-28)". Keep the growth to the signal and the emit, at most 4 lines.

- [ ] **Step 5: The scenes.**
  - In `court.tscn` and `conversation.tscn`, add beside `ArmyOrders`:

    ```
    [node name="SpyOrders" type="PopupMenu" parent="."]
    unique_name_in_owner = true
    script = ExtResource("<new id>")
    ```

    Add the ext_resource for `res://scripts/ui/spy_order_menu.gd` with an unused id, matching each file's format.
  - In `court_screen.gd` and `conversation_scene.gd`, the lines that call `Map3DView.attach(...)` return the view: follow it with `%SpyOrders.follow(view)`. Capture the return value if it is discarded today.

- [ ] **Step 6: The card button.** In `map_objects.gd`, `manor_card`, `province_card` and `burg_card` each append this to `card["actions"]` (creating the key where it is missing):

```gdscript
{"action_code": "SPY_SEND", "label": "Send a spy", "params": {"x": centre.x, "y": centre.y}, "error": ""}
```

Here `centre` is the card's `center`. For the manor's basic branch, append it before its `return`. In `map_detail_panel.gd` `_give_order`, after a successful `SPY_SEND`, publish the `intel` effect's reason to the news bar and return without the `show_manor(_shown_manor)` refresh.

- [ ] **Step 7: Run** this test, `tests/ui/test_army_order_menu.gd`, `tests/map3d/test_map3d_shape.gd`, `test_map_detail_panel.gd` and `test_map_objects.gd`, then the whole suite.
- [ ] **Step 8: Commit**

```bash
git add scripts/ui/spy_order_menu.gd scripts/ui/spy_order_menu.gd.uid scripts/map3d/map3d_view.gd tests/map3d/test_map3d_shape.gd scenes/court.tscn scenes/conversation.tscn scripts/ui/court_screen.gd scripts/ui/conversation_scene.gd scripts/engine/map_objects.gd scripts/ui/map_detail_panel.gd tests/ui/test_spy_orders.gd tests/ui/test_spy_orders.gd.uid
git commit -m "feat(spies): send a spy by a right click on the ground or from any land card"
```

---

### Task 10: Art prompts, the look check, and the docs

**Files:**
- Modify: `docs/references/art_prompt_library.md` (a new "Missive board" section; prompts only)
- Modify: `CLAUDE.md` (a "Missives and spies" paragraph after "Couriers")
- Modify: `.claude/skills/visual-review/taste.md` only on an owner ruling

- [ ] **Step 1: The art prompts.** No generation — the owner approves each run.
  - Add a "Missive board (spec 2026-09-28 §3)" section to the prompt library, with one entry per `data/missive_art.csv` key (frame, board, note, letter, envelope, pin, plaque).
  - Write each in the library's existing entry format, in the v2 colour style, each naming its canvas and its intended installed size (the asset-resolution-per-use rule).
  - The installer mapping and the actual generation are a follow-up the owner triggers.

- [ ] **Step 2: Shoot through the real window.** Use `tools/snapshot_screen.tscn` (read its header for flags; never `--headless`). Take:
  1. the board with letters in truth, credible and rumour after a few months with a spy sent (drive it with `--march3d` / a new `--spy3d FX,FY` flag if you must add one, plus `--speed` and `--shot-frame`);
  2. the report dialog;
  3. an envelope mid-flight;
  4. a foreign manor card before and after a spy report.

  Follow `.claude/skills/visual-review/`. The flat stand-ins must read cleanly on the dark theme. Fix what is broken (layout, overflow in the 240-px left column, unreadable text), each with its own commit.

- [ ] **Step 3: CLAUDE.md.** Add after the Couriers paragraph:

```markdown
**Missives and spies** (owner 2026-09-28, spec `docs/superpowers/specs/2026-09-28-missive-board-and-spies-design.md`, sub-project B): a FOG OF KNOWLEDGE — `Intel` is the one gate every card and panel asks: `full` (provinces the crown controls, its regiments) shows exact figures, `general` (the rest of the realm) words ("thousands", rich / middling / poor), `basic` (abroad) only holder, stance (the pack's `diplomacy.csv`) and wealth; the newest report about a place overrides the words with its estimate, tagged by source and date; DEV MODE (`Intel.dev_all`) lifts it. SPY couriers (`SPY_SEND`, a right click on the ground or a card's Send a spy) ride A's roads to a POINT and file a report (`SpySystem`): one quality roll from `GameState.rng` shifted by the place (`spy_difficulty.csv`) decides the column and each estimate's width and bias. Every letter is a MISSIVE (`MissiveLog`, `GameState.missives`, saved, capped per column): receipts (A's deliveries, highly credible), the steward's monthly report (ground truth), spy reports (highly credible or rumour); "worth consulting" waits for C. The MISSIVE tab opens the board (`MissiveScreen`: four columns and a reading desk with Show on map); a spy's report stops the clock and seals into a flying envelope (`MissiveReportPopup`, `EnvelopeFlight`), receipts and reports fly quietly. The board's art is Flux, prompts in the library, flat stand-ins until installed (`missive_art.csv`).
```

- [ ] **Step 4: Run the whole suite in the foreground** and confirm it is green.
- [ ] **Step 5: Commit**

```bash
git add docs/references/art_prompt_library.md CLAUDE.md <any fix files>
git commit -m "docs: missives and spies in CLAUDE.md; the board's art prompts"
```
