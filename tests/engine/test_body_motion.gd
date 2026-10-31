extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _api() -> GDScript:
	var path := "res://scripts/engine/body_motion.gd"
	assert_true(FileAccess.file_exists(path), "CF03 candidate planner exists")
	return load(path) if FileAccess.file_exists(path) else null

func test_candidate_api_exists() -> void:
	var api := _api()
	if api == null: return
	assert_true(api.has_method("plan"))
	assert_true(api.has_method("commit"))

func _fixture(points: Array) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 319)
	var codes: Array = state.regiments.keys()
	codes.sort()
	var code := String(codes[0])
	var result := Personnel.replace(repo, state, code, points.size() * 100)
	assert_false(result.has("error"))
	state.regiments = {code: state.regiments[code]}
	state.army_roster = {code: state.army_roster[code]}
	state.foes = {}
	state.battles = []
	state.military_rosters = {code: state.military_rosters[code]}
	var cohorts := {}
	for id: String in state.military_rosters[code].cohort_ids:
		cohorts[id] = state.military_cohorts[id]
	state.military_cohorts = cohorts
	state.military_migration.body_version = 1
	var entry: Dictionary = state.regiments[code]
	entry.group_next_slot = points.size()
	entry.body_groups = []
	for i: int in points.size():
		entry.body_groups.append({"slot": i, "home_slot": i, "count": 100,
			"x_m": points[i][0], "y_m": points[i][1], "role": "front", "facing_deg": 0, "path_m": []})
	var piece := MapObjects.army_piece(repo, state.army_roster[code])
	repo.unit_footprints[piece] = {"radius_m": 10, "pitch_m": 40, "width_m": 180, "depth_m": 60, "files": 5, "ranks": 2}
	assert_eq(UnitBodies.migrate_candidate(repo, state).status, "complete")
	return {"repo": repo, "state": state, "code": code}

func _intent(f: Dictionary, slot: int, target: Array, budget: int = 400, hostile: bool = false) -> Dictionary:
	var row: Dictionary = f.state.regiments[f.code].body_groups[slot]
	return {"unit": f.code, "slot": slot, "path_m": [[row.x_m, row.y_m], target], "budget_m": budget, "hostile": hostile}

func _json(state: GameState) -> GameState:
	return GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))

func _unchanged(f: Dictionary, api: GDScript, intents: Array) -> Dictionary:
	var before: Dictionary = f.state.to_dict()
	var rng: Dictionary = f.state.rng.to_dict()
	var result: Dictionary = api.plan(f.repo, f.state, intents, 70, 0)
	assert_eq(f.state.to_dict(), before)
	assert_eq(f.state.rng.to_dict(), rng)
	return result

func _safe(result: Dictionary, radius: int = 10) -> void:
	# Independent piecewise linear sampling supplements the analytic regression cases.
	for move: Dictionary in result.moves:
		var length := 0
		for i: int in range(1, move.path_m.size()):
			var a: Array = move.path_m[i - 1]
			var b: Array = move.path_m[i]
			length += int(ceil(Vector2(b[0] - a[0], b[1] - a[1]).length()))
		assert_eq(move.used_m, length)
		assert_true(length <= move.budget_m)
	for i: int in result.moves.size():
		for j: int in range(i + 1, result.moves.size()):
			for tick: int in 1001:
				var a := _position(result.moves[i], tick / 1000.0)
				var b := _position(result.moves[j], tick / 1000.0)
				assert_true(a.distance_to(b) >= radius * 2 - 0.00001, "entire simultaneous path is clear")

func _position(move: Dictionary, time: float) -> Vector2:
	var remaining: float = time * move.budget_m
	for i: int in range(1, move.path_m.size()):
		var a := Vector2(move.path_m[i - 1][0], move.path_m[i - 1][1])
		var b := Vector2(move.path_m[i][0], move.path_m[i][1])
		var length := ceilf(a.distance_to(b))
		if remaining <= length and length > 0: return a.lerp(b, remaining / length)
		remaining -= length
	var end: Array = move.path_m.back()
	return Vector2(end[0], end[1])

