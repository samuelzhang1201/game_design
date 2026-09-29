# LEDGER M1 + M2 — Supply Lines, Morale and the War Workshop — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the chain civil goods → war workshop → strategic goods → supply line → regiment → morale, and light those links on the LEDGER.

**Architecture:** Two pure systems in `scripts/engine/` — `WorkshopSystem` (turns the lord's civil goods into strategic goods at each war workshop, rate set by an order) and `SupplySystem` (ships strategic goods to each regiment along the road from the capital, losing a share by distance; a garrison in a controlled province loses nothing) — each with ONE `plan()` read by the tick, the cards and the LEDGER. `ArmySystem.settle_month` gains morale drift toward a mark set by the stores in hand.

**Tech Stack:** Godot 4.7, typed GDScript, GUT 9.4.

**Spec:** `docs/superpowers/specs/2026-09-30-ledger-supply-design.md` (charter: `2026-09-30-ledger-ontology-design.md`). Runs AFTER the L0 plan (`2026-09-30-ledger-l0.md`) is complete on the same branch.

## Global Constraints

- Typed GDScript; no GDScript warnings (unused params/locals; an intentional integer division carries `@warning_ignore("integer_division")` on the line before it).
- Every tuning number is a `balance.csv` row; every new table a CSV under `data/`.
- **Invariant 2**: no RNG, no clock; every loop over regiments or cells in sorted order.
- **Invariant 3**: new engine classes are `RefCounted`, no Node, no `Game.`; `tests/engine/test_engine_isolation.gd` must keep passing.
- **Invariant 4**: every metric change carries a reason (the tick's `_apply(r, m, metric, delta, reason)`).
- **Invariant 8**: the new order `WORKSHOP_RATE` has rows in `policy_actions_court_additions.csv`, `action_signatures.csv` and `order_costs.csv`.
- **Invariant 11**: pools move in whole gold; no float reaches a metric except through `float(int)`.
- Repo files English; commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Run one test: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/<dir>/<file>.gd -gexit`. Full suite: `./run_tests.sh` (in this worktree the known pre-existing failure is `test_map3d_layers.gd::test_a_camera_move_refreshes_the_houses`, which needs the git-ignored built world; any OTHER failure is ours). After adding a `class_name` file run `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import` once.

## Review Focus

1. **A regiment standing exactly at the depot** (the capital) — a zero-length road must give loss 0, not a division error. Pinned in Task 3 (`test_a_regiment_at_the_depot_loses_nothing`).
2. **Empty pools** — no strategic goods anywhere: nothing ships, nothing is paid, supplies only fall, morale sinks. Pinned in Task 3 (`test_empty_pools_ship_nothing`) and Task 4.
3. **A workshop whose lord's civil goods run out mid-list** — later workshops take what is left, never below zero. Pinned in Task 1 (`test_the_lords_civil_goods_run_out_in_cell_order`).
4. **An old save** with no `workshop_rate` key — loads with every workshop at full. Pinned in Task 1 (`test_workshop_rates_survive_a_save`).
5. **A fleet** — never supplied, never drifts. Pinned in Task 3 and Task 4.

---

### Task 1: The war workshop — data, `WorkshopSystem`, the tick

**Files:**
- Modify: `data/manor_buildings.csv` (append a row), `data/resource_icons.csv` (append a row), `data/balance.csv` (append), `scripts/engine/game_state.gd` (field + save), `scripts/engine/tick_engine.gd` (`advance`)
- Create: `scripts/engine/workshop_system.gd`
- Test: `tests/engine/test_workshop_system.gd`

**Interfaces:**
- Produces: `WorkshopSystem.BUILDING := "war_workshop"`; `cells(state) -> Array[int]` (sorted); `rate_of(state, cell: int) -> int`; `set_rate(state, cell: int, rate: int) -> void`; `rate_word(rate: int) -> String`; `plan(repo, state) -> Array` of `{cell: int, rate: int, take: int, make: int}`; `settle_month(repo, state) -> Array` of `{metric: String, delta: int, reason: String}`. `GameState.workshop_rate: Dictionary` (cell String → permille; only rates away from 1000).

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/engine/test_workshop_system.gd
extends GutTest
## The war workshop (spec 2026-09-30-ledger-supply-design §2): the lord's
## civil goods into strategic goods, capacity × rate, at a loss.

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	assert_not_null(data, DataRepository.last_error)
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func _home_cells(n: int) -> Array:
	var cells: Array = MapManors.manors_of_province(data, MapManors.home_province(data, s), s)
	return cells.slice(0, n)

func _build(cell: int) -> void:
	assert_true(MapManors.build(data, s, cell, WorkshopSystem.BUILDING, "a test workshop"))

func test_the_building_row_exists() -> void:
	var row: Dictionary = data.manor_buildings["war_workshop"]
	assert_eq(String(row["land"]), "town")
	assert_eq(String(row["prereq"]), "smithy")
	assert_eq(int(row["civil_cost"]), 180)

func test_one_workshop_at_full_takes_its_capacity() -> void:
	var cell: int = _home_cells(1)[0]
	_build(cell)
	s.metrics["lord_civil"] = 100.0
	assert_eq(WorkshopSystem.plan(data, s), [{"cell": cell, "rate": 1000, "take": 40, "make": 28}])

func test_half_rate_halves_it() -> void:
	var cell: int = _home_cells(1)[0]
	_build(cell)
	WorkshopSystem.set_rate(s, cell, 500)
	s.metrics["lord_civil"] = 100.0
	assert_eq(WorkshopSystem.plan(data, s)[0], {"cell": cell, "rate": 500, "take": 20, "make": 14})

func test_the_lords_civil_goods_run_out_in_cell_order() -> void:
	var cells := _home_cells(2)
	for c: int in cells:
		_build(c)
	s.metrics["lord_civil"] = 50.0
	var p := WorkshopSystem.plan(data, s)
	cells.sort()
	assert_eq(p[0]["cell"], cells[0])
	assert_eq([p[0]["take"], p[1]["take"]], [40, 10])
	assert_eq([p[0]["make"], p[1]["make"]], [28, 7])
	s.metrics["lord_civil"] = -5.0
	assert_eq(WorkshopSystem.plan(data, s)[0]["take"], 0, "a debt takes nothing")

func test_settlement_moves_the_goods_with_reasons() -> void:
	var cell: int = _home_cells(1)[0]
	_build(cell)
	s.metrics["lord_civil"] = 100.0
	assert_eq(WorkshopSystem.settle_month(data, s), [
		{"metric": "lord_civil", "delta": -40, "reason": "the war workshops take civil goods"},
		{"metric": "lord_strategic", "delta": 28, "reason": "the war workshops make strategic goods"}])
	WorkshopSystem.set_rate(s, cell, 0)
	assert_eq(WorkshopSystem.settle_month(data, s), [], "a cold workshop moves nothing")

func test_the_tick_runs_the_workshops() -> void:
	var twin := GameState.from_dict(s.to_dict())
	var cell: int = _home_cells(1)[0]
	_build(cell)
	for st: GameState in [s, twin]:
		st.metrics["lord_civil"] = 1000.0
		st.metrics["strategic"] = 100000.0
	var eng := TickEngine.new(data)
	eng.advance(s)
	RealmEconomy.forget()
	eng.advance(twin)
	assert_eq(int(s.metrics["lord_strategic"]) - int(twin.metrics["lord_strategic"]), 28)
	assert_eq(int(s.metrics["lord_civil"]) - int(twin.metrics["lord_civil"]), -40)

func test_workshop_rates_survive_a_save() -> void:
	var cell: int = _home_cells(1)[0]
	WorkshopSystem.set_rate(s, cell, 500)
	var back := GameState.from_dict(s.to_dict())
	assert_eq(WorkshopSystem.rate_of(back, cell), 500)
	WorkshopSystem.set_rate(back, cell, 1000)
	assert_false(back.workshop_rate.has(str(cell)), "full is the default and is not stored")
	var old := s.to_dict()
	old.erase("workshop_rate")
	assert_eq(WorkshopSystem.rate_of(GameState.from_dict(old), cell), 1000, "an old save runs every workshop in full")
```
If `TickEngine.new(data)` / `eng.advance(state)` or `GameState.from_dict(to_dict())` are spelled differently (read `tick_engine.gd:9` `_init(d)` and `:42 advance(state)`, `game_state.gd:302/341`), follow the source.

- [ ] **Step 2: Run it to verify it fails** — Expected: FAIL (`WorkshopSystem` not declared / no `war_workshop` row).

- [ ] **Step 3: Data**

Append to `data/manor_buildings.csv` (columns `building_code,label,tier,land,prereq,cost_gold,civil_cost,build_days,tax_bonus,output_bonus,defence_bonus,church_bonus,gold_per_tick,grain_per_tick,contentment_per_tick,unrest_per_tick,produce_good,produce_units,notes`):
```csv
war_workshop,War workshop,2,town,smithy,60,180,50,0,0,0,0,0,0,0,0,,0,"turns the lord's civil goods into strategic goods each month, as fast as its rate allows (spec 2026-09-30-ledger-supply-design)"
```
The existing test "every building yields" may reject a row with no produce and no bonus: read `tests/engine/` for the test that asserts every building yields (grep `produce_units` in tests) and extend ITS rule to accept a building whose code is `WorkshopSystem.BUILDING` (it yields strategic goods through the workshop system), with a comment saying so.

Append to `data/resource_icons.csv` (header `key,label,icon,tooltip,texture` — no texture until art exists):
```csv
bld_war_workshop,War workshop,hammer,"Turns the lord's civil goods into strategic goods each month, as its rate allows.",
```
(If the `icon` glyph `hammer` is not in `ResourceIcon`'s glyph set, use the glyph the `smithy` row uses.)

Append to `data/balance.csv`:
```csv
workshop_capacity_gold,40,"LEDGER M2 (spec 2026-09-30-ledger-supply-design §2): gold of the lord's civil goods one war workshop takes a month at full rate"
workshop_ratio_permille,700,LEDGER M2: strategic goods made per mille of civil goods taken
```

- [ ] **Step 4: `GameState.workshop_rate`**

In `scripts/engine/game_state.gd`, beside `manor_focus`:
```gdscript
## cell id (String) -> permille (0 or 500) for each war workshop set away
## from full (spec 2026-09-30-ledger-supply-design §2); full is not stored.
var workshop_rate: Dictionary = {}
```
`to_dict()` beside `"manor_focus"` (`:330`): `"workshop_rate": workshop_rate.duplicate(true),`
`from_dict()` beside `s.manor_focus` (`:393`): `s.workshop_rate = d.get("workshop_rate", {}).duplicate(true)  # older saves: every workshop in full`

- [ ] **Step 5: `WorkshopSystem`**

```gdscript
# scripts/engine/workshop_system.gd
class_name WorkshopSystem
extends RefCounted
## The war workshops (spec 2026-09-30-ledger-supply-design §2): each standing
## war workshop turns up to workshop_capacity_gold of the LORD's civil goods
## a month, times its rate, into workshop_ratio_permille as much strategic
## goods. Whole gold, cell order; plan() is the one function the tick, the
## cards and the LEDGER read.

const BUILDING := "war_workshop"
const RATES := [0, 500, 1000]


static func cells(state: GameState) -> Array:
	var out: Array = []
	for key: String in state.manor_buildings:
		if BUILDING in (state.manor_buildings[key] as Array):
			out.append(int(key))
	out.sort()
	return out


static func rate_of(state: GameState, cell: int) -> int:
	return int(state.workshop_rate.get(str(cell), 1000))


static func set_rate(state: GameState, cell: int, rate: int) -> void:
	if rate == 1000:
		state.workshop_rate.erase(str(cell))
	else:
		state.workshop_rate[str(cell)] = rate


static func rate_word(rate: int) -> String:
	match rate:
		0:
			return "cold"
		500:
			return "at half"
	return "in full"


static func plan(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	var left := maxi(int(state.metrics.get("lord_civil", 0.0)), 0)
	var cap := int(repo.bal("workshop_capacity_gold"))
	var ratio := int(repo.bal("workshop_ratio_permille"))
	for cell: int in cells(state):
		var rate := rate_of(state, cell)
		@warning_ignore("integer_division")
		var take := mini(cap * rate / 1000, left)
		left -= take
		@warning_ignore("integer_division")
		var make := take * ratio / 1000
		out.append({"cell": cell, "rate": rate, "take": take, "make": make})
	return out


## The month's lines for the tick to apply (it owns the report).
static func settle_month(repo: DataRepository, state: GameState) -> Array:
	var took := 0
	var made := 0
	for row: Dictionary in plan(repo, state):
		took += int(row["take"])
		made += int(row["make"])
	if took == 0:
		return []
	return [{"metric": "lord_civil", "delta": -took, "reason": "the war workshops take civil goods"},
		{"metric": "lord_strategic", "delta": made, "reason": "the war workshops make strategic goods"}]
```

- [ ] **Step 6: The tick**

In `scripts/engine/tick_engine.gd` `advance()`, right after `_settle_economy(state, r)` (`:47`):
```gdscript
	# The war workshops (spec 2026-09-30-ledger-supply-design §2): this
	# month's civil goods are in; turn the lord's share into arms before the
	# supply lines ship.
	for l: Dictionary in WorkshopSystem.settle_month(data, state):
		_apply(r, state.metrics, String(l["metric"]), float(int(l["delta"])), String(l["reason"]))
```

- [ ] **Step 7: Import, run the test and the tick / building tests** — `--import`, then this test, `test_tick_engine.gd`, and the building-yield test you touched. Expected: PASS.

- [ ] **Step 8: Commit** — `feat(workshop): the war workshop turns the lord's civil goods into strategic goods`

---

### Task 2: The `WORKSHOP_RATE` order

**Files:**
- Modify: `data/policy_actions_court_additions.csv`, `data/action_signatures.csv`, `data/order_costs.csv`, `scripts/engine/action_system.gd` (validate + execute)
- Test: `tests/engine/test_workshop_orders.gd`

**Interfaces:**
- Consumes: `WorkshopSystem` (Task 1), `ActionSystem.manor_of(req) -> int` (reads `params.manor` or `params.cell`).
- Produces: order `WORKSHOP_RATE {cell | manor, rate: 0|500|1000}`.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/engine/test_workshop_orders.gd
extends GutTest
## WORKSHOP_RATE (spec 2026-09-30-ledger-supply-design §2).

var data: DataRepository
var s: GameState
var sys: ActionSystem
var cell := -1

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	sys = ActionSystem.new(data)
	cell = int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[0])
	MapManors.build(data, s, cell, WorkshopSystem.BUILDING, "a test workshop")

func test_the_rate_is_set_and_costs_the_stewards_goodwill() -> void:
	var req := ActionRequest.make("WORKSHOP_RATE", {"cell": cell, "rate": 500})
	assert_eq(sys.validate(req, s), "")
	var before := OrderCosts.snapshot_opinions(s)
	var out := sys.execute(req, s)
	assert_eq(WorkshopSystem.rate_of(s, cell), 500)
	assert_true(OrderCosts.has_cost(data, s, out["effects"], out["drift"], before), "the order left a cost")

func test_refusals() -> void:
	assert_ne(sys.validate(ActionRequest.make("WORKSHOP_RATE", {"cell": cell, "rate": 700}), s), "", "no such rate")
	assert_ne(sys.validate(ActionRequest.make("WORKSHOP_RATE", {"cell": cell, "rate": 1000}), s), "", "already in full")
	var bare := int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[1])
	assert_string_contains(sys.validate(ActionRequest.make("WORKSHOP_RATE", {"cell": bare, "rate": 0}), s), "no war workshop")

func test_the_order_is_catalogued() -> void:
	assert_true(data.actions.has("WORKSHOP_RATE"))
	assert_true(data.order_costs.has("WORKSHOP_RATE"))
```

- [ ] **Step 2: Run it** — Expected: FAIL (`Unknown action: WORKSHOP_RATE`).

- [ ] **Step 3: Catalogue rows**

`data/policy_actions_court_additions.csv`:
```csv
WORKSHOP_RATE,economy,Set a war workshop's rate,none,0.5,none,0,0,,workshop_rate,6,yes,no,"params: cell (or manor), rate (0|500|1000). How much of the lord's civil goods a war workshop turns into strategic goods each month (spec 2026-09-30-ledger-supply-design §2)."
```
`data/action_signatures.csv`: `WORKSHOP_RATE,,0,5,0,0,0,civil goods turned to arms`
`data/order_costs.csv`: `WORKSHOP_RATE,opinion:steward:-1:the workshop's reeve re-sets his fires,1,`

- [ ] **Step 4: Validate and execute**

Read `action_system.gd` `validate` for `MANOR_FOCUS` (`:250-265`) and how its branch gets `cell`, `label` and `crowns`; add a `WORKSHOP_RATE` branch in the same place, reusing them:
```gdscript
		"WORKSHOP_RATE":
			if not WorkshopSystem.BUILDING in MapManors.buildings_of(state, cell):
				return "%s has no war workshop" % label
			var rate := int(req.params.get("rate", -1))
			if not rate in WorkshopSystem.RATES:
				return "A war workshop runs cold, at half or in full"
			if rate == WorkshopSystem.rate_of(state, cell):
				return "The war workshop at %s already runs %s" % [label, WorkshopSystem.rate_word(rate)]
```
and in `execute` beside `MANOR_FOCUS` (`:409-419`):
```gdscript
		"WORKSHOP_RATE":
			var cell := manor_of(req)
			var rate := int(req.params["rate"])
			WorkshopSystem.set_rate(state, cell, rate)
			effects.append({"metric": "manor", "delta": 0.0, "reason": "the war workshop at %s now runs %s"
				% [MapManors.label_of(data, cell), WorkshopSystem.rate_word(rate)]})
```
If the manor-order preamble refuses orders on manors outside the crown's hold before reaching the branch, keep that — a workshop is only ever the crown's.

- [ ] **Step 5: Run it, then `tests/engine/test_order_costs.gd`** — Expected: PASS.

- [ ] **Step 6: Commit** — `feat(workshop): WORKSHOP_RATE sets how hard a workshop works`

---

### Task 3: Supply lines — `SupplySystem`

**Files:**
- Create: `scripts/engine/supply_system.gd`
- Modify: `data/balance.csv`, `scripts/engine/tick_engine.gd` (`advance`, before `ArmySystem.settle_month`)
- Test: `tests/engine/test_supply_system.gd`

**Interfaces:**
- Consumes: `ArmySystem.regiment / position_of / supply_use / order_of / ORDER_GARRISON / pack_to_metres / supply_score`, `CourierSystem.origin / path_between` (path entries `[x_m, y_m, kind]`), `MapEconomy.cell_at`, `MapManors.province_of / crown_controls`.
- Produces: `SupplySystem.loss_of(repo, km: int) -> int`; `ship_for(short: int, loss: int) -> int`; `share(avail: int, golds: Array) -> Array`; `stronghold_of(repo, state, code) -> String` (the town a garrison draws on, `""` if none); `line_of(repo, state, code) -> {length_km, loss_permille, garrison: bool, stronghold}`; `plan(repo, state) -> Array` of `{code, need, ship, gold, paid, delivered, loss_permille, length_km, garrison, stronghold}` (land regiments of `state.regiments`, code order); `settle_month(repo, state) -> Array` of tick lines; `any_hungry(repo, state) -> bool`.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/engine/test_supply_system.gd
extends GutTest
## Supply lines (spec 2026-09-30-ledger-supply-design §3).

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func _land_codes() -> Array:
	var out: Array = []
	for c in s.regiments.keys():
		if String(ArmySystem.regiment(data, String(c)).get("is_naval", "0")) != "1":
			out.append(String(c))
	out.sort()
	return out

func _place(code: String, px: Vector2) -> void:
	var m := ArmySystem.pack_to_metres(data, px)
	s.regiments[code]["x_m"] = m.x
	s.regiments[code]["y_m"] = m.y
	s.regiments[code]["dest_x_m"] = m.x
	s.regiments[code]["dest_y_m"] = m.y

func test_the_loss_grows_with_the_road_and_is_capped() -> void:
	assert_eq(SupplySystem.loss_of(data, 0), 0)
	assert_eq(SupplySystem.loss_of(data, 100), 60)
	assert_eq(SupplySystem.loss_of(data, 250), 150)
	assert_eq(SupplySystem.loss_of(data, 5000), 600)

func test_what_is_shipped_covers_what_the_road_loses() -> void:
	assert_eq(SupplySystem.ship_for(90, 100), 100)
	assert_eq(SupplySystem.ship_for(0, 300), 0)
	assert_eq(SupplySystem.ship_for(7, 0), 7)

func test_a_short_pool_is_shared_by_need() -> void:
	assert_eq(SupplySystem.share(50, [60, 40]), [30, 20])
	assert_eq(SupplySystem.share(0, [60, 40]), [0, 0])
	assert_eq(SupplySystem.share(500, [60, 40]), [60, 40], "enough for all: each paid in full")

func test_a_regiment_at_the_depot_loses_nothing() -> void:
	var code: String = _land_codes()[0]
	_place(code, CourierSystem.origin(data, s))
	var line := SupplySystem.line_of(data, s, code)
	assert_eq(int(line["length_km"]), 0)
	assert_eq(int(line["loss_permille"]), 0)

func test_a_garrison_in_the_crowns_province_draws_on_its_town() -> void:
	var code: String = _land_codes()[0]
	var home := MapManors.home_province(data, s)
	var p: Dictionary = data.provinces[home]
	_place(code, Vector2(float(p["center_x"]), float(p["center_y"])))
	s.regiments[code]["order"] = ArmySystem.ORDER_GARRISON
	var line := SupplySystem.line_of(data, s, code)
	assert_true(line["garrison"])
	assert_eq(String(line["stronghold"]), String(p["capital_burg"]))
	assert_eq(int(line["loss_permille"]), 0)

func test_a_hungry_regiment_is_refilled_to_its_target() -> void:
	var code: String = _land_codes()[0]
	s.regiments[code]["supplies"] = 0
	s.metrics["strategic"] = 1000000.0
	var use := ArmySystem.supply_use(data, ArmySystem.regiment(data, code))
	var target := use * int(data.bal("army_supply_target_months"))
	var before := int(s.metrics["strategic"])
	var lines := SupplySystem.settle_month(data, s)
	assert_eq(int(s.regiments[code]["supplies"]), target)
	var paid := 0
	for l: Dictionary in lines:
		if String(l["metric"]) == "strategic":
			paid = -int(l["delta"])
	assert_gt(paid, 0)
	assert_eq(int(s.metrics["strategic"]), before, "settle_month returns lines; the tick applies them")

func test_empty_pools_ship_nothing() -> void:
	s.metrics["strategic"] = 0.0
	s.metrics["lord_strategic"] = 0.0
	var code: String = _land_codes()[0]
	s.regiments[code]["supplies"] = 0
	assert_eq(SupplySystem.settle_month(data, s), [])
	assert_eq(int(s.regiments[code]["supplies"]), 0)

func test_the_crown_pays_first_then_the_lord() -> void:
	for c in _land_codes():
		s.regiments[c]["supplies"] = 0
	s.metrics["strategic"] = 10.0
	s.metrics["lord_strategic"] = 1000000.0
	var lines := SupplySystem.settle_month(data, s)
	assert_eq(lines[0], {"metric": "strategic", "delta": -10, "reason": "supplies sent to the host"})
	assert_eq(String(lines[1]["metric"]), "lord_strategic")

func test_fleets_are_never_supplied() -> void:
	for row: Dictionary in SupplySystem.plan(data, s):
		assert_ne(String(ArmySystem.regiment(data, String(row["code"])).get("is_naval", "0")), "1")

func test_the_plan_is_deterministic() -> void:
	assert_eq_deep(SupplySystem.plan(data, s), SupplySystem.plan(data, s))

func test_full_supply_costs_about_half_the_crowns_strategic_intake() -> void:
	# The calibration of army_supply_gold_permille (spec §3): refilling every
	# land regiment's month of use, road losses included, against what the
	# crown and the lord take in strategic goods a month.
	var monthly := 0
	for code: String in _land_codes():
		var use := ArmySystem.supply_use(data, ArmySystem.regiment(data, code))
		var ship := SupplySystem.ship_for(use, int(SupplySystem.line_of(data, s, code)["loss_permille"]))
		monthly += SupplySystem.gold_for(data, ship)
	var p := RealmEconomy.purses(data, s)
	var intake := int(p["lord"]["strategic"]) + int(p["realm_share"]["strategic"])
	gut.p("full supply %d gold a month against a strategic intake of %d" % [monthly, intake])
	assert_between(float(monthly) / float(maxi(intake, 1)), 0.3, 0.7)
```

- [ ] **Step 2: Run it** — Expected: FAIL (`SupplySystem` not declared).

- [ ] **Step 3: Balance rows**

```csv
army_supply_gold_permille,100,"LEDGER M1 (spec 2026-09-30-ledger-supply-design §3): gold per mille a supply unit costs; calibrated so refilling the realm's regiments costs about half the crown's and lord's monthly strategic intake (test_supply_system)"
army_supply_target_months,3,LEDGER M1: months of its own use a regiment is refilled to each month
army_supply_loss_permille_per_100km,60,LEDGER M1: supplies lost on the road per mille for every 100 km of it
army_supply_loss_cap_permille,600,LEDGER M1: the most a road can lose
army_supply_warn_permille,500,"LEDGER M1: a regiment whose supply score is under this is hungry (TriggerDsl host_hungry, the hungry_host loop)"
```

- [ ] **Step 4: Write `SupplySystem`**

```gdscript
# scripts/engine/supply_system.gd
class_name SupplySystem
extends RefCounted
## Supply lines (spec 2026-09-30-ledger-supply-design §3): each land
## regiment of the realm is refilled every month to army_supply_target_months
## of its own use, shipped from the depot (CourierSystem.origin) over the
## road network to where it stands NOW; the road loses
## army_supply_loss_permille_per_100km per 100 km (capped). A garrison in a
## province the crown controls draws through its town: no road, no loss.
## The crown's strategic goods pay first, then the lord's; a short pool is
## shared by need. Whole numbers, code order. plan() is the one function
## the tick, the regiment card and the LEDGER read.


static func loss_of(repo: DataRepository, km: int) -> int:
	@warning_ignore("integer_division")
	var loss := km * int(repo.bal("army_supply_loss_permille_per_100km")) / 100
	return mini(loss, int(repo.bal("army_supply_loss_cap_permille")))


## Units to ship so that `short` arrive after a `loss` per mille.
static func ship_for(short: int, loss: int) -> int:
	if short <= 0:
		return 0
	var keep := 1000 - loss
	@warning_ignore("integer_division")
	return (short * 1000 + keep - 1) / keep


static func gold_for(repo: DataRepository, units: int) -> int:
	@warning_ignore("integer_division")
	return (units * int(repo.bal("army_supply_gold_permille")) + 999) / 1000


static func share(avail: int, golds: Array) -> Array:
	var total := 0
	for g: int in golds:
		total += g
	if total <= avail:
		return golds.duplicate()
	var out: Array = []
	for g: int in golds:
		@warning_ignore("integer_division")
		out.append(maxi(avail, 0) * g / total)
	return out


## The town a garrison draws on: a regiment under a GARRISON order standing
## in a province the crown controls draws on that province's capital town.
static func stronghold_of(repo: DataRepository, state: GameState, code: String) -> String:
	if ArmySystem.order_of(repo, state, code) != ArmySystem.ORDER_GARRISON:
		return ""
	var cell := MapEconomy.cell_at(repo, ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code)))
	if cell < 0:
		return ""
	var prov := MapManors.province_of(repo, cell, state)
	if prov == "" or not MapManors.crown_controls(repo, state, prov):
		return ""
	return String((repo.provinces.get(prov, {}) as Dictionary).get("capital_burg", ""))


