# LEDGER M5 + M6 — Raw Materials, Artisans, Markets and Trade Routes — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Buildings that transform goods eat their inputs (own manor first, then the lord's stores, else they idle); a province's townsfolk speed its building works; the pack's markets and trade flows become the realm's trade, with a toll the steward governs and routes the crown can close.

**Architecture:** `IndustrySystem` (pure) plans each input building's feed from `data/building_inputs.csv`; `ManorEconomy.line_of` nets a building's input against its own manor's units (still the ONE rounding) and skips an idle building's output; the settlement buys the rest from the lord's pools or idles the building (`GameState.idle_buildings`). `MapManors.advance_works` accumulates progress in permille-days with an artisan bonus. `MarketSystem` (pure) reads the pack's `markets`, `market_goods` and the newly loaded `deals` into the realm's markets and trade routes (by buyer kingdom, live ownership), with a toll into the treasury governed through M3's `Governance` (flow `trade_route`).

**Tech Stack:** Godot 4.7, typed GDScript, GUT 9.4.

**Spec:** `docs/superpowers/specs/2026-09-30-ledger-industry-trade-design.md`. Runs AFTER `2026-09-30-ledger-m3-governors.md` on the same branch.

## Global Constraints

- Typed GDScript, no warnings; every number `balance.csv` or a `data/` table; no RNG; sorted iteration.
- **Invariant 11**: `ManorEconomy.line_of` stays the only rounding in the economy; `RealmEconomy.province_key` must include every state the new line depends on (`idle_buildings`), or the cache serves stale lines.
- **Invariant 8**: the new order `TRADE_ROUTE_SET` has its three catalogue rows.
- **Invariant 5**: no kingdom named in prose — a route's label is built from the live kingdom label (`repo.kingdoms[code]["label"]`), never a literal.
- **Invariant 6**: markets and routes follow LIVE ownership (`MapOwnership.owner_of`), never the pack's starting border.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Test command and suite as in the earlier LEDGER plans (known pre-existing failure `test_map3d_layers.gd::test_a_camera_move_refreshes_the_houses`).

## Review Focus

1. **A building idle for want of inputs** must also EAT nothing and MAKE nothing that month — its line neither nets inputs nor adds output. Pinned in Task 1.
2. **The cache** — idling or un-idling a building must change `RealmEconomy`'s province key. Pinned in Task 1 (`test_idling_a_building_moves_the_province_sums`).
3. **An old save** with works that carry only `start` — progress falls back to whole days elapsed, so no work jumps or stalls on load. Pinned in Task 2.
4. **A conquest** — a market whose centre town changes hands leaves the realm's markets and its deals change sides. Pinned in Task 3 (`test_markets_follow_live_ownership`).
5. **A closed route** pays no toll and is reopened by the same order. Pinned in Task 4.

---

### Task 1: Buildings eat — `IndustrySystem`, inputs netted in the line, idling

**Files:**
- Create: `data/building_inputs.csv`, `scripts/engine/industry_system.gd`
- Modify: `scripts/engine/data_repository.gd` (load inputs), `scripts/engine/game_state.gd` (`idle_buildings` + save), `scripts/engine/map_manors.gd` (`building_output_of` skips idle; `is_idle`), `scripts/engine/manor_economy.gd` (`line_of` nets inputs, returns `fed`), `scripts/engine/realm_economy.gd` (`province_key` includes idle), `scripts/engine/tick_engine.gd` (settle after the economy, before the workshops), `data/balance.csv`
- Test: `tests/engine/test_industry.gd`

**Interfaces:**
- Produces: `DataRepository.building_inputs: Dictionary` (building code → Array of `{good, units}`, file order); `GameState.idle_buildings: Dictionary` (cell String → Array of building codes idle THIS month); `MapManors.is_idle(state, cell, code) -> bool`; `ManorEconomy.line_of(...)` returns an extra `fed: Dictionary` (building code → `{good: own units eaten}`); `IndustrySystem.plan(repo, state) -> Array` of `{cell, code, good, need, own, buy, gold, pool}` (one row per input of every standing input building, cell then code then input order) and `settle_month(repo, state) -> Array` of tick lines (it also rewrites `state.idle_buildings`); `IndustrySystem.buildings(state) -> Array` of `[cell, code]` pairs.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/engine/test_industry.gd
extends GutTest
## Buildings eat (spec 2026-09-30-ledger-industry-trade-design, M5).

var data: DataRepository
var s: GameState
var cell := -1

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()
	cell = int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[0])

func after_each() -> void:
	RealmEconomy.forget()

func _smithy() -> void:
	assert_true(MapManors.build(data, s, cell, "smithy", "a test forge"))

func test_the_inputs_table() -> void:
	assert_eq(data.building_inputs["smithy"], [{"good": "iron", "units": 3}])
	assert_eq(data.building_inputs["armoury"].size(), 2)

func test_a_fed_smithy_makes_tools() -> void:
	_smithy()
	var line := ManorEconomy.line_of(data, s, cell, s.tick)
	assert_gt(int((line["units"] as Dictionary).get("tools", 0)), 0)
	assert_true((line["fed"] as Dictionary).has("smithy"))

