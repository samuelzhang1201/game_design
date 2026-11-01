extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func after_each() -> void:
	MarchPath.forget()

func _api() -> GDScript:
	var path := "res://scripts/engine/body_motion.gd"
	assert_true(FileAccess.file_exists(path), "CF03 candidate planner exists")
	return load(path) if FileAccess.file_exists(path) else null

func test_candidate_api_exists() -> void:
	var api := _api()
	if api == null: return
	assert_true(api.has_method("plan"))
	assert_true(api.has_method("commit"))

func test_locomotion_candidate_api_exists() -> void:
	var api := _api()
	for method: String in ["plan_locomotion_candidate", "commit_locomotion_candidate", "sample_locomotion_candidate"]:
		assert_true(api.has_method(method), method)

func test_locomotion_integer_heading_bins() -> void:
	var api := _api()
	assert_true(api.has_method("_locomotion_heading"))
	if not api.has_method("_locomotion_heading"): return
	for item: Array in [[1, 0, 0], [0, 1, 90000000], [-1, 0, 180000000], [0, -1, 270000000],
		[1, 1, 45000000], [3, 4, 53130102], [3, -4, 306869898], [67108864, 1, 1],
		[67108864, -1, 359999999], [1, 67108864, 89999999], [67108864, 67108863, 45000000],
		[38197186, 1, 2], [38197187, 1, 1], [57295779, 57295778, 44999999],
		[57295780, 57295779, 44999999], [57295781, 57295780, 45000000]]:
		assert_eq(api.call("_locomotion_heading", item[0], item[1]), item[2], str(item))
	assert_eq(api.call("_locomotion_heading", 0, 0), -1)
	assert_eq(api.call("_locomotion_heading", BodyMotion.INT_MIN, 1), -1)
	assert_eq(BodyMotion._Nat.integer(BodyMotion._Nat.of(BodyMotion.INT_MAX)), BodyMotion.INT_MAX)
	assert_eq(BodyMotion._Nat.integer([32767, 32767, 32767, 32767, 32767]), -1, "checked limb conversion cannot wrap")
	var grid := MarchPath.new()
	grid.cols = 4294967296
	grid.rows = 4294967296
	assert_false(BodyMotion._loco_grid_ok(grid), "grid shape products cannot wrap to an empty valid grid")

func _loco_fixture(points: Array = [[100, 100]]) -> Dictionary:
	var f := _fixture(points)
	var piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
	# An explicit test certificate is not installed arm support or art acceptance.
	f.repo.unit_footprints[piece].locomotion_certificate = {"digest": "a".repeat(64),
		"turn_q": 400000, "contact_um": 100, "radius_m": 10,
		"clips": ["PIVOT_LEFT", "PIVOT_RIGHT", "MARCH"], "all_turns": true}
	f.repo.balance["body_locomotion_" + piece + "_turn_q"] = 400000
	f.repo.balance["body_locomotion_" + piece + "_contact_um"] = 100
	f.repo.balance.army_march_grid_px = 1
	var slopes := PackedByteArray()
	slopes.resize(10000)
	f.grid = MarchPath.build(f.repo, 100, 100, 10, slopes)
	MarchPath.use(f.repo, f.grid)
	return f

func _loco_plan(f: Dictionary, intents: Array, day: int = 70, substep: int = 0) -> Dictionary:
	var before: Dictionary = f.state.to_dict()
	var out: Dictionary = _api().call("plan_locomotion_candidate", f.repo, f.state, intents, day, substep)
	assert_eq(f.state.to_dict(), before, "plan preserves entire source, including RNG")
	return out

func _loco_ready() -> bool:
	return _api().has_method("plan_locomotion_candidate")

func test_locomotion_hand_computed_l_shared_time() -> void:
	if not _loco_ready(): return
	for budget: int in [10, 8, 20]:
		var f := _loco_fixture()
		var intent := _intent(f, 0, [103, 100], budget)
		intent.path_m.append([103, 104])
		var p := _loco_plan(f, [intent])
		assert_eq(p.get("version"), 2, str(p))
		if not p.has("version"): continue
		var move: Dictionary = p.moves[0]
		if budget == 8:
			assert_ne(move.end, [103, 104], "1075000 quanta cannot fit")
			assert_eq(move.ops.back().t1_q, 1000000)
			continue
		assert_eq(move.used_m, 7)
		assert_eq(move.end, [103, 104])
		var endpoints: Array = [300000, 400000, 800000, 900000, 1000000] if budget == 10 else [150000, 250000, 450000, 550000, 1000000]
		assert_eq(move.ops.map(func(op: Dictionary) -> int: return int(op.t1_q)), endpoints)
		assert_eq(move.ops.map(func(op: Dictionary) -> String: return op.kind), ["move", "pivot", "move", "pivot", "hold"])
		if budget == 10:
			for example: Array in [[350000, 103.0, 100.0, 45000000.0, "pivot"], [500000, 103.0, 101.0, 90000000.0, "move"], [850000, 103.0, 104.0, 45000000.0, "pivot"]]:
				var sample: Dictionary = _api().call("sample_locomotion_candidate", {"version": 2, "moves": [move]}, example[0])
				assert_eq(sample.get("status"), "complete", str(sample))
				if sample.get("rows", []).is_empty(): continue
				assert_eq(sample.rows[0].x_m, example[1])
				assert_eq(sample.rows[0].y_m, example[2])
				assert_eq(sample.rows[0].yaw_udeg, example[3])
				assert_eq(sample.rows[0].kind, example[4])

