# WAR ROOM P3-A — the war economy on the sheet — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ink on the WAR ROOM's sheets where war goods are made (works by family), the 27 markets and the pack's trade weight on the roads, and name them in the hover slip, the fine print and the key.

**Architecture:** A pure engine class `WarEconomy` (`scripts/engine/war_economy.gd`) reads the pack's production, markets and deals once per pack and answers: the works, the markets and a market's food price, the trade flows summed per `RoadGraph` segment, a tier and the trade at a point. `WarSheetInk` adds the works / market glyphs to its towns and the trade segments to its strokes; `WarInkPainter` draws them; `WarFinePrint` adds a works note; `WarGround` adds three slip lines; `WarMarginKey` adds six legend entries. Read only — no state, no save change.

**Tech Stack:** Godot 4.7, typed GDScript, GUT (headless).

**Spec:** `docs/superpowers/specs/2026-10-07-war-room-p3-economy-layer-design.md` (§0 rulings 1–5, 9, 10; §1 — sub-project A only).

## Global Constraints

- Engine purity: `scripts/engine/` is `RefCounted`, no UI/LLM class, never `Game` (`test_engine_isolation.gd`); `scripts/war_room/` never reads `Game`.
- Determinism: sorted iteration, whole numbers where the slip quotes them, no RNG, no wall clock.
- Design values live in `data/*.csv`: every number below is a `balance.csv` key or a `war_works.csv` row.
- Authored prose never names a kingdom or a map pack; tests find their towns and markets from the pack's tables.
- Economic geography is public (ruling 2): works, markets and trade are inked on every sheet, foreign or not; only the live strategic gold of a HOME work is added in the slip.
- The look is drawn in ink by code like P2's marks (`WarMarkGlyph`); no new art, no `.tscn` change, the 3D map untouched.
- Tests take data from `tests/suite_data.gd` (`SuiteData.repo()`, `SuiteData.campaign(repo, seed)`); wait with `wait_process_frames`.
- `./run_tests.sh --fast` for the edit loop; the full `./run_tests.sh` before the last commit (0 errors in a worktree without the gdai binaries).

