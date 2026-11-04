extends GutTest

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _fixture(fit: int = 100) -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_deploy.gd").new()
	var f: Dictionary = helper.call("_field", fit)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	f.code = f.unit
	_put(f, f.code, [50000, 60000])
	_put(f, f.enemy, [48000, 60000])
	_put(f, f.other, [100000, 100000])
	var entry := UnitBodies._entry(f.state, f.code)
	entry.order = ArmySystem.ORDER_MARCH
	entry.dest_x_m = 90000
	entry.dest_y_m = 60000
	entry.route_m = [[90000, 60000]]
	entry.battle_retreat = true
	entry.disengaging = 1
	entry.withdrawal_cause = "retreat"
	f.state.battles[0].actions.att = {"kind": "retreat", "reason": "Received withdrawal"}
	f.state.day_resolution.march_budgets[f.code] = 10000
	f.state.day_resolution.march_budgets[f.enemy] = 0
	f.state.day_resolution.march_budgets[f.other] = 0
	f.repo.balance.battle_deploy_step_m = 10000
	f.repo.balance.army_run_min_score = 1000000 # Isolate the hand-computed walking slice from commander gait.
	entry.erase("gait")
	return f

func _put(f: Dictionary, code: String, point: Array) -> void:
	var entry := UnitBodies._entry(f.state, code)
	entry.x_m = point[0]
	entry.y_m = point[1]
	f.state.battles[0].group_anchor_m[code] = point.duplicate()
	var slot := 0
	for row: Dictionary in f.state.battles[0].groups[code]:
		row.x_m = point[0]
		row.y_m = point[1] + slot * 1954
		slot += 1

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _advance(f: Dictionary, state: GameState) -> GameState:
	if state.military_migration.has("body_motion"):
		var closed := BodyMotion.close_battle_locomotion_candidate(f.repo, state, BodyBattleMotion._boundary(state))
		assert_eq(closed.status, "complete", closed.reason)
		if closed.candidate == null: return state
		state = closed.candidate
	state.day_resolution.body_battle.stage = "advance"
	state.day_resolution.battle_step = "fighting"
	BodyBattle._seal_private(f.repo, state)
	return state

func _withdraw(f: Dictionary, state: GameState) -> Dictionary:
	var boundary := BodyBattleMotion._boundary(state)
	var request := {"kind": "withdraw", "unit": f.code, "battle_id": "8", "reason": "Actual separated withdrawal"}
	var before := BodyMotion._hash(state.to_dict())
	var plan := BodyBattle.plan_candidate(f.repo, state, request, boundary)
	assert_eq(BodyMotion._hash(state.to_dict()), before)
	if plan.status != "complete": return plan
	var result := BodyBattle.commit_candidate(f.repo, state, plan.plan, boundary)
	assert_eq(BodyMotion._hash(state.to_dict()), before)
	return result

func test_blocked_retreat_keeps_owner() -> void:
	var api: GDScript = load("res://scripts/engine/battle_system.gd")
	assert_true(api.has_method("retreat_intent_candidate"), "withdrawal needs its pure route provider")
	if not api.has_method("retreat_intent_candidate"): return
	var f := _fixture()
	# A hostile protected circle occupies the requested route; it still blocks the sweep.
	_put(f, f.other, [52000, 60000])
	f.state.foes[f.other].battle_retreat = true
	f.state.battles[0].parley = {"agreed": {"safe_withdrawal": {"policy": "protect", "until_day": 0}},
		"parties": {"att": [f.code], "def": [f.enemy, f.other]}}
	var boundary := BodyBattleMotion._boundary(f.state)
	var planned := BodyBattleMotion.plan_candidate(f.repo, f.state, boundary)
	assert_eq(planned.status, "complete", planned.reason)
	if planned.plan.is_empty(): return
	var moved := BodyBattleMotion.commit_candidate(f.repo, f.state, planned.plan, boundary)
	assert_eq(moved.status, "complete", moved.reason)
	if moved.candidate == null: return
	assert_lt(UnitBodies._entry(moved.candidate, f.code).x_m, 52000 - 1731 + 1)
	var state := _advance(f, moved.candidate)
	var exit := _withdraw(f, state)
	assert_eq(exit.status, "deferred", exit.reason)
	assert_null(exit.candidate)
	assert_true(f.code in state.battles[0].att)
	assert_false(UnitBodies._entry(state, f.code).has("body_groups"))
	var protected := BodyBattleContact.query_candidate(f.repo, state, 8, f.code, [f.other], BodyBattleMotion._boundary(state))
	assert_eq(protected.status, "complete", protected.reason)
	assert_eq(protected.engaged, 0)
	assert_true(protected.reason.contains("safe withdrawal"))

