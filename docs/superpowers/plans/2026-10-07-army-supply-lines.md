# Army Supply Lines Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the monthly capital resupply with carried days (≤30), per-town strategic stores fed by their manors, and player-ordered supply lines that draw daily from one town over the roads, cost daily cartage, can be cut by enemies, and are reported by missive.

**Architecture:** Two new engine-pure modules: `TownStores` (each realm town's `{crown, lord, house}` stores in SUPPLY UNITS, the catchment, the month's deposit, draws, and a reconcile that keeps `metrics.strategic` / `lord_strategic` equal to the towns' sums so every existing writer of those metrics keeps working) and `SupplyLines` (the per-regiment line record, eligibility, the daily step, interception, the month's report). `SupplySystem` keeps its small helpers and becomes a read-only projection for the cards and the LEDGER. The day's step runs in `TickEngine._end_day` after the couriers ride and before the host eats.

**Tech Stack:** Godot 4.7, GDScript (typed), GUT. Data in `data/*.csv`.

**Spec:** `docs/superpowers/specs/2026-10-07-army-supply-lines-design.md`

## Global Constraints

- Engine code under `scripts/engine/` is `RefCounted`, deterministic, names no `Game`, no `scripts/ui/`, no wall clock (`test_engine_isolation.gd`).
- Every tuning number is a `data/balance.csv` key or a CSV row; never a literal in a script.
- Whole numbers only in saved state (no floats); gold changes to the treasury carry a reason.
- Supplies cap: `army_supply_max_days` (30). Low mark: `army_supply_low_days` (5). Rates: 800 / 1000 / 1200 per mille.
- One supply point per regiment; a supply-point order rides by courier to the TOWN; a carry order rides to the regiment.
- Interception: cut on contact (`supply_cut_reach_m`), no rerouting; hostile = a stance listed in `data/army_hostile_stances.csv` (`Enemy`).
- Draw order from a town: `crown`, `lord`, then BUY `house` at value × (1000 + `supply_buy_markup_permille`) / 1000, from the treasury.
- `scripts/map3d/` never reads `Game`; looks live in `.tres`; every visual change goes through the `visual-review` skill with real-window shots.
- Tests read data through `tests/suite_data.gd` (`SuiteData.repo()`, `SuiteData.campaign()`), never `DataRepository.load_all`. Wait with `wait_process_frames` / `wait_until`.
- `./run_tests.sh` must end with the expected engine-error count ("Errors 2" with the gdai binaries installed, 0 without).
- Work only in the worktree `.claude/worktrees/army-supply-lines` (branch `feat/army-supply-lines`); never switch the shared main checkout's branch.

## Measures (read before any task)

- A **supply unit** is the regiments' measure (`ArmySystem.supply_use` units a month). A regiment's DAYS in hand = `supplies × 30 / use` (integer division). Max units = `use × army_supply_max_days / 30`.
- **Town stores are in supply units.** One gold of strategic goods = `1000 / army_supply_gold_permille` units (`TownStores.units_per_gold`, 10 today; a data test asserts the permille divides 1000). A pool's gold = `total_units × army_supply_gold_permille / 1000` (integer division, `TownStores.gold_of_units`).
- `metrics.strategic` = gold of every realm town's `crown` units; `metrics.lord_strategic` = gold of every `lord`. `house` units are in no metric.
- Any writer that changes those two metrics without touching the towns (events, order costs, model deltas, GOODS_BUY/SELL, building inputs) is absorbed by `TownStores.reconcile`: a rise lands in the depot town, a fall is taken from the towns in proportion to their stock (largest remainder, ties by burg code). Reconcile runs at the start of every day's supply step and once at the end of the month's settlement.

## Review Focus

1. **A town captured or lost while a line flows** — the line must cancel that day with a letter, never draw from a foreign town (Task 7 test `test_a_line_whose_town_leaves_the_realm_is_cancelled`).
2. **A pool metric moved by an event or an order cost mid-month** — the towns' sums must follow it exactly at the next reconcile, never drift or go negative (Task 3 test `test_reconcile_follows_a_metric_moved_elsewhere`).
3. **An empty treasury** — house purchases stop, the line still delivers crown/lord goods; cartage may take the treasury below zero like salaries do, never crash (Task 7 test `test_an_empty_treasury_buys_nothing_from_the_house`).
4. **An old save** (no `town_stock`, no `carry_days`, supplies of 4 months) — loads, seeds the towns from the pools, clamps supplies to 30 days (Task 2 / Task 4 migration tests).
5. **A regiment with a line marching out of range, and a fleet** — the line keeps flowing at a growing cost; a fleet can never be given a line (Task 6 refusal test, Task 7 `test_a_line_follows_a_marching_column`).

---

### Task 1: Data — keys, tables, loaders

**Files:**
- Modify: `data/balance.csv` (add keys; leave the retired ones until Task 7 removes their last readers)
- Create: `data/army_carry_loads.csv`, `data/army_supply_orders.csv`, `data/army_hostile_stances.csv`
- Modify: `scripts/engine/data_repository.gd` (fields + loaders, next to `army_route_orders`)
- Modify: `data/CLAUDE.md` (one line per new table)
- Test: `tests/engine/test_army_supply_data.gd`

**Interfaces:**
- Produces: `repo.army_carry_loads: Array` of `{days: int, pace_permille: int, label: String}` sorted by days ascending; `repo.army_supply_orders: Dictionary` key → `{label, hint}`; `repo.army_hostile_stances: Array[String]`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Army supply data (spec 2026-10-07-army-supply-lines §6).

var data: DataRepository

func before_each() -> void:
	data = SuiteData.repo()

func test_the_new_balance_keys_exist() -> void:
	for key in ["army_start_supply_days", "army_supply_low_days", "army_supply_max_days",
			"army_carry_default_days", "army_morale_hungry_day", "army_morale_starving_day",
			"supply_wagon_km_per_day", "supply_point_max_days", "supply_cut_reach_m",
			"supply_cart_milligold_per_unit_km", "supply_buy_markup_permille",
			"supply_warn_town_days", "town_house_stock_months"]:
		assert_true(data.balance.has(key), key)
	assert_eq(int(data.bal("army_supply_max_days")), 30)
	assert_eq(int(data.bal("army_supply_low_days")), 5)

func test_a_gold_of_goods_is_a_whole_number_of_units() -> void:
	var permille := int(data.bal("army_supply_gold_permille"))
	assert_gt(permille, 0)
	assert_eq(1000 % permille, 0, "army_supply_gold_permille must divide 1000")

func test_the_carry_loads_run_10_to_30_and_slow_as_they_grow() -> void:
	var days: Array = data.army_carry_loads.map(func(r: Dictionary) -> int: return int(r["days"]))
	assert_eq(days, [10, 15, 20, 25, 30])
	for i in range(1, data.army_carry_loads.size()):
		assert_true(int(data.army_carry_loads[i]["pace_permille"]) <= int(data.army_carry_loads[i - 1]["pace_permille"]))
	assert_true(days.has(int(data.bal("army_carry_default_days"))))

func test_the_supply_menu_rows_and_the_hostile_stances_load() -> void:
	for key in ["add", "change", "withdraw", "carry", "pick_far", "confirm", "cancel"]:
		assert_true(data.army_supply_orders.has(key), key)
	assert_true(data.army_hostile_stances.has("Enemy"))
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./run_tests.sh --fast 2>&1 | grep -A3 test_army_supply_data`
Expected: FAIL — `army_carry_loads` is not a member / keys missing.

- [ ] **Step 3: Add the data**

Append to `data/balance.csv` (notes quote the spec):

```csv
army_start_supply_days,20,"army supply (spec 2026-10-07-army-supply-lines §6): days of its own use a regiment starts a campaign with"
army_supply_low_days,5,"army supply §3.6–3.7: below this many days in hand a regiment is hungry — morale falls daily and the march drags"
army_supply_max_days,30,"army supply §1: the most days of supplies a regiment can carry (owner 2026-10-07: 最多携带30天)"
army_carry_default_days,20,"army supply §2.1: the carried-load order a regiment starts with, and an old save's"
army_morale_hungry_day,1,"army supply §3.7: morale lost each day under army_supply_low_days days in hand"
army_morale_starving_day,3,"army supply §3.7: morale lost each day with no supplies at all (instead of the hungry loss)"
supply_wagon_km_per_day,25,"army supply §3.2: the supply wagons' road km a day — how long a new line takes to start flowing, and the reach of a supply point"
supply_point_max_days,10,"army supply §3.5: the most wagon days a supply point may be from its regiment when it is chosen"
supply_cut_reach_m,5000,"army supply §3.2: a supply line is cut on any day a hostile regiment stands within this many metres of its road"
supply_cart_milligold_per_unit_km,1,"army supply §3.4: cartage, in thousandths of a gold, for each supply unit carried one km; charged daily in whole gold"
supply_buy_markup_permille,200,"army supply §3.3: a house sells its stock to the crown at its value plus this per mille"
supply_warn_town_days,10,"army supply §5.5: a supply town whose stores hold fewer days of its lines' draw than this sends a warning"
town_house_stock_months,3,"army supply §3.1: a house keeps at most this many months of its own strategic goods in a town (it sells the rest elsewhere)"
```

`data/army_carry_loads.csv`:

```csv
days,pace_permille,label,notes
10,1000,10 days,"spec 2026-10-07-army-supply-lines §3.6: a light train marches at full pace"
15,970,15 days,
20,940,20 days,
25,890,25 days,
30,850,30 days,"owner 2026-10-07 (第5题 A): a full train is the slowest, about -15%"
```

`data/army_supply_orders.csv`:

```csv
key,label,hint,notes
add,Add supply point…,Then click a lit town to supply this regiment from,"spec 2026-10-07-army-supply-lines §5.1: the ellipsis says a click follows"
change,Change supply point…,Then click a lit town to supply it from instead,
withdraw,Withdraw supply point,Send a courier to the supply town to stop the wagons,
carry,Carry,"How many days of supplies it keeps in hand; a heavier train marches slower",the submenu's title
pick_far,,"{town}: the wagons need {days} days, the most is {max}",a greyed town's reason
confirm,"{rate}× — {fee} gold a day","Supply from {town}: {km} km, {loss}% lost on the road, wagons {wagon_days} days, stores for {stock_days} days; the courier rides {courier_days} days",one row per rate
cancel,Cancel,Choose no supply point,
```

`data/army_hostile_stances.csv`:

```csv
stance,notes
Enemy,"spec 2026-10-07-army-supply-lines §3.2: a regiment of a kingdom the realm holds in this stance cuts supply lines (a later war state joins this table)"
```

In `scripts/engine/data_repository.gd`, next to `army_route_orders` declare:

```gdscript
## data/army_carry_loads.csv: [{days, pace_permille, label}], days ascending
## (spec 2026-10-07-army-supply-lines §3.6).
var army_carry_loads: Array = []
## data/army_supply_orders.csv: key -> {label, hint} — the supply rows of the
## regiment's right-click menu (spec 2026-10-07-army-supply-lines §5.1).
var army_supply_orders: Dictionary = {}
## data/army_hostile_stances.csv: the stances whose regiments cut supply lines.
var army_hostile_stances: Array[String] = []
```

and after the `army_route_orders.csv` loader:

```gdscript
	if not _load_if_present(dir + "/army_carry_loads.csv", ["days", "pace_permille", "label"],
			func(r): army_carry_loads.append({"days": int(r["days"]),
				"pace_permille": int(r["pace_permille"]), "label": String(r["label"])})):
		return false
	army_carry_loads.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["days"]) < int(b["days"]))
	if not _load_if_present(dir + "/army_supply_orders.csv", ["key", "label", "hint"],
			func(r): army_supply_orders[String(r["key"])] = {"label": String(r["label"]),
				"hint": String(r["hint"])}):
		return false
	if not _load_if_present(dir + "/army_hostile_stances.csv", ["stance"],
			func(r): army_hostile_stances.append(String(r["stance"]))):
		return false
```

Add to `data/CLAUDE.md` under the army tables: `army_carry_loads.csv` (carried-load days → march pace), `army_supply_orders.csv` (supply menu rows), `army_hostile_stances.csv` (stances that cut supply lines).

- [ ] **Step 4: Run it to verify it passes**

Run: `./run_tests.sh --fast 2>&1 | tail -5`
Expected: PASS, no new failures.

- [ ] **Step 5: Commit**

```bash
git add data/balance.csv data/army_carry_loads.csv data/army_supply_orders.csv data/army_hostile_stances.csv data/CLAUDE.md scripts/engine/data_repository.gd tests/engine/test_army_supply_data.gd
git commit -m "feat(supply): data for carried days, supply orders and hostile stances"
```

---

### Task 2: Days, the carried load and hunger in ArmySystem

**Files:**
- Modify: `scripts/engine/army_system.gd` (`starting_state`, `ensure`, `supply_score`, `stores_permille`, `bars_of`, `day_step_m`, `speed_km_per_day`; new `days_in_hand`, `max_units`, `load_permille`, `hunger_day`)
- Modify: `scripts/engine/tick_engine.gd` (`_end_day`: `ArmySystem.hunger_day` after `eat_day`)
- Test: `tests/engine/test_army_days.gd`; update `tests/engine/test_army_speed.gd`, `tests/engine/test_army_system.gd`, `tests/engine/test_army_data.gd`

**Interfaces:**
- Produces:
  - `ArmySystem.days_in_hand(supplies: int, use: int) -> int` (999 when use ≤ 0)
  - `ArmySystem.max_units(repo, use: int) -> int`
  - `ArmySystem.carry_of(repo, entry: Dictionary) -> int`
  - `ArmySystem.load_permille(repo, carry_days: int) -> int`
  - `ArmySystem.supply_score(repo, supplies, use) -> int` — NEW meaning: 1000 at ≥ `army_supply_low_days` days, linear to 0
  - `ArmySystem.stores_permille(repo, supplies, use, carry_days) -> int` — days in hand over the carried load
  - `ArmySystem.hunger_day(repo, state) -> void`
  - regiment entry gains `carry_days: int`

- [ ] **Step 1: Write the failing test**

`tests/engine/test_army_days.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Days in hand, the carried load and hunger (spec 2026-10-07-army-supply-lines §3.6–3.7).

var repo: DataRepository
var s: GameState

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)

func _land() -> String:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			return String(c)
	return ""

func test_days_in_hand_is_supplies_over_a_thirtieth_of_the_month() -> void:
	assert_eq(ArmySystem.days_in_hand(300, 300), 30)
	assert_eq(ArmySystem.days_in_hand(149, 300), 14)   # 149*30/300 = 14.9 -> 14
	assert_eq(ArmySystem.days_in_hand(0, 300), 0)
	assert_eq(ArmySystem.max_units(repo, 300), 300)    # 30 days of 300 a month

func test_the_supply_score_is_full_from_the_low_mark_up() -> void:
	# use 300 a month = 10 a day; low mark 5 days = 50 units
	assert_eq(ArmySystem.supply_score(repo, 50, 300), 1000)
	assert_eq(ArmySystem.supply_score(repo, 300, 300), 1000)
	assert_eq(ArmySystem.supply_score(repo, 25, 300), 500)
	assert_eq(ArmySystem.supply_score(repo, 0, 300), 0)
	assert_eq(ArmySystem.supply_score(repo, 10, 0), 1000, "a banner that eats nothing never runs short")

func test_the_stores_bar_reads_days_against_the_carried_load() -> void:
	# 20 days carried; 150 units of 300 a month = 15 days -> 750
	assert_eq(ArmySystem.stores_permille(repo, 150, 300, 20), 750)
	assert_eq(ArmySystem.stores_permille(repo, 300, 300, 20), 1000, "capped")

func test_a_heavier_load_marches_slower() -> void:
	assert_eq(ArmySystem.load_permille(repo, 10), 1000)
	assert_eq(ArmySystem.load_permille(repo, 30), 850)
	var code := _land()
	s.regiments[code]["carry_days"] = 10
	var light := ArmySystem.day_step_m(repo, s, code)
	s.regiments[code]["carry_days"] = 30
	var heavy := ArmySystem.day_step_m(repo, s, code)
	assert_eq(heavy, light * 850 / 1000)

func test_a_new_regiment_starts_with_twenty_days_and_the_default_load() -> void:
	var code := _land()
	var reg := ArmySystem.regiment(repo, code)
	var st := ArmySystem.starting_state(repo, reg)
	var use := ArmySystem.supply_use(repo, reg)
	assert_eq(int(st["supplies"]), use * 20 / 30)
	assert_eq(int(st["carry_days"]), 20)

func test_an_old_entry_gets_a_load_and_is_clamped_to_thirty_days() -> void:
	var code := _land()
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code), s)
	s.regiments[code].erase("carry_days")
	s.regiments[code]["supplies"] = use * 4      # four months, the old refill
	ArmySystem.ensure(repo, s)
	assert_eq(int(s.regiments[code]["carry_days"]), 20)
	assert_eq(int(s.regiments[code]["supplies"]), ArmySystem.max_units(repo, use))

func test_hunger_costs_morale_every_day_under_five_days() -> void:
	var code := _land()
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code), s)
	s.regiments[code]["morale"] = 60
	s.regiments[code]["supplies"] = use * 4 / 30          # 4 days: hungry
	ArmySystem.hunger_day(repo, s)
	assert_eq(int(s.regiments[code]["morale"]), 59)
	s.regiments[code]["supplies"] = 0                     # starving
	ArmySystem.hunger_day(repo, s)
	assert_eq(int(s.regiments[code]["morale"]), 56)
	s.regiments[code]["supplies"] = use * 6 / 30          # fed: no daily loss
	ArmySystem.hunger_day(repo, s)
	assert_eq(int(s.regiments[code]["morale"]), 56)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./run_tests.sh --fast 2>&1 | grep -A3 test_army_days`
Expected: FAIL — `days_in_hand` not found.

- [ ] **Step 3: Implement**

In `scripts/engine/army_system.gd`:

`starting_state` — replace the `"supplies"` line and add the load:

```gdscript
		"supplies": supply_use(repo, reg) * int(repo.bal("army_start_supply_days")) / Calendar.DAYS_PER_TICK,
		"carry_days": int(repo.bal("army_carry_default_days")),
```

(keep the `@warning_ignore("integer_division")` above the dictionary).

`ensure` — inside the loop, after the `x_m` migration block:

```gdscript
		# A save from before the carried load (spec 2026-10-07-army-supply-lines
		# §6): the default load, and no more than the most a train can carry.
		if not entry.has("carry_days"):
			entry["carry_days"] = int(repo.bal("army_carry_default_days"))
			entry["supplies"] = mini(int(entry["supplies"]), max_units(repo, supply_use(repo, reg, state)))