static func line_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var town := stronghold_of(repo, state, code)
	if town != "":
		return {"length_km": 0, "loss_permille": 0, "garrison": true, "stronghold": town}
	var from := CourierSystem.origin(repo, state)
	var to := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code))
	var metres := 0.0
	var path := CourierSystem.path_between(repo, from, to)
	if path.size() >= 2:
		for i in range(1, path.size()):
			metres += Vector2(float(path[i - 1][0]), float(path[i - 1][1])).distance_to(
				Vector2(float(path[i][0]), float(path[i][1])))
	else:
		metres = Vector2(ArmySystem.pack_to_metres(repo, from)).distance_to(Vector2(ArmySystem.pack_to_metres(repo, to)))
	var km := int(metres / 1000.0)
	return {"length_km": km, "loss_permille": loss_of(repo, km), "garrison": false, "stronghold": ""}


static func _land_codes(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	for c in state.regiments.keys():
		var reg := ArmySystem.regiment(repo, String(c))
		if not reg.is_empty() and String(reg.get("is_naval", "0")) != "1":
			out.append(String(c))
	out.sort()
	return out


static func plan(repo: DataRepository, state: GameState) -> Array:
	var rows: Array = []
	var golds: Array = []
	for code: String in _land_codes(repo, state):
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code))
		var target := use * int(repo.bal("army_supply_target_months"))
		var short := maxi(target - int(state.regiments[code]["supplies"]), 0)
		var line := line_of(repo, state, code)
		var loss := int(line["loss_permille"])
		var ship := ship_for(short, loss)
		var gold := gold_for(repo, ship)
		golds.append(gold)
		rows.append({"code": code, "need": short, "ship": ship, "gold": gold, "paid": 0, "delivered": 0,
			"loss_permille": loss, "length_km": int(line["length_km"]), "garrison": bool(line["garrison"]),
			"stronghold": String(line["stronghold"])})
	var avail := maxi(int(state.metrics.get("strategic", 0.0)), 0) + maxi(int(state.metrics.get("lord_strategic", 0.0)), 0)
	var paid := share(avail, golds)
	var price := int(repo.bal("army_supply_gold_permille"))
	for i in rows.size():
		var row: Dictionary = rows[i]
		row["paid"] = int(paid[i])
		@warning_ignore("integer_division")
		var units := int(row["ship"]) if int(paid[i]) >= int(row["gold"]) else int(paid[i]) * 1000 / maxi(price, 1)
		@warning_ignore("integer_division")
		row["delivered"] = mini(units * (1000 - int(row["loss_permille"])) / 1000, int(row["need"]))
	return rows


