extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
var repo: DataRepository
var state: GameState
var province: String
var buyer: String
var seller: String
var batch_id: String

func before_each() -> void:
	repo = SuiteData.repo()
	state = GameState.new()
	state.rng = Rng.new(52)
	buyer = repo.resolve_realm("raider_realm")
	seller = repo.resolve_realm("player_realm")
	province = String(repo.provinces.keys()[0])
	repo.balance.recruitment_eligible_permille = 1000
	state.world[MilitaryPopulation.path(province, "rural_population")] = 1000
	state.world[_treasury(buyer)] = 500
	state.metrics.treasury = 0
	_add_unit("source", buyer, 60, "noble")
	_add_unit("holder", seller, 20, "commoner")
	state.battles = [{"id": 52, "att": ["source"], "def": ["holder"]}]
	BattleReport.enroll(state, state.battles[0], "source", "att")
	var result := PrisonerSystem.capture(repo, state, {"capture_id": "capture52", "battle_id": 52,
		"participants": {"holder": 1}, "reason": "Surrender accepted",
		"changes": [{"cohort_id": "source", "from": "fit", "to": "captured_current", "count": 60}]})
	assert_false(result.has("error"), str(result))
	batch_id = String(result.batch_ids[0])
	BattleReport.snapshot(repo, state, 52)

func _treasury(realm: String) -> String:
	return "metrics.treasury" if realm == seller else "economy.kingdoms.%s.treasury" % realm

func _add_unit(code: String, realm: String, count: int, identity: String) -> void:
	state.army_roster[code] = {"regiment_code": code, "kingdom_code": realm, "is_naval": "0"}
	state.regiments[code] = {}
	state.military_rosters[code] = {"commander_id": "", "cohort_ids": [code]}
	state.military_cohorts[code] = {"id": code, "unit_code": code, "source_province": province,
		"source_population_field": "rural_population", "stage": "active", "identity": identity,
		"initial": count, "fit": count, "wounded": 0, "captured_current": 0, "dead": 0, "released": 0}

func _system() -> Script:
	var path := "res://scripts/engine/prisoner_disposition.gd"
	assert_true(FileAccess.file_exists(path), "Negotiated prisoner settlement must exist")
	return load(path) if FileAccess.file_exists(path) else null

func _proposal(id := "ransom52", count := 10) -> Dictionary:
	return {"id": id, "kind": "ransom", "batches": [{"batch_id": batch_id, "count": count, "wounded_count": 0}],
		"money": 100, "parties": {"proposer": seller, "payer": buyer}, "terms": {}, "reason": "Agreed noble ransom"}

func _accepted(system: Script, proposal: Dictionary) -> void:
	var result: Dictionary = system.propose(repo, state, proposal)
	assert_false(result.has("error"), str(result))
	assert_false(system.respond(repo, state, proposal.id, buyer, true).has("error"))

func test_settlement_releases_once_to_civilians() -> void:
	var system := _system()
	if system == null: return
	var history := state.battle_records.duplicate(true)
	var people := int(WorldLedger.value_of(repo, state, MilitaryPopulation.path(province, "rural_population")))
	var available := MilitaryPopulation.available(repo, state, province, "rural_population")
	_accepted(system, _proposal())
	var result: Dictionary = system.settle(repo, state, "ransom52")
	assert_false(result.has("error"), str(result))
	assert_eq(result.get("released"), 10)
	assert_eq(int(state.metrics.treasury), 70)
	assert_eq(state.get("unit_prize_gold").get("holder"), 30)
	assert_eq(int(WorldLedger.value_of(repo, state, _treasury(buyer))), 400)
	assert_eq(PrisonerSystem.held_counts(state, "holder").total, 50)
	assert_eq(state.military_cohorts.source.captured_current, 50)
	assert_eq(state.military_cohorts.source.released, 10)
	assert_eq(MilitaryPopulation.available(repo, state, province, "rural_population"), available + 10)
	assert_eq(int(WorldLedger.value_of(repo, state, MilitaryPopulation.path(province, "rural_population"))), people)
	assert_eq(MilitaryRoster.living(state, "source"), 0)
	assert_eq(MilitaryRoster.living(state, "holder"), 20)
	assert_eq(state.battle_records, history)
	var before := state.to_dict()
	assert_eq(system.settle(repo, state, "ransom52"), result)
	assert_eq(state.to_dict(), before)
	assert_eq(BattleReport.tally(state, state.battles[0]).att, {"participants": 60, "fit": 0, "wounded": 0, "dead": 0, "captured": 60, "released": 0})

