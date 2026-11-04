extends GutTest

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _fixture() -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_budget.gd").new()
	var f: Dictionary = helper.call("_fixture", [100], 1000)
	helper.call("_battle", f, "hold")
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	var battle: Dictionary = f.state.battles[0]
	battle.place_x_m = 60000
	battle.place_y_m = 50000
	battle.deployment_axis_deg = 180
	f.repo.balance.battle_deploy_step_m = 1000
	return f

func _boundary(state: GameState) -> Dictionary:
	return BodyBattleMotion._boundary(state)

func test_deployment_provider_and_default_union_are_pure() -> void:
	var f := _fixture()
	var api: GDScript = load("res://scripts/engine/battle_groups.gd")
	assert_true(api.has_method("deployment_intent_candidate"), "candidate deployment provider exists")
	if not api.has_method("deployment_intent_candidate"): return
	var before := BodyMotion._hash(f.state.to_dict())
	var contribution: Dictionary = api.call("deployment_intent_candidate", f.repo, f.state, 8, f.code, 100)
	assert_eq(contribution.status, "complete", contribution.reason)
	assert_eq(contribution.size(), 5)
	assert_eq(contribution.path_m[0], [50000, 50000])
	var collected := BodyBattleMotion.collect_candidate(f.repo, f.state, _boundary(f.state))
	assert_eq(collected.status, "complete", collected.reason)
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)

# Policy certificates here are isolated numerical inputs, never installed-art evidence.
func _field(own_fit: int = 100) -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_contact.gd").new()
	var f: Dictionary = helper.call("_fixture", own_fit)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	f.code = f.unit
	f.codes = [f.unit, f.enemy, f.other]
	var state: GameState = f.state
	var tx := DayResolution.begin(state.day, false, state.absolute_day())
	tx.phase = "FIXED_TACTICAL_SUBSTEPS"
	tx.phase_cursor = 5
	tx.march_entries = {}
	tx.march_budgets = {}
	tx.marching_codes = []
	tx.body_battle = {"version": "1", "abs_day": str(state.absolute_day()), "sequence": "0", "next_substep": "0",
		"substep_count": "10", "stage": "move", "battle_ids": [], "battle_index": "0", "processed_units": []}
	state.day_resolution = tx
	var battle: Dictionary = state.battles[0]
	battle.group_anchor_m = {}
	battle.group_facing = {}
	battle.place_x_m = 70000
	battle.place_y_m = 60000
	battle.deployment_axis_deg = 0
	battle.actions = {"att": {"kind": "hold", "reason": "Hold"}, "def": {"kind": "hold", "reason": "Hold"}}
	for i: int in f.codes.size():
		var code: String = f.codes[i]
		var point: Array = [[40000, 60000], [100000, 60000], [70000, 100000]][i]
		var entry := UnitBodies._entry(state, code)
		entry.x_m = point[0]
		entry.y_m = point[1]
		entry.order = ArmySystem.ORDER_GARRISON
		entry.erase("departure")
		entry.erase("camp_state")
		entry.erase("captured")
		entry.supplies = 100000
		battle.group_anchor_m[code] = point.duplicate()
		battle.group_facing[code] = 0 if i == 0 else 180
		var piece := MapObjects.army_piece(f.repo, state.army_roster[code])
		var radius: int = f.repo.unit_footprints[piece].radius_m
		for row: Dictionary in battle.groups[code]:
			row.x_m = point[0] + int(row.slot) * (2 * radius + 100)
			row.y_m = point[1]
			row.facing_deg = battle.group_facing[code]
			row.path_m = []
		f.repo.unit_footprints[piece].locomotion_certificate = {"digest": "a".repeat(64), "turn_q": 400000,
			"contact_um": 100, "radius_m": radius, "clips": ["PIVOT_LEFT", "PIVOT_RIGHT", "MARCH"], "all_turns": true}
		f.repo.balance["body_locomotion_" + piece + "_turn_q"] = 400000
		f.repo.balance["body_locomotion_" + piece + "_contact_um"] = 100
		tx.march_budgets[code] = 600000
	f.repo.balance.battle_deploy_step_m = 600000
	return f

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func test_occupied_lines_hand_calculation_and_existing_rows_only() -> void:
	var f := _field()
	var before := BodyMotion._hash(f.state.to_dict())
	var targets: Dictionary = BattleGroups._body_deployment(f.repo, f.state, f.state.battles[0]).targets
	# Infantry R927, cavalry R804, configured gap100; actual single-row envelopes.
	assert_eq(targets[f.unit], [70977, 60000])
	assert_eq(targets[f.enemy], [69146, 59146])
	assert_eq(targets[f.other], [69146, 60854])
	var result := BattleGroups.deployment_intent_candidate(f.repo, f.state, 8, f.unit, 100)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(result.path_m, [[40000, 60000], [40100, 60000]])
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	var missing := UnitBodies._copy(f.state)
	missing.battles[0].groups.erase(f.unit)
	var hash_before := BodyMotion._hash(missing.to_dict())
	assert_eq(BattleGroups.deployment_intent_candidate(f.repo, missing, 8, f.unit, 100).status, "error")
	assert_eq(BodyMotion._hash(missing.to_dict()), hash_before, "missing rows are never refreshed")

