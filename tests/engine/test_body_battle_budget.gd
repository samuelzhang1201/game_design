extends GutTest

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _api() -> GDScript:
	var exists := ResourceLoader.exists("res://scripts/engine/body_battle_motion.gd")
	assert_true(exists, "B-TIME complete paid transaction API")
	return load("res://scripts/engine/body_battle_motion.gd") if exists else null

func _fixture(counts: Array = [1000], daily: int = 25) -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_marches.gd").new()
	var f: Dictionary = helper.call("_loco_fixture", counts)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	var state: GameState = f.state
	var tx := DayResolution.begin(state.day, false, state.absolute_day())
	tx.phase = "FIXED_TACTICAL_SUBSTEPS"
	tx.phase_cursor = 5
	tx.march_entries = {}
	tx.march_budgets = {}
	tx.marching_codes = []
	tx.body_battle = {"version": "1", "abs_day": str(state.absolute_day()), "sequence": "0",
		"next_substep": "0", "substep_count": "10", "stage": "move",
		"battle_ids": [], "battle_index": "0", "processed_units": []}
	for code: String in f.codes:
		tx.march_entries[code] = state.regiments[code].duplicate(true)
		tx.march_budgets[code] = daily
		tx.marching_codes.append(code)
	state.day_resolution = tx
	return f

func _boundary(state: GameState) -> Dictionary:
	var c: Dictionary = state.day_resolution.body_battle
	return {"version": 1, "kind": "battle", "abs_day": c.abs_day,
		"sequence": c.sequence, "substep": c.next_substep, "stage": c.stage}

func _battle(f: Dictionary, action: String = "charge") -> void:
	var state: GameState = f.state
	var code: String = f.code
	state.battles = [{"id": 8, "att": [code], "def": [], "groups": {code: state.regiments[code].body_groups},
		"body_version": 1, "group_size_version": 2, "group_size_men": 100,
		"group_anchor_m": {code: [50000, 50000]}, "group_facing": {code: 0},
		"actions": {"att": {"kind": action, "reason": "Received order"}, "def": {"kind": "hold", "reason": "Hold"}}}]
	state.regiments[code].erase("body_groups")

func _provider(_repo: DataRepository, state: GameState, _battle_id: int, code: String, budget: int) -> Dictionary:
	var entry := ArmySystem._entry_of(state, code)
	return {"status": "complete", "reason": "Explicit pure test contribution", "error": "", "unit": code,
		"path_m": [[entry.x_m, entry.y_m], [entry.x_m + budget, entry.y_m]]}

func test_one_share_and_writer() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture()
	var shares: Array = []
	for i: int in 10:
		f.state.day_resolution.substep_index = i
		f.state.day_resolution.body_battle.next_substep = str(i)
		var collected: Dictionary = api.call("collect_candidate", f.repo, f.state, _boundary(f.state))
		assert_eq(collected.status, "complete", collected.reason)
		if collected.units.is_empty(): return
		shares.append(collected.units[0].budget_m)
	assert_eq(shares, [3, 3, 3, 3, 3, 2, 2, 2, 2, 2])
	_battle(f)
	f.repo.balance.battle_deploy_step_m = 20
	shares.clear()
	for i: int in 10:
		f.state.day_resolution.substep_index = i
		f.state.day_resolution.body_battle.next_substep = str(i)
		var before: Dictionary = f.state.to_dict()
		var collected: Dictionary = api.call("collect_candidate", f.repo, f.state, _boundary(f.state), {"charge": _provider})
		assert_eq(collected.status, "complete", collected.reason)
		assert_true(f.state.to_dict() == before)
		if collected.units.is_empty(): return
		assert_eq(collected.units.size(), 1)
		assert_eq(collected.units[0].writer, "charge", "charge supersedes simultaneous march")
		assert_eq(collected.intents.size(), 10)
		shares.append(collected.units[0].budget_m)
	assert_eq(shares, [2, 2, 2, 2, 2, 2, 2, 2, 2, 2])
	var missing: Dictionary = api.call("collect_candidate", f.repo, f.state, _boundary(f.state))
	assert_eq(missing.status, "error", "unimplemented tactical provider never silently holds")
	assert_eq(missing.intents, [])
	assert_eq(missing.units, [])

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _planned(api: GDScript, f: Dictionary, providers: Dictionary = {}) -> Dictionary:
	var before: Dictionary = f.state.to_dict()
	var result: Dictionary = api.call("plan_candidate", f.repo, f.state, _boundary(f.state), providers)
	assert_true(f.state.to_dict() == before, "planning preserves complete source")
	assert_eq(result.status, "complete", result.reason)
	assert_eq(result.keys().size(), 5)
	return result.plan

