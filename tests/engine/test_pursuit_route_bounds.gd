extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture(path: Array, extra: Dictionary) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 9460)
	SuiteData.flat_ground(repo)
	repo.balance["army_clearance_on"] = 0
	var codes := state.regiments.keys()
	codes.sort()
	var code := String(codes[0])
	var enemy := String(state.foes.keys()[0])
	repo.balance["army_supply_per_head_permille"] = 3000 # 1000 commoners still use 3000 a month.
	Personnel.replace(repo, state, code, 1000)
	var e: Dictionary = state.regiments[code]
	e.merge({"x_m": 100, "y_m": 100, "dest_x_m": path[-1].x, "dest_y_m": path[-1].y,
		"order": ArmySystem.ORDER_MARCH, "route_m": MarchRoute.to_pairs(path),
		"morale": 100, "training": 100, "supplies": 100000}, true)
	e.erase("camp_state")
	e.erase("departure")
	var provinces := repo.provinces.keys()
	provinces.sort()
	var inside := String(provinces[0])
	var outside := String(provinces[1])
	# A U: the straight route from (100,100) to (900,100) exits at x=400,
	# although both endpoints are inside. The bottom bridge is y=800..1000.
	repo.vertices.clear()
	repo.cells.clear()
	repo.manors.clear()
	var polys: Array = [[Vector2i(0,0), Vector2i(400,0), Vector2i(400,1000), Vector2i(0,1000)],
		[Vector2i(400,800), Vector2i(600,800), Vector2i(600,1000), Vector2i(400,1000)],
		[Vector2i(600,0), Vector2i(1000,0), Vector2i(1000,1000), Vector2i(600,1000)],
		[Vector2i(400,0), Vector2i(600,0), Vector2i(600,800), Vector2i(400,800)]]
	for i in polys.size():
		var ids := PackedInt32Array()
		for p: Vector2i in polys[i]:
			ids.append(repo.vertices.size())
			repo.vertices[repo.vertices.size()] = ArmySystem.metres_to_pack(repo, p)
		repo.cells[i + 1] = {"vertex_ids": ids, "height": 30.0, "biome_id": 1}
		repo.manors[i + 1] = {"province_code": outside if i == 3 else inside}
	repo.province_borders = {inside: [], outside: []}
	for i in polys.size():
		repo.province_borders[outside if i == 3 else inside].append(MapEconomy.cell_polygon(repo, repo.cells[i + 1]))
	MapEconomy.forget()
	state.manor_province.clear()
	state.battles = [{"id": 9460, "att": [code], "def": [enemy], "rounds": 0, "town": "",
		"actions": {"att": {"kind": "hold"}, "def": {"kind": "retreat"}}}]
	var order := {"id": "route", "unit": code, "battle_id": 9460, "task": "pursue", "target_unit": enemy}
	var bounds := extra.duplicate()
	if bounds.get("region", "") == "inside":
		bounds["region"] = inside
	order.merge(bounds)
	assert_eq(BattleTaskSystem.issue_task(repo, state, order).status, "pending")
	assert_eq(BattleTaskSystem.deliver_task(repo, state, "route").status, "received")
	state.battles.clear()
	return {"repo": repo, "state": state, "code": code, "inside": inside, "outside": outside, "enemy": enemy}

func _step(f: Dictionary, budget: int, index := 0, slices := 1) -> void:
	var state: GameState = f.state
	if state.day_resolution.is_empty():
		state.day_resolution = DayResolution.begin(state.day, false, state.absolute_day(), slices)
		state.day_resolution["march_entries"] = {f.code: state.regiments[f.code].duplicate(true)}
		state.day_resolution["march_budgets"] = {f.code: budget}
	ArmySystem.march_day_saved(f.repo, state, slices, index, state.day_resolution.march_entries,
		state.day_resolution.march_budgets)

func _assert_stop(f: Dictionary, at: Vector2i, metres: int) -> void:
	var e: Dictionary = f.state.regiments[f.code]
	assert_eq(Vector2i(int(e.x_m), int(e.y_m)), at)
	assert_eq(e.order, ArmySystem.ORDER_GARRISON)
	var task := BattleTaskSystem.current(f.state, f.code)
	assert_eq(task.status, "bounded")
	assert_eq(int(task.pursuit.route_m), metres)
	assert_eq(String(f.state.unit_tasks[f.code].current_id), "route")

func test_distance_clips_before_substep_overshoot() -> void:
	var f := _fixture([Vector2i(900,100)], {"max_route_m": 250})
	_step(f, 800)
	_assert_stop(f, Vector2i(350,100), 250)