```

Replace `supply_score` and `stores_permille`, and add the new helpers next to them:

```gdscript
## Whole days a regiment's `supplies` last at `use` a month (spec
## 2026-10-07-army-supply-lines §2.1): never saved, always read off the units.
static func days_in_hand(supplies: int, use: int) -> int:
	if use <= 0:
		return 999
	@warning_ignore("integer_division")  # whole days
	return maxi(supplies, 0) * Calendar.DAYS_PER_TICK / use

## The most units a regiment of `use` a month can carry: army_supply_max_days.
static func max_units(repo: DataRepository, use: int) -> int:
	@warning_ignore("integer_division")  # whole supplies
	return use * int(repo.bal("army_supply_max_days")) / Calendar.DAYS_PER_TICK

## A regiment entry's carried-load order, the default when it has none.
static func carry_of(repo: DataRepository, entry: Dictionary) -> int:
	return int(entry.get("carry_days", int(repo.bal("army_carry_default_days"))))

## The march's per-mille under a carried load (data/army_carry_loads.csv):
## the row with the most days not above `carry_days`; 1000 with no rows.
static func load_permille(repo: DataRepository, carry_days: int) -> int:
	var out := 1000
	for row: Dictionary in repo.army_carry_loads:
		if int(row["days"]) <= carry_days:
			out = int(row["pace_permille"])
	return out

## Supplies as a score, per mille (spec 2026-10-07-army-supply-lines §3.6):
## full at army_supply_low_days days in hand or more, falling linearly to 0
## at none — only a hungry column is slowed and loses heart. A banner that
## uses nothing never runs short.
static func supply_score(repo: DataRepository, supplies: int, use_per_month: int) -> int:
	if use_per_month <= 0:
		return 1000
	var low := maxi(1, int(repo.bal("army_supply_low_days")))
	@warning_ignore("integer_division")  # whole per-mille
	return clampi(maxi(supplies, 0) * Calendar.DAYS_PER_TICK * 1000 / (use_per_month * low), 0, 1000)

## The map's yellow bar: days in hand over the carried load, per mille,
## capped at 1000 — it falls a little every day the column eats.
static func stores_permille(repo: DataRepository, supplies: int, use_per_month: int, carry_days: int) -> int:
	if use_per_month <= 0:
		return 1000
	var full := maxi(1, carry_days)
	@warning_ignore("integer_division")  # whole per-mille
	return clampi(maxi(supplies, 0) * Calendar.DAYS_PER_TICK * 1000 / (use_per_month * full), 0, 1000)

## A day of hunger for every land regiment of the player's realm, in code
## order (spec §3.7): under army_supply_low_days days in hand morale falls
## army_morale_hungry_day, at none army_morale_starving_day instead.
static func hunger_day(repo: DataRepository, state: GameState) -> void:
	var codes := state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := regiment(repo, code)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		var entry: Dictionary = state.regiments[code]
		var supplies := int(entry["supplies"])
		var loss := 0
		if supplies <= 0:
			loss = int(repo.bal("army_morale_starving_day"))
		elif days_in_hand(supplies, supply_use(repo, reg, state)) < int(repo.bal("army_supply_low_days")):
			loss = int(repo.bal("army_morale_hungry_day"))
		entry["morale"] = maxi(0, int(entry["morale"]) - loss)
```

`bars_of` — pass the load:

```gdscript
	return Vector2i(readiness_permille(repo, supply, int(st["morale"]), int(st["training"])),
		stores_permille(repo, int(st["supplies"]), use, carry_of(repo, st)))
```

`day_step_m` — multiply in the load:

```gdscript
	@warning_ignore("integer_division")  # whole metres
	return pace_tenths(repo, base_pace_km(repo, reg),
		supply_score(repo, int(st["supplies"]), supply_use(repo, reg, state)),
		int(st["morale"]), int(st["training"])) * 100 * load_permille(repo, carry_of(repo, st)) / 1000
```

`speed_km_per_day` — the same factor:

```gdscript
	return pace_tenths(repo, base_pace_km(repo, reg),
		supply_score(repo, int(st["supplies"]), supply_use(repo, reg, state)),
		int(st["morale"]), int(st["training"])) / 10.0 \
		* float(load_permille(repo, carry_of(repo, st))) / 1000.0 \
		* float(ground_permille(repo, reg, position_of(repo, state, reg))) / 1000.0
```

Update the doc comments that name `army_supply_target_months` / `army_speed_supply_full_months` / `army_start_supply_months` to the new keys.

In `scripts/engine/tick_engine.gd` `_end_day`, right after `ArmySystem.eat_day(data, state)`:

```gdscript
	# A hungry host loses heart every day (spec 2026-10-07-army-supply-lines §3.7).
	ArmySystem.hunger_day(data, state)
```

Remove `army_speed_supply_full_months` and `army_start_supply_months` from `data/balance.csv`.

Update the old tests to the new meaning:
- `tests/engine/test_army_speed.gd`: the header comment's `S` line reads "supplies in hand over army_supply_low_days days"; `test_` asserting `supply_score(repo, 150, 100) == 500` becomes `supply_score(repo, 8, 100) == 480` (8×30×1000/(100×5) = 480) and `(600,100) == 1000`, `(0,100) == 0`; drop `repo.balance["army_speed_supply_full_months"]` and `army_start_supply_months` writes; any expected pace that assumed a load uses `load_permille(repo, 20)` (940) — multiply the old expectation by 940/1000 with integer division in the same place the code does.
- `tests/engine/test_army_system.gd:93`: `use * int(repo.bal("army_supply_target_months"))` → `ArmySystem.max_units(repo, use)`.
- `tests/engine/test_army_data.gd:37`: replace `army_start_supply_months` with `army_start_supply_days` in the key list.

- [ ] **Step 4: Run tests**

Run: `./run_tests.sh --fast 2>&1 | tail -15`
Expected: `test_army_days` passes. Any remaining failure must be in a supply test that Task 7 rewrites (`test_supply_system`, `test_governed_flows`, `test_ledger_supply`, `test_ledger_governors`): note their names; do not fix them here.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/army_system.gd scripts/engine/tick_engine.gd data/balance.csv tests/engine/test_army_days.gd tests/engine/test_army_speed.gd tests/engine/test_army_system.gd tests/engine/test_army_data.gd
git commit -m "feat(supply): days in hand, carried load pace and daily hunger"
```

---

### Task 3: TownStores — catchment, stores, reconcile

**Files:**
- Create: `scripts/engine/town_stores.gd`
- Modify: `scripts/engine/game_state.gd` (`town_stock` field, save/load)
- Test: `tests/engine/test_town_stores.gd`

**Interfaces:**
- Consumes: `MapManors.province_of`, `MapManors.manors_of_province`, `MapManors.crown_controls`, `MapOwnership.owner_of`, `MapOwnership.provinces_of`, `MapEconomy.burg_cells`, `MapTerrain.cell_center`, `RealmEconomy.lines_of_province`, `RealmEconomy.purses`.
- Produces (all `static`):
  - `TownStores.units_per_gold(repo) -> int`, `gold_of_units(repo, units: int) -> int`
  - `is_realm_town(repo, state, burg: String) -> bool`, `realm_towns(repo, state) -> Array` (sorted)
  - `depot(repo, state) -> String`
  - `catchment(repo, state) -> Dictionary` cell(int) → burg(String), realm manors only
  - `town_of_cell(repo, state, cell: int) -> String`
  - `stock_of(state, burg) -> Dictionary` `{crown, lord, house}` (zeros when none)
  - `total(state, pool: String) -> int`
  - `add(state, burg, pool, units: int) -> void`, `take(state, burg, pool, units: int) -> int`
  - `apportion(total: int, weights: Dictionary) -> Dictionary`
  - `reconcile(repo, state) -> void`, `sync_metrics(repo, state) -> void`
  - `GameState.town_stock: Dictionary` burg → `{crown: int, lord: int, house: int}`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Town stores (spec 2026-10-07-army-supply-lines §2, §3.1).

var repo: DataRepository
var s: GameState

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func test_apportion_is_largest_remainder_with_ties_by_code() -> void:
	assert_eq(TownStores.apportion(10, {"a": 1, "b": 1, "c": 1}), {"a": 4, "b": 3, "c": 3})
	assert_eq(TownStores.apportion(7, {"a": 0, "b": 0}), {"a": 4, "b": 3}, "no weight: shared evenly")
	assert_eq(TownStores.apportion(0, {"a": 5}), {"a": 0})

func test_units_and_gold_convert_at_the_supply_price() -> void:
	# army_supply_gold_permille 100: a gold is 10 units
	assert_eq(TownStores.units_per_gold(repo), 1000 / int(repo.bal("army_supply_gold_permille")))
	assert_eq(TownStores.gold_of_units(repo, 129), 129 * int(repo.bal("army_supply_gold_permille")) / 1000)

func test_every_realm_manor_feeds_the_nearest_town_of_its_province() -> void:
	var c := TownStores.catchment(repo, s)
	assert_false(c.is_empty())
	for cell: int in c:
		var burg := String(c[cell])
		assert_true(TownStores.is_realm_town(repo, s, burg), burg)
		var prov := MapManors.province_of(repo, cell, s)
		var here := MapTerrain.cell_center(repo, repo.cells[cell])
		var best := ""
		var best_d := INF
		for b: String in TownStores.realm_towns(repo, s):
			if String(repo.burgs[b]["province_code"]) != prov:
				continue
			var d := here.distance_squared_to(Vector2(float(repo.burgs[b]["x"]), float(repo.burgs[b]["y"])))
			if d < best_d or (d == best_d and b < best):
				best_d = d
				best = b
		if best != "":
			assert_eq(burg, best, "cell %d" % cell)

func test_take_never_goes_below_empty() -> void:
	var b: String = TownStores.realm_towns(repo, s)[0]
	s.town_stock[b] = {"crown": 5, "lord": 0, "house": 0}
	assert_eq(TownStores.take(s, b, "crown", 8), 5)
	assert_eq(int(TownStores.stock_of(s, b)["crown"]), 0)

func test_reconcile_follows_a_metric_moved_elsewhere() -> void:
	TownStores.sync_metrics(repo, s)
	var before := TownStores.total(s, "crown")
	# an order cost takes 20 gold of the crown's strategic goods (LEVY_RAISE)
	s.metrics["strategic"] = float(s.metrics["strategic"]) - 20.0
	TownStores.reconcile(repo, s)
	assert_eq(TownStores.total(s, "crown"), before - 20 * TownStores.units_per_gold(repo))
	assert_eq(int(s.metrics["strategic"]), TownStores.gold_of_units(repo, TownStores.total(s, "crown")))
	for b: String in s.town_stock:
		assert_true(int(s.town_stock[b]["crown"]) >= 0)
	# an event gives 7 gold: it lands in the depot
	var depot := TownStores.depot(repo, s)
	var had := int(TownStores.stock_of(s, depot)["crown"])
	s.metrics["strategic"] = float(s.metrics["strategic"]) + 7.0
	TownStores.reconcile(repo, s)
	assert_eq(int(TownStores.stock_of(s, depot)["crown"]), had + 7 * TownStores.units_per_gold(repo))

func test_the_stores_survive_the_save() -> void:
	var b: String = TownStores.realm_towns(repo, s)[0]
	s.town_stock[b] = {"crown": 11, "lord": 22, "house": 33}
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(TownStores.stock_of(back, b), {"crown": 11, "lord": 22, "house": 33})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./run_tests.sh --fast 2>&1 | grep -A3 test_town_stores`
Expected: FAIL — `TownStores` not declared.

- [ ] **Step 3: Implement**

`scripts/engine/game_state.gd` — after `wealth_tiers`:

```gdscript
## Each realm town's strategic stores in SUPPLY UNITS (spec 2026-10-07-army-
## supply-lines §2.1, TownStores): burg -> {crown, lord, house}. crown and
## lord sum to metrics.strategic / lord_strategic; house is a house's stock
## the crown may buy.
var town_stock: Dictionary = {}
```

In `to_dict()` add `"town_stock": _encode_values(town_stock.duplicate(true)),`; in `from_dict` before `if invalidate:` add:

```gdscript
	# Saves from before the town stores carry none: TownStores.ensure seeds
	# them from the pools on load (Game.load_campaign).
	s.town_stock = _decode_values(d.get("town_stock", {}))
```

Bump nothing in `SAVE_VERSION` (an added key with a default is backward compatible, as every earlier addition was).

`scripts/engine/town_stores.gd`:

```gdscript
class_name TownStores
extends RefCounted
## Each realm town's strategic stores (owner 2026-10-07, spec
## docs/superpowers/specs/2026-10-07-army-supply-lines-design.md §2–3):
## GameState.town_stock, burg -> {crown, lord, house} in SUPPLY UNITS. Every
## manor of the realm feeds the nearest town of its province (the catchment);
## the crown's and the lord's units ARE metrics.strategic / lord_strategic
## (their gold, rounded down once over the whole pool), the house's are a
## house's stock the crown may buy. A writer that moves those two metrics
## without touching a town is absorbed by reconcile(). Whole numbers, burg
## code order.

const POOLS := ["crown", "lord", "house"]
const METRIC := {"crown": "strategic", "lord": "lord_strategic"}

static var _catch_cache: Dictionary = {}


static func units_per_gold(repo: DataRepository) -> int:
	@warning_ignore("integer_division")  # the permille divides 1000 (test_army_supply_data)
	return 1000 / maxi(1, int(repo.bal("army_supply_gold_permille")))


static func gold_of_units(repo: DataRepository, units: int) -> int:
	@warning_ignore("integer_division")  # whole gold, rounded down once
	return maxi(units, 0) * int(repo.bal("army_supply_gold_permille")) / 1000


## A burg whose province the player's kingdom holds now, whatever house holds it.
static func is_realm_town(repo: DataRepository, state: GameState, burg: String) -> bool:
	var b: Dictionary = repo.burgs.get(burg, {})
	if b.is_empty():
		return false
	return MapOwnership.owner_of(repo, state, String(b.get("province_code", ""))) \
		== repo.resolve_realm("player_realm")