func test_its_own_iron_feeds_it_first() -> void:
	s.manor_focus[str(cell)] = {"focus": "iron", "tick": -1000}
	RealmEconomy.forget()
	_smithy()
	var line := ManorEconomy.line_of(data, s, cell, s.tick)
	var own := int((line["fed"]["smithy"] as Dictionary).get("iron", 0))
	assert_gt(own, 0, "a manor working iron feeds its own forge")
	var rows := IndustrySystem.plan(data, s).filter(func(r: Dictionary) -> bool: return int(r["cell"]) == cell)
	assert_eq(int(rows[0]["own"]), own)
	assert_eq(int(rows[0]["buy"]), 3 - own)

func test_the_rest_is_bought_from_the_lords_stores() -> void:
	_smithy()
	s.metrics["lord_strategic"] = 1000.0
	var lines := IndustrySystem.settle_month(data, s)
	assert_eq(lines, [{"metric": "lord_strategic", "delta": -12,
		"reason": "the lord's workshops buy their inputs"}], "3 iron × 4 gold")
	assert_false(MapManors.is_idle(s, cell, "smithy"))

func test_unfed_it_idles_and_eats_and_makes_nothing() -> void:
	_smithy()
	s.metrics["lord_strategic"] = 0.0
	assert_eq(IndustrySystem.settle_month(data, s), [])
	assert_true(MapManors.is_idle(s, cell, "smithy"))
	RealmEconomy.forget()
	var line := ManorEconomy.line_of(data, s, cell, s.tick)
	assert_eq(int((line["units"] as Dictionary).get("tools", 0)), 0, "an idle forge makes nothing")
	assert_false((line["fed"] as Dictionary).has("smithy"), "and eats nothing")

func test_idling_a_building_moves_the_province_sums() -> void:
	_smithy()
	var home := MapManors.home_province(data, s)
	var before := RealmEconomy.province(data, s, home)
	s.idle_buildings[str(cell)] = ["smithy"]
	assert_ne(RealmEconomy.province_key(data, s, home), "", "the key is built")
	var after := RealmEconomy.province(data, s, home)
	assert_lt(int(after["strategic"]), int(before["strategic"]), "the cache saw the idle forge")

func test_idle_state_survives_a_save() -> void:
	s.idle_buildings[str(cell)] = ["smithy"]
	assert_eq(GameState.from_dict(s.to_dict()).idle_buildings, s.idle_buildings)
	var old := s.to_dict()
	old.erase("idle_buildings")
	assert_eq(GameState.from_dict(old).idle_buildings, {}, "an old save: nothing idle")
```
(Read `GameState.manor_focus`'s entry shape in `MapManors.set_focus` and use it in `test_its_own_iron_feeds_it_first` — the `{"focus", "tick"}` shape above is a guess; a tick far in the past makes the ramp complete. If the manor's land does not allow iron, pick a home-province manor whose `MapManors.land_allows` iron.)

- [ ] **Step 2: Run it** — Expected: FAIL.

- [ ] **Step 3: Data and loading**

`data/building_inputs.csv`:
```csv
building_code,good_code,units,notes
smithy,iron,3,"spec 2026-09-30-ledger-industry-trade-design M5: a forge eats iron"
armoury,tools,1,
armoury,iron,2,
tannery,cattle,2,
loom,sheep,2,
brewery,grain,4,
shipwright,wood,10,
shipwright,ropes,2,
```
`DataRepository`: `var building_inputs: Dictionary = {}`; in `_load`:
```gdscript
	if not _load_if_present(dir + "/building_inputs.csv", ["building_code", "good_code", "units"],
			func(r):
				var code := String(r["building_code"])
				if not building_inputs.has(code):
					building_inputs[code] = []
				building_inputs[code].append({"good": String(r["good_code"]), "units": int(r["units"])})):
		return false
```
`GameState`: `var idle_buildings: Dictionary = {}` (doc comment: "cell (String) -> building codes idle THIS month for want of inputs (M5); rewritten by every settlement"), saved with `duplicate(true)` and loaded with `d.get("idle_buildings", {})`.

- [ ] **Step 4: `MapManors`**

```gdscript
static func is_idle(state: GameState, cell_id: int, code: String) -> bool:
	return code in (state.idle_buildings.get(str(cell_id), []) as Array)
```
and in `building_output_of`, skip `if is_idle(state, cell_id, code): continue` inside its loop.

- [ ] **Step 5: `ManorEconomy.line_of`**

After the town goods are added to `units` and BEFORE the pool sums (`var strategic := 0`), insert:
```gdscript
	# Buildings eat (spec 2026-09-30-ledger-industry-trade-design, M5): each
	# standing, working input building is fed from this manor's own units
	# first; what it still needs the lord's stores sell it at the month's end
	# (IndustrySystem).
	var fed: Dictionary = {}
	for code: String in MapManors.buildings_of(state, cell):
		if MapManors.is_idle(state, cell, code) or not repo.building_inputs.has(code):
			continue
		var eaten: Dictionary = {}
		for inp: Dictionary in repo.building_inputs[code]:
			var good := String(inp["good"])
			var own := mini(int(units.get(good, 0)), int(inp["units"]))
			if own > 0:
				units[good] = int(units[good]) - own
				if int(units[good]) == 0:
					units.erase(good)
			eaten[good] = own
		fed[code] = eaten
```
and add `"fed": fed` to the returned Dictionary. (The pool sums below now count only what is left — the forge's own iron is no longer sold.)

- [ ] **Step 6: `RealmEconomy.province_key`** — inside its per-manor loop add:
```gdscript
		if state.idle_buildings.has(k):
			parts.append("i%s=%s" % [k, str(state.idle_buildings[k])])