**Naming notes against the spec** (the plan's rulings, carried into the ledger):
- `balance.csv` holds numbers only, so `war_trade_tier_gold` "40|120|300" is three keys `war_trade_tier1_gold` / `2` / `3`.
- The glyph sizes follow the sheet's `war_ink_<k>_px` convention so the sheet AND the near-zoom patch pick them up through `WarRoomInk.INK_PX`: `war_ink_works_px`, `war_ink_market_px`, `war_ink_trade_px` (the spec's `war_works_glyph_px` / `war_market_glyph_px`).
- `war_works.csv` carries a `glyph` column beside `family` (the spec's "every family has a glyph"); a test holds one glyph per family.
- `WarEconomy` caches per repo instance and map (as `MapEconomy` and `MarketSystem.goods_of_market` do), so no `forget` hook is needed.
- `war_works_min_gold` first draft is 60, not 40: on beria 40 marks 119 towns, 60 marks 53 (34 arms, 9 horses, 9 naval, 1 ore) — about one a land sheet. Visual review sets it.

## Review Focus

- **A town that is a work, a market, a port and has a P2 mark at once** — its glyphs stand apart (works above the ring, market below, anchor and marks left, name right); pinned in Task 3 (`test_a_towns_glyphs_never_touch_its_ring_or_each_other`).
- **The near-zoom patch (a window)** draws the trade roads and glyphs at the sheet's own sizes in its own px; pinned in Task 3 (`test_a_window_keeps_the_trade_roads_in_its_own_px`).
- **A conquest** leaves the trade roads as they are but the slip's market line names the new holder; pinned in Task 5 (`test_a_market_won_reads_ours`).
- **The flows are built once per pack**, not per sheet or per hover — the road graph's trees are not run again on a second call; pinned in Task 2 (`test_the_flows_are_built_once_per_pack`).
- **Deals that do not run town-to-market** (market to market; a town that IS its market's centre; a town off the roads) neither crash nor draw; pinned in Task 2 (`test_a_market_to_market_deal_runs_between_their_centres`, `test_towns_off_the_roads_add_nothing`).

---

## File Structure

- Create `data/war_works.csv` — strategic good → family, glyph.
- Modify `data/balance.csv` — 7 keys.
- Modify `scripts/engine/data_repository.gd` — `var war_works`, its loader.
- Create `scripts/engine/war_economy.gd` — `WarEconomy`: works, markets, food price, trade flows / tier / segments / at.
- Modify `scripts/engine/war_marks.gd` — five new glyph names in `GLYPHS`.
- Modify `scripts/war_room/war_mark_glyph.gd` — draw them.
- Modify `scripts/war_room/war_sheet_ink.gd` — towns' `works` / `market` and their glyph spots, `trade` strokes, the grown label box, `town_marks`.
- Modify `scripts/war_room/war_ink_painter.gd` — draw trade weight and town glyphs.
- Modify `scripts/war_room/war_room_ink.gd` — `INK_PX` gains `trade`, `works`, `market`.
- Modify `scripts/war_room/war_fine_print.gd` — the works note.
- Modify `scripts/engine/war_ground.gd` — `trade`, `making`, `making_live`, `market` in the reading; `_economy_lines`.
- Modify `scripts/ui/war_margin_key.gd` — six legend entries and their marks.
- Tests: create `tests/engine/test_war_economy.gd`; modify `tests/engine/test_war_room_data.gd`, `tests/war_room/test_war_sheet_ink.gd`, `tests/war_room/test_war_fine_print.gd`, `tests/engine/test_war_ground.gd`, `tests/ui/test_war_margin_key.gd`.
- Docs (Task 7): `scripts/war_room/CLAUDE.md`, `scripts/engine/CLAUDE.md`, `data/CLAUDE.md`.

---

### Task 1: The works, the markets and a market's food price

**Files:**
- Create: `data/war_works.csv`, `scripts/engine/war_economy.gd`, `tests/engine/test_war_economy.gd`
- Modify: `data/balance.csv`, `scripts/engine/data_repository.gd` (beside the `war_marks` var and loader, ~lines 83–92 and ~668), `tests/engine/test_war_room_data.gd:14`

**Interfaces:**
- Consumes: `DataRepository.world_table("economy", "production" | "markets" | "goods")`, `repo.goods_economy_of(good) -> {pool, price_gold}`, `MarketSystem.goods_of_market(repo, id) -> Array` of `{good_code, stock, price}`.
- Produces:
  - `repo.war_works: Dictionary` — good → `{family: String, glyph: String}`.
  - `WarEconomy.works(repo) -> Dictionary` — burg → `{gold: int, family: String, glyph: String, goods: Array[{good: String, units: float, gold: int}]}`.
  - `WarEconomy.markets(repo) -> Array` — `[{id: String, burg: String, at: Vector2}]`, ids in numeric order.
  - `WarEconomy.market_of_town(repo, burg: String) -> String` — the market id centred on it, "" if none.
  - `WarEconomy.food_price_permille(repo, market_id: String) -> int`.
  - `WarEconomy.good_label(repo, good: String) -> String` — goods.csv label, the code if none.

- [ ] **Step 1: Write the data and the failing tests**

`data/war_works.csv`:

```csv
good_code,family,glyph,notes
arms,arms,anvil,"WAR ROOM P3-A ruling 3: a town making these is an arms works — weapons, cannon, powder and the metal and tools that make them"
artillery,arms,anvil,
gunpowder,arms,anvil,
bronze,arms,anvil,
tools,arms,anvil,
horses,horses,horseshoe,"mounts and their harness"
camels,horses,horseshoe,
elephants,horses,horseshoe,
harnesses,horses,horseshoe,
iron,ore,ingot,"ore and what smelts it"
copper,ore,ingot,
tin,ore,ingot,
saltpeter,ore,ingot,
coal,ore,ingot,
ships,naval,keel,"ships and their stores"
sails,naval,keel,
tar,naval,keel,
ropes,naval,keel,
hemp,naval,keel,
barrels,naval,keel,
```

Append to `data/balance.csv` (after the `war_hazard_dot_ratio` row):

```csv
war_works_min_gold,60,"WAR ROOM P3-A (spec 2026-10-07-war-room-p3 §0 ruling 3): a town is marked as a war works when its strategic goods (pack units x goods_economy price_gold) reach this many gold a month"
war_trade_tier1_gold,40,"WAR ROOM P3-A ruling 5: a road segment carrying this much trade gold a month is drawn one weight heavier"
war_trade_tier2_gold,120,WAR ROOM P3-A ruling 5: ... two weights heavier
war_trade_tier3_gold,300,WAR ROOM P3-A ruling 5: ... three weights heavier
war_ink_trade_px,3,"WAR ROOM P3-A §1.3: a trade road's extra width per tier over war_ink_road_px, sheet ink px"
war_ink_works_px,30,"WAR ROOM P3-A §1.3: a works glyph's height above its town ring, sheet ink px"
war_ink_market_px,30,"WAR ROOM P3-A §1.3: a market's scales below its town ring, sheet ink px"
```

In `tests/engine/test_war_room_data.gd:14`, add `"war_works_min_gold", "war_trade_tier1_gold", "war_trade_tier2_gold", "war_trade_tier3_gold", "war_ink_trade_px", "war_ink_works_px", "war_ink_market_px", ` right after `"war_hazard_dot_ratio", `.

`tests/engine/test_war_economy.gd`:

```gdscript
extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The war economy on the sheet (spec 2026-10-07-war-room-p3-economy-layer §1).

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_every_works_row_is_a_strategic_good_and_a_family_has_one_glyph() -> void:
	assert_gt(repo.war_works.size(), 0)
	var glyph_of: Dictionary = {}
	for good: String in repo.war_works:
		assert_eq(String(repo.goods_economy_of(good)["pool"]), "strategic", good)
		var row: Dictionary = repo.war_works[good]
		assert_true(WarMarkGlyph.knows(String(row["glyph"])), "%s's glyph" % good)
		if glyph_of.has(row["family"]):
			assert_eq(String(glyph_of[row["family"]]), String(row["glyph"]), "one glyph for %s" % row["family"])
		glyph_of[row["family"]] = row["glyph"]


func test_a_work_reaches_the_floor_and_takes_its_largest_listed_goods_family() -> void:
	var works := WarEconomy.works(repo)
	assert_gt(works.size(), 0)
	var floor_gold := int(repo.bal("war_works_min_gold"))
	for burg: String in works:
		var w: Dictionary = works[burg]
		assert_gte(int(w["gold"]), floor_gold, burg)
		var listed: Array = (w["goods"] as Array).filter(func(g: Dictionary) -> bool: return repo.war_works.has(String(g["good"])))
		assert_eq(String(w["family"]), String(repo.war_works[String(listed[0]["good"])]["family"]), burg)
		var golds: Array = (w["goods"] as Array).map(func(g: Dictionary) -> int: return int(g["gold"]))
		var sorted := golds.duplicate()
		sorted.sort()
		sorted.reverse()
		assert_eq(golds, sorted, "%s's goods largest first" % burg)


func test_no_floor_marks_every_town_with_a_listed_good_and_a_high_one_none() -> void:
	repo.balance["war_works_min_gold"] = 1000000.0
	assert_eq(WarEconomy.works(repo).size(), 0)
	var other := SuiteData.repo()
	other.balance["war_works_min_gold"] = 0.0
	var all := WarEconomy.works(other)
	assert_gt(all.size(), WarEconomy.works(SuiteData.repo()).size())


func test_a_town_with_no_listed_good_is_not_a_work() -> void:
	repo.war_works = {}
	assert_eq(WarEconomy.works(repo).size(), 0)


func test_the_markets_in_numeric_order_at_their_centre_towns() -> void:
	var ms := WarEconomy.markets(repo)
	assert_eq(ms.size(), repo.world_table("economy", "markets").size())
	for i in ms.size():
		var m: Dictionary = ms[i]
		var b: Dictionary = repo.burgs[String(m["burg"])]
		assert_eq(m["at"], Vector2(float(b["x"]), float(b["y"])))
		assert_eq(WarEconomy.market_of_town(repo, String(m["burg"])), String(m["id"]))
		if i > 0:
			assert_lt(int(ms[i - 1]["id"]), int(m["id"]))
	assert_eq(WarEconomy.market_of_town(repo, "no_such_town"), "")


func test_a_markets_food_price_by_hand() -> void:
	# market 1 on the default pack: stock x price of its food goods 533.64,
	# stock x catalogue 1131.93 (python over market_goods.csv, goods.csv tags,
	# goods_economy + defaults) -> 471 per mille
	var first := String(WarEconomy.markets(repo)[0]["id"])
	assert_eq(WarEconomy.food_price_permille(repo, first), 471)
	assert_eq(WarEconomy.food_price_permille(repo, "no_such_market"), 1000, "no food held: the catalogue")
```

- [ ] **Step 2: Run them to watch them fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_war_economy.gd -gexit`
Expected: FAIL — parse error, `WarEconomy` not declared (and `war_works` missing).

- [ ] **Step 3: Load the table**

In `scripts/engine/data_repository.gd`, beside `var war_mark_hazards`:

```gdscript
## data/war_works.csv: strategic good -> {family, glyph} — the goods that make
## a town a war works on the WAR ROOM's sheet, by family (spec 2026-10-07-war-room-p3 §1.1).
var war_works: Dictionary = {}
```

and after the `war_mark_hazards.csv` loader:

```gdscript
	if not _load_if_present(dir + "/war_works.csv", ["good_code", "family", "glyph"],
			func(r): war_works[String(r["good_code"])] = {"family": String(r["family"]), "glyph": String(r["glyph"])}):
		return false
```

- [ ] **Step 4: Write `WarEconomy` (works, markets, food price)**

`scripts/engine/war_economy.gd`:

```gdscript
class_name WarEconomy
extends RefCounted
## The war economy on the WAR ROOM's sheet (spec 2026-10-07-war-room-p3-economy-layer
## §1): the works — towns making war_works_min_gold of strategic goods a month,
## marked by the family of their largest listed good (data/war_works.csv) — the
## markets and their food price, and the pack's trade flows laid on the road
## network. Public, static facts of the pack (ruling 2); pure; cached per repo
## and map, as MapEconomy caches.

static var _cache: Dictionary = {}


static func _key(repo: DataRepository, what: String) -> String:
	return "%d:%s:%s" % [repo.get_instance_id(), repo.map_id, what]


## Every town at or over war_works_min_gold: {burg: {gold, family, glyph,
## goods: [{good, units, gold}]}}, goods largest gold first (ties on the code).
## A town none of whose strategic goods is listed in war_works is not a work.
static func works(repo: DataRepository) -> Dictionary:
	var key := _key(repo, "works")
	if _cache.has(key):
		return _cache[key]
	var by: Dictionary = {}   # burg -> {good: units}
	for row: Dictionary in repo.world_table("economy", "production").values():
		var good := String(row.get("good_code", ""))
		var burg := String(row.get("burg_code", ""))
		if not repo.burgs.has(burg) or String(repo.goods_economy_of(good).get("pool", "")) != "strategic":
			continue
		if not by.has(burg):
			by[burg] = {}
		by[burg][good] = float((by[burg] as Dictionary).get(good, 0.0)) + float(row.get("units", 0))
	var floor_gold := int(repo.bal("war_works_min_gold"))
	var out: Dictionary = {}
	var burgs: Array = by.keys()
	burgs.sort()
	for burg: String in burgs:
		var goods: Array = []
		var total := 0
		var codes: Array = (by[burg] as Dictionary).keys()
		codes.sort()
		for good: String in codes:
			var units := float(by[burg][good])
			var gold := roundi(units * float(int(repo.goods_economy_of(good)["price_gold"])))
			total += gold
			goods.append({"good": good, "units": units, "gold": gold})
		if total < floor_gold:
			continue
		goods.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return int(a["gold"]) > int(b["gold"]) or (int(a["gold"]) == int(b["gold"]) and String(a["good"]) < String(b["good"])))
		var top := ""
		for g: Dictionary in goods:
			if repo.war_works.has(String(g["good"])):
				top = String(g["good"])
				break
		if top == "":
			continue
		var row: Dictionary = repo.war_works[top]
		out[burg] = {"gold": total, "family": String(row["family"]), "glyph": String(row["glyph"]), "goods": goods}
	_cache[key] = out
	return out


## The pack's markets at their centre towns, ids in numeric order.
static func markets(repo: DataRepository) -> Array:
	var table: Dictionary = repo.world_table("economy", "markets")
	var ids: Array = table.keys()
	ids.sort_custom(func(a: Variant, b: Variant) -> bool: return int(a) < int(b))
	var out: Array = []
	for id: Variant in ids:
		var burg := String((table[id] as Dictionary).get("center_burg", ""))
		if not repo.burgs.has(burg):
			continue
		var b: Dictionary = repo.burgs[burg]
		out.append({"id": String(id), "burg": burg, "at": Vector2(float(b["x"]), float(b["y"]))})
	return out


## The market centred on this town, "" when none is.
static func market_of_town(repo: DataRepository, burg: String) -> String:
	for m: Dictionary in markets(repo):
		if String(m["burg"]) == burg:
			return String(m["id"])
	return ""


## The market's food price against the catalogue, per mille: stock-weighted
## over its food-tagged goods, the catalogue being the one
## MarketSystem.basket_price_permille weighs a pool against. 1000 when it holds no food.
static func food_price_permille(repo: DataRepository, market_id: String) -> int:
	var tags: Dictionary = repo.world_table("economy", "goods")
	var paid := 0.0
	var list := 0.0
	for row: Dictionary in MarketSystem.goods_of_market(repo, market_id):
		var good := String(row["good_code"])
		if not String((tags.get(good, {}) as Dictionary).get("tags", "")).split("|").has("food"):
			continue
		paid += float(row["stock"]) * float(row["price"])
		list += float(row["stock"]) * float(repo.goods_economy_of(good)["price_gold"])
	return 1000 if list <= 0.0 else roundi(paid / list * 1000.0)


## A good's name as goods.csv gives it; its code when the table has none.
static func good_label(repo: DataRepository, good: String) -> String:
	return String((repo.world_table("economy", "goods").get(good, {}) as Dictionary).get("label", good))
```

- [ ] **Step 5: Run the tests to watch them pass**

Run: the Step 2 command, then `-gtest=res://tests/engine/test_war_room_data.gd`.
Expected: PASS (6/6 in `test_war_economy.gd`). If `test_a_markets_food_price_by_hand` reads anything but 471, compare `MarketSystem.goods_of_market(repo, "1")` with `market_goods.csv`'s market 1 rows before touching the expected value.

- [ ] **Step 6: Commit**

```bash
git add data/war_works.csv data/balance.csv scripts/engine/data_repository.gd scripts/engine/war_economy.gd tests/engine/test_war_economy.gd tests/engine/test_war_room_data.gd
git commit -m "feat(war economy): the works by family, the markets and their food price"
```

---

### Task 2: The trade flows on the roads

**Files:**
- Modify: `scripts/engine/war_economy.gd`, `tests/engine/test_war_economy.gd`

**Interfaces:**
- Consumes: Task 1's `WarEconomy.markets`; `RoadGraph.of_pack(repo)` (`nodes: Array[Vector2i]` in metres, `shortest(id) -> {dist, prev}`, `nearest(at_m: Vector2i) -> int`, `route(tree, goal) -> Array`, `dijkstra_runs`); `repo.deals` (`{seller_type, seller, buyer_type, buyer, good, units: float, price: float}`); `ArmySystem.pack_to_metres(repo, Vector2) -> Vector2i`, `ArmySystem.metres_to_pack(repo, Vector2i) -> Vector2`; balance `courier_offroad_max_km`, `army_road_reach_m`.
- Produces:
  - `WarEconomy.trade_flows(repo) -> Dictionary` — `Vector2i(a, b)` (RoadGraph node ids, a < b) → gold a month (int).
  - `WarEconomy.trade_tier(repo, gold: int) -> int` — 0..3.
  - `WarEconomy.trade_segments(repo, rect: Rect2) -> Array` — `[{poly: PackedVector2Array (2 points, pack px), tier: int}]`, tier ≥ 1, an end inside `rect`.
  - `WarEconomy.trade_at(repo, at: Vector2) -> int` — gold on the nearest flow segment within `army_road_reach_m` of `at` (pack px), 0 if none.

- [ ] **Step 1: Write the failing tests** (append to `tests/engine/test_war_economy.gd`)

```gdscript
## A town reachable on the roads from the first market's centre, by another node.
func _reachable_town(m: Dictionary) -> String:
	var g := RoadGraph.of_pack(repo)
	var start := g.nearest(ArmySystem.pack_to_metres(repo, m["at"]))
	var tree := g.shortest(start)
	var reach := repo.bal("courier_offroad_max_km") * 1000.0
	var codes: Array = repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var b: Dictionary = repo.burgs[code]
		var at := ArmySystem.pack_to_metres(repo, Vector2(float(b["x"]), float(b["y"])))
		var node := g.nearest(at)
		if node != start and int(tree["dist"][node]) > 0 and Vector2(at).distance_to(Vector2(g.nodes[node])) <= reach:
			return code
	return ""


func test_a_pairs_gold_lies_on_every_segment_of_its_path_and_nowhere_else() -> void:
	var m: Dictionary = WarEconomy.markets(repo)[0]
	var town := _reachable_town(m)
	assert_ne(town, "")
	repo.deals = [{"seller_type": "market", "seller": String(m["id"]), "buyer_type": "burg", "buyer": town,
		"good": "grain", "units": 10.0, "price": 3.0}]
	var flows := WarEconomy.trade_flows(repo)
	var g := RoadGraph.of_pack(repo)
	var tree := g.shortest(g.nearest(ArmySystem.pack_to_metres(repo, m["at"])))
	var b: Dictionary = repo.burgs[town]
	var goal := g.nearest(ArmySystem.pack_to_metres(repo, Vector2(float(b["x"]), float(b["y"]))))
	assert_eq(flows.size(), g.route(tree, goal).size(), "one entry per segment of the path")
	for seg: Vector2i in flows:
		assert_eq(int(flows[seg]), 30)
		assert_lt(seg.x, seg.y)


func test_a_towns_sale_to_its_market_runs_the_same_road() -> void:
	var m: Dictionary = WarEconomy.markets(repo)[0]
	var town := _reachable_town(m)
	repo.deals = [{"seller_type": "burg", "seller": town, "buyer_type": "market", "buyer": String(m["id"]),
		"good": "grain", "units": 2.0, "price": 2.6}]
	var flows := WarEconomy.trade_flows(repo)
	assert_gt(flows.size(), 0)
	for seg: Vector2i in flows:
		assert_eq(int(flows[seg]), 5, "5.2 gold rounded once to whole gold")


func test_a_market_to_market_deal_runs_between_their_centres() -> void:
	var ms := WarEconomy.markets(repo)
	repo.deals = [{"seller_type": "market", "seller": String(ms[0]["id"]), "buyer_type": "market", "buyer": String(ms[1]["id"]),
		"good": "grain", "units": 10.0, "price": 1.0},
		{"seller_type": "market", "seller": String(ms[0]["id"]), "buyer_type": "burg", "buyer": String(ms[0]["burg"]),
		"good": "grain", "units": 10.0, "price": 1.0}]
	var flows := WarEconomy.trade_flows(repo)
	for seg: Vector2i in flows:
		assert_eq(int(flows[seg]), 10, "the market's own centre town adds nothing")


func test_towns_off_the_roads_add_nothing() -> void:
	repo.balance["courier_offroad_max_km"] = -1.0
	assert_eq(WarEconomy.trade_flows(repo).size(), 0)


func test_the_flows_are_built_once_per_pack() -> void:
	var a := WarEconomy.trade_flows(repo)
	var runs := RoadGraph.of_pack(repo).dijkstra_runs
	var b := WarEconomy.trade_flows(repo)
	assert_eq(RoadGraph.of_pack(repo).dijkstra_runs, runs)
	assert_eq(a, b)
	assert_eq(WarEconomy.trade_flows(SuiteData.repo()), a, "a fresh copy of the pack lays the same flows")
	for seg: Vector2i in a:
		assert_typeof(a[seg], TYPE_INT)


func test_tiers_by_the_thresholds() -> void:
	repo.balance["war_trade_tier1_gold"] = 40.0
	repo.balance["war_trade_tier2_gold"] = 120.0
	repo.balance["war_trade_tier3_gold"] = 300.0
	assert_eq(WarEconomy.trade_tier(repo, 39), 0)
	assert_eq(WarEconomy.trade_tier(repo, 40), 1)
	assert_eq(WarEconomy.trade_tier(repo, 299), 2)
	assert_eq(WarEconomy.trade_tier(repo, 300), 3)


func test_the_trade_at_a_point_on_and_off_the_road() -> void:
	var flows := WarEconomy.trade_flows(repo)
	var g := RoadGraph.of_pack(repo)
	var busiest := Vector2i(-1, -1)
	for seg: Vector2i in flows:
		if busiest.x < 0 or int(flows[seg]) > int(flows[busiest]):
			busiest = seg
	var mid_m := Vector2i((Vector2(g.nodes[busiest.x]) + Vector2(g.nodes[busiest.y])) * 0.5)
	assert_eq(WarEconomy.trade_at(repo, ArmySystem.metres_to_pack(repo, mid_m)), int(flows[busiest]))
	assert_eq(WarEconomy.trade_at(repo, Vector2(-100000, -100000)), 0)


func test_segments_are_the_drawn_tiers_touching_the_rect() -> void:
	var m: Dictionary = WarEconomy.markets(repo)[0]
	var rect := Rect2(m["at"] - Vector2(40, 40), Vector2(80, 80))
	var segs := WarEconomy.trade_segments(repo, rect)
	assert_gt(segs.size(), 0)
	for s: Dictionary in segs:
		assert_between(int(s["tier"]), 1, 3)
		var poly: PackedVector2Array = s["poly"]
		assert_eq(poly.size(), 2)
		assert_true(rect.has_point(poly[0]) or rect.has_point(poly[1]))
```

- [ ] **Step 2: Run them to watch them fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_war_economy.gd -gexit`
Expected: FAIL — `trade_flows` / `trade_tier` / `trade_at` / `trade_segments` not found.

- [ ] **Step 3: Write the flows** (append to `scripts/engine/war_economy.gd`)

```gdscript
## The pack's trade laid on the road network (ruling 5): {Vector2i(a, b) (RoadGraph
## node ids, a < b): gold a month}. Every deal has a market on one side; its
## month (units x price, the gold MarketSystem counts) is summed per market–
## town pair (a market buying from a market: its centre town), rounded once,
## and laid on every segment of the shortest road from the market's centre
## town — one tree per market, markets in numeric order. A town farther than
## courier_offroad_max_km from the network, or not reached, adds nothing.
static func trade_flows(repo: DataRepository) -> Dictionary:
	var key := _key(repo, "flows")
	if _cache.has(key):
		return _cache[key]
	var centre: Dictionary = {}
	for m: Dictionary in markets(repo):
		centre[String(m["id"])] = String(m["burg"])
	var pairs: Dictionary = {}   # market id -> {town: gold}
	for d: Dictionary in repo.deals:
		var market := ""
		var other := ""
		var other_type := ""
		if String(d["seller_type"]) == "market":
			market = String(d["seller"])
			other = String(d["buyer"])
			other_type = String(d["buyer_type"])
		elif String(d["buyer_type"]) == "market":
			market = String(d["buyer"])
			other = String(d["seller"])
			other_type = String(d["seller_type"])
		if not centre.has(market):
			continue
		var town := String(centre.get(other, "")) if other_type == "market" else other
		if not repo.burgs.has(town) or town == String(centre[market]):
			continue
		if not pairs.has(market):
			pairs[market] = {}
		pairs[market][town] = float((pairs[market] as Dictionary).get(town, 0.0)) + float(d["units"]) * float(d["price"])
	var g := RoadGraph.of_pack(repo)
	var reach := repo.bal("courier_offroad_max_km") * 1000.0
	var node_of: Dictionary = {}   # town -> node, -1 off the roads
	var out: Dictionary = {}
	var ids: Array = pairs.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a) < int(b))
	for id: String in ids:
		var start := _node_of(repo, g, String(centre[id]), reach, node_of)
		if start < 0:
			continue
		var tree := g.shortest(start)
		var towns: Array = (pairs[id] as Dictionary).keys()
		towns.sort()
		for town: String in towns:
			var gold := roundi(float(pairs[id][town]))
			var goal := _node_of(repo, g, town, reach, node_of)
			if gold <= 0 or goal < 0 or goal == start or int(tree["dist"][goal]) < 0:
				continue
			var at := goal
			while int(tree["prev"][at]) >= 0:
				var p := int(tree["prev"][at])
				var seg := Vector2i(mini(p, at), maxi(p, at))
				out[seg] = int(out.get(seg, 0)) + gold
				at = p
	_cache[key] = out
	return out


