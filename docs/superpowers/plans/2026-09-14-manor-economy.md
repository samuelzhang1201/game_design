# Manor Economy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every manor earns whole-gold tax, strategic goods and civil goods each 30-day month; provinces and the realm are exact sums; the treasury, strategic and civil pools settle at the month's end; the top bar shows the realm and the crown's provinces.

**Architecture:** Nothing per manor is stored — `ManorEconomy` derives a manor's month from the pack, the buildings, the focus and an integer growth table; `RealmEconomy` keeps a columnar cache (`PackedInt32Array` per line, province-major) with per-province keys as the dirty flag and 30-day buckets; `TickEngine` settles the month from the cached sums before the tick increments. Goods are classified and priced in a game-side table keyed by the pack's good codes.

**Tech Stack:** Godot 4.7 / typed GDScript, GUT (`./run_tests.sh`, one file: `Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/<file>.gd -gexit`), CSV data under `data/`.

**Spec:** `docs/superpowers/specs/2026-09-14-economy-and-staging-design.md` (§2–§6, §8–§12). The staging half (§7) is a separate plan.

## Global Constraints

- Design values live in CSVs, never in scripts (CLAUDE.md). Every new number below is a `data/balance.csv` row or a column.
- Engine classes are `RefCounted`, headless, no `Time.*`, no wall clock, no unseeded RNG; nothing under `scripts/engine/` names a `scripts/ui/` or `scripts/llm/` class or `Game.` (`tests/engine/test_engine_isolation.gd` enforces it).
- Integers only in the economy: the unit is **one whole gold**; growth is integer per-mille; iteration order is fixed (manors ascend by cell id within a province, provinces by code, goods by code).
- The only rounding is at the manor (`ManorEconomy.line_of`); province and realm are sums.
- Every metric change carries a reason string.
- The suite must stay green with the expected error count (`./run_tests.sh` says so); run it before every commit that touches `scripts/` or `data/`.
- Commit messages end with the two attribution lines the session's reminder gives.
- The pack's `data/maps/beria/**` CSVs are importer output: never hand-edit them; game-side tables go under `data/`.
- The metric key for the civil pool stays `grain` in `state.metrics` (a dozen readers use it directly); the schema exposes `metrics.civil` as an alias of it. The spec wrote the alias the other way round; the effect is the same and no reader breaks.

---

## File structure

| file | responsibility |
|---|---|
| `scripts/engine/calendar.gd` (modify) | 30-day tick, 12 a year |
| `data/goods_economy.csv`, `data/goods_economy_defaults.csv` (create) | pool, price, growth per good; defaults by tag |
| `scripts/engine/data_repository.gd` (modify) | load the two tables; `goods_economy_of()` |
| `scripts/engine/map_manors.gd` (modify) | integer people (`people_table`, `people_of`, `apportion`); `rush_work` |
| `scripts/engine/manor_economy.gd` (create) | one manor's month: tax, tariff, units, strategic, civil; growth table |
| `scripts/engine/realm_economy.gd` (create) | columnar cache, province keys, buckets, realm/crown sums, full check |
| `scripts/engine/tick_engine.gd` (modify) | day step warms a bucket; the month's settlement before the tick increments |
| `scripts/engine/game_state.gd`, `scripts/engine/world_ledger.gd` (modify) | new metrics, seeding of the pools |
| `data/world_schema.csv`, `data/metric_polarity.csv`, `data/balance.csv`, `data/council_seats.csv`, `data/manor_buildings.csv`, `data/manor_focus.csv`, `data/order_costs.csv`, `data/policy_actions_court_additions.csv`, `data/action_signatures.csv`, `data/resource_icons.csv` (modify) | the data rewrite |
| `scripts/engine/action_system.gd` (modify) | `GOODS_BUY`, `GOODS_SELL`, `MANOR_RUSH`; `MANOR_BUILD` pays civil |
| `scripts/ui/top_bar.gd`, `scenes/top_bar.tscn` (modify) | two lines |
| `tools/bench_economy.gd` (create) | the bench |
| `tests/engine/test_calendar.gd`, `test_tick_engine.gd`, `test_map_manors.gd`, `test_action_system.gd`, `test_world_tables.gd` (modify); `test_goods_economy.gd`, `test_manor_economy.gd`, `test_realm_economy.gd` (create); `tests/ui/test_top_bar.gd` (modify) | tests |

---

### Task 1: A tick is a month

**Files:**
- Modify: `scripts/engine/calendar.gd:8-9`
- Modify: `tests/engine/test_calendar.gd`
- Modify: `tests/engine/test_tick_engine.gd:30-39, 83-99`
- Modify: `data/balance.csv` (`promise_default_ticks`, `event_pity_ticks`), `data/manor_focus.csv` (`transition_ticks`)

**Interfaces:**
- Produces: `Calendar.DAYS_PER_TICK == 30`, `Calendar.TICKS_PER_YEAR == 12`; seasons are ticks 1–3 spring, 4–6 summer, 7–9 autumn, 10–12 winter.

- [ ] **Step 1: Rewrite the calendar test for a 30-day tick**

Replace `tests/engine/test_calendar.gd` with:

```gdscript
extends GutTest
## A tick is a month of 30 days (owner 2026-09-14), twelve a year, three a season.

func test_first_day_of_campaign() -> void:
	assert_eq(Calendar.DAYS_PER_TICK, 30)
	assert_eq(Calendar.TICKS_PER_YEAR, 12)
	assert_eq(Calendar.absolute_day(1, 1), 1)
	assert_eq(Calendar.date_string(1, 1), "Spring 1, Year 1")

func test_season_blocks_are_three_ticks() -> void:
	assert_eq(Calendar.season_name(3), "Spring")   # days 61..90
	assert_eq(Calendar.season_name(4), "Summer")   # day 91
	assert_eq(Calendar.season_name(7), "Autumn")
	assert_eq(Calendar.season_name(10), "Winter")

func test_year_boundary() -> void:
	assert_eq(Calendar.date_string(12, 30), "Winter 90, Year 1")
	assert_eq(Calendar.date_string(13, 1), "Spring 1, Year 2")

func test_day_within_tick_advances() -> void:
	# tick 2 covers days 31..60 of spring
	assert_eq(Calendar.day_of_season(2, 1), 31)
	assert_eq(Calendar.day_of_season(2, 30), 60)

func test_game_state_agrees_with_calendar() -> void:
	var data := DataRepository.load_all("res://data")
	var s := GameState.new_campaign(data, 42)
	for t in [1, 3, 4, 6, 7, 9, 10, 12, 13]:
		s.tick = t
		assert_eq(s.season(), Calendar.season_name(t).to_lower(), "tick %d" % t)
		assert_eq(s.year(), Calendar.year_of(t), "tick %d" % t)
```

- [ ] **Step 2: Run it to see it fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_calendar.gd -gexit 2>&1 | grep -E "Passing|Failing"`
Expected: failing (DAYS_PER_TICK is 15).

- [ ] **Step 3: Change the constants**

In `scripts/engine/calendar.gd` replace the header comment and the two constants:

```gdscript
## Pure date math over the tick clock: 12 ticks/year, 30 days/tick — a tick
## is a MONTH (owner 2026-09-14) — 4 seasons x 90 days (a 360-day year).
## Presentation helper - no state, no RNG, single source of truth for
## season/year boundaries (tick 1..12 is year 1; each season spans exactly
## 3 ticks).

const DAYS_PER_TICK := 30
const TICKS_PER_YEAR := 12
```

- [ ] **Step 4: Fix the tick engine tests that encode 15 and 24**

In `tests/engine/test_tick_engine.gd`, `test_grain_seasonal`: change `s.tick = 12  # advance() makes it 13 -> autumn` to `s.tick = 6  # advance() makes it 7 -> autumn` and `s.tick = 19  # -> 20, winter` to `s.tick = 9  # -> 10, winter`. Rename `test_days_step_works_and_the_fifteenth_is_a_tick` to `test_days_step_works_and_the_thirtieth_is_a_tick`; its body already uses `Calendar.DAYS_PER_TICK`. Its assertion `assert_gt(days, Calendar.DAYS_PER_TICK, "a palisade outlasts a tick")` compares the palisade's 20 build days to 30 and will now fail: change it to `assert_lt(days, Calendar.DAYS_PER_TICK, "a palisade is done within a month")` and change the loop that follows so it expects the work to finish: replace

```gdscript
	for i in Calendar.DAYS_PER_TICK - 1:
		assert_eq(engine.advance_day(s), [])
```
with
```gdscript
	for i in days - 1:
		assert_eq(engine.advance_day(s), [], "day %d" % (i + 2))
	assert_eq(engine.advance_day(s), [{"cell": cell, "building": "palisade"}], "done on its last day")
	for i in Calendar.DAYS_PER_TICK - 1 - days:
		assert_eq(engine.advance_day(s), [])
```
(keep whatever assertions follow about `s.day == Calendar.DAYS_PER_TICK` and the tick).

- [ ] **Step 5: Re-tune the tick-counted data**

`data/balance.csv`: `promise_default_ticks,24,` → `promise_default_ticks,12,due when the parser omits tick_due (a year of months)`; `event_pity_ticks,6,` → `event_pity_ticks,3,force an event after this many quiet months`.
`data/manor_focus.csv`: halve every `transition_ticks` (rounding up): grain 3→2, cattle 4→2, sheep 3→2, wood 2→1, honey 2→1, wine 6→3, dates 3→2, furs 3→2, fish 2→1, salt 4→2, stone 5→3, iron 6→3.
Then grep the rest of the data for fortnight wording: `grep -rn "fortnight\|per tick\|ticks" data/*.csv | grep -v "^data/balance.csv:.*map_"` and change wording to "month" where a row's note says "tick" meaning a fortnight; values that are counts of ticks (durations) halve, rounding up.

- [ ] **Step 6: Run the whole suite and fix what encodes 15 or 24**

Run: `./run_tests.sh 2>&1 | tail -20`
Expected: green. If a test asserts a date string, a tick count or "15", it is asserting the old calendar: update the expectation to the 30-day calendar (the season of tick t is `Calendar.season_name(t)`).

- [ ] **Step 7: Commit**

```bash
git add scripts/engine/calendar.gd tests/engine/test_calendar.gd tests/engine/test_tick_engine.gd data/balance.csv data/manor_focus.csv
git commit -m "feat(time): a tick is a month — 30 days, twelve a year"
```

---

### Task 2: Goods classified, priced, growing

**Files:**
- Create: `data/goods_economy.csv`, `data/goods_economy_defaults.csv`
- Modify: `scripts/engine/data_repository.gd` (near the `goods_art` loader, line ~316)
- Create: `tests/engine/test_goods_economy.gd`

**Interfaces:**
- Produces: `DataRepository.goods_economy: Dictionary` (good_code → row), `goods_economy_defaults: Dictionary` (tag → row), `func goods_economy_of(good_code: String) -> Dictionary` returning `{"pool": String, "price_gold": int, "growth_permille": int}` for any code (unknown code and unknown tag → `{"pool": "civil", "price_gold": 1, "growth_permille": 0}`).

- [ ] **Step 1: Write the failing test**

`tests/engine/test_goods_economy.gd`:

```gdscript
extends GutTest
## data/goods_economy.csv (spec §3): every good of the pack has a pool, a
## whole-gold price and an integer growth; a good the table does not name
## takes its first tag's default row.

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_every_pack_good_resolves_to_a_pool_and_a_price() -> void:
	var goods := data.world_table("economy", "goods")
	assert_gt(goods.size(), 60, "the pack's goods loaded")
	for code: String in goods:
		var ge := data.goods_economy_of(code)
		assert_true(ge["pool"] in ["strategic", "civil"], "%s has a pool" % code)
		assert_gt(int(ge["price_gold"]), 0, "%s has a price" % code)
		assert_typeof(ge["price_gold"], TYPE_INT, "%s price is whole gold" % code)
		assert_typeof(ge["growth_permille"], TYPE_INT, "%s growth is per mille" % code)
		assert_true(data.goods_economy.has(code), "%s is named in the table, not defaulted" % code)

func test_the_scale_is_deliberate() -> void:
	assert_eq(data.goods_economy_of("grain")["pool"], "civil")
	assert_eq(int(data.goods_economy_of("grain")["price_gold"]), 1)
	assert_eq(data.goods_economy_of("iron")["pool"], "strategic")
	assert_eq(int(data.goods_economy_of("iron")["price_gold"]), 4)
	assert_eq(data.goods_economy_of("arms")["pool"], "strategic")
	assert_eq(int(data.goods_economy_of("ships")["price_gold"]), 30)
	assert_eq(int(data.goods_economy_of("gold")["price_gold"]), 40)
	assert_gt(int(data.goods_economy_of("silk")["growth_permille"]), int(data.goods_economy_of("grain")["growth_permille"]),
		"luxuries grow faster than bread")

func test_an_unnamed_good_takes_its_tags_default() -> void:
	var r := DataRepository.new()
	r.goods_economy_defaults = {"military": {"tag": "military", "pool": "strategic", "price_gold": "9", "growth_permille": "4"}}
	r._register_table("economy", "goods", {"halberds": {"good_code": "halberds", "tags": "military|luxury"}})
	var ge := r.goods_economy_of("halberds")
	assert_eq(ge["pool"], "strategic")
	assert_eq(int(ge["price_gold"]), 9)
	assert_eq(int(ge["growth_permille"]), 4)
	var none := r.goods_economy_of("nothing")
	assert_eq(none, {"pool": "civil", "price_gold": 1, "growth_permille": 0})
```

