extends GutTest

var view: GDScript = load("res://scripts/map3d/map3d_candidate_bodies.gd")

func test_candidate_api_is_explicit_and_default_off() -> void:
	assert_true(view.has_method("sample_candidate"))
	assert_true(view.has_method("along_candidate"))
	assert_true(view.has_method("sample_locomotion_candidate"))
	assert_true(view.has_method("along_locomotion_candidate"))
	var layer := Map3DLayerUnits.new()
	autofree(layer)
	assert_true(layer.has_method("set_candidate_bodies"))

func test_l_path_uses_committed_budget_and_stationary_tail() -> void:
	if not view.has_method("along_candidate"): return
	var sample := {"mode": "bodies", "error": "", "unit": "unit", "moving": true,
		"cursor": {}, "key": [], "rows": [{"slot": 7, "home_slot": 0, "count": 1,
		"role": "front", "x_m": 3, "y_m": 4, "facing_deg": 90,
		"path_m": [[0, 0], [3, 0], [3, 4]], "budget_m": 7}]}
	var middle: Dictionary = view.call("along_candidate", sample, 0.5)
	assert_eq(middle.mode, "bodies")
	assert_eq(middle.rows[0].x_m, 3.0)
	assert_almost_eq(middle.rows[0].y_m, 0.5, 0.000000000001)
	sample.rows[0].budget_m = 10
	middle = view.call("along_candidate", sample, 0.5)
	assert_almost_eq(middle.rows[0].y_m, 2.0, 0.000000000001)
	for share: float in [0.7, 0.9, 1.0, 2.0]:
		var end: Dictionary = view.call("along_candidate", sample, share)
		assert_eq(end.rows[0].x_m, 3.0)
		assert_eq(end.rows[0].y_m, 4.0)
	for share: float in [NAN, INF, -INF]:
		assert_eq(view.call("along_candidate", sample, share).mode, "invalid")

var _contexts: Array[Map3DContext] = []

func after_each() -> void:
	for ctx: Map3DContext in _contexts:
		ctx.state_fn = Callable()
		ctx.day_fn = Callable()
		ctx.clock_fn = Callable()
	_contexts.clear()
	MarchPath.forget()

const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture(fit: int = 100, points: Array = []) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 319)
	var codes := state.regiments.keys()
	codes.sort()
	var code := String(codes[0])
	assert_false(Personnel.replace(repo, state, code, fit).has("error"))
	state.regiments = {code: state.regiments[code]}
	state.army_roster = {code: state.army_roster[code]}
	state.foes = {}
	state.battles = []
	state.military_rosters = {code: state.military_rosters[code]}
	var cohorts := {}
	for id: String in state.military_rosters[code].cohort_ids: cohorts[id] = state.military_cohorts[id]
	state.military_cohorts = cohorts
	state.military_migration.body_version = 1
	state.regiments[code].group_next_slot = ceili(float(fit) / 100)
	state.regiments[code].body_groups = []
	var i := 0
	for count: int in BattleGroups.counts(fit, 100):
		var point: Array = points[i] if i < points.size() else [i * 20000, 0]
		state.regiments[code].body_groups.append({"slot": i, "home_slot": i, "count": count,
			"role": "front", "x_m": point[0], "y_m": point[1], "facing_deg": 90, "path_m": []})
		i += 1
	var ctx := Map3DContext.new(repo, {"pack_origin": [-100, 50], "m_per_px": 2.0})
	ctx.state_fn = func() -> GameState: return state
	ctx.view_size = Vector2(2560, 1600)
	_contexts.append(ctx)
	return {"repo": repo, "state": state, "code": code, "ctx": ctx}

func _sample(f: Dictionary, envelope: Dictionary = {}) -> Dictionary:
	return view.call("sample_candidate", f.ctx, f.code, envelope)

func _commit(f: Dictionary, paths: Array, budgets: Array, substep: int = 0) -> Dictionary:
	var intents: Array = []
	for i: int in paths.size():
		intents.append({"unit": f.code, "slot": i, "path_m": paths[i], "budget_m": budgets[i], "hostile": false})
	var plan := BodyMotion.plan(f.repo, f.state, intents, f.state.absolute_day(), substep)
	assert_false(plan.cursor.is_empty(), str(plan.reasons))
	assert_eq(BodyMotion.commit(f.repo, f.state, plan).status, "complete")
	var cursor := {"version": 1, "abs_day": plan.cursor.abs_day, "substep": plan.cursor.substep,
		"receipt": BodyMotion._hash(plan)}
	var moves: Array = []
	for move: Dictionary in plan.moves: moves.append({"unit": move.unit, "slot": move.slot, "budget_m": move.budget_m})
	return {"cursor": cursor, "moves": moves}

