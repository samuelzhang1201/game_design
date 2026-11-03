extends GutTest

func test_pivot_consumes_same_slice() -> void:
	var api: GDScript = load("res://scripts/engine/body_motion.gd")
	assert_true(api.has_method("plan_battle_locomotion_candidate"), "explicit battle TIME entrance")
	assert_true(api.has_method("commit_battle_locomotion_candidate"), "atomic battle TIME commit")
	if not api.has_method("plan_battle_locomotion_candidate"): return
	var body := {"unit": "math", "slot": 0, "start": [0, 0], "budget_m": 100,
		"start_yaw_udeg": 0, "final_facing_deg": 0}
	var timed := BodyMotion._loco_timeline(body, [[0, 0], [0, 50]], 1000000)
	assert_eq(timed.used_m, 50)
	assert_eq(timed.ops.map(func(op: Dictionary) -> String: return op.kind), ["pivot", "move", "pivot"])
	assert_eq(timed.ops.map(func(op: Dictionary) -> int: return op.t1_q - op.t0_q), [250000, 500000, 250000])
	var too_far := BodyMotion._loco_timeline(body, [[0, 0], [0, 51]], 1000000)
	assert_lte(too_far.used_m, 50)

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _fixture(counts: Array = [100], daily: int = 1000) -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_budget.gd").new()
	var f: Dictionary = helper.call("_fixture", counts, daily)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	f.grid.closed.fill(0)
	f.grid.water.fill(0)
	return f

func _boundary(f: Dictionary) -> Dictionary:
	return BodyBattleMotion._boundary(f.state)

func _route(f: Dictionary, index: int, path: Array, facing: int = 0) -> void:
	var code: String = f.codes[index]
	var entry: Dictionary = f.state.regiments[code]
	entry.x_m = path[0][0]
	entry.y_m = path[0][1]
	entry.dest_x_m = path.back()[0]
	entry.dest_y_m = path.back()[1]
	entry.route_m = path.slice(1)
	entry.body_groups[0].x_m = entry.x_m
	entry.body_groups[0].y_m = entry.y_m
	entry.body_groups[0].facing_deg = facing
	f.state.day_resolution.march_entries[code] = entry.duplicate(true)

func test_real_timeline_pivot_prefix_and_boundary_json_equality() -> void:
	var f := _fixture()
	var piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
	f.repo.balance["body_locomotion_" + piece + "_turn_q"] = 1000000
	f.repo.unit_footprints[piece].locomotion_certificate.turn_q = 1000000
	for distance: int in [50, 51]:
		_route(f, 0, [[50000, 50000], [50000, 50000 + distance]])
		var planned := BodyBattleMotion.plan_candidate(f.repo, f.state, _boundary(f))
		assert_eq(planned.status, "complete", planned.reason)
		if planned.plan.is_empty(): continue
		var move: Dictionary = planned.plan.motion.moves[0]
		assert_eq(move.used_m, 50)
		assert_eq(move.ops.map(func(op: Dictionary) -> String: return op.kind), ["pivot", "move", "pivot"])
		assert_eq(move.ops.map(func(op: Dictionary) -> int: return op.t1_q), [250000, 750000, 1000000])
		var committed := BodyBattleMotion.commit_candidate(f.repo, f.state, planned.plan, _boundary(f))
		assert_eq(committed.status, "complete", committed.reason)
		if committed.candidate == null: continue
		var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(committed.candidate.to_dict())), false)
		for time: int in [0, 1, 249999, 250000, 250001, 749999, 750000, 750001, 999999, 1000000]:
			var a := BodyMotion.sample_locomotion_candidate({"version": 2, "moves": committed.candidate.military_migration.body_motion.plan.moves}, time)
			var b := BodyMotion.sample_locomotion_candidate({"version": 2, "moves": restored.military_migration.body_motion.plan.moves}, time)
			assert_eq(a, b, "JSON sample at operation boundary")
		assert_eq(restored.regiments[f.code].y_m, 50050)

