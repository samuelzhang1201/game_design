extends GutTest

const API: String = "res://scripts/engine/body_battle.gd"

func after_each() -> void:
	MarchPath.forget()

func _fixture() -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_contact.gd").new()
	var f: Dictionary = helper.call("_fixture", 901, 100)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	for code: String in f.state.army_roster:
		var entry := UnitBodies._entry(f.state, code)
		entry.body_groups = f.state.battles[0].groups[code]
		entry.group_anchor_m = [int(entry.x_m), int(entry.y_m)]
		entry.group_facing = 37
		entry.facing_deg = 37
		for row: Dictionary in entry.body_groups:
			row.path_m = [[row.x_m - 2, row.y_m], [row.x_m, row.y_m]]
		var piece := MapObjects.army_piece(f.repo, f.state.army_roster[code])
		f.repo.unit_footprints[piece].locomotion_certificate = {"digest": "a".repeat(64),
			"turn_q": 400000, "contact_um": 100, "radius_m": int(f.repo.unit_footprints[piece].radius_m),
			"clips": ["PIVOT_LEFT", "PIVOT_RIGHT", "MARCH"], "all_turns": true}
		f.repo.balance["body_locomotion_" + piece + "_turn_q"] = 400000
		f.repo.balance["body_locomotion_" + piece + "_contact_um"] = 100
	f.state.battles = []
	var tx := DayResolution.begin(f.state.day, false, f.state.absolute_day())
	tx.phase = "FIXED_TACTICAL_SUBSTEPS"
	tx.phase_cursor = 5
	tx.march_entries = {}
	tx.march_budgets = {}
	tx.marching_codes = []
	tx.body_battle = {"version": "1", "abs_day": str(f.state.absolute_day()), "sequence": "0",
		"next_substep": "0", "substep_count": "10", "stage": "contact",
		"battle_ids": [], "battle_index": "0", "processed_units": []}
	f.state.day_resolution = tx
	return f

func _api() -> GDScript:
	assert_true(ResourceLoader.exists(API), "B-ENTER contact/start/join API must exist")
	return load(API) if ResourceLoader.exists(API) else null

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)

func test_founders_and_join_do_not_reseed() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture()
	var boundary := BodyBattleMotion._boundary(f.state)
	var before: Dictionary = f.state.to_dict()
	var planned: Dictionary = api.plan_candidate(f.repo, f.state, {"kind": "contacts"}, boundary)
	assert_eq(planned.status, "complete", planned.reason)
	assert_eq(f.state.to_dict(), before)
	if planned.plan.is_empty(): return
	var result: Dictionary = api.commit_candidate(f.repo, f.state, planned.plan, boundary)
	assert_eq(result.status, "complete", result.reason)
	assert_eq(f.state.to_dict(), before)
	if result.candidate == null: return
	var state: GameState = result.candidate
	assert_eq(state.battles.size(), 1)
	if state.battles.is_empty(): return
	for code: String in [f.unit, f.enemy]:
		assert_eq(UnitBodies.rows(f.repo, state, code), UnitBodies.rows(f.repo, f.state, code))
		assert_eq(state.battles[0].group_anchor_m[code], UnitBodies._entry(f.state, code).group_anchor_m)
		assert_eq(state.battles[0].group_facing[code], 37)
		assert_eq(UnitBodies._entry(state, code).facing_deg, 37)
	assert_eq(state.rng.to_dict(), f.state.rng.to_dict())
	assert_eq(state.metrics, f.state.metrics)
	assert_eq(state.military_cohorts, f.state.military_cohorts)
	for source: GameState in [state, _json(state)]:
		var retry: Dictionary = api.commit_candidate(f.repo, source, planned.plan, boundary)
		assert_eq(retry.status, "complete", retry.reason)
		if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), BodyMotion._hash(source.to_dict()))

func test_closed_requests_and_failure_rollback() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture()
	var before: Dictionary = f.state.to_dict()
	for request: Dictionary in [{"kind": "move"}, {"kind": "contacts", "extra": true},
		{"kind": "enter", "unit": f.other, "battle_id": "i8", "side": "att"}]:
		var result: Dictionary = api.plan_candidate(f.repo, f.state, request, BodyBattleMotion._boundary(f.state))
		assert_eq(result.status, "error")
		assert_null(result.candidate)
		assert_eq(result.plan, {})
		assert_eq(f.state.to_dict(), before)