static func _node_of(repo: DataRepository, g: RoadGraph, town: String, reach: float, memo: Dictionary) -> int:
	if memo.has(town):
		return int(memo[town])
	var b: Dictionary = repo.burgs[town]
	var at := ArmySystem.pack_to_metres(repo, Vector2(float(b["x"]), float(b["y"])))
	var node := g.nearest(at)
	if node >= 0 and Vector2(at).distance_to(Vector2(g.nodes[node])) > reach:
		node = -1
	memo[town] = node
	return node


## A segment's weight on the sheet, 0..3 by war_trade_tier<N>_gold.
static func trade_tier(repo: DataRepository, gold: int) -> int:
	var tier := 0
	for n in [1, 2, 3]:
		if float(gold) >= repo.bal("war_trade_tier%d_gold" % n):
			tier = n
	return tier


## The drawn segments (tier >= 1) with an end inside `rect`, pack px, in the
## flows' own order.
static func trade_segments(repo: DataRepository, rect: Rect2) -> Array:
	var g := RoadGraph.of_pack(repo)
	var flows := trade_flows(repo)
	var out: Array = []
	for seg: Vector2i in flows:
		var tier := trade_tier(repo, int(flows[seg]))
		if tier <= 0:
			continue
		var a := ArmySystem.metres_to_pack(repo, g.nodes[seg.x])
		var b := ArmySystem.metres_to_pack(repo, g.nodes[seg.y])
		if rect.has_point(a) or rect.has_point(b):
			out.append({"poly": PackedVector2Array([a, b]), "tier": tier})
	return out