func test_forbidden_middle_edge_corner_bounds_and_scarps() -> void:
	for kind: String in ["closed", "water", "scarp", "edge", "corner", "bounds", "detour"]:
		var f := _fixture([100], 200000)
		var piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
		var radius := int(f.repo.unit_footprints[piece].radius_m)
		assert_gt(radius, 500, "use measured radius, not reduced geometry fixture")
		var path: Array = [[48000, 50500], [55000, 50500]]
		var cell: int = 50 * f.grid.cols + 51
		match kind:
			"closed": f.grid.closed[cell] = 1
			"water": f.grid.water[cell] = 1
			"scarp":
				var slopes := PackedByteArray()
				slopes.resize(200 * 200)
				slopes[cell] = 254
				f.grid = MarchPath.build(f.repo, 200, 200, 1000, slopes)
				MarchPath.use(f.repo, f.grid)
				assert_eq(f.grid.closed[cell], 1)
			"edge":
				f.grid.closed[cell] = 1
				path = [[48000, 50000 - radius], [55000, 50000 - radius]]
			"corner":
				f.grid.closed[cell] = 1
				path = [[51000 - radius, 48000], [51000 - radius, 50000], [49000, 48000]]
			"bounds": path = [[radius + 100, 50000], [radius - 1, 50000], [radius + 200, 50000]]
			"detour":
				f.grid.closed[cell] = 1
				path = [[48000, 48000], [51500, 50500], [55000, 48000]]
		_route(f, 0, path)
		assert_eq(ArmySystem._body_path_terrain(f.grid, [path[0]], radius), "", kind + " legal start")
		assert_eq(ArmySystem._body_path_terrain(f.grid, [path.back()], radius), "", kind + " legal endpoint")
		var before := BodyMotion._hash(f.state.to_dict())
		var planned := BodyBattleMotion.plan_candidate(f.repo, f.state, _boundary(f))
		assert_eq(planned.status, "error", kind + " illegal middle rejects entire transaction")
		assert_null(planned.candidate)
		assert_eq(planned.plan, {})
		assert_eq(BodyMotion._hash(f.state.to_dict()), before, kind + " costs and RNG unchanged")

func test_real_radius_opposed_three_way_and_stationary_pivot_sweep() -> void:
	var f := _fixture([100, 100, 100], 100000)
	_route(f, 0, [[40000, 50000], [60000, 50000]])
	_route(f, 1, [[60000, 50000], [40000, 50000]], 180)
	_route(f, 2, [[50000, 40000], [50000, 60000]], 0)
	var planned := BodyBattleMotion.plan_candidate(f.repo, f.state, _boundary(f))
	assert_eq(planned.status, "complete", planned.reason)
	if planned.plan.is_empty(): return
	var moves: Array = planned.plan.motion.moves
	assert_eq(moves.size(), 3)
	for i: int in moves.size():
		var piece_a := MapObjects.army_piece(f.repo, f.state.army_roster[moves[i].unit])
		var radius_a := int(f.repo.unit_footprints[piece_a].radius_m)
		for j: int in range(i + 1, moves.size()):
			var piece_b := MapObjects.army_piece(f.repo, f.state.army_roster[moves[j].unit])
			var radius_b := int(f.repo.unit_footprints[piece_b].radius_m)
			assert_false(BodyMotion._sweep_collision({"radius": radius_a, "budget_m": moves[i].budget_m}, BodyMotion._loco_segments(moves[i]),
				{"radius": radius_b, "budget_m": moves[j].budget_m}, BodyMotion._loco_segments(moves[j])), "whole continuous intervals, including pivots and tails")
	var reverse: Array = planned.plan.motion.cursor.intents.duplicate(true)
	reverse.reverse()
	assert_eq(BodyMotion.plan_battle_locomotion_candidate(f.repo, f.state, reverse, _boundary(f)), planned.plan.motion)
	var applied := BodyBattleMotion.commit_candidate(f.repo, f.state, planned.plan, _boundary(f))
	assert_eq(applied.status, "complete", applied.reason)
	var stationary: Array[Dictionary] = [{"a": [50000, 50000], "b": [50000, 50000], "t0": 0.25, "t1": 0.5}]
	var crossing: Array[Dictionary] = [{"a": [40000, 50000], "b": [60000, 50000], "t0": 0.25, "t1": 0.5}]
	assert_true(BodyMotion._sweep_collision({"radius": 927, "budget_m": 0}, stationary, {"radius": 804, "budget_m": 20000}, crossing))
