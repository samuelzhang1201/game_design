extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func _fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 944)
	var codes := state.regiments.keys()
	codes.sort()
	var enemy := String(state.foes.keys()[0])
	state.battles = [{"id": 944, "att": [codes[0], codes[1]], "def": [enemy], "rounds": 0}]
	state.king_state.x_m = 100000000
	state.king_state.y_m = 100000000
	state.metrics.treasury = 100
	repo.courier_kinds.ordinary.gold = 2
	return {"repo": repo, "state": state, "a": String(codes[0]), "b": String(codes[1]), "enemy": enemy}

func _request(f: Dictionary, id: String, task := "flank", unit := "") -> ActionRequest:
	return ActionRequest.make("BATTLE_TASK", {"request_id": id, "regiment": f.a if unit == "" else unit,
		"battle_id": 944, "task": task, "target_unit": f.enemy})

func test_remote_dispatch_charges_once_and_json_retry_is_inert() -> void:
	var f := _fixture()
	var actions := ActionSystem.new(f.repo)
	var req := _request(f, "paid")
	assert_eq(actions.validate(req, f.state), "")
	if actions.validate(req, f.state) != "": return
	var out := actions.execute(req, f.state)
	assert_true(out.ok)
	if not out.ok: return
	assert_eq(int(f.state.metrics.treasury), 97, "one filing gold plus two courier gold")
	assert_eq(f.state.couriers.size(), 1)
	assert_true(BattleTaskSystem.current(f.state, f.a).is_empty())
	assert_eq(f.state.unit_tasks[f.a].orders.paid.status, "pending")
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	saved.metrics.treasury = 0
	var before: Dictionary = saved.to_dict()
	assert_eq(actions.execute(req, saved), out)
	assert_eq(saved.to_dict(), before)
	req.params.task = "defend"
	assert_false(actions.execute(req, saved).ok)
	assert_eq(saved.to_dict(), before)

func test_local_receipt_is_unit_scoped_and_costs_only_filing() -> void:
	var f := _fixture()
	var at := ArmySystem.pack_to_metres(f.repo, ArmySystem.position_of(f.repo, f.state, ArmySystem.regiment(f.repo, f.a, f.state)))
	f.state.king_state.x_m = at.x
	f.state.king_state.y_m = at.y
	assert_true(KingSystem.can_command(f.repo, f.state, f.a))
	var actions := ActionSystem.new(f.repo)
	assert_eq(actions.validate(_request(f, "local"), f.state), "")
	if actions.validate(_request(f, "local"), f.state) != "": return
	var out := actions.execute(_request(f, "local"), f.state)
	assert_true(out.ok)
	if not out.ok: return
	assert_eq(int(f.state.metrics.treasury), 99)
	assert_eq(f.state.couriers.size(), 0)
	assert_eq(BattleTaskSystem.current(f.state, f.a).request.task, "flank")
	assert_true(BattleTaskSystem.current(f.state, f.b).is_empty())

func test_invalid_authority_scope_and_unaffordable_requests_are_atomic() -> void:
	var f := _fixture()
	var actions := ActionSystem.new(f.repo)
	for patch: Dictionary in [{"source": "general"}, {"issuer": "king"}, {"formation": "line"},
			{"regiment": f.enemy}, {"battle_id": 945}, {"target_unit": f.a}, {"task": "unknown"},
			{"request_id": ""}, {"battle_id": 944.5}]:
		var req := _request(f, "bad")
		req.params.merge(patch, true)
		var before: Dictionary = f.state.to_dict()
		assert_ne(actions.validate(req, f.state), "")
		assert_eq(f.state.to_dict(), before)
	f.state.metrics.treasury = 2
	var before: Dictionary = f.state.to_dict()
	assert_ne(actions.validate(_request(f, "poor"), f.state), "")
	assert_eq(f.state.to_dict(), before)