func test_separated_exit_preserves_exact_rows_and_replay() -> void:
	var f := _fixture(901)
	_put(f, f.enemy, [30000, 60000])
	var state := _advance(f, f.state)
	var rows: Array = state.battles[0].groups[f.code].duplicate(true)
	var boundary := BodyBattleMotion._boundary(state)
	var result := _withdraw(f, state)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	var after: GameState = result.candidate
	assert_eq(UnitBodies._entry(after, f.code).body_groups, rows)
	assert_eq(UnitBodies._entry(after, f.code).body_groups.map(func(row: Dictionary) -> int: return row.count), [100, 100, 100, 100, 100, 100, 100, 100, 100, 1])
	assert_eq(UnitBodies._entry(after, f.code).group_next_slot, 20)
	assert_false(f.code in after.battles[0].att)
	assert_false(after.battles[0].groups.has(f.code))
	assert_eq(after.military_cohorts, state.military_cohorts)
	assert_eq(after.rng.to_dict(), state.rng.to_dict())
	assert_eq(after.day_resolution.journal.battles.back().kind, "withdrawal")
	for source: GameState in [after, _json(after)]:
		var retry := BodyBattle.commit_candidate(f.repo, source, result.plan, boundary)
		assert_eq(retry.status, "complete", retry.reason)
		if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), BodyMotion._hash(after.to_dict()))

func test_no_safe_destination_holds_pose_and_records_reason() -> void:
	var api: GDScript = load("res://scripts/engine/battle_system.gd")
	if not api.has_method("retreat_intent_candidate"): return
	var f := _fixture()
	var entry := UnitBodies._entry(f.state, f.code)
	entry.order = ArmySystem.ORDER_GARRISON
	entry.erase("battle_retreat")
	entry.erase("disengaging")
	entry.erase("route_m")
	f.repo.burgs.clear()
	var before := BodyMotion._hash(f.state.to_dict())
	var intent: Dictionary = api.call("retreat_intent_candidate", f.repo, f.state, 8, f.code, 1000)
	assert_eq(intent.status, "complete", intent.reason)
	assert_eq(intent.path_m, [[50000, 60000]])
	assert_true(intent.reason.contains("safe destination"))
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	var boundary := BodyBattleMotion._boundary(f.state)
	var planned := BodyBattleMotion.plan_candidate(f.repo, f.state, boundary)
	assert_eq(planned.status, "complete", planned.reason)
	if planned.plan.is_empty(): return
	var moved := BodyBattleMotion.commit_candidate(f.repo, f.state, planned.plan, boundary)
	assert_eq(moved.status, "complete", moved.reason)
	if moved.candidate == null: return
	for key: String in ["slot", "home_slot", "count", "x_m", "y_m", "facing_deg", "role"]:
		assert_eq(moved.candidate.battles[0].groups[f.code][0][key], f.state.battles[0].groups[f.code][0][key])
	assert_true(UnitBodies._entry(moved.candidate, f.code).withdrawal_reason.contains("safe destination"))
	assert_eq(UnitBodies._entry(moved.candidate, f.code).supplies, entry.supplies)
	assert_eq(UnitBodies._entry(moved.candidate, f.code).morale, entry.morale)
	assert_eq(_withdraw(f, _advance(f, moved.candidate)).status, "deferred")

