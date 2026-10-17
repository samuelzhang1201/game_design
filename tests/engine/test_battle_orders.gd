extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func test_orders_reserve_and_execute_once() -> void:
	var orders: GDScript = load("res://scripts/engine/battle_orders.gd")
	assert_not_null(orders)
	if orders == null:
		return
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 924)
	var mine := state.regiments.keys()
	mine.sort()
	var code := String(mine[0])
	state.battles.append({"id": 992, "att": [code], "def": [state.foes.keys()[0]], "rounds": 0})
	_thousand(state, code)
	state.metrics["treasury"] = 98.0
	state.regiments[code]["morale"] = 50
	var order := {"id": "inspire-one", "battle_id": 992, "side": "att", "kind": "inspire",
		"issued_day": state.absolute_day(), "params": {"regiment": code}}
	var issued: Dictionary = orders.issue(repo, state, order)
	assert_eq(issued.get("status"), "pending")
	assert_eq(orders.available_gold(state), 91)
	var first: Dictionary = orders.deliver(repo, state, "inspire-one")
	assert_eq(first.get("status"), "delivered")
	assert_eq(int(state.metrics["treasury"]), 91)
	var morale := int(state.regiments[code]["morale"])
	assert_gt(morale, 50)
	assert_eq(orders.deliver(repo, state, "inspire-one"), first)
	assert_eq(int(state.regiments[code]["morale"]), morale)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	orders.deliver(repo, restored, "inspire-one")
	assert_eq(int(restored.metrics["treasury"]), 91)
	assert_eq(int(restored.regiments[code]["morale"]), morale)

func _thousand(state: GameState, code: String) -> void:
	var roster: Dictionary = state.military_rosters[code]
	var ids: Array = roster.cohort_ids
	var first := String(ids[0])
	for id: String in ids:
		if id != first:
			state.military_cohorts.erase(id)
	roster.cohort_ids = [first]
	roster.commander_id = ""
	var cohort: Dictionary = state.military_cohorts[first]
	cohort.erase("person_id")
	cohort.identity = "commoner"
	cohort.initial = 1000
	cohort.fit = 1000
	for status: String in ["wounded", "dead", "captured_current", "released"]:
		cohort[status] = 0

func _fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 925)
	var mine := state.regiments.keys()
	mine.sort()
	var code := String(mine[0])
	var battle := {"id": 993, "att": [code], "def": [state.foes.keys()[0]], "rounds": 0,
		"place_x_m": 0, "place_y_m": 0}
	state.battles.append(battle)
	_thousand(state, code)
	state.metrics["treasury"] = 100.0
	state.regiments[code]["morale"] = 50
	state.king_state["x_m"] = 100000000
	state.king_state["y_m"] = 100000000
	repo.courier_kinds["ordinary"]["gold"] = 2
	return {"repo": repo, "state": state, "code": code, "battle": battle}

func _order(f: Dictionary, id: String, action: String) -> Dictionary:
	return {"id": id, "battle_id": 993, "side": "att", "kind": action,
		"issued_day": f.state.absolute_day(), "params": {"regiment": f.code}}

func test_cancel_end_and_membership_release_only_unspent_reward() -> void:
	var f := _fixture()
	BattleOrders.issue(f.repo, f.state, _order(f, "cancel", "inspire"))
	assert_eq(BattleOrders.available_gold(f.state), 93)
	BattleOrders.invalidate(f.repo, f.state, "cancel", "The king cancels this reward.")
	assert_eq(BattleOrders.available_gold(f.state), 100)
	BattleOrders.deliver(f.repo, f.state, "cancel")
	assert_eq(int(f.state.metrics.treasury), 100)
	BattleOrders.issue(f.repo, f.state, _order(f, "end", "inspire"))
	BattleOrders.end_battle(f.repo, f.state, 993, "The battle has ended.")
	f.state.battles.clear()
	BattleOrders.deliver(f.repo, f.state, "end")
	assert_eq(BattleOrders.available_gold(f.state), 100)
	assert_eq(f.state.battle_orders.end.status, "invalid")
	f = _fixture()
	BattleOrders.issue(f.repo, f.state, _order(f, "member", "inspire"))
	f.battle.att.clear()
	assert_eq(BattleOrders.deliver(f.repo, f.state, "member").status, "invalid")
	assert_eq(BattleOrders.available_gold(f.state), 100)