```

- [ ] **Step 7: `IndustrySystem`**

```gdscript
# scripts/engine/industry_system.gd
class_name IndustrySystem
extends RefCounted
## Buildings eat (spec 2026-09-30-ledger-industry-trade-design, M5): every
## standing input building (data/building_inputs.csv) is fed from its own
## manor's units (ManorEconomy.line_of nets them); the rest it buys from the
## LORD's pool of each good at its price at the month's end — or, if the pool
## cannot pay, it stands IDLE the next month (GameState.idle_buildings).
## plan() is the one function the tick, the card and the LEDGER read.


static func buildings(state: GameState) -> Array:
	var out: Array = []
	var keys: Array = state.manor_buildings.keys()
	keys.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for key: String in keys:
		var codes: Array = (state.manor_buildings[key] as Array).duplicate()
		codes.sort()
		for code: String in codes:
			out.append([int(key), code])
	return out


static func _pool_metric(pool: String) -> String:
	return "lord_strategic" if pool == "strategic" else "lord_civil"


static func plan(repo: DataRepository, state: GameState) -> Array:
	var rows: Array = []
	for pair: Array in buildings(state):
		var cell := int(pair[0])
		var code := String(pair[1])
		if not repo.building_inputs.has(code):
			continue
		var fed: Dictionary = {}
		if not MapManors.is_idle(state, cell, code):
			fed = (ManorEconomy.line_of(repo, state, cell, state.tick)["fed"] as Dictionary).get(code, {})
		for inp: Dictionary in repo.building_inputs[code]:
			var good := String(inp["good"])
			var own := int(fed.get(good, 0))
			var buy := int(inp["units"]) - own
			var ge := repo.goods_economy_of(good)
			rows.append({"cell": cell, "code": code, "good": good, "need": int(inp["units"]), "own": own,
				"buy": buy, "gold": buy * int(ge["price_gold"]), "pool": String(ge["pool"])})
	return rows


## Buys next month's inputs building by building (cell, code order) from the
## lord's pools; a building its pools cannot pay for idles next month.
static func settle_month(repo: DataRepository, state: GameState) -> Array:
	var left := {"lord_strategic": maxi(int(state.metrics.get("lord_strategic", 0.0)), 0),
		"lord_civil": maxi(int(state.metrics.get("lord_civil", 0.0)), 0)}
	var spent := {"lord_strategic": 0, "lord_civil": 0}
	var idle: Dictionary = {}
	var by_building: Dictionary = {}
	for row: Dictionary in plan(repo, state):
		var key := "%d|%s" % [int(row["cell"]), row["code"]]
		if not by_building.has(key):
			by_building[key] = {"cell": int(row["cell"]), "code": String(row["code"]), "cost": {}}
		var cost: Dictionary = by_building[key]["cost"]
		var metric := _pool_metric(String(row["pool"]))
		cost[metric] = int(cost.get(metric, 0)) + int(row["gold"])
	for key: String in by_building:
		var b: Dictionary = by_building[key]
		var ok := true
		for metric: String in b["cost"]:
			if int(b["cost"][metric]) > int(left[metric]):
				ok = false
		if ok:
			for metric: String in b["cost"]:
				left[metric] = int(left[metric]) - int(b["cost"][metric])
				spent[metric] = int(spent[metric]) + int(b["cost"][metric])
		else:
			var k := str(int(b["cell"]))
			if not idle.has(k):
				idle[k] = []
			idle[k].append(String(b["code"]))
	state.idle_buildings = idle
	var lines: Array = []
	for metric in ["lord_strategic", "lord_civil"]:
		if int(spent[metric]) > 0:
			lines.append({"metric": metric, "delta": -int(spent[metric]),
				"reason": "the lord's workshops buy their inputs"})
	return lines
```
(`by_building` keeps insertion order, which is the plan's cell/code order — Godot Dictionaries preserve insertion order.)

- [ ] **Step 8: The tick** — in `TickEngine.advance`, after `_settle_economy` and BEFORE the workshops' block (Task 1 of the M1+M2 plan):
```gdscript
	# The lord's input buildings buy next month's inputs, or idle (M5).
	for l: Dictionary in IndustrySystem.settle_month(data, state):
		_apply(r, state.metrics, String(l["metric"]), float(int(l["delta"])), String(l["reason"]))
	RealmEconomy.forget()  # an idle building changes next month's lines
```
(If `RealmEconomy.forget()` inside the tick is too blunt for its day-bucket spreading, rely on the province key instead — the key already includes `idle_buildings` — and drop the call; read how the tick uses the cache first and choose, noting why.)

- [ ] **Step 9: Balance note** — no new balance key; the prices are `goods_economy.csv`'s.

- [ ] **Step 10: Run this test, `test_realm_economy.gd`, `test_manor_economy*.gd`, `test_tick_engine.gd`** — the economy tests may need a smithy-less fixture or updated sums where a fixture had a smithy; update with a comment naming M5.

- [ ] **Step 11: Commit** — `feat(industry): buildings eat their inputs — own manor first, then the lord's stores, else idle`

---

### Task 2: Artisans speed the works

