extends GutTest

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _fixture() -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_deploy.gd").new()
	var f: Dictionary = helper.call("_field")
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	f.code = f.unit
	_put(f, f.code, [50000, 60000])
	_put(f, f.enemy, [60000, 60000])
	_put(f, f.other, [100000, 100000])
	f.state.day_resolution.march_budgets[f.enemy] = 0
	f.state.day_resolution.march_budgets[f.other] = 0
	f.repo.balance.battle_deploy_step_m = 10000
	f.repo.balance.player_sight_km = 1 # Lost sight retains received geometry and ordered corners.
	f.state.unit_tasks = {f.code: {"current_id": "flank", "received_sequence": 1, "player_received_sequence": 1,
		"issued_sequence": 1, "orders": {"flank": {"sequence": 1, "status": "received", "reason": "Received", "history": [],
		"request": {"id": "flank", "unit": f.code, "battle_id": 8, "task": "flank", "formation": "",
		"target_unit": f.enemy, "source": "player", "issuer": "", "max_route_m": 0, "region": ""},
		"flank": {"known": {"x_m": 60000, "y_m": 60000, "facing_deg": 180, "radius_m": 804,
			"piece_radius_m": 804, "own_radius_m": 927, "points_m": [[60000, 60000]]},
			"path_m": [[50000, 61000], [58000, 61000]]}}}}}
	return f

func _put(f: Dictionary, code: String, point: Array) -> void:
	var entry := UnitBodies._entry(f.state, code)
	entry.x_m = point[0]
	entry.y_m = point[1]
	f.state.battles[0].group_anchor_m[code] = point.duplicate()
	for row: Dictionary in f.state.battles[0].groups[code]:
		row.x_m = point[0]
		row.y_m = point[1]

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _move(f: Dictionary, state: GameState = null) -> Dictionary:
	if state == null: state = f.state
	var before := BodyMotion._hash(state.to_dict())
	var boundary := BodyBattleMotion._boundary(state)
	var planned := BodyBattleMotion.plan_candidate(f.repo, state, boundary)
	assert_eq(planned.status, "complete", planned.reason)
	if planned.plan.is_empty(): return planned
	var moved := BodyBattleMotion.commit_candidate(f.repo, state, planned.plan, boundary)
	assert_eq(moved.status, "complete", moved.reason)
	assert_eq(BodyMotion._hash(state.to_dict()), before)
	return moved

func _next(f: Dictionary, state: GameState) -> void:
	var closed := BodyMotion.close_battle_locomotion_candidate(f.repo, state, BodyBattleMotion._boundary(state))
	assert_eq(closed.status, "complete", closed.reason)
	if closed.candidate == null: return
	f.state = closed.candidate
	var helper: GutTest = load("res://tests/engine/test_body_battle_closure.gd").new()
	helper.call("_successor", f.repo, f.state)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()