func test_projection_counts_validation_and_detached_copy() -> void:
	for fit: int in [0, 1, 900, 901, 1000]:
		var f := _fixture(fit)
		var before: Dictionary = f.state.to_dict()
		var sampled := _sample(f)
		assert_eq(sampled.mode, "bodies")
		assert_eq(sampled.rows.size(), ceili(float(fit) / 100))
		if fit > 0: sampled.rows[0].path_m[0][0] = 99
		assert_eq(f.state.to_dict(), before)
	var f := _fixture()
	for field: String in ["slot", "home_slot", "count", "facing_deg", "role", "x_m"]:
		var row: Dictionary = f.state.regiments[f.code].body_groups[0]
		var old: Variant = row[field]
		row.erase(field)
		assert_eq(_sample(f).mode, "invalid", field)
		row[field] = old
	f.state.regiments[f.code].body_groups = []
	assert_eq(_sample(f).mode, "invalid", "positive fit cannot become empty")
	f.state.regiments[f.code].erase("body_groups")
	assert_eq(_sample(f).mode, "invalid", "initialized missing rows never guesses legacy")
	f.state.military_migration.erase("body_version")
	assert_eq(_sample(f).mode, "fallback")

func test_committed_timing_and_fractional_world_placement() -> void:
	var f := _fixture()
	var envelope := _commit(f, [[[0, 0], [3, 0], [3, 4]]], [7])
	var sampled := _sample(f, envelope)
	assert_eq(sampled.mode, "bodies")
	assert_true(sampled.moving)
	var along: Dictionary = view.call("along_candidate", sampled, 0.5)
	assert_almost_eq(along.rows[0].y_m, 0.5, 0.000000000001)
	var piece := Map3DBattleGroups.build(f.repo, ArmySystem.regiment(f.repo, f.code, f.state), along)
	add_child_autofree(piece.node)
	Map3DBattleGroups.place(f.ctx, piece, Vector2.ZERO, 1.6, false)
	var actual: Vector3 = piece.groups[0].piece.node.global_position
	var expected: Vector2 = f.ctx.to_world(Vector2(3, 0.5) / float(ArmySystem.metres_per_pack_px(f.repo)))
	assert_almost_eq(actual.z, expected.y, 0.00001)
	assert_ne(Vector2(actual.x, actual.z), f.ctx.to_world(Vector2(3, 0) / float(ArmySystem.metres_per_pack_px(f.repo))))
	assert_false(_sample(f).moving, "save receipt alone draws endpoint")
	assert_eq(_sample(f).rows[0].path_m, [[3, 4]])
	for field: String in ["version", "abs_day", "substep", "receipt"]:
		var bad := envelope.duplicate(true)
		bad.cursor[field] = "bad"
		assert_eq(_sample(f, bad).mode, "invalid", field)
	var duplicate := envelope.duplicate(true)
	duplicate.moves.append(duplicate.moves[0].duplicate())
	assert_eq(_sample(f, duplicate).mode, "invalid")
	assert_eq(_sample(f, {"cursor": envelope.cursor, "moves": []}).mode, "invalid")
	for raw: Variant in [null, {}, {"version": "2"}, 1.5]:
		f.state.military_migration.body_motion = raw
		assert_eq(_sample(f).mode, "invalid")

func test_sampler_malformed_and_degenerate_paths() -> void:
	var f := _fixture()
	var sampled := _sample(f)
	for path: Array in [[[0, 0]], [[0, 0], [0, 0]], [[-3, -4], [0, 0]]]:
		sampled.rows[0].path_m = path
		sampled.rows[0].budget_m = 10
		assert_eq(view.call("along_candidate", sampled, 1.0).rows[0].x_m, 0.0)
	for path: Variant in [[], [[0]], [[0, 0], [1.5, 0]], [[0, 0], [1, 1]], null]:
		sampled.rows[0].path_m = path
		assert_eq(view.call("along_candidate", sampled, 0.5).mode, "invalid")
	sampled.rows[0].path_m = [[-3, -4], [0, 0]]
	sampled.rows[0].budget_m = 0
	assert_eq(view.call("along_candidate", sampled, 0.5).mode, "invalid")

func _layer(f: Dictionary, envelope: Dictionary = {}) -> Map3DLayerUnits:
	var camera := Camera3D.new()
	add_child_autofree(camera)
	camera.position = Vector3(0, 10000, 10000)
	camera.look_at(Vector3.ZERO)
	f.ctx.camera = camera
	var layer := Map3DLayerUnits.new()
	add_child_autofree(layer)
	layer.bind(f.ctx)
	layer.set_candidate_bodies(true, envelope)
	layer.set_shown(true)
	return layer

