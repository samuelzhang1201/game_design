# Knowledge & Deception Core — Implementation Plan (Phases 1–2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the deterministic engine core that lets every character hold their own knowledge, judge whether they believe a claim, and eventually catch a lie — with zero LLM or API involvement.

**Architecture:** Five new `RefCounted` engine classes (`WorldRules`, `KnowledgeBase`, `SourceTrust`, `Belief`, `ClaimLedger`) plus three new CSVs. All state lives in `GameState` and rides the existing one-JSON save. Facts carry knower lists so knowledge is per-character; belief is computed from an externally supplied plausibility score times the speaker's source trust, adjusted by listener traits and corroboration; claims are recorded with the engine's ground truth so a lie can be resolved against reality later.

**Tech Stack:** Godot 4.7.1, typed GDScript, GUT for tests (`./run_tests.sh`).

**Spec:** `docs/superpowers/specs/2026-08-30-ai-conversation-system-design.md`

## Global Constraints

Every task's requirements implicitly include this section.

- **Typed GDScript everywhere.** Type hints on vars, params, and returns.
- **Warnings are errors, and inference from Variant fails to parse.** `var x := some_dictionary["k"]` and `var x := weakref(y)` both fail with "Cannot infer the type" or "inferred from a Variant value". Always annotate when the right-hand side is Variant-typed: `var x: float = row["sentiment"]`. This has broken the build three times; assume it will bite.
- **A test script that fails to parse is silently skipped by GUT.** `run_tests.sh` now fails the run if the script count drops, but always confirm the `Scripts` total rises when you add a test file.
- **`Errors 2` in the GUT summary is expected** (documented vendored-GExtension condition). Any other count is fatal.
- **Design values live in CSVs, never in scripts.** Add a `balance.csv` row rather than a constant.
- **Every opinion or relationship delta carries a reason string** at creation time (architecture invariant 4).
- **Simulation classes are `RefCounted`, Node-free**, so GUT runs them headless.
- **`GameState.SAVE_VERSION` stays at `1`.** All new fields read via `d.get(key, default)` so pre-feature saves still load.
- **No `Time.get_*`, no unseeded `randi()`** inside simulation code.
- **Commit messages** end with the repo's `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>` and `Claude-Session:` trailers.
- **Run the full suite** with `./run_tests.sh` before every commit, not a single test file.

## File Structure

**Create — engine (all `RefCounted`, Node-free):**

| File | Responsibility |
|---|---|
| `scripts/engine/world_rules.gd` | Deterministic impossibility floor. Answers one question: is this claim ruled out by the world itself? |
| `scripts/engine/knowledge.gd` | Facts and who knows them, at what credibility. The only unit permitted to answer "does X know Y?" |
| `scripts/engine/source_trust.gd` | Directed speaker→listener trust: derivation, lookup, audited adjustment |
| `scripts/engine/belief.gd` | Pure scoring: plausibility + trust + traits + corroboration → a belief number |
| `scripts/engine/claims.gd` | The claim ledger and the reckoning |

**Create — data:**

| File | Responsibility |
|---|---|
| `data/world_rules.csv` | Ontology, magnitude, and era rules |
| `data/claim_types.csv` | Claim taxonomy that magnitude rules key off |
| `data/facts.csv` | Seed knowledge: public facts, secrets, common sense |

**Create — tests:** `tests/engine/test_world_rules.gd`, `test_knowledge.gd`, `test_source_trust.gd`, `test_belief.gd`, `test_claims.gd`

**Modify:**

| File | Change |
|---|---|
| `scripts/engine/data_repository.gd` | Load the three new CSVs |
| `scripts/engine/game_state.gd` | Add `knowledge`, `source_trust`, `claims`; init and serialize them |
| `scripts/engine/tick_engine.gd` | Call the reckoning each tick |
| `scripts/engine/tick_report.gd` | Surface `claim_resolutions` |
| `data/balance.csv` | Eight new tuning keys |

Splitting `belief.gd` from `claims.gd` is deliberate: scoring is a pure function worth testing with hand-computed values, while the ledger owns mutation. Keeping them apart means the formula can be retuned without touching the reckoning.

---

### Task 1: World rules — the impossibility floor

**Files:**
- Create: `data/world_rules.csv`, `data/claim_types.csv`, `scripts/engine/world_rules.gd`
- Modify: `scripts/engine/data_repository.gd`
- Test: `tests/engine/test_world_rules.gd`

**Interfaces:**
- Consumes: `DataRepository.parse_csv`, `_load_if_present` (existing).
- Produces: `DataRepository.world_rules: Dictionary` (rule_code → row), `DataRepository.claim_types: Dictionary` (claim_type → row), and `WorldRules.veto(data: DataRepository, claim_type: String, text: String, magnitude: float) -> Dictionary` returning `{"vetoed": bool, "rule_code": String, "reason": String}`.

- [ ] **Step 1: Create the claim taxonomy**

Create `data/claim_types.csv`:

```csv
claim_type,label,magnitude_unit,notes
army_size,Army strength,soldiers,Claims about how many troops someone commands.
treasury,Treasury,gold,Claims about coin held or owed.
grain,Grain stores,measures,Claims about food supply.
identity,Identity,,Claims about who or what someone is.
intent,Intent,,Claims about what someone means to do.
loyalty,Loyalty,,Claims about where someone's allegiance lies.
event_report,Event report,,Claims that something happened.
```

- [ ] **Step 2: Create the world rules**

Create `data/world_rules.csv`. `pattern` is a `|`-separated list of lowercase substrings; a rule matches if any appears in the lowercased claim text. Magnitude rules match on `claim_type` and a value outside `[bound_min, bound_max]`.

```csv
rule_code,kind,claim_type,pattern,bound_min,bound_max,verdict,notes
onto_dragon,ontology,,dragon|wyrm|drake,0,0,impossible,Dragons are stories. No one believes a man is one.
onto_resurrection,ontology,,raised the dead|back from the dead|resurrect,0,0,impossible,The dead stay dead.
onto_magic,ontology,,cast a spell|sorcery|enchanted|immortal,0,0,impossible,This court has no working magic.
era_gunpowder,era,,cannon|gunpowder|musket|rifle,0,0,impossible,Anachronism: no gunpowder in this age.
era_optics,era,,telescope|microscope|printing press,0,0,impossible,Anachronism: not yet invented.
mag_army,magnitude,army_size,,0,40000,impossible,"A realm of this age fields thousands, never millions."
mag_treasury,magnitude,treasury,,0,100000,impossible,Coin beyond this scale is not credible.
mag_grain,magnitude,grain,,0,5000,impossible,No granary in the realm holds this much.
```

- [ ] **Step 3: Write the failing test**

Create `tests/engine/test_world_rules.gd`:

```gdscript
extends GutTest
## The deterministic floor that overrides any model verdict (spec D8).

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_data_loads() -> void:
	assert_gte(data.world_rules.size(), 8, "world rules loaded")
	assert_true(data.claim_types.has("army_size"), "claim taxonomy loaded")

func test_ontology_claim_is_vetoed() -> void:
	var v := WorldRules.veto(data, "identity", "I am a dragon", 0.0)
	assert_true(v["vetoed"])
	assert_eq(String(v["rule_code"]), "onto_dragon")
	assert_ne(String(v["reason"]), "", "veto carries a reason")

func test_ontology_match_is_case_insensitive() -> void:
	assert_true(WorldRules.veto(data, "identity", "I AM A DRAGON", 0.0)["vetoed"])

func test_magnitude_beyond_bound_is_vetoed() -> void:
	var v := WorldRules.veto(data, "army_size", "I command a great host", 100000000.0)
	assert_true(v["vetoed"])
	assert_eq(String(v["rule_code"]), "mag_army")

func test_magnitude_within_bound_passes() -> void:
	assert_false(WorldRules.veto(data, "army_size", "I command eight thousand", 8000.0)["vetoed"])

func test_plausible_claim_is_not_vetoed() -> void:
	var v := WorldRules.veto(data, "event_report", "The granary is full", 0.0)
	assert_false(v["vetoed"])
	assert_eq(String(v["rule_code"]), "")

func test_magnitude_rule_ignores_other_claim_types() -> void:
	# A huge number in a claim type with no magnitude rule must pass.
	assert_false(WorldRules.veto(data, "intent", "I mean to build much", 100000000.0)["vetoed"])
```

