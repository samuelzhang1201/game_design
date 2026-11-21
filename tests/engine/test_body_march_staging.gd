extends GutTest
## ACT-DRIVER B2e: a march off its row facing ends facing its heading, and a column's rows
## reserve front first (BodyMotion's locomotion timeline and reservation order).

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _fixture(counts: Array, daily: int) -> Dictionary:
	var helper: GutTest = load("res://tests/engine/test_body_battle_budget.gd").new()
	var f: Dictionary = helper.call("_fixture", counts, daily)
	assert_eq(helper.get_fail_count(), 0)
	helper.free()
	f.grid.closed.fill(0)
	f.grid.water.fill(0)
	return f

## The unit marches from `rows[0]` (its anchor) along `route`; row i stands at rows[i], facing `facing`.
func _march(f: Dictionary, rows: Array, route: Array, facing: int) -> Dictionary:
	var entry: Dictionary = f.state.regiments[f.code]
	entry.x_m = rows[0][0]
	entry.y_m = rows[0][1]
	entry.route_m = route.duplicate(true)
	entry.dest_x_m = route.back()[0]
	entry.dest_y_m = route.back()[1]
	assert_eq(entry.body_groups.size(), rows.size())
	for i: int in rows.size():
		entry.body_groups[i].x_m = rows[i][0]
		entry.body_groups[i].y_m = rows[i][1]
		entry.body_groups[i].facing_deg = facing
		entry.body_groups[i].path_m = [rows[i].duplicate()]
	f.state.day_resolution.march_entries[f.code] = entry.duplicate(true)
	var planned := BodyBattleMotion.plan_candidate(f.repo, f.state, BodyBattleMotion._boundary(f.state))
	assert_eq(planned.status, "complete", planned.reason)
	if planned.status != "complete": return {}
	var committed := BodyBattleMotion.commit_candidate(f.repo, f.state, planned.plan, BodyBattleMotion._boundary(f.state))
	assert_eq(committed.status, "complete", committed.reason)
	return {"plan": planned.plan, "state": committed.candidate}

func _move(plan: Dictionary, slot: int) -> Dictionary:
	for move: Dictionary in plan.motion.moves:
		if int(move.slot) == slot: return move
	return {}

func _kinds(move: Dictionary) -> Array:
	return move.ops.map(func(op: Dictionary) -> String: return op.kind)

func _ends(move: Dictionary) -> Array:
	return move.ops.map(func(op: Dictionary) -> int: return int(op.t1_q))

## 1000 m a day over 10 slices: 100 m this slice. turn_q 400000: a quarter turn takes
## ceil(90e6 * 400000 / 360e6) = 100000 of the slice's 1000000.
func test_a_turn_ends_facing_the_heading_and_a_row_facing_it_walks_straight() -> void:
	var f := _fixture([100], 1000)
	# Facing east (0), the route goes north (90). The row prefix keeps room for a pivot back,
	# so 0.1 + d/100 + 0.1 <= 1: d = 80. The row then ends facing north with no pivot back.
	var turned := _march(f, [[50000, 50000]], [[50000, 50500]], 0)
	if turned.is_empty(): return
	var move := _move(turned.plan, 0)
	assert_eq(move.used_m, 80)
	assert_eq(move.end, [50000, 50080])
	assert_eq(_kinds(move), ["pivot", "move", "hold"])
	assert_eq(_ends(move), [100000, 900000, 1000000])
	assert_eq(move.final_facing_deg, 90)
	var row: Dictionary = turned.state.regiments[f.code].body_groups[0]
	assert_eq([row.x_m, row.y_m, row.facing_deg], [50000, 50080, 90], "the row's facing is written to its heading")
	var json := GameState.from_dict(JSON.parse_string(JSON.stringify(turned.state.to_dict())), false)
	assert_eq(json.regiments[f.code].body_groups[0].facing_deg, 90, "the facing survives the save")
	# Already facing north: no pivot either way, the whole 100 m in the whole slice.
	var straight := _march(_fixture([100], 1000), [[50000, 50000]], [[50000, 50500]], 90)
	if straight.is_empty(): return
	move = _move(straight.plan, 0)
	assert_eq(move.used_m, 100)
	assert_eq(_kinds(move), ["move"])
	assert_eq(_ends(move), [1000000])
	assert_eq(move.final_facing_deg, 90)

