extends GutTest

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

# Keep the accepted measured circles; only the locomotion certificates are numerical fixtures.
func _fixture(runup: int = 300) -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_deploy.gd").new()
	var f: Dictionary = helper.call("_field")
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	f.code = f.enemy
	f.target = f.unit
	_put(f.state, f.code, [50000, 60000])
	_put(f.state, f.target, [51831 + runup, 60000])
	_put(f.state, f.other, [100000, 100000])
	UnitBodies._entry(f.state, f.other).captured = true
	f.state.day_resolution.march_budgets[f.target] = 0
	f.state.battles[0].group_facing[f.code] = 0
	f.state.battles[0].groups[f.code][0].facing_deg = 0
	f.state.unit_tasks = {f.code: {"current_id": "charge", "received_sequence": 1, "orders": {"charge": {
		"sequence": 1, "status": "received", "request": {"id": "charge", "unit": f.code, "battle_id": 8,
		"task": "charge", "formation": "", "target_unit": f.target, "source": "general", "issuer": "", "max_route_m": 0, "region": ""}}}}}
	f.repo.balance.battle_deploy_step_m = 10000
	return f

func _put(state: GameState, code: String, point: Array) -> void:
	var entry := UnitBodies._entry(state, code)
	entry.x_m = point[0]
	entry.y_m = point[1]
	state.battles[0].group_anchor_m[code] = point.duplicate()
	for row: Dictionary in state.battles[0].groups[code]:
		row.x_m = point[0]
		row.y_m = point[1]

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _move(f: Dictionary, source: GameState = null) -> Dictionary:
	if source == null: source = f.state
	var boundary := BodyBattleMotion._boundary(source)
	var before := BodyMotion._hash(source.to_dict())
	var planned := BodyBattleMotion.plan_candidate(f.repo, source, boundary, f.get("providers", {}))
	assert_eq(planned.status, "complete", planned.reason)
	if planned.plan.is_empty(): return planned
	var result := BodyBattleMotion.commit_candidate(f.repo, source, planned.plan, boundary, f.get("providers", {}))
	assert_eq(result.status, "complete", result.reason)
	assert_eq(BodyMotion._hash(source.to_dict()), before, "all candidate work leaves its source untouched")
	return result

func test_runup_replay_and_regroup() -> void:
	var api: GDScript = load("res://scripts/engine/battle_charge.gd")
	assert_true(api.has_method("intent_candidate"), "received charge needs its pure candidate provider")
	if not api.has_method("intent_candidate"): return
	for distance: int in [299, 300]:
		var f := _fixture(distance)
		assert_eq(int(f.repo.bal("battle_charge_runup_m")), 300)
		var before := BodyMotion._hash(f.state.to_dict())
		var contribution: Dictionary = api.call("intent_candidate", f.repo, f.state, 8, f.code, 1000)
		assert_eq(contribution.status, "complete", contribution.reason)
		assert_eq(contribution.size(), 5)
		assert_eq(contribution.path_m, [[50000, 60000], [50000 + distance, 60000]])
		assert_eq(BodyMotion._hash(f.state.to_dict()), before)
		var result := _move(f)
		if result.candidate == null: continue
		var charge: Dictionary = UnitBodies._entry(result.candidate, f.code).charge
		assert_eq(charge.runup_m, distance)
		assert_eq(charge.phase, "impact" if distance == 300 else "disengage")
		assert_eq(result.candidate.rng.to_dict(), f.state.rng.to_dict())
		assert_eq(result.candidate.military_cohorts, f.state.military_cohorts)
		assert_eq(result.candidate.unit_tasks, f.state.unit_tasks)
		var endpoint := BodyMotion._hash(result.candidate.to_dict())
		for source: GameState in [result.candidate, _json(result.candidate)]:
			var retry := BodyBattleMotion.commit_candidate(f.repo, source, JSON.parse_string(JSON.stringify(result.plan)), BodyBattleMotion._boundary(f.state))
			assert_eq(retry.status, "complete", retry.reason)
			if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), endpoint, "full receipt retries never make 300 become 600")
		var loaded := _move(f, _json(f.state))
		if loaded.candidate != null: assert_eq(BodyMotion._hash(loaded.candidate.to_dict()), endpoint)