func test_atomic_move_json_replay_and_corruption() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([1000], 1000)
	var plan := _planned(api, f)
	if plan.is_empty(): return
	var before: Dictionary = f.state.to_dict()
	var result: Dictionary = api.call("commit_candidate", f.repo, f.state, plan, _boundary(f.state))
	assert_eq(result.status, "complete", result.reason)
	assert_true(f.state.to_dict() == before)
	if result.candidate == null: return
	var candidate: GameState = result.candidate
	assert_eq(candidate.regiments[f.code].x_m, 50100)
	assert_eq(candidate.day_resolution.march_entries[f.code].day_walked_m, 100, "ten bodies grant one maximum path credit")
	assert_eq(candidate.day_resolution.body_battle.stage, "contact")
	assert_eq(candidate.day_resolution.body_battle.sequence, "1")
	assert_eq(candidate.rng.to_dict(), f.state.rng.to_dict())
	assert_eq(candidate.military_cohorts, f.state.military_cohorts)
	for imported: bool in [false, true]:
		var input := UnitBodies._copy(f.state)
		if imported: input.military_migration.import_main_v7 = {}
		else: input.military_migration.erase("import_main_v7")
		var p: Dictionary = api.call("plan_candidate", f.repo, input, _boundary(input)).plan
		var applied: Dictionary = api.call("commit_candidate", f.repo, input, p, _boundary(input))
		assert_eq(applied.status, "complete", applied.reason)
		if applied.candidate == null: continue
		for state: GameState in [applied.candidate, _json(applied.candidate)]:
			assert_eq(UnitBodies.validate_battle_candidate(f.repo, state, _boundary(state)).status, "complete")
			var hash_before := BodyMotion._hash(state.to_dict())
			var retry: Dictionary = api.call("commit_candidate", f.repo, state, JSON.parse_string(JSON.stringify(p)), _boundary(input))
			assert_eq(retry.status, "complete", retry.reason)
			if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), hash_before)
			assert_eq(BodyMotion._hash(state.to_dict()), hash_before)
	for change: String in ["cost", "rng", "stage", "sequence", "queue", "receipt", "result", "inner", "pose", "path", "policy", "terrain"]:
		var state := _json(candidate)
		match change:
			"cost": state.regiments[f.code].supplies -= 1
			"rng": state.rng.randi_range(1, 20)
			"stage": state.day_resolution.body_battle.stage = "move"
			"sequence": state.day_resolution.body_battle.sequence = "2"
			"queue": state.day_resolution.battle_ids = [8]
			"receipt": state.military_migration.body_battle.receipt = "c".repeat(64)
			"result": state.military_migration.body_battle.result = "c".repeat(64)
			"inner": state.military_migration.body_motion.receipt = "c".repeat(64)
			"pose": state.regiments[f.code].body_groups[0].x_m += 1
			"path": state.regiments[f.code].body_groups[0].path_m.append([1, 2])
			"policy": f.repo.balance.battle_deploy_step_m += 1
			"terrain": f.grid.closed[0] = 1
		var input_hash := BodyMotion._hash(state.to_dict())
		var retry: Dictionary = api.call("commit_candidate", f.repo, state, plan, _boundary(f.state))
		assert_eq(retry.status, "error", change)
		assert_null(retry.candidate)
		assert_eq(BodyMotion._hash(state.to_dict()), input_hash, change)
		if change == "policy": f.repo.balance.battle_deploy_step_m -= 1
		if change == "terrain": f.grid.closed[0] = 0