func test_last_delivered_action_wins_and_inspire_keeps_it() -> void:
	var f := _fixture()
	BattleOrders.issue(f.repo, f.state, _order(f, "old-attack", "attack"))
	BattleOrders.issue(f.repo, f.state, _order(f, "new-hold", "hold"))
	BattleOrders.deliver(f.repo, f.state, "new-hold")
	BattleOrders.deliver(f.repo, f.state, "old-attack")
	assert_eq(BattleOrders.kind(f.battle, "att"), "attack")
	BattleOrders.issue(f.repo, f.state, _order(f, "aid", "inspire"))
	BattleOrders.deliver(f.repo, f.state, "aid")
	assert_eq(BattleOrders.kind(f.battle, "att"), "attack")
	assert_eq(BattleOrders.issue(f.repo, f.state, _order(f, "aid-two", "inspire")).status, "invalid")
	assert_eq(int(f.state.regiments[f.code].morale), 58)

func test_law_is_revalidated_at_send_and_arrival() -> void:
	var f := _fixture()
	f.battle.parley = {"agreed": {"ceasefire": {"policy": "protect"}}}
	assert_eq(BattleOrders.issue(f.repo, f.state, _order(f, "forbidden", "attack")).status, "invalid")
	f.battle.erase("parley")
	BattleOrders.issue(f.repo, f.state, _order(f, "sent", "attack"))
	f.battle.parley = {"agreed": {"ceasefire": {"policy": "protect"}}}
	assert_eq(BattleOrders.deliver(f.repo, f.state, "sent").status, "invalid")
	assert_eq(BattleOrders.kind(f.battle, "att"), "hold")

func test_action_replay_and_remote_fee_fixture() -> void:
	var f := _fixture()
	var actions := ActionSystem.new(f.repo)
	var req := ActionRequest.make("BATTLE_ORDER", {"regiment": f.code, "battle_id": 993,
		"kind": "inspire", "request_id": "paid"})
	assert_eq(actions.validate(req, f.state), "")
	var first := actions.execute(req, f.state)
	assert_true(first.ok)
	assert_eq(int(f.state.metrics.treasury), 98)
	assert_eq(BattleOrders.available_gold(f.state), 91)
	var count: int = f.state.recent_outcomes.size()
	assert_eq(actions.execute(req, f.state), first)
	assert_eq(f.state.recent_outcomes.size(), count)
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	assert_eq(actions.execute(req, saved), first)
	var rider: Dictionary = f.state.couriers.back()
	f.state.regiments[f.code]["order_id"] = int(rider.id) + 99
	CourierSystem._deliver(f.repo, f.state, rider)
	assert_eq(int(f.state.metrics.treasury), 91)
	assert_eq(BattleOrders.available_gold(f.state), 91)
	assert_eq(int(f.state.regiments[f.code].morale), 58)
	CourierSystem._deliver(f.repo, f.state, rider)
	assert_eq(int(f.state.regiments[f.code].morale), 58)
	req.params.kind = "hold"
	assert_false(actions.execute(req, f.state).ok)

func test_local_king_and_same_courier_batch() -> void:
	var f := _fixture()
	var at := ArmySystem.pack_to_metres(f.repo, ArmySystem.position_of(f.repo, f.state, ArmySystem.regiment(f.repo, f.code, f.state)))
	f.state.king_state.x_m = at.x
	f.state.king_state.y_m = at.y
	f.battle.place_x_m = at.x
	f.battle.place_y_m = at.y
	var actions := ActionSystem.new(f.repo)
	var req := ActionRequest.make("BATTLE_ORDER", {"regiment": f.code, "battle_id": 993,
		"kind": "inspire", "request_id": "local"})
	actions.execute(req, f.state)
	assert_eq(f.state.couriers.size(), 0)
	assert_eq(int(f.state.metrics.treasury), 93)
	assert_eq(int(f.state.regiments[f.code].morale), 62)
	f = _fixture()
	actions = ActionSystem.new(f.repo)
	for action: String in ["attack", "hold", "retreat"]:
		actions.execute(ActionRequest.make("BATTLE_ORDER", {"regiment": f.code, "battle_id": 993,
			"kind": action, "request_id": action}), f.state)
	assert_eq(f.state.couriers.size(), 1)
	CourierSystem._deliver(f.repo, f.state, f.state.couriers[0])
	assert_eq(BattleOrders.kind(f.battle, "att"), "retreat")