func test_locomotion_commit_json_detached_retry_and_tampering() -> void:
	if not _loco_ready(): return
	var f := _loco_fixture()
	var intent := _intent(f, 0, [103, 104], 10)
	var p := _loco_plan(f, [intent])
	assert_eq(p, _loco_plan(f, JSON.parse_string(JSON.stringify([intent]))))
	var before: Dictionary = f.state.to_dict()
	var result: Dictionary = _api().call("commit_locomotion_candidate", f.repo, f.state, p)
	assert_eq(result.get("status"), "complete", str(result))
	assert_eq(f.state.to_dict(), before, "v2 commit returns detached candidate")
	if result.get("candidate") == null: return
	var state: GameState = result.candidate
	var after := state.to_dict()
	var conserved := after.duplicate(true)
	conserved.regiments[f.code].body_groups = before.regiments[f.code].body_groups.duplicate(true)
	conserved.military_migration = before.military_migration.duplicate(true)
	assert_eq(conserved, before, "only body poses/path and motion control change; all costs, people, anchors and RNG are conserved")
	var old_row: Dictionary = f.state.regiments[f.code].body_groups[0].duplicate(true)
	var new_row: Dictionary = state.regiments[f.code].body_groups[0].duplicate(true)
	for key: String in ["x_m", "y_m", "facing_deg", "path_m"]:
		old_row.erase(key)
		new_row.erase(key)
	assert_eq(new_row, old_row, "body identity, count, home and role are conserved")
	assert_eq(state.military_migration.body_motion.version, "2")
	assert_eq(state.military_migration.body_motion.receipt, BodyMotion._hash(p))
	for restored: GameState in [state, _json(state)]:
		var retry: Dictionary = _api().call("commit_locomotion_candidate", f.repo, restored, JSON.parse_string(JSON.stringify(p)))
		assert_eq(retry.get("status"), "complete", str(retry))
		if retry.get("candidate") != null:
			assert_ne(retry.candidate, restored)
			assert_eq(retry.candidate.to_dict(), after)
	for field: String in ["duration", "gap", "turn", "tangent", "end", "used", "extra", "version", "basis", "policy", "bool", "null"]:
		var bad := p.duplicate(true)
		match field:
			"duration": bad.moves[0].ops[0].t1_q = 0
			"gap": bad.moves[0].ops[0].t0_q = 1
			"turn": bad.moves[0].ops[0].turn_udeg = -180000000
			"tangent": bad.moves[0].ops[0].yaw0_udeg += 1
			"end": bad.moves[0].end[0] += 1
			"used": bad.moves[0].used_m += 1
			"extra": bad.moves[0].hidden = true
			"version": bad.version = 3
			"basis": bad.cursor.basis = "b".repeat(64)
			"policy": bad.policy_digest = "b".repeat(64)
			"bool": bad.moves[0].slot = true
			"null": bad.moves[0].budget_m = null
		var rejected: Dictionary = _api().call("commit_locomotion_candidate", f.repo, f.state, bad)
		assert_eq(rejected.get("status"), "error", field)
		assert_eq(f.state.to_dict(), before)
		assert_eq(_api().call("commit_locomotion_candidate", f.repo, state, bad).status, "error", "same-cursor tamper: " + field)

func test_locomotion_sampler_is_readonly_and_closed() -> void:
	if not _loco_ready(): return
	var f := _loco_fixture()
	var p := _loco_plan(f, [_intent(f, 0, [103, 100], 10)])
	var projected := {"version": 2, "moves": p.moves.duplicate(true)}
	var before := projected.duplicate(true)
	for t: int in [0, 299999, 300000, 1000000]:
		var sample: Dictionary = _api().call("sample_locomotion_candidate", projected, t)
		assert_eq(sample.status, "complete", str(sample))
		assert_eq(projected, before)
	for t: int in [-1, 1000001]:
		var rejected: Dictionary = _api().call("sample_locomotion_candidate", projected, t)
		assert_eq(rejected.status, "error")
		assert_eq(rejected.rows, [])
	var malformed := projected.duplicate(true)
	malformed.moves[0].ops[0].t1_q = 0
	assert_eq(_api().call("sample_locomotion_candidate", malformed, 0).status, "error")
	malformed = projected.duplicate(true)
	malformed.moves.append(malformed.moves[0].duplicate(true))
	var duplicate: Dictionary = _api().call("sample_locomotion_candidate", malformed, 0)
	assert_eq(duplicate.status, "error")
	assert_eq(duplicate.rows, [], "no partial row publication")
	assert_eq(_api().call("sample_locomotion_candidate", {"version": 3, "moves": []}, 0).status, "error", "empty arrays still validate version")
	assert_eq(_api().call("sample_locomotion_candidate", {"version": 2, "moves": []}, 0).rows, [])