func test_inside_endpoints_cannot_leave_and_reenter() -> void:
	var f := _fixture([Vector2i(900,100)], {"region": "inside"})
	_step(f, 800)
	_assert_stop(f, Vector2i(400,100), 300)

func test_first_of_region_and_distance_wins() -> void:
	for limit in [250, 500]:
		var f := _fixture([Vector2i(900,100)], {"region": "inside", "max_route_m": limit})
		_step(f, 800)
		var walked := mini(limit, 300)
		_assert_stop(f, Vector2i(100 + walked,100), walked)

func test_detour_metres_count_instead_of_displacement() -> void:
	# 200 north + 300 east + 100 south = 600; displacement is sqrt(300²+100²).
	var f := _fixture([Vector2i(100,300), Vector2i(400,300), Vector2i(400,100)], {"max_route_m": 600})
	_step(f, 1000)
	_assert_stop(f, Vector2i(400,200), 600)

func test_later_route_leg_cannot_exit_before_inside_destination() -> void:
	# 100 north, 300 east to boundary: x=400,y=200, total 400.
	var f := _fixture([Vector2i(100,200), Vector2i(900,200), Vector2i(900,100)], {"region": "inside"})
	_step(f, 1000)
	_assert_stop(f, Vector2i(400,200), 400)

func test_midpoint_json_retry_and_same_meaning_reissue_keep_distance() -> void:
	var f := _fixture([Vector2i(900,100)], {"max_route_m": 350})
	_step(f, 800, 0, 4)
	assert_eq(int(BattleTaskSystem.current(f.state, f.code).pursuit.route_m), 200)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	var replay := f.duplicate()
	replay.state = back
	for branch: Dictionary in [f, replay]:
		_step(branch, 800, 1, 4)
		_assert_stop(branch, Vector2i(450,100), 350)
		var before := JSON.stringify(branch.state.to_dict())
		_step(branch, 800, 1, 4)
		assert_eq(JSON.stringify(branch.state.to_dict()).sha256_text(), before.sha256_text(), "retry cannot walk/credit again")
	assert_eq(JSON.stringify(back.to_dict()).sha256_text(), JSON.stringify(f.state.to_dict()).sha256_text())

func test_same_meaning_reissue_keeps_partial_and_completed_budget() -> void:
	var f := _fixture([Vector2i(900,100)], {"max_route_m": 350})
	_step(f, 800, 0, 4)
	# Receipt still requires the original live battle; movement itself was out of it.
	var battle := {"id": 9460, "att": [f.code], "def": [f.enemy], "rounds": 0, "town": ""}
	for id: String in ["partial", "completed"]:
		f.state.battles = [battle]
		var order: Dictionary = BattleTaskSystem.current(f.state, f.code).request.duplicate()
		order.id = id
		assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, order).status, "pending")
		var received := BattleTaskSystem.deliver_task(f.repo, f.state, id)
		assert_eq(int(received.pursuit.route_m), 200 if id == "partial" else 350)
		assert_eq(received.status, "received" if id == "partial" else "bounded")
		f.state.battles.clear()
		if id == "partial":
			_step(f, 800, 1, 4)
	assert_eq(int(f.state.regiments[f.code].x_m), 450)

func test_target_return_does_not_restart_bounded_task_or_leave_contact() -> void:
	var f := _fixture([Vector2i(900,100)], {"max_route_m": 250})
	_step(f, 800)
	var e: Dictionary = f.state.regiments[f.code]
	var before := Vector2i(int(e.x_m), int(e.y_m))
	f.state.foes[f.enemy].x_m = 360
	f.state.foes[f.enemy].y_m = 100
	f.state.day += 1
	BattleTaskSystem.track_day(f.repo, f.state)
	_assert_stop(f, before, 250)
	var battle := {"id": 9460, "att": [f.code], "def": [f.enemy], "rounds": 0, "town": "",
		"actions": {"att": {"kind": "attack"}, "def": {"kind": "attack"}},
		"groups": {f.code: [{"count": 50, "role": "front", "x_m": before.x, "y_m": before.y}],
			f.enemy: [{"count": 50, "role": "front", "x_m": 360, "y_m": 100}]}}
	f.state.battles = [battle]
	assert_eq(BattleSystem.unit_action(f.repo, f.state, battle, f.code).kind, "hold")
	assert_eq(BattleGroups.engaged_permille(f.repo, f.state, battle, f.code), 1000)
	assert_eq(Vector2i(int(e.x_m), int(e.y_m)), before, "real self-defence does not teleport away")

