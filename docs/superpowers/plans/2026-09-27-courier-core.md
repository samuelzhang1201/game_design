# Courier Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An order to a regiment rides from the capital as a courier on the road network, at a pace set by the road, the height tier and the province's weather. The order takes effect only when the courier reaches the column.

**Architecture:**
- Three pure engine classes:
  - `RoadGraph`: the pack's roads and trails snapped into one network, with Dijkstra over it.
  - `Weather`: stateless and hashed from the seed, per province, per 3-day spell.
  - `CourierSystem`: dispatch, a day's ride, and delivery; its state is `GameState.couriers`.
- `ActionSystem`'s `ARMY_MARCH` / `ARMY_GARRISON` dispatch a courier instead of writing the regiment.
- `TickEngine` rides the couriers before `march_day`.
- The 3D map gets a courier layer (`Map3DLayerCouriers`) and two HUD pieces:
  - `Map3DHudCouriers`: routes, pending orders and counters;
  - `Map3DHudWeather`: the weather marks.
- The left column gets a courier card (`CourierCard`).

**Tech Stack:** Godot 4.7, typed GDScript, GUT (`./run_tests.sh`), CSV data under `data/`.

**Spec:** `docs/superpowers/specs/2026-09-27-courier-core-design.md`

## Global Constraints

- Typed GDScript everywhere (type hints on vars, params, returns).
- Engine classes are `RefCounted`: no Node, no `Time.*`, no unseeded random.
- Design values live in CSVs: `data/*.csv` and `balance.csv` keys. Nothing is tuned in code.
- State holds whole numbers only:
  - positions are whole METRES of the pack's measure (`ArmySystem.pack_to_metres`);
  - rates are whole per-mille;
  - no floats in `GameState`.
- Weather never draws from `GameState.rng`. It is a hash of `(campaign seed, province, spell)`.
- Couriers advance in ascending `id` order, and Dijkstra breaks ties by node id.
- Every opinion or metric change carries a reason string (invariant 4). The courier fee is a ledger line with a reason.
- Nothing under `scripts/map3d/` may reference the `Game` autoload, except `map3d_view.gd` (a test scans for it).
- Every `scripts/map3d/*.gd` other than the view stays ≤ 300 lines.
- `map3d_view.gd` may grow only by forwarders, guards and signals. Task 10 raises its cap from 556 to 559.
- `./run_tests.sh` must end with the expected error count: "Errors 2" with the gdai plugin installed, else 0. Any other count is a failure.
- **The working tree carries the owner's uncommitted units work** (`data/balance.csv`, `data/army_art.csv`, `assets/units3d/*` and more). Every commit in this plan `git add`s ONLY the files its task names. Never `git add -A` or `git commit -a`.
- The ordinary courier's base is `courier_base_km_per_day` 160, and a secret courier rides at 750‰ of it. The UI offers only the ordinary courier (`courier_kinds.csv` `offered` 1 / 0).
- Fleets are exempt from couriers in this sub-project: their orders apply at once.
- The cavalry `.glb` stands in for the courier model until sub-project D delivers one. This is deliberate and temporary.

## Review Focus

1. **A courier chasing a column that is itself marching away.** Expected: he re-aims each day and still delivers. Pinned in Task 5, `test_a_courier_catches_a_column_on_the_march`.
2. **March, then Cancel march, sent back to back.** Expected: the newer order wins even when the older courier arrives later; the older one is set aside with news. Pinned in Task 5, `test_an_older_order_arriving_late_is_set_aside`.
3. **Save and load in the middle of a ride.** Expected: identical afterwards. Pinned in Task 5, `test_a_ride_survives_a_save_mid_road`.
4. **An order given on a paused clock.** Expected: the courier appears but nothing moves and the regiment is untouched until a day runs. Pinned in Task 6, `test_the_order_rides_and_the_regiment_waits`.
5. **A chest too thin for the fee.** Expected: the order is refused with a reason, not charged into the red. Pinned in Task 6, `test_a_chest_too_thin_for_the_courier_is_refused`.

---

### Task 1: Courier and weather data, and the loaders

**Files:**
- Create: `data/courier_kinds.csv`, `data/courier_art.csv`, `data/road_speed.csv`, `data/weather.csv`, `data/weather_odds.csv`
- Modify: `data/balance.csv` (append rows)
- Modify: `scripts/engine/data_repository.gd` (vars near `var army_height_supply` ~:88; loaders after the `army_speed.csv` loader ~:527; the forget list in `load_map` ~:593)
- Modify: `scripts/engine/rng.gd` (add `seed_value`)
- Modify: `scripts/engine/calendar.gd` (add `season_of_day`)
- Test: `tests/engine/test_courier_data.gd`

**Interfaces:**
- Produces:
  - `DataRepository.courier_kinds: Dictionary`, kind → `{speed_permille: int, fee_gold: int, offered: bool}`
  - `DataRepository.courier_art: Dictionary`, kind → CSV row
  - `DataRepository.road_speed: Dictionary`, key → int ‰. Keys: `road`, `trail`, `offroad`, `sea`, `tier_plains`, `tier_hills`, `tier_mountains`, `tier_peak`.
  - `DataRepository.weather_kinds: Dictionary`, kind → `{speed_permille: int, icon: String, label: String}`, in file order
  - `DataRepository.weather_odds: Dictionary`, `"season|tier"` → `{kind: int weight}`, with keys in `weather_kinds` order
  - `Rng.seed_value() -> int`
  - `Calendar.season_of_day(abs_day: int) -> String`, lower case
  - `RoadGraph.forget()` and `Weather.forget()` are called from `load_map`. They are created in Tasks 2–3; add their two lines in those tasks.

- [ ] **Step 1: Write the failing test** — `tests/engine/test_courier_data.gd`

```gdscript
extends GutTest
## The courier core's tables (spec 2026-09-27-courier-core §3).

var repo: DataRepository


func before_all() -> void:
	repo = DataRepository.load_all("res://data")


func test_the_courier_kinds() -> void:
	assert_eq(int(repo.courier_kinds["ordinary"]["speed_permille"]), 1000)
	assert_true(bool(repo.courier_kinds["ordinary"]["offered"]), "A offers the ordinary courier")
	assert_eq(int(repo.courier_kinds["secret"]["speed_permille"]), 750)
	assert_false(bool(repo.courier_kinds["secret"]["offered"]), "the secret one waits for C")
	for kind: String in repo.courier_kinds:
		assert_gt(int(repo.courier_kinds[kind]["fee_gold"]), 0, kind + " has a fee")
		assert_true(repo.courier_art.has(kind), kind + " has an art row")


func test_the_road_speeds() -> void:
	for key in ["road", "trail", "offroad", "sea", "tier_plains", "tier_hills", "tier_mountains", "tier_peak"]:
		assert_gt(int(repo.road_speed.get(key, 0)), 0, key)
	assert_gt(int(repo.road_speed["road"]), int(repo.road_speed["trail"]), "a road beats a trail")
	assert_gt(int(repo.road_speed["trail"]), int(repo.road_speed["offroad"]), "a trail beats open country")


func test_every_season_and_tier_has_odds() -> void:
	for season in ["spring", "summer", "autumn", "winter"]:
		for row: Dictionary in repo.army_height_supply:
			var key := "%s|%s" % [season, String(row["tier"])]
			assert_true(repo.weather_odds.has(key), key)
			var total := 0
			for kind: String in repo.weather_odds[key]:
				assert_true(repo.weather_kinds.has(kind), kind + " is a weather kind")
				total += int(repo.weather_odds[key][kind])
			assert_gt(total, 0, key + " can roll something")


func test_every_weather_kind_has_a_speed() -> void:
	assert_eq(repo.weather_kinds.keys(), ["clear", "rain", "mud", "snow", "blizzard"])
	assert_eq(int(repo.weather_kinds["clear"]["speed_permille"]), 1000)
	for kind: String in repo.weather_kinds:
		assert_gt(int(repo.weather_kinds[kind]["speed_permille"]), 0, kind)


func test_the_balance_keys() -> void:
	for key in ["courier_base_km_per_day", "courier_graph_snap_px", "courier_offroad_max_km",
			"courier_reaim_m", "courier_max_days", "courier_slow_news_permille",
			"courier_sea_sample_km", "weather_spell_days"]:
		assert_true(repo.balance.has(key), key)
	assert_eq(int(repo.bal("courier_base_km_per_day")), 160, "owner 2026-09-27: four times the cavalry")


func test_the_seed_is_readable_and_survives_a_save() -> void:
	var r := Rng.new(1234)
	assert_eq(r.seed_value(), 1234)
	r.randi_range(0, 10)
	assert_eq(Rng.from_dict(r.to_dict()).seed_value(), 1234)


func test_the_season_of_an_absolute_day() -> void:
	assert_eq(Calendar.season_of_day(1), "spring")
	assert_eq(Calendar.season_of_day(90), "spring")
	assert_eq(Calendar.season_of_day(91), "summer")
	assert_eq(Calendar.season_of_day(360), "winter")
	assert_eq(Calendar.season_of_day(361), "spring")
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./run_tests.sh -gtest=res://tests/engine/test_courier_data.gd`. If `run_tests.sh` passes no args through, run `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/engine/test_courier_data.gd -gexit`.
Expected: FAIL (`courier_kinds` not a member, `seed_value` not found).

- [ ] **Step 3: Write the data**

`data/courier_kinds.csv`:
```
kind,speed_permille,fee_gold,offered,notes
ordinary,1000,2,1,"owner 2026-09-27 (spec 2026-09-27-courier-core): the fastest rider, courier_base_km_per_day on a clear road on the plain; one per order, gone on delivery; the fee is charged by ActionSystem as a ledger line"
secret,750,5,0,"slower, but never intercepted — which means nothing until sub-project C, so the UI does not offer it yet (offered 0)"
```

`data/courier_art.csv`:
```
kind,model,painting,size,notes
ordinary,res://assets/units3d/cavalry.glb,,0.7,"INTERIM (spec 2026-09-27-courier-core §2): the cavalry model stands in until sub-project D delivers the courier rider — D changes the model and painting columns and nothing else"
secret,res://assets/units3d/cavalry.glb,,0.7,the same stand-in
```

`data/road_speed.csv`:
```
key,permille,notes
road,1000,"owner 2026-09-27: couriers ride the road network (RoadGraph); a road is the pace courier_base_km_per_day is quoted at"
trail,800,a trail: narrower and rougher
offroad,550,"across country: the legs from the capital to the network and from it to the column"
sea,625,"a crossing to another landmass at the fleet's 100 km a day (data/army_speed.csv) over the courier's 160"
tier_plains,1000,"the Elevation tier of the ground a stretch starts on (data/army_height_supply.csv lines)"
tier_hills,800,hills slow a horse
tier_mountains,600,mountain passes
tier_peak,400,above the snow line
```

`data/weather.csv`:
```
kind,speed_permille,icon,label,notes
clear,1000,weather_clear,Clear,"owner 2026-09-27: regional weather changes SPEED only — a courier's ride and a regiment's march (Weather)"
rain,850,weather_rain,Rain,wet roads
mud,700,weather_mud,Mud,the spring and autumn roads
snow,650,weather_snow,Snow,
blizzard,400,weather_blizzard,Blizzard,"under courier_slow_news_permille, so the news bar says a courier is held up"
```

`data/weather_odds.csv` (weights, not percentages; each row sums to 100 for reading):
```
season,tier,clear,rain,mud,snow,blizzard
spring,plains,55,25,20,0,0
spring,hills,50,25,20,5,0
spring,mountains,40,20,15,20,5
spring,peak,25,10,5,40,20
summer,plains,75,20,5,0,0
summer,hills,70,22,8,0,0
summer,mountains,60,25,5,8,2
summer,peak,45,15,0,30,10
autumn,plains,50,30,20,0,0
autumn,hills,45,30,20,5,0
autumn,mountains,35,25,15,20,5
autumn,peak,20,10,5,45,20
winter,plains,40,15,15,25,5
winter,hills,30,10,10,40,10
winter,mountains,15,5,0,55,25
winter,peak,5,0,0,55,40
```

Append to `data/balance.csv`. Use `>>` or an editor append; do not rewrite the file, since it holds uncommitted owner edits.
```
courier_base_km_per_day,160,"owner 2026-09-27: an ordinary courier's km a day on a clear road on the plain — four times the cavalry's 40 (spec 2026-09-27-courier-core)"
courier_graph_snap_px,2,"RoadGraph: route vertices within this many pack px merge into one node — routes join each other mid-line, so without it the network falls into dozens of pieces"
courier_offroad_max_km,80,"a place farther than this from every road node is ridden to straight across country"
courier_reaim_m,2000,"a courier re-aims his last leg once the column he rides for has moved this many metres"
courier_max_days,60,"the fuse: a courier out this many days is lost and his orders undelivered"
courier_slow_news_permille,500,"a day's weather slower than this raises one news line per courier per spell"
courier_sea_sample_km,5,"a leg is sampled every this many km; any point off the land grid makes it a sea crossing"
weather_spell_days,3,"days a province's weather holds (Weather.spell_of) so it does not flicker daily"
```

- [ ] **Step 4: Write the loaders, `seed_value` and `season_of_day`**

In `scripts/engine/data_repository.gd`, beside `var army_height_supply: Array = []`:
```gdscript
## data/courier_kinds.csv: kind -> {speed_permille, fee_gold, offered}
## (spec 2026-09-27-courier-core §3).
var courier_kinds: Dictionary = {}
## data/courier_art.csv: kind -> its row (model, painting, size).
var courier_art: Dictionary = {}
## data/road_speed.csv: key -> per mille (road, trail, offroad, sea, tier_<tier>).
var road_speed: Dictionary = {}
## data/weather.csv: kind -> {speed_permille, icon, label}, in the file's order.
var weather_kinds: Dictionary = {}
## data/weather_odds.csv: "season|tier" -> {kind: weight}, kinds in weather_kinds' order.
var weather_odds: Dictionary = {}
```

Right after the `army_speed.csv` loader in `_load`:
```gdscript
	if not _load_if_present(dir + "/courier_kinds.csv", ["kind", "speed_permille", "fee_gold", "offered"],
			func(r): courier_kinds[String(r["kind"])] = {"speed_permille": int(r["speed_permille"]),
				"fee_gold": int(r["fee_gold"]), "offered": int(r["offered"]) == 1}):
		return false
	if not _load_if_present(dir + "/courier_art.csv", ["kind", "model", "painting", "size"],
			func(r): courier_art[String(r["kind"])] = r):
		return false
	if not _load_if_present(dir + "/road_speed.csv", ["key", "permille"],
			func(r): road_speed[String(r["key"])] = int(r["permille"])):
		return false
	if not _load_if_present(dir + "/weather.csv", ["kind", "speed_permille", "icon", "label"],
			func(r): weather_kinds[String(r["kind"])] = {"speed_permille": int(r["speed_permille"]),
				"icon": String(r["icon"]), "label": String(r["label"])}):
		return false
	if not _load_if_present(dir + "/weather_odds.csv", ["season", "tier"], _add_weather_odds):
		return false
```

And a method beside `_add_matchup`:
```gdscript
func _add_weather_odds(r: Dictionary) -> void:
	var w: Dictionary = {}
	for kind: String in weather_kinds:
		w[kind] = int(r.get(kind, "0"))
	weather_odds["%s|%s" % [String(r["season"]), String(r["tier"])]] = w
```

In `scripts/engine/rng.gd`:
```gdscript
## The seed this stream started from — Weather hashes it, so the skies are
## the campaign's own without drawing from the stream.
func seed_value() -> int:
	return int(_rng.seed)
```