func test_locomotion_wrap_ties_stationary_and_duplicate_legs() -> void:
	if not _loco_ready(): return
	assert_eq(BodyMotion._loco_turn(359000000, 1000000), 2000000)
	assert_eq(BodyMotion._loco_turn(1000000, 359000000), -2000000)
	assert_eq(BodyMotion._loco_turn(0, 180000000), 180000000)
	assert_eq(BodyMotion._loco_turn(180000000, 0), 180000000)
	assert_eq(BodyMotion._loco_duration(2000000, 400000, 360000000), 2223)
	assert_eq(BodyMotion._loco_duration(180000000, 400000, 360000000), 200000)
	assert_eq(BodyMotion._loco_duration(180000000, BodyMotion.INT_MAX, 360000000), -1)
	var f := _loco_fixture()
	var intent := _intent(f, 0, [100, 100], 0)
	intent.path_m.append([100, 100])
	var p := _loco_plan(f, [intent])
	assert_eq(p.moves[0].ops, [{"kind": "hold", "t0_q": 0, "t1_q": 1000000,
		"a": [100, 100], "b": [100, 100], "yaw0_udeg": 0, "turn_udeg": 0}])
	var body := {"unit": "test", "slot": 0, "start": [-100, -100], "start_yaw_udeg": 0, "final_facing_deg": 0, "budget_m": 10}
	var move := BodyMotion._loco_timeline(body, [[-100, -100], [-100, -100], [-97, -96]], 400000)
	assert_true(BodyMotion._loco_move_ok(move))
	assert_eq(move.ops[0].turn_udeg, 53130102)
	assert_eq(move.ops[1].t1_q - move.ops[1].t0_q, 500000)

func test_locomotion_pivot_occupancy_and_unequal_three_way() -> void:
	if not _loco_ready(): return
	var a := {"radius": 1, "budget_m": 0}
	var b := {"radius": 1, "budget_m": 6}
	var stationary: Array[Dictionary] = [{"a": [0, 0], "b": [0, 0], "t0": 0.3, "t1": 0.4}]
	var crossing: Array[Dictionary] = [{"a": [-3, 0], "b": [3, 0], "t0": 0.3, "t1": 0.4}]
	assert_true(BodyMotion._sweep_collision(a, stationary, b, crossing), "stationary pivot occupies its full interval")
	var tangent: Array[Dictionary] = [{"a": [-3, 2], "b": [3, 2], "t0": 0.3, "t1": 0.4}]
	assert_false(BodyMotion._sweep_collision(a, stationary, b, tangent), "exact constant-axis tangency remains legal")
	var f := _loco_fixture([[100, 200], [300, 200], [200, 100]])
	var intents: Array = [_intent(f, 0, [300, 200], 400), _intent(f, 1, [100, 200], 200), _intent(f, 2, [200, 300], 300)]
	var p := _loco_plan(f, intents)
	assert_eq(p.get("version"), 2, str(p))
	if not p.has("version"): return
	assert_eq(p.moves.size(), 3)
	intents.reverse()
	assert_eq(_loco_plan(f, intents), p)
	for i: int in p.moves.size():
		for j: int in range(i + 1, p.moves.size()):
			for time: int in 101:
				var pa := _loco_test_position(p.moves[i], time * 10000)
				var pb := _loco_test_position(p.moves[j], time * 10000)
				assert_true(pa.distance_to(pb) >= 20.0 - 0.000001)

func _loco_test_position(move: Dictionary, time: int) -> Vector2:
	for op: Dictionary in move.ops:
		if time < int(op.t1_q):
			var ratio := float(time - int(op.t0_q)) / float(int(op.t1_q) - int(op.t0_q))
			return Vector2(op.a[0], op.a[1]).lerp(Vector2(op.b[0], op.b[1]), ratio)
	return Vector2(move.end[0], move.end[1])