func test_waypoints_and_received_cancel() -> void:
	var api: GDScript = load("res://scripts/engine/battle_task_system.gd")
	assert_true(api.has_method("flank_intent_candidate"), "flank needs the received-route candidate provider")
	if not api.has_method("flank_intent_candidate"): return
	var f := _fixture()
	var before := BodyMotion._hash(f.state.to_dict())
	var intent: Dictionary = api.call("flank_intent_candidate", f.repo, f.state, 8, f.code, 1000)
	assert_eq(intent.path_m, [[50000, 60000], [50000, 61000]], "A→B before C, never the chord")
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	var moved := _move(f)
	if moved.candidate == null: return
	var row: Dictionary = moved.candidate.battles[0].groups[f.code][0]
	# Two 90-degree pivots cost 100000q each, leaving 800m of a 1000m allowance.
	assert_eq([row.x_m, row.y_m], [50000, 60800])
	assert_eq(BattleTaskSystem.current(moved.candidate, f.code).flank.path_m, [[50000, 61000], [58000, 61000]])
	assert_ne(BattleTaskSystem.current(moved.candidate, f.code).flank.get("phase"), "contact")
	assert_eq(moved.candidate.military_cohorts, f.state.military_cohorts)
	assert_eq(moved.candidate.rng.to_dict(), f.state.rng.to_dict())
	_next(f, moved.candidate)
	var second := _move(f, _json(f.state))
	if second.candidate != null:
		assert_eq(UnitBodies._entry(second.candidate, f.code).x_m, 50000)
		assert_eq(UnitBodies._entry(second.candidate, f.code).y_m, 61000)
		assert_eq(BattleTaskSystem.current(second.candidate, f.code).flank.path_m, [[58000, 61000]])
	f = _fixture()
	var cancel := BattleTaskSystem.issue_task(f.repo, f.state, {"id": "cancel", "unit": f.code, "battle_id": 8, "task": "cancel"})
	assert_eq(cancel.status, "pending", str(cancel))
	var pending := _move(f)
	if pending.candidate != null: assert_eq(UnitBodies._entry(pending.candidate, f.code).y_m, 60800, "pending cancel cannot stop the received route")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "cancel").status, "received")
	var after: Dictionary = f.state.unit_tasks.duplicate(true)
	var held: Dictionary = api.call("flank_intent_candidate", f.repo, f.state, 8, f.code, 1000)
	assert_eq(held.path_m, [[50000, 60000]])
	assert_eq(BattleTaskSystem.combat_action(f.repo, f.state, f.state.battles[0], f.code).kind, "hold")
	BattleTaskSystem.deliver_task(f.repo, f.state, "cancel")
	assert_eq(f.state.unit_tasks, after, "delivery retry retains filing/terminal receipts")

func test_blocked_wing_and_terrain_do_not_complete_or_skip_a_corner() -> void:
	for obstacle: String in ["peer", "terrain"]:
		var f := _fixture()
		if obstacle == "peer":
			_put(f, f.other, [50000, 62000])
			UnitBodies._entry(f.state, f.other).captured = true
		else: f.grid.closed[6 * f.grid.cols + 5] = 1
		var before := BodyMotion._hash(f.state.to_dict())
		if obstacle == "terrain":
			var intent := BattleTaskSystem.flank_intent_candidate(f.repo, f.state, 8, f.code, 1000)
			# Invalid source ground rejects before a route can be declared complete.
			assert_eq(intent.status, "error")
		else:
			var moved := _move(f)
			if moved.candidate != null:
				assert_eq(UnitBodies._entry(moved.candidate, f.code).x_m, 50000)
				assert_lt(UnitBodies._entry(moved.candidate, f.code).y_m, 61000)
				assert_eq(BattleTaskSystem.current(moved.candidate, f.code).flank.path_m, [[50000, 61000], [58000, 61000]])
				assert_ne(BattleTaskSystem.current(moved.candidate, f.code).flank.get("phase"), "contact")
		assert_eq(BodyMotion._hash(f.state.to_dict()), before)

func test_actual_contact_commits_phase_once_without_instantaneous_bonus() -> void:
	var f := _fixture()
	_put(f, f.enemy, [52831, 60000]) # 927+804+100+1000: only a real 1000m advance closes contact.
	var record: Dictionary = f.state.unit_tasks[f.code].orders.flank
	record.flank.known.x_m = 52831
	record.flank.known.points_m = [[52831, 60000]]
	record.flank.path_m = [[52000, 60000], [52000, 65000]]
	var moved := _move(f)
	if moved.candidate == null: return
	assert_eq(UnitBodies._entry(moved.candidate, f.code).x_m, 51000)
	assert_eq(BattleTaskSystem.current(moved.candidate, f.code).flank.phase, "contact")
	assert_eq(moved.candidate.battles[0].get("formations", {}), f.state.battles[0].get("formations", {}), "movement grants no formation/side/rear multiplier")
	var endpoint := BodyMotion._hash(moved.candidate.to_dict())
	for state: GameState in [moved.candidate, _json(moved.candidate)]:
		var retry := BodyBattleMotion.commit_candidate(f.repo, state, moved.plan, BodyBattleMotion._boundary(f.state))
		assert_eq(retry.status, "complete", retry.reason)
		if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), endpoint)
	_next(f, moved.candidate)
	var next := _move(f)
	if next.candidate != null: assert_eq(UnitBodies._entry(next.candidate, f.code).x_m, 51000, "contact never starts another circle")