func test_other_spenders_cannot_use_reserved_gold() -> void:
	var f := _fixture()
	f.state.metrics.treasury = 10.0
	BattleOrders.issue(f.repo, f.state, _order(f, "reserved", "inspire"))
	var actions := ActionSystem.new(f.repo)
	assert_ne(actions.validate(ActionRequest.make("GOODS_BUY", {"pool": "strategic", "gold": 4}), f.state), "")

func test_surrender_refusal_preserves_action_acceptance_captures_wounded() -> void:
	var f := _fixture()
	var enemy := String(f.battle.def[0])
	f.state.foes[enemy]["received_laws"] = {"quarter": {"value": "refuse", "decree_id": 1}}
	BattleOrders.issue(f.repo, f.state, _order(f, "attack-first", "attack"))
	BattleOrders.deliver(f.repo, f.state, "attack-first")
	BattleOrders.issue(f.repo, f.state, _order(f, "refused", "surrender"))
	var refusal := BattleOrders.deliver(f.repo, f.state, "refused")
	assert_eq(refusal.status, "refused")
	assert_eq(BattleOrders.kind(f.battle, "att"), "attack")
	var cohort_id := String(f.state.military_rosters[f.code].cohort_ids[0])
	MilitaryRoster.transition(f.repo, f.state, "wounded-before", [{"cohort_id": cohort_id, "from": "fit", "to": "wounded", "count": 1}], "Wounded before surrender.")
	var living := MilitaryRoster.living(f.state, f.code)
	f.battle.parley = {"agreed": {"surrender": {"policy": "accept"}}}
	BattleOrders.issue(f.repo, f.state, _order(f, "accepted", "surrender"))
	var accepted := BattleOrders.deliver(f.repo, f.state, "accepted")
	assert_eq(accepted.status, "delivered")
	var captured := 0
	for id: String in f.state.military_rosters[f.code].cohort_ids:
		captured += int(f.state.military_cohorts[id].captured_current)
	assert_eq(captured, living)
	assert_eq(MilitaryRoster.living(f.state, f.code), 0)
	assert_true(f.battle.att.is_empty())
	assert_eq(accepted.result.capture_handoff.captor_unit, enemy)
	assert_false(accepted.result.capture_handoff.units[0].equipment.is_empty())
	assert_eq(BattleOrders.deliver(f.repo, f.state, "accepted"), accepted)

func test_lost_and_expired_couriers_release_reservations() -> void:
	for lost: bool in [true, false]:
		var f := _fixture()
		var actions := ActionSystem.new(f.repo)
		actions.execute(ActionRequest.make("BATTLE_ORDER", {"regiment": f.code, "battle_id": 993,
			"kind": "inspire", "request_id": "lost"}), f.state)
		var rider: Dictionary = f.state.couriers[0]
		if lost:
			f.state.regiments.erase(f.code)
		else:
			rider.days = int(f.repo.bal("courier_max_days"))
		var events: Array = []
		CourierSystem._ride(f.repo, f.state, rider, f.state.absolute_day(), events)
		assert_eq(f.state.battle_orders.lost.status, "invalid")
		assert_eq(int(f.state.metrics.treasury), 98)
		assert_eq(BattleOrders.available_gold(f.state), 98)

func test_reward_scales_with_living_personnel_hand_values() -> void:
	var repo := SuiteData.repo()
	assert_eq(BattleOrders.reward_gold(repo, 1000), 7, "ceil(1000 × 7 / 1000)")
	assert_eq(BattleOrders.reward_gold(repo, 500), 4, "ceil(500 × 7 / 1000)")
	assert_eq(BattleOrders.reward_gold(repo, 1), 1)
	assert_eq(BattleOrders.reward_gold(repo, 0), 0)