In `scripts/engine/calendar.gd`:
```gdscript
## The season of an absolute day, lower case ("spring".."winter") — the
## weather's odds are keyed by it.
static func season_of_day(abs_day: int) -> String:
	@warning_ignore("integer_division")  # whole seasons
	return String(SEASONS[((maxi(abs_day, 1) - 1) % DAYS_PER_YEAR) / DAYS_PER_SEASON]).to_lower()
```

- [ ] **Step 5: Run the test to verify it passes**

Run the same command as Step 2. Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add data/courier_kinds.csv data/courier_art.csv data/road_speed.csv data/weather.csv data/weather_odds.csv data/balance.csv scripts/engine/data_repository.gd scripts/engine/rng.gd scripts/engine/calendar.gd tests/engine/test_courier_data.gd
git commit -m "feat(couriers): courier, road-speed and weather tables with their loaders"
```

`data/balance.csv` carries uncommitted owner edits. Before `git add`, run `git diff data/balance.csv`. If it shows more than your appended rows, stage only your rows with `git add -p data/balance.csv`; answer `y` only to hunks that are your rows.

---

### Task 2: Weather

**Files:**
- Create: `scripts/engine/weather.gd`
- Modify: `scripts/engine/data_repository.gd` (`load_map` forget list: add `Weather.forget()`)
- Test: `tests/engine/test_weather.gd`

**Interfaces:**
- Consumes: `repo.weather_kinds`, `repo.weather_odds`, `Rng.seed_value()`, `Calendar.season_of_day`, `Elevation.tier_of`, `MapEconomy.cell_at`, `MapManors.province_of`, `MapManors.manors_of_province(repo, province, state = null)`
- Produces:
  - `Weather.CLEAR := "clear"`
  - `Weather.forget() -> void`
  - `Weather.spell_of(repo, abs_day: int) -> int`
  - `Weather.tier_of_province(repo, province: String) -> String`
  - `Weather.of(repo, state: GameState, province: String, abs_day: int) -> String`
  - `Weather.at(repo, state: GameState, pack_px: Vector2, abs_day: int) -> String`
  - `Weather.speed_permille(repo, kind: String) -> int`
  - `Weather.label_of(repo, kind: String) -> String`
  - `Weather.describe_kind(repo, kind: String) -> String`, e.g. `"Rain (march and couriers ×0.85)"` or `"Clear"`
  - `Weather.describe(repo, state, province: String) -> String`, today's weather described

- [ ] **Step 1: Write the failing test** — `tests/engine/test_weather.gd`

```gdscript
extends GutTest
## Regional weather (spec 2026-09-27-courier-core §1): stateless, hashed from
## (seed, province, spell), drawn from data/weather_odds.csv.

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	Weather.forget()


func _a_province() -> String:
	var codes := repo.provinces.keys()
	codes.sort()
	return String(codes[0])


## Every season and tier rolls `kind` and nothing else.
func _skies(kind: String) -> void:
	for key in repo.weather_odds:
		var w: Dictionary = {}
		for k: String in repo.weather_kinds:
			w[k] = 1 if k == kind else 0
		repo.weather_odds[key] = w


func test_the_same_seed_province_and_day_give_the_same_weather() -> void:
	var s := GameState.new_campaign(repo, 7)
	var p := _a_province()
	for day in [1, 50, 200, 333]:
		assert_eq(Weather.of(repo, s, p, day), Weather.of(repo, s, p, day))


func test_weather_holds_across_a_spell() -> void:
	repo.balance["weather_spell_days"] = 3.0
	assert_eq(Weather.spell_of(repo, 1), 0)
	assert_eq(Weather.spell_of(repo, 3), 0)
	assert_eq(Weather.spell_of(repo, 4), 1)
	var s := GameState.new_campaign(repo, 7)
	var p := _a_province()
	assert_eq(Weather.of(repo, s, p, 4), Weather.of(repo, s, p, 6), "days 4-6 are one spell")


func test_the_odds_decide() -> void:
	var s := GameState.new_campaign(repo, 7)
	_skies("blizzard")
	assert_eq(Weather.of(repo, s, _a_province(), 10), "blizzard")
	_skies("clear")
	assert_eq(Weather.of(repo, s, _a_province(), 10), "clear")


func test_no_province_is_clear() -> void:
	var s := GameState.new_campaign(repo, 7)
	assert_eq(Weather.of(repo, s, "", 10), Weather.CLEAR)
	assert_eq(Weather.of(repo, null, _a_province(), 10), Weather.CLEAR)


func test_a_seasons_frequencies_follow_its_odds() -> void:
	# Summer on the plains is 75 clear in 100. Over ~2,000 summer spells of
	# one province the share must land within 5 points of it.
	var s := GameState.new_campaign(repo, 11)
	var plains := ""
	var codes := repo.provinces.keys()
	codes.sort()
	for c: String in codes:
		if Weather.tier_of_province(repo, c) == "plains":
			plains = c
			break
	assert_ne(plains, "", "the pack has a lowland province")
	var clear := 0
	var total := 0
	for year in 67:
		for spell in 30:
			if Weather.of(repo, s, plains, 360 * year + 91 + 3 * spell) == "clear":
				clear += 1
			total += 1
	assert_almost_eq(float(clear) / float(total), 0.75, 0.05)


func test_speeds_and_words() -> void:
	assert_eq(Weather.speed_permille(repo, "rain"), 850)
	assert_eq(Weather.speed_permille(repo, "no_such"), 1000, "unknown weather does not slow anyone")
	assert_eq(Weather.describe_kind(repo, "clear"), "Clear")
	assert_eq(Weather.describe_kind(repo, "rain"), "Rain (march and couriers ×0.85)")
```

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL (`Weather` not found).

- [ ] **Step 3: Write `scripts/engine/weather.gd`**

```gdscript
class_name Weather
extends RefCounted
## Regional weather (owner 2026-09-27, spec 2026-09-27-courier-core §1): each
## province has one kind for a spell of weather_spell_days days, drawn from
## data/weather_odds.csv by season and the province's height tier. STATELESS:
## a hash of (campaign seed, province, spell) — never GameState.rng — so it
## costs the save nothing and cannot shift any other roll. It changes speed
## only: a courier's ride and a regiment's march.

const CLEAR := "clear"

static var _tiers: Dictionary = {}
static var _tiers_map := ""


static func forget() -> void:
	_tiers = {}
	_tiers_map = ""


## The spell a day falls in: whole spells of weather_spell_days from day 1.
static func spell_of(repo: DataRepository, abs_day: int) -> int:
	@warning_ignore("integer_division")  # whole spells
	return (maxi(abs_day, 1) - 1) / maxi(1, int(repo.bal("weather_spell_days")))


## A province's height tier: its seat's cell, else its first manor's; plains
## when it has neither. Cached per pack.
static func tier_of_province(repo: DataRepository, province: String) -> String:
	if _tiers_map != repo.map_id:
		_tiers = {}
		_tiers_map = repo.map_id
	if _tiers.has(province):
		return _tiers[province]
	var cell := -1
	var burg := String((repo.provinces.get(province, {}) as Dictionary).get("capital_burg", ""))
	if repo.burgs.has(burg):
		var b: Dictionary = repo.burgs[burg]
		cell = MapEconomy.cell_at(repo, Vector2(float(b["x"]), float(b["y"])))
	if not repo.cells.has(cell):
		var ids := MapManors.manors_of_province(repo, province)
		cell = int(ids[0]) if not ids.is_empty() else -1
	var tier := "plains"
	if repo.cells.has(cell):
		tier = String(Elevation.tier_of(repo, float(repo.cells[cell]["height"]))["tier"])
	_tiers[province] = tier
	return tier


## A well-mixed 32-bit hash of a text: String.hash() alone keeps too much of
## the order of nearby spells.
static func _mix(text: String) -> int:
	var h := text.hash() & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	return h ^ (h >> 16)


## The weather over a province on an absolute day. No province, no state,
## or no odds for its season and tier: clear.
static func of(repo: DataRepository, state: GameState, province: String, abs_day: int) -> String:
	if province == "" or state == null:
		return CLEAR
	var key := "%s|%s" % [Calendar.season_of_day(abs_day), tier_of_province(repo, province)]
	var weights: Dictionary = repo.weather_odds.get(key, {})
	var total := 0
	for k: String in weights:
		total += int(weights[k])
	if total <= 0:
		return CLEAR
	var roll := posmod(_mix("%d|%s|%d" % [state.rng.seed_value(), province, spell_of(repo, abs_day)]), total)
	for k: String in weights:
		roll -= int(weights[k])
		if roll < 0:
			return k
	return CLEAR


## The weather at a map point: its land cell's province's, clear at sea.
static func at(repo: DataRepository, state: GameState, pack_px: Vector2, abs_day: int) -> String:
	var cell := MapEconomy.cell_at(repo, pack_px)
	if cell < 0:
		return CLEAR
	return of(repo, state, MapManors.province_of(repo, cell, state), abs_day)


static func speed_permille(repo: DataRepository, kind: String) -> int:
	return int((repo.weather_kinds.get(kind, {}) as Dictionary).get("speed_permille", 1000))


static func label_of(repo: DataRepository, kind: String) -> String:
	return String((repo.weather_kinds.get(kind, {}) as Dictionary).get("label", kind.capitalize()))


## "Clear", or "Rain (march and couriers ×0.85)".
static func describe_kind(repo: DataRepository, kind: String) -> String:
	var permille := speed_permille(repo, kind)
	if permille >= 1000:
		return label_of(repo, kind)
	return "%s (march and couriers ×%.2f)" % [label_of(repo, kind), float(permille) / 1000.0]


## Today's weather over a province, described.
static func describe(repo: DataRepository, state: GameState, province: String) -> String:
	if state == null:
		return label_of(repo, CLEAR)
	return describe_kind(repo, of(repo, state, province, state.absolute_day()))
```

Add `Weather.forget()` to the forget list in `DataRepository.load_map`, beside `Elevation.forget()`.

- [ ] **Step 4: Run the test to verify it passes.** Expected: PASS. If the frequency test lands outside ±0.05, the hash is not mixing well: check `_mix` for precedence mistakes. Do not widen the tolerance.

- [ ] **Step 5: Commit**

```bash
git add scripts/engine/weather.gd scripts/engine/data_repository.gd tests/engine/test_weather.gd
git commit -m "feat(couriers): stateless regional weather by season and height tier"
```

---

### Task 3: RoadGraph

**Files:**
- Create: `scripts/engine/road_graph.gd`
- Modify: `scripts/engine/data_repository.gd` (`load_map` forget list: add `RoadGraph.forget()`)
- Test: `tests/engine/test_road_graph.gd`

**Interfaces:**
- Consumes:
  - `repo.routes` (route_code → row with `group`, `polyline: PackedVector2Array`);
  - `repo.road_speed`;
  - `ArmySystem.pack_to_metres` / `metres_to_pack`;
  - `MapEconomy.cell_at`;
  - `Elevation.tier_of`.
- Produces:
  - `RoadGraph.forget()`
  - `RoadGraph.of_pack(repo) -> RoadGraph`
  - `RoadGraph.build(repo, routes: Dictionary) -> RoadGraph`
  - `var nodes: Array[Vector2i]` (metres)
  - `var edges: Array`, where `edges[id]` is `Array` of `[to: int, length_m: int, kind: String, cost: int]`
  - `nearest(at_m: Vector2i, reached: Array = []) -> int`
  - `shortest(from_id: int) -> Dictionary` `{dist: Array[int], prev: Array[int]}` (dist −1 = unreached)
  - `route(tree: Dictionary, goal: int) -> Array` of `[x_m, y_m, kind]`, excluding the start node
  - `static factor_permille(repo, kind) -> int`
  - `static tier_permille(repo, at_m: Vector2) -> int`
  - `static stretch_need(length_m: int, factor: int) -> int`, where `factor` is a product out of 10⁹ and the result is in clear-road metres, rounded up

- [ ] **Step 1: Write the failing test** — `tests/engine/test_road_graph.gd`

```gdscript
extends GutTest
## The road network (spec 2026-09-27-courier-core §1). Fixtures in pack px on
## beria's measure (1 px = 1000 m). Every height tier is forced to 1000‰ so
## the hand sums hold whatever cells lie under the fixture.

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	RoadGraph.forget()
	repo.road_speed = {"road": 1000, "trail": 500, "offroad": 250, "sea": 625,
		"tier_plains": 1000, "tier_hills": 1000, "tier_mountains": 1000, "tier_peak": 1000}
	repo.balance["courier_graph_snap_px"] = 2.0


func after_all() -> void:
	RoadGraph.forget()


func _routes() -> Dictionary:
	return {
		"r1": {"group": "roads", "polyline": PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(20, 0)])},
		# joins r1 MID-LINE, a hair off its vertex: the snap merges them
		"r2": {"group": "trails", "polyline": PackedVector2Array([Vector2(10.4, 0.3), Vector2(10, 10)])},
		"r3": {"group": "trails", "polyline": PackedVector2Array([Vector2(100, 100), Vector2(110, 100)])},
		"r4": {"group": "searoutes", "polyline": PackedVector2Array([Vector2(20, 0), Vector2(100, 100)])},
	}


func test_the_snap_merges_a_mid_line_join() -> void:
	var g := RoadGraph.build(repo, _routes())
	# r1: 3 nodes; r2 adds only (10,10); r3: 2; the sea route adds nothing.
	assert_eq(g.nodes.size(), 6)


func test_the_fastest_route_and_its_cost_by_hand() -> void:
	var g := RoadGraph.build(repo, _routes())
	var a := g.nearest(Vector2i(0, 0))
	var b := g.nearest(Vector2i(10000, 10000))
	var tree := g.shortest(a)
	# road 10 km at 1000‰: 10,000 m -> 10,000 clear-road metres x 1000 units
	# trail 10 km at 500‰: 20,000 clear-road metres x 1000 units
	assert_eq(int(tree["dist"][b]), 10_000_000 + 20_000_000)
	assert_eq(g.route(tree, b), [[10000, 0, "road"], [10000, 10000, "trail"]])


func test_a_separate_network_is_unreached() -> void:
	var g := RoadGraph.build(repo, _routes())
	var tree := g.shortest(g.nearest(Vector2i(0, 0)))
	assert_eq(int(tree["dist"][g.nearest(Vector2i(110000, 100000))]), -1)
	assert_ne(g.nearest(Vector2i(110000, 100000), tree["dist"]), g.nearest(Vector2i(110000, 100000)),
		"among the reached, the nearest is on the capital's own network")


func test_stretch_need_rounds_up() -> void:
	assert_eq(RoadGraph.stretch_need(1000, 1_000_000_000), 1000)
	assert_eq(RoadGraph.stretch_need(1000, 500_000_000), 2000)
	assert_eq(RoadGraph.stretch_need(1, 3), 333_333_334)


func test_the_capital_reaches_nearly_the_whole_pack() -> void:
	var fresh := DataRepository.load_all("res://data")
	RoadGraph.forget()
	var g := RoadGraph.of_pack(fresh)
	var cap: Dictionary = fresh.burgs[String(fresh.kingdoms[fresh.resolve_realm("player_realm")]["capital_burg"])]
	var tree := g.shortest(g.nearest(ArmySystem.pack_to_metres(fresh, Vector2(float(cap["x"]), float(cap["y"])))))
	var reached := 0
	for d: int in tree["dist"]:
		if d >= 0:
			reached += 1
	assert_gt(float(reached) / float(g.nodes.size()), 0.95, "97% of nodes are one component (2026-09-27)")
	RoadGraph.forget()
