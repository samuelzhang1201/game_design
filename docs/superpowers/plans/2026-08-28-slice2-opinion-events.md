# Slice 2 — Opinion Drift + Promises + Random Events Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ministers react deterministically to how you rule (ideology-distance opinion drift with reason strings), promises resolve as kept/broken, and a 20-event random pool fires ~every third tick with clickable choices whose consequences run through the same opinion math.

**Architecture:** All new mechanics are pure engine math (`OpinionDrift`, `TriggerDsl`, `EventEffects`, `EventSystem` — RefCounted, data-driven from new CSVs); events consume the campaign `state.rng` only inside `EventSystem.roll`, keeping the twin-run determinism harness authoritative. UI renders pending events as conversation-frame panels with choice buttons; LLM voicing reuses the existing Voicer degradation ladder with a new flagship tier.

**Tech Stack:** Godot 4.7.1 GDScript, GUT (`./run_tests.sh`, exits nonzero on failure; "Errors 2" is a documented unrelated-plugin condition), OpenAI via existing `OpenAIClient` (no live calls in tests).

**Spec:** `docs/superpowers/specs/2026-08-28-slice2-opinion-events-design.md` (+ `RANDOM_EVENTS.md` for event content, `COUNCIL_SYSTEM.md` for formula provenance)

## Global Constraints

- Engine scripts (`scripts/engine/*`): `RefCounted`, no Node imports, no clock reads, randomness ONLY from the injected/state `Rng` — and for slice 2, ONLY inside `EventSystem.roll` (drift, promises, triggers, effects are RNG-free).
- Every design number in `data/*.csv` (new balance keys listed per task); every opinion/metric change carries a reason string at creation time.
- New CSVs load fail-loud via `DataRepository` (real required_cols, `load_all` → null + `last_error` file+row) and carry `.csv.import` sidecars (`[remap]`, blank line, `importer="keep"`).
- Save/load stays bit-exact: new `GameState` fields (`event_state`, `pending_event`, `Character.flags`) serialize through `to_dict`/`from_dict` with the existing int→float normalization; never weaken a determinism test.
- Effect/`requires`/reason strings in event CSVs must not contain `:` except as the op separator, and no `;` inside args (the parsers split on these; the lint test enforces it).
- No test performs a network call. Commit after every green cycle with the two trailer lines from `git log -1 --format=%B` (author yourself honestly).
- Diagnostics when a class_name won't register: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --check-only --script <file>` (autoload "Game not found" errors from ui-layer scripts are a known false positive — the suite is the gate). Never name helpers `_set`/`_get`; use `: float =` not `:=` for Variant-derived expressions; GDScript lambdas capture by value (hoist test state to members).

## File Structure

```
data/
  action_signatures.csv (+.import)      # Task 1
  random_events.csv (+.import)          # Task 6
  random_event_choices.csv (+.import)   # Task 6
  balance.csv                           # +keys in Tasks 1,3,5
  templates.csv                         # +promise lines (T3), event lines (T6)
scripts/engine/
  opinion_drift.gd                      # Task 1
  trigger_dsl.gd  event_effects.gd      # Task 4
  event_system.gd                       # Task 5
  action_system.gd                      # modify: T2 (drift), T3 (promise-kept), T4 (last_action_tick)
  game_state.gd                         # modify: T4 (event_state), T5 (pending_event)
  character.gd                          # modify: T3 (flags)
  tick_engine.gd                        # modify: T3 (promise check), T5 (event roll)
  data_repository.gd                    # modify: T1 (signatures), T6 (events/choices)
scripts/llm/
  response_validator.gd                 # modify: T3 (promise codes), T8 (EVENT_CHOICE)
  prompt_builder.gd  voicer.gd          # modify: T8
  openai_client.gd                      # modify: T8 (model_flagship config)
scripts/ui/
  council_screen.gd                     # modify: T2 (opinion badges), T7 (event panel)
  game.gd                               # modify: T7 (apply_event_choice), T9 (cleanup)
tests/engine/  tests/ui/  tests/llm/    # mirror
```

---

### Task 1: Action signatures + OpinionDrift

**Files:**
- Create: `data/action_signatures.csv`, `data/action_signatures.csv.import`, `scripts/engine/opinion_drift.gd`
- Modify: `scripts/engine/data_repository.gd` (load signatures), `data/balance.csv` (+1 key)
- Test: `tests/engine/test_opinion_drift.gd`

**Interfaces:**
- Consumes: `DataRepository` (`_load_if_present` pattern from the slice-1 fix wave), `Character.change_opinion(delta, reason, tick)`, `GameState.council/characters`.
- Produces: `DataRepository.signatures: Array[Dictionary]`; `class_name OpinionDrift` statics — `signature_for(data, code: String, params: Dictionary) -> Dictionary` (empty = no drift), `alignment(sig, ideology) -> float` (∈[−1,1]), `dominant_axis(sig, ideology) -> String`, `apply(data, state, sig, label: String) -> Array` of `{character_id, delta, reason}` (applies to all seated ministers, skips zero deltas, reason format `"<label> (<approves|opposes>, <axis>)"`).

- [ ] **Step 1: Create `data/action_signatures.csv`** — copy VERBATIM from spec §2.1 (the 18-row table starting `TAX_RATE_ADJUST,delta_pos,...` — open the spec and transcribe exactly, including the notes column). Add the standard `.import` sidecar. Append to `data/balance.csv`:

```csv
opinion_drift_scale,20,scales alignment x sensitivity x (1-pragmatism) into opinion points
```

- [ ] **Step 2: Load signatures in DataRepository.** Add field `var signatures: Array[Dictionary] = []` and in `_load()` (alongside the other `_load_if_present` calls added by the slice-1 fix wave):

```gdscript
	if not _load_if_present(dir + "/action_signatures.csv",
			["action_code", "variant", "centralism", "militarism", "orthodoxy",
			"tax_incidence", "expansionism"],
			func(r): signatures.append(r)):
		return false
```

(Match the exact `_load_if_present` signature in the current file — read it first; if its callback/return contract differs, adapt this call, not the loader.)

- [ ] **Step 3: Write failing tests** — `tests/engine/test_opinion_drift.gd`:

```gdscript
extends GutTest

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)

func test_signatures_loaded() -> void:
	assert_gt(data.signatures.size(), 10)

func test_variant_matching() -> void:
	var pos := OpinionDrift.signature_for(data, "TAX_RATE_ADJUST", {"delta": 2})
	var neg := OpinionDrift.signature_for(data, "TAX_RATE_ADJUST", {"delta": -1})
	assert_eq(pos["tax_incidence"], -30.0)
	assert_eq(neg["tax_incidence"], 30.0)
	var tithe := OpinionDrift.signature_for(data, "CHURCH_POLICY", {"mode": "tithe"})
	assert_eq(tithe["orthodoxy"], -50.0)
	assert_eq(OpinionDrift.signature_for(data, "COUNCIL_CONSULT", {}), {
		"centralism": 0.0, "militarism": 0.0, "orthodoxy": 0.0,
		"tax_incidence": 0.0, "expansionism": 0.0})
	assert_eq(OpinionDrift.signature_for(data, "NO_SUCH_ACTION", {}), {})

func test_odo_hates_the_tithe_worked_example() -> void:
	# CHURCH_POLICY tithe sig: centralism +10, orthodoxy -50 (L1 norm 60).
	# Odo: centralism 10, orthodoxy 70, sensitivity 80, pragmatism 30.
	# dot = 10*10 + (-50)*70 = -3400; alignment = -3400/6000 = -0.5667
	# delta = round(-0.5667 * 0.8 * 0.7 * 20) = round(-6.35) = -6
	var sig := OpinionDrift.signature_for(data, "CHURCH_POLICY", {"mode": "tithe"})
	var odo: Character = s.characters["char_chaplain"]
	var before: int = odo.opinion
	var applied := OpinionDrift.apply(data, s, sig, "tithed the church")
	assert_eq(odo.opinion, before - 6)
	assert_string_contains(odo.opinion_log[-1]["reason"], "tithed the church (opposes, orthodoxy)")
	var found := false
	for a in applied:
		if a["character_id"] == "char_chaplain":
			found = true
			assert_eq(a["delta"], -6)
	assert_true(found)

func test_pragmatist_barely_notices() -> void:
	# Mirella on tithe: dot = 10*10 + (-50)*(-20) = 1100; a = 0.1833
	# delta = round(0.1833 * 0.75 * 0.25 * 20) = round(0.69) = 1
	var sig := OpinionDrift.signature_for(data, "CHURCH_POLICY", {"mode": "tithe"})
	var before: int = s.characters["char_steward"].opinion
	OpinionDrift.apply(data, s, sig, "tithed the church")
	assert_eq(s.characters["char_steward"].opinion, before + 1)

func test_zero_signature_applies_nothing() -> void:
	var logs_before := s.characters["char_marshal"].opinion_log.size()
	OpinionDrift.apply(data, s, {}, "nothing")
	OpinionDrift.apply(data, s, OpinionDrift.signature_for(data, "COUNCIL_CONSULT", {}), "consulted")
	assert_eq(s.characters["char_marshal"].opinion_log.size(), logs_before)
```

