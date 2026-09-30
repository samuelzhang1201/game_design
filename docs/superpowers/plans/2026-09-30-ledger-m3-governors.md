# LEDGER M3 (+ L1) — Governors, Skimming and the Audit — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The flows a councillor governs (the war workshops, the supply lines) run as well as HE runs them — and he is the one who reports them; a venal governor skims and reports the flow whole, a second source or an audit exposes him, and the LEDGER draws the disagreeing accounts as split strands.

**Architecture:** A pure `Governance` (`scripts/engine/`) reads `data/ledger_governance.csv`, the council and the character (skill, opinion, traits, integrity) into an efficiency and a skim for each governed flow type. `WorkshopSystem.plan` and `SupplySystem.plan` apply them and carry both the truth and the governor's claim. Two orders, `GOVERNOR_SET` and `LEDGER_AUDIT`. The LEDGER's link accounts become a list (L1), built from the claims, the receiving side's own count and a fresh audit, drawn as strands.

**Tech Stack:** Godot 4.7, typed GDScript, GUT 9.4.

**Spec:** `docs/superpowers/specs/2026-09-30-ledger-governors-design.md`. Runs AFTER `2026-09-30-ledger-m1-m2-supply.md` on the same branch.

## Global Constraints

- Typed GDScript; no GDScript warnings (`@warning_ignore("integer_division")` on intentional integer divisions).
- Every number a `balance.csv` row or a `data/ledger_governance.csv` cell; no RNG anywhere in governance (a skim is a fixed share decided by traits and integrity — "a bias must be learnable").
- **Invariant 4**: every opinion change through `Character.change_opinion(delta, reason, state.tick)` with a reason.
- **Invariant 8**: `GOVERNOR_SET` and `LEDGER_AUDIT` carry rows in `policy_actions_court_additions.csv`, `action_signatures.csv`, `order_costs.csv`.
- **No numeric credibility in the LEDGER UI** — strands show sources and ages, never a percentage of belief.
- New engine classes `RefCounted`, no `Game.`; nothing under `scripts/ledger3d/` contains `Game.`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`. Test command and suite as in the M1+M2 plan (known pre-existing failure: `test_map3d_layers.gd::test_a_camera_move_refreshes_the_houses`).

## Review Focus

1. **An empty seat** — a flow with no governor runs at `min_permille`, skims nothing and cannot be audited (refusal, not a crash). Pinned in Task 1 and Task 3.
2. **A governor who leaves the council** (reassigned away, or the character gone) — `governor_of` falls back to the seat holder. Pinned in Task 1 (`test_a_gone_governor_falls_back_to_the_seat`).
3. **Two identical accounts** — an honest governor's claim equals the receiving side's count: ONE strand, both sources named, never two identical threads. Pinned in Task 4.
4. **An audit of an honest governor** — a letter with the true figures, the audited man's small goodwill loss, no "caught". Pinned in Task 3.
5. **An audit letter never becomes an Intel estimate** for a place (its subject is the ledger, not a province). Pinned in Task 3.

---

### Task 1: `Governance` — who governs, how well, how honestly

**Files:**
- Create: `data/ledger_governance.csv`, `scripts/engine/governance.gd`
- Modify: `data/balance.csv`, `scripts/engine/data_repository.gd` (load the table), `scripts/engine/game_state.gd` (`governors`, `skims`, `caught`, `records` + save)
- Test: `tests/engine/test_governance.gd`

**Interfaces:**
- Produces: `DataRepository.ledger_governance: Dictionary` (flow_type → row with int columns); `GameState.governors: Dictionary` (flow_type → character id, only reassigned), `skims: Dictionary` (character id → whole gold skimmed since his last audit), `caught: Dictionary` (character id → Array of `{flow, day, amount}`), `records: Dictionary` (character id → Array[String]); `Governance.FLOWS` (the table's keys, sorted), `governor_of(repo, state, flow) -> String`, `skim_of(repo, c: Character) -> int`, `factors(repo, state, flow) -> Dictionary` `{governor, skill, opinion, efficiency, skim, reasons: Array[String]}`, `seat_label(repo, flow) -> String`.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/engine/test_governance.gd
extends GutTest
## Governance (spec 2026-09-30-ledger-governors-design §2-3).

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)

func _steward() -> Character:
	return s.characters[String(s.council["steward"])]

func _plain(c: Character, skill: String, value: int) -> void:
	c.skills[skill] = value
	c.opinion = 50
	c.traits = []
	c.attributes["integrity"] = 50

func test_the_seat_holder_governs_by_default() -> void:
	assert_eq(Governance.governor_of(data, s, "workshop"), String(s.council["steward"]))
	assert_eq(Governance.governor_of(data, s, "supply_line"), String(s.council["marshal"]))

func test_a_gone_governor_falls_back_to_the_seat() -> void:
	s.governors["workshop"] = "char_nobody"
	assert_eq(Governance.governor_of(data, s, "workshop"), String(s.council["steward"]))

func test_skill_sets_the_ceiling() -> void:
	_plain(_steward(), "sk_steward", 8)
	assert_eq(int(Governance.factors(data, s, "workshop")["efficiency"]), 850)
	_steward().skills["sk_steward"] = 12
	assert_eq(int(Governance.factors(data, s, "workshop")["efficiency"]), 930)
	_steward().skills["sk_steward"] = 20
	assert_eq(int(Governance.factors(data, s, "workshop")["efficiency"]), 1000, "capped")
	_steward().skills["sk_steward"] = 0
	assert_eq(int(Governance.factors(data, s, "workshop")["efficiency"]), 690)

func test_a_sour_governor_gives_less() -> void:
	_plain(_steward(), "sk_steward", 12)
	_steward().opinion = -20
	var f := Governance.factors(data, s, "workshop")
	assert_eq(int(f["efficiency"]), 830, "930 less 20 × 5")
	assert_eq(f["reasons"].size(), 2, "the skill and the opinion each give their reason")

func test_the_venal_skim_the_low_skim_less_the_honest_never() -> void:
	var c := _steward()
	_plain(c, "sk_steward", 8)
	assert_eq(Governance.skim_of(data, c), 0)
	c.traits = ["venal"]
	assert_eq(Governance.skim_of(data, c), 200)
	c.traits = []
	c.attributes["integrity"] = 20
	assert_eq(Governance.skim_of(data, c), 100)
	c.traits = ["honest"]
	assert_eq(Governance.skim_of(data, c), 0, "honest never skims, whatever his integrity")

func test_an_empty_seat_runs_at_the_floor() -> void:
	s.council.erase("steward")
	var f := Governance.factors(data, s, "workshop")
	assert_eq(String(f["governor"]), "")
	assert_eq(int(f["efficiency"]), 600)
	assert_eq(int(f["skim"]), 0)

func test_the_new_state_survives_a_save() -> void:
	s.governors["workshop"] = "char_x"
	s.skims["char_x"] = 12
	s.caught["char_x"] = [{"flow": "workshop", "day": 40, "amount": 12}]
	s.records["char_x"] = ["Caught skimming the war workshops"]
	var back := GameState.from_dict(s.to_dict())
	assert_eq(back.governors, s.governors)
	assert_eq(int(back.skims["char_x"]), 12)
	assert_eq(int(back.caught["char_x"][0]["amount"]), 12)
	assert_eq(back.records["char_x"], ["Caught skimming the war workshops"])
```
(Use a real trait code for "venal"/"honest" — both exist in `data/character_traits.csv`.)