func test_locomotion_closed_terrain_and_stale_input_retry() -> void:
	if not _loco_ready(): return
	var f := _loco_fixture()
	f.grid.closed[10 * f.grid.cols + 12] = 1
	var p := _loco_plan(f, [_intent(f, 0, [130, 100], 100)])
	assert_eq(p.get("version"), 2, str(p))
	if not p.has("version"): return
	for move: Dictionary in p.moves:
		assert_eq(ArmySystem._body_path_terrain(f.grid, BodyMotion._loco_path(move), 10), "")
	var before: Dictionary = f.state.to_dict()
	f.grid.closed[10 * f.grid.cols + 12] = 0
	assert_eq(_api().call("commit_locomotion_candidate", f.repo, f.state, p).status, "error", "terrain is frozen input")
	assert_eq(f.state.to_dict(), before)
	p = _loco_plan(f, [_intent(f, 0, [103, 100], 10)])
	var result: Dictionary = _api().call("commit_locomotion_candidate", f.repo, f.state, p)
	assert_eq(result.status, "complete", str(result))
	if result.get("candidate") == null: return
	var state: GameState = result.candidate
	for kind: String in ["supplies", "rng", "owner", "pose", "policy"]:
		var changed := UnitBodies._copy(state)
		var piece := MapObjects.army_piece(f.repo, state.army_roster[f.code])
		match kind:
			"supplies": changed.regiments[f.code].supplies += 1
			"rng": changed.rng.randi_range(0, 100)
			"owner": changed.army_roster[f.code].kingdom_code = "fixture:other"
			"pose": changed.regiments[f.code].body_groups[0].x_m += 1
			"policy": f.repo.unit_footprints[piece].locomotion_certificate.digest = "b".repeat(64)
		before = changed.to_dict()
		assert_eq(_api().call("commit_locomotion_candidate", f.repo, changed, p).status, "error", kind)
		assert_eq(changed.to_dict(), before)
		f.repo.unit_footprints[piece].locomotion_certificate.digest = "a".repeat(64)

func test_locomotion_unsupported_and_raw_schema_fail_closed() -> void:
	if not _loco_ready(): return
	var f := _loco_fixture()
	var intent := _intent(f, 0, [103, 100], 10)
	for value: Variant in [-1, true, null, "10", 0.25, INF, 9007199254740992]:
		var bad := intent.duplicate(true)
		bad.budget_m = value
		assert_true(_loco_plan(f, [bad]).cursor.is_empty(), str(value))
	assert_true(_loco_plan(f, [intent, intent]).cursor.is_empty())
	var piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
	var certificate: Dictionary = f.repo.unit_footprints[piece].locomotion_certificate.duplicate(true)
	for field: String in ["digest", "radius_m", "turn_q", "clips", "all_turns", "contact_um"]:
		var bad := certificate.duplicate(true)
		match field:
			"digest": bad.digest = "invalid"
			"radius_m": bad.radius_m -= 1
			"turn_q": bad.turn_q = BodyMotion.INT_MAX
			"clips": bad.clips = ["MARCH"]
			"all_turns": bad.all_turns = false
			"contact_um": bad.contact_um = 0
		f.repo.unit_footprints[piece].locomotion_certificate = bad
		assert_true(_loco_plan(f, [intent]).cursor.is_empty(), field)
	f.repo.unit_footprints[piece].locomotion_certificate = certificate
	for field: String in ["clips", "all_turns"]:
		for value: Variant in [0.25, "true", null, [], {}]:
			var bad := certificate.duplicate(true)
			bad[field] = value
			f.repo.unit_footprints[piece].locomotion_certificate = bad
			assert_true(_loco_plan(f, [intent]).cursor.is_empty(), field + " " + str(value))
	f.repo.unit_footprints[piece].locomotion_certificate = certificate
	var p := _loco_plan(f, [intent])
	for field: String in ["version", "cursor", "policy_digest", "moves", "reasons"]:
		var bad := p.duplicate(true)
		bad.erase(field)
		assert_eq(_api().call("commit_locomotion_candidate", f.repo, f.state, bad).status, "error")
	for control: Variant in [{}, null, {"version": "3"}, {"version": 2}]:
		var changed := UnitBodies._copy(f.state)
		changed.military_migration.body_motion = control
		var before := changed.to_dict()
		assert_eq(_api().call("commit_locomotion_candidate", f.repo, changed, p).status, "error")
		assert_eq(changed.to_dict(), before)

