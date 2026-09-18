# Regiment State, Terrain and War Room Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The player's regiments carry morale, wounded, supplies, a hidden training value and hidden per-arm attack/defence, settled monthly and shown on the regiment card as numbers and fuzzy grades; terrain modifies each arm; counters scale with the map; a WAR ROOM tab opens a placeholder.

**Architecture:** A new engine-pure `ArmySystem` (`scripts/engine/army_system.gd`, `RefCounted`, static functions) owns every regiment formula and reads four new data tables; `GameState.regiments` stores only what changes; `TickEngine.advance` calls `ArmySystem.settle_month`; `MapObjects.army_card` reads `ArmySystem` for the card; `WorldMapView` only changes the counter's height rule; `BottomBar` / `InfoScreen` gain one tab.

**Tech Stack:** Godot 4.7, typed GDScript, GUT tests. Run the suite with `./run_tests.sh`; run one file with
`CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gtest=res://tests/<dir>/<file>.gd -gexit`
(read the `Passing` / `Failing` lines; "Errors 2" from the gdai plugin is expected).

**Spec:** `docs/superpowers/specs/2026-09-17-regiment-state-design.md`

## Global Constraints

- **DO NOT COMMIT.** The working tree carries ~150 uncommitted changes from other work (house arms, army art, settlement variants) that these files depend on and that must not be swept into our commits. Leave every change uncommitted; the owner commits. Never run `git add`, `git commit`, `git stash`, `git checkout -- <file>` or `git reset`.
- Another session may edit `data/balance.csv`, `scripts/ui/world_map_view.gd` or other files. Always re-read a file immediately before editing it and use exact-string edits; never rewrite a whole existing file.
- Typed GDScript everywhere (type hints on vars, params, returns). Match surrounding comment density and `##` doc-comment style.
- Design values live in CSVs (`data/*.csv`), never hardcoded in scripts. Every number below that is a tunable goes into `data/balance.csv` or a new table.
- Engine code (`scripts/engine/`) must not reference `Game`, any `scripts/ui` class, `Time.*`, or unseeded `randi()` (a test enforces this). Determinism: the monthly float is a hash of (regiment code, vs arm, tick), NOT a draw from `state.rng`.
- UI words are English: terrains capitalised (`Plains`, `Hills`, …), grades `Strong` / `Average` / `Weak` and `Elite` / `Well drilled` / `Recruits` / `Militia`.
- State exists only for the player's realm's regiments (`repo.resolve_realm("player_realm")`).
- Baseline before this work: `./run_tests.sh` — Scripts 80, Tests 760, Passing 758, Risky/Pending 2, Errors 2, no failures (`/private/tmp/claude-501/-Users-samuelzhang-game-design/f19b83e0-344a-4d36-b4a2-379ff5bf4371/scratchpad/baseline_tests.txt`). Any failure after a task is ours.

---

### Task 1: Data tables and their loading

**Files:**
- Create: `data/army_terrain_biomes.csv`, `data/army_terrain.csv`, `data/army_matchups.csv`, `data/army_training_grades.csv`
- Modify: `scripts/engine/data_repository.gd` (declare four vars next to `army_art` ~line 48; clear them where `army_art` is cleared if it is; load them next to the `army_art.csv` load ~line 407)
- Modify: `data/balance.csv` (append rows at the END of the file)
- Modify: `data/resource_icons.csv` (append six rows at the END)
- Test: `tests/engine/test_army_data.gd` (create)

**Interfaces:**
- Produces on `DataRepository`:
  - `var army_terrain_biomes: Dictionary` — `int biome_id -> String terrain`
  - `var army_terrain: Dictionary` — `"terrain|arm" -> {"defend": int, "attack": int}`
  - `var army_matchups: Dictionary` — `String arm -> Array[Dictionary]` of `{"vs": String, "attack": int, "defense": int}` in file order
  - `var army_training_grades: Array[Dictionary]` — `{"above": int, "label": String}` in file order
- Produces balance keys (exact names): `army_start_morale`, `army_start_training`, `army_start_supply_months`, `army_supply_per_head_permille`, `army_wound_recovery_permille`, `army_training_per_month`, `army_float_permille`, `army_training_base_permille`, `army_training_step_permille`, `army_morale_base_permille`, `army_morale_step_permille`, `army_strong_ratio_permille`, `army_weak_ratio_permille`.
- Produces resource icon keys: `army_terrain`, `army_morale`, `army_wounded`, `army_supply`, `army_training`, `army_strength`.

- [ ] **Step 1: Write the failing test** — `tests/engine/test_army_data.gd`:

```gdscript
extends GutTest
## The regiment tables (owner 2026-09-17, spec 2026-09-17-regiment-state):
## biome -> terrain, terrain x arm modifiers, arm x arm matchups and the
## training grades load, and cover what the pack needs.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")
	assert_not_null(repo, DataRepository.last_error)

func test_every_biome_of_the_pack_names_a_terrain() -> void:
	for id: int in repo.cells.values().map(func(c: Dictionary) -> int: return int(c["biome_id"])):
		assert_true(repo.army_terrain_biomes.has(id), "biome %d has a terrain" % id)

func test_terrain_rows_parse_as_permille() -> void:
	var row: Dictionary = repo.army_terrain["mountains|cavalry"]
	assert_eq(int(row["defend"]), 700)
	assert_eq(int(row["attack"]), 650)
	assert_eq(int((repo.army_terrain["fortified|infantry"] as Dictionary)["defend"]), 1300)

func test_every_arm_has_matchups() -> void:
	for arm: String in repo.world_table("military", "unit_types"):
		assert_true(repo.army_matchups.has(arm), "%s has matchups" % arm)
		assert_gt((repo.army_matchups[arm] as Array).size(), 0)
	var cav: Array = repo.army_matchups["cavalry"]
	var vs_archers: Dictionary = cav.filter(func(m: Dictionary) -> bool: return m["vs"] == "archers")[0]
	assert_eq(int(vs_archers["attack"]), 1300)

func test_training_grades_run_from_elite_to_militia() -> void:
	var labels: Array = repo.army_training_grades.map(func(g: Dictionary) -> String: return String(g["label"]))
	assert_eq(labels, ["Elite", "Well drilled", "Recruits", "Militia"])
	assert_eq(int(repo.army_training_grades[0]["above"]), 80)

func test_balance_and_icons_are_present() -> void:
	for key in ["army_start_morale", "army_start_training", "army_start_supply_months",
			"army_supply_per_head_permille", "army_wound_recovery_permille", "army_training_per_month",
			"army_float_permille", "army_training_base_permille", "army_training_step_permille",
			"army_morale_base_permille", "army_morale_step_permille", "army_strong_ratio_permille",
			"army_weak_ratio_permille"]:
		assert_true(repo.balance.has(key), key)
	assert_eq(int(repo.bal("army_start_training")), 10)
	for key in ["army_terrain", "army_morale", "army_wounded", "army_supply", "army_training", "army_strength"]:
		assert_true(repo.resource_icons.has(key), key)
```

- [ ] **Step 2: Run it — expect FAIL** (`army_terrain_biomes` not declared).

- [ ] **Step 3: Create the CSVs.**

`data/army_terrain_biomes.csv`:
```csv
biome_id,terrain,notes
0,sea,"Marine (owner 2026-09-17, spec 2026-09-17-regiment-state §4): the terrain a regiment stands on, by the biome of its cell; height first makes hills and mountains"
1,desert,Hot desert
2,desert,Cold desert
3,plains,Savanna
4,plains,Grassland
5,jungle,Tropical seasonal forest
6,forest,Temperate deciduous forest
7,jungle,Tropical rainforest
8,forest,Temperate rainforest
9,forest,Taiga
10,tundra,Tundra
11,tundra,Glacier
12,marsh,Wetland
```