func _charge(f: Dictionary, phase: String = "approach", credit: int = 200) -> Dictionary:
	return {"phase": phase, "target": f.target, "origin_x_m": 50000 - credit, "origin_y_m": 60000,
		"x_m": 50000, "y_m": 60000, "heading_deg": 0, "runup_m": credit,
		"impact_day": f.state.absolute_day() if phase == "impact" else -1}

func test_target_heading_external_displacement_and_hold_discard_unfinished_credit() -> void:
	for change: String in ["target", "heading", "external", "hold"]:
		var f := _fixture(100)
		var charge := _charge(f)
		match change:
			"target": charge.target = f.other
			"heading": charge.heading_deg = 90
			"external": charge.x_m -= 1
			"hold": f.state.unit_tasks = {}
		UnitBodies._entry(f.state, f.code).charge = charge
		var result := _move(f)
		if result.candidate == null: continue
		var actual: Dictionary = UnitBodies._entry(result.candidate, f.code).get("charge", {})
		if change == "hold": assert_true(actual.is_empty())
		else:
			assert_eq(actual.runup_m, 100, change)
			assert_eq(actual.phase, "disengage", "new 100m cannot borrow old 200m")

func test_saved_impact_is_not_consumed_by_movement_and_requires_real_regroup_day() -> void:
	var f := _fixture(0)
	UnitBodies._entry(f.state, f.code).charge = _charge(f, "impact", 300)
	var result := _move(f)
	if result.candidate == null: return
	assert_eq(UnitBodies._entry(result.candidate, f.code).charge.phase, "impact", "no personnel settlement occurred")
	assert_eq(UnitBodies._entry(result.candidate, f.code).charge.runup_m, 300)
	# Model the already successful ordinary consume operation, not a candidate damage writer.
	BattleCharge.consume(f.state, [f.code], f.state.absolute_day())
	var away := _move(f)
	if away.candidate == null: return
	assert_eq(UnitBodies._entry(away.candidate, f.code).x_m, 49700)
	var regroup: Dictionary = UnitBodies._entry(away.candidate, f.code).charge
	assert_eq(regroup.phase, "regroup")
	assert_eq(regroup.regroup_day, f.state.absolute_day())
	for elapsed: int in [0, 1, 2]:
		var fresh := _fixture(300)
		fresh.state.day += elapsed
		_put(fresh.state, fresh.code, [49700, 60000])
		_put(fresh.state, fresh.target, [51831, 60000])
		UnitBodies._entry(fresh.state, fresh.code).charge = regroup.duplicate(true)
		fresh.state.day_resolution.day = fresh.state.day
		fresh.state.day_resolution.absolute_day = fresh.state.absolute_day()
		fresh.state.day_resolution.body_battle.abs_day = str(fresh.state.absolute_day())
		var next := _move(fresh)
		if next.candidate != null:
			assert_eq(UnitBodies._entry(next.candidate, fresh.code).x_m, 50000 if elapsed == 2 else 49700, "one entire saved regroup day")
			assert_eq(UnitBodies._entry(next.candidate, fresh.code).charge.phase, "impact" if elapsed == 2 else "regroup")

func test_blocked_ground_and_occupied_charge_cannot_create_credit_or_cross_enemy() -> void:
	var f := _fixture(20000)
	f.grid.closed[6 * f.grid.cols + 5] = 1
	# Move off the closed cell while keeping the swept route across it.
	_put(f.state, f.code, [48000, 60000])
	var before := BodyMotion._hash(f.state.to_dict())
	var result := BattleCharge.intent_candidate(f.repo, f.state, 8, f.code, 10000)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(result.path_m, [[48000, 60000]])
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	f = _fixture(300)
	_put(f.state, f.other, [50100, 61605])
	# Captured peer remains a physical obstacle although it is no lawful target.
	var applied := _move(f)
	if applied.candidate != null:
		var entry := UnitBodies._entry(applied.candidate, f.code)
		assert_lte(entry.x_m, 50192, "two actual cavalry radii require 1608m clearance")
		assert_ne(entry.get("charge", {}).get("phase"), "impact")
		assert_lte(entry.get("charge", {}).get("runup_m", 0), 192)