func test_raw_geometry_is_rejected_direct_and_through_both_json_provenances() -> void:
	for imported: bool in [false, true]:
		for field: String in ["point", "path", "facing", "radius", "unknown", "phase", "pursuit"]:
			for raw: Variant in [true, 1.5, "i42", "f3ff0000000000000", null]:
				var f := _fixture()
				if imported: f.state.military_migration.import_main_v7 = {}
				else: f.state.military_migration.erase("import_main_v7")
				var flank: Dictionary = f.state.unit_tasks[f.code].orders.flank.flank
				match field:
					"point": flank.known.x_m = raw
					"path": flank.path_m[0][0] = raw
					"facing": flank.known.facing_deg = raw
					"radius": flank.known.radius_m = raw
					"unknown": flank.future = raw
					"phase": flank.phase = raw
					"pursuit": f.state.unit_tasks[f.code].orders.flank.pursuit = {"start_x_m": 50000, "start_y_m": 60000, "route_m": raw}
				for state: GameState in [f.state, _json(f.state)]:
					var before := BodyMotion._hash(state.to_dict())
					var result := BodyBattleMotion.plan_candidate(f.repo, state, BodyBattleMotion._boundary(state))
					assert_eq(result.status, "error", field + ":" + str(raw))
					assert_null(result.candidate)
					assert_eq(BodyMotion._hash(state.to_dict()), before)

func test_visible_snapshot_uses_exact_existing_rows_and_unseen_geometry_stays_frozen() -> void:
	var f := _fixture()
	f.repo.balance.player_sight_km = 100
	f.state.unit_tasks[f.code].orders.flank.erase("flank")
	f.state.foes[f.enemy].facing_deg = 90
	var source_hash := BodyMotion._hash(f.state.to_dict())
	var moved := _move(f)
	if moved.candidate == null: return
	var known: Dictionary = BattleTaskSystem.current(moved.candidate, f.code).flank.known
	assert_eq(known.points_m, [[60000, 60000]], "copy actual authoritative rows; never a formation layout")
	assert_eq(known.facing_deg, 90)
	assert_eq(known.piece_radius_m, 804)
	assert_eq(known.own_radius_m, 927)
	assert_eq(BodyMotion._hash(f.state.to_dict()), source_hash)
	f = _fixture()
	var first := BattleTaskSystem.flank_intent_candidate(f.repo, f.state, 8, f.code, 1000)
	_put(f, f.enemy, [70000, 70000])
	f.state.foes[f.enemy].facing_deg = 0
	var unseen := BattleTaskSystem.flank_intent_candidate(f.repo, f.state, 8, f.code, 1000)
	assert_eq(unseen.path_m, first.path_m)
	assert_eq(BattleTaskSystem.current(f.state, f.code).flank.known.points_m, [[60000, 60000]])

func _pursuit() -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_budget.gd").new()
	var f: Dictionary = helper.call("_fixture", [100], 10000)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	var entry := UnitBodies._entry(f.state, f.code)
	entry.route_m = [[50100, 50000], [50100, 51000]]
	entry.dest_x_m = 50100
	entry.dest_y_m = 51000
	f.state.day_resolution.march_entries[f.code] = entry.duplicate(true)
	f.state.unit_tasks = {f.code: {"current_id": "pursue", "received_sequence": 1, "orders": {"pursue": {
		"sequence": 1, "status": "received", "reason": "Received", "history": [], "pursuit": {"start_x_m": 50000, "start_y_m": 50000, "route_m": 90},
		"request": {"id": "pursue", "unit": f.code, "battle_id": 8, "task": "pursue", "formation": "", "target_unit": "",
		"source": "player", "issuer": "", "max_route_m": 250, "region": ""}}}}}
	return f