Before running, RE-DERIVE the two worked examples from the actual CSVs (`founding_council.csv` ideology/sensitivity/pragmatism columns and your `action_signatures.csv`) — the CSVs are source of truth; if your arithmetic differs, fix the expected numbers and show the derivation in your report.

- [ ] **Step 4: Run** — `./run_tests.sh` — Expected: FAIL (`OpinionDrift` not found).

- [ ] **Step 5: Implement `scripts/engine/opinion_drift.gd`:**

```gdscript
class_name OpinionDrift
extends RefCounted
## Deterministic ideology-distance opinion drift (spec §2.2). No RNG.

const AXES := ["centralism", "militarism", "orthodoxy", "tax_incidence", "expansionism"]

static func signature_for(data: DataRepository, code: String, params: Dictionary) -> Dictionary:
	for row in data.signatures:
		if row["action_code"] != code:
			continue
		if _variant_matches(String(row.get("variant", "")), params):
			var sig := {}
			for ax in AXES:
				sig[ax] = float(row[ax])
			return sig
	return {}

static func _variant_matches(variant: String, params: Dictionary) -> bool:
	if variant == "":
		return true
	if variant == "delta_pos":
		return float(params.get("delta", 0)) > 0.0
	if variant == "delta_neg":
		return float(params.get("delta", 0)) < 0.0
	if "=" in variant:
		var kv := variant.split("=")
		return String(params.get(kv[0], "")) == kv[1]
	return false

static func alignment(sig: Dictionary, ideology: Dictionary) -> float:
	var dot := 0.0
	var norm := 0.0
	for ax in AXES:
		dot += float(sig.get(ax, 0)) * float(ideology.get(ax, 0))
		norm += absf(float(sig.get(ax, 0)))
	if norm == 0.0:
		return 0.0
	return dot / (norm * 100.0)

static func dominant_axis(sig: Dictionary, ideology: Dictionary) -> String:
	var best := ""
	var best_v := -1.0
	for ax in AXES:
		var v := absf(float(sig.get(ax, 0)) * float(ideology.get(ax, 0)))
		if v > best_v:
			best_v = v
			best = ax
	return best

static func apply(data: DataRepository, state: GameState, sig: Dictionary, label: String) -> Array:
	var out: Array = []
	if sig.is_empty():
		return out
	for seat in state.council:
		var char_id: String = state.council[seat]
		var c: Character = state.characters[char_id]
		var a := alignment(sig, c.ideology)
		var delta := roundi(a * float(c.ideology.get("policy_sensitivity", 50)) / 100.0 \
			* (1.0 - float(c.attributes.get("pragmatism", 50)) / 100.0) \
			* data.bal("opinion_drift_scale"))
		if delta == 0:
			continue
		var stance := "approves" if delta > 0 else "opposes"
		var reason := "%s (%s, %s)" % [label, stance, dominant_axis(sig, c.ideology)]
		c.change_opinion(delta, reason, state.tick)
		out.append({"character_id": char_id, "delta": delta, "reason": reason})
	return out
```

- [ ] **Step 6: Run** — Expected: PASS. **Step 7: Commit** — `feat: action ideology signatures + OpinionDrift`

---

### Task 2: Wire drift into execution + opinion badges on the roster

**Files:**
- Modify: `scripts/engine/action_system.gd` (execute), `scripts/ui/council_screen.gd` (_build_portrait)
- Test: extend `tests/engine/test_action_system.gd`, extend `tests/ui/test_council_screen.gd`

**Interfaces:**
- Consumes: `OpinionDrift` (Task 1).
- Produces: `ActionSystem.execute` outcome dict gains `"drift": Array` (OpinionDrift.apply result). Roster portraits show the minister's opinion number and a tooltip with the last opinion-log reasons — later tasks rely on nothing new here beyond the outcome key.

- [ ] **Step 1: Failing engine test** — append to `tests/engine/test_action_system.gd`:

```gdscript
func test_execute_applies_ideology_drift() -> void:
	var odo_before: int = s.characters["char_chaplain"].opinion
	var out := sys.execute(ActionRequest.make("CHURCH_POLICY", {"mode": "tithe"}), s)
	assert_eq(s.characters["char_chaplain"].opinion, odo_before - 6)
	assert_true(out.has("drift"))
	assert_gt(out["drift"].size(), 0)
	assert_string_contains(
		s.characters["char_chaplain"].opinion_log[-1]["reason"], "opposes, orthodoxy")
```

(Note: the tithe ALSO pays +25 gold etc. — those effects are unrelated to this assertion. If `s` isn't the fixture name in the current file, match the file's existing fixture names.)

- [ ] **Step 2: Run** — FAIL (no `drift` key). **Step 3: Implement** — in `ActionSystem.execute`, immediately before the `outcome` dictionary is built:

```gdscript
	var drift := OpinionDrift.apply(data, state,
		OpinionDrift.signature_for(data, req.action_code, req.params),
		String(row["label"]))
```

and add `"drift": drift` to the outcome dictionary.

- [ ] **Step 4: UI badge.** In `council_screen.gd` `_build_portrait`, after the texture/fallback block, add an opinion badge and enrich the tooltip:

```gdscript
	var c: Character = Game.state.characters[char_id]
	var badge := Label.new()
	badge.text = str(c.opinion)
	badge.add_theme_font_size_override("font_size", 12)
	badge.add_theme_color_override("font_color",
		Color("7fd47f") if c.opinion >= 0 else Color("d47f7f"))
	badge.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	badge.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	badge.grow_vertical = Control.GROW_DIRECTION_BEGIN
	panel.add_child(badge)
	var recent := ""
	var log := c.opinion_log
	for i in range(maxi(0, log.size() - 5), log.size()):
		recent += "\n%+d %s" % [int(log[i]["delta"]), log[i]["reason"]]
	panel.tooltip_text = c.display_name + recent
```

(This replaces the existing plain `tooltip_text` assignment in `_build_portrait`.)

- [ ] **Step 5: UI test** — append to `tests/ui/test_council_screen.gd`:

```gdscript
func test_roster_shows_opinion_and_reasons() -> void:
	Game.start_campaign(42)
	var screen: Node = load("res://scenes/council.tscn").instantiate()
	add_child_autofree(screen)
	Game.next_tick()
	Game.try_execute(ActionRequest.make("CHURCH_POLICY", {"mode": "tithe"}))
	screen._render_portraits()
	await wait_frames(2)
	var found_reason := false
	for p in screen.portraits_box.get_children():
		if "opposes, orthodoxy" in p.tooltip_text:
			found_reason = true
	assert_true(found_reason)
```

- [ ] **Step 6: Run full suite** — Expected: ALL PASS (the determinism harness recomputes both runs identically; drift changes hashes but symmetrically). **Step 7: Commit** — `feat: ideology drift wired into execution; roster opinion badges`

---

### Task 3: Promise resolution

**Files:**
- Modify: `scripts/engine/character.gd` (flags), `scripts/engine/action_system.gd` (kept check + due default), `scripts/engine/tick_engine.gd` (broken check + report), `scripts/llm/response_validator.gd` (promise_code validation), `data/balance.csv` (+3 keys), `data/templates.csv` (+2 rows)
- Test: `tests/engine/test_promises.gd`, extend `tests/llm/test_response_validator.gd`

**Interfaces:**
- Consumes: `state.promises` entries `{character_id, promise_code, made_tick, tick_due, status}` (slice 1), `Character.change_opinion`.
- Produces: `Character.flags: Array` (serialized; contains `"grudge"` after a broken promise). `TickReport.promise_events: Array` of `{character_id, promise_code, status}`. Promise statuses move `open → kept|broken`. Balance keys `promise_kept_opinion=15`, `promise_broken_opinion=-25`, `promise_default_ticks=24`. Validator rejects promise_codes that aren't real action codes.

- [ ] **Step 1: Balance + template rows.** Append to `data/balance.csv`:

```csv
promise_kept_opinion,15,
promise_broken_opinion,-25,largest single penalty in the game by design
promise_default_ticks,24,due when the parser omits tick_due
```

Append to `data/templates.csv`:

```csv
promise_kept,,"Your word, kept. The court takes note."
promise_broken,,"A promise has lapsed unkept. The court remembers that too."
```

- [ ] **Step 2: Failing tests** — `tests/engine/test_promises.gd`:

```gdscript
extends GutTest

var data: DataRepository
var engine: TickEngine
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	engine = TickEngine.new(data)
	s = GameState.new_campaign(data, 42)
	engine.advance(s)

func _promise(code: String, due: int) -> void:
	s.promises.append({"character_id": "char_marshal", "promise_code": code,
		"made_tick": s.tick, "tick_due": due, "status": "open"})

func test_kept_when_action_executes_before_due() -> void:
	_promise("LEVY_RAISE", s.tick + 4)
	var before: int = s.characters["char_marshal"].opinion
	engine.actions.execute(ActionRequest.make("LEVY_RAISE"), s)
	assert_eq(s.promises[0]["status"], "kept")
	# +15 kept, minus whatever ideology drift the levy itself causes — assert the log entry
	var found := false
	for e in s.characters["char_marshal"].opinion_log:
		if "promise kept" in String(e["reason"]) and int(e["delta"]) == 15:
			found = true
	assert_true(found)
	assert_gt(s.characters["char_marshal"].opinion, before)

func test_targeted_promise_needs_matching_target() -> void:
	_promise("CHARACTER_REWARD", s.tick + 4)
	engine.actions.execute(ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, "char_steward"), s)
	assert_eq(s.promises[0]["status"], "open")  # rewarded the wrong person
	engine.actions.execute(ActionRequest.make("CHARACTER_REWARD", {"mode": "gold"}, "char_marshal"), s)
	assert_eq(s.promises[0]["status"], "kept")

func test_broken_when_due_passes() -> void:
	_promise("LEVY_RAISE", s.tick + 1)
	var before: int = s.characters["char_marshal"].opinion
	var r1 := engine.advance(s)   # tick == due: still open
	assert_eq(s.promises[0]["status"], "open")
	var r2 := engine.advance(s)   # past due -> broken
	assert_eq(s.promises[0]["status"], "broken")
	assert_eq(s.characters["char_marshal"].opinion, before + int(data.bal("promise_broken_opinion")))
	assert_true("grudge" in s.characters["char_marshal"].flags)
	assert_eq(r2.promise_events.size(), 1)
	assert_eq(r2.promise_events[0]["status"], "broken")

func test_flags_survive_round_trip() -> void:
	s.characters["char_marshal"].flags.append("grudge")
	var s2 := GameState.from_dict(s.to_dict())
	assert_true("grudge" in s2.characters["char_marshal"].flags)
	assert_eq(SaveLoad.state_hash(s2), SaveLoad.state_hash(s))
```

Append to `tests/llm/test_response_validator.gd`:

```gdscript
func test_promise_code_must_be_real_action() -> void:
	var text := JSON.stringify({"actions": [], "court_reaction": {"addressed": [],
		"tone": "neutral", "promises": [{"character_id": "char_marshal",
		"promise_code": "GRANT_UNICORN", "tick_due": 30}]}})
	var out := ResponseValidator.parse(text, data)
	assert_false(out["ok"])
	assert_string_contains(out["error"], "GRANT_UNICORN")
```

- [ ] **Step 3: Run** — FAIL. **Step 4: Implement.**

`character.gd`: add `var flags: Array = []`, include `"flags": flags.duplicate()` in `to_dict()` and `c.flags = d.get("flags", []).duplicate()` in `from_dict`.

`response_validator.gd`, in the promises loop: after extracting `promise_code`, add

```gdscript
				if not data.actions.has(String(p["promise_code"])):
					return fail.call("unknown promise action: " + String(p["promise_code"]))
```

`action_system.gd`: in `apply_court_reaction`'s promise append, default the due date:

```gdscript
		var due := int(p["tick_due"])
		if due <= 0:
			due = state.tick + int(data.bal("promise_default_ticks"))
```

and in `execute`, after the effects `match` (before cooldown/outcome), the kept check:

```gdscript
	for pr in state.promises:
		if String(pr["status"]) != "open":
			continue
		if String(pr["promise_code"]) != req.action_code:
			continue
		if req.target != "" and req.target != String(pr["character_id"]):
			continue
		pr["status"] = "kept"
		var who: String = String(pr["character_id"])
		if state.characters.has(who):
			state.characters[who].change_opinion(int(data.bal("promise_kept_opinion")),
				"a promise kept: " + String(row["label"]), state.tick)
```

`tick_engine.gd`: add `var promise_events: Array = []` to `TickReport` (+ include in `to_dict()`), and in `advance` (after drift, before concerns):

```gdscript
	for pr in state.promises:
		if String(pr["status"]) == "open" and state.tick > int(pr["tick_due"]):
			pr["status"] = "broken"
			var who: String = String(pr["character_id"])
			if state.characters.has(who):
				var c: Character = state.characters[who]
				c.change_opinion(int(data.bal("promise_broken_opinion")),
					"a promise broken: " + String(pr["promise_code"]), state.tick)
				if not "grudge" in c.flags:
					c.flags.append("grudge")
			r.promise_events.append({"character_id": who,
				"promise_code": String(pr["promise_code"]), "status": "broken"})
```

Also render them: in `council_screen.gd` `_render_report`, after the outcomes loop:

```gdscript
	for pe in report.promise_events:
		var key := "promise_" + String(pe["status"])
		_say({"speaker": "Herald", "text": TemplateVoicer.line_for(Game.data, key, [], report.tick)})
```

`TemplateVoicer`: expose the private `_line` selection as a public static `line_for(data, key, speaker_traits, tick) -> String` (same body; keep `_line` delegating to it so existing call sites are untouched).

- [ ] **Step 5: Run full suite** — PASS. **Step 6: Commit** — `feat: promises resolve kept/broken with grudge flags`

---

### Task 4: TriggerDsl + EventEffects + event_state scaffold

**Files:**
- Create: `scripts/engine/trigger_dsl.gd`, `scripts/engine/event_effects.gd`
- Modify: `scripts/engine/game_state.gd` (event_state), `scripts/engine/action_system.gd` (last_action_tick)
- Test: `tests/engine/test_trigger_dsl.gd`, `tests/engine/test_event_effects.gd`

**Interfaces:**
- Consumes: `GameState`, `Character.change_opinion`, `data.bal`.
- Produces: `GameState.event_state: Dictionary` = `{"cooldowns": {}, "once": [], "pity": 0, "scheduled": [], "flags": [], "last_action_tick": {}}`, serialized (deep int→float normalized like recent_outcomes; read sites re-cast with `int(...)`). `TriggerDsl.evaluate(expr: String, state, data) -> bool` with clauses joined by `&`: `always`, `metric<N`, `metric>N`, `season=<name>`, `year>=N`, `trait_at_court=<code>`, `seat_filled=<seat>`, `action_since=<CODE>:<ticks>`, `flag=<name>`. `EventEffects.apply(ops: String, state, data) -> Array` of result records; ops split on `;`: `metric:<name>:<±N>`, `gold:<±N>`, `opinion:<seat|char_id>:<±N>:<reason>`, `schedule:<event_id>:<delay>`, `flag:<name>`, `promise:<seat|char_id>:<action_code>:<due_ticks>`. `EventEffects._resolve(key, state) -> String` (char_id, or seat→char_id, or "").

- [ ] **Step 1: event_state scaffold.** In `game_state.gd`: add

```gdscript
var event_state: Dictionary = {
	"cooldowns": {}, "once": [], "pity": 0, "scheduled": [],
	"flags": [], "last_action_tick": {},
}
```

Serialize: in `to_dict()` add `"event_state": _normalize_ints(event_state.duplicate(true))` (reuse the existing deep normalizer; if its signature takes an Array, generalize it to accept Dictionary or Array — it recurses over both anyway). In `from_dict`: `s.event_state = d.get("event_state", <same defaults>).duplicate(true)`. In `action_system.gd` `execute`, right before the outcome append: `state.event_state["last_action_tick"][req.action_code] = state.tick`.

- [ ] **Step 2: Failing tests** — `tests/engine/test_trigger_dsl.gd`:

```gdscript
extends GutTest

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	s.tick = 5

func test_always_and_metrics() -> void:
	assert_true(TriggerDsl.evaluate("always", s, data))
	s.metrics["grain"] = 10.0
	assert_true(TriggerDsl.evaluate("grain<30", s, data))
	assert_false(TriggerDsl.evaluate("grain>30", s, data))
	assert_true(TriggerDsl.evaluate("grain<30&unrest>-1", s, data))
	assert_false(TriggerDsl.evaluate("grain<30&treasury<1", s, data))

func test_season_year_seat_trait() -> void:
	assert_true(TriggerDsl.evaluate("season=spring", s, data))
	assert_false(TriggerDsl.evaluate("season=winter", s, data))
	assert_false(TriggerDsl.evaluate("year>=2", s, data))
	s.tick = 30
	assert_true(TriggerDsl.evaluate("year>=2", s, data))
	assert_true(TriggerDsl.evaluate("seat_filled=marshal", s, data))
	assert_false(TriggerDsl.evaluate("seat_filled=admiral", s, data))
	assert_true(TriggerDsl.evaluate("trait_at_court=paranoid", s, data))   # Quill
	assert_false(TriggerDsl.evaluate("trait_at_court=venal", s, data))

func test_action_since_and_flags() -> void:
	s.event_state["last_action_tick"]["TARIFF_ADJUST"] = 3
	assert_true(TriggerDsl.evaluate("action_since=TARIFF_ADJUST:24", s, data))
	s.tick = 40
	assert_false(TriggerDsl.evaluate("action_since=TARIFF_ADJUST:24", s, data))
	assert_false(TriggerDsl.evaluate("flag=black_market", s, data))
	s.event_state["flags"].append("black_market")
	assert_true(TriggerDsl.evaluate("flag=black_market", s, data))
```

`tests/engine/test_event_effects.gd`:

```gdscript
extends GutTest

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	s.tick = 3

func test_metric_gold_and_opinion_ops() -> void:
	var t0: float = s.metrics["treasury"]
	var o0: int = s.characters["char_chaplain"].opinion
	var res := EventEffects.apply(
		"gold:-30; metric:church_opinion:8; opinion:chaplain:4:blessed the gift", s, data)
	assert_eq(s.metrics["treasury"], t0 - 30.0)
	assert_eq(s.characters["char_chaplain"].opinion, o0 + 4)
	assert_string_contains(
		s.characters["char_chaplain"].opinion_log[-1]["reason"], "blessed the gift")
	assert_eq(res.size(), 3)

func test_schedule_flag_promise_ops() -> void:
	EventEffects.apply("schedule:ev_test_followup:12; flag:omen_seen; promise:marshal:LEVY_RAISE:8", s, data)
	assert_eq(s.event_state["scheduled"].size(), 1)
	assert_eq(String(s.event_state["scheduled"][0]["event_id"]), "ev_test_followup")
	assert_eq(int(s.event_state["scheduled"][0]["due_tick"]), 15)
	assert_true("omen_seen" in s.event_state["flags"])
	assert_eq(s.promises.size(), 1)
	assert_eq(String(s.promises[0]["character_id"]), "char_marshal")
	assert_eq(int(s.promises[0]["tick_due"]), 11)

func test_unknown_op_is_loud_but_safe() -> void:
	var res := EventEffects.apply("frobnicate:9", s, data)
	assert_eq(res.size(), 0)

func test_event_state_round_trip() -> void:
	EventEffects.apply("schedule:ev_x:5; flag:f1", s, data)
	var s2 := GameState.from_dict(s.to_dict())
	assert_eq(SaveLoad.state_hash(s2), SaveLoad.state_hash(s))
	assert_true("f1" in s2.event_state["flags"])
```

- [ ] **Step 3: Run** — FAIL. **Step 4: Implement** `trigger_dsl.gd`:

```gdscript
class_name TriggerDsl
extends RefCounted
## Deterministic trigger evaluator for random_events.csv (spec §4.1). No RNG.

static func evaluate(expr: String, state: GameState, data: DataRepository) -> bool:
	if expr.strip_edges() == "always":
		return true
	for clause in expr.split("&"):
		if not _clause(clause.strip_edges(), state, data):
			return false
	return true

static func _clause(c: String, state: GameState, _data: DataRepository) -> bool:
	if c.begins_with("season="):
		return state.season() == c.substr(7)
	if c.begins_with("year>="):
		return state.year() >= int(c.substr(6))
	if c.begins_with("trait_at_court="):
		var t := c.substr(15)
		for id in state.characters:
			if t in state.characters[id].traits:
				return true
		return false
	if c.begins_with("seat_filled="):
		return state.council.has(c.substr(12))
	if c.begins_with("action_since="):
		var parts := c.substr(13).split(":")
		var last := int(state.event_state["last_action_tick"].get(parts[0], -99999))
		return last >= state.tick - int(parts[1])
	if c.begins_with("flag="):
		return c.substr(5) in state.event_state["flags"]
	if "<" in c:
		var kv := c.split("<")
		return float(state.metrics.get(kv[0], 0.0)) < float(kv[1])
	if ">" in c:
		var kv := c.split(">")
		return float(state.metrics.get(kv[0], 0.0)) > float(kv[1])
	push_error("TriggerDsl: unknown clause: " + c)
	return false
```

`event_effects.gd`:

```gdscript
class_name EventEffects
extends RefCounted
## Executes an event choice's effect ops (spec §4.1). Deterministic, no RNG.

static func apply(ops: String, state: GameState, data: DataRepository) -> Array:
	var results: Array = []
	for raw in ops.split(";", false):
		var op := raw.strip_edges()
		if op == "":
			continue
		var p := op.split(":")
		match p[0]:
			"metric":
				state.metrics[p[1]] = float(state.metrics.get(p[1], 0.0)) + float(p[2])
				results.append({"kind": "metric", "metric": p[1], "delta": float(p[2])})
			"gold":
				state.metrics["treasury"] = float(state.metrics["treasury"]) + float(p[1])
				results.append({"kind": "metric", "metric": "treasury", "delta": float(p[1])})
			"opinion":
				var id := _resolve(p[1], state)
				if id != "":
					state.characters[id].change_opinion(int(p[2]), p[3], state.tick)
					results.append({"kind": "opinion", "character_id": id,
						"delta": int(p[2]), "reason": p[3]})
			"schedule":
				state.event_state["scheduled"].append(
					{"event_id": p[1], "due_tick": state.tick + int(p[2])})
				results.append({"kind": "schedule", "event_id": p[1]})
			"flag":
				if not p[1] in state.event_state["flags"]:
					state.event_state["flags"].append(p[1])
				results.append({"kind": "flag", "flag": p[1]})
			"promise":
				var id2 := _resolve(p[1], state)
				if id2 != "":
					state.promises.append({"character_id": id2, "promise_code": p[2],
						"made_tick": state.tick, "tick_due": state.tick + int(p[3]),
						"status": "open"})
					results.append({"kind": "promise", "character_id": id2})
			_:
				push_error("EventEffects: unknown op: " + op)
	return results

static func _resolve(key: String, state: GameState) -> String:
	if state.characters.has(key):
		return key
	if state.council.has(key):
		return String(state.council[key])
	return ""
```

- [ ] **Step 5: Run full suite** — PASS (test_unknown_op prints one push_error — GUT counts engine errors, and run_tests.sh validates the known count of 2; if the error-count gate trips, route the unknown-op path through a returned `{"kind":"error"}` record + `printerr` instead of `push_error`, note it in the report). **Step 6: Commit** — `feat: trigger DSL + event effects vocabulary + event_state`

---

### Task 5: EventSystem core + determinism extension

**Files:**
- Create: `scripts/engine/event_system.gd`
- Modify: `scripts/engine/game_state.gd` (pending_event), `scripts/engine/tick_engine.gd` (roll in advance), `scripts/engine/data_repository.gd` (events/choices load), `data/balance.csv` (+1 key)
- Test: `tests/engine/test_event_system.gd`, extend `tests/engine/test_determinism.gd`

**Interfaces:**
- Consumes: `TriggerDsl`, `EventEffects`, `OpinionDrift`, `state.rng` (`chance`, `pick_weighted`).
- Produces: `DataRepository.events: Array[Dictionary]`, `events_by_id: Dictionary`, `event_choices: Array[Dictionary]` (loaded fail-loud when files exist; empty otherwise). `GameState.pending_event: Dictionary` (`{}` = none; serialized). `TickEngine` public `events: EventSystem`. `TickReport.event: Dictionary` (`{}` or pending descriptor `{event_id, title_key, voice, choices: [{choice_id, label}]}`). `EventSystem.roll(state) -> Dictionary`, `EventSystem.apply_choice(choice_id: String, state) -> Dictionary` outcome `{event_id, choice_id, label, effects: Array, drift: Array}` (clears pending; unknown/inactive choice_id returns `{}` unchanged). Balance key `event_pity_ticks,6`.

