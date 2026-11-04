extends GutTest

const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _api() -> GDScript:
	var api: GDScript = load("res://scripts/engine/body_motion.gd")
	assert_true(api.has_method("close_battle_locomotion_candidate"), "explicit verified Q closure")
	return api if api.has_method("close_battle_locomotion_candidate") else null

func _fixture(counts: Array = [200], daily: int = 1000) -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_budget.gd").new()
	var f: Dictionary = helper.call("_fixture", counts, daily)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	return f

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func _move(f: Dictionary) -> Dictionary:
	var boundary := BodyBattleMotion._boundary(f.state)
	var planned := BodyBattleMotion.plan_candidate(f.repo, f.state, boundary, f.get("providers", {}))
	assert_eq(planned.status, "complete", planned.reason)
	if planned.plan.is_empty(): return {}
	var result := BodyBattleMotion.commit_candidate(f.repo, f.state, planned.plan, boundary, f.get("providers", {}))
	assert_eq(result.status, "complete", result.reason)
	if result.candidate == null: return {}
	return {"state": result.candidate, "plan": planned.plan, "boundary": boundary}

# Simulate the separately owned enclosing transaction; closure itself must not seal it.
func _seal(repo: DataRepository, state: GameState) -> void:
	var outer: Dictionary = state.military_migration.body_battle
	outer.sequence = state.day_resolution.body_battle.sequence
	state.day_resolution.body_battle.sequence = str(int(outer.sequence) + 1)
	outer.receipt = BodyMotion._hash(["test enclosing transaction", state.day_resolution.body_battle])
	outer.result = UnitBodies._battle_result_hash(repo, state)

func _successor(repo: DataRepository, state: GameState) -> void:
	state.day_resolution.substep_index += 1
	state.day_resolution.battle_step = ""
	state.day_resolution.battle_ids = []
	state.day_resolution.body_battle.battle_ids = []
	state.day_resolution.body_battle.next_substep = str(state.day_resolution.substep_index)
	state.day_resolution.body_battle.stage = "move"
	_seal(repo, state)

func _close(api: GDScript, repo: DataRepository, state: GameState) -> Dictionary:
	var before := BodyMotion._hash(state.to_dict())
	var result: Dictionary = api.call("close_battle_locomotion_candidate", repo, state, BodyBattleMotion._boundary(state))
	assert_eq(result.keys().size(), 3)
	assert_eq(BodyMotion._hash(state.to_dict()), before, "closure never mutates its source")
	return result

func test_move_contact_retry_close_successor() -> void:
	var api := _api()
	if api == null: return
	for imported: bool in [false, true]:
		var f := _fixture()
		if imported: f.state.military_migration.import_main_v7 = {}
		else: f.state.military_migration.erase("import_main_v7")
		var moved := _move(f)
		if moved.is_empty(): return
		var next_plans: Array = []
		for state: GameState in [moved.state, _json(moved.state)]:
			var retry := BodyBattleMotion.commit_candidate(f.repo, state, moved.plan, moved.boundary)
			assert_eq(retry.status, "complete", retry.reason)
			if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), BodyMotion._hash(state.to_dict()))
			var closed := _close(api, f.repo, state)
			assert_eq(closed.status, "complete", closed.reason)
			if closed.candidate == null: return
			var candidate: GameState = closed.candidate
			var expected: Dictionary = state.military_migration.body_motion.duplicate(true)
			expected.erase("plan")
			assert_eq(candidate.military_migration.body_battle.closed_motion, expected)
			assert_eq(expected.priority, [{"unit": f.code, "slot": "0"}, {"unit": f.code, "slot": "1"}])
			assert_false(candidate.military_migration.has("body_motion"))
			var unchanged := candidate.to_dict()
			unchanged.military_migration = state.to_dict().military_migration
			assert_eq(BodyMotion._hash(unchanged), BodyMotion._hash(state.to_dict()), "only receipt retirement changes; all poses/costs/RNG/stage exact")
			assert_ne(UnitBodies._battle_result_hash(f.repo, candidate), candidate.military_migration.body_battle.result, "private closure cannot publish an enclosing receipt")
			assert_eq(UnitBodies.validate_battle_candidate(f.repo, candidate, BodyBattleMotion._boundary(candidate)).status, "error")
			_seal(f.repo, candidate)
			assert_eq(UnitBodies.validate_battle_candidate(f.repo, candidate, BodyBattleMotion._boundary(candidate)).status, "complete")
			_successor(f.repo, candidate)
			var next := BodyBattleMotion.plan_candidate(f.repo, _json(candidate), BodyBattleMotion._boundary(candidate))
			assert_eq(next.status, "complete", next.reason)
			if next.plan.is_empty(): return
			assert_eq(next.plan.motion.cursor.priority, [{"unit": f.code, "slot": 0}, {"unit": f.code, "slot": 1}])
			assert_eq(next.plan.motion.moves[0].used_m, 100)
			assert_eq(next.plan.motion.moves[0].budget_m, 100)
			next_plans.append(next.plan)
		assert_eq(next_plans[0], next_plans[1], "JSON before/after closure gives identical next budget/order/basis")