## The gold a month on the flow segment nearest `at` (pack px) within
## army_road_reach_m; 0 when no trade road is that near. The first of equals wins.
static func trade_at(repo: DataRepository, at: Vector2) -> int:
	var g := RoadGraph.of_pack(repo)
	var flows := trade_flows(repo)
	var m := Vector2(ArmySystem.pack_to_metres(repo, at))
	var reach := repo.bal("army_road_reach_m")
	var best := INF
	var gold := 0
	for seg: Vector2i in flows:
		var d := m.distance_to(Geometry2D.get_closest_point_to_segment(m, Vector2(g.nodes[seg.x]), Vector2(g.nodes[seg.y])))
		if d <= reach and d < best:
			best = d
			gold = int(flows[seg])
	return gold
```

- [ ] **Step 4: Run the tests to watch them pass**

Run: the Step 2 command.
Expected: PASS (14/14).

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/war_economy.gd tests/engine/test_war_economy.gd
git commit -m "feat(war economy): the pack's trade laid on the roads, by tier"
```

---

### Task 3: The sheet's ink — trade weight, works and market glyphs

**Files:**
- Modify: `scripts/engine/war_marks.gd:10-11` (`GLYPHS`), `scripts/war_room/war_mark_glyph.gd` (the `match`), `scripts/war_room/war_sheet_ink.gd` (`strokes` towns loop ~line 105, a new `trade` block after `bridges`/`fords`, `town_label_box` ~line 198, a new `town_marks`), `scripts/war_room/war_ink_painter.gd` (before the roads loop ~line 82; inside the towns loop ~line 97), `scripts/war_room/war_room_ink.gd:13-14` (`INK_PX`)
- Test: `tests/war_room/test_war_sheet_ink.gd`