- [ ] **Step 2: Run it to see it fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_goods_economy.gd -gexit 2>&1 | grep -E "Passing|Failing|rror"`
Expected: fails — `goods_economy_of` does not exist.

- [ ] **Step 3: Write the two tables**

`data/goods_economy_defaults.csv`:

```csv
tag,pool,price_gold,growth_permille,notes
food,civil,2,2,"a good the table does not name takes its FIRST tag's row (spec §3)"
construction,civil,2,3,
ore,strategic,4,3,
luxury,civil,8,5,
clothing,civil,3,3,
preservative,civil,3,2,
supply,strategic,10,2,
naval,strategic,4,4,
military,strategic,9,4,
fuel,strategic,3,3,
mineral,civil,2,2,
storage,civil,3,3,
ritual,civil,5,3,
currency,civil,25,2,
aquatic,civil,2,2,
educational,civil,6,4,
```

`data/goods_economy.csv` (every good of `data/maps/beria/economy/goods.csv`; prices are the owner's deliberate spread — grain 1 to gold 40 — and growth per mille a month):

```csv
good_code,pool,price_gold,growth_permille,notes
wood,civil,1,3,"pool: where a unit's gold lands (strategic feeds the army, civil the building); price_gold: whole gold a unit; growth_permille: the good's monthly growth of output"
stone,civil,2,3,
marble,civil,6,4,
iron,strategic,4,3,
copper,strategic,4,3,
tin,strategic,4,3,
silver,civil,20,4,bullion is wealth not war
gold,civil,40,4,
grain,civil,1,2,
cattle,civil,3,2,
fish,civil,1,2,
game,civil,2,1,
wine,civil,5,4,
olives,civil,2,2,
honey,civil,3,2,
salt,civil,3,2,
dates,civil,2,2,
horses,strategic,12,2,
elephants,strategic,30,1,
camels,strategic,10,2,
hemp,strategic,2,3,rope and sailcloth
pearls,civil,25,5,
gemstones,civil,30,5,
dyes,civil,6,4,
incense,civil,12,5,
silk,civil,15,6,
spices,civil,20,5,
amber,civil,10,4,
furs,civil,6,3,
sheep,civil,2,2,
slaves,strategic,15,1,
tar,strategic,3,3,
saltpeter,strategic,4,4,
coal,strategic,3,3,
oil,strategic,4,3,
mahogany,civil,8,4,
whales,civil,3,2,
sugarcane,civil,4,3,
tea,civil,6,5,
tobacco,civil,6,5,
clay,civil,1,2,
white_sand,civil,1,2,
leather,strategic,5,3,
cloth,civil,3,3,
garments,civil,8,4,
ceramics,civil,5,3,
glass,civil,8,4,
ropes,strategic,3,4,
paper,civil,6,4,
ink,civil,5,4,
books,civil,20,5,
sails,strategic,8,4,
ships,strategic,30,3,
boots,strategic,6,4,
harnesses,strategic,8,4,
barrels,strategic,3,3,
bronze,strategic,9,4,
tools,strategic,12,4,
arms,strategic,10,5,
gunpowder,strategic,12,5,
artillery,strategic,40,4,
coins,civil,25,2,
jewelry,civil,35,5,
preserved_food,strategic,4,3,the army marches on it
vinegar,civil,2,2,
cheese,civil,4,2,
beer,civil,4,3,
liquor,civil,8,4,
candles,civil,5,3,
soap,civil,5,4,
perfume,civil,15,5,
```

- [ ] **Step 4: Load them in DataRepository**

In `scripts/engine/data_repository.gd`, next to `var goods_art: Dictionary = {}` add:

```gdscript
## data/goods_economy.csv: good_code -> {pool, price_gold, growth_permille}
## (spec 2026-09-14 §3); goods_economy_defaults.csv: tag -> the same, for a
## good the table does not name.
var goods_economy: Dictionary = {}
var goods_economy_defaults: Dictionary = {}
```

Next to the `goods_art.csv` loader add:

```gdscript
	if not _load_if_present("res://data/goods_economy.csv",
			["good_code", "pool", "price_gold", "growth_permille"],
			func(r): goods_economy[String(r["good_code"])] = r):
		return false
	if not _load_if_present("res://data/goods_economy_defaults.csv",
			["tag", "pool", "price_gold", "growth_permille"],
			func(r): goods_economy_defaults[String(r["tag"])] = r):
		return false
```

After `func world_row(...)` add:

```gdscript
## A good's pool, whole-gold price and monthly growth per mille: its own
## row, else its first tag's default row, else civil at 1 gold growing 0.
func goods_economy_of(good_code: String) -> Dictionary:
	var row: Dictionary = goods_economy.get(good_code, {})
	if row.is_empty():
		var tags := String(world_row("economy", "goods", good_code).get("tags", "")).split("|", false)
		if not tags.is_empty():
			row = goods_economy_defaults.get(String(tags[0]), {})
	if row.is_empty():
		return {"pool": "civil", "price_gold": 1, "growth_permille": 0}
	return {"pool": String(row.get("pool", "civil")),
		"price_gold": int(float(row.get("price_gold", 1))),
		"growth_permille": int(float(row.get("growth_permille", 0)))}
```

- [ ] **Step 5: Run the test**

Run the same command. Expected: 3 passing.

- [ ] **Step 6: Commit**

```bash
git add data/goods_economy.csv data/goods_economy_defaults.csv scripts/engine/data_repository.gd tests/engine/test_goods_economy.gd
git commit -m "feat(economy): every good has a pool, a whole-gold price and a growth"
```

---

### Task 3: People are integers that sum to the province

**Files:**
- Modify: `scripts/engine/map_manors.gd` (after `population_table`, line ~357; `invalidate`, line 26)
- Modify: `tests/engine/test_map_manors.gd` (append tests)

**Interfaces:**
- Produces: `MapManors.apportion(ids: Array, weights: PackedFloat64Array, total: int) -> Dictionary` (id → int), `MapManors.people_table(repo, state, province_code: String) -> Dictionary` (cell → int, rural + urban), `MapManors.people_of(repo, state, cell_id: int) -> int`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/engine/test_map_manors.gd`:

```gdscript
## Integer people (spec §4.1): largest remainder, ties to the lower id.
func test_apportion_hands_the_remainder_to_the_largest_fractions() -> void:
	var out := MapManors.apportion([1, 2, 3], PackedFloat64Array([1.0, 1.0, 1.0]), 1000)
	assert_eq(out, {1: 334, 2: 333, 3: 333})
	assert_eq(MapManors.apportion([7, 9], PackedFloat64Array([3.0, 1.0]), 10), {7: 8, 9: 2}, "7.5 and 2.5: the tie goes to the lower id")
	assert_eq(MapManors.apportion([], PackedFloat64Array(), 5), {})
	assert_eq(MapManors.apportion([4], PackedFloat64Array([0.0]), 5), {4: 0}, "no weight, no people")

## Province p: 3 000 country folk over weights 80 and 80, and Shole's 1 000
## townsfolk to cell 2 -> 1 500 and 2 500, summing to the province's 4 000.
func test_people_sum_exactly_to_the_province() -> void:
	var r := _repo()
	var s := _state()
	var t := MapManors.people_table(r, s, "p")
	assert_eq(t, {1: 1500, 2: 2500})
	assert_eq(MapManors.people_of(r, s, 1), 1500)
	assert_eq(MapManors.people_of(r, s, 2), 2500)
	assert_eq(MapManors.people_of(r, s, 4), 800, "q's 800 go to its one manor")
	WorldLedger.apply(r, s, "economy.provinces.p.rural_population", 1, "test: one more", "test")
	assert_eq(MapManors.people_table(r, s, "p"), {1: 1501, 2: 2500}, "an odd one goes to the lower id; the cache keys on the figure")
```

- [ ] **Step 2: Run to see them fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_map_manors.gd -gexit 2>&1 | grep -E "Passing|Failing|rror"`
Expected: two failures (no `apportion`).

- [ ] **Step 3: Implement**

In `scripts/engine/map_manors.gd` after `_share(...)` add:

```gdscript
## --- Integer people (spec 2026-09-14 §4.1) -----------------------------------
## The province's country folk apportioned to its manors by weight with the
## largest-remainder method, so the manors sum EXACTLY to the province and
## no manor has a fraction of a person; its townsfolk the same way over its
## burgs. Cached per (province, rural, urban): the two ledger figures are
## the only inputs that move.
static var _people_cache: Dictionary = {}

## Largest remainder: every id gets the floor of its share, the units left
## go to the largest fractional remainders, ties to the id that comes first.
static func apportion(ids: Array, weights: PackedFloat64Array, total: int) -> Dictionary:
	var out: Dictionary = {}
	var sum := 0.0
	for w in weights:
		sum += w
	if ids.is_empty() or total <= 0 or sum <= 0.0:
		for id in ids:
			out[id] = 0
		return out
	var floors := PackedInt32Array()
	var rem := PackedFloat64Array()
	var given := 0
	for i in ids.size():
		var exact := float(total) * weights[i] / sum
		var f := int(floor(exact))
		floors.append(f)
		rem.append(exact - float(f))
		given += f
	var order: Array = range(ids.size())
	order.sort_custom(func(a: int, b: int) -> bool:
		return a < b if rem[a] == rem[b] else rem[a] > rem[b])
	for k in total - given:
		floors[order[k]] += 1
	for i in ids.size():
		out[ids[i]] = floors[i]
	return out

static func people_table(repo: DataRepository, state: GameState, province_code: String) -> Dictionary:
	var rural := int(roundf(_ledger(repo, state, "economy.provinces.%s.rural_population" % province_code)))
	var urban := int(roundf(_ledger(repo, state, "economy.provinces.%s.urban_population" % province_code)))
	var key := "%d|%s|%d|%d" % [repo.get_instance_id(), province_code, rural, urban]
	if _people_cache.has(key):
		return _people_cache[key]
	if _people_cache.size() > 4096:
		_people_cache.clear()
	var cells := manors_of_province(repo, province_code)
	var weights := PackedFloat64Array()
	for id: int in cells:
		weights.append(weight_of(repo, id))
	var out := apportion(cells, weights, rural)
	var burg_cells: Array = []
	var burg_weights := PackedFloat64Array()
	for id: int in cells:
		var burg := burg_of(repo, id)
		if burg != "":
			burg_cells.append(id)
			burg_weights.append(float(repo.burgs[burg].get("population", 0)))
	var town := apportion(burg_cells, burg_weights, urban)
	for id: int in town:
		out[id] = int(out[id]) + int(town[id])
	_people_cache[key] = out
	return out

## A manor's people, whole. 0 for a cell that is no manor.
static func people_of(repo: DataRepository, state: GameState, cell_id: int) -> int:
	var province := province_of(repo, cell_id)
	return 0 if province == "" else int(people_table(repo, state, province).get(cell_id, 0))
```

In `invalidate()` add `_people_cache.clear()`.

- [ ] **Step 4: Run the tests**

Expected: all of `test_map_manors.gd` passing.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/map_manors.gd tests/engine/test_map_manors.gd
git commit -m "feat(manor): people are integers apportioned by largest remainder"
```

---

### Task 4: A manor's month

**Files:**
- Create: `scripts/engine/manor_economy.gd`
- Create: `tests/engine/test_manor_economy.gd`
- Modify: `data/balance.csv` (add `manor_tax_per_1000`, `tax_rate_base`, `tariff_per_sales_tax`)

