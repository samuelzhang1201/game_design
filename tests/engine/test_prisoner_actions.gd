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

func _proposal(id := "ransom52", count := 10) -> Dictionary:
	return {"id": id, "kind": "ransom", "batches": [{"batch_id": batch_id, "count": count, "wounded_count": 0}],
		"money": 100, "parties": {"proposer": seller, "payer": buyer}, "terms": {}, "reason": "Agreed noble ransom"}

func _act(code: String, params: Dictionary) -> Dictionary:
	return ActionSystem.new(repo).execute(ActionRequest.make(code, params), state)

func _release() -> Dictionary:
	var proposal := _proposal("release")
	proposal.kind = "release"
	proposal.money = 0
	proposal.parties.payer = ""
	return proposal

func test_action_release_charges_once_and_replays_after_json() -> void:
	state.metrics.treasury = 10
	var proposal := _release()
	var request := ActionRequest.make("PRISONER_PROPOSE", proposal)
	var before := state.to_dict()
	assert_eq(ActionSystem.new(repo).validate(request, state), "")
	assert_eq(state.to_dict(), before)
	var offered := _act("PRISONER_PROPOSE", proposal)
	assert_true(offered.get("ok", false), str(offered))
	assert_eq(int(state.metrics.treasury), 9)
	var settled := _act("PRISONER_SETTLE", {"proposal_id": proposal.id})
	assert_true(settled.get("ok", false), str(settled))
	assert_eq(int(state.metrics.treasury), 8)
	assert_eq(state.recent_outcomes.size(), 2)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	before = state.to_dict()
	assert_eq(_act("PRISONER_PROPOSE", proposal), offered)
	assert_eq(_act("PRISONER_SETTLE", {"proposal_id": proposal.id}), settled)
	assert_eq(state.to_dict(), before)
	proposal.reason = "Changed terms"
	assert_false(_act("PRISONER_PROPOSE", proposal).get("ok", true))
	assert_eq(state.to_dict(), before)

func test_action_errors_never_spend_or_mutate() -> void:
	state.metrics.treasury = 10
	var proposal := _proposal()
	var before := state.to_dict()
	proposal.parties.proposer = buyer
	assert_false(_act("PRISONER_PROPOSE", proposal).get("ok", true))
	assert_eq(state.to_dict(), before)
	proposal.parties.proposer = seller
	assert_true(_act("PRISONER_PROPOSE", proposal).get("ok", false))
	before = state.to_dict()
	assert_false(_act("PRISONER_SETTLE", {"proposal_id": proposal.id}).get("ok", true))
	assert_eq(state.to_dict(), before)
	# Supplied foreign authority cannot accept for the payer.
	assert_false(_act("PRISONER_RESPOND", {"proposal_id": proposal.id, "accepted": false, "party": buyer}).get("ok", true))
	assert_eq(state.to_dict(), before)
	state.metrics.treasury = 0
	before = state.to_dict()
	assert_false(_act("PRISONER_PROPOSE", _release()).get("ok", true))
	assert_eq(state.to_dict(), before)

func test_response_uses_player_authority_and_is_paid_once() -> void:
	state.metrics.treasury = 10
	# A foreign holder proposes a release requiring the recipient's promise.
	state.army_roster.holder.kingdom_code = buyer
	state.military_cohorts.source.origin_realm = seller
	state.prisoner_batches[batch_id].origin_realm = seller
	var proposal := _release()
	proposal.parties.proposer = buyer
	proposal.terms = {"no_fighting_until_day": state.absolute_day() + 30}
	var offered := PrisonerDisposition.propose(repo, state, proposal)
	assert_false(offered.has("error"), str(offered))
	var params := {"proposal_id": proposal.id, "accepted": true, "party": "spoof"}
	var response := _act("PRISONER_RESPOND", params)
	assert_true(response.get("ok", false), str(response))
	assert_eq(int(state.metrics.treasury), 9)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	var before := state.to_dict()
	assert_eq(_act("PRISONER_RESPOND", params), response)
	params.accepted = false
	assert_false(_act("PRISONER_RESPOND", params).get("ok", true))
	assert_eq(state.to_dict(), before)

func test_settlement_requires_fee_before_ransom_income() -> void:
	state.metrics.treasury = 1 + CourierSystem.fee_gold(repo, CourierSystem.ORDINARY)
	var proposal := _proposal()
	assert_true(_act("PRISONER_PROPOSE", proposal).get("ok", false))
	assert_false(PrisonerDisposition.respond(repo, state, proposal.id, buyer, true).has("error"))
	var before := state.to_dict()
	assert_false(_act("PRISONER_SETTLE", {"proposal_id": proposal.id}).get("ok", true))
	assert_eq(state.to_dict(), before)
	state.metrics.treasury = 1
	assert_true(_act("PRISONER_SETTLE", {"proposal_id": proposal.id}).get("ok", false))
	assert_eq(int(state.metrics.treasury), 70)

func test_player_payer_needs_ransom_plus_fee_and_unreserved_gold() -> void:
	state.army_roster.holder.kingdom_code = buyer
	state.prisoner_batches[batch_id].origin_realm = seller
	var proposal := _proposal()
	proposal.parties = {"proposer": buyer, "payer": seller}
	assert_false(PrisonerDisposition.propose(repo, state, proposal).has("error"))
	state.metrics.treasury = 102
	assert_true(_act("PRISONER_RESPOND", {"proposal_id": proposal.id, "accepted": true}).get("ok", false))
	state.metrics.treasury = 100
	var before := state.to_dict()
	assert_false(_act("PRISONER_SETTLE", {"proposal_id": proposal.id}).get("ok", true))
	assert_eq(state.to_dict(), before)
	state.metrics.treasury = 101
	state.battle_orders["reserved"] = {"reserved_gold": 1}
	before = state.to_dict()
	assert_false(_act("PRISONER_SETTLE", {"proposal_id": proposal.id}).get("ok", true))
	assert_eq(state.to_dict(), before)
	state.battle_orders.clear()
	assert_true(_act("PRISONER_SETTLE", {"proposal_id": proposal.id}).get("ok", false))
	assert_eq(int(state.metrics.treasury), 0)

func test_invalid_typed_response_and_outsider_settlement_are_atomic() -> void:
	state.metrics.treasury = 10
	var proposal := _release()
	assert_true(_act("PRISONER_PROPOSE", proposal).get("ok", false))
	var before := state.to_dict()
	assert_false(_act("PRISONER_RESPOND", {"proposal_id": proposal.id, "accepted": 1}).get("ok", true))
	assert_eq(state.to_dict(), before)
	state.prisoner_proposals[proposal.id].frozen.required_parties = [buyer]
	before = state.to_dict()
	assert_false(_act("PRISONER_SETTLE", {"proposal_id": proposal.id, "party": buyer}).get("ok", true))
	assert_eq(state.to_dict(), before)