```

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL (`RoadGraph` not found).

- [ ] **Step 3: Write `scripts/engine/road_graph.gd`**

```gdscript
class_name RoadGraph
extends RefCounted
## The pack's land routes as one network (spec 2026-09-27-courier-core §1):
## roads and trails, their polyline vertices snapped to a courier_graph_snap_px
## grid and merged into nodes. The routes join each other MID-LINE, so by
## their burg endpoints alone the network falls into dozens of pieces; by
## shared vertices 97% of it is one. Positions are the pack's whole METRES
## (ArmySystem); an edge's cost is its clear-road metres x 1000, so a metre of
## road on the plain costs 1000. Cached per pack, forgotten by load_map.
## Weather is not in the cost: the route is chosen once, on the static
## network; the weather changes the pace along it day by day.

const GROUPS := {"roads": "road", "trails": "trail"}

var nodes: Array[Vector2i] = []
var edges: Array = []

static var _cached: RoadGraph = null
static var _cached_map := ""


static func forget() -> void:
	_cached = null
	_cached_map = ""


static func of_pack(repo: DataRepository) -> RoadGraph:
	if _cached == null or _cached_map != repo.map_id:
		_cached = build(repo, repo.routes)
		_cached_map = repo.map_id
	return _cached


static func build(repo: DataRepository, routes: Dictionary) -> RoadGraph:
	var g := RoadGraph.new()
	var snap := maxf(repo.bal("courier_graph_snap_px"), 0.001)
	var index: Dictionary = {}
	var codes := routes.keys()
	codes.sort()
	for code in codes:
		var r: Dictionary = routes[code]
		var group := String(r.get("group", ""))
		if not GROUPS.has(group):
			continue
		var prev := -1
		for p: Vector2 in r["polyline"]:
			var key := Vector2i(roundi(p.x / snap), roundi(p.y / snap))
			var id: int = index.get(key, -1)
			if id < 0:
				id = g.nodes.size()
				index[key] = id
				g.nodes.append(ArmySystem.pack_to_metres(repo, p))
				g.edges.append([])
			if prev >= 0 and prev != id:
				g._link(repo, prev, id, String(GROUPS[group]))
			prev = id
	return g


static func factor_permille(repo: DataRepository, kind: String) -> int:
	return maxi(1, int(repo.road_speed.get(kind, 1000)))


## The height tier's per mille at a point in metres; 1000 off the land.
static func tier_permille(repo: DataRepository, at_m: Vector2) -> int:
	var cell := MapEconomy.cell_at(repo, ArmySystem.metres_to_pack(repo, Vector2i(at_m)))
	if not repo.cells.has(cell):
		return 1000
	var tier := String(Elevation.tier_of(repo, float(repo.cells[cell]["height"]))["tier"])
	return maxi(1, int(repo.road_speed.get("tier_" + tier, 1000)))


## Clear-road metres a stretch takes, rounded up: length x 10^9 / factor,
## the factor a product of per-milles out of 10^9 (segment x tier x weather).
static func stretch_need(length_m: int, factor: int) -> int:
	var f := maxi(1, factor)
	@warning_ignore("integer_division")  # rounded up, whole metres
	return (length_m * 1_000_000_000 + f - 1) / f


func _link(repo: DataRepository, a: int, b: int, kind: String) -> void:
	var length := int(round(Vector2(nodes[a]).distance_to(Vector2(nodes[b]))))
	var mid := (Vector2(nodes[a]) + Vector2(nodes[b])) * 0.5
	# cost units: clear-road metres x 1000, the weather held at 1000‰
	var cost := stretch_need(length, factor_permille(repo, kind) * tier_permille(repo, mid) * 1000) * 1000
	for e: Array in edges[a]:
		if int(e[0]) == b:
			if cost < int(e[3]):
				_set_edge(e, length, kind, cost)
				for f: Array in edges[b]:
					if int(f[0]) == a:
						_set_edge(f, length, kind, cost)
			return
	edges[a].append([b, length, kind, cost])
	edges[b].append([a, length, kind, cost])


static func _set_edge(e: Array, length: int, kind: String, cost: int) -> void:
	e[1] = length
	e[2] = kind
	e[3] = cost


## The node nearest a point, the lowest id on a tie; among `reached` only
## (a shortest() dist array: -1 = unreached) when one is given. -1 if none.
func nearest(at_m: Vector2i, reached: Array = []) -> int:
	var best := -1
	var best_d := INF
	for id in nodes.size():
		if not reached.is_empty() and int(reached[id]) < 0:
			continue
		var d := Vector2(nodes[id]).distance_squared_to(Vector2(at_m))
		if d < best_d:
			best_d = d
			best = id
	return best


## Dijkstra from one node over a binary heap of [cost, id] (ties by id).
func shortest(from_id: int) -> Dictionary:
	var n := nodes.size()
	var dist: Array[int] = []
	var prev: Array[int] = []
	dist.resize(n)
	dist.fill(-1)
	prev.resize(n)
	prev.fill(-1)
	if from_id < 0 or from_id >= n:
		return {"dist": dist, "prev": prev}
	var heap: Array = []
	dist[from_id] = 0
	_push(heap, [0, from_id])
	while not heap.is_empty():
		var top: Array = _pop(heap)
		var d := int(top[0])
		var u := int(top[1])
		if d != dist[u]:
			continue
		for e: Array in edges[u]:
			var v := int(e[0])
			var nd := d + int(e[3])
			if dist[v] < 0 or nd < dist[v]:
				dist[v] = nd
				prev[v] = u
				_push(heap, [nd, v])
	return {"dist": dist, "prev": prev}


## The waypoints from the tree's start to `goal`, each [x_m, y_m, kind of the
## edge into it]; the start node itself is not included.
func route(tree: Dictionary, goal: int) -> Array:
	var prev: Array = tree["prev"]
	var chain: Array[int] = []
	var at := goal
	while at >= 0:
		chain.push_front(at)
		at = int(prev[at])
	var out: Array = []
	for i in range(1, chain.size()):
		out.append([nodes[chain[i]].x, nodes[chain[i]].y, _kind_between(chain[i - 1], chain[i])])
	return out


func _kind_between(u: int, v: int) -> String:
	for e: Array in edges[u]:
		if int(e[0]) == v:
			return String(e[2])
	return "offroad"


static func _less(a: Array, b: Array) -> bool:
	return int(a[0]) < int(b[0]) or (int(a[0]) == int(b[0]) and int(a[1]) < int(b[1]))


static func _push(h: Array, item: Array) -> void:
	h.append(item)
	var i := h.size() - 1
	while i > 0:
		@warning_ignore("integer_division")  # the heap's parent index
		var p := (i - 1) / 2
		if not _less(h[i], h[p]):
			break
		var t: Array = h[i]
		h[i] = h[p]
		h[p] = t
		i = p


static func _pop(h: Array) -> Array:
	var top: Array = h[0]
	var last: Array = h.pop_back()
	if h.is_empty():
		return top
	h[0] = last
	var i := 0
	while true:
		var l := 2 * i + 1
		var r := l + 1
		var m := i
		if l < h.size() and _less(h[l], h[m]):
			m = l
		if r < h.size() and _less(h[r], h[m]):
			m = r
		if m == i:
			break
		var t: Array = h[i]
		h[i] = h[m]
		h[m] = t
		i = m
	return top
```

**How the cost is computed.** `stretch_need(length, seg‰ × tier‰ × 1000)` gives the clear-road metres, with weather held at 1000‰. Multiplying by 1000 gives cost units, so a road metre on the plain costs 1000. This is why the test's 10 km road costs 10,000,000.

Add `RoadGraph.forget()` to `load_map`'s forget list.

- [ ] **Step 4: Run the test to verify it passes.** Expected: PASS.
- [ ] **Step 5: Commit**

```bash
git add scripts/engine/road_graph.gd scripts/engine/data_repository.gd tests/engine/test_road_graph.gd
git commit -m "feat(couriers): the pack's roads and trails as one network with Dijkstra"
```

---

### Task 4: CourierSystem — origin, path, dispatch, estimates

**Files:**
- Create: `scripts/engine/courier_system.gd`
- Modify: `scripts/engine/game_state.gd` (add `var couriers: Array = []`, `var next_courier_id := 0` beside `regiments`; saving is in Task 5)
- Test: `tests/engine/test_courier_dispatch.gd`

**Interfaces:**
- Consumes:
  - `RoadGraph` (Task 3), `Weather` (Task 2);
  - `ArmySystem.regiment/position_of/pack_to_metres/metres_to_pack/state_of`;
  - `MapOwnership.owner_of(data, state, province)`;
  - `MapManors.home_province/controlled_provinces`.
- Produces:
  - `CourierSystem.ORDINARY := "ordinary"`, `SECRET := "secret"`
  - `carries_orders(reg: Dictionary) -> bool` (false for a fleet)
  - `fee_gold(repo, kind) -> int`
  - `day_budget(repo, kind) -> int` (clear-road metres a day)
  - `origin(repo, state) -> Vector2` (pack px)
  - `path_between(repo, from_px: Vector2, to_px: Vector2) -> Array` of `[x_m, y_m, kind]`
  - `stretch_factor(repo, kind: String, at_m: Vector2i, weather: String) -> int` (out of 10⁹)
  - `need_along(repo, state, from_m: Vector2i, path: Array, abs_day: int) -> int`
  - `days_for(repo, kind, need: int) -> int` (≥ 1)
  - `dispatch(repo, state, kind: String, code: String, order: Dictionary) -> Dictionary` (the courier)
  - `days_left(repo, state, c: Dictionary) -> int`
  - `eta_days(repo, state, kind: String, code: String) -> int`
- **The courier Dictionary** (stored in `GameState.couriers`, JSON-safe, all ints but `kind` / `target` / path kinds):
  - `id`, `kind`
  - `x_m`, `y_m`
  - `path` (`[[x_m, y_m, kind], …]`)
  - `target` (regiment code)
  - `order` (`{action_code, dest_x_m?, dest_y_m?}`)
  - `issued` (absolute day)
  - `aim_x_m`, `aim_y_m`
  - `days` (days ridden)
  - `day_m` (metres ridden on the last day, for drawing)
  - `slow_spell` (−1 or the last spell a slow-down was announced)

- [ ] **Step 1: Write the failing test** — `tests/engine/test_courier_dispatch.gd`

```gdscript
extends GutTest
## Dispatch (spec 2026-09-27-courier-core §1): from the capital, along the
## road network, to the regiment where it stands.

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	RoadGraph.forget()
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _skies(kind: String) -> void:
	for key in repo.weather_odds:
		var w: Dictionary = {}
		for k: String in repo.weather_kinds:
			w[k] = 1 if k == kind else 0
		repo.weather_odds[key] = w


func _marcher() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(repo, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


func _capital_px() -> Vector2:
	var b: Dictionary = repo.burgs[String(repo.kingdoms[repo.resolve_realm("player_realm")]["capital_burg"])]
	return Vector2(float(b["x"]), float(b["y"]))


func test_a_courier_rides_from_the_capital_to_the_regiment() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	var c := CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	var home := ArmySystem.pack_to_metres(repo, _capital_px())
	assert_eq(Vector2i(int(c["x_m"]), int(c["y_m"])), home, "he sets out from the capital")
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)))
	var last: Array = (c["path"] as Array).back()
	assert_eq(Vector2i(int(last[0]), int(last[1])), at, "his road ends at the column")
	assert_eq(int(c["id"]), 1)
	assert_eq(s.next_courier_id, 1)
	assert_eq(s.couriers.size(), 1)
	assert_eq(int(c["days"]), 0)
	assert_eq(String(c["target"]), code)


func test_most_of_the_way_is_on_the_roads() -> void:
	var s := GameState.new_campaign(repo, 7)
	var c := CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, _marcher(), {"action_code": "ARMY_GARRISON"})
	var kinds: Dictionary = {}
	for p: Array in c["path"]:
		kinds[String(p[2])] = true
	for k: String in kinds:
		assert_true(k in ["road", "trail", "offroad", "sea"], k)


func test_the_capital_lost_he_rides_from_the_realms_largest_town() -> void:
	var s := GameState.new_campaign(repo, 7)
	var realm := repo.resolve_realm("player_realm")
	var cap_code := String(repo.kingdoms[realm]["capital_burg"])
	var prov := String(repo.burgs[cap_code]["province_code"])
	var other := ""
	var ks := repo.kingdoms.keys()
	ks.sort()
	for k: String in ks:
		if k != realm:
			other = k
			break
	MapOwnership.set_owner(repo, s, prov, other, "test: the capital falls")
	var from := CourierSystem.origin(repo, s)
	assert_ne(from, _capital_px(), "not from a capital the realm no longer holds")
	var held := false
	for b: Dictionary in repo.burgs.values():
		if Vector2(float(b["x"]), float(b["y"])) == from:
			held = MapOwnership.owner_of(repo, s, String(b["province_code"])) == realm
	assert_true(held, "from a town of the realm")


func test_need_along_a_path_by_hand() -> void:
	var s := GameState.new_campaign(repo, 7)
	_skies("clear")
	repo.road_speed = {"road": 1000, "trail": 800, "offroad": 500, "sea": 625,
		"tier_plains": 1000, "tier_hills": 1000, "tier_mountains": 1000, "tier_peak": 1000}
	# 100 km of road + 100 km across country at 500‰ = 100,000 + 200,000.
	var path := [[100000, 0, "road"], [200000, 0, "offroad"]]
	assert_eq(CourierSystem.need_along(repo, s, Vector2i(0, 0), path, 10), 300000)
	# 160 km a day at 1000‰: 300,000 / 160,000 -> 2 days, rounded up.
	assert_eq(CourierSystem.days_for(repo, CourierSystem.ORDINARY, 300000), 2)
	assert_eq(CourierSystem.days_for(repo, CourierSystem.ORDINARY, 0), 1, "never less than a day")
	assert_eq(CourierSystem.days_for(repo, CourierSystem.SECRET, 300000), 3, "750‰: 120 km a day")


func test_the_estimate_is_the_dispatched_couriers() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	var eta := CourierSystem.eta_days(repo, s, CourierSystem.ORDINARY, code)
	var c := CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	assert_eq(CourierSystem.days_left(repo, s, c), eta)
	assert_gt(eta, 0)


func test_a_fleet_takes_no_courier() -> void:
	assert_false(CourierSystem.carries_orders({"is_naval": "1"}))
	assert_true(CourierSystem.carries_orders({"is_naval": "0"}))
```

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL (`CourierSystem` not found).

- [ ] **Step 3: Add the state fields** in `scripts/engine/game_state.gd`, beside `var regiments`:

```gdscript
## The couriers on the road (owner 2026-09-27, CourierSystem): an Array of
## Dictionaries in whole metres and ints, walked in ascending id order.
var couriers: Array = []
## The last courier id handed out; a higher id is a NEWER order.
var next_courier_id := 0
```

- [ ] **Step 4: Write `scripts/engine/courier_system.gd`**, dispatch half. The ride half comes in Task 5.

```gdscript
class_name CourierSystem
extends RefCounted
## Couriers (owner 2026-09-27, spec docs/superpowers/specs/2026-09-27-courier-core-design.md):
## an order to a regiment rides from the capital and takes effect only when
## the courier reaches the column. One courier per order, gone on delivery.
## The route is the road network's fastest (RoadGraph); the pace each day is
## the stretch's kind, the height tier it starts on and the province's
## weather (Weather). Whole metres and whole per-mille throughout; couriers
## ride in id order.

const ORDINARY := "ordinary"
const SECRET := "secret"


## Whether a regiment's orders ride by courier: every land regiment; a fleet
## is exempt in this sub-project (spec §1).
static func carries_orders(reg: Dictionary) -> bool:
	return String(reg.get("is_naval", "0")) != "1"