**Interfaces:**
- Consumes: Task 1 `WarEconomy.works`, `WarEconomy.market_of_town`; Task 2 `WarEconomy.trade_segments`.
- Produces:
  - `WarMarks.GLYPHS` gains `"anvil", "horseshoe", "ingot", "keel", "scales"`.
  - `WarSheetInk.town_marks(repo, burg: String) -> Dictionary` — `{works: String (glyph or ""), market: bool}`.
  - A town stroke gains `works`, `market`, `works_at: Vector2`, `market_at: Vector2` (ink px; meaningful only when set).
  - `strokes()["trade"]: Array[{poly: PackedVector2Array (tex px), tier: int}]`.
  - `town_label_box` grows up / down for a town carrying `works` / `market`.
  - Painter widths gain `trade`, `works`, `market` (from `war_ink_<k>_px` via `INK_PX`).

- [ ] **Step 1: Write the failing tests** (append to `tests/war_room/test_war_sheet_ink.gd`)

```gdscript
## The sheet holding the first market's centre town (a work on the default pack).
func _market_sheet() -> Dictionary:
	var m: Dictionary = WarEconomy.markets(repo)[0]
	return WarSheets.series(repo)[WarSheets.sheet_of(repo, m["at"])]


func test_towns_carry_their_works_and_market() -> void:
	var sheet := _market_sheet()
	var ink := WarSheetInk.strokes(repo, state, sheet, int(repo.bal("war_sheet_texture_px")))
	var works := WarEconomy.works(repo)
	var seen_market := false
	for t: Dictionary in ink["towns"]:
		var code := String(t["code"])
		assert_eq(String(t["works"]), String((works.get(code, {}) as Dictionary).get("glyph", "")), code)
		assert_eq(bool(t["market"]), WarEconomy.market_of_town(repo, code) != "", code)
		seen_market = seen_market or bool(t["market"])
	assert_true(seen_market)


func test_a_towns_glyphs_never_touch_its_ring_or_each_other() -> void:
	var tex := int(repo.bal("war_sheet_texture_px"))
	var checked := 0
	for s: Dictionary in WarSheets.series(repo):
		for t: Dictionary in WarSheetInk.strokes(repo, state, s, tex)["towns"]:
			var ring := repo.bal("war_ink_town_px") * (1.0 + repo.bal("war_ink_town_tier_growth") * float(int(t["tier"])))
			if String(t["works"]) != "":
				assert_gte((t["works_at"] as Vector2).distance_to(t["at"]), ring + repo.bal("war_ink_works_px") * 0.5, String(t["label"]))
				checked += 1
			if bool(t["market"]):
				assert_gte((t["market_at"] as Vector2).distance_to(t["at"]), ring + repo.bal("war_ink_market_px") * 0.5, String(t["label"]))
			if String(t["works"]) != "" and bool(t["market"]):
				assert_gte((t["works_at"] as Vector2).distance_to(t["market_at"]),
					(repo.bal("war_ink_works_px") + repo.bal("war_ink_market_px")) * 0.5, String(t["label"]))
	assert_gt(checked, 0)


func test_a_town_box_grows_to_hold_its_glyphs() -> void:
	var plain := WarSheetInk.town_label_box(repo, {"at": Vector2(500, 500), "tier": 1, "label": "Testford"})
	var marked := WarSheetInk.town_label_box(repo, {"at": Vector2(500, 500), "tier": 1, "label": "Testford",
		"works": "anvil", "market": true})
	assert_lt(marked.position.y, plain.position.y, "room above for the works")
	assert_gt(marked.end.y, plain.end.y, "room below for the market")
	assert_eq(marked.position.x, plain.position.x)


func test_trade_roads_are_inked_by_tier_in_texture_px() -> void:
	var sheet := _market_sheet()
	var tex := int(repo.bal("war_sheet_texture_px"))
	var ink := WarSheetInk.strokes(repo, state, sheet, tex)
	assert_gt((ink["trade"] as Array).size(), 0)
	var r: Rect2 = sheet["rect"]
	var k := float(tex) / r.size.x
	# a road leaving the sheet is drawn to its edge: the sheet grown 2 %, as strokes() asks
	var segs := WarEconomy.trade_segments(repo, r.grow(r.size.x * 0.02))
	assert_eq((ink["trade"] as Array).size(), segs.size())
	for tr: Dictionary in ink["trade"]:
		assert_between(int(tr["tier"]), 1, 3)
		assert_eq((tr["poly"] as PackedVector2Array).size(), 2)
	var first: Dictionary = segs[0]
	assert_almost_eq((ink["trade"][0]["poly"] as PackedVector2Array)[0], ((first["poly"] as PackedVector2Array)[0] - r.position) * k, Vector2.ONE * 0.01)


func test_a_window_keeps_the_trade_roads_in_its_own_px() -> void:
	var sheet := _market_sheet()
	var m: Dictionary = WarEconomy.markets(repo)[0]
	var window := Rect2(m["at"] - Vector2(8, 8), Vector2(16, 16))
	var ink := WarSheetInk.strokes(repo, state, sheet, 2048, null, window)
	var k := 2048.0 / window.size.x
	for tr: Dictionary in ink["trade"]:
		var poly: PackedVector2Array = tr["poly"]
		var grown := Rect2(Vector2.ZERO, window.size * k).grow(window.size.x * k)
		assert_true(grown.has_point(poly[0]) or grown.has_point(poly[1]), "an end in or beside the window")
	for t: Dictionary in ink["towns"]:
		if String(t["code"]) == String(m["burg"]):
			assert_true(bool(t["market"]))
```

- [ ] **Step 2: Run them to watch them fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/war_room/test_war_sheet_ink.gd -gexit`
Expected: FAIL — towns have no `code` / `works` / `market`, no `trade` key, `town_label_box` ignores the glyphs.

- [ ] **Step 3: The glyphs**

`scripts/engine/war_marks.gd`:

```gdscript
const GLYPHS := ["crossed_swords", "galley", "pick", "tankard", "pennon", "broken_column",
	"tower_light", "dot", "anvil", "horseshoe", "ingot", "keel", "scales"]
```

`scripts/war_room/war_mark_glyph.gd`, new arms of the `match` before `_:`:

```gdscript
		"anvil":   # an arms works: the anvil's face and horn on its waist and foot
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.55, -s * 0.45), at + Vector2(s * 0.55, -s * 0.45),
				at + Vector2(s, -s * 0.3), at + Vector2(s * 0.55, -s * 0.15), at + Vector2(-s * 0.55, -s * 0.15)]), color)
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.25, -s * 0.15), at + Vector2(s * 0.25, -s * 0.15),
				at + Vector2(s * 0.15, s * 0.45), at + Vector2(-s * 0.15, s * 0.45)]), color)
			ci.draw_rect(Rect2(at + Vector2(-s * 0.6, s * 0.45), Vector2(s * 1.2, s * 0.3)), color, true)
		"horseshoe":   # horse works: a shoe, open below, its nail holes
			ci.draw_arc(at + Vector2(0, -s * 0.05), s * 0.7, PI * 0.95, PI * 2.05, 16, color, w * 2.2, true)
			ci.draw_line(at + Vector2(-s * 0.7, -s * 0.05), at + Vector2(-s * 0.6, s * 0.75), color, w * 2.2, true)
			ci.draw_line(at + Vector2(s * 0.7, -s * 0.05), at + Vector2(s * 0.6, s * 0.75), color, w * 2.2, true)
		"ingot":   # ore works: a cast bar, its top face lit
			ci.draw_colored_polygon(PackedVector2Array([at + Vector2(-s * 0.9, s * 0.45), at + Vector2(s * 0.9, s * 0.45),
				at + Vector2(s * 0.6, -s * 0.3), at + Vector2(-s * 0.6, -s * 0.3)]), color)
			ci.draw_line(at + Vector2(-s * 0.45, -s * 0.05), at + Vector2(s * 0.45, -s * 0.05), Color(color, color.a * 0.4), w, true)
		"keel":   # a shipyard: a hull's ribs on the stocks
			ci.draw_arc(at + Vector2(0, -s * 0.6), s * 0.95, PI * 0.2, PI * 0.8, 12, color, w * 1.5, true)
			for x in [-0.5, 0.0, 0.5]:
				ci.draw_line(at + Vector2(s * x, s * 0.25 - absf(x) * s * 0.35), at + Vector2(s * x * 1.25, -s * 0.55), color, w, true)
			ci.draw_line(at + Vector2(-s, s * 0.75), at + Vector2(s, s * 0.75), color, w, true)
		"scales":   # a market: the beam, its post and two pans
			ci.draw_line(at + Vector2(0, -s * 0.85), at + Vector2(0, s * 0.8), color, w, true)
			ci.draw_line(at + Vector2(-s * 0.85, -s * 0.6), at + Vector2(s * 0.85, -s * 0.6), color, w, true)
			ci.draw_line(at + Vector2(-s * 0.5, s * 0.8), at + Vector2(s * 0.5, s * 0.8), color, w, true)
			for side in [-1.0, 1.0]:
				ci.draw_line(at + Vector2(s * 0.85 * side, -s * 0.6), at + Vector2(s * 0.6 * side, s * 0.05), color, w * 0.7, true)
				ci.draw_line(at + Vector2(s * 0.85 * side, -s * 0.6), at + Vector2(s * 1.1 * side, s * 0.05), color, w * 0.7, true)
				ci.draw_arc(at + Vector2(s * 0.85 * side, s * 0.05), s * 0.3, 0.0, PI, 8, color, w, true)