func test_shared_courier_replaces_on_receipt_only_and_keeps_unit_b_untouched() -> void:
	var f := _fixture()
	var actions := ActionSystem.new(f.repo)
	assert_eq(actions.validate(_request(f, "first"), f.state), "")
	if actions.validate(_request(f, "first"), f.state) != "": return
	var first := actions.execute(_request(f, "first"), f.state)
	assert_true(first.ok)
	if not first.ok: return
	assert_true(actions.execute(_request(f, "second", "defend"), f.state).ok)
	assert_eq(int(f.state.metrics.treasury), 96, "two filing fees and one shared courier")
	assert_eq(f.state.couriers.size(), 1)
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	assert_eq(CourierSystem._deliver(f.repo, saved, saved.couriers[0]).type, "delivered")
	assert_eq(BattleTaskSystem.current(saved, f.a).request.id, "second")
	assert_true(BattleTaskSystem.current(saved, f.b).is_empty())
	assert_eq(saved.unit_tasks[f.a].orders.first.status, "replaced")
	var before: Dictionary = saved.to_dict()
	BattleTaskSystem.deliver_task(f.repo, saved, "first")
	assert_eq(saved.to_dict(), before)

func test_receipt_rechecks_law_and_missing_unit_and_deadline_lapse_pending_task() -> void:
	for problem: String in ["law", "missing", "deadline"]:
		var f := _fixture()
		var actions := ActionSystem.new(f.repo)
		assert_eq(actions.validate(_request(f, problem), f.state), "")
		if actions.validate(_request(f, problem), f.state) != "": continue
		var out := actions.execute(_request(f, problem), f.state)
		assert_true(out.ok)
		if not out.ok: continue
		var courier: Dictionary = f.state.couriers[0]
		if problem == "law":
			f.state.battles[0]["parley"] = {"agreed": {"ceasefire": {"policy": "protect"}}}
			assert_eq(CourierSystem._deliver(f.repo, f.state, courier).type, "lapsed")
		else:
			if problem == "missing":
				f.state.regiments.erase(f.a)
			else:
				courier.days = int(f.repo.bal("courier_max_days"))
			var events: Array = []
			CourierSystem._ride(f.repo, f.state, courier, f.state.absolute_day(), events)
		assert_eq(f.state.unit_tasks[f.a].orders[problem].status, "invalid")
		assert_true(BattleTaskSystem.current(f.state, f.a).is_empty())
		assert_eq(int(f.state.metrics.treasury), 97, "spent fees are not refunded")

func test_reserved_gold_and_foreign_realm_cannot_fund_or_receive_task() -> void:
	var f := _fixture()
	var actions := ActionSystem.new(f.repo)
	f.state.metrics.treasury = 3
	f.state.battle_orders["promise"] = {"status": "pending", "reserved_gold": 1}
	assert_ne(actions.validate(_request(f, "reserved"), f.state), "")
	f.state.battle_orders.clear()
	f.state.metrics.treasury = 100
	f.state.army_roster[f.a]["kingdom_code"] = f.repo.resolve_realm("raider_realm")
	assert_ne(actions.validate(_request(f, "foreign"), f.state), "")

func test_delivery_rejects_changed_realm_or_wrong_courier_recipient() -> void:
	var f := _fixture()
	var actions := ActionSystem.new(f.repo)
	assert_true(actions.execute(_request(f, "sent"), f.state).ok)
	var courier: Dictionary = f.state.couriers[0]
	var wrong := courier.duplicate(true)
	wrong.target = f.b
	assert_eq(CourierSystem._deliver(f.repo, f.state, wrong).type, "lapsed")
	assert_eq(f.state.unit_tasks[f.a].orders.sent.status, "pending")
	f.state.army_roster[f.a]["kingdom_code"] = f.repo.resolve_realm("raider_realm")
	assert_eq(CourierSystem._deliver(f.repo, f.state, courier).type, "lapsed")
	assert_eq(f.state.unit_tasks[f.a].orders.sent.status, "invalid")

func test_non_text_request_ids_are_refused_without_mutation() -> void:
	var f := _fixture()
	var actions := ActionSystem.new(f.repo)
	for id: Variant in [42, null, [], {}]:
		var req := _request(f, "malformed")
		req.params.request_id = id
		var before: Dictionary = f.state.to_dict()
		assert_ne(actions.validate(req, f.state), "")
		assert_false(actions.execute(req, f.state).ok)
		assert_eq(f.state.to_dict(), before)