static func realm_towns(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	for code: String in repo.burgs:
		if is_realm_town(repo, state, code):
			out.append(code)
	out.sort()
	return out


## Where goods with no town of their own land: the realm's capital while the
## realm holds it, else the first realm town by code; "" with none.
static func depot(repo: DataRepository, state: GameState) -> String:
	var cap := String((repo.kingdoms.get(repo.resolve_realm("player_realm"), {}) as Dictionary).get("capital_burg", ""))
	if cap != "" and is_realm_town(repo, state, cap):
		return cap
	var towns := realm_towns(repo, state)
	return String(towns[0]) if not towns.is_empty() else ""


static func _burg_px(b: Dictionary) -> Vector2:
	return Vector2(float(b.get("x", 0)), float(b.get("y", 0)))


static func _nearest(repo: DataRepository, at: Vector2, towns: Array) -> String:
	var best := ""
	var best_d := INF
	for code: String in towns:
		var d := at.distance_squared_to(_burg_px(repo.burgs[code]))
		if d < best_d or (d == best_d and code < best):
			best_d = d
			best = code
	return best


## cell -> burg for every manor of the realm (spec §2.2): the nearest realm
## town of the same province; a province with none sends to the nearest
## realm town anywhere. Cached on what moves it.
static func catchment(repo: DataRepository, state: GameState) -> Dictionary:
	var key := hash([repo.get_instance_id(), state.manor_province.hash(), state.province_owner.hash()])
	if _catch_cache.has(key):
		return _catch_cache[key]
	if _catch_cache.size() > 16:
		_catch_cache.clear()
	var towns := realm_towns(repo, state)
	var by_prov: Dictionary = {}
	for code: String in towns:
		var p := String(repo.burgs[code].get("province_code", ""))
		if not by_prov.has(p):
			by_prov[p] = []
		(by_prov[p] as Array).append(code)
	var out: Dictionary = {}
	var provs: Array = Array(MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm")))
	provs.sort()
	for prov: String in provs:
		var pool: Array = by_prov.get(prov, towns)
		if pool.is_empty():
			continue
		for cell: int in MapManors.manors_of_province(repo, prov, state):
			out[cell] = _nearest(repo, MapTerrain.cell_center(repo, repo.cells[cell]), pool)
	_catch_cache[key] = out
	return out


static func town_of_cell(repo: DataRepository, state: GameState, cell: int) -> String:
	return String(catchment(repo, state).get(cell, depot(repo, state)))


static func stock_of(state: GameState, burg: String) -> Dictionary:
	var s: Dictionary = state.town_stock.get(burg, {})
	return {"crown": int(s.get("crown", 0)), "lord": int(s.get("lord", 0)), "house": int(s.get("house", 0))}


static func total(state: GameState, pool: String) -> int:
	var n := 0
	for b: String in state.town_stock:
		n += int((state.town_stock[b] as Dictionary).get(pool, 0))
	return n


static func add(state: GameState, burg: String, pool: String, units: int) -> void:
	if burg == "" or units == 0:
		return
	var s := stock_of(state, burg)
	s[pool] = maxi(0, int(s[pool]) + units)
	state.town_stock[burg] = s


## Takes up to `units` of `pool` from `burg`; returns what was taken.
static func take(state: GameState, burg: String, pool: String, units: int) -> int:
	var s := stock_of(state, burg)
	var got := clampi(units, 0, int(s[pool]))
	s[pool] = int(s[pool]) - got
	state.town_stock[burg] = s
	return got


## `total` split over `weights` (key -> int >= 0) by largest remainder, ties
## to the key that sorts first; all-zero weights share it evenly.
static func apportion(total: int, weights: Dictionary) -> Dictionary:
	var keys: Array = weights.keys()
	keys.sort()
	var out: Dictionary = {}
	if keys.is_empty():
		return out
	var sum := 0
	for k in keys:
		sum += maxi(int(weights[k]), 0)
	var w: Dictionary = {}
	for k in keys:
		w[k] = 1 if sum == 0 else maxi(int(weights[k]), 0)
	if sum == 0:
		sum = keys.size()
	var given := 0
	var rems: Array = []
	for k in keys:
		@warning_ignore("integer_division")
		var whole: int = total * int(w[k]) / sum
		out[k] = whole
		given += whole
		rems.append([total * int(w[k]) % sum, k])
	rems.sort_custom(func(a: Array, b: Array) -> bool:
		return int(a[0]) > int(b[0]) or (int(a[0]) == int(b[0]) and String(a[1]) < String(b[1])))
	for i in range(total - given):
		var k: String = rems[i % rems.size()][1]
		out[k] = int(out[k]) + 1
	return out


## The two metrics are the gold of their pools' units (spec §2.1).
static func sync_metrics(repo: DataRepository, state: GameState) -> void:
	for pool: String in METRIC:
		state.metrics[METRIC[pool]] = float(gold_of_units(repo, total(state, pool)))


## Absorb what other writers did to the two metrics (spec §3.1, plan
## "Measures"): a rise lands in the depot, a fall is taken from the towns in
## proportion to their stock. Then the metrics are re-synced.
static func reconcile(repo: DataRepository, state: GameState) -> void:
	var upg := units_per_gold(repo)
	for pool: String in METRIC:
		var want := maxi(int(state.metrics.get(METRIC[pool], 0.0)), 0)
		var have := gold_of_units(repo, total(state, pool))
		var diff := want - have
		if diff > 0:
			add(state, depot(repo, state), pool, diff * upg)
		elif diff < 0:
			var weights: Dictionary = {}
			for b: String in state.town_stock:
				weights[b] = int((state.town_stock[b] as Dictionary).get(pool, 0))
			var cut := apportion(mini(-diff * upg, total(state, pool)), weights)
			for b: String in cut:
				take(state, b, pool, int(cut[b]))
	sync_metrics(repo, state)
```

- [ ] **Step 4: Run tests**

Run: `./run_tests.sh --fast 2>&1 | grep -A3 "test_town_stores\|Failing"`
Expected: `test_town_stores` PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/town_stores.gd scripts/engine/game_state.gd tests/engine/test_town_stores.gd
git commit -m "feat(supply): TownStores — catchment, per-town stores, reconcile"
```

---

### Task 4: The month's goods into the towns; seeding and old saves

**Files:**
- Modify: `scripts/engine/town_stores.gd` (`month_inflow`, `deposit_month`, `seed`, `ensure`)
- Modify: `scripts/engine/tick_engine.gd` (`_settle_economy` calls `deposit_month`; `advance` calls `reconcile` before the steward's report)
- Modify: `scripts/engine/workshop_system.gd` (`settle_month` deposits each workshop's make in its town)
- Modify: `scripts/engine/game_state.gd` (`new_campaign` calls `TownStores.seed`)
- Modify: `scripts/ui/game.gd:302` (after `Intel.ensure_wealth_tiers`, `TownStores.ensure(data, state)`)
- Test: `tests/engine/test_town_stores_month.gd`

**Interfaces:**
- Produces: `TownStores.month_inflow(repo, state) -> Dictionary` burg → `{lord, crown, house}` in GOLD; `TownStores.deposit_month(repo, state) -> void`; `TownStores.seed(repo, state) -> void`; `TownStores.ensure(repo, state) -> void` (seeds only when `town_stock` is empty).

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The month's goods into the towns (spec 2026-10-07-army-supply-lines §3.1).

var repo: DataRepository
var s: GameState

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func test_the_inflow_sums_to_the_purses() -> void:
	var p := RealmEconomy.purses(repo, s)
	var lord := 0
	var crown := 0
	for b: String in TownStores.month_inflow(repo, s):
		var row: Dictionary = TownStores.month_inflow(repo, s)[b]
		lord += int(row["lord"])
		crown += int(row["crown"])
	assert_eq(lord, int(p["lord"]["strategic"]))
	assert_eq(crown, int(p["realm_share"]["strategic"]))

func test_a_new_campaign_seeds_the_towns_from_the_pools() -> void:
	assert_false(s.town_stock.is_empty())
	assert_eq(TownStores.gold_of_units(repo, TownStores.total(s, "crown")), int(s.metrics["strategic"]))
	assert_eq(TownStores.gold_of_units(repo, TownStores.total(s, "lord")), int(s.metrics["lord_strategic"]))

func test_the_months_settlement_keeps_the_pools_equal_to_the_towns() -> void:
	var engine := TickEngine.new(repo)
	for i in Calendar.DAYS_PER_TICK - 1:
		engine.advance_day(s)
	engine.advance(s)
	assert_eq(TownStores.gold_of_units(repo, TownStores.total(s, "crown")), int(s.metrics["strategic"]))
	assert_eq(TownStores.gold_of_units(repo, TownStores.total(s, "lord")), int(s.metrics["lord_strategic"]))

func test_the_house_stock_is_capped_at_its_months() -> void:
	var inflow := TownStores.month_inflow(repo, s)
	var months := int(repo.bal("town_house_stock_months"))
	for i in months + 3:
		TownStores.deposit_month(repo, s)
	for b: String in inflow:
		var cap := int(inflow[b]["house"]) * months * TownStores.units_per_gold(repo)
		assert_true(int(TownStores.stock_of(s, b)["house"]) <= cap, b)

func test_an_old_save_seeds_on_ensure() -> void:
	var lord := int(s.metrics["lord_strategic"])
	s.town_stock = {}
	TownStores.ensure(repo, s)
	assert_eq(TownStores.gold_of_units(repo, TownStores.total(s, "lord")), lord)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./run_tests.sh --fast 2>&1 | grep -A3 test_town_stores_month`
Expected: FAIL — `month_inflow` not found.

- [ ] **Step 3: Implement**

Append to `scripts/engine/town_stores.gd`:

```gdscript
## The month's strategic goods by town, in GOLD (spec §3.1): a manor of a
## province the crown controls gives all of it to `lord`; any other realm
## manor's goods are split between `crown` (crown_share_permille of the
## realm's, apportioned over the towns by what reaches them, so the crown's
## sum equals RealmEconomy.purses exactly) and `house` (the rest).
static func month_inflow(repo: DataRepository, state: GameState) -> Dictionary:
	var catch := catchment(repo, state)
	var lord: Dictionary = {}
	var other: Dictionary = {}
	var provs: Array = Array(MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm")))
	provs.sort()
	for prov: String in provs:
		var mine := MapManors.crown_controls(repo, state, prov)
		var lines := RealmEconomy.lines_of_province(repo, state, prov)
		var cells: Array = lines.keys()
		cells.sort()
		for cell: int in cells:
			var town := String(catch.get(cell, ""))
			if town == "":
				continue
			var g := int((lines[cell] as Dictionary)["strategic"])
			if mine:
				lord[town] = int(lord.get(town, 0)) + g
			else:
				other[town] = int(other.get(town, 0)) + g
	var crown_total := int(RealmEconomy.purses(repo, state)["realm_share"]["strategic"])
	var crown := apportion(crown_total, other) if not other.is_empty() else {}
	var out: Dictionary = {}
	var towns: Array = lord.keys()
	for t in other.keys():
		if not towns.has(t):
			towns.append(t)
	towns.sort()
	for t: String in towns:
		var c := int(crown.get(t, 0))
		out[t] = {"lord": int(lord.get(t, 0)), "crown": c, "house": maxi(int(other.get(t, 0)) - c, 0)}
	return out


## Settle the month's goods into the towns (TickEngine._settle_economy, beside
## the purse lines that raise the two metrics by the same gold).
static func deposit_month(repo: DataRepository, state: GameState) -> void:
	var upg := units_per_gold(repo)
	var months := int(repo.bal("town_house_stock_months"))
	var inflow := month_inflow(repo, state)
	var towns: Array = inflow.keys()
	towns.sort()
	for t: String in towns:
		var row: Dictionary = inflow[t]
		add(state, t, "lord", int(row["lord"]) * upg)
		add(state, t, "crown", int(row["crown"]) * upg)
		var cap := int(row["house"]) * months * upg
		var s := stock_of(state, t)
		s["house"] = mini(int(s["house"]) + int(row["house"]) * upg, cap)
		state.town_stock[t] = s


## Spread the two pools as they stand over the towns by each town's share of
## a month's inflow (a new campaign; an old save), and fill each house stock
## to its cap. The depot takes what no town draws.
static func seed(repo: DataRepository, state: GameState) -> void:
	state.town_stock = {}
	var upg := units_per_gold(repo)
	var inflow := month_inflow(repo, state)
	var months := int(repo.bal("town_house_stock_months"))
	for pool: String in METRIC:
		var units := maxi(int(state.metrics.get(METRIC[pool], 0.0)), 0) * upg
		var weights: Dictionary = {}
		for t: String in inflow:
			weights[t] = int(inflow[t][pool])
		if weights.is_empty():
			add(state, depot(repo, state), pool, units)
			continue
		var split := apportion(units, weights)
		for t: String in split:
			add(state, t, pool, int(split[t]))
	for t: String in inflow:
		add(state, t, "house", int(inflow[t]["house"]) * months * upg)
	sync_metrics(repo, state)


## Seed only a state that has no stores yet (Game.load_campaign: a save from
## before the town stores).
static func ensure(repo: DataRepository, state: GameState) -> void:
	if state.town_stock.is_empty():
		seed(repo, state)
```

`scripts/engine/game_state.gd` `new_campaign`, after `ArmySystem.ensure(data, s)`:

```gdscript
	# The pools as each town holds them (spec 2026-10-07-army-supply-lines §3.1).
	TownStores.seed(data, s)
```

`scripts/ui/game.gd` after line 302 `Intel.ensure_wealth_tiers(data, state)`:

```gdscript
	TownStores.ensure(data, state)  # a save from before the town stores
```

`scripts/engine/tick_engine.gd` `_settle_economy`, right after the two strategic `_apply` lines (lord's and crown's), add:

```gdscript
	# ...and the same goods into the towns that hold them (spec 2026-10-07-army-
	# supply-lines §3.1): the metrics just raised are the towns' sums.
	TownStores.deposit_month(data, state)
```

In `advance`, right before `if state.tick > 0: MissiveLog.add(... MissiveWriter.monthly ...)`:

```gdscript
	# Whatever else moved the strategic pools this month (the workshops'
	# lines, the industry's inputs) is settled into the towns.
	TownStores.reconcile(data, state)
```

`scripts/engine/workshop_system.gd` `settle_month`: before returning the `lord_strategic` line, deposit each workshop's output in its town:

```gdscript
	# Its goods are stored in the workshop's own town (spec 2026-10-07-army-
	# supply-lines §3.1); the line below raises the lord's metric by the same.
	for row: Dictionary in rows:
		TownStores.add(state, TownStores.town_of_cell(repo, state, int(row["cell"])), "lord",
			int(row["make"]) * TownStores.units_per_gold(repo))
```

(`rows` is the `plan()` result the function already reads; if it names it differently, use that name. The units deposited must equal the gold of the line it returns — if the line is the SUM of `make` capped as `reached`, deposit `reached` split by `apportion(reached, {cell: make})` instead, keyed back to each cell's town.)

- [ ] **Step 4: Run tests**

Run: `./run_tests.sh --fast 2>&1 | tail -15`
Expected: `test_town_stores_month` PASS; `test_tick_engine` still PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/town_stores.gd scripts/engine/tick_engine.gd scripts/engine/workshop_system.gd scripts/engine/game_state.gd scripts/ui/game.gd tests/engine/test_town_stores_month.gd
git commit -m "feat(supply): the month's strategic goods land in the towns"
```

---

### Task 5: SupplyLines — the record, the road, eligibility, interception

**Files:**
- Create: `scripts/engine/supply_lines.gd`
- Modify: `scripts/engine/game_state.gd` (`supply_lines` field + save/load)
- Test: `tests/engine/test_supply_lines.gd`

**Interfaces:**
- Consumes: `CourierSystem.path_between(repo, from_px, to_px) -> Array` of `[x_m, y_m, kind]`; `ArmySystem.position_of`, `ArmySystem.metres_to_pack`, `SupplySystem.loss_of`, `TownStores.is_realm_town`, `Intel.stance_of`, `MapObjects.regiments_of`.
- Produces (static):
  - consts `ORDERED := "ordered"`, `RIDING := "riding"`, `FLOWING := "flowing"`, `CUT := "cut"`, `RATES := [800, 1000, 1200]`
  - `SupplyLines.line(state, code) -> Dictionary` (`{}` when none)
  - `road_px(repo, state, code, town) -> PackedVector2Array` (town → regiment, pack px)
  - `road_km(repo, route: PackedVector2Array) -> int`
  - `wagon_days(repo, km: int) -> int` (≥ 1)
  - `eligibility(repo, state, code) -> Dictionary` burg → reason (`""` = eligible), every realm town
  - `cut_point(repo, state, route: PackedVector2Array) -> Dictionary` `{}` or `{at: Vector2, by: String}` (the kingdom)
  - `GameState.supply_lines: Dictionary`

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Supply lines: the road, eligibility, interception (spec 2026-10-07-army-supply-lines §3.2, §3.5).

var repo: DataRepository
var s: GameState

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)

func _land() -> String:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			return String(c)
	return ""

func test_the_road_runs_from_the_town_to_the_column() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	var route := SupplyLines.road_px(repo, s, code, town)
	assert_true(route.size() >= 2)
	var b: Dictionary = repo.burgs[town]
	assert_almost_eq(route[0].distance_to(Vector2(float(b["x"]), float(b["y"]))), 0.0, 1.0)
	assert_almost_eq(route[route.size() - 1].distance_to(
		ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code))), 0.0, 1.0)

func test_wagon_days_round_up_and_are_at_least_one() -> void:
	var per := int(repo.bal("supply_wagon_km_per_day"))
	assert_eq(SupplyLines.wagon_days(repo, 0), 1)
	assert_eq(SupplyLines.wagon_days(repo, per), 1)
	assert_eq(SupplyLines.wagon_days(repo, per + 1), 2)

func test_a_town_within_reach_is_eligible_and_a_far_one_says_why() -> void:
	var code := _land()
	var e := SupplyLines.eligibility(repo, s, code)
	assert_false(e.is_empty())
	var max_days := int(repo.bal("supply_point_max_days"))
	var some_ok := false
	for town: String in e:
		var km := SupplyLines.road_km(repo, SupplyLines.road_px(repo, s, code, town))
		var ok := SupplyLines.wagon_days(repo, km) <= max_days
		assert_eq(String(e[town]) == "", ok, town)
		some_ok = some_ok or ok
	assert_true(some_ok, "the town it stands in is always within reach")

func test_no_hostile_regiment_no_cut() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	assert_eq(SupplyLines.cut_point(repo, s, SupplyLines.road_px(repo, s, code, town)), {})

func test_a_hostile_regiment_on_the_road_cuts_it() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	var route := SupplyLines.road_px(repo, s, code, town)
	# make a foreign kingdom an Enemy and stand one of its regiments on the road's midpoint
	var realm := repo.resolve_realm("player_realm")
	var foe := ""
	for r: Dictionary in repo.world_table("military", "regiments").values():
		if String(r["kingdom_code"]) != realm and String(r.get("is_naval", "0")) != "1":
			foe = String(r["regiment_code"])
			break
	var foe_reg: Dictionary = repo.world_table("military", "regiments")[foe]
	var mid := route[route.size() / 2]
	foe_reg["x"] = mid.x
	foe_reg["y"] = mid.y
	repo.world_table("political", "diplomacy")["%s>%s" % [realm, String(foe_reg["kingdom_code"])]] = {"stance": "Enemy"}
	var cut := SupplyLines.cut_point(repo, s, route)
	assert_false(cut.is_empty())
	assert_eq(String(cut["by"]), String(foe_reg["kingdom_code"]))

func test_the_lines_survive_the_save() -> void:
	s.supply_lines["x"] = {"town": "t", "rate": 1000, "state": SupplyLines.FLOWING}
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(String(SupplyLines.line(back, "x")["state"]), SupplyLines.FLOWING)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./run_tests.sh --fast 2>&1 | grep -A3 test_supply_lines`
Expected: FAIL — `SupplyLines` not declared.

- [ ] **Step 3: Implement**

`game_state.gd` after `town_stock`:

```gdscript
## The supply lines (spec 2026-10-07-army-supply-lines §2.1, SupplyLines):
## regiment code -> {town, rate, state, order_id, ready_day, cut_x_m, cut_y_m,
## cut_by, fee_milli, buy_milli, pending, warned, m_*}. Whole numbers only.
var supply_lines: Dictionary = {}
```

`to_dict`: `"supply_lines": _encode_values(supply_lines.duplicate(true)),`; `from_dict`: `s.supply_lines = _decode_values(d.get("supply_lines", {}))` with the comment "Saves from before the supply lines carry none".

`scripts/engine/supply_lines.gd`:

```gdscript
class_name SupplyLines
extends RefCounted
## Supply lines (owner 2026-10-07, spec docs/superpowers/specs/2026-10-07-army-
## supply-lines-design.md): ONE per regiment at most, from a realm town, over
## the road to where the column stands each day. A line is ORDERED while the
## courier rides to the town, RIDING while its first wagons are on the road,
## then FLOWING — or CUT on a day a hostile regiment stands by its road (no
## rerouting). GameState.supply_lines; whole numbers; regiment code order.

const ORDERED := "ordered"
const RIDING := "riding"
const FLOWING := "flowing"
const CUT := "cut"
const RATES := [800, 1000, 1200]


static func line(state: GameState, code: String) -> Dictionary:
	return state.supply_lines.get(code, {}) if state != null else {}


static func _burg_px(repo: DataRepository, town: String) -> Vector2:
	var b: Dictionary = repo.burgs.get(town, {})
	return Vector2(float(b.get("x", 0)), float(b.get("y", 0)))


## The road from `town` to the regiment, pack px (the courier's road:
## CourierSystem.path_between), the town first and the column last.
static func road_px(repo: DataRepository, state: GameState, code: String, town: String) -> PackedVector2Array:
	var out := PackedVector2Array()
	var reg := ArmySystem.regiment(repo, code)
	if reg.is_empty() or not repo.burgs.has(town):
		return out
	var from := _burg_px(repo, town)
	var to := ArmySystem.position_of(repo, state, reg)
	out.append(from)
	for p: Array in CourierSystem.path_between(repo, from, to):
		out.append(ArmySystem.metres_to_pack(repo, Vector2i(int(p[0]), int(p[1]))))
	if out[out.size() - 1].distance_to(to) > 0.001:
		out.append(to)
	return out


static func road_km(repo: DataRepository, route: PackedVector2Array) -> int:
	var m := 0.0
	for i in range(1, route.size()):
		m += route[i - 1].distance_to(route[i]) * float(ArmySystem.metres_per_pack_px(repo))
	return int(m / 1000.0)


static func wagon_days(repo: DataRepository, km: int) -> int:
	var per := maxi(1, int(repo.bal("supply_wagon_km_per_day")))
	@warning_ignore("integer_division")  # whole days, rounded up
	return maxi(1, (km + per - 1) / per)


## Every realm town -> "" when it may supply `code` now, else why not
## (data/army_supply_orders.csv pick_far).
static func eligibility(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var out: Dictionary = {}
	var max_days := int(repo.bal("supply_point_max_days"))
	var hint := String((repo.army_supply_orders.get("pick_far", {}) as Dictionary).get("hint", ""))
	for town: String in TownStores.realm_towns(repo, state):
		var days := wagon_days(repo, road_km(repo, road_px(repo, state, code, town)))
		out[town] = "" if days <= max_days else hint.format({
			"town": String(repo.burgs[town].get("label", town)), "days": days, "max": max_days})
	return out


## The hostile regiments' positions (data/army_hostile_stances.csv), [[px, kingdom]].
static func _hostiles(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	var realm := repo.resolve_realm("player_realm")
	var rows: Array = repo.world_table("military", "regiments").values()
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a["regiment_code"]) < String(b["regiment_code"]))
	for r: Dictionary in rows:
		var k := String(r["kingdom_code"])
		if k == realm or not Intel.stance_of(repo, k) in repo.army_hostile_stances:
			continue
		out.append([ArmySystem.position_of(repo, state, r), k])
	return out


## Where a hostile regiment stands within supply_cut_reach_m of the road:
## {at: the nearest road point (pack px), by: its kingdom}; {} when clear.
static func cut_point(repo: DataRepository, state: GameState, route: PackedVector2Array) -> Dictionary:
	if route.size() < 2:
		return {}
	var reach := float(repo.bal("supply_cut_reach_m")) / float(ArmySystem.metres_per_pack_px(repo))
	for h: Array in _hostiles(repo, state):
		var p: Vector2 = h[0]
		for i in range(1, route.size()):
			var q := Geometry2D.get_closest_point_to_segment(p, route[i - 1], route[i])
			if q.distance_to(p) <= reach:
				return {"at": q, "by": String(h[1])}
	return {}
```

- [ ] **Step 4: Run tests**

Run: `./run_tests.sh --fast 2>&1 | grep -A3 "test_supply_lines"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/supply_lines.gd scripts/engine/game_state.gd tests/engine/test_supply_lines.gd
git commit -m "feat(supply): SupplyLines — road, eligibility, interception"
```

---

### Task 6: The three orders, by courier

**Files:**
- Modify: `data/policy_actions_court_additions.csv`, `data/action_signatures.csv`, `data/order_costs.csv` (one row each per action)
- Modify: `scripts/engine/courier_system.gd` (`dispatch_to`; `_reaim` skipped for a town-bound courier; `_deliver` routes the supply orders)
- Modify: `scripts/engine/supply_lines.gd` (`deliver(repo, state, c) -> Dictionary`)
- Modify: `scripts/engine/action_system.gd` (validate + execute)
- Test: `tests/engine/test_supply_orders.gd`

**Interfaces:**
- Consumes: Task 5's `eligibility`, `line`, consts.
- Produces:
  - actions `SUPPLY_POINT_SET {regiment, town, rate}`, `SUPPLY_POINT_CLEAR {regiment}`, `SUPPLY_CARRY_SET {regiment, days}`
  - `CourierSystem.dispatch_to(repo, state, kind, code, order, to_px: Vector2) -> Dictionary`
  - `SupplyLines.deliver(repo, state, c: Dictionary) -> Dictionary` (a ride_day event)
  - line record after SET delivery: `{town, rate, state: RIDING, order_id, ready_day, cut_x_m: -1, cut_y_m: -1, cut_by: "", fee_milli: 0, buy_milli: 0, warned: "", m_drawn: 0, m_arrived: 0, m_claimed: 0, m_skim: 0, m_fee: 0, m_buy: 0, m_bought: {}}`
  - a pending replacement is held in the record's `pending: {town, rate, order_id}` until its courier delivers

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Supply orders ride by courier (spec 2026-10-07-army-supply-lines §4).

var repo: DataRepository
var s: GameState
var actions: ActionSystem
var engine: TickEngine

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	actions = ActionSystem.new(repo)
	engine = TickEngine.new(repo)
	s.metrics["treasury"] = 1000.0

func _land() -> String:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			return String(c)
	return ""

func _eligible(code: String) -> String:
	var e := SupplyLines.eligibility(repo, s, code)
	var towns: Array = e.keys()
	towns.sort()
	for t: String in towns:
		if String(e[t]) == "":
			return t
	return ""

func _run_until_no_couriers() -> void:
	for i in int(repo.bal("courier_max_days")) + 1:
		if s.couriers.is_empty():
			return
		engine.advance_day(s)

func test_set_rides_to_the_town_and_opens_the_line_on_delivery() -> void:
	var code := _land()
	var town := _eligible(code)
	var req := ActionRequest.make("SUPPLY_POINT_SET", {"regiment": code, "town": town, "rate": 1200})
	assert_eq(actions.validate(req, s), "")
	actions.execute(req, s)
	assert_eq(s.couriers.size(), 1)
	var c: Dictionary = s.couriers[0]
	var b: Dictionary = repo.burgs[town]
	assert_eq(Vector2i(int(c["aim_x_m"]), int(c["aim_y_m"])),
		ArmySystem.pack_to_metres(repo, Vector2(float(b["x"]), float(b["y"]))), "he rides for the town")
	assert_eq(String(SupplyLines.line(s, code).get("state", "")), SupplyLines.ORDERED)
	_run_until_no_couriers()
	var ln := SupplyLines.line(s, code)
	assert_true(String(ln["state"]) in [SupplyLines.RIDING, SupplyLines.FLOWING])
	assert_eq(String(ln["town"]), town)
	assert_eq(int(ln["rate"]), 1200)

func test_refusals() -> void:
	var code := _land()
	assert_ne(actions.validate(ActionRequest.make("SUPPLY_POINT_SET",
		{"regiment": code, "town": _eligible(code), "rate": 900}), s), "", "a rate not in the table")
	assert_ne(actions.validate(ActionRequest.make("SUPPLY_POINT_CLEAR", {"regiment": code}), s), "",
		"no line to withdraw")
	assert_ne(actions.validate(ActionRequest.make("SUPPLY_CARRY_SET", {"regiment": code, "days": 12}), s), "",
		"12 days is not a load")
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) == "1":
			assert_ne(actions.validate(ActionRequest.make("SUPPLY_CARRY_SET",
				{"regiment": String(r["regiment_code"]), "days": 20}), s), "", "a fleet carries no train")
			break

func test_carry_rides_to_the_regiment_and_sets_the_load() -> void:
	var code := _land()
	actions.execute(ActionRequest.make("SUPPLY_CARRY_SET", {"regiment": code, "days": 30}), s)
	assert_eq(ArmySystem.carry_of(repo, s.regiments[code]), 20, "not before he arrives")
	_run_until_no_couriers()
	assert_eq(ArmySystem.carry_of(repo, s.regiments[code]), 30)

func test_clear_ends_the_line_when_its_courier_reaches_the_town() -> void:
	var code := _land()
	actions.execute(ActionRequest.make("SUPPLY_POINT_SET", {"regiment": code, "town": _eligible(code), "rate": 1000}), s)
	_run_until_no_couriers()
	actions.execute(ActionRequest.make("SUPPLY_POINT_CLEAR", {"regiment": code}), s)
	assert_false(SupplyLines.line(s, code).is_empty(), "the wagons run until he arrives")
	_run_until_no_couriers()
	assert_true(SupplyLines.line(s, code).is_empty())
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./run_tests.sh --fast 2>&1 | grep -A3 test_supply_orders`
Expected: FAIL — `Unknown action: SUPPLY_POINT_SET`.

- [ ] **Step 3: Implement**

Data rows:

`data/policy_actions_court_additions.csv`:

```csv
SUPPLY_POINT_SET,military,Give a regiment a supply point,none,0.5,none,0,0,,supply_point_set,60,yes,no,"spec 2026-10-07-army-supply-lines §4. params: regiment, town (a realm burg within supply_point_max_days of wagons), rate (800|1000|1200). A courier rides to the town; the line flows when its first wagons reach the column."
SUPPLY_POINT_CLEAR,military,Withdraw a regiment's supply point,none,0.3,none,0,0,,supply_point_clear,60,yes,no,"params: regiment. A courier rides to the supply town; the wagons stop when he arrives."
SUPPLY_CARRY_SET,military,Set how many days a regiment carries,none,0.3,none,0,0,,supply_carry_set,60,yes,no,"params: regiment, days (a data/army_carry_loads.csv row). A courier rides to the regiment."
```

`data/action_signatures.csv`:

```csv
SUPPLY_POINT_SET,,5,5,0,0,0,the crown feeds its host from its own towns
SUPPLY_POINT_CLEAR,,0,0,0,0,0,the wagons are called home
SUPPLY_CARRY_SET,,0,3,0,0,0,the host's train is loaded
```

`data/order_costs.csv`:

```csv
SUPPLY_POINT_SET,gold:-1:the quartermaster's warrant to the town,1,spec 2026-10-07-army-supply-lines §4; the courier's fee is the courier_kinds ordinary row
SUPPLY_POINT_CLEAR,gold:-1:the quartermaster's letter recalling the wagons,1,
SUPPLY_CARRY_SET,gold:-1:the wagon-master's tally,1,
```

`scripts/engine/courier_system.gd`:

Refactor `dispatch` into `dispatch_to` (same body, the target point a parameter) and keep `dispatch` calling it:

```gdscript
static func dispatch(repo: DataRepository, state: GameState, kind: String, code: String,
		order: Dictionary) -> Dictionary:
	return dispatch_to(repo, state, kind, code, order,
		ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code)))


## A courier for regiment `code` whose road ends at `to_px` — the regiment
## itself (dispatch), or its supply TOWN (spec 2026-10-07-army-supply-lines
## §4, `order.to_town`): such a courier is never re-aimed at the column.
static func dispatch_to(repo: DataRepository, state: GameState, kind: String, code: String,
		order: Dictionary, to_px: Vector2) -> Dictionary:
	var from := origin(repo, state)
	var home := ArmySystem.pack_to_metres(repo, from)
	var aim := ArmySystem.pack_to_metres(repo, to_px)
	state.next_courier_id += 1
	var c := {
		"id": state.next_courier_id, "kind": kind, "x_m": home.x, "y_m": home.y,
		"path": path_between(repo, from, to_px), "target": code, "order": order.duplicate(true),
		"issued": state.absolute_day(), "aim_x_m": aim.x, "aim_y_m": aim.y,
		"days": 0, "day_m": 0, "slow_spell": -1,
	}
	state.couriers.append(c)
	return c


## A courier bound for a fixed point, never re-aimed at a column: a spy, or
## a supply order riding to its town.
static func _fixed_point(c: Dictionary) -> bool:
	return _is_spy(c) or String((c.get("order", {}) as Dictionary).get("to_town", "")) != ""
```

In `_ride` and `_ride_copy` replace `if not _is_spy(c): _reaim(...)` / `if not _is_spy(c): _reaim(repo, state, copy, reg)` with `if not _fixed_point(c):`.

In `_deliver`, first thing after `var code := ...`:

```gdscript
	if String((c["order"] as Dictionary).get("action_code", "")).begins_with("SUPPLY_"):
		return SupplyLines.deliver(repo, state, c)
```

`scripts/engine/supply_lines.gd` — add:

```gdscript
static func _new_record(town: String, rate: int, order_id: int) -> Dictionary:
	return {"town": town, "rate": rate, "state": ORDERED, "order_id": order_id, "ready_day": 0,
		"cut_x_m": -1, "cut_y_m": -1, "cut_by": "", "fee_milli": 0, "buy_milli": 0, "warned": "",
		"m_drawn": 0, "m_arrived": 0, "m_claimed": 0, "m_skim": 0, "m_fee": 0, "m_buy": 0, "m_bought": {}}


## ActionSystem's SUPPLY_POINT_SET: a new line waits ORDERED; a line already
## running keeps running and holds the new point as `pending`.
static func order_set(state: GameState, code: String, town: String, rate: int, order_id: int) -> void:
	var ln := line(state, code)
	if ln.is_empty():
		state.supply_lines[code] = _new_record(town, rate, order_id)
	else:
		ln["pending"] = {"town": town, "rate": rate, "order_id": order_id}


## A supply courier delivered (CourierSystem._deliver). An older order than
## the line's newest is set aside.
static func deliver(repo: DataRepository, state: GameState, c: Dictionary) -> Dictionary:
	var code := String(c["target"])
	var order: Dictionary = c["order"]
	var id := int(c["id"])
	var ev := {"type": "delivered", "courier": id, "regiment": code, "weather": ""}
	match String(order["action_code"]):
		"SUPPLY_CARRY_SET":
			var entry: Dictionary = state.regiments.get(code, {})
			if entry.is_empty() or int(entry.get("carry_order_id", 0)) > id:
				ev["type"] = "stale"
				return ev
			entry["carry_days"] = int(order["days"])
			entry["carry_order_id"] = id
		"SUPPLY_POINT_SET":
			var ln := line(state, code)
			var p: Dictionary = ln.get("pending", {}) if not ln.is_empty() else {}
			if not p.is_empty() and int(p["order_id"]) == id:
				ln = _new_record(String(p["town"]), int(p["rate"]), id)
				state.supply_lines[code] = ln
			elif ln.is_empty() or int(ln["order_id"]) != id:
				ev["type"] = "stale"
				return ev
			ln["state"] = RIDING
			var km := road_km(repo, road_px(repo, state, code, String(ln["town"])))
			ln["ready_day"] = state.absolute_day() + wagon_days(repo, km)
		"SUPPLY_POINT_CLEAR":
			var ln := line(state, code)
			if ln.is_empty() or int(ln["order_id"]) > id:
				ev["type"] = "stale"
				return ev
			state.supply_lines.erase(code)
	return ev
```

`scripts/engine/action_system.gd` — in `validate`'s `match`:

```gdscript
		"SUPPLY_POINT_SET", "SUPPLY_POINT_CLEAR", "SUPPLY_CARRY_SET":
			return _validate_supply(req, state)
```

and the function (beside `_validate_army`):

```gdscript
## The supply orders (spec 2026-10-07-army-supply-lines §4): a land regiment
## of the realm, a courier the chest can pay, and a point / rate / load the
## tables allow.
func _validate_supply(req: ActionRequest, state: GameState) -> String:
	var code := String(req.params.get("regiment", ""))
	var reg := ArmySystem.regiment(data, code)
	if reg.is_empty():
		return "No such regiment: " + code
	if String(reg["kingdom_code"]) != data.resolve_realm("player_realm"):
		return "%s is not yours to command" % String(reg["label"])
	if String(reg.get("is_naval", "0")) == "1":
		return "%s is a fleet: it carries no supply train" % String(reg["label"])
	if float(state.metrics["treasury"]) < OrderCosts.gold_of(data, req.action_code) \
			+ float(CourierSystem.fee_gold(data, CourierSystem.ORDINARY)):
		return "The chancery cannot pay a courier to ride for %s" % String(reg["label"])
	match req.action_code:
		"SUPPLY_POINT_SET":
			var rate := int(req.params.get("rate", 0))
			if not rate in SupplyLines.RATES:
				return "The wagons run at 0.8×, 1× or 1.2×"
			var town := String(req.params.get("town", ""))
			var why := String(SupplyLines.eligibility(data, state, code).get(town, "That is no town of the realm"))
			if why != "":
				return why
		"SUPPLY_POINT_CLEAR":
			if SupplyLines.line(state, code).is_empty():
				return "%s has no supply point" % String(reg["label"])
		"SUPPLY_CARRY_SET":
			var days := int(req.params.get("days", 0))
			if not data.army_carry_loads.any(func(r: Dictionary) -> bool: return int(r["days"]) == days):
				return "A train carries 10, 15, 20, 25 or 30 days"
	return ""
```

In `execute`'s `match` (beside `ARMY_GARRISON`):

```gdscript
		"SUPPLY_POINT_SET":
			var code := String(req.params["regiment"])
			var town := String(req.params["town"])
			var c := CourierSystem.dispatch_to(data, state, CourierSystem.ORDINARY, code,
				{"action_code": "SUPPLY_POINT_SET", "to_town": town, "rate": int(req.params["rate"])},
				Vector2(float(data.burgs[town]["x"]), float(data.burgs[town]["y"])))
			SupplyLines.order_set(state, code, town, int(req.params["rate"]), int(c["id"]))
			_courier_fee(state, effects, c, "to %s with a supply warrant" % String(data.burgs[town]["label"]))
		"SUPPLY_POINT_CLEAR":
			var code := String(req.params["regiment"])
			var town := String(SupplyLines.line(state, code)["town"])
			var c := CourierSystem.dispatch_to(data, state, CourierSystem.ORDINARY, code,
				{"action_code": "SUPPLY_POINT_CLEAR", "to_town": town},
				Vector2(float(data.burgs[town]["x"]), float(data.burgs[town]["y"])))
			SupplyLines.line(state, code)["order_id"] = int(c["id"])
			_courier_fee(state, effects, c, "to %s to stop the wagons" % String(data.burgs[town]["label"]))
		"SUPPLY_CARRY_SET":
			var code := String(req.params["regiment"])
			_send_courier(state, effects, code, {"action_code": "SUPPLY_CARRY_SET",
				"days": int(req.params["days"])}, "with orders to carry %d days" % int(req.params["days"]))
```

and the helper (beside `_send_courier`):

```gdscript
## A supply courier's fee and the army line saying when he gets there.
func _courier_fee(state: GameState, effects: Array, c: Dictionary, what: String) -> void:
	_apply(state, effects, "treasury", -float(CourierSystem.fee_gold(data, CourierSystem.ORDINARY)),
		"a courier rides " + what)
	var days := CourierSystem.days_left(data, state, c)
	effects.append({"metric": "army", "delta": 0.0, "reason": "A courier rides %s; about %d day%s" % [
		what, days, "" if days == 1 else "s"]})
```

Note on `SUPPLY_POINT_CLEAR`: setting the line's `order_id` to the clear courier's id makes an older SET still riding stale, and `deliver` then erases the line.

- [ ] **Step 4: Run tests**

Run: `./run_tests.sh --fast 2>&1 | grep -A3 "test_supply_orders\|test_courier\|Failing"`
Expected: `test_supply_orders` PASS; every `test_courier_*` still PASS.

- [ ] **Step 5: Commit**

```bash
git add data/policy_actions_court_additions.csv data/action_signatures.csv data/order_costs.csv scripts/engine/courier_system.gd scripts/engine/supply_lines.gd scripts/engine/action_system.gd tests/engine/test_supply_orders.gd
git commit -m "feat(supply): supply point and carried-load orders ride by courier"
```

---

### Task 7: The day's supply step; the monthly resupply retired

**Files:**
- Modify: `scripts/engine/supply_lines.gd` (`day_step`, `_draw`, `_refill_in_town`, `_deliver_line`)
- Modify: `scripts/engine/tick_engine.gd` (`_end_day` calls `SupplyLines.day_step`; `advance` drops `SupplySystem.settle_month`)
- Modify: `scripts/engine/supply_system.gd` (remove `plan`'s monthly refill, `settle_month`, `stronghold_of`, `share`, `ship_for`, `_road_context`, `_path_from_ctx`; keep `loss_of`, `gold_for`, `garrisoned_in`, `any_hungry`; rewrite `line_of` / `route_px` to read the line)
- Modify: `data/balance.csv` (remove `army_supply_target_months`)
- Test: `tests/engine/test_supply_day.gd`; rewrite `tests/engine/test_supply_system.gd`; update `tests/engine/test_army_towns.gd`, `tests/engine/test_trigger_dsl.gd`

**Interfaces:**
- Consumes: Tasks 2–6.
- Produces:
  - `SupplyLines.day_step(repo, state) -> Array` of events `{type, regiment, town, by?, at?}` with `type` ∈ `opened|cut|restored|town_low|low|empty|cancelled`
  - `SupplySystem.line_of(repo, state, code) -> Dictionary` `{town, state, rate, length_km, loss_permille, garrison: bool, garrison_town}` (`town == ""` when none)
  - `SupplySystem.route_px(repo, state, code) -> PackedVector2Array` (the line's road; empty with no line)
  - `TickEngine.day_supply: Array` — the last day's supply events (for Task 8)

- [ ] **Step 1: Write the failing test**

`tests/engine/test_supply_day.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The day's supply step (spec 2026-10-07-army-supply-lines §3.2–3.4).

var repo: DataRepository
var s: GameState
var code := ""
var town := ""

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	RealmEconomy.forget()
	# an able, honest marshal: efficiency 1000, no skim, so the arithmetic is plain
	var m: Character = s.characters[String(s.council["marshal"])]
	m.skills["sk_admin"] = 16
	m.opinion = 50
	m.traits = []
	m.attributes["integrity"] = 50
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		var reg := ArmySystem.regiment(repo, String(c))
		if String(reg.get("is_naval", "0")) != "1" and ArmySystem.held_town_of(repo, reg, s) == "":
			code = String(c)
			break
	if code == "":   # every regiment stands in a town: march the first out into the field
		code = String(codes[0])
		var at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)) + Vector2(40.0, 0.0)
		var mm := ArmySystem.pack_to_metres(repo, at)
		s.regiments[code]["x_m"] = mm.x
		s.regiments[code]["y_m"] = mm.y
	var e := SupplyLines.eligibility(repo, s, code)
	var towns: Array = e.keys()
	towns.sort()
	for t: String in towns:
		if String(e[t]) == "":
			town = t
			break
	s.supply_lines[code] = SupplyLines._new_record(town, 1000, 1)
	s.supply_lines[code]["state"] = SupplyLines.FLOWING

func after_each() -> void:
	RealmEconomy.forget()

func _use() -> int:
	return ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code), s)

func test_a_flowing_line_draws_from_its_town_and_delivers_less_the_road() -> void:
	s.day = 5
	s.regiments[code]["supplies"] = 0
	s.town_stock[town] = {"crown": 100000, "lord": 0, "house": 0}
	var send := ArmySystem.day_bite(_use(), 5)
	var km := SupplyLines.road_km(repo, SupplyLines.road_px(repo, s, code, town))
	var keep := 1000 - SupplySystem.loss_of(repo, km)
	SupplyLines.day_step(repo, s)
	assert_eq(int(TownStores.stock_of(s, town)["crown"]), 100000 - send)
	assert_eq(int(s.regiments[code]["supplies"]), send * keep / 1000)

func test_the_rate_scales_the_draw() -> void:
	s.day = 5
	s.regiments[code]["supplies"] = 0
	s.town_stock[town] = {"crown": 100000, "lord": 0, "house": 0}
	s.supply_lines[code]["rate"] = 1200
	SupplyLines.day_step(repo, s)
	assert_eq(100000 - int(TownStores.stock_of(s, town)["crown"]), ArmySystem.day_bite(_use() * 1200 / 1000, 5))

func test_the_draw_stops_at_thirty_days() -> void:
	s.regiments[code]["supplies"] = ArmySystem.max_units(repo, _use())
	s.town_stock[town] = {"crown": 100000, "lord": 0, "house": 0}
	SupplyLines.day_step(repo, s)
	assert_true(int(s.regiments[code]["supplies"]) <= ArmySystem.max_units(repo, _use()) + ArmySystem.day_bite(_use(), s.day))

func test_crown_then_lord_then_the_house_is_bought() -> void:
	s.day = 5
	s.regiments[code]["supplies"] = 0
	var send := ArmySystem.day_bite(_use(), 5)
	assert_gt(send, 2)
	s.town_stock[town] = {"crown": 1, "lord": 1, "house": 100}
	var gold := float(s.metrics["treasury"])
	SupplyLines.day_step(repo, s)
	var st := TownStores.stock_of(s, town)
	assert_eq(int(st["crown"]), 0)
	assert_eq(int(st["lord"]), 0)
	assert_eq(int(st["house"]), 100 - (send - 2))
	assert_true(float(s.metrics["treasury"]) <= gold, "the house's goods are paid for")

func test_an_empty_treasury_buys_nothing_from_the_house() -> void:
	s.day = 5
	s.regiments[code]["supplies"] = 0
	s.town_stock[town] = {"crown": 0, "lord": 0, "house": 100}
	s.metrics["treasury"] = 0.0
	SupplyLines.day_step(repo, s)
	assert_eq(int(TownStores.stock_of(s, town)["house"]), 100)

func test_cartage_is_charged_in_whole_gold_and_the_rest_carried() -> void:
	s.day = 5
	s.regiments[code]["supplies"] = 0
	s.town_stock[town] = {"crown": 100000, "lord": 0, "house": 0}
	var km := SupplyLines.road_km(repo, SupplyLines.road_px(repo, s, code, town))
	var milli := ArmySystem.day_bite(_use(), 5) * km * int(repo.bal("supply_cart_milligold_per_unit_km"))
	var gold := float(s.metrics["treasury"])
	SupplyLines.day_step(repo, s)
	assert_eq(int(gold - float(s.metrics["treasury"])), milli / 1000)
	assert_eq(int(s.supply_lines[code]["fee_milli"]), milli % 1000)

func test_a_riding_line_flows_on_its_ready_day() -> void:
	s.supply_lines[code]["state"] = SupplyLines.RIDING
	s.supply_lines[code]["ready_day"] = s.absolute_day() + 1
	var ev := SupplyLines.day_step(repo, s)
	assert_eq(String(s.supply_lines[code]["state"]), SupplyLines.RIDING)
	s.day += 1
	ev = SupplyLines.day_step(repo, s)
	assert_eq(String(s.supply_lines[code]["state"]), SupplyLines.FLOWING)
	assert_true(ev.any(func(e: Dictionary) -> bool: return String(e["type"]) == "opened"))

func test_a_line_whose_town_leaves_the_realm_is_cancelled() -> void:
	var prov := String(repo.burgs[town]["province_code"])
	var other := repo.resolve_realm("raider_realm")
	MapOwnership.set_owner(repo, s, prov, other, "a test conquest")
	var ev := SupplyLines.day_step(repo, s)
	assert_true(SupplyLines.line(s, code).is_empty())
	assert_true(ev.any(func(e: Dictionary) -> bool: return String(e["type"]) == "cancelled"))

func test_a_cut_line_draws_nothing_and_says_so() -> void:
	s.regiments[code]["supplies"] = 0
	s.town_stock[town] = {"crown": 100000, "lord": 0, "house": 0}
	var route := SupplyLines.road_px(repo, s, code, town)
	var realm := repo.resolve_realm("player_realm")
	for r: Dictionary in repo.world_table("military", "regiments").values():
		if String(r["kingdom_code"]) != realm:
			r["x"] = route[route.size() / 2].x
			r["y"] = route[route.size() / 2].y
			repo.world_table("political", "diplomacy")["%s>%s" % [realm, String(r["kingdom_code"])]] = {"stance": "Enemy"}
			break
	var ev := SupplyLines.day_step(repo, s)
	assert_eq(String(s.supply_lines[code]["state"]), SupplyLines.CUT)
	assert_eq(int(TownStores.stock_of(s, town)["crown"]), 100000)
	assert_true(ev.any(func(e: Dictionary) -> bool: return String(e["type"]) == "cut"))

func test_a_regiment_in_a_realm_town_is_topped_up_free() -> void:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		var reg := ArmySystem.regiment(repo, String(c))
		var held := ArmySystem.held_town_of(repo, reg, s)
		if held == "" or String(c) == code:
			continue
		s.regiments[c]["supplies"] = 0
		s.town_stock[held] = {"crown": 100000, "lord": 0, "house": 0}
		var gold := float(s.metrics["treasury"])
		SupplyLines.day_step(repo, s)
		var use := ArmySystem.supply_use(repo, reg, s)
		var want := use * ArmySystem.carry_of(repo, s.regiments[c]) / 30 + ArmySystem.day_bite(use, s.day)
		assert_eq(int(s.regiments[c]["supplies"]), mini(want, ArmySystem.max_units(repo, use) + ArmySystem.day_bite(use, s.day)))
		assert_eq(float(s.metrics["treasury"]), gold, "no cartage inside a town")
		return
	pending("no regiment stands in a realm town on this pack")

func test_a_line_follows_a_marching_column() -> void:
	var before := SupplyLines.road_km(repo, SupplyLines.road_px(repo, s, code, town))
	var at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)) + Vector2(60.0, 0.0)
	var m := ArmySystem.pack_to_metres(repo, at)
	s.regiments[code]["x_m"] = m.x
	s.regiments[code]["y_m"] = m.y
	SupplyLines.day_step(repo, s)
	assert_false(SupplyLines.line(s, code).is_empty(), "out of range, the line still runs")
	assert_ne(SupplyLines.road_km(repo, SupplyLines.road_px(repo, s, code, town)), before)
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./run_tests.sh --fast 2>&1 | grep -A3 test_supply_day`
Expected: FAIL — `day_step` not found.

- [ ] **Step 3: Implement**

Append to `scripts/engine/supply_lines.gd`:

```gdscript
## Draws up to `units` from `town` (spec §3.3): crown, lord, then the house's
## stock BOUGHT at value × (1000 + supply_buy_markup_permille) / 1000 while
## the treasury can pay, the price accrued in milligold on `acc["buy_milli"]`
## and whole gold taken as it crosses. {got, house, house_gold}.
static func _draw(repo: DataRepository, state: GameState, town: String, units: int, acc: Dictionary) -> Dictionary:
	var got := TownStores.take(state, town, "crown", units)
	got += TownStores.take(state, town, "lord", units - got)
	var want := units - got
	var bought := 0
	var paid := 0
	if want > 0:
		var milli_each := int(repo.bal("army_supply_gold_permille")) * (1000 + int(repo.bal("supply_buy_markup_permille"))) / 1000
		var purse := maxi(int(state.metrics.get("treasury", 0.0)), 0) * 1000 + int(acc.get("buy_milli", 0))
		@warning_ignore("integer_division")
		var afford := purse / maxi(milli_each, 1)
		bought = TownStores.take(state, town, "house", mini(want, afford))
		var milli := int(acc.get("buy_milli", 0)) + bought * milli_each
		@warning_ignore("integer_division")
		paid = milli / 1000
		acc["buy_milli"] = milli % 1000
		if paid > 0:
			state.metrics["treasury"] = float(state.metrics["treasury"]) - float(paid)
	return {"got": got + bought, "house": bought, "house_gold": paid}


## The units a regiment may still take today: up to `target`, never past
## army_supply_max_days after today's meal.
static func _room(repo: DataRepository, supplies: int, use: int, day: int, target: int) -> int:
	var bite := ArmySystem.day_bite(use, day)
	return maxi(mini(target, ArmySystem.max_units(repo, use) + bite) - supplies, 0)


## A land regiment standing in a realm town is topped up to its carried load
## from that town, free of cartage and road (spec §3.2 step 4).
static func _refill_in_town(repo: DataRepository, state: GameState, code: String, reg: Dictionary) -> void:
	var held := ArmySystem.held_town_of(repo, reg, state)
	if held == "" or not TownStores.is_realm_town(repo, state, held):
		return
	var entry: Dictionary = state.regiments[code]
	var use := ArmySystem.supply_use(repo, reg, state)
	@warning_ignore("integer_division")
	var target := use * ArmySystem.carry_of(repo, entry) / Calendar.DAYS_PER_TICK + ArmySystem.day_bite(use, state.day)
	var room := _room(repo, int(entry["supplies"]), use, state.day, target)
	if room <= 0:
		return
	var acc := {"buy_milli": int(entry.get("buy_milli", 0))}
	var d := _draw(repo, state, held, room, acc)
	entry["buy_milli"] = int(acc["buy_milli"])
	entry["supplies"] = int(entry["supplies"]) + int(d["got"])


## A flowing line's day (spec §3.2 step 3, §3.4): the day's quota at its
## rate, drawn, thinned by the road and the marshal, its cartage charged.
static func _deliver_line(repo: DataRepository, state: GameState, code: String, reg: Dictionary,
		ln: Dictionary, km: int) -> void:
	var entry: Dictionary = state.regiments[code]
	var use := ArmySystem.supply_use(repo, reg, state)
	@warning_ignore("integer_division")
	var quota := ArmySystem.day_bite(use * int(ln["rate"]) / 1000, state.day)
	var send := mini(quota, _room(repo, int(entry["supplies"]), use, state.day, ArmySystem.max_units(repo, use) + ArmySystem.day_bite(use, state.day)))
	if send <= 0:
		return
	var d := _draw(repo, state, String(ln["town"]), send, ln)
	var got := int(d["got"])
	var g := Governance.factors(repo, state, "supply_line")
	@warning_ignore("integer_division")
	var skimmed := got * int(g["skim"]) / 1000
	var keep := 1000 - SupplySystem.loss_of(repo, km)
	@warning_ignore("integer_division")
	var arrived := (got - skimmed) * keep / 1000 * int(g["efficiency"]) / 1000
	@warning_ignore("integer_division")
	var claimed := got * keep / 1000 * int(g["efficiency"]) / 1000
	entry["supplies"] = int(entry["supplies"]) + arrived
	var milli := int(ln["fee_milli"]) + got * km * int(repo.bal("supply_cart_milligold_per_unit_km"))
	@warning_ignore("integer_division")
	var fee := milli / 1000
	ln["fee_milli"] = milli % 1000
	if fee > 0:
		state.metrics["treasury"] = float(state.metrics["treasury"]) - float(fee)
	ln["m_drawn"] = int(ln["m_drawn"]) + got
	ln["m_arrived"] = int(ln["m_arrived"]) + arrived
	ln["m_claimed"] = int(ln["m_claimed"]) + claimed
	ln["m_skim"] = int(ln["m_skim"]) + skimmed
	ln["m_fee"] = int(ln["m_fee"]) + fee
	ln["m_buy"] = int(ln["m_buy"]) + int(d["house_gold"])
	if int(d["house"]) > 0:
		var house := MapManors.controller_of(repo, state, String(repo.burgs[String(ln["town"])]["province_code"]))
		var bought: Dictionary = ln["m_bought"]
		bought[house] = int(bought.get(house, 0)) + int(d["house"])


## The day's supply for every regiment of the realm, in code order
## (TickEngine._end_day, after the couriers ride, before the host eats):
## the town refills, then each line's state, interception and delivery.
## Returns the day's events for the dispatches (MissiveWriter.supply_dispatch).
static func day_step(repo: DataRepository, state: GameState) -> Array:
	TownStores.reconcile(repo, state)
	var events: Array = []
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		_refill_in_town(repo, state, code, reg)
	var lines: Array = state.supply_lines.keys()
	lines.sort()
	for c in lines:
		var code := String(c)
		var ln: Dictionary = state.supply_lines[code]
		var reg := ArmySystem.regiment(repo, code)
		if reg.is_empty() or not state.regiments.has(code):
			state.supply_lines.erase(code)
			continue
		var town := String(ln["town"])
		if not TownStores.is_realm_town(repo, state, town):
			state.supply_lines.erase(code)
			events.append({"type": "cancelled", "regiment": code, "town": town})
			continue
		if String(ln["state"]) == ORDERED:
			continue
		if String(ln["state"]) == RIDING:
			if state.absolute_day() < int(ln["ready_day"]):
				continue
			ln["state"] = FLOWING
			events.append({"type": "opened", "regiment": code, "town": town})
		var route := road_px(repo, state, code, town)
		var cut := cut_point(repo, state, route)
		if not cut.is_empty():
			if String(ln["state"]) != CUT:
				var at := ArmySystem.pack_to_metres(repo, cut["at"])
				ln["cut_x_m"] = at.x
				ln["cut_y_m"] = at.y
				ln["cut_by"] = String(cut["by"])
				events.append({"type": "cut", "regiment": code, "town": town, "by": String(cut["by"]),
					"at": cut["at"]})
			ln["state"] = CUT
			continue
		if String(ln["state"]) == CUT:
			ln["state"] = FLOWING
			ln["cut_x_m"] = -1
			ln["cut_y_m"] = -1
			ln["cut_by"] = ""
			events.append({"type": "restored", "regiment": code, "town": town})
		_deliver_line(repo, state, code, reg, ln, road_km(repo, route))
	events.append_array(_warnings(repo, state))
	TownStores.sync_metrics(repo, state)
	return events


## Low and empty regiments, and supply towns running short — each said once
## until it recovers (the `warned` marks on the regiment and the line).
static func _warnings(repo: DataRepository, state: GameState) -> Array:
	var out: Array = []
	var low := int(repo.bal("army_supply_low_days"))
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		var entry: Dictionary = state.regiments[code]
		var days := ArmySystem.days_in_hand(int(entry["supplies"]), ArmySystem.supply_use(repo, reg, state))
		var now := "empty" if int(entry["supplies"]) <= 0 else ("low" if days < low else "")
		if now != String(entry.get("supply_warn", "")):
			entry["supply_warn"] = now
			if now != "":
				out.append({"type": now, "regiment": code, "town": String(line(state, code).get("town", ""))})
	var warn_days := int(repo.bal("supply_warn_town_days"))
	var draw: Dictionary = {}
	for code: String in state.supply_lines:
		var ln: Dictionary = state.supply_lines[code]
		if String(ln["state"]) != FLOWING:
			continue
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code), state)
		@warning_ignore("integer_division")
		draw[String(ln["town"])] = int(draw.get(String(ln["town"]), 0)) + use * int(ln["rate"]) / 1000
	var towns: Array = draw.keys()
	towns.sort()
	for t: String in towns:
		var st := TownStores.stock_of(state, t)
		@warning_ignore("integer_division")
		var holds := (int(st["crown"]) + int(st["lord"]) + int(st["house"])) * Calendar.DAYS_PER_TICK / maxi(int(draw[t]), 1)
		for code: String in state.supply_lines:
			var ln: Dictionary = state.supply_lines[code]
			if String(ln["town"]) != t:
				continue
			var short := holds < warn_days
			if short and String(ln.get("warned", "")) != "town_low":
				out.append({"type": "town_low", "regiment": code, "town": t, "days": holds})
			ln["warned"] = "town_low" if short else ""
	return out
```

`scripts/engine/tick_engine.gd` `_end_day`, after `day_couriers = CourierSystem.ride_day(data, state)`:

```gdscript
	# The supply lines' day (spec 2026-10-07-army-supply-lines §3.2): the towns
	# refill their garrisons, the wagons roll, before the host eats.
	day_supply = SupplyLines.day_step(data, state)
```

declare `var day_supply: Array = []` beside `day_couriers`, and in `advance`'s `else` branch for tick 0 add `day_supply = []`. Remove the `SupplySystem.settle_month` loop from `advance` (Task 8 puts the marshal's month there).

`scripts/engine/supply_system.gd` — replace the file's body below the class doc with the kept helpers and the two readers. New class doc: "The supply helpers the cards, the WAR ROOM and the LEDGER read (spec 2026-10-07-army-supply-lines): the road's loss, the garrison test, and a regiment's line as it stands. The daily step is SupplyLines.day_step." Keep `loss_of`, `gold_for`, `garrisoned_in`, `_land_codes`, `any_hungry` verbatim; delete `ship_for`, `share`, `stronghold_of`, `_road_context`, `_path_from_ctx`, `plan`, `settle_month`; replace `line_of` and `route_px`:

```gdscript
## A regiment's line as it stands, for the cards: {town ("" with none),
## state, rate, length_km, loss_permille, garrison, garrison_town}.
static func line_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var held := garrisoned_in(repo, state, code)
	var ln := SupplyLines.line(state, code)
	var out := {"town": "", "state": "", "rate": 0, "length_km": 0, "loss_permille": 0,
		"garrison": held != "", "garrison_town": held}
	if ln.is_empty():
		return out
	var km := SupplyLines.road_km(repo, SupplyLines.road_px(repo, state, code, String(ln["town"])))
	out["town"] = String(ln["town"])
	out["state"] = String(ln["state"])
	out["rate"] = int(ln["rate"])
	out["length_km"] = km
	out["loss_permille"] = loss_of(repo, km)
	return out


## The supply road a regiment is fed along, pack px from its supply town to
## where it stands (the WAR ROOM's ink, the 3D map's line); empty with none.
static func route_px(repo: DataRepository, state: GameState, code: String) -> PackedVector2Array:
	var ln := SupplyLines.line(state, code)
	if ln.is_empty():
		return PackedVector2Array()
	return SupplyLines.road_px(repo, state, code, String(ln["town"]))
```

Remove `army_supply_target_months` from `data/balance.csv`.

Rewrite `tests/engine/test_supply_system.gd` to the kept functions: keep `test_the_loss_grows_with_the_road_and_is_capped`; delete the `ship_for`/`share`/`plan`/`settle_month`/stronghold tests; add:

```gdscript
func test_line_of_reads_the_line() -> void:
	var code := String(_land_codes()[0])
	assert_eq(String(SupplySystem.line_of(data, s, code)["town"]), "", "no line yet")
	var town: String = TownStores.realm_towns(data, s)[0]
	s.supply_lines[code] = SupplyLines._new_record(town, 800, 1)
	var line := SupplySystem.line_of(data, s, code)
	assert_eq(String(line["town"]), town)
	assert_eq(int(line["rate"]), 800)
	assert_eq(int(line["loss_permille"]), SupplySystem.loss_of(data, int(line["length_km"])))
	assert_eq(SupplySystem.route_px(data, s, code), SupplyLines.road_px(data, s, code, town))
```

In `tests/engine/test_army_towns.gd:224–226` drop the `stronghold_of` assertion and keep `assert_false(bool(SupplySystem.line_of(repo, s, code)["garrison"]))`. In `tests/engine/test_trigger_dsl.gd` set hunger with days: `s.regiments[c]["supplies"] = 0` for hungry, `ArmySystem.max_units(...)` for fed (keep the assertions).

- [ ] **Step 4: Run tests**

Run: `./run_tests.sh --fast 2>&1 | tail -20`
Expected: `test_supply_day`, `test_supply_system` PASS. Remaining failures only in `test_governed_flows`, `test_ledger_supply`, `test_ledger_governors`, `test_war_folio`, `tests/ledger3d/test_ledger_strands` (they call `SupplySystem.plan`; Task 9 restores `plan` as a projection) — list them and move on.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/supply_lines.gd scripts/engine/supply_system.gd scripts/engine/tick_engine.gd data/balance.csv tests/engine/test_supply_day.gd tests/engine/test_supply_system.gd tests/engine/test_army_towns.gd tests/engine/test_trigger_dsl.gd
git commit -m "feat(supply): the daily supply step; the monthly capital refill retired"
```

---

### Task 8: Missives — the day's dispatch and the marshal's month

**Files:**
- Modify: `scripts/engine/missive_writer.gd` (`supply_dispatch`, `marshal_report`)
- Modify: `scripts/engine/supply_lines.gd` (`settle_month(repo, state) -> Array` rows; resets `m_*`; banks skims)
- Modify: `scripts/engine/tick_engine.gd` (`_end_day` files the dispatch; `advance` files the marshal's report)
- Test: `tests/engine/test_supply_missives.gd`

**Interfaces:**
- Consumes: Task 7 events; `Governance.add_skims(state, rows, flow)` (rows need `skimmed` gold and `governor`).
- Produces: `MissiveWriter.supply_dispatch(repo, state, events: Array) -> Dictionary`; `MissiveWriter.marshal_report(repo, state, tick: int, rows: Array) -> Dictionary`; `SupplyLines.settle_month(repo, state) -> Array` rows `{code, town, rate, days, carry, km, drawn, arrived, claimed, fee, buy, bought: {house: units}, skimmed (gold), governor}`.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Supply missives (spec 2026-10-07-army-supply-lines §5.5).

var repo: DataRepository
var s: GameState

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)

func _land() -> String:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			return String(c)
	return ""

func test_one_dispatch_gathers_the_days_events() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	var m := MissiveWriter.supply_dispatch(repo, s, [
		{"type": "opened", "regiment": code, "town": town},
		{"type": "low", "regiment": code, "town": town}])
	assert_eq(String(m["kind"]), "supply")
	assert_eq(String(m["column"]), "credible")
	assert_eq((m["facts"] as Array).size(), 2)

func test_a_day_with_events_files_one_letter_and_a_quiet_day_none() -> void:
	var engine := TickEngine.new(repo)
	var code := _land()
	# out in the field, so no town tops it up before the warnings are read
	var at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)) + Vector2(40.0, 0.0)
	var mm := ArmySystem.pack_to_metres(repo, at)
	s.regiments[code]["x_m"] = mm.x
	s.regiments[code]["y_m"] = mm.y
	s.regiments[code]["dest_x_m"] = mm.x
	s.regiments[code]["dest_y_m"] = mm.y
	var before := s.missives.size()
	s.regiments[code]["supplies"] = 0     # it goes hungry today: one "empty" event
	engine.advance_day(s)
	var supply: Array = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "supply")
	assert_eq(supply.size(), 1)
	engine.advance_day(s)                 # nothing new to say
	supply = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "supply")
	assert_eq(supply.size(), 1)
	assert_true(s.missives.size() >= before + 1)

func test_the_marshals_report_has_a_row_per_land_regiment_and_resets_the_month() -> void:
	var code := _land()
	var town: String = TownStores.realm_towns(repo, s)[0]
	s.supply_lines[code] = SupplyLines._new_record(town, 1000, 1)
	s.supply_lines[code]["m_fee"] = 9
	var rows := SupplyLines.settle_month(repo, s)
	var row: Dictionary = rows.filter(func(r: Dictionary) -> bool: return String(r["code"]) == code)[0]
	assert_eq(int(row["fee"]), 9)
	assert_eq(int(s.supply_lines[code]["m_fee"]), 0, "the month starts afresh")
	var m := MissiveWriter.marshal_report(repo, s, 1, rows)
	assert_eq(String(m["kind"]), "supply_month")
	assert_true((m["facts"] as Array).size() >= rows.size())
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./run_tests.sh --fast 2>&1 | grep -A3 test_supply_missives`
Expected: FAIL — `supply_dispatch` not found.

- [ ] **Step 3: Implement**

`scripts/engine/missive_writer.gd`:

```gdscript
const _SUPPLY_WORDS := {
	"opened": "The wagons from %s have reached %s.",
	"cut": "The road from %s to %s is cut by %s.",
	"restored": "The road from %s to %s is open again.",
	"town_low": "%s can feed %s for only %d more days.",
	"low": "%s has under five days of supplies (fed from %s).",
	"empty": "%s has eaten its last supplies (fed from %s).",
	"cancelled": "%s is no longer ours: the line to %s is gone.",
}


## The day's supply news in ONE letter (spec 2026-10-07-army-supply-lines
## §5.5): a fact per event, about the first event's regiment.
static func supply_dispatch(repo: DataRepository, state: GameState, events: Array) -> Dictionary:
	var facts: Array = []
	for i in events.size():
		var e: Dictionary = events[i]
		var reg := String(ArmySystem.regiment(repo, String(e["regiment"])).get("label", e["regiment"]))
		var town := String((repo.burgs.get(String(e.get("town", "")), {}) as Dictionary).get("label", e.get("town", "")))
		var text := ""
		match String(e["type"]):
			"cut":
				text = _SUPPLY_WORDS["cut"] % [town, reg, String((repo.kingdoms.get(String(e["by"]), {}) as Dictionary).get("label", e["by"]))]
			"town_low":
				text = _SUPPLY_WORDS["town_low"] % [town, reg, int(e["days"])]
			"low", "empty":
				text = _SUPPLY_WORDS[String(e["type"])] % [reg, town if town != "" else "no town"]
			"cancelled":
				text = _SUPPLY_WORDS["cancelled"] % [town, reg]
			_:
				text = _SUPPLY_WORDS[String(e["type"])] % [town, reg]
		facts.append(MissiveLog.words("supply_%d" % i, String(e["type"]).capitalize(), text))
	var first := String((events[0] as Dictionary)["regiment"])
	var at := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, first))
	return MissiveLog.make("supply", "credible", state.absolute_day(),
		MissiveLog.subject("regiment", first, -1, at), "Supply dispatch", facts)


## The marshal's month (spec §5.5): a row per land regiment — his CLAIM of
## what arrived, beside days in hand, load, point, rate, road, cartage and
## purchases.
static func marshal_report(repo: DataRepository, state: GameState, tick: int, rows: Array) -> Dictionary:
	var facts: Array = []
	var fee := 0
	var buy := 0
	for r: Dictionary in rows:
		var label := String(ArmySystem.regiment(repo, String(r["code"])).get("label", r["code"]))
		var town := String((repo.burgs.get(String(r["town"]), {}) as Dictionary).get("label", ""))
		var where := "no supply point" if town == "" else "%s · %.1f× · %d km" % [town, float(int(r["rate"])) / 1000.0, int(r["km"])]
		facts.append(MissiveLog.words("days@" + String(r["code"]), label,
			"%d days in hand of %d · %s · %d arrived · %d gold cartage" % [int(r["days"]), int(r["carry"]), where, int(r["claimed"]), int(r["fee"])]))
		fee += int(r["fee"])
		buy += int(r["buy"])
	facts.push_front(MissiveLog.exact("supply_buy", "Bought from the houses", buy))
	facts.push_front(MissiveLog.exact("supply_fee", "Cartage, all lines", fee))
	var home := MapManors.home_province(repo, state)
	var prov: Dictionary = repo.provinces.get(home, {})
	return MissiveLog.make("supply_month", "credible", state.absolute_day(),
		MissiveLog.subject("province", home, -1, Vector2(float(prov.get("center_x", 0)), float(prov.get("center_y", 0)))),
		"Marshal's supply report — %s, Year %d" % [Calendar.month_label(tick), Calendar.year_of(tick)], facts)
```

`scripts/engine/supply_lines.gd`:

```gdscript
## The month's close (TickEngine.advance): a row per land regiment for the
## marshal's report, his skims banked (Governance.add_skims), the month's
## counters reset.
static func settle_month(repo: DataRepository, state: GameState) -> Array:
	var rows: Array = []
	var gov := Governance.governor_of(repo, state, "supply_line")
	var codes: Array = state.regiments.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code)
		if reg.is_empty() or String(reg.get("is_naval", "0")) == "1":
			continue
		var entry: Dictionary = state.regiments[code]
		var ln := line(state, code)
		var use := ArmySystem.supply_use(repo, reg, state)
		var row := {"code": code, "town": String(ln.get("town", "")), "rate": int(ln.get("rate", 0)),
			"days": ArmySystem.days_in_hand(int(entry["supplies"]), use), "carry": ArmySystem.carry_of(repo, entry),
			"km": 0 if ln.is_empty() else road_km(repo, road_px(repo, state, code, String(ln["town"]))),
			"drawn": int(ln.get("m_drawn", 0)), "arrived": int(ln.get("m_arrived", 0)),
			"claimed": int(ln.get("m_claimed", 0)), "fee": int(ln.get("m_fee", 0)), "buy": int(ln.get("m_buy", 0)),
			"bought": (ln.get("m_bought", {}) as Dictionary).duplicate(),
			"skimmed": TownStores.gold_of_units(repo, int(ln.get("m_skim", 0))), "governor": gov}
		rows.append(row)
		for k: String in ["m_drawn", "m_arrived", "m_claimed", "m_skim", "m_fee", "m_buy"]:
			if not ln.is_empty():
				ln[k] = 0
		if not ln.is_empty():
			ln["m_bought"] = {}
	Governance.add_skims(state, rows, "supply_line")
	return rows
```

`scripts/engine/tick_engine.gd` `_end_day`, after `day_supply = ...`:

```gdscript
	if not day_supply.is_empty():
		MissiveLog.add(data, state, MissiveWriter.supply_dispatch(data, state, day_supply))
```

`advance`, where `SupplySystem.settle_month` stood (after the steward's report):

```gdscript
	# The marshal's month (spec 2026-10-07-army-supply-lines §5.5): his
	# report, his skims banked, the lines' counters reset.
	var supply_rows := SupplyLines.settle_month(data, state)
	if state.tick > 0:
		MissiveLog.add(data, state, MissiveWriter.marshal_report(data, state, state.tick, supply_rows))
```

Check the Missive board's kind filters (`scripts/ui/missive_screen.gd`, `Intel._latest`): a `supply` / `supply_month` letter must show in the credible column like a receipt. If `missive_screen.gd` maps kinds to an icon or a label table, add rows for the two kinds in that table's CSV.

- [ ] **Step 4: Run tests**

Run: `./run_tests.sh --fast 2>&1 | grep -A3 "test_supply_missives\|test_missive"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/missive_writer.gd scripts/engine/supply_lines.gd scripts/engine/tick_engine.gd tests/engine/test_supply_missives.gd
git commit -m "feat(supply): the day's supply dispatch and the marshal's monthly report"
```

---

### Task 9: The LEDGER, the audit, the WAR ROOM folio and the cards' engine side

**Files:**
- Modify: `scripts/engine/supply_system.gd` (`plan(repo, state) -> Array`: the month projected from today)
- Modify: `data/ledger_link_types.csv` (add `stocks`, `dispatches`, `sells_to`; delete the `supplies_in` row)
- Modify: `scripts/engine/ledger_resolvers.gd` (resolvers `stocks`, `dispatches`, `sells_to`; `_supply` reads the new plan; `_instances_of_flow` / `supply_lines` list only lines)
- Modify: `scripts/engine/ledger_cards.gd` (`_head` for `supply_line`), `scripts/engine/war_folio.gd` (`_supply`), `scripts/engine/map_objects.gd` (regiment card stats; town card stores), `scripts/engine/audit_writer.gd` (unchanged call, new rows)
- Test: `tests/engine/test_supply_ledger.gd`; update `tests/engine/test_governed_flows.gd`, `tests/engine/test_ledger_supply.gd`, `tests/engine/test_ledger_governors.gd`, `tests/engine/test_war_folio.gd`, `tests/ledger3d/test_ledger_strands.gd`

**Interfaces:**
- Produces: `SupplySystem.plan(repo, state) -> Array` rows `{code, town, rate, state, length_km, loss_permille, need, paid, delivered, claimed, skimmed, efficiency, skim, governor}` — one per line (no line, no row); `need` = the month's draw at today's rate (`use × rate / 1000`), `paid` its gold (`TownStores.gold_of_units`), `delivered` / `claimed` after the road and the marshal, exactly as `_deliver_line` computes a day, times the month.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The LEDGER's supply chain (spec 2026-10-07-army-supply-lines §2.3).

var repo: DataRepository
var s: GameState
var code := ""
var town := ""

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			code = String(c)
			break
	town = TownStores.realm_towns(repo, s)[0]

func test_no_line_no_plan_row() -> void:
	assert_eq(SupplySystem.plan(repo, s), [])

func test_a_line_is_one_row_projecting_its_month() -> void:
	s.supply_lines[code] = SupplyLines._new_record(town, 1200, 1)
	s.supply_lines[code]["state"] = SupplyLines.FLOWING
	var rows := SupplySystem.plan(repo, s)
	assert_eq(rows.size(), 1)
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code), s)
	assert_eq(int(rows[0]["need"]), use * 1200 / 1000)
	assert_eq(int(rows[0]["paid"]), TownStores.gold_of_units(repo, use * 1200 / 1000))
	assert_eq(String(rows[0]["town"]), town)

func test_the_link_types_are_the_new_chain() -> void:
	var live: Array = []
	for row: Dictionary in repo.ledger_links:
		if String(row["status"]) == "live":
			live.append(String(row["link_id"]))
	for id in ["stocks", "dispatches", "sells_to", "supplies_out"]:
		assert_true(live.has(id), id)
	assert_false(live.has("supplies_in"))

func test_the_regiment_card_names_the_supply_point() -> void:
	s.supply_lines[code] = SupplyLines._new_record(town, 800, 1)
	s.supply_lines[code]["state"] = SupplyLines.FLOWING
	var card := MapObjects.army_card(repo, code, s)
	var stat: Dictionary = (card["stats"] as Array).filter(func(x: Dictionary) -> bool:
		return String(x["key"]) == "army_supply_line")[0]
	assert_true(String(stat["tooltip"]).contains(String(repo.burgs[town]["label"])))
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./run_tests.sh --fast 2>&1 | grep -A3 test_supply_ledger`
Expected: FAIL — `plan` not found.

- [ ] **Step 3: Implement**

`scripts/engine/supply_system.gd`:

```gdscript
## The month a line will run at today's rate, read by the LEDGER, the audit
## and the WAR ROOM (spec 2026-10-07-army-supply-lines §2.3): one row per
## line, code order. `delivered` is the truth after the road and the
## marshal's efficiency and skim; `claimed` his word. Memoised by
## LedgerResolvers as before.
static func plan(repo: DataRepository, state: GameState) -> Array:
	var rows: Array = []
	var g := Governance.factors(repo, state, "supply_line")
	var eff := int(g["efficiency"])
	var skim := int(g["skim"])
	var codes: Array = state.supply_lines.keys()
	codes.sort()
	for c in codes:
		var code := String(c)
		var reg := ArmySystem.regiment(repo, code)
		if reg.is_empty():
			continue
		var ln: Dictionary = state.supply_lines[code]
		var line := line_of(repo, state, code)
		@warning_ignore("integer_division")
		var need := ArmySystem.supply_use(repo, reg, state) * int(ln["rate"]) / 1000
		var keep := 1000 - int(line["loss_permille"])
		@warning_ignore("integer_division")
		var skimmed := need * skim / 1000
		@warning_ignore("integer_division")
		var delivered := (need - skimmed) * keep / 1000 * eff / 1000
		@warning_ignore("integer_division")
		var claimed := need * keep / 1000 * eff / 1000
		rows.append({"code": code, "town": String(ln["town"]), "rate": int(ln["rate"]), "state": String(ln["state"]),
			"length_km": int(line["length_km"]), "loss_permille": int(line["loss_permille"]),
			"need": need, "paid": TownStores.gold_of_units(repo, need), "delivered": delivered,
			"claimed": claimed, "skimmed": TownStores.gold_of_units(repo, skimmed),
			"efficiency": eff, "skim": skim, "governor": String(g["governor"])})
	return rows
```

`data/ledger_link_types.csv` — delete the `supplies_in` row (the goods now come from a named town, spec §2.3; `Ledger._check_status` accepts only its `STATUSES`, so a "retired" status is not an option) and add:

```csv
stocks,manor,town,stocks,economy|war|all,live,stocks,,,,,flow,"spec 2026-10-07-army-supply-lines §2.3: a manor's strategic goods landing in its catchment town"
dispatches,town,supply_line,dispatches,war|all,live,dispatches,marshal,seat,,,flow,"spec 2026-10-07 §2.3: a town's wagons on a supply line"
sells_to,house,town,sells to,economy|war|all,live,sells_to,,,,,flow,"spec 2026-10-07 §2.3: a house's stock bought for the host this month"
```

Remove `"supplies_in"` from any `data/ledger_loops.csv` row that lists it (the `hungry_host` loop becomes `dispatches|supplies_out`) and from `data/ledger_actions.csv` if a row keys on it.

`scripts/engine/ledger_resolvers.gd`:
- add `"stocks", "dispatches", "sells_to"` to the resolver-name list at line 24;
- in the `match String(row["resolver"])` add:

```gdscript
		"stocks":
			return _stocks(repo, state, id)
		"dispatches":
			return _dispatches(repo, state, id)
		"sells_to":
			return _sells_to(repo, state, id)
```

- the three resolvers (beside `_supply`), following `_supply`'s type-level / instance-level shape:

```gdscript
## manor -> town: the month's strategic goods into its catchment town (gold).
static func _stocks(repo: DataRepository, state: GameState, id: String) -> Array:
	var inflow := TownStores.month_inflow(repo, state)
	if id == "":
		var n := 0
		for t: String in inflow:
			n += int(inflow[t]["lord"]) + int(inflow[t]["crown"]) + int(inflow[t]["house"])
		return [_type_link("manor", "town", n, "gold")]
	var out: Array = []
	if id.begins_with("manor:"):
		var cell := int(id.substr(6))
		var town := TownStores.town_of_cell(repo, state, cell)
		if town != "":
			out.append(_link(id, "town:" + town, int(RealmEconomy.line_of(repo, state, cell)["strategic"]), "gold"))
	elif id.begins_with("town:"):
		var town := id.substr(5)
		var catch := TownStores.catchment(repo, state)
		var cells: Array = catch.keys().filter(func(c: int) -> bool: return String(catch[c]) == town)
		cells.sort()
		for cell: int in cells:
			out.append(_link("manor:%d" % cell, id, int(RealmEconomy.line_of(repo, state, cell)["strategic"]), "gold"))
	return out


## town -> supply_line: what each line draws in the month (gold).
static func _dispatches(repo: DataRepository, state: GameState, id: String) -> Array:
	var rows := _supply_plan(repo, state)
	if id == "":
		var n := 0
		for row: Dictionary in rows:
			n += int(row["paid"])
		return [_type_link("town", "supply_line", n, "gold")]
	var out: Array = []
	for row: Dictionary in rows:
		var lid := "supply_line:" + String(row["code"])
		var tid := "town:" + String(row["town"])
		if id == lid or id == tid:
			out.append(_link(tid, lid, int(row["paid"]), "gold"))
	return out


## house -> town: what the crown bought from a house this month (gold, from
## the lines' month counters).
static func _sells_to(repo: DataRepository, state: GameState, id: String) -> Array:
	var by: Dictionary = {}
	for code: String in state.supply_lines:
		var ln: Dictionary = state.supply_lines[code]
		var bought: Dictionary = ln.get("m_bought", {})
		for house: String in bought:
			var key := "%s>%s" % [house, String(ln["town"])]
			by[key] = int(by.get(key, 0)) + TownStores.gold_of_units(repo, int(bought[house]))
	if id == "":
		var n := 0
		for k: String in by:
			n += int(by[k])
		return [_type_link("house", "town", n, "gold")] if n > 0 else []
	var out: Array = []
	var keys: Array = by.keys()
	keys.sort()
	for k: String in keys:
		var parts := k.split(">")
		var hid := "house:" + parts[0]
		var tid := "town:" + parts[1]
		if id == hid or id == tid:
			out.append(_link(hid, tid, int(by[k]), "gold"))
	return out
```

- `_supply`: drop the `inward` branch's use (the `supplies_in` link is retired); for `supplies_out` keep the code, it reads `delivered` / `claimed` from the new rows unchanged.
- `_instances_of_flow("supply_line")` and the `supply_lines` instance lister already iterate `_supply_plan` rows — unchanged; they now list only regiments with lines.
- `label_of("supply_line")`: also require `state.supply_lines.has(rest)` and read "Supply line from <town> to <regiment>".

`scripts/engine/ledger_cards.gd` `_head("supply_line")`:

```gdscript
		"supply_line":
			var line := SupplySystem.line_of(repo, state, rest)
			if String(line["town"]) == "":
				return ""
			var from := String((repo.burgs.get(String(line["town"]), {}) as Dictionary).get("label", line["town"]))
			@warning_ignore("integer_division")  # whole percent from per-mille
			return "from %s, %d km, %d%% lost on the way — %s" % [from, int(line["length_km"]),
				int(line["loss_permille"]) / 10, String(line["state"])]
```

`scripts/engine/war_folio.gd` `_supply`: the "In hand" row reads days: `"%s (%d days of %d)" % [WarRoom.group(supplies), ArmySystem.days_in_hand(supplies, use), ArmySystem.carry_of(repo, st)]`; the "Line" row: no line → `"no supply point"`; else `"%s from %s, %.1f×, %d km, %d%% lost"` with the state word (`line["state"]`); in garrison add `"; topped up in %s" % held`. Remove `depot_name` if nothing else calls it.

`scripts/engine/map_objects.gd` regiment card (the block at ~line 999): replace the supply-line stat with

```gdscript
		if state != null and state.regiments.has(code) and not naval:
			var line := SupplySystem.line_of(repo, state, code)
			var from := String((repo.burgs.get(String(line["town"]), {}) as Dictionary).get("label", ""))
			var held := String((repo.burgs.get(String(line["garrison_town"]), {}) as Dictionary).get("label", ""))
			var ln := SupplyLines.line(state, code)
			var text := "none"
			var tip := "No supply point — it eats what it carries%s" % ("" if held == "" else "; %s tops it up" % held)
			match String(line["state"]):
				SupplyLines.ORDERED:
					text = "ordered"
					tip = "A courier rides to %s with the supply warrant" % from
				SupplyLines.RIDING:
					var days := maxi(int(ln["ready_day"]) - state.absolute_day(), 0)
					text = "wagons %dd" % days
					tip = "The first wagons from %s arrive in %d day%s" % [from, days, "" if days == 1 else "s"]
				SupplyLines.FLOWING:
					@warning_ignore("integer_division")
					var fee := ArmySystem.day_bite(use * int(line["rate"]) / 1000, state.day) * int(line["length_km"]) \
						* int(repo.bal("supply_cart_milligold_per_unit_km")) / 1000
					text = "%s %.1f×" % [from, float(int(line["rate"])) / 1000.0]
					tip = "Supply point: %s · %.1f× · about %d gold a day · %d km, %d%% lost on the road" % [
						from, float(int(line["rate"])) / 1000.0, fee, int(line["length_km"]), int(line["loss_permille"]) / 10]
				SupplyLines.CUT:
					text = "cut"
					tip = "The road from %s is cut by %s" % [from, String((repo.kingdoms.get(String(ln["cut_by"]), {}) as Dictionary).get("label", ln["cut_by"]))]
			stats.append(_stat("army_supply_line", text, tip))
```

(`use` is the variable defined just above as `ArmySystem.supply_use(repo, r, state)`; move that line above this block.)

and the supplies stat:

```gdscript
		var days := ArmySystem.days_in_hand(int(st["supplies"]), use)
		var carry := ArmySystem.carry_of(repo, st)
		stats.append(_stat("army_supply", "%d / %d days" % [mini(days, 999), carry],
			"Supplies — %d days in hand; it carries %d days; under %d days morale falls every day" % [
				mini(days, 999), carry, int(repo.bal("army_supply_low_days"))]))
```

Town card (the `"kind": "burg"` builder at ~line 285): when `TownStores.is_realm_town(repo, state, code)`, append a stat with the existing strategic-goods key (reuse `manor_strategic`, so no new icon is needed):

```gdscript
	if state != null and TownStores.is_realm_town(repo, state, code):
		var st := TownStores.stock_of(state, code)
		var lines := state.supply_lines.keys().filter(func(k: String) -> bool:
			return String((state.supply_lines[k] as Dictionary)["town"]) == code)
		stats.append(_stat("manor_strategic", "%d stores" % (int(st["crown"]) + int(st["lord"]) + int(st["house"])),
			"Strategic stores — crown %d, lord %d, House stock %d (bought at +%d%%); %d supply line%s from here" % [
				int(st["crown"]), int(st["lord"]), int(st["house"]),
				int(repo.bal("supply_buy_markup_permille")) / 10, lines.size(), "" if lines.size() == 1 else "s"]))
```

(If the burg card has no `stats` array, add the line to its `fields` in the same `{key, text, tooltip}` form its other rows use.)

Update the old LEDGER tests: in `test_governed_flows.gd`, `test_ledger_supply.gd`, `test_ledger_governors.gd`, `tests/ledger3d/test_ledger_strands.gd`, every test that took `SupplySystem.plan(data, s)[0]` must first give the first land regiment a FLOWING line (`s.supply_lines[code] = SupplyLines._new_record(TownStores.realm_towns(data, s)[0], 1000, 1); s.supply_lines[code]["state"] = SupplyLines.FLOWING`) — put that in each file's `before_each`. Every `SupplySystem.settle_month(data, s)` call becomes `SupplyLines.settle_month(data, s)` and the assertions on gold debited to `strategic`/`lord_strategic` become assertions on `GameState.skims` and the report rows (`skimmed`, `claimed`). Delete assertions about `supplies_in`. In `test_war_folio.gd:154` replace the `stronghold_of` filter with `SupplyLines.line(state, c).is_empty()`.

- [ ] **Step 4: Run tests**

Run: `./run_tests.sh --fast 2>&1 | tail -20`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/supply_system.gd scripts/engine/ledger_resolvers.gd scripts/engine/ledger_cards.gd scripts/engine/war_folio.gd scripts/engine/map_objects.gd data/ledger_link_types.csv tests/engine/test_supply_ledger.gd tests/engine/test_governed_flows.gd tests/engine/test_ledger_supply.gd tests/engine/test_ledger_governors.gd tests/engine/test_war_folio.gd tests/ledger3d/test_ledger_strands.gd
git commit -m "feat(supply): the LEDGER's town-to-line chain, cards and folio read the lines"
```

---

### Task 10: The right-click menu — supply rows, pick mode, confirm

**Files:**
- Modify: `scripts/ui/army_order_menu.gd`
- Modify: `scripts/map3d/map3d_view.gd` (two plain properties the menu sets: `supply_pick: Dictionary`, `supply_preview: PackedVector2Array`)
- Test: `tests/ui/test_supply_menu.gd`; update `tests/ui/test_army_order_menu.gd` (`test_the_menu_offers_exactly_the_rows_in_the_table`)

**Interfaces:**
- Consumes: `SupplyLines.eligibility`, `SupplyLines.road_px`, `road_km`, `wagon_days`, `RATES`; `CourierSystem.eta_days`; `repo.army_supply_orders`, `repo.army_carry_loads`.
- Produces: menu ids `SUPPLY_ADD := 400`, `SUPPLY_WITHDRAW := 401`, `CARRY_BASE := 410` (+ index in `army_carry_loads`), `RATE_BASE := 420` (+ index in `RATES`); test seams `supply_picking() -> String`, `supply_town() -> String`; map properties `supply_pick` (burg → reason) and `supply_preview` (pack px) — `{}` / empty when not picking.

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest
## The supply rows of the regiment's menu (spec 2026-10-07-army-supply-lines §5.1–5.2),
## driven in the engine's real order: right click, row, click on the ground, rate.

class FakeMap extends Node:
	signal army_menu_requested(code: String, at: Vector2)
	signal ground_clicked(pack_px: Vector2, screen_px: Vector2)
	var aiming := false
	var aim_dest := Vector2(-1, -1)
	var supply_pick: Dictionary = {}
	var supply_preview := PackedVector2Array()

var _menu: ArmyOrderMenu
var _map: FakeMap

func before_each() -> void:
	Game.start_campaign(42)
	Game.set_clock_speed(0)
	_menu = ArmyOrderMenu.new()
	add_child_autofree(_menu)
	_map = FakeMap.new()
	add_child_autofree(_map)
	_menu.follow(_map)

func _land() -> String:
	for r: Dictionary in MapObjects.regiments_of(Game.data, Game.data.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""

func _row(label_key: String) -> int:
	var label := String(Game.data.army_supply_orders[label_key]["label"])
	for i in _menu.item_count:
		if _menu.get_item_text(i) == label:
			return _menu.get_item_id(i)
	return -1

func test_add_supply_point_lights_the_eligible_towns() -> void:
	var code := _land()
	_map.army_menu_requested.emit(code, Vector2(10, 10))
	var id := _row("add")
	assert_ne(id, -1, "the Add supply point row is offered")
	_menu.id_pressed.emit(id)
	assert_eq(_menu.supply_picking(), code)
	assert_eq(_map.supply_pick, SupplyLines.eligibility(Game.data, Game.state, code))

func test_clicking_a_lit_town_then_a_rate_sends_the_order() -> void:
	var code := _land()
	_map.army_menu_requested.emit(code, Vector2(10, 10))
	_menu.id_pressed.emit(_row("add"))
	var town := ""
	for t: String in _map.supply_pick:
		if String(_map.supply_pick[t]) == "":
			town = t
			break
	var b: Dictionary = Game.data.burgs[town]
	_map.ground_clicked.emit(Vector2(float(b["x"]), float(b["y"])), Vector2(20, 20))
	assert_eq(_menu.supply_town(), town)
	assert_true(_map.supply_preview.size() >= 2, "the road is drawn while the rate is asked")
	_menu.id_pressed.emit(ArmyOrderMenu.RATE_BASE + 2)   # 1.2x
	assert_eq(String(SupplyLines.line(Game.state, code).get("state", "")), SupplyLines.ORDERED)
	assert_eq(int(SupplyLines.line(Game.state, code)["rate"]), 1200)
	assert_eq(_map.supply_pick, {}, "pick mode ends")

func test_a_greyed_town_says_why_and_keeps_picking() -> void:
	var code := _land()
	_map.army_menu_requested.emit(code, Vector2(10, 10))
	_menu.id_pressed.emit(_row("add"))
	for t: String in _map.supply_pick:
		if String(_map.supply_pick[t]) != "":
			var b: Dictionary = Game.data.burgs[t]
			_map.ground_clicked.emit(Vector2(float(b["x"]), float(b["y"])), Vector2(20, 20))
			assert_eq(_menu.supply_town(), "")
			assert_eq(_menu.supply_picking(), code)
			return
	pending("every town is in reach on this pack")

func test_escape_leaves_pick_mode() -> void:
	_map.army_menu_requested.emit(_land(), Vector2(10, 10))
	_menu.id_pressed.emit(_row("add"))
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.pressed = true
	_menu._unhandled_input(ev)
	assert_eq(_menu.supply_picking(), "")
	assert_eq(_map.supply_pick, {})

func test_carry_rows_send_the_load_order() -> void:
	var code := _land()
	_map.army_menu_requested.emit(code, Vector2(10, 10))
	_menu.id_pressed.emit(ArmyOrderMenu.CARRY_BASE + 4)   # 30 days
	assert_eq(String(CourierSystem.pending_for(Game.state, code)["order"]["action_code"]), "SUPPLY_CARRY_SET")
```

In `tests/ui/test_army_order_menu.gd` change the row-count test to count only the march rows: `assert_eq(_menu.get_item_text(i), ...)` for `i < Game.data.army_orders.size()` and drop the `item_count ==` equality (the supply rows follow).

- [ ] **Step 2: Run it to verify it fails**

Run: `./run_tests.sh 2>&1 | grep -A3 test_supply_menu`
Expected: FAIL — `supply_picking` not found.

- [ ] **Step 3: Implement**

`scripts/map3d/map3d_view.gd`, beside `aim_dest`:

```gdscript
## The supply point being picked (ArmyOrderMenu sets both, spec
## 2026-10-07-army-supply-lines §5.2): every realm town -> "" when it may
## supply the regiment, else why not; and the chosen town's road while its
## rate is asked. {} / empty otherwise. Map3DSupplyLines draws them.
var supply_pick: Dictionary = {}:
	set(v):
		supply_pick = v
		if _loaded: _supply.redraw()
var supply_preview := PackedVector2Array():
	set(v):
		supply_preview = v
		if _loaded: _supply.redraw()
```

(`_supply` is Task 11's layer; until Task 11 lands, guard with `if _loaded and _supply != null`. Declare `var _supply: Map3DSupplyLines = null` in this task and construct it in Task 11.)

`scripts/ui/army_order_menu.gd` — constants:

```gdscript
## The supply rows (spec 2026-10-07-army-supply-lines §5.1): Add / Change
## supply point…, Withdraw supply point, Carry N days (CARRY_BASE + the
## row's index in data/army_carry_loads.csv), and the confirm's rates
## (RATE_BASE + the index in SupplyLines.RATES).
const SUPPLY_ADD := 400
const SUPPLY_WITHDRAW := 401
const CARRY_BASE := 410
const RATE_BASE := 420
```

state:

```gdscript
## The regiment whose supply point is being picked, "" when none; and the
## town clicked, whose rate the confirm asks.
var _supply_for := ""
var _supply_town := ""
```

In `_open_for`, after the march rows and before `if item_count == 0`:

```gdscript
	_add_supply_rows(code)
```

```gdscript
func _supply_row(key: String, id: int, why: String) -> void:
	var row: Dictionary = Game.data.army_supply_orders.get(key, {"label": key, "hint": ""})
	add_item(String(row["label"]), id)
	var i := get_item_index(id)
	set_item_disabled(i, why != "")
	set_item_tooltip(i, why if why != "" else String(row["hint"]))


## The regiment's supply rows: offered only for a land regiment of the realm.
func _add_supply_rows(code: String) -> void:
	var reg := ArmySystem.regiment(Game.data, code)
	if reg.is_empty() or String(reg.get("is_naval", "0")) == "1" \
			or String(reg["kingdom_code"]) != Game.data.resolve_realm("player_realm"):
		return
	add_separator()
	var has_line := not SupplyLines.line(Game.state, code).is_empty()
	_supply_row("change" if has_line else "add", SUPPLY_ADD, _paused_reason())
	if has_line:
		_supply_row("withdraw", SUPPLY_WITHDRAW, _refusal("SUPPLY_POINT_CLEAR", code))
	var carry := ArmySystem.carry_of(Game.data, Game.state.regiments.get(code, {}))
	var title := String((Game.data.army_supply_orders.get("carry", {}) as Dictionary).get("label", "Carry"))
	for i in Game.data.army_carry_loads.size():
		var row: Dictionary = Game.data.army_carry_loads[i]
		add_check_item("%s %s" % [title, String(row["label"])], CARRY_BASE + i)
		set_item_checked(get_item_index(CARRY_BASE + i), int(row["days"]) == carry)
```

`_refusal` builds `ActionRequest.make(action_code, {"regiment": code})` — that is enough for `SUPPLY_POINT_CLEAR`.

In `_on_chosen`, before the `match id:`:

```gdscript
	if id >= RATE_BASE and id < RATE_BASE + SupplyLines.RATES.size():
		_send_supply(int(SupplyLines.RATES[id - RATE_BASE]))
		return
	if id >= CARRY_BASE and id < CARRY_BASE + Game.data.army_carry_loads.size():
		if _code != "":
			_run(ActionRequest.make("SUPPLY_CARRY_SET", {"regiment": _code,
				"days": int(Game.data.army_carry_loads[id - CARRY_BASE]["days"])}))
		return
	if id == SUPPLY_ADD:
		if _code != "" and _paused_reason() == "":
			_start_supply_pick(_code)
		return
	if id == SUPPLY_WITHDRAW:
		if _code != "":
			_run(ActionRequest.make("SUPPLY_POINT_CLEAR", {"regiment": _code}))
		return
```

Pick mode:

```gdscript
func _start_supply_pick(code: String) -> void:
	_set_aim("")
	_supply_for = code
	_supply_town = ""
	_map_set("supply_pick", SupplyLines.eligibility(Game.data, Game.state, code))
	_map_set("supply_preview", PackedVector2Array())
	if _map != null and "aiming" in _map:
		_map.set("aiming", true)   # the next left click only says where it landed
	Game.publish_news("%s — click a lit town to supply it from." % _name_of(code))


func _end_supply_pick() -> void:
	if _supply_for == "":
		return
	_supply_for = ""
	_supply_town = ""
	_map_set("supply_pick", {})
	_map_set("supply_preview", PackedVector2Array())
	if _map != null and "aiming" in _map:
		_map.set("aiming", _aiming != "")


func _map_set(prop: String, value: Variant) -> void:
	if _map != null and prop in _map:
		_map.set(prop, value)


## A click while picking: the realm town under it (ArmySystem.town_at), lit
## or greyed. A lit one asks its rate; a greyed one says why in the news bar.
func _on_supply_ground(pack_px: Vector2, at: Vector2) -> void:
	var town := ArmySystem.town_at(Game.data, pack_px)
	var pick: Dictionary = _map.get("supply_pick") if _map != null and "supply_pick" in _map else {}
	if town == "" or not pick.has(town):
		Game.publish_news("Click a lit town of the realm.")
		return
	if String(pick[town]) != "":
		Game.publish_news(String(pick[town]))
		return
	_supply_town = town
	var route := SupplyLines.road_px(Game.data, Game.state, _supply_for, town)
	_map_set("supply_preview", route)
	_open_rates(town, route, at)


func _open_rates(town: String, route: PackedVector2Array, at: Vector2) -> void:
	clear()
	var km := SupplyLines.road_km(Game.data, route)
	var reg := ArmySystem.regiment(Game.data, _supply_for)
	var use := ArmySystem.supply_use(Game.data, reg, Game.state)
	var st := TownStores.stock_of(Game.state, town)
	var row: Dictionary = Game.data.army_supply_orders["confirm"]
	for i in SupplyLines.RATES.size():
		var rate := int(SupplyLines.RATES[i])
		@warning_ignore("integer_division")
		var per_day := use * rate / 1000 / Calendar.DAYS_PER_TICK
		@warning_ignore("integer_division")
		var fee := per_day * km * int(Game.data.bal("supply_cart_milligold_per_unit_km")) / 1000
		@warning_ignore("integer_division")
		var stock_days := (int(st["crown"]) + int(st["lord"]) + int(st["house"])) / maxi(per_day, 1)
		add_item(String(row["label"]).format({"rate": "%.1f" % (float(rate) / 1000.0), "fee": fee}), RATE_BASE + i)
		set_item_tooltip(get_item_index(RATE_BASE + i), String(row["hint"]).format({
			"town": String(Game.data.burgs[town]["label"]), "km": km,
			"loss": SupplySystem.loss_of(Game.data, km) / 10,
			"wagon_days": SupplyLines.wagon_days(Game.data, km), "stock_days": stock_days,
			"courier_days": CourierSystem.eta_days(Game.data, Game.state, CourierSystem.ORDINARY, _supply_for)}))
	_add_row("cancel", CANCEL, "")
	_pop(at)


func _send_supply(rate: int) -> void:
	if _supply_for == "" or _supply_town == "":
		return
	var req := ActionRequest.make("SUPPLY_POINT_SET", {"regiment": _supply_for, "town": _supply_town, "rate": rate})
	_end_supply_pick()
	_run(req)
```

`_on_ground` — first lines:

```gdscript
	if _supply_for != "" and _supply_town == "":
		var at := screen_px
		if at.x < 0.0:
			at = (_map as Control).get_local_mouse_position() if _map is Control else Vector2.ZERO
		_on_supply_ground(pack_px, at)
		return
```

`CANCEL` in `_on_chosen` — before `_withdraw(...)`: `if _supply_for != "": _end_supply_pick(); Game.publish_news("No supply point is chosen."); return`.

`_after_hide`: also `if _supply_town != "" and not visible: _end_supply_pick()` (a click away from the rates gives it up; deferred as the existing code is, because PopupMenu hides before `id_pressed`).

`_process`: when `Game.clock_speed > 0` and `_supply_for != ""`: `hide()` if visible, `_end_supply_pick()`, news "Time runs — the supply order is withdrawn.".

`_unhandled_input`: Escape while `_supply_for != ""` → `_end_supply_pick()`, news "The supply order is withdrawn.", set handled.

`_run`: extend the paused-clock courier news to the three supply actions (`req.action_code.begins_with("SUPPLY_")` → "A courier will ride for %s when time runs.").

Test seams:

```gdscript
func supply_picking() -> String:
	return _supply_for

func supply_town() -> String:
	return _supply_town
```

- [ ] **Step 4: Run tests**

Run: `./run_tests.sh 2>&1 | grep -A3 "test_supply_menu\|test_army_order_menu\|Failing"`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/army_order_menu.gd scripts/map3d/map3d_view.gd tests/ui/test_supply_menu.gd tests/ui/test_army_order_menu.gd
git commit -m "feat(supply): the regiment's supply rows, town pick mode and rate confirm"
```

---

### Task 11: The supply lines on the 3D map (and the pick rings), visual review

**Files:**
- Create: `scripts/map3d/map3d_supply_lines.gd`
- Create: `scenes/map3d/materials/lines/supply_line.tres`, `supply_pick.tres`, `supply_pick_off.tres`, `supply_preview.tres` (each a `ShaderMaterial` of `border_line.gdshader`, made in the editor via gdai MCP — never text-edited)
- Modify: `scripts/map3d/map3d_layer_lines.gd` (preload the four looks), `scripts/map3d/map3d_priority.gd` (`SUPPLY_LINES := 2`, below the borders, above the roads — confirm by eye), `scripts/map3d/map3d_view.gd` (construct, bind, step)
- Modify: `scripts/map3d/CLAUDE.md` (one bullet)
- Test: `tests/map3d/test_map3d_supply_lines.gd`

**Interfaces:**
- Consumes: `SupplySystem.route_px`, `SupplyLines.line`, `Map3DContext.state()`, `Map3DGeometry.pack_to_world`, `Map3DGeometry.resample`, `Map3DLayerLines.set_lines`, the view's `supply_pick` / `supply_preview`.
- Produces: `Map3DSupplyLines.lines_world(ctx) -> Array` (testable, no nodes), `redraw()`, `step() -> void` (redraws when the state's signature moves).

- [ ] **Step 1: Write the failing test**

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The faint supply lines (spec 2026-10-07-army-supply-lines §5.3): only FLOWING lines are drawn.

func test_only_flowing_lines_are_drawn() -> void:
	var repo := SuiteData.repo()
	var s := SuiteData.campaign(repo, 42)
	var codes: Array = s.regiments.keys()
	codes.sort()
	var code := String(codes[0])
	var town: String = TownStores.realm_towns(repo, s)[0]
	s.supply_lines[code] = SupplyLines._new_record(town, 1000, 1)
	var ctx := Map3DContext.new(repo, {"pack_w": 1, "pack_h": 1, "world_w": 1.0, "world_h": 1.0})
	ctx.state_fn = func() -> GameState: return s
	for st in [SupplyLines.ORDERED, SupplyLines.RIDING, SupplyLines.CUT]:
		s.supply_lines[code]["state"] = st
		assert_eq(Map3DSupplyLines.lines_world(ctx).size(), 0, st)
	s.supply_lines[code]["state"] = SupplyLines.FLOWING
	assert_eq(Map3DSupplyLines.lines_world(ctx).size(), 1)
```

(Build the `ctx` meta the way other `tests/map3d/` tests build a bare context — copy the helper they use, e.g. `Map3DPreview.context_for` or a fixture meta; the shape above is illustrative of the keys `pack_to_world` needs.)

- [ ] **Step 2: Run it to verify it fails**

Run: `./run_tests.sh 2>&1 | grep -A3 test_map3d_supply_lines`
Expected: FAIL — `Map3DSupplyLines` not declared.

- [ ] **Step 3: Implement**

`scripts/map3d/map3d_supply_lines.gd`:

```gdscript
class_name Map3DSupplyLines
extends RefCounted
## The supply lines on the 3D map (owner 2026-10-07: 淡淡的虚化的补给线, spec
## 2026-10-07-army-supply-lines §5.3): one faint ribbon per FLOWING line of
## the player's regiments, along the road from its town to the column; an
## ordered, riding or cut line is not drawn. While a supply point is picked,
## a ring round each realm town — lit when it may supply, greyed when not —
## and the chosen town's road dashed. Looks: scenes/map3d/materials/lines/
## supply_*.tres. Never the Game autoload.

var ctx: Map3DContext
var lines: Map3DLayerLines
var view: Node
var _sig := 0


func bind(p_ctx: Map3DContext, p_lines: Map3DLayerLines, p_view: Node) -> void:
	ctx = p_ctx
	lines = p_lines
	view = p_view


static func _world(ctx: Map3DContext, route: PackedVector2Array) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for p in route:
		pts.append(Map3DGeometry.pack_to_world(ctx.meta, p))
	return Map3DGeometry.resample(pts, ctx.line_step())


## Every FLOWING line's road in world XZ, code order.
static func lines_world(ctx: Map3DContext) -> Array:
	var out: Array = []
	var st := ctx.state()
	if st == null:
		return out
	var codes: Array = st.supply_lines.keys()
	codes.sort()
	for c in codes:
		if String((st.supply_lines[c] as Dictionary)["state"]) != SupplyLines.FLOWING:
			continue
		var route := SupplySystem.route_px(ctx.repo, st, String(c))
		if route.size() >= 2:
			out.append(_world(ctx, route))
	return out


static func _ring(ctx: Map3DContext, burg: Dictionary, radius_px: float) -> PackedVector2Array:
	var c := Vector2(float(burg["x"]), float(burg["y"]))
	var pts := PackedVector2Array()
	for i in 33:
		var a := TAU * float(i) / 32.0
		pts.append(Map3DGeometry.pack_to_world(ctx.meta, c + Vector2(cos(a), sin(a)) * radius_px))
	return pts


func redraw() -> void:
	if ctx == null or lines == null:
		return
	lines.set_lines("SupplyLines", lines_world(ctx), Map3DLayerLines.SUPPLY_LINE, Map3DPriority.SUPPLY_LINES)
	var pick: Dictionary = view.get("supply_pick") if view != null and "supply_pick" in view else {}
	var lit: Array = []
	var off: Array = []
	var r_px := float(ctx.repo.bal("supply_cut_reach_m")) / float(ArmySystem.metres_per_pack_px(ctx.repo))
	var towns: Array = pick.keys()
	towns.sort()
	for t: String in towns:
		(lit if String(pick[t]) == "" else off).append(_ring(ctx, ctx.repo.burgs[t], r_px))
	lines.set_lines("SupplyPick", lit, Map3DLayerLines.SUPPLY_PICK, Map3DPriority.SELECTION)
	lines.set_lines("SupplyPickOff", off, Map3DLayerLines.SUPPLY_PICK_OFF, Map3DPriority.SELECTION)
	var preview: PackedVector2Array = view.get("supply_preview") if view != null and "supply_preview" in view else PackedVector2Array()
	lines.set_lines("SupplyPreview", [_world(ctx, preview)] if preview.size() >= 2 else [],
		Map3DLayerLines.SUPPLY_PREVIEW, Map3DPriority.SELECTION)


## Redraw when the lines or the columns moved (the day turned, an order
## delivered); cheap otherwise.
func step() -> void:
	var st := ctx.state() if ctx != null else null
	if st == null:
		return
	var sig := hash([st.absolute_day(), st.supply_lines.hash()])
	if sig != _sig:
		_sig = sig
		redraw()
```

`map3d_layer_lines.gd`: preload the four looks as consts `SUPPLY_LINE`, `SUPPLY_PICK`, `SUPPLY_PICK_OFF`, `SUPPLY_PREVIEW`.

`map3d_priority.gd`: `## A flowing supply line (Map3DSupplyLines): faint, over the roads, under the borders.` `const SUPPLY_LINES := 2` — if 2 collides with `MANOR_EDGES`, keep both at 2 (ties are fine for see-through ribbons) or move to 1 and verify by eye in Step 5.

`map3d_view.gd`: `_supply = Map3DSupplyLines.new()`; in the bind section beside `_selection.bind(...)`: `_supply.bind(_ctx, _lines, self)`; in `_process` under `if _loaded:` add `_supply.step()`.

The four `.tres` looks — create in the editor (gdai MCP `add_resource` / `update_property`, per root `CLAUDE.md`): duplicate `scenes/map3d/materials/lines/hover.tres` as a start; `supply_line`: a warm parchment or the realm's own hue at low alpha (≈0.35), width ≈2 design px, soft edge high, no dash; `supply_preview`: same hue, dashed (`dash_px` 8, `gap_px` 6), alpha ≈0.7; `supply_pick`: a gold ring ≈2 px; `supply_pick_off`: grey ≈1.5 px, alpha ≈0.4. The values are starting points for the visual review, not rulings.

- [ ] **Step 4: Run tests**

Run: `./run_tests.sh 2>&1 | grep -A3 "test_map3d_supply_lines\|test_map3d_editor_owned_look\|Failing"`
Expected: PASS (the editor-owned-look guard included).

- [ ] **Step 5: Visual review**

Invoke the `visual-review` skill. Shoot a real window (`tools/snapshot_screen.gd --resolution 1920x1080`, never `--headless`) of: (a) two regiments with flowing lines at the opening zoom and one closer zoom; (b) pick mode with lit and greyed towns and a previewed road. Compare at least two variants of `supply_line.tres` (alpha / width / hue) side by side, crop, and have the independent critic judge "faint, blurred, readable, never confused with a road or a border" against `taste.md`. Record the chosen values in the `.tres` and a line in `.claude/skills/visual-review/taste.md` only if the owner rules on it.

- [ ] **Step 6: Commit**

```bash
git add scripts/map3d/map3d_supply_lines.gd scripts/map3d/map3d_layer_lines.gd scripts/map3d/map3d_priority.gd scripts/map3d/map3d_view.gd scripts/map3d/CLAUDE.md scenes/map3d/materials/lines/supply_*.tres tests/map3d/test_map3d_supply_lines.gd
git commit -m "feat(supply): faint supply lines and the pick rings on the 3D map"
```

---

### Task 12: Docs, the full suite, and the real game

**Files:**
- Modify: `scripts/engine/CLAUDE.md` (the "Supply, morale and the war workshop" section and the "Bars" / "Pace" lines: replace the monthly capital refill with the town stores, the lines, days and the carried load; keep within `test_claude_md_size.gd`'s cap)
- Modify: `docs/superpowers/specs/2026-10-07-army-supply-lines-design.md` (status → BUILT; record the plan's three implementer rulings: stores in supply units with the pool's gold rounded down once; reconcile takes a fall from the towns in proportion, not in burg-code order; the route preview shows on CLICK of a lit town, not on hover)
- Modify: `docs/superpowers/specs/2026-09-30-ledger-supply-design.md` (one line at its top: "§3's monthly capital resupply is replaced by 2026-10-07-army-supply-lines")

- [ ] **Step 1: Update the docs** as listed (rules as they stand now, no history, no CSV numbers).

- [ ] **Step 2: Run the full suite**

Run: `./run_tests.sh 2>&1 | tail -8`
Expected: all tests pass; "Errors 2" with the gdai binaries installed (0 without).

- [ ] **Step 3: Play it**

Launch the real game (`/Applications/Godot.app/Contents/MacOS/Godot --path .` from the worktree, after `cp -Rc` of the main checkout's `.godot` if it has none). Pause; right-click a regiment in the field; Add supply point…; check lit/greyed towns; click a lit town; pick 1.2×; run time until the courier and the wagons arrive; see the faint line; open the regiment card (supply point, days of carry) and the town card (stores); open the Missive board for the dispatch; let a month turn for the marshal's report; set Carry 30 and see the march slow. Note anything off and fix it in the owning task's files with a test.

- [ ] **Step 4: Commit**

```bash
git add scripts/engine/CLAUDE.md docs/superpowers/specs/2026-10-07-army-supply-lines-design.md docs/superpowers/specs/2026-09-30-ledger-supply-design.md
git commit -m "docs(supply): engine guidance and spec status for the supply lines"
```

- [ ] **Step 5: Land** — follow `superpowers:finishing-a-development-branch`; landing on main is a fast-forward from the worktree after merging main in (the shared checkout's rule in the owner's memory), only when the owner says so.