func test_surrender_cost_is_personnel_without_a_local_filing_fee() -> void:
	for accepts: bool in [true, false]:
		var f := _fixture()
		var at := ArmySystem.pack_to_metres(f.repo, ArmySystem.position_of(f.repo, f.state, ArmySystem.regiment(f.repo, f.code, f.state)))
		f.state.king_state.x_m = at.x
		f.state.king_state.y_m = at.y
		var enemy := String(f.battle.def[0])
		f.state.foes[enemy].received_laws = {"quarter": {"value": "give" if accepts else "refuse", "decree_id": 1}}
		var outcome := ActionSystem.new(f.repo).execute(ActionRequest.make("BATTLE_ORDER", {"regiment": f.code,
			"battle_id": 993, "kind": "surrender", "request_id": "no-extra-fee"}), f.state)
		assert_true(outcome.ok)
		assert_eq(int(f.state.metrics.treasury), 100)

func test_reinforcement_does_not_enlarge_the_promised_reward() -> void:
	var f := _fixture()
	BattleOrders.issue(f.repo, f.state, _order(f, "limited", "inspire"))
	var mine: Array = f.state.regiments.keys()
	mine.erase(f.code)
	var extra := String(mine[0])
	f.state.regiments[extra].morale = 40
	f.battle.att.append(extra)
	BattleOrders.deliver(f.repo, f.state, "limited")
	assert_eq(int(f.state.metrics.treasury), 93)
	assert_eq(int(f.state.regiments[extra].morale), 40)

func test_later_delivered_hold_stops_an_active_withdrawal_route() -> void:
	var f := _fixture()
	var entry: Dictionary = f.state.regiments[f.code]
	entry["battle_retreat"] = true
	entry["disengaging"] = 1
	entry["order"] = ArmySystem.ORDER_MARCH
	entry["departure"] = {"dest_x_m": 100000, "dest_y_m": 100000}
	BattleOrders.issue(f.repo, f.state, _order(f, "hold-again", "hold"))
	assert_eq(BattleOrders.deliver(f.repo, f.state, "hold-again").status, "delivered")
	assert_false(bool(entry.get("battle_retreat", false)))
	assert_ne(String(entry["order"]), ArmySystem.ORDER_MARCH)
	assert_false(entry.has("departure"))

func test_captured_unit_cannot_receive_regular_orders_or_march() -> void:
	var f := _fixture()
	f.state.regiments[f.code]["captured"] = true
	var entry: Dictionary = f.state.regiments[f.code]
	var at := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	var request := ActionRequest.make("ARMY_GARRISON", {"regiment": f.code})
	assert_ne(ActionSystem.new(f.repo).validate(request, f.state), "")
	entry["order"] = ArmySystem.ORDER_MARCH
	entry["dest_x_m"] = at.x + 100000
	entry["dest_y_m"] = at.y
	assert_false(ArmySystem._march_one(f.repo, f.state, f.code, entry, f.state.absolute_day()))
	assert_eq(Vector2i(int(entry["x_m"]), int(entry["y_m"])), at)

func test_surrender_includes_an_army_with_only_wounded_survivors() -> void:
	var f := _fixture()
	assert_false(MilitaryRoster.transfer_units(f.repo, f.state, "all-wounded", [{"unit_code": f.code,
		"from": "fit", "to": "wounded", "count": 1000}], "The last fit personnel are wounded").has("error"))
	var issued := BattleOrders.issue(f.repo, f.state, _order(f, "wounded-surrender", "surrender"))
	assert_eq(issued.status, "pending")
	assert_eq(BattleOrders.deliver(f.repo, f.state, "wounded-surrender").status, "delivered")
	assert_eq(MilitaryRoster.living(f.state, f.code), 0)
	var count := 0
	for id: String in f.state.military_rosters[f.code].cohort_ids:
		count += int(f.state.military_cohorts[id].captured_current)
	assert_eq(count, 1000)