func _field(f: Dictionary) -> void:
	var state: GameState = f.state
	var b := BattleSystem.contact_skeleton_candidate(f.repo, state, f.unit, f.enemy)
	b.id = 8
	b.groups = {}
	b.group_anchor_m = {}
	b.group_facing = {}
	b.body_version = 1
	b.group_size_version = 2
	b.group_size_men = 100
	for code: String in [f.unit, f.enemy]:
		var entry := UnitBodies._entry(state, code)
		b.groups[code] = entry.body_groups
		entry.erase("body_groups")
		for key: String in ["group_anchor_m", "group_facing"]:
			b[key][code] = entry[key]
			entry.erase(key)
	state.battles = [b]

func _joiner(f: Dictionary) -> void:
	var personnel: GDScript = load("res://tests/engine/personnel_helpers.gd")
	assert_false(personnel.replace(f.repo, f.state, f.other, 901).has("error"))
	var entry := UnitBodies._entry(f.state, f.other)
	entry.body_groups = []
	for slot: int in 10:
		entry.body_groups.append({"slot": slot, "home_slot": slot, "count": 100 if slot < 9 else 1,
			"x_m": 10000 + slot * 10000, "y_m": 11731, "facing_deg": 37, "role": "reserve",
			"path_m": [[10000 + slot * 10000, 11730], [10000 + slot * 10000, 11731]]})

func test_ten_row_join_is_once_and_preserves_party_baseline() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture()
	_field(f)
	_joiner(f)
	var request := {"kind": "enter", "unit": f.other, "battle_id": "8", "side": "att"}
	var original := UnitBodies.rows(f.repo, f.state, f.other)
	var baseline: Dictionary = f.state.battles[0].parley.duplicate(true)
	var before: Dictionary = f.state.to_dict()
	var boundary := BodyBattleMotion._boundary(f.state)
	var p: Dictionary = api.plan_candidate(f.repo, f.state, request, boundary)
	assert_eq(p.status, "complete", p.reason)
	if p.plan.is_empty(): return
	assert_eq(p.plan.contacts, [], "enter has no discovery payload")
	var committed: Dictionary = api.commit_candidate(f.repo, f.state, p.plan, boundary)
	assert_eq(committed.status, "complete", committed.reason)
	assert_eq(f.state.to_dict(), before)
	if committed.candidate == null: return
	var state: GameState = committed.candidate
	assert_eq(UnitBodies.rows(f.repo, state, f.other), original)
	assert_eq(UnitBodies._owners(state).owners[f.other].id, 8)
	assert_eq(state.battles[0].att.count(f.other), 1)
	assert_eq(state.battles[0].event_reinforcements, [f.other])
	assert_eq(state.battles[0].reinforcement_evidence.size(), 1)
	assert_eq(state.battles[0].parley.received, baseline.received)
	assert_eq(state.battles[0].parley.parties.att, baseline.parties.att + [f.other])
	assert_eq(state.day_resolution.body_battle.stage, "contact")
	for source: GameState in [state, _json(state)]:
		var retried: Dictionary = api.commit_candidate(f.repo, source, p.plan, boundary)
		assert_eq(retried.status, "complete", retried.reason)
		if retried.candidate != null: assert_eq(BodyMotion._hash(retried.candidate.to_dict()), BodyMotion._hash(source.to_dict()))

func test_friendly_frames_and_no_contact_emit_no_start_or_cost() -> void:
	var api := _api()
	if api == null: return
	for friendly: bool in [false, true]:
		var f := _fixture()
		if friendly:
			for code: String in [f.enemy, f.other]:
				f.state.army_roster[code].kingdom_code = f.repo.resolve_realm("player_realm")
		else:
			for code: String in [f.enemy, f.other]:
				for row: Dictionary in UnitBodies._entry(f.state, code).body_groups: row.y_m += 10000
		var before: Dictionary = f.state.to_dict()
		var boundary := BodyBattleMotion._boundary(f.state)
		var p: Dictionary = api.plan_candidate(f.repo, f.state, {"kind": "contacts"}, boundary)
		assert_eq(p.status, "complete", p.reason)
		if p.plan.is_empty(): continue
		var result: Dictionary = api.commit_candidate(f.repo, f.state, p.plan, boundary)
		assert_eq(result.status, "complete", result.reason)
		assert_eq(f.state.to_dict(), before)
		if result.candidate == null: continue
		assert_eq(result.candidate.battles, [])
		assert_eq(result.candidate.day_resolution.journal.battles, [])
		assert_eq(result.candidate.foe_next_id, f.state.foe_next_id)
		assert_eq(result.candidate.metrics, f.state.metrics)
		assert_eq(result.candidate.regiments, f.state.regiments)
		assert_eq(result.candidate.foes, f.state.foes)
		assert_eq(result.candidate.rng.to_dict(), f.state.rng.to_dict())