- [ ] **Step 4: Run tests and verify they fail**

Run: `./run_tests.sh`
Expected: FAIL — `WorldRules` is not declared, and `data.world_rules` does not exist.

- [ ] **Step 5: Load the new CSVs in the repository**

In `scripts/engine/data_repository.gd`, add to the member declarations near `var relationships`:

```gdscript
var world_rules: Dictionary = {}
var claim_types: Dictionary = {}
```

And in `_load`, immediately before the `regions.csv` block:

```gdscript
	if not _load_if_present(dir + "/world_rules.csv",
			["rule_code", "kind", "verdict"],
			func(r): world_rules[r["rule_code"]] = r):
		return false
	if not _load_if_present(dir + "/claim_types.csv", ["claim_type", "label"],
			func(r): claim_types[r["claim_type"]] = r):
		return false
```

- [ ] **Step 6: Implement WorldRules**

Create `scripts/engine/world_rules.gd`:

```gdscript
class_name WorldRules
extends RefCounted
## The deterministic impossibility floor (spec D8). Whatever plausibility a
## model returns, a claim matching an `impossible` rule is worth nothing.
## Pure, no RNG, no Nodes: the one part of credibility a player cannot argue
## with, because no model is consulted.

## Returns {"vetoed": bool, "rule_code": String, "reason": String}.
## `magnitude` is the claim's numeric size where one applies (army size, gold);
## pass 0.0 for claims that carry no number.
static func veto(data: DataRepository, claim_type: String, text: String,
		magnitude: float) -> Dictionary:
	var lowered := text.to_lower()
	for code in data.world_rules:
		var row: Dictionary = data.world_rules[code]
		if String(row["verdict"]) != "impossible":
			continue
		if _matches(row, claim_type, lowered, magnitude):
			return {"vetoed": true, "rule_code": String(code),
				"reason": String(row.get("notes", ""))}
	return {"vetoed": false, "rule_code": "", "reason": ""}

static func _matches(row: Dictionary, claim_type: String, lowered_text: String,
		magnitude: float) -> bool:
	var kind := String(row["kind"])
	if kind == "magnitude":
		if String(row.get("claim_type", "")) != claim_type:
			return false
		return magnitude < float(row["bound_min"]) or magnitude > float(row["bound_max"])
	# ontology and era rules match on substrings of the claim text.
	var row_type := String(row.get("claim_type", ""))
	if row_type != "" and row_type != claim_type:
		return false
	for needle in String(row.get("pattern", "")).split("|", false):
		if String(needle).strip_edges() != "" and lowered_text.contains(String(needle)):
			return true
	return false
```

- [ ] **Step 7: Run tests and verify they pass**

Run: `./run_tests.sh`
Expected: PASS. Confirm the `Scripts` count rose by one and `Errors` is still `2`.

- [ ] **Step 8: Commit**

```bash
git add data/world_rules.csv data/claim_types.csv scripts/engine/world_rules.gd tests/engine/test_world_rules.gd scripts/engine/data_repository.gd
git commit -m "feat(knowledge): deterministic world-rule impossibility floor"
```

---

### Task 2: Facts and the knowledge base

**Files:**
- Create: `data/facts.csv`, `scripts/engine/knowledge.gd`
- Modify: `scripts/engine/data_repository.gd`, `scripts/engine/game_state.gd`
- Test: `tests/engine/test_knowledge.gd`

**Interfaces:**
- Consumes: `DataRepository._load_if_present`; `GameState.new_campaign`.
- Produces: `DataRepository.facts: Array[Dictionary]`; `GameState.knowledge: Dictionary`; and on `KnowledgeBase`: `init_from_data(data, state) -> Dictionary`, `knows(state, char_id, fact_code) -> bool`, `credibility_of(state, char_id, fact_code) -> float`, `learn(state, char_id, fact_code, credibility) -> void`, `add_fact(state, fact_code, fields) -> void`, `known_facts(state, char_id) -> Array`, `facts_about(state, char_id, claim_type, subject) -> Array`.

Stored shape, per fact code, in `GameState.knowledge`:

```gdscript
{"kind": String, "subject": String, "claim_type": String, "text": String,
 "truth": bool, "knowers": Array, "credibility": Dictionary}
```

Text and truth live in state rather than only in the CSV because the reckoning creates facts at runtime that were never authored (Task 6).

- [ ] **Step 1: Create the seed facts**

Create `data/facts.csv`. `initial_knowers` is `|`-separated character ids, or the sentinel `ALL` for common sense.

```csv
fact_code,kind,subject,claim_type,text,truth,base_credibility,initial_knowers,notes
common_dragons,common_sense,world,identity,Dragons do not exist.,true,100,ALL,Common sense is known by everyone and never decays.
common_dead,common_sense,world,event_report,The dead do not return.,true,100,ALL,Common sense.
common_army_scale,common_sense,world,army_size,A great realm fields thousands of soldiers.,true,100,ALL,Anchors magnitude intuition.
fact_chancellor_graft,secret,char_chancellor,loyalty,The Chancellor has skimmed the treasury for years.,true,80,char_steward|char_spymaster,Mirella holds the ledger; Quill keeps the file.
fact_tomas_claim,public,char_duke_tomas,intent,Duke Tomas covets the throne.,true,90,you|char_chancellor|char_marshal|char_steward|char_spymaster|char_chaplain|char_lord_malvern|char_lady_corina,An open secret per game_start.md.
fact_malvern_dying,secret,char_lord_malvern,event_report,Lord Malvern's health is failing badly.,true,70,you|char_lord_malvern|char_chaplain,He hides how bad it is.
fact_food_shortage,public,realm,grain,The realm's granaries are running short.,true,85,you|char_chancellor|char_steward|char_chaplain|char_prophet_cassian|char_guildmaster_tessa,Unrest is beginning.
fact_doncaster_muster,secret,doncaster,army_size,Doncaster is massing for a raid southward.,true,60,char_spymaster|char_marshal,Quill's scouts brought word.
fact_bentleigh_puppet,public,char_emperor,intent,Queen Isabeau rules the Emperor as a puppet.,true,75,you|char_chancellor|char_envoy_petra,Widely known at court.
```

- [ ] **Step 2: Write the failing test**

Create `tests/engine/test_knowledge.gd`:

```gdscript
extends GutTest
## Per-character knowledge (spec D5): facts carry knower lists, so who knows
## what is the engine's business, never the model's.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)

func test_seed_facts_load_into_state() -> void:
	assert_gte(state.knowledge.size(), 9, "seed facts present")
	assert_true(state.knowledge.has("fact_chancellor_graft"))

func test_every_seed_knower_exists_in_the_roster() -> void:
	for code in state.knowledge:
		for id in state.knowledge[code]["knowers"]:
			assert_true(state.characters.has(String(id)),
				"%s knower %s is a real character" % [code, id])

func test_secret_is_known_only_to_its_knowers() -> void:
	assert_true(KnowledgeBase.knows(state, "char_steward", "fact_chancellor_graft"))
	assert_true(KnowledgeBase.knows(state, "char_spymaster", "fact_chancellor_graft"))
	assert_false(KnowledgeBase.knows(state, "char_marshal", "fact_chancellor_graft"),
		"the Marshal has not heard about the graft")
	assert_false(KnowledgeBase.knows(state, "you", "fact_chancellor_graft"),
		"nor has the king — this is the plot")

func test_common_sense_is_known_by_everyone_at_full_credibility() -> void:
	for id in state.characters:
		assert_true(KnowledgeBase.knows(state, String(id), "common_dragons"),
			String(id) + " has common sense")
		assert_eq(KnowledgeBase.credibility_of(state, String(id), "common_dragons"), 100.0)

func test_learn_adds_a_knower_at_the_given_credibility() -> void:
	KnowledgeBase.learn(state, "char_marshal", "fact_chancellor_graft", 42.0)
	assert_true(KnowledgeBase.knows(state, "char_marshal", "fact_chancellor_graft"))
	assert_eq(KnowledgeBase.credibility_of(state, "char_marshal", "fact_chancellor_graft"), 42.0)
	# Learning again does not duplicate the knower.
	KnowledgeBase.learn(state, "char_marshal", "fact_chancellor_graft", 50.0)
	assert_eq(state.knowledge["fact_chancellor_graft"]["knowers"].count("char_marshal"), 1)

func test_credibility_of_unknown_fact_is_zero() -> void:
	assert_eq(KnowledgeBase.credibility_of(state, "char_marshal", "fact_chancellor_graft"), 0.0)

func test_add_fact_creates_a_runtime_fact() -> void:
	KnowledgeBase.add_fact(state, "fact_test_lie", {
		"kind": "secret", "subject": "you", "claim_type": "loyalty",
		"text": "The king lied about the granaries.", "truth": true})
	KnowledgeBase.learn(state, "char_chaplain", "fact_test_lie", 90.0)
	assert_true(KnowledgeBase.knows(state, "char_chaplain", "fact_test_lie"))
	assert_eq(String(state.knowledge["fact_test_lie"]["text"]),
		"The king lied about the granaries.")

func test_facts_about_filters_by_type_and_subject_for_one_knower() -> void:
	var found := KnowledgeBase.facts_about(state, "char_spymaster", "army_size", "doncaster")
	assert_eq(found.size(), 1)
	assert_eq(String(found[0]["code"]), "fact_doncaster_muster")
	assert_eq(KnowledgeBase.facts_about(state, "char_chaplain", "army_size", "doncaster").size(), 0,
		"the chaplain knows nothing of Doncaster's muster")

func test_knowledge_survives_save_round_trip() -> void:
	KnowledgeBase.learn(state, "char_marshal", "fact_chancellor_graft", 42.0)
	var restored := GameState.from_dict(state.to_dict())
	assert_true(KnowledgeBase.knows(restored, "char_marshal", "fact_chancellor_graft"))
	assert_eq(KnowledgeBase.credibility_of(restored, "char_marshal", "fact_chancellor_graft"), 42.0)
	assert_eq(bool(restored.knowledge["fact_chancellor_graft"]["truth"]), true)

func test_pre_feature_save_loads_with_empty_knowledge() -> void:
	var d := state.to_dict()
	d.erase("knowledge")
	var restored := GameState.from_dict(d)
	assert_not_null(restored, "old saves are not refused")
	assert_eq(restored.knowledge.size(), 0)
```

- [ ] **Step 3: Run tests and verify they fail**

Run: `./run_tests.sh`
Expected: FAIL — `KnowledgeBase` not declared, `state.knowledge` missing.

- [ ] **Step 4: Load facts.csv**

In `scripts/engine/data_repository.gd`, add near the other members:

```gdscript
var facts: Array[Dictionary] = []
```

And in `_load`, after the `claim_types.csv` block:

```gdscript
	if not _load_if_present(dir + "/facts.csv",
			["fact_code", "kind", "subject", "claim_type", "text", "truth"],
			func(r): facts.append(r)):
		return false
```

- [ ] **Step 5: Implement KnowledgeBase**

Create `scripts/engine/knowledge.gd`:

```gdscript
class_name KnowledgeBase
extends RefCounted
## Facts and who knows them (spec D5). Knowledge is per-character: a secret
## exists as one fact with a knower list, never as a copy per person.
## Deterministic, no RNG, no Nodes.
##
## GameState.knowledge maps fact_code to:
##   {"kind": public|secret|rumor|common_sense, "subject": String,
##    "claim_type": String, "text": String, "truth": bool,
##    "knowers": Array[String], "credibility": {char_id: float}}
##
## text/truth are stored in state, not read back from CSV, because the
## reckoning (ClaimLedger) creates facts at runtime that no CSV authored.

const ALL_KNOWERS := "ALL"

## Builds the starting knowledge from data/facts.csv. The ALL sentinel in
## initial_knowers seeds a fact to every character in the roster.
static func init_from_data(data: DataRepository, state: GameState) -> Dictionary:
	var out: Dictionary = {}
	for row in data.facts:
		var code := String(row["fact_code"])
		var credit: float = float(row.get("base_credibility", 50))
		var knowers: Array = []
		var credibility: Dictionary = {}
		var raw := String(row.get("initial_knowers", ""))
		var ids: Array = state.characters.keys() if raw == ALL_KNOWERS \
			else Array(raw.split("|", false))
		for id in ids:
			var char_id := String(id)
			if not state.characters.has(char_id):
				continue
			knowers.append(char_id)
			credibility[char_id] = credit
		out[code] = {
			"kind": String(row["kind"]), "subject": String(row["subject"]),
			"claim_type": String(row["claim_type"]), "text": String(row["text"]),
			"truth": String(row["truth"]).to_lower() == "true",
			"knowers": knowers, "credibility": credibility,
		}
	return out

static func knows(state: GameState, char_id: String, fact_code: String) -> bool:
	if not state.knowledge.has(fact_code):
		return false
	return char_id in state.knowledge[fact_code]["knowers"]

## This character's credibility for a fact; 0.0 when they do not know it.
static func credibility_of(state: GameState, char_id: String, fact_code: String) -> float:
	if not knows(state, char_id, fact_code):
		return 0.0
	return float(state.knowledge[fact_code]["credibility"].get(char_id, 0.0))

## Teaches a character a fact at a credibility. Idempotent on the knower list;
## a repeat call updates credibility without duplicating the knower.
static func learn(state: GameState, char_id: String, fact_code: String,
		credibility: float) -> void:
	if not state.knowledge.has(fact_code):
		return
	var fact: Dictionary = state.knowledge[fact_code]
	if not char_id in fact["knowers"]:
		fact["knowers"].append(char_id)
	fact["credibility"][char_id] = clampf(credibility, 0.0, 100.0)

## Creates a fact at runtime (the reckoning's betrayal facts). No knowers
## until learn() is called.
static func add_fact(state: GameState, fact_code: String, fields: Dictionary) -> void:
	state.knowledge[fact_code] = {
		"kind": String(fields.get("kind", "secret")),
		"subject": String(fields.get("subject", "")),
		"claim_type": String(fields.get("claim_type", "")),
		"text": String(fields.get("text", "")),
		"truth": bool(fields.get("truth", true)),
		"knowers": [], "credibility": {},
	}

## Every fact this character knows, each as the stored fact plus its "code".
static func known_facts(state: GameState, char_id: String) -> Array:
	var out: Array = []
	for code in state.knowledge:
		if knows(state, char_id, String(code)):
			var entry: Dictionary = state.knowledge[code].duplicate(true)
			entry["code"] = String(code)
			out.append(entry)
	return out

## Known facts narrowed to one claim_type and subject — the corroboration
## lookup used by Belief.
static func facts_about(state: GameState, char_id: String, claim_type: String,
		subject: String) -> Array:
	var out: Array = []
	for entry in known_facts(state, char_id):
		if String(entry["claim_type"]) == claim_type and String(entry["subject"]) == subject:
			out.append(entry)
	return out
```

- [ ] **Step 6: Wire knowledge into GameState**

In `scripts/engine/game_state.gd`, add after the `relationships` declaration:

```gdscript
## Facts and who knows them; shape and API in KnowledgeBase.
var knowledge: Dictionary = {}
```

In `new_campaign`, after `s.relationships = RelationshipGraph.init_from_data(data)`:

```gdscript
	s.knowledge = KnowledgeBase.init_from_data(data, s)
```

In `to_dict`, beside the relationships entry:

```gdscript
		"knowledge": _encode_values(knowledge.duplicate(true)),
```

In `from_dict`, beside the relationships line:

```gdscript
	s.knowledge = _decode_values(d.get("knowledge", {}))
```

Note `_encode_values` turns the `truth` booleans into… nothing: booleans pass through untouched (only ints and floats are hex-encoded), so `truth` round-trips as a real bool. Credibility floats are hex-encoded and come back bit-exact.

- [ ] **Step 7: Run tests and verify they pass**

Run: `./run_tests.sh`
Expected: PASS, `Scripts` up by one, `Errors 2`.

- [ ] **Step 8: Commit**

```bash
git add data/facts.csv scripts/engine/knowledge.gd tests/engine/test_knowledge.gd scripts/engine/data_repository.gd scripts/engine/game_state.gd
git commit -m "feat(knowledge): per-character facts with knower lists"
```

