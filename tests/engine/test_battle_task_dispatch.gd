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