func test_swept_crossing_and_head_on() -> void:
	var api := _api()
	if api == null: return
	for start: Array in [[100, 0], [0, -100]]:
		var f := _fixture([[-100, 0], start])
		var target: Array = [-100, 0] if start[0] == 100 else [0, 100]
		var intents := [_intent(f, 0, [100, 0]), _intent(f, 1, target)]
		var p := _unchanged(f, api, intents)
		assert_false(p.cursor.is_empty(), str(p.reasons))
		assert_eq(p.moves.size(), 2)
		_safe(p)
		assert_true(p.moves[0].used_m > 0, "priority body progresses")
		intents.reverse()
		assert_eq(api.plan(f.repo, f.state, intents, 70, 0), p)
		assert_eq(api.plan(f.repo, _json(f.state), JSON.parse_string(JSON.stringify(intents)), 70, 0), p)

func test_budget_is_actual_polyline_not_chord() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([[0, 0]])
	var intent := _intent(f, 0, [3, 4], 12)
	intent.path_m.append([9, 12])
	var p := _unchanged(f, api, [intent])
	_safe(p)
	assert_eq(p.moves[0].path_m, [[0, 0], [3, 4], [7, 9]])
	assert_eq(p.moves[0].used_m, 12, "5 + ceil(sqrt(41)) = 12")

func test_commit_retry_json_and_stale_atomic() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([[-100, 0], [100, 0]])
	var p := _unchanged(f, api, [_intent(f, 0, [100, 0]), _intent(f, 1, [-100, 0])])
	var rng: Dictionary = f.state.rng.to_dict()
	var result: Dictionary = api.commit(f.repo, f.state, p)
	assert_eq(result.status, "complete", str(result))
	assert_eq(f.state.rng.to_dict(), rng)
	assert_eq(UnitBodies.migrate_candidate(f.repo, f.state).status, "complete")
	var after: Dictionary = f.state.to_dict()
	assert_eq(api.commit(f.repo, f.state, p).status, "complete")
	assert_eq(f.state.to_dict(), after)
	var restored := _json(f.state)
	assert_eq(api.commit(f.repo, restored, JSON.parse_string(JSON.stringify(p))).status, "complete")
	assert_eq(restored.to_dict(), after)
	var changed := p.duplicate(true)
	changed.moves[0].path_m.back()[0] += 1
	assert_eq(api.commit(f.repo, f.state, changed).status, "error")
	assert_eq(f.state.to_dict(), after)

func test_invalid_inputs_and_forged_stale_plan_are_atomic() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([[0, 0]])
	var valid := _intent(f, 0, [100, 0])
	for field: String in ["budget_m", "path_m", "slot", "hostile"]:
		var bad := valid.duplicate(true)
		match field:
			"budget_m": bad.budget_m = -1
			"path_m": bad.path_m[1][0] = 1.5
			"slot": bad.slot = true
			"hostile": bad.hostile = 1
		var p := _unchanged(f, api, [bad])
		assert_true(p.cursor.is_empty())
		assert_true(p.reasons.has("error"))
	assert_true(_unchanged(f, api, [valid, valid]).cursor.is_empty())
	var p := _unchanged(f, api, [valid])
	var before: Dictionary = f.state.to_dict()
	p.moves[0].used_m = 0
	assert_eq(api.commit(f.repo, f.state, p).status, "error")
	assert_eq(f.state.to_dict(), before)
	p = _unchanged(f, api, [valid])
	f.state.regiments[f.code].body_groups[0].x_m = 1
	before = f.state.to_dict()
	assert_eq(api.commit(f.repo, f.state, p).status, "error")
	assert_eq(f.state.to_dict(), before)

func test_uninitialized_frozen_invalid_bodies_not_materialized() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([[0, 0]])
	var intent := _intent(f, 0, [50, 0])
	f.state.regiments[f.code].erase("body_groups")
	f.state.military_migration.erase("body_version")
	assert_true(_unchanged(f, api, [intent]).cursor.is_empty())
	f = _fixture([[0, 0], [100, 0]])
	f.state.regiments[f.code].body_groups[1].x_m = 0
	assert_true(_unchanged(f, api, []).cursor.is_empty())