func test_union_sweep_and_open_gap() -> void:
	var f := _field()
	var original := BodyMotion._hash(f.state.to_dict())
	var result := BodyBattleMotion.plan_candidate(f.repo, f.state, _boundary(f.state))
	assert_eq(result.status, "complete", result.reason)
	if result.plan.is_empty(): return
	var plan: Dictionary = result.plan
	assert_eq(plan.motion.moves.size(), 3)
	_continuous(f, plan.motion)
	for move: Dictionary in plan.motion.moves:
		assert_lte(move.used_m, 60000, "one daily quotient share, never extra deployment distance")
		assert_lte(move.ops.back().t1_q, BodyMotion.LOCOMOTION_Q)
	var permuted := UnitBodies._copy(f.state)
	permuted.battles[0].def.reverse()
	var budgets := {}
	for code: String in [f.other, f.enemy, f.unit]: budgets[code] = permuted.day_resolution.march_budgets[code]
	permuted.day_resolution.march_budgets = budgets
	var second := BodyBattleMotion.plan_candidate(f.repo, permuted, _boundary(permuted))
	assert_eq(second.status, "complete", second.reason)
	if not second.plan.is_empty():
		assert_eq(second.plan.motion.moves, plan.motion.moves)
		assert_eq(second.plan.motion.reasons, plan.motion.reasons)
	assert_eq(BodyMotion._hash(f.state.to_dict()), original)

func test_deployment_commit_direct_json_retry_and_whole_state_rollback() -> void:
	var f := _field()
	f.repo.balance.battle_deploy_step_m = 1000
	var source_hash := BodyMotion._hash(f.state.to_dict())
	var boundary := _boundary(f.state)
	var plan := BodyBattleMotion.plan_candidate(f.repo, f.state, boundary)
	assert_eq(plan.status, "complete", plan.reason)
	if plan.plan.is_empty(): return
	var applied := BodyBattleMotion.commit_candidate(f.repo, f.state, plan.plan, boundary)
	assert_eq(applied.status, "complete", applied.reason)
	assert_eq(BodyMotion._hash(f.state.to_dict()), source_hash)
	if applied.candidate == null: return
	assert_eq(applied.candidate.rng.to_dict(), f.state.rng.to_dict())
	assert_eq(applied.candidate.military_cohorts, f.state.military_cohorts)
	assert_eq(applied.candidate.unit_tasks, f.state.unit_tasks)
	assert_eq(applied.candidate.day_resolution.march_entries, f.state.day_resolution.march_entries)
	for code: String in f.codes:
		assert_eq(UnitBodies._entry(applied.candidate, code).supplies, UnitBodies._entry(f.state, code).supplies)
		assert_eq(UnitBodies._entry(applied.candidate, code).group_next_slot, UnitBodies._entry(f.state, code).group_next_slot)
		var row: Dictionary = applied.candidate.battles[0].groups[code][0]
		var old: Dictionary = f.state.battles[0].groups[code][0]
		for key: String in ["slot", "home_slot", "count", "role"]: assert_eq(row[key], old[key])
	var endpoint := BodyMotion._hash(applied.candidate.to_dict())
	for state: GameState in [applied.candidate, _json(applied.candidate)]:
		var retry := BodyBattleMotion.commit_candidate(f.repo, state, JSON.parse_string(JSON.stringify(plan.plan)), boundary)
		assert_eq(retry.status, "complete", retry.reason)
		if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), endpoint, "zero repeated anchor/preparation/metre or supply credit")
	var loaded := BodyBattleMotion.plan_candidate(f.repo, _json(f.state), boundary)
	assert_eq(loaded.status, "complete", loaded.reason)
	assert_eq(loaded.plan, plan.plan, "JSON input determinism")
	for key: String in ["pose", "path", "anchor", "count", "slot", "policy", "radius", "terrain", "target"]:
		var state := UnitBodies._copy(f.state)
		match key:
			"pose": state.battles[0].groups[f.unit][0].x_m += 1
			"path": state.battles[0].groups[f.unit][0].path_m.append([40001, 60000])
			"anchor": state.battles[0].group_anchor_m[f.unit][0] += 1
			"count": state.battles[0].groups[f.unit][0].count -= 1
			"slot": state.battles[0].groups[f.unit][0].slot += 1
			"policy": f.repo.balance.body_locomotion_infantry_turn_q += 1
			"radius": f.repo.unit_footprints.infantry.radius_m += 1
			"terrain": f.grid.closed[0] = 1
			"target": state.battles[0].place_x_m += 1
		var before := BodyMotion._hash(state.to_dict())
		var failed := BodyBattleMotion.commit_candidate(f.repo, state, plan.plan, boundary)
		assert_eq(failed.status, "error", key)
		assert_null(failed.candidate)
		assert_eq(BodyMotion._hash(state.to_dict()), before)
		if key == "policy": f.repo.balance.body_locomotion_infantry_turn_q -= 1
		if key == "radius": f.repo.unit_footprints.infantry.radius_m -= 1
		if key == "terrain": f.grid.closed[0] = 0