## The month's shipment: supplies land on each regiment now; the pool lines
## are returned for the tick to apply with its report (crown first, then
## the lord).
static func settle_month(repo: DataRepository, state: GameState) -> Array:
	var total := 0
	for row: Dictionary in plan(repo, state):
		total += int(row["paid"])
		var entry: Dictionary = state.regiments[String(row["code"])]
		entry["supplies"] = int(entry["supplies"]) + int(row["delivered"])
	if total == 0:
		return []
	var crown := mini(maxi(int(state.metrics.get("strategic", 0.0)), 0), total)
	var lines: Array = []
	if crown > 0:
		lines.append({"metric": "strategic", "delta": -crown, "reason": "supplies sent to the host"})
	if total - crown > 0:
		lines.append({"metric": "lord_strategic", "delta": -(total - crown), "reason": "supplies sent to the host"})
	return lines


## Any land regiment under army_supply_warn_permille (TriggerDsl host_hungry).
static func any_hungry(repo: DataRepository, state: GameState) -> bool:
	for code: String in _land_codes(repo, state):
		if ArmySystem.bars_of(repo, state, code).y < int(repo.bal("army_supply_warn_permille")):
			return true
	return false
```
Read `ArmySystem.pack_to_metres` (`army_system.gd:383`, returns `Vector2i`) and `CourierSystem.path_between` (`courier_system.gd:86`) to confirm the path entries are `[x_m, y_m, kind]` in the same metres before relying on the sum; if the entries are `Vector2`/`Vector2i`, sum those instead.

Note the settle test: `settle_month` writes supplies but returns the pool lines — the pools are debited by the tick's `_apply` — so `test_a_hungry_regiment_is_refilled_to_its_target` checks the pool is untouched by `settle_month` itself.

- [ ] **Step 5: The tick**

In `tick_engine.gd` `advance()`, immediately before `ArmySystem.settle_month(data, state)` (`:59`):
```gdscript
	# The supply lines (spec 2026-09-30-ledger-supply-design §3): the host is
	# refilled before its month is spent.
	for l: Dictionary in SupplySystem.settle_month(data, state):
		_apply(r, state.metrics, String(l["metric"]), float(int(l["delta"])), String(l["reason"]))