static func fee_gold(repo: DataRepository, kind: String) -> int:
	return int((repo.courier_kinds.get(kind, {}) as Dictionary).get("fee_gold", 0))


## Clear-road metres a courier of this kind rides in a day.
static func day_budget(repo: DataRepository, kind: String) -> int:
	return int(repo.bal("courier_base_km_per_day")) \
		* int((repo.courier_kinds.get(kind, {}) as Dictionary).get("speed_permille", 1000))


## Where couriers ride from, in pack px: the realm's capital while the realm
## holds its province; else the most populous town of the realm, the
## crown's home and controlled provinces first, then any province it holds.
static func origin(repo: DataRepository, state: GameState) -> Vector2:
	var realm := repo.resolve_realm("player_realm")
	var cap := String((repo.kingdoms.get(realm, {}) as Dictionary).get("capital_burg", ""))
	if repo.burgs.has(cap) and _holds(repo, state, String(repo.burgs[cap]["province_code"]), realm):
		return _burg_px(repo.burgs[cap])
	var order: Array = []
	var home := MapManors.home_province(repo, state)
	if home != "":
		order.append(home)
	for p: String in MapManors.controlled_provinces(repo, state):
		if not p in order:
			order.append(p)
	var rest := repo.provinces.keys()
	rest.sort()
	for p: String in rest:
		if not p in order:
			order.append(p)
	var codes := repo.burgs.keys()
	codes.sort()
	for p: String in order:
		if not _holds(repo, state, p, realm):
			continue
		var best := ""
		var best_pop := -1
		for b: String in codes:
			var row: Dictionary = repo.burgs[b]
			if String(row["province_code"]) != p:
				continue
			var pop := int(float(row["population"]))
			if pop > best_pop:
				best = b
				best_pop = pop
		if best != "":
			return _burg_px(repo.burgs[best])
	return _burg_px(repo.burgs[cap]) if repo.burgs.has(cap) else Vector2.ZERO


static func _holds(repo: DataRepository, state: GameState, province: String, realm: String) -> bool:
	return MapOwnership.owner_of(repo, state, province) == realm


static func _burg_px(b: Dictionary) -> Vector2:
	return Vector2(float(b["x"]), float(b["y"]))


## The waypoints from one point to another, [x_m, y_m, kind] each (the kind
## of the stretch INTO it): across country to the nearest road node, the
## network's fastest route to the reached node nearest the target, across
## country (or by sea) to the target. Farther than courier_offroad_max_km
## from any node: one straight leg.
static func path_between(repo: DataRepository, from_px: Vector2, to_px: Vector2) -> Array:
	var a := ArmySystem.pack_to_metres(repo, from_px)
	var b := ArmySystem.pack_to_metres(repo, to_px)
	var g := RoadGraph.of_pack(repo)
	var reach := float(repo.bal("courier_offroad_max_km")) * 1000.0
	var start := g.nearest(a)
	if start < 0 or Vector2(a).distance_to(Vector2(g.nodes[start])) > reach:
		return [[b.x, b.y, _leg_kind(repo, a, b)]]
	var tree := g.shortest(start)
	var goal := g.nearest(b, tree["dist"])
	var way: Array = [[g.nodes[start].x, g.nodes[start].y, _leg_kind(repo, a, g.nodes[start])]]
	way.append_array(g.route(tree, goal))
	way.append([b.x, b.y, _leg_kind(repo, g.nodes[goal], b)])
	return way


## "offroad", or "sea" when any sample every courier_sea_sample_km along the
## leg is off the land grid (MapEconomy.cell_at < 0, the land/sea test
## ActionSystem uses).
static func _leg_kind(repo: DataRepository, a: Vector2i, b: Vector2i) -> String:
	var step := maxf(repo.bal("courier_sea_sample_km") * 1000.0, 1.0)
	var length := Vector2(a).distance_to(Vector2(b))
	for i in range(1, int(length / step) + 1):
		var p := Vector2(a).lerp(Vector2(b), float(i) * step / length)
		if MapEconomy.cell_at(repo, ArmySystem.metres_to_pack(repo, Vector2i(p))) < 0:
			return "sea"
	return "offroad"


## A stretch's pace as a product of per-milles out of 10^9: its kind x the
## height tier where it starts (none at sea) x the weather there.
static func stretch_factor(repo: DataRepository, kind: String, at_m: Vector2i, weather: String) -> int:
	var tier := 1000 if kind == "sea" else RoadGraph.tier_permille(repo, Vector2(at_m))
	return RoadGraph.factor_permille(repo, kind) * tier * Weather.speed_permille(repo, weather)


## Clear-road metres from a point along a path, each stretch at its start's
## weather on `abs_day`.
static func need_along(repo: DataRepository, state: GameState, from_m: Vector2i, path: Array,
		abs_day: int) -> int:
	var need := 0
	var here := from_m
	for p: Array in path:
		var to := Vector2i(int(p[0]), int(p[1]))
		var wx := Weather.at(repo, state, ArmySystem.metres_to_pack(repo, here), abs_day)
		need += RoadGraph.stretch_need(int(round(Vector2(here).distance_to(Vector2(to)))),
			stretch_factor(repo, String(p[2]), here, wx))
		here = to
	return need


## Whole days to ride `need` clear-road metres, rounded up, at least one.
static func days_for(repo: DataRepository, kind: String, need: int) -> int:
	var b := maxi(1, day_budget(repo, kind))
	@warning_ignore("integer_division")  # whole days, rounded up
	return maxi(1, (need + b - 1) / b)


## Send a courier of `kind` with `order` for regiment `code`. Charges
## nothing: the fee is ActionSystem's ledger line.
static func dispatch(repo: DataRepository, state: GameState, kind: String, code: String,
		order: Dictionary) -> Dictionary:
	var from := origin(repo, state)
	var at := ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code))
	var home := ArmySystem.pack_to_metres(repo, from)
	var aim := ArmySystem.pack_to_metres(repo, at)
	state.next_courier_id += 1
	var c := {
		"id": state.next_courier_id, "kind": kind, "x_m": home.x, "y_m": home.y,
		"path": path_between(repo, from, at), "target": code, "order": order.duplicate(true),
		"issued": state.absolute_day(), "aim_x_m": aim.x, "aim_y_m": aim.y,
		"days": 0, "day_m": 0, "slow_spell": -1,
	}
	state.couriers.append(c)
	return c


## Days a courier still has to ride, today's weather held.
static func days_left(repo: DataRepository, state: GameState, c: Dictionary) -> int:
	return days_for(repo, String(c["kind"]), need_along(repo, state,
		Vector2i(int(c["x_m"]), int(c["y_m"])), c["path"], state.absolute_day()))


## The aim ruler's estimate (spec §1): days for a courier sent now to reach
## the regiment, the route and today's weather held. 0 for no regiment.
static func eta_days(repo: DataRepository, state: GameState, kind: String, code: String) -> int:
	var reg := ArmySystem.regiment(repo, code)
	if reg.is_empty():
		return 0
	var from := origin(repo, state)
	var path := path_between(repo, from, ArmySystem.position_of(repo, state, reg))
	return days_for(repo, kind, need_along(repo, state, ArmySystem.pack_to_metres(repo, from),
		path, state.absolute_day()))
```

- [ ] **Step 5: Run the test to verify it passes.** Expected: PASS.
- [ ] **Step 6: Commit**

```bash
git add scripts/engine/courier_system.gd scripts/engine/game_state.gd tests/engine/test_courier_dispatch.gd
git commit -m "feat(couriers): dispatch from the capital along the road network, with estimates"
```

---

### Task 5: CourierSystem — the day's ride, delivery, save, tick

**Files:**
- Modify: `scripts/engine/courier_system.gd` (append the ride half)
- Modify: `scripts/engine/game_state.gd` (`to_dict` / `from_dict`)
- Modify: `scripts/engine/tick_engine.gd` (ride before `march_day` in `advance_day` and `advance`; `var day_couriers`)
- Test: `tests/engine/test_courier_ride.gd`

**Interfaces:**
- Consumes: Task 4's API; `ArmySystem.set_march/set_garrison`.
- Produces:
  - `CourierSystem.ride_day(repo, state) -> Array` of events `{type, courier: int, regiment: String, weather: String}`. `type` is one of `delivered`, `stale`, `lost`, `fuse`, `slow`.
  - `CourierSystem.pending_for(state, code) -> Dictionary`, the newest courier riding for that regiment, or `{}`.
  - `CourierSystem.headline(repo, e: Dictionary) -> String`
  - `TickEngine.day_couriers: Array`
  - A regiment entry gains `order_id: int`, the id of the courier whose order it obeys.

- [ ] **Step 1: Write the failing test** — `tests/engine/test_courier_ride.gd`

```gdscript
extends GutTest
## A day's ride and delivery (spec 2026-09-27-courier-core §1). Every
## height tier and the weather are forced so the hand sums hold.

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	RoadGraph.forget()
	Weather.forget()
	repo.road_speed = {"road": 1000, "trail": 800, "offroad": 500, "sea": 625,
		"tier_plains": 1000, "tier_hills": 1000, "tier_mountains": 1000, "tier_peak": 1000}
	_skies("clear")


func after_all() -> void:
	RoadGraph.forget()


func _skies(kind: String) -> void:
	for key in repo.weather_odds:
		var w: Dictionary = {}
		for k: String in repo.weather_kinds:
			w[k] = 1 if k == kind else 0
		repo.weather_odds[key] = w


func _marcher() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(repo, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


## A hand-built courier on a straight road, re-aim switched off.
func _courier(s: GameState, id: int, code: String, path: Array, order: Dictionary) -> Dictionary:
	repo.balance["courier_reaim_m"] = 1.0e12
	var c := {"id": id, "kind": "ordinary", "x_m": 0, "y_m": 0, "path": path, "target": code,
		"order": order, "issued": 1, "aim_x_m": 0, "aim_y_m": 0, "days": 0, "day_m": 0, "slow_spell": -1}
	s.couriers.append(c)
	s.next_courier_id = maxi(s.next_courier_id, id)
	return c


func test_a_days_ride_by_hand() -> void:
	var s := GameState.new_campaign(repo, 7)
	var c := _courier(s, 1, _marcher(), [[100000, 0, "road"], [400000, 0, "offroad"]],
		{"action_code": "ARMY_GARRISON"})
	# Day 1: 160,000 of budget. 100 km of road costs 100,000; 60,000 left at
	# 500‰ across country carries him 30 km more.
	assert_eq(CourierSystem.ride_day(repo, s), [])
	assert_eq(Vector2i(int(c["x_m"]), int(c["y_m"])), Vector2i(130000, 0))
	assert_eq(int(c["day_m"]), 130000)
	# Days 2-4: 80 km each across country.
	for i in 3:
		CourierSystem.ride_day(repo, s)
	assert_eq(int(c["x_m"]), 370000)
	# Day 5: 30 km left costs 60,000; he arrives and delivers.
	var ev := CourierSystem.ride_day(repo, s)
	assert_eq(ev.size(), 1)
	assert_eq(String(ev[0]["type"]), "delivered")
	assert_eq(s.couriers, [], "gone on delivery")


func test_delivery_applies_the_order_on_that_day_and_not_before() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	var dest := Vector2i(123000, 456000)
	_courier(s, 1, code, [[200000, 0, "road"]], {"action_code": "ARMY_MARCH", "dest_x_m": dest.x, "dest_y_m": dest.y})
	CourierSystem.ride_day(repo, s)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_GARRISON, "still on the road")
	CourierSystem.ride_day(repo, s)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH)
	assert_eq(ArmySystem.pack_to_metres(repo, ArmySystem.destination_of(repo, s, code)), dest)
	assert_eq(int(s.regiments[code]["order_id"]), 1)