func _at(move: Dictionary, q: int, axis: int) -> float:
	for op: Dictionary in move.ops:
		if q > op.t1_q: continue
		if op.kind != "move" or op.t1_q == op.t0_q: return float(op.a[axis])
		return float(op.a[axis]) + (int(op.b[axis]) - int(op.a[axis])) * float(q - op.t0_q) / (op.t1_q - op.t0_q)
	return float(move.end[axis])

func _continuous(f: Dictionary, motion: Dictionary) -> void:
	for i: int in motion.moves.size():
		var a: Dictionary = motion.moves[i]
		var ar: int = f.repo.unit_footprints[MapObjects.army_piece(f.repo, f.state.army_roster[a.unit])].radius_m
		for j: int in range(i + 1, motion.moves.size()):
			var b: Dictionary = motion.moves[j]
			var br: int = f.repo.unit_footprints[MapObjects.army_piece(f.repo, f.state.army_roster[b.unit])].radius_m
			var knots: Array = [0, BodyMotion.LOCOMOTION_Q]
			for move: Dictionary in [a, b]:
				for op: Dictionary in move.ops:
					knots.append(op.t0_q)
					knots.append(op.t1_q)
			knots.sort()
			for k: int in range(1, knots.size()):
				var t0: int = knots[k - 1]
				var t1: int = knots[k]
				if t0 == t1: continue
				var x := _at(a, t0, 0) - _at(b, t0, 0)
				var y := _at(a, t0, 1) - _at(b, t0, 1)
				var dx := _at(a, t1, 0) - _at(b, t1, 0) - x
				var dy := _at(a, t1, 1) - _at(b, t1, 1) - y
				var squared := dx * dx + dy * dy
				var u := clampf(-(x * dx + y * dy) / squared, 0.0, 1.0) if squared > 0 else 0.0
				assert_gte(pow(x + u * dx, 2) + pow(y + u * dy, 2), float((ar + br) * (ar + br)) - 0.001, "entire relative Q sweep stays clear")

func _put(f: Dictionary, code: String, point: Array) -> void:
	var entry := UnitBodies._entry(f.state, code)
	entry.x_m = point[0]
	entry.y_m = point[1]
	f.state.battles[0].group_anchor_m[code] = point.duplicate()
	f.state.battles[0].groups[code][0].x_m = point[0]
	f.state.battles[0].groups[code][0].y_m = point[1]

func test_actual_radius_open_and_narrow_corridor() -> void:
	for gap: int in [1731, 1730]:
		var f := _field()
		_put(f, f.unit, [50000, 60000])
		_put(f, f.enemy, [52000, 60000 - gap])
		_put(f, f.other, [52000, 60000 + gap])
		for code: String in [f.enemy, f.other]: UnitBodies._entry(f.state, code).captured = true
		f.repo.balance.battle_deploy_step_m = 40000
		var planned := BodyBattleMotion.plan_candidate(f.repo, f.state, _boundary(f.state))
		assert_eq(planned.status, "complete", planned.reason)
		if planned.plan.is_empty(): continue
		_continuous(f, planned.plan.motion)
		var own: Dictionary = planned.plan.motion.moves.filter(func(row: Dictionary) -> bool: return row.unit == f.unit)[0]
		assert_lte(own.used_m, 4000)
		if gap == 1731:
			assert_eq(own.end, [54000, 60000], "exact real-radius corridor passes")
		else:
			assert_lt(int(own.end[0]), 52000, "one metre narrower cannot cross the occupied throat")
			assert_false(planned.plan.motion.reasons.is_empty())
		for move: Dictionary in planned.plan.motion.moves:
			if move.unit != f.unit:
				assert_eq(move.used_m, 0)
				assert_eq(move.ops.size(), 1)
				assert_eq(move.ops[0].kind, "hold", "captured/protected peers retain real occupied discs")

