extends "res://tests/engine/prisoner_actions_fixture.gd"

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