func test_running_ten_bodies_pays_once_and_rejection_rolls_back() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([1000], 1000)
	var helper: GutTest = load("res://tests/engine/test_body_marches.gd").new()
	helper.call("_runner", f, 1000)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	f.state.day_resolution.day = f.state.day
	f.state.day_resolution.absolute_day = f.state.absolute_day()
	f.state.day_resolution.body_battle.abs_day = str(f.state.absolute_day())
	f.state.day_resolution.march_entries[f.code] = f.state.regiments[f.code].duplicate(true)
	var plan := _planned(api, f)
	if plan.is_empty(): return
	var before: Dictionary = f.state.to_dict()
	var applied: Dictionary = api.call("commit_candidate", f.repo, f.state, plan, _boundary(f.state))
	assert_eq(applied.status, "complete", applied.reason)
	assert_true(f.state.to_dict() == before)
	if applied.candidate == null: return
	assert_eq(applied.candidate.regiments[f.code].supplies, 990, "base100, extra100 divided by ten slices =10, once per unit")
	assert_eq(applied.candidate.regiments[f.code].run_supply_rem, 0)
	assert_eq(f.state.regiments[f.code].supplies, 1000)
	var corrupt := plan.duplicate(true)
	corrupt.motion.moves[0].end[0] += 1
	var failed: Dictionary = api.call("commit_candidate", f.repo, f.state, corrupt, _boundary(f.state))
	assert_eq(failed.status, "error")
	assert_null(failed.candidate)
	assert_true(f.state.to_dict() == before, "final plan validation publishes none of staged costs/state/RNG")

func test_provider_mutation_bad_output_and_raw_inputs_are_atomic() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture()
	_battle(f)
	var bad_provider := func(_repo: DataRepository, state: GameState, _id: int, _code: String, _budget: int) -> Dictionary:
		state.rng.randi_range(0, 10)
		return {}
	var before: Dictionary = f.state.to_dict()
	assert_eq(api.call("plan_candidate", f.repo, f.state, _boundary(f.state), {"charge": bad_provider}).status, "error")
	assert_true(f.state.to_dict() == before)
	for value: Variant in [true, 1.5, "3", -1, 9007199254740992]:
		var state := UnitBodies._copy(f.state)
		state.day_resolution.march_budgets[f.code] = value
		var original := BodyMotion._hash(state.to_dict())
		assert_eq(api.call("plan_candidate", f.repo, state, _boundary(state), {"charge": _provider}).status, "error")
		assert_eq(BodyMotion._hash(state.to_dict()), original)

func test_selected_charge_holds_under_law_without_falling_through_to_march() -> void:
	var f := _fixture()
	_battle(f)
	f.state.battles[0].parley = {"agreed": {"tactics": {"policy": "restrained", "until_day": 0}}, "parties": {"att": [f.code], "def": []}}
	var collected := BodyBattleMotion.collect_candidate(f.repo, f.state, _boundary(f.state), {"charge": _provider})
	assert_eq(collected.status, "complete", collected.reason)
	if collected.units.is_empty(): return
	assert_eq(collected.units[0].writer, "charge")
	assert_eq(collected.units[0].budget_m, 0)
	assert_eq(collected.units[0].anchor_path_m, [[50000, 50000]])

func test_battle_owned_move_uses_same_transaction_and_preserves_legacy_entries() -> void:
	var f := _fixture([1000], 1000)
	_battle(f)
	f.repo.balance.battle_deploy_step_m = 200
	var before := BodyMotion._hash(f.state.to_dict())
	var providers := {"charge": _provider}
	var planned := BodyBattleMotion.plan_candidate(f.repo, f.state, _boundary(f.state), providers)
	assert_eq(planned.status, "complete", planned.reason)
	if planned.plan.is_empty(): return
	var applied := BodyBattleMotion.commit_candidate(f.repo, f.state, planned.plan, _boundary(f.state), providers)
	assert_eq(applied.status, "complete", applied.reason)
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	if applied.candidate == null: return
	assert_eq(applied.candidate.battles[0].group_anchor_m[f.code], [50020, 50000])
	assert_eq(applied.candidate.battles[0].groups[f.code][0].x_m, 50020)
	assert_false(applied.candidate.regiments[f.code].has("body_groups"))
	assert_eq(applied.candidate.day_resolution.march_entries, f.state.day_resolution.march_entries, "charge does not also spend the received march")
	assert_eq(BodyBattleMotion.commit_candidate(f.repo, _json(applied.candidate), planned.plan, _boundary(f.state)).status, "complete")
	assert_eq(BodyMotion.plan_locomotion_candidate(f.repo, f.state, planned.plan.motion.cursor.intents, f.state.absolute_day(), 0, _boundary(f.state)).cursor, {}, "ordinary TIME stays closed")
	assert_eq(BodyMotion.commit_locomotion_candidate(f.repo, f.state, planned.plan.motion, _boundary(f.state)).status, "error")
	assert_eq(BodyMotion.commit_battle_locomotion_candidate(f.repo, applied.candidate, planned.plan.motion, _boundary(f.state)).status, "error", "only outer transaction can replay contact endpoint")