func test_surviving_slot_nodes_phase_and_pose_across_transfer_and_attrition() -> void:
	var f := _fixture(901)
	var layer := _layer(f)
	var piece := layer.built_piece(f.code)
	assert_eq(piece.figures, 10)
	var survivor: Node3D = piece.groups[0].piece.node
	var anim: AnimationPlayer = piece.groups[0].piece.anims[0]
	anim.advance(0.123)
	var phase := anim.current_animation_position
	var pose := survivor.global_transform
	for suffix: String in ["-a", "-b"]:
		var other := String(f.code) + suffix
		f.state.army_roster[other] = f.state.army_roster[f.code].duplicate(true)
		f.state.regiments[other] = {"group_next_slot": 0}
	f.state.battles = [{"id": 7, "att": [f.code + "-a"], "def": [], "groups": {f.code + "-a": []}, "body_version": 1,
		"group_size_version": 2, "group_size_men": 100},
		{"id": 9, "att": [f.code + "-b"], "def": [], "groups": {f.code + "-b": []}, "body_version": 1,
		"group_size_version": 2, "group_size_men": 100}]
	f.state.day_resolution = DayResolution.begin(f.state.day, false, f.state.absolute_day())
	var frozen: Dictionary = f.state.to_dict()
	var deferred := UnitBodies.transfer_candidate(f.state, f.code, 0, 7)
	assert_eq(deferred.status, "deferred")
	assert_eq(f.state.to_dict(), frozen)
	layer.refresh()
	assert_same(layer.built_piece(f.code).groups[0].piece.node, survivor)
	assert_eq(anim.current_animation_position, phase)
	assert_eq(survivor.global_transform, pose)
	f.state.day_resolution = {}
	for pair: Array in [[0, 7], [7, 9], [9, 0]]:
		var transfer := UnitBodies.transfer_candidate(f.state, f.code, pair[0], pair[1])
		assert_eq(transfer.status, "complete", transfer.reason)
		if transfer.candidate == null: return
		f.state = transfer.candidate
		f.ctx.state_fn = func() -> GameState: return f.state
		layer.refresh()
		piece = layer.built_piece(f.code)
		assert_same(piece.groups[0].piece.node, survivor)
		assert_eq(anim.current_animation_position, phase)
		assert_eq(survivor.global_transform, pose)
	assert_false(Personnel.replace(f.repo, f.state, f.code, 900).has("error"))
	var reconciled := UnitBodies.reconcile_candidate(f.repo, f.state, f.code, 901)
	assert_eq(reconciled.status, "complete", reconciled.reason)
	f.state = reconciled.candidate
	layer.refresh()
	assert_eq(layer.built_piece(f.code).figures, 9)
	assert_same(layer.built_piece(f.code).groups[0].piece.node, survivor)
	assert_eq(anim.current_animation_position, phase)
	assert_eq(survivor.global_transform, pose)
	var single := _fixture(1)
	var last_layer := _layer(single)
	assert_eq(last_layer.built_piece(single.code).figures, 1)
	assert_false(Personnel.replace(single.repo, single.state, single.code, 0).has("error"))
	single.state = UnitBodies.reconcile_candidate(single.repo, single.state, single.code, 1).candidate
	single.ctx.state_fn = func() -> GameState: return single.state
	last_layer.refresh()
	assert_eq(last_layer.built_piece(single.code).figures, 0)
	assert_false(last_layer.screen_rects().has(single.code))

func test_committed_sweeps_dense_boundaries_retry_and_readonly_sampling() -> void:
	for paths: Array in [
		[[[-10000, 0], [10000, 0]], [[10000, 0], [-10000, 0]]],
		[[[-10000, 0], [10000, 0]], [[0, -10000], [0, 10000]], [[10000, 10000], [-10000, -10000]]],
		[[[0, 0], [5000, 0], [5000, 5000]], [[12000, 0], [12000, 12000]]]]:
		var points: Array = []
		var budgets: Array = []
		for path: Array in paths:
			points.append(path[0])
			budgets.append(40000)
		var f := _fixture(paths.size() * 100, points)
		var envelope := _commit(f, paths, budgets)
		var sampled := _sample(f, envelope)
		assert_eq(sampled.mode, "bodies")
		var before: Dictionary = f.state.to_dict()
		var radius := int(f.repo.unit_footprints[MapObjects.army_piece(f.repo, f.state.army_roster[f.code])].radius_m)
		var shares: Array = [0.0, 1.0]
		for row: Dictionary in sampled.rows:
			for segment: Dictionary in BodyMotion._segments(row.path_m, row.budget_m):
				shares.append(segment.t0)
				shares.append(segment.t1)
		for tick: int in 1001: shares.append(tick / 1000.0)
		for share: float in shares:
			var drawn: Dictionary = view.call("along_candidate", sampled, share)
			for i: int in drawn.rows.size():
				for j: int in range(i + 1, drawn.rows.size()):
					var a: Dictionary = drawn.rows[i]
					var b: Dictionary = drawn.rows[j]
					assert_gte(Vector2(a.x_m, a.y_m).distance_to(Vector2(b.x_m, b.y_m)), radius * 2 - 0.01)
		assert_eq(f.state.to_dict(), before, "view leaves RNG, costs, personnel and receipt unchanged")
		var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
		f.ctx.state_fn = func() -> GameState: return restored
		assert_eq(_sample(f, envelope), sampled)
		assert_false(_sample(f).moving, "JSON rebind without retained commit timing cannot replay")

class SightContext extends Map3DContext:
	var admitted: Array = []
	var hostile := false
	func regiments() -> Array: return admitted
	func fogged(_code: String) -> bool: return hostile and not dev