func test_hostile_waits_and_tangent_rotation_envelope() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([[-100, 0], [100, 0]])
	var p := _unchanged(f, api, [_intent(f, 0, [100, 0], 400, true), _intent(f, 1, [-100, 0], 400, true)])
	_safe(p)
	for move: Dictionary in p.moves:
		for point: Array in move.path_m: assert_eq(int(point[1]), 0, "hostile bodies receive no friendly detour")
	f = _fixture([[0, 0], [20, 0]])
	p = _unchanged(f, api, [_intent(f, 0, [0, 20], 20)])
	assert_eq(p.moves[0].used_m, 20, "conservative circular envelope permits tangent start in any facing")

func test_three_way_stable_priority_and_finite_stall() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([[-100, 0], [100, 0], [0, -100]])
	var intents := [_intent(f, 0, [100, 0]), _intent(f, 1, [-100, 0]), _intent(f, 2, [0, 100])]
	var p := _unchanged(f, api, intents)
	_safe(p)
	intents.reverse()
	assert_eq(p, api.plan(f.repo, f.state, intents, 70, 0))
	# Equal diameter corridor has no lateral exit: stationary bodies enclose the mover.
	f = _fixture([[0, 0], [20, 0], [-20, 0], [0, 20], [0, -20]])
	p = _unchanged(f, api, [_intent(f, 0, [100, 0])])
	assert_eq(p.moves[0].used_m, 0)
	assert_eq(p.blocked, [{"unit": f.code, "slot": 0}])
	assert_false(p.reasons.is_empty())
	assert_eq(api.commit(f.repo, f.state, p).status, "complete")
	var next: Dictionary = api.plan(f.repo, f.state, [_intent(f, 0, [100, 0])], 70, 1)
	assert_eq(next.moves[0].used_m, 0, "no endless mutual retreat")

func test_small_radius_large_coordinate_local_differences() -> void:
	var api := _api()
	if api == null: return
	var base: int = 9007199254740000
	var f := _fixture([[base, 0], [base + 20, 0]])
	var p := _unchanged(f, api, [_intent(f, 0, [base, 20], 20)])
	assert_false(p.cursor.is_empty())
	assert_eq(p.moves[0].path_m.back(), [base, 20])
	assert_eq(p.moves[0].used_m, 20)

func test_narrow_corridor_priority_batch_passes_other_waits() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([[-60, 0], [60, 0], [-20, 20], [0, 20], [20, 20], [-20, -20], [0, -20], [20, -20]])
	var p := _unchanged(f, api, [_intent(f, 0, [40, 0], 100), _intent(f, 1, [-40, 0], 100)])
	assert_eq(p.moves[0].path_m.back(), [40, 0], "priority passes the one-body-wide corridor")
	assert_eq(p.moves[1].used_m, 0, "opposing batch waits at the mouth")
	_safe(p)
	for move: Dictionary in p.moves:
		for tick: int in 1001:
			var point := _position(move, tick / 1000.0)
			for row: Dictionary in f.state.regiments[f.code].body_groups.slice(2):
				assert_true(point.distance_to(Vector2(row.x_m, row.y_m)) >= 20, "wall bodies remain physical obstacles")
	assert_eq(api.commit(f.repo, f.state, p).status, "complete")
	# The passing batch continues out; the waiting batch still cannot swap through it.
	var next_intents := [_intent(f, 0, [120, 0]), _intent(f, 1, [-40, 0])]
	var next: Dictionary = api.plan(f.repo, f.state, next_intents, 70, 1)
	_safe(next)
	assert_eq(next.cursor.priority[0], {"unit": f.code, "slot": 0}, "saved progress retains priority")
	assert_eq(api.plan(f.repo, _json(f.state), JSON.parse_string(JSON.stringify(next_intents)), 70, 1), next)

func test_cursor_raw_schema_survives_save_without_rounding_acceptance() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([[0, 0]])
	var p := _unchanged(f, api, [_intent(f, 0, [50, 0])])
	assert_eq(api.commit(f.repo, f.state, p).status, "complete")
	var saved: Dictionary = f.state.military_migration.body_motion
	assert_eq(saved.version, "1", "decimal strings bypass legacy numeric rounding")
	assert_eq(saved.abs_day, "70")
	for bad: Variant in [1, 1.1, true, "01", "2"]:
		var copy := _json(f.state)
		copy.military_migration.body_motion.version = bad
		copy = _json(copy)
		var before: Dictionary = copy.to_dict()
		assert_true(api.plan(f.repo, copy, [], 71, 0).cursor.is_empty())
		assert_eq(api.commit(f.repo, copy, p).status, "error")
		assert_eq(copy.to_dict(), before)