func _cancel(f: Dictionary, id: String) -> ActionRequest:
	return ActionRequest.make("BATTLE_TASK_CANCEL", {"request_id": id, "regiment": f.a, "battle_id": 944})

func test_cancellation_waits_for_receipt_and_blocks_older_warrant_after_json() -> void:
	var f := _fixture()
	var actions := ActionSystem.new(f.repo)
	assert_true(actions.execute(_request(f, "active"), f.state).ok)
	BattleTaskSystem.deliver_task(f.repo, f.state, "active")
	assert_true(actions.execute(_request(f, "late", "defend"), f.state).ok)
	var req := _cancel(f, "cancel")
	assert_eq(actions.validate(req, f.state), "")
	if actions.validate(req, f.state) != "": return
	var out := actions.execute(req, f.state)
	assert_true(out.ok)
	assert_eq(BattleTaskSystem.current(f.state, f.a).request.id, "active")
	assert_eq(int(f.state.metrics.treasury), 95, "three filings and one shared courier")
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	var pending_before: Dictionary = saved.to_dict()
	assert_eq(actions.execute(req, saved), out)
	assert_eq(saved.to_dict(), pending_before)
	var courier: Dictionary = saved.couriers[0].duplicate(true)
	courier.orders = [{"action_code": "BATTLE_TASK", "unit_task_id": "cancel"}]
	assert_eq(CourierSystem._deliver(f.repo, saved, courier).type, "delivered")
	assert_true(BattleTaskSystem.current(saved, f.a).is_empty())
	assert_eq(saved.unit_tasks[f.a].orders.active.status, "cancelled")
	assert_ne(saved.unit_tasks[f.a].orders.active.reason, "")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, saved, "late").status, "superseded")
	saved.metrics.treasury = 0
	var before: Dictionary = saved.to_dict()
	assert_eq(actions.execute(req, saved), out)
	assert_eq(BattleTaskSystem.deliver_task(f.repo, saved, "cancel").status, "received")
	assert_eq(saved.to_dict(), before)
	assert_true(BattleTaskSystem.current(saved, f.b).is_empty())

func test_local_cancellation_is_a_paid_barrier_and_future_task_can_arrive() -> void:
	var f := _fixture()
	var at := ArmySystem.pack_to_metres(f.repo, ArmySystem.position_of(f.repo, f.state, ArmySystem.regiment(f.repo, f.a, f.state)))
	f.state.king_state.x_m = at.x
	f.state.king_state.y_m = at.y
	var actions := ActionSystem.new(f.repo)
	assert_eq(actions.validate(_cancel(f, "empty"), f.state), "")
	if actions.validate(_cancel(f, "empty"), f.state) != "": return
	assert_true(actions.execute(_cancel(f, "empty"), f.state).ok)
	assert_eq(int(f.state.metrics.treasury), 99)
	assert_eq(f.state.couriers.size(), 0)
	assert_true(BattleTaskSystem.current(f.state, f.a).is_empty())
	var before: Dictionary = f.state.to_dict()
	var conflicting := _cancel(f, "empty")
	conflicting.action_code = "BATTLE_TASK"
	assert_false(actions.execute(conflicting, f.state).ok)
	assert_eq(f.state.to_dict(), before)
	assert_true(actions.execute(_request(f, "new"), f.state).ok)
	assert_eq(BattleTaskSystem.current(f.state, f.a).request.id, "new")

func test_cancellation_refusals_and_cross_action_reuse_are_atomic() -> void:
	var f := _fixture()
	var actions := ActionSystem.new(f.repo)
	for patch: Dictionary in [{"regiment": f.enemy}, {"battle_id": 945}, {"task": "flank"},
			{"source": "general"}, {"request_id": 42}, {"battle_id": 944.5}]:
		var req := _cancel(f, "bad")
		req.params.merge(patch, true)
		var before: Dictionary = f.state.to_dict()
		assert_false(actions.execute(req, f.state).ok)
		assert_eq(f.state.to_dict(), before)
	assert_true(actions.execute(_request(f, "used"), f.state).ok)
	var before: Dictionary = f.state.to_dict()
	assert_false(actions.execute(_cancel(f, "used"), f.state).ok)
	assert_eq(f.state.to_dict(), before)
	f.state.metrics.treasury = 0
	before = f.state.to_dict()
	assert_false(actions.execute(_cancel(f, "poor"), f.state).ok)
	assert_eq(f.state.to_dict(), before)