func test_bounded_pursuit_charges_actual_legs_once_and_never_displacement_chord() -> void:
	var f := _pursuit()
	var result := _move(f)
	if result.candidate == null: return
	var task := BattleTaskSystem.current(result.candidate, f.code)
	# Remaining allowance160; a 100m east leg then 60m north costs160, not sqrt(100²+60²).
	var move: Dictionary = result.plan.motion.moves[0]
	assert_lte(move.used_m, 160)
	assert_eq(task.pursuit.route_m, 90 + int(move.used_m))
	assert_lte(task.pursuit.route_m, 250)
	var before := BodyMotion._hash(result.candidate.to_dict())
	for source: GameState in [result.candidate, _json(result.candidate)]:
		var retry := BodyBattleMotion.commit_candidate(f.repo, source, result.plan, BodyBattleMotion._boundary(f.state))
		assert_eq(retry.status, "complete", retry.reason)
		if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), before)

func test_legacy_unopted_task_codec_and_opted_integral_json_are_preserved() -> void:
	var f := _fixture()
	f.state.unit_tasks[f.code].orders.flank.flank.known.x_m = 60000.0
	var loaded := _json(f.state)
	assert_true(BattleTaskSystem.current(loaded, f.code).flank.known.x_m is int)
	assert_eq(BattleTaskSystem.current(loaded, f.code).flank.known.x_m, 60000)
	f.state.military_migration.erase("body_version")
	f.state.unit_tasks[f.code].orders.flank.flank.known.x_m = 60000.4
	assert_eq(BattleTaskSystem.current(_json(f.state), f.code).flank.known.x_m, 60000, "unopted legacy behavior remains rounded")

func test_pursuit_requires_received_player_authority_and_bounds_region_after_real_route() -> void:
	var f := _pursuit()
	f.state.unit_tasks[f.code].orders.pursue.request.source = "general"
	var result := _move(f)
	if result.candidate != null:
		assert_eq(UnitBodies._entry(result.candidate, f.code).x_m, 50000, "a general's plan grants no pursuit")
		assert_eq(BattleTaskSystem.current(result.candidate, f.code).pursuit.route_m, 90)
	f = _pursuit()
	var provinces: Array = f.repo.provinces.keys()
	provinces.sort()
	var region: String = provinces[0]
	var polygon := PackedVector2Array()
	for point: Vector2i in [Vector2i(40000, 40000), Vector2i(50100, 40000), Vector2i(50100, 60000), Vector2i(40000, 60000)]:
		polygon.append(ArmySystem.metres_to_pack(f.repo, point))
	f.repo.province_borders = {region: [polygon]}
	f.state.manor_province.clear()
	var task: Dictionary = f.state.unit_tasks[f.code].orders.pursue
	task.request.region = region
	task.request.max_route_m = 0
	f.state.regiments[f.code].route_m = [[51000, 50000]]
	f.state.regiments[f.code].dest_x_m = 51000
	f.state.regiments[f.code].dest_y_m = 50000
	f.state.day_resolution.march_entries[f.code] = f.state.regiments[f.code].duplicate(true)
	result = _move(f)
	if result.candidate != null:
		assert_eq(UnitBodies._entry(result.candidate, f.code).x_m, 50100)
		assert_eq(BattleTaskSystem.current(result.candidate, f.code).status, "bounded")
		assert_eq(BattleTaskSystem.current(result.candidate, f.code).pursuit.route_m, 190)