---

### Task 3: Source trust

**Files:**
- Create: `scripts/engine/source_trust.gd`
- Modify: `scripts/engine/game_state.gd`, `data/balance.csv`
- Test: `tests/engine/test_source_trust.gd`

**Interfaces:**
- Consumes: `RelationshipGraph.edge`, `GameState.relationships`, `DataRepository.bal`.
- Produces: `GameState.source_trust: Dictionary`; on `SourceTrust`: `key(speaker, listener) -> String`, `init_from_relationships(data, state) -> Dictionary`, `get_trust(data, state, speaker, listener) -> float`, `adjust(data, state, speaker, listener, delta, reason, tick) -> void`.

Stored per key `"speaker>listener"`: `{"value": float, "log": Array}`.

- [ ] **Step 1: Add the balance key**

Append to `data/balance.csv`:

```csv
source_trust_default,50,trust in a speaker with no relationship edge to the listener
```

- [ ] **Step 2: Write the failing test**

Create `tests/engine/test_source_trust.gd`:

```gdscript
extends GutTest
## Directed speaker->listener trust (spec §4.3). Derived from relationships at
## campaign start, then moved only by the reckoning, so it stays auditable.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)

func test_trust_is_derived_from_how_the_listener_feels_about_the_speaker() -> void:
	# Malvern feels +75 toward the king (liege), so he trusts the king's word:
	# 50 + 75/2 = 87.5
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_lord_malvern"),
		87.5, 0.001)
	# Duke Tomas feels -45 toward the king: 50 + (-45)/2 = 27.5
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_duke_tomas"),
		27.5, 0.001)

func test_trust_is_directional() -> void:
	# The king's own feeling toward Tomas (-35) governs the other direction:
	# 50 + (-35)/2 = 32.5
	assert_almost_eq(SourceTrust.get_trust(data, state, "char_duke_tomas", "you"),
		32.5, 0.001)

func test_pair_with_no_edge_uses_the_default() -> void:
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_bard_corvin"),
		50.0, 0.001)

func test_adjust_clamps_and_logs_a_reason() -> void:
	SourceTrust.adjust(data, state, "you", "char_lord_malvern", -25.0, "caught in a lie", 7)
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_lord_malvern"),
		62.5, 0.001)
	var entry: Dictionary = state.source_trust[SourceTrust.key("you", "char_lord_malvern")]
	var last: Dictionary = entry["log"][entry["log"].size() - 1]
	assert_eq(String(last["reason"]), "caught in a lie")
	assert_eq(int(last["tick"]), 7)
	SourceTrust.adjust(data, state, "you", "char_lord_malvern", -999.0, "utter ruin", 8)
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_lord_malvern"),
		0.0, 0.001)

func test_adjust_on_an_underived_pair_starts_from_default() -> void:
	SourceTrust.adjust(data, state, "you", "char_bard_corvin", 10.0, "a kindness", 3)
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_bard_corvin"),
		60.0, 0.001)

func test_trust_survives_save_round_trip() -> void:
	SourceTrust.adjust(data, state, "you", "char_lord_malvern", -25.0, "caught in a lie", 7)
	var restored := GameState.from_dict(state.to_dict())
	assert_almost_eq(SourceTrust.get_trust(data, restored, "you", "char_lord_malvern"),
		62.5, 0.001)

func test_pre_feature_save_falls_back_to_derivation() -> void:
	var d := state.to_dict()
	d.erase("source_trust")
	var restored := GameState.from_dict(d)
	assert_not_null(restored)
	assert_almost_eq(SourceTrust.get_trust(data, restored, "you", "char_lord_malvern"),
		87.5, 0.001, "derivation still works from relationships alone")
```

- [ ] **Step 3: Run tests and verify they fail**

Run: `./run_tests.sh`
Expected: FAIL — `SourceTrust` not declared.

- [ ] **Step 4: Implement SourceTrust**

Create `scripts/engine/source_trust.gd`:

```gdscript
class_name SourceTrust
extends RefCounted
## How much one character's word is worth to another (spec §4.3). Directed:
## trust in A as a source, held by B. Derived from the listener's sentiment
## toward the speaker at campaign start, then moved only by the reckoning
## (ClaimLedger), so every change carries a reason.
##
## GameState.source_trust maps "speaker>listener" to
##   {"value": float 0..100, "log": [{"tick", "delta", "reason"}]}
## An absent key is not an error: get_trust derives it on demand, which keeps
## the save small and lets pre-feature saves work untouched.

static func key(speaker: String, listener: String) -> String:
	return speaker + ">" + listener

## Derivation: a listener trusts a speaker in proportion to how they feel
## about them. clamp(50 + sentiment(listener -> speaker) / 2, 0, 100).
static func derive(data: DataRepository, state: GameState, speaker: String,
		listener: String) -> float:
	var base := data.bal("source_trust_default")
	var edge := RelationshipGraph.edge(state, listener, speaker)
	if edge.is_empty():
		return base
	return clampf(base + float(edge["sentiment"]) / 2.0, 0.0, 100.0)

## Seeds every derived pair. Optional — get_trust derives on demand — but a
## campaign calls it so the opening values are visible in the save.
static func init_from_relationships(data: DataRepository, state: GameState) -> Dictionary:
	var out: Dictionary = {}
	for e in state.relationships:
		var speaker := String(e["to"])
		var listener := String(e["from"])
		out[key(speaker, listener)] = {
			"value": derive(data, state, speaker, listener), "log": [],
		}
	return out

static func get_trust(data: DataRepository, state: GameState, speaker: String,
		listener: String) -> float:
	var k := key(speaker, listener)
	if state.source_trust.has(k):
		return float(state.source_trust[k]["value"])
	return derive(data, state, speaker, listener)

## Moves trust and logs why. A reason is mandatory, same rule as
## Character.change_opinion and RelationshipGraph.adjust.
static func adjust(data: DataRepository, state: GameState, speaker: String,
		listener: String, delta: float, reason: String, tick: int) -> void:
	assert(reason != "", "source trust change requires a reason")
	var k := key(speaker, listener)
	if not state.source_trust.has(k):
		# Seed from the same derivation get_trust would have returned for this
		# pair, so the two can never disagree — including after a designer
		# retunes source_trust_default in balance.csv.
		state.source_trust[k] = {
			"value": derive(data, state, speaker, listener), "log": [],
		}
	var entry: Dictionary = state.source_trust[k]
	entry["value"] = clampf(float(entry["value"]) + delta, 0.0, 100.0)
	entry["log"].append({"tick": tick, "delta": delta, "reason": reason})
```

`adjust` takes `data` so its seed for an unseeded pair comes from `derive`,
never a literal. Not every pair is seeded: `init_from_relationships` only
covers pairs that have a relationship edge, and characters like
`char_bard_corvin` have none — so this path is reachable, and a hardcoded
default here would silently diverge from `balance.csv` the moment
`source_trust_default` is tuned.

- [ ] **Step 5: Wire into GameState**

In `scripts/engine/game_state.gd`, after the `knowledge` declaration:

```gdscript
## "speaker>listener" -> {"value", "log"}; API in SourceTrust.
var source_trust: Dictionary = {}
```

In `new_campaign`, after the knowledge line:

```gdscript
	s.source_trust = SourceTrust.init_from_relationships(data, s)
```

In `to_dict`:

```gdscript
		"source_trust": _encode_values(source_trust.duplicate(true)),
```

In `from_dict`:

```gdscript
	s.source_trust = _decode_values(d.get("source_trust", {}))
```

- [ ] **Step 6: Run tests and verify they pass**