func test_an_older_order_arriving_late_is_set_aside() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	# id 1 (march) has far to go; id 2 (garrison, newer) arrives first.
	_courier(s, 1, code, [[400000, 0, "road"]], {"action_code": "ARMY_MARCH", "dest_x_m": 5000, "dest_y_m": 5000})
	_courier(s, 2, code, [[10000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	var first := CourierSystem.ride_day(repo, s)
	assert_eq(String(first[0]["type"]), "delivered")
	assert_eq(int(first[0]["courier"]), 2)
	var later: Array = []
	for i in 3:
		later.append_array(CourierSystem.ride_day(repo, s))
	assert_eq(String(later[0]["type"]), "stale", "the older order is set aside")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_GARRISON, "the newer order stands")


func test_a_vanished_regiment_leaves_the_orders_undelivered() -> void:
	var s := GameState.new_campaign(repo, 7)
	_courier(s, 1, "no_such_regiment", [[10000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	var ev := CourierSystem.ride_day(repo, s)
	assert_eq(String(ev[0]["type"]), "lost")
	assert_eq(s.couriers, [])


func test_the_fuse() -> void:
	var s := GameState.new_campaign(repo, 7)
	repo.balance["courier_max_days"] = 2.0
	_courier(s, 1, _marcher(), [[9000000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	assert_eq(CourierSystem.ride_day(repo, s), [])
	assert_eq(CourierSystem.ride_day(repo, s), [])
	assert_eq(String(CourierSystem.ride_day(repo, s)[0]["type"]), "fuse")
	assert_eq(s.couriers, [])


func test_bad_weather_slows_him_and_is_announced_once_a_spell() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	# He rides on land so the weather applies: from the regiment's own spot.
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)))
	_skies("blizzard")
	var c := _courier(s, 1, code, [[at.x + 900000, at.y, "road"]], {"action_code": "ARMY_GARRISON"})
	c["x_m"] = at.x
	c["y_m"] = at.y
	var ev := CourierSystem.ride_day(repo, s)
	assert_eq(String(ev[0]["type"]), "slow")
	assert_eq(String(ev[0]["weather"]), "blizzard")
	# 160,000 x 400‰ = 64 km in a blizzard, the tiers forced to 1000.
	assert_eq(int(c["x_m"]) - at.x, 64000)
	assert_eq(CourierSystem.ride_day(repo, s), [], "said once for the spell")


func test_a_courier_catches_a_column_on_the_march() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	var reg := ArmySystem.regiment(repo, code)
	var home: Vector2 = ArmySystem.position_of(repo, s, reg)
	var far := home + Vector2(300.0, 0.0)
	ArmySystem.set_march(repo, s, code, far)
	CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	for day in int(repo.bal("courier_max_days")):
		CourierSystem.ride_day(repo, s)
		if s.couriers.is_empty():
			break
		ArmySystem.march_day(repo, s)
	assert_eq(s.couriers, [], "he caught them")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_GARRISON)
	assert_lt(ArmySystem.position_of(repo, s, reg).distance_to(home), 300.0, "halted short of where they were going")


func test_a_ride_survives_a_save_mid_road() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	CourierSystem.ride_day(repo, s)
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(copy.next_courier_id, s.next_courier_id)
	for i in 3:
		CourierSystem.ride_day(repo, s)
		CourierSystem.ride_day(repo, copy)
	assert_eq(JSON.stringify(copy.to_dict()), JSON.stringify(s.to_dict()))


func test_headlines() -> void:
	var code := _marcher()
	var label := String(ArmySystem.regiment(repo, code)["label"])
	assert_eq(CourierSystem.headline(repo, {"type": "delivered", "regiment": code}), "Orders delivered to %s." % label)
	assert_string_contains(CourierSystem.headline(repo, {"type": "slow", "regiment": code, "weather": "snow"}), "snow")
	assert_string_contains(CourierSystem.headline(repo, {"type": "stale", "regiment": code}), "set aside")
	assert_string_contains(CourierSystem.headline(repo, {"type": "lost", "regiment": code}), "undelivered")
	assert_string_contains(CourierSystem.headline(repo, {"type": "fuse", "regiment": code}), "undelivered")
```

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL (`ride_day` not found).

- [ ] **Step 3: Append the ride half to `scripts/engine/courier_system.gd`**

```gdscript
## One DAY on the road for every courier, in id order (TickEngine, before the
## regiments march). Returns the day's events for the news bar.
static func ride_day(repo: DataRepository, state: GameState) -> Array:
	var events: Array = []
	var today := state.absolute_day()
	var list: Array = state.couriers.duplicate()
	list.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	var keep: Array = []
	for c: Dictionary in list:
		if _ride(repo, state, c, today, events):
			keep.append(c)
	state.couriers = keep
	return events


## One courier's day; false when he is done (delivered, lost, or out of time).
static func _ride(repo: DataRepository, state: GameState, c: Dictionary, today: int, events: Array) -> bool:
	var code := String(c["target"])
	var reg := ArmySystem.regiment(repo, code)
	if reg.is_empty() or ArmySystem.state_of(repo, state, code).is_empty():
		events.append(_event("lost", c))
		return false
	c["days"] = int(c.get("days", 0)) + 1
	if int(c["days"]) > int(repo.bal("courier_max_days")):
		events.append(_event("fuse", c))
		return false
	_reaim(repo, state, c, reg)
	var budget := day_budget(repo, String(c["kind"]))
	var here := Vector2i(int(c["x_m"]), int(c["y_m"]))
	var start := here
	var path: Array = c["path"]
	while not path.is_empty() and budget > 0:
		var to := Vector2i(int(path[0][0]), int(path[0][1]))
		var wx := Weather.at(repo, state, ArmySystem.metres_to_pack(repo, here), today)
		_note_slow(repo, c, wx, today, events)
		var f := stretch_factor(repo, String(path[0][2]), here, wx)
		var length := int(round(Vector2(here).distance_to(Vector2(to))))
		var need := RoadGraph.stretch_need(length, f)
		if need <= budget:
			budget -= need
			here = to
			path.pop_front()
			continue
		@warning_ignore("integer_division")  # whole metres into the stretch
		var adv := budget * f / 1_000_000_000
		if length > 0:
			var way := (Vector2(to) - Vector2(here)) / float(length)
			here = Vector2i(roundi(float(here.x) + way.x * float(adv)), roundi(float(here.y) + way.y * float(adv)))
		budget = 0
	c["day_m"] = int(round(Vector2(start).distance_to(Vector2(here))))
	c["x_m"] = here.x
	c["y_m"] = here.y
	if path.is_empty():
		events.append(_deliver(repo, state, c))
		return false
	return true


## The column has moved more than courier_reaim_m since his road was set:
## his last leg now ends where it stands (a column is far slower than a
## courier, so the road itself is not re-planned).
static func _reaim(repo: DataRepository, state: GameState, c: Dictionary, reg: Dictionary) -> void:
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state, reg))
	if Vector2(at).distance_to(Vector2(int(c["aim_x_m"]), int(c["aim_y_m"]))) <= repo.bal("courier_reaim_m"):
		return
	c["aim_x_m"] = at.x
	c["aim_y_m"] = at.y
	var path: Array = c["path"]
	if path.is_empty():
		path.append([at.x, at.y, "offroad"])
	else:
		path[path.size() - 1] = [at.x, at.y, String(path[path.size() - 1][2])]


static func _note_slow(repo: DataRepository, c: Dictionary, weather: String, today: int, events: Array) -> void:
	if Weather.speed_permille(repo, weather) >= int(repo.bal("courier_slow_news_permille")):
		return
	var spell := Weather.spell_of(repo, today)
	if int(c.get("slow_spell", -1)) == spell:
		return
	c["slow_spell"] = spell
	events.append(_event("slow", c, weather))


## The order takes effect — unless the column already obeys a NEWER one (a
## higher courier id), in which case this one is set aside.
static func _deliver(repo: DataRepository, state: GameState, c: Dictionary) -> Dictionary:
	var code := String(c["target"])
	var entry: Dictionary = state.regiments.get(code, {})
	if int(entry.get("order_id", 0)) > int(c["id"]):
		return _event("stale", c)
	var order: Dictionary = c["order"]
	match String(order.get("action_code", "")):
		"ARMY_MARCH":
			ArmySystem.set_march(repo, state, code, ArmySystem.metres_to_pack(repo,
				Vector2i(int(order["dest_x_m"]), int(order["dest_y_m"]))))
		"ARMY_GARRISON":
			ArmySystem.set_garrison(repo, state, code)
	if state.regiments.has(code):
		state.regiments[code]["order_id"] = int(c["id"])
	return _event("delivered", c)


static func _event(type: String, c: Dictionary, weather: String = "") -> Dictionary:
	return {"type": type, "courier": int(c["id"]), "regiment": String(c["target"]), "weather": weather}


## The newest courier riding for a regiment, {} when none.
static func pending_for(state: GameState, code: String) -> Dictionary:
	var best: Dictionary = {}
	if state == null:
		return best
	for c: Dictionary in state.couriers:
		if String(c["target"]) == code and (best.is_empty() or int(c["id"]) > int(best["id"])):
			best = c
	return best


## The news bar's line for a ride_day event.
static func headline(repo: DataRepository, e: Dictionary) -> String:
	var label := String(ArmySystem.regiment(repo, String(e.get("regiment", ""))).get("label", e.get("regiment", "")))
	match String(e.get("type", "")):
		"delivered":
			return "Orders delivered to %s." % label
		"stale":
			return "Older orders to %s came after newer ones and were set aside." % label
		"lost":
			return "Orders to %s undelivered: the regiment is gone." % label
		"fuse":
			return "Orders to %s undelivered: the courier never found them." % label
		"slow":
			return "The courier to %s is held up by %s." % [label, Weather.label_of(repo, String(e.get("weather", ""))).to_lower()]
	return ""
```

- [ ] **Step 4: Save and load.** In `GameState.to_dict`, add beside `"regiments"`:

```gdscript
		"couriers": _encode_values(couriers.duplicate(true)),
		"next_courier_id": _encode_values(next_courier_id),
```

In `from_dict`, beside `s.regiments = ...`:

```gdscript
	# Saves from before the couriers carry neither key: no one is on the road.
	s.couriers = _decode_values(d.get("couriers", []))
	s.next_courier_id = int(_decode_values(d.get("next_courier_id", 0)))
```

- [ ] **Step 5: Ride in the tick.** In `scripts/engine/tick_engine.gd`:
  - In `advance_day`, before `day_arrivals = ArmySystem.march_day(data, state)`, add:

    ```gdscript
    	# The couriers ride before the columns march (owner 2026-09-27): an order
    	# delivered today is marched on today.
    	day_couriers = CourierSystem.ride_day(data, state)
    ```

  - Add the same two lines before the `march_day` in `advance`.
  - Declare the variable under `var day_arrivals`:

    ```gdscript
    ## The couriers' events of the last day (CourierSystem.ride_day), for the news bar.
    var day_couriers: Array = []
    ```

- [ ] **Step 6: Run the tests.** Run `tests/engine/test_courier_ride.gd`, then the whole suite (`./run_tests.sh`). Expected: PASS with the expected error count. `test_determinism.gd` must still pass: no couriers exist in its script, so its hashes do not move.
- [ ] **Step 7: Commit**

```bash
git add scripts/engine/courier_system.gd scripts/engine/game_state.gd scripts/engine/tick_engine.gd tests/engine/test_courier_ride.gd
git commit -m "feat(couriers): the day's ride, delivery with supersession, saves and the tick"
```

---

### Task 6: Army orders ride by courier

**Files:**
- Modify: `scripts/engine/action_system.gd` (`_validate_army` ~:99; the `ARMY_MARCH` / `ARMY_GARRISON` arms ~:414–430; a new `_send_courier`)
- Modify: `tests/engine/test_army_march.gd` (`test_the_order_runs_and_charges_its_cost`)
- Test: `tests/engine/test_courier_orders.gd`

**Interfaces:**
- Consumes: `CourierSystem.carries_orders/dispatch/fee_gold/days_left/ride_day`.
- Produces: `ARMY_MARCH` / `ARMY_GARRISON` on a land regiment add ONE courier and two effects:
  - `{metric: "treasury", delta: -fee, reason: "a courier rides for <label>"}`;
  - `{metric: "army", delta: 0, reason: "A courier rides for <label> with orders to march|stand; about N day(s)"}`.

  A fleet's orders behave as before.

- [ ] **Step 1: Write the failing test** — `tests/engine/test_courier_orders.gd`

```gdscript
extends GutTest
## ARMY_MARCH / ARMY_GARRISON send a courier (spec 2026-09-27-courier-core §1).

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	RoadGraph.forget()
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _marcher() -> Dictionary:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(repo, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return r
	return {}


func _land_near(s: GameState, r: Dictionary) -> Vector2:
	var home: Vector2 = ArmySystem.position_of(repo, s, r)
	for i in range(3, 60):
		var probe := home + Vector2(float(i), 0.0)
		if MapEconomy.cell_at(repo, probe) >= 0:
			return probe
	return Vector2.ZERO


func test_the_order_rides_and_the_regiment_waits() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var dest := _land_near(s, r)
	if dest == Vector2.ZERO:
		return
	var home: Vector2 = ArmySystem.position_of(repo, s, r)
	var before: float = s.metrics["treasury"]
	var req := ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": dest.x, "y": dest.y})
	assert_eq(actions.validate(req, s), "")
	var out: Dictionary = actions.execute(req, s)
	assert_eq(s.couriers.size(), 1, "one courier rides")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_GARRISON, "the column waits for him")
	assert_eq(ArmySystem.position_of(repo, s, r), home, "and has not moved")
	var fee := false
	for e: Dictionary in out.get("effects", []):
		if String(e["metric"]) == "treasury" and String(e["reason"]).begins_with("a courier rides for"):
			fee = is_equal_approx(float(e["delta"]), -float(CourierSystem.fee_gold(repo, CourierSystem.ORDINARY)))
	assert_true(fee, "the fee is a ledger line with its reason")
	assert_lt(float(s.metrics["treasury"]), before)
	for day in int(repo.bal("courier_max_days")):
		CourierSystem.ride_day(repo, s)
		if s.couriers.is_empty():
			break
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH, "delivered: now it marches")


func test_garrison_rides_too() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	ArmySystem.set_march(repo, s, code, ArmySystem.position_of(repo, s, r) + Vector2(200.0, 0.0))
	actions.execute(ActionRequest.make("ARMY_GARRISON", {"regiment": code}), s)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH, "still marching until the courier comes")
	assert_eq(s.couriers.size(), 1)


func test_a_chest_too_thin_for_the_courier_is_refused() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var code := String(_marcher()["regiment_code"])
	# ARMY_GARRISON's own cost is 1 gold (order_costs.csv); the fee is more
	# than what is left over it.
	s.metrics["treasury"] = float(CourierSystem.fee_gold(repo, CourierSystem.ORDINARY)) - 0.5
	assert_string_contains(actions.validate(ActionRequest.make("ARMY_GARRISON", {"regiment": code}), s), "courier")


func test_a_fleets_orders_apply_at_once() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) == "1":
			actions.execute(ActionRequest.make("ARMY_GARRISON", {"regiment": String(r["regiment_code"])}), s)
			assert_eq(s.couriers, [], "a fleet takes no courier in sub-project A")
			return
	pass_test("this pack's realm has no fleet")
```

**Before relying on `ActionRequest.make` and `execute`'s return value:** confirm that `ActionRequest.make(code, params)` exists (the UI test uses it) and that `execute` returns a Dictionary with `effects`. Open `action_system.gd`'s `func execute` and adapt the test's `out.get("effects")` to whatever it actually returns, for example an outcome whose `effects` array the arm appends to.

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL (no courier created; order applied at once).

- [ ] **Step 3: Validation.** In `_validate_army`, after the "not yours to command" check and before `if req.action_code == "ARMY_GARRISON": return ""`, add:

```gdscript
	# The order rides by courier (owner 2026-09-27): his fee is paid from the
	# crown's chest, so an order the chest cannot send is refused, not sent
	# into the red.
	if CourierSystem.carries_orders(reg) and float(state.metrics["treasury"]) \
			< float(CourierSystem.fee_gold(data, CourierSystem.ORDINARY)):
		return "The chancery cannot pay a courier to ride for %s" % String(reg["label"])
```

- [ ] **Step 4: Execution.** Replace the two arms:

```gdscript
		"ARMY_MARCH":
			var code := String(req.params["regiment"])
			var reg := ArmySystem.regiment(data, code)
			var dest := Vector2(float(req.params["x"]), float(req.params["y"]))
			if CourierSystem.carries_orders(reg):
				var m := ArmySystem.pack_to_metres(data, dest)
				_send_courier(state, effects, code, {"action_code": "ARMY_MARCH",
					"dest_x_m": m.x, "dest_y_m": m.y}, "with orders to march")
			else:
				ArmySystem.set_march(data, state, code, dest)
				var days := ArmySystem.days_out(data, state, code)
				effects.append({"metric": "army", "delta": 0.0,
					"reason": "%s takes the road; %d day%s' march" % [
						String(reg["label"]), days, "" if days == 1 else "s"]})
		"ARMY_GARRISON":
			var code := String(req.params["regiment"])
			var reg := ArmySystem.regiment(data, code)
			if CourierSystem.carries_orders(reg):
				_send_courier(state, effects, code, {"action_code": "ARMY_GARRISON"}, "with orders to stand")
			else:
				var was := ArmySystem.order_of(data, state, code)
				ArmySystem.set_garrison(data, state, code)
				effects.append({"metric": "army", "delta": 0.0,
					"reason": ("%s halts and takes up quarters" if was == ArmySystem.ORDER_MARCH
						else "%s stands to its post") % String(reg["label"])})
```

And the helper, beside `_apply`:

```gdscript
## An order that rides (owner 2026-09-27, spec 2026-09-27-courier-core): one
## courier from the capital, his fee a ledger line, and the army line saying
## when he should get there. The regiment is untouched until he does.
func _send_courier(state: GameState, effects: Array, code: String, order: Dictionary, what: String) -> void:
	var label := String(ArmySystem.regiment(data, code)["label"])
	var c := CourierSystem.dispatch(data, state, CourierSystem.ORDINARY, code, order)
	_apply(state, effects, "treasury", -float(CourierSystem.fee_gold(data, CourierSystem.ORDINARY)),
		"a courier rides for " + label)
	var days := CourierSystem.days_left(data, state, c)
	effects.append({"metric": "army", "delta": 0.0, "reason": "A courier rides for %s %s; about %d day%s" % [
		label, what, days, "" if days == 1 else "s"]})
```

- [ ] **Step 5: Fix the old engine test.** In `tests/engine/test_army_march.gd` `test_the_order_runs_and_charges_its_cost`, replace `assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH)` with:

```gdscript
	assert_eq(s.couriers.size(), 1, "the order rides by courier (2026-09-27)")