func test_packing_does_not_walk_or_spend_pursuit_distance() -> void:
	var f := _fixture([Vector2i(900,100)], {"max_route_m": 250})
	f.state.regiments[f.code]["camp_state"] = {"phase": CampSystem.PACKING,
		"ready_day": f.state.absolute_day() + 2, "started_day": f.state.absolute_day()}
	_step(f, 800)
	assert_eq(int(f.state.regiments[f.code].x_m), 100)
	assert_eq(int(BattleTaskSystem.current(f.state, f.code).pursuit.route_m), 0)
	assert_eq(BattleTaskSystem.current(f.state, f.code).status, "received")

func test_actual_withdrawal_can_cross_pursuit_limit() -> void:
	var f := _fixture([Vector2i(900,100)], {"max_route_m": 250, "region": "inside"})
	f.state.regiments[f.code]["disengaging"] = 1
	f.state.regiments[f.code]["battle_retreat"] = true
	_step(f, 800)
	assert_eq(int(f.state.regiments[f.code].x_m), 900)
	assert_eq(int(BattleTaskSystem.current(f.state, f.code).pursuit.route_m), 0)

func test_diagonal_rounding_never_exceeds_distance() -> void:
	var f := _fixture([Vector2i(900,900)], {"max_route_m": 250})
	_step(f, 1000)
	var e: Dictionary = f.state.regiments[f.code]
	# (177,177) would be 250.315 m. The inner rounded point is (176,176).
	_assert_stop(f, Vector2i(276,276), 249)
	assert_lte(Vector2(100,100).distance_to(Vector2(e.x_m,e.y_m)), 250.0)

func test_live_province_change_moves_the_route_boundary() -> void:
	var f := _fixture([Vector2i(900,100)], {"region": "inside"})
	f.state.manor_province["4"] = f.inside
	_step(f, 800)
	assert_eq(int(f.state.regiments[f.code].x_m), 900)
	assert_eq(BattleTaskSystem.current(f.state, f.code).status, "received")

func test_border_query_is_pure_and_includes_multiple_provinces() -> void:
	var f := _fixture([Vector2i(900,100)], {"region": "inside"})
	var before := JSON.stringify(f.state.to_dict()).sha256_text()
	assert_almost_eq(MarchPath.region_exit(f.repo, f.state, Vector2i(100,100), [Vector2i(900,100)], f.inside), 300.0, 0.01)
	assert_eq(MarchPath.region_exit(f.repo, f.state, Vector2i(100,100), [Vector2i(900,100)], f.inside + "|" + f.outside), -1.0)
	assert_eq(JSON.stringify(f.state.to_dict()).sha256_text(), before)

func _isolate_clearance(f: Dictionary, blocker: String, at: Vector2i) -> void:
	f.repo.balance["army_clearance_on"] = 1
	for arm: String in f.repo.army_clearance:
		f.repo.army_clearance[arm] = 20
	for code: String in f.state.army_roster.keys():
		if code not in [f.code, blocker]:
			f.state.army_roster.erase(code)
			f.state.regiments.erase(code)
			f.state.foes.erase(code)
	var e: Dictionary = f.state.foes.get(blocker, f.state.regiments.get(blocker, {}))
	e.merge({"x_m": at.x, "y_m": at.y, "dest_x_m": at.x, "dest_y_m": at.y,
		"order": ArmySystem.ORDER_GARRISON, "camp_town": ""}, true)
	Personnel.replace(f.repo, f.state, blocker, 100)

func test_clearance_enemy_halt_cannot_jump_past_the_earlier_bound() -> void:
	for region: bool in [false, true]:
		var f := _fixture([Vector2i(900,100)], {"region": "inside"} if region else {"max_route_m": 250})
		_isolate_clearance(f, f.enemy, Vector2i(600,100))
		_step(f, 800)
		_assert_stop(f, Vector2i(400,100) if region else Vector2i(350,100), 300 if region else 250)
		assert_false(f.state.regiments[f.code].has("halted_by"), "the boundary precedes contact")

func test_earlier_real_contact_keeps_membership_and_credits_the_approach() -> void:
	var f := _fixture([Vector2i(900,100)], {"max_route_m": 700})
	_isolate_clearance(f, f.enemy, Vector2i(600,100))
	_step(f, 800)
	# D=20+20, halt is D+1 west of x600: 559, walk459.
	assert_eq(int(f.state.regiments[f.code].x_m), 559)
	assert_eq(String(f.state.regiments[f.code].halted_by), f.enemy)
	assert_eq(int(BattleTaskSystem.current(f.state, f.code).pursuit.route_m), 459)
	assert_eq(BattleTaskSystem.current(f.state, f.code).status, "received")