**Interfaces:**
- Consumes: `DataRepository.goods_economy_of`, `MapManors.people_of`, `MapManors.focus_of/focus_ramp/land_value_of/building_bonus/building_output_of`, `MapEconomy.manors(repo)[cell]["goods"]` (a burg's `{good: float units}`).
- Produces: `ManorEconomy.growth_index(repo, good: String, tick: int) -> int` (per mille, 1000 at tick 0); `ManorEconomy.focus_units(repo, state, cell: int, people: int, tick: int) -> Dictionary` `{good, units: int}`; `ManorEconomy.line_of(repo, state, cell: int, tick: int) -> Dictionary` `{people: int, tax: int, tariff: int, strategic: int, civil: int, units: {good: int}}` where `tax` includes the tariff; `ManorEconomy.forget()`.

- [ ] **Step 1: Add the balance rows**

Append to `data/balance.csv`:

```csv
manor_tax_per_1000,20,"ECONOMY (spec 2026-09-14 §4.2): whole gold a month a manor pays per 1 000 people at tax_rate_base, before its buildings' tax_bonus"
tax_rate_base,5,"ECONOMY: the poll-tax level (metrics.tax_rate, 1..10) at which a manor's tax factor is 1; 10 doubles it, 1 fifths it"
tariff_per_sales_tax,2,"ECONOMY: a settlement's tariff = its town goods' gold x tariff_rate (0..10) x this / 100 — at 5 that is a tenth"
```

- [ ] **Step 2: Write the failing tests**

`tests/engine/test_manor_economy.gd` — the fixture is `test_map_manors.gd`'s two squares with a chief good, a town line and the goods table added:

```gdscript
extends GutTest
## ManorEconomy (spec §4): one manor's month in whole gold, hand-computed.
## Province p (rural 3 000, urban 1 000): cell 1 is 10x10 on land 0.8 and
## works grain; cell 2 is 20x10 on land 0.4, holds Shole (1 000 townsfolk)
## which makes 7 wood and 2 iron a month, and works nothing. Balance: 20
## gold a month per 1 000 people at tax level 5; tariff 2 per level per
## hundred.

func _repo() -> DataRepository:
	var r := DataRepository.new()
	r.balance = {"manor_tax_per_1000": 20.0, "tax_rate_base": 5.0, "tariff_per_sales_tax": 2.0,
		"manor_focus_high_height": 52.0, "manor_focus_peak_height": 63.0}
	r.biomes = {1: {"habitability": "80"}, 2: {"habitability": "40"}}
	r.vertices = {0: Vector2(0, 0), 1: Vector2(10, 0), 2: Vector2(10, 10), 3: Vector2(0, 10),
		4: Vector2(30, 0), 5: Vector2(30, 10)}
	r.cells = {
		1: {"vertex_ids": PackedInt32Array([0, 1, 2, 3]), "height": 30.0, "biome_id": 1,
			"water": "", "neighbor_ids": PackedInt32Array([2])},
		2: {"vertex_ids": PackedInt32Array([1, 4, 5, 2]), "height": 30.0, "biome_id": 2,
			"water": "", "neighbor_ids": PackedInt32Array([1])},
	}
	r.manors = {
		1: {"cell_id": 1, "manor_code": "ashcombe", "label": "Ashcombe", "province_code": "p",
			"burg_code": "", "culture_code": "c"},
		2: {"cell_id": 2, "manor_code": "shole_manor", "label": "Shole Manor", "province_code": "p",
			"burg_code": "shole", "culture_code": "c"},
	}
	for id: int in r.manors:
		r.manor_by_code[String(r.manors[id]["manor_code"])] = id
		r.manor_by_label[String(r.manors[id]["label"]).to_lower()] = id
	r.provinces = {"p": {"province_code": "p", "label": "Prov", "kingdom_code": "k", "capital_burg": "shole"}}
	r.burgs = {"shole": {"burg_code": "shole", "label": "Shole", "province_code": "p",
		"population": "1000", "x": "20", "y": "5"}}
	r.house_bindings = {"p": "Valorin"}
	r.manor_buildings = {
		"mill": {"building_code": "mill", "label": "Mill", "cost_gold": "40", "tax_bonus": "0.05",
			"output_bonus": "0.15", "defence_bonus": "0", "church_bonus": "0", "produce_good": "", "produce_units": "0"},
	}
	r.manor_focus = {"grain": {"focus_code": "grain", "label": "Grain fields", "good_code": "grain",
		"biomes": "1", "coast": "0", "yield_per_1000": "12", "rent_bonus": "0.10",
		"switch_cost_gold": "20", "transition_ticks": "2", "default_on": "1"}}
	r.goods_economy = {
		"grain": {"good_code": "grain", "pool": "civil", "price_gold": "1", "growth_permille": "2"},
		"wood": {"good_code": "wood", "pool": "civil", "price_gold": "1", "growth_permille": "3"},
		"iron": {"good_code": "iron", "pool": "strategic", "price_gold": "4", "growth_permille": "3"},
	}
	r.world_schema = [
		{"path": "economy.provinces.*.rural_population", "type": "int", "min": "0",
			"max": "100000000", "enum_values": "", "good_direction": "1", "llm_cap": "2000",
			"alias_to": "", "alias_scale_key": ""},
		{"path": "economy.provinces.*.urban_population", "type": "int", "min": "0",
			"max": "100000000", "enum_values": "", "good_direction": "1", "llm_cap": "1000",
			"alias_to": "", "alias_scale_key": ""},
	]
	r._register_table("economy", "provinces", {
		"p": {"province_code": "p", "rural_population": "3000", "urban_population": "1000"}})
	r._register_table("economy", "goods", {
		"grain": {"good_code": "grain", "label": "Grain", "tags": "food"},
		"wood": {"good_code": "wood", "label": "Wood", "tags": "construction|fuel"},
		"iron": {"good_code": "iron", "label": "Iron", "tags": "ore|military"}})
	r._register_table("economy", "production", {
		"shole:wood": {"burg_code": "shole", "good_code": "wood", "units": "7"},
		"shole:iron": {"burg_code": "shole", "good_code": "iron", "units": "2"}})
	MapManors.invalidate()
	MapEconomy.forget()
	ManorEconomy.forget()
	return r

func _state() -> GameState:
	var s := GameState.new()
	s.rng = Rng.new(1)
	s.tick = 0
	s.metrics = {"tax_rate": 5.0, "tariff_rate": 3.0}
	s.player_setup = {"first_name": "Anne", "family_name": "Rex", "flag": ""}
	return s

## 1000 per mille at tick 0; 2 per mille compounding in integers: every
## month adds round(prev x 2 / 1000) = 2, so tick 12 is 1024 (the float
## 1.002^12 is 1.0243); a good with no growth stays 1000.
func test_growth_is_an_integer_table() -> void:
	var r := _repo()
	assert_eq(ManorEconomy.growth_index(r, "grain", 0), 1000)
	assert_eq(ManorEconomy.growth_index(r, "grain", 1), 1002)
	assert_eq(ManorEconomy.growth_index(r, "grain", 12), 1024)
	assert_eq(ManorEconomy.growth_index(r, "nothing", 40), 1000)
	assert_eq(ManorEconomy.growth_index(r, "grain", 12), 1024, "the same the second time")

## Cell 1: 1 500 people -> tax round(1.5 x 20 x 5/5) = 30; grain units
## round(1.5 x 12 x 0.8 x ramp 1 x growth 1) = round(14.4) = 14 -> 14 gold
## of civil goods, no town, no tariff, no strategic.
func test_a_country_manor_pays_tax_and_grows_its_chief_good() -> void:
	var r := _repo()
	var s := _state()
	var line := ManorEconomy.line_of(r, s, 1, 0)
	assert_eq(line["people"], 1500)
	assert_eq(line["tax"], 30)
	assert_eq(line["tariff"], 0)
	assert_eq(line["units"], {"grain": 14})
	assert_eq(line["civil"], 14)
	assert_eq(line["strategic"], 0)

## Cell 2: 2 500 people -> 50 tax; the town's 7 wood (1 gold) and 2 iron
## (4 gold) are 15 gold of goods -> tariff round(15 x 3 x 2 / 100) = 1, so
## tax 51; wood is civil (7), iron strategic (8). Its land allows no focus.
func test_a_town_manor_earns_its_towns_lines_and_a_tariff() -> void:
	var r := _repo()
	var s := _state()
	var line := ManorEconomy.line_of(r, s, 2, 0)
	assert_eq(line["people"], 2500)
	assert_eq(line["tariff"], 1)
	assert_eq(line["tax"], 51)
	assert_eq(line["units"], {"iron": 2, "wood": 7})
	assert_eq(line["civil"], 7)
	assert_eq(line["strategic"], 8)

## At tick 12 grain has grown to 1024 per mille: round(14.4 x 1.024) =
## round(14.7456) = 15. A mill's output_bonus 0.15 on cell 1 at tick 0:
## round(14.4 x 1.15) = round(16.56) = 17; its tax_bonus 0.05: round(31.5) = 32.
func test_growth_and_buildings_raise_the_line() -> void:
	var r := _repo()
	var s := _state()
	assert_eq(ManorEconomy.line_of(r, s, 1, 12)["units"], {"grain": 15})
	s.manor_buildings["1"] = ["mill"]
	var line := ManorEconomy.line_of(r, s, 1, 0)
	assert_eq(line["units"], {"grain": 17})
	assert_eq(line["tax"], 32)

## The poll tax scales the tax: level 10 doubles, level 1 fifths; the
## sales tax scales the tariff: level 0 is none.
func test_the_tax_levels_scale_the_lines() -> void:
	var r := _repo()
	var s := _state()
	s.metrics["tax_rate"] = 10.0
	assert_eq(ManorEconomy.line_of(r, s, 1, 0)["tax"], 60)
	s.metrics["tax_rate"] = 1.0
	assert_eq(ManorEconomy.line_of(r, s, 1, 0)["tax"], 6)
	s.metrics["tariff_rate"] = 0.0
	assert_eq(ManorEconomy.line_of(r, s, 2, 0)["tariff"], 0)
```

- [ ] **Step 3: Run to see them fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_manor_economy.gd -gexit 2>&1 | grep -E "Passing|Failing|rror"`
Expected: parse failure / all failing (no `ManorEconomy`).

- [ ] **Step 4: Write ManorEconomy**

`scripts/engine/manor_economy.gd`:

```gdscript
class_name ManorEconomy
extends RefCounted
## A manor's MONTH in whole gold (spec 2026-09-14 §4): tax, the tariff its
## town pays, and the goods it makes — its chief good, its buildings' and
## its settlement's lines — each rounded to whole units and valued at
## goods_economy.csv prices into the strategic or the civil pool. THE ONLY
## ROUNDING IN THE ECONOMY HAPPENS HERE; provinces and the realm are sums.
## Nothing is stored: a line is a pure function of the pack, the state's
## buildings, focus and ledger figures, and the tick. Iteration is by good
## code, ascending, so a line is the same integers on every machine.

## "repo id|good" -> PackedInt32Array, index tick -> per-mille growth.
static var _growth: Dictionary = {}

static func forget() -> void:
	_growth.clear()

## A good's growth index at a tick, per mille: 1000 at tick 0, compounding
## growth_permille a month in INTEGERS (next = round(prev x (1000 + g) /
## 1000)), tabulated once per good as ticks pass. Integer, so a save ticks
## to the same numbers on every machine (invariant 2, architecture R-7).
static func growth_index(repo: DataRepository, good: String, tick: int) -> int:
	var g := int(repo.goods_economy_of(good)["growth_permille"])
	var key := "%d|%s" % [repo.get_instance_id(), good]
	var table: PackedInt32Array = _growth.get(key, PackedInt32Array([1000]))
	while table.size() <= tick:
		var prev := table[table.size() - 1]
		table.append((prev * (1000 + g) + 500) / 1000)
	_growth[key] = table
	return table[maxi(tick, 0)]

## What the chief good yields this month: {good, units} — people / 1000 x
## yield_per_1000 x land value x the settling-in ramp x (1 + the buildings'
## output bonus) x growth, rounded. {"", 0} for land that works nothing.
static func focus_units(repo: DataRepository, state: GameState, cell: int, people: int,
		tick: int) -> Dictionary:
	var code := MapManors.focus_of(repo, state, cell)
	var row: Dictionary = repo.manor_focus.get(code, {})
	if row.is_empty():
		return {"good": "", "units": 0}
	var good := String(row.get("good_code", ""))
	var exact := float(people) / 1000.0 * float(row.get("yield_per_1000", 0)) \
		* MapManors.land_value_of(repo, cell) * MapManors.focus_ramp(repo, state, cell) \
		* (1.0 + MapManors.building_bonus(repo, state, cell, "output_bonus")) \
		* float(growth_index(repo, good, tick)) / 1000.0
	return {"good": good, "units": int(roundf(exact))}

## The manor's month: {people, tax, tariff, strategic, civil, units}.
## `tax` INCLUDES the tariff (the tariff is also given on its own for the
## card). tax = round(people / 1000 x manor_tax_per_1000 x tax_rate /
## tax_rate_base x (1 + Σ tax_bonus)); tariff = round(town goods' gold x
## tariff_rate x tariff_per_sales_tax / 100); a town's lines are the pack's
## production rows for its burg, each x growth x (1 + Σ output_bonus).
static func line_of(repo: DataRepository, state: GameState, cell: int, tick: int) -> Dictionary:
	var people := MapManors.people_of(repo, state, cell)
	var m := state.metrics
	var tax_rate := float(m.get("tax_rate", repo.bal("tax_rate_base")))
	var tax := int(roundf(float(people) / 1000.0 * repo.bal("manor_tax_per_1000")
		* tax_rate / repo.bal("tax_rate_base")
		* (1.0 + MapManors.building_bonus(repo, state, cell, "tax_bonus"))))
	var units: Dictionary = {}
	var f := focus_units(repo, state, cell, people, tick)
	if int(f["units"]) > 0:
		units[f["good"]] = int(f["units"])
	var made := MapManors.building_output_of(repo, state, cell)
	var made_codes: Array = made.keys()
	made_codes.sort()
	for good: String in made_codes:
		var u := int(roundf(float(made[good]) * float(growth_index(repo, good, tick)) / 1000.0))
		if u > 0:
			units[good] = int(units.get(good, 0)) + u
	var out_bonus := 1.0 + MapManors.building_bonus(repo, state, cell, "output_bonus")
	var town: Dictionary = (MapEconomy.manors(repo).get(cell, {}) as Dictionary).get("goods", {})
	var town_codes: Array = town.keys()
	town_codes.sort()
	var town_gold := 0
	for good: String in town_codes:
		var u := int(roundf(float(town[good]) * float(growth_index(repo, good, tick)) / 1000.0 * out_bonus))
		if u <= 0:
			continue
		units[good] = int(units.get(good, 0)) + u
		town_gold += u * int(repo.goods_economy_of(good)["price_gold"])
	var tariff := 0
	if town_gold > 0:
		tariff = int(roundf(float(town_gold) * float(m.get("tariff_rate", 0.0))
			* repo.bal("tariff_per_sales_tax") / 100.0))
	var strategic := 0
	var civil := 0
	var codes: Array = units.keys()
	codes.sort()
	for good: String in codes:
		var ge := repo.goods_economy_of(good)
		var gold := int(units[good]) * int(ge["price_gold"])
		if String(ge["pool"]) == "strategic":
			strategic += gold
		else:
			civil += gold
	return {"people": people, "tax": tax + tariff, "tariff": tariff,
		"strategic": strategic, "civil": civil, "units": units}
```

Note for the `units` assertions: a Dictionary compares equal regardless of insertion order, so `{"iron": 2, "wood": 7}` matches.

- [ ] **Step 5: Run the tests**

Expected: 5 passing. If `test_a_town_manor_...` finds no town goods, `MapEconomy.manors(repo)` did not place Shole in cell 2: its point (20, 5) lies inside cell 2's polygon (10..30 x 0..10); check `burg_cells` and that the fixture's burg row has `x` and `y`.

- [ ] **Step 6: Commit**

```bash
git add scripts/engine/manor_economy.gd tests/engine/test_manor_economy.gd data/balance.csv
git commit -m "feat(economy): a manor's month in whole gold — tax, tariff, goods by pool, integer growth"
```

---

### Task 5: The realm's cache — columnar, keyed, bucketed

**Files:**
- Create: `scripts/engine/realm_economy.gd`
- Create: `tests/engine/test_realm_economy.gd`
- Modify: `scripts/engine/data_repository.gd:388-392` (`load_map` cache resets)

**Interfaces:**
- Consumes: `ManorEconomy.line_of`, `MapManors.manors_of_province/controlled_provinces/buildings_of/province_of`, `MapOwnership.provinces_of(data, state, kingdom) -> Array[String]`, `WorldLedger.value_of`.
- Produces: `RealmEconomy.setup(repo)`, `province_key(repo, state, code) -> String`, `province(repo, state, code) -> Dictionary {tax, strategic, civil}` (current), `realm(repo, state) -> Dictionary {realm: {...}, crown: {...}, per_province: {code: {...}}}`, `step_day(repo, state) -> int` (provinces recomputed), `line_of(repo, state, cell) -> Dictionary {tax, strategic, civil}`, `recompute_all(repo, state) -> Dictionary` (code → sums, no cache), `check_full(repo, state) -> Array` (mismatches), `strategic_stock(state) -> int`, `forget()`, `static var compute_count: int`.

- [ ] **Step 1: Write the failing tests**

`tests/engine/test_realm_economy.gd`:

```gdscript
extends GutTest
## RealmEconomy (spec §4.4, §11.2): province sums from the columnar cache,
## the realm and the crown over the real pack, exact tie-out, and a cache
## that recomputes only what changed.

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func test_a_province_is_the_sum_of_its_manors_lines() -> void:
	var codes: Array = Array(MapOwnership.provinces_of(data, s, data.resolve_realm("player_realm")))
	codes.sort()
	for code: String in codes.slice(0, 3):
		var sum := {"tax": 0, "strategic": 0, "civil": 0}
		for cell: int in MapManors.manors_of_province(data, code):
			var line := ManorEconomy.line_of(data, s, cell, s.tick)
			sum["tax"] += int(line["tax"])
			sum["strategic"] += int(line["strategic"])
			sum["civil"] += int(line["civil"])
			var cached := RealmEconomy.line_of(data, s, cell)
			assert_eq(cached, {"tax": line["tax"], "strategic": line["strategic"], "civil": line["civil"]}, "the cache keeps the line of %d" % cell)
		assert_eq(RealmEconomy.province(data, s, code), sum, "province %s ties out" % code)

func test_the_realm_is_the_sum_of_its_provinces_and_the_crown_of_its_own() -> void:
	var e := RealmEconomy.realm(data, s)
	var realm := {"tax": 0, "strategic": 0, "civil": 0}
	var crown := {"tax": 0, "strategic": 0, "civil": 0}
	var mine := MapManors.controlled_provinces(data, s)
	assert_gt(mine.size(), 0, "the crown controls a province")
	for code: String in e["per_province"]:
		var p: Dictionary = e["per_province"][code]
		for k in ["tax", "strategic", "civil"]:
			realm[k] += int(p[k])
			if code in mine:
				crown[k] += int(p[k])
	assert_eq(e["realm"], realm)
	assert_eq(e["crown"], crown)
	assert_gt(int(realm["tax"]), int(crown["tax"]), "the realm is more than the crown's provinces")
	for k in ["tax", "strategic", "civil"]:
		assert_typeof(e["realm"][k], TYPE_INT, "%s is whole gold" % k)

func test_the_cache_recomputes_only_what_changed() -> void:
	RealmEconomy.realm(data, s)
	var n := RealmEconomy.compute_count
	assert_gt(n, 100, "every province of the realm was computed once")
	RealmEconomy.realm(data, s)
	assert_eq(RealmEconomy.compute_count, n, "a second read is a hit")
	s.day = 7
	RealmEconomy.realm(data, s)
	assert_eq(RealmEconomy.compute_count, n, "a day step is a hit")
	var cell := MapManors.manors_of_house(data, s, MapManors.crown(s), data.resolve_realm("player_realm"))[0]
	s.manor_buildings[str(cell)] = ["mill"]
	RealmEconomy.realm(data, s)
	assert_eq(RealmEconomy.compute_count, n + 1, "a building recomputes exactly its province")
	s.tick += 1
	RealmEconomy.realm(data, s)
	assert_gt(RealmEconomy.compute_count, n + 100, "a new month recomputes every province")

func test_the_day_buckets_spread_the_months_work() -> void:
	RealmEconomy.realm(data, s)
	s.tick += 1
	var total := 0
	for d in range(1, Calendar.DAYS_PER_TICK + 1):
		s.day = d
		total += RealmEconomy.step_day(data, s)
	assert_eq(total, RealmEconomy.realm(data, s)["per_province"].size(), "thirty buckets covered every province once")
	var n := RealmEconomy.compute_count
	RealmEconomy.realm(data, s)
	assert_eq(RealmEconomy.compute_count, n, "the month's end had nothing left to do")

func test_the_full_recompute_agrees_with_the_cache() -> void:
	RealmEconomy.realm(data, s)
	var cell := MapManors.manors_of_house(data, s, MapManors.crown(s), data.resolve_realm("player_realm"))[0]
	s.manor_buildings[str(cell)] = ["mill", "market"]
	WorldLedger.apply(data, s, "economy.provinces.%s.rural_population" % MapManors.province_of(data, cell), 500, "test", "test")
	RealmEconomy.realm(data, s)
	assert_eq(RealmEconomy.check_full(data, s), [], "no province differs")
```

- [ ] **Step 2: Run to see them fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_realm_economy.gd -gexit 2>&1 | grep -E "Passing|Failing|rror"`
Expected: failing (no `RealmEconomy`).

- [ ] **Step 3: Write RealmEconomy**

`scripts/engine/realm_economy.gd`:

```gdscript
class_name RealmEconomy
extends RefCounted
## The realm's economy from its manors (spec 2026-09-14 §4.4, §11): every
## manor's month kept COLUMNAR — three PackedInt32Array, tax / strategic /
## civil, one entry per manor, province-major (provinces by code, manors
## by cell id), so a province is a contiguous slice — with a KEY per
## province standing in for a dirty flag: the key strings together
## everything a line depends on (the tick, the tax levels, the province's
## two ledger figures, and its manors' owner, buildings and focus), so a
## province is recomputed exactly when one of those moved and never
## otherwise, and nothing can forget to mark it (architecture RK-1). The
## realm's answer is cached on a signature of the same state, so a day
## step and a top-bar refresh are one string compare.
##
## The month's work is spread over its days: step_day recomputes the
## provinces of the day's bucket (province index mod 30) whose key went
## stale, so the month's end has almost nothing left (architecture R-5;
## the bucket count is the calendar's, in the save by construction).

static var _repo_id := 0
static var _cells := PackedInt32Array()      # i -> cell id
static var _index: Dictionary = {}            # cell id -> i
static var _codes := PackedStringArray()      # province index -> code
static var _range: Dictionary = {}            # code -> [start, end)
static var _tax := PackedInt32Array()
static var _strategic := PackedInt32Array()
static var _civil := PackedInt32Array()
static var _keys: Dictionary = {}             # code -> key computed under
static var _sums: Dictionary = {}             # code -> {tax, strategic, civil}
static var _realm_sig := ""
static var _realm: Dictionary = {}
## Provinces recomputed since forget(). Test seam.
static var compute_count := 0

static func forget() -> void:
	_repo_id = 0
	_cells = PackedInt32Array()
	_index = {}
	_codes = PackedStringArray()
	_range = {}
	_tax = PackedInt32Array()
	_strategic = PackedInt32Array()
	_civil = PackedInt32Array()
	_keys = {}
	_sums = {}
	_realm_sig = ""
	_realm = {}
	compute_count = 0

## Index the pack's manors, province-major. Once per repository.
static func setup(repo: DataRepository) -> void:
	if _repo_id == repo.get_instance_id() and not _cells.is_empty():
		return
	forget()
	_repo_id = repo.get_instance_id()
	var codes: Array = []
	for code: String in repo.provinces:
		if not MapManors.manors_of_province(repo, code).is_empty():
			codes.append(code)
	codes.sort()
	for code: String in codes:
		var start := _cells.size()
		for id: int in MapManors.manors_of_province(repo, code):
			_index[id] = _cells.size()
			_cells.append(id)
		_range[code] = [start, _cells.size()]
		_codes.append(code)
	_tax.resize(_cells.size())
	_strategic.resize(_cells.size())
	_civil.resize(_cells.size())

static func _figure(repo: DataRepository, state: GameState, path: String) -> int:
	var v: Variant = WorldLedger.value_of(repo, state, path)
	return int(roundf(float(v))) if v != null else 0

## Everything a province's lines depend on, as one string.
static func province_key(repo: DataRepository, state: GameState, code: String) -> String:
	var parts := PackedStringArray()
	parts.append(str(state.tick))
	parts.append(str(int(state.metrics.get("tax_rate", 0))))
	parts.append(str(int(state.metrics.get("tariff_rate", 0))))
	parts.append(str(_figure(repo, state, "economy.provinces.%s.rural_population" % code)))
	parts.append(str(_figure(repo, state, "economy.provinces.%s.urban_population" % code)))
	for id: int in MapManors.manors_of_province(repo, code):
		var k := str(id)
		if state.manor_owner.has(k):
			parts.append("o%s=%s" % [k, str(state.manor_owner[k])])
		if state.manor_buildings.has(k):
			parts.append("b%s=%s" % [k, str(state.manor_buildings[k])])
		if state.manor_focus.has(k):
			parts.append("f%s=%s" % [k, str(state.manor_focus[k])])
	return "|".join(parts)

static func recompute_province(repo: DataRepository, state: GameState, code: String) -> void:
	setup(repo)
	compute_count += 1
	var r: Array = _range[code]
	var tax := 0
	var strategic := 0
	var civil := 0
	for i in range(int(r[0]), int(r[1])):
		var line := ManorEconomy.line_of(repo, state, _cells[i], state.tick)
		_tax[i] = int(line["tax"])
		_strategic[i] = int(line["strategic"])
		_civil[i] = int(line["civil"])
		tax += _tax[i]
		strategic += _strategic[i]
		civil += _civil[i]
	_sums[code] = {"tax": tax, "strategic": strategic, "civil": civil}
	_keys[code] = province_key(repo, state, code)

## A province's month, current: recomputed when its key moved.
static func province(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	setup(repo)
	if not _range.has(code):
		return {"tax": 0, "strategic": 0, "civil": 0}
	if String(_keys.get(code, "")) != province_key(repo, state, code):
		recompute_province(repo, state, code)
	return _sums[code]

## A manor's cached line, current.
static func line_of(repo: DataRepository, state: GameState, cell: int) -> Dictionary:
	province(repo, state, MapManors.province_of(repo, cell))
	if not _index.has(cell):
		return {"tax": 0, "strategic": 0, "civil": 0}
	var i: int = _index[cell]
	return {"tax": _tax[i], "strategic": _strategic[i], "civil": _civil[i]}

## What the realm's answer depends on, cheaply: the dictionaries that hold
## only what moved hash in C++.
static func realm_signature(state: GameState) -> String:
	return "%d|%d|%d|%d|%d|%d|%d" % [state.tick, state.manor_owner.hash(),
		state.manor_buildings.hash(), state.manor_focus.hash(), state.world.hash(),
		int(state.metrics.get("tax_rate", 0)), int(state.metrics.get("tariff_rate", 0))]

## {realm, crown, per_province}: the player's realm's provinces (live
## ownership), the crown's controlled ones summed apart.
static func realm(repo: DataRepository, state: GameState) -> Dictionary:
	setup(repo)
	var sig := realm_signature(state)
	if sig == _realm_sig and not _realm.is_empty():
		return _realm
	var mine := MapManors.controlled_provinces(repo, state)
	var total := {"tax": 0, "strategic": 0, "civil": 0}
	var crown := {"tax": 0, "strategic": 0, "civil": 0}
	var per: Dictionary = {}
	var codes: Array = Array(MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm")))
	codes.sort()
	for code: String in codes:
		if not _range.has(code):
			continue
		var p := province(repo, state, code)
		per[code] = p
		for k in ["tax", "strategic", "civil"]:
			total[k] += int(p[k])
			if code in mine:
				crown[k] += int(p[k])
	_realm = {"realm": total, "crown": crown, "per_province": per}
	_realm_sig = sig
	return _realm

## The day's bucket: recompute the stale provinces whose index falls on
## today. Returns how many were recomputed.
static func step_day(repo: DataRepository, state: GameState) -> int:
	setup(repo)
	var n := 0
	var bucket := (state.day - 1) % Calendar.DAYS_PER_TICK
	for pi in _codes.size():
		if pi % Calendar.DAYS_PER_TICK != bucket:
			continue
		var code := _codes[pi]
		if String(_keys.get(code, "")) != province_key(repo, state, code):
			recompute_province(repo, state, code)
			n += 1
	return n

## Every province from scratch, no cache: code -> {tax, strategic, civil}.
static func recompute_all(repo: DataRepository, state: GameState) -> Dictionary:
	setup(repo)
	var out: Dictionary = {}
	for code in _codes:
		var r: Array = _range[code]
		var sum := {"tax": 0, "strategic": 0, "civil": 0}
		for i in range(int(r[0]), int(r[1])):
			var line := ManorEconomy.line_of(repo, state, _cells[i], state.tick)
			sum["tax"] += int(line["tax"])
			sum["strategic"] += int(line["strategic"])
			sum["civil"] += int(line["civil"])
		out[code] = sum
	return out

## The provinces whose cached sum differs from a fresh one:
## [{province, cached, fresh}]. Empty is the only right answer.
static func check_full(repo: DataRepository, state: GameState) -> Array:
	var fresh := recompute_all(repo, state)
	var out: Array = []
	for code in _codes:
		var cached := province(repo, state, code)
		if cached != fresh[code]:
			out.append({"province": code, "cached": cached, "fresh": fresh[code]})
	return out

## The one number the military reads as the army's capacity and reach.
static func strategic_stock(state: GameState) -> int:
	return int(state.metrics.get("strategic", 0))
```

- [ ] **Step 4: Reset the cache on a pack load**

In `scripts/engine/data_repository.gd` `load_map`, after `MapObjects.forget_decor()` add:

```gdscript
	RealmEconomy.forget()
	ManorEconomy.forget()
```

- [ ] **Step 5: Run the tests**

Expected: 5 passing. If `test_the_cache_recomputes_only_what_changed` counts more than one after the building: the province's key already contained the change — check that no other state moved; if `test_the_day_buckets_...` covers fewer provinces than `per_province`: `_codes` includes provinces outside the player's realm (all provinces with manors) — the bucket walk touches all of them, the realm only its own: change the assertion to `assert_gt(total, 0)` and `assert_eq(total, RealmEconomy._codes.size())`.

- [ ] **Step 6: Commit**

```bash
git add scripts/engine/realm_economy.gd scripts/engine/data_repository.gd tests/engine/test_realm_economy.gd
git commit -m "feat(economy): the realm's columnar cache — province keys, day buckets, a full check"
```

---

### Task 6: The month's settlement and the pools

**Files:**
- Modify: `scripts/engine/tick_engine.gd:19-21` (day step), `:23-51` (advance), `:53-98` (`_drift`)
- Modify: `scripts/engine/game_state.gd:44-60` (`new_campaign` metrics), `scripts/engine/world_ledger.gd:243-254` (`seed_metrics`)
- Modify: `data/world_schema.csv`, `data/metric_polarity.csv`, `data/council_seats.csv`, `data/balance.csv`
- Modify: `tests/engine/test_tick_engine.gd`, `tests/engine/test_world_tables.gd` (if it pins the schema row count)

**Interfaces:**
- Consumes: `RealmEconomy.realm/step_day`, `data.seats[seat]["salary_gold"]`.
- Produces: `state.metrics["strategic"]` (int gold), `state.metrics["grain"]` (the CIVIL pool, int gold); `TickEngine._settle_economy(state, r)`; ledger lines named "taxes of the crown's provinces", "the crown's share of the realm's taxes", "the crown's strategic goods", "the crown's share of the realm's strategic goods", "the crown's civil goods", "the crown's share of the realm's civil goods", "ministers' salaries", "the court's ration", "the harvest comes in".

- [ ] **Step 1: Write the failing tests**

Replace `test_tax_income_formula` and `test_grain_seasonal` in `tests/engine/test_tick_engine.gd` with:

```gdscript
## The month's settlement (spec §5): the crown's provinces in full, a share
## of the rest, less salaries and the ration — all whole gold, all from
## RealmEconomy's sums for the month that just ended.
func test_the_months_end_settles_the_three_pools() -> void:
	var s := GameState.new_campaign(data, 42)
	var e := RealmEconomy.realm(data, s)
	var share := data.bal("crown_share_permille") / 1000.0
	var expect := {}
	for k in ["tax", "strategic", "civil"]:
		var own := int(e["crown"][k])
		expect[k] = own + int(roundf(share * float(int(e["realm"][k]) - own)))
	var salaries := 0
	for seat: String in s.council:
		salaries += int(float(data.seats[seat].get("salary_gold", 0)))
	assert_gt(salaries, 0, "ministers are paid")
	var people := 0
	for code: String in MapManors.controlled_provinces(data, s):
		people += int(roundf(float(WorldLedger.value_of(data, s, "economy.provinces.%s.rural_population" % code))))
		people += int(roundf(float(WorldLedger.value_of(data, s, "economy.provinces.%s.urban_population" % code))))
	var ration := int(roundf(float(people) / 1000.0 * data.bal("ration_gold_per_1000")))
	var t0 := int(s.metrics["treasury"])
	var st0 := int(s.metrics["strategic"])
	var cv0 := int(s.metrics["grain"])
	var built := MapManors.crown_building_effects(data, s)
	s.tick = 0  # spring: no harvest
	var r := engine.advance(s)
	assert_eq(int(s.metrics["treasury"]), t0 + expect["tax"] - salaries + int(built["treasury"]))
	assert_eq(int(s.metrics["strategic"]), st0 + expect["strategic"])
	assert_eq(int(s.metrics["grain"]), cv0 + expect["civil"] - ration + int(built["grain"]))
	assert_eq(int(s.metrics["tax_income"]), expect["tax"])
	var reasons: Array = []
	for d in r.metric_deltas:
		reasons.append(String(d["reason"]))
	for want in ["taxes of the crown's provinces", "the crown's share of the realm's taxes",
			"ministers' salaries", "the court's ration"]:
		assert_true(want in reasons, want)
	for m in ["treasury", "strategic", "grain"]:
		assert_eq(s.metrics[m], float(int(s.metrics[m])), "%s stays whole" % m)

func test_the_harvest_is_civil_goods_in_autumn() -> void:
	var s := GameState.new_campaign(data, 42)
	s.tick = 6  # advance() settles month 6 and makes it 7: autumn
	var before := int(s.metrics["grain"])
	var r := engine.advance(s)
	var harvest := 0
	for d in r.metric_deltas:
		if String(d["reason"]) == "the harvest comes in":
			harvest = int(d["delta"])
	assert_gt(harvest, 0)
	assert_gt(int(s.metrics["grain"]), before, "the harvest outweighs the ration")

func test_the_day_step_warms_a_bucket() -> void:
	var s := GameState.new_campaign(data, 42)
	RealmEconomy.forget()
	engine.advance_day(s)
	assert_gt(RealmEconomy.compute_count, 0, "a day computes its bucket")
	assert_lt(RealmEconomy.compute_count, 20, "not the realm")

func test_the_pools_start_with_months_of_the_crowns_own_production() -> void:
	var s := GameState.new_campaign(data, 42)
	var e := RealmEconomy.realm(data, s)
	assert_eq(int(s.metrics["strategic"]), int(e["crown"]["strategic"]) * int(data.bal("start_strategic_months")))
	assert_eq(int(s.metrics["grain"]), int(e["crown"]["civil"]) * int(data.bal("start_civil_months")))
```

- [ ] **Step 2: Run to see them fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_tick_engine.gd -gexit 2>&1 | grep -E "Passing|Failing|rror"`
Expected: the four new tests fail.

- [ ] **Step 3: The data**

`data/balance.csv`: remove the rows `court_upkeep`, `tax_income_factor`, `tariff_income_factor`, `harvest_gain`, `grain_drain`, `grain_drain_winter`, `grain_cap_base`, `start_grain`, `manor_rent_per_1000`; append:

```csv
crown_share_permille,200,"ECONOMY (spec §5): the crown's share, per mille, of the tax, strategic and civil goods of the realm's provinces it does NOT control; its own provinces pay in full"
ration_gold_per_1000,1,"ECONOMY: civil goods (gold) the court's provinces eat a month per 1 000 people; halved under the ration order"
harvest_civil_per_1000,6,"ECONOMY: civil goods (gold) the autumn harvest brings per 1 000 people of the crown's provinces, on top of the month's goods"
start_strategic_months,2,"ECONOMY: the strategic stock at the start = the crown's monthly strategic goods x this"
start_civil_months,3,"ECONOMY: the civil stock at the start = the crown's monthly civil goods x this"
economy_check_full,0,"ECONOMY (architecture RK-1): 1 = after every settlement recompute every province from scratch and push_error on any that differs from the cache (debug only; slow)"
```

`data/council_seats.csv`: add a column `salary_gold` after `vacancy_penalty` with 8 for the chancellor, 6 for every other seat (open the file, add the header cell and one value per row).

`data/world_schema.csv`: change the `metrics.grain` row to `metrics.grain,int,0,100000000,,1,30,,,Civil goods,"the CIVIL pool in whole gold (spec §5): food, timber, cloth, wares; the harvest fills it, the court eats from it, building spends it"` and the `metrics.treasury` row's type to `int`; add after it:

```csv
metrics.strategic,int,0,100000000,,1,30,,,Strategic goods,"the STRATEGIC pool in whole gold (spec §5): iron, horses, arms, ships — the army's capacity and reach"
metrics.civil,int,0,100000000,,1,30,metrics.grain,,Civil goods,the schema's name for the civil pool; the metric key stays grain
economy.kingdoms.player_realm.strategic,int,0,100000000,,1,30,metrics.strategic,,Strategic goods,
economy.kingdoms.player_realm.civil,int,0,100000000,,1,30,metrics.grain,,Civil goods,
```
Remove the `metrics.grain_capacity_bonus` row. `data/metric_polarity.csv`: add `strategic,1,` and remove `manor_rents,1,...`.

- [ ] **Step 4: The state and the seeding**

In `scripts/engine/game_state.gd` `new_campaign`, the metrics dictionary becomes:

```gdscript
	s.metrics = {
		"treasury": data.bal("start_treasury"),
		"strategic": 0.0,
		"grain": 0.0,  # the CIVIL pool (spec 2026-09-14 §5); the key stays for its readers
		"tax_rate": data.bal("start_tax_rate"),
		"tariff_rate": data.bal("start_tariff_rate"),
		"tax_income": 0.0,
		"admin_capacity": data.bal("admin_base"),
		"legitimacy": data.bal("start_metric_default"),
		"unrest": 0.0,
		"army_quality": data.bal("start_metric_default"),
		"church_opinion": data.bal("start_metric_default"),
		"peasant_contentment": data.bal("start_metric_default"),
		"road_income_bonus": 0.0,
		"grain_ration": 0.0,
	}
```

In `scripts/engine/world_ledger.gd` `seed_metrics`, after the tariff line add:

```gdscript
	# The pools start with months of the crown's own production (spec §5).
	var e := RealmEconomy.realm(data, state)
	state.metrics["strategic"] = float(int(e["crown"]["strategic"]) * int(data.bal("start_strategic_months")))
	state.metrics["grain"] = float(int(e["crown"]["civil"]) * int(data.bal("start_civil_months")))
```

Then grep for the removed keys and fix each reader: `grep -rn "grain_capacity_bonus\|grain_cap_base\|granary_capacity_gain\|manor_rents\|court_upkeep\|harvest_gain\|grain_drain\|start_grain\|crown_rents\|manor_rent_per_1000" scripts tests data`. `ActionSystem` `BUILD_ECONOMIC granary` (line ~195) applied `grain_capacity_bonus`: make it apply `+data.bal("granary_civil_gain")` to `"grain"` with reason "a royal granary stocked" and add `granary_civil_gain,60,"ECONOMY: civil goods a new royal granary is stocked with"` to balance. `MapManors.crown_rents` and `rent_of`: make `rent_of` return `float(ManorEconomy.line_of(repo, state, cell_id, state.tick)["tax"])` (its doc: "the manor's month of tax, for the card"), delete `crown_rents`, and delete the `_set_metric(... "manor_rents" ...)` / rent lines from the tick (next step). The realm dashboard / info screen read `m["grain"]` and keep working.

- [ ] **Step 5: The tick**

In `scripts/engine/tick_engine.gd` replace `advance_day` and the top of `advance`, and replace `_drift`'s income and grain parts:

```gdscript
func advance_day(state: GameState) -> Array:
	state.day = mini(state.day + 1, Calendar.DAYS_PER_TICK)
	var done := MapManors.advance_works(data, state)
	# The month's economy is computed a bucket a day (spec §11.2).
	RealmEconomy.step_day(data, state)
	return done

func advance(state: GameState) -> TickReport:
	var r := TickReport.new()
	# The month that just ended is settled BEFORE the tick moves: its lines
	# are the month's own (growth of tick t), and the ledger reasons carry
	# its tick.
	_settle_economy(state, r)
	state.tick += 1
	state.day = 1
	r.finished_works = MapManors.advance_works(data, state)
	... (the rest of advance unchanged, from `r.tick = state.tick` on, with `_drift(state, r)` still called)

## The month's settlement (spec §5): the crown's provinces in full, the
## crown's share of the rest, less the ministers' salaries and the court's
## ration; the harvest in autumn. Whole gold, from RealmEconomy's sums.
func _settle_economy(state: GameState, r: TickReport) -> void:
	var m := state.metrics
	var e := RealmEconomy.realm(data, state)
	var share := data.bal("crown_share_permille") / 1000.0
	var own_tax := int(e["crown"]["tax"])
	var share_tax := int(roundf(share * float(int(e["realm"]["tax"]) - own_tax)))
	_apply(r, m, "treasury", float(own_tax), "taxes of the crown's provinces")
	_apply(r, m, "treasury", float(share_tax), "the crown's share of the realm's taxes")
	_set_metric(r, m, "tax_income", float(own_tax + share_tax), "taxes collected this month")
	var own_st := int(e["crown"]["strategic"])
	_apply(r, m, "strategic", float(own_st), "the crown's strategic goods")
	_apply(r, m, "strategic", float(int(roundf(share * float(int(e["realm"]["strategic"]) - own_st)))),
		"the crown's share of the realm's strategic goods")
	var own_cv := int(e["crown"]["civil"])
	_apply(r, m, "grain", float(own_cv), "the crown's civil goods")
	_apply(r, m, "grain", float(int(roundf(share * float(int(e["realm"]["civil"]) - own_cv)))),
		"the crown's share of the realm's civil goods")
	var salaries := 0
	for seat: String in state.council:
		salaries += int(float((data.seats.get(seat, {}) as Dictionary).get("salary_gold", 0)))
	_apply(r, m, "treasury", float(-salaries), "ministers' salaries")
	var people := 0
	for code: String in MapManors.controlled_provinces(data, state):
		people += RealmEconomy._figure(data, state, "economy.provinces.%s.rural_population" % code)
		people += RealmEconomy._figure(data, state, "economy.provinces.%s.urban_population" % code)
	var ration := int(roundf(float(people) / 1000.0 * data.bal("ration_gold_per_1000")))
	if m.get("grain_ration", 0.0) > 0.0:
		ration = ration / 2
	_apply(r, m, "grain", float(-ration), "the court's ration")
	if Calendar.season_name(state.tick + 1) == "Autumn":
		_apply(r, m, "grain", float(int(roundf(float(people) / 1000.0 * data.bal("harvest_civil_per_1000")))),
			"the harvest comes in")
	var built := MapManors.crown_building_effects(data, state)
	_apply(r, m, "treasury", float(int(built["treasury"])), "tolls and rents of the crown's buildings")
	_apply(r, m, "grain", float(int(built["grain"])), "the crown's mills and granaries")
	m["grain"] = maxf(m["grain"], 0.0)
	if data.bal("economy_check_full") > 0.0:
		var bad := RealmEconomy.check_full(data, state)
		if not bad.is_empty():
			push_error("economy_check_full: %d province(s) differ from the cache: %s" % [bad.size(), str(bad[0])])
```

In `_drift`, delete everything from `var income: float = ...` through `m["grain"] = clampf(...)` EXCEPT the three building lines for church_opinion, peasant_contentment and unrest (they stay), i.e. `_drift` keeps: the admin capacity block, then

```gdscript
	var built := MapManors.crown_building_effects(data, state)
	_apply(r, m, "church_opinion", float(built["church_opinion"]), "the crown's chapels")
	_apply(r, m, "peasant_contentment", float(built["peasant_contentment"]), "lords in residence")
	_apply(r, m, "unrest", float(built["unrest"]), "the crown's walls")
```
and the unrest/contentment/legitimacy/church/army drift that follows. Note the harvest uses `season_name(state.tick + 1)` because the settlement runs before the increment and the harvest belongs to the month beginning.

- [ ] **Step 6: Run the tick tests, then the suite**

Run the tick test file; expected: all passing. Then `./run_tests.sh 2>&1 | tail -20`; fix readers of removed keys the grep found (concern thresholds for grain are re-tuned in Task 10; a test asserting `court_upkeep` or `harvest_gain` follows the new lines).

- [ ] **Step 7: Commit**

```bash
git add scripts/engine/tick_engine.gd scripts/engine/game_state.gd scripts/engine/world_ledger.gd scripts/engine/map_manors.gd scripts/engine/action_system.gd data/ tests/
git commit -m "feat(economy): the month's end settles treasury, strategic and civil from the manors"
```

---

### Task 7: Buying and selling goods

**Files:**
- Modify: `data/policy_actions_court_additions.csv`, `data/action_signatures.csv`, `data/order_costs.csv`, `data/balance.csv`
- Modify: `scripts/engine/action_system.gd` (`validate` match, `execute` match)
- Modify: `tests/engine/test_action_system.gd` (append)

**Interfaces:**
- Produces: actions `GOODS_BUY` and `GOODS_SELL` with params `{pool: "strategic"|"civil", gold: int}`; `ActionSystem.pool_metric(pool: String) -> String` (`"strategic"` → `"strategic"`, `"civil"` → `"grain"`).

- [ ] **Step 1: Write the failing tests**

Append to `tests/engine/test_action_system.gd`:

```gdscript
## GOODS_BUY / GOODS_SELL (spec §5): the treasury buys a pool's goods at
## the spread and sells them under it, whole gold both ways.
func test_buying_goods_costs_the_spread_and_selling_pays_under_it() -> void:
	var spread := data.bal("goods_trade_spread")
	s.metrics["treasury"] = 1000.0
	s.metrics["strategic"] = 50.0
	s.metrics["grain"] = 50.0
	var out := sys.execute(ActionRequest.make("GOODS_BUY", {"pool": "strategic", "gold": 100}), s)
	assert_true(out["ok"])
	assert_eq(int(s.metrics["strategic"]), 150)
	assert_eq(int(s.metrics["treasury"]), 1000 - int(roundf(100.0 * (1.0 + spread))))
	var t := int(s.metrics["treasury"])
	out = sys.execute(ActionRequest.make("GOODS_SELL", {"pool": "civil", "gold": 40}), s)
	assert_true(out["ok"])
	assert_eq(int(s.metrics["grain"]), 10)
	assert_eq(int(s.metrics["treasury"]), t + int(roundf(40.0 * (1.0 - spread))))

func test_goods_orders_are_validated() -> void:
	s.metrics["treasury"] = 10.0
	s.metrics["grain"] = 5.0
	assert_string_contains(sys.validate(ActionRequest.make("GOODS_BUY", {"pool": "wine", "gold": 10}), s), "pool")
	assert_string_contains(sys.validate(ActionRequest.make("GOODS_BUY", {"pool": "civil", "gold": 0}), s), "gold")
	assert_string_contains(sys.validate(ActionRequest.make("GOODS_BUY", {"pool": "civil", "gold": 100}), s), "afford")
	assert_string_contains(sys.validate(ActionRequest.make("GOODS_SELL", {"pool": "civil", "gold": 100}), s), "only 5")
	assert_eq(sys.validate(ActionRequest.make("GOODS_SELL", {"pool": "civil", "gold": 5}), s), "")
```

- [ ] **Step 2: Run to see them fail**

Expected: "Unknown action: GOODS_BUY".

- [ ] **Step 3: The data rows**

`data/balance.csv` append: `goods_trade_spread,0.25,"ECONOMY (spec §5): the factor's cut — buying a pool's goods costs gold x (1 + this), selling yields gold x (1 - this)"`.

`data/policy_actions_court_additions.csv` append (same columns as the MANOR rows):

```csv
GOODS_BUY,economy,Buy goods,none,0.2,none,0,0,,goods_buy,3,no,no,"spec 2026-09-14 §5. params: pool (strategic|civil), gold. The treasury buys that much of the pool's goods at goods_trade_spread over"
GOODS_SELL,economy,Sell goods,none,0.2,none,0,0,,goods_sell,3,no,no,"params: pool (strategic|civil), gold. The treasury sells that much of the pool's goods at goods_trade_spread under"
```

`data/action_signatures.csv` append: `GOODS_BUY,,0,0,0,0,0,` and `GOODS_SELL,,0,0,0,0,0,` (the trade is neither centralist nor martial).
`data/order_costs.csv` append: `GOODS_BUY,gold:-1:the factor's fee,1,the spread is the cost; this is the paperwork` and `GOODS_SELL,gold:-1:the factor's fee,1,`.

- [ ] **Step 4: The handlers**

In `scripts/engine/action_system.gd` add after `manor_of`:

```gdscript
## The metric that holds a pool: strategic -> strategic, civil -> grain
## (the civil pool's key, kept for its readers; spec §5).
static func pool_metric(pool: String) -> String:
	return "strategic" if pool == "strategic" else "grain"
```

In `validate`'s `match`, add:

```gdscript
		"GOODS_BUY", "GOODS_SELL":
			var pool := String(req.params.get("pool", ""))
			if not pool in ["strategic", "civil"]:
				return "pool must be strategic|civil"
			var gold := int(req.params.get("gold", 0))
			if gold <= 0:
				return "gold must be a whole number above zero"
			if req.action_code == "GOODS_BUY":
				var price := int(roundf(float(gold) * (1.0 + data.bal("goods_trade_spread"))))
				if state.metrics["treasury"] < price + needs:
					return "Cannot afford %d gold of %s goods (%d with the factor's cut)" % [gold, pool, price]
			else:
				var have := int(state.metrics.get(pool_metric(pool), 0.0))
				if have < gold:
					return "The %s stock holds only %d gold of goods" % [pool, have]
```

In `execute`'s `match`, add:

```gdscript
		"GOODS_BUY":
			var pool := String(req.params["pool"])
			var gold := int(req.params["gold"])
			var price := int(roundf(float(gold) * (1.0 + data.bal("goods_trade_spread"))))
			_apply(state, effects, "treasury", float(-price), "bought %d gold of %s goods" % [gold, pool])
			_apply(state, effects, pool_metric(pool), float(gold), "%s goods bought" % pool)
		"GOODS_SELL":
			var pool := String(req.params["pool"])
			var gold := int(req.params["gold"])
			var paid := int(roundf(float(gold) * (1.0 - data.bal("goods_trade_spread"))))
			_apply(state, effects, pool_metric(pool), float(-gold), "%s goods sold" % pool)
			_apply(state, effects, "treasury", float(paid), "sold %d gold of %s goods" % [gold, pool])
```

- [ ] **Step 5: Run the action tests**

Expected: passing. `test_goods_orders_are_validated`'s "afford" case: 100 × 1.25 = 125 > 10 + the cost row's 1.

- [ ] **Step 6: Commit**

```bash
git add data/ scripts/engine/action_system.gd tests/engine/test_action_system.gd
git commit -m "feat(economy): GOODS_BUY and GOODS_SELL trade the pools at a spread"
```

---

### Task 8: Building spends civil goods, gold rushes it; military orders spend strategic goods

**Files:**
- Modify: `data/manor_buildings.csv` (`civil_cost` column), `data/balance.csv` (`build_rush_gold_per_day`), `data/policy_actions_court_additions.csv`, `data/action_signatures.csv`, `data/order_costs.csv` (`MANOR_RUSH`; strategic costs on `LEVY_RAISE`)
- Modify: `scripts/engine/action_system.gd` (`MANOR_BUILD` validate/execute; `MANOR_RUSH`), `scripts/engine/map_manors.gd` (`rush_work`)
- Modify: `tests/engine/test_action_system.gd`, `tests/engine/test_map_manors.gd`

**Interfaces:**
- Produces: `MapManors.rush_work(repo, state, cell_id: int, building_code: String, days: int, reason: String) -> int` (days actually cut); action `MANOR_RUSH {manor, building, days}`.

- [ ] **Step 1: Write the failing tests**

Append to `tests/engine/test_map_manors.gd`:

```gdscript
## Rushing (spec §5): gold takes days off a work, never below done.
func test_rushing_cuts_days_off_a_work() -> void:
	var r := _repo()
	r.manor_buildings["mill"]["build_days"] = "30"
	var s := _state()
	s.tick = 1
	s.day = 1
	assert_true(MapManors.start_work(r, s, 1, "mill", "test"))
	assert_eq(MapManors.work_days_left(s, 1, "mill"), 30)
	assert_eq(MapManors.rush_work(r, s, 1, "mill", 10, "test: gold"), 10)
	assert_eq(MapManors.work_days_left(s, 1, "mill"), 20)
	assert_eq(MapManors.rush_work(r, s, 1, "mill", 50, "test: gold"), 20, "only what is left")
	assert_eq(MapManors.work_days_left(s, 1, "mill"), 0)
	assert_eq(MapManors.rush_work(r, s, 1, "chapel", 5, "test"), 0, "no such work")
```

Append to `tests/engine/test_action_system.gd`:

```gdscript
## MANOR_BUILD pays civil goods, not gold (spec §5); MANOR_RUSH pays gold a day.
func test_building_spends_civil_goods_and_rushing_spends_gold() -> void:
	var cell := _crown_manor()
	var civil := int(float(data.manor_buildings["palisade"]["civil_cost"]))
	assert_gt(civil, 0)
	s.metrics["grain"] = float(civil - 1)
	s.metrics["treasury"] = 1000.0
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": "palisade"}), s), "civil goods")
	s.metrics["grain"] = float(civil + 10)
	var t := int(s.metrics["treasury"])
	assert_true(sys.execute(ActionRequest.make("MANOR_BUILD", {"manor": cell, "building": "palisade"}), s)["ok"])
	assert_eq(int(s.metrics["grain"]), 10)
	assert_eq(int(s.metrics["treasury"]), t - int(OrderCosts.gold_of(data, "MANOR_BUILD")), "only the surveyor")
	var per_day := int(data.bal("build_rush_gold_per_day"))
	t = int(s.metrics["treasury"])
	var left := MapManors.work_days_left(s, cell, "palisade")
	assert_true(sys.execute(ActionRequest.make("MANOR_RUSH", {"manor": cell, "building": "palisade", "days": 5}), s)["ok"])
	assert_eq(MapManors.work_days_left(s, cell, "palisade"), left - 5)
	assert_eq(int(s.metrics["treasury"]), t - 5 * per_day - int(OrderCosts.gold_of(data, "MANOR_RUSH")))
	assert_string_contains(sys.validate(ActionRequest.make("MANOR_RUSH", {"manor": cell, "building": "chapel", "days": 1}), s), "no work")

## The levy marches on strategic goods (spec §5): its cost row charges them.
func test_raising_levies_spends_strategic_goods() -> void:
	s.metrics["treasury"] = 1000.0
	s.metrics["strategic"] = 100.0
	var out := sys.execute(ActionRequest.make("LEVY_RAISE"), s)
	assert_true(out["ok"])
	assert_lt(int(s.metrics["strategic"]), 100, "the baggage train was paid for")
```

- [ ] **Step 2: Run to see them fail**

Expected: `rush_work` missing; `civil_cost` missing; MANOR_RUSH unknown; strategic unchanged.

- [ ] **Step 3: The data**

`data/manor_buildings.csv`: add a column `civil_cost` after `cost_gold`: manor_house 40, mill 25, granary 20, chapel 15, palisade 30, market 30; change the note of `cost_gold` in `manor_house`'s note to say "cost_gold is now what a full rush would cost per build_rush_gold_per_day; civil_cost is the civil goods (gold) the work takes (spec 2026-09-14 §5)".
`data/balance.csv` append: `build_rush_gold_per_day,3,"ECONOMY (spec §5): gold that takes one day off a work on a crown manor (MANOR_RUSH)"`.
`data/policy_actions_court_additions.csv` append: `MANOR_RUSH,economy,Hurry a work on a manor,none,0.2,none,0,0,,manor_rush,3,no,no,"params: manor, building, days. Pays build_rush_gold_per_day a day to cut days off a work in progress on a crown manor"`.
`data/action_signatures.csv` append: `MANOR_RUSH,,10,0,0,0,0,the crown hurries its own works`.
`data/order_costs.csv`: append `MANOR_RUSH,gold:-1:the foreman's bonus,1,`; change the `LEVY_RAISE` row's `cost` to add `;metric:strategic:-20:the baggage train of the levy` after its existing op(s) and set its `always` to `1` (if no `LEVY_RAISE` row exists, add `LEVY_RAISE,metric:strategic:-20:the baggage train of the levy,1,"the levy marches on strategic goods (spec §5)"`).

- [ ] **Step 4: rush_work**

In `scripts/engine/map_manors.gd` after `work_progress` add:

```gdscript
## Cut `days` off a work in progress (spec 2026-09-14 §5: gold hurries the
## masons), never below done. Returns the days actually cut; 0 for no
## such work or an empty reason. Logs into manor_log with a "rushed" field.
static func rush_work(repo: DataRepository, state: GameState, cell_id: int, building_code: String,
		days: int, reason: String) -> int:
	if days <= 0 or reason.strip_edges() == "":
		return 0
	for w: Dictionary in works_of(state, cell_id):
		if String(w["building"]) != building_code:
			continue
		var left := maxi(int(w["start"]) + int(w["days"]) - state.absolute_day(), 0)
		var cut := mini(days, left)
		if cut <= 0:
			return 0
		w["days"] = int(w["days"]) - cut
		state.manor_log.append({"tick": state.tick, "cell": cell_id, "building": building_code,
			"rushed": cut, "reason": reason})
		return cut
	return 0
```

- [ ] **Step 5: The actions**

In `scripts/engine/action_system.gd`: add `"MANOR_RUSH"` to the manor list in `validate`'s match (`"MANOR_BUY", "MANOR_SELL", "MANOR_BUILD", "MANOR_SEIZE", "MANOR_FOCUS", "MANOR_DEMOLISH", "MANOR_RUSH":`). In `_validate_manor`'s match, in the `"MANOR_BUILD"` branch add after its existing checks:

```gdscript
			var civil := int(float(data.manor_buildings[String(req.params.get("building", ""))].get("civil_cost", 0)))
			if int(state.metrics.get("grain", 0.0)) < civil:
				return "Not enough civil goods for a %s at %s (%d needed)" % [
					String(data.manor_buildings[String(req.params.get("building", ""))]["label"]).to_lower(), label, civil]
```
(place it after the branch's check that the building exists and the manor is the crown's; read the branch first). Add a branch:

```gdscript
		"MANOR_RUSH":
			if not crowns:
				return "%s is not the crown's" % label
			var building := String(req.params.get("building", ""))
			if MapManors.work_days_left(state, cell, building) < 0:
				return "There is no work on a %s at %s" % [building, label]
			var days := int(req.params.get("days", 0))
			if days <= 0:
				return "days must be a whole number above zero"
			var price := days * int(data.bal("build_rush_gold_per_day"))
			if state.metrics["treasury"] < price + needs:
				return "Cannot afford to hurry %s by %d days (%d gold)" % [label, days, price]
```

In `execute`'s `"MANOR_BUILD"` branch replace the treasury line with:

```gdscript
			_apply(state, effects, "grain", -float(int(float(row_b.get("civil_cost", 0)))),
				"timber and stone for a %s at %s" % [String(row_b["label"]).to_lower(), label])
```
and add:

```gdscript
		"MANOR_RUSH":
			var cell := manor_of(req)
			var building := String(req.params["building"])
			var days := int(req.params["days"])
			var label := MapManors.label_of(data, cell)
			var cut := MapManors.rush_work(data, state, cell, building, days, "hurried by the crown")
			_apply(state, effects, "treasury", -float(cut * int(data.bal("build_rush_gold_per_day"))),
				"hurried the %s at %s by %d days" % [building, label, cut])
			effects.append({"metric": "manor", "delta": 0.0,
				"reason": "the %s at %s is %d days nearer done" % [building, label, cut]})
```

The `LEVY_RAISE` charge: `OrderCosts.ensure` charges the row only when the order carried no cost of its own; with `always` 1 the row is charged regardless — confirm `ActionSystem.execute` charges `always` rows (the note in `order_costs.gd:73` says it does); if it does not, add after the drift block in `execute`: `if OrderCosts.always(data, req.action_code): effects.append_array(OrderCosts.charge(data, state, req.action_code, req.target))`.

- [ ] **Step 6: Run the two test files, then the suite**

Expected: green. A test that asserted `MANOR_BUILD` charged `cost_gold` now expects civil goods: update it.

- [ ] **Step 7: Commit**

```bash
git add data/ scripts/engine/action_system.gd scripts/engine/map_manors.gd tests/engine/
git commit -m "feat(economy): building spends civil goods, gold hurries it, the levy spends strategic goods"
```

---

### Task 9: The top bar's two lines

**Files:**
- Modify: `scenes/top_bar.tscn`, `scripts/ui/top_bar.gd`
- Modify: `data/resource_icons.csv`
- Modify: `tests/ui/test_top_bar.gd`

**Interfaces:**
- Produces: `TopBar.ORDER == ["treasury", "strategic", "grain", "unrest", "legitimacy", "army_quality", "church_opinion"]`; `TopBar.monthly_text(metric) -> String` (the realm's monthly figure for treasury/strategic/grain, e.g. `+310`); `TopBar.crown_text(kind) -> String` for `"tax"|"strategic"|"civil"` (e.g. `120 (39%)`); `bar_height()` reflects two lines.

- [ ] **Step 1: Write the failing test**

Append to `tests/ui/test_top_bar.gd` (use the file's existing way of instancing the bar — a `_bar()` helper or `load("res://scenes/top_bar.tscn").instantiate()` added with `add_child_autofree` after `Game.start_campaign(42)`, as the other tests there do):

```gdscript
## Two lines (spec §6): the realm's stocks and monthly figures, then the
## crown's provinces' monthly tax, strategic and civil goods with their
## share of the realm in whole percent, in a smaller font.
func test_the_bar_shows_the_realm_and_the_crowns_share() -> void:
	var bar := _bar()
	await wait_frames(2)
	var e := RealmEconomy.realm(Game.data, Game.state)
	assert_eq(bar.metric_text("strategic"), str(int(Game.state.metrics["strategic"])))
	assert_eq(bar.metric_text("grain"), str(int(Game.state.metrics["grain"])))
	assert_eq(bar.monthly_text("treasury"), "+%d" % int(e["realm"]["tax"]))
	assert_eq(bar.monthly_text("strategic"), "+%d" % int(e["realm"]["strategic"]))
	assert_eq(bar.monthly_text("grain"), "+%d" % int(e["realm"]["civil"]))
	var pct := int(roundf(100.0 * float(e["crown"]["tax"]) / maxf(float(e["realm"]["tax"]), 1.0)))
	assert_eq(bar.crown_text("tax"), "%d (%d%%)" % [int(e["crown"]["tax"]), pct])
	assert_true(bar.crown_text("civil").ends_with("%)"))
	assert_gt(bar.bar_height(), 40.0, "two lines are taller than one")
	var second: Label = bar.crown_label("tax")
	assert_lt(second.get_theme_font_size("font_size"), 18, "the second line is smaller")
```

- [ ] **Step 2: Run to see it fail**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/ui/test_top_bar.gd -gexit 2>&1 | grep -E "Passing|Failing|rror"`
Expected: failing (`monthly_text` missing; ORDER lacks strategic).

- [ ] **Step 3: The scene**

In `scenes/top_bar.tscn` wrap `Row` in a `VBoxContainer` and add the second row: replace the `Row` node header and add `CrownRow`:

```
[node name="Rows" type="VBoxContainer" parent="Bar"]
theme_override_constants/separation = 0

[node name="Row" type="HBoxContainer" parent="Bar/Rows"]
theme_override_constants/separation = 8
```
(every child that was `parent="Bar/Row"` becomes `parent="Bar/Rows/Row"`), then after `MenuButton`:

```
[node name="CrownRow" type="HBoxContainer" parent="Bar/Rows"]
unique_name_in_owner = true
alignment = 1
theme_override_constants/separation = 14
```
and change the root's `offset_bottom = 26.0` to `offset_bottom = 44.0`.

- [ ] **Step 4: The script**

In `scripts/ui/top_bar.gd`: `const ORDER := ["treasury", "strategic", "grain", "unrest", "legitimacy", "army_quality", "church_opinion"]`; add `const POOLS := {"treasury": "tax", "strategic": "strategic", "grain": "civil"}` (metric → the realm figure it shows monthly) and `const CROWN := ["tax", "strategic", "civil"]`; fields `var _monthly_labels: Dictionary = {}`, `var _crown_labels: Dictionary = {}`. In `_ready`'s metric loop, after the delta label, add for pool metrics:

```gdscript
		if POOLS.has(m):
			var monthly_l := Label.new()
			monthly_l.add_theme_font_size_override("font_size", 13)
			monthly_l.add_theme_color_override("font_color", UiPalette.INK_MUTED)
			monthly_l.tooltip_text = "the realm's %s this month" % String(POOLS[m])
			cell.add_child(monthly_l)
			_monthly_labels[m] = monthly_l
```
(if `UiPalette` has no `INK_MUTED`, use `UiPalette.INK` with `modulate.a = 0.7` on the label). After the loop, build the second line:

```gdscript
	# The crown's own provinces (spec §6): the same three figures, smaller,
	# each with its share of the realm.
	for kind: String in CROWN:
		var cell := HBoxContainer.new()
		cell.add_theme_constant_override("separation", 4)
		var icon := ResourceIcon.create({"tax": "treasury", "strategic": "strategic", "civil": "grain"}[kind])
		icon.name = "CrownIcon_" + kind
		cell.add_child(icon)
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 13)
		l.tooltip_text = "your provinces' %s this month, and its share of the realm's" % kind
		cell.add_child(l)
		_crown_labels[kind] = l
		%CrownRow.add_child(cell)
```
In `refresh()` after the metric loop:

```gdscript
	var e := RealmEconomy.realm(Game.data, Game.state)
	for m: String in _monthly_labels:
		_monthly_labels[m].text = "+%d" % int(e["realm"][String(POOLS[m])])
	for kind: String in _crown_labels:
		var realm_v := int(e["realm"][kind])
		var crown_v := int(e["crown"][kind])
		var pct := int(roundf(100.0 * float(crown_v) / maxf(float(realm_v), 1.0)))
		_crown_labels[kind].text = "%d (%d%%)" % [crown_v, pct]
```
Add the seams:

```gdscript
func monthly_text(metric: String) -> String:
	return String(_monthly_labels[metric].text) if _monthly_labels.has(metric) else ""

func crown_text(kind: String) -> String:
	return String(_crown_labels[kind].text) if _crown_labels.has(kind) else ""

func crown_label(kind: String) -> Label:
	return _crown_labels.get(kind)
```
`bar_height()` is unchanged and now reports the two rows' minimum.

`data/resource_icons.csv`: change the `treasury` row's tooltip to "Gold in the crown's chest. Taxes fill it each month; salaries and your orders empty it."; change the `grain` row to `grain,Civil goods,grain,"Civil goods, in gold: food, timber, cloth and wares. The harvest and your provinces fill them each month; the court eats from them and building spends them.",res://assets/icons/grain.png`; add `strategic,Strategic goods,swords,"Strategic goods, in gold: iron, horses, arms and ships. Your provinces fill them each month; the levy and the campaign spend them — the army goes as far as they stretch.",` (no texture yet; `ResourceIcon` draws the swords glyph).

- [ ] **Step 5: Run the top bar tests and the screens**

Run the test file; expected: green. Then the snapshot: `/Applications/Godot.app/Contents/MacOS/Godot --path . -s tools/snapshot_screen.gd -- --screen court --out /tmp/court_bar.png` and look at the bar: two lines, the columns start under it (`bar_height()` grew; `tests/ui/test_display_fit.gd` or a layout test may pin 26 — update to `bar_height()`).

- [ ] **Step 6: Commit**

```bash
git add scenes/top_bar.tscn scripts/ui/top_bar.gd data/resource_icons.csv tests/ui/test_top_bar.gd
git commit -m "feat(ui): the top bar shows the realm's month and the crown's share on a second line"
```

---

### Task 10: The bench, the retune, the docs

**Files:**
- Create: `tools/bench_economy.gd`
- Modify: `data/balance.csv` (grain-era thresholds), `data/order_costs.csv`, `CLAUDE.md`, `MANOR_SYSTEM.md`

**Interfaces:**
- Produces: `tools/bench_economy.gd` printing four timings.

- [ ] **Step 1: The bench**

`tools/bench_economy.gd`:

```gdscript
extends SceneTree
## Times the manor economy on the loaded pack (spec 2026-09-14 §11.3):
##   /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/bench_economy.gd
## Targets: a day's bucket <= 8 ms, the month's end <= 8 ms (16 hard), a
## warm realm read < 0.1 ms, one province < 1 ms; a cold recompute_all is
## reported, not bounded. A tool: it reads the clock, the engine never does.

func _init() -> void:
	var data := DataRepository.load_all("res://data")
	var s := GameState.new_campaign(data, 42)
	var engine := TickEngine.new(data)
	RealmEconomy.forget()
	var t0 := Time.get_ticks_usec()
	RealmEconomy.recompute_all(data, s)
	var cold := (Time.get_ticks_usec() - t0) / 1000.0
	RealmEconomy.forget()
	RealmEconomy.realm(data, s)
	t0 = Time.get_ticks_usec()
	for i in 100:
		RealmEconomy.realm(data, s)
	var warm := (Time.get_ticks_usec() - t0) / 100000.0
	var code := MapManors.controlled_provinces(data, s)[0]
	t0 = Time.get_ticks_usec()
	RealmEconomy.recompute_province(data, s, code)
	var one := (Time.get_ticks_usec() - t0) / 1000.0
	s.tick += 1
	var worst_day := 0.0
	for d in range(1, Calendar.DAYS_PER_TICK + 1):
		s.day = d
		t0 = Time.get_ticks_usec()
		RealmEconomy.step_day(data, s)
		worst_day = maxf(worst_day, (Time.get_ticks_usec() - t0) / 1000.0)
	t0 = Time.get_ticks_usec()
	engine.advance(s)
	var month_end := (Time.get_ticks_usec() - t0) / 1000.0
	print("bench_economy: cold recompute_all %.1f ms | warm realm read %.3f ms | one province %.2f ms | worst day bucket %.1f ms | month's end (advance) %.1f ms | provinces %d" % [
		cold, warm, one, worst_day, month_end, RealmEconomy._codes.size()])
	quit(0)
```

Run it: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s tools/bench_economy.gd 2>&1 | grep bench_economy`. Expected: worst day bucket and month's end under 8 ms; if the month's end is over, the settlement's `advance` includes events and concerns — time `RealmEconomy.realm` alone there too and report both.

- [ ] **Step 2: Retune the grain-era thresholds to gold**

`data/balance.csv`: `concern_grain_low` 30 → 200 (the steward worries under 200 gold of civil goods); `grain_release_amount` 20 → 100 (gold of civil goods opened to the villages); `unrest_famine` stays. `data/resource_icons.csv` and any `data/*.csv` note still saying "fortnight": say "month".

- [ ] **Step 3: Run the whole suite**

`./run_tests.sh 2>&1 | tail -15` — green with the expected error count.

- [ ] **Step 4: The docs**

`CLAUDE.md`: in the "Key documents" bullet for `MANOR_SYSTEM.md`, replace the sentence about rent ("rent (paid into the treasury each tick as `manor_rents`)") with: "every manor earns a MONTH of whole-gold tax, strategic and civil goods (`ManorEconomy.line_of`; spec `docs/superpowers/specs/2026-09-14-economy-and-staging-design.md`), summed into provinces and the realm by `RealmEconomy` (columnar, province keys, day buckets) and settled at the month's end into `metrics.treasury`, `metrics.strategic` and `metrics.grain` — the CIVIL pool, whose key stays `grain` for its readers". In the Stack section note the tick is 30 days. Add to the invariants list, after 8: "**9. The economy is whole gold, rounded once, at the manor.** Provinces and the realm are sums; growth is an integer per-mille table; iteration order is fixed" (renumber the ones after).
`MANOR_SYSTEM.md` §3 "Tax (rent)": replace the formula with §4.2 of the spec and point to it.

- [ ] **Step 5: Commit**

```bash
git add tools/bench_economy.gd data/balance.csv data/resource_icons.csv CLAUDE.md MANOR_SYSTEM.md
git commit -m "chore(economy): the bench, gold-era thresholds, the docs"
```

---

## Self-review

- **Spec coverage:** §2 calendar → Task 1; §3 goods → Task 2; §4.1 people → Task 3; §4.2–4.3 lines → Task 4; §4.4 sums and cache, §11.2 → Task 5; §5 pools, settlement, salaries, ration/harvest, seeding → Task 6; §5 buy/sell → Task 7; §5 civil cost, rush, strategic costs → Task 8; §6 top bar → Task 9; §11.3 bench, check switch (Task 6), §9 data → Tasks 1, 6, 10. §7 (staging) is the other plan. §12's isolation test already exists.
- **Placeholders:** none; every step carries its code or its exact data.
- **Names:** `ManorEconomy.line_of(repo, state, cell, tick)`, `RealmEconomy.realm/province/line_of/step_day/recompute_all/check_full/compute_count`, `MapManors.people_of/people_table/apportion/rush_work`, `DataRepository.goods_economy_of`, `ActionSystem.pool_metric`, `TopBar.monthly_text/crown_text/crown_label` are used with the same signatures throughout.