`data/army_terrain.csv` (a missing terrain|arm pair is 1000/1000; `fortified` multiplies onto the terrain when defending):
```csv
terrain,arm,defend_permille,attack_permille,notes
mountains,cavalry,700,650,"first draft (owner 2026-09-17): horse cannot charge up a mountain"
jungle,cavalry,750,700,
marsh,cavalry,750,700,
forest,cavalry,850,800,
jungle,infantry,800,800,"infantry lose order in jungle"
hills,archers,1150,1050,"height lengthens a bow's reach"
mountains,artillery,700,700,"guns cannot be hauled up"
marsh,artillery,700,700,
sea,fleet,1000,1000,
fortified,infantry,1300,1000,"behind walls or a citadel"
fortified,archers,1250,1000,
fortified,artillery,1200,1000,
fortified,cavalry,1000,1000,
```

`data/army_matchups.csv`:
```csv
arm,vs_arm,attack_permille,defense_permille,notes
infantry,infantry,1000,1000,"first draft (owner 2026-09-17): each arm's base against each arm; a regiment's value floats around it monthly"
infantry,archers,900,1000,
infantry,cavalry,1200,1300,"spears hold a charge"
infantry,artillery,1100,900,
archers,infantry,1200,800,"arrows thin a slow line"
archers,archers,1000,1000,
archers,cavalry,800,700,
archers,artillery,1000,900,
cavalry,infantry,900,800,
cavalry,archers,1300,1200,"horse rides down bowmen"
cavalry,cavalry,1000,1000,
cavalry,artillery,1300,1100,
artillery,infantry,1100,700,
artillery,archers,900,800,
artillery,cavalry,800,600,
artillery,artillery,1000,1000,
fleet,fleet,1000,1000,
```

`data/army_training_grades.csv` (first row whose `above` is exceeded wins):
```csv
above,label,notes
80,Elite,"owner 2026-09-17: the hidden training value shows only as a grade"
50,Well drilled,
30,Recruits,
-1,Militia,every regiment starts at 10
```

- [ ] **Step 4: Append to `data/balance.csv`** (re-read the file first; append at the very end; keep its `key,value,notes` form and quote notes containing commas):

```csv
army_start_morale,70,"regiments (owner 2026-09-17, spec 2026-09-17-regiment-state): morale a regiment starts with, 0..100; it does not change yet"
army_start_training,10,regiments: the hidden training value a regiment starts with — militia
army_start_supply_months,6,regiments: supplies a regiment starts with in months of its own use
army_supply_per_head_permille,100,"regiments: supply units a head uses a month, per mille (5000 heads use 500 a month); nothing resupplies yet"
army_wound_recovery_permille,200,"regiments: share of the wounded who return to the ranks each month, per mille, at least 1 while any are wounded"
army_training_per_month,0,regiments: training gained each month (placeholder: none)
army_float_permille,150,"regiments: how far a regiment's hidden attack/defence against an arm floats round its base each month, per mille"
army_training_base_permille,500,regiments: the training factor of power at training 0
army_training_step_permille,10,regiments: the training factor gained per point of training (100 -> 1500)
army_morale_base_permille,500,regiments: the morale factor of power at morale 0
army_morale_step_permille,5,regiments: the morale factor gained per point of morale (100 -> 1000)
army_strong_ratio_permille,1250,regiments: power over the mean of the player's regiments of the same kind at/above which a regiment reads Strong
army_weak_ratio_permille,750,regiments: power over that mean at/below which a regiment reads Weak
```

- [ ] **Step 5: Append to `data/resource_icons.csv`** (columns `key,label,icon,tooltip,texture`; texture left empty so the glyph draws):

```csv
army_terrain,Terrain,tower,"The ground the regiment is quartered on, and whether walls shelter it.",
army_morale,Morale,flame,"The regiment's spirit, 0 to 100.",
army_wounded,Wound recovery,cross,The wounded who return to the ranks each month.,
army_supply,Supplies,grain,The supplies the regiment holds and what it uses each month.,
army_training,Training,shield,"How well drilled the regiment is.",
army_strength,Strength,swords,"How the regiment measures against the realm's others of its kind.",
```

- [ ] **Step 6: Load them in `scripts/engine/data_repository.gd`.** Next to `var army_art: Dictionary = {}` add:

```gdscript
## data/army_terrain_biomes.csv: biome id -> the terrain a regiment on it
## stands on (ArmySystem.terrain_of, owner 2026-09-17).
var army_terrain_biomes: Dictionary = {}
## data/army_terrain.csv: "terrain|arm" -> {defend, attack} per mille.
var army_terrain: Dictionary = {}
## data/army_matchups.csv: arm -> [{vs, attack, defense}] per mille, in file order.
var army_matchups: Dictionary = {}
## data/army_training_grades.csv rows {above, label}, first match wins.
var army_training_grades: Array[Dictionary] = []
```

Find where `army_art` is reset (search `army_art.clear()`); if it is, clear the four new containers beside it. Right after the `army_art.csv` `_load_if_present` block add:

```gdscript
	if not _load_if_present(dir + "/army_terrain_biomes.csv", ["biome_id", "terrain"],
			func(r): army_terrain_biomes[int(r["biome_id"])] = String(r["terrain"])):
		return false
	if not _load_if_present(dir + "/army_terrain.csv", ["terrain", "arm", "defend_permille", "attack_permille"],
			func(r): army_terrain["%s|%s" % [r["terrain"], r["arm"]]] = {
				"defend": int(r["defend_permille"]), "attack": int(r["attack_permille"])}):
		return false
	if not _load_if_present(dir + "/army_matchups.csv", ["arm", "vs_arm", "attack_permille", "defense_permille"],
			func(r):
				if not army_matchups.has(String(r["arm"])):
					army_matchups[String(r["arm"])] = []
				(army_matchups[String(r["arm"])] as Array).append({"vs": String(r["vs_arm"]),
					"attack": int(r["attack_permille"]), "defense": int(r["defense_permille"])})):
		return false
	if not _load_if_present(dir + "/army_training_grades.csv", ["above", "label"],
			func(r): army_training_grades.append({"above": int(r["above"]), "label": String(r["label"])})):
		return false
```

(Match the exact indentation of the neighbouring `army_art` block. If a multi-line lambda does not parse, move the matchup sink into a private method `_add_matchup(r: Dictionary) -> void` and pass `_add_matchup`.)