func test_provider_raw_controls_holds_and_terrain_rejection() -> void:
	var f := _field()
	for change: String in ["marker", "place", "axis", "missing", "duplicate", "future", "policy"]:
		var state := UnitBodies._copy(f.state)
		match change:
			"marker": state.day_resolution.body_battle = {}
			"place": state.battles[0].place_x_m = 1.5
			"axis": state.battles[0].deployment_axis_deg = true
			"missing": state.battles[0].groups.erase(f.unit)
			"duplicate": state.battles[0].groups[f.unit].append(state.battles[0].groups[f.unit][0].duplicate(true))
			"future": state.battles[0].body_version = 99
			"policy": f.repo.unit_footprints.infantry.erase("locomotion_certificate")
		var before := BodyMotion._hash(state.to_dict())
		var result := BattleGroups.deployment_intent_candidate(f.repo, state, 8, f.unit, 100)
		assert_eq(result.status, "error", change)
		assert_eq(result.path_m, [])
		assert_eq(BodyMotion._hash(state.to_dict()), before)
	for budget: int in [-1, BodyMotion.LOCAL_LIMIT + 1]:
		assert_eq(BattleGroups.deployment_intent_candidate(f.repo, f.state, 8, f.unit, budget).status, "error")
	f = _field()
	assert_eq(BattleGroups.deployment_intent_candidate(f.repo, f.state, 99, f.unit, 100).status, "error")
	assert_eq(BattleGroups.deployment_intent_candidate(f.repo, f.state, 8, "missing", 100).status, "error")
	for kind: String in ["zero", "captured", "reserve", "packing"]:
		var state := UnitBodies._copy(f.state)
		match kind:
			"captured": UnitBodies._entry(state, f.unit).captured = true
			"reserve": state.battles[0].reserves = {f.unit: true}
			"packing": UnitBodies._entry(state, f.unit).camp_state = {"phase": "packing", "until_day": state.absolute_day() + 1}
		var result := BattleGroups.deployment_intent_candidate(f.repo, state, 8, f.unit, 0 if kind == "zero" else 100)
		assert_eq(result.status, "complete", result.reason)
		assert_eq(result.path_m, [[40000, 60000]], kind)
		assert_false(result.reason.is_empty())
	# Endpoints are dry, but the full measured disc crosses a closed middle cell.
	f.grid.closed[6 * f.grid.cols + 5] = 1
	var held := BattleGroups.deployment_intent_candidate(f.repo, f.state, 8, f.unit, 30000)
	assert_eq(held.status, "complete", held.reason)
	assert_eq(held.path_m, [[40000, 60000]])
	assert_false(held.reason.is_empty())

func test_at_line_melee_closes_to_actual_rows_without_role_or_remote_bonus() -> void:
	var f := _field()
	_put(f, f.unit, [70977, 60000])
	_put(f, f.enemy, [69146, 59146])
	_put(f, f.other, [69146, 60854])
	f.state.battles[0].actions.att = {"kind": "attack", "reason": "Received attack"}
	var result := BattleGroups.deployment_intent_candidate(f.repo, f.state, 8, f.unit, 1000)
	assert_eq(result.status, "complete", result.reason)
	assert_gt(result.path_m.size(), 1, "nominal line cannot leave separated physical rows stranded")
	if result.path_m.size() <= 1: return
	var point: Array = result.path_m.back()
	var reached := false
	for enemy: String in [f.enemy, f.other]:
		var row: Dictionary = f.state.battles[0].groups[enemy][0]
		var pair := BattleGroupGeometry.pair(point, 927, [row.x_m, row.y_m], 804, 100)
		reached = reached or (pair.ok and pair.in_reach and not pair.overlap)
	assert_true(reached, "whole-metre endpoint reaches actual measured surface")