func test_request_is_not_retreat_authority_and_raw_requests_are_closed() -> void:
	var f := _fixture()
	UnitBodies._entry(f.state, f.code).erase("battle_retreat")
	UnitBodies._entry(f.state, f.code).erase("disengaging")
	f.state.battles[0].actions.att.kind = "hold"
	UnitBodies._entry(f.state, f.code).order = ArmySystem.ORDER_GARRISON
	_put(f, f.enemy, [30000, 60000])
	var state := _advance(f, f.state)
	assert_eq(_withdraw(f, state).status, "deferred", "a request reason cannot authorize withdrawal")
	var request := {"kind": "withdraw", "unit": f.code, "battle_id": "8", "reason": "Received"}
	for field: String in ["battle_id", "reason", "extra"]:
		var corrupt := request.duplicate(true)
		corrupt[field] = true
		var before := BodyMotion._hash(state.to_dict())
		assert_eq(BodyBattle.plan_candidate(f.repo, state, corrupt, BodyBattleMotion._boundary(state)).status, "error")
		assert_eq(BodyMotion._hash(state.to_dict()), before)

func test_raw_withdrawal_controls_reject_before_deferral_direct_and_json() -> void:
	for field: String in ["battle_retreat", "disengaging", "dest_x_m", "withdrawal_cause"]:
		for raw: Variant in [true, 1.5, "1"]:
			if field == "battle_retreat" and raw is bool: continue
			for imported: bool in [false, true]:
				var f := _fixture()
				if imported: f.state.military_migration.import_main_v7 = {}
				else: f.state.military_migration.erase("import_main_v7")
				UnitBodies._entry(f.state, f.code)[field] = raw
				if field == "withdrawal_cause" and raw is String: continue
				for state: GameState in [f.state, _json(f.state)]:
					var before := BodyMotion._hash(state.to_dict())
					var result := BodyBattleMotion.plan_candidate(f.repo, state, BodyBattleMotion._boundary(state))
					assert_eq(result.status, "error", "%s=%s imported=%s" % [field, raw, imported])
					assert_null(result.candidate)
					assert_eq(BodyMotion._hash(state.to_dict()), before)

func test_swept_separation_then_exit_and_costs_are_once() -> void:
	var f := _fixture()
	f.state.day_resolution.march_budgets[f.code] = 60000
	f.repo.balance.battle_deploy_step_m = 60000
	var entry := UnitBodies._entry(f.state, f.code)
	entry.erase("battle_retreat")
	entry.erase("disengaging")
	var before := BodyMotion._hash(f.state.to_dict())
	var boundary := BodyBattleMotion._boundary(f.state)
	var p := BodyBattleMotion.plan_candidate(f.repo, f.state, boundary)
	assert_eq(p.status, "complete", p.reason)
	if p.plan.is_empty(): return
	var result := BodyBattleMotion.commit_candidate(f.repo, f.state, p.plan, boundary)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	if result.candidate == null: return
	var after: GameState = result.candidate
	# Facing east, 6000m slice: actual body and anchor move6000, enemy gap becomes8000.
	assert_eq(UnitBodies._entry(after, f.code).x_m, 56000)
	assert_eq(after.battles[0].groups[f.code][0].x_m, 56000)
	assert_eq(UnitBodies._entry(after, f.code).route_m, [[90000, 60000]], "unreached route survives the clipped contribution")
	assert_eq(after.battles[0].withdrawal_costs.size(), 1)
	assert_eq(UnitBodies._entry(after, f.code).morale, entry.morale - 5)
	assert_eq(UnitBodies._entry(after, f.code).supplies, 90000)
	for source: GameState in [after, _json(after)]:
		var retry := BodyBattleMotion.commit_candidate(f.repo, source, p.plan, boundary)
		assert_eq(retry.status, "complete", retry.reason)
		if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), BodyMotion._hash(after.to_dict()))
	var exit := _withdraw(f, _advance(f, after))
	assert_eq(exit.status, "complete", exit.reason)
	if exit.candidate != null:
		assert_eq(UnitBodies._entry(exit.candidate, f.code).supplies, 90000)
		assert_eq(exit.candidate.battles[0].withdrawal_costs.size(), 1)
		assert_eq(UnitBodies._entry(exit.candidate, f.code).body_groups[0].x_m, 56000)

func test_tail_contact_prevents_exit_even_after_anchor_separates() -> void:
	var f := _fixture()
	_put(f, f.code, [70000, 60000])
	f.state.battles[0].groups[f.code][0].x_m = 50000
	_put(f, f.enemy, [48169, 60000])
	var state := _advance(f, f.state)
	var before := BodyMotion._hash(state.to_dict())
	assert_eq(_withdraw(f, state).status, "deferred")
	assert_eq(BodyMotion._hash(state.to_dict()), before)
	assert_true(f.code in state.battles[0].att)
	var incoming := BodyBattleContact.query_candidate(f.repo, state, 8, f.enemy, [f.code], BodyBattleMotion._boundary(state))
	assert_eq(incoming.status, "complete", incoming.reason)
	assert_eq(incoming.engaged, 100, "unprotected withdrawing tail remains exposed to lawful incoming contact")