```
Also update `ArmySystem.settle_month`'s doc comment ("nothing resupplies yet" → "the supply lines refill it first, SupplySystem").

- [ ] **Step 6: Calibrate**

Run the test. If `test_full_supply_costs_about_half_the_crowns_strategic_intake` fails, read the printed `full supply N gold a month against a strategic intake of M`, set `army_supply_gold_permille` in `balance.csv` to `round(100 × 0.5 × M / N)` (keep it ≥ 1), note the measured N and M in that row's notes, and re-run until it passes.

- [ ] **Step 7: Run this test, `test_tick_engine.gd`, `test_army_*.gd`** — Expected: PASS (an army test that assumed supplies never rise across a tick must be updated to the new rule, with a comment).

- [ ] **Step 8: Commit** — `feat(supply): supply lines refill the host from the capital, losing a share by road`

---

### Task 4: Morale follows the stores; the regiment card; `host_hungry`

**Files:**
- Create: `data/army_morale_words.csv`
- Modify: `data/balance.csv`, `data/resource_icons.csv`, `scripts/engine/data_repository.gd` (load the words), `scripts/engine/army_system.gd` (`settle_month`, helpers), `scripts/engine/map_objects.gd` (`army_card`), `scripts/engine/trigger_dsl.gd` (`_clause`)
- Test: `tests/engine/test_army_morale.gd`, `tests/engine/test_trigger_dsl.gd` (add a case)

**Interfaces:**
- Produces: `ArmySystem.morale_mark(repo, score: int, garrison: bool) -> int`, `ArmySystem.drift_morale(morale: int, mark: int, step: int) -> int`, `ArmySystem.morale_word(repo, score: int) -> String`; `DataRepository.army_morale_words: Array` (rows `{min_score: int, word: String}`, highest first); TriggerDsl clause `host_hungry`; army card stat `army_supply_line`.

- [ ] **Step 1: Write the failing tests**

```gdscript
# tests/engine/test_army_morale.gd
extends GutTest
## Morale follows the stores (spec 2026-09-30-ledger-supply-design §4).

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func test_the_mark_rises_with_the_stores() -> void:
	assert_eq(ArmySystem.morale_mark(data, 0, false), 20)
	assert_eq(ArmySystem.morale_mark(data, 500, false), 47)
	assert_eq(ArmySystem.morale_mark(data, 1000, false), 75)
	assert_eq(ArmySystem.morale_mark(data, 1000, true), 80, "a garrison stands a little taller")