- [ ] **Step 2: Run it** — Expected: FAIL.

- [ ] **Step 3: Data**

`data/ledger_governance.csv`:
```csv
flow_type,seat,skill,base_permille,skill_mid,skill_step_permille,min_permille,max_permille,label,notes
workshop,steward,sk_steward,850,8,20,600,1000,the war workshops,spec 2026-09-30-ledger-governors-design §2
supply_line,marshal,sk_admin,850,8,20,600,1000,the supply lines,logistics is administration (Default)
```
`balance.csv`:
```csv
gov_opinion_cooperate,0,"LEDGER M3 (spec 2026-09-30-ledger-governors-design §2): a governor's opinion of the king at and above which he gives all his skill"
gov_opinion_step_permille,5,LEDGER M3: efficiency lost per point of opinion below gov_opinion_cooperate
gov_skim_permille,200,LEDGER M3: the share a venal governor (special_flag skims_treasury) skims
gov_skim_integrity_below,30,LEDGER M3: integrity under which a governor skims even without the trait
gov_skim_low_integrity_permille,100,LEDGER M3: the share a governor of low integrity skims
gov_audit_fresh_days,90,LEDGER M3: days an audit's figures stand as an account on the LEDGER
gov_caught_opinion,-12,LEDGER M3: a governor's opinion when an audit catches him skimming
gov_audited_opinion,-3,LEDGER M3: a governor's opinion when the crown's clerks go through his books
gov_passed_over_opinion,-8,LEDGER M3: the displaced governor's opinion when his flow is given to another
gov_new_governor_opinion,4,LEDGER M3: the new governor's opinion when he is given a flow
```
`DataRepository`: `var ledger_governance: Dictionary = {}` and in `_load` after the ledger tables:
```gdscript
	if not _load_if_present(dir + "/ledger_governance.csv",
			["flow_type", "seat", "skill", "base_permille", "skill_mid", "skill_step_permille", "min_permille",
				"max_permille", "label"],
			func(r): ledger_governance[String(r["flow_type"])] = {"seat": String(r["seat"]),
				"skill": String(r["skill"]), "base_permille": int(r["base_permille"]),
				"skill_mid": int(r["skill_mid"]), "skill_step_permille": int(r["skill_step_permille"]),
				"min_permille": int(r["min_permille"]), "max_permille": int(r["max_permille"]),
				"label": String(r["label"])}):
		return false
```
`GameState` (beside `workshop_rate`), each with a doc comment, and in `to_dict` / `from_dict` with `d.get(key, {})` defaults (`_encode_values` / `_decode_values` for `caught`, which holds arrays of dictionaries, like `couriers`):
```gdscript
## flow type -> character id, only flows given away from their seat (M3).
var governors: Dictionary = {}
## character id -> whole gold skimmed since his last audit (M3; the truth).
var skims: Dictionary = {}
## character id -> [{flow, day, amount}] every time an audit caught him (M3).
var caught: Dictionary = {}
## character id -> [record lines], permanent, each a reason (M3; the debrief's data).
var records: Dictionary = {}
```

- [ ] **Step 4: `Governance`**

```gdscript
# scripts/engine/governance.gd
class_name Governance
extends RefCounted
## Who governs a flow and how (spec 2026-09-30-ledger-governors-design §2-3):
## the seat holder unless the flow was given to another councillor; his
## skill sets the ceiling, his opinion of the king how much he gives, his
## traits and integrity whether he skims. Pure; no RNG.


static func flows(repo: DataRepository) -> Array:
	var out: Array = repo.ledger_governance.keys()
	out.sort()
	return out


static func seat_label(repo: DataRepository, flow: String) -> String:
	var seat := String((repo.ledger_governance.get(flow, {}) as Dictionary).get("seat", ""))
	return String((repo.seats.get(seat, {}) as Dictionary).get("label", seat))


static func governor_of(repo: DataRepository, state: GameState, flow: String) -> String:
	var given := String(state.governors.get(flow, ""))
	if given != "" and state.characters.has(given):
		return given
	var seat := String((repo.ledger_governance.get(flow, {}) as Dictionary).get("seat", ""))
	return String(state.council.get(seat, ""))


static func skim_of(repo: DataRepository, c: Character) -> int:
	var flags: Array = []
	for t in c.traits:
		flags.append(String((repo.traits.get(String(t), {}) as Dictionary).get("special_flag", "")))
	if "truthful_advice" in flags:
		return 0
	if "skims_treasury" in flags:
		return int(repo.bal("gov_skim_permille"))
	if int(c.attributes.get("integrity", 50)) < int(repo.bal("gov_skim_integrity_below")):
		return int(repo.bal("gov_skim_low_integrity_permille"))
	return 0


static func factors(repo: DataRepository, state: GameState, flow: String) -> Dictionary:
	var row: Dictionary = repo.ledger_governance.get(flow, {})
	var lo := int(row.get("min_permille", 1000))
	var hi := int(row.get("max_permille", 1000))
	var gid := governor_of(repo, state, flow)
	if gid == "":
		return {"governor": "", "skill": 0, "opinion": 0, "efficiency": lo, "skim": 0,
			"reasons": ["no one governs it"]}
	var c: Character = state.characters[gid]
	var skill := int(c.skills.get(String(row["skill"]), 0))
	var by_skill := (skill - int(row["skill_mid"])) * int(row["skill_step_permille"])
	var reasons: Array[String] = ["skill %d: %+d‰" % [skill, by_skill]]
	var eff := int(row["base_permille"]) + by_skill
	var coop := int(repo.bal("gov_opinion_cooperate"))
	if c.opinion < coop:
		var cut := (coop - c.opinion) * int(repo.bal("gov_opinion_step_permille"))
		eff -= cut
		reasons.append("opinion %d: −%d‰" % [c.opinion, cut])
	return {"governor": gid, "skill": skill, "opinion": c.opinion, "efficiency": clampi(eff, lo, hi),
		"skim": skim_of(repo, c), "reasons": reasons}
```