func test_forged_exit_and_changed_endpoint_fail_atomically() -> void:
	var f := _fixture()
	_put(f, f.enemy, [30000, 60000])
	var state := _advance(f, f.state)
	var boundary := BodyBattleMotion._boundary(state)
	var request := {"kind": "withdraw", "unit": f.code, "battle_id": "8", "reason": "Received withdrawal"}
	var p := BodyBattle.plan_candidate(f.repo, state, request, boundary)
	assert_eq(p.status, "complete", p.reason)
	if p.plan.is_empty(): return
	var forged: Dictionary = p.plan.duplicate(true)
	forged.request.reason = "Another reason"
	var before := BodyMotion._hash(state.to_dict())
	assert_eq(BodyBattle.commit_candidate(f.repo, state, forged, boundary).status, "error")
	assert_eq(BodyMotion._hash(state.to_dict()), before)
	var done := BodyBattle.commit_candidate(f.repo, state, p.plan, boundary)
	assert_eq(done.status, "complete", done.reason)
	if done.candidate == null: return
	for change: String in ["rows", "paid", "receipt", "party", "rng"]:
		var source := _json(done.candidate)
		match change:
			"rows": UnitBodies._entry(source, f.code).body_groups[0].x_m += 1
			"paid": UnitBodies._entry(source, f.code).supplies -= 1
			"receipt": source.military_migration.body_battle.receipt = "a".repeat(64)
			"party": source.battles[0].parley = {"agreed": {"ceasefire": {"policy": "protect", "until_day": 0}}}
			"rng": source.rng.randi_range(0, 100)
		var original := BodyMotion._hash(source.to_dict())
		var retry := BodyBattle.commit_candidate(f.repo, source, p.plan, boundary)
		assert_eq(retry.status, "error", change)
		assert_null(retry.candidate)
		assert_eq(BodyMotion._hash(source.to_dict()), original)

func test_rout_uses_same_exposed_route_without_offensive_pursuit_credit() -> void:
	var f := _fixture()
	var entry := UnitBodies._entry(f.state, f.code)
	entry.erase("battle_retreat")
	entry.erase("disengaging")
	entry.erase("withdrawal_cause")
	f.state.battles[0].actions.att.kind = "hold"
	f.state.battles[0].routed_side = "att"
	f.state.unit_tasks = {f.code: {"current_id": "pursue", "received_sequence": 1, "orders": {"pursue": {
		"sequence": 1, "status": "bounded", "reason": "Received route exhausted", "history": [],
		"pursuit": {"start_x_m": 50000, "start_y_m": 60000, "route_m": 250},
		"request": {"id": "pursue", "unit": f.code, "battle_id": 8, "task": "pursue", "formation": "",
			"target_unit": f.enemy, "source": "player", "issuer": "", "max_route_m": 250, "region": ""}}}}}
	var boundary := BodyBattleMotion._boundary(f.state)
	var p := BodyBattleMotion.plan_candidate(f.repo, f.state, boundary)
	assert_eq(p.status, "complete", p.reason)
	if p.plan.is_empty(): return
	var moved := BodyBattleMotion.commit_candidate(f.repo, f.state, p.plan, boundary)
	assert_eq(moved.status, "complete", moved.reason)
	if moved.candidate != null:
		assert_eq(UnitBodies._entry(moved.candidate, f.code).x_m, 51000)
		assert_eq(UnitBodies._entry(moved.candidate, f.code).withdrawal_cause, "rout")
		assert_eq(BattleTaskSystem.current(moved.candidate, f.code).pursuit.route_m, 250)
		assert_true(f.code in moved.candidate.battles[0].att, "routing alone cannot remove an exposed body")