func test_raw_charge_controls_reject_atomically_direct_and_json() -> void:
	for field: String in ["phase", "target", "runup_m", "heading_deg", "impact_day", "regroup_day", "future"]:
		for raw: Variant in [true, 1.5, null]:
			var f := _fixture()
			var charge := _charge(f)
			charge[field] = raw
			UnitBodies._entry(f.state, f.code).charge = charge
			for state: GameState in [f.state, _json(f.state)]:
				var before := BodyMotion._hash(state.to_dict())
				var result := BodyBattleMotion.plan_candidate(f.repo, state, BodyBattleMotion._boundary(state))
				assert_eq(result.status, "error", field + "=" + str(raw))
				assert_null(result.candidate)
				assert_eq(BodyMotion._hash(state.to_dict()), before)

func test_three_actual_slices_earn_300_once_through_json_and_closure() -> void:
	var f := _fixture(300)
	f.repo.balance.battle_deploy_step_m = 1000
	var helper: GutTest = load("res://tests/engine/test_body_battle_closure.gd").new()
	for slice: int in 3:
		var applied := _move(f, _json(f.state))
		if applied.candidate == null: break
		var charge: Dictionary = UnitBodies._entry(applied.candidate, f.code).charge
		assert_eq(charge.runup_m, (slice + 1) * 100)
		assert_eq(charge.phase, "impact" if slice == 2 else "approach")
		if slice == 2: break
		var closed := BodyMotion.close_battle_locomotion_candidate(f.repo, applied.candidate, BodyBattleMotion._boundary(applied.candidate))
		assert_eq(closed.status, "complete", closed.reason)
		if closed.candidate == null: break
		f.state = closed.candidate
		helper.call("_successor", f.repo, f.state)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()

func test_300_without_contact_and_sidesteps_and_enemy_movement_do_not_impact() -> void:
	var f := _fixture(301)
	f.repo.balance.battle_deploy_step_m = 3000
	var result := _move(f)
	if result.candidate != null:
		assert_eq(UnitBodies._entry(result.candidate, f.code).charge.runup_m, 300)
		assert_eq(UnitBodies._entry(result.candidate, f.code).charge.phase, "approach", "300m with one metre still open has no impact")
	f = _fixture(300)
	UnitBodies._entry(f.state, f.code).charge = _charge(f)
	f.providers = {"charge": func(_repo: DataRepository, source: GameState, _id: int, code: String, _budget: int) -> Dictionary:
		var entry := UnitBodies._entry(source, code)
		var here: Array = [entry.x_m, entry.y_m]
		return {"status": "complete", "reason": "Explicit test side leg", "error": "", "unit": code,
			"path_m": [here, [here[0], here[1] + 50], [here[0] + 300, here[1] + 50]]}}
	result = _move(f)
	if result.candidate != null:
		assert_eq(UnitBodies._entry(result.candidate, f.code).charge.runup_m, 0, "side legs and pivots cannot bank forward momentum")
		assert_ne(UnitBodies._entry(result.candidate, f.code).charge.phase, "impact")
	f = _fixture(300)
	f.state.day_resolution.march_budgets[f.code] = 0
	f.state.day_resolution.march_budgets[f.target] = 10000
	UnitBodies._entry(f.state, f.code).charge = _charge(f, "approach", 299)
	f.providers = {"deployment": func(_repo: DataRepository, source: GameState, _id: int, code: String, _budget: int) -> Dictionary:
		var entry := UnitBodies._entry(source, code)
		var here: Array = [entry.x_m, entry.y_m]
		return {"status": "complete", "reason": "Explicit test enemy movement", "error": "", "unit": code,
			"path_m": [here, [here[0] - 300, here[1]]]}}
	result = _move(f)
	if result.candidate != null:
		assert_eq(UnitBodies._entry(result.candidate, f.code).charge.runup_m, 299)
		assert_ne(UnitBodies._entry(result.candidate, f.code).charge.phase, "impact", "enemy closure is not the rider's movement")

