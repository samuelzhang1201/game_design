extends GutTest
## P2-B2: a resolved battle round feeds FamilyLosses once per unit, replay-safe.

const SuiteData := preload("res://tests/suite_data.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")

var repo: DataRepository
var state: GameState
var realm: String

func before_each() -> void:
	repo = SuiteData.no_clearance(SuiteData.open_country(SuiteData.repo()))
	repo.balance["family_loss_opinion_dead_cadre"] = -2
	repo.balance["family_loss_opinion_dead_named"] = -2
	state = Scenario.contact(repo, 10)
	# Family casualty arithmetic assumes a melee attacker, not ranged reach.
	for code: String in state.foes:
		var fit := ArmySystem.fit_count(repo, state, code)
		for arm: String in repo.world_table("military", "unit_types"):
			state.army_roster[code][arm] = "0"
		state.army_roster[code]["infantry"] = str(fit)
	realm = repo.resolve_realm("player_realm")
	BattleSystem.detect_contacts(repo, state)
	state.battles[0]["actions"] = {"att": {"kind": "attack"}, "def": {"kind": "hold"}}
	for entry: Dictionary in state.regiments.values() + state.foes.values():
		entry["morale"] = 80
		entry["supplies"] = 10000
	var c := Character.new()
	c.id = "h1"
	c.family_name = "Harrow"
	c.kingdom = realm
	c.opinion = 10
	state.characters["h1"] = c

## Make every cohort of the player's unit a Harrow noble cadre (or commoners).
func _make_nobles(noble: bool) -> void:
	for cohort: Dictionary in state.military_cohorts.values():
		if state.regiments.has(String(cohort["unit_code"])):
			cohort["identity"] = "noble" if noble else "commoner"
			cohort["family_name"] = "Harrow" if noble else ""

func _dead_heads() -> int:
	var receipt: Dictionary = state.military_events["battle:%d:round:1:personnel" % int(state.battles[0]["id"])]
	var total := 0
	for change: Dictionary in receipt["result"]["changes"]:
		if change["to"] == "dead" and state.regiments.has(String(state.military_cohorts[change["cohort_id"]]["unit_code"])):
			total += int(change["count"])
	return total

func test_round_death_moves_opinion_and_reports_place_and_order() -> void:
	_make_nobles(true)
	BattleSystem.settle_day(repo, state)
	var heads := _dead_heads()
	assert_gt(heads, 0)
	assert_eq((state.characters["h1"] as Character).opinion, 10 - 2 * heads)
	var rows: Array = state.battles[0]["family_changes"]
	assert_gt(rows.size(), 0)
	var reason := String(rows[0]["reason"])
	assert_true(reason.contains(BattleSystem.place_label(repo, state, state.battles[0])), reason)
	assert_true(reason.contains("under attack") or reason.contains("under hold"), reason)

func test_same_round_replay_applies_and_appends_nothing_twice() -> void:
	_make_nobles(true)
	BattleSystem.settle_day(repo, state)
	var b: Dictionary = state.battles[0]
	var opinion := (state.characters["h1"] as Character).opinion
	var rows_before: Array = b["family_changes"].duplicate(true)
	# Replay the round as a failed-and-retried settlement would: pending kept, round not counted.
	var pending := {"day": 10, "round": 1, "att": b["att"].duplicate(), "def": b["def"].duplicate(),
		"tier": repo.battle_outcomes[0].duplicate(true), "reason": "r", "contexts": {"att": {"kind": "attack"}, "def": {"kind": "hold"}}}
	BattleSystem._settle_family_losses(repo, state, b, pending, 1)
	assert_eq((state.characters["h1"] as Character).opinion, opinion)
	assert_eq(b["family_changes"], rows_before)
	var twin := Scenario.roundtrip(state)
	BattleSystem._settle_family_losses(repo, twin, twin.battles[0], pending, 1)
	assert_eq((twin.characters["h1"] as Character).opinion, opinion)
	assert_eq(twin.battles[0]["family_changes"], rows_before)

func test_commoner_only_round_records_no_row() -> void:
	_make_nobles(false)
	BattleSystem.settle_day(repo, state)
	assert_eq((state.characters["h1"] as Character).opinion, 10)
	assert_eq(state.battles[0].get("family_changes", []), [])

func test_old_receipt_without_changes_reads_as_no_loss() -> void:
	_make_nobles(true)
	var b: Dictionary = state.battles[0]
	state.military_events["battle:%d:round:1:personnel" % int(b["id"])] = {"request": {}, "result": {"status": "applied"}}
	BattleSystem._settle_family_losses(repo, state, b, {"att": b["att"], "def": b["def"], "contexts": {}}, 1)
	assert_eq(b.get("family_changes", []), [])