func test_close_then_loss_does_not_replay() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([100, 200])
	var newcomer: String = f.codes[0]
	f.code = f.codes[1]
	f.state.day_resolution.march_entries[newcomer].order = ArmySystem.ORDER_GARRISON
	var helper: GutTest = load("res://tests/engine/test_body_battle_budget.gd").new()
	helper.call("_battle", f, "hold")
	helper.free()
	f.state.battles[0].group_anchor_m[f.code] = [50000, 80000]
	f.repo.balance.battle_deploy_step_m = 1000
	f.providers = {"deployment": func(_repo: DataRepository, source: GameState, _id: int, code: String, budget: int) -> Dictionary:
		var entry := ArmySystem._entry_of(source, code)
		return {"status": "complete", "reason": "Test deployment", "error": "", "unit": code,
			"path_m": [[entry.x_m, entry.y_m], [entry.x_m + budget, entry.y_m]]}}
	var moved := _move(f)
	if moved.is_empty(): return
	var closed := _close(api, f.repo, moved.state)
	assert_eq(closed.status, "complete", closed.reason)
	if closed.candidate == null: return
	var state: GameState = closed.candidate
	state.day_resolution.body_battle.stage = "round"
	state.day_resolution.battle_step = "fighting"
	state.day_resolution.battle_ids = [8]
	state.day_resolution.body_battle.battle_ids = ["8"]
	# A separate valid personnel transaction retires the tail; no lifecycle code is added here.
	assert_false(Personnel.move(f.repo, state, f.code, "fit", "dead", 100).has("error"))
	state.battles[0].groups[f.code].pop_back()
	_seal(f.repo, state)
	assert_eq(UnitBodies.validate_battle_candidate(f.repo, state, BodyBattleMotion._boundary(state)).status, "complete")
	assert_eq(state.military_migration.body_battle.closed_motion.priority.size(), 2, "descriptor retains original ordering proof")
	var stale := BodyBattleMotion.commit_candidate(f.repo, state, moved.plan, moved.boundary)
	assert_eq(stale.status, "error", "retired movement cannot replay after loss")
	assert_null(stale.candidate)
	state.day_resolution.march_entries[newcomer].order = ArmySystem.ORDER_MARCH
	_successor(f.repo, state)
	var plans: Array = []
	for source: GameState in [state, _json(state)]:
		var next := BodyBattleMotion.plan_candidate(f.repo, source, BodyBattleMotion._boundary(source), f.providers)
		assert_eq(next.status, "complete", next.reason)
		if next.plan.is_empty(): return
		assert_eq(next.plan.motion.moves.size(), 2)
		assert_eq(next.plan.motion.cursor.priority, [{"unit": f.code, "slot": 0}, {"unit": newcomer, "slot": 0}], "survivor keeps priority ahead of lexically earlier new mover")
		assert_eq(next.plan.motion.moves[1].used_m, 100)
		assert_eq(next.plan.motion.moves[1].start[0], 50100)
		assert_eq(next.plan.motion.moves[1].end[0], 50200)
		plans.append(next.plan)
	assert_eq(plans[0], plans[1])

func test_close_and_retry_reject_each_corrupt_proof_atomically() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture()
	var moved := _move(f)
	if moved.is_empty(): return
	var early := _close(api, f.repo, f.state)
	assert_eq(early.status, "error", "move stage is before Q closure")
	assert_null(early.candidate)
	for change: String in ["stage", "day_sequence", "outer_sequence", "queue", "cost", "rng", "inner_result", "inner_plan", "inner_hash", "outer_receipt", "outer_result", "endpoint", "policy", "grid", "unknown"]:
		var state := _json(moved.state)
		match change:
			"stage": state.day_resolution.body_battle.stage = "round"
			"day_sequence": state.day_resolution.body_battle.sequence = "2"
			"outer_sequence": state.military_migration.body_battle.sequence = "1"
			"queue": state.day_resolution.battle_ids = [8]
			"cost": state.regiments[f.code].supplies -= 1
			"rng": state.rng.randi_range(1, 20)
			"inner_result": state.military_migration.body_motion.plan.cursor.basis.result = "c".repeat(64)
			"inner_plan": state.military_migration.body_motion.plan.moves[0].end[0] += 1
			"inner_hash": state.military_migration.body_motion.receipt = "c".repeat(64)
			"outer_receipt": state.military_migration.body_battle.receipt = "c".repeat(64)
			"outer_result": state.military_migration.body_battle.result = "c".repeat(64)
			"endpoint": state.regiments[f.code].body_groups[0].x_m += 1
			"policy": f.repo.balance.battle_deploy_step_m += 1
			"grid": f.grid.closed[0] = 1
			"unknown": state.military_migration.body_motion.extra = 0
		var before := BodyMotion._hash(state.to_dict())
		var rejected := _close(api, f.repo, state)
		assert_eq(rejected.status, "error", change)
		assert_null(rejected.candidate, change)
		var retry := BodyBattleMotion.commit_candidate(f.repo, state, moved.plan, moved.boundary)
		assert_eq(retry.status, "error", change)
		assert_null(retry.candidate, change)
		assert_eq(BodyMotion._hash(state.to_dict()), before, change)
		if change == "policy": f.repo.balance.battle_deploy_step_m -= 1
		if change == "grid": f.grid.closed[0] = 0