func test_locomotion_complete_schema_and_loaded_fractional_control() -> void:
	if not _loco_ready(): return
	var f := _loco_fixture()
	var intent := _intent(f, 0, [103, 104], 10)
	var p := _loco_plan(f, [intent])
	for layer: String in ["move", "op", "cursor"]:
		var source: Dictionary = p.moves[0] if layer == "move" else (p.moves[0].ops[0] if layer == "op" else p.cursor)
		for key: String in source:
			var bad := p.duplicate(true)
			var target: Dictionary = bad.moves[0] if layer == "move" else (bad.moves[0].ops[0] if layer == "op" else bad.cursor)
			target.erase(key)
			assert_eq(_api().call("commit_locomotion_candidate", f.repo, f.state, bad).status, "error", layer + " missing " + key)
	for value: Variant in [true, null, 0.1, INF, NAN, "1", 9007199254740992]:
		for field: String in ["slot", "budget_m", "used_m", "start_yaw_udeg", "final_facing_deg"]:
			var bad := p.duplicate(true)
			bad.moves[0][field] = value
			assert_eq(_api().call("commit_locomotion_candidate", f.repo, f.state, bad).status, "error", field + " " + str(value))
		for field: String in ["t0_q", "t1_q", "yaw0_udeg", "turn_udeg"]:
			var bad := p.duplicate(true)
			bad.moves[0].ops[0][field] = value
			assert_eq(_api().call("commit_locomotion_candidate", f.repo, f.state, bad).status, "error", field + " " + str(value))
	var result: Dictionary = _api().call("commit_locomotion_candidate", f.repo, f.state, p)
	if result.get("candidate") == null:
		fail_test(str(result))
		return
	# Exercise the supported save path without unrelated legacy provenance.
	var state: GameState = result.candidate
	state.military_migration.erase("import_main_v7")
	var raw := state.to_dict()
	raw.military_migration.body_motion.plan.moves[0].ops[0].t0_q = 0.1
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(raw)), false)
	assert_false(BodyMotion._loco_saved_ok(loaded.military_migration.body_motion), "load must not round corrupt timeline fields into a valid receipt")
	var no_budget := _intent(f, 0, [103, 100], 0)
	assert_true(_loco_plan(f, [no_budget]).cursor.is_empty(), "zero budget cannot request movement")
	var future := p.duplicate(true)
	future.cursor.abs_day += 1
	assert_eq(_api().call("commit_locomotion_candidate", f.repo, f.state, future).status, "error", "cursor belongs in the source basis")

func test_locomotion_zero_fit_and_missing_current_schema() -> void:
	if not _loco_ready(): return
	var f := _loco_fixture([])
	var p := _loco_plan(f, [])
	assert_eq(p.get("version"), 2, str(p))
	assert_eq(p.moves, [])
	var result: Dictionary = _api().call("commit_locomotion_candidate", f.repo, f.state, p)
	assert_eq(result.status, "complete", str(result))
	f.state.military_migration.erase("body_version")
	assert_true(_loco_plan(f, []).cursor.is_empty(), "zero fit still requires explicit current schema")
	assert_eq(_api().call("commit_locomotion_candidate", f.repo, f.state, p).status, "error")

func test_locomotion_cannot_convert_frozen_v1_boundary() -> void:
	if not _loco_ready(): return
	var f := _loco_fixture()
	var tx := DayResolution.begin(f.state.day, false, f.state.absolute_day())
	tx.phase = "FIXED_TACTICAL_SUBSTEPS"
	tx.phase_cursor = DayResolution.PHASES.find(tx.phase)
	tx.march_entries = {}
	tx.march_budgets = {}
	tx.marching_codes = []
	tx.body_march = {"version": "1", "abs_day": str(f.state.absolute_day()), "next_substep": "0", "substep_count": "10", "last": {}}
	f.state.day_resolution = tx
	var boundary := {"version": 1, "abs_day": f.state.absolute_day(), "substep": 0}
	var before: Dictionary = f.state.to_dict()
	var p := BodyMotion.plan_locomotion_candidate(f.repo, f.state, [_intent(f, 0, [103, 100], 10)], int(boundary.abs_day), 0, boundary)
	assert_true(p.cursor.is_empty(), "a frozen v1 day never acquires v2 timing")
	assert_eq(f.state.to_dict(), before)

func test_locomotion_hostile_opposing_and_corrupt_owner_counts() -> void:
	if not _loco_ready(): return
	var f := _loco_fixture([[100, 100], [300, 100]])
	var intents := [_intent(f, 0, [300, 100], 400, true), _intent(f, 1, [100, 100], 400, true)]
	var p := _loco_plan(f, intents)
	assert_eq(p.get("version"), 2, str(p))
	if not p.has("version"): return
	for move: Dictionary in p.moves:
		for point: Array in BodyMotion._loco_path(move): assert_eq(point[1], 100, "hostile intent cannot grant a friendly sidestep")
	for kind: String in ["count", "reuse", "duplicate", "version", "missing"]:
		var changed := UnitBodies._copy(f.state)
		match kind:
			"count": changed.regiments[f.code].body_groups[0].count -= 1
			"reuse": changed.regiments[f.code].group_next_slot = 1
			"duplicate": changed.regiments[f.code].body_groups[1].slot = 0
			"version": changed.military_migration.body_version = 2
			"missing": changed.regiments[f.code].erase("body_groups")
		var before := changed.to_dict()
		assert_true(BodyMotion.plan_locomotion_candidate(f.repo, changed, intents, 70, 0).cursor.is_empty(), kind)
		assert_eq(BodyMotion.commit_locomotion_candidate(f.repo, changed, p).status, "error", kind)
		assert_eq(changed.to_dict(), before)

