extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
var repo: DataRepository
var state: GameState
var realm: String
const CTX := {"place": "Harrow Ford", "order": "HOLD THE BRIDGE"}

func before_each() -> void:
	repo = SuiteData.repo()
	state = GameState.new()
	state.rng = Rng.new(7)
	realm = repo.resolve_realm("player_realm")
	repo.balance["family_loss_opinion_dead_cadre"] = -2
	repo.balance["family_loss_opinion_dead_named"] = -3
	repo.balance["family_loss_opinion_captured_cadre"] = -1
	repo.balance["family_loss_opinion_captured_named"] = -2
	_member("h1", "Harrow", realm)
	_cohort("noble_h", "noble", "Harrow", "")
	_cohort("commoner_h", "commoner", "", "")

func _member(id: String, family: String, kingdom: String) -> void:
	var c := Character.new()
	c.id = id
	c.family_name = family
	c.kingdom = kingdom
	c.opinion = 10
	state.characters[id] = c

func _cohort(id: String, identity: String, family: String, person: String) -> void:
	var c := {"id": id, "unit_code": "u", "identity": identity, "family_name": family, "fit": 5, "wounded": 0,
		"captured_current": 0, "dead": 0, "stage": "active"}
	if person != "":
		c["person_id"] = person
	state.military_cohorts[id] = c

func _loss(cohort: String, from := "fit", to := "dead", n := 1) -> Array:
	return [{"cohort_id": cohort, "from": from, "to": to, "count": n}]

func test_cadre_death_moves_opinion_with_reason() -> void:
	var rows: Array = FamilyLosses.consume(repo, state, "L1", _loss("noble_h"), CTX)
	assert_eq((state.characters["h1"] as Character).opinion, 8)
	assert_eq(rows.size(), 1)
	assert_eq(rows[0].delta, -2)
	assert_true(String(rows[0].reason).contains("Harrow Ford") and String(rows[0].reason).contains("HOLD THE BRIDGE"))
	assert_eq(String((state.characters["h1"] as Character).opinion_log[-1].reason), rows[0].reason)

func test_replay_and_roundtrip_apply_once() -> void:
	var first: Variant = FamilyLosses.consume(repo, state, "L1", _loss("noble_h"), CTX)
	var again: Variant = FamilyLosses.consume(repo, state, "L1", _loss("noble_h"), CTX)
	assert_eq(again, first)
	assert_eq((state.characters["h1"] as Character).opinion, 8)
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	var third: Variant = FamilyLosses.consume(repo, saved, "L1", _loss("noble_h"), CTX)
	assert_false(third.is_empty())
	assert_eq((saved.characters["h1"] as Character).opinion, 8)

func test_commoner_and_wounded_do_nothing() -> void:
	assert_eq(FamilyLosses.consume(repo, state, "L2", _loss("commoner_h"), CTX), [])
	assert_eq(FamilyLosses.consume(repo, state, "L3", _loss("noble_h", "fit", "wounded"), CTX), [])
	assert_eq((state.characters["h1"] as Character).opinion, 10)

func test_every_family_member_in_id_order_scaled_by_count() -> void:
	_member("h0", "Harrow", realm)
	_member("foe", "Harrow", "elsewhere_realm")
	var rows: Array = FamilyLosses.consume(repo, state, "L4", _loss("noble_h", "fit", "dead", 2), CTX)
	assert_eq(rows.size(), 2)
	assert_eq(rows[0].person, "h0")
	assert_eq((state.characters["h0"] as Character).opinion, 6)
	assert_eq((state.characters["h1"] as Character).opinion, 6)
	assert_eq((state.characters["foe"] as Character).opinion, 10)

func test_named_captured_uses_its_own_key() -> void:
	_cohort("lord", "noble", "Harrow", "h1")
	FamilyLosses.consume(repo, state, "L5", _loss("lord", "fit", "captured_current"), CTX)
	assert_eq((state.characters["h1"] as Character).opinion, 8)

func test_same_id_different_request_errors_and_changes_nothing() -> void:
	FamilyLosses.consume(repo, state, "L1", _loss("noble_h"), CTX)
	var before := JSON.stringify(state.to_dict())
	var r: Variant = FamilyLosses.consume(repo, state, "L1", _loss("noble_h", "fit", "dead", 3), CTX)
	assert_true(r is Dictionary and r.has("error"))
	assert_eq(JSON.stringify(state.to_dict()), before)