func test_closed_descriptor_raw_json_and_same_older_cursors() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture()
	# Close slice 1 so both same and older nonnegative cursors can be challenged.
	f.state.day_resolution.substep_index = 1
	f.state.day_resolution.body_battle.next_substep = "1"
	var moved := _move(f)
	if moved.is_empty(): return
	var closed := _close(api, f.repo, moved.state)
	assert_eq(closed.status, "complete", closed.reason)
	if closed.candidate == null: return
	var sealed: GameState = closed.candidate
	_seal(f.repo, sealed)
	var repeated := _close(api, f.repo, sealed)
	assert_eq(repeated.status, "error", "an absent timeline cannot be closed again")
	assert_null(repeated.candidate)
	for change: String in ["unknown", "version", "day", "slot", "duplicate", "receipt", "priority", "future"]:
		var state := _json(sealed)
		var descriptor: Dictionary = state.military_migration.body_battle.closed_motion
		match change:
			"unknown": descriptor.extra = 0
			"version": descriptor.version = "3"
			"day": descriptor.abs_day = 0
			"slot": descriptor.priority[0].slot = "i0"
			"duplicate": descriptor.priority.append(descriptor.priority[0].duplicate())
			"receipt": descriptor.receipt = "c".repeat(64)
			"priority": descriptor.priority.reverse()
			"future": descriptor.substep = "2"
		for source: GameState in [state, _json(state)]:
			var before := BodyMotion._hash(source.to_dict())
			assert_eq(UnitBodies.validate_battle_candidate(f.repo, source, BodyBattleMotion._boundary(source)).status, "error", change)
			assert_eq(BodyMotion._hash(source.to_dict()), before)
	for slice: int in [0, 1]:
		var state := _json(sealed)
		state.day_resolution.substep_index = slice
		state.day_resolution.body_battle.next_substep = str(slice)
		state.day_resolution.body_battle.stage = "move"
		_seal(f.repo, state)
		assert_eq(BodyBattleMotion.plan_candidate(f.repo, state, BodyBattleMotion._boundary(state)).status, "error", "cannot reopen closed cursor")
		# Standalone TIME cannot bypass the shared cursor by leaving the battle day.
		state.day_resolution = {}
		state.military_migration.body_battle.result = UnitBodies._battle_result_hash(f.repo, state)
		assert_true(BodyMotion.plan_locomotion_candidate(f.repo, state, [], state.absolute_day(), slice).cursor.is_empty())
		assert_true(BodyMotion.plan(f.repo, state, [], state.absolute_day(), slice).cursor.is_empty())
		for version: int in [1, 2]:
			var begun := TickEngine.new(f.repo).begin_body_march_candidate(state) if version == 1 else TickEngine.new(f.repo).begin_locomotion_march_candidate(state)
			assert_eq(begun.status, "error", "standalone march cannot begin behind closed movement")
			assert_null(begun.candidate)

func _safe_closed(api: GDScript, counts: Array = [200]) -> Dictionary:
	var f := _fixture(counts)
	var moved := _move(f)
	if moved.is_empty(): return {}
	var closed := _close(api, f.repo, moved.state)
	assert_eq(closed.status, "complete", closed.reason)
	if closed.candidate == null: return {}
	f.state = closed.candidate
	f.state.day_resolution = {}
	f.state.military_migration.body_battle.sequence = "1"
	f.state.military_migration.body_battle.receipt = BodyMotion._hash(["test safe enclosing transaction"])
	f.state.military_migration.body_battle.result = UnitBodies._battle_result_hash(f.repo, f.state)
	return f