- [ ] **Step 1: Data plumbing.** `data/balance.csv` += `event_pity_ticks,6,force an event after this many quiet ticks` (note: `event_base_chance,0.35` already exists from slice 1). `data_repository.gd`: add fields `events: Array[Dictionary]`, `events_by_id: Dictionary`, `event_choices: Array[Dictionary]`; load via `_load_if_present` with required cols `["event_id","category","trigger","weight","cooldown_ticks","once","voice","title_key"]` and `["event_id","choice_id","label","centralism","militarism","orthodoxy","tax_incidence","expansionism","effects","requires"]`; after loading, index `events_by_id[row["event_id"]] = row`. `game_state.gd`: add `var pending_event: Dictionary = {}`, serialize like event_state (deep-normalized both directions; `from_dict` default `{}`).

- [ ] **Step 2: Failing tests** — `tests/engine/test_event_system.gd` (uses a synthetic data fixture so it doesn't depend on Task 6's content):

```gdscript
extends GutTest

var data: DataRepository
var s: GameState
var es: EventSystem

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	# Synthetic pool: deterministic, independent of the real content task.
	data.events = [
		{"event_id": "ev_a", "category": "folk", "trigger": "always", "weight": "1",
			"cooldown_ticks": "4", "once": "0", "voice": "template", "title_key": "event_ev_a"},
		{"event_id": "ev_once", "category": "folk", "trigger": "always", "weight": "1",
			"cooldown_ticks": "0", "once": "1", "voice": "template", "title_key": "event_ev_once"},
		{"event_id": "ev_gated", "category": "realm", "trigger": "grain<5", "weight": "99",
			"cooldown_ticks": "0", "once": "0", "voice": "template", "title_key": "event_ev_gated"},
	]
	data.events_by_id = {}
	for row in data.events:
		data.events_by_id[row["event_id"]] = row
	data.event_choices = [
		{"event_id": "ev_a", "choice_id": "accept", "label": "Accept the geese",
			"centralism": "0", "militarism": "0", "orthodoxy": "0",
			"tax_incidence": "20", "expansionism": "0",
			"effects": "metric:peasant_contentment:2", "requires": ""},
		{"event_id": "ev_a", "choice_id": "refuse", "label": "Refuse",
			"centralism": "0", "militarism": "0", "orthodoxy": "0",
			"tax_incidence": "0", "expansionism": "0",
			"effects": "metric:peasant_contentment:-2", "requires": ""},
		{"event_id": "ev_once", "choice_id": "ok", "label": "So be it",
			"centralism": "0", "militarism": "0", "orthodoxy": "0",
			"tax_incidence": "0", "expansionism": "0", "effects": "flag:seen_once",
			"requires": ""},
		{"event_id": "ev_gated", "choice_id": "ok", "label": "Endure",
			"centralism": "0", "militarism": "0", "orthodoxy": "0",
			"tax_incidence": "0", "expansionism": "0", "effects": "", "requires": ""},
	]
	s = GameState.new_campaign(data, 42)
	s.tick = 1
	es = EventSystem.new(data)

func test_pity_forces_event_within_window() -> void:
	var fired := 0
	for i in 30:
		s.tick += 1
		var ev := es.roll(s)
		if not ev.is_empty():
			fired += 1
			es.apply_choice(String(ev["choices"][0]["choice_id"]), s)
	assert_gt(fired, 3)  # 35% + pity 6 over 30 ticks fires several times

func test_trigger_gates_eligibility() -> void:
	# grain healthy: ev_gated (weight 99) must never fire
	for i in 40:
		s.tick += 1
		var ev := es.roll(s)
		if not ev.is_empty():
			assert_ne(String(ev["event_id"]), "ev_gated")
			es.apply_choice(String(ev["choices"][0]["choice_id"]), s)

func test_once_fires_at_most_once() -> void:
	var seen := 0
	for i in 60:
		s.tick += 1
		var ev := es.roll(s)
		if not ev.is_empty():
			if String(ev["event_id"]) == "ev_once":
				seen += 1
			es.apply_choice(String(ev["choices"][0]["choice_id"]), s)
	assert_lte(seen, 1)

func test_apply_choice_runs_effects_and_signature_drift() -> void:
	s.pending_event = {}
	var ev := es._fire("ev_a", s)
	var pc0: float = s.metrics["peasant_contentment"]
	var out := es.apply_choice("accept", s)
	assert_eq(s.metrics["peasant_contentment"], pc0 + 2.0)
	assert_eq(String(out["choice_id"]), "accept")
	assert_true(s.pending_event.is_empty())
	# tax_incidence +20 signature drifts seated ministers (e.g. Mirella -40 axis)
	assert_gt(out["drift"].size(), 0)

func test_scheduled_event_fires_regardless_of_roll() -> void:
	EventEffects.apply("schedule:ev_once:2", s, data)
	s.tick += 1
	assert_true(es.roll(s).is_empty() or true)  # may or may not fire random event
	s.pending_event = {}
	s.tick += 2
	var ev := es.roll(s)
	assert_eq(String(ev.get("event_id", "")), "ev_once")

func test_pending_event_round_trip() -> void:
	es._fire("ev_a", s)
	var s2 := GameState.from_dict(s.to_dict())
	assert_eq(SaveLoad.state_hash(s2), SaveLoad.state_hash(s))
	assert_eq(String(s2.pending_event.get("event_id", "")), "ev_a")
```

Extend `tests/engine/test_determinism.gd`: in `_run_campaign`, after `engine.advance(s)` and the scripted-input execution, add deterministic event resolution:

```gdscript
		if not s.pending_event.is_empty():
			engine.events.apply_choice(String(s.pending_event["choices"][0]["choice_id"]), s)
```

(The three existing assertions stay untouched; with events consuming rng, `test_different_seeds_diverge` now diverges through real gameplay — update its comment accordingly.)

- [ ] **Step 3: Run** — FAIL. **Step 4: Implement** `event_system.gd`:

```gdscript
class_name EventSystem
extends RefCounted
## Rolls and resolves random events (spec §4.2). The ONLY slice-2 consumer of
## state.rng; everything else stays RNG-free so headless and UI runs match.

var data: DataRepository

func _init(d: DataRepository) -> void:
	data = d

func roll(state: GameState) -> Dictionary:
	if not state.pending_event.is_empty():
		return state.pending_event
	# chains first: due scheduled events fire regardless of the daily roll
	var remaining: Array = []
	var due_id := ""
	for sc in state.event_state["scheduled"]:
		if due_id == "" and int(sc["due_tick"]) <= state.tick \
				and data.events_by_id.has(String(sc["event_id"])):
			due_id = String(sc["event_id"])
		else:
			remaining.append(sc)
	state.event_state["scheduled"] = remaining
	if due_id != "":
		return _fire(due_id, state)
	state.event_state["pity"] = int(state.event_state["pity"]) + 1
	var forced: bool = int(state.event_state["pity"]) > int(data.bal("event_pity_ticks"))
	if not forced and not state.rng.chance(data.bal("event_base_chance")):
		return {}
	var eligible: Array = []
	var weights: Array = []
	for row in data.events:
		var id := String(row["event_id"])
		if id in state.event_state["once"]:
			continue
		if int(state.event_state["cooldowns"].get(id, -99999)) > state.tick:
			continue
		if not TriggerDsl.evaluate(String(row["trigger"]), state, data):
			continue
		eligible.append(row)
		weights.append(float(row["weight"]))
	if eligible.is_empty():
		return {}
	return _fire(String(eligible[state.rng.pick_weighted(weights)]["event_id"]), state)

func _fire(event_id: String, state: GameState) -> Dictionary:
	var row: Dictionary = data.events_by_id[event_id]
	state.event_state["pity"] = 0
	state.event_state["cooldowns"][event_id] = state.tick + int(row["cooldown_ticks"])
	if String(row["once"]) == "1":
		state.event_state["once"].append(event_id)
	var choices: Array = []
	for c in data.event_choices:
		if String(c["event_id"]) != event_id:
			continue
		if not _requires_met(String(c.get("requires", "")), state):
			continue
		choices.append({"choice_id": String(c["choice_id"]), "label": String(c["label"])})
	state.pending_event = {"event_id": event_id, "title_key": String(row["title_key"]),
		"voice": String(row["voice"]), "choices": choices}
	return state.pending_event

func _requires_met(requires: String, state: GameState) -> bool:
	if requires.strip_edges() == "":
		return true
	return TriggerDsl.evaluate(requires, state, data)

func apply_choice(choice_id: String, state: GameState) -> Dictionary:
	if state.pending_event.is_empty():
		return {}
	var event_id := String(state.pending_event["event_id"])
	var active := false
	for ch in state.pending_event["choices"]:
		if String(ch["choice_id"]) == choice_id:
			active = true
	if not active:
		return {}
	for c in data.event_choices:
		if String(c["event_id"]) == event_id and String(c["choice_id"]) == choice_id:
			var effects := EventEffects.apply(String(c["effects"]), state, data)
			var sig := {}
			for ax in OpinionDrift.AXES:
				sig[ax] = float(c[ax])
			var all_zero := true
			for ax in OpinionDrift.AXES:
				if sig[ax] != 0.0:
					all_zero = false
			var drift: Array = []
			if not all_zero:
				drift = OpinionDrift.apply(data, state, sig, String(c["label"]))
			state.pending_event = {}
			return {"event_id": event_id, "choice_id": choice_id,
				"label": String(c["label"]), "effects": effects, "drift": drift}
	return {}
```