```

- [ ] **Step 6: Run the tests.** Run `test_courier_orders.gd`, `test_army_march.gd`, `test_action_system.gd`. Expected: PASS. `tests/ui/test_army_order_menu.gd` will now FAIL on its "order is given" / "sends it on commit" / "garrison runs at once" asserts. Task 8 fixes them, so leave them failing only until then, and do not commit a red suite across a task boundary: do Task 8 Step 1 next.
- [ ] **Step 7: Commit** (after Task 8's UI test fixes are in and green, or commit both tasks together):

```bash
git add scripts/engine/action_system.gd tests/engine/test_army_march.gd tests/engine/test_courier_orders.gd
git commit -m "feat(couriers): army orders ride by courier and take effect on delivery"
```

---

### Task 7: Weather in the march

**Files:**
- Modify: `scripts/engine/army_system.gd` (new `day_march_m`; `march_day` and `days_out` use it)
- Modify: `scripts/map3d/map3d_units.gd` (`day_world_m` uses `day_march_m`)
- Modify: `tests/engine/test_army_march.gd` (clear skies in `before_all`; a weather test)
- Modify: `tests/map3d/test_map3d_units.gd` (~:156–172: `day_step_m` → `day_march_m`)

**Interfaces:**
- Produces: `ArmySystem.day_march_m(repo, state, code) -> int`, which is `day_step_m × weather‰ ÷ 1000` at the regiment's position today.

- [ ] **Step 1: Write the failing test.** Append to `tests/engine/test_army_march.gd`:

```gdscript
func test_the_weather_where_it_stands_scales_its_day() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := String(_marcher()["regiment_code"])
	var step := ArmySystem.day_step_m(repo, s, code)
	var saved := repo.weather_odds.duplicate(true)
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 0, "rain": 0, "mud": 0, "snow": 0, "blizzard": 1}
	Weather.forget()
	@warning_ignore("integer_division")
	assert_eq(ArmySystem.day_march_m(repo, s, code), step * 400 / 1000, "a blizzard: 400‰")
	repo.weather_odds = saved
```

In the same file's `before_all`, after loading, force clear skies so every existing hand sum still holds:

```gdscript
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}
```

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL (`day_march_m` not found).

- [ ] **Step 3: Implement.** In `army_system.gd`, after `day_step_m`:

```gdscript
## Metres a regiment covers TODAY (spec 2026-09-27-courier-core §1): its
## day_step_m under the weather of the province it stands in.
static func day_march_m(repo: DataRepository, state: GameState, code: String) -> int:
	var step := day_step_m(repo, state, code)
	if step <= 0 or state == null:
		return step
	var kind := Weather.at(repo, state, position_of(repo, state, regiment(repo, code)), state.absolute_day())
	@warning_ignore("integer_division")  # whole metres
	return step * Weather.speed_permille(repo, kind) / 1000
```

In `march_day`, change `var step := day_step_m(repo, state, code)` to `var step := day_march_m(repo, state, code)`. Do the same in `days_out`. In `scripts/map3d/map3d_units.gd` `day_world_m`, change `ArmySystem.day_step_m(` to `ArmySystem.day_march_m(`.

In `tests/map3d/test_map3d_units.gd` (~:156–172), replace every `ArmySystem.day_step_m(` with `ArmySystem.day_march_m(`.

- [ ] **Step 4: Run the suite.** Expected: PASS. If a test elsewhere hand-sums a march, force clear skies in its setup exactly as above; never loosen its tolerance.
- [ ] **Step 5: Commit**

```bash
git add scripts/engine/army_system.gd scripts/map3d/map3d_units.gd tests/engine/test_army_march.gd tests/map3d/test_map3d_units.gd
git commit -m "feat(couriers): regional weather scales a regiment's day on the march"
```

---

### Task 8: News and the order menu's words

**Files:**
- Modify: `scripts/ui/game.gd` (`advance_day` :80–86: add `"couriers"`)
- Modify: `scripts/ui/game_root.gd` (after the finished-works news loop, ~:128)
- Modify: `scripts/ui/army_order_menu.gd` (`_add_row` :101–106; `_run` :221–235)
- Modify: `data/army_route_orders.csv` (`commit`, `halt` rows)
- Modify: `tests/ui/test_army_order_menu.gd`

**Interfaces:**
- Consumes: `TickEngine.day_couriers`, `CourierSystem.headline/carries_orders/fee_gold`.
- Produces: `Game.advance_day()` returns `{ticked, finished, arrived, couriers}`.

- [ ] **Step 1: Update the UI tests to the courier flow.** In `tests/ui/test_army_order_menu.gd`, add this helper:

```gdscript
## Days run until every courier has delivered (or the fuse has taken him).
func _deliver_all() -> void:
	Game.set_clock_speed(0)
	for i in int(Game.data.bal("courier_max_days")) + 1:
		if Game.state.couriers.is_empty():
			return
		Game.advance_day()
```

- In the paused-commit test (~:95), replace `assert_eq(ArmySystem.order_of(...), ArmySystem.ORDER_MARCH, "the order is given")` with:

  ```gdscript
  	assert_eq(Game.state.couriers.size(), 1, "the order is given: a courier waits to ride")
  	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_GARRISON, "the column waits for him")
  ```

  and before `_commit()` add `watch_signals(Game)`. After the asserts add:

  ```gdscript
  	assert_signal_emitted_with_parameters(Game, "news_published",
  		["A courier will ride for %s when time runs." % String(ArmySystem.regiment(Game.data, code)["label"])])
  ```

- In `test_the_next_click_on_the_ground_sends_it_on_commit` (~:117), replace the `ORDER_MARCH` assert with:

  ```gdscript
  	assert_eq(Game.state.couriers.size(), 1)
  	_deliver_all()
  	assert_eq(Game.state.couriers, [], "delivered")
  ```

  Keep the destination asserts after it. They hold whether the column is still marching or has already arrived.
- Rename `test_garrison_runs_at_once_and_halts_a_march` to `test_garrison_rides_and_halts_a_march_on_delivery`. After `_menu.id_pressed.emit(1)` it asserts:

  ```gdscript
  	assert_eq(Game.state.couriers.size(), 1, "a courier rides with the halt")
  	_deliver_all()
  	assert_eq(ArmySystem.order_of(Game.data, Game.state, code), ArmySystem.ORDER_GARRISON)
  ```

- Add:

  ```gdscript
  func test_the_commit_row_names_the_courier_and_his_fee() -> void:
  	var row: Dictionary = Game.data.army_route_orders["commit"]
  	assert_eq(String(row["label"]), "Send courier")
  	assert_string_contains(String(row["hint"]), "{fee}")
  ```

- [ ] **Step 2: Run the file to verify the new asserts fail.** Expected: FAIL on the label and the news text.

- [ ] **Step 3: Implement.**

`data/army_route_orders.csv`: replace the `commit` and `halt` rows' label and hint. Keep their notes and add ", owner 2026-09-27: the order rides by courier (spec 2026-09-27-courier-core)".
- `commit`: label `Send courier`, hint `A courier rides from the capital with this route; the column moves when he reaches it. Fee: {fee} gold`
- `halt`: hint `Send a courier to halt the column where it has got to`

`army_order_menu.gd` `_add_row`: change the tooltip line to:

```gdscript
	set_item_tooltip(i, why if why != "" else String(row["hint"]).replace("{fee}",
		str(CourierSystem.fee_gold(Game.data, CourierSystem.ORDINARY))))
```

`_run`: replace the paused branch with:

```gdscript
	# An order on a stopped clock waits for play (owner 2026-09-24) — and since
	# 2026-09-27 it rides by courier, who waits in the capital with it.
	if Game.clock_speed <= 0 and req.action_code in ["ARMY_MARCH", "ARMY_GARRISON"]:
		var code := String(req.params["regiment"])
		if CourierSystem.carries_orders(ArmySystem.regiment(Game.data, code)):
			Game.publish_news("A courier will ride for %s when time runs." % _name_of(code))
			return
		if req.action_code == "ARMY_MARCH":
			Game.publish_news("%s will set out when time runs." % _name_of(code))
			return
```

`game.gd` `advance_day`: add `"couriers": engine.day_couriers` to both returned dictionaries.

`game_root.gd`, after the `for w: Dictionary in out["finished"]:` loop:

```gdscript
		for e: Dictionary in out.get("couriers", []):
			Game.publish_news(CourierSystem.headline(Game.data, e))
```

- [ ] **Step 4: Run the whole suite.** Expected: PASS, expected error count.
- [ ] **Step 5: Commit** (Task 6's files too, if not yet committed):

```bash
git add scripts/ui/game.gd scripts/ui/game_root.gd scripts/ui/army_order_menu.gd data/army_route_orders.csv tests/ui/test_army_order_menu.gd
git commit -m "feat(couriers): the order menu sends a courier; the news bar follows him"
```

---

### Task 9: The courier card, the weather on cards, and the glyphs

**Files:**
- Create: `scripts/engine/courier_card.gd`
- Modify: `scripts/engine/map_objects.gd` (`province_card` fields ~:434; `manor_card` stats ~:537)
- Modify: `scripts/ui/map_detail_panel.gd` (`show_entry` ~:264; `show_card` ~:346)
- Modify: `scripts/ui/resource_icon.gd` (`draw_glyph` match: `drop`, `cloud`, `flake`, `letter`)
- Modify: `data/resource_icons.csv` (rows `weather_clear` … `weather_blizzard`, no texture)
- Test: `tests/engine/test_courier_card.gd`

**Interfaces:**
- Produces:
  - `CourierCard.courier(state, id) -> Dictionary`
  - `CourierCard.title(repo, state, id) -> String` ("Courier to <regiment>")
  - `CourierCard.card(repo, state, id) -> Dictionary`, with `kind: "courier"`, `known: "courier"`, `fields`, `painting`, `center`; `{}` when he is gone
  - `CourierCard.date_of(abs_day) -> String`

- [ ] **Step 1: Write the failing test** — `tests/engine/test_courier_card.gd`

```gdscript
extends GutTest

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	RoadGraph.forget()
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _code() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


func _field(card: Dictionary, name: String) -> String:
	for f: Array in card["fields"]:
		if String(f[0]) == name:
			return String(f[1])
	return ""


func test_the_card_says_what_he_carries_and_when() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _code()
	var c := CourierSystem.dispatch(repo, s, "ordinary", code, {"action_code": "ARMY_GARRISON"})
	var card := CourierCard.card(repo, s, int(c["id"]))
	var label := String(ArmySystem.regiment(repo, code)["label"])
	assert_eq(String(card["title"]), "Courier to " + label)
	assert_eq(String(card["known"]), "courier")
	assert_eq(_field(card, "Carrying"), "Orders to stand for " + label)
	assert_string_contains(_field(card, "Arrives"), "day")
	assert_ne(_field(card, "Weather"), "")
	assert_ne(_field(card, "Ground"), "")
	assert_eq(_field(card, "Rode out"), Calendar.date_string(s.tick, s.day))


func test_a_gone_courier_has_no_card() -> void:
	var s := GameState.new_campaign(repo, 7)
	assert_eq(CourierCard.card(repo, s, 99), {})


func test_province_and_manor_cards_carry_the_weather() -> void:
	var s := GameState.new_campaign(repo, 7)
	var codes := repo.provinces.keys()
	codes.sort()
	var p := String(codes[0])
	var names: Array = []
	for f: Array in MapObjects.province_card(repo, s, p)["fields"]:
		names.append(String(f[0]))
	assert_has(names, "Weather", "even a foreign province: the sky is no secret")
	var cell := int(MapManors.manors_of_province(repo, p)[0])
	var keys: Array = []
	for st: Dictionary in MapObjects.manor_card(repo, s, cell)["stats"]:
		keys.append(String(st["key"]))
	assert_has(keys, "weather_" + Weather.of(repo, s, p, s.absolute_day()))


func test_every_weather_icon_has_a_row() -> void:
	for kind: String in repo.weather_kinds:
		assert_true(repo.resource_icons.has(String(repo.weather_kinds[kind]["icon"])), kind)
```

- [ ] **Step 2: Run it to verify it fails.** Expected: FAIL (`CourierCard` not found).

- [ ] **Step 3: Write `scripts/engine/courier_card.gd`**

```gdscript
class_name CourierCard
extends RefCounted
## A courier's fact card for the left column (spec 2026-09-27-courier-core §2,
## invariant 10), shaped like MapObjects' cards: title, subtitle, painting,
## fields. The painting is courier_art.csv's, omitted until sub-project D
## installs one.

const GROUND := {"road": "On the road", "trail": "On a trail", "offroad": "Across country", "sea": "By sea"}


static func courier(state: GameState, id: int) -> Dictionary:
	if state == null:
		return {}
	for c: Dictionary in state.couriers:
		if int(c["id"]) == id:
			return c
	return {}


static func title(repo: DataRepository, state: GameState, id: int) -> String:
	var c := courier(state, id)
	if c.is_empty():
		return "A courier"
	return "Courier to " + String(ArmySystem.regiment(repo, String(c["target"])).get("label", c["target"]))


## Calendar's date of an absolute day.
static func date_of(abs_day: int) -> String:
	var d := maxi(abs_day, 1) - 1
	@warning_ignore("integer_division")  # whole months
	return Calendar.date_string(d / Calendar.DAYS_PER_TICK + 1, d % Calendar.DAYS_PER_TICK + 1)


static func card(repo: DataRepository, state: GameState, id: int) -> Dictionary:
	var c := courier(state, id)
	if c.is_empty():
		return {}
	var realm := repo.resolve_realm("player_realm")
	var kind := String(c["kind"])
	var reg_label := String(ArmySystem.regiment(repo, String(c["target"])).get("label", c["target"]))
	var order := String((c["order"] as Dictionary).get("action_code", ""))
	var here := Vector2i(int(c["x_m"]), int(c["y_m"]))
	var wx := Weather.at(repo, state, ArmySystem.metres_to_pack(repo, here), state.absolute_day())
	var path: Array = c["path"]
	var ground := String(path[0][2]) if not path.is_empty() else "offroad"
	var days := CourierSystem.days_left(repo, state, c)
	return {
		"kind": "courier", "id": int(c["id"]), "title": title(repo, state, id),
		"subtitle": "%s courier of %s" % [kind.capitalize(),
			String((repo.kingdoms.get(realm, {}) as Dictionary).get("label", ""))],
		"kingdom_code": realm, "initial": "C",
		"painting": String((repo.courier_art.get(kind, {}) as Dictionary).get("painting", "")),
		"stats": [], "rates": [], "features": [], "production": [], "actions": [],
		"fields": [
			["Carrying", ("Orders to march" if order == "ARMY_MARCH" else "Orders to stand") + " for " + reg_label],
			["Rode out", date_of(int(c["issued"]))],
			["Arrives", "in about %d day%s" % [days, "" if days == 1 else "s"]],
			["Ground", String(GROUND.get(ground, ground))],
			["Weather", Weather.describe_kind(repo, wx)],
		],
		"known": "courier",
		"center": ArmySystem.metres_to_pack(repo, here),
		"ask": "",
	}
```

- [ ] **Step 4: Put the weather on the cards.**

`map_objects.gd` `province_card`: in the card literal's `"fields"`, add a third pair after `["Seat", …]`:

```gdscript
			["Weather", Weather.describe(repo, state, code)]],
```

It stands before the `if card["known"] == "basic": return card`, because the sky is no secret.

`manor_card`: right after `card["painting"] = estate_painting(repo, state, cell)`:

```gdscript
	var wx := Weather.of(repo, state, province, state.absolute_day()) if state != null else Weather.CLEAR
	stats.append(_stat("weather_" + wx, Weather.label_of(repo, wx), "Weather — " + Weather.describe_kind(repo, wx)))
```

`data/resource_icons.csv`: append five rows (`key,label,icon,tooltip,texture`, texture empty):

```
weather_clear,Clear,sun,"Clear weather: roads at their pace",
weather_rain,Rain,drop,"Rain: marches and couriers slowed (data/weather.csv)",
weather_mud,Mud,cloud,"Mud: the roads of spring and autumn, slow going",
weather_snow,Snow,flake,"Snow: slow going on every road",
weather_blizzard,Blizzard,flake,"Blizzard: little moves",
```

`resource_icon.gd` `draw_glyph`: add these arms to the match:

```gdscript
		"drop":
			ci.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4.0) * u, c + Vector2(2.6, 0.8) * u,
				c + Vector2(0, 3.8) * u, c + Vector2(-2.6, 0.8) * u]), tint)
		"cloud":
			ci.draw_circle(c + Vector2(-1.8, 0.6) * u, 2.0 * u, tint)
			ci.draw_circle(c + Vector2(1.0, -0.6) * u, 2.6 * u, tint)
			ci.draw_rect(Rect2(c + Vector2(-3.8, 0.6) * u, Vector2(7.4, 2.0) * u), tint)
		"flake":
			for i in 3:
				var d := Vector2(cos(PI * float(i) / 3.0), sin(PI * float(i) / 3.0)) * 3.8 * u
				ci.draw_line(c - d, c + d, tint, 1.0 * u, true)
		"letter":
			ci.draw_rect(Rect2(c + Vector2(-3.8, -2.6) * u, Vector2(7.6, 5.2) * u), tint, false, 1.0 * u)
			ci.draw_polyline(PackedVector2Array([c + Vector2(-3.8, -2.6) * u, c + Vector2(0, 0.6) * u,
				c + Vector2(3.8, -2.6) * u]), tint, 1.0 * u, true)