Run: `./run_tests.sh`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add scripts/engine/source_trust.gd tests/engine/test_source_trust.gd scripts/engine/game_state.gd data/balance.csv
git commit -m "feat(knowledge): directed source trust derived from relationships"
```

---

### Task 4: Belief scoring

**Files:**
- Create: `scripts/engine/belief.gd`
- Modify: `data/balance.csv`
- Test: `tests/engine/test_belief.gd`

**Interfaces:**
- Consumes: `WorldRules.veto`, `SourceTrust.get_trust`, `KnowledgeBase.facts_about`, `Character.traits`.
- Produces: `Belief.score(data, state, listener, speaker, claim, plausibility) -> Dictionary` where `claim` is `{"claim_type", "subject", "text", "magnitude", "truth"}` and the result is `{"belief": float, "vetoed": bool, "rule_code": String, "corroboration": int, "reason": String}`.

Formula, in order: an impossible claim scores 0. Otherwise
`belief = clamp(plausibility * (trust / 100) + trait_mod + corroboration * bonus, 0, 100)`
where corroboration counts the listener's known facts sharing the claim's type and subject, `+1` each when their truth agrees with the claim's and `-1` each when it does not.

- [ ] **Step 1: Add the balance keys**

Append to `data/balance.csv`:

```csv
belief_threshold,55,claims at or above this belief are swallowed as fact
belief_corroboration_bonus,8,per agreeing fact the listener already knows; also the penalty per contradicting fact
belief_trait_paranoid,-10,paranoid listeners discount every claim
belief_trait_trusting,10,trusting listeners inflate every claim
```

- [ ] **Step 2: Write the failing test**

Create `tests/engine/test_belief.gd`:

```gdscript
extends GutTest
## Belief scoring (spec §2.1, §5 node 2). Plausibility comes from outside;
## this unit is the engine half that turns it into a number, so every value
## below is hand-computed.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)

func _claim(claim_type: String, subject: String, text: String,
		magnitude: float, truth: bool) -> Dictionary:
	return {"claim_type": claim_type, "subject": subject, "text": text,
		"magnitude": magnitude, "truth": truth}

func test_impossible_claim_scores_zero_whatever_the_plausibility() -> void:
	var c := _claim("identity", "you", "I am a dragon", 0.0, false)
	var r := Belief.score(data, state, "char_lord_malvern", "you", c, 100.0)
	assert_eq(float(r["belief"]), 0.0, "the floor overrides any plausibility")
	assert_true(bool(r["vetoed"]))
	assert_eq(String(r["rule_code"]), "onto_dragon")

func test_trusted_listener_believes_a_plausible_claim() -> void:
	# Malvern's trust in the king is 87.5, he has no belief traits, and knows
	# nothing about grain stores in "eastmarch": 80 * 0.875 = 70.0
	var c := _claim("grain", "eastmarch", "The eastmarch granaries are full", 400.0, true)
	var r := Belief.score(data, state, "char_lord_malvern", "you", c, 80.0)
	assert_almost_eq(float(r["belief"]), 70.0, 0.001)
	assert_eq(int(r["corroboration"]), 0)

func test_paranoid_listener_discounts_the_same_claim() -> void:
	# Quill is paranoid and has no edge toward the king, so trust is the
	# default 50: 80 * 0.5 = 40.0, minus 10 for paranoia = 30.0
	var c := _claim("grain", "eastmarch", "The eastmarch granaries are full", 400.0, true)
	var r := Belief.score(data, state, "char_spymaster", "you", c, 80.0)
	assert_almost_eq(float(r["belief"]), 30.0, 0.001)

func test_corroboration_raises_belief() -> void:
	# Quill knows fact_doncaster_muster (army_size / doncaster, truth true).
	# An agreeing claim: 80 * 0.5 = 40.0, -10 paranoid, +8 corroboration = 38.0
	var c := _claim("army_size", "doncaster", "Doncaster masses for a raid", 9000.0, true)
	var r := Belief.score(data, state, "char_spymaster", "you", c, 80.0)
	assert_eq(int(r["corroboration"]), 1)
	assert_almost_eq(float(r["belief"]), 38.0, 0.001)

func test_contradiction_lowers_belief() -> void:
	# Same known fact, but the claim asserts the opposite: 40.0 - 10 - 8 = 22.0
	var c := _claim("army_size", "doncaster", "Doncaster is at peace", 0.0, false)
	var r := Belief.score(data, state, "char_spymaster", "you", c, 80.0)
	assert_eq(int(r["corroboration"]), -1)
	assert_almost_eq(float(r["belief"]), 22.0, 0.001)

func test_belief_is_clamped_to_the_range() -> void:
	var c := _claim("grain", "eastmarch", "The granaries are full", 400.0, true)
	var high := Belief.score(data, state, "char_lord_malvern", "you", c, 100.0)
	assert_lte(float(high["belief"]), 100.0)
	var low := Belief.score(data, state, "char_spymaster", "you", c, 0.0)
	assert_gte(float(low["belief"]), 0.0)

func test_result_always_carries_a_reason() -> void:
	var c := _claim("grain", "eastmarch", "The granaries are full", 400.0, true)
	assert_ne(String(Belief.score(data, state, "char_lord_malvern", "you", c, 80.0)["reason"]), "")
```

- [ ] **Step 3: Run tests and verify they fail**

Run: `./run_tests.sh`
Expected: FAIL — `Belief` not declared.

- [ ] **Step 4: Implement Belief**

Create `scripts/engine/belief.gd`:

```gdscript
class_name Belief
extends RefCounted
## Turns an externally supplied plausibility into this listener's belief
## (spec §2.1). The model may judge how credible a claim sounds in the
## abstract; who is speaking, who is listening, and what they already know
## are engine business, so relationship maths stays testable and a model can
## never adjudicate its own trust with the player.
##
## Pure and deterministic: no RNG, no Nodes, no state mutation.

## `claim`: {"claim_type", "subject", "text", "magnitude", "truth"}.
## `plausibility`: 0..100 from the judge (or a test).
## Returns {"belief", "vetoed", "rule_code", "corroboration", "reason"}.
static func score(data: DataRepository, state: GameState, listener: String,
		speaker: String, claim: Dictionary, plausibility: float) -> Dictionary:
	var veto := WorldRules.veto(data, String(claim["claim_type"]),
		String(claim["text"]), float(claim.get("magnitude", 0.0)))
	if bool(veto["vetoed"]):
		return {"belief": 0.0, "vetoed": true,
			"rule_code": String(veto["rule_code"]), "corroboration": 0,
			"reason": "impossible on its face: " + String(veto["reason"])}
	var trust := SourceTrust.get_trust(data, state, speaker, listener)
	var corroboration := _corroboration(state, listener, claim)
	var trait_mod := _trait_modifier(data, state, listener)
	var raw := plausibility * (trust / 100.0) \
		+ trait_mod \
		+ float(corroboration) * data.bal("belief_corroboration_bonus")
	return {
		"belief": clampf(raw, 0.0, 100.0), "vetoed": false, "rule_code": "",
		"corroboration": corroboration,
		"reason": "plausibility %d, trust %d, corroboration %d" % [
			int(plausibility), int(trust), corroboration],
	}

## Net count of the listener's known facts on the same claim_type and subject:
## +1 each when their truth agrees with the claim, -1 each when it does not.
static func _corroboration(state: GameState, listener: String, claim: Dictionary) -> int:
	var net := 0
	var claim_truth := bool(claim.get("truth", true))
	for fact in KnowledgeBase.facts_about(state, listener,
			String(claim["claim_type"]), String(claim["subject"])):
		net += 1 if bool(fact["truth"]) == claim_truth else -1
	return net

static func _trait_modifier(data: DataRepository, state: GameState, listener: String) -> float:
	if not state.characters.has(listener):
		return 0.0
	var c: Character = state.characters[listener]
	var mod := 0.0
	if "paranoid" in c.traits:
		mod += data.bal("belief_trait_paranoid")
	if "trusting" in c.traits:
		mod += data.bal("belief_trait_trusting")
	return mod
```

- [ ] **Step 5: Run tests and verify they pass**

Run: `./run_tests.sh`
Expected: PASS. If a hand-computed value is off, check the relationship sentiments in `data/relationships.csv` before changing the formula — the test values are derived from them.

- [ ] **Step 6: Commit**

```bash
git add scripts/engine/belief.gd tests/engine/test_belief.gd data/balance.csv
git commit -m "feat(knowledge): belief scoring from plausibility, trust, traits, corroboration"
```

---

### Task 5: The claim ledger

**Files:**
- Create: `scripts/engine/claims.gd`
- Modify: `scripts/engine/game_state.gd`
- Test: `tests/engine/test_claims.gd`

**Interfaces:**
- Consumes: `Belief.score`, `KnowledgeBase.add_fact`, `KnowledgeBase.learn`, `DataRepository.bal`.
- Produces: `GameState.claims: Array`; on `ClaimLedger`: `record(data, state, claimant, listener, claim, plausibility, tick) -> Dictionary` and `open_claims(state) -> Array`.

Claim record shape:

```gdscript
{"claimant": String, "listener": String, "claim_type": String,
 "subject": String, "text": String, "truth": bool, "belief": float,
 "believed": bool, "tick": int, "status": "open"|"disbelieved"|"kept"|"caught",
 "fact_code": String}