func test_paid_running_hold_and_final_physical_rejection_publish_no_partial_cost() -> void:
	var f := _fixture([1000, 100], 1000)
	var helper: GutTest = load("res://tests/engine/test_body_marches.gd").new()
	helper.call("_runner", f, 1000)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	var first: Dictionary = f.state.regiments[f.code]
	var other: Dictionary = f.state.regiments[f.codes[1]]
	var first_piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
	var other_piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.codes[1]])
	var radii: int = f.repo.unit_footprints[first_piece].radius_m + f.repo.unit_footprints[other_piece].radius_m
	# Block the foremost body at exact tangency; no side leg fits this slice.
	other.x_m = first.body_groups.back().x_m + radii
	other.y_m = first.y_m
	other.dest_x_m = other.x_m
	other.dest_y_m = other.y_m
	other.order = ArmySystem.ORDER_GARRISON
	other.body_groups[0].x_m = other.x_m
	other.body_groups[0].y_m = other.y_m
	f.state.day_resolution.day = f.state.day
	f.state.day_resolution.absolute_day = f.state.absolute_day()
	f.state.day_resolution.body_battle.abs_day = str(f.state.absolute_day())
	for code: String in f.codes: f.state.day_resolution.march_entries[code] = f.state.regiments[code].duplicate(true)
	var plan := _planned(_api(), f)
	if plan.is_empty(): return
	var applied := BodyBattleMotion.commit_candidate(f.repo, f.state, plan, _boundary(f.state))
	assert_eq(applied.status, "complete", applied.reason)
	if applied.candidate == null: return
	assert_eq(applied.candidate.regiments[f.code].x_m, 50000, "one blocked body denies shared anchor progress")
	assert_eq(applied.candidate.regiments[f.code].supplies, 990, "run payment precedes reservation, even when waiting")
	assert_eq(BodyBattleMotion.commit_candidate(f.repo, _json(applied.candidate), plan, _boundary(f.state)).candidate.regiments[f.code].supplies, 990)
	var blocked: Dictionary = plan.motion.moves.filter(func(move: Dictionary) -> bool: return move.unit == f.code and move.slot == 9)[0]
	assert_eq(blocked.used_m, 0)
	assert_eq(blocked.ops.size(), 1)
	assert_eq(blocked.ops[0].kind, "hold")
	# An overlapping final row fails the real final public validator after costs exist.
	var invalid := UnitBodies._copy(applied.candidate)
	invalid.regiments[f.code].body_groups[0].x_m = other.x_m
	invalid.regiments[f.code].body_groups[0].y_m = other.y_m
	invalid.military_migration.body_battle.result = UnitBodies._battle_result_hash(f.repo, invalid)
	var before := BodyMotion._hash(f.state.to_dict())
	assert_eq(UnitBodies.validate_battle_candidate(f.repo, invalid, _boundary(invalid)).status, "error")
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	assert_eq(f.state.regiments[f.code].supplies, 1000)

func test_malformed_replay_markers_and_contradictory_tasks_reject_cleanly() -> void:
	var f := _fixture([100], 1000)
	var planned := BodyBattleMotion.plan_candidate(f.repo, f.state, _boundary(f.state))
	assert_eq(planned.status, "complete", planned.reason)
	if planned.plan.is_empty(): return
	var result := BodyBattleMotion.commit_candidate(f.repo, f.state, planned.plan, _boundary(f.state))
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return
	for marker: Variant in [true, null, {}, {"version": "1"}]:
		var state := UnitBodies._copy(result.candidate)
		state.day_resolution.body_battle = marker
		var before := BodyMotion._hash(state.to_dict())
		var retry := BodyBattleMotion.commit_candidate(f.repo, state, planned.plan, _boundary(f.state))
		assert_eq(retry.get("status"), "error", "malformed replay marker returns an error, never a script failure")
		assert_eq(BodyMotion._hash(state.to_dict()), before)
	f.state.unit_tasks[f.code] = {"current_id": "bad", "orders": {"bad": {"status": "received", "request": {"unit": f.code, "id": "bad", "task": "charge"}}}}
	var invalid := BodyBattleMotion.plan_candidate(f.repo, f.state, _boundary(f.state), {"charge": _provider})
	assert_eq(invalid.status, "error", "a task without received battlefield/authority/target/bounds cannot authorize motion")