**Files:**
- Modify: `scripts/engine/map_manors.gd` (`advance_works`, a pure `work_speed_permille`), `data/balance.csv`, `data/ledger_governance.csv` (a `works` row), `scripts/engine/map_objects.gd` (the manor card's works row)
- Test: `tests/engine/test_artisans.gd`

**Interfaces:**
- Produces: `MapManors.work_speed_permille(repo, state, province: String) -> int` (1000 + the artisans' bonus × the master of works' efficiency / 1000); works entries gain `done` (permille-days); a work finishes when `done >= days × 1000`.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/engine/test_artisans.gd
extends GutTest
## Artisans raise buildings faster (spec 2026-09-30-ledger-industry-trade-design, M5).

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	var mw: Character = s.characters.get(String(s.council.get("master_of_works", "")))
	if mw != null:
		mw.skills["sk_steward"] = 16
		mw.opinion = 50

func test_the_speed_grows_with_the_townsfolk_and_is_capped() -> void:
	var home := MapManors.home_province(data, s)
	var urban := RealmEconomy._figure(data, s, "economy.provinces.%s.urban_population" % home)
	var bonus := mini(int(data.bal("artisan_speed_cap_permille")),
		urban / int(data.bal("artisan_per_step")) * int(data.bal("artisan_step_permille")))
	assert_eq(MapManors.work_speed_permille(data, s, home), 1000 + bonus)

func test_a_work_finishes_sooner_with_artisans() -> void:
	var home := MapManors.home_province(data, s)
	var cell := int(MapManors.manors_of_province(data, home, s)[0])
	assert_true(MapManors.start_work(data, s, cell, "chapel", "a test chapel"))
	var days := int(data.manor_buildings["chapel"]["build_days"])
	var speed := MapManors.work_speed_permille(data, s, home)
	var need := int(ceil(float(days) * 1000.0 / float(speed)))
	for i in need - 1:
		s.day += 1
		MapManors.advance_works(data, s)
	assert_false("chapel" in MapManors.buildings_of(s, cell), "not yet")
	s.day += 1
	MapManors.advance_works(data, s)
	assert_true("chapel" in MapManors.buildings_of(s, cell), "done in %d days, not %d" % [need, days])

func test_an_old_work_keeps_its_days() -> void:
	var home := MapManors.home_province(data, s)
	var cell := int(MapManors.manors_of_province(data, home, s)[0])
	s.manor_works[str(cell)] = [{"building": "chapel", "start": s.absolute_day() - 10, "days": 40}]
	MapManors.advance_works(data, s)
	var w: Dictionary = s.manor_works[str(cell)][0]
	assert_gte(int(w["done"]), 10 * 1000, "the days already spent are counted")
```
(`s.day += 1` must advance `absolute_day()`; if the calendar needs `tick` rolled at 30, use the tick engine's own day step instead — read `GameState.absolute_day`.)

- [ ] **Step 2: Run it** — Expected: FAIL.

- [ ] **Step 3: Balance and governance rows**

```csv
artisan_per_step,2000,"LEDGER M5 (spec 2026-09-30-ledger-industry-trade-design): townsfolk of a province per step of faster building"
artisan_step_permille,50,LEDGER M5: per mille faster a work goes for each step of townsfolk
artisan_speed_cap_permille,500,LEDGER M5: the most the artisans can add
```
`data/ledger_governance.csv`: `works,master_of_works,sk_steward,850,8,20,600,1000,the building works,the artisans' bonus is scaled by his efficiency (M5)`

- [ ] **Step 4: `MapManors`**

```gdscript
## How fast a province's works go (spec 2026-09-30-ledger-industry-trade-design,
## M5): 1000 per mille a day, plus its townsfolk's bonus scaled by the master
## of works' efficiency (Governance flow "works").
static func work_speed_permille(repo: DataRepository, state: GameState, province: String) -> int:
	var urban := RealmEconomy._figure(repo, state, "economy.provinces.%s.urban_population" % province)
	@warning_ignore("integer_division")
	var bonus := mini(int(repo.bal("artisan_speed_cap_permille")),
		urban / maxi(int(repo.bal("artisan_per_step")), 1) * int(repo.bal("artisan_step_permille")))
	@warning_ignore("integer_division")
	return 1000 + bonus * int(Governance.factors(repo, state, "works")["efficiency"]) / 1000
```
In `advance_works`, replace the finish test with accumulated progress:
```gdscript
			var speed := work_speed_permille(repo, state, province_of(repo, int(key), state))
			var done := int(w.get("done", maxi(today - 1 - int(w["start"]), 0) * 1000)) + speed
			w["done"] = done
			if done >= int(w["days"]) * 1000:
				…the existing build/finish branch…
```
(compute `speed` once per key, outside the inner loop). The news bar's 30% / 70% milestones read a work's progress — find their reader (`grep news_build_milestone scripts`) and make it read `done / (days × 1000)` when `done` is present.

- [ ] **Step 5: The card** — the manor card's works row (find where `MapObjects.manor_card` states a work's days left) says "artisans: +N%" when the bonus > 0.

- [ ] **Step 6: Run it, `test_manor*.gd`, `test_news*.gd`** — Expected: PASS.

- [ ] **Step 7: Commit** — `feat(industry): a province's artisans raise its buildings faster`

---

### Task 3: Markets and trade routes — `MarketSystem`, the deals loaded

**Files:**
- Modify: `scripts/engine/data_repository.gd` (`load_map`: `deals`), `data/balance.csv`, `data/ledger_governance.csv` (a `trade_route` row), `scripts/engine/game_state.gd` (`closed_routes` + save)
- Create: `scripts/engine/market_system.gd`
- Test: `tests/engine/test_markets.gd`