- [ ] **Step 7: Run `tests/engine/test_army_data.gd` — expect PASS.** Also run `tests/engine/test_data_repository.gd` and `tests/engine/test_map_data.gd` — expect no new failures (a test may assert every `data/*.csv` has a loader or every icon row has a texture; if one fails because of the new files, adapt the new data to that test's rule, e.g. give the rows what it demands, and report it).

- [ ] **Step 8: Do not commit.**

---

### Task 2: ArmySystem state and the monthly settlement

**Files:**
- Create: `scripts/engine/army_system.gd`
- Modify: `scripts/engine/game_state.gd` (a `regiments` var, `new_campaign`, `to_dict`, `from_dict`)
- Modify: `scripts/engine/tick_engine.gd` (`advance`)
- Test: `tests/engine/test_army_system.gd` (create)

**Interfaces:**
- Consumes (Task 1): balance keys `army_start_*`, `army_supply_per_head_permille`, `army_wound_recovery_permille`, `army_training_per_month`.
- Consumes (existing): `MapObjects.regiments_of(repo, kingdom_code) -> Array`, `MapObjects.regiment_size(repo, regiment: Dictionary) -> float`, `repo.world_table("military", "regiments") -> Dictionary` (code -> row), `repo.resolve_realm("player_realm") -> String`.
- Produces on `GameState`: `var regiments: Dictionary = {}` — `code -> {"morale": int, "wounded": int, "supplies": int, "training": int}`.
- Produces on `ArmySystem` (class_name `ArmySystem`, extends `RefCounted`, all `static`):
  - `regiment(repo: DataRepository, code: String) -> Dictionary` (the pack row, `{}` if unknown)
  - `headcount(repo: DataRepository, regiment: Dictionary) -> int`
  - `starting_state(repo: DataRepository, regiment: Dictionary) -> Dictionary`
  - `ensure(repo: DataRepository, state: GameState) -> void`
  - `state_of(repo: DataRepository, state: GameState, code: String) -> Dictionary` (stored entry, else the starting state; never writes; `{}` for a regiment that is not the player's)
  - `supply_use(repo: DataRepository, regiment: Dictionary) -> int`
  - `wound_recovery(repo: DataRepository, wounded: int) -> int`
  - `settle_month(repo: DataRepository, state: GameState) -> void`

- [ ] **Step 1: Write the failing test** — `tests/engine/test_army_system.gd`:

```gdscript
extends GutTest
## ArmySystem (owner 2026-09-17, spec 2026-09-17-regiment-state §2-3): the
## player's regiments carry morale, wounded, supplies and training; the
## month's end returns wounded to the ranks and spends supplies.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")

func _mine() -> Array:
	return MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))

func _other_code() -> String:
	var mine := repo.resolve_realm("player_realm")
	for r: Dictionary in repo.world_table("military", "regiments").values():
		if String(r["kingdom_code"]) != mine:
			return String(r["regiment_code"])
	return ""

func test_a_new_campaign_seeds_only_the_players_regiments() -> void:
	var s := GameState.new_campaign(repo, 7)
	assert_eq(s.regiments.size(), _mine().size())
	var r: Dictionary = _mine()[0]
	var entry: Dictionary = s.regiments[String(r["regiment_code"])]
	var heads := int(MapObjects.regiment_size(repo, r))
	assert_eq(int(entry["morale"]), 70)
	assert_eq(int(entry["training"]), 10)
	assert_eq(int(entry["wounded"]), 0)
	# heads x 100 / 1000 a month, times 6 months
	assert_eq(int(entry["supplies"]), heads * 100 / 1000 * 6)
	assert_false(s.regiments.has(_other_code()))

func test_wound_recovery_is_a_share_with_a_floor_of_one() -> void:
	assert_eq(ArmySystem.wound_recovery(repo, 0), 0)
	assert_eq(ArmySystem.wound_recovery(repo, 3), 1, "200 per mille of 3 is 0, floored up to 1")
	assert_eq(ArmySystem.wound_recovery(repo, 250), 50)

func test_the_month_returns_wounded_and_spends_supplies() -> void:
	var s := GameState.new_campaign(repo, 7)
	var r: Dictionary = _mine()[0]
	var code := String(r["regiment_code"])
	var heads := int(MapObjects.regiment_size(repo, r))
	var use := heads * 100 / 1000
	s.regiments[code]["wounded"] = 250
	s.regiments[code]["supplies"] = use + 5
	ArmySystem.settle_month(repo, s)
	assert_eq(int(s.regiments[code]["wounded"]), 200)
	assert_eq(int(s.regiments[code]["supplies"]), 5)
	ArmySystem.settle_month(repo, s)
	assert_eq(int(s.regiments[code]["supplies"]), 0, "supplies stop at zero")
	assert_eq(int(s.regiments[code]["morale"]), 70, "morale does not move yet")

func test_wounded_never_exceed_the_headcount() -> void:
	var s := GameState.new_campaign(repo, 7)
	var r: Dictionary = _mine()[0]
	var code := String(r["regiment_code"])
	var heads := int(MapObjects.regiment_size(repo, r))
	s.regiments[code]["wounded"] = heads * 10
	ArmySystem.settle_month(repo, s)
	assert_lte(int(s.regiments[code]["wounded"]), heads)
	assert_gte(int(s.regiments[code]["wounded"]), 0)

func test_training_is_capped_at_100() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := String(_mine()[0]["regiment_code"])
	s.regiments[code]["training"] = 100
	var saved := repo.balance["army_training_per_month"]
	repo.balance["army_training_per_month"] = 5.0
	ArmySystem.settle_month(repo, s)
	repo.balance["army_training_per_month"] = saved
	assert_eq(int(s.regiments[code]["training"]), 100)

func test_state_of_reads_without_writing() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := String(_mine()[0]["regiment_code"])
	s.regiments.erase(code)
	var view := ArmySystem.state_of(repo, s, code)
	assert_eq(int(view["training"]), 10, "the starting state stands in")
	assert_false(s.regiments.has(code), "a read never seeds")
	assert_true(ArmySystem.state_of(repo, s, _other_code()).is_empty())
	ArmySystem.ensure(repo, s)
	assert_true(s.regiments.has(code), "ensure fills an old save in")

func test_the_state_survives_a_save() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := String(_mine()[0]["regiment_code"])
	s.regiments[code]["wounded"] = 12
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(int(back.regiments[code]["wounded"]), 12)
	assert_eq(int(back.regiments[code]["morale"]), 70)

func test_the_tick_settles_the_regiments() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := String(_mine()[0]["regiment_code"])
	s.regiments[code]["wounded"] = 250
	TickEngine.new(repo).advance(s)
	assert_eq(int(s.regiments[code]["wounded"]), 200)
```

- [ ] **Step 2: Run it — expect FAIL** (`ArmySystem` not found).

- [ ] **Step 3: Add the state to `scripts/engine/game_state.gd`.** Next to `var manor_log: Array = []` add:

```gdscript
## The player's regiments (owner 2026-09-17, ArmySystem): code ->
## {morale, wounded, supplies, training}, all whole numbers. Only the player's
## realm's regiments; the pack's arms stay the headcount.
var regiments: Dictionary = {}
```

In `new_campaign`, after `WorldLedger.seed_metrics(data, s)`, add `ArmySystem.ensure(data, s)`.
In `to_dict`, after the `"manor_log"` entry add `"regiments": _encode_values(regiments.duplicate(true)),`.
In `from_dict`, after `s.manor_log = ...` add `s.regiments = _decode_values(d.get("regiments", {}))`.
Do NOT change `SAVE_VERSION` (an old save simply has no key; `ensure` fills it at the next settlement).

- [ ] **Step 4: Create `scripts/engine/army_system.gd`:**

```gdscript
class_name ArmySystem
extends RefCounted
## The player's regiments as more than a headcount (owner 2026-09-17, spec
## docs/superpowers/specs/2026-09-17-regiment-state-design.md): morale,
## wounded, supplies and a hidden training value, stored in
## GameState.regiments, moved once a month by settle_month. Every number is a
## whole number and every rate is data (balance.csv army_*).

## The pack's row for a regiment, {} when there is none.
static func regiment(repo: DataRepository, code: String) -> Dictionary:
	return repo.world_table("military", "regiments").get(code, {})

## Heads under a regiment's banner, as a whole number.
static func headcount(repo: DataRepository, reg: Dictionary) -> int:
	return int(MapObjects.regiment_size(repo, reg))

## What a regiment starts a campaign with.
static func starting_state(repo: DataRepository, reg: Dictionary) -> Dictionary:
	return {
		"morale": int(repo.bal("army_start_morale")),
		"wounded": 0,
		"supplies": supply_use(repo, reg) * int(repo.bal("army_start_supply_months")),
		"training": int(repo.bal("army_start_training")),
	}

## Seeds every regiment of the player's realm that has no state yet — a new
## campaign, and an old save at its next settlement.
static func ensure(repo: DataRepository, state: GameState) -> void:
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		var code := String(reg["regiment_code"])
		if not state.regiments.has(code):
			state.regiments[code] = starting_state(repo, reg)

## A regiment's state for reading: the stored one, else what it would start
## with. Never writes. {} for a regiment that is not the player's.
static func state_of(repo: DataRepository, state: GameState, code: String) -> Dictionary:
	var reg := regiment(repo, code)
	if reg.is_empty() or String(reg["kingdom_code"]) != repo.resolve_realm("player_realm"):
		return {}
	if state != null and state.regiments.has(code):
		return state.regiments[code]
	return starting_state(repo, reg)

## Supplies a regiment uses in a month.
static func supply_use(repo: DataRepository, reg: Dictionary) -> int:
	return headcount(repo, reg) * int(repo.bal("army_supply_per_head_permille")) / 1000

## Wounded who return to the ranks in a month: a share, at least one while
## any are wounded.
static func wound_recovery(repo: DataRepository, wounded: int) -> int:
	if wounded <= 0:
		return 0
	return maxi(1, wounded * int(repo.bal("army_wound_recovery_permille")) / 1000)

## The month's end for every regiment of the player's realm, in code order:
## wounded return, supplies are spent (nothing resupplies yet), training
## grows by its rate up to 100. Morale does not move yet.
static func settle_month(repo: DataRepository, state: GameState) -> void:
	ensure(repo, state)
	var codes := state.regiments.keys()
	codes.sort()
	for code: String in codes:
		var reg := regiment(repo, code)
		if reg.is_empty():
			continue
		var entry: Dictionary = state.regiments[code]
		var heads := headcount(repo, reg)
		var wounded := clampi(int(entry["wounded"]), 0, heads)
		entry["wounded"] = clampi(wounded - wound_recovery(repo, wounded), 0, heads)
		entry["supplies"] = maxi(0, int(entry["supplies"]) - supply_use(repo, reg))
		entry["training"] = mini(100, int(entry["training"]) + int(repo.bal("army_training_per_month")))
```

(If `for code: String in codes` complains about the Array element type, use `for c in codes:` with `var code := String(c)`.)

- [ ] **Step 5: Hook the tick.** In `scripts/engine/tick_engine.gd` `advance`, right after `_settle_economy(state, r)` add:

```gdscript
	# The regiments' month (owner 2026-09-17): wounded return, supplies spent.
	ArmySystem.settle_month(data, state)
```

- [ ] **Step 6: Run `tests/engine/test_army_system.gd` — expect PASS.** Then run `tests/engine/test_tick_engine.gd`, `tests/engine/test_game_state.gd`, `tests/engine/test_save_load.gd`, `tests/engine/test_determinism.gd`, `tests/engine/test_engine_isolation.gd` — expect no new failures.

- [ ] **Step 7: Do not commit.**

---

### Task 3: Terrain under a regiment

**Files:**
- Modify: `scripts/engine/map_economy.gd` (extract a cached land grid and a public `cell_at`; make `burg_cells` use it)
- Modify: `scripts/engine/army_system.gd` (terrain functions)
- Test: `tests/engine/test_army_terrain.gd` (create)

**Interfaces:**
- Consumes (Task 1): `repo.army_terrain_biomes`, `repo.army_terrain`; balance `manor_focus_peak_height`, `manor_focus_high_height`.
- Produces:
  - `MapEconomy.cell_at(repo: DataRepository, point: Vector2) -> int` — the land cell whose polygon holds the point, else the nearest land cell centre within the 3x3 bucket neighbourhood, else `-1`.
  - `ArmySystem.terrain_of(repo: DataRepository, reg: Dictionary) -> String` — `sea`, `mountains`, `hills` or the biome's terrain (`plains` when the biome has no row).
  - `ArmySystem.is_fortified(repo: DataRepository, reg: Dictionary) -> bool`
  - `ArmySystem.terrain_factor(repo: DataRepository, terrain: String, arm: String, stance: String, fortified: bool) -> int` — `stance` is `"defend"` or `"attack"`; per mille.
  - `ArmySystem.terrain_label(repo: DataRepository, reg: Dictionary) -> String` — e.g. `"Hills"` or `"Hills (fortified)"`.

- [ ] **Step 1: Write the failing test** — `tests/engine/test_army_terrain.gd`:

```gdscript
extends GutTest
## Terrain under a regiment (owner 2026-09-17, spec §4): height makes hills
## and mountains, else the cell's biome decides; walls or a citadel in the
## same cell fortify it; the modifier table is per mille and defaults to 1000.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")

## A regiment dict standing at a cell's centre (the pack is generated, so the
## test finds its cells by what they are, never by id).
func _at_cell(id: int, naval: bool = false) -> Dictionary:
	var c := MapTerrain.cell_center(repo, repo.cells[id])
	return {"regiment_code": "t", "kingdom_code": "t", "x": str(c.x), "y": str(c.y),
		"is_naval": "1" if naval else "0"}

func _land_cell(pred: Callable) -> int:
	var ids := repo.cells.keys()
	ids.sort()
	for id: int in ids:
		var cell: Dictionary = repo.cells[id]
		if MapTerrain.is_water(cell) or (cell["vertex_ids"] as PackedInt32Array).size() < 3:
			continue
		if pred.call(cell):
			return id
	return -1

func test_cell_at_finds_the_cell_it_stands_in() -> void:
	var id := _land_cell(func(_c: Dictionary) -> bool: return true)
	assert_eq(MapEconomy.cell_at(repo, MapTerrain.cell_center(repo, repo.cells[id])), id)

func test_height_makes_mountains_and_hills() -> void:
	var peak := repo.bal("manor_focus_peak_height")
	var high := repo.bal("manor_focus_high_height")
	var m := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= peak)
	if m >= 0:
		assert_eq(ArmySystem.terrain_of(repo, _at_cell(m)), "mountains")
	var h := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) >= high and float(c["height"]) < peak)
	assert_gte(h, 0, "the pack has hills")
	assert_eq(ArmySystem.terrain_of(repo, _at_cell(h)), "hills")

func test_low_ground_takes_its_biomes_terrain() -> void:
	var high := repo.bal("manor_focus_high_height")
	var f := _land_cell(func(c: Dictionary) -> bool: return float(c["height"]) < high and int(c["biome_id"]) == 6)
	assert_gte(f, 0, "the pack has low deciduous forest")
	assert_eq(ArmySystem.terrain_of(repo, _at_cell(f)), "forest")
	assert_eq(ArmySystem.terrain_label(repo, _at_cell(f)).begins_with("Forest"), true)

func test_a_fleet_is_at_sea() -> void:
	var id := _land_cell(func(_c: Dictionary) -> bool: return true)
	assert_eq(ArmySystem.terrain_of(repo, _at_cell(id, true)), "sea")

func test_walls_in_the_cell_fortify() -> void:
	var cells := MapEconomy.burg_cells(repo)
	var walled := ""
	var codes := repo.burgs.keys()
	codes.sort()
	for code: String in codes:
		var feats := String(repo.burgs[code].get("features", "")).split("|")
		if ("walls" in feats or "citadel" in feats) and cells.has(code):
			walled = code
			break
	assert_ne(walled, "", "the pack has a walled town")
	var reg := _at_cell(int(cells[walled]))
	assert_true(ArmySystem.is_fortified(repo, reg))
	assert_string_contains(ArmySystem.terrain_label(repo, reg), "(fortified)")

func test_the_modifier_table() -> void:
	assert_eq(ArmySystem.terrain_factor(repo, "mountains", "cavalry", "defend", false), 700)
	assert_eq(ArmySystem.terrain_factor(repo, "mountains", "cavalry", "attack", false), 650)
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "cavalry", "attack", false), 1000, "a missing row is 1000")
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "infantry", "defend", true), 1300, "walls on open ground")
	assert_eq(ArmySystem.terrain_factor(repo, "jungle", "infantry", "defend", true), 800 * 1300 / 1000)
	assert_eq(ArmySystem.terrain_factor(repo, "jungle", "infantry", "attack", true), 800, "walls only help the defender")
```

- [ ] **Step 2: Run it — expect FAIL.**

- [ ] **Step 3: Refactor `scripts/engine/map_economy.gd`.** Re-read the file. Keep `burg_cells`' behaviour exactly (the existing economy tests guard it). Add a second cache var next to `_burg_cell_cache` (and clear it in `forget()` beside the others), move the bucket-grid construction into a cached `_land_grid(repo) -> Dictionary` returning `{"bucket": float, "grid": Dictionary}`, and move the 3x3 search into:

```gdscript
## The land cell holding a map point: the cell whose polygon contains it, else
## the land cell with the nearest centre in the neighbouring buckets (a point
## on the shoreline can sit a hair outside every land polygon). -1 when no
## land cell is near.
static func cell_at(repo: DataRepository, p: Vector2) -> int:
	var lg := _land_grid(repo)
	var bucket: float = lg["bucket"]
	var grid: Dictionary = lg["grid"]
	var home := Vector2i((p / bucket).floor())
	var nearest := -1
	var nearest_d := INF
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			for id: int in grid.get(home + Vector2i(dx, dy), []):
				var cell: Dictionary = repo.cells[id]
				if Geometry2D.is_point_in_polygon(p, cell_polygon(repo, cell)):
					return id
				var d := p.distance_squared_to(MapTerrain.cell_center(repo, cell))
				if d < nearest_d:
					nearest_d = d
					nearest = id
	return nearest
```

Then `burg_cells` loops the burgs calling `cell_at` and keeps its own cache. Note: the old loop only compared distances while no polygon had matched; returning on the first polygon hit is the same result.

- [ ] **Step 4: Add terrain to `scripts/engine/army_system.gd`** (append):

```gdscript
## --- Terrain (spec §4) ---------------------------------------------------

## The ground a regiment stands on: sea for a fleet; mountains and hills by
## the cell's height (the manors' own thresholds); else its biome's terrain.
static func terrain_of(repo: DataRepository, reg: Dictionary) -> String:
	if String(reg.get("is_naval", "0")) == "1":
		return "sea"
	var id := MapEconomy.cell_at(repo, Vector2(float(reg["x"]), float(reg["y"])))
	if id < 0:
		return "plains"
	var cell: Dictionary = repo.cells[id]
	var h := float(cell["height"])
	if h >= repo.bal("manor_focus_peak_height"):
		return "mountains"
	if h >= repo.bal("manor_focus_high_height"):
		return "hills"
	return String(repo.army_terrain_biomes.get(int(cell["biome_id"]), "plains"))

## Whether walls or a citadel stand in the regiment's cell.
static func is_fortified(repo: DataRepository, reg: Dictionary) -> bool:
	if String(reg.get("is_naval", "0")) == "1":
		return false
	var id := MapEconomy.cell_at(repo, Vector2(float(reg["x"]), float(reg["y"])))
	if id < 0:
		return false
	var cells := MapEconomy.burg_cells(repo)
	for code: String in cells:
		if int(cells[code]) != id:
			continue
		var feats := String((repo.burgs.get(code, {}) as Dictionary).get("features", "")).split("|")
		if "walls" in feats or "citadel" in feats:
			return true
	return false

## An arm's modifier on a terrain, per mille (1000 when the table has no
## row); walls multiply onto it for the defender only.
static func terrain_factor(repo: DataRepository, terrain: String, arm: String, stance: String, fortified: bool) -> int:
	var f := int((repo.army_terrain.get("%s|%s" % [terrain, arm], {}) as Dictionary).get(stance, 1000))
	if fortified and stance == "defend":
		f = f * int((repo.army_terrain.get("fortified|%s" % arm, {}) as Dictionary).get("defend", 1000)) / 1000
	return f

## "Hills", or "Hills (fortified)".
static func terrain_label(repo: DataRepository, reg: Dictionary) -> String:
	var text := terrain_of(repo, reg).capitalize()
	return text + " (fortified)" if is_fortified(repo, reg) else text
```

- [ ] **Step 5: Run `tests/engine/test_army_terrain.gd` — expect PASS.** Run `tests/engine/test_map_economy.gd`, `tests/engine/test_manor_economy.gd`, `tests/engine/test_realm_economy.gd` — expect no new failures.

- [ ] **Step 6: Do not commit.**

---

### Task 4: Power, grades and the placeholder battle odds

**Files:**
- Modify: `scripts/engine/army_system.gd` (append)
- Test: `tests/engine/test_army_power.gd` (create)

**Interfaces:**
- Consumes: Task 1 tables and balance keys; Task 2 `state_of`, `regiment`, `headcount`; Task 3 `terrain_of`, `is_fortified`, `terrain_factor`.
- Produces:
  - `ArmySystem.float_factor(repo: DataRepository, code: String, vs_arm: String, tick: int) -> int` — in `[1000 − F, 1000 + F]`, `F = army_float_permille`.
  - `ArmySystem.power(repo: DataRepository, state: GameState, code: String, stance: String) -> int`
  - `ArmySystem.training_grade(repo: DataRepository, training: int) -> String`
  - `ArmySystem.strength_grade(repo: DataRepository, state: GameState, code: String) -> String` — `"Strong"`, `"Average"` or `"Weak"`.
  - `ArmySystem.battle_odds(repo: DataRepository, state: GameState, attacker_code: String, defender_code: String) -> float` — PLACEHOLDER.

- [ ] **Step 1: Write the failing test** — `tests/engine/test_army_power.gd`:

```gdscript
extends GutTest
## Hidden strength (owner 2026-09-17, spec §5-6): a float round each arm's
## base, power from heads, training, morale and terrain, grades that show only
## words, and a placeholder battle odds.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")

func _land_codes() -> Array:
	var out: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1":
			out.append(String(r["regiment_code"]))
	out.sort()
	return out

func test_the_float_is_deterministic_bounded_and_monthly() -> void:
	var a := ArmySystem.float_factor(repo, "x", "cavalry", 3)
	assert_eq(a, ArmySystem.float_factor(repo, "x", "cavalry", 3))
	var changed := false
	for t in range(4, 12):
		var f := ArmySystem.float_factor(repo, "x", "cavalry", t)
		assert_between(f, 850, 1150)
		changed = changed or f != a
	assert_true(changed, "the value moves month to month")

func test_training_grades_at_their_edges() -> void:
	assert_eq(ArmySystem.training_grade(repo, 10), "Militia")
	assert_eq(ArmySystem.training_grade(repo, 30), "Militia")
	assert_eq(ArmySystem.training_grade(repo, 31), "Recruits")
	assert_eq(ArmySystem.training_grade(repo, 50), "Recruits")
	assert_eq(ArmySystem.training_grade(repo, 51), "Well drilled")
	assert_eq(ArmySystem.training_grade(repo, 80), "Well drilled")
	assert_eq(ArmySystem.training_grade(repo, 81), "Elite")

func test_power_follows_training_morale_and_wounds() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code: String = _land_codes()[0]
	var base := ArmySystem.power(repo, s, code, "defend")
	assert_gt(base, 0)
	s.regiments[code]["training"] = 90
	var drilled := ArmySystem.power(repo, s, code, "defend")
	assert_gt(drilled, base)
	# training factor 500+10*10=600 -> 500+10*90=1400
	assert_almost_eq(float(drilled) / float(base), 1400.0 / 600.0, 0.01)
	s.regiments[code]["wounded"] = ArmySystem.headcount(repo, ArmySystem.regiment(repo, code))
	assert_eq(ArmySystem.power(repo, s, code, "defend"), 0, "a regiment of wounded has no power")

func test_strength_grades_against_the_mean_of_its_kind() -> void:
	var s := GameState.new_campaign(repo, 7)
	var codes := _land_codes()
	assert_gt(codes.size(), 1, "the player has several land regiments")
	var code: String = codes[0]
	s.regiments[code]["training"] = 100
	s.regiments[code]["morale"] = 100
	assert_eq(ArmySystem.strength_grade(repo, s, code), "Strong")
	var weak: String = codes[1]
	s.regiments[weak]["wounded"] = ArmySystem.headcount(repo, ArmySystem.regiment(repo, weak))
	assert_eq(ArmySystem.strength_grade(repo, s, weak), "Weak")

func test_a_lone_kind_is_average() -> void:
	var s := GameState.new_campaign(repo, 7)
	var fleets: Array = MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")).filter(
		func(r: Dictionary) -> bool: return String(r.get("is_naval", "0")) == "1")
	if fleets.size() == 1:
		assert_eq(ArmySystem.strength_grade(repo, s, String(fleets[0]["regiment_code"])), "Average")
	else:
		pass_test("the pack's player realm has %d fleets" % fleets.size())

func test_battle_odds_placeholder() -> void:
	var s := GameState.new_campaign(repo, 7)
	var codes := _land_codes()
	var odds := ArmySystem.battle_odds(repo, s, codes[0], codes[1])
	assert_between(odds, 0.0, 1.0)
	s.regiments[codes[0]]["training"] = 100
	assert_gt(ArmySystem.battle_odds(repo, s, codes[0], codes[1]), odds, "a better drilled attacker has better odds")
```

- [ ] **Step 2: Run it — expect FAIL.**

- [ ] **Step 3: Append to `scripts/engine/army_system.gd`:**

```gdscript
## --- Hidden strength (spec §5) ------------------------------------------

## A regiment's hidden value against an arm floats round its base, month by
## month: a hash of (regiment, arm, tick), never a draw from the engine's
## RNG stream, so it is deterministic and moves no other seeded roll.
static func float_factor(repo: DataRepository, code: String, vs_arm: String, tick: int) -> int:
	var spread := int(repo.bal("army_float_permille"))
	return 1000 - spread + posmod(("%s|%s|%d" % [code, vs_arm, tick]).hash(), spread * 2 + 1)

## An arm's base, per mille: the mean over its matchups of (attack +
## defense) / 2, each scaled by the month's float.
static func _arm_base(repo: DataRepository, code: String, arm: String, tick: int) -> int:
	var rows: Array = repo.army_matchups.get(arm, [])
	if rows.is_empty():
		return 1000
	var sum := 0
	for m: Dictionary in rows:
		sum += (int(m["attack"]) + int(m["defense"])) / 2 * float_factor(repo, code, String(m["vs"]), tick) / 1000
	return sum / rows.size()

## A regiment's power where it stands, in the given stance ("defend" or
## "attack"): each arm's heads less its share of the wounded, times the arm's
## base, the training and morale factors and the terrain. 0 for a regiment
## without state.
static func power(repo: DataRepository, state: GameState, code: String, stance: String) -> int:
	var reg := regiment(repo, code)
	var st := state_of(repo, state, code)
	if reg.is_empty() or st.is_empty():
		return 0
	var heads := headcount(repo, reg)
	if heads <= 0:
		return 0
	var fit := heads - clampi(int(st["wounded"]), 0, heads)
	var tick := 0 if state == null else state.tick
	var training_f := int(repo.bal("army_training_base_permille")) + int(st["training"]) * int(repo.bal("army_training_step_permille"))
	var morale_f := int(repo.bal("army_morale_base_permille")) + int(st["morale"]) * int(repo.bal("army_morale_step_permille"))
	var terrain := terrain_of(repo, reg)
	var walls := is_fortified(repo, reg)
	var total := 0
	for arm: String in repo.world_table("military", "unit_types"):
		var n := int(float(reg.get(arm, 0)))
		if n <= 0:
			continue
		var p := n * fit / heads
		p = p * _arm_base(repo, code, arm, tick) / 1000
		p = p * training_f / 1000
		p = p * morale_f / 1000
		p = p * terrain_factor(repo, terrain, arm, stance, walls) / 1000
		total += p
	return total

## The training grade a hidden training value shows as.
static func training_grade(repo: DataRepository, training: int) -> String:
	for g: Dictionary in repo.army_training_grades:
		if training > int(g["above"]):
			return String(g["label"])
	return "" if repo.army_training_grades.is_empty() else String(repo.army_training_grades.back()["label"])

## Strong, Average or Weak: the regiment's defending power over the mean of
## the player's regiments of the same kind (land or fleet). A kind of one is
## Average.
static func strength_grade(repo: DataRepository, state: GameState, code: String) -> String:
	var reg := regiment(repo, code)
	if reg.is_empty():
		return ""
	var naval := String(reg.get("is_naval", "0")) == "1"
	var sum := 0
	var n := 0
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if (String(r.get("is_naval", "0")) == "1") != naval:
			continue
		sum += power(repo, state, String(r["regiment_code"]), "defend")
		n += 1
	if n <= 1 or sum <= 0:
		return "Average"
	var ratio := power(repo, state, code, "defend") * 1000 * n / sum
	if ratio >= int(repo.bal("army_strong_ratio_permille")):
		return "Strong"
	if ratio <= int(repo.bal("army_weak_ratio_permille")):
		return "Weak"
	return "Average"

## PLACEHOLDER (owner 2026-09-17: the battle formula is not decided). The
## attacker's power in the attack stance over both sides' powers, each on its
## own ground. Called by nothing but its test; replace it whole when the
## owner settles the formula.
static func battle_odds(repo: DataRepository, state: GameState, attacker_code: String, defender_code: String) -> float:
	var a := power(repo, state, attacker_code, "attack")
	var d := power(repo, state, defender_code, "defend")
	if a + d <= 0:
		return 0.5
	return float(a) / float(a + d)
```

- [ ] **Step 4: Run `tests/engine/test_army_power.gd` — expect PASS.** If `test_strength_grades_against_the_mean_of_its_kind` fails because the player's land regiments differ so much in size that a maxed regiment is not ≥1.25× the mean, pick in the test the regiment with the largest headcount for "Strong" and the one with the smallest for "Weak" (sort `codes` by `ArmySystem.headcount`), keeping the same assertions. Run `tests/engine/test_engine_isolation.gd` and `tests/engine/test_army_system.gd` too.

- [ ] **Step 5: Do not commit.**

---

### Task 5: The regiment card shows the state

**Files:**
- Modify: `scripts/engine/map_objects.gd` (`army_card`, ~line 1457)
- Modify: `scripts/ui/map_detail_panel.gd` (~line 256, the `army_card` call)
- Modify: `tests/engine/test_map_objects.gd` (`test_a_regiment_card_paints_its_piece_and_lists_its_arms`, ~line 347)

**Interfaces:**
- Consumes: Task 2 `state_of`, `wound_recovery`, `supply_use`, `headcount`; Task 3 `terrain_label`; Task 4 `training_grade`, `strength_grade`.
- Produces: `MapObjects.army_card(repo: DataRepository, code: String, state: GameState = null) -> Dictionary`. With a state and a player regiment, `stats` holds (after the per-arm stats) in order: `army` ("N (W wounded)"), `manor_province` (unchanged, when quartered), `army_terrain`, `army_morale`, `army_wounded` ("+R / mo"), `army_supply` ("S (−U / mo)"), `army_training` (grade), `army_strength` (grade). Without a state (or for another realm's regiment) the card is exactly as before.

- [ ] **Step 1: Update the test first.** In `tests/engine/test_map_objects.gd`, inside `test_a_regiment_card_paints_its_piece_and_lists_its_arms`, keep the existing loop (it calls `army_card(Game.data, code)` with no state and must still pass) and add a second test after it:

```gdscript
## The card of a player's regiment reads its state (owner 2026-09-17): the
## ground, morale, the wounded beside the headcount, the month's recovery
## and supply use, and the training and strength only as words.
func test_a_regiment_card_shows_its_state() -> void:
	var s := GameState.new_campaign(Game.data, 7)
	var mine := Game.data.resolve_realm("player_realm")
	var r: Dictionary = MapObjects.regiments_of(Game.data, mine)[0]
	var code := String(r["regiment_code"])
	var heads := int(MapObjects.regiment_size(Game.data, r))
	s.regiments[code]["wounded"] = 120
	var card := MapObjects.army_card(Game.data, code, s)
	var order: Array = []
	var text: Dictionary = {}
	for st: Dictionary in card["stats"]:
		order.append(String(st["key"]))
		text[String(st["key"])] = String(st["text"])
		assert_ne(String(st["tooltip"]), "", "%s explains itself" % st["key"])
	for key in ["army_terrain", "army_morale", "army_wounded", "army_supply", "army_training", "army_strength"]:
		assert_true(text.has(key), key)
	assert_true(order.find("army_terrain") < order.find("army_strength"), "the state reads in order")
	assert_eq(text["army"], "%d (120 wounded)" % heads)
	assert_eq(text["army_morale"], "70")
	assert_eq(text["army_wounded"], "+%d / mo" % ArmySystem.wound_recovery(Game.data, 120))
	var use := ArmySystem.supply_use(Game.data, r)
	assert_eq(text["army_supply"], "%d (−%d / mo)" % [int(s.regiments[code]["supplies"]), use])
	assert_eq(text["army_training"], "Militia")
	assert_true(text["army_strength"] in ["Strong", "Average", "Weak"])
	assert_eq(text["army_terrain"], ArmySystem.terrain_label(Game.data, r))
	# No number leaks for the hidden values.
	assert_false(text["army_training"].is_valid_int())
```

- [ ] **Step 2: Run `tests/engine/test_map_objects.gd` — expect the new test to FAIL** (too many arguments / missing keys).

- [ ] **Step 3: Change `MapObjects.army_card`.** Re-read the function. Change the signature to `static func army_card(repo: DataRepository, code: String, state: GameState = null) -> Dictionary:` and update its doc comment's last line to mention "and, for the player's own regiment with a state, its terrain, morale, wounded, supplies, training and strength (ArmySystem, owner 2026-09-17)". Then, replacing the line `stats.append(_stat("army", str(total), "Under arms — %d" % total))`:

```gdscript
	var st := ArmySystem.state_of(repo, state, code) if state != null else {}
	if st.is_empty():
		stats.append(_stat("army", str(total), "Under arms — %d" % total))
	else:
		var wounded := int(st["wounded"])
		stats.append(_stat("army", "%d (%d wounded)" % [total, wounded],
			"Under arms — %d, of whom %d are wounded" % [total, wounded]))
```

and, after the existing `if province != "":` block (before `return`), add:

```gdscript
	if not st.is_empty():
		var ground := ArmySystem.terrain_label(repo, r)
		stats.append(_stat("army_terrain", ground, "Quartered on %s" % ground.to_lower()))
		stats.append(_stat("army_morale", str(int(st["morale"])), "Morale — %d of 100" % int(st["morale"])))
		var back := ArmySystem.wound_recovery(repo, int(st["wounded"]))
		stats.append(_stat("army_wounded", "+%d / mo" % back,
			"%d wounded return to the ranks each month" % back))
		var use := ArmySystem.supply_use(repo, r)
		stats.append(_stat("army_supply", "%d (−%d / mo)" % [int(st["supplies"]), use],
			"Supplies — %d held, %d used each month" % [int(st["supplies"]), use]))
		var drill := ArmySystem.training_grade(repo, int(st["training"]))
		stats.append(_stat("army_training", drill, "Training — %s" % drill))
		var might := ArmySystem.strength_grade(repo, state, code)
		stats.append(_stat("army_strength", might, "Strength — %s against the realm's others of its kind" % might))
```

(The minus sign in `−%d` is U+2212, as in the test; keep them identical.)

- [ ] **Step 4: Pass the state from the panel.** In `scripts/ui/map_detail_panel.gd` change `MapObjects.army_card(Game.data, String(obj["code"]))` to `MapObjects.army_card(Game.data, String(obj["code"]), Game.state)`.

- [ ] **Step 5: Run `tests/engine/test_map_objects.gd` (both regiment tests PASS) and `tests/ui/test_map_detail_panel.gd` — expect no new failures.** If the detail panel's stat grid cannot fit seven more rows in the fixed-width column, it must wrap/scroll per CLAUDE.md invariant 10 — check with `tests/ui/test_map_detail_panel.gd` and, if needed, report rather than widen the column.

- [ ] **Step 6: Do not commit.**

---

### Task 6: Counters scale with the map, never thinned

**Files:**
- Modify: `scripts/ui/world_map_view.gd` (`army_badge_height`, ~line 670, and its doc comment)
- Modify: `data/balance.csv` (rows `map_army_badge_frac` and `map_army_badge_max_px` replaced by `map_army_badge_native_px`)
- Modify: `tests/ui/test_world_map_view.gd` (~line 800, the zoom loop that asserts `< sprite_height` and `<= map_army_badge_max_px`)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: balance key `map_army_badge_native_px` (7.7); `army_badge_height()` = `maxf(map_army_badge_native_px × view_scale(), map_army_badge_min_px)`.

- [ ] **Step 1: Update the view test.** Re-read `tests/ui/test_world_map_view.gd` around the zoom loop. Replace the loop body's two assertions `assert_lt(v.army_badge_height(), v.sprite_height(), ...)` and `assert_lte(v.army_badge_height(), Game.data.bal("map_army_badge_max_px"))` (keep `assert_gt(v.sprite_height(), 0.0, ...)` only if still true; keep the "covers no settlement" check) and add a new test after that test:

```gdscript
## Owner 2026-09-17: a counter grows and shrinks with the map (above a small
## floor), and every regiment in the frame is drawn at every zoom — nothing
## thins the counters the way the estates thin.
func test_counters_scale_with_the_map_and_are_never_thinned() -> void:
	var v := _view()
	await wait_frames(2)
	v.show_armies = true
	var mine := Game.data.resolve_realm("player_realm")
	var floor_px := Game.data.bal("map_army_badge_min_px")
	var native := Game.data.bal("map_army_badge_native_px")
	for zoom in [0.25, 1.0, 4.0, 16.0]:
		v._zoom_at(v.size / 2.0, zoom)
		var expect := maxf(native * v.view_scale(), floor_px)
		assert_almost_eq(v.army_badge_height(), expect, 0.01, "height at scale %f" % v.view_scale())
		var frame := Rect2(Vector2.ZERO, v.size).grow(v.army_badge_height() * 4.0)
		var in_frame := 0
		for r: Dictionary in MapObjects.regiments_of(Game.data, mine):
			if frame.has_point(v.map_to_screen(Vector2(float(r["x"]), float(r["y"])))):
				in_frame += 1
		assert_eq(v.army_markers().size(), in_frame, "every regiment in the frame is drawn")
```

(`_zoom_at(point, factor)` multiplies the zoom and clamps it; the test reads `view_scale()` after each call rather than assuming the factor stuck.)

- [ ] **Step 2: Run `tests/ui/test_world_map_view.gd` — expect the new test to FAIL** (`map_army_badge_native_px` missing).

- [ ] **Step 3: Change the balance rows.** Re-read `data/balance.csv`. Replace the `map_army_badge_frac` row and the `map_army_badge_max_px` row with ONE row:

```csv
map_army_badge_native_px,7.7,"military layer: height of a regiment's counter in NATIVE map px, times the zoom (owner 2026-09-17: counters scale with the map and are never thinned; 7.7 = the old 0.35 of a 0.22 settlement drawing, so the unclamped size is unchanged), never below map_army_badge_min_px"
```

Update the `map_army_badge_min_px` note to: `military layer: the smallest a counter gets in screen px however far the map zooms out`.
Then `grep -rn "map_army_badge_frac\|map_army_badge_max_px" scripts tests tools` and fix every remaining reference.

- [ ] **Step 4: Change `army_badge_height()`** in `scripts/ui/world_map_view.gd`:

```gdscript
## A counter's height in screen px: map_army_badge_native_px of the map,
## times the zoom — it grows and shrinks with the map (owner 2026-09-17) —
## never below map_army_badge_min_px, so the farthest zoom still shows every
## regiment. No ceiling and no thinning: every regiment is always drawn.
func army_badge_height() -> float:
	var repo := Game.data
	return maxf(repo.bal("map_army_badge_native_px") * view_scale(), repo.bal("map_army_badge_min_px"))
```

Also update the `army_markers()` doc comment's first paragraph to say counters are never thinned (only the screen frame filters).

- [ ] **Step 5: Run `tests/ui/test_world_map_view.gd` — expect PASS** (both the new test and the updated one). Render a check shot and look at it:
`/Applications/Godot.app/Contents/MacOS/Godot --path . res://tools/snapshot_map.tscn -- --out /private/tmp/claude-501/-Users-samuelzhang-game-design/f19b83e0-344a-4d36-b4a2-379ff5bf4371/scratchpad/army_zoom.png --armies 1 --home 1 --zoom 3.0`
Report whether the counters are visible and not covering towns.

- [ ] **Step 6: Do not commit.**

---

### Task 7: WAR ROOM placeholder tab, docs, full suite

**Files:**
- Modify: `scripts/ui/bottom_bar.gd` (`TABS`, the header comment)
- Modify: `scripts/ui/info_screen.gd` (`_rows_for`)
- Modify: `tests/ui/test_ui_rework.gd` or `tests/ui/test_game_root.gd` (add a test)
- Modify: `CLAUDE.md` (one paragraph)

**Interfaces:**
- Consumes: nothing.
- Produces: tab `"WAR ROOM"` in `BottomBar.TABS` (after `"MILITARY"`), routed by `GameRoot._on_bottom_tab`'s default branch to `InfoScreen.show_tab("WAR ROOM")`, whose rows are `[["War Room", "The war room is being prepared."]]`.

- [ ] **Step 1: Write the failing test.** Re-read how `tests/ui/test_game_root.gd` presses a bottom tab and reads the InfoScreen (search `_on_bottom_tab` / `info_screen()` in that file) and add, following its setup exactly:

```gdscript
## Owner 2026-09-17: a WAR ROOM tab, a placeholder page for now.
func test_the_war_room_tab_opens_its_placeholder() -> void:
	assert_true("WAR ROOM" in BottomBar.TABS)
	assert_false("WAR ROOM" in BottomBar.TOGGLES, "it opens a page, it is not a map toggle")
	# <GameRoot setup as the neighbouring tab tests do it>
	root._on_bottom_tab("WAR ROOM")
	var info := root.info_screen()
	assert_true(info.visible)
	assert_eq(info._current_tab, "WAR ROOM")
	assert_eq(info._rows_for("WAR ROOM"), [["War Room", "The war room is being prepared."]])
```

Replace the `# <GameRoot setup …>` comment with the same lines the neighbouring bottom-tab test in that file uses to build `root` (copy them verbatim). The existing `tests/ui/test_ui_rework.gd` check that all tabs fit 1280 px covers the width.

- [ ] **Step 2: Run it — expect FAIL.**

- [ ] **Step 3: Implement.** In `scripts/ui/bottom_bar.gd`: `const TABS := ["HEIGHTS", "ECONOMY", "MANORS", "REALM", "MILITARY", "WAR ROOM", "FAMILIES", "LAWS", "RELIGION", "RELATIONSHIP"]` and add `WAR ROOM` to the header comment's list with "(a placeholder page, owner 2026-09-17)". In `scripts/ui/info_screen.gd` `_rows_for`, add a branch before the default:

```gdscript
		"WAR ROOM":
			# Owner 2026-09-17: a placeholder until the war room is designed.
			return [["War Room", "The war room is being prepared."]]
```

- [ ] **Step 4: Run the new test and `tests/ui/test_ui_rework.gd` — expect PASS** (the row must still fit 1280 px; if it does not, report the measured width instead of shrinking fonts).

- [ ] **Step 5: CLAUDE.md.** Re-read `CLAUDE.md`, find the paragraph starting `**Armies are 3D tabletop pieces from Hunyuan3D**` and append at its end:

```markdown
 **Regiments carry a state** (owner 2026-09-17, spec `docs/superpowers/specs/2026-09-17-regiment-state-design.md`): `ArmySystem` (`scripts/engine/`, pure, static) keeps the PLAYER's regiments' morale, wounded (never above the headcount), supplies and a hidden training value in `GameState.regiments`, and `TickEngine.advance` settles them monthly (`settle_month`: wounded return at `army_wound_recovery_permille`, supplies fall by `army_supply_per_head_permille` with no resupply yet, morale fixed, training growth 0). Terrain comes from the regiment's cell (`MapEconomy.cell_at`: height makes hills and mountains, else `data/army_terrain_biomes.csv`; walls or a citadel in the cell fortify) and scales each arm through `data/army_terrain.csv`; each arm's base against each arm is `data/army_matchups.csv`, floating monthly by a hash of (regiment, arm, tick) — never the engine's RNG stream. The card shows terrain, morale, "N (W wounded)", "+R / mo", "S (−U / mo)", and only WORDS for training (`data/army_training_grades.csv`) and strength (Strong / Average / Weak against the mean of the player's regiments of the same kind). `ArmySystem.battle_odds` is a PLACEHOLDER wired into nothing. Counters scale with the zoom (`map_army_badge_native_px`, floored at `map_army_badge_min_px`) and are never thinned. The WAR ROOM tab is a placeholder page.
```

- [ ] **Step 6: Full suite.** Run `./run_tests.sh` and compare its failing tests with the baseline file named in Global Constraints. Every failure not in the baseline must be fixed (or, if it belongs to a file this plan did not touch, reported with its output).

- [ ] **Step 7: Do not commit.**