func test_admission_and_hostile_path_access_instrumented() -> void:
	# Instrument the actual consumer source, without adding a production tracing seam.
	var source := FileAccess.get_file_as_string("res://scripts/map3d/map3d_candidate_bodies.gd")
	source = source.replace("class_name Map3DCandidateBodies\n", "")
	source = source.replace("extends RefCounted", "extends RefCounted\nstatic var reads := {\"owner\": 0, \"copy\": 0, \"control\": 0, \"path\": 0}")
	for mark: String in ["var index := UnitBodies._owners(state)", "var copied := UnitBodies.rows(ctx.repo, state, code)",
		"var saved: Variant = state.military_migration.get(\"body_motion\")", "var path: Variant = copied[i].get(\"path_m\")"]:
		var key := "owner" if "_owners" in mark else ("copy" if "UnitBodies.rows" in mark else ("control" if "body_motion" in mark else "path"))
		var indent := "\t\t" if mark.begins_with("var path:") else "\t"
		source = source.replace(indent + mark, indent + "reads[\"" + key + "\"] += 1\n" + indent + mark)
	var spy := GDScript.new()
	spy.source_code = source
	assert_eq(spy.reload(), OK)
	var f := _fixture()
	var ctx := SightContext.new(f.repo, f.ctx.meta)
	ctx.state_fn = func() -> GameState: return f.state
	var reg := ArmySystem.regiment(f.repo, f.code, f.state)
	for code: String in [f.code, Sighting.GHOST_CODE + f.code]:
		var admitted := reg.duplicate(true)
		admitted.regiment_code = code
		ctx.admitted = [] if code == f.code else [admitted]
		assert_eq(spy.call("sample_candidate", ctx, code).mode, "fallback")
		assert_eq(spy.get("reads"), {"owner": 0, "copy": 0, "control": 0, "path": 0})
	ctx.admitted = [reg]
	ctx.hostile = true
	f.state.regiments[f.code].body_groups[0].path_m = {"secret": "must never be read or copied"}
	f.state.military_migration.body_motion = {"secret": "unobserved control"}
	var observed: Dictionary = spy.call("sample_candidate", ctx, f.code)
	assert_eq(observed.mode, "bodies")
	assert_eq(observed.rows[0].path_m, [[0, 0]])
	assert_eq(spy.get("reads"), {"owner": 1, "copy": 0, "control": 0, "path": 0})
	f.state.regiments[f.code].body_groups[0].path_m = [[999, 999], [1234, 3456]]
	assert_eq(spy.call("sample_candidate", ctx, f.code), observed, "hidden path cannot enter cache key")
	ctx.dev = true
	assert_eq(spy.call("sample_candidate", ctx, f.code).mode, "invalid", "DEV does not repair malformed current controls")
	reg.is_naval = "1"
	var counts: Dictionary = spy.get("reads").duplicate()
	assert_eq(spy.call("sample_candidate", ctx, f.code).mode, "fallback")
	assert_eq(spy.get("reads"), counts, "fleet needs no body/control lookup")
	ctx.state_fn = Callable()

func test_repeated_receipt_refresh_pause_fps_and_camera_are_readonly() -> void:
	var f := _fixture()
	var envelope := _commit(f, [[[0, 0], [0, 3000], [0, 7000]]], [10000])
	var clock := {"share": 0.0, "speed": 1}
	f.ctx.day_fn = func() -> float: return clock.share
	f.ctx.clock_fn = func() -> int: return clock.speed
	var layer := _layer(f, envelope)
	layer.set_candidate_bodies(true, envelope)
	var before: Dictionary = f.state.to_dict()
	for speed: int in [0, 1, 4]:
		clock.speed = speed
		for delta: float in [0.0, 1.0 / 30, 1.0 / 60, 1.0 / 144]:
			clock.share = 0.5
			layer.step(delta)
			layer.ctx.camera.position.x += 100
			layer.refresh()
			assert_eq(f.state.to_dict(), before)
	clock.share = 1.0
	layer.step(0.0)
	var endpoint: Transform3D = layer.built_piece(f.code).groups[0].piece.node.global_transform
	clock.share = 0.0
	layer.set_candidate_bodies(true, envelope)
	layer.step(0.01)
	assert_eq(layer.built_piece(f.code).groups[0].piece.node.global_transform, endpoint, "completed receipt cannot restart")

func _script_files(path: String) -> Array[String]:
	var files: Array[String] = []
	for file: String in DirAccess.get_files_at(path):
		if file.ends_with(".gd"): files.append(path.path_join(file))
	for child: String in DirAccess.get_directories_at(path): files.append_array(_script_files(path.path_join(child)))
	return files

func test_no_ordinary_candidate_callers_or_query_writers() -> void:
	var callers: Array[String] = []
	for file: String in _script_files("res://scripts"):
		if file in ["res://scripts/map3d/map3d_candidate_bodies.gd", "res://scripts/map3d/map3d_layer_units.gd"]: continue
		var source := FileAccess.get_file_as_string(file)
		for token: String in ["sample_candidate(", "along_candidate(", "set_candidate_bodies(", "along_locomotion_candidate(",
				"Map3DCandidateBodies.sample_locomotion_candidate(", "CandidateView.sample_locomotion_candidate("]:
			if token in source: callers.append(file + ":" + token)
	assert_eq(callers, [])
	var source := FileAccess.get_file_as_string("res://scripts/map3d/map3d_candidate_bodies.gd")
	for token: String in ["migrate_candidate(", "reconcile_candidate(", "BodyMotion.plan(", "BodyMotion.commit(", "initialize_bodies_candidate("]:
		assert_false(token in source, "render query cannot invoke " + token)
	var layer := Map3DLayerUnits.new()
	autofree(layer)
	assert_false(layer.get("_candidate_bodies"))