**Interfaces:**
- Produces: `DataRepository.deals: Array` (rows `{seller_type, seller, buyer_type, buyer, good, units: float, price: float}`, file order, cleared on `load_map`); `GameState.closed_routes: Array` (kingdom codes); `MarketSystem.kingdom_of_party(repo, state, type, code) -> String`, `realm_markets(repo, state) -> Array[String]` (market ids, sorted as ints), `market_value(repo, market_id, pool) -> int` (Σ stock × price of its goods in that pool, whole gold), `basket_price_permille(repo, market_id, pool) -> int`, `routes(repo, state) -> Array` of `{kingdom, value, deals, open, toll, claimed, skimmed}` (sorted by kingdom code), `settle_month(repo, state) -> Array` of tick lines.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/engine/test_markets.gd
extends GutTest
## Markets and trade routes (spec 2026-09-30-ledger-industry-trade-design, M6).

var data: DataRepository
var s: GameState
var realm := ""

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	realm = data.resolve_realm("player_realm")
	var st: Character = s.characters[String(s.council["steward"])]
	st.skills["sk_steward"] = 16
	st.opinion = 50
	st.traits = []
	st.attributes["integrity"] = 50

func test_the_deals_are_loaded() -> void:
	assert_gt(data.deals.size(), 10000)
	assert_true(data.deals[0].has("units"))

func test_the_realms_markets_are_those_its_towns_centre() -> void:
	for id: String in MarketSystem.realm_markets(data, s):
		var burg := String(data.world_table("economy", "markets")[id]["center_burg"])
		assert_eq(MarketSystem.kingdom_of_party(data, s, "burg", burg), realm)

func test_markets_follow_live_ownership() -> void:
	var ids := MarketSystem.realm_markets(data, s)
	assert_gt(ids.size(), 0)
	var burg := String(data.world_table("economy", "markets")[ids[0]]["center_burg"])
	var prov := String(data.burgs[burg]["province_code"])
	var other := ""
	for k: String in data.kingdoms:
		if k != realm:
			other = k
			break
	MapOwnership.set_owner(data, s, prov, other, "a test conquest")
	assert_false(ids[0] in MarketSystem.realm_markets(data, s))

func test_a_route_sums_its_deals_by_buyer_kingdom() -> void:
	var routes := MarketSystem.routes(data, s)
	assert_gt(routes.size(), 0)
	var r: Dictionary = routes[0]
	assert_ne(String(r["kingdom"]), realm)
	var sum := 0.0
	for d: Dictionary in data.deals:
		if MarketSystem.kingdom_of_party(data, s, String(d["seller_type"]), String(d["seller"])) == realm \
				and MarketSystem.kingdom_of_party(data, s, String(d["buyer_type"]), String(d["buyer"])) == String(r["kingdom"]):
			sum += float(d["units"]) * float(d["price"])
	assert_eq(int(r["value"]), int(roundf(sum)))

func test_the_toll_and_closing() -> void:
	var r: Dictionary = MarketSystem.routes(data, s)[0]
	@warning_ignore("integer_division")
	assert_eq(int(r["toll"]), int(r["value"]) * int(data.bal("trade_toll_permille")) / 1000)
	var lines := MarketSystem.settle_month(data, s)
	assert_eq(String(lines[0]["metric"]), "treasury")
	s.closed_routes.append(String(r["kingdom"]))
	var closed: Dictionary = MarketSystem.routes(data, s)[0]
	assert_false(closed["open"])
	assert_eq(int(closed["toll"]), 0)

func test_tolls_are_a_modest_share_of_the_crowns_tax() -> void:
	var tolls := 0
	for r: Dictionary in MarketSystem.routes(data, s):
		tolls += int(r["toll"])
	var p := RealmEconomy.purses(data, s)
	var tax := int(p["lord"]["tax"]) + int(p["realm_share"]["tax"])
	gut.p("tolls %d a month against %d of tax" % [tolls, tax])
	assert_between(float(tolls) / float(maxi(tax, 1)), 0.05, 0.25)

func test_closed_routes_survive_a_save() -> void:
	s.closed_routes = ["x"]
	assert_eq(GameState.from_dict(s.to_dict()).closed_routes, ["x"])
```
(If `MapOwnership.set_owner`'s signature differs, read `map_ownership.gd` and follow it.)

- [ ] **Step 2: Run it** — Expected: FAIL.

- [ ] **Step 3: Load the deals**

In `DataRepository`: `var deals: Array = []`, cleared in `load_map` with the other pack tables, loaded after `production`:
```gdscript
	if not _load_if_present(dir + "/economy/deals.csv",
			["seller_type", "seller", "buyer_type", "buyer", "good_code", "units", "price"],
			func(r): deals.append({"seller_type": String(r["seller_type"]), "seller": String(r["seller"]),
				"buyer_type": String(r["buyer_type"]), "buyer": String(r["buyer"]),
				"good": String(r["good_code"]), "units": float(r["units"]), "price": float(r["price"])})):
		return false