func test_morale_drifts_toward_its_mark_and_stops_there() -> void:
	assert_eq(ArmySystem.drift_morale(70, 47, 6), 64)
	assert_eq(ArmySystem.drift_morale(40, 47, 6), 46)
	assert_eq(ArmySystem.drift_morale(45, 47, 6), 47)
	assert_eq(ArmySystem.drift_morale(47, 47, 6), 47)

func test_a_fed_regiment_climbs_a_starving_one_sinks() -> void:
	var codes: Array = []
	for c in s.regiments.keys():
		if String(ArmySystem.regiment(data, String(c)).get("is_naval", "0")) != "1":
			codes.append(String(c))
	codes.sort()
	var fed: String = codes[0]
	var starving: String = codes[1]
	var use := ArmySystem.supply_use(data, ArmySystem.regiment(data, fed))
	s.regiments[fed]["supplies"] = use * 3
	s.regiments[fed]["morale"] = 60
	s.regiments[starving]["supplies"] = 0
	s.regiments[starving]["morale"] = 60
	ArmySystem.settle_month(data, s)
	assert_eq(int(s.regiments[fed]["morale"]), 66, "full stores: the mark is 75, one step of 6")
	assert_eq(int(s.regiments[starving]["morale"]), 54, "empty stores: the mark is 20")