func test_real_march_slices_use_matching_inner_receipt_and_outer_boundary() -> void:
	var f := _fixture(100, [[50000, 50000]])
	var entry: Dictionary = f.state.regiments[f.code]
	entry.x_m = 50000
	entry.y_m = 50000
	entry.dest_x_m = 60000
	entry.dest_y_m = 50000
	entry.order = ArmySystem.ORDER_MARCH
	entry.order_id = 10
	entry.erase("departure")
	entry.erase("camp_state")
	entry.supplies = 100000
	f.repo.balance.army_march_grid_px = 1
	var slopes := PackedByteArray()
	slopes.resize(200 * 200)
	MarchPath.use(f.repo, MarchPath.build(f.repo, 200, 200, 1000, slopes))
	var begin := TickEngine.new(f.repo).begin_body_march_candidate(f.state)
	assert_eq(begin.status, "complete", begin.reason)
	if begin.candidate == null: return
	f.state = begin.candidate
	f.ctx.state_fn = func() -> GameState: return f.state
	assert_eq(_sample(f).mode, "bodies", "before first commit shows current points")
	for slice: int in 3:
		var result := TickEngine.new(f.repo).step_body_march_candidate(f.state)
		assert_eq(result.status, "complete", result.reason)
		if result.candidate == null: return
		f.state = result.candidate
		var motion: Dictionary = result.plan.motion
		var envelope := {"cursor": {"version": 1, "abs_day": motion.cursor.abs_day, "substep": motion.cursor.substep,
			"receipt": BodyMotion._hash(motion)}, "moves": []}
		for move: Dictionary in motion.moves: envelope.moves.append({"unit": move.unit, "slot": move.slot, "budget_m": move.budget_m})
		var sample := _sample(f, envelope)
		assert_eq(sample.mode, "bodies", sample.error)
		assert_eq(sample.cursor.substep, slice)
		var before: Dictionary = f.state.to_dict()
		var retry := ArmySystem.commit_body_march_candidate(f.repo, f.state, result.plan)
		assert_eq(retry.status, "complete")
		assert_eq(retry.candidate.to_dict(), before)
		var next := String(f.state.day_resolution.body_march.next_substep)
		f.state.day_resolution.body_march.next_substep = str(int(next) + 1)
		assert_eq(_sample(f, envelope).mode, "invalid")
		f.state.day_resolution.body_march.next_substep = next
		assert_eq(f.state.to_dict(), before)
	MarchPath.forget()

func test_new_receipt_continuity_and_rejected_transfer_keep_current_view() -> void:
	var f := _fixture()
	var envelope := _commit(f, [[[0, 0], [0, 100]]], [100])
	var clock := {"share": 1.0}
	f.ctx.day_fn = func() -> float: return clock.share
	var layer := _layer(f, envelope)
	layer.set_candidate_bodies(true, envelope)
	var node: Node3D = layer.built_piece(f.code).groups[0].piece.node
	var transform := node.global_transform
	var before: Dictionary = f.state.to_dict()
	var rejected := UnitBodies.transfer_candidate(f.state, f.code, 0, 99)
	assert_eq(rejected.status, "error")
	layer.refresh()
	assert_same(layer.built_piece(f.code).groups[0].piece.node, node)
	assert_eq(node.global_transform, transform)
	assert_eq(f.state.to_dict(), before)
	envelope = _commit(f, [[[0, 100], [0, 200]]], [100], 1)
	clock.share = 0.0
	layer.set_candidate_bodies(true, envelope)
	assert_eq(node.global_transform, transform, "new slice begins at prior endpoint")
	assert_same(layer.built_piece(f.code).groups[0].piece.node, node)
	clock.share = 1.0
	layer.step(0.0)
	f.state.regiments[f.code].body_groups[0].y_m = 300
	envelope = _commit(f, [[[0, 300], [0, 400]]], [100], 2)
	clock.share = 0.0
	layer.set_candidate_bodies(true, envelope)
	assert_false(node.is_visible_in_tree(), "discontinuous input never gets a fabricated bridge")
	assert_false(layer.screen_rects().has(f.code))
	assert_false(String(layer.built_piece(f.code).candidate_error).is_empty())

func test_candidate_legacy_fallback_never_enters_whole_state_prediction() -> void:
	var f := _fixture()
	f.state.regiments[f.code].erase("body_groups")
	f.state.military_migration.erase("body_version")
	var layer := _layer(f)
	layer.step(0.1)
	assert_true((layer.get("_days") as Dictionary).is_empty(), "legacy endpoint display cannot copy hidden routes through ordinary prediction")

func test_first_explicit_clock_plays_but_late_timing_cannot_replay_loaded_endpoint() -> void:
	var f := _fixture()
	var envelope := _commit(f, [[[0, 0], [0, 4000]]], [4000])
	f.ctx.day_fn = func() -> float: return 0.5
	var layer := _layer(f, envelope)
	var node: Node3D = layer.built_piece(f.code).groups[0].piece.node
	var expected: Vector2 = f.ctx.to_world(Vector2(0, 2000) / float(ArmySystem.metres_per_pack_px(f.repo)))
	assert_almost_eq(node.global_position.z, expected.y, 0.0001, "explicit first bind actually renders the in-slice pose")
	var loaded := _layer(f)
	var endpoint: Transform3D = loaded.built_piece(f.code).groups[0].piece.node.global_transform
	loaded.set_candidate_bodies(true, envelope)
	assert_eq(loaded.built_piece(f.code).groups[0].piece.node.global_transform, endpoint, "late receipt cannot restart an endpoint already presented")