func test_delivered_task_selects_charge_and_pending_cancel_does_not_replace_it() -> void:
	var f := _fixture()
	_battle(f, "hold")
	var issued := BattleTaskSystem.issue_task(f.repo, f.state, {"id": "bt:charge", "unit": f.code, "battle_id": 8, "task": "charge", "source": "player"})
	assert_eq(issued.status, "pending", str(issued))
	var delivered := BattleTaskSystem.deliver_task(f.repo, f.state, "bt:charge")
	assert_eq(delivered.status, "received", str(delivered))
	var cancelled := BattleTaskSystem.issue_task(f.repo, f.state, {"id": "bt:cancel", "unit": f.code, "battle_id": 8, "task": "cancel", "source": "player"})
	assert_eq(cancelled.status, "pending", str(cancelled))
	var collected := BodyBattleMotion.collect_candidate(f.repo, f.state, _boundary(f.state), {"charge": _provider})
	assert_eq(collected.status, "complete", collected.reason)
	if collected.units.is_empty(): return
	assert_eq(collected.units[0].writer, "charge")
	assert_eq(collected.units[0].budget_m, 3)
	var before := BodyMotion._hash(f.state.to_dict())
	var planned := BodyBattleMotion.plan_candidate(f.repo, f.state, _boundary(f.state), {"charge": _provider})
	assert_eq(planned.status, "complete", planned.reason)
	assert_eq(BodyMotion._hash(f.state.to_dict()), before)
	var corrupt := UnitBodies._copy(f.state)
	corrupt.unit_tasks[f.code].orders["bt:charge"].request.unit = "absent"
	assert_eq(BodyBattleMotion.plan_candidate(f.repo, corrupt, _boundary(corrupt), {"charge": _provider}).status, "error")

func test_bounded_pursuit_does_not_hold_actual_rout() -> void:
	var f := _fixture([1000], 1000)
	var helper: GutTest = load("res://tests/engine/test_body_marches.gd").new()
	helper.call("_runner", f, 1000)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	f.state.day_resolution.day = f.state.day
	f.state.day_resolution.absolute_day = f.state.absolute_day()
	f.state.day_resolution.body_battle.abs_day = str(f.state.absolute_day())
	f.state.day_resolution.march_entries[f.code] = f.state.regiments[f.code].duplicate(true)
	_battle(f, "hold")
	f.repo.balance.battle_deploy_step_m = 1000
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, {"id": "bt:pursue", "unit": f.code,
		"battle_id": 8, "task": "pursue", "max_route_m": 1, "source": "player"}).status, "pending")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "bt:pursue").status, "received")
	assert_true(BattleTaskSystem.credit_pursuit(f.repo, f.state, f.code, 1))
	assert_eq(BattleTaskSystem.current(f.state, f.code).status, "bounded")
	var held := BodyBattleMotion.collect_candidate(f.repo, f.state, _boundary(f.state))
	assert_eq(held.status, "complete", held.reason)
	if held.units.is_empty(): return
	assert_eq(held.units[0].writer, "pursuit_march")
	assert_eq(held.units[0].budget_m, 0, "bounded pursuit itself still waits")
	f.state.battles[0].routed_side = "att"
	assert_has(BattleRules.legal_actions(f.repo, f.state, 8, "att", f.code, ""), "retreat")
	var providers := {"withdrawal": _provider}
	# Bounding halts the old march; also cover a subsequently received withdrawal march.
	var running := UnitBodies._copy(f.state)
	running.regiments[f.code].order = ArmySystem.ORDER_MARCH
	running.regiments[f.code].dest_x_m = 51000
	running.regiments[f.code].route_m = [[51000, 50000]]
	var endpoints := {}
	for source: GameState in [f.state, _json(f.state), running, _json(running)]:
		var order: String = source.regiments[f.code].order
		var before := BodyMotion._hash(source.to_dict())
		var boundary := _boundary(source)
		var collected := BodyBattleMotion.collect_candidate(f.repo, source, boundary, providers)
		assert_eq(collected.status, "complete", collected.reason)
		if collected.units.is_empty(): continue
		assert_eq(collected.units[0].writer, "withdrawal")
		assert_eq(collected.units[0].budget_m, 100, "actual rout supersedes the old pursuit bound")
		assert_eq(collected.units[0].anchor_path_m, [[50000, 50000], [50100, 50000]])
		var planned := BodyBattleMotion.plan_candidate(f.repo, source, boundary, providers)
		assert_eq(planned.status, "complete", planned.reason)
		if planned.plan.is_empty(): continue
		var applied := BodyBattleMotion.commit_candidate(f.repo, source, planned.plan, boundary, providers)
		assert_eq(applied.status, "complete", applied.reason)
		assert_eq(BodyMotion._hash(source.to_dict()), before, "no source or RNG mutation")
		if applied.candidate == null: continue
		assert_eq(applied.candidate.battles[0].group_anchor_m[f.code], [50100, 50000])
		assert_eq(applied.candidate.regiments[f.code].supplies, 990 if order == ArmySystem.ORDER_MARCH else 1000, "only a running withdrawal pays, once per unit")
		assert_eq(BattleTaskSystem.current(applied.candidate, f.code).pursuit.route_m, 1, "withdrawal earns no pursuit credit")
		var result_hash := BodyMotion._hash(applied.candidate.to_dict())
		if not endpoints.has(order): endpoints[order] = result_hash
		else: assert_eq(result_hash, endpoints[order], "JSON source gives the identical complete endpoint")
		for saved: GameState in [applied.candidate, _json(applied.candidate)]:
			var retry := BodyBattleMotion.commit_candidate(f.repo, saved, planned.plan, boundary)
			assert_eq(retry.status, "complete", retry.reason)
			if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), result_hash, "retry pays nothing")
		var corrupt: Dictionary = planned.plan.duplicate(true)
		corrupt.motion.moves[0].end[0] += 1
		var rejected := BodyBattleMotion.commit_candidate(f.repo, source, corrupt, boundary, providers)
		assert_eq(rejected.status, "error")
		assert_null(rejected.candidate)
		assert_eq(BodyMotion._hash(source.to_dict()), before, "rejection publishes no costs or RNG")