func test_invalid_provider_controls_and_forged_receipt_fail_without_mutation() -> void:
	var f := _fixture()
	for budget: int in [-1, BodyMotion.LOCAL_LIMIT + 1]:
		assert_eq(BattleTaskSystem.flank_intent_candidate(f.repo, f.state, 8, f.code, budget).status, "error")
	assert_eq(BattleTaskSystem.flank_intent_candidate(f.repo, f.state, 99, f.code, 100).status, "error")
	assert_eq(BattleTaskSystem.flank_intent_candidate(f.repo, f.state, 8, "missing", 100).status, "error")
	var moved := _move(f)
	if moved.candidate == null: return
	for change: String in ["waypoint", "phase", "receipt", "paid", "rng"]:
		var state := _json(moved.candidate)
		match change:
			"waypoint": state.unit_tasks[f.code].orders.flank.flank.path_m[0][1] += 1
			"phase": state.unit_tasks[f.code].orders.flank.flank.phase = "contact"
			"receipt": state.military_migration.body_battle.receipt = "a".repeat(64)
			"paid": UnitBodies._entry(state, f.code).supplies -= 1
			"rng": state.rng.randi_range(0, 100)
		var before := BodyMotion._hash(state.to_dict())
		var retry := BodyBattleMotion.commit_candidate(f.repo, state, moved.plan, BodyBattleMotion._boundary(f.state))
		assert_eq(retry.status, "error", change)
		assert_null(retry.candidate)
		assert_eq(BodyMotion._hash(state.to_dict()), before)

func test_generated_route_chooses_full_radius_reachable_wing() -> void:
	var f := _fixture()
	f.repo.balance.player_sight_km = 100
	f.state.unit_tasks[f.code].orders.flank.erase("flank")
	f.grid.cell_m = 1000
	f.grid.cols = 200
	f.grid.rows = 200
	f.grid.closed.resize(40000)
	f.grid.water.resize(40000)
	# North stage centre58169 is dry, but its927m disc touches the cell ending58000.
	f.grid.closed[57 * 200 + 50] = 1
	var before := BodyMotion._hash(f.state.to_dict())
	var result := BattleTaskSystem.flank_intent_candidate(f.repo, f.state, 8, f.code, 1000)
	assert_eq(result.status, "complete", result.reason)
	assert_gt(result.path_m.size(), 1, "south wing remains reachable at the real measured radius")
	if result.path_m.size() > 1: assert_gt(int(result.path_m[1][1]), 60000)
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)

func test_pursuit_cannot_take_a_friendly_detour_outside_received_region() -> void:
	var f := _pursuit()
	var helper: GutTest = load("res://tests/engine/test_body_battle_budget.gd").new()
	var pair: Dictionary = helper.call("_fixture", [100, 100], 1000000)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	pair.state.unit_tasks = f.state.unit_tasks.duplicate(true)
	f = pair
	for i: int in f.codes.size():
		var code: String = f.codes[i]
		var entry := UnitBodies._entry(f.state, code)
		entry.x_m = 50000 + i * 2000
		entry.y_m = 50000
		entry.dest_x_m = 55000 if i == 0 else entry.x_m
		entry.dest_y_m = 50000
		entry.route_m = [[entry.dest_x_m, 50000]]
		for row: Dictionary in entry.body_groups:
			row.x_m = entry.x_m
			row.y_m = entry.y_m
		f.state.day_resolution.march_entries[code] = entry.duplicate(true)
		if i == 1: f.state.day_resolution.march_budgets[code] = 0
	var regions: Array = f.repo.provinces.keys()
	regions.sort()
	var region: String = regions[0]
	var polygon := PackedVector2Array()
	for point: Vector2i in [Vector2i(40000, 49999), Vector2i(60000, 49999), Vector2i(60000, 50001), Vector2i(40000, 50001)]:
		polygon.append(ArmySystem.metres_to_pack(f.repo, point))
	f.repo.province_borders = {region: [polygon]}
	f.state.manor_province.clear()
	f.state.unit_tasks[f.code].orders.pursue.request.max_route_m = 0
	f.state.unit_tasks[f.code].orders.pursue.request.region = region
	var before := BodyMotion._hash(f.state.to_dict())
	var unbounded := UnitBodies._copy(f.state)
	unbounded.unit_tasks[f.code].orders.pursue.request.region = ""
	var baseline := BodyBattleMotion.plan_candidate(f.repo, unbounded, BodyBattleMotion._boundary(unbounded))
	assert_eq(baseline.status, "complete", baseline.reason)
	if not baseline.plan.is_empty():
		var own: Dictionary = baseline.plan.motion.moves.filter(func(move: Dictionary) -> bool: return move.unit == f.code)[0]
		assert_true(BodyMotion._loco_path(own).any(func(point: Array) -> bool: return point[1] != 50000), "fixture really takes a friendly side detour: " + str(own))
	var result := BodyBattleMotion.plan_candidate(f.repo, f.state, BodyBattleMotion._boundary(f.state))
	assert_eq(result.status, "error", "a desired in-region route cannot certify an out-of-region physical detour")
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)