```

(`test_war_mark_glyph.gd`'s `test_every_glyph_draws` covers them through `GLYPHS`.)

- [ ] **Step 4: The strokes**

In `scripts/war_room/war_sheet_ink.gd`, add after `crossings` / before `town_label_box`:

```gdscript
## A town's economic marks (spec 2026-10-07-war-room-p3 §1.3): the glyph of
## its works family ("" for none) and whether a market is centred on it.
static func town_marks(repo: DataRepository, burg: String) -> Dictionary:
	return {"works": String((WarEconomy.works(repo).get(burg, {}) as Dictionary).get("glyph", "")),
		"market": WarEconomy.market_of_town(repo, burg) != ""}
```

Replace the towns loop's append (the `(out["towns"] as Array).append({...})` line) with:

```gdscript
		var t := {"code": code, "at": (at - r.position) * k, "tier": tier, "label": String(b["label"]),
			"walls": String(b.get("features", "")).split("|").has("walls"), "port": String(b.get("is_port", "0")) == "1"}
		t.merge(town_marks(repo, code))
		# a works glyph stands above the ring, a market's scales below it
		var ring := repo.bal("war_ink_town_px") * px_k * (1.0 + repo.bal("war_ink_town_tier_growth") * float(tier))
		t["works_at"] = (t["at"] as Vector2) - Vector2(0.0, ring + repo.bal("war_ink_works_px") * px_k * 0.75)
		t["market_at"] = (t["at"] as Vector2) + Vector2(0.0, ring + repo.bal("war_ink_market_px") * px_k * 0.75)
		(out["towns"] as Array).append(t)
```

After `out["fords"] = crossings(...)`:

```gdscript
	# the pack's trade on the roads (spec 2026-10-07-war-room-p3 §1.3): a busy
	# road is drawn heavier, by tier
	out["trade"] = []
	for s: Dictionary in WarEconomy.trade_segments(repo, r.grow(r.size.x * 0.02)):
		(out["trade"] as Array).append({"poly": _to_tex(r, k, s["poly"]), "tier": int(s["tier"])})
```

`town_label_box`, replace the last two lines with:

```gdscript
	var h := maxf(r, label * 0.6)
	var up := h
	var down := h
	if String(t.get("works", "")) != "":
		up = maxf(up, r + repo.bal("war_ink_works_px") * px_k * 1.25)
	if bool(t.get("market", false)):
		down = maxf(down, r + repo.bal("war_ink_market_px") * px_k * 1.25)
	var at: Vector2 = t["at"]
	return Rect2(at.x - r, at.y - up, r + w, up + down)
```

- [ ] **Step 5: The painter and its widths**

`scripts/war_room/war_room_ink.gd`:

```gdscript
const INK_PX := ["road", "trail", "river", "coast", "border", "band", "seam", "town", "label", "dash", "gap",
	"wood", "manor", "manor_label", "manor_dash", "manor_gap", "river_label", "bridge", "trade", "works", "market"]
```

`scripts/war_room/war_ink_painter.gd`, just before `for poly: PackedVector2Array in ink["roads"]:`:

```gdscript
	for tr: Dictionary in ink.get("trade", []):   # a trade road weighs more, by tier (spec P3 §1.3)
		draw_polyline(tr["poly"], c_ink, float(px["road"]) + float(px.get("trade", 0.0)) * float(int(tr["tier"])), true)
```

Inside the towns loop, right after the `draw_string(... t["label"] ...)` call:

```gdscript
		if String(t.get("works", "")) != "":
			WarMarkGlyph.draw(self, String(t["works"]), t["works_at"], float(px.get("works", px["town"])), c_ink)
		if bool(t.get("market", false)):
			WarMarkGlyph.draw(self, "scales", t["market_at"], float(px.get("market", px["town"])), c_ink)
```

- [ ] **Step 6: Run the tests to watch them pass**

Run: the Step 2 command, then `-gtest=res://tests/war_room/test_war_mark_glyph.gd` and `-gtest=res://tests/engine/test_war_marks.gd`.
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/engine/war_marks.gd scripts/war_room/war_mark_glyph.gd scripts/war_room/war_sheet_ink.gd scripts/war_room/war_ink_painter.gd scripts/war_room/war_room_ink.gd tests/war_room/test_war_sheet_ink.gd
git commit -m "feat(war room): trade roads weigh more; works and markets marked at their towns"
```

---

### Task 4: The fine print's works note

**Files:**
- Modify: `scripts/war_room/war_fine_print.gd` (`strokes`, the towns loop ~lines 30–46; a new `works_note`)
- Test: `tests/war_room/test_war_fine_print.gd`

**Interfaces:**
- Consumes: Task 1 `WarEconomy.works`, `WarEconomy.good_label`; Task 3 `WarSheetInk.town_marks`, `town_label_box` (grown).
- Produces: `WarFinePrint.works_note(repo, w: Dictionary) -> String` — "works: artillery · bronze" (its two largest goods, lower case).

- [ ] **Step 1: Write the failing test**

```gdscript
func test_a_works_town_says_what_it_makes_under_its_note() -> void:
	var works := WarEconomy.works(repo)
	var code := ""
	var keys: Array = works.keys()
	keys.sort()
	code = String(keys[0])
	var w: Dictionary = works[code]
	var expected := "works: %s · %s" % [WarEconomy.good_label(repo, String(w["goods"][0]["good"])).to_lower(),
		WarEconomy.good_label(repo, String(w["goods"][1]["good"])).to_lower()] if (w["goods"] as Array).size() > 1 \
		else "works: %s" % WarEconomy.good_label(repo, String(w["goods"][0]["good"])).to_lower()
	assert_eq(WarFinePrint.works_note(repo, w), expected)
	var b: Dictionary = repo.burgs[code]
	var sheet: Dictionary = WarSheets.series(repo)[WarSheets.sheet_of(repo, Vector2(float(b["x"]), float(b["y"])))]
	var fine := WarFinePrint.strokes(repo, state, sheet, int(repo.bal("war_sheet_texture_px")), null)
	var texts: Array = (fine["notes"] as Array).map(func(n: Dictionary) -> String: return String(n["text"]))
	var works_here := 0
	for c: String in works:
		var wb: Dictionary = repo.burgs[c]
		if (sheet["rect"] as Rect2).has_point(Vector2(float(wb["x"]), float(wb["y"]))):
			works_here += 1
	assert_gt(texts.filter(func(t: String) -> bool: return t.begins_with("works: ")).size(), 0, "of %d works here" % works_here)
```

- [ ] **Step 2: Run it to watch it fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/war_room/test_war_fine_print.gd -gexit`
Expected: FAIL — `works_note` not found.

- [ ] **Step 3: Write it**

In `scripts/war_room/war_fine_print.gd`, after `town_note`:

```gdscript
## "works: artillery · bronze" — a works town's two largest strategic goods
## (spec 2026-10-07-war-room-p3 §1.3).
static func works_note(repo: DataRepository, w: Dictionary) -> String:
	var names: Array[String] = []
	for g: Dictionary in (w["goods"] as Array).slice(0, 2):
		names.append(WarEconomy.good_label(repo, String(g["good"])).to_lower())
	return "works: " + " · ".join(names)
```

In `strokes`, replace the towns loop body from `var box := ...` to the end of the loop with:

```gdscript
		var t := {"at": (at - r.position) * k, "tier": tier, "label": String(b["label"])}
		var plain := WarSheetInk.town_label_box(repo, t)
		t.merge(WarSheetInk.town_marks(repo, code))
		var box := WarSheetInk.town_label_box(repo, t)
		# under the name (and under a market's scales), left-aligned with the name
		var pos := Vector2(plain.position.x + plain.size.y, box.end.y + note_px * 0.9)
		for text: String in [town_note(b), works_note(repo, WarEconomy.works(repo)[code]) if WarEconomy.works(repo).has(code) else ""]:
			if text == "":
				continue
			var nb := Rect2(pos - Vector2(0, note_px), Vector2(float(text.length()) * note_px * char_w, note_px * 1.2))
			if _clear(nb, taken):
				taken.append(nb)
				(out["notes"] as Array).append({"at": pos, "text": text})
			pos.y += note_px * 1.25
```

Also replace the opening `for t: Dictionary in ink["towns"]: taken.append(WarSheetInk.town_label_box(repo, t))` — unchanged: the ink's towns now carry `works` / `market`, so their boxes already hold the glyphs.

The existing `test_a_town_note_says_size_works_souls_and_height` asserts every note is a town note; extend its loop to accept the works notes:

```gdscript
	for t: String in notes:
		assert_true(expected.has(t) or t.begins_with("works: "), t)
```

- [ ] **Step 4: Run the file to watch it pass**

Run: the Step 2 command.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add scripts/war_room/war_fine_print.gd tests/war_room/test_war_fine_print.gd
git commit -m "feat(war room): the fine print says what a works makes"
```

---

### Task 5: The slip — trade, works, market

**Files:**
- Modify: `scripts/engine/war_ground.gd` (`reading` ~lines 26–45; `lines` ~lines 77–110; a new `_economy_lines`)
- Test: `tests/engine/test_war_ground.gd`

**Interfaces:**
- Consumes: Task 1 `WarEconomy.works`, `market_of_town`, `food_price_permille`, `good_label`; Task 2 `WarEconomy.trade_at`; `ManorEconomy.line_of(repo, state, cell, tick) -> {strategic: int, …}`; `MapEconomy.burg_cells(repo) -> {burg: cell}`; `MarketSystem.kingdom_of_party(repo, state, "market", id) -> String`.
- Produces: the reading gains `trade: int`, `making: Dictionary` (a `works` entry or `{}`), `making_live: int` (−1 abroad), `market: Dictionary` (`{id, label, holder, food_permille}` or `{}`); the slip lines "Trade: about N gold a month passes", "Works: artillery 8, bronze 5 (N gold a month)" + " (this month: N)" at home, "Market of X (ours | Kingdom) — food at ×0.47".

- [ ] **Step 1: Write the failing tests** (append to `tests/engine/test_war_ground.gd`)

```gdscript
func _texts(r: Dictionary) -> Array:
	return WarGround.lines(repo, r).map(func(l: Dictionary) -> String: return String(l["text"]))


func _town_point(code: String) -> Vector2:
	var b: Dictionary = repo.burgs[code]
	return Vector2(float(b["x"]), float(b["y"]))


func test_a_road_carrying_trade_names_it() -> void:
	var flows := WarEconomy.trade_flows(repo)
	var g := RoadGraph.of_pack(repo)
	var busiest := Vector2i(-1, -1)
	for seg: Vector2i in flows:
		if busiest.x < 0 or int(flows[seg]) > int(flows[busiest]):
			busiest = seg
	var at := ArmySystem.metres_to_pack(repo, Vector2i((Vector2(g.nodes[busiest.x]) + Vector2(g.nodes[busiest.y])) * 0.5))
	var r := WarGround.reading(repo, state, at, "")
	assert_eq(int(r["trade"]), WarEconomy.trade_at(repo, at))
	assert_true(_texts(r).any(func(t: String) -> bool: return t == "Trade: about %s gold a month passes" % Intel.num(int(r["trade"]))))


func test_a_work_names_its_goods_and_at_home_its_month() -> void:
	var realm := repo.resolve_realm("player_realm")
	var home := ""
	var abroad := ""
	var codes: Array = WarEconomy.works(repo).keys()
	codes.sort()
	for code: String in codes:
		var mine := MapOwnership.owner_of(repo, state, String(repo.burgs[code]["province_code"])) == realm
		if mine and home == "":
			home = code
		elif not mine and abroad == "":
			abroad = code
	assert_ne(abroad, "")
	var ra := WarGround.reading(repo, state, _town_point(abroad), "")
	var line_a: Array = _texts(ra).filter(func(t: String) -> bool: return t.begins_with("Works: "))
	assert_eq(line_a.size(), 1)
	assert_false(String(line_a[0]).contains("this month"), "a foreign works' month is not known")
	assert_string_contains(String(line_a[0]), "(%s gold a month)" % Intel.num(int(WarEconomy.works(repo)[abroad]["gold"])))
	if home != "":
		var rh := WarGround.reading(repo, state, _town_point(home), "")
		assert_true(_texts(rh).any(func(t: String) -> bool: return t.begins_with("Works: ") and t.contains("(this month: ")))


func test_a_market_town_names_its_market_and_food_price() -> void:
	var m: Dictionary = WarEconomy.markets(repo)[0]
	var r := WarGround.reading(repo, state, m["at"], "")
	var label := String(repo.burgs[String(m["burg"])]["label"])
	var price := String.num(float(WarEconomy.food_price_permille(repo, String(m["id"]))) / 1000.0, 2)
	assert_true(_texts(r).any(func(t: String) -> bool: return t.begins_with("Market of %s (" % label) and t.ends_with("— food at ×%s" % price)))


func test_a_market_won_reads_ours() -> void:
	var m: Dictionary = WarEconomy.markets(repo)[0]
	var prov := String(repo.burgs[String(m["burg"])]["province_code"])
	MapOwnership.set_owner(repo, state, prov, repo.resolve_realm("player_realm"), "test: the market's province is taken")
	var r := WarGround.reading(repo, state, m["at"], "")
	assert_true(_texts(r).any(func(t: String) -> bool: return t.begins_with("Market of ") and t.contains("(ours)")))


func test_the_open_sea_has_no_economy_lines() -> void:
	var texts := _texts(WarGround.reading(repo, state, _sea_point(), ""))
	for t: String in texts:
		assert_false(t.begins_with("Trade: ") or t.begins_with("Works: ") or t.begins_with("Market of "), t)
```

- [ ] **Step 2: Run them to watch them fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_war_ground.gd -gexit`
Expected: FAIL — the reading has no `trade` key; no "Works:" / "Market of" lines.

- [ ] **Step 3: The reading**

In `WarGround.reading`, after the `var out := {...}` dictionary and before `if code != "":`:

```gdscript
	# the war economy at the point (spec 2026-10-07-war-room-p3 §1.3): public,
	# save a home works' live month
	out["trade"] = 0 if sea or String(out["road"]) == "" else WarEconomy.trade_at(repo, at)
	out["making"] = WarEconomy.works(repo).get(town, {}) if town != "" else {}
	out["making_live"] = -1
	if not (out["making"] as Dictionary).is_empty() and state != null and town_holder == repo.resolve_realm("player_realm"):
		var cell := int(MapEconomy.burg_cells(repo).get(town, -1))
		if cell >= 0:
			out["making_live"] = int(ManorEconomy.line_of(repo, state, cell, state.tick)["strategic"])
	out["market"] = {}
	var market := WarEconomy.market_of_town(repo, town) if town != "" else ""
	if market != "":
		out["market"] = {"id": market, "label": String(repo.burgs[town].get("label", town)),
			"holder": MarketSystem.kingdom_of_party(repo, state, "market", market) if state != null else "",
			"food_permille": WarEconomy.food_price_permille(repo, market)}
```