func test_fast_small_disc_cannot_tunnel_between_sampling_frames() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([[0, 0], [500001, 0]])
	var piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
	f.repo.unit_footprints[piece] = {"radius_m": 1, "pitch_m": 4, "width_m": 18, "depth_m": 6, "files": 5, "ranks": 2}
	var p := _unchanged(f, api, [_intent(f, 0, [1000000, 0], 1000000, true)])
	assert_eq(p.moves[0].path_m.back(), [499999, 0], "exact integer tangency stops at the two-metre envelope even between sample times")
	assert_true(p.moves[0].used_m <= 499999)

func test_extreme_int64_points_do_not_wrap_toward_each_other() -> void:
	var api := _api()
	if api == null: return
	var low: int = -9223372036854775708
	var high: int = 9223372036854775707
	var f := _fixture([[low, 0], [high, 0]])
	var p := _unchanged(f, api, [_intent(f, 0, [low + 20, 0], 20)])
	assert_false(p.cursor.is_empty(), str(p.reasons))
	assert_eq(p.moves[0].used_m, 20)
	assert_eq(p.moves[0].path_m.back(), [low + 20, 0])

func test_malformed_saved_cursor_and_frozen_transaction_fail_closed() -> void:
	var api := _api()
	if api == null: return
	for value: Variant in [{}, null, [], {"version": "1"}]:
		var f := _fixture([[0, 0]])
		f.state.military_migration.body_motion = value
		assert_true(_unchanged(f, api, [_intent(f, 0, [20, 0])]).cursor.is_empty())
	var f := _fixture([[0, 0]])
	f.state.day_resolution = {"phase": "battles", "costs": [18]}
	assert_eq(UnitBodies.migrate_candidate(f.repo, f.state).status, "deferred")
	assert_true(_unchanged(f, api, [_intent(f, 0, [20, 0])]).cursor.is_empty())

func _unit_fixture(points: Array) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 319)
	var codes: Array = state.regiments.keys()
	codes.sort()
	codes = codes.slice(0, points.size())
	var entries := {}
	var definitions := {}
	var rosters := {}
	var cohorts := {}
	for i: int in points.size():
		var code := String(codes[i])
		assert_false(Personnel.replace(repo, state, code, 100).has("error"))
		entries[code] = state.regiments[code]
		definitions[code] = state.army_roster[code]
		rosters[code] = state.military_rosters[code]
		for id: String in rosters[code].cohort_ids: cohorts[id] = state.military_cohorts[id]
		entries[code].group_next_slot = 1
		entries[code].body_groups = [{"slot": 0, "home_slot": 0, "count": 100, "x_m": points[i][0],
			"y_m": points[i][1], "role": "front", "facing_deg": 90, "path_m": []}]
		var piece := MapObjects.army_piece(repo, definitions[code])
		repo.unit_footprints[piece] = {"radius_m": 10, "pitch_m": 40, "width_m": 180, "depth_m": 60, "files": 5, "ranks": 2}
	state.regiments = entries
	state.army_roster = definitions
	state.military_rosters = rosters
	state.military_cohorts = cohorts
	state.foes = {}
	state.battles = []
	state.military_migration.body_version = 1
	assert_eq(UnitBodies.migrate_candidate(repo, state).status, "complete")
	return {"repo": repo, "state": state, "code": codes[0], "codes": codes}

func test_distinct_units_cross_overlapping_rectangles_but_not_hostile_bodies() -> void:
	var api := _api()
	if api == null: return
	var f := _unit_fixture([[-40, 0], [40, 0]])
	var intents: Array = []
	for i: int in 2:
		intents.append({"unit": f.codes[i], "slot": 0, "path_m": [[-40 if i == 0 else 40, 0], [40 if i == 0 else -40, 0]],
			"budget_m": 400, "hostile": false})
	var p := _unchanged(f, api, intents)
	_safe(p)
	assert_true(p.moves[0].used_m > 0)
	assert_true(p.moves[1].path_m.size() > 2, "friendly bodies can sidestep despite overlapping fixed deployment rectangles")
	intents.reverse()
	assert_eq(api.plan(f.repo, f.state, intents, 70, 0), p)
	f.state.army_roster[f.codes[1]].kingdom_code = "fixture:hostile"
	p = _unchanged(f, api, intents)
	_safe(p)
	for move: Dictionary in p.moves:
		for point: Array in move.path_m: assert_eq(int(point[1]), 0, "realm hostility disallows friendly bypass even if intent hostile is false")