```

- [ ] **Step 5: The panel.** In `map_detail_panel.gd` `show_entry`, after the army branch:

```gdscript
	if String(obj.get("kind", "")) == "courier":
		show_card(CourierCard.card(Game.data, Game.state, int(obj.get("id", -1))))
		return
```

In `show_card`, between the `if known == "army":` block and `elif not basic:` insert:

```gdscript
	elif known == "courier":
		pass  # a courier's card is his painting and his fields; no land sections
```

- [ ] **Step 6: Run the whole suite.** Expected: PASS. If a test pins `province_card`'s field list or a manor card's stat count exactly, add the new Weather entry to its expectation. It is an intended addition.
- [ ] **Step 7: Commit**

```bash
git add scripts/engine/courier_card.gd scripts/engine/map_objects.gd scripts/ui/map_detail_panel.gd scripts/ui/resource_icon.gd data/resource_icons.csv tests/engine/test_courier_card.gd
git commit -m "feat(couriers): the courier's card and the weather on province and manor cards"
```

---

### Task 10: Couriers on the 3D map — layer, pick, select

**Files:**
- Create: `scripts/map3d/map3d_layer_couriers.gd` (≤ 300 lines)
- Modify: `scripts/map3d/map3d_context.gd` (add `couriers()`; the file is at 297 lines, so keep it to 2)
- Modify: `scripts/map3d/map3d_view.gd` (4 lines: `@onready`, bind, step, forwarder)
- Modify: `scripts/map3d/map3d_picker.gd` (`pick_at`: courier kind after route ends)
- Modify: `scripts/map3d/map3d_selection.gd` (`select`: `"courier"` arm)
- Modify: `scenes/map3d/world_map_3d.tscn` (node `Viewport/Couriers`)
- Modify: `data/balance.csv` (`map3d_courier_counter_px`, `map3d_courier_anim_rate`)
- Modify: `tests/map3d/test_map3d_shape.gd` (cap 556 → 559 and its comment), `tests/map3d/test_map3d_scene.gd` (TREE gains `"Viewport/Couriers"`)

**Interfaces:**
- Consumes: `GameState.couriers`, `repo.courier_art`, `Map3DUnits.*` (`as_counters`, `scale_for`, `seat_at`, `screen_box`, `model_size`, `stand_extent`, `find_anim`, `clip_named`, `walk`, `yaw_for`), `Map3DGeometry.distance_for_bar`.
- Produces:
  - `Map3DContext.couriers() -> Array`
  - `Map3DLayerCouriers.bind(ctx)`, `refresh()`, `step(delta) -> bool`, `screen_rects() -> Dictionary` (id → `{rect: Rect2, counter: bool}` in design px)
  - `Map3DView.courier_rects() -> Dictionary`
  - pick `{kind: "courier", id: int}`
  - selection emits `object_selected({title, obj: {kind: "courier", id}})`

- [ ] **Step 1: Failing tests.**
  - In `tests/map3d/test_map3d_shape.gd`, change `556` to `559`, and add to its comment block: "559 since the couriers (2026-09-27): the Couriers layer's @onready, its bind, its step in _process and a courier_rects() forwarder — the layer does the work."
  - In `tests/map3d/test_map3d_scene.gd`'s `TREE`, add `"Viewport/Couriers"` after `"Viewport/Houses"`.
  - Add to `tests/map3d/test_map3d_context.gd`:

```gdscript
func test_the_context_hands_out_the_live_couriers() -> void:
	var repo := DataRepository.load_all("res://data")
	var s := GameState.new_campaign(repo, 7)
	s.couriers = [{"id": 1}]
	var ctx := Map3DContext.new(repo, {}, null)
	ctx.state_fn = func() -> GameState: return s
	assert_eq(ctx.couriers(), [{"id": 1}])
	ctx.state_fn = Callable()
	assert_eq(ctx.couriers(), [])
```

If `Map3DContext.new` needs a real world node, build the context the way the other tests in that file do.

- [ ] **Step 2: Run them to verify they fail.** Expected: FAIL (the scene has no Couriers node; `couriers()` is missing).

- [ ] **Step 3: The context.** In `map3d_context.gd`, after `regiments()`:

```gdscript
## The couriers on the road (spec 2026-09-27-courier-core §2), from the live state.
func couriers() -> Array: return state().couriers if state() != null else []
```

- [ ] **Step 4: Write `scripts/map3d/map3d_layer_couriers.gd`**

```gdscript
class_name Map3DLayerCouriers
extends Node3D
## The couriers on the 3D map (spec 2026-09-27-courier-core §2): one small
## rider per courier of GameState.couriers, sized, seated and walked between
## the engine's whole days with the regiment pieces' own rules (Map3DUnits),
## galloping always. Past the counter scale no rider is drawn and his rect is
## a counter's, which Map3DHudCouriers paints. The model is courier_art.csv's —
## the cavalry until sub-project D delivers the courier's own. Nothing here
## reaches Game.

const MARCH := "MARCH"

var ctx: Map3DContext
var _pieces: Dictionary = {}
var _shown_xz: Dictionary = {}
var _rects: Dictionary = {}
var _scenes: Dictionary = {}


func bind(p_ctx: Map3DContext) -> void:
	ctx = p_ctx
	if not ctx.camera_moved.is_connected(refresh):
		ctx.camera_moved.connect(refresh)
	refresh()


## id -> {rect: Rect2 in design px, counter: bool}.
func screen_rects() -> Dictionary:
	return _rects


func refresh() -> void:
	if ctx == null or ctx.camera == null:
		return
	_rects = {}
	var live: Dictionary = {}
	for c: Dictionary in ctx.couriers():
		var id := int(c["id"])
		live[id] = true
		if not _shown_xz.has(id):
			_shown_xz[id] = _target_xz(c)
		_place(c, _shown_xz[id])
	for id in _pieces.keys():
		if not live.has(id):
			(_pieces[id]["node"] as Node3D).queue_free()
			_pieces.erase(id)
	for id in _shown_xz.keys():
		if not live.has(id):
			_shown_xz.erase(id)


## Walk each drawn rider toward where the engine has him, a day's ride per
## day's real seconds; true when anything changed (the HUD redraws).
func step(delta: float) -> bool:
	if ctx == null or ctx.camera == null:
		return false
	var list := ctx.couriers()
	var dirty := list.size() != _rects.size()
	var clock := ctx.clock_speed()
	var day_s := maxf(ctx.repo.bal("time_day_seconds") / float(maxi(clock, 1)), 0.001)
	var per_m := float(ctx.meta.get("m_per_px", 50.0)) / float(ArmySystem.metres_per_pack_px(ctx.repo))
	for c: Dictionary in list:
		var id := int(c["id"])
		var want := _target_xz(c)
		if not _shown_xz.has(id):
			_shown_xz[id] = want
			dirty = true
			continue
		var now: Vector2 = _shown_xz[id]
		if now == want:
			continue
		var day_m := float(maxi(int(c.get("day_m", 0)), 1)) * per_m
		var speed := day_m / day_s if clock > 0 else 0.0
		_shown_xz[id] = Map3DUnits.walk(now, want, speed * delta, day_m * ctx.repo.bal("map3d_unit_snap_days"))
		dirty = true
	if dirty:
		refresh()
	return dirty


func _target_xz(c: Dictionary) -> Vector2:
	return ctx.to_world(ArmySystem.metres_to_pack(ctx.repo, Vector2i(int(c["x_m"]), int(c["y_m"]))))


## He faces the next waypoint of his road.
func _heading(c: Dictionary) -> Vector2:
	var path: Array = c["path"]
	if path.is_empty():
		return Vector2.ZERO
	var d := Vector2(float(path[0][0]) - float(c["x_m"]), float(path[0][1]) - float(c["y_m"]))
	return d.normalized() if d.length() > 0.5 else Vector2.ZERO


func _place(c: Dictionary, xz: Vector2) -> void:
	var id := int(c["id"])
	var repo := ctx.repo
	var s_px := ctx.viewport_px_scale()
	var centre := Vector3(xz.x, ctx.height_at(xz), xz.y)
	if ctx.camera.is_position_behind(centre):
		if _pieces.has(id):
			(_pieces[id]["node"] as Node3D).visible = false
		return
	var counter := Map3DUnits.as_counters(repo, ctx.meta, ctx.distance, ctx.view_size.y)
	var piece: Dictionary = {} if counter else _piece_of(c)
	if piece.is_empty():
		if _pieces.has(id):
			(_pieces[id]["node"] as Node3D).visible = false
		var at: Vector2 = ctx.camera.unproject_position(centre) / s_px
		var half := repo.bal("map3d_courier_counter_px") * 0.5
		_rects[id] = {"rect": Rect2(at - Vector2(half, half), Vector2(half, half) * 2.0), "counter": true}
		return
	var node: Node3D = piece["node"]
	node.visible = true
	var ref_m := Map3DGeometry.distance_for_bar(repo, ctx.meta, repo.bal("map3d_zoom_start_scale"), ctx.view_size.y)
	var k := Map3DUnits.scale_for(repo, ctx.camera.global_position.distance_to(centre),
		repo.bal("map3d_fov_deg"), ctx.view_size.y, ref_m, float(piece["height_m"]), float(piece["size"]))
	var cam := Vector2(ctx.camera.global_position.x, ctx.camera.global_position.z)
	var yaw := Map3DUnits.yaw_for(_heading(c), cam, xz)
	var sit := Map3DUnits.seat_at(repo, ctx.height_at, xz, piece["extent"], yaw, k)
	var high := float(piece["height_m"]) * k
	var ground := Vector3(xz.x, float(sit["y"]) + high * repo.bal("map3d_unit_seat_clear")
		- repo.bal("map3d_unit_sink_m"), xz.y)
	var up: Vector3 = sit["normal"]
	node.transform = Transform3D((Basis(Quaternion(Vector3.UP, up)) * Basis(Vector3.UP, yaw))
		.scaled(Vector3(k, k, k)), ground)
	_rects[id] = {"rect": Map3DUnits.screen_box(ctx.camera, ground, high, float(piece["half_w_m"]) * k, s_px),
		"counter": false}


func _piece_of(c: Dictionary) -> Dictionary:
	var id := int(c["id"])
	if _pieces.has(id):
		return _pieces[id]
	var art: Dictionary = ctx.repo.courier_art.get(String(c["kind"]), {})
	var path := String(art.get("model", ""))
	var scene := _scene(path) if path != "" else null
	if scene == null:
		return {}
	var node := scene.instantiate() as Node3D
	node.name = "Courier%d" % id
	add_child(node)  # no owner: never saved into the authored scene
	var span := Map3DUnits.model_size(node)
	var anims := Map3DUnits.find_anim(node)
	if anims != null:
		var clip := Map3DUnits.clip_named(anims, MARCH)
		if clip != "":
			anims.play(clip)
			anims.speed_scale = ctx.repo.bal("map3d_courier_anim_rate")
	var piece := {"node": node, "height_m": maxf(span.y, 0.01), "half_w_m": span.x * 0.5,
		"extent": Map3DUnits.stand_extent(node), "size": float(art.get("size", "1"))}
	_pieces[id] = piece
	return piece


func _scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	var scene: PackedScene = null
	if ResourceLoader.exists(path):
		scene = load(path) as PackedScene
	else:
		Map3DWorldLoader.warn_once("couriers:" + path, "map3d couriers: no model at " + path)
	_scenes[path] = scene
	return scene
```

**Check before running:**
- `Map3DUnits.yaw_for(heading, camera_xz, at_xz, stand_deg := 0.0)`: confirm the parameter order at `map3d_units.gd:58` and adapt the call.
- Confirm `model_size().x` is the width, since that is what the regiment layer's `half_w_m` uses. Read `map3d_layer_units.gd`'s `_piece_of` to see which component it halves, and use the same one.

- [ ] **Step 5: Balance keys** (append; stage only these rows):

```
map3d_courier_counter_px,16,"a courier's square counter in design px, drawn past map3d_unit_counter_scale (Map3DHudCouriers) and his click box then"
map3d_courier_anim_rate,2.5,"the courier's MARCH clip playback rate — a gallop, not a walk — until sub-project D's own gallop clip"
```

- [ ] **Step 6: The scene node.** Prefer the gdai MCP: `add_node` a `Node3D` named `Couriers` under `Viewport`, right after `Units`, and `attach_script` `res://scripts/map3d/map3d_layer_couriers.gd`. Then check `git diff scenes/map3d/world_map_3d.tscn` shows only the ext_resource and the node. The editor rewrites stale buffers ([[godot-editor-buffer-clobbers-files]]), so check `git status` for surprise edits.

Fallback, with the editor closed: add the ext_resource line beside `15_exbav`, then add the node after the `Units` node:

```
[ext_resource type="Script" path="res://scripts/map3d/map3d_layer_couriers.gd" id="40_cour"]
```
```
[node name="Couriers" type="Node3D" parent="Viewport"]
script = ExtResource("40_cour")
```

- [ ] **Step 7: The view (exactly 4 lines).** In `map3d_view.gd`:
  - beside `@onready var _units`:

    ```gdscript
    @onready var _couriers: Map3DLayerCouriers = $Viewport/Couriers
    ```

  - in `_load()`, after `_units.bind(_ctx)`:

    ```gdscript
    	_couriers.bind(_ctx)
    ```

  - in `_process`, after the `_units.step` line:

    ```gdscript
    		if _couriers.step(delta): _hud.refresh()  # the couriers' roads and counters follow them
    ```

  - after `func unit_moves()`:

    ```gdscript
    func courier_rects() -> Dictionary: return _couriers.screen_rects() if _loaded else {}
    ```

- [ ] **Step 8: Pick and select.** In `map3d_picker.gd` `pick_at`, after the route-ends loop:

```gdscript
	var couriers: Dictionary = view.courier_rects()
	var ids := couriers.keys()
	ids.sort()
	for id in ids:
		if (couriers[id]["rect"] as Rect2).has_point(pos):
			return {"kind": "courier", "id": int(id)}
```

In `map3d_selection.gd` `select`, add an arm modelled on `"army"`:

```gdscript
		"courier":
			var id := int(picked["id"])
			burg = ""
			army = ""
			_show_ring("")
			_set_province("")
			_refresh_hud()
			object_selected.emit({"title": CourierCard.title(ctx.repo, ctx.state(), id),
				"obj": {"kind": "courier", "id": id}})
```