func test_locomotion_json_control_both_loader_branches_and_forged_pivot() -> void:
	if not _loco_ready(): return
	for imported: bool in [false, true]:
		var f := _loco_fixture()
		if imported: f.state.military_migration.import_main_v7 = {}
		else: f.state.military_migration.erase("import_main_v7")
		var p := _loco_plan(f, [_intent(f, 0, [103, 104], 10)])
		var committed := BodyMotion.commit_locomotion_candidate(f.repo, f.state, p)
		assert_eq(committed.status, "complete", str(committed))
		if not committed.has("candidate"): continue
		var state: GameState = committed.candidate
		var restored := _json(state)
		assert_true(BodyMotion._loco_saved_ok(restored.military_migration.body_motion))
		assert_eq(BodyMotion.commit_locomotion_candidate(f.repo, restored, p).status, "complete", "supported JSON provenance branch")
		for value: Variant in [0.1, "i0", true, null, "0", 9007199254740992]:
			var raw := state.to_dict()
			raw.military_migration.body_motion.plan.moves[0].ops[0].t0_q = value
			var original := JSON.stringify(raw)
			var bad := GameState.from_dict(JSON.parse_string(original), false)
			assert_eq(JSON.stringify(raw), original, "loader never changes source JSON")
			assert_false(BodyMotion._loco_saved_ok(bad.military_migration.body_motion), str(value))
			var before := bad.to_dict()
			assert_eq(BodyMotion.commit_locomotion_candidate(f.repo, bad, p).status, "error")
			assert_eq(bad.to_dict(), before)
		for field: String in ["abs_day", "substep", "version"]:
			var raw := state.to_dict()
			raw.military_migration.body_motion[field] = 2
			var bad := GameState.from_dict(JSON.parse_string(JSON.stringify(raw)), false)
			assert_false(BodyMotion._loco_saved_ok(bad.military_migration.body_motion), field)
		var forged := p.duplicate(true)
		for i: int in forged.moves[0].ops.size():
			var op: Dictionary = forged.moves[0].ops[i]
			if i > 0: op.t0_q += 1
			if i < forged.moves[0].ops.size() - 1: op.t1_q += 1
		var bad := UnitBodies._copy(state)
		bad.military_migration.body_motion.plan = forged.duplicate(true)
		bad.military_migration.body_motion.receipt = BodyMotion._hash(forged)
		bad = _json(bad)
		var before := bad.to_dict()
		assert_eq(BodyMotion.commit_locomotion_candidate(f.repo, bad, forged).status, "error", "rehashing a forged pivot cannot bypass certified timing")
		var successor := BodyMotion.plan_locomotion_candidate(f.repo, bad, [], 70, 1)
		assert_true(successor.cursor.is_empty(), "successor validates the saved certified timing and sweep")
		if successor.has("version"):
			assert_eq(BodyMotion.commit_locomotion_candidate(f.repo, bad, successor).status, "error", "successor cannot replace a forged old control")
		assert_eq(bad.to_dict(), before)