func test_charge_provider_holds_and_forged_replays_reject_without_side_effects() -> void:
	for reason: String in ["zero", "captured", "reserve", "packing", "law", "infantry", "supply", "authorization"]:
		var f := _fixture()
		match reason:
			"authorization": f.state.unit_tasks[f.code].orders.charge.request.source = "player"
			"captured": UnitBodies._entry(f.state, f.code).captured = true
			"reserve": f.state.battles[0].reserves = {f.code: true}
			"packing": UnitBodies._entry(f.state, f.code).camp_state = {"phase": "packing", "until_day": f.state.absolute_day() + 1}
			"law": f.state.battles[0].parley = {"agreed": {"tactics": {"policy": "restrained", "until_day": 0}}}
			"infantry":
				f.state.army_roster[f.code].cavalry = "0"
				f.state.army_roster[f.code].infantry = "100"
			"supply":
				f.state.day = 30
				f.state.day_resolution.day = 30
				f.state.day_resolution.absolute_day = f.state.absolute_day()
				f.state.day_resolution.body_battle.abs_day = str(f.state.absolute_day())
				UnitBodies._entry(f.state, f.code).supplies = 0
		var before := BodyMotion._hash(f.state.to_dict())
		var contribution := BattleCharge.intent_candidate(f.repo, f.state, 8, f.code, 0 if reason == "zero" else 1000)
		assert_eq(contribution.status, "complete", contribution.reason)
		assert_eq(contribution.path_m, [[50000, 60000]], reason)
		assert_false(contribution.reason.is_empty())
		assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	var f := _fixture()
	var moved := _move(f)
	if moved.candidate == null: return
	for change: String in ["runup", "phase", "receipt", "sequence", "rng"]:
		var state := _json(moved.candidate)
		match change:
			"runup": UnitBodies._entry(state, f.code).charge.runup_m += 1
			"phase": UnitBodies._entry(state, f.code).charge.phase = "approach"
			"receipt": state.military_migration.body_battle.receipt = "a".repeat(64)
			"sequence": state.day_resolution.body_battle.sequence = "2"
			"rng": state.rng.randi_range(0, 1000)
		var before := BodyMotion._hash(state.to_dict())
		var retry := BodyBattleMotion.commit_candidate(f.repo, state, moved.plan, BodyBattleMotion._boundary(f.state))
		assert_eq(retry.status, "error", change)
		assert_null(retry.candidate)
		assert_eq(BodyMotion._hash(state.to_dict()), before)

func test_pivoting_breaks_continuous_credit_even_when_endpoint_reaches_contact() -> void:
	var f := _fixture(100)
	UnitBodies._entry(f.state, f.code).charge = _charge(f)
	f.state.battles[0].groups[f.code][0].facing_deg = 90
	f.state.battles[0].group_facing[f.code] = 90
	var moved := _move(f)
	if moved.candidate != null:
		assert_eq(UnitBodies._entry(moved.candidate, f.code).charge.runup_m, 0, "a timed pivot interrupts the old continuous approach")
		assert_ne(UnitBodies._entry(moved.candidate, f.code).charge.phase, "impact")

func test_fractional_diagonal_metres_cannot_round_a_short_approach_up_to_300() -> void:
	var f := _fixture()
	_put(f.state, f.target, [51277, 61705])
	f.state.battles[0].groups[f.code][0].facing_deg = 53
	f.state.battles[0].group_facing[f.code] = 53
	f.providers = {"charge": func(_repo: DataRepository, source: GameState, _id: int, code: String, _budget: int) -> Dictionary:
		var entry := UnitBodies._entry(source, code)
		return {"status": "complete", "reason": "Explicit whole-metre diagonal", "error": "", "unit": code,
			"path_m": [[entry.x_m, entry.y_m], [entry.x_m + 179, entry.y_m + 240]]}}
	var moved := _move(f)
	if moved.candidate != null:
		# 179² + 240² = 89641: 299²=89401 <89641 <300²=90000.
		assert_eq(UnitBodies._entry(moved.candidate, f.code).charge.runup_m, 299)
		assert_ne(UnitBodies._entry(moved.candidate, f.code).charge.phase, "impact")