func test_actual_withdrawal_is_never_clipped_or_charged_to_offensive_pursuit() -> void:
	var f := _pursuit()
	f.state.regiments[f.code].disengaging = 1
	f.state.day_resolution.march_entries[f.code].disengaging = 1
	var result := _move(f)
	if result.candidate != null:
		assert_gt(int(result.plan.motion.moves[0].budget_m), 160)
		assert_eq(BattleTaskSystem.current(result.candidate, f.code).pursuit.route_m, 90)
		assert_eq(BattleTaskSystem.current(result.candidate, f.code).status, "received")

func test_partial_rosters_keep_survivors_and_empty_units_never_gain_contact() -> void:
	var personnel: GDScript = load("res://tests/engine/personnel_helpers.gd")
	for fit: int in [1000, 901, 900, 1, 0]:
		var f := _fixture()
		assert_false(personnel.replace(f.repo, f.state, f.code, fit).has("error"))
		var rows: Array = []
		var remaining := fit
		while remaining > 0:
			var slot := rows.size()
			rows.append({"slot": slot, "home_slot": slot, "count": mini(100, remaining), "role": "reserve",
				"x_m": 50000, "y_m": 60000 + slot * 1954, "facing_deg": 0, "path_m": []})
			remaining -= mini(100, remaining)
		f.state.battles[0].groups[f.code] = rows
		var result := _move(f)
		if result.candidate == null: continue
		var actual: Array = result.candidate.battles[0].groups[f.code]
		assert_eq(actual.size(), rows.size())
		for i: int in rows.size():
			for key: String in ["slot", "home_slot", "count", "role"]: assert_eq(actual[i][key], rows[i][key])
		assert_eq(UnitBodies._entry(result.candidate, f.code).group_next_slot, 20)
		assert_eq(result.candidate.military_cohorts, f.state.military_cohorts)
		assert_ne(BattleTaskSystem.current(result.candidate, f.code).flank.get("phase"), "contact")

func test_full_flank_commit_keeps_historical_party_inference_off_source() -> void:
	var f := _fixture()
	f.state.battles[0].parley = {"agreed": {"tactics": {"policy": "restrained", "until_day": 0}}}
	var before := BodyMotion._hash(f.state.to_dict())
	for state: GameState in [f.state, _json(f.state)]:
		var result := _move(f, state)
		assert_eq(BodyMotion._hash(state.to_dict()), before, "historical parties are inferred only on detached staging")
		if result.candidate != null:
			assert_eq(UnitBodies._entry(result.candidate, f.code).y_m, 60800)