func test_partial_and_empty_stores_keep_identity_and_personnel() -> void:
	for fit: int in [1000, 901, 900, 1, 0]:
		var f := _fixture(fit)
		var boundary := BodyBattleMotion._boundary(f.state)
		var p := BodyBattleMotion.plan_candidate(f.repo, f.state, boundary)
		assert_eq(p.status, "complete", "%d: %s" % [fit, p.reason])
		if p.plan.is_empty(): continue
		var moved := BodyBattleMotion.commit_candidate(f.repo, f.state, p.plan, boundary)
		assert_eq(moved.status, "complete", moved.reason)
		if moved.candidate == null: continue
		var rows: Array = moved.candidate.battles[0].groups[f.code]
		assert_eq(rows.size(), BattleGroups.counts(fit, 100).size())
		for i: int in rows.size():
			for key: String in ["slot", "home_slot", "count", "role"]:
				assert_eq(rows[i][key], f.state.battles[0].groups[f.code][i][key])
		assert_eq(UnitBodies._entry(moved.candidate, f.code).group_next_slot, 20)
		assert_eq(moved.candidate.military_cohorts, f.state.military_cohorts)
		assert_eq(moved.candidate.rng.to_dict(), f.state.rng.to_dict())
		assert_true(f.code in moved.candidate.battles[0].att)

func test_legacy_entry_wire_codec_and_new_request_raw_schema_remain_distinct() -> void:
	var f := _fixture()
	# Existing regiment integers are encoded on disk; this wire value is a valid legacy number.
	assert_eq(f.state.to_dict().regiments[f.code].disengaging, "i1")
	var loaded := _json(f.state)
	assert_eq(UnitBodies._entry(loaded, f.code).disengaging, 1)
	assert_eq(BodyBattleMotion.plan_candidate(f.repo, loaded, BodyBattleMotion._boundary(loaded)).status, "complete")
	# A direct candidate is already decoded; encoded-looking strings are invalid there.
	UnitBodies._entry(f.state, f.code).disengaging = "i1"
	assert_eq(BodyBattleMotion.plan_candidate(f.repo, f.state, BodyBattleMotion._boundary(f.state)).status, "error")
	f = _fixture()
	var state := _advance(f, f.state)
	for raw: Variant in [true, 8.5, 8, "i8", "f4020000000000000", "08", "0"]:
		var request := {"kind": "withdraw", "unit": f.code, "battle_id": raw, "reason": "Received"}
		for input: Dictionary in [request, JSON.parse_string(JSON.stringify(request))]:
			var before := BodyMotion._hash(state.to_dict())
			assert_eq(BodyBattle.plan_candidate(f.repo, state, input, BodyBattleMotion._boundary(state)).status, "error")
			assert_eq(BodyMotion._hash(state.to_dict()), before)

func test_integral_json_battle_id_preserves_exact_exit() -> void:
	var f := _fixture()
	_put(f, f.enemy, [30000, 60000])
	f.state.battles[0].id = 8.0
	var result := _withdraw(f, _advance(f, f.state))
	assert_eq(result.status, "complete", result.reason)
	if result.candidate != null: assert_true(UnitBodies._entry(result.candidate, f.code).has("body_groups"))

func test_malformed_withdrawal_action_rejects_without_runtime_or_mutation() -> void:
	for raw: Variant in [true, [], {"att": true}, {"att": {"kind": true}}, {"att": {"kind": "retreat", "reason": false}}]:
		var f := _fixture()
		f.state.battles[0].actions = raw
		for source: GameState in [f.state, _json(f.state)]:
			var before := BodyMotion._hash(source.to_dict())
			var result := BodyBattleMotion.plan_candidate(f.repo, source, BodyBattleMotion._boundary(source))
			assert_eq(result.status, "error")
			assert_null(result.candidate)
			assert_eq(BodyMotion._hash(source.to_dict()), before)

func test_inconsistent_received_route_never_falls_back_to_destination_chord() -> void:
	var f := _fixture()
	UnitBodies._entry(f.state, f.code).route_m = [[50000, 70000], [80000, 70000]]
	var before := BodyMotion._hash(f.state.to_dict())
	var contribution := BattleSystem.retreat_intent_candidate(f.repo, f.state, 8, f.code, 1000)
	assert_eq(contribution.status, "complete", contribution.reason)
	assert_eq(contribution.path_m, [[50000, 60000]], "a stale route cannot authorize a straight shortcut to another destination")
	assert_false(contribution.reason.is_empty())
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