func test_empty_task_id_rejects_empty_key_record_and_preserves_cancellation() -> void:
	var f := _fixture([100], 1000)
	for record: Variant in [true, null, {}, {"status": "received"}]:
		var damaged := UnitBodies._copy(f.state)
		damaged.unit_tasks[f.code] = {"current_id": "", "orders": {"": record}}
		for source: GameState in [damaged, _json(damaged)]:
			var before := BodyMotion._hash(source.to_dict())
			var rejected := BodyBattleMotion.plan_candidate(f.repo, source, _boundary(source))
			assert_eq(rejected.status, "error", "empty-id record is corrupt, never an absent task")
			assert_null(rejected.candidate)
			assert_eq(rejected.plan, {})
			assert_eq(BodyMotion._hash(source.to_dict()), before)
	f.state.unit_tasks[f.code] = {"current_id": "", "orders": {}}
	assert_eq(BodyBattleMotion.plan_candidate(f.repo, f.state, _boundary(f.state)).status, "complete")
	f.state.unit_tasks.clear()
	_battle(f, "hold")
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, {"id": "bt:charge", "unit": f.code,
		"battle_id": 8, "task": "charge", "source": "player"}).status, "pending")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "bt:charge").status, "received")
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, {"id": "bt:cancel", "unit": f.code,
		"battle_id": 8, "task": "cancel", "source": "player"}).status, "pending")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "bt:cancel").status, "received")
	assert_eq(f.state.unit_tasks[f.code].current_id, "")
	for source: GameState in [f.state, _json(f.state)]:
		var before := BodyMotion._hash(source.to_dict())
		var collected := BodyBattleMotion.collect_candidate(f.repo, source, _boundary(source), {"deployment": _provider})
		assert_eq(collected.status, "complete", collected.reason)
		if not collected.units.is_empty():
			assert_eq(collected.units[0].writer, "deployment")
			assert_gt(collected.units[0].budget_m, 0)
		assert_eq(BodyBattleMotion.plan_candidate(f.repo, source, _boundary(source), {"deployment": _provider}).status, "complete")
		assert_eq(BodyMotion._hash(source.to_dict()), before)