func test_proposal_freezes_without_payment_and_needs_actual_acceptance() -> void:
	var system := _system()
	if system == null: return
	var proposal := _proposal()
	var result: Dictionary = system.propose(repo, state, proposal)
	assert_false(result.has("error"), str(result))
	assert_eq(int(state.metrics.treasury), 0)
	assert_eq(PrisonerSystem.held_counts(state, "holder").total, 60)
	var before := state.to_dict()
	assert_true(system.settle(repo, state, proposal.id).has("error"))
	assert_eq(state.to_dict(), before)
	proposal.money = 1
	assert_true(system.propose(repo, state, proposal).has("error"))
	assert_eq(state.to_dict(), before)
	assert_true(system.respond(repo, state, proposal.id, "unknown", true).has("error"))
	assert_false(system.respond(repo, state, proposal.id, buyer, false).has("error"))
	before = state.to_dict()
	assert_true(system.settle(repo, state, proposal.id).has("error"))
	assert_eq(state.to_dict(), before)

func test_unaffordable_stale_and_changed_terms_settle_nothing() -> void:
	var system := _system()
	if system == null: return
	for cause: String in ["funds", "holder", "released", "share", "policy"]:
		before_each()
		_accepted(system, _proposal())
		match cause:
			"funds": state.world[_treasury(buyer)] = 99
			"holder": state.prisoner_batches[batch_id].holder_code = "source"
			"released": state.prisoner_batches[batch_id].disposition = "released"
			"share": state.law_in_force["unit:holder"] = {"ransom_captor_share": {"value": "400", "decree_id": 5}}
			"policy": state.law_in_force["unit:holder"] = {"ransom": {"value": "execute", "decree_id": 5}}
		var before := state.to_dict()
		assert_true(system.settle(repo, state, "ransom52").has("error"), cause)
		assert_eq(state.to_dict(), before, cause)

func test_exchange_is_bilateral_atomic_and_saved_replay_is_inert() -> void:
	var system := _system()
	if system == null: return
	_add_unit("reverse", seller, 10, "commoner")
	_add_unit("enemy_holder", buyer, 20, "commoner")
	var capture := PrisonerSystem.capture(repo, state, {"capture_id": "reverse", "reason": "Reciprocal prisoners",
		"participants": {"enemy_holder": 1}, "changes": [{"cohort_id": "reverse", "from": "fit", "to": "captured_current", "count": 10}]})
	assert_false(capture.has("error"))
	var reverse := String(capture.batch_ids[0])
	var proposal := _proposal("exchange")
	proposal.kind = "exchange"
	proposal.money = 0
	proposal.parties.payer = ""
	proposal.batches.append({"batch_id": reverse, "count": 10, "wounded_count": 0})
	_accepted(system, proposal)
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	state.prisoner_batches[reverse].holder_code = "holder"
	var before := state.to_dict()
	assert_true(system.settle(repo, state, "exchange").has("error"))
	assert_eq(state.to_dict(), before)
	state = saved
	var result: Dictionary = system.settle(repo, state, "exchange")
	assert_eq(result.get("released"), 20, str(result))
	assert_eq(state.military_cohorts.source.captured_current, 50)
	assert_eq(state.military_cohorts.reverse.captured_current, 0)
	assert_eq(state.military_cohorts.reverse.released, 10)
	assert_eq(int(state.metrics.treasury), 0)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	before = restored.to_dict()
	assert_eq(system.settle(repo, restored, "exchange"), result)
	assert_eq(restored.to_dict(), before)

func test_release_retains_origin_after_conquest_and_does_not_duplicate_history() -> void:
	var system := _system()
	if system == null: return
	var proposal := _proposal("release", 60)
	proposal.kind = "release"
	proposal.money = 0
	proposal.parties.payer = ""
	var history := state.battle_records.duplicate(true)
	assert_false(system.propose(repo, state, proposal).has("error"))
	MapOwnership.set_owner(repo, state, province, seller, "Origin conquered")
	var residents := int(WorldLedger.value_of(repo, state, MilitaryPopulation.path(province, "rural_population")))
	var result: Dictionary = system.settle(repo, state, "release")
	assert_eq(result.get("released"), 60, str(result))
	assert_eq(state.military_cohorts.source.source_province, province)
	assert_eq(int(WorldLedger.value_of(repo, state, MilitaryPopulation.path(province, "rural_population"))), residents)
	assert_eq(PrisonerSystem.held_counts(state, "holder").total, 0)
	assert_eq(state.battle_records, history)
	assert_eq(state.prisoner_batches[batch_id].initial_count, 60)
	assert_eq(state.prisoner_batches[batch_id].disposition, "released")

func test_invalid_shapes_never_create_proposals() -> void:
	var system := _system()
	if system == null: return
	for field: String in ["money", "count", "duplicate", "names", "wounds", "terms", "buyer"]:
		var proposal := _proposal()
		match field:
			"money": proposal.money = 1.5
			"count": proposal.batches[0].count = 61
			"duplicate": proposal.batches.append(proposal.batches[0].duplicate(true))
			"names": proposal.batches[0].named_ids = ["you"]
			"wounds": proposal.batches[0].wounded_count = 1
			"terms": proposal.terms = {"no_fighting_until_day": -1}
			"buyer": proposal.parties.payer = seller
		var before := state.to_dict()
		assert_true(system.propose(repo, state, proposal).has("error"), field)
		assert_eq(state.to_dict(), before, field)