func test_standalone_later_cursor_authenticates_closed_proof() -> void:
	var api := _api()
	if api == null: return
	var f := _safe_closed(api)
	if f.is_empty(): return
	var intents: Array = []
	for row: Dictionary in UnitBodies.rows(f.repo, f.state, f.code):
		intents.append({"unit": f.code, "slot": row.slot, "path_m": [[row.x_m, row.y_m], [row.x_m + 100, row.y_m]], "budget_m": 100, "hostile": false})
	for change: String in ["valid", "priority", "closed_receipt", "outer_result", "unsealed"]:
		var state := UnitBodies._copy(f.state)
		match change:
			"priority": state.military_migration.body_battle.closed_motion.priority.reverse()
			"closed_receipt": state.military_migration.body_battle.closed_motion.receipt = "c".repeat(64)
			"outer_result": state.military_migration.body_battle.result = "c".repeat(64)
			"unsealed": state.military_migration.body_battle.sequence = "0"
		for source: GameState in [state, _json(state)]:
			var before := BodyMotion._hash(source.to_dict())
			var v1 := BodyMotion.plan(f.repo, source, intents, source.absolute_day(), 1)
			var v2 := BodyMotion.plan_locomotion_candidate(f.repo, source, intents, source.absolute_day(), 1)
			assert_eq(v1.cursor.is_empty(), change != "valid", change + " v1 admission")
			assert_eq(v2.cursor.is_empty(), change != "valid", change + " v2 admission")
			for version: int in [1, 2]:
				var plan: Dictionary = v1 if version == 1 else v2
				if change != "valid":
					# A forged numerical plan must not bypass public commit admission.
					plan = BodyMotion._plan(f.repo, source, intents, source.absolute_day(), 1, {}, false) if version == 1 else BodyMotion._plan_locomotion(f.repo, source, intents, source.absolute_day(), 1, {}, false)
				assert_false(plan.cursor.is_empty(), "complete numerical plan for admission check")
				if plan.cursor.is_empty(): continue
				var detached := UnitBodies._copy(source)
				var result := BodyMotion.commit(f.repo, detached, plan) if version == 1 else BodyMotion.commit_locomotion_candidate(f.repo, detached, plan)
				assert_eq(result.status, "complete" if change == "valid" else "error", change + " commit")
				if change == "valid" and result.status == "complete":
					var endpoint: GameState = detached if version == 1 else result.candidate
					assert_eq(endpoint.regiments[f.code].body_groups[0].x_m, 50200, "legitimate later cursor moves once")
				else: assert_eq(BodyMotion._hash(detached.to_dict()), before, "rejected commit preserves source")
			assert_eq(BodyMotion._hash(source.to_dict()), before, change + " preserves source")

func test_march_authenticates_closed_proof_before_private_staging() -> void:
	var api := _api()
	if api == null: return
	var f := _safe_closed(api, [1000])
	if f.is_empty(): return
	var helper: GutTest = load("res://tests/engine/test_body_marches.gd").new()
	helper.call("_runner", f, 1000)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	f.state.day += 1
	f.state.military_migration.body_battle.result = UnitBodies._battle_result_hash(f.repo, f.state)
	for version: int in [1, 2]:
		for change: String in ["valid", "priority", "closed_receipt", "outer_result"]:
			var state := _json(f.state)
			match change:
				"priority": state.military_migration.body_battle.closed_motion.priority.reverse()
				"closed_receipt": state.military_migration.body_battle.closed_motion.receipt = "c".repeat(64)
				"outer_result": state.military_migration.body_battle.result = "c".repeat(64)
			var before := BodyMotion._hash(state.to_dict())
			var begun := TickEngine.new(f.repo).begin_body_march_candidate(state) if version == 1 else TickEngine.new(f.repo).begin_locomotion_march_candidate(state)
			assert_eq(begun.status, "complete" if change == "valid" else "error", change + " march begin")
			assert_eq(BodyMotion._hash(state.to_dict()), before)
			if change != "valid" or begun.candidate == null: continue
			var candidate: GameState = begun.candidate
			for slice: int in 2:
				var planned := ArmySystem.plan_body_march_candidate(f.repo, candidate) if version == 1 else ArmySystem.plan_locomotion_march_candidate(f.repo, candidate)
				assert_eq(planned.status, "complete", planned.reason)
				if planned.plan.is_empty(): break
				var applied := ArmySystem.commit_body_march_candidate(f.repo, candidate, planned.plan) if version == 1 else ArmySystem.commit_locomotion_march_candidate(f.repo, candidate, planned.plan)
				assert_eq(applied.status, "complete", applied.reason)
				if applied.candidate == null: break
				candidate = _json(applied.candidate)
				assert_eq(candidate.day_resolution.body_march.next_substep, str(slice + 1))
				assert_eq(candidate.regiments[f.code].supplies, 990 - slice * 10, "private run staging pays ten per slice once")