func _assert_failure(result: Dictionary, state: GameState, before: Dictionary, status: String = "error") -> void:
	assert_eq(result.status, status, result.reason)
	assert_eq(result.keys().size(), 5)
	assert_null(result.candidate)
	assert_eq(result.plan, {})
	assert_eq(state.to_dict(), before, "failed or deferred operations preserve the entire source")

func test_pending_decision_and_round_defer_but_malformed_controls_error() -> void:
	var api := _api()
	if api == null: return
	for kind: String in ["decision", "round"]:
		var f := _fixture()
		_field(f)
		_joiner(f)
		if kind == "decision":
			f.state.day_resolution.battle_step = "fighting"
			f.state.day_resolution.battle_ids = [8]
			f.state.day_resolution.substep_battle_ids = [8]
			f.state.day_resolution.body_battle.battle_ids = ["8"]
			f.state.day_resolution.body_battle.stage = "round"
			DayResolution.block_on_encounter(f.state.day_resolution, 8)
		else:
			var b: Dictionary = f.state.battles[0]
			var ready := {"version": "1", "token": "bodyround:8:%d:1" % f.state.absolute_day(),
				"abs_day": str(f.state.absolute_day()), "round": "1", "motion_receipt": "a".repeat(64),
				"contact_digest": BodyMotion._hash([]), "basis": "b".repeat(64), "contacts": [], "unit_actions": {}}
			b.body_round = ready
			b.pending_round = {"day": f.state.absolute_day(), "round": 1, "att": b.att.duplicate(), "def": b.def.duplicate(),
				"tier": BattleSystem.tier_of(f.repo, 500).duplicate(true), "att_power": 1, "def_power": 1,
				"odds": 500, "roll": 500, "eff": 500, "contexts": {
					"att": {"kind": "melee", "loss_permille": 1000, "reason": "Frozen contact"},
					"def": {"kind": "melee", "loss_permille": 1000, "reason": "Frozen contact"}},
				"reason": "Frozen round", "costs": [], "unit_actions": {}, "body_round_receipt": BodyMotion._hash(ready)}
		for source: GameState in [f.state, _json(f.state)]:
			var request := {"kind": "enter", "unit": f.other, "battle_id": "8", "side": "att"}
			var before := source.to_dict()
			_assert_failure(api.plan_candidate(f.repo, source, request, BodyBattleMotion._boundary(source)), source, before, "deferred")
			if kind == "decision": source.day_resolution.pending_decision.choices = [true]
			else: source.battles[0].pending_round.costs = [{"code": f.other, "supplies": true, "reason": "Forged"}]
			before = source.to_dict()
			_assert_failure(api.plan_candidate(f.repo, source, request, BodyBattleMotion._boundary(source)), source, before)

func test_raw_hostile_inputs_stale_plans_and_endpoint_tampering() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture()
	var boundary := BodyBattleMotion._boundary(f.state)
	var p: Dictionary = api.plan_candidate(f.repo, f.state, {"kind": "contacts"}, boundary)
	if p.plan.is_empty():
		fail_test(p.reason)
		return
	for key: String in ["basis", "contacts", "request", "boundary", "motion", "extra"]:
		var changed: Dictionary = p.plan.duplicate(true)
		match key:
			"basis": changed.basis.source = "a".repeat(64)
			"contacts": changed.contacts[0].count += 1
			"request": changed.request.kind = "move"
			"boundary": changed.boundary.sequence = "01"
			"motion": changed.motion = {"unused": true}
			"extra": changed.extra = true
		var before: Dictionary = f.state.to_dict()
		_assert_failure(api.commit_candidate(f.repo, f.state, changed, changed.boundary), f.state, before)
	var applied: Dictionary = api.commit_candidate(f.repo, f.state, p.plan, boundary)
	assert_eq(applied.status, "complete", applied.reason)
	if applied.candidate == null: return
	for imported: bool in [false, true]:
		for key: String in ["stage", "sequence", "queue", "cost", "rng", "receipt", "result", "row", "anchor", "unknown"]:
			var changed := UnitBodies._copy(applied.candidate)
			match key:
				"stage": changed.day_resolution.body_battle.stage = "contact"
				"sequence": changed.military_migration.body_battle.sequence = "9"
				"queue": changed.day_resolution.body_battle.battle_ids = []
				"cost": UnitBodies._entry(changed, f.unit).supplies += 1
				"rng": changed.rng.randi_range(0, 100)
				"receipt": changed.military_migration.body_battle.receipt = "a".repeat(64)
				"result": changed.military_migration.body_battle.result = "a".repeat(64)
				"row": changed.battles[0].groups[f.unit][0].facing_deg += 1
				"anchor": changed.battles[0].group_anchor_m[f.unit][0] += 1
				"unknown": changed.military_migration.body_battle.extra = true
			if imported: changed = _json(changed)
			var before := changed.to_dict()
			_assert_failure(api.commit_candidate(f.repo, changed, p.plan, boundary), changed, before)
	for raw: Variant in [true, 1.25, "i42", "f3ff0000000000000"]:
		var changed := UnitBodies._copy(f.state)
		UnitBodies._entry(changed, f.unit).body_groups[0].count = raw
		for source: GameState in [changed, _json(changed)]:
			var before := source.to_dict()
			_assert_failure(api.plan_candidate(f.repo, source, {"kind": "contacts"}, boundary), source, before)
	var changed := UnitBodies._copy(f.state)
	UnitBodies._entry(changed, f.unit).supplies += 1
	var before := changed.to_dict()
	_assert_failure(api.commit_candidate(f.repo, changed, p.plan, boundary), changed, before)