## A heading off a whole degree ends at its nearest one: (3, 4) is 53.130102 degrees, so the
## row ends facing 53 after a 130102-microdegree pivot of ceil(130102 * 400000 / 360e6) = 145.
func test_an_oblique_leg_ends_at_its_whole_degree() -> void:
	var f := _fixture([100], 1000)
	var oblique := _march(f, [[50000, 50000]], [[50030, 50040]], 0)
	if oblique.is_empty(): return
	var move := _move(oblique.plan, 0)
	assert_eq(move.used_m, 50)
	assert_eq(_kinds(move), ["pivot", "move", "pivot", "hold"])
	assert_eq(move.ops[2].turn_udeg, -130102)
	assert_eq(move.ops[2].t1_q - move.ops[2].t0_q, 145)
	assert_eq(move.final_facing_deg, 53)
	assert_eq(oblique.state.regiments[f.code].body_groups[0].facing_deg, 53)

## Two rows in file east, `gap` apart centre to centre: the rear (slot 0) can close by only 50 m
## on a still front. Front first, the front walks 100 m and the rear follows it the whole 100 m.
func test_a_column_reserves_front_first_and_its_rear_follows() -> void:
	var f := _fixture([200], 1000)
	var piece := MapObjects.army_piece(f.repo, f.state.army_roster[f.code])
	var radius := int(f.repo.unit_footprints[piece].radius_m)
	var gap := 2 * radius + int(f.repo.balance.get("cluster_motion_clearance_m", 0)) + 50
	var marched := _march(f, [[50000, 50000], [50000 + gap, 50000]], [[60000, 50000]], 0)
	if marched.is_empty(): return
	var rear := _move(marched.plan, 0)
	var front := _move(marched.plan, 1)
	assert_eq([front.used_m, front.end], [100, [50100 + gap, 50000]])
	assert_eq([rear.used_m, rear.end], [100, [50100, 50000]], "the rear walks its whole share behind the front")
	assert_eq(_kinds(rear), ["move"])
	assert_eq(_kinds(front), ["move"])
	assert_eq(marched.plan.motion.cursor.priority, [{"unit": f.code, "slot": 1}, {"unit": f.code, "slot": 0}], "reserved front first")

## The timeline's rule (a body in a battle has no face_heading and pivots back) and its validator.
func test_the_timeline_rule_and_its_validator() -> void:
	var body := {"unit": "u", "slot": 0, "start": [0, 0], "budget_m": 100, "start_yaw_udeg": 0, "final_facing_deg": 0}
	var kept := BodyMotion._loco_timeline(body, [[0, 0], [0, 50]], 400000)
	assert_eq([_kinds(kept), kept.final_facing_deg], [["pivot", "move", "pivot", "hold"], 0], "without face_heading it pivots back")
	body.face_heading = true
	var faced := BodyMotion._loco_timeline(body, [[0, 0], [0, 50]], 400000)
	assert_eq([_kinds(faced), _ends(faced), faced.final_facing_deg], [["pivot", "move", "hold"], [100000, 600000, 1000000], 90])
	assert_true(BodyMotion._loco_move_ok(faced), "a moved row may end at its last leg's whole degree")
	# A consistent timeline that ends at 80 after its leg at 90 is neither the row's facing nor its heading.
	var forged := faced.duplicate(true)
	forged.ops.insert(2, BodyMotion._loco_op("pivot", 600000, 700000, [0, 50], [0, 50], 90000000, -10000000))
	forged.ops[3].t0_q = 700000
	forged.ops[3].yaw0_udeg = 80000000
	forged.final_facing_deg = 80
	assert_false(BodyMotion._loco_move_ok(forged), "nor any other facing")
	forged.final_facing_deg = 0
	assert_false(BodyMotion._loco_move_ok(forged), "it must end where its final facing says")
	var off := faced.duplicate(true)
	off.start_yaw_udeg = 1
	off.ops[0].yaw0_udeg = 1
	off.ops[0].turn_udeg = 89999999
	assert_false(BodyMotion._loco_move_ok(off), "a slice starts at a whole degree")