func test_the_words_name_the_stores() -> void:
	assert_eq(ArmySystem.morale_word(data, 1000), "well fed")
	assert_eq(ArmySystem.morale_word(data, 500), "on short rations")
	assert_eq(ArmySystem.morale_word(data, 0), "starving")

func test_the_regiment_card_states_its_supply_line() -> void:
	var code := String(s.regiments.keys()[0])
	var keys: Array = []
	for st: Dictionary in MapObjects.army_card(data, code, s)["stats"]:
		keys.append(String(st["key"]))
	assert_has(keys, "army_supply_line")
```
(`army_speed_supply_full_months` is 3, so `use × 3` scores 1000.)

In `tests/engine/test_trigger_dsl.gd` add:
```gdscript
func test_host_hungry_reads_the_regiments() -> void:
	var data := DataRepository.load_all("res://data")
	var s := GameState.new_campaign(data, 42)
	for c in s.regiments.keys():
		s.regiments[c]["supplies"] = 0
	assert_true(TriggerDsl.evaluate("host_hungry", s, data))
	for c in s.regiments.keys():
		s.regiments[c]["supplies"] = 1000000
	assert_false(TriggerDsl.evaluate("host_hungry", s, data))
```
(Follow that file's own fixture style if it already builds `data`/`s` in `before_each`.)

- [ ] **Step 2: Run them** — Expected: FAIL.

- [ ] **Step 3: Data**

`data/army_morale_words.csv`:
```csv
min_score,word,notes
800,well fed,supply score per mille at or above which the ranks eat well (spec 2026-09-30-ledger-supply-design §4)
400,on short rations,
0,starving,
```
`balance.csv`:
```csv
army_morale_starving,20,"LEDGER M1 (spec 2026-09-30-ledger-supply-design §4): the morale a regiment with no stores sinks toward"
army_morale_fed,75,LEDGER M1: the morale a regiment with full stores climbs toward
army_morale_garrison_bonus,5,LEDGER M1: a garrison's mark stands this much higher
army_morale_drift_per_month,6,LEDGER M1: points morale moves toward its mark a month
```
`resource_icons.csv` (no texture):
```csv
army_supply_line,Supply line,wagon,"The road the regiment's supplies travel from the capital and the share they lose on the way; a garrison in the crown's own province draws on its town (spec 2026-09-30-ledger-supply-design).",
```
(Use an existing glyph if `wagon` is not one; `army_height` uses `tower`.)

`DataRepository`: field `var army_morale_words: Array = []` and in `_load` beside the other `army_*` tables:
```gdscript
	if not _load_if_present(dir + "/army_morale_words.csv", ["min_score", "word"],
			func(r): army_morale_words.append({"min_score": int(r["min_score"]), "word": String(r["word"])})):
		return false
	army_morale_words.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["min_score"]) > int(b["min_score"]))
```

- [ ] **Step 4: `ArmySystem`**

Add:
```gdscript
## Where a regiment's morale is heading (spec 2026-09-30-ledger-supply-design
## §4): from army_morale_starving with no stores to army_morale_fed with
## full ones, higher in garrison.
static func morale_mark(repo: DataRepository, score: int, garrison: bool) -> int:
	var lo := int(repo.bal("army_morale_starving"))
	var hi := int(repo.bal("army_morale_fed"))
	@warning_ignore("integer_division")
	var mark := lo + (hi - lo) * clampi(score, 0, 1000) / 1000
	if garrison:
		mark += int(repo.bal("army_morale_garrison_bonus"))
	return clampi(mark, 0, 100)


static func drift_morale(morale: int, mark: int, step: int) -> int:
	if morale < mark:
		return mini(morale + step, mark)
	return maxi(morale - step, mark)


static func morale_word(repo: DataRepository, score: int) -> String:
	for row: Dictionary in repo.army_morale_words:
		if score >= int(row["min_score"]):
			return String(row["word"])
	return ""
```
In `settle_month`, replace the supplies line with:
```gdscript
		var use := supply_use(repo, reg)
		if String(reg.get("is_naval", "0")) != "1":
			# Morale reads the stores in hand as the month turns, after the
			# supply lines refilled them and before the month is eaten.
			var mark := morale_mark(repo, supply_score(repo, int(entry["supplies"]), use),
				SupplySystem.stronghold_of(repo, state, code) != "")
			entry["morale"] = drift_morale(int(entry["morale"]), mark, int(repo.bal("army_morale_drift_per_month")))
		entry["supplies"] = maxi(0, int(entry["supplies"]) - use)