func test_live_observation_rejects_noninteger_facing_before_snapshot() -> void:
	for raw: Variant in [true, 1.5]:
		var f := _fixture()
		f.repo.balance.player_sight_km = 100
		f.state.foes[f.enemy].facing_deg = raw
		for source: GameState in [f.state, _json(f.state)]:
			var before := BodyMotion._hash(source.to_dict())
			var result := BodyBattleMotion.plan_candidate(f.repo, source, BodyBattleMotion._boundary(source))
			assert_eq(result.status, "error", str(raw))
			assert_eq(BodyMotion._hash(source.to_dict()), before)

func test_pursuit_total_uses_json_range_and_rejects_actual_credit_overflow() -> void:
	var f := _pursuit()
	var record: Dictionary = f.state.unit_tasks[f.code].orders.pursue
	record.pursuit.route_m = BodyMotion.LOCAL_LIMIT + 1
	record.request.max_route_m = BodyMotion.LOCAL_LIMIT + 251
	var collected := BodyBattleMotion.collect_candidate(f.repo, f.state, BodyBattleMotion._boundary(f.state))
	assert_eq(collected.status, "complete", "saved lifetime route credit is not a local sweep coordinate")
	if not collected.units.is_empty(): assert_eq(collected.units[0].budget_m, 250)
	record.pursuit.route_m = BodyMotion.JSON_INTEGER_MAX - 1
	record.request.max_route_m = 0
	assert_eq(BattleTaskSystem._flank_candidate_error(f.state), "", "the near-limit source itself is valid")
	var before := BodyMotion._hash(f.state.to_dict())
	var planned := BodyBattleMotion.plan_candidate(f.repo, f.state, BodyBattleMotion._boundary(f.state))
	assert_eq(planned.status, "error", "actual committed credit must remain in the exact JSON range")
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)

func test_bounded_prior_pursuit_does_not_stop_actual_withdrawal() -> void:
	for json_roundtrip: bool in [false, true]:
		var f: Dictionary = _pursuit()
		var code: String = f.code
		f.state.unit_tasks[code].orders.pursue.status = "bounded"
		f.state.regiments[code].disengaging = 1
		f.state.day_resolution.march_entries[code].disengaging = 1
		if json_roundtrip: f.state = GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())), false)
		var before := BodyMotion._hash(f.state.to_dict())
		var boundary := BodyBattleMotion._boundary(f.state)
		var p := BodyBattleMotion.plan_candidate(f.repo, f.state, boundary)
		assert_eq(p.status, "complete", p.reason)
		if p.plan.is_empty(): continue
		var result := BodyBattleMotion.commit_candidate(f.repo, f.state, p.plan, boundary)
		assert_eq(result.status, "complete", result.reason)
		assert_eq(BodyMotion._hash(f.state.to_dict()), before)
		if result.candidate == null: continue
		assert_gt(p.plan.motion.moves[0].used_m, 0, "actual nonbattle withdrawal must not be stopped by its prior bounded pursuit")
		assert_eq(BattleTaskSystem.current(result.candidate, code).pursuit.route_m, 90)
		assert_eq(BattleTaskSystem.current(result.candidate, code).status, "bounded")
		var offensive := UnitBodies._copy(f.state)
		offensive.regiments[code].disengaging = 0
		offensive.day_resolution.march_entries[code].disengaging = 0
		var held := _move(f, offensive)
		if held.candidate != null:
			assert_eq(held.plan.motion.moves[0].used_m, 0, "ordinary bounded offensive march still holds")
			assert_eq(UnitBodies._entry(held.candidate, code).x_m, 50000)

func _withdrawal_hold(_repo: DataRepository, state: GameState, _battle_id: int, unit: String, _budget: int) -> Dictionary:
	var at: Dictionary = UnitBodies._entry(state, unit)
	return {"status": "complete", "reason": "Explicit unavailable-future-writer hold for protected target only", "error": "", "unit": unit, "path_m": [[at.x_m, at.y_m]]}