func test_closed_contact_failure_discards_both_private_founders() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture()
	var personnel: GDScript = load("res://tests/engine/personnel_helpers.gd")
	assert_false(personnel.replace(f.repo, f.state, f.unit, 100).has("error"))
	var mine := UnitBodies._entry(f.state, f.unit)
	mine.body_groups = [mine.body_groups[0]]
	mine.body_groups[0].count = 100
	for pair: Array in [[f.unit, 2000, 2000], [f.enemy, 3831, 2000], [f.other, 8000, 8000]]:
		var row: Dictionary = UnitBodies._entry(f.state, pair[0]).body_groups[0]
		row.x_m = pair[1]
		row.y_m = pair[2]
		row.path_m = []
	f.grid.cell_m = 50
	f.grid.cols = 200
	f.grid.rows = 200
	f.grid.closed.resize(40000)
	f.grid.water.resize(40000)
	# The blocked 50m cell lies in the 100m surface gap, outside both physical discs.
	f.grid.closed[40 * 200 + 59] = 1
	var before: Dictionary = f.state.to_dict()
	var boundary := BodyBattleMotion._boundary(f.state)
	assert_eq(UnitBodies.validate_battle_candidate(f.repo, f.state, boundary).status, "complete")
	var p: Dictionary = api.plan_candidate(f.repo, f.state, {"kind": "contacts"}, boundary)
	assert_eq(p.status, "complete", p.reason)
	if p.plan.is_empty(): return
	var result: Dictionary = api.commit_candidate(f.repo, f.state, p.plan, boundary)
	assert_eq(result.status, "complete", result.reason)
	if result.candidate != null:
		assert_eq(result.candidate.battles, [])
		assert_eq(result.candidate.regiments, f.state.regiments)
		assert_eq(result.candidate.foes, f.state.foes)
	assert_eq(f.state.to_dict(), before)