```
and update its doc comment: "wounded return, morale drifts toward what its stores allow, supplies are spent, training grows".

- [ ] **Step 5: The card**

In `MapObjects.army_card`, after the `army_height` stat (`:1108-1115`), for a regiment of the player's realm that is not naval:
```gdscript
	if state != null and state.regiments.has(code) and String(r.get("is_naval", "0")) != "1":
		var line := SupplySystem.line_of(repo, state, code)
		var st := ArmySystem.state_of(repo, state, code)
		var word := ArmySystem.morale_word(repo, ArmySystem.supply_score(repo, int(st["supplies"]),
			ArmySystem.supply_use(repo, r)))
		if bool(line["garrison"]):
			var town := String((repo.burgs.get(String(line["stronghold"]), {}) as Dictionary).get("label", ""))
			stats.append(_stat("army_supply_line", "in garrison",
				"Supplied through %s — no road to lose them on; the ranks are %s" % [town, word]))
		else:
			stats.append(_stat("army_supply_line", "%d km · %d%% lost" % [int(line["length_km"]),
				int(line["loss_permille"]) / 10],
				"Supplied from the capital over %d km of road, which loses %d%% of every shipment; the ranks are %s"
				% [int(line["length_km"]), int(line["loss_permille"]) / 10, word]))
```
(Use the names `army_card` already uses for the regiment row and state — read `:1062-1136`; add `@warning_ignore("integer_division")` where needed.)

- [ ] **Step 6: `TriggerDsl`**

In `_clause` before the `"<" in c` fallback, and rename the unused `_data` parameter to `data`:
```gdscript
	if c == "host_hungry":
		return SupplySystem.any_hungry(data, state)
```

- [ ] **Step 7: Run both tests, the army and map-object tests** — Expected: PASS.

- [ ] **Step 8: Commit** — `feat(army): morale follows the stores; the card states the supply line`

---

### Task 5: The LEDGER lights the chain

**Files:**
- Modify: `data/ledger_object_types.csv`, `data/ledger_link_types.csv`, `data/ledger_actions.csv`, `data/ledger_loops.csv`, `scripts/engine/ledger_resolvers.gd`, `tests/engine/test_ledger_snapshot.gd` (the planned-link example moves), `docs/superpowers/specs/2026-09-30-ledger-ontology-design.md` (§2 / §3 rows)
- Test: `tests/engine/test_ledger_supply.gd`

**Interfaces:**
- Consumes: `WorkshopSystem.cells / plan / rate_of`, `SupplySystem.plan / stronghold_of`, Task-2-of-L0 `LedgerResolvers` conventions.
- Produces: live types `workshop` (instances `workshops`, ids `workshop:<cell>`), `supply_line` (instances `supply_lines`, ids `supply_line:<regiment>`); live links `converts_in`, `converts_out`, `supplies_in`, `supplies_out`, `garrisons` (regiment → town); loop `hungry_host`; `workshop` orders.
- **Gauges** (added by the L0 final review, not yet specified in the steps below): supplies and morale inside a regiment's sphere, stock inside a pool's — spec 2026-09-30-ledger-ontology-design §6.3 (its "a property" row; §12 records it as M1's). L0 draws no gauge.
- Note (L0 final fix M2): `Ledger.params_of` already returns a numeric `@id` as an int, so `{"cell": cell, "rate": 0}` below holds as written.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/engine/test_ledger_supply.gd
extends GutTest
## The LEDGER reads the supply chain from its one plan each (spec
## 2026-09-30-ledger-supply-design §5).

var data: DataRepository
var s: GameState
var cell := -1

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()
	cell = int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[0])
	MapManors.build(data, s, cell, WorkshopSystem.BUILDING, "a test workshop")
	s.metrics["lord_civil"] = 100.0

func after_each() -> void:
	RealmEconomy.forget()

func _link(snap: Dictionary, type: String) -> Dictionary:
	for l: Dictionary in snap["links"]:
		if String(l["type"]) == type:
			return l
	return {}

func test_the_ontology_stays_clean() -> void:
	assert_eq(Ledger.validate(data), [] as Array[String])

func test_the_workshop_threads_carry_its_plan() -> void:
	var snap := Ledger.snapshot(data, s, "economy", {})
	assert_eq(int(_link(snap, "converts_in")["flow"]), 40)
	assert_eq(int(_link(snap, "converts_out")["flow"]), 28)
	var ego := Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell})
	assert_eq(String(_link(ego, "converts_in")["from"]), "type:civil_goods")

func test_a_regiments_supply_line_is_its_plan() -> void:
	var row: Dictionary = SupplySystem.plan(data, s)[0]
	var code := String(row["code"])
	var ego := Ledger.snapshot(data, s, "war", {"id": "regiment:" + code})
	var out := _link(ego, "supplies_out")
	assert_eq(String(out["from"]), "supply_line:" + code)
	assert_eq(out["flow"], int(row["delivered"]))

func test_a_garrison_stands_in_its_town() -> void:
	var code := String(SupplySystem.plan(data, s)[0]["code"])
	var home := MapManors.home_province(data, s)
	var p: Dictionary = data.provinces[home]
	var m := ArmySystem.pack_to_metres(data, Vector2(float(p["center_x"]), float(p["center_y"])))
	s.regiments[code]["x_m"] = m.x
	s.regiments[code]["y_m"] = m.y
	s.regiments[code]["order"] = ArmySystem.ORDER_GARRISON
	var g := _link(Ledger.snapshot(data, s, "war", {"id": "regiment:" + code}), "garrisons")
	assert_eq(String(g["to"]), "town:" + String(p["capital_burg"]))

func test_a_workshop_takes_its_rate_orders() -> void:
	var codes := Ledger.actions_for(data, "workshop:%d" % cell).map(func(a: Dictionary) -> String: return String(a["label"]))
	assert_eq(codes, ["Let it go cold", "Run it at half", "Run it in full"])
	var cold: Dictionary = Ledger.actions_for(data, "workshop:%d" % cell)[0]
	assert_eq(Ledger.params_of(cold, "workshop:%d" % cell), {"cell": cell, "rate": 0})

func test_the_hungry_host_loop_runs_when_the_ranks_go_hungry() -> void:
	for c in s.regiments.keys():
		s.regiments[c]["supplies"] = 0
	var running := false
	for lp: Dictionary in Ledger.snapshot(data, s, "war", {})["loops"]:
		if String(lp["id"]) == "hungry_host":
			running = bool(lp["running"])
	assert_true(running)

func test_labels() -> void:
	assert_string_contains(LedgerResolvers.label_of(data, s, "workshop:%d" % cell), "War workshop at")
	assert_eq(LedgerResolvers.label_of(data, s, "workshop:999999999"), "")
	var code := String(SupplySystem.plan(data, s)[0]["code"])
	assert_string_contains(LedgerResolvers.label_of(data, s, "supply_line:" + code), "Supply line to")
```

- [ ] **Step 2: Run it** — Expected: FAIL.

- [ ] **Step 3: Data edits**

`ledger_object_types.csv`:
- `workshop` row → `workshop,things,economy|war|all,War workshops,,1,0,workshops,live,,civil goods made into strategic`
- `supply_line` row → `supply_line,things,war|all,Supply lines,,6.5,0,supply_lines,live,,`
- delete the `stronghold` row (a garrison stands in a TOWN — spec §5)
- `town` row: lenses `economy|war|intelligence|all`