func test_invalid_provider_inputs_and_import_provenance_remain_atomic() -> void:
	var f := _fixture()
	for budget: int in [-1, BodyMotion.LOCAL_LIMIT + 1]:
		assert_eq(BattleCharge.intent_candidate(f.repo, f.state, 8, f.code, budget).status, "error")
	assert_eq(BattleCharge.intent_candidate(f.repo, f.state, 99, f.code, 1000).status, "error")
	assert_eq(BattleCharge.intent_candidate(f.repo, f.state, 8, "missing", 1000).status, "error")
	for imported: bool in [false, true]:
		var state := UnitBodies._copy(f.state)
		if imported: state.military_migration.import_main_v7 = {}
		else: state.military_migration.erase("import_main_v7")
		var direct := _move(f, state)
		var loaded := _move(f, _json(state))
		if direct.candidate != null and loaded.candidate != null:
			assert_eq(BodyMotion._hash(direct.candidate.to_dict()), BodyMotion._hash(loaded.candidate.to_dict()))

func test_target_opening_gap_still_requires_own_disengagement_then_regroup() -> void:
	var f := _fixture(600)
	UnitBodies._entry(f.state, f.code).charge = _charge(f, "disengage", 300)
	var moved := _move(f)
	if moved.candidate != null:
		assert_eq(UnitBodies._entry(moved.candidate, f.code).x_m, 49700, "enemy movement alone cannot regroup the rider; its bounded away route must still move")
		assert_eq(UnitBodies._entry(moved.candidate, f.code).charge.phase, "regroup")
		assert_eq(UnitBodies._entry(moved.candidate, f.code).charge.get("regroup_day", -1), f.state.absolute_day())

func test_full_charge_commit_keeps_legacy_party_inference_off_source() -> void:
	var f := _fixture()
	f.state.battles[0].parley = {"agreed": {"tactics": {"policy": "restrained", "until_day": 0}}}
	UnitBodies._entry(f.state, f.code).charge = _charge(f)
	var original := BodyMotion._hash(f.state.to_dict())
	for source: GameState in [f.state, _json(f.state)]:
		var moved := _move(f, source)
		assert_eq(BodyMotion._hash(source.to_dict()), original, "law queries infer parties only on private staging")
		if moved.candidate != null: assert_true(UnitBodies._entry(moved.candidate, f.code).get("charge", {}).is_empty(), "barred charge discards only the candidate's unfinished credit")

func test_charge_preserves_partial_multiple_and_empty_body_rosters() -> void:
	var personnel: GDScript = load("res://tests/engine/personnel_helpers.gd")
	for fit: int in [901, 101, 1, 0]:
		var f := _fixture()
		assert_false(personnel.replace(f.repo, f.state, f.code, fit).has("error"))
		var rows: Array = []
		var remaining := fit
		while remaining > 0:
			var slot := rows.size()
			rows.append({"slot": slot, "home_slot": slot, "count": mini(100, remaining), "role": "reserve",
				"x_m": 50000, "y_m": 60000 + slot * 1808, "facing_deg": 0, "path_m": []})
			remaining -= mini(100, remaining)
		f.state.battles[0].groups[f.code] = rows
		var moved := _move(f)
		if moved.candidate == null: continue
		var actual: Array = moved.candidate.battles[0].groups[f.code]
		assert_eq(actual.size(), rows.size())
		for i: int in rows.size():
			for key: String in ["slot", "home_slot", "count", "role"]: assert_eq(actual[i][key], rows[i][key])
		assert_eq(UnitBodies._entry(moved.candidate, f.code).group_next_slot, 20)
		assert_eq(moved.candidate.military_cohorts, f.state.military_cohorts)
		if fit > 0:
			assert_eq(UnitBodies._entry(moved.candidate, f.code).charge.runup_m, 300)
			assert_eq(UnitBodies._entry(moved.candidate, f.code).charge.phase, "impact")
		else: assert_true(UnitBodies._entry(moved.candidate, f.code).get("charge", {}).is_empty())