## A column that turns back keeps its saved place, but its new front reserves first. Two rows
## 25 m apart (radius 10) walk east 10 m front first ([1, 0]), then west, where the old rear
## leads ([0, 1]). The standalone planner takes a leg only when it fits whole, so each path is
## sized to its slice: a half turn takes 200000 and there is no pivot back, so 0.2 + 8/10 = 1.
func test_a_reversed_column_reserves_its_new_front_first() -> void:
	var helper: GutTest = load("res://tests/engine/test_body_motion.gd").new()
	var f: Dictionary = helper.call("_loco_fixture", [[100, 100], [125, 100]])
	assert_eq(helper.get_fail_count(), 0)
	var east := [helper.call("_intent", f, 0, [110, 100], 10), helper.call("_intent", f, 1, [135, 100], 10)]
	helper.free()
	var first := BodyMotion.plan_locomotion_candidate(f.repo, f.state, east, 70, 0)
	assert_eq(first.get("version"), 2, str(first))
	if not first.has("version"): return
	assert_eq(first.moves.map(func(m: Dictionary) -> int: return int(m.used_m)), [10, 10])
	assert_eq(first.cursor.priority, [{"unit": f.code, "slot": 1}, {"unit": f.code, "slot": 0}])
	var committed := BodyMotion.commit_locomotion_candidate(f.repo, f.state, first)
	assert_eq(committed.status, "complete", str(committed))
	if committed.status != "complete": return
	var state: GameState = committed.candidate
	var west := [{"unit": f.code, "slot": 0, "path_m": [[110, 100], [102, 100]], "budget_m": 10, "hostile": false},
		{"unit": f.code, "slot": 1, "path_m": [[135, 100], [127, 100]], "budget_m": 10, "hostile": false}]
	var back := BodyMotion.plan_locomotion_candidate(f.repo, state, west, 70, 1)
	assert_eq(back.get("version"), 2, str(back))
	if not back.has("version"): return
	assert_eq(back.cursor.priority, [{"unit": f.code, "slot": 0}, {"unit": f.code, "slot": 1}], "the new front reserves first")
	assert_eq(back.moves.map(func(m: Dictionary) -> int: return int(m.used_m)), [8, 8])
	assert_eq(back.moves.map(func(m: Dictionary) -> int: return int(m.final_facing_deg)), [180, 180])

func test_a_heading_rounds_to_its_nearest_whole_degree_across_north() -> void:
	assert_eq(BodyMotion._loco_whole(359500000), 0)
	assert_eq(BodyMotion._loco_whole(359499999), 359000000)
	assert_eq(BodyMotion._loco_whole(500000), 1000000)
	assert_eq(BodyMotion._loco_whole(499999), 0)

## B2e's rule, swept: a row in no battle never ends its slice in a pivot, except the sub-degree
## turn from an oblique leg's heading to its nearest whole degree, and it ends at that degree.
func test_a_row_in_no_battle_ends_no_slice_in_a_pivot_but_a_sub_degree_one() -> void:
	var q := BodyMotion.LOCOMOTION_Q
	for facing: int in [0, 45, 90, 179, 270, 359]:
		for leg: Array in [[50, 0], [0, -50], [-30, 40], [30, 40], [7, -7], [1, 50], [-49, -3]]:
			var body := {"unit": "u", "slot": 0, "start": [0, 0], "budget_m": 100,
				"start_yaw_udeg": facing * q, "final_facing_deg": facing, "face_heading": true}
			var timed := BodyMotion._loco_timeline(body, [[0, 0], leg], 400000)
			var heading := BodyMotion._locomotion_heading(leg[0], leg[1])
			var last: Dictionary = timed.ops.filter(func(op: Dictionary) -> bool: return op.kind != "hold").back()
			var case := "%s from %s" % [leg, facing]
			assert_eq(timed.used_m, BodyMotion._distance_ceil([0, 0], leg), case + ": the whole leg fits")
			if last.kind == "pivot":
				assert_ne(heading % q, 0, case + ": only an oblique heading ends in a pivot")
				assert_lt(absi(int(last.turn_udeg)), q, case + ": and only a sub-degree one")
			assert_eq(timed.final_facing_deg * q, BodyMotion._loco_whole(heading), case)