```
(Update CLAUDE.md's note that deals are "deliberately NOT loaded" in Task 5.)

- [ ] **Step 4: Balance, governance, state**

```csv
trade_toll_permille,50,"LEDGER M6 (spec 2026-09-30-ledger-industry-trade-design): the crown's toll on each open trade route's monthly value; calibrated so tolls are 5-25% of the crown's tax (test_markets)"
trade_close_opinion,-6,LEDGER M6: the guildmaster's opinion when the crown closes a trade route
```
`ledger_governance.csv`: `trade_route,steward,sk_steward,850,8,20,600,1000,the trade tolls,the toll is scaled by his efficiency and skimmed by a venal steward (M6)`
`GameState`: `var closed_routes: Array = []` (doc: "kingdom codes whose trade route the crown has closed (M6)"), saved and loaded with `d.get("closed_routes", [])`.

- [ ] **Step 5: `MarketSystem`**

```gdscript
# scripts/engine/market_system.gd
class_name MarketSystem
extends RefCounted
## Markets and trade routes (spec 2026-09-30-ledger-industry-trade-design,
## M6): the pack's markets and trade flows (deals.csv) read through LIVE
## ownership. A trade route is every deal a seller in the realm makes with a
## buyer of one foreign kingdom, a month's units × price; the crown takes
## trade_toll_permille of an open route, scaled and skimmed by the steward
## (Governance flow "trade_route").


static func kingdom_of_party(repo: DataRepository, state: GameState, type: String, code: String) -> String:
	var burg := code
	if type == "market":
		burg = String((repo.world_table("economy", "markets").get(code, {}) as Dictionary).get("center_burg", ""))
	var prov := String((repo.burgs.get(burg, {}) as Dictionary).get("province_code", ""))
	return "" if prov == "" else MapOwnership.owner_of(repo, state, prov)


static func realm_markets(repo: DataRepository, state: GameState) -> Array:
	var realm := repo.resolve_realm("player_realm")
	var out: Array = []
	for id: String in repo.world_table("economy", "markets"):
		if kingdom_of_party(repo, state, "market", id) == realm:
			out.append(id)
	out.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	return out


static func market_value(repo: DataRepository, market_id: String, pool: String) -> int:
	var total := 0.0
	for row: Dictionary in repo.world_table("economy", "market_goods").values():
		if String(row["market_id"]) != market_id:
			continue
		if String(repo.goods_economy_of(String(row["good_code"]))["pool"]) == pool:
			total += float(row["stock"]) * float(row["price"])
	return int(roundf(total))


## The market's price for a pool's goods against their catalogue price, per
## mille (1000 = catalogue): stock-weighted over the goods it holds.
static func basket_price_permille(repo: DataRepository, market_id: String, pool: String) -> int:
	var paid := 0.0
	var list := 0.0
	for row: Dictionary in repo.world_table("economy", "market_goods").values():
		if String(row["market_id"]) != market_id:
			continue
		var ge := repo.goods_economy_of(String(row["good_code"]))
		if String(ge["pool"]) != pool:
			continue
		paid += float(row["stock"]) * float(row["price"])
		list += float(row["stock"]) * float(ge["price_gold"])
	return 1000 if list <= 0.0 else int(roundf(paid / list * 1000.0))


static func routes(repo: DataRepository, state: GameState) -> Array:
	var realm := repo.resolve_realm("player_realm")
	var by: Dictionary = {}
	for d: Dictionary in repo.deals:
		if kingdom_of_party(repo, state, String(d["seller_type"]), String(d["seller"])) != realm:
			continue
		var buyer := kingdom_of_party(repo, state, String(d["buyer_type"]), String(d["buyer"]))
		if buyer == "" or buyer == realm:
			continue
		if not by.has(buyer):
			by[buyer] = {"value": 0.0, "deals": 0}
		by[buyer]["value"] = float(by[buyer]["value"]) + float(d["units"]) * float(d["price"])
		by[buyer]["deals"] = int(by[buyer]["deals"]) + 1
	var g := Governance.factors(repo, state, "trade_route")
	var codes: Array = by.keys()
	codes.sort()
	var out: Array = []
	for k: String in codes:
		var value := int(roundf(float(by[k]["value"])))
		var open := not k in state.closed_routes
		@warning_ignore("integer_division")
		var claimed := value * int(repo.bal("trade_toll_permille")) / 1000 * int(g["efficiency"]) / 1000 if open else 0
		@warning_ignore("integer_division")
		var skimmed := claimed * int(g["skim"]) / 1000
		out.append({"kingdom": k, "value": value, "deals": int(by[k]["deals"]), "open": open,
			"claimed": claimed, "skimmed": skimmed, "toll": claimed - skimmed, "governor": String(g["governor"])})
	return out


static func settle_month(repo: DataRepository, state: GameState) -> Array:
	var lines: Array = []
	for r: Dictionary in routes(repo, state):
		if int(r["toll"]) > 0:
			var label := String((repo.kingdoms.get(String(r["kingdom"]), {}) as Dictionary).get("label", r["kingdom"]))
			lines.append({"metric": "treasury", "delta": int(r["toll"]), "reason": "tolls on the trade with " + label})
		if int(r["skimmed"]) > 0 and String(r["governor"]) != "":
			state.skims[String(r["governor"])] = int(state.skims.get(String(r["governor"]), 0)) + int(r["skimmed"])
	return lines
```
The toll test in Step 1 computes `value × toll / 1000` with an able governor (efficiency 1000); keep them consistent. `routes()` loops 10,815 deals: if the LEDGER's per-state-change snapshot makes it slow (measure one call; > 20 ms), cache the per-kingdom sums keyed by `MapOwnership`'s ownership signature (the border code already has one) — note the measured time in the report either way.

Tick: in `TickEngine.advance`, after the workshops block:
```gdscript
	# Trade tolls (M6).
	for l: Dictionary in MarketSystem.settle_month(data, state):
		_apply(r, state.metrics, String(l["metric"]), float(int(l["delta"])), String(l["reason"]))
