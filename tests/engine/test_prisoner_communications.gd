extends "res://tests/engine/test_prisoner_actions.gd"

func before_each() -> void:
	super.before_each()
	repo = SuiteData.flat_ground(repo)
	repo.routes = {}
	repo.rivers = {}
	RoadGraph.forget()
	Weather.forget()
	state.metrics.treasury = 100
	state.king_state = {"x_m": 0, "y_m": 0}
	repo.balance.king_command_radius_m = 1
	var cap := String(repo.kingdoms[buyer].capital_burg)
	var at := ArmySystem.metres_to_pack(repo, Vector2i(1000, 0))
	repo.burgs[cap].x = at.x
	repo.burgs[cap].y = at.y

func after_each() -> void:
	RoadGraph.forget()
	Weather.forget()

func _day() -> void:
	CourierSystem.ride_day(repo, state)
	state.day += 1
	if state.day > 30:
		state.day = 1
		state.tick += 1

func _view(id := "ransom52") -> Dictionary:
	return PrisonerCommunications.projection(state, id)

func _accepted(proposal: Dictionary) -> void:
	var offered := _act("PRISONER_PROPOSE", proposal)
	assert_true(offered.get("ok", false), str(offered))
	_day()
	assert_false(state.prisoner_proposals[proposal.id].consents.has(buyer))
	_day()
	assert_eq(state.prisoner_proposals[proposal.id].status, "accepted")

func _move(holder: String, x: int) -> void:
	state.regiments[holder]["x_m"] = x
	state.regiments[holder]["y_m"] = 0

func test_production_offer_needs_return_delivery_before_consent() -> void:
	var proposal := _proposal()
	var before := state.to_dict()
	var req := ActionRequest.make("PRISONER_PROPOSE", proposal)
	assert_eq(ActionSystem.new(repo).validate(req, state), "")
	assert_eq(state.to_dict(), before)
	var offered := _act("PRISONER_PROPOSE", proposal)
	assert_true(offered.get("ok", false), str(offered))
	assert_eq(state.couriers.size(), 1)
	assert_eq(int(offered.prisoner_result.valuation.asking_gold), 600)
	var fee := 1 + CourierSystem.fee_gold(repo, CourierSystem.ORDINARY)
	assert_eq(int(state.metrics.treasury), 100 - fee)
	_day()
	assert_eq(state.couriers.size(), 1, "The same physical rider carries the response")
	assert_false(state.prisoner_proposals.ransom52.consents.has(buyer))
	assert_eq(_view().status, "proposed")
	assert_false(_view().consents.has(buyer))
	state.king_state.x_m = 5000
	var preview := CourierSystem.ride_ahead(repo, state, state.couriers[0])
	assert_false(preview.points.is_empty())
	_day()
	assert_eq(state.couriers.size(), 0)
	assert_true(state.prisoner_proposals.ransom52.consents[buyer])
	assert_eq(_view().status, "accepted")
	assert_eq(int(state.metrics.treasury), 100 - fee)
	assert_false(state.regiments.holder.has("order_id"))

func test_foreign_policy_rejects_above_reference_and_current_funds() -> void:
	var proposal := _proposal("high")
	proposal.money = 601
	state.world[_treasury(buyer)] = 1000
	assert_true(_act("PRISONER_PROPOSE", proposal).ok)
	_day()
	_day()
	assert_eq(_view("high").status, "rejected")
	proposal = _proposal("poor")
	assert_true(_act("PRISONER_PROPOSE", proposal).ok)
	state.world[_treasury(buyer)] = 99
	_day()
	assert_eq(_view("poor").status, "proposed")
	_day()
	assert_eq(_view("poor").status, "rejected")
	assert_eq(int(state.prisoner_batches[batch_id].nobles), 60)
	assert_eq(int(state.world[_treasury(buyer)]), 99)

func _second_capture(holder_realm: String, origin: String, count: int) -> String:
	_add_unit("source2", origin, count, "noble")
	_add_unit("holder2", holder_realm, 20, "commoner")
	var captured := PrisonerSystem.capture(repo, state, {"capture_id": "second", "battle_id": 53,
		"participants": {"holder2": 1}, "reason": "Reciprocal surrender accepted",
		"changes": [{"cohort_id": "source2", "from": "fit", "to": "captured_current", "count": count}]})
	assert_false(captured.has("error"), str(captured))
	return String(captured.batch_ids[0])