func test_unequal_budgets_diagonal_ceil_and_waiting_peers() -> void:
	var f := _fixture(200)
	var sample := _sample(f)
	sample.rows[0].x_m = 3
	sample.rows[0].y_m = 1
	sample.rows[0].path_m = [[0, 0], [1, 1], [3, 1]]
	sample.rows[0].budget_m = 6
	sample.rows[1].x_m = 3
	sample.rows[1].y_m = 10004
	sample.rows[1].path_m = [[0, 10000], [3, 10000], [3, 10004]]
	sample.rows[1].budget_m = 10
	var before := sample.duplicate(true)
	var middle: Dictionary = view.call("along_candidate", sample, 0.5)
	assert_almost_eq(middle.rows[0].x_m, 2.0, 0.000000000001, "ceil(sqrt(2))=2 then one of the two horizontal metres")
	assert_eq(middle.rows[0].y_m, 1.0)
	assert_eq(middle.rows[1].x_m, 3.0)
	assert_almost_eq(middle.rows[1].y_m, 10002.0, 0.000000000001)
	var tail: Dictionary = view.call("along_candidate", sample, 0.9)
	assert_eq(tail.rows[0].x_m, 3.0)
	assert_eq(tail.rows[1].y_m, 10004.0)
	assert_eq(BodyMotion._segments(sample.rows[0].path_m, 6)[0].t1, 2.0 / 6)
	assert_eq(sample, before)

func test_present_body_rows_require_current_version_even_at_zero_fit() -> void:
	for fit: int in [0, 100]:
		var f := _fixture(fit)
		f.state.military_migration.erase("body_version")
		assert_eq(_sample(f).mode, "invalid", "present rows without applicable schema cannot publish")
		f.state.regiments[f.code].erase("body_groups")
		assert_eq(_sample(f).mode, "fallback", "truly absent legacy bodies remain ordinary fallback")

func test_hostile_animation_never_reopens_hidden_intent() -> void:
	var f := _fixture()
	f.state.foes = {f.code: f.state.regiments[f.code]}
	f.state.regiments = {}
	var ctx := SightContext.new(f.repo, f.ctx.meta)
	ctx.admitted = [ArmySystem.regiment(f.repo, f.code, f.state)]
	ctx.hostile = true
	ctx.state_fn = func() -> GameState: return f.state
	_contexts.append(ctx)
	f.ctx = ctx
	var source := FileAccess.get_file_as_string("res://scripts/map3d/map3d_candidate_bodies.gd").replace("class_name Map3DCandidateBodies\n", "")
	source = source.replace("extends RefCounted", "extends RefCounted\nstatic var intent_reads := 0")
	source = source.replace("ArmySystem.order_of(ctx.repo, state, code)", "_order_read(ctx, code)")
	source = source.replace("BattleSystem.stance_of(state, code)", "_stance_read(ctx, code)")
	source += "\nstatic func _order_read(ctx: Map3DContext, code: String) -> String:\n\tintent_reads += 1\n\treturn ArmySystem.order_of(ctx.repo, ctx.state(), code)\n"
	source += "\nstatic func _stance_read(ctx: Map3DContext, code: String) -> String:\n\tintent_reads += 1\n\treturn BattleSystem.stance_of(ctx.state(), code)\n"
	var spy := GDScript.new()
	spy.source_code = source
	assert_eq(spy.reload(), OK)
	var layer := _layer(f)
	var piece: Dictionary = layer.built_piece(f.code)
	var observed := _sample(f)
	var actions: Array = []
	for order: String in [ArmySystem.ORDER_MARCH, ArmySystem.ORDER_GARRISON]:
		f.state.foes[f.code].order = order
		f.state.foes[f.code].stance = "hidden-" + order
		spy.call("_animate_candidate", ctx, f.code, piece, observed, 1.0, 0.3, Map3DBattleSignals.new())
		actions.append([piece.action, piece.groups[0].piece.action])
		layer.refresh()
		layer.step(0.0)
		assert_eq([piece.action, piece.groups[0].piece.action], actions[0], "real layer must preserve the observed clip")
	assert_eq(actions[0], actions[1])
	assert_eq(spy.get("intent_reads"), 0, "downstream hostile animation cannot query hidden order/stance")
	ctx.dev = true
	spy.call("_animate_candidate", ctx, f.code, piece, observed, 1.0, 0.3, Map3DBattleSignals.new())
	assert_eq(spy.get("intent_reads"), 2, "DEV retains its explicit intent access")

## v2 stop-pivot-move: an explicit test certificate, not installed arm support.
func _loco_policy(f: Dictionary) -> void:
	var piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
	f.repo.unit_footprints[piece].locomotion_certificate = {"digest": "a".repeat(64),
		"turn_q": 400000, "contact_um": 100, "radius_m": int(f.repo.unit_footprints[piece].radius_m),
		"clips": ["PIVOT_LEFT", "PIVOT_RIGHT", "MARCH"], "all_turns": true}
	f.repo.balance["body_locomotion_" + piece + "_turn_q"] = 400000
	f.repo.balance["body_locomotion_" + piece + "_contact_um"] = 100