func test_clearance_detour_is_charged_before_distance_stop() -> void:
	var f := _fixture([Vector2i(900,100)], {"max_route_m": 600})
	var codes: Array = f.state.regiments.keys()
	codes.erase(f.code)
	codes.sort()
	_isolate_clearance(f, String(codes[0]), Vector2i(600,100))
	_step(f, 1000)
	var e: Dictionary = f.state.regiments[f.code]
	var progress := int(BattleTaskSystem.current(f.state, f.code).pursuit.route_m)
	assert_eq(BattleTaskSystem.current(f.state, f.code).status, "bounded")
	assert_lte(progress, 600)
	assert_gte(progress, 599)
	assert_lt(int(e.x_m), 700, "the detour rejoins the line but spends metres before the stop")
	assert_lt(Vector2(100,100).distance_to(Vector2(e.x_m,e.y_m)), float(progress))

func test_enclosed_region_hole_is_not_skipped() -> void:
	var f := _fixture([Vector2i(900,100)], {"region": "inside"})
	var outer := PackedVector2Array()
	var hole := PackedVector2Array()
	for p: Vector2i in [Vector2i(0,0), Vector2i(1000,0), Vector2i(1000,1000), Vector2i(0,1000)]:
		outer.append(ArmySystem.metres_to_pack(f.repo, p))
	for p: Vector2i in [Vector2i(400,50), Vector2i(600,50), Vector2i(600,800), Vector2i(400,800)]:
		hole.append(ArmySystem.metres_to_pack(f.repo, p))
	f.repo.province_borders[f.inside] = [outer, hole]
	_step(f, 800)
	_assert_stop(f, Vector2i(400,100), 300)

func test_legacy_march_and_preview_share_bounds_without_preview_mutation() -> void:
	var f := _fixture([Vector2i(900,100)], {"max_route_m": 250})
	var before := JSON.stringify(f.state.to_dict()).sha256_text()
	var preview: Dictionary = f.state.regiments[f.code].duplicate(true)
	ArmySystem._march_one(f.repo, f.state, f.code, preview, f.state.absolute_day(), {}, [], 1, 0, 800, 800)
	assert_eq(int(preview.x_m), 350)
	assert_eq(JSON.stringify(f.state.to_dict()).sha256_text(), before)
	ArmySystem.march_day(f.repo, f.state, 1, 0, true, [f.code], {f.code: 800})
	_assert_stop(f, Vector2i(350,100), 250)

func test_zero_walk_bound_cancels_saved_packing_departure() -> void:
	var f := _fixture([Vector2i(900,100)], {"max_route_m": 250})
	var e: Dictionary = f.state.regiments[f.code]
	e["departure"] = {"dest_x_m": 900, "dest_y_m": 100, "waypoints_m": []}
	e["camp_state"] = {"phase": CampSystem.PACKING, "move_not_before_day": f.state.absolute_day() + 2}
	assert_true(BattleTaskSystem.credit_pursuit(f.repo, f.state, f.code, 250))
	assert_false(e.has("departure"))
	assert_false(e.has("route_m"))
	f.state.day += 3
	ArmySystem.march_day(f.repo, f.state, 1, 0, true, [f.code], {f.code: 800})
	assert_eq(int(e.x_m), 100)
	assert_eq(e.order, ArmySystem.ORDER_GARRISON)

func test_slanting_border_keeps_the_rounded_stop_inside() -> void:
	var f := _fixture([Vector2i(900,400)], {"region": "inside"})
	var triangle := PackedVector2Array()
	for p: Vector2i in [Vector2i(0,0), Vector2i(501,0), Vector2i(0,501)]:
		triangle.append(ArmySystem.metres_to_pack(f.repo, p))
	f.repo.province_borders[f.inside] = [triangle]
	_step(f, 1000)
	var e: Dictionary = f.state.regiments[f.code]
	assert_eq(BattleTaskSystem.current(f.state, f.code).status, "bounded")
	assert_lte(int(e.x_m) + int(e.y_m), 501)
	assert_gte(int(e.x_m) + int(e.y_m), 499)
	assert_eq(MarchPath.region_exit(f.repo, f.state, Vector2i(100,100),
		[Vector2i(int(e.x_m),int(e.y_m))], f.inside), -1.0)

func test_short_diagonal_destination_arrives_without_spending_a_bound() -> void:
	var f := _fixture([Vector2i(101,101)], {"max_route_m": 250})
	_step(f, 800)
	var e: Dictionary = f.state.regiments[f.code]
	assert_eq(Vector2i(int(e.x_m), int(e.y_m)), Vector2i(101,101))
	assert_eq(e.order, ArmySystem.ORDER_GARRISON)
	var task := BattleTaskSystem.current(f.state, f.code)
	assert_eq(task.status, "received")
	assert_eq(int(task.pursuit.route_m), 2)