func test_locomotion_saved_heading_binds_row_on_retry_and_successor() -> void:
	if not _loco_ready(): return
	for imported: bool in [false, true]:
		var f := _loco_fixture()
		if imported: f.state.military_migration.import_main_v7 = {}
		else: f.state.military_migration.erase("import_main_v7")
		var p := _loco_plan(f, [_intent(f, 0, [103, 104], 10)])
		var result := BodyMotion.commit_locomotion_candidate(f.repo, f.state, p)
		assert_eq(result.status, "complete", str(result))
		if not result.has("candidate"): continue
		var state: GameState = result.candidate
		var next := BodyMotion.plan_locomotion_candidate(f.repo, state, [], 70, 1)
		assert_eq(next.get("version"), 2)
		var clean := state.to_dict()
		var advanced := BodyMotion.commit_locomotion_candidate(f.repo, state, next)
		assert_eq(advanced.status, "complete", "valid successor remains executable")
		if advanced.has("candidate"):
			assert_eq(advanced.candidate.military_migration.body_motion.substep, "1")
		assert_eq(state.to_dict(), clean, "successor is detached")
		# Removing the first pivot keeps positions, speeds and remaining turns legal.
		var skipped := p.duplicate(true)
		skipped.moves[0].start_yaw_udeg = 53130102
		skipped.moves[0].ops.pop_front()
		for op: Dictionary in skipped.moves[0].ops:
			op.t0_q -= 59034
			op.t1_q -= 59034
		skipped.moves[0].ops.back().t1_q = 1000000
		var rejected := BodyMotion.sample_locomotion_candidate({"version": 2, "moves": skipped.moves}, 0)
		assert_eq(rejected.status, "error")
		assert_eq(rejected.rows, [])
		# Also make both claimed headings agree, while the actual row still faces 0.
		var wrong_row := p.duplicate(true)
		var move: Dictionary = wrong_row.moves[0]
		move.start_yaw_udeg = 90000000
		move.final_facing_deg = 90
		move.ops[0].yaw0_udeg = 90000000
		move.ops[0].turn_udeg = -36869898
		move.ops[0].t1_q = 40967
		move.ops[1].t0_q = 40967
		move.ops[1].t1_q = 540967
		move.ops[2].t0_q = 540967
		move.ops[2].t1_q = 581934
		move.ops[2].turn_udeg = 36869898
		move.ops[3].t0_q = 581934
		move.ops[3].yaw0_udeg = 90000000
		assert_true(BodyMotion._loco_plan_ok(wrong_row), "self-consistent timeline still needs source-row admission")
		for forged: Dictionary in [skipped, wrong_row]:
			var bad := UnitBodies._copy(state)
			bad.military_migration.body_motion.plan = forged.duplicate(true)
			bad.military_migration.body_motion.receipt = BodyMotion._hash(forged)
			bad = _json(bad)
			var before := bad.to_dict()
			assert_eq(BodyMotion.commit_locomotion_candidate(f.repo, bad, forged).status, "error", "rehashed heading cannot bypass original facing")
			assert_true(BodyMotion.plan_locomotion_candidate(f.repo, bad, [], 70, 1).cursor.is_empty(), "successor cannot admit a bad saved heading")
			assert_eq(BodyMotion.commit_locomotion_candidate(f.repo, bad, next).status, "error")
			assert_eq(bad.to_dict(), before, "all failures preserve complete source and RNG")

func test_locomotion_saved_sweep_cannot_be_bypassed_by_successor() -> void:
	if not _loco_ready(): return
	for imported: bool in [false, true]:
		var f := _loco_fixture([[100, 200], [200, 100]])
		if imported: f.state.military_migration.import_main_v7 = {}
		else: f.state.military_migration.erase("import_main_v7")
		var p := _loco_plan(f, [_intent(f, 0, [300, 200], 400), _intent(f, 1, [200, 300], 400)])
		assert_eq(p.moves[0].end, [300, 200])
		assert_eq(p.moves[1].end, [200, 300])
		var result := BodyMotion.commit_locomotion_candidate(f.repo, f.state, p)
		assert_eq(result.status, "complete", str(result))
		if not result.has("candidate"): continue
		var state: GameState = result.candidate
		var forged := p.duplicate(true)
		var move: Dictionary = forged.moves[0]
		assert_eq(move.ops[0].kind, "move")
		assert_eq(move.ops[0].t1_q, 500000)
		move.ops[0].t0_q = 100000
		move.ops[0].t1_q = 600000
		move.ops[1].t0_q = 600000
		move.ops.push_front({"kind": "hold", "t0_q": 0, "t1_q": 100000,
			"a": [100, 200], "b": [100, 200], "yaw0_udeg": 0, "turn_udeg": 0})
		# All move/pivot durations and geometry remain unchanged; both now hit (200,200) at350000.
		assert_true(BodyMotion._loco_plan_ok(forged))
		assert_eq(_loco_test_position(forged.moves[0], 350000), Vector2(200, 200))
		assert_eq(_loco_test_position(forged.moves[1], 350000), Vector2(200, 200))
		state.military_migration.body_motion.plan = forged.duplicate(true)
		state.military_migration.body_motion.receipt = BodyMotion._hash(forged)
		state = _json(state)
		var before := state.to_dict()
		assert_eq(BodyMotion.commit_locomotion_candidate(f.repo, state, forged).status, "error")
		var successor := BodyMotion.plan_locomotion_candidate(f.repo, state, [], 70, 1)
		assert_true(successor.cursor.is_empty(), "successor validates the saved continuous sweep")
		if successor.has("version"):
			assert_eq(BodyMotion.commit_locomotion_candidate(f.repo, state, successor).status, "error")
		assert_eq(state.to_dict(), before)