func test_contact_closes_actual_move_and_seals_one_outer_operation() -> void:
	var api := _api()
	if api == null: return
	var helper: GutTest = load("res://tests/engine/test_body_battle_budget.gd").new()
	var f: Dictionary = helper.call("_fixture", [100], 1000)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	var moved_plan := BodyBattleMotion.plan_candidate(f.repo, f.state, BodyBattleMotion._boundary(f.state))
	assert_eq(moved_plan.status, "complete", moved_plan.reason)
	if moved_plan.plan.is_empty(): return
	var moved := BodyBattleMotion.commit_candidate(f.repo, f.state, moved_plan.plan, BodyBattleMotion._boundary(f.state))
	assert_eq(moved.status, "complete", moved.reason)
	if moved.candidate == null: return
	var plans: Array = []
	for source: GameState in [moved.candidate, _json(moved.candidate)]:
		var before := source.to_dict()
		var boundary := BodyBattleMotion._boundary(source)
		var p: Dictionary = api.plan_candidate(f.repo, source, {"kind": "contacts"}, boundary)
		assert_eq(p.status, "complete", p.reason)
		if p.plan.is_empty(): return
		plans.append(p.plan)
		var result: Dictionary = api.commit_candidate(f.repo, source, p.plan, boundary)
		assert_eq(result.status, "complete", result.reason)
		assert_eq(source.to_dict(), before)
		if result.candidate == null: return
		var state: GameState = result.candidate
		assert_false(state.military_migration.has("body_motion"))
		assert_eq(state.military_migration.body_battle.closed_motion.receipt, source.military_migration.body_motion.receipt)
		assert_eq(state.military_migration.body_battle.sequence, "1")
		assert_eq(state.day_resolution.body_battle.sequence, "2")
		assert_eq(state.day_resolution.body_battle.stage, "advance")
		assert_eq(state.regiments, source.regiments)
		assert_eq(state.military_cohorts, source.military_cohorts)
		assert_eq(state.rng.to_dict(), source.rng.to_dict())
		assert_eq(state.day_resolution.march_entries, source.day_resolution.march_entries)
		var retry: Dictionary = api.commit_candidate(f.repo, _json(state), p.plan, boundary)
		assert_eq(retry.status, "complete", retry.reason)
		if retry.candidate != null: assert_eq(BodyMotion._hash(retry.candidate.to_dict()), BodyMotion._hash(state.to_dict()))
	assert_eq(plans[0], plans[1])
	for key: String in ["inner_result", "inner_plan", "inner_hash", "rehashed_inner", "endpoint", "outer", "sequence"]:
		var state := _json(moved.candidate)
		match key:
			"inner_result", "rehashed_inner": state.military_migration.body_motion.plan.cursor.basis.result = "c".repeat(64)
			"inner_plan": state.military_migration.body_motion.plan.moves[0].end[0] += 1
			"inner_hash": state.military_migration.body_motion.receipt = "c".repeat(64)
			"endpoint": state.regiments[f.code].body_groups[0].x_m += 1
			"outer": state.military_migration.body_battle.receipt = "c".repeat(64)
			"sequence": state.day_resolution.body_battle.sequence = "3"
		if key == "rehashed_inner":
			state.military_migration.body_motion.receipt = BodyMotion._hash(state.military_migration.body_motion.plan)
			state.military_migration.body_battle.result = UnitBodies._battle_result_hash(f.repo, state)
		var before := state.to_dict()
		_assert_failure(api.plan_candidate(f.repo, state, {"kind": "contacts"}, BodyBattleMotion._boundary(state)), state, before)

func test_founders_after_real_hold_timeline_preserve_closed_cursor() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture()
	f.state.day_resolution.body_battle.stage = "move"
	for code: String in f.state.army_roster:
		var entry := UnitBodies._entry(f.state, code)
		entry.order = ArmySystem.ORDER_GARRISON
		entry.x_m = entry.body_groups[0].x_m
		entry.y_m = entry.body_groups[0].y_m
		entry.dest_x_m = entry.x_m
		entry.dest_y_m = entry.y_m
		entry.group_anchor_m = [entry.x_m, entry.y_m]
		f.state.day_resolution.march_budgets[code] = 0
	var boundary := BodyBattleMotion._boundary(f.state)
	var motion := BodyBattleMotion.plan_candidate(f.repo, f.state, boundary)
	assert_eq(motion.status, "complete", motion.reason)
	if motion.plan.is_empty(): return
	var moved := BodyBattleMotion.commit_candidate(f.repo, f.state, motion.plan, boundary)
	assert_eq(moved.status, "complete", moved.reason)
	if moved.candidate == null: return
	for source: GameState in [moved.candidate, _json(moved.candidate)]:
		var before := source.to_dict()
		boundary = BodyBattleMotion._boundary(source)
		var p: Dictionary = api.plan_candidate(f.repo, source, {"kind": "contacts"}, boundary)
		assert_eq(p.status, "complete", p.reason)
		if p.plan.is_empty(): return
		var result: Dictionary = api.commit_candidate(f.repo, source, p.plan, boundary)
		assert_eq(result.status, "complete", result.reason)
		assert_eq(source.to_dict(), before)
		if result.candidate == null: return
		var state: GameState = result.candidate
		assert_eq(state.battles.size(), 1)
		assert_eq(state.military_migration.body_battle.sequence, "1")
		assert_eq(state.military_migration.body_battle.closed_motion.receipt, source.military_migration.body_motion.receipt)
		assert_eq(state.military_migration.body_battle.closed_motion.priority, source.military_migration.body_motion.priority)
		for code: String in f.state.army_roster:
			assert_eq(UnitBodies.rows(f.repo, state, code), UnitBodies.rows(f.repo, source, code))
			assert_eq(UnitBodies._entry(state, code).group_next_slot, UnitBodies._entry(source, code).group_next_slot)
		assert_eq(state.rng.to_dict(), source.rng.to_dict())
		var retried: Dictionary = api.commit_candidate(f.repo, _json(state), p.plan, boundary)
		assert_eq(retried.status, "complete", retried.reason)
		if retried.candidate != null: assert_eq(BodyMotion._hash(retried.candidate.to_dict()), BodyMotion._hash(state.to_dict()))