- [ ] **Step 9: Run the whole suite.** Expected: PASS, expected error count. This includes the `Game.` scan over `scripts/map3d`, the 300-line rule and the view cap.
- [ ] **Step 10: Commit**

```bash
git add scripts/map3d/map3d_layer_couriers.gd scripts/map3d/map3d_context.gd scripts/map3d/map3d_view.gd scripts/map3d/map3d_picker.gd scripts/map3d/map3d_selection.gd scenes/map3d/world_map_3d.tscn data/balance.csv tests/map3d/test_map3d_shape.gd tests/map3d/test_map3d_scene.gd tests/map3d/test_map3d_context.gd
git commit -m "feat(couriers): riders on the 3D map, clickable into their card"
```

---

### Task 11: The HUD — roads ahead, pending orders, counters, weather marks, the ruler's estimate

**Files:**
- Create: `scripts/map3d/map3d_hud_couriers.gd`, `scripts/map3d/map3d_hud_weather.gd`
- Modify: `scripts/map3d/map3d_hud_ruler.gd` (`_draw_aim`: courier estimate)
- Modify: `scenes/map3d/world_map_3d.tscn` (`Hud/Weather` after `Hud/Landmarks`; `Hud/Couriers` after `Hud/Armies`)
- Modify: `data/balance.csv` (`map3d_courier_route_px`, `map3d_courier_pending_alpha`, `map3d_weather_view_m`, `map3d_weather_icon_px`)
- Modify: `data/political_palette.csv` (`weather_mark_bg`)
- Modify: `tests/map3d/test_map3d_hud.gd` (the paint order list), `tests/map3d/test_map3d_scene.gd` (TREE)
- Test: `tests/map3d/test_map3d_hud_weather.gd`

**Interfaces:**
- Consumes: `view.courier_rects()`, `ctx.couriers()`, `Weather.of`, `CourierSystem.eta_days/carries_orders`, `ResourceIcon.draw_glyph/draw_icon_texture`, `MapPalette.named/color_of`.
- Produces: `Map3DHudWeather.thin(marks: Array, min_px: float, bounds: Rect2) -> Array`, which is pure.

- [ ] **Step 1: Failing tests.**
  - In `test_map3d_hud.gd`, the paint order list becomes `["Labels", "Landmarks", "Weather", "HeatLegend", "Badges", "Armies", "Couriers", "Backdrop", "ScaleBar", "Ruler", "Compass", "Needle"]`.
  - In `test_map3d_scene.gd` `TREE`, add `"Hud/Weather"` after `"Hud/Landmarks"` and `"Hud/Couriers"` after `"Hud/Armies"`.
  - Create `tests/map3d/test_map3d_hud_weather.gd`:

```gdscript
extends GutTest


func test_marks_keep_clear_of_each_other_and_inside_the_view() -> void:
	var marks := [{"at": Vector2(10, 10), "kind": "rain"}, {"at": Vector2(15, 10), "kind": "snow"},
		{"at": Vector2(60, 10), "kind": "mud"}, {"at": Vector2(-5, 10), "kind": "rain"}]
	var kept := Map3DHudWeather.thin(marks, 20.0, Rect2(0, 0, 100, 100))
	assert_eq(kept.size(), 2)
	assert_eq(String(kept[0]["kind"]), "rain", "the first in province order keeps its place")
	assert_eq(String(kept[1]["kind"]), "mud")
```

- [ ] **Step 2: Run them to verify they fail.**

- [ ] **Step 3: Write `scripts/map3d/map3d_hud_couriers.gd`**

```gdscript
class_name Map3DHudCouriers
extends Map3DHudPiece
## The couriers on the HUD (spec 2026-09-27-courier-core §2): each courier's
## road still ahead as a thin dashed line in the realm's colour, finer than a
## march line; a march order still on the road as a faint dotted line from
## the column to where it will go, an envelope in its end ring; and, past the
## counter scale, each courier as a small square counter with a letter.


func _draw() -> void:
	if not bound() or ctx.state() == null:
		return
	var repo := ctx.repo
	var ink := MapPalette.color_of(repo, repo.resolve_realm("player_realm"))
	var w := repo.bal("map3d_courier_route_px")
	for c: Dictionary in ctx.couriers():
		_draw_road(c, ink, w)
		_draw_pending(c, ink, w)
	var rects: Dictionary = view.courier_rects()
	for id in rects:
		if bool(rects[id]["counter"]):
			_draw_counter(rects[id]["rect"], ink)


func _draw_road(c: Dictionary, ink: Color, w: float) -> void:
	var here: Variant = _screen_of_m(Vector2i(int(c["x_m"]), int(c["y_m"])))
	if here == null:
		return
	var pts := PackedVector2Array([here])
	for p: Array in c["path"]:
		var s: Variant = _screen_of_m(Vector2i(int(p[0]), int(p[1])))
		if s == null:
			break
		pts.append(s)
	for i in range(pts.size() - 1):
		draw_dashed_line(pts[i], pts[i + 1], ink, w, w * 3.0)


func _draw_pending(c: Dictionary, ink: Color, w: float) -> void:
	var order: Dictionary = c["order"]
	if String(order.get("action_code", "")) != "ARMY_MARCH":
		return
	var reg := ArmySystem.regiment(ctx.repo, String(c["target"]))
	if reg.is_empty():
		return
	var from: Variant = _screen_of(ArmySystem.position_of(ctx.repo, ctx.state(), reg))
	var to: Variant = _screen_of_m(Vector2i(int(order["dest_x_m"]), int(order["dest_y_m"])))
	if from == null or to == null:
		return
	var faint := Color(ink, ink.a * ctx.repo.bal("map3d_courier_pending_alpha"))
	draw_dashed_line(from, to, faint, w, w)  # dotted: a dash as long as the line is wide
	var r := ctx.repo.bal("map3d_unit_route_px") * 4.0
	draw_arc(to, r, 0.0, TAU, 24, faint, w, true)
	ResourceIcon.draw_glyph(self, "letter", to, r * 1.4, faint)


func _draw_counter(rect: Rect2, ink: Color) -> void:
	draw_rect(rect, MapPalette.named(ctx.repo, "army_icon_bg"))
	draw_rect(rect, MapPalette.named(ctx.repo, "army_outline"), false, 1.0)
	draw_rect(Rect2(rect.position.x, rect.end.y - 2.0, rect.size.x, 2.0), ink)
	ResourceIcon.draw_glyph(self, "letter", rect.get_center(), rect.size.x * 0.8, Color.WHITE)


func _screen_of(pack: Vector2) -> Variant:
	var p := ctx.ground_of_pack(pack)
	if ctx.camera.is_position_behind(p):
		return null
	return ctx.camera.unproject_position(p) / ctx.viewport_px_scale()


func _screen_of_m(m: Vector2i) -> Variant:
	return _screen_of(ArmySystem.metres_to_pack(ctx.repo, m))
```

`Color.WHITE` for the glyph ink on the dark counter matches `ArmyCounters`' glyph. Before shipping, read `ArmyCounters.draw`, and if its glyph ink is a palette key, use that key instead.

- [ ] **Step 4: Write `scripts/map3d/map3d_hud_weather.gd`**

```gdscript
class_name Map3DHudWeather
extends Map3DHudPiece
## The weather marks (spec 2026-09-27-courier-core §2): each province whose
## weather is not clear today shows its weather's icon at its centre — only
## within map3d_weather_view_m of the camera, inside the view, and clear of
## one another (the first in province order keeps its place). The icon is
## resource_icons.csv's art once installed (sub-project D), its glyph till then.


func _draw() -> void:
	if not bound() or ctx.state() == null or ctx.distance > ctx.repo.bal("map3d_weather_view_m"):
		return
	var repo := ctx.repo
	var st := ctx.state()
	var px := repo.bal("map3d_weather_icon_px")
	var marks: Array = []
	var codes := repo.provinces.keys()
	codes.sort()
	for code: String in codes:
		var kind := Weather.of(repo, st, code, st.absolute_day())
		if kind == Weather.CLEAR:
			continue
		var prov: Dictionary = repo.provinces[code]
		var p := ctx.ground_of_pack(Vector2(float(prov["center_x"]), float(prov["center_y"])))
		if ctx.camera.is_position_behind(p):
			continue
		marks.append({"at": ctx.camera.unproject_position(p) / ctx.viewport_px_scale(), "kind": kind})
	for m: Dictionary in thin(marks, px * 1.5, Rect2(Vector2.ZERO, size)):
		_draw_icon(String(m["kind"]), m["at"], px)


## The marks inside `bounds`, each at least `min_px` from every mark kept before it.
static func thin(marks: Array, min_px: float, bounds: Rect2) -> Array:
	var out: Array = []
	for m: Dictionary in marks:
		var at: Vector2 = m["at"]
		if not bounds.has_point(at):
			continue
		var clear := true
		for k: Dictionary in out:
			if (k["at"] as Vector2).distance_to(at) < min_px:
				clear = false
				break
		if clear:
			out.append(m)
	return out


func _draw_icon(kind: String, at: Vector2, px: float) -> void:
	var row: Dictionary = ctx.repo.resource_icons.get(String((ctx.repo.weather_kinds.get(kind, {}) as Dictionary).get("icon", "")), {})
	var path := String(row.get("texture", ""))
	var tex: Texture2D = load(path) as Texture2D if path != "" and ResourceLoader.exists(path) else null
	if tex != null:
		ResourceIcon.draw_icon_texture(self, tex, at, px)
		return
	draw_circle(at, px * 0.62, MapPalette.named(ctx.repo, "weather_mark_bg"))
	ResourceIcon.draw_glyph(self, String(row.get("icon", "sun")), at, px, Color.WHITE)
```

- [ ] **Step 5: The ruler's estimate.** In `map3d_hud_ruler.gd`, add:

```gdscript
var _eta_key := ""
var _eta := 0


## Days for a courier sent now to reach the column (spec 2026-09-27-courier-core
## §2): one Dijkstra per aim, not per frame — the route depends only on where
## the column stands, and the weather only on the day.
func _courier_eta(code: String) -> int:
	var st := ctx.state()
	var reg := ArmySystem.regiment(ctx.repo, code)
	if st == null or reg.is_empty() or not CourierSystem.carries_orders(reg):
		return 0
	var key := "%s|%s|%d" % [code, ArmySystem.position_of(ctx.repo, st, reg), st.absolute_day()]
	if key != _eta_key:
		_eta_key = key
		_eta = CourierSystem.eta_days(ctx.repo, st, CourierSystem.ORDINARY, code)
	return _eta
```

In `_draw_aim`, after the `text += " · %d day%s"` block:

```gdscript
	var eta := _courier_eta(code)
	if eta > 0:
		text += " · courier ≈%d day%s" % [eta, "" if eta == 1 else "s"]
```

- [ ] **Step 6: Data.** Append to `balance.csv` (stage only these rows):

```
map3d_courier_route_px,1.2,"a courier's road still ahead: dashed, in the realm's colour, finer than a march's map3d_unit_route_px (Map3DHudCouriers)"
map3d_courier_pending_alpha,0.55,"an order still on the road: its route drawn dotted at this share of the realm colour's opacity, an envelope in its ring"
map3d_weather_view_m,60000,"the weather marks show only while the camera is nearer than this (world metres)"
map3d_weather_icon_px,18,"a weather mark's size in design px"
```

Append to `data/political_palette.csv`:

```
weather_mark_bg,#1A1D22,"3D HUD (2026-09-27): the dark disc behind a weather glyph until its art is installed"
```

Add `Hud/Weather` (`Control`, script `map3d_hud_weather.gd`) after `Landmarks`, and `Hud/Couriers` (`Control`, script `map3d_hud_couriers.gd`) after `Armies`. Use the gdai MCP as in Task 10 Step 6; with the text fallback, parent `"Hud"` and give each a new ext_resource id.

- [ ] **Step 7: Run the whole suite.** Expected: PASS, expected error count.
- [ ] **Step 8: Commit**

```bash
git add scripts/map3d/map3d_hud_couriers.gd scripts/map3d/map3d_hud_weather.gd scripts/map3d/map3d_hud_ruler.gd scenes/map3d/world_map_3d.tscn data/balance.csv data/political_palette.csv tests/map3d/test_map3d_hud.gd tests/map3d/test_map3d_scene.gd tests/map3d/test_map3d_hud_weather.gd
git commit -m "feat(couriers): roads ahead, pending orders, counters, weather marks and the aim's estimate"
```

---

### Task 12: Look check through the real game, and the docs

**Files:**
- Modify: `CLAUDE.md` (a "Couriers" paragraph after the military paragraph)
- Modify: `.claude/skills/visual-review/taste.md` only if the owner rules on the look

- [ ] **Step 1: Shoot the flow through the real window.** Use `tools/snapshot_screen.gd`, never a SubViewport shortcut. Follow `.claude/skills/visual-review/`:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_screen.tscn -- --screen court --march3d 0.55,0.5 --march-confirm --shot-frame 5 --out /private/tmp/claude-501/courier_aim.png
```
```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_screen.tscn -- --screen court --march3d 0.55,0.5 --march-confirm --march-commit --speed 4 --shot-frame 240 --out /private/tmp/claude-501/courier_ride.png
```

Read `tools/snapshot_screen.gd`'s argument parser first and use its real flag names. Never pass `--headless`: [[headless-godot-cannot-render-3d]].

Check:
- the aim ruler reads "courier ≈N days";
- a rider leaves the capital;
- his dashed road runs ahead of him;
- the column's pending route is dotted with an envelope;
- zoomed out, the rider is a square letter counter;
- a click on him opens his card in the left column.

- [ ] **Step 2: Independent critic.** Per the visual-review skill, have a fresh reviewer compare the shots to the spec §2. Fix what it finds inside this sub-project's files only.

- [ ] **Step 3: The stand-in check.** Confirm `data/courier_art.csv` still points at `cavalry.glb`. If sub-project D has not delivered, say so in the report as an open item ("the courier model is the INTERIM cavalry — spec §2"). Do not leave it unmentioned.

- [ ] **Step 4: CLAUDE.md.** Add after the military paragraph:

```markdown
**Couriers** (owner 2026-09-27, spec `docs/superpowers/specs/2026-09-27-courier-core-design.md`, sub-project A of the missive system; B intelligence and the Missive kanban next, C interception deferred with enemy AI, D the courier art): an order to a land regiment (`ARMY_MARCH` / `ARMY_GARRISON`) no longer writes the regiment — it DISPATCHES a courier (`CourierSystem`, `GameState.couriers`, saved) from the capital (else the realm's largest town) along the pack's road network (`RoadGraph`: roads and trails with their vertices snapped by `courier_graph_snap_px`, since routes join mid-line; Dijkstra), and the order takes effect only when he reaches the column, re-aiming his last leg as it moves; a higher courier id is a newer order, and an older one arriving late is set aside. His pace is `courier_base_km_per_day` 160 × `courier_kinds.csv` (ordinary 1000‰; secret 750‰, not offered until C) × the stretch's kind (`road_speed.csv`) × the height tier × the WEATHER (`Weather`: stateless, hashed from the seed per province per `weather_spell_days` spell, odds by season and tier in `weather_odds.csv`; it scales a regiment's march too, `ArmySystem.day_march_m`). His fee is a ledger line; fleets are exempt for now. On the 3D map he is `Map3DLayerCouriers` (the cavalry .glb as an INTERIM stand-in until D), his road ahead and a pending order's dotted route are `Map3DHudCouriers`, the weather marks `Map3DHudWeather`; a click opens `CourierCard` in the left column.
```

- [ ] **Step 5: Run the whole suite once more.** Expected: PASS with the expected error count.
- [ ] **Step 6: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: the courier core in CLAUDE.md"
```
