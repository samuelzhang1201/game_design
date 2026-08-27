# Slice 1 — Walking Skeleton + Council Step 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A playable year-1 build of Crown and Council: tick engine, five founding ministers briefing every tick, clickable suggestions + free-text orders, JSON save/load, deterministic, pixel-art council screen, fully playable offline.

**Architecture:** Four layers with one-way dependencies (`ui → llm → engine → data`). Engine is pure `RefCounted` GDScript emitting deterministic `TickReport`s; LLM layer voices them and parses free text behind strict validation; all design numbers live in CSVs loaded by a fail-loud `DataRepository`.

**Tech Stack:** Godot 4.7.1 (binary at `/Applications/Godot.app/Contents/MacOS/Godot`), GDScript (typed), GUT 9.x for tests, OpenAI HTTP API via `HTTPRequest` (live calls only in the final tasks; tests never call the network).

**Spec:** `docs/superpowers/specs/2026-08-28-slice1-skeleton-council-design.md`

## Global Constraints

- Engine scripts (`scripts/engine/*`) are `RefCounted`, import no Node/scene types, never read the clock, and take all randomness from the injected `Rng`.
- Every design number lives in `data/*.csv` — never a literal in a script. Access via `DataRepository`.
- Every opinion or metric change records a reason string at creation time.
- `DataRepository` load failures abort with file + row number (fail-loud), never a silent default.
- No test may perform a network call. `OpenAIClient` is faked at the `Voicer`/parse boundary.
- All test runs headless: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit`
- Commit after every green test cycle. Message prefix `feat:`/`test:`/`chore:`; end commit messages with the session trailer used in this repo's history.
- Base viewport 640×360, integer scaling, nearest-neighbor filtering (set once in Task 1, never overridden per-node).

## File Structure

```
project.godot                      # Task 1 — pixel render settings, autoload
addons/gut/                        # Task 1 — GUT (vendored)
data/
  balance.csv                      # Task 3 — all tunable constants
  policy_actions_domain.csv        # Task 6 — 8 domain actions
  founding_council.csv             # Task 5 — the five ministers
  templates.csv                    # Task 10 — template voice lines
  (existing: character_traits.csv, council_seats.csv,
   faction_escalation.csv, policy_actions_court_additions.csv)
scripts/engine/
  rng.gd                           # Task 2
  data_repository.gd               # Task 3
  game_state.gd  character.gd      # Task 4, 5
  character_factory.gd             # Task 5
  action_request.gd                # Task 6
  action_system.gd                 # Task 6
  concern_scanner.gd               # Task 7
  suggestion_generator.gd          # Task 7
  tick_engine.gd  tick_report.gd   # Task 8
  save_load.gd                     # Task 9
scripts/llm/
  template_voicer.gd               # Task 10
  response_validator.gd            # Task 12
  openai_client.gd prompt_builder.gd voicer.gd   # Task 13
scripts/ui/
  game.gd                          # Task 11 — autoload wiring
  council_screen.gd                # Task 11