func test_two_opposed_writers_and_stationary_tail_share_entire_q() -> void:
	var f := _field()
	_put(f, f.other, [130000, 130000])
	UnitBodies._entry(f.state, f.other).captured = true
	var result := BodyBattleMotion.plan_candidate(f.repo, f.state, _boundary(f.state))
	assert_eq(result.status, "complete", result.reason)
	if result.plan.is_empty(): return
	_continuous(f, result.plan.motion)
	var stationary: Dictionary = result.plan.motion.moves.filter(func(row: Dictionary) -> bool: return row.unit == f.other)[0]
	assert_eq(stationary.ops.size(), 1)
	assert_eq(stationary.ops[0].t0_q, 0)
	assert_eq(stationary.ops[0].t1_q, BodyMotion.LOCOMOTION_Q)
	assert_eq(stationary.used_m, 0)
	var reverse := UnitBodies._copy(f.state)
	reverse.battles[0].def.reverse()
	var second := BodyBattleMotion.plan_candidate(f.repo, reverse, _boundary(reverse))
	assert_eq(second.status, "complete", second.reason)
	if not second.plan.is_empty():
		assert_eq(second.plan.motion.moves, result.plan.motion.moves)
		assert_eq(second.plan.motion.reasons, result.plan.motion.reasons)

func test_partial_and_empty_rosters_keep_exact_identity_and_counts() -> void:
	for fit: int in [1000, 901, 900, 1, 0]:
		var f := _field(fit)
		f.repo.balance.battle_deploy_step_m = 1000
		var before := BodyMotion._hash(f.state.to_dict())
		var result := BodyBattleMotion.plan_candidate(f.repo, f.state, _boundary(f.state))
		assert_eq(result.status, "complete", result.reason)
		if result.plan.is_empty(): continue
		var own_moves: Array = result.plan.motion.moves.filter(func(row: Dictionary) -> bool: return row.unit == f.unit)
		assert_eq(own_moves.size(), BattleGroups.counts(fit, 100).size())
		var applied := BodyBattleMotion.commit_candidate(f.repo, f.state, result.plan, _boundary(f.state))
		assert_eq(applied.status, "complete", applied.reason)
		assert_eq(BodyMotion._hash(f.state.to_dict()), before)
		if applied.candidate == null: continue
		var count := 0
		var rows: Array = applied.candidate.battles[0].groups[f.unit]
		for i: int in rows.size():
			count += int(rows[i].count)
			for key: String in ["slot", "home_slot", "count", "role"]:
				assert_eq(rows[i][key], f.state.battles[0].groups[f.unit][i][key])
		assert_eq(count, fit)
		assert_eq(UnitBodies._entry(applied.candidate, f.unit).group_next_slot, 20)
		assert_eq(applied.candidate.military_cohorts, f.state.military_cohorts)

func test_large_whole_world_points_are_not_narrowed_and_null_axis_rejects() -> void:
	var f := _field()
	var offset: int = 1 << 29
	f.grid.cell_m = 100000000
	for code: String in f.codes:
		var entry := UnitBodies._entry(f.state, code)
		_put(f, code, [int(entry.x_m) + offset, int(entry.y_m) + offset])
	f.state.battles[0].place_x_m += offset
	f.state.battles[0].place_y_m += offset
	var before := BodyMotion._hash(f.state.to_dict())
	var result := BattleGroups.deployment_intent_candidate(f.repo, f.state, 8, f.unit, 100)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(result.path_m, [[offset + 40000, offset + 60000], [offset + 40100, offset + 60000]])
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	f.state.battles[0].deployment_axis_deg = null
	assert_eq(BattleGroups.deployment_intent_candidate(f.repo, f.state, 8, f.unit, 100).status, "error", "present null is not an absent control")

func test_legacy_party_inference_is_private_and_never_mutates_provider_source() -> void:
	var f := _field()
	_put(f, f.unit, [70977, 60000])
	_put(f, f.enemy, [69146, 59146])
	_put(f, f.other, [69146, 60854])
	f.state.battles[0].parley = {"agreed": {"tactics": {"policy": "restrained", "until_day": 0}}}
	for source: GameState in [f.state, _json(f.state)]:
		var before := BodyMotion._hash(source.to_dict())
		var result := BattleGroups.deployment_intent_candidate(f.repo, source, 8, f.unit, 1000)
		assert_eq(result.status, "complete", result.reason)
		assert_eq(BodyMotion._hash(source.to_dict()), before, "law queries may infer parties only in a private candidate")
		var collected := BodyBattleMotion.collect_candidate(f.repo, source, _boundary(source))
		assert_eq(collected.status, "complete", collected.reason)
		assert_eq(BodyMotion._hash(source.to_dict()), before)