func test_measured_production_radius_candidate_and_configuration_staleness() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([[0, 0], [100000, 0]])
	f.repo.unit_footprints = SuiteData.repo().unit_footprints.duplicate(true)
	var piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
	var radius := int(f.repo.unit_footprints[piece].radius_m)
	f.state.regiments[f.code].body_groups[0].x_m = -3 * radius
	f.state.regiments[f.code].body_groups[1].x_m = 3 * radius
	var intents := [_intent(f, 0, [3 * radius, 0], 12 * radius), _intent(f, 1, [-3 * radius, 0], 12 * radius)]
	var p := _unchanged(f, api, intents)
	_safe(p, radius)
	var before: Dictionary = f.state.to_dict()
	f.repo.balance.cluster_motion_clearance_m += 1
	assert_eq(api.commit(f.repo, f.state, p).status, "error", "motion config belongs to frozen plan input")
	assert_eq(f.state.to_dict(), before)
	p = _unchanged(f, api, intents)
	assert_eq(api.commit(f.repo, f.state, p).status, "complete")
	assert_eq(UnitBodies.migrate_candidate(f.repo, f.state).status, "complete")

func test_three_distinct_unit_crossing_and_prior_cursor_rejection() -> void:
	var api := _api()
	if api == null: return
	var points := [[-100, 0], [100, 0], [0, -100]]
	var targets := [[100, 0], [-100, 0], [0, 100]]
	var f := _unit_fixture(points)
	var intents: Array = []
	for i: int in 3:
		intents.append({"unit": f.codes[i], "slot": 0, "path_m": [points[i], targets[i]], "budget_m": 400, "hostile": false})
	var p := _unchanged(f, api, intents)
	_safe(p)
	intents.reverse()
	assert_eq(api.plan(f.repo, f.state, intents, 70, 0), p)
	assert_eq(api.commit(f.repo, f.state, p).status, "complete")
	var next: Dictionary = api.plan(f.repo, f.state, [], 71, 0)
	assert_eq(api.commit(f.repo, f.state, next).status, "complete")
	var before: Dictionary = f.state.to_dict()
	assert_eq(api.commit(f.repo, f.state, p).status, "error", "older saved cursor cannot move again")
	assert_eq(f.state.to_dict(), before)

func test_malformed_receipt_cannot_masquerade_as_saved_success() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([[0, 0]])
	var p := _unchanged(f, api, [_intent(f, 0, [20, 0])])
	assert_eq(api.commit(f.repo, f.state, p).status, "complete")
	f.state.military_migration.body_motion.receipt = "z".repeat(64)
	assert_true(_unchanged(f, api, []).cursor.is_empty())
	var before: Dictionary = f.state.to_dict()
	assert_eq(api.commit(f.repo, f.state, p).status, "error")
	assert_eq(f.state.to_dict(), before)

func test_distance_rounding_cannot_spend_one_metre_less_than_exact_length() -> void:
	var api := _api()
	if api == null: return
	var f := _fixture([[0, 0]])
	# sqrt(2^52 + 1) rounds to 2^26 in double precision, but exact ceil is 2^26 + 1.
	var limit := 67108864
	var p := _unchanged(f, api, [_intent(f, 0, [limit, 1], limit)])
	assert_ne(p.moves[0].path_m.back(), [limit, 1], "actual segment exceeds the budget despite rounded sqrt")
	for i: int in range(1, p.moves[0].path_m.size()):
		var a: Array = p.moves[0].path_m[i - 1]
		var b: Array = p.moves[0].path_m[i]
		var x: int = int(b[0]) - int(a[0])
		var y: int = int(b[1]) - int(a[1])
		assert_true(x * x + y * y <= limit * limit, "integer squared distance independently proves the budget")