scenes/council.tscn                # Task 11
tests/engine/  tests/llm/          # mirror structure
```

---

### Task 1: Godot project scaffold + GUT

**Files:**
- Create: `project.godot`, `icon.svg` (Godot default ok), `addons/gut/` (vendored), `tests/engine/test_smoke.gd`
- Modify: `.gitignore`

**Interfaces:**
- Produces: a bootable Godot 4.7 project; `run_tests.sh` at repo root that later tasks call verbatim.

- [ ] **Step 1: Verify the Godot project file's pixel settings**

`project.godot` already exists at the repo root (created 2026-08-28 when the project was flattened; it also carries the `gdai-mcp-plugin-godot` autoload + editor plugin, GL Compatibility renderer, and `data/*.csv.import` files with `importer="keep"` so Godot never re-imports the design CSVs as translations — leave all of that in place). Verify it contains the settings below and add any that are missing; do not remove the existing sections:

```ini
; Engine configuration file.
config_version=5

[application]
config/name="Crown and Council"
config/features=PackedStringArray("4.7")
run/main_scene=""

[display]
window/size/viewport_width=640
window/size/viewport_height=360
window/size/window_width_override=1280
window/size/window_height_override=720
window/stretch/mode="canvas_items"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"

[rendering]
textures/canvas_textures/default_texture_filter=0
```

(`default_texture_filter=0` = nearest. `run/main_scene` stays empty until Task 11.)

- [ ] **Step 2: Vendor GUT**

```bash
git clone --depth 1 --branch v9.4.0 https://github.com/bitwes/Gut.git /tmp/gut-checkout \
  && mkdir -p addons && cp -R /tmp/gut-checkout/addons/gut addons/gut
```

If tag `v9.4.0` is missing, use the newest `v9.x` tag (GUT 9 targets Godot 4). Then add to `project.godot`:

```ini
[editor_plugins]
enabled=PackedStringArray("res://addons/gut/plugin.cfg")
```

- [ ] **Step 3: Add `run_tests.sh` and a smoke test**

`run_tests.sh` (repo root, `chmod +x`):

```bash
#!/bin/sh
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . \
  -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

`tests/engine/test_smoke.gd`:

```gdscript
extends GutTest

func test_project_boots() -> void:
	assert_true(true)
```

- [ ] **Step 4: Import assets headless once, then run tests**

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
./run_tests.sh
```

Expected: `1 passed`. (The `--import` pass generates `.godot/`; needed after vendoring GUT.)

- [ ] **Step 5: Update .gitignore and commit**

`.gitignore` should contain exactly:

```
.godot/
.DS_Store
```

(Remove the earlier `user://` and `*.import` lines — `user://` is not a repo path and Godot 4.7 has no sidecar `.import` files.)

```bash
git add -A && git commit -m "chore: Godot 4.7 scaffold, pixel render settings, GUT vendored"
```

---

### Task 2: Seeded Rng

**Files:**
- Create: `scripts/engine/rng.gd`
- Test: `tests/engine/test_rng.gd`

**Interfaces:**
- Produces: `class_name Rng` — `Rng.new(seed_value: int)`, `randi_range(from: int, to: int) -> int`, `randf() -> float`, `chance(p: float) -> bool`, `pick_weighted(weights: Array) -> int`, `to_dict() -> Dictionary`, `static from_dict(d: Dictionary) -> Rng`.

- [ ] **Step 1: Write failing tests**

`tests/engine/test_rng.gd`:

```gdscript
extends GutTest

func test_same_seed_same_sequence() -> void:
	var a := Rng.new(42)
	var b := Rng.new(42)
	for i in 20:
		assert_eq(a.randi_range(0, 1000), b.randi_range(0, 1000))

func test_round_trip_preserves_stream() -> void:
	var a := Rng.new(7)
	a.randf(); a.randf()
	var b := Rng.from_dict(a.to_dict())
	for i in 10:
		assert_eq(a.randi_range(0, 99), b.randi_range(0, 99))

func test_pick_weighted_is_deterministic_and_in_range() -> void:
	var a := Rng.new(3)
	var b := Rng.new(3)
	for i in 50:
		var ia: int = a.pick_weighted([1.0, 5.0, 2.0])
		assert_eq(ia, b.pick_weighted([1.0, 5.0, 2.0]))
		assert_between(ia, 0, 2)
```

- [ ] **Step 2: Run to verify failure**

Run: `./run_tests.sh` — Expected: FAIL (`Rng` not found).

- [ ] **Step 3: Implement**

`scripts/engine/rng.gd`:

```gdscript
class_name Rng
extends RefCounted

var _rng := RandomNumberGenerator.new()

func _init(seed_value: int = 0) -> void:
	_rng.seed = seed_value

func randi_range(from: int, to: int) -> int:
	return _rng.randi_range(from, to)

func randf() -> float:
	return _rng.randf()

func chance(p: float) -> bool:
	return _rng.randf() < p

func pick_weighted(weights: Array) -> int:
	var total := 0.0
	for w in weights:
		total += w
	var roll := _rng.randf() * total
	var acc := 0.0
	for i in weights.size():
		acc += weights[i]
		if roll < acc:
			return i
	return weights.size() - 1

func to_dict() -> Dictionary:
	return {"seed": _rng.seed, "state": _rng.state}

static func from_dict(d: Dictionary) -> Rng:
	var r := Rng.new(int(d["seed"]))
	r._rng.state = int(d["state"])
	return r
```

- [ ] **Step 4: Run tests** — Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: seeded serializable Rng"`

---

### Task 3: DataRepository + balance.csv

**Files:**
- Create: `scripts/engine/data_repository.gd`, `data/balance.csv`, `tests/engine/test_data_repository.gd`, `tests/fixtures/bad_balance.csv`

**Interfaces:**
- Produces: `class_name DataRepository` — `static load_all(dir: String) -> DataRepository` (returns `null` on failure and sets `static var last_error: String`, which contains file name and 1-based row number). Instance fields: `balance: Dictionary` (String→float), `traits: Dictionary` (trait_code→row Dictionary), `seats: Dictionary` (seat_code→row), `actions: Dictionary` (action_code→row, court + domain merged), `founding: Array[Dictionary]`, `templates: Array[Dictionary]`. Helper `bal(key: String) -> float` that fail-louds on missing key. Files that don't exist yet (`founding_council.csv`, `templates.csv`, `policy_actions_domain.csv`) load as empty when absent — later tasks add them.

- [ ] **Step 1: Create `data/balance.csv`**

```csv
key,value,notes
start_treasury,500,gold at campaign start
start_grain,120,
start_tax_rate,5,scale 1-10
start_tariff_rate,3,scale 0-10
start_metric_default,50,legitimacy/unrest-style baselines start here
court_upkeep,18,gold per tick
tax_income_factor,0.8,income = tax_rate * admin_capacity * factor
tariff_income_factor,3.0,income += tariff_rate * factor
admin_base,5.0,before chancellor bonus
chancellor_vacancy_penalty,3.0,
harvest_gain,30,grain per autumn tick
grain_drain,4,per non-winter tick
grain_drain_winter,6,
unrest_tax_pressure,0.3,per point of tax_rate above 5
unrest_decay,0.2,toward 0
unrest_famine,2.0,per tick while grain <= 0
contentment_drift,0.2,toward 50
legitimacy_drift,0.1,toward 50
church_drift,0.2,toward 50
army_decay,0.3,per tick
army_floor,20,
concern_treasury_low,100,steward fires below this
concern_grain_low,30,steward
concern_unrest_high,40,chancellor
concern_church_low,35,chaplain
concern_army_low,50,marshal
concern_legitimacy_low,40,spymaster (rumors)
event_base_chance,0.35,reserved for events slice
tone_delta_cap,3,
reward_gold_cost,30,
reward_opinion,8,
reward_opinion_vain_bonus,4,
punish_opinion,-10,
confide_opinion,4,
levy_cost,40,
levy_army_gain,8,
levy_unrest,2,
church_endow_cost,30,
church_endow_gain,8,
church_tithe_gain,25,
church_tithe_opinion,-6,
spy_cost,15,
spy_legitimacy_gain,1,
build_cost,60,
justice_unrest_per_point,-2.0,
justice_contentment_per_point,-2.0,
grain_release_amount,20,
grain_release_contentment,5,
grain_ration_contentment,-3,
```

- [ ] **Step 2: Write failing tests**

`tests/fixtures/bad_balance.csv`:

```csv
key,value,notes
good_key,1.0,
broken_row_missing_value
```

`tests/engine/test_data_repository.gd`:

```gdscript
extends GutTest

func test_loads_real_data_dir() -> void:
	var repo := DataRepository.load_all("res://data")
	assert_not_null(repo)
	assert_eq(repo.bal("start_treasury"), 500.0)
	assert_true(repo.traits.has("venal"))
	assert_true(repo.seats.has("chancellor"))
	assert_true(repo.actions.has("COUNCIL_CONSULT"))

func test_malformed_row_fails_loud_with_location() -> void:
	var repo := DataRepository.load_all("res://tests/fixtures")
	assert_null(repo)
	assert_string_contains(DataRepository.last_error, "bad_balance.csv")
	assert_string_contains(DataRepository.last_error, "row 3")
```

Note: the fixtures dir doubles as a "data dir" whose balance file is `bad_balance.csv` — see Step 3's convention: `load_all` reads every `*.csv` whose name matches a known logical table (`balance` in `bad_balance.csv` via suffix match is NOT wanted; instead `load_all` takes the directory and looks for exact filenames, and the fixture test calls the lower-level static `DataRepository.parse_csv("res://tests/fixtures/bad_balance.csv", ["key","value"])` instead). Adjust the second test to:

```gdscript
func test_malformed_row_fails_loud_with_location() -> void:
	var rows := DataRepository.parse_csv("res://tests/fixtures/bad_balance.csv", ["key", "value"])
	assert_eq(rows, [])
	assert_string_contains(DataRepository.last_error, "bad_balance.csv")
	assert_string_contains(DataRepository.last_error, "row 3")
```

- [ ] **Step 3: Implement**

`scripts/engine/data_repository.gd`:

```gdscript
class_name DataRepository
extends RefCounted

static var last_error: String = ""

var balance: Dictionary = {}
var traits: Dictionary = {}
var seats: Dictionary = {}
var actions: Dictionary = {}
var founding: Array[Dictionary] = []
var templates: Array[Dictionary] = []

## Parses a CSV with a header row into an Array of row Dictionaries.
## Returns [] and sets last_error if any row is shorter than required_cols
## or a file error occurs. Extra columns are kept; empty trailing lines skipped.
static func parse_csv(path: String, required_cols: Array) -> Array[Dictionary]:
	last_error = ""
	var out: Array[Dictionary] = []
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		last_error = "cannot open %s" % path
		return []
	var header := f.get_csv_line()
	var row_num := 1
	while not f.eof_reached():
		var line := f.get_csv_line()
		row_num += 1
		if line.size() == 1 and line[0].strip_edges() == "":
			continue
		if line.size() < required_cols.size():
			last_error = "%s row %d: expected at least %d columns, got %d" % [
				path.get_file(), row_num, required_cols.size(), line.size()]
			return []
		var row := {}
		for i in header.size():
			row[header[i]] = line[i] if i < line.size() else ""
		out.append(row)
	return out

static func load_all(dir: String) -> DataRepository:
	var repo := DataRepository.new()
	if not repo._load(dir):
		return null
	return repo

func _load(dir: String) -> bool:
	var bal_rows := DataRepository.parse_csv(dir + "/balance.csv", ["key", "value"])
	if bal_rows.is_empty():
		return false
	for r in bal_rows:
		balance[r["key"]] = float(r["value"])
	var trait_rows := DataRepository.parse_csv(dir + "/character_traits.csv", ["trait_code"])
	if trait_rows.is_empty():
		return false
	for r in trait_rows:
		traits[r["trait_code"]] = r
	var seat_rows := DataRepository.parse_csv(dir + "/council_seats.csv", ["seat_code"])
	if seat_rows.is_empty():
		return false
	for r in seat_rows:
		seats[r["seat_code"]] = r
	var court_rows := DataRepository.parse_csv(dir + "/policy_actions_court_additions.csv", ["action_code"])
	if court_rows.is_empty():
		return false
	for r in court_rows:
		actions[r["action_code"]] = r
	_load_optional(dir + "/policy_actions_domain.csv", func(r): actions[r["action_code"]] = r)
	_load_optional(dir + "/founding_council.csv", func(r): founding.append(r))
	_load_optional(dir + "/templates.csv", func(r): templates.append(r))
	return true

func _load_optional(path: String, sink: Callable) -> void:
	if not FileAccess.file_exists(path):
		return
	for r in DataRepository.parse_csv(path, []):
		sink.call(r)

func bal(key: String) -> float:
	assert(balance.has(key), "balance.csv missing key: " + key)
	return balance[key]
```

- [ ] **Step 4: Run tests** — Expected: PASS (both).

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: fail-loud DataRepository + balance table"`

---

### Task 4: GameState

**Files:**
- Create: `scripts/engine/game_state.gd`
- Test: `tests/engine/test_game_state.gd`

**Interfaces:**
- Consumes: `Rng` (Task 2), `DataRepository` (Task 3).
- Produces: `class_name GameState` — `static new_campaign(data: DataRepository, seed_value: int) -> GameState`; fields `tick: int`, `rng: Rng`, `metrics: Dictionary` (String→float; keys: `treasury, tax_rate, tariff_rate, tax_income, admin_capacity, legitimacy, unrest, grain, army_quality, church_opinion, peasant_contentment, grain_capacity_bonus, road_income_bonus, grain_ration`), `characters: Dictionary` (id→Character, filled in Task 5), `council: Dictionary` (seat_code→character id), `cooldowns: Dictionary` (action_code→tick usable again), `recent_outcomes: Array`, `promises: Array`; methods `season() -> String` (`spring|summer|autumn|winter` from `tick % 24` in blocks of 6), `year() -> int` (1-based), `to_dict() -> Dictionary`, `static from_dict(d: Dictionary) -> GameState` (round-trip lossless; `characters` round-trip added in Task 5).

- [ ] **Step 1: Write failing tests**

`tests/engine/test_game_state.gd`:

```gdscript
extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_new_campaign_reads_balance() -> void:
	var s := GameState.new_campaign(data, 42)
	assert_eq(s.tick, 0)
	assert_eq(s.metrics["treasury"], 500.0)
	assert_eq(s.metrics["grain"], 120.0)
	assert_eq(s.metrics["tax_rate"], 5.0)
	assert_eq(s.metrics["legitimacy"], 50.0)

func test_seasons_and_years() -> void:
	var s := GameState.new_campaign(data, 1)
	assert_eq(s.season(), "spring")
	s.tick = 13
	assert_eq(s.season(), "autumn")
	s.tick = 23
	assert_eq(s.season(), "winter")
	s.tick = 24
	assert_eq(s.season(), "spring")
	assert_eq(s.year(), 2)

func test_round_trip() -> void:
	var s := GameState.new_campaign(data, 42)
	s.tick = 9
	s.metrics["treasury"] = 123.5
	s.cooldowns["LEVY_RAISE"] = 12
	var s2 := GameState.from_dict(s.to_dict())
	assert_eq(s2.tick, 9)
	assert_eq(s2.metrics["treasury"], 123.5)
	assert_eq(s2.cooldowns["LEVY_RAISE"], 12)
	assert_eq(s2.rng.randi_range(0, 9999), s.rng.randi_range(0, 9999))
```

- [ ] **Step 2: Run** — Expected: FAIL (`GameState` not found).

- [ ] **Step 3: Implement**

`scripts/engine/game_state.gd`:

```gdscript
class_name GameState
extends RefCounted

var tick: int = 0
var rng: Rng
var metrics: Dictionary = {}
var characters: Dictionary = {}
var council: Dictionary = {}
var cooldowns: Dictionary = {}
var recent_outcomes: Array = []
var promises: Array = []

const SEASONS := ["spring", "summer", "autumn", "winter"]

static func new_campaign(data: DataRepository, seed_value: int) -> GameState:
	var s := GameState.new()
	s.rng = Rng.new(seed_value)
	s.metrics = {
		"treasury": data.bal("start_treasury"),
		"tax_rate": data.bal("start_tax_rate"),
		"tariff_rate": data.bal("start_tariff_rate"),
		"tax_income": 0.0,
		"admin_capacity": data.bal("admin_base"),
		"legitimacy": data.bal("start_metric_default"),
		"unrest": 0.0,
		"grain": data.bal("start_grain"),
		"army_quality": data.bal("start_metric_default"),
		"church_opinion": data.bal("start_metric_default"),
		"peasant_contentment": data.bal("start_metric_default"),
		"grain_capacity_bonus": 0.0,
		"road_income_bonus": 0.0,
		"grain_ration": 0.0,
	}
	return s

func season() -> String:
	return SEASONS[(tick % 24) / 6]

func year() -> int:
	return tick / 24 + 1

func to_dict() -> Dictionary:
	var chars := {}
	for id in characters:
		chars[id] = characters[id].to_dict()
	return {
		"tick": tick, "rng": rng.to_dict(), "metrics": metrics.duplicate(),
		"characters": chars, "council": council.duplicate(),
		"cooldowns": cooldowns.duplicate(), "recent_outcomes": recent_outcomes.duplicate(true),
		"promises": promises.duplicate(true),
	}

static func from_dict(d: Dictionary) -> GameState:
	var s := GameState.new()
	s.tick = int(d["tick"])
	s.rng = Rng.from_dict(d["rng"])
	s.metrics = d["metrics"].duplicate()
	for id in d["characters"]:
		s.characters[id] = Character.from_dict(d["characters"][id])
	s.council = d["council"].duplicate()
	for k in d["cooldowns"]:
		s.cooldowns[k] = int(d["cooldowns"][k])
	s.recent_outcomes = d["recent_outcomes"].duplicate(true)
	s.promises = d["promises"].duplicate(true)
	return s
```

Note: `Character` doesn't exist until Task 5. For this task only, create it as a stub so the project parses — `scripts/engine/character.gd`:

```gdscript
class_name Character
extends RefCounted

func to_dict() -> Dictionary:
	return {}

static func from_dict(_d: Dictionary) -> Character:
	return Character.new()
```

- [ ] **Step 4: Run** — Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: GameState with metrics, seasons, lossless round-trip"`

---

### Task 5: Character, CharacterFactory, founding council data

**Files:**
- Create: `data/founding_council.csv`, `scripts/engine/character_factory.gd`
- Modify: `scripts/engine/character.gd` (replace stub)
- Test: `tests/engine/test_character_factory.gd`

**Interfaces:**
- Consumes: `DataRepository.traits`, `DataRepository.founding`, `GameState`.
- Produces: `Character` fields `id: String`, `display_name: String`, `seat: String`, `attributes: Dictionary` (ambition, loyalty, integrity, boldness, piety, compassion, vanity, temper, pragmatism — 0–100), `skills: Dictionary` (sk_admin, sk_martial, sk_intrigue, sk_diplomacy, sk_steward — 0–20), `ideology: Dictionary` (centralism, militarism, orthodoxy, tax_incidence, expansionism — −100…100; plus `policy_sensitivity`), `traits: Array`, `opinion: int` (−100…100), `opinion_log: Array` of `{tick: int, delta: int, reason: String}`; method `change_opinion(delta: int, reason: String, tick: int) -> void` (clamps to ±100, appends log); full `to_dict()/from_dict()`. `CharacterFactory.build_founding(data: DataRepository) -> Dictionary` returns id→Character and is what `GameState.new_campaign` calls (wire it in this task); also fills `state.council`.

- [ ] **Step 1: Create `data/founding_council.csv`**

Columns: base values BEFORE trait modifiers; traits pipe-separated.

```csv
id,display_name,seat,ambition,loyalty,integrity,boldness,piety,compassion,vanity,temper,pragmatism,sk_admin,sk_martial,sk_intrigue,sk_diplomacy,sk_steward,centralism,militarism,orthodoxy,tax_incidence,expansionism,policy_sensitivity,traits,opinion
char_chancellor,Aldwin Reeve,chancellor,30,70,60,35,40,55,25,30,60,12,2,5,8,8,40,-10,10,20,-20,60,lowborn|gifted_admin|honest|patient,20
char_marshal,Ser Brandt of Harrow,marshal,55,55,45,70,35,30,50,65,35,4,13,3,5,3,-20,70,10,-30,50,70,noble_born|born_soldier|bold|wrathful,10
char_steward,Mirella of the Weighhouse,steward,45,50,45,40,25,40,35,45,75,8,2,6,7,12,10,-60,-20,10,-40,55,merchant_family|shrewd_trader|blunt|cynical,10
char_spymaster,Quill,spymaster,50,55,40,30,30,30,20,45,55,6,3,13,7,4,50,10,-30,0,0,50,lowborn|schemer|paranoid,15
char_chaplain,Father Odo,chaplain,25,65,70,25,80,70,20,40,30,9,1,3,10,5,10,-30,70,20,-20,80,clergy_trained|pious|compassionate,15
```

- [ ] **Step 2: Write failing tests**

`tests/engine/test_character_factory.gd`:

```gdscript
extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_builds_five_ministers_seated() -> void:
	var s := GameState.new_campaign(data, 42)
	assert_eq(s.characters.size(), 5)
	for seat in ["chancellor", "marshal", "steward", "spymaster", "chaplain"]:
		assert_true(s.council.has(seat), seat + " seated")

func test_trait_modifiers_applied() -> void:
	var s := GameState.new_campaign(data, 42)
	var brandt: Character = s.characters[s.council["marshal"]]
	# base temper 65 + wrathful +35 + bold +10 + noble_born +5 + born_soldier +5 = 120 -> clamp 100
	assert_eq(brandt.attributes["temper"], 100)
	# base sk_martial 13 + born_soldier +5 + bold +2 + veteran(no) = 20 cap
	assert_eq(brandt.skills["sk_martial"], 20)

func test_opinion_change_logs_reason_and_clamps() -> void:
	var c := Character.new()
	c.opinion = 95
	c.change_opinion(10, "test reason", 3)
	assert_eq(c.opinion, 100)
	assert_eq(c.opinion_log.size(), 1)
	assert_eq(c.opinion_log[0]["reason"], "test reason")

func test_character_round_trip() -> void:
	var s := GameState.new_campaign(data, 42)
	var c: Character = s.characters[s.council["chaplain"]]
	c.change_opinion(-5, "rt", 1)
	var c2 := Character.from_dict(c.to_dict())
	assert_eq(c2.display_name, "Father Odo")
	assert_eq(c2.opinion, c.opinion)
	assert_eq(c2.opinion_log[0]["reason"], "rt")
	assert_eq(c2.ideology["orthodoxy"], c.ideology["orthodoxy"])
```

Verify the Brandt arithmetic against `data/character_traits.csv` columns (`temper`, `sk_martial` etc.) before running; if the CSV's modifier values differ from the comment, recompute the expected numbers from the CSV — the CSV is the source of truth.

- [ ] **Step 3: Run** — Expected: FAIL.

- [ ] **Step 4: Implement**

Replace `scripts/engine/character.gd`:

```gdscript
class_name Character
extends RefCounted

var id: String = ""
var display_name: String = ""
var seat: String = ""
var attributes: Dictionary = {}
var skills: Dictionary = {}
var ideology: Dictionary = {}
var traits: Array = []
var opinion: int = 0
var opinion_log: Array = []

func change_opinion(delta: int, reason: String, tick: int) -> void:
	opinion = clampi(opinion + delta, -100, 100)
	opinion_log.append({"tick": tick, "delta": delta, "reason": reason})

func to_dict() -> Dictionary:
	return {
		"id": id, "display_name": display_name, "seat": seat,
		"attributes": attributes.duplicate(), "skills": skills.duplicate(),
		"ideology": ideology.duplicate(), "traits": traits.duplicate(),
		"opinion": opinion, "opinion_log": opinion_log.duplicate(true),
	}

static func from_dict(d: Dictionary) -> Character:
	var c := Character.new()
	c.id = d["id"]; c.display_name = d["display_name"]; c.seat = d["seat"]
	c.attributes = d["attributes"].duplicate(); c.skills = d["skills"].duplicate()
	c.ideology = d["ideology"].duplicate(); c.traits = d["traits"].duplicate()
	c.opinion = int(d["opinion"]); c.opinion_log = d["opinion_log"].duplicate(true)
	return c
```

`scripts/engine/character_factory.gd`:

```gdscript
class_name CharacterFactory
extends RefCounted

const ATTRS := ["ambition","loyalty","integrity","boldness","piety","compassion","vanity","temper"]
const SKILLS := ["sk_admin","sk_martial","sk_intrigue","sk_diplomacy","sk_steward"]
const AXES := ["centralism","militarism","orthodoxy","tax_incidence","expansionism"]

static func build_founding(data: DataRepository) -> Dictionary:
	var out := {}
	for row in data.founding:
		out[row["id"]] = build(row, data)
	return out

static func build(row: Dictionary, data: DataRepository) -> Character:
	var c := Character.new()
	c.id = row["id"]; c.display_name = row["display_name"]; c.seat = row["seat"]
	for a in ATTRS:
		c.attributes[a] = int(row[a])
	c.attributes["pragmatism"] = int(row["pragmatism"])
	for sk in SKILLS:
		c.skills[sk] = int(row[sk])
	for ax in AXES:
		c.ideology[ax] = int(row[ax])
	c.ideology["policy_sensitivity"] = int(row["policy_sensitivity"])
	c.opinion = int(row["opinion"])
	c.traits = row["traits"].split("|")
	for t in c.traits:
		assert(data.traits.has(t), "unknown trait: " + t)
		var tr: Dictionary = data.traits[t]
		for a in ATTRS:
			c.attributes[a] = clampi(c.attributes[a] + int(tr[a]), 0, 100)
		for sk in SKILLS:
			c.skills[sk] = clampi(c.skills[sk] + int(tr[sk]), 0, 20)
	return c
```

Wire into `GameState.new_campaign` (add before `return s`):

```gdscript
	s.characters = CharacterFactory.build_founding(data)
	for id in s.characters:
		s.council[s.characters[id].seat] = id
```

- [ ] **Step 5: Run** — Expected: PASS (fix expected numbers from the traits CSV if the arithmetic comment was off).

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: characters, trait application, founding council"`

---

### Task 6: ActionRequest + ActionSystem + domain actions data

**Files:**
- Create: `data/policy_actions_domain.csv`, `scripts/engine/action_request.gd`, `scripts/engine/action_system.gd`
- Test: `tests/engine/test_action_system.gd`

**Interfaces:**
- Consumes: `GameState`, `DataRepository`, `Character.change_opinion`.
- Produces: `class_name ActionRequest` — fields `action_code: String`, `params: Dictionary`, `target: String`; `static make(code: String, params: Dictionary = {}, target: String = "") -> ActionRequest`; `to_dict()/from_dict()`. `class_name ActionSystem` — `_init(data: DataRepository)`, `validate(req: ActionRequest, state: GameState) -> String` (empty string = valid, else human-readable reason), `execute(req: ActionRequest, state: GameState) -> Dictionary` outcome record `{action_code: String, ok: bool, effects: Array of {metric: String, delta: float, reason: String}, notes: String}`. Execute asserts validate passed, applies effects, sets cooldown (`cooldown_ticks` column), appends the outcome to `state.recent_outcomes`.

- [ ] **Step 1: Create `data/policy_actions_domain.csv`** (same schema as the court CSV)

```csv
action_code,domain,label,target_type,admin_cost,gold_cost_formula,cooldown_ticks,min_era,unlock_req,effect_handler,max_per_turn,reversible,notes
TAX_RATE_ADJUST,economy,Adjust the tax rate,none,1.0,none,2,0,,tax_rate_adjust,1,yes,"params: delta (int -3..3). New rate clamped 1-10."
TARIFF_ADJUST,economy,Adjust tariffs,none,1.0,none,2,0,,tariff_adjust,1,yes,"params: delta (int -3..3). New rate clamped 0-10."
LEVY_RAISE,military,Raise fresh levies,none,1.5,levy_cost,4,0,,levy_raise,1,no,"Improves army quality; costs gold and goodwill."
GRAIN_POLICY_SET,economy,Set grain policy,none,1.0,none,2,0,,grain_policy_set,1,yes,"params: mode (market|ration|release)."
CHURCH_POLICY,religion,Set church policy,none,1.0,none,4,0,,church_policy,1,yes,"params: mode (endow|tithe)."
JUSTICE_SEVERITY,justice,Adjust severity of justice,none,1.0,none,4,0,,justice_severity,1,yes,"params: delta (int -2..2)."
BUILD_ECONOMIC,economy,Commission a public work,none,1.5,build_cost,6,0,,build_economic,1,no,"params: project (granary|road)."
SPY_MISSION,intrigue,Send out the whisperers,none,1.0,spy_cost,4,0,,spy_mission,1,no,"Quiets rumors; costs gold."
```

- [ ] **Step 2: Write failing tests**

`tests/engine/test_action_system.gd`:

```gdscript
extends GutTest

var data: DataRepository
var sys: ActionSystem
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	sys = ActionSystem.new(data)
	s = GameState.new_campaign(data, 42)

func test_unknown_action_rejected() -> void:
	assert_string_contains(sys.validate(ActionRequest.make("FLY_TO_MOON"), s), "Unknown")

func test_unaffordable_rejected() -> void:
	s.metrics["treasury"] = 5.0
	assert_string_contains(sys.validate(ActionRequest.make("LEVY_RAISE"), s), "afford")

func test_cooldown_enforced() -> void:
	var req := ActionRequest.make("TAX_RATE_ADJUST", {"delta": 1})
	assert_eq(sys.validate(req, s), "")
	sys.execute(req, s)
	assert_string_contains(sys.validate(req, s), "cooldown")

func test_tax_adjust_moves_rate_with_reason() -> void:
	var out := sys.execute(ActionRequest.make("TAX_RATE_ADJUST", {"delta": 2}), s)
	assert_true(out["ok"])
	assert_eq(s.metrics["tax_rate"], 7.0)
	var found := false
	for e in out["effects"]:
		if e["metric"] == "tax_rate":
			found = true
			assert_string_contains(e["reason"], "tax")
	assert_true(found)

func test_reward_changes_opinion_with_reason() -> void:
	var target: String = s.council["marshal"]
	var gold_before: float = s.metrics["treasury"]
	sys.execute(ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, target), s)
	var c: Character = s.characters[target]
	assert_gt(c.opinion, 10)
	assert_string_contains(c.opinion_log[-1]["reason"], "reward")
	assert_lt(s.metrics["treasury"], gold_before)

func test_bad_params_rejected() -> void:
	assert_string_contains(sys.validate(ActionRequest.make("TAX_RATE_ADJUST", {"delta": 9}), s), "delta")
	assert_string_contains(sys.validate(ActionRequest.make("GRAIN_POLICY_SET", {"mode": "feast"}), s), "mode")
	assert_string_contains(
		sys.validate(ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, "char_nobody"), s), "target")
```

- [ ] **Step 3: Run** — Expected: FAIL.

- [ ] **Step 4: Implement**

`scripts/engine/action_request.gd`:

```gdscript
class_name ActionRequest
extends RefCounted

var action_code: String = ""
var params: Dictionary = {}
var target: String = ""

static func make(code: String, p: Dictionary = {}, t: String = "") -> ActionRequest:
	var r := ActionRequest.new()
	r.action_code = code; r.params = p; r.target = t
	return r

func to_dict() -> Dictionary:
	return {"action_code": action_code, "params": params.duplicate(), "target": target}

static func from_dict(d: Dictionary) -> ActionRequest:
	return make(d.get("action_code", ""), d.get("params", {}), d.get("target", ""))
```

`scripts/engine/action_system.gd` (full file):

```gdscript
class_name ActionSystem
extends RefCounted

var data: DataRepository

## gold cost formula name -> balance key (formulas beyond flat keys come later)
const COST_KEYS := {
	"levy_cost": "levy_cost", "build_cost": "build_cost", "spy_cost": "spy_cost",
	"formula_reward_cost": "reward_gold_cost",
}

func _init(d: DataRepository) -> void:
	data = d

func gold_cost(row: Dictionary) -> float:
	var formula: String = row.get("gold_cost_formula", "none")
	if formula == "none" or formula == "":
		return 0.0
	if COST_KEYS.has(formula):
		return data.bal(COST_KEYS[formula])
	return 0.0  # unknown formulas are free in slice 1; slice 2 adds real formulas

func validate(req: ActionRequest, state: GameState) -> String:
	if not data.actions.has(req.action_code):
		return "Unknown action: " + req.action_code
	var row: Dictionary = data.actions[req.action_code]
	if state.cooldowns.get(req.action_code, 0) > state.tick:
		return "%s is on cooldown until tick %d" % [req.action_code, state.cooldowns[req.action_code]]
	if state.metrics["treasury"] < gold_cost(row):
		return "Cannot afford %s (needs %d gold)" % [req.action_code, int(gold_cost(row))]
	if row.get("target_type", "none") == "character" and not state.characters.has(req.target):
		return "No such target character for " + req.action_code
	match req.action_code:
		"TAX_RATE_ADJUST", "TARIFF_ADJUST":
			var d := int(req.params.get("delta", 0))
			if d < -3 or d > 3 or d == 0:
				return "delta must be -3..3 and nonzero"
		"JUSTICE_SEVERITY":
			var d := int(req.params.get("delta", 0))
			if d < -2 or d > 2 or d == 0:
				return "delta must be -2..2 and nonzero"
		"GRAIN_POLICY_SET":
			if not req.params.get("mode", "") in ["market", "ration", "release"]:
				return "mode must be market|ration|release"
		"CHURCH_POLICY":
			if not req.params.get("mode", "") in ["endow", "tithe"]:
				return "mode must be endow|tithe"
		"BUILD_ECONOMIC":
			if not req.params.get("project", "") in ["granary", "road"]:
				return "project must be granary|road"
		"CHARACTER_REWARD":
			if not req.params.get("mode", "gold") in ["gold"]:
				return "mode must be gold (slice 1)"
	return ""

func execute(req: ActionRequest, state: GameState) -> Dictionary:
	var err := validate(req, state)
	assert(err == "", "execute called with invalid request: " + err)
	var row: Dictionary = data.actions[req.action_code]
	var effects: Array = []
	var cost := gold_cost(row)
	if cost > 0.0:
		_apply(state, effects, "treasury", -cost, "paid for " + String(row["label"]))
	match req.action_code:
		"TAX_RATE_ADJUST":
			var d := int(req.params["delta"])
			var new_rate := clampf(state.metrics["tax_rate"] + d, 1.0, 10.0)
			_set(state, effects, "tax_rate", new_rate, "adjusted the tax rate")
		"TARIFF_ADJUST":
			var d := int(req.params["delta"])
			var new_rate := clampf(state.metrics["tariff_rate"] + d, 0.0, 10.0)
			_set(state, effects, "tariff_rate", new_rate, "adjusted tariffs")
		"LEVY_RAISE":
			_apply(state, effects, "army_quality", data.bal("levy_army_gain"), "fresh levies drilled")
			_apply(state, effects, "unrest", data.bal("levy_unrest"), "villages resent the levy")
		"GRAIN_POLICY_SET":
			var mode: String = req.params["mode"]
			_set(state, effects, "grain_ration", 1.0 if mode == "ration" else 0.0, "grain policy: " + mode)
			if mode == "ration":
				_apply(state, effects, "peasant_contentment", data.bal("grain_ration_contentment"), "rationing bites")
			elif mode == "release":
				_apply(state, effects, "grain", -data.bal("grain_release_amount"), "stores opened")
				_apply(state, effects, "peasant_contentment", data.bal("grain_release_contentment"), "grain released to the people")
		"CHURCH_POLICY":
			if req.params["mode"] == "endow":
				_apply(state, effects, "treasury", -data.bal("church_endow_cost"), "endowed the church")
				_apply(state, effects, "church_opinion", data.bal("church_endow_gain"), "the church blessed the endowment")
			else:
				_apply(state, effects, "treasury", data.bal("church_tithe_gain"), "tithed the church")
				_apply(state, effects, "church_opinion", data.bal("church_tithe_opinion"), "the church resents the tithe")
		"JUSTICE_SEVERITY":
			var d := int(req.params["delta"])
			_apply(state, effects, "unrest", data.bal("justice_unrest_per_point") * d, "justice severity changed")
			_apply(state, effects, "peasant_contentment", data.bal("justice_contentment_per_point") * d, "harsher courts")
		"BUILD_ECONOMIC":
			if req.params["project"] == "granary":
				_apply(state, effects, "grain_capacity_bonus", 50.0, "granary raised")
			else:
				_apply(state, effects, "road_income_bonus", 2.0, "road improves trade")
		"SPY_MISSION":
			_apply(state, effects, "legitimacy", data.bal("spy_legitimacy_gain"), "rumors quietly answered")
		"COUNCIL_CONSULT":
			pass  # outcome record only; the Voicer renders the consult
		"CHARACTER_REWARD":
			var c: Character = state.characters[req.target]
			var gain := int(data.bal("reward_opinion"))
			if "vain" in c.traits:
				gain += int(data.bal("reward_opinion_vain_bonus"))
			c.change_opinion(gain, "rewarded with gold", state.tick)
		"CHARACTER_PUNISH":
			state.characters[req.target].change_opinion(
				int(data.bal("punish_opinion")), "publicly reprimanded", state.tick)
		"CHARACTER_CONFIDE":
			state.characters[req.target].change_opinion(
				int(data.bal("confide_opinion")), "you confided in them", state.tick)
	var cd := int(row.get("cooldown_ticks", 0))
	if cd > 0:
		state.cooldowns[req.action_code] = state.tick + cd
	var outcome := {"action_code": req.action_code, "ok": true, "effects": effects,
		"notes": String(row["label"]), "target": req.target, "params": req.params.duplicate()}
	state.recent_outcomes.append(outcome)
	return outcome

func _apply(state: GameState, effects: Array, metric: String, delta: float, reason: String) -> void:
	state.metrics[metric] = state.metrics[metric] + delta
	effects.append({"metric": metric, "delta": delta, "reason": reason})

func _set(state: GameState, effects: Array, metric: String, value: float, reason: String) -> void:
	var delta := value - state.metrics[metric]
	state.metrics[metric] = value
	effects.append({"metric": metric, "delta": delta, "reason": reason})
```

Note: `CHARACTER_REWARD` in `policy_actions_court_additions.csv` has `gold_cost_formula=formula_reward_cost` — covered by `COST_KEYS`. `GUARD_ADJUST` and faction actions stay in the table but are simply never suggested in slice 1; validate/execute handles them falling through `match` with no effects, which is acceptable — they're unreachable from slice-1 UI.

- [ ] **Step 5: Run** — Expected: PASS.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: ActionSystem with validation, effects, reason strings"`

---

### Task 7: ConcernScanner + SuggestionGenerator

**Files:**
- Create: `scripts/engine/concern_scanner.gd`, `scripts/engine/suggestion_generator.gd`
- Test: `tests/engine/test_concerns_suggestions.gd`

**Interfaces:**
- Consumes: `GameState`, `DataRepository`, `ActionSystem.validate`, `ActionRequest.make`.
- Produces: `ConcernScanner.scan(state: GameState, data: DataRepository) -> Array` of `{seat: String, metric: String, value: float, severity: float}` (severity 0–1, how far past threshold), sorted worst-first. `SuggestionGenerator._init(data: DataRepository, actions: ActionSystem)`, `generate(state: GameState, concerns: Array) -> Array` of `{seat: String, request: ActionRequest, pitch_key: String, tradeoff: String}` — 2–3 entries, every request passes `ActionSystem.validate`.

- [ ] **Step 1: Write failing tests**

`tests/engine/test_concerns_suggestions.gd`:

```gdscript
extends GutTest

var data: DataRepository
var sys: ActionSystem
var gen: SuggestionGenerator

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	sys = ActionSystem.new(data)
	gen = SuggestionGenerator.new(data, sys)

func test_no_concerns_when_healthy() -> void:
	var s := GameState.new_campaign(data, 42)
	assert_eq(ConcernScanner.scan(s, data).size(), 0)

func test_low_grain_flags_steward_sorted_by_severity() -> void:
	var s := GameState.new_campaign(data, 42)
	s.metrics["grain"] = 10.0     # threshold 30 -> severe
	s.metrics["treasury"] = 95.0  # threshold 100 -> mild
	var concerns := ConcernScanner.scan(s, data)
	assert_eq(concerns.size(), 2)
	assert_eq(concerns[0]["metric"], "grain")
	assert_eq(concerns[0]["seat"], "steward")
	assert_gt(concerns[0]["severity"], concerns[1]["severity"])

func test_suggestions_valid_and_bounded() -> void:
	var s := GameState.new_campaign(data, 42)
	s.metrics["grain"] = 10.0
	s.metrics["unrest"] = 55.0
	var concerns := ConcernScanner.scan(s, data)
	var sugs := gen.generate(s, concerns)
	assert_between(sugs.size(), 2, 3)
	for sug in sugs:
		assert_eq(sys.validate(sug["request"], s), "", sug["request"].action_code + " must validate")
		assert_ne(sug["tradeoff"], "")

func test_quiet_tick_still_offers_something() -> void:
	var s := GameState.new_campaign(data, 42)
	var sugs := gen.generate(s, [])
	assert_between(sugs.size(), 2, 3)
```

- [ ] **Step 2: Run** — Expected: FAIL.

- [ ] **Step 3: Implement**

`scripts/engine/concern_scanner.gd`:

```gdscript
class_name ConcernScanner
extends RefCounted

## metric -> [balance threshold key, owning seat, direction]
## direction "below" fires when value < threshold, "above" when value > threshold.
const RULES := {
	"treasury": ["concern_treasury_low", "steward", "below"],
	"grain": ["concern_grain_low", "steward", "below"],
	"unrest": ["concern_unrest_high", "chancellor", "above"],
	"church_opinion": ["concern_church_low", "chaplain", "below"],
	"army_quality": ["concern_army_low", "marshal", "below"],
	"legitimacy": ["concern_legitimacy_low", "spymaster", "below"],
}

static func scan(state: GameState, data: DataRepository) -> Array:
	var out: Array = []
	for metric in RULES:
		var rule: Array = RULES[metric]
		var threshold := data.bal(rule[0])
		var value: float = state.metrics[metric]
		var breached := value < threshold if rule[2] == "below" else value > threshold
		if breached:
			var severity := absf(value - threshold) / maxf(threshold, 1.0)
			out.append({"seat": rule[1], "metric": metric, "value": value,
				"severity": clampf(severity, 0.05, 1.0)})
	out.sort_custom(func(a, b): return a["severity"] > b["severity"])
	return out
```

`scripts/engine/suggestion_generator.gd` — heuristics are deliberately seat-biased (the Marshal over-reaches, per PRD §8). Each concern maps to candidate requests; first valid ones win; quiet ticks fall back to a standing menu:

```gdscript
class_name SuggestionGenerator
extends RefCounted

var data: DataRepository
var actions: ActionSystem

func _init(d: DataRepository, a: ActionSystem) -> void:
	data = d
	actions = a

func generate(state: GameState, concerns: Array) -> Array:
	var out: Array = []
	for concern in concerns:
		for cand in _candidates_for(concern, state):
			if out.size() >= 3:
				break
			if actions.validate(cand["request"], state) == "" and not _duplicate(out, cand):
				out.append(cand)
	for cand in _standing_menu(state):
		if out.size() >= 2 and out.size() >= 3:
			break
		if out.size() < 2 and actions.validate(cand["request"], state) == "" and not _duplicate(out, cand):
			out.append(cand)
	return out

func _duplicate(out: Array, cand: Dictionary) -> bool:
	for s in out:
		if s["request"].action_code == cand["request"].action_code:
			return true
	return false

func _sug(seat: String, req: ActionRequest, pitch_key: String, tradeoff: String) -> Dictionary:
	return {"seat": seat, "request": req, "pitch_key": pitch_key, "tradeoff": tradeoff}

func _candidates_for(concern: Dictionary, _state: GameState) -> Array:
	match concern["metric"]:
		"grain":
			return [
				_sug("steward", ActionRequest.make("GRAIN_POLICY_SET", {"mode": "ration"}),
					"grain_ration", "Stretches stores through winter; the villages will grumble."),
				_sug("steward", ActionRequest.make("BUILD_ECONOMIC", {"project": "granary"}),
					"build_granary", "Costs gold now; we stop losing harvests to rot."),
			]
		"treasury":
			return [
				_sug("steward", ActionRequest.make("TAX_RATE_ADJUST", {"delta": 1}),
					"raise_tax", "Gold now; unrest creeps up while the rate stays high."),
				_sug("steward", ActionRequest.make("CHURCH_POLICY", {"mode": "tithe"}),
					"tithe_church", "Quick silver; Father Odo will not thank you."),
			]
		"unrest":
			return [
				_sug("chancellor", ActionRequest.make("TAX_RATE_ADJUST", {"delta": -1}),
					"ease_tax", "Costs income; cools the villages fastest."),
				_sug("chancellor", ActionRequest.make("JUSTICE_SEVERITY", {"delta": 1}),
					"harsh_justice", "Order through fear; contentment pays for it."),
			]
		"church_opinion":
			return [_sug("chaplain", ActionRequest.make("CHURCH_POLICY", {"mode": "endow"}),
				"endow_church", "Gold for grace; the pulpits turn friendly.")]
		"army_quality":
			return [_sug("marshal", ActionRequest.make("LEVY_RAISE"),
				"raise_levies", "Gold and grumbling; the ranks fill out.")]
		"legitimacy":
			return [_sug("spymaster", ActionRequest.make("SPY_MISSION", {"target": "rumors"}),
				"quiet_rumors", "Coin for whispers; the talk in the taverns turns kinder.")]
	return []

func _standing_menu(_state: GameState) -> Array:
	return [
		_sug("marshal", ActionRequest.make("LEVY_RAISE"),
			"raise_levies", "Gold and grumbling; the ranks fill out."),
		_sug("steward", ActionRequest.make("BUILD_ECONOMIC", {"project": "road"}),
			"build_road", "Costs gold; trade moves quicker every tick after."),
		_sug("chaplain", ActionRequest.make("CHURCH_POLICY", {"mode": "endow"}),
			"endow_church", "Gold for grace; the pulpits turn friendly."),
	]
```

- [ ] **Step 4: Run** — Expected: PASS. If `test_suggestions_valid_and_bounded` finds cooldown collisions, that's real: fix by the `_duplicate` guard (already present), not by loosening the test.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: concern scan + biased suggestion heuristics"`

---

### Task 8: TickEngine + TickReport

**Files:**
- Create: `scripts/engine/tick_engine.gd`, `scripts/engine/tick_report.gd`
- Test: `tests/engine/test_tick_engine.gd`

**Interfaces:**
- Consumes: everything engine-side so far.
- Produces: `class_name TickReport` — fields `tick: int`, `season: String`, `year: int`, `metric_deltas: Array of {metric, delta, reason}`, `concerns: Array` (ConcernScanner shape), `suggestions: Array` (SuggestionGenerator shape), `outcomes: Array` (last turn's `state.recent_outcomes`, drained); `to_dict()`. `class_name TickEngine` — `_init(data: DataRepository)`, public fields `actions: ActionSystem`, `suggestions: SuggestionGenerator`; `advance(state: GameState) -> TickReport` which: ① increments `state.tick`, ② drains `state.recent_outcomes` into the report, ③ applies metric drift (all deltas recorded with reasons), ④ scans concerns, ⑤ generates suggestions.

- [ ] **Step 1: Write failing tests**

`tests/engine/test_tick_engine.gd`:

```gdscript
extends GutTest

var data: DataRepository
var engine: TickEngine

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	engine = TickEngine.new(data)

func test_advance_increments_and_reports() -> void:
	var s := GameState.new_campaign(data, 42)
	var r := engine.advance(s)
	assert_eq(r.tick, 1)
	assert_eq(s.tick, 1)
	assert_eq(r.season, "spring")
	assert_gt(r.metric_deltas.size(), 0)
	for d in r.metric_deltas:
		assert_ne(d["reason"], "")

func test_tax_income_formula() -> void:
	var s := GameState.new_campaign(data, 42)
	engine.advance(s)
	# income = tax_rate(5) * admin_capacity * 0.8 + tariff_rate(3) * 3.0 + road bonus(0)
	var chancellor: Character = s.characters[s.council["chancellor"]]
	var cap: float = data.bal("admin_base") + chancellor.skills["sk_admin"] * 0.10
	var expected: float = 5.0 * cap * data.bal("tax_income_factor") + 3.0 * data.bal("tariff_income_factor")
	assert_almost_eq(s.metrics["tax_income"], expected, 0.001)

func test_grain_seasonal() -> void:
	var s := GameState.new_campaign(data, 42)
	s.tick = 11  # advance() makes it 12 -> autumn
	var g0: float = s.metrics["grain"]
	engine.advance(s)
	assert_gt(s.metrics["grain"], g0)  # harvest
	s.tick = 19  # -> 20, winter
	var g1: float = s.metrics["grain"]
	engine.advance(s)
	assert_lt(s.metrics["grain"], g1)

func test_outcomes_drain_into_next_report() -> void:
	var s := GameState.new_campaign(data, 42)
	engine.advance(s)
	engine.actions.execute(ActionRequest.make("TAX_RATE_ADJUST", {"delta": 1}), s)
	var r := engine.advance(s)
	assert_eq(r.outcomes.size(), 1)
	assert_eq(s.recent_outcomes.size(), 0)
	assert_eq(r.outcomes[0]["action_code"], "TAX_RATE_ADJUST")
```

- [ ] **Step 2: Run** — Expected: FAIL.

- [ ] **Step 3: Implement**

`scripts/engine/tick_report.gd`:

```gdscript
class_name TickReport
extends RefCounted

var tick: int = 0
var season: String = ""
var year: int = 1
var metric_deltas: Array = []
var concerns: Array = []
var suggestions: Array = []
var outcomes: Array = []

func to_dict() -> Dictionary:
	var sug_dicts: Array = []
	for s in suggestions:
		sug_dicts.append({"seat": s["seat"], "request": s["request"].to_dict(),
			"pitch_key": s["pitch_key"], "tradeoff": s["tradeoff"]})
	return {"tick": tick, "season": season, "year": year,
		"metric_deltas": metric_deltas.duplicate(true), "concerns": concerns.duplicate(true),
		"suggestions": sug_dicts, "outcomes": outcomes.duplicate(true)}
```

`scripts/engine/tick_engine.gd`:

```gdscript
class_name TickEngine
extends RefCounted

var data: DataRepository
var actions: ActionSystem
var suggestions: SuggestionGenerator

func _init(d: DataRepository) -> void:
	data = d
	actions = ActionSystem.new(d)
	suggestions = SuggestionGenerator.new(d, actions)

func advance(state: GameState) -> TickReport:
	state.tick += 1
	var r := TickReport.new()
	r.tick = state.tick
	r.season = state.season()
	r.year = state.year()
	r.outcomes = state.recent_outcomes
	state.recent_outcomes = []
	_drift(state, r)
	r.concerns = ConcernScanner.scan(state, data)
	r.suggestions = suggestions.generate(state, r.concerns)
	return r

func _drift(state: GameState, r: TickReport) -> void:
	var m := state.metrics
	# admin capacity from the Chancellor (council_seats.csv: 0.10 per sk_admin)
	var cap := data.bal("admin_base")
	if state.council.has("chancellor"):
		var ch: Character = state.characters[state.council["chancellor"]]
		cap += ch.skills["sk_admin"] * 0.10
	else:
		cap -= data.bal("chancellor_vacancy_penalty")
	_set(r, m, "admin_capacity", cap, "council administration")
	# income
	var income := m["tax_rate"] * cap * data.bal("tax_income_factor") \
		+ m["tariff_rate"] * data.bal("tariff_income_factor") + m["road_income_bonus"]
	_set(r, m, "tax_income", income, "taxes and tariffs collected")
	_apply(r, m, "treasury", income - data.bal("court_upkeep"), "income minus court upkeep")
	# grain
	if state.season() == "autumn":
		_apply(r, m, "grain", data.bal("harvest_gain"), "the harvest comes in")
	else:
		var drain := data.bal("grain_drain_winter") if state.season() == "winter" else data.bal("grain_drain")
		if m["grain_ration"] > 0.0:
			drain *= 0.5
		_apply(r, m, "grain", -drain, "the realm eats")
	m["grain"] = clampf(m["grain"], 0.0, 200.0 + m["grain_capacity_bonus"])
	# unrest
	var unrest_delta := (m["tax_rate"] - 5.0) * data.bal("unrest_tax_pressure") - data.bal("unrest_decay")
	if m["grain"] <= 0.0:
		unrest_delta += data.bal("unrest_famine")
	_apply(r, m, "unrest", unrest_delta, "tax pressure and the mood of the villages")
	m["unrest"] = clampf(m["unrest"], 0.0, 100.0)
	# drifts toward baselines
	_drift_toward(r, m, "peasant_contentment", 50.0, data.bal("contentment_drift"), "life goes on")
	_drift_toward(r, m, "legitimacy", 50.0, data.bal("legitimacy_drift"), "memory of the crown settles")
	_drift_toward(r, m, "church_opinion", 50.0, data.bal("church_drift"), "sermons soften")
	# army decay
	if m["army_quality"] > data.bal("army_floor"):
		_apply(r, m, "army_quality", -data.bal("army_decay"), "drills lapse")

func _apply(r: TickReport, m: Dictionary, metric: String, delta: float, reason: String) -> void:
	if is_zero_approx(delta):
		return
	m[metric] = m[metric] + delta
	r.metric_deltas.append({"metric": metric, "delta": delta, "reason": reason})

func _set(r: TickReport, m: Dictionary, metric: String, value: float, reason: String) -> void:
	var delta: float = value - m[metric]
	m[metric] = value
	if not is_zero_approx(delta):
		r.metric_deltas.append({"metric": metric, "delta": delta, "reason": reason})

func _drift_toward(r: TickReport, m: Dictionary, metric: String, baseline: float, rate: float, reason: String) -> void:
	var delta := clampf(baseline - m[metric], -rate, rate)
	_apply(r, m, metric, delta, reason)
```

- [ ] **Step 4: Run** — Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: TickEngine drift + TickReport"`

---

### Task 9: SaveLoad + the determinism harness

**Files:**
- Create: `scripts/engine/save_load.gd`
- Test: `tests/engine/test_save_load.gd`, `tests/engine/test_determinism.gd`

**Interfaces:**
- Consumes: `GameState.to_dict/from_dict`, `TickEngine`.
- Produces: `class_name SaveLoad` — `static save_game(state: GameState, path: String) -> bool`, `static load_game(path: String) -> GameState` (null + `push_error` on failure), `static state_hash(state: GameState) -> String` (SHA-256 of `JSON.stringify(state.to_dict(), "", true)` — the `sort_keys=true` argument is what makes the hash canonical).

- [ ] **Step 1: Write failing tests**

`tests/engine/test_save_load.gd`:

```gdscript
extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_save_load_round_trip_hash_equal() -> void:
	var engine := TickEngine.new(data)
	var s := GameState.new_campaign(data, 42)
	for i in 5:
		engine.advance(s)
	engine.actions.execute(ActionRequest.make("CHURCH_POLICY", {"mode": "tithe"}), s)
	var path := "user://test_save.json"
	assert_true(SaveLoad.save_game(s, path))
	var loaded := SaveLoad.load_game(path)
	assert_not_null(loaded)
	assert_eq(SaveLoad.state_hash(loaded), SaveLoad.state_hash(s))
```

`tests/engine/test_determinism.gd` — the permanent twin-run harness (gates every future slice):

```gdscript
extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

## Scripted year: on listed ticks, execute the listed request.
func _scripted_inputs() -> Dictionary:
	return {
		2: ActionRequest.make("TAX_RATE_ADJUST", {"delta": 1}),
		5: ActionRequest.make("CHURCH_POLICY", {"mode": "tithe"}),
		9: ActionRequest.make("LEVY_RAISE"),
		14: ActionRequest.make("GRAIN_POLICY_SET", {"mode": "ration"}),
		20: ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, "char_marshal"),
		30: ActionRequest.make("BUILD_ECONOMIC", {"project": "road"}),
		41: ActionRequest.make("JUSTICE_SEVERITY", {"delta": 1}),
	}

func _run_campaign(seed_value: int, reload_at: int = -1) -> String:
	var engine := TickEngine.new(data)
	var s := GameState.new_campaign(data, seed_value)
	var inputs := _scripted_inputs()
	for i in 48:
		engine.advance(s)
		if inputs.has(s.tick) and engine.actions.validate(inputs[s.tick], s) == "":
			engine.actions.execute(inputs[s.tick], s)
		if s.tick == reload_at:
			SaveLoad.save_game(s, "user://det_test.json")
			s = SaveLoad.load_game("user://det_test.json")
	return SaveLoad.state_hash(s)

func test_twin_runs_identical() -> void:
	assert_eq(_run_campaign(1234), _run_campaign(1234))

func test_save_load_mid_run_changes_nothing() -> void:
	assert_eq(_run_campaign(1234), _run_campaign(1234, 24))

func test_different_seeds_diverge() -> void:
	assert_ne(_run_campaign(1234), _run_campaign(9999))
```

Note on `test_different_seeds_diverge`: slice-1 drift consumes no randomness, so if this assertion fails it is allowed to change it to compare `state.rng.to_dict()` instead — but leave the test in place; the moment events (which roll dice) land, hashes must diverge.

- [ ] **Step 2: Run** — Expected: FAIL (`SaveLoad` not found).

- [ ] **Step 3: Implement**

`scripts/engine/save_load.gd`:

```gdscript
class_name SaveLoad
extends RefCounted

static func save_game(state: GameState, path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("SaveLoad: cannot write " + path)
		return false
	f.store_string(JSON.stringify(state.to_dict(), "\t", true))
	return true

static func load_game(path: String) -> GameState:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("SaveLoad: cannot read " + path)
		return null
	var parsed = JSON.parse_string(f.get_as_text())
	if parsed == null or not parsed is Dictionary:
		push_error("SaveLoad: corrupt save " + path)
		return null
	return GameState.from_dict(parsed)

static func state_hash(state: GameState) -> String:
	var canonical := JSON.stringify(state.to_dict(), "", true)
	return canonical.sha256_text()
```

Caution: JSON round-trips ints as floats. `GameState.from_dict`/`Character.from_dict` already re-cast with `int(...)` where it matters (tick, cooldowns, opinion). If the round-trip hash test fails, the fix is to normalize in `to_dict()`/`from_dict()` (cast consistently), never to weaken the test.

- [ ] **Step 4: Run** — Expected: PASS. This is the milestone where the engine is provably deterministic.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: JSON save/load + twin-run determinism harness"`

---

### Task 10: templates.csv + TemplateVoicer

**Files:**
- Create: `data/templates.csv`, `scripts/llm/template_voicer.gd`
- Test: `tests/llm/test_template_voicer.gd`

**Interfaces:**
- Consumes: `TickReport`, `GameState`, `DataRepository.templates`.
- Produces: `class_name TemplateVoicer` — `static render_briefing(report: TickReport, state: GameState, data: DataRepository) -> Array` of `{speaker: String, text: String}` (speaker = character display name; opener line + one line per concern + one per suggestion pitch) and `static render_outcomes(report: TickReport, state: GameState, data: DataRepository) -> Array` (same shape, narrating last turn's outcomes). Line selection is deterministic: from matching template rows, pick `rows[state.tick % rows.size()]` — variety without randomness. `{placeholders}` filled via `String.format`.

- [ ] **Step 1: Create `data/templates.csv`**

Columns: `key` (pitch_key, `concern_<metric>`, `opener`, or `outcome_<action_code>`), `trait` (empty = generic; a trait code = preferred for speakers with it), `text` (may use `{value}`, `{season}`, `{year}`, `{tradeoff}`, `{label}`). Ship at least: 2 openers ×(generic, patient, wrathful), one `concern_` line per scanner metric ×(generic + 1 trait variant), one line per `pitch_key` used in Task 7 (`grain_ration`, `build_granary`, `raise_tax`, `tithe_church`, `ease_tax`, `harsh_justice`, `endow_church`, `raise_levies`, `quiet_rumors`, `build_road`), and one `outcome_` line per slice-1 action. Sample rows (author the rest in the same voice):

```csv
key,trait,text
opener,,"My lord, the council is assembled. It is {season} of year {year}."
opener,patient,"In good time, my lord. The council waits on your word — {season}, year {year}."
opener,wrathful,"Let us not waste the morning, my lord. {season}. Year {year}. To business."
concern_grain,,"Grain stores stand at {value} — thinner than I would like with winter ahead."
concern_grain,cynical,"We have {value} grain. Prayers will not refill a granary, whatever the Chaplain says."
concern_treasury,,"The treasury holds {value} gold. Our obligations do not shrink to match."
concern_unrest,,"There is talk in the villages, my lord. Unrest stands at {value} and climbs."
concern_army_quality,,"The levies grow soft. Quality stands at {value} — I would not march them far."
concern_church_opinion,,"The pulpits grow cold toward us. The church's regard stands at {value}."
concern_legitimacy,,"There are whispers about the crown itself, my lord. Best answered before they harden."
pitch_grain_ration,,"Ration the stores now. {tradeoff}"
pitch_build_granary,,"Commission a granary. {tradeoff}"
pitch_raise_tax,,"Raise the rate a point. {tradeoff}"
pitch_tithe_church,,"The church can spare a tithe. {tradeoff}"
pitch_ease_tax,,"Ease the rate a point. {tradeoff}"
pitch_harsh_justice,,"Let the courts bite harder. {tradeoff}"
pitch_endow_church,,"An endowment would mend fences. {tradeoff}"
pitch_raise_levies,,"Fresh levies, drilled hard. {tradeoff}"
pitch_raise_levies,bold,"Give me the coin and I will give you an army worth fearing. {tradeoff}"
pitch_quiet_rumors,,"Let my people answer the whispers quietly. {tradeoff}"
pitch_build_road,,"A road pays for itself, given time. {tradeoff}"
outcome_TAX_RATE_ADJUST,,"The new rate is cried in every market square."
outcome_TARIFF_ADJUST,,"The customs houses post the new tariff."
outcome_LEVY_RAISE,,"The muster rolls fill; sergeants curse recruits on every green."
outcome_GRAIN_POLICY_SET,,"The granary doors move to your word."
outcome_CHURCH_POLICY,,"Word of your policy reaches every parish by Sunday."
outcome_JUSTICE_SEVERITY,,"The courts adjust their temper to yours."
outcome_BUILD_ECONOMIC,,"Surveyors and masons are engaged; work begins."
outcome_SPY_MISSION,,"Coin changes hands in quiet rooms."
outcome_COUNCIL_CONSULT,,"The minister leans in and speaks freely."
outcome_CHARACTER_REWARD,,"The court takes careful note of your favour."
outcome_CHARACTER_PUNISH,,"The rebuke lands before the whole court."
outcome_CHARACTER_CONFIDE,,"You speak privately; the rest of the council pretends not to notice."
```

- [ ] **Step 2: Write failing tests**

`tests/llm/test_template_voicer.gd`:

```gdscript
extends GutTest

var data: DataRepository
var engine: TickEngine

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	engine = TickEngine.new(data)

func test_briefing_has_opener_and_pitches() -> void:
	var s := GameState.new_campaign(data, 42)
	s.metrics["grain"] = 10.0
	var r := engine.advance(s)
	var lines := TemplateVoicer.render_briefing(r, s, data)
	assert_gt(lines.size(), 1)
	assert_eq(lines[0]["speaker"], "Aldwin Reeve")  # chancellor opens
	assert_string_contains(lines[0]["text"], "year 1")
	var joined := ""
	for l in lines:
		joined += l["text"] + "\n"
		assert_false("{" in l["text"], "unfilled placeholder in: " + l["text"])
	assert_string_contains(joined, "Grain")

func test_trait_variant_preferred() -> void:
	var s := GameState.new_campaign(data, 42)
	s.metrics["army_quality"] = 30.0
	var r := engine.advance(s)
	var lines := TemplateVoicer.render_briefing(r, s, data)
	var brandt_lines := ""
	for l in lines:
		if l["speaker"] == "Ser Brandt of Harrow":
			brandt_lines += l["text"]
	# Brandt is `bold`; the bold pitch variant must win over the generic one
	assert_string_contains(brandt_lines, "worth fearing")

func test_outcomes_narrated_deterministically() -> void:
	var s := GameState.new_campaign(data, 42)
	engine.advance(s)
	engine.actions.execute(ActionRequest.make("LEVY_RAISE"), s)
	var r := engine.advance(s)
	var a := TemplateVoicer.render_outcomes(r, s, data)
	var b := TemplateVoicer.render_outcomes(r, s, data)
	assert_eq(a.size(), 1)
	assert_string_contains(a[0]["text"], "muster")
	assert_eq(a, b)
```

- [ ] **Step 3: Run** — Expected: FAIL.

- [ ] **Step 4: Implement**

`scripts/llm/template_voicer.gd`:

```gdscript
class_name TemplateVoicer
extends RefCounted

static func render_briefing(report: TickReport, state: GameState, data: DataRepository) -> Array:
	var lines: Array = []
	var chancellor := _speaker_for_seat("chancellor", state)
	lines.append({"speaker": chancellor["name"], "text": _line(data, "opener",
		chancellor["traits"], report.tick, {"season": report.season, "year": report.year})})
	for c in report.concerns:
		var sp := _speaker_for_seat(c["seat"], state)
		lines.append({"speaker": sp["name"], "text": _line(data, "concern_" + c["metric"],
			sp["traits"], report.tick, {"value": int(c["value"])})})
	for sug in report.suggestions:
		var sp := _speaker_for_seat(sug["seat"], state)
		lines.append({"speaker": sp["name"], "text": _line(data, "pitch_" + sug["pitch_key"],
			sp["traits"], report.tick, {"tradeoff": sug["tradeoff"]})})
	return lines

static func render_outcomes(report: TickReport, state: GameState, data: DataRepository) -> Array:
	var lines: Array = []
	var chancellor := _speaker_for_seat("chancellor", state)
	for o in report.outcomes:
		lines.append({"speaker": chancellor["name"], "text": _line(data,
			"outcome_" + o["action_code"], chancellor["traits"], report.tick,
			{"label": o["notes"]})})
	return lines

static func _speaker_for_seat(seat: String, state: GameState) -> Dictionary:
	if state.council.has(seat):
		var c: Character = state.characters[state.council[seat]]
		return {"name": c.display_name, "traits": c.traits}
	return {"name": "The court clerk", "traits": []}

static func _line(data: DataRepository, key: String, speaker_traits: Array,
		tick: int, vars: Dictionary) -> String:
	var generic: Array = []
	var tinted: Array = []
	for row in data.templates:
		if row["key"] != key:
			continue
		if row["trait"] == "":
			generic.append(row["text"])
		elif row["trait"] in speaker_traits:
			tinted.append(row["text"])
	var pool := tinted if not tinted.is_empty() else generic
	if pool.is_empty():
		return "[missing template: %s]" % key
	return String(pool[tick % pool.size()]).format(vars)
```

- [ ] **Step 5: Run** — Expected: PASS.

- [ ] **Step 6: Commit** — `git add -A && git commit -m "feat: trait-tinted template voicing"`

---

### Task 11: Game autoload + council screen (offline-playable milestone)

**Files:**
- Create: `scripts/ui/game.gd`, `scripts/ui/council_screen.gd`, `scenes/council.tscn`
- Modify: `project.godot` (autoload + main scene)
- Test: `tests/ui/test_council_screen.gd`

**Interfaces:**
- Consumes: everything so far.
- Produces: autoload `Game` (`scripts/ui/game.gd`, extends Node) — fields `data: DataRepository`, `state: GameState`, `engine: TickEngine`, `current_report: TickReport`; methods `start_campaign(seed_value: int = 42) -> void`, `next_tick() -> TickReport`, `try_execute(req: ActionRequest) -> Dictionary` (returns `{ok: bool, error: String, outcome}`), `save(path)`, `load(path)`; signal `report_ready(report)`. `CouncilScreen` builds its whole UI in `_ready()` from code (no editor-built node tree, so the scene stays reviewable in diffs): top metrics strip (one `Label` per key metric, tooltip = last reasons), center `RichTextLabel` transcript, bottom `VBoxContainer` with up to 3 suggestion `Button`s + `LineEdit` (free text, disabled until Task 14) + `End Turn` button. Portraits: 48×48 `ColorRect` + initial letter per minister (placeholder; if `assets/portraits/<id>.png` exists, a `TextureRect` is used instead).

- [ ] **Step 1: Write the failing UI smoke test**

`tests/ui/test_council_screen.gd`:

```gdscript
extends GutTest

func test_screen_builds_and_click_executes() -> void:
	var screen: Node = load("res://scenes/council.tscn").instantiate()
	add_child_autofree(screen)
	Game.start_campaign(42)
	screen.begin()          # renders first tick
	await wait_frames(2)
	var buttons: Array = screen.suggestion_buttons()
	assert_between(buttons.size(), 2, 3)
	var treasury_before: float = Game.state.metrics["treasury"]
	buttons[0].pressed.emit()
	await wait_frames(2)
	assert_ne(Game.state.recent_outcomes, [])
	screen.end_turn_button().pressed.emit()
	await wait_frames(2)
	assert_eq(Game.state.tick, 2)
```

- [ ] **Step 2: Run** — Expected: FAIL (no scene, no autoload — the autoload error is expected until Step 3).

- [ ] **Step 3: Implement**

`scripts/ui/game.gd`:

```gdscript
extends Node
## Autoload "Game": owns the sim; UI talks only to this.

signal report_ready(report: TickReport)

var data: DataRepository
var state: GameState
var engine: TickEngine
var current_report: TickReport

func _ready() -> void:
	data = DataRepository.load_all("res://data")
	assert(data != null, "data load failed: " + DataRepository.last_error)

func start_campaign(seed_value: int = 42) -> void:
	state = GameState.new_campaign(data, seed_value)
	engine = TickEngine.new(data)

func next_tick() -> TickReport:
	current_report = engine.advance(state)
	report_ready.emit(current_report)
	return current_report

func try_execute(req: ActionRequest) -> Dictionary:
	var err := engine.actions.validate(req, state)
	if err != "":
		return {"ok": false, "error": err, "outcome": null}
	return {"ok": true, "error": "", "outcome": engine.actions.execute(req, state)}

func save_campaign(path: String = "user://save.json") -> bool:
	return SaveLoad.save_game(state, path)

func load_campaign(path: String = "user://save.json") -> bool:
	var loaded := SaveLoad.load_game(path)
	if loaded == null:
		return false
	state = loaded
	return true
```

Register in `project.godot`:

```ini
[autoload]
Game="*res://scripts/ui/game.gd"
```

and set `run/main_scene="res://scenes/council.tscn"`.

`scenes/council.tscn` (text format, minimal — the script builds everything):

```
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://scripts/ui/council_screen.gd" id="1"]

[node name="CouncilScreen" type="Control"]
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
script = ExtResource("1")
```

`scripts/ui/council_screen.gd` (key structure; style values are suggestions, keep them token-simple):

```gdscript
extends Control
## Council screen: metrics strip / transcript / input row. Built in code.

const PIXEL_FONT_PATH := "res://assets/fonts/pixel.ttf"  # optional; falls back to default

var metrics_box: HBoxContainer
var transcript: RichTextLabel
var suggestions_box: VBoxContainer
var free_text: LineEdit
var end_turn: Button
var _suggestion_buttons: Array = []

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("1a1423")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)
	metrics_box = HBoxContainer.new()
	root.add_child(metrics_box)
	transcript = RichTextLabel.new()
	transcript.bbcode_enabled = true
	transcript.scroll_following = true
	transcript.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(transcript)
	suggestions_box = VBoxContainer.new()
	root.add_child(suggestions_box)
	var input_row := HBoxContainer.new()
	root.add_child(input_row)
	free_text = LineEdit.new()
	free_text.placeholder_text = "Give an order... (couriers arrive in a later build)"
	free_text.editable = false
	free_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input_row.add_child(free_text)
	end_turn = Button.new()
	end_turn.text = "End Turn"
	end_turn.pressed.connect(_on_end_turn)
	input_row.add_child(end_turn)
	_apply_font()
	if Game.state == null:
		Game.start_campaign(42)
	begin.call_deferred()

func begin() -> void:
	_render_report(Game.next_tick())

func suggestion_buttons() -> Array:
	return _suggestion_buttons

func end_turn_button() -> Button:
	return end_turn

func _on_end_turn() -> void:
	_render_report(Game.next_tick())

func _render_report(report: TickReport) -> void:
	_render_metrics(report)
	for line in TemplateVoicer.render_outcomes(report, Game.state, Game.data):
		_say(line)
	for line in TemplateVoicer.render_briefing(report, Game.state, Game.data):
		_say(line)
	_render_suggestions(report)

func _say(line: Dictionary) -> void:
	transcript.append_text("[b]%s:[/b] %s\n" % [line["speaker"], line["text"]])

func _render_metrics(report: TickReport) -> void:
	for child in metrics_box.get_children():
		child.queue_free()
	var reasons := {}
	for d in report.metric_deltas:
		reasons[d["metric"]] = "%+.1f: %s" % [d["delta"], d["reason"]]
	for m in ["treasury", "grain", "unrest", "legitimacy", "army_quality", "church_opinion"]:
		var l := Label.new()
		l.text = "%s %d" % [m.capitalize(), int(Game.state.metrics[m])]
		l.tooltip_text = reasons.get(m, "no change")
		l.mouse_filter = Control.MOUSE_FILTER_STOP
		metrics_box.add_child(l)

func _render_suggestions(report: TickReport) -> void:
	for child in suggestions_box.get_children():
		child.queue_free()
	_suggestion_buttons = []
	for sug in report.suggestions:
		var b := Button.new()
		var sp: String = Game.state.characters[Game.state.council[sug["seat"]]].display_name \
			if Game.state.council.has(sug["seat"]) else sug["seat"]
		b.text = "%s: %s" % [sp, sug["request"].action_code]
		b.tooltip_text = sug["tradeoff"]
		b.pressed.connect(_on_suggestion.bind(sug["request"]))
		suggestions_box.add_child(b)
		_suggestion_buttons.append(b)

func _on_suggestion(req: ActionRequest) -> void:
	var result: Dictionary = Game.try_execute(req)
	if not result["ok"]:
		_say({"speaker": "Herald", "text": result["error"]})
		return
	for b in _suggestion_buttons:
		b.disabled = true

func _apply_font() -> void:
	if not FileAccess.file_exists(PIXEL_FONT_PATH):
		return
	var font := load(PIXEL_FONT_PATH)
	if font:
		theme = Theme.new()
		theme.default_font = font
		theme.default_font_size = 16
```

Drop a public-domain pixel TTF at `assets/fonts/pixel.ttf` if available (e.g. Pixel Operator); the screen works without it.

- [ ] **Step 4: Run tests + launch by hand**

`./run_tests.sh` — Expected: PASS. Then a real launch:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --path . scenes/council.tscn
```

Play a few ticks by clicking. This is the **first playtest milestone** — the game is playable offline, click-only.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: council screen, offline click-playable build"`

---

### Task 12: ResponseValidator + court reaction application

**Files:**
- Create: `scripts/llm/response_validator.gd`
- Modify: `scripts/engine/action_system.gd` (add `apply_court_reaction`)
- Test: `tests/llm/test_response_validator.gd`

**Interfaces:**
- Consumes: `DataRepository.actions`, `ActionRequest`, `GameState`, `Character.change_opinion`.
- Produces: `class_name ResponseValidator` — `static parse(json_text: String, data: DataRepository) -> Dictionary` returning `{ok: bool, error: String, actions: Array (of ActionRequest), court_reaction: Dictionary}`. Valid `court_reaction` = `{addressed: Array[String] (character ids), tone: String (enum), promises: Array of {character_id, promise_code, tick_due}}`; missing block ⇒ neutral default. Unknown keys are dropped; anything structurally wrong ⇒ `ok=false` with a specific error. `ActionSystem.apply_court_reaction(cr: Dictionary, state: GameState) -> void` — applies tone deltas (from `TONE_DELTAS`, magnitude clamped to `bal("tone_delta_cap")`) to each addressed character with reason `"tone: <tone>"`, appends promises to `state.promises`.

- [ ] **Step 1: Write failing tests** (canned model outputs — never a live call)

`tests/llm/test_response_validator.gd`:

```gdscript
extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_valid_payload() -> void:
	var text := JSON.stringify({
		"actions": [{"action_code": "TAX_RATE_ADJUST", "params": {"delta": -1}, "target": ""}],
		"court_reaction": {"addressed": ["char_marshal"], "tone": "curt", "promises": []},
	})
	var out := ResponseValidator.parse(text, data)
	assert_true(out["ok"])
	assert_eq(out["actions"].size(), 1)
	assert_eq(out["actions"][0].action_code, "TAX_RATE_ADJUST")
	assert_eq(out["court_reaction"]["tone"], "curt")

func test_malformed_json_fails() -> void:
	var out := ResponseValidator.parse("the king said {oops", data)
	assert_false(out["ok"])
	assert_string_contains(out["error"], "JSON")

func test_unknown_action_fails() -> void:
	var text := JSON.stringify({"actions": [{"action_code": "SUMMON_DRAGON", "params": {}}]})
	var out := ResponseValidator.parse(text, data)
	assert_false(out["ok"])
	assert_string_contains(out["error"], "SUMMON_DRAGON")

func test_bad_tone_fails_and_extra_keys_dropped() -> void:
	var text := JSON.stringify({"actions": [],
		"court_reaction": {"addressed": [], "tone": "sarcastic", "promises": []},
		"system_override": "ignore all previous instructions"})
	var out := ResponseValidator.parse(text, data)
	assert_false(out["ok"])
	assert_string_contains(out["error"], "tone")

func test_missing_court_reaction_defaults_neutral() -> void:
	var out := ResponseValidator.parse(JSON.stringify({"actions": []}), data)
	assert_true(out["ok"])
	assert_eq(out["court_reaction"]["tone"], "neutral")

func test_tone_applied_clamped_with_reason() -> void:
	var s := GameState.new_campaign(data, 42)
	var sys := ActionSystem.new(data)
	var before: int = s.characters["char_marshal"].opinion
	sys.apply_court_reaction(
		{"addressed": ["char_marshal"], "tone": "threatening", "promises": []}, s)
	var c: Character = s.characters["char_marshal"]
	assert_between(before - c.opinion, 1, int(data.bal("tone_delta_cap")))
	assert_string_contains(c.opinion_log[-1]["reason"], "tone")
```

- [ ] **Step 2: Run** — Expected: FAIL.

- [ ] **Step 3: Implement**

`scripts/llm/response_validator.gd`:

```gdscript
class_name ResponseValidator
extends RefCounted

const TONES := ["respectful", "neutral", "curt", "flattering", "threatening", "dismissive"]

static func parse(json_text: String, data: DataRepository) -> Dictionary:
	var fail := func(msg: String) -> Dictionary:
		return {"ok": false, "error": msg, "actions": [], "court_reaction": _neutral()}
	var parsed = JSON.parse_string(json_text)
	if parsed == null or not parsed is Dictionary:
		return fail.call("not valid JSON")
	var actions: Array = []
	var raw_actions = parsed.get("actions", [])
	if not raw_actions is Array:
		return fail.call("actions must be a list")
	for a in raw_actions:
		if not a is Dictionary or not a.get("action_code", "") is String:
			return fail.call("malformed action entry")
		var code: String = a["action_code"]
		if not data.actions.has(code):
			return fail.call("unknown action: " + code)
		var params = a.get("params", {})
		if not params is Dictionary:
			return fail.call("params must be an object")
		actions.append(ActionRequest.make(code, params, String(a.get("target", ""))))
	var cr = parsed.get("court_reaction", null)
	var reaction := _neutral()
	if cr is Dictionary:
		var tone := String(cr.get("tone", "neutral"))
		if not tone in TONES:
			return fail.call("invalid tone: " + tone)
		reaction["tone"] = tone
		var addressed = cr.get("addressed", [])
		if addressed is Array:
			for id in addressed:
				reaction["addressed"].append(String(id))
		var promises = cr.get("promises", [])
		if promises is Array:
			for p in promises:
				if p is Dictionary and p.has("character_id") and p.has("promise_code"):
					reaction["promises"].append({
						"character_id": String(p["character_id"]),
						"promise_code": String(p["promise_code"]),
						"tick_due": int(p.get("tick_due", 0)),
					})
	return {"ok": true, "error": "", "actions": actions, "court_reaction": reaction}

static func _neutral() -> Dictionary:
	return {"addressed": [], "tone": "neutral", "promises": []}
```

Add to `scripts/engine/action_system.gd`:

```gdscript
const TONE_DELTAS := {
	"respectful": 2, "neutral": 0, "curt": -2, "flattering": 2,
	"threatening": -3, "dismissive": -3,
}

func apply_court_reaction(cr: Dictionary, state: GameState) -> void:
	var cap := int(data.bal("tone_delta_cap"))
	var delta: int = clampi(TONE_DELTAS.get(cr.get("tone", "neutral"), 0), -cap, cap)
	for id in cr.get("addressed", []):
		if state.characters.has(id) and delta != 0:
			state.characters[id].change_opinion(delta, "tone: " + cr["tone"], state.tick)
	for p in cr.get("promises", []):
		state.promises.append({"character_id": p["character_id"],
			"promise_code": p["promise_code"], "made_tick": state.tick,
			"tick_due": p["tick_due"], "status": "open"})
```

- [ ] **Step 4: Run** — Expected: PASS.

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: strict parse validation + clamped court reactions"`

---

### Task 13: OpenAIClient + PromptBuilder + Voicer

**Files:**
- Create: `scripts/llm/openai_client.gd`, `scripts/llm/prompt_builder.gd`, `scripts/llm/voicer.gd`
- Test: `tests/llm/test_prompt_builder.gd`, `tests/llm/test_voicer_fallback.gd`

**Interfaces:**
- Consumes: `TickReport`, `GameState`, `ResponseValidator`, `TemplateVoicer`.
- Produces: `class_name LlmConfig` (inner detail of `OpenAIClient`): `static load_config() -> Dictionary` reading `user://config.json` → `{api_key: String, model_parse: String, model_voice: String, offline_mode: bool}`; missing file ⇒ `offline_mode=true`. `class_name OpenAIClient` extends **Node** — `signal completed(ok: bool, text: String)`; `request_completion(system_prompt: String, user_prompt: String, model: String, force_json: bool) -> void` (adds an `HTTPRequest` child, 20 s timeout, one retry, emits `completed`). Before coding the HTTP body, check OpenAI's current API reference for the exact endpoint/fields (spec: "verify current endpoint shape at implementation"); isolate them in `_build_body()`/`_extract_text()` so drift touches one place. `class_name PromptBuilder` — `static briefing_prompts(report, state) -> Dictionary {system, user}`, `static parse_prompts(player_text, report, state, data) -> Dictionary {system, user}` (system lists the legal action codes + params pulled from `data.actions`, the JSON shape from Task 12, and "output JSON only"). `class_name Voicer` extends **Node** — `_init(client: OpenAIClient)` (test seam: any object with the same signal/method), `voice_briefing(report, state, data, cb: Callable) -> void` and `parse_player_text(text, report, state, data, cb: Callable) -> void`; both call `cb` exactly once; template/validated fallback on any failure (`cb` gets `{ok, lines}` or ResponseValidator's dict with `degraded: bool`).

- [ ] **Step 1: Write failing tests** (no network anywhere)

`tests/llm/test_prompt_builder.gd`:

```gdscript
extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_parse_prompt_lists_actions_and_schema() -> void:
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	var p := PromptBuilder.parse_prompts("cut taxes by one", r, s, data)
	assert_string_contains(p["system"], "TAX_RATE_ADJUST")
	assert_string_contains(p["system"], "court_reaction")
	assert_string_contains(p["system"], "JSON")
	assert_string_contains(p["user"], "cut taxes by one")

func test_briefing_prompt_carries_personas_and_report() -> void:
	var s := GameState.new_campaign(data, 42)
	s.metrics["grain"] = 10.0
	var r := TickEngine.new(data).advance(s)
	var p := PromptBuilder.briefing_prompts(r, s)
	assert_string_contains(p["system"], "Aldwin Reeve")
	assert_string_contains(p["user"], "grain")
```

`tests/llm/test_voicer_fallback.gd`:

```gdscript
extends GutTest

class FakeClient:
	extends Node
	signal completed(ok: bool, text: String)
	var canned_ok := false
	var canned_text := ""
	func request_completion(_s: String, _u: String, _m: String, _j: bool) -> void:
		completed.emit.call_deferred(canned_ok, canned_text)

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_briefing_falls_back_to_template_on_failure() -> void:
	var fake := FakeClient.new()
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	var got: Dictionary = {}
	v.voice_briefing(r, s, data, func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_true(got["degraded"])
	assert_gt(got["lines"].size(), 0)  # template lines

func test_parse_path_validates_model_output() -> void:
	var fake := FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions":
		[{"action_code": "TAX_RATE_ADJUST", "params": {"delta": -1}, "target": ""}]})
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	var got: Dictionary = {}
	v.parse_player_text("lower taxes", r, s, data, func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_eq(got["actions"][0].action_code, "TAX_RATE_ADJUST")

func test_parse_bad_model_output_reports_error_not_crash() -> void:
	var fake := FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = "I think you should raise taxes, sire!"
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	var got: Dictionary = {}
	v.parse_player_text("lower taxes", r, s, data, func(res): got = res)
	await wait_frames(3)
	assert_false(got["ok"])
	assert_ne(got["error"], "")
```

- [ ] **Step 2: Run** — Expected: FAIL.

- [ ] **Step 3: Implement**

`scripts/llm/prompt_builder.gd`:

```gdscript
class_name PromptBuilder
extends RefCounted

static func briefing_prompts(report: TickReport, state: GameState) -> Dictionary:
	var personas := ""
	for id in state.characters:
		var c: Character = state.characters[id]
		personas += "- %s, %s. Traits: %s. Opinion of the ruler: %d.\n" % [
			c.display_name, c.seat, ", ".join(c.traits), c.opinion]
	var system := """You write in-character dialogue for a medieval royal council.
Voice ONLY what the report contains — never invent numbers, actions, or events.
One short paragraph per speaking minister, plain prose, no markdown.
Council:
%s""" % personas
	return {"system": system, "user": JSON.stringify(report.to_dict(), "", true)}

static func parse_prompts(player_text: String, report: TickReport, state: GameState,
		data: DataRepository) -> Dictionary:
	var catalog := ""
	for code in data.actions:
		catalog += "- %s: %s\n" % [code, data.actions[code].get("notes", "")]
	var ids := ", ".join(state.characters.keys())
	var system := """You translate a ruler's plain-language order into game actions.
Output ONLY a JSON object, no prose, shaped exactly:
{"actions":[{"action_code":"...","params":{},"target":""}],
 "court_reaction":{"addressed":[],"tone":"neutral","promises":[]}}
Legal action codes (use ONLY these; leave "actions" empty if nothing fits):
%s
Character ids for target/addressed: %s
tone is one of respectful|neutral|curt|flattering|threatening|dismissive.
Current tick: %d.""" % [catalog, ids, report.tick]
	return {"system": system, "user": player_text}
```

`scripts/llm/openai_client.gd`:

```gdscript
class_name OpenAIClient
extends Node

signal completed(ok: bool, text: String)

const CONFIG_PATH := "user://config.json"

static func load_config() -> Dictionary:
	var defaults := {"api_key": "", "model_parse": "gpt-5.6-luna",
		"model_voice": "gpt-5.6-terra", "offline_mode": true}
	if not FileAccess.file_exists(CONFIG_PATH):
		return defaults
	var parsed = JSON.parse_string(FileAccess.open(CONFIG_PATH, FileAccess.READ).get_as_text())
	if not parsed is Dictionary:
		return defaults
	for k in defaults:
		if not parsed.has(k):
			parsed[k] = defaults[k]
	if String(parsed["api_key"]) == "":
		parsed["offline_mode"] = true
	return parsed

var _config: Dictionary
var _retried := false

func _ready() -> void:
	_config = OpenAIClient.load_config()

func offline() -> bool:
	return bool(_config.get("offline_mode", true))

func request_completion(system_prompt: String, user_prompt: String,
		model: String, force_json: bool) -> void:
	if offline():
		completed.emit.call_deferred(false, "offline")
		return
	_retried = false
	_send(system_prompt, user_prompt, model, force_json)

func _send(system_prompt: String, user_prompt: String, model: String, force_json: bool) -> void:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	http.request_completed.connect(func(result, code, _headers, body):
		http.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS or code < 200 or code >= 300:
			if not _retried:
				_retried = true
				_send(system_prompt, user_prompt, model, force_json)
			else:
				completed.emit(false, "http error %d" % code)
			return
		var text := _extract_text(body.get_string_from_utf8())
		completed.emit(text != "", text))
	var err := http.request(_endpoint(), _headers_list(), HTTPClient.METHOD_POST,
		_build_body(system_prompt, user_prompt, model, force_json))
	if err != OK:
		http.queue_free()
		completed.emit.call_deferred(false, "request error %d" % err)

# --- OpenAI wire format lives ONLY below this line; verify against current docs ---

func _endpoint() -> String:
	return "https://api.openai.com/v1/chat/completions"

func _headers_list() -> PackedStringArray:
	return PackedStringArray(["Content-Type: application/json",
		"Authorization: Bearer " + String(_config["api_key"])])

func _build_body(system_prompt: String, user_prompt: String,
		model: String, force_json: bool) -> String:
	var body := {"model": model, "messages": [
		{"role": "system", "content": system_prompt},
		{"role": "user", "content": user_prompt}]}
	if force_json:
		body["response_format"] = {"type": "json_object"}
	return JSON.stringify(body)

func _extract_text(raw: String) -> String:
	var parsed = JSON.parse_string(raw)
	if parsed is Dictionary and parsed.has("choices") and parsed["choices"].size() > 0:
		return String(parsed["choices"][0]["message"]["content"])
	return ""
```

`scripts/llm/voicer.gd`:

```gdscript
class_name Voicer
extends Node

var client: Node  # OpenAIClient or a test fake with the same surface
var _config: Dictionary

func _init(c: Node) -> void:
	client = c
	_config = OpenAIClient.load_config()

func voice_briefing(report: TickReport, state: GameState, data: DataRepository,
		cb: Callable) -> void:
	var fallback := TemplateVoicer.render_briefing(report, state, data)
	var p := PromptBuilder.briefing_prompts(report, state)
	client.completed.connect(func(ok: bool, text: String):
		if ok:
			cb.call({"ok": true, "degraded": false,
				"lines": [{"speaker": "Council", "text": text}]})
		else:
			cb.call({"ok": true, "degraded": true, "lines": fallback}),
		CONNECT_ONE_SHOT)
	client.request_completion(p["system"], p["user"],
		String(_config["model_voice"]), false)

func parse_player_text(text: String, report: TickReport, state: GameState,
		data: DataRepository, cb: Callable) -> void:
	var p := PromptBuilder.parse_prompts(text, report, state, data)
	client.completed.connect(func(ok: bool, raw: String):
		if not ok:
			cb.call({"ok": false, "error": "couriers unavailable", "actions": [],
				"court_reaction": {}, "degraded": true})
			return
		var out := ResponseValidator.parse(raw, data)
		out["degraded"] = false
		cb.call(out),
		CONNECT_ONE_SHOT)
	client.request_completion(p["system"], p["user"],
		String(_config["model_parse"]), true)
```

- [ ] **Step 4: Run** — Expected: PASS (fallback + fixture tests; nothing touches the network — the fake replaces the client, and the real client in offline mode emits failure immediately).

- [ ] **Step 5: Commit** — `git add -A && git commit -m "feat: OpenAI client, prompt builder, voicer with degradation ladder"`

---

### Task 14: Free-text wiring + Guided polish + acceptance run

**Files:**
- Modify: `scripts/ui/council_screen.gd`, `scripts/ui/game.gd`, `CLAUDE.md`
- Test: extend `tests/ui/test_council_screen.gd`

**Interfaces:**
- Consumes: `Voicer`, `ResponseValidator`, `ActionSystem.apply_court_reaction`.
- Produces: the finished slice. `Game` gains `voicer: Voicer` + `client: OpenAIClient` (children of the autoload), and `submit_free_text(text: String, cb: Callable)` which parses → validates each action via `try_execute` → applies `court_reaction` → calls `cb` with `{ok, executed: Array, rejected: Array, error}`.

- [ ] **Step 1: Write the failing test** (fake client injected into `Game`)

Append to `tests/ui/test_council_screen.gd`:

```gdscript
func test_free_text_path_executes_via_fake_client() -> void:
	Game.start_campaign(42)
	var fake := preload("res://tests/llm/test_voicer_fallback.gd").FakeClient.new()
	fake.canned_ok = true
	fake.canned_text = JSON.stringify({"actions":
		[{"action_code": "TAX_RATE_ADJUST", "params": {"delta": -1}, "target": ""}],
		"court_reaction": {"addressed": ["char_steward"], "tone": "respectful", "promises": []}})
	add_child_autofree(fake)
	Game.use_client_for_tests(fake)
	Game.next_tick()
	var got: Dictionary = {}
	Game.submit_free_text("ease the taxes a little", func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_eq(got["executed"].size(), 1)
	assert_eq(Game.state.metrics["tax_rate"], 4.0)
	assert_string_contains(
		Game.state.characters["char_steward"].opinion_log[-1]["reason"], "tone")
```

- [ ] **Step 2: Run** — Expected: FAIL.

- [ ] **Step 3: Implement**

Add to `scripts/ui/game.gd`:

```gdscript
var client: OpenAIClient
var voicer: Voicer

func _ensure_llm() -> void:
	if voicer != null:
		return
	client = OpenAIClient.new()
	add_child(client)
	voicer = Voicer.new(client)
	add_child(voicer)

func use_client_for_tests(fake: Node) -> void:
	if voicer != null:
		voicer.queue_free()
	voicer = Voicer.new(fake)
	add_child(voicer)

func submit_free_text(text: String, cb: Callable) -> void:
	_ensure_llm()
	voicer.parse_player_text(text, current_report, state, data,
		func(res: Dictionary):
			if not res["ok"]:
				cb.call({"ok": false, "executed": [], "rejected": [], "error": res["error"]})
				return
			var executed: Array = []
			var rejected: Array = []
			for req in res["actions"]:
				var attempt := try_execute(req)
				if attempt["ok"]:
					executed.append(attempt["outcome"])
				else:
					rejected.append({"request": req, "error": attempt["error"]})
			engine.actions.apply_court_reaction(res["court_reaction"], state)
			cb.call({"ok": true, "executed": executed, "rejected": rejected, "error": ""}))
```

In `council_screen.gd`: set `free_text.editable = true`, connect `free_text.text_submitted`:

```gdscript
func _on_free_text_submitted(text: String) -> void:
	if text.strip_edges() == "":
		return
	free_text.editable = false
	_say({"speaker": "You", "text": text})
	Game.submit_free_text(text, func(res: Dictionary):
		free_text.editable = true
		free_text.clear()
		if not res["ok"]:
			_say({"speaker": "Herald", "text":
				"The Chancellor frowns — the council doesn't follow. (%s)" % res["error"]})
			return
		for outcome in res["executed"]:
			_say({"speaker": "Herald", "text": "It is done: " + outcome["notes"]})
		for rej in res["rejected"]:
			_say({"speaker": "Herald", "text":
				"The council cannot: " + rej["error"]}))
```

Guided-phase polish (also this step): after every executed action, the screen already narrates outcome + effects; add the Chancellor's explanation line by rendering each effect's reason: `for e in outcome["effects"]: _say({"speaker": chancellor_name, "text": "%s: %+d — %s" % [e["metric"], int(e["delta"]), e["reason"]]})`.

- [ ] **Step 4: Run all tests** — `./run_tests.sh` — Expected: ALL PASS.

- [ ] **Step 5: Acceptance run (manual, spec §6)**

Launch the game. Verify each acceptance criterion:

1. Play through year 1 (24 ticks) — clicks and (with a key configured in `user://config.json`, `offline_mode: false`) free text.
2. Briefings every tick; clicks make zero API calls (watch: no HTTPRequest children spawn).
3. "Raise the salt tariff by two points" executes; "make everyone happy forever" is rejected in-fiction.
4. Save (add temporary F5/F9 keys or call from the debugger), reload, continue — determinism suite green.
5. Delete/blank the config → full offline template play.
6. 640×360 integer-scaled window, portraits and backdrop visible.

Record any failures as new tasks; do not ship red criteria.

- [ ] **Step 6: Update CLAUDE.md and commit**

Add to CLAUDE.md under Stack: run command (`/Applications/Godot.app/Contents/MacOS/Godot --path .`), test command (`./run_tests.sh`), and the `user://config.json` shape from Task 13.

```bash
git add -A && git commit -m "feat: free-text orders wired end-to-end; slice 1 complete"
```

---

## Self-review notes (already applied)

- Spec coverage: BG-1…6 → Tasks 1–9; CS-1.1/1.2 → Task 5; CS-1.3/1.4 → Task 7; CS-1.5 → Tasks 10/11/14; parse + court_reaction → Tasks 12–14; pixel presentation → Tasks 1, 11; determinism harness → Task 9; degradation ladder → Task 13. Assisted/Independent phases are framework-only in slice 1 by design (spec §1) — the scaffolding phase enum ships with the settings screen in a later slice; Guided is the only active phase here, which is what year-1 content needs.
- Type consistency: `ActionRequest.make`, `try_execute` result shape, `{speaker, text}` line shape, and `{ok, degraded, ...}` callback shapes are used identically across Tasks 6–14.
- Known simplification: suggestion `pitch_key` template lookup uses prefix `pitch_` (Task 10) — matches Task 7's keys one-for-one.