func test_partial_wounds_and_multi_holder_rounding_preserve_captor_credit() -> void:
	var system := _system()
	if system == null: return
	state.prisoner_batches[batch_id].wounded_subset = 7
	state.military_cohorts.source.identity = "noble"
	var proposal := _proposal("wounded", 8)
	proposal.money = 101
	proposal.batches[0].wounded_count = 3
	_accepted(system, proposal)
	var result: Dictionary = system.settle(repo, state, proposal.id)
	assert_eq(result.get("released"), 8)
	assert_eq(state.prisoner_batches[batch_id].wounded_subset, 4)
	assert_eq(state.prisoner_batches[batch_id].nobles, 52)
	assert_eq(result.get("payments", [])[0].captor_gold, 30)
	assert_eq(result.get("payments", [])[0].crown_gold, 71)
	assert_eq(state.military_cohorts.source.wounded, 0)
	state.prisoner_batches[batch_id].erase("captor_code") # A P5.1 save predates explicit captor credit.
	_add_unit("next_holder", seller, 20, "commoner")
	assert_false(PrisonerSystem.holder_defeated(repo, state, "holder", ["next_holder"], "transfer").has("error"))
	proposal = _proposal("after_transfer", 1)
	_accepted(system, proposal)
	result = system.settle(repo, state, proposal.id)
	assert_eq(result.get("civilians", [])[0].captor_code, "holder")
	assert_eq(result.get("civilians", [])[0].holder_code, "next_holder")

func test_multi_holder_gross_is_apportioned_once_and_receiver_overflow_is_atomic() -> void:
	var system := _system()
	if system == null: return
	_add_unit("second_source", buyer, 2, "noble")
	_add_unit("second_holder", seller, 20, "commoner")
	var captured := PrisonerSystem.capture(repo, state, {"capture_id": "other", "reason": "Second capture",
		"participants": {"second_holder": 1}, "changes": [{"cohort_id": "second_source", "from": "fit", "to": "captured_current", "count": 2}]})
	var proposal := _proposal("multi", 3)
	proposal.money = 101
	proposal.batches.append({"batch_id": captured.batch_ids[0], "count": 2})
	_accepted(system, proposal)
	state.metrics.treasury = 100000000
	var before := state.to_dict()
	assert_true(system.settle(repo, state, proposal.id).has("error"))
	assert_eq(state.to_dict(), before)
	state.metrics.treasury = 0
	var result: Dictionary = system.settle(repo, state, proposal.id)
	assert_eq(result.get("payments", [])[0].gross, 61)
	assert_eq(result.get("payments", [])[1].gross, 40)
	assert_eq(state.get("unit_prize_gold"), {"holder": 18, "second_holder": 12})
	assert_eq(int(state.metrics.treasury), 71)

func test_save_fulfills_same_proposal_and_old_saves_default_new_accounts() -> void:
	var system := _system()
	if system == null: return
	_accepted(system, _proposal())
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	var first: Dictionary = system.settle(repo, state, "ransom52")
	assert_eq(system.settle(repo, restored, "ransom52"), first)
	assert_eq(restored.to_dict(), state.to_dict())
	var save := state.to_dict()
	save.erase("unit_prize_gold")
	save.erase("prisoner_proposals")
	restored = GameState.from_dict(save, false)
	assert_eq(restored.get("unit_prize_gold"), {})
	assert_eq(restored.get("prisoner_proposals"), {})

func test_ransom_reference_uses_identity_wealth_and_actual_payment_capacity() -> void:
	var system := _system()
	if system == null: return
	repo.prisoner_terms.ransom["base_gold"] = 2
	repo.prisoner_terms.ransom["wealth_gold_per_point"] = 1
	repo.prisoner_terms.ransom["unnamed_wealth"] = 50
	var person := Character.new()
	person.id = "named_noble"
	person.category = "noble"
	person.kingdom = buyer
	person.attributes.wealth = 80
	state.characters[person.id] = person
	_add_unit("named_source", buyer, 1, "noble")
	state.military_cohorts.named_source.person_id = person.id
	var captured := PrisonerSystem.capture(repo, state, {"capture_id": "valued", "reason": "Noble capture",
		"participants": {"holder": 1}, "changes": [{"cohort_id": "named_source", "from": "fit", "to": "captured_current", "count": 1}]})
	var proposal := _proposal("valuation", 3)
	proposal.batches.append({"batch_id": captured.batch_ids[0], "count": 1, "named_ids": [person.id]})
	state.world[_treasury(buyer)] = 100
	var result: Dictionary = system.propose(repo, state, proposal)
	assert_false(result.has("error"), str(result))
	assert_eq(result.get("valuation", {}).get("asking_gold"), 238, "3*(2+50) + 1*(2+80)")
	assert_eq(result.get("valuation", {}).get("affordable_gold"), 100)
	assert_eq(int(WorldLedger.value_of(repo, state, _treasury(buyer))), 100)