- [ ] **Step 4: The lines**

In `WarGround.lines`, in the land branch, between the town block (ending with the garrison `_add`) and `_add(out, "Weather: " ...)`:

```gdscript
	_economy_lines(repo, r, out)
```

and add the function after `_hazard_lines`:

```gdscript
## The war economy at the point (spec 2026-10-07-war-room-p3 §1.3): the trade
## passing on the road, a works' goods (at home with this month's gold), a
## market and its food price against the catalogue.
static func _economy_lines(repo: DataRepository, r: Dictionary, out: Array) -> void:
	if int(r.get("trade", 0)) > 0:
		_add(out, "Trade: about %s gold a month passes" % Intel.num(int(r["trade"])))
	var mk: Dictionary = r.get("making", {})
	if not mk.is_empty():
		var parts: Array[String] = []
		for g: Dictionary in (mk["goods"] as Array).slice(0, 3):
			parts.append("%s %s" % [WarEconomy.good_label(repo, String(g["good"])).to_lower(), Intel.num(roundi(float(g["units"])))])
		var text := "Works: %s (%s gold a month)" % [", ".join(parts), Intel.num(int(mk["gold"]))]
		if int(r.get("making_live", -1)) >= 0:
			text += " (this month: %s)" % Intel.num(int(r["making_live"]))
		_add(out, text)
	var m: Dictionary = r.get("market", {})
	if not m.is_empty():
		var holder := String(m["holder"])
		var whose := "ours" if holder == repo.resolve_realm("player_realm") \
			else String((repo.kingdoms.get(holder, {}) as Dictionary).get("label", holder))
		_add(out, "Market of %s (%s) — food at ×%s" % [String(m["label"]), whose,
			String.num(float(int(m["food_permille"])) / 1000.0, 2)])
```

- [ ] **Step 5: Run the file to watch it pass**

Run: the Step 2 command.
Expected: PASS (every earlier test in the file too).

- [ ] **Step 6: Commit**

```bash
git add scripts/engine/war_ground.gd tests/engine/test_war_ground.gd
git commit -m "feat(war room): the slip names the trade on a road, a works' goods and a market"
```

---

### Task 6: The key slip

**Files:**
- Modify: `scripts/ui/war_margin_key.gd` (`LEGEND` ~lines 18–33; `_draw_mark` ~line 162 and its `match key:`)
- Test: `tests/ui/test_war_margin_key.gd`

**Interfaces:**
- Consumes: Task 1 `repo.war_works`; Task 3 `WarMarkGlyph` glyphs (`scales`).
- Produces: `WarMarginKey.LEGEND` gains `works_arms`, `works_horses`, `works_ore`, `works_naval`, `market`, `trade` (after the `hazard_*` entries).

- [ ] **Step 1: Write the failing tests**

In `test_the_legend_lists_the_sheets_inks`, append to the expected keys after `"hazard_rock"`:

```gdscript
		"hazard_plague", "hazard_unrest", "hazard_water", "hazard_rock",
		"works_arms", "works_horses", "works_ore", "works_naval", "market", "trade"]))
```

and add:

```gdscript
func test_the_key_lists_every_works_family() -> void:
	var keys := WarMarginKey.legend_keys()
	for good: String in repo.war_works:
		assert_true(keys.has("works_" + String(repo.war_works[good]["family"])), good)
```

- [ ] **Step 2: Run them to watch them fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/ui/test_war_margin_key.gd -gexit`
Expected: FAIL — the legend lacks the six keys.

- [ ] **Step 3: Write it**

`LEGEND`, after the `hazard_*` line:

```gdscript
	{"key": "works_arms", "label": "Arms works"}, {"key": "works_horses", "label": "Horse works"},
	{"key": "works_ore", "label": "Ore works"}, {"key": "works_naval", "label": "Shipyard"},
	{"key": "market", "label": "Market"}, {"key": "trade", "label": "Trade road"},
```

`_draw_mark`, before the `if key.begins_with("hazard_"):` block:

```gdscript
	if key.begins_with("works_"):   # a works' glyph by family (spec 2026-10-07-war-room-p3 §1.3)
		var family := key.trim_prefix("works_")
		var glyph := "dot"
		var goods: Array = _repo.war_works.keys()
		goods.sort()
		for good: String in goods:
			if String(_repo.war_works[good]["family"]) == family:
				glyph = String(_repo.war_works[good]["glyph"])
				break
		WarMarkGlyph.draw(self, glyph, r.get_center(), r.size.y * 0.9, ink)
		return
	if key == "market":
		WarMarkGlyph.draw(self, "scales", r.get_center(), r.size.y * 0.9, ink)
		return
```

and in `match key:` beside `"road":`:

```gdscript
		"trade":
			draw_line(a, b, ink, line * 3.0, true)
```

- [ ] **Step 4: Run the file to watch it pass**

Run: the Step 2 command.
Expected: PASS (including `test_the_key_sizes_itself_from_data`, which reads `LEGEND.size()`).

- [ ] **Step 5: Commit**

```bash
git add scripts/ui/war_margin_key.gd tests/ui/test_war_margin_key.gd
git commit -m "feat(war room): the key names the works, the market and the trade road"
```

---

### Task 7: Visual review, the rules written down, the whole suite

**Files:**
- Modify: `data/balance.csv` (values only, as the review rules), `scripts/war_room/CLAUDE.md`, `scripts/engine/CLAUDE.md`, `data/CLAUDE.md`

- [ ] **Step 1: Visual review** — the `visual-review` skill: real-window shots at 2560x1600 (`res://scenes/tools/snapshot_screen.tscn -- --screen root --war-room --war-cell <ID> --war-focus-px X,Y --war-zoom Z`), on the first market's centre town (a works and a market; find its sheet id as P2 did: column `floor(x / sheet_w)` lettered, row `floor(y / sheet_h) + 1`) at 1.6 / 1.0 / 0.5 m, a sheet with no works, a hover on a trade road and on the market town (`--war-hover`), and the key. Bracket `war_works_min_gold` (40 / 60 / 90), `war_ink_trade_px` (2 / 3 / 5) and `war_ink_works_px` (24 / 30 / 38) with `contact_sheet.py`; an independent critic with `taste.md` and the rubric. Fix what breaks a principle; re-shoot.

- [ ] **Step 2: Write the rules as they stand**

`scripts/war_room/CLAUDE.md`, in "The sheets", after the **Marks** bullet:

```markdown
- **The war economy** (`WarEconomy`, pure, `scripts/engine/`; `data/war_works.csv`, spec `2026-10-07-war-room-p3-economy-layer-design.md` §1): public, static facts of the pack inked on every sheet — a town making `war_works_min_gold` of strategic goods a month carries its family's glyph above its ring (arms, horses, ore, naval), a market's centre town its scales below; the pack's deals summed per road segment (`trade_flows`, built once per pack) weigh a road by tier (`war_trade_tier<N>_gold`, `war_ink_trade_px`). The fine print says what a works makes; the slip names the trade on a road, a works' goods (at home with this month's live gold) and a market with its food price.
```

`scripts/engine/CLAUDE.md`, "Industry and trade", a last bullet:

```markdown
- `WarEconomy` reads the same pack tables for the WAR ROOM only (works, markets, trade on the roads); it never feeds the economy — `ManorEconomy` and `MarketSystem` stay the source of every gold figure.
```

`data/CLAUDE.md`, in the `war_*` parenthesis, after the `hazard_kinds` clause: `; war_works: the strategic goods that make a town a war works on the sheet, by family and glyph`.

- [ ] **Step 3: The whole suite**

Run: `./run_tests.sh > /tmp/p3a_suite.log 2>&1; tail -15 /tmp/p3a_suite.log`
Expected: "All tests passed", 0 errors in a worktree without the gdai binaries.

- [ ] **Step 4: Commit**

```bash
git add data/balance.csv scripts/war_room/CLAUDE.md scripts/engine/CLAUDE.md data/CLAUDE.md
git commit -m "docs(war economy): the rules as they stand; values tuned at visual review"
```