```

- [ ] **Step 6: Calibrate** — if `test_tolls_are_a_modest_share_of_the_crowns_tax` fails, set `trade_toll_permille` so the printed share is ~0.12 (`round(50 × 0.12 / share)`), note the measured figures in the row, re-run.

- [ ] **Step 7: `GOODS_BUY` / `GOODS_SELL` at a market** — in `ActionSystem`, when `params` carries `market` (a realm market id; validate it is one), multiply the price by `basket_price_permille(market, pool) / 1000` instead of the flat spread; a test in this file: buying 100 gold of civil goods at a realm market costs `100 × basket / 1000` gold.

- [ ] **Step 8: Run it, `test_tick_engine.gd`, `test_world_tables.gd`, `test_deals_table.gd`** — Expected: PASS.

- [ ] **Step 9: Commit** — `feat(trade): markets and trade routes — tolls on the realm's trade, governed by the steward`

---

### Task 4: `TRADE_ROUTE_SET` and the LEDGER lights industry and trade

**Files:**
- Modify: catalogue CSVs (`TRADE_ROUTE_SET`), `scripts/engine/action_system.gd`, `data/ledger_object_types.csv`, `data/ledger_link_types.csv`, `data/ledger_actions.csv`, `scripts/engine/ledger_resolvers.gd`, `scripts/engine/audit_writer.gd` (`trade_route` facts), `tests/engine/test_ledger_snapshot.gd` (its planned example), the ontology spec §2/§3
- Test: `tests/engine/test_ledger_trade.gd`

**Interfaces:**
- Produces: order `TRADE_ROUTE_SET {kingdom, open: 0|1}`; live types `artisans` (instances `artisans:<province>`), `market` (`market:<id>`), `trade_route` (`trade_route:<kingdom>`); `raw_material` type retired; live links `builds` (artisans → building, flow = the bonus per mille), `consumes` (building → civil_goods / strategic_goods by the input's pool: two rows `consumes`, `consumes_strategic`), `trades` (market → civil_goods, flow its civil value) and `trades_strategic` (market → strategic_goods), `routes` (trade_route → gold, flow the toll, with the steward's claim like M3), `governs_trade` / `skims_trade` (character → trade_route).

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/engine/test_ledger_trade.gd
extends GutTest
## The LEDGER lights industry and trade (spec 2026-09-30-ledger-industry-trade-design).

var data: DataRepository
var s: GameState
var sys: ActionSystem

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	sys = ActionSystem.new(data)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func _link(snap: Dictionary, type: String) -> Dictionary:
	for l: Dictionary in snap["links"]:
		if String(l["type"]) == type:
			return l
	return {}

func test_the_ontology_stays_clean() -> void:
	assert_eq(Ledger.validate(data), [] as Array[String])

func test_every_charter_type_is_now_built_but_factions_and_sources() -> void:
	for r: Dictionary in data.ledger_types:
		if String(r["status"]) == "planned":
			assert_true(String(r["type_id"]) in ["faction", "source", "enemy_host"], String(r["type_id"]))

func test_a_route_is_its_toll() -> void:
	var r: Dictionary = MarketSystem.routes(data, s)[0]
	var ego := Ledger.snapshot(data, s, "economy", {"id": "trade_route:" + String(r["kingdom"])})
	assert_eq(_link(ego, "routes")["flow"], int(r["claimed"]))

func test_closing_and_reopening_a_route() -> void:
	var k := String(MarketSystem.routes(data, s)[0]["kingdom"])
	var close := ActionRequest.make("TRADE_ROUTE_SET", {"kingdom": k, "open": 0})
	assert_eq(sys.validate(close, s), "")
	sys.execute(close, s)
	assert_true(k in s.closed_routes)
	assert_ne(sys.validate(close, s), "", "already closed")
	sys.execute(ActionRequest.make("TRADE_ROUTE_SET", {"kingdom": k, "open": 1}), s)
	assert_false(k in s.closed_routes)

func test_a_forge_eats_on_the_ledger() -> void:
	var cell := int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[0])
	MapManors.build(data, s, cell, "smithy", "a test forge")
	var ego := Ledger.snapshot(data, s, "economy", {"id": "building:%d:smithy" % cell})
	assert_false(_link(ego, "consumes_strategic").is_empty(), "iron is a strategic good")

func test_the_route_offers_close_audit_and_give() -> void:
	var k := String(MarketSystem.routes(data, s)[0]["kingdom"])
	var codes: Array = Ledger.actions_for(data, "trade_route:" + k, s).map(
		func(a: Dictionary) -> String: return String(a["code"]))
	assert_has(codes, "TRADE_ROUTE_SET")
```

- [ ] **Step 2: Run it** — Expected: FAIL.

- [ ] **Step 3: The order** — catalogue rows:
```csv
TRADE_ROUTE_SET,economy,Open or close a trade route,none,1.0,none,0,0,,trade_route_set,2,yes,no,"params: kingdom, open (0|1). Closing it forgoes its toll and angers the merchants (spec 2026-09-30-ledger-industry-trade-design M6)."
```
`TRADE_ROUTE_SET,,5,5,0,0,0,the crown's hand on the trade` (signatures); `TRADE_ROUTE_SET,gold:-2:the harbour-masters' letters,1,the guildmaster's goodwill is charged by the order itself` (costs).
Validate: the kingdom has a route in `MarketSystem.routes`; `open` ∈ {0, 1}; refuse a no-op ("already open" / "already closed"). Execute: add/remove from `state.closed_routes`; on closing, `char_guildmaster_tessa`'s opinion `trade_close_opinion` with the reason "the crown closed the trade with <label>" when that character exists (find the guildmaster by the `roles.csv` row whose seat or role names the guild — do not hard-code the id if a data column identifies it; if none does, use the id and say so).