func test_cancellation_receipt_rechecks_control_and_lapses_with_courier() -> void:
	for problem: String in ["foreign", "missing", "battle", "deadline"]:
		var f := _fixture()
		var actions := ActionSystem.new(f.repo)
		assert_eq(actions.validate(_cancel(f, problem), f.state), "")
		if actions.validate(_cancel(f, problem), f.state) != "": continue
		assert_true(actions.execute(_cancel(f, problem), f.state).ok)
		var courier: Dictionary = f.state.couriers[0]
		match problem:
			"foreign": f.state.army_roster[f.a]["kingdom_code"] = f.repo.resolve_realm("raider_realm")
			"missing": f.state.regiments.erase(f.a)
			"battle": f.state.battles.clear()
			"deadline": courier.days = int(f.repo.bal("courier_max_days"))
		if problem in ["missing", "deadline"]:
			var events: Array = []
			CourierSystem._ride(f.repo, f.state, courier, f.state.absolute_day(), events)
		else:
			assert_eq(CourierSystem._deliver(f.repo, f.state, courier).type, "lapsed")
		assert_eq(f.state.unit_tasks[f.a].orders[problem].status, "invalid")
		assert_eq(int(f.state.metrics.treasury), 97)

func test_cancel_can_arrive_under_ceasefire_without_executing_old_attack() -> void:
	var f := _fixture()
	var actions := ActionSystem.new(f.repo)
	assert_true(actions.execute(_request(f, "attack"), f.state).ok)
	BattleTaskSystem.deliver_task(f.repo, f.state, "attack")
	f.state.battles[0]["parley"] = {"agreed": {"ceasefire": {"policy": "protect"}}}
	assert_eq(actions.validate(_cancel(f, "stop"), f.state), "")
	if actions.validate(_cancel(f, "stop"), f.state) != "": return
	assert_true(actions.execute(_cancel(f, "stop"), f.state).ok)
	assert_eq(CourierSystem._deliver(f.repo, f.state, f.state.couriers[0]).type, "delivered")
	assert_true(BattleTaskSystem.current(f.state, f.a).is_empty())
	assert_eq(f.state.unit_tasks[f.a].orders.attack.status, "cancelled")

func test_cancel_respects_reserved_gold_and_rejects_assignment_alias() -> void:
	var f := _fixture()
	var actions := ActionSystem.new(f.repo)
	f.state.metrics.treasury = 3
	f.state.battle_orders["reserved"] = {"status": "pending", "reserved_gold": 1}
	var before: Dictionary = f.state.to_dict()
	assert_false(actions.execute(_cancel(f, "reserved"), f.state).ok)
	assert_eq(f.state.to_dict(), before)
	assert_false(actions.execute(_request(f, "alias", "cancel"), f.state).ok)
	assert_eq(f.state.to_dict(), before)

func test_cancellation_is_received_when_the_actual_courier_finishes_riding() -> void:
	var f := _fixture()
	var actions := ActionSystem.new(f.repo)
	assert_true(actions.execute(_request(f, "old"), f.state).ok)
	BattleTaskSystem.deliver_task(f.repo, f.state, "old")
	assert_true(actions.execute(_cancel(f, "riding"), f.state).ok)
	var saved := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	var courier: Dictionary = saved.couriers[0]
	# Resume the saved rider at the recipient after his final road segment.
	courier.x_m = courier.aim_x_m
	courier.y_m = courier.aim_y_m
	courier.path = []
	assert_eq(BattleTaskSystem.current(saved, f.a).request.id, "old")
	var events := CourierSystem.ride_day(f.repo, saved)
	assert_eq(events.size(), 1)
	assert_eq(events[0].type, "delivered")
	assert_eq(saved.couriers.size(), 0)
	assert_true(BattleTaskSystem.current(saved, f.a).is_empty())
	assert_eq(saved.unit_tasks[f.a].orders.old.status, "cancelled")