`ledger_link_types.csv`:
- `converts_in,civil_goods,workshop,feeds,economy|war|all,live,converts_in,steward,seat,,,`
- `converts_out,workshop,strategic_goods,makes,economy|war|all,live,converts_out,steward,seat,,,`
- `supplies_in,strategic_goods,supply_line,loads,war|all,live,supplies_in,marshal,seat,,,`
- `supplies_out,supply_line,regiment,supplies,war|all,live,supplies_out,marshal,seat,,,`
- `garrisons,regiment,town,garrisons in,war|all,live,garrisons,marshal,seat,,,`

`ledger_actions.csv`:
```csv
workshop,WORKSHOP_RATE,Let it go cold,cell=@id|rate=0,0
workshop,WORKSHOP_RATE,Run it at half,cell=@id|rate=500,0
workshop,WORKSHOP_RATE,Run it in full,cell=@id|rate=1000,0
```
`ledger_loops.csv`:
```csv
hungry_host,supplies_in|supplies_out,vicious,host_hungry,hunger in the ranks: thin supply lines sink morale and pace
```

- [ ] **Step 4: Resolvers**

In `LedgerResolvers`: add `"converts_in", "converts_out", "supplies_in", "supplies_out", "garrisons"` to `NAMES`, `"workshops", "supply_lines"` to `INSTANCE_LISTS`; dispatch in `run`:
```gdscript
		"converts_in":
			return _workshops(repo, state, id, true)
		"converts_out":
			return _workshops(repo, state, id, false)
		"supplies_in":
			return _supply(repo, state, id, true)
		"supplies_out":
			return _supply(repo, state, id, false)
		"garrisons":
			return _garrisons(repo, state, id)
```
and:
```gdscript
static func _workshops(repo: DataRepository, state: GameState, id: String, inward: bool) -> Array:
	var rows := WorkshopSystem.plan(repo, state)
	var key := "take" if inward else "make"
	if id == "":
		var n := 0
		for row: Dictionary in rows:
			n += int(row[key])
		return [_type_link("civil_goods", "workshop", n, "gold") if inward
			else _type_link("workshop", "strategic_goods", n, "gold")]
	var out: Array = []
	for row: Dictionary in rows:
		var wid := "workshop:%d" % int(row["cell"])
		if id == wid:
			out.append(_link("type:civil_goods", wid, int(row[key]), "gold") if inward
				else _link(wid, "type:strategic_goods", int(row[key]), "gold"))
	return out


static func _supply(repo: DataRepository, state: GameState, id: String, inward: bool) -> Array:
	var rows := SupplySystem.plan(repo, state)
	if id == "":
		var n := 0
		for row: Dictionary in rows:
			n += int(row["paid"] if inward else row["delivered"])
		return [_type_link("strategic_goods", "supply_line", n, "gold") if inward
			else _type_link("supply_line", "regiment", n, "units")]
	var out: Array = []
	for row: Dictionary in rows:
		var code := String(row["code"])
		var line := "supply_line:" + code
		if inward and id == line:
			out.append(_link("type:strategic_goods", line, int(row["paid"]), "gold"))
		elif not inward and (id == line or id == "regiment:" + code):
			out.append(_link(line, "regiment:" + code, int(row["delivered"]), "units"))
	return out


static func _garrisons(repo: DataRepository, state: GameState, id: String) -> Array:
	var codes: Array = state.regiments.keys()
	codes.sort()
	var out: Array = []
	for c in codes:
		var town := SupplySystem.stronghold_of(repo, state, String(c))
		if town == "":
			continue
		var rid := "regiment:" + String(c)
		if id == "" or id == rid or id == "town:" + town:
			out.append(_link(rid, "town:" + town, -1, "count"))
	if id == "":
		return [_type_link("regiment", "town", out.size(), "count")]
	return out
```
In `instances()`:
```gdscript
		"workshops":
			for c: int in WorkshopSystem.cells(state):
				out.append({"id": "workshop:%d" % c, "strain": 1000 - WorkshopSystem.rate_of(state, c)})
		"supply_lines":
			for row: Dictionary in SupplySystem.plan(repo, state):
				out.append({"id": "supply_line:" + String(row["code"]), "strain": int(row["loss_permille"])})
```
In `label_of()`:
```gdscript
		"workshop":
			return "War workshop at " + MapManors.label_of(repo, int(rest)) \
				if int(rest) in WorkshopSystem.cells(state) else ""
		"supply_line":
			var reg := ArmySystem.regiment(repo, rest)
			return "Supply line to " + String(reg["label"]) if not reg.is_empty() and state.regiments.has(rest) else ""
```

- [ ] **Step 5: Move the snapshot test's planned example**

`tests/engine/test_ledger_snapshot.gd::test_the_type_level_draws_every_type_of_its_lens_built_or_not` asserts `type:workshop` and a planned `converts_in` — both are live now. Change it to `type:market` and the planned `trades` link (note "lit by markets and trade routes"), which stay planned until M6.

- [ ] **Step 6: Spec rows** — in `2026-09-30-ledger-ontology-design.md` §2 mark War workshop and Supply lines ✅ (M2 / M1 done), drop the Strongholds row with a note ("a garrison stands in a town — M1"), and in §3 mark `converts`, `supplies`, `garrisons` (now regiment → town) ✅.

- [ ] **Step 7: Run the LEDGER tests** (`test_ledger_*.gd`, `test_ledger_supply.gd`) — Expected: PASS.

- [ ] **Step 8: Commit** — `feat(ledger): the supply chain lights up — workshops, supply lines, garrisons, the hungry host`

---

### Task 6: Documents and the whole suite

- [ ] **Step 1: CLAUDE.md** — after the LEDGER paragraph add:

```markdown
**Supply lines, morale and the war workshop** (LEDGER M1 + M2, 2026-09-30, spec `docs/superpowers/specs/2026-09-30-ledger-supply-design.md`): a `war_workshop` building (tier 2, town, after a smithy) turns up to `workshop_capacity_gold` of the LORD's civil goods a month into `workshop_ratio_permille` as much strategic goods (`WorkshopSystem`, rate by `WORKSHOP_RATE` 0/500/1000, `GameState.workshop_rate`), settled right after the month's economy; then every land regiment is refilled to `army_supply_target_months` of its use from the capital over the road (`SupplySystem`: `army_supply_loss_permille_per_100km`, capped; a GARRISON in a controlled province draws through its town with no loss), the crown's strategic goods paying first, then the lord's, a short pool shared by need; and morale drifts `army_morale_drift_per_month` toward a mark set by the stores in hand as the month turns (`ArmySystem.morale_mark`: `army_morale_starving` … `army_morale_fed`, + `army_morale_garrison_bonus`). Each system has ONE `plan()` the tick, the regiment card (`army_supply_line`) and the LEDGER read; `TriggerDsl`'s `host_hungry` drives the LEDGER's vicious `hungry_host` loop.
```

- [ ] **Step 2: Full suite** — `./run_tests.sh`. Expected: only the known pre-existing `test_map3d_layers` failure.

- [ ] **Step 3: Commit** — `docs(supply): CLAUDE.md records supply lines, morale and the war workshop`