func test_reciprocal_exchange_accepts_ten_for_ten_but_not_ten_for_nine() -> void:
	var second := _second_capture(buyer, seller, 10)
	var proposal := _proposal("equal")
	proposal.kind = "exchange"
	proposal.money = 0
	proposal.parties.payer = ""
	proposal.batches.append({"batch_id": second, "count": 10, "wounded_count": 0})
	_accepted(proposal)
	proposal.id = "unequal"
	proposal.batches[1].count = 9
	assert_true(_act("PRISONER_PROPOSE", proposal).ok)
	_day()
	_day()
	assert_eq(_view("unequal").status, "rejected")

func test_remote_fulfillment_moves_money_once_and_receipt_follows_king() -> void:
	_accepted(_proposal())
	_move("holder", 1000)
	var funds := int(state.metrics.treasury)
	var sent := _act("PRISONER_SETTLE", {"proposal_id": "ransom52"})
	assert_true(sent.ok, str(sent))
	assert_eq(sent.prisoner_result.status, "riding")
	assert_eq(int(state.prisoner_batches[batch_id].nobles), 60)
	assert_true(_view().result.is_empty())
	assert_eq(int(state.metrics.treasury), funds - 1 - CourierSystem.fee_gold(repo, CourierSystem.ORDINARY))
	_day()
	assert_eq(int(state.prisoner_batches[batch_id].nobles), 50)
	assert_eq(int(state.unit_prize_gold.holder), 30)
	assert_eq(int(state.world[_treasury(buyer)]), 400)
	assert_eq(_view().status, "fulfilling")
	assert_true(_view().result.is_empty(), "Execution must not reveal an undelivered receipt")
	state.king_state.x_m = 5000
	_day()
	assert_eq(_view().status, "fulfilled")
	assert_eq(int(_view().result.released), 10)
	assert_eq(int(state.metrics.treasury), funds - 1 - CourierSystem.fee_gold(repo, CourierSystem.ORDINARY) + 70)
	assert_false(state.regiments.holder.has("order_id"))
	var before := state.to_dict()
	assert_eq(_act("PRISONER_SETTLE", {"proposal_id": "ransom52"}), sent)
	assert_eq(state.to_dict(), before)

func test_last_holder_gate_is_atomic_and_failed_custody_keeps_fees() -> void:
	var second := _second_capture(seller, buyer, 10)
	var proposal := _release()
	proposal.batches.append({"batch_id": second, "count": 10, "wounded_count": 0})
	assert_true(_act("PRISONER_PROPOSE", proposal).ok)
	_move("holder", 1000)
	_move("holder2", 2000)
	var issued := _act("PRISONER_SETTLE", {"proposal_id": proposal.id})
	assert_true(issued.ok, str(issued))
	assert_eq(state.couriers.size(), 2)
	var slow: Dictionary = state.couriers[1]
	slow.path = [[500000, 0, "road"], [2000, 0, "road"]]
	_day()
	assert_eq(int(state.prisoner_batches[batch_id].nobles), 60, "First command releases nobody")
	assert_eq(int(state.prisoner_batches[second].nobles), 10)
	assert_eq(state.prisoner_proposals.release.communications.fulfillment.delivered, ["holder"])
	state.prisoner_batches[second].holder_code = "holder"
	var paid := int(state.metrics.treasury)
	for i: int in 20:
		if state.couriers.is_empty():
			break
		_day()
	assert_eq(_view("release").status, "failed")
	assert_eq(int(state.prisoner_batches[batch_id].nobles), 60)
	assert_eq(int(state.prisoner_batches[second].nobles), 10)
	assert_eq(int(state.metrics.treasury), paid, "Issued clerk and postage fees remain paid")

func test_save_retry_replays_riding_response_and_receipt_identically() -> void:
	var offered := _act("PRISONER_PROPOSE", _proposal())
	_day()
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	var before := state.to_dict()
	assert_eq(_act("PRISONER_PROPOSE", _proposal()), offered)
	assert_eq(state.to_dict(), before)
	_day()
	_move("holder", 1000)
	assert_true(_act("PRISONER_SETTLE", {"proposal_id": "ransom52"}).ok)
	_day()
	var saved := state.to_dict()
	_day()
	var completed := state.to_dict()
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(saved)), false)
	_day()
	assert_eq(state.to_dict(), completed)

func test_batching_pays_one_rider_and_ordinary_foe_orders_stay_forbidden() -> void:
	assert_true(_act("PRISONER_PROPOSE", _proposal("one")).ok)
	var funds := int(state.metrics.treasury)
	assert_true(_act("PRISONER_PROPOSE", _proposal("two")).ok)
	assert_eq(int(state.metrics.treasury), funds - 1)
	assert_eq(state.couriers.size(), 1)
	assert_eq(CourierSystem.orders_of(state.couriers[0]).size(), 2)
	_day()
	_day()
	assert_eq(_view("one").status, "accepted")
	assert_eq(_view("two").status, "accepted")
	state.foes.holder2 = {"x_m": 1000, "y_m": 0}
	state.army_roster.holder2 = {"regiment_code": "holder2", "kingdom_code": buyer}
	assert_true(CourierSystem.dispatch(repo, state, "ordinary", "holder2", {"action_code": "ARMY_GARRISON"}).is_empty())