- [ ] **Step 4: Ontology data**

- `ledger_object_types.csv`: `artisans` → live, instances `artisans`; `market` → live, instances `markets`; `trade_route` → live, instances `trade_routes`; delete `raw_material` (a raw material is a GOOD — spec M5 "The ontology").
- `ledger_link_types.csv` (live, with resolvers of the same names unless given):
```csv
builds,artisans,building,raise,economy|all,live,builds,master_of_works,seat,,,
consumes,building,civil_goods,eats,economy|all,live,consumes,master_of_works,seat,,,
consumes_strategic,building,strategic_goods,eats,economy|war|all,live,consumes,master_of_works,seat,,,
trades,market,civil_goods,trades,economy|all,live,trades,steward,seat,,,
trades_strategic,market,strategic_goods,trades,economy|war|all,live,trades,steward,seat,,,
routes,trade_route,gold,pays tolls,economy|all,live,routes,steward,seat,,,
governs_trade,character,trade_route,governs,economy|court|all,live,governs,,,,,
skims_trade,character,trade_route,skims,intelligence|economy|all,live,skims,,,,,drawn only once an audit has caught him
```
(replacing the planned `builds`, `consumes`, `trades`, `routes` rows).
- `ledger_actions.csv`:
```csv
trade_route,TRADE_ROUTE_SET,Close the route,kingdom=@id|open=0,0
trade_route,TRADE_ROUTE_SET,Open the route,kingdom=@id|open=1,0
routes,LEDGER_AUDIT,Audit the trade tolls,flow=trade_route,0
routes,GOVERNOR_SET,Give it to,flow=trade_route|character=@council,0
market,GOODS_BUY,Buy civil goods here,pool=civil|gold=50|market=@id,0
market,GOODS_SELL,Sell civil goods here,pool=civil|gold=50|market=@id,0
```

- [ ] **Step 5: Resolvers** — following the M1+M2 and M3 patterns:
  - `builds`: type level `artisans → building`, flow = the home province's bonus; instance `artisans:<prov>` → each building standing or in work in that province's crown manors, flow = `work_speed_permille − 1000`.
  - `consumes`: per `IndustrySystem.plan` row whose pool matches the link's `to_type` (`civil_goods` ↔ civil, `strategic_goods` ↔ strategic): `building:<cell>:<code>` → the pool type, flow = `gold`; type level the sum.
  - `trades`: per realm market, `market:<id>` → the pool type, flow = `market_value`.
  - `routes`: per route, `trade_route:<k>` → `type:gold`, flow = `toll`, `claims` = `[{claimed, "<steward seat>: <name>"}]` (the treasury's own receipt is the truth: add `{toll, "the treasury's own count"}` as a second claim, so a skim splits the thread exactly like M3's supply line).
  - `governs` / `skims` with `to_type` `trade_route` → flow `trade_route` (extend `_instances_of_flow`).
  - `instances`: `artisans` (controlled provinces), `markets` (realm markets), `trade_routes` (routes, strain = value).
  - `label_of`: `artisans:<p>` "Artisans of <province>", `market:<id>` "Market of <centre town>", `trade_route:<k>` "Trade with <kingdom label>".
  - `AuditWriter.facts` for `trade_route`: one fact per route keyed `trade_route:<k>` with the true `toll`.
- Move `test_ledger_snapshot.gd`'s planned example to the planned `faction_governs` link (type `faction`), and mark the ontology spec's §2 / §3 rows ✅.

- [ ] **Step 6: Run every `test_ledger_*.gd` and this test** — Expected: PASS.

- [ ] **Step 7: Commit** — `feat(ledger): industry and trade light up — artisans, inputs, markets, routes`

---

### Task 5: Documents and the whole suite

- [ ] **Step 1: CLAUDE.md** — add after the governors paragraph, and change the pack-tables note that `deals.csv` is "deliberately NOT loaded" to say it is loaded as `DataRepository.deals` since M6:

```markdown
**Industry and trade** (LEDGER M5 + M6, 2026-09-30, spec `docs/superpowers/specs/2026-09-30-ledger-industry-trade-design.md`): a building that transforms goods EATS its inputs (`data/building_inputs.csv`) — `ManorEconomy.line_of` (still the one rounding) nets them against its own manor's units first; `IndustrySystem` buys the rest from the lord's pool of each good at the month's end, or the building stands IDLE next month (`GameState.idle_buildings`, part of `RealmEconomy.province_key`), making and eating nothing. A province's townsfolk speed its works (`MapManors.work_speed_permille`: `artisan_*`, scaled by the master of works through `Governance` flow `works`; works accumulate `done` permille-days). The pack's markets and `deals.csv` are the realm's trade through LIVE ownership (`MarketSystem`): a route per foreign buyer kingdom, `trade_toll_permille` of its value into the treasury, scaled and skimmed by the steward (flow `trade_route`), closed or reopened by `TRADE_ROUTE_SET` (the guildmaster's goodwill); `GOODS_BUY` / `GOODS_SELL` with a `market` trade at that market's basket price. Every charter type is now live on the LEDGER except factions (PRD Step 5), sources (intel P1) and enemy hosts (M4, the raid).
```

- [ ] **Step 2: Full suite; commit** — `docs(industry): CLAUDE.md records industry and trade`