const O := 50000  ## v2 cases run at (O, O) + offset on an open test grid

func _commit_v2(f: Dictionary, path: Array, budget: int) -> Dictionary:
	_loco_policy(f)
	f.repo.balance.army_march_grid_px = 1
	var slopes := PackedByteArray()
	slopes.resize(200 * 200)
	MarchPath.use(f.repo, MarchPath.build(f.repo, 200, 200, 1000, slopes))
	var row: Dictionary = f.state.regiments[f.code].body_groups[0]
	row.x_m = O + int(path[0][0])
	row.y_m = O + int(path[0][1])
	row.facing_deg = 0
	var absolute: Array = path.map(func(p: Array) -> Array: return [O + int(p[0]), O + int(p[1])])
	var intents := [{"unit": f.code, "slot": 0, "path_m": absolute, "budget_m": budget, "hostile": false}]
	var plan := BodyMotion.plan_locomotion_candidate(f.repo, f.state, intents, f.state.absolute_day(), 0)
	assert_eq(plan.get("version"), 2, str(plan))
	var result := BodyMotion.commit_locomotion_candidate(f.repo, f.state, plan)
	assert_eq(result.status, "complete", result.reason)
	var state: GameState = result.candidate
	f.state = state
	f.ctx.state_fn = func() -> GameState: return state
	return {"cursor": {"version": 2, "abs_day": plan.cursor.abs_day, "substep": plan.cursor.substep, "receipt": BodyMotion._hash(plan)}}

func test_v1_leg_off_saved_facing_is_refused_not_walked_sideways() -> void:
	var f := _fixture()
	var envelope := _commit(f, [[[0, 0], [3, 0], [3, 4]]], [10])
	f.ctx.day_fn = func() -> float: return 0.5
	var layer := _layer(f, envelope)
	var piece: Dictionary = layer.built_piece(f.code)
	assert_false(piece.groups[0].piece.node.is_visible_in_tree(), "facing 90 cannot walk the +X leg on forward clips")
	assert_string_contains(String(piece.candidate_error), "transverse leg refused")
	assert_false(layer.screen_rects().has(f.code))

func test_v2_stop_pivot_move_hand_computed_l() -> void:
	var f := _fixture()
	var envelope := _commit_v2(f, [[0, 0], [3, 0], [3, 4]], 10)
	var endpoint := view.call("sample_locomotion_candidate", f.ctx, f.code) as Dictionary
	assert_eq(endpoint.mode, "bodies", endpoint.error)
	assert_false(endpoint.moving, "a saved v2 receipt alone draws its endpoint")
	assert_false(endpoint.rows[0].has("move"))
	var still: Dictionary = view.call("along_locomotion_candidate", endpoint, 500000)
	assert_eq([still.rows[0].x_m - O, still.rows[0].y_m - O, still.rows[0].yaw_udeg], [3, 4, 0.0])
	var sampled: Dictionary = view.call("sample_locomotion_candidate", f.ctx, f.code, envelope)
	assert_eq(sampled.mode, "bodies", sampled.error)
	assert_true(sampled.moving)
	assert_eq(sampled.rows[0].move.ops.map(func(op: Dictionary) -> String: return op.kind), ["move", "pivot", "move", "pivot", "hold"])
	var before := sampled.duplicate(true)
	for example: Array in [[150000, 1.5, 0.0, 0.0, "move"], [350000, 3.0, 0.0, 45000000.0, "pivot"],
			[500000, 3.0, 1.0, 90000000.0, "move"], [850000, 3.0, 4.0, 45000000.0, "pivot"], [1000000, 3.0, 4.0, 0.0, "hold"]]:
		var at: Dictionary = view.call("along_locomotion_candidate", sampled, example[0])
		assert_eq([at.rows[0].x_m - O, at.rows[0].y_m - O, at.rows[0].yaw_udeg, at.rows[0].op], example.slice(1), str(example[0]))
	assert_eq(sampled, before, "sampling leaves the copied projection intact")
	for bad: int in [-1, 1000001]:
		assert_eq(view.call("along_locomotion_candidate", sampled, bad).mode, "invalid")
	var mixed := envelope.duplicate(true)
	mixed.moves = []
	assert_eq(view.call("sample_candidate", f.ctx, f.code, mixed).mode, "invalid", "v1 budget envelope cannot time a v2 receipt")
	var forged := envelope.duplicate(true)
	forged.cursor.receipt = "b".repeat(64)
	assert_eq(view.call("sample_candidate", f.ctx, f.code, forged).mode, "invalid")
	var v1 := _fixture()
	var v1_envelope := _commit(v1, [[[0, 0], [0, 4]]], [10])
	assert_eq(view.call("sample_locomotion_candidate", v1.ctx, v1.code, v1_envelope).mode, "invalid", "v1 receipt is not a v2 timeline")
	assert_eq(view.call("sample_candidate", v1.ctx, v1.code, v1_envelope).mode, "bodies")