```

A believed claim becomes a fact the listener knows, so a swallowed lie behaves exactly like knowledge until reality contradicts it (spec §6).

- [ ] **Step 1: Write the failing test**

Create `tests/engine/test_claims.gd`:

```gdscript
extends GutTest
## Recording claims (spec §6, "Telling"). Resolution is Task 6.

var data: DataRepository
var state: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	state = GameState.new_campaign(data, 42)

func _claim(claim_type: String, subject: String, text: String,
		magnitude: float, truth: bool) -> Dictionary:
	return {"claim_type": claim_type, "subject": subject, "text": text,
		"magnitude": magnitude, "truth": truth}

func test_believed_claim_is_recorded_open_and_becomes_a_known_fact() -> void:
	# Malvern trusts the king at 87.5; plausibility 90 gives 78.75, over the
	# belief_threshold of 55.
	var c := _claim("grain", "eastmarch", "The eastmarch granaries are full", 400.0, false)
	var rec := ClaimLedger.record(data, state, "you", "char_lord_malvern", c, 90.0, 4)
	assert_true(bool(rec["believed"]))
	assert_eq(String(rec["status"]), "open")
	assert_eq(state.claims.size(), 1)
	assert_ne(String(rec["fact_code"]), "", "a believed claim creates a fact")
	assert_true(KnowledgeBase.knows(state, "char_lord_malvern", String(rec["fact_code"])),
		"the listener now knows the thing he was told")
	assert_almost_eq(KnowledgeBase.credibility_of(state, "char_lord_malvern",
		String(rec["fact_code"])), 78.75, 0.001)

func test_disbelieved_claim_is_recorded_but_teaches_nothing() -> void:
	# Quill has no edge toward the king (trust 50) and is paranoid (-10):
	# 80 * 0.50 - 10 = 30, under the belief_threshold of 55.
	var c := _claim("grain", "eastmarch", "The eastmarch granaries are full", 400.0, false)
	var rec := ClaimLedger.record(data, state, "you", "char_spymaster", c, 80.0, 4)
	assert_false(bool(rec["believed"]))
	assert_eq(String(rec["status"]), "disbelieved")
	assert_eq(String(rec["fact_code"]), "", "nothing is learned")
	assert_eq(KnowledgeBase.known_facts(state, "char_spymaster").filter(
		func(f): return String(f["subject"]) == "eastmarch").size(), 0)

func test_impossible_claim_is_disbelieved_and_never_open() -> void:
	var c := _claim("identity", "you", "I am a dragon", 0.0, false)
	var rec := ClaimLedger.record(data, state, "you", "char_lord_malvern", c, 100.0, 4)
	assert_false(bool(rec["believed"]))
	assert_eq(String(rec["status"]), "disbelieved")
	assert_eq(ClaimLedger.open_claims(state).size(), 0)

func test_claim_stores_ground_truth_the_listener_cannot_see() -> void:
	var c := _claim("grain", "eastmarch", "The granaries are full", 400.0, false)
	var rec := ClaimLedger.record(data, state, "you", "char_lord_malvern", c, 90.0, 4)
	assert_false(bool(rec["truth"]), "the engine records that this was a lie")

func test_open_claims_lists_only_believed_unresolved_ones() -> void:
	var lie := _claim("grain", "eastmarch", "The granaries are full", 400.0, false)
	ClaimLedger.record(data, state, "you", "char_lord_malvern", lie, 90.0, 4)
	ClaimLedger.record(data, state, "you", "char_spymaster", lie, 80.0, 4)
	assert_eq(ClaimLedger.open_claims(state).size(), 1)

func test_fact_codes_are_unique_across_claims() -> void:
	var c := _claim("grain", "eastmarch", "The granaries are full", 400.0, false)
	var a := ClaimLedger.record(data, state, "you", "char_lord_malvern", c, 90.0, 4)
	var b := ClaimLedger.record(data, state, "you", "char_chaplain", c, 90.0, 5)
	assert_ne(String(a["fact_code"]), String(b["fact_code"]))

func test_claims_survive_save_round_trip() -> void:
	var c := _claim("grain", "eastmarch", "The granaries are full", 400.0, false)
	ClaimLedger.record(data, state, "you", "char_lord_malvern", c, 90.0, 4)
	var restored := GameState.from_dict(state.to_dict())
	assert_eq(restored.claims.size(), 1)
	assert_eq(String(restored.claims[0]["listener"]), "char_lord_malvern")
	assert_false(bool(restored.claims[0]["truth"]))

func test_pre_feature_save_loads_with_no_claims() -> void:
	var d := state.to_dict()
	d.erase("claims")
	var restored := GameState.from_dict(d)
	assert_not_null(restored)
	assert_eq(restored.claims.size(), 0)
```

- [ ] **Step 2: Run tests and verify they fail**

Run: `./run_tests.sh`
Expected: FAIL — `ClaimLedger` not declared.

- [ ] **Step 3: Implement recording**

Create `scripts/engine/claims.gd`:

```gdscript
class_name ClaimLedger
extends RefCounted
## Every assertion made to a character, with the engine's ground truth
## attached (spec §6). A believed claim becomes a fact the listener knows, so
## a swallowed lie behaves exactly like knowledge until reality contradicts
## it — at which point resolve_due (Task 6) collects the debt.
##
## Records live in GameState.claims:
##   {"claimant", "listener", "claim_type", "subject", "text", "truth",
##    "belief", "believed", "tick", "status", "fact_code"}
## status: open | disbelieved | kept | caught

const FACT_PREFIX := "claim_"

## Records one claim and, when believed, teaches it to the listener.
## `claim`: {"claim_type", "subject", "text", "magnitude", "truth"}.
static func record(data: DataRepository, state: GameState, claimant: String,
		listener: String, claim: Dictionary, plausibility: float,
		tick: int) -> Dictionary:
	var scored := Belief.score(data, state, listener, claimant, claim, plausibility)
	var belief := float(scored["belief"])
	var believed := belief >= data.bal("belief_threshold")
	var fact_code := ""
	if believed:
		fact_code = "%s%d" % [FACT_PREFIX, state.claims.size()]
		KnowledgeBase.add_fact(state, fact_code, {
			"kind": "rumor", "subject": String(claim["subject"]),
			"claim_type": String(claim["claim_type"]),
			"text": String(claim["text"]), "truth": bool(claim["truth"]),
		})
		KnowledgeBase.learn(state, listener, fact_code, belief)
	var record := {
		"claimant": claimant, "listener": listener,
		"claim_type": String(claim["claim_type"]),
		"subject": String(claim["subject"]), "text": String(claim["text"]),
		"truth": bool(claim["truth"]), "belief": belief, "believed": believed,
		"tick": tick, "status": "open" if believed else "disbelieved",
		"fact_code": fact_code,
	}
	state.claims.append(record)
	return record

## Believed claims still awaiting their reckoning, in record order.
static func open_claims(state: GameState) -> Array:
	var out: Array = []
	for c in state.claims:
		if String(c["status"]) == "open":
			out.append(c)
	return out
```

- [ ] **Step 4: Wire claims into GameState**

In `scripts/engine/game_state.gd`, after the `source_trust` declaration:

```gdscript
## Claim records; shape and API in ClaimLedger.
var claims: Array = []
```

In `to_dict`:

```gdscript
		"claims": _encode_values(claims.duplicate(true)),
```

In `from_dict`:

```gdscript
	s.claims = _decode_values(d.get("claims", []))