func test_invalid_capital_or_unaffordable_postage_publishes_nothing() -> void:
	var cap := String(repo.kingdoms[buyer].capital_burg)
	state.province_owner[String(repo.burgs[cap].province_code)] = seller
	var before := state.to_dict()
	assert_false(_act("PRISONER_PROPOSE", _proposal()).ok)
	assert_eq(state.to_dict(), before)
	state.province_owner.clear()
	state.metrics.treasury = 1
	before = state.to_dict()
	assert_false(_act("PRISONER_PROPOSE", _proposal()).ok)
	assert_eq(state.to_dict(), before)

func test_last_holder_success_releases_both_sides_once_after_moving_target() -> void:
	var second := _second_capture(seller, buyer, 10)
	var proposal := _release()
	proposal.batches.append({"batch_id": second, "count": 10, "wounded_count": 0})
	assert_true(_act("PRISONER_PROPOSE", proposal).ok)
	_move("holder", 1000)
	_move("holder2", 2000)
	assert_true(_act("PRISONER_SETTLE", {"proposal_id": proposal.id}).ok)
	state.couriers[1].path = [[500000, 0, "road"], [2000, 0, "road"]]
	_day()
	assert_eq(state.prisoner_proposals.release.communications.fulfillment.delivered, ["holder"])
	assert_eq(int(state.military_cohorts.source.released), 0)
	assert_eq(int(state.military_cohorts.source2.released), 0)
	_move("holder2", 3000)
	var rider: Dictionary = state.couriers[0]
	var before := rider.duplicate(true)
	CourierSystem.ride_ahead(repo, state, rider)
	assert_eq(rider, before, "Moving-target preview is read-only")
	# Keep the second rider's current position but take the direct final leg.
	PrisonerCommunications._route(repo, rider, Vector2i(3000, 0))
	for i: int in 20:
		if state.prisoner_proposals.release.communications.fulfillment.phase != "riding":
			break
		_day()
	assert_eq(int(state.military_cohorts.source.released), 10)
	assert_eq(int(state.military_cohorts.source2.released), 10)
	assert_true(_view("release").result.is_empty())
	for i: int in 20:
		if state.couriers.is_empty():
			break
		_day()
	assert_eq(int(_view("release").result.get("released", -1)), 20)
	assert_eq(int(state.military_cohorts.source.captured_current), 50)

func test_treaty_commands_reach_foreign_holder_without_military_authority() -> void:
	var second := _second_capture(buyer, seller, 10)
	state.foes.holder2 = {"x_m": 1000, "y_m": 0}
	state.regiments.erase("holder2")
	var proposal := _proposal("treaty")
	proposal.kind = "exchange"
	proposal.money = 0
	proposal.parties.payer = ""
	proposal.batches.append({"batch_id": second, "count": 10, "wounded_count": 0})
	_accepted(proposal)
	assert_true(_act("PRISONER_SETTLE", {"proposal_id": proposal.id}).ok)
	assert_eq(int(state.military_cohorts.source.released), 0)
	_day()
	assert_eq(int(state.military_cohorts.source.released), 10)
	assert_eq(int(state.military_cohorts.source2.released), 10)
	assert_false(state.foes.holder2.has("order_id"))
	_day()
	assert_eq(_view("treaty").status, "fulfilled")

func test_lawful_release_promise_accepts_and_is_enforced_at_fulfillment() -> void:
	var proposal := _release()
	proposal.terms = {"no_fighting_until_day": state.absolute_day() + 30}
	_accepted(proposal)
	assert_true(_act("PRISONER_SETTLE", {"proposal_id": proposal.id}).ok)
	assert_eq(int(state.military_cohorts.source.civilian_promises[0].count), 10)

func test_return_leg_expiry_cannot_publish_response_or_receipt() -> void:
	assert_true(_act("PRISONER_PROPOSE", _proposal()).ok)
	_day()
	repo.balance.courier_max_days = 0
	_day()
	assert_eq(state.couriers.size(), 0)
	assert_false(state.prisoner_proposals.ransom52.consents.has(buyer))
	assert_eq(_view().status, "unconfirmed")
	assert_eq(int(state.prisoner_proposals.ransom52.communications.offers[buyer].received_day), 0)
	# A different accepted agreement executes, but its lost receipt stays unknown.
	repo.balance.courier_max_days = 100
	_accepted(_proposal("receipt"))
	_move("holder", 1000)
	assert_true(_act("PRISONER_SETTLE", {"proposal_id": "receipt"}).ok)
	_day()
	assert_eq(int(state.military_cohorts.source.released), 10)
	repo.balance.courier_max_days = 0
	_day()
	assert_eq(state.couriers.size(), 0)
	assert_true(_view("receipt").result.is_empty())
	assert_eq(_view("receipt").status, "unconfirmed")
	assert_false(state.prisoner_proposals.receipt.communications.fulfillment.has("received_day"))