func test_v2_pivot_needs_the_arms_clip_else_refuses_the_unit() -> void:
	var f := _fixture()
	f.state.army_roster[f.code].organization_arm = "infantry"
	assert_eq(MapObjects.army_piece(f.repo, f.state.army_roster[f.code]), "infantry", "this arm has MARCH only")
	var envelope := _commit_v2(f, [[0, 0], [3, 0], [3, 4]], 10)
	f.ctx.day_fn = func() -> float: return 0.35
	var layer := _layer(f, envelope)
	var piece: Dictionary = layer.built_piece(f.code)
	assert_false(piece.groups[0].piece.node.is_visible_in_tree())
	assert_string_contains(String(piece.candidate_error), "no PIVOT_RIGHT clip")
	assert_false(layer.screen_rects().has(f.code))
	# A straight v2 leg along the facing needs no pivot and plays on MARCH alone.
	var straight := _fixture()
	straight.state.army_roster[straight.code].organization_arm = "infantry"
	var ahead := _commit_v2(straight, [[0, 0], [4, 0]], 8)
	straight.ctx.day_fn = func() -> float: return 0.25
	var walking := _layer(straight, ahead)
	var shown: Dictionary = walking.built_piece(straight.code)
	assert_true(shown.groups[0].piece.node.is_visible_in_tree(), String(shown.get("candidate_error", "")))
	assert_eq(shown.groups[0].piece.action, "MARCH")

func test_v2_arm_with_pivot_clips_stops_turns_then_walks() -> void:
	var f := _fixture()
	f.state.army_roster[f.code].organization_arm = "archers"
	assert_eq(MapObjects.army_piece(f.repo, f.state.army_roster[f.code]), "archers")
	var envelope := _commit_v2(f, [[0, 0], [3, 0], [3, 4]], 10)
	var clock := {"share": 0.3 + 0.1 * 0.25, "speed": 1}
	f.ctx.day_fn = func() -> float: return clock.share
	f.ctx.clock_fn = func() -> int: return clock.speed
	var layer := _layer(f, envelope)
	var child: Dictionary = layer.built_piece(f.code).groups[0].piece
	assert_true(child.node.is_visible_in_tree(), String(layer.built_piece(f.code).get("candidate_error", "")))
	var anim: AnimationPlayer = child.anims[0]
	layer.step(0.0)
	assert_eq(child.action, "PIVOT_RIGHT")
	assert_eq(anim.speed_scale, 0.0, "pivot is scrubbed by operation phase, not frame delta")
	assert_almost_eq(anim.current_animation_position, 0.25 * anim.current_animation_length, 0.001)
	var expected := [["PIVOT_RIGHT", 45.0, Vector2(3, 0)], ["MARCH", 90.0, Vector2(3, 1)], ["PIVOT_LEFT", 45.0, Vector2(3, 4)]]
	var i := 0
	for share: float in [0.35, 0.5, 0.85]:
		clock.share = share
		layer.step(0.0)
		assert_eq(child.action, expected[i][0], str(share))
		var yaw := Map3DUnits.facing_yaw(Vector2.from_angle(deg_to_rad(expected[i][1])), child.stand_deg)
		assert_almost_eq(wrapf((child.node as Node3D).global_rotation.y - yaw, -PI, PI), 0.0, 0.0001, str(share))
		var xz: Vector2 = f.ctx.to_world((expected[i][2] + Vector2(O, O)) / float(ArmySystem.metres_per_pack_px(f.repo)))
		assert_almost_eq((child.node as Node3D).global_position.x, xz.x, 0.0001)
		assert_almost_eq((child.node as Node3D).global_position.z, xz.y, 0.0001)
		i += 1

func test_v2_saved_path_must_match_the_committed_operations() -> void:
	var f := _fixture()
	f.state.army_roster[f.code].organization_arm = "archers"
	var envelope := _commit_v2(f, [[0, 0], [3, 0], [3, 4]], 10)
	assert_eq(_sample(f, envelope).mode, "bodies")
	f.state.regiments[f.code].body_groups[0].path_m = [[O - 1, O], [O + 3, O + 4]]
	assert_eq(_sample(f, envelope).mode, "invalid", "a continuity anchor that disagrees with the ops is never trusted")

func test_earlier_v1_receipt_does_not_hide_a_fresh_v2_day() -> void:
	var f := _fixture(100, [[50000, 50000]])
	var entry: Dictionary = f.state.regiments[f.code]
	entry.x_m = 50000
	entry.y_m = 50000
	entry.erase("departure")
	entry.erase("camp_state")
	f.repo.balance.army_march_grid_px = 1
	var slopes := PackedByteArray()
	slopes.resize(200 * 200)
	MarchPath.use(f.repo, MarchPath.build(f.repo, 200, 200, 1000, slopes))
	_loco_policy(f)
	_commit(f, [[[50000, 50000]]], [0])
	assert_eq(f.state.military_migration.body_motion.version, "1")
	f.state.day += 1  # the v1 receipt now belongs to an earlier, closed day
	var begin := TickEngine.new(f.repo).begin_locomotion_march_candidate(f.state)
	assert_eq(begin.status, "complete", begin.reason)
	if begin.candidate == null: return
	var state: GameState = begin.candidate
	f.ctx.state_fn = func() -> GameState: return state
	assert_eq(state.day_resolution.body_march.version, "2")
	var sampled := _sample(f)
	assert_eq(sampled.mode, "bodies", sampled.error)