`tick_engine.gd`: add `var events: EventSystem`, construct in `_init` (`events = EventSystem.new(d)`), add `var event: Dictionary = {}` to `TickReport` (+ `to_dict`), and in `advance` after `r.concerns = ...`:

```gdscript
	r.event = events.roll(state)
```

- [ ] **Step 5: Run full suite** — PASS (twin-run + mid-run-reload must stay green with events firing; if they diverge, the bug is real — investigate the rng call ordering, never mask). **Step 6: Commit** — `feat: EventSystem — roll, pity, chains, choices, drift`

---

### Task 6: The 20-event content pool + lint test

**Files:**
- Create: `data/random_events.csv` (+`.import`), `data/random_event_choices.csv` (+`.import`)
- Modify: `data/templates.csv` (scene + outcome lines per event)
- Test: `tests/engine/test_event_content.gd`

**Interfaces:**
- Consumes: the CSV schemas from Task 5, `RANDOM_EVENTS.md` (normative content source — read its "Starter pool" section in full), the effects/trigger vocabularies from Task 4.
- Produces: 20 events (`ev_01`…`ev_20`), each ≥2 choices; template keys `event_<event_id>` (scene text) and `event_<event_id>_<choice_id>` (outcome line) for every event/choice.

- [ ] **Step 1: Write the lint test FIRST** — `tests/engine/test_event_content.gd` (this is the task's spec-in-code):

```gdscript
extends GutTest

var data: DataRepository

func before_each() -> void:
	data = DataRepository.load_all("res://data")

func test_pool_inventory() -> void:
	assert_eq(data.events.size(), 20)
	for row in data.events:
		var id := String(row["event_id"])
		var n := 0
		for c in data.event_choices:
			if String(c["event_id"]) == id:
				n += 1
		assert_between(n, 2, 4, id + " choice count")
		assert_true(String(row["voice"]) in ["template", "mini", "flagship"], id + " voice")
		assert_gt(float(row["weight"]), 0.0, id)

func test_voice_tier_distribution() -> void:
	var flagship := 0
	for row in data.events:
		if String(row["voice"]) == "flagship":
			flagship += 1
	assert_eq(flagship, 2)  # ev_10 prophet debate, ev_19 orphan (spec/PRD cost posture)

func test_every_template_key_exists() -> void:
	var keys := {}
	for t in data.templates:
		keys[String(t["key"])] = true
	for row in data.events:
		assert_true(keys.has("event_" + String(row["event_id"])),
			"missing scene template for " + String(row["event_id"]))
	for c in data.event_choices:
		assert_true(keys.has("event_%s_%s" % [c["event_id"], c["choice_id"]]),
			"missing outcome template for %s/%s" % [c["event_id"], c["choice_id"]])

func test_effects_and_triggers_parse() -> void:
	var s := GameState.new_campaign(data, 7)
	s.tick = 30  # year>=2 triggers evaluable either way
	for row in data.events:
		TriggerDsl.evaluate(String(row["trigger"]), s, data)  # must not push unknown-clause errors
	for c in data.event_choices:
		for raw in String(c["effects"]).split(";", false):
			var op := raw.strip_edges()
			if op == "":
				continue
			var head := op.split(":")[0]
			assert_true(head in ["metric", "gold", "opinion", "schedule", "flag", "promise"],
				"unknown op '%s' in %s/%s" % [head, c["event_id"], c["choice_id"]])

func test_schedule_targets_exist() -> void:
	for c in data.event_choices:
		for raw in String(c["effects"]).split(";", false):
			var op := raw.strip_edges()
			if op.begins_with("schedule:"):
				var target := op.split(":")[1]
				assert_true(data.events_by_id.has(target),
					"schedule target %s missing (from %s)" % [target, c["event_id"]])

func test_every_event_reachable_or_chained() -> void:
	# every event is either trigger-reachable or the target of a schedule op
	var chained := {}
	for c in data.event_choices:
		for raw in String(c["effects"]).split(";", false):
			if raw.strip_edges().begins_with("schedule:"):
				chained[raw.strip_edges().split(":")[1]] = true
	for row in data.events:
		var trig := String(row["trigger"])
		var ok: bool = trig != "never" or chained.has(String(row["event_id"]))
		assert_true(ok, String(row["event_id"]) + " unreachable")
```

- [ ] **Step 2: Author `data/random_events.csv`** — header `event_id,category,trigger,weight,cooldown_ticks,once,voice,title_key` then EXACTLY these 20 rows (title_key = `event_<id>`; `never` marks chain-only events — see the reachability test; base events per `RANDOM_EVENTS.md` EV-01…EV-20 in order):

```csv
ev_01,folk,always,2,96,0,template,event_ev_01
ev_02,court,seat_filled=steward,3,96,0,mini,event_ev_02
ev_03,court,trait_at_court=wrathful,3,96,0,mini,event_ev_03
ev_04,folk,seat_filled=marshal&year>=2,2,96,1,mini,event_ev_04
ev_05,realm,unrest>30,3,96,0,mini,event_ev_05
ev_06,realm,grain<60&season=autumn,4,48,0,template,event_ev_06
ev_07,realm,action_since=TARIFF_ADJUST:24,3,96,0,mini,event_ev_07
ev_08,folk,year>=1,2,96,1,mini,event_ev_08
ev_09,realm,action_since=BUILD_ECONOMIC:48,3,96,0,mini,event_ev_09
ev_10,church,unrest>40,3,96,0,flagship,event_ev_10
ev_11,windfall,season=winter,2,96,0,mini,event_ev_11
ev_12,windfall,year>=2,2,96,1,mini,event_ev_12
ev_13,church,seat_filled=chaplain,2,120,1,mini,event_ev_13
ev_14,court,seat_filled=steward&year>=2,2,96,0,mini,event_ev_14
ev_15,folk,legitimacy>40&year>=2,2,96,1,mini,event_ev_15
ev_16,folk,always,2,120,1,template,event_ev_16
ev_17,personal,season=autumn&seat_filled=marshal,2,120,1,mini,event_ev_17
ev_18,realm,treasury<150,4,96,0,mini,event_ev_18
ev_19,personal,year>=3&legitimacy<60,2,999,1,flagship,event_ev_19
ev_20,court,season=winter,2,96,0,mini,event_ev_20
```

Deviations from `RANDOM_EVENTS.md` you must NOT make silently: EV-11's "coastal province owned, storm season" has no province system → trigger is `season=winter` (note it in the CSV-adjacent report); EV-18's "outstanding LOAN_TAKE" has no loan action yet → `treasury<150`; EV-20's "once-per-4-years" → `cooldown_ticks=96` with `once=0`. List every such adaptation in your report.

- [ ] **Step 3: Author `data/random_event_choices.csv`** — header `event_id,choice_id,label,centralism,militarism,orthodoxy,tax_incidence,expansionism,effects,requires`. Derive each event's choices from its `RANDOM_EVENTS.md` entry using these conversion rules:
  1. Signatures: transcribe the doc's explicit signature notes (e.g. EV-05 ③ "tax_incidence −40, centralism +30"); otherwise author values consistent with `action_signatures.csv`'s scale (±10…±50 on 1–2 axes, 0 elsewhere).
  2. Doc opinion effects on named seats → `opinion:<seat>:<±N>:<reason>` (reasons must contain no `:` or `;`).
  3. Metric/gold effects → `metric:`/`gold:` ops matching the doc's numbers (doc "small" ≈ 2–3, "+"≈5, "++"≈40 gold).
  4. Chains → `schedule:` where the follow-up exists as its own row is NOT required in slice 2: instead use `flag:` markers named in the doc's spirit (`flag:parrot_kept`, `flag:black_market`, `flag:orphan_ward`, …) EXCEPT ev_02's follow-up which IS implemented as chain proof: give ev_02 choice `ignore` the op `schedule:ev_18:24` (the debt collector arrives — thematically apt and exercises scheduling in real content).
  5. Relation/trait effects the engine can't express yet → nearest opinion/flag effect, commented in the report (spec §1: `# slice-4 upgrade`).
  6. Trait-gated options from the doc (e.g. EV-17's bold option) → `requires` clauses (`trait_at_court=bold`); shown/hidden deterministically.

  Three rows fully worked as the style reference (transcribe these verbatim, author the rest to match):

```csv
ev_01,accept,"Accept them with thanks",0,0,0,10,0,"metric:peasant_contentment:2; opinion:chancellor:2:touched by plain gratitude",
ev_01,feast,"Feast the court on them tonight",0,0,0,0,0,"gold:-10; opinion:steward:2:a merry table; opinion:marshal:2:a merry table",
ev_01,refuse,"Decline curtly",5,0,0,-10,0,"metric:peasant_contentment:-2; metric:legitimacy:-1",
ev_07,patrols,"Fund road patrols",10,10,0,0,0,"gold:-30; metric:unrest:-2",
ev_07,tariff,"Raise the tariff to pay for patrols",10,0,0,15,-15,"metric:tariff_rate:1; flag:black_market",
ev_07,hire,"Hire the bandits as toll-keepers",-10,0,-20,0,0,"gold:-15; metric:unrest:-3; opinion:spymaster:4:admires the realpolitik; opinion:chaplain:-5:appalled at brigands in office",
ev_19,ward,"Take the child as a ward",0,0,0,0,-20,"gold:-20; flag:orphan_ward; opinion:chaplain:6:mercy remembered; opinion:spymaster:-4:a claimant under our roof",
ev_19,monastery,"Leave him to the monastery watched",10,0,10,0,0,"flag:orphan_watched; opinion:spymaster:4:prudent; opinion:chaplain:-2:cold comfort",
ev_19,exile,"Exile the child abroad",20,0,0,0,10,"metric:legitimacy:-2; flag:orphan_exiled; opinion:chancellor:-4:the story will not die abroad",
```

- [ ] **Step 4: Template lines.** For every event add `event_<id>` (scene text in the doc's voice, ≤2 sentences, comma-quoted) and per choice `event_<id>_<choice_id>` (one outcome line). Example rows:

```csv
event_ev_01,,"A farmer walks the length of the hall and presents two geese — for the fairest lord since the old king, he says. The court holds its breath."
event_ev_01_accept,,"You accept them with thanks. Somewhere in the hall, someone decides you are the humble sort."
event_ev_01_feast,,"That night the court dines on goose, and the story grows fatter with each telling."
event_ev_01_refuse,,"The farmer bows and withdraws. The geese, insulted, honk all the way home."
```

- [ ] **Step 5: Run** — lint test drives you to completeness; iterate until the FULL suite passes. **Step 6: Commit** — `feat: 20-event starter pool with choices, templates, lint`

---

### Task 7: Event UI panel + turn gating

**Files:**
- Modify: `scripts/ui/game.gd` (apply_event_choice), `scripts/ui/council_screen.gd` (event panel)
- Test: extend `tests/ui/test_council_screen.gd`

**Interfaces:**
- Consumes: `TickReport.event`, `Game.engine.events.apply_choice`, `TemplateVoicer.line_for`, existing `_say` frames + calendar interlude flow.
- Produces: `Game.apply_event_choice(choice_id: String) -> Dictionary`. While `Game.state.pending_event` is non-empty: suggestions hidden, End Turn + Enter disabled, event scene framed in the transcript with one Button per choice; choosing narrates the outcome + effect/drift lines and restores normal input.

- [ ] **Step 1: Failing UI test** — append to `tests/ui/test_council_screen.gd`:

```gdscript
func test_pending_event_gates_turn_and_choice_resolves() -> void:
	Game.start_campaign(42)
	var screen: Node = load("res://scenes/council.tscn").instantiate()
	add_child_autofree(screen)
	screen.begin()
	await wait_frames(2)
	# Force a known event deterministically (bypasses the roll)
	Game.engine.events._fire("ev_01", Game.state)
	screen._render_event(Game.state.pending_event)
	await wait_frames(2)
	assert_true(screen.end_turn_button().disabled)
	assert_gt(screen.event_buttons().size(), 1)
	var pc0: float = Game.state.metrics["peasant_contentment"]
	screen.event_buttons()[0].pressed.emit()
	await wait_frames(2)
	assert_true(Game.state.pending_event.is_empty())
	assert_false(screen.end_turn_button().disabled)
	assert_ne(Game.state.metrics["peasant_contentment"], pc0)
```

- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.**

`game.gd`:

```gdscript
func apply_event_choice(choice_id: String) -> Dictionary:
	return engine.events.apply_choice(choice_id, state)
```

`council_screen.gd`: add `var event_box: VBoxContainer` and `var _event_buttons: Array = []` + accessor `func event_buttons() -> Array: return _event_buttons`. Create `event_box` in `_ready` between `transcript_scroll` and `suggestions_box`. In `_render_report`, after the suggestions render:

```gdscript
	if not report.event.is_empty():
		_render_event(report.event)
```

New methods:

```gdscript
func _render_event(ev: Dictionary) -> void:
	for child in event_box.get_children():
		child.queue_free()
	_event_buttons = []
	for child in suggestions_box.get_children():
		child.visible = false
	end_turn.disabled = true
	free_text.placeholder_text = "The court waits on your decision..."
	var scene_text := TemplateVoicer.line_for(Game.data, String(ev["title_key"]), [], Game.state.tick)
	_say({"speaker": "Herald", "text": scene_text})
	for ch in ev["choices"]:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.text = String(ch["label"])
		b.pressed.connect(_on_event_choice.bind(String(ch["choice_id"])))
		event_box.add_child(b)
		_event_buttons.append(b)

func _on_event_choice(choice_id: String) -> void:
	var event_id := String(Game.state.pending_event.get("event_id", ""))
	var out: Dictionary = Game.apply_event_choice(choice_id)
	if out.is_empty():
		return
	for b in _event_buttons:
		b.queue_free()
	_event_buttons = []
	_say({"speaker": "You", "text": String(out["label"])})
	_say({"speaker": "Herald", "text": TemplateVoicer.line_for(Game.data,
		"event_%s_%s" % [event_id, choice_id], [], Game.state.tick)})
	for d in out["drift"]:
		var c: Character = Game.state.characters[d["character_id"]]
		_say({"speaker": c.display_name, "text": "%+d — %s" % [int(d["delta"]), d["reason"]]})
	for child in suggestions_box.get_children():
		child.visible = true
	end_turn.disabled = false
	free_text.placeholder_text = "Give an order..."
	_render_portraits()
```

Also gate Enter: in `_unhandled_input`, add `and Game.state.pending_event.is_empty()` to the guard, and in `_on_interlude_finished` no change (the report's event renders after the interlude because `_render_report` runs there).

- [ ] **Step 4: Run full suite** — PASS. **Step 5: Commit** — `feat: event panel — choices gate the turn`

---

### Task 8: LLM voicing for events + parse-path updates

**Files:**
- Modify: `scripts/llm/voicer.gd` (voice_event), `scripts/llm/openai_client.gd` (model_flagship), `scripts/llm/prompt_builder.gd` (event + promise context), `scripts/llm/response_validator.gd` (EVENT_CHOICE), `scripts/ui/game.gd` + `scripts/ui/council_screen.gd` (route voiced scene text)
- Test: extend `tests/llm/test_voicer_fallback.gd`, `tests/llm/test_prompt_builder.gd`, `tests/llm/test_response_validator.gd`

**Interfaces:**
- Consumes: FakeClient seam, `Voicer` busy-guard pattern, `OpenAIClient.load_config`.
- Produces: config key `model_flagship` (default `"gpt-5.6-sol"`). `Voicer.voice_event(ev: Dictionary, state, data, cb)` — template tier calls back synchronously-deferred with the template scene line (`degraded=false`, it IS the intended voice); mini/flagship tiers call the model with template fallback, choosing `model_voice` vs `model_flagship` by `ev["voice"]`; cb gets `{ok, degraded, text}`. `ResponseValidator` accepts pseudo-action `EVENT_CHOICE` (params `{choice_id}`) without requiring it in `data.actions`; `Game.submit_free_text` routes an `EVENT_CHOICE` request to `apply_event_choice` when the choice is active, else rejects in-fiction. `PromptBuilder.parse_prompts` lists active event choices and the promise_code rule.

- [ ] **Step 1: Failing tests.** `tests/llm/test_response_validator.gd`:

```gdscript
func test_event_choice_pseudo_action_accepted() -> void:
	var out := ResponseValidator.parse(JSON.stringify({"actions":
		[{"action_code": "EVENT_CHOICE", "params": {"choice_id": "accept"}, "target": ""}]}), data)
	assert_true(out["ok"])
	assert_eq(out["actions"][0].action_code, "EVENT_CHOICE")
```

`tests/llm/test_prompt_builder.gd`:

```gdscript
func test_parse_prompt_lists_event_choices_and_promise_rule() -> void:
	var s := GameState.new_campaign(data, 42)
	var r := TickEngine.new(data).advance(s)
	s.pending_event = {"event_id": "ev_01", "title_key": "event_ev_01", "voice": "template",
		"choices": [{"choice_id": "accept", "label": "Accept them with thanks"}]}
	var p := PromptBuilder.parse_prompts("take the geese", r, s, data)
	assert_string_contains(p["system"], "EVENT_CHOICE")
	assert_string_contains(p["system"], "accept")
	assert_string_contains(p["system"], "promise_code")
```

`tests/llm/test_voicer_fallback.gd`:

```gdscript
func test_voice_event_template_tier_no_client_call() -> void:
	var fake := FakeClient.new()
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var ev := {"event_id": "ev_01", "title_key": "event_ev_01", "voice": "template", "choices": []}
	var got: Dictionary = {}
	v.voice_event(ev, s, data, func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_ne(String(got["text"]), "")

func test_voice_event_mini_falls_back_on_failure() -> void:
	var fake := FakeClient.new()  # canned_ok=false -> failure path
	add_child_autofree(fake)
	var v := Voicer.new(fake)
	add_child_autofree(v)
	var s := GameState.new_campaign(data, 42)
	var ev := {"event_id": "ev_01", "title_key": "event_ev_01", "voice": "mini", "choices": []}
	var got: Dictionary = {}
	v.voice_event(ev, s, data, func(res): got = res)
	await wait_frames(3)
	assert_true(got["ok"])
	assert_true(got["degraded"])
	assert_ne(String(got["text"]), "")
```

- [ ] **Step 2: Run** — FAIL. **Step 3: Implement.**

`openai_client.gd` `load_config` defaults gain `"model_flagship": "gpt-5.6-sol"`. `response_validator.gd`: at the top of the actions loop, before the `data.actions.has(code)` check:

```gdscript
		if code == "EVENT_CHOICE":
			actions.append(ActionRequest.make(code, params, String(a.get("target", ""))))
			continue
```

`prompt_builder.gd` `parse_prompts`: extend the system prompt with (append before the final "Current tick" line):

```gdscript
	var event_ctx := ""
	if not state.pending_event.is_empty():
		var ids := []
		for ch in state.pending_event["choices"]:
			ids.append("%s (%s)" % [ch["choice_id"], ch["label"]])
		event_ctx = "\nAn event awaits a decision. To resolve it use action_code EVENT_CHOICE with params {\"choice_id\": one of: %s}." % ", ".join(ids)
	var promise_rule := "\npromise_code in promises MUST be one of the legal action codes above."
```

and include `event_ctx + promise_rule` in the returned system string.

`voicer.gd`:

```gdscript
func voice_event(ev: Dictionary, state: GameState, data: DataRepository, cb: Callable) -> void:
	var fallback := TemplateVoicer.line_for(data, String(ev["title_key"]), [], state.tick)
	var tier := String(ev.get("voice", "template"))
	if tier == "template":
		cb.call_deferred({"ok": true, "degraded": false, "text": fallback})
		return
	if _busy:
		push_warning("Voicer busy — event scene degraded to template")
		cb.call({"ok": true, "degraded": true, "text": fallback})
		return
	_busy = true
	var model := String(_config.get("model_flagship", "gpt-5.6-sol")) if tier == "flagship" \
		else String(_config["model_voice"])
	var p := PromptBuilder.briefing_prompts_for_event(ev, state, fallback)
	client.completed.connect(func(ok: bool, text: String):
		_busy = false
		if ok and text != "":
			cb.call({"ok": true, "degraded": false, "text": text})
		else:
			cb.call({"ok": true, "degraded": true, "text": fallback}),
		CONNECT_ONE_SHOT)
	client.request_completion(p["system"], p["user"], model, false)
```

`prompt_builder.gd` companion:

```gdscript
static func briefing_prompts_for_event(ev: Dictionary, state: GameState, template_line: String) -> Dictionary:
	var system := """You narrate a single scene at a medieval royal court.
Rewrite the scene below in 2-3 vivid sentences, second person, present tense.
Do not add choices, numbers, or events beyond what the scene states."""
	return {"system": system, "user": "Scene (tick %d): %s" % [state.tick, template_line]}
```

`game.gd` route in `submit_free_text` (inside the executed-actions loop, before `try_execute`):

```gdscript
			if req.action_code == "EVENT_CHOICE":
				var ev_out := apply_event_choice(String(req.params.get("choice_id", "")))
				if ev_out.is_empty():
					rejected.append({"request": req, "error": "no such choice awaits"})
				else:
					executed.append({"action_code": "EVENT_CHOICE", "ok": true, "effects": [],
						"notes": String(ev_out["label"]), "drift": ev_out["drift"]})
				continue
```

`council_screen.gd` `_render_event`: replace the direct `_say` of scene_text with the voiced path:

```gdscript
	Game.voice_event_scene(ev, func(res: Dictionary):
		_say({"speaker": "Herald", "text": String(res["text"])}))
```

with `game.gd` gaining:

```gdscript
func voice_event_scene(ev: Dictionary, cb: Callable) -> void:
	_ensure_llm()
	voicer.voice_event(ev, state, data, cb)
```

(The Task 7 UI test still passes: offline template tier calls back deferred within a frame.)

- [ ] **Step 4: Run full suite** — PASS. **Step 5: Commit** — `feat: event voicing tiers + EVENT_CHOICE free-text path`

---

### Task 9: Slice-1 parked cleanup + acceptance

**Files:**
- Modify: `scripts/ui/game.gd` (client cleanup), `data/balance.csv` (concern_army_low), `CLAUDE.md` (data files note)
- Test: full suite + boot + manual acceptance notes

**Interfaces:** none new — this closes the ledgered parks.

- [ ] **Step 1: Leaked-client cleanup.** In `game.gd` `use_client_for_tests`: also `client.queue_free(); client = null` when a real client exists. Add:

```gdscript
func _exit_tree() -> void:
	if voicer != null:
		voicer.queue_free()
	if client != null:
		client.queue_free()
```

Run the suite and confirm the "2 ObjectDB instances were leaked at exit" warning is gone from the transcript (grep the run output; if instances remain, find the owner — do not shrug).

- [ ] **Step 2: Balance tune.** `data/balance.csv`: `concern_army_low` 50 → 45 (stops the Marshal complaining on tick 1; his standing-menu levy pitch remains). Update any test that asserted the tick-1 army concern (check `test_template_voicer.gd`'s trait-variant test — it sets `army_quality = 30.0` explicitly, so it stays valid; fix others only as the suite demands, never by weakening an assertion's intent).

- [ ] **Step 3: CLAUDE.md.** Under Key documents, extend the data bullet to name the new CSVs (`action_signatures.csv`, `random_events.csv`, `random_event_choices.csv`) as design-value homes.

- [ ] **Step 4: Acceptance run (automated parts).** Full suite green; boot check `--quit-after 120` no SCRIPT ERROR; then a scripted 60-tick campaign smoke via a temporary GUT test or the determinism harness with a longer loop confirming: ≥8 events fired, ≥1 chain fired (ev_18 via ev_02), ≥1 promise resolved, opinions have drifted from their starting values. Record per-criterion results in the report; visual/live-API checks are the human's.

- [ ] **Step 5: Commit** — `feat: slice 2 complete — cleanup, tuning, acceptance`

---

## Self-review notes (applied)

- Spec coverage: §2 → Tasks 1–2; §3 → Task 3; §4.1 data → Tasks 5–6; §4.2 engine → Task 5; §4.3 UI → Task 7; §5 LLM (incl. EVENT_CHOICE pseudo-action) → Task 8; §6 testing → embedded per task + Task 9 acceptance; §7 order preserved; slice-1 parks → Task 9.
- Type consistency: `EventSystem.roll/_fire/apply_choice`, `pending_event` shape `{event_id, title_key, voice, choices:[{choice_id, label}]}`, `TemplateVoicer.line_for`, `Game.apply_event_choice/voice_event_scene` used identically across Tasks 5–8. `OpinionDrift.AXES` shared by Tasks 1/5.
- Known simplifications called out in-plan: ev_11/ev_18/ev_20 trigger adaptations (Task 6 Step 2), relation effects → flags/opinions (Task 6 Step 3 rule 5), chains mostly flags except ev_02→ev_18 (rule 4).
- Worked-example numbers (−6 Odo, +1 Mirella, kept/broken promises) derived from current CSVs; implementers must re-derive before trusting.