func test_protected_withdrawal_cannot_commit_offensive_flank_contact() -> void:
	for json_roundtrip: bool in [false, true]:
		var f: Dictionary = _fixture()
		_put(f, f.enemy, [52831, 60000])
		var record: Dictionary = f.state.unit_tasks[f.code].orders.flank
		record.flank.known.x_m = 52831
		record.flank.known.points_m = [[52831, 60000]]
		record.flank.path_m = [[52000, 60000], [52000, 65000]]
		f.state.foes[f.enemy].battle_retreat = true
		f.state.battles[0].parley = {"agreed": {"safe_withdrawal": {"policy": "protect", "until_day": 0}}, "parties": {"att": [f.code, f.other], "def": [f.enemy]}}
		if json_roundtrip: f.state = GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())), false)
		var barred := BodyBattleContact._barred(f.repo, f.state, f.state.battles[0], f.state.battles[0], "att", f.code, f.enemy)
		assert_false(barred.is_empty(), "fixture target really has protected withdrawal")
		var before := BodyMotion._hash(f.state.to_dict())
		var boundary := BodyBattleMotion._boundary(f.state)
		var p := BodyBattleMotion.plan_candidate(f.repo, f.state, boundary, {"withdrawal": _withdrawal_hold})
		assert_eq(p.status, "complete", p.reason)
		if p.plan.is_empty(): continue
		var result := BodyBattleMotion.commit_candidate(f.repo, f.state, p.plan, boundary, {"withdrawal": _withdrawal_hold})
		assert_eq(result.status, "complete", result.reason)
		assert_eq(BodyMotion._hash(f.state.to_dict()), before)
		if result.candidate == null: continue
		var phase: String = BattleTaskSystem.current(result.candidate, f.code).flank.get("phase", "")
		var query := BodyBattleContact.query_candidate(f.repo, result.candidate, 8, f.code, [f.enemy], BodyBattleMotion._boundary(result.candidate))
		assert_ne(phase, "contact", "protected withdrawal cannot publish lawful offensive flank contact")
		assert_eq(UnitBodies._entry(result.candidate, f.code).x_m, 50000, "protected withdrawal bars offensive approach")
		assert_eq(query.engaged, 0)
		assert_eq(BattleTaskSystem.current(result.candidate, f.code).flank.path_m, record.flank.path_m)

func test_unrelated_party_withdrawal_agreement_does_not_bar_flank() -> void:
	for json_roundtrip: bool in [false, true]:
		var f := _fixture()
		_put(f, f.enemy, [52831, 60000])
		var record: Dictionary = f.state.unit_tasks[f.code].orders.flank
		record.flank.known.x_m = 52831
		record.flank.known.points_m = [[52831, 60000]]
		record.flank.path_m = [[52000, 60000], [52000, 65000]]
		f.state.foes[f.enemy].battle_retreat = true
		f.state.battles[0].parley = {"agreed": {"safe_withdrawal": {"policy": "protect", "until_day": 0}}, "parties": {"att": [f.other], "def": [f.enemy]}}
		if json_roundtrip: f.state = _json(f.state)
		assert_eq(BodyBattleContact._barred(f.repo, f.state, f.state.battles[0], f.state.battles[0], "att", f.code, f.enemy), "")
		var before := BodyMotion._hash(f.state.to_dict())
		var boundary := BodyBattleMotion._boundary(f.state)
		var planned := BodyBattleMotion.plan_candidate(f.repo, f.state, boundary, {"withdrawal": _withdrawal_hold})
		assert_eq(planned.status, "complete", planned.reason)
		if planned.plan.is_empty(): continue
		var result := BodyBattleMotion.commit_candidate(f.repo, f.state, planned.plan, boundary, {"withdrawal": _withdrawal_hold})
		assert_eq(result.status, "complete", result.reason)
		assert_eq(BodyMotion._hash(f.state.to_dict()), before)
		if result.candidate != null:
			assert_eq(UnitBodies._entry(result.candidate, f.code).x_m, 51000)
			assert_eq(BattleTaskSystem.current(result.candidate, f.code).flank.phase, "contact")