- [ ] **Step 5: Import, run, commit** — `feat(governance): who governs a flow, how well and how honestly`

---

### Task 2: The flows take their governor — truth and claim

**Files:**
- Modify: `scripts/engine/workshop_system.gd` (`plan`, `settle_month`), `scripts/engine/supply_system.gd` (`plan`, `settle_month`), `tests/engine/test_workshop_system.gd`, `tests/engine/test_supply_system.gd`, `tests/engine/test_ledger_supply.gd` (fixtures)
- Test: `tests/engine/test_governed_flows.gd`

**Interfaces:**
- Consumes: `Governance.factors` (Task 1).
- Produces: workshop plan rows gain `efficiency`, `skim`, `governor`, `made` (the truth before the skim), `skimmed`, `claimed` (= `made`: he reports the flow whole); `make` stays what REACHES the lord's stores (`made − skimmed`). Supply plan rows gain `efficiency`, `skim`, `governor`, `skimmed` (gold), `claimed` (units he says arrived), and `delivered` stays the truth. `settle_month` of both adds each row's `skimmed` to `state.skims[governor]`.

- [ ] **Step 1: Pin the old tests to an able, honest governor**

Add to the three existing test files' `before_each` (after the state is built) a call to this helper, defined in each file:
```gdscript
## An able, honest governor: efficiency 1000, no skim — so the M1/M2
## figures stay the plain arithmetic they were written against.
func _able_honest_governors() -> void:
	for pair in [["steward", "sk_steward"], ["marshal", "sk_admin"]]:
		var c: Character = s.characters[String(s.council[pair[0]])]
		c.skills[pair[1]] = 16
		c.opinion = 50
		c.traits = []
		c.attributes["integrity"] = 50
```
(In `test_workshop_system.gd`'s twin-state tick test, call it before `GameState.from_dict(s.to_dict())` so both twins carry it.)

- [ ] **Step 2: Write the failing test**

```gdscript
# tests/engine/test_governed_flows.gd
extends GutTest
## The truth and the claim (spec 2026-09-30-ledger-governors-design §3).

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

func _set(seat: String, skill: String, value: int, traits: Array) -> Character:
	var c: Character = s.characters[String(s.council[seat])]
	c.skills[skill] = value
	c.opinion = 50
	c.traits = traits
	c.attributes["integrity"] = 50
	return c

func test_a_venal_steward_skims_the_workshops_and_reports_them_whole() -> void:
	var st := _set("steward", "sk_steward", 16, ["venal"])
	var row: Dictionary = WorkshopSystem.plan(data, s)[0]
	assert_eq(int(row["made"]), 28)
	assert_eq(int(row["skimmed"]), 5, "a fifth of 28, whole gold")
	assert_eq(int(row["make"]), 23, "what reaches the lord's stores")
	assert_eq(int(row["claimed"]), 28, "what he reports")
	WorkshopSystem.settle_month(data, s)
	assert_eq(int(s.skims[st.id]), 5)

func test_a_clumsy_steward_makes_less_and_says_so() -> void:
	_set("steward", "sk_steward", 8, [])
	var row: Dictionary = WorkshopSystem.plan(data, s)[0]
	assert_eq(int(row["made"]), 23, "28 × 850‰, whole")
	assert_eq(int(row["claimed"]), 23)
	assert_eq(int(row["skimmed"]), 0)

func test_a_venal_marshal_skims_the_supply_gold() -> void:
	var m := _set("marshal", "sk_admin", 16, ["venal"])
	s.metrics["strategic"] = 1000000.0
	for c in s.regiments.keys():
		s.regiments[c]["supplies"] = 0
	var rows := SupplySystem.plan(data, s)
	var row: Dictionary = rows[0]
	assert_eq(int(row["skimmed"]), int(row["paid"]) * 200 / 1000)
	assert_lt(int(row["delivered"]), int(row["claimed"]), "less reaches the ranks than he reports")
	SupplySystem.settle_month(data, s)
	assert_gt(int(s.skims[m.id]), 0)

func test_an_honest_able_marshal_delivers_what_he_says() -> void:
	_set("marshal", "sk_admin", 16, ["honest"])
	s.metrics["strategic"] = 1000000.0
	for row: Dictionary in SupplySystem.plan(data, s):
		assert_eq(int(row["delivered"]), int(row["claimed"]))
```
(Adjust the "whole" arithmetic in the comments only if the code's integer order differs; the values follow from `make = take × ratio × eff / 10⁶` with take 40, ratio 700.)

- [ ] **Step 3: Run it** — Expected: FAIL.

- [ ] **Step 4: Workshop**

In `WorkshopSystem.plan`, read `var g := Governance.factors(repo, state, "workshop")` once before the loop and replace the row's `make`:
```gdscript
		@warning_ignore("integer_division")
		var made := take * ratio / 1000 * int(g["efficiency"]) / 1000
		@warning_ignore("integer_division")
		var skimmed := made * int(g["skim"]) / 1000
		out.append({"cell": cell, "rate": rate, "take": take, "made": made, "skimmed": skimmed,
			"make": made - skimmed, "claimed": made, "efficiency": int(g["efficiency"]),
			"skim": int(g["skim"]), "governor": String(g["governor"])})
```
Update `test_workshop_system.gd`'s exact-dictionary asserts to the new keys (with the able honest governor: `made` 28, `skimmed` 0, `make` 28, `claimed` 28, `efficiency` 1000, `skim` 0, `governor` the steward's id). In `settle_month`, sum `skimmed` per governor and add it to `state.skims` (whole gold, the governor's id as key, skipping `""`).

- [ ] **Step 5: Supply**

In `SupplySystem.plan`, read `var g := Governance.factors(repo, state, "supply_line")` once; after `paid` is known per row:
```gdscript
		@warning_ignore("integer_division")
		var skimmed := int(paid[i]) * int(g["skim"]) / 1000
		var price := maxi(int(repo.bal("army_supply_gold_permille")), 1)
		@warning_ignore("integer_division")
		var bought := int(row["ship"]) if int(paid[i]) >= int(row["gold"]) and skimmed == 0 \
			else (int(paid[i]) - skimmed) * 1000 / price
		@warning_ignore("integer_division")
		var claimed_units := int(row["ship"]) if int(paid[i]) >= int(row["gold"]) else int(paid[i]) * 1000 / price
		var keep := 1000 - int(row["loss_permille"])
		@warning_ignore("integer_division")
		row["delivered"] = mini(bought * keep / 1000 * int(g["efficiency"]) / 1000, int(row["need"]))
		@warning_ignore("integer_division")
		row["claimed"] = mini(claimed_units * keep / 1000 * int(g["efficiency"]) / 1000, int(row["need"]))
		row["skimmed"] = skimmed
		row["efficiency"] = int(g["efficiency"])
		row["skim"] = int(g["skim"])
		row["governor"] = String(g["governor"])
```
(replacing the M1 `delivered` computation). `settle_month` adds each row's `skimmed` to `state.skims[governor]`. With efficiency 1000 and no skim, every M1 figure is unchanged — the M1 tests, pinned by Step 1, must still pass.

- [ ] **Step 6: Run the new test and the three pinned files** — Expected: PASS.

- [ ] **Step 7: Commit** — `feat(governance): the workshops and supply lines run as their governor runs them`

---

### Task 3: `GOVERNOR_SET` and `LEDGER_AUDIT`

**Files:**
- Modify: `data/policy_actions_court_additions.csv`, `data/action_signatures.csv`, `data/order_costs.csv`, `scripts/engine/action_system.gd`
- Create: `scripts/engine/audit_writer.gd`
- Test: `tests/engine/test_governor_orders.gd`

**Interfaces:**
- Consumes: `Governance`, `WorkshopSystem.plan`, `SupplySystem.plan`, `MissiveLog.make / add / subject / exact`, `Character.change_opinion`, `state.calendar` words for the record line (read `GameState` for `season()` / `year()`).
- Produces: orders `GOVERNOR_SET {flow, character}`, `LEDGER_AUDIT {flow}`; `AuditWriter.facts(repo, state, flow) -> Array` (one `MissiveLog.exact` per instance keyed by its LEDGER node id — `workshop:<cell>` with the true `make`, `supply_line:<code>` with the true `delivered` — plus `total`); missive kind `audit`, column `credible`, subject `MissiveLog.subject("ledger", flow, -1, Vector2.ZERO)`.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/engine/test_governor_orders.gd
extends GutTest
## GOVERNOR_SET and LEDGER_AUDIT (spec 2026-09-30-ledger-governors-design §3).

var data: DataRepository
var s: GameState
var sys: ActionSystem
var cell := -1

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	sys = ActionSystem.new(data)
	RealmEconomy.forget()
	cell = int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[0])
	MapManors.build(data, s, cell, WorkshopSystem.BUILDING, "a test workshop")

func after_each() -> void:
	RealmEconomy.forget()

func _steward() -> Character:
	return s.characters[String(s.council["steward"])]

func test_giving_a_flow_to_another_councillor() -> void:
	var other := String(s.council["chancellor"])
	var was := _steward()
	var was_opinion := was.opinion
	var req := ActionRequest.make("GOVERNOR_SET", {"flow": "workshop", "character": other})
	assert_eq(sys.validate(req, s), "")
	sys.execute(req, s)
	assert_eq(Governance.governor_of(data, s, "workshop"), other)
	assert_eq(was.opinion, was_opinion + int(data.bal("gov_passed_over_opinion")))
	assert_string_contains(String(was.opinion_log[-1]["reason"]), "war workshops")

func test_giving_it_refusals() -> void:
	assert_ne(sys.validate(ActionRequest.make("GOVERNOR_SET", {"flow": "workshop",
		"character": String(s.council["steward"])}), s), "", "he already holds it")
	assert_ne(sys.validate(ActionRequest.make("GOVERNOR_SET", {"flow": "workshop",
		"character": "you"}), s), "", "only a councillor")
	assert_ne(sys.validate(ActionRequest.make("GOVERNOR_SET", {"flow": "moat",
		"character": String(s.council["chancellor"])}), s), "", "no such flow")

func test_an_audit_catches_a_skimmer() -> void:
	var st := _steward()
	st.traits = ["venal"]
	s.metrics["lord_civil"] = 100.0
	WorkshopSystem.settle_month(data, s)
	var skimmed := int(s.skims[st.id])
	assert_gt(skimmed, 0)
	var n := s.missives.size()
	var op := st.opinion
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	assert_eq(s.missives.size(), n + 1)
	var m: Dictionary = s.missives[-1]
	assert_eq(String(m["kind"]), "audit")
	assert_eq(String(m["column"]), "credible")
	assert_eq(int(s.caught[st.id][0]["amount"]), skimmed)
	assert_eq(int(s.skims.get(st.id, 0)), 0, "the count starts again")
	assert_string_contains(String(s.records[st.id][0]), "Caught skimming the war workshops")
	assert_eq(st.opinion, op + int(data.bal("gov_audited_opinion")) + int(data.bal("gov_caught_opinion")))

func test_an_audit_of_an_honest_man_finds_nothing() -> void:
	var st := _steward()
	st.traits = ["honest"]
	var op := st.opinion
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	assert_false(s.caught.has(st.id))
	assert_eq(st.opinion, op + int(data.bal("gov_audited_opinion")))

func test_no_governor_no_audit() -> void:
	s.council.erase("steward")
	assert_ne(sys.validate(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s), "")

func test_an_audit_letter_is_no_estimate_of_a_place() -> void:
	var home := MapManors.home_province(data, s)
	var p: Dictionary = data.provinces[home]
	var subj := MissiveLog.subject("province", home, -1, Vector2(float(p["center_x"]), float(p["center_y"])))
	var before := Intel.fact(data, s, subj, "people", 1234)
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	assert_eq(Intel.fact(data, s, subj, "people", 1234), before)

func test_both_orders_are_catalogued_with_costs() -> void:
	for code in ["GOVERNOR_SET", "LEDGER_AUDIT"]:
		assert_true(data.actions.has(code))
		assert_true(data.order_costs.has(code))
```

- [ ] **Step 2: Run it** — Expected: FAIL.

- [ ] **Step 3: Catalogue rows**

`policy_actions_court_additions.csv`:
```csv
GOVERNOR_SET,administration,Give a flow to a councillor,none,0.5,none,0,0,,governor_set,2,yes,no,"params: flow (data/ledger_governance.csv), character (a councillor). He governs it from now on; the one passed over takes it ill (spec 2026-09-30-ledger-governors-design)."
LEDGER_AUDIT,intrigue,Audit a flow,none,1.0,none,0,0,,ledger_audit,2,no,no,"params: flow. The crown's clerks go through the governor's books: a credible letter with the month's true figures, and a skimmer caught (spec 2026-09-30-ledger-governors-design)."
```
`action_signatures.csv`:
```csv
GOVERNOR_SET,,5,0,0,0,0,the crown chooses its own men
LEDGER_AUDIT,,10,0,0,0,0,the crown's clerks in a councillor's books
```
`order_costs.csv`:
```csv
GOVERNOR_SET,gold:-2:the chancery's letters of appointment,1,the passed-over governor's goodwill is charged by the order itself
LEDGER_AUDIT,gold:-15:the clerks' fees,1,the audited governor's goodwill is charged by the order itself
```

- [ ] **Step 4: `AuditWriter`**

```gdscript
# scripts/engine/audit_writer.gd
class_name AuditWriter
extends RefCounted
## An audit's letter (spec 2026-09-30-ledger-governors-design §3): the
## month's TRUE figures of a governed flow, one fact per instance keyed by
## its LEDGER node id, and the total.


static func facts(repo: DataRepository, state: GameState, flow: String) -> Array:
	var out: Array = []
	var total := 0
	match flow:
		"workshop":
			for row: Dictionary in WorkshopSystem.plan(repo, state):
				out.append(MissiveLog.exact("workshop:%d" % int(row["cell"]),
					"War workshop at " + MapManors.label_of(repo, int(row["cell"])), int(row["make"])))
				total += int(row["make"])
		"supply_line":
			for row: Dictionary in SupplySystem.plan(repo, state):
				var code := String(row["code"])
				out.append(MissiveLog.exact("supply_line:" + code,
					"To " + String(ArmySystem.regiment(repo, code).get("label", code)), int(row["delivered"])))
				total += int(row["delivered"])
	out.append(MissiveLog.exact("total", "In all, this month", total))
	return out
```

- [ ] **Step 5: Validate and execute**

In `ActionSystem.validate`:
```gdscript
		"GOVERNOR_SET":
			var flow := String(req.params.get("flow", ""))
			if not data.ledger_governance.has(flow):
				return "No such flow: " + flow
			var who := String(req.params.get("character", ""))
			if not who in state.council.values():
				return "Only a councillor can govern %s" % String(data.ledger_governance[flow]["label"])
			if who == Governance.governor_of(data, state, flow):
				return "He already governs %s" % String(data.ledger_governance[flow]["label"])
		"LEDGER_AUDIT":
			var flow := String(req.params.get("flow", ""))
			if not data.ledger_governance.has(flow):
				return "No such flow: " + flow
			if Governance.governor_of(data, state, flow) == "":
				return "No one governs %s: there are no books to audit" % String(data.ledger_governance[flow]["label"])
```
In `execute`:
```gdscript
		"GOVERNOR_SET":
			var flow := String(req.params["flow"])
			var label := String(data.ledger_governance[flow]["label"])
			var was := Governance.governor_of(data, state, flow)
			var who := String(req.params["character"])
			var seat_holder := String(state.council.get(String(data.ledger_governance[flow]["seat"]), ""))
			if who == seat_holder:
				state.governors.erase(flow)
			else:
				state.governors[flow] = who
			if was != "" and state.characters.has(was):
				(state.characters[was] as Character).change_opinion(int(data.bal("gov_passed_over_opinion")),
					"passed over: %s given to another" % label, state.tick)
			(state.characters[who] as Character).change_opinion(int(data.bal("gov_new_governor_opinion")),
				"given %s to govern" % label, state.tick)
			effects.append({"metric": "council", "delta": 0.0, "reason": "%s now governs %s"
				% [(state.characters[who] as Character).display_name, label]})
		"LEDGER_AUDIT":
			var flow := String(req.params["flow"])
			var label := String(data.ledger_governance[flow]["label"])
			var gid := Governance.governor_of(data, state, flow)
			var c: Character = state.characters[gid]
			c.change_opinion(int(data.bal("gov_audited_opinion")),
				"the crown's clerks went through his books on %s" % label, state.tick)
			MissiveLog.add(data, state, MissiveLog.make("audit", "credible", state.absolute_day(),
				MissiveLog.subject("ledger", flow, -1, Vector2.ZERO), "Audit — " + label.capitalize(),
				AuditWriter.facts(data, state, flow)))
			var amount := int(state.skims.get(gid, 0))
			if amount > 0:
				if not state.caught.has(gid):
					state.caught[gid] = []
				state.caught[gid].append({"flow": flow, "day": state.absolute_day(), "amount": amount})
				if not state.records.has(gid):
					state.records[gid] = []
				state.records[gid].append("Caught skimming %s, %s of year %d (%d gold)"
					% [label, state.season(), state.year(), amount])
				state.skims.erase(gid)
				c.change_opinion(int(data.bal("gov_caught_opinion")), "caught skimming %s" % label, state.tick)
				effects.append({"metric": "council", "delta": 0.0, "reason": "%s caught skimming %s"
					% [c.display_name, label]})
```
Read `GameState` for `season()` / `year()` spellings (TriggerDsl uses `state.season()` and `state.year()`); capitalise the record line's first word as the test expects ("Caught skimming the war workshops, …").

Read `Intel._latest` (`intel.gd:211+`) to confirm a subject of kind `ledger` never matches a place query; if its point fallback could match (0,0), make `_latest` skip missives whose subject kind is `ledger` and say why in a comment — `test_an_audit_letter_is_no_estimate_of_a_place` pins it.

- [ ] **Step 6: Run the test, `test_order_costs.gd`, `test_missive*.gd`** — Expected: PASS.

- [ ] **Step 7: Commit** — `feat(governance): give a flow to another councillor; audit it and catch a skimmer`

---

### Task 4: The LEDGER — accounts that differ, governors and skims drawn

**Files:**
- Modify: `data/ledger_link_types.csv`, `data/ledger_actions.csv`, `scripts/engine/ledger_resolvers.gd`, `scripts/engine/ledger.gd` (`_believed`, `actions_for`), `scripts/engine/ledger_cards.gd` (character card records), `scripts/ledger3d/ledger_view_3d.gd` (strands), `scripts/ui/ledger_screen.gd` (thread ids with a strand suffix; `actions_for` with state), `data/balance.csv`, the ontology spec §3 rows
- Test: `tests/engine/test_ledger_governors.gd`

**Interfaces:**
- Consumes: Tasks 1-3; the L0 snapshot and view.
- Produces:
  - A resolver link may carry `claims: Array` of `{value: int, source: String}` — when present, `Ledger` builds the link's `accounts` from them (level `full`, today's day) instead of from `flow`/`subj`, appends the latest audit's figure for that node when it is no older than `gov_audit_fresh_days` (source "the audit of <day words>"), and MERGES accounts of equal value into one (sources joined with "; "). `flow` becomes the first account's value.
  - Live links `governs` (character → workshop), `governs_supply` (character → supply_line), `skims` (character → workshop), `skims_supply` (character → supply_line) — the skim links only for `state.caught`, flow = the caught total.
  - `Ledger.actions_for(repo, node_id, state: GameState = null)` expands a row whose params contain `character=@council` into one row per councillor (label "Give it to <name>"), skipping the current governor; audit and give rows target the THREADS `converts_out` / `supplies_out`.
  - View: a link with n > 1 accounts is drawn as n strands `ledger_strand_gap_m` apart, each its own width and ink; a strand's pick id is `<link id>#<i>` and the screen strips `#<i>`.

- [ ] **Step 1: Write the failing test**

```gdscript
# tests/engine/test_ledger_governors.gd
extends GutTest
## The governor is the reporter (spec 2026-09-30-ledger-governors-design §4).

var data: DataRepository
var s: GameState
var sys: ActionSystem
var cell := -1

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	sys = ActionSystem.new(data)
	RealmEconomy.forget()
	cell = int(MapManors.manors_of_province(data, MapManors.home_province(data, s), s)[0])
	MapManors.build(data, s, cell, WorkshopSystem.BUILDING, "a test workshop")
	s.metrics["lord_civil"] = 100.0
	s.metrics["strategic"] = 1000000.0
	for c in s.regiments.keys():
		s.regiments[c]["supplies"] = 0

func after_each() -> void:
	RealmEconomy.forget()

func _link(snap: Dictionary, type: String) -> Dictionary:
	for l: Dictionary in snap["links"]:
		if String(l["type"]) == type:
			return l
	return {}

func _marshal(traits: Array) -> Character:
	var m: Character = s.characters[String(s.council["marshal"])]
	m.skills["sk_admin"] = 16
	m.opinion = 50
	m.traits = traits
	m.attributes["integrity"] = 50
	return m

func test_the_ontology_stays_clean() -> void:
	assert_eq(Ledger.validate(data), [] as Array[String])

func test_an_honest_marshal_is_one_strand_with_both_sources() -> void:
	_marshal(["honest"])
	var code := String(SupplySystem.plan(data, s)[0]["code"])
	var out := _link(Ledger.snapshot(data, s, "war", {"id": "regiment:" + code}), "supplies_out")
	assert_eq(out["accounts"].size(), 1)
	assert_string_contains(String(out["accounts"][0]["source"]), "the regiment's own count")

func test_a_venal_marshal_splits_the_thread() -> void:
	var m := _marshal(["venal"])
	var row: Dictionary = SupplySystem.plan(data, s)[0]
	var out := _link(Ledger.snapshot(data, s, "war", {"id": "regiment:" + String(row["code"])}), "supplies_out")
	assert_eq(out["accounts"].size(), 2)
	assert_eq(int(out["accounts"][0]["value"]), int(row["claimed"]))
	assert_string_contains(String(out["accounts"][0]["source"]), m.display_name)
	assert_eq(int(out["accounts"][1]["value"]), int(row["delivered"]))

func test_a_fresh_audit_is_an_account_of_its_own() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.traits = ["venal"]
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	var out := _link(Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell}), "converts_out")
	assert_eq(out["accounts"].size(), 2, "the steward's word and the audit's figure")
	assert_string_contains(String(out["accounts"][1]["source"]), "audit")

func test_skims_are_drawn_only_once_caught() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	st.traits = ["venal"]
	WorkshopSystem.settle_month(data, s)
	var ego := {"id": "character:" + st.id}
	assert_true(_link(Ledger.snapshot(data, s, "all", ego), "skims").is_empty())
	sys.execute(ActionRequest.make("LEDGER_AUDIT", {"flow": "workshop"}), s)
	var skims := _link(Ledger.snapshot(data, s, "all", ego), "skims")
	assert_eq(int(skims["flow"]), int(s.caught[st.id][0]["amount"]))

func test_the_governor_is_drawn() -> void:
	var st := String(s.council["steward"])
	var gov := _link(Ledger.snapshot(data, s, "economy", {"id": "workshop:%d" % cell}), "governs")
	assert_eq(String(gov["from"]), "character:" + st)

func test_the_thread_offers_the_audit_and_every_other_councillor() -> void:
	var rows := Ledger.actions_for(data, "converts_out|workshop:%d|type:strategic_goods" % cell, s)
	var codes: Array = rows.map(func(a: Dictionary) -> String: return String(a["code"]))
	assert_has(codes, "LEDGER_AUDIT")
	var gives: Array = rows.filter(func(a: Dictionary) -> bool: return String(a["code"]) == "GOVERNOR_SET")
	assert_eq(gives.size(), s.council.size() - 1, "every councillor but the steward")
	assert_string_contains(String(gives[0]["label"]), "Give it to ")

func test_a_characters_card_carries_his_record() -> void:
	var st: Character = s.characters[String(s.council["steward"])]
	s.records[st.id] = ["Caught skimming the war workshops, spring of year 1 (5 gold)"]
	var e := LedgerCards.entry(data, s, "character:" + st.id, Ledger.snapshot(data, s, "court", {}))
	assert_has(e["lines"], "Caught skimming the war workshops, spring of year 1 (5 gold)")
```

- [ ] **Step 2: Run it** — Expected: FAIL.

- [ ] **Step 3: Data**

`ledger_link_types.csv`: replace the planned `governs` and `skims` rows and add their supply twins:
```csv
governs,character,workshop,governs,economy|war|court|all,live,governs,,,,,
governs_supply,character,supply_line,governs,war|court|all,live,governs,,,,,
skims,character,workshop,skims,intelligence|economy|all,live,skims,,,,,drawn only once an audit has caught him
skims_supply,character,supply_line,skims,intelligence|war|all,live,skims,,,,,drawn only once an audit has caught him
```
(Keep the planned `faction_governs` row as it is.)
`ledger_actions.csv`:
```csv
converts_out,LEDGER_AUDIT,Audit the war workshops,flow=workshop,0
converts_out,GOVERNOR_SET,Give it to,flow=workshop|character=@council,0
supplies_out,LEDGER_AUDIT,Audit the supply lines,flow=supply_line,0
supplies_out,GOVERNOR_SET,Give it to,flow=supply_line|character=@council,0
```
`balance.csv`: `ledger_strand_gap_m,0.35,"LEDGER L1 (spec 2026-09-30-ledger-governors-design §4): the gap between two strands of one thread whose accounts differ"`

- [ ] **Step 4: Resolvers**

Add `"governs"` and `"skims"` to `NAMES`; dispatch both by the row's `to_type` (`workshop` → flow `workshop`, `supply_line` → flow `supply_line`):
```gdscript
		"governs":
			return _governs(repo, state, id, String(row["to_type"]), false)
		"skims":
			return _governs(repo, state, id, String(row["to_type"]), true)
```
```gdscript
static func _instances_of_flow(repo: DataRepository, state: GameState, flow: String) -> Array:
	var out: Array = []
	if flow == "workshop":
		for c: int in WorkshopSystem.cells(state):
			out.append("workshop:%d" % c)
	else:
		for row: Dictionary in SupplySystem.plan(repo, state):
			out.append("supply_line:" + String(row["code"]))
	return out


static func _governs(repo: DataRepository, state: GameState, id: String, flow: String, skims: bool) -> Array:
	var gid := Governance.governor_of(repo, state, flow)
	if skims:
		var total := 0
		for hit: Dictionary in state.caught.get(gid, []):
			if String(hit["flow"]) == flow:
				total += int(hit["amount"])
		if gid == "" or total == 0:
			return []
		if id == "":
			return [_type_link("character", flow, total, "gold")]
		var out: Array = []
		for node: String in _instances_of_flow(repo, state, flow):
			if id == node or id == "character:" + gid:
				out.append(_link("character:" + gid, node, total, "gold"))
		return out
	if gid == "":
		return []
	if id == "":
		return [_type_link("character", flow, -1, "count")]
	var out: Array = []
	for node: String in _instances_of_flow(repo, state, flow):
		if id == node or id == "character:" + gid:
			out.append(_link("character:" + gid, node, -1, "count"))
	return out
```
(The "character → type" self-link filter in `Ledger._type_level` only drops same-type links; `character → workshop` is fine.)

In `_workshops` (outward, i.e. `converts_out`) and `_supply` (`supplies_out`), add `claims` to each INSTANCE link:
```gdscript
# converts_out, per workshop row:
	var l := _link(wid, "type:strategic_goods", int(row["make"]), "gold")
	l["claims"] = [{"value": int(row["claimed"]), "source": _governor_source(repo, state, "workshop")}]
# supplies_out, per supply row:
	var l := _link(line, "regiment:" + code, int(row["delivered"]), "units")
	l["claims"] = [{"value": int(row["claimed"]), "source": _governor_source(repo, state, "supply_line")},
		{"value": int(row["delivered"]), "source": "the regiment's own count"}]
```
with
```gdscript
static func _governor_source(repo: DataRepository, state: GameState, flow: String) -> String:
	var gid := Governance.governor_of(repo, state, flow)
	if gid == "":
		return "no one's account"
	return "%s: %s" % [Governance.seat_label(repo, flow), (state.characters[gid] as Character).display_name]
```
(The type-level `converts_out` / `supplies_out` links carry claims too: the governor's claimed total, and for `supplies_out` the regiments' delivered total.)

- [ ] **Step 5: `Ledger` builds the accounts**

In `Ledger._believed`, when `t` has `claims`:
```gdscript
	var accs: Array
	if t.has("claims"):
		accs = _claimed(repo, state, t)
	else:
		accs = [_account(repo, state, t)]
	return {… "flow": accs[0]["value"], "accounts": accs, …}
```
```gdscript
## The accounts of a governed flow (spec 2026-09-30-ledger-governors-design
## §4): each claim, then the latest fresh audit's figure for this node; equal
## figures merge into one account naming every source.
static func _claimed(repo: DataRepository, state: GameState, t: Dictionary) -> Array:
	var today := state.absolute_day()
	var raw: Array = []
	for c: Dictionary in t["claims"]:
		raw.append({"value": int(c["value"]), "source": String(c["source"]), "day": today})
	var node := String(t["from"]) if not String(t["from"]).begins_with("type:") else String(t["to"])
	var audit := _audit_figure(repo, state, node)
	if not audit.is_empty():
		raw.append(audit)
	var out: Array = []
	for a: Dictionary in raw:
		var merged := false
		for o: Dictionary in out:
			if int(o["value"]) == int(a["value"]):
				o["source"] = String(o["source"]) + "; " + String(a["source"])
				merged = true
				break
		if not merged:
			out.append({"value": int(a["value"]), "text": Intel.num(int(a["value"])),
				"source": String(a["source"]), "day": int(a["day"]), "level": "full"})
	return out


static func _audit_figure(repo: DataRepository, state: GameState, node: String) -> Dictionary:
	var fresh := int(repo.bal("gov_audit_fresh_days"))
	for i in range(state.missives.size() - 1, -1, -1):
		var m: Dictionary = state.missives[i]
		if String(m["kind"]) != "audit" or state.absolute_day() - int(m["day"]) > fresh:
			continue
		for f: Dictionary in m["facts"]:
			if String(f["key"]) == node:
				return {"value": int(f["exact"]), "source": "the audit of day %d" % int(m["day"]),
					"day": int(m["day"])}
	return {}
```
(For a type-level link `node` is `type:…`; the audit's `total` fact is keyed `total` — match `node.begins_with("type:")` to the `total` key of an audit whose subject `code` is this link's flow, if you want the type level to show it; otherwise the audit account appears on instance threads only — **Ruling for the implementer**: instance threads only, keeping the type level to the governor's word and the receiving count.)

`Ledger.actions_for(repo, node_id, state: GameState = null)`: after building a row whose `params` contain `character=@council`, if `state` is not null replace it by one row per `state.council` value (sorted by seat), skipping `Governance.governor_of(repo, state, flow)`, label `"Give it to " + display_name`, params with `@council` replaced by the character id; with `state` null drop such rows. `params_of` needs no change (the id is literal by then). `LedgerScreen._on_orders` passes `Game.state`.

- [ ] **Step 6: `LedgerCards`**

In `LedgerCards.entry`, for a `character:` node, append his record lines (`state.records.get(id, [])`) after the thread lines.

- [ ] **Step 7: The view draws strands**

In `LedgerView3D._build_threads`, for a link whose `accounts.size() > 1`: for account `i` of `n`, offset both ends sideways by `(i − (n − 1) / 2.0) × ledger_strand_gap_m` (perpendicular to the thread and to UP), build it with `_add_thread` using a per-account copy of the link whose `flow` is that account's `value` and whose `accounts` is `[that account]`, and register it in `_thread_mi` under `"<link id>#<i>"`. `_pick` lists strands under those ids. In `LedgerScreen._on_thread` and `_on_orders`, strip a `#<digits>` suffix before looking the link up. (No headless test can render this; the look pass of the L0 plan's Task 9 command shoots it — run `snapshot_screen --ledger war --ledger-focus regiment` with a venal marshal set through `--bal` is not possible, so check it by reading the code path and the unit tests above, and note it for the morning's look check.)

- [ ] **Step 8: Ontology spec** — in `2026-09-30-ledger-ontology-design.md` §3 mark `governs` and `skims` ✅ (M3), and §8's L1 row "delivered with M3".

- [ ] **Step 9: Run the LEDGER tests and `test_ledger_screen.gd`** — Expected: PASS.

- [ ] **Step 10: Commit** — `feat(ledger): the governor is the reporter — split strands, audits and skims on the LEDGER`

---

### Task 5: Documents and the whole suite

- [ ] **Step 1: CLAUDE.md** — after the supply paragraph add:

```markdown
**Governors, skimming and the audit** (LEDGER M3 + L1, 2026-09-30, spec `docs/superpowers/specs/2026-09-30-ledger-governors-design.md`): each governed flow (`data/ledger_governance.csv`: the war workshops under the steward, the supply lines under the marshal) runs as its governor runs it — `Governance.factors`: skill against `skill_mid`, opinion under `gov_opinion_cooperate`, clamped — and a venal governor (trait flag `skims_treasury`) or one of low integrity SKIMS a fixed share, never at random; he REPORTS the flow whole. The flows' plans carry both the truth and his claim; `GameState.skims` / `caught` / `records` / `governors` are saved. `GOVERNOR_SET` gives a flow to another councillor (the passed-over's goodwill), `LEDGER_AUDIT` files a credible `audit` letter of the true figures and catches a skimmer (a permanent record line, opinion with its reason). On the LEDGER a governed thread's accounts are the governor's word, the receiving side's own count and a fresh audit, equal ones merged — two that differ are drawn as two STRANDS; `skims` is drawn only once caught.
```

- [ ] **Step 2: Full suite; commit** — `docs(governance): CLAUDE.md records governors, skimming and the audit`