```

- [ ] **Step 5: Run tests and verify they pass**

Run: `./run_tests.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/engine/claims.gd tests/engine/test_claims.gd scripts/engine/game_state.gd
git commit -m "feat(deception): claim ledger records assertions with ground truth"
```

---

### Task 6: The reckoning

**Files:**
- Modify: `scripts/engine/claims.gd`, `data/balance.csv`
- Test: `tests/engine/test_claims.gd` (extend)

**Interfaces:**
- Consumes: `SourceTrust.adjust`, `RelationshipGraph.adjust`, `KnowledgeBase`.
- Produces: `ClaimLedger.resolve_due(data, state, tick) -> Array` returning one entry per resolved claim: `{"claim": Dictionary, "status": String, "trust_delta": float, "betrayal_fact": String}`.

A claim resolves when the listener has come to know a *contradicting true fact* — one sharing the claim's `claim_type` and `subject`, whose `truth` is `true`, and which is not the claim's own fact. Truth told raises trust; a lie caught drops trust, costs relationship sentiment with a reason, and mints a betrayal fact the wronged character knows.

- [ ] **Step 1: Add the balance keys**

Append to `data/balance.csv`:

```csv
truth_told_trust_gain,3,source trust gained when a claim is borne out
lie_caught_trust_penalty,25,source trust lost when a lie is exposed
lie_relationship_penalty,12,relationship sentiment lost when a lie is exposed
```

- [ ] **Step 2: Write the failing test**

Append to `tests/engine/test_claims.gd`:

```gdscript
## --- Task 6: the reckoning (spec §6) ---

func _tell_lie_to_malvern() -> Dictionary:
	var lie := _claim("grain", "eastmarch", "The eastmarch granaries are full", 400.0, false)
	return ClaimLedger.record(data, state, "you", "char_lord_malvern", lie, 90.0, 4)

func test_nothing_resolves_while_the_truth_stays_hidden() -> void:
	_tell_lie_to_malvern()
	assert_eq(ClaimLedger.resolve_due(data, state, 5).size(), 0)
	assert_eq(ClaimLedger.open_claims(state).size(), 1)

func test_lie_is_caught_when_the_listener_learns_the_truth() -> void:
	var rec := _tell_lie_to_malvern()
	var trust_before := SourceTrust.get_trust(data, state, "you", "char_lord_malvern")
	# The truth reaches Malvern by some other route.
	KnowledgeBase.add_fact(state, "fact_eastmarch_empty", {
		"kind": "public", "subject": "eastmarch", "claim_type": "grain",
		"text": "The eastmarch granaries stand empty.", "truth": true})
	KnowledgeBase.learn(state, "char_lord_malvern", "fact_eastmarch_empty", 90.0)
	var resolved := ClaimLedger.resolve_due(data, state, 9)
	assert_eq(resolved.size(), 1)
	assert_eq(String(resolved[0]["status"]), "caught")
	assert_eq(String(rec["status"]), "caught", "the stored record is updated in place")
	# Trust drops by lie_caught_trust_penalty (25): 87.5 -> 62.5
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_lord_malvern"),
		trust_before - 25.0, 0.001)

func test_caught_lie_costs_relationship_sentiment_with_a_reason() -> void:
	_tell_lie_to_malvern()
	var edge_before: float = RelationshipGraph.edge(state, "char_lord_malvern", "you")["sentiment"]
	KnowledgeBase.add_fact(state, "fact_eastmarch_empty", {
		"kind": "public", "subject": "eastmarch", "claim_type": "grain",
		"text": "The eastmarch granaries stand empty.", "truth": true})
	KnowledgeBase.learn(state, "char_lord_malvern", "fact_eastmarch_empty", 90.0)
	ClaimLedger.resolve_due(data, state, 9)
	var edge := RelationshipGraph.edge(state, "char_lord_malvern", "you")
	assert_almost_eq(float(edge["sentiment"]), edge_before - 12.0, 0.001)
	var last: Dictionary = edge["log"][edge["log"].size() - 1]
	assert_string_contains(String(last["reason"]), "lied")

func test_caught_lie_mints_a_betrayal_fact_the_wronged_character_knows() -> void:
	_tell_lie_to_malvern()
	KnowledgeBase.add_fact(state, "fact_eastmarch_empty", {
		"kind": "public", "subject": "eastmarch", "claim_type": "grain",
		"text": "The eastmarch granaries stand empty.", "truth": true})
	KnowledgeBase.learn(state, "char_lord_malvern", "fact_eastmarch_empty", 90.0)
	var resolved := ClaimLedger.resolve_due(data, state, 9)
	var betrayal := String(resolved[0]["betrayal_fact"])
	assert_ne(betrayal, "")
	assert_eq(String(state.knowledge[betrayal]["kind"]), "secret")
	assert_eq(String(state.knowledge[betrayal]["subject"]), "you",
		"the liar is the subject, so it spreads as news about the king")
	assert_true(bool(state.knowledge[betrayal]["truth"]), "the betrayal itself is true")
	assert_true(KnowledgeBase.knows(state, "char_lord_malvern", betrayal))
	assert_false(KnowledgeBase.knows(state, "char_chaplain", betrayal),
		"it starts with the wronged character alone and spreads later")

func test_truth_told_is_rewarded_and_mints_nothing() -> void:
	var honest := _claim("grain", "eastmarch", "The eastmarch granaries stand empty", 0.0, true)
	ClaimLedger.record(data, state, "you", "char_lord_malvern", honest, 90.0, 4)
	var trust_before := SourceTrust.get_trust(data, state, "you", "char_lord_malvern")
	KnowledgeBase.add_fact(state, "fact_eastmarch_empty", {
		"kind": "public", "subject": "eastmarch", "claim_type": "grain",
		"text": "The eastmarch granaries stand empty.", "truth": true})
	KnowledgeBase.learn(state, "char_lord_malvern", "fact_eastmarch_empty", 90.0)
	var resolved := ClaimLedger.resolve_due(data, state, 9)
	assert_eq(String(resolved[0]["status"]), "kept")
	assert_eq(String(resolved[0]["betrayal_fact"]), "")
	assert_almost_eq(SourceTrust.get_trust(data, state, "you", "char_lord_malvern"),
		trust_before + 3.0, 0.001)

func test_a_claim_resolves_only_once() -> void:
	_tell_lie_to_malvern()
	KnowledgeBase.add_fact(state, "fact_eastmarch_empty", {
		"kind": "public", "subject": "eastmarch", "claim_type": "grain",
		"text": "The eastmarch granaries stand empty.", "truth": true})
	KnowledgeBase.learn(state, "char_lord_malvern", "fact_eastmarch_empty", 90.0)
	assert_eq(ClaimLedger.resolve_due(data, state, 9).size(), 1)
	assert_eq(ClaimLedger.resolve_due(data, state, 10).size(), 0, "no double jeopardy")
```

- [ ] **Step 3: Run tests and verify they fail**

Run: `./run_tests.sh`
Expected: FAIL — `resolve_due` not defined.

- [ ] **Step 4: Implement the reckoning**

Append to `scripts/engine/claims.gd`:

```gdscript
const BETRAYAL_PREFIX := "betrayal_"

## Resolves every open claim whose listener has since learned a contradicting
## true fact (spec §6, "The reckoning"). Returns one entry per resolution:
##   {"claim", "status", "trust_delta", "betrayal_fact"}
## Deterministic and idempotent: a resolved claim leaves the open list.
static func resolve_due(data: DataRepository, state: GameState, tick: int) -> Array:
	var out: Array = []
	for claim in open_claims(state):
		if not _reality_known(state, claim):
			continue
		out.append(_resolve(data, state, claim, tick))
	return out

## True when the listener knows a true fact on the same claim_type and
## subject that is not the claim's own fact — reality has caught up with what
## they were told. Named for reality rather than contradiction because it
## fires for honest claims too, which is how truth-telling earns trust.
static func _reality_known(state: GameState, claim: Dictionary) -> bool:
	for fact in KnowledgeBase.facts_about(state, String(claim["listener"]),
			String(claim["claim_type"]), String(claim["subject"])):
		if String(fact["code"]) == String(claim["fact_code"]):
			continue
		if bool(fact["truth"]):
			return true
	return false

