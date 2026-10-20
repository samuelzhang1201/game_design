extends GutTest
## A task quote can use current enemy condition only under royal observation.
const ViewTests := preload("res://tests/engine/test_task_view_intel.gd")

func _fixture() -> Dictionary:
	var helper := ViewTests.new()
	var f := helper._fixture()
	helper.free()
	return f

func _remove_fit(f: Dictionary) -> void:
	for id: String in f.state.military_rosters[f.enemy].cohort_ids:
		var cohort: Dictionary = f.state.military_cohorts[id]
		cohort.wounded = int(cohort.wounded) + int(cohort.fit)
		cohort.fit = 0

func _quote(f: Dictionary, target: String = "") -> Dictionary:
	return BattlePresentation.task_quote(f.repo, f.state, f.a, "flank", f.enemy if target == "" else target)

func _request(quote: Dictionary) -> ActionRequest:
	return ActionRequest.make(quote.action_code, quote.params)

func test_hidden_personnel_capture_and_position_preserve_quote_and_json_replay() -> void:
	for change: String in ["personnel", "capture", "position"]:
		var f := _fixture()
		var saved := JSON.stringify(f.state.to_dict())
		var before := _quote(f)
		assert_eq(before.reason, "", change)
		assert_eq(JSON.stringify(f.state.to_dict()), saved, "A quote mutates neither state nor RNG")
		match change:
			"personnel": _remove_fit(f)
			"capture": f.state.foes[f.enemy].captured = true
			"position": f.state.foes[f.enemy].x_m -= 100000
		assert_eq(_quote(f), before, "Unobserved " + change + " cannot change a quote")
		var hidden := JSON.stringify(f.state.to_dict())
		f.state = GameState.from_dict(JSON.parse_string(hidden))
		assert_eq(_quote(f), before, "Equal observer evidence survives JSON: " + change)
		assert_eq(JSON.stringify(f.state.to_dict()), hidden, "Replay preview is read-only")
		if change != "position":
			var actions := ActionSystem.new(f.repo)
			assert_ne(actions.validate(_request(before), f.state), "", "Execution still validates real target condition")
			assert_false(actions.execute(_request(before), f.state).ok)
			assert_eq(JSON.stringify(f.state.to_dict()), hidden, "Failed execution spends and changes nothing")

func test_direct_observation_refreshes_condition_refusal() -> void:
	for change: String in ["personnel", "capture"]:
		var f := _fixture()
		f.state.king_state.x_m = int(f.state.foes[f.enemy].x_m)
		f.state.king_state.y_m = int(f.state.foes[f.enemy].y_m)
		assert_true(BattlePresentation.local_unit(f.repo, f.state, f.enemy))
		assert_eq(_quote(f).reason, "")
		if change == "personnel": _remove_fit(f)
		else: f.state.foes[f.enemy].captured = true
		var quote := _quote(f)
		assert_ne(quote.reason, "", "Current local observation refreshes " + change)
		assert_eq(quote.reason, ActionSystem.new(f.repo).validate(_request(quote), f.state))

func test_unknown_target_own_condition_law_and_affordability_still_refuse() -> void:
	var f := _fixture()
	assert_ne(_quote(f, "not-a-battle-member").reason, "")
	assert_ne(_quote(f, f.b).reason, "", "A friendly unit is not an enemy target")
	f.state.foes[f.enemy].captured = true
	f.state.battles[0]["parley"] = {"agreed": {"ceasefire": {"policy": "protect"}}}
	assert_eq(_quote(f).reason, "Received military law or an agreed battlefield term forbids this unit task.")
	f.state.battles[0].erase("parley")
	f.state.metrics.treasury = 2
	assert_eq(_quote(f).reason, "The chancery cannot pay for this unit task.")
	f.state.metrics.treasury = 3
	f.state.battle_orders["reserved"] = {"status": "pending", "reserved_gold": 1}
	assert_eq(_quote(f).reason, "The chancery cannot pay for this unit task.", "Reserved rewards cannot fund a quote")
	f.state.battle_orders.clear()
	f.state.metrics.treasury = 100
	f.state.regiments[f.a].captured = true
	assert_ne(_quote(f).reason, "", "Own capture cannot be hidden by the preview boundary")

func test_received_law_and_delivery_revalidate_actual_condition() -> void:
	var f := _fixture()
	f.state.law_in_force["unit:" + f.a] = {"battle_tactics": {"value": "restrained", "decree_id": 1}}
	assert_ne(BattlePresentation.task_quote(f.repo, f.state, f.a, "charge", f.enemy).reason, "")
	f.state.law_in_force.clear()
	var quote := _quote(f)
	assert_eq(quote.reason, "")
	assert_true(ActionSystem.new(f.repo).execute(_request(quote), f.state).ok)
	var paid := int(f.state.metrics.treasury)
	_remove_fit(f)
	assert_eq(CourierSystem._deliver(f.repo, f.state, f.state.couriers[0]).type, "lapsed")
	assert_eq(int(f.state.metrics.treasury), paid, "Delivery failure does not charge again")
	assert_eq(BattleTaskSystem.current(f.state, f.a), {})