func test_removed_holder_fails_without_releasing_and_waits_for_failure_receipt() -> void:
	assert_true(_act("PRISONER_PROPOSE", _release()).ok)
	_move("holder", 1000)
	assert_true(_act("PRISONER_SETTLE", {"proposal_id": "release"}).ok)
	var funds := int(state.metrics.treasury)
	state.regiments.erase("holder")
	_day()
	assert_eq(_view("release").status, "fulfilling")
	assert_true(_view("release").result.is_empty())
	assert_eq(int(state.military_cohorts.source.released), 0)
	_day()
	assert_eq(_view("release").status, "failed")
	assert_eq(int(state.metrics.treasury), funds)

func test_ransom_checks_actual_payer_funds_for_every_responding_holder() -> void:
	var other := repo.resolve_realm("neighbor_realm")
	var second := _second_capture(other, buyer, 10)
	state.world[_treasury(other)] = 0
	var cap := String(repo.kingdoms[other].capital_burg)
	var at := ArmySystem.metres_to_pack(repo, Vector2i(1000, 0))
	repo.burgs[cap].x = at.x
	repo.burgs[cap].y = at.y
	var proposal := _proposal("multiple")
	proposal.batches.append({"batch_id": second, "count": 10, "wounded_count": 0})
	assert_true(_act("PRISONER_PROPOSE", proposal).ok)
	assert_eq(state.couriers.size(), 2)
	_day()
	_day()
	assert_eq(_view("multiple").status, "accepted")
	assert_true(_view("multiple").consents[other], "A nonpaying holder needs no ransom funds")

func test_undelivered_offer_returns_failure_without_fabricating_rejection() -> void:
	assert_true(_act("PRISONER_PROPOSE", _proposal()).ok)
	repo.balance.courier_max_days = 0
	_day()
	assert_false(state.prisoner_proposals.ransom52.consents.has(buyer))
	assert_eq(_view().status, "proposed", "The delivery failure is still on its return leg")
	assert_eq(state.couriers.size(), 1)
	repo.balance.courier_max_days = 100
	_day()
	assert_false(state.prisoner_proposals.ransom52.consents.has(buyer))
	assert_eq(_view().status, "unconfirmed")
	assert_string_contains(_view().reason, "not delivered")
	assert_eq(int(state.military_cohorts.source.released), 0)
	assert_eq(int(state.world[_treasury(buyer)]), 500)

func test_redundant_player_response_cannot_disclose_remote_execution() -> void:
	_accepted(_proposal())
	_move("holder", 1000)
	assert_true(_act("PRISONER_SETTLE", {"proposal_id": "ransom52"}).ok)
	_day()
	assert_eq(state.prisoner_proposals.ransom52.status, "fulfilled")
	var reply := _act("PRISONER_RESPOND", {"proposal_id": "ransom52", "accepted": true})
	assert_true(reply.ok, str(reply))
	assert_eq(reply.prisoner_result.status, "fulfilling")
	assert_eq(_view().status, "fulfilling")
	assert_true(_view().result.is_empty())

func test_later_response_preserves_another_partys_delivery_failure() -> void:
	var other := repo.resolve_realm("neighbor_realm")
	var second := _second_capture(other, buyer, 10)
	var cap := String(repo.kingdoms[other].capital_burg)
	var at := ArmySystem.metres_to_pack(repo, Vector2i(1000, 0))
	repo.burgs[cap].x = at.x
	repo.burgs[cap].y = at.y
	var proposal := _proposal("partial")
	proposal.batches.append({"batch_id": second, "count": 10, "wounded_count": 0})
	assert_true(_act("PRISONER_PROPOSE", proposal).ok)
	var failed_realm := String(CourierSystem.first_order(state.couriers[0]).realm)
	var accepted_realm := String(CourierSystem.first_order(state.couriers[1]).realm)
	repo.balance.courier_max_days = 1
	state.couriers[0].days = 1
	_day()
	_day()
	assert_eq(_view("partial").status, "unconfirmed")
	assert_string_contains(_view("partial").reason, "not delivered")
	assert_false(_view("partial").consents.has(failed_realm))
	assert_true(_view("partial").consents[accepted_realm])