static func _resolve(data: DataRepository, state: GameState, claim: Dictionary,
		tick: int) -> Dictionary:
	var claimant := String(claim["claimant"])
	var listener := String(claim["listener"])
	var betrayal := ""
	var trust_delta := 0.0
	if bool(claim["truth"]):
		claim["status"] = "kept"
		trust_delta = data.bal("truth_told_trust_gain")
		SourceTrust.adjust(data, state, claimant, listener, trust_delta,
			"told the truth about " + String(claim["subject"]), tick)
	else:
		claim["status"] = "caught"
		trust_delta = -data.bal("lie_caught_trust_penalty")
		var reason := "lied about " + String(claim["subject"])
		SourceTrust.adjust(data, state, claimant, listener, trust_delta, reason, tick)
		RelationshipGraph.adjust(state, listener, claimant,
			-data.bal("lie_relationship_penalty"), reason, tick)
		betrayal = "%s%d" % [BETRAYAL_PREFIX, state.claims.size() + state.knowledge.size()]
		KnowledgeBase.add_fact(state, betrayal, {
			"kind": "secret", "subject": claimant, "claim_type": "loyalty",
			"text": "%s lied about %s." % [_display_name(state, claimant),
				String(claim["subject"])],
			"truth": true,
		})
		# The wronged character knows it firsthand; propagation spreads it.
		KnowledgeBase.learn(state, listener, betrayal, 100.0)
	return {"claim": claim, "status": String(claim["status"]),
		"trust_delta": trust_delta, "betrayal_fact": betrayal}

static func _display_name(state: GameState, char_id: String) -> String:
	if state.characters.has(char_id):
		return state.characters[char_id].display_name
	return char_id
```

- [ ] **Step 5: Run tests and verify they pass**

Run: `./run_tests.sh`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/engine/claims.gd tests/engine/test_claims.gd data/balance.csv
git commit -m "feat(deception): the reckoning — caught lies cost trust and mint betrayal facts"
```

---

### Task 7: Tick integration

**Files:**
- Modify: `scripts/engine/tick_engine.gd`, `scripts/engine/tick_report.gd`
- Test: `tests/engine/test_claims.gd` (extend)

**Interfaces:**
- Consumes: `ClaimLedger.resolve_due`.
- Produces: `TickReport.claim_resolutions: Array`, populated every tick and included in `to_dict()`.

- [ ] **Step 1: Write the failing test**

Append to `tests/engine/test_claims.gd`:

```gdscript
## --- Task 7: tick integration ---

func test_tick_engine_resolves_claims_and_reports_them() -> void:
	_tell_lie_to_malvern()
	KnowledgeBase.add_fact(state, "fact_eastmarch_empty", {
		"kind": "public", "subject": "eastmarch", "claim_type": "grain",
		"text": "The eastmarch granaries stand empty.", "truth": true})
	KnowledgeBase.learn(state, "char_lord_malvern", "fact_eastmarch_empty", 90.0)
	var report := TickEngine.new(data).advance(state)
	assert_eq(report.claim_resolutions.size(), 1)
	assert_eq(String(report.claim_resolutions[0]["status"]), "caught")
	assert_true(report.to_dict().has("claim_resolutions"))

func test_quiet_tick_reports_no_resolutions() -> void:
	var report := TickEngine.new(data).advance(state)
	assert_eq(report.claim_resolutions.size(), 0)

func test_reckoning_is_deterministic_across_identical_states() -> void:
	_tell_lie_to_malvern()
	KnowledgeBase.add_fact(state, "fact_eastmarch_empty", {
		"kind": "public", "subject": "eastmarch", "claim_type": "grain",
		"text": "The eastmarch granaries stand empty.", "truth": true})
	KnowledgeBase.learn(state, "char_lord_malvern", "fact_eastmarch_empty", 90.0)
	var twin := GameState.from_dict(state.to_dict())
	var a := TickEngine.new(data).advance(state)
	var b := TickEngine.new(data).advance(twin)
	assert_eq(a.claim_resolutions.size(), b.claim_resolutions.size())
	assert_eq(SourceTrust.get_trust(data, state, "you", "char_lord_malvern"),
		SourceTrust.get_trust(data, twin, "you", "char_lord_malvern"))
```

- [ ] **Step 2: Run tests and verify they fail**

Run: `./run_tests.sh`
Expected: FAIL — `claim_resolutions` is not a property of `TickReport`.

- [ ] **Step 3: Add the report field**

In `scripts/engine/tick_report.gd`, after `var relationship_deltas: Array = []`:

```gdscript
var claim_resolutions: Array = []
```

And in `to_dict`, beside the relationship entry:

```gdscript
		"claim_resolutions": claim_resolutions.duplicate(true),
```

- [ ] **Step 4: Call the reckoning each tick**

In `scripts/engine/tick_engine.gd`, in `advance`, immediately after the
`r.relationship_deltas = RelationshipGraph.drift(state, data)` line:

```gdscript
	r.claim_resolutions = ClaimLedger.resolve_due(data, state, state.tick)
```

- [ ] **Step 5: Run tests and verify they pass**

Run: `./run_tests.sh`
Expected: PASS. Existing determinism tests (`test_determinism.gd`, `test_save_load.gd`) must stay green — if they fail, the reckoning has introduced non-determinism and that is a real defect, not a test to update.

- [ ] **Step 6: Commit**

```bash
git add scripts/engine/tick_engine.gd scripts/engine/tick_report.gd tests/engine/test_claims.gd
git commit -m "feat(deception): resolve claims each tick and surface them in the report"
```

---

### Task 8: Document the built system

**Files:**
- Modify: `role_player.md`, `CLAUDE.md`

**Interfaces:**
- Consumes: everything above. Produces: no code.

- [ ] **Step 1: Document the knowledge model in role_player.md**

Add a section after "Locations and regions":

```markdown
## Knowledge, belief, and deception

`data/facts.csv` seeds what each character knows — public facts, secrets with
knower lists, and common sense everyone holds at credibility 100. Knowledge is
per-character: the Chancellor's graft is one fact known only to Mirella and
Quill. `KnowledgeBase.knows` is the single authority on who knows what, so that
once the prompt builder is wired to it (a later phase), no character can be
shown a fact they were never told.

Anyone may assert anything. `Belief` scores an assertion from its plausibility,
the listener's trust in the speaker (derived from how the listener feels about
them), the listener's traits, and corroboration with what they already know.
`data/world_rules.csv` vetoes the impossible outright — no one believes you are
a dragon, whatever else is true.

A believed claim becomes a fact the listener knows, so a swallowed lie behaves
exactly like knowledge. `ClaimLedger` keeps the engine's ground truth beside it;
when the listener later learns a contradicting truth, the reckoning fires: a
truth told earns a little trust, a lie caught costs a lot of it, costs
relationship sentiment, and mints a secret — "the king lied about X" — that the
wronged character knows and the court will eventually learn.
```

- [ ] **Step 2: Add the new CSVs to CLAUDE.md's data list**

In `CLAUDE.md`, extend the key-documents CSV line to include
`world_rules.csv`, `claim_types.csv`, and `facts.csv`.

- [ ] **Step 3: Run the full suite one final time**

Run: `./run_tests.sh`
Expected: PASS, `Errors 2`, `Scripts` up by five from the plan's start.

- [ ] **Step 4: Commit**

```bash
git add role_player.md CLAUDE.md
git commit -m "docs: knowledge, belief, and deception model"
```

---

## Out of scope for this plan

Deferred to later plans, per the spec's build order:

- **Phase 3 — Propagation:** facts crossing relationship edges each tick. Until it exists, a listener only learns a contradicting truth when something else teaches them, so the reckoning is testable but rarely fires in play.
- **Phase 4 — Tools and guardrails:** role pools, per-tick budget, severity ceiling, chronicle.
- **Phase 5 — LLM integration:** `CredibilityJudge`, `ConversationAgent`, `AgentMemory`. Nothing in this plan calls an API; `Belief.score` takes plausibility as a parameter precisely so the judge can be swapped in later without touching the formula.

**One spec test deferred, deliberately.** Spec §9 names the prompt-level
knowledge-isolation check — build a non-knower's prompt and assert the secret's
text is absent — as the highest-value test in the design. It cannot be written
here because `PromptBuilder` is not wired to `KnowledgeBase` until Phase 5.
This plan covers the layer beneath it (`test_secret_is_known_only_to_its_knowers`
in Task 2 pins that `knows()` is false for non-knowers). The prompt-string
assertion is a required deliverable of the Phase 5 plan; do not let it slip.