func test_locomotion_saved_plan_links_requests_and_stationary_rows() -> void:
	if not _loco_ready(): return
	var f := _loco_fixture()
	var p := _loco_plan(f, [_intent(f, 0, [103, 104], 10)])
	var result := BodyMotion.commit_locomotion_candidate(f.repo, f.state, p)
	assert_eq(result.status, "complete")
	if not result.has("candidate"): return
	var state: GameState = result.candidate
	var faster := p.duplicate(true)
	var move: Dictionary = faster.moves[0]
	move.budget_m = 20
	move.ops[1].t1_q = 309034
	move.ops[2].t0_q = 309034
	move.ops[2].t1_q = 368068
	move.ops[3].t0_q = 368068
	assert_true(BodyMotion._loco_move_ok(move), "speed is internally consistent but exceeds the recorded request budget")
	var wrong_start := p.duplicate(true)
	wrong_start.cursor.intents[0].path_m[0][0] += 1
	var unrequested := p.duplicate(true)
	unrequested.cursor.intents = []
	for forged: Dictionary in [faster, wrong_start, unrequested]:
		assert_false(BodyMotion._loco_plan_ok(forged), "full plan must link movements to their requests")
		var bad := UnitBodies._copy(state)
		bad.military_migration.body_motion.plan = forged.duplicate(true)
		bad.military_migration.body_motion.receipt = BodyMotion._hash(forged)
		bad = _json(bad)
		var before := bad.to_dict()
		assert_eq(BodyMotion.commit_locomotion_candidate(f.repo, bad, forged).status, "error")
		assert_true(BodyMotion.plan_locomotion_candidate(f.repo, bad, [], 70, 1).cursor.is_empty())
		assert_eq(bad.to_dict(), before)
	var stationary: Dictionary = p.moves[0].duplicate(true)
	stationary.end = stationary.start.duplicate()
	stationary.used_m = 0
	stationary.ops = [
		{"kind": "pivot", "t0_q": 0, "t1_q": 100000, "a": [100, 100], "b": [100, 100], "yaw0_udeg": 0, "turn_udeg": 90000000},
		{"kind": "pivot", "t0_q": 100000, "t1_q": 200000, "a": [100, 100], "b": [100, 100], "yaw0_udeg": 90000000, "turn_udeg": -90000000},
		{"kind": "hold", "t0_q": 200000, "t1_q": 1000000, "a": [100, 100], "b": [100, 100], "yaw0_udeg": 0, "turn_udeg": 0}]
	assert_false(BodyMotion._loco_move_ok(stationary), "an entirely stationary row has one full-slice hold")
	stationary.budget_m = 0
	stationary.ops = [{"kind": "hold", "t0_q": 0, "t1_q": 1000000,
		"a": [100, 100], "b": [100, 100], "yaw0_udeg": 0, "turn_udeg": 0}]
	var no_budget := p.duplicate(true)
	no_budget.moves[0] = stationary
	no_budget.cursor.intents[0].budget_m = 0
	no_budget.cursor.priority = []
	assert_false(BodyMotion._loco_plan_ok(no_budget), "a saved zero-budget request cannot ask for translation")

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

func test_real_frozen_boundary_plan_commit_and_json_retry() -> void:
	var f := _fixture([[0, 0]])
	var tx := DayResolution.begin(f.state.day, false, f.state.absolute_day())
	tx.phase = "FIXED_TACTICAL_SUBSTEPS"
	tx.phase_cursor = DayResolution.PHASES.find(tx.phase)
	tx.march_entries = {}
	tx.march_budgets = {}
	tx.marching_codes = []
	tx.body_march = {"version": "1", "abs_day": str(f.state.absolute_day()), "next_substep": "0", "substep_count": "10", "last": {}}
	f.state.day_resolution = tx
	var boundary := {"version": 1, "abs_day": f.state.absolute_day(), "substep": 0}
	var intents := [_intent(f, 0, [20, 0])]
	var before: Dictionary = f.state.to_dict()
	assert_true(BodyMotion.plan(f.repo, f.state, intents, boundary.abs_day, 0).cursor.is_empty())
	var plan := BodyMotion.plan(f.repo, f.state, intents, boundary.abs_day, 0, boundary)
	assert_false(plan.cursor.is_empty(), str(plan.reasons))
	assert_eq(f.state.to_dict(), before)
	var bad := boundary.duplicate(true)
	bad.substep = 1
	assert_eq(BodyMotion.commit(f.repo, f.state, plan, bad).status, "error")
	assert_eq(f.state.to_dict(), before)
	assert_eq(BodyMotion.commit(f.repo, f.state, plan, boundary).status, "complete")
	assert_eq(f.state.day_resolution, tx, "inner commit retains exact frozen outer payload")
	assert_eq(f.state.regiments[f.code].body_groups[0].x_m, 20)
	var after: Dictionary = f.state.to_dict()
	assert_eq(BodyMotion.commit(f.repo, f.state, plan, boundary).status, "complete")
	var restored := _json(f.state)
	assert_eq(BodyMotion.commit(f.repo, restored, JSON.parse_string(JSON.stringify(plan)), boundary).status, "complete")
	assert_eq(restored.to_dict(), after)
	var tamper := plan.duplicate(true)
	tamper.moves[0].path_m.back()[0] += 1
	assert_eq(BodyMotion.commit(f.repo, restored, tamper, boundary).status, "error")
	assert_eq(restored.to_dict(), after)
