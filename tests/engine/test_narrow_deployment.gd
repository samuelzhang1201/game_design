extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func after_each() -> void:
	MarchPath.forget()
	RoadGraph.forget()

func _fixture(people := 101, legacy := false) -> Dictionary:
	var repo := SuiteData.open_country(SuiteData.repo())
	repo.balance["army_living_cap_men"] = 10000.0 # isolated scale fixture, not production capacity
	repo.balance["battle_group_spacing_m"] = 20.0
	repo.balance["battle_group_depth_m"] = 20.0
	repo.balance["battle_line_gap_m"] = 40.0
	repo.balance["battle_deploy_step_m"] = 10.0
	var state := SuiteData.campaign(repo, 9459)
	var codes := state.regiments.keys()
	codes.sort()
	var a := String(codes[0])
	var enemies := state.foes.keys()
	enemies.sort()
	var enemy := String(enemies[0])
	assert_false(Personnel.replace(repo, state, a, people).has("error"))
	Personnel.replace(repo, state, enemy, 0)
	state.regiments[a].merge({"x_m": 80, "y_m": 100, "facing_deg": 0}, true)
	state.foes[enemy].merge({"x_m": 320, "y_m": 100}, true)
	var battle := {"id": 9459, "att": [a], "def": [enemy], "rounds": 0,
		"town": "", "place_x_m": 220, "place_y_m": 100, "actions": {}}
	state.battles = [battle]
	BattleFormation.ensure(battle)
	battle.formations.att.current = "line"
	if legacy:
		battle.merge({"groups": {}, "group_size_version": 1, "group_size_men": 50})
	BattleGroups.refresh(repo, state, battle)
	# Arrival facts are a single rear lane, not the desired front line.
	for i: int in battle.groups[a].size():
		battle.groups[a][i].x_m = 80 - i * 20
		battle.groups[a][i].y_m = 100
	return {"repo": repo, "state": state, "battle": battle, "a": a, "enemy": enemy}

func _strip(f: Dictionary, low := 89, high := 111) -> MarchPath:
	var bytes := PackedByteArray()
	bytes.resize(500 * 220)
	bytes.fill(255)
	for y: int in range(low, high):
		for x: int in 500:
			bytes[y * 500 + x] = 0
	f.repo.balance["army_march_grid_px"] = 1.0
	var grid := MarchPath.build(f.repo, 500, 220, 1, bytes)
	MarchPath.use(f.repo, grid)
	return grid

func _points(rows: Array) -> Array:
	return rows.map(func(row: Dictionary) -> Vector2i: return Vector2i(int(row.x_m), int(row.y_m)))

func test_one_lane_adds_depth() -> void:
	var f := _fixture()
	_strip(f)
	var before := JSON.stringify(f.state.to_dict())
	var goals := BattleGroups.targets(f.repo, f.state, f.battle, f.a)
	assert_eq(_points(goals), [Vector2i(200, 100), Vector2i(180, 100)])
	assert_eq(goals.map(func(row: Dictionary) -> String: return row.role), ["front", "reserve"])
	assert_eq(f.battle.groups[f.a].map(func(row: Dictionary) -> int: return row.count), [100, 1])
	assert_eq(JSON.stringify(f.state.to_dict()), before, "target queries are pure")

func test_frozen_fifty_has_three_slots() -> void:
	var f := _fixture(101, true)
	_strip(f)
	assert_eq(BattleGroups.saved_size(f.repo, f.battle), 50)
	assert_eq(f.battle.groups[f.a].map(func(row: Dictionary) -> int: return row.count), [50, 50, 1])
	assert_eq(_points(BattleGroups.targets(f.repo, f.state, f.battle, f.a)),
		[Vector2i(200, 100), Vector2i(180, 100), Vector2i(160, 100)])

func test_no_legal_front_waits() -> void:
	var f := _fixture()
	_strip(f, 95, 105)
	assert_eq(BattleGroups.targets(f.repo, f.state, f.battle, f.a), [])
	var before := _points(f.battle.groups[f.a])
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_points(f.battle.groups[f.a]), before)

func test_disconnected_destination_rejected() -> void:
	var f := _fixture(1)
	var grid := _strip(f)
	for y: int in 220:
		grid.closed[y * 500 + 140] = 1
	var before := _points(f.battle.groups[f.a])
	assert_eq(BattleGroups.targets(f.repo, f.state, f.battle, f.a), [])
	var result := BattleGroups.move_row(f.repo, f.state, f.battle, f.a, 0, [Vector2i(200, 100)], 200)
	assert_eq(result.at, Vector2i(80, 100))
	assert_eq(_points(f.battle.groups[f.a]), before)

func test_partial_group_uses_one_slot() -> void:
	for people: int in [0, 1, 49, 50, 51, 800, 1000, 10000]:
		var f := _fixture(people)
		_strip(f)
		var goals := BattleGroups.targets(f.repo, f.state, f.battle, f.a)
		assert_eq(goals.filter(func(row: Dictionary) -> bool: return row.role == "front").size(), 0 if people == 0 else 1)
		assert_eq(f.battle.groups[f.a].reduce(func(n: int, row: Dictionary) -> int: return n + int(row.count), 0), people)

func test_two_lanes_and_all_four_shapes() -> void:
	for shape: String in ["line", "double_rank", "wedge", "diamond"]:
		var f := _fixture(800)
		_strip(f, 79, 121)
		f.battle.formations.att.current = shape
		var goals := BattleGroups.targets(f.repo, f.state, f.battle, f.a)
		for row: Dictionary in goals:
			assert_true(int(row.y_m) >= 89 and int(row.y_m) <= 111, shape)
		assert_lte(goals.filter(func(row: Dictionary) -> bool: return row.role == "front").size(), 2)
		assert_gt(goals.size(), 0, shape)
	var f := _fixture(401)
	_strip(f, 79, 121)
	var fronts := BattleGroups.targets(f.repo, f.state, f.battle, f.a).filter(func(row: Dictionary) -> bool: return row.role == "front")
	assert_eq(_points(fronts), [Vector2i(200, 90), Vector2i(200, 110)])

func test_sweep_checks_interior_endcap_and_raw_bounds() -> void:
	var f := _fixture(1)
	var grid := _strip(f, 0, 220)
	# The centre and both offset edges miss this cell inside the capsule.
	grid.closed[105 * 500 + 120] = 1
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(80, 100), [Vector2i(160, 100)]))
	assert_false(BattleCharge._clear(f.repo, f.battle, f.a, Vector2i(80, 0)))
	grid.closed[105 * 500 + 120] = 0
	grid.closed[105 * 500 + 166] = 1
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(80, 100), [Vector2i(160, 100)]))
	grid.closed[105 * 500 + 166] = 0
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(80, 100), [Vector2i(-20, 100)]))
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(80, 100), [Vector2i(5, 100)]))
	grid.closed[110 * 500 + 120] = 1
	assert_true(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(80, 100), [Vector2i(160, 100)]), "tangency is legal")

func test_one_budget_mean_anchor_and_retry() -> void:
	var f := _fixture()
	_strip(f)
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_points(f.battle.groups[f.a]), [Vector2i(90, 100), Vector2i(70, 100)])
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), Vector2i(80, 100))
	var before := JSON.stringify(f.state.to_dict())
	BattleGroups.follow_anchor(f.repo, f.state, f.battle, f.a)
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(JSON.stringify(f.state.to_dict()), before)
	f.battle.pending_round = {"day": 1}
	f.state.day += 1
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_points(f.battle.groups[f.a]), [Vector2i(90, 100), Vector2i(70, 100)])

func test_move_row_inward_budget_and_own_reserve_occupancy() -> void:
	var f := _fixture(1)
	var result := BattleGroups.move_row(f.repo, f.state, f.battle, f.a, 0, [Vector2i(100, 100)], 10)
	assert_eq(result.at, Vector2i(90, 100))
	assert_eq(result.moved_m, 10)
	f.battle.groups[f.a].append({"slot": 1, "count": 1, "role": "reserve", "x_m": 120, "y_m": 100})
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(90, 100), [Vector2i(130, 100)]))
	assert_true(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, -1, Vector2i(80, 100), [Vector2i(90, 100)]))

func test_seed_and_reinforcement_do_not_snap() -> void:
	var f := _fixture(1)
	_strip(f)
	var before := _points(f.battle.groups[f.a])
	BattleGroups.targets(f.repo, f.state, f.battle, f.a)
	assert_eq(_points(f.battle.groups[f.a]), before)
	Personnel.replace(f.repo, f.state, f.a, 201)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var arrived := _points(f.battle.groups[f.a])
	BattleGroups.targets(f.repo, f.state, f.battle, f.a)
	assert_eq(_points(f.battle.groups[f.a]), arrived)

func test_private_detour_preserves_pack_and_routes_full_disk() -> void:
	var f := _fixture(1)
	var grid := _strip(f, 0, 220)
	for y: int in range(95, 106):
		grid.closed[y * 500 + 140] = 1
	var before := grid.closed.duplicate()
	var path := BattleGroups._route(f.repo, f.state, f.battle, f.a, 0, Vector2i(80, 100), Vector2i(200, 100))
	assert_gt(path.size(), 1, "a clear centre-only rejection must still find a full-disk detour")
	assert_true(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(80, 100), path))
	assert_eq(grid.closed, before)
	var moved := BattleGroups.move_row(f.repo, f.state, f.battle, f.a, 0, path, 10)
	assert_lte(Vector2(80, 100).distance_to(Vector2(moved.at)), 10.0)

func test_open_ground_keeps_native_shapes_and_json_retry() -> void:
	for shape: String in ["line", "double_rank", "wedge", "diamond"]:
		var f := _fixture(800)
		f.battle.formations.att.current = shape
		var goal: Vector2i = BattleGroups.deployment(f.repo, f.state, f.battle)[f.a]
		assert_eq(_points(BattleGroups.targets(f.repo, f.state, f.battle, f.a)), BattleGroups.layout(f.repo, shape, 8, goal, 0), shape)
	var f := _fixture(101)
	_strip(f)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	BattleGroups.deploy_day(f.repo, restored, restored.battles[0])
	assert_eq(SaveLoad.state_hash(f.state), SaveLoad.state_hash(restored))

func test_flank_snapshot_uses_actual_rows_after_mean_summary() -> void:
	var f := _fixture(1)
	Personnel.replace(f.repo, f.state, f.enemy, 101)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	f.battle.groups[f.enemy][0].merge({"x_m": 320, "y_m": 100}, true)
	f.battle.groups[f.enemy][1].merge({"x_m": 360, "y_m": 150}, true)
	BattleGroups._mean_anchor(f.repo, f.state, f.battle, f.enemy)
	var record := {"request": {"target_unit": f.enemy}}
	BattleTaskSystem._snapshot_flank(f.repo, f.state, f.a, record)
	assert_eq(record.flank.known.points_m, [[320, 100], [360, 150]], "summary anchor cannot reconstruct non-rigid rows")

func test_real_flank_and_charge_stop_on_enclosed_footprint_cell() -> void:
	var f := _fixture(1)
	Personnel.replace(f.repo, f.state, f.enemy, 1)
	for code: String in [f.a, f.enemy]:
		var entry := BattleSystem._stored(f.state, code)
		entry.erase("camp_town")
		entry.supplies = 100000
		entry.morale = 100
		entry.order = ArmySystem.ORDER_STANDBY
	f.repo.balance["battle_deploy_step_m"] = 80.0
	f.battle.actions = {"att": {"kind": "hold"}, "def": {"kind": "hold"}}
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var grid := _strip(f, 0, 220)
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, {"id": "narrow:flank", "unit": f.a,
		"battle_id": 9459, "task": "flank", "target_unit": f.enemy}).status, "pending")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "narrow:flank").status, "received")
	var record := BattleTaskSystem._find(f.state, "narrow:flank")
	BattleTaskSystem._snapshot_flank(f.repo, f.state, f.a, record)
	var here := BattleSystem._at_m(f.repo, f.state, f.a)
	var path := BattleTaskSystem._flank_path(f.repo, f.state, f.a, record)
	assert_false(path.is_empty(), str(record))
	if path.is_empty(): return
	var next: Vector2i = MarchRoute.walk(here, [path[0]], 80).at
	var axis := Vector2(next - here).normalized()
	var rock := Vector2i((Vector2(here + next) / 2.0 + Vector2(-axis.y, axis.x) * 6.0).round())
	grid.closed[rock.y * 500 + rock.x] = 1
	assert_true(grid.clear(here, next), "the centre line misses the rock")
	assert_true(BattleTaskSystem.deploy_flank(f.repo, f.state, f.battle, f.a))
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), here, "actual flank writer cannot move its full disk over the rock")
	grid.closed[rock.y * 500 + rock.x] = 0
	grid.closed[105 * 500 + 120] = 1
	f.battle.actions.att.kind = "attack"
	BattleCharge.move(f.repo, f.state, f.battle, f.a, f.enemy)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), here, "actual charge writer cannot move its full disk over the rock")
	assert_eq(int(f.state.regiments[f.a].charge.runup_m), 0)

func _overlap_fixture() -> Dictionary:
	var f := _fixture(101)
	f.repo.balance["battle_group_spacing_m"] = 50.0
	f.repo.balance["battle_group_depth_m"] = 40.0
	f.battle.groups[f.a][0].merge({"x_m": 100, "y_m": 100}, true)
	f.battle.groups[f.a][1].merge({"x_m": 60, "y_m": 100}, true)
	return f

func test_existing_same_unit_overlap_only_separates_until_clear() -> void:
	var f := _overlap_fixture()
	var here := Vector2i(100, 100)
	assert_true(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, here, [Vector2i(110, 100)]), "40 -> 50 exits")
	assert_true(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, here, [Vector2i(100, 110)]), "40 -> sqrt(1700), tangent departure")
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, here, [Vector2i(90, 100), Vector2i(120, 100)]), "a farther endpoint cannot excuse a closer leg")
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, here, [Vector2i(110, 100), Vector2i(109, 100)]), "once clear, no reentry")
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, here, [Vector2i(105, 100), Vector2i(104, 100)]), "every still-overlapping leg must separate")
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(90, 100), [here]), "arbitrary query origin cannot manufacture eligibility")
	var before := _points(f.battle.groups[f.a])
	var walked := BattleGroups.move_row(f.repo, f.state, f.battle, f.a, 0, [Vector2i(120, 100)], 10)
	assert_eq(walked.at, Vector2i(110, 100))
	assert_eq(int(walked.moved_m), 10)
	assert_eq(_points(f.battle.groups[f.a])[1], before[1], "the stationary partner is untouched")
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, walked.at, [Vector2i(109, 100)]))

func test_overlap_exception_never_applies_across_units_or_to_terrain() -> void:
	var f := _overlap_fixture()
	var row: Dictionary = f.battle.groups[f.a].pop_back()
	f.battle.groups[f.enemy] = [row]
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(100, 100), [Vector2i(110, 100)]))
	var codes: Array = f.state.regiments.keys()
	codes.sort()
	f.battle.groups[String(codes[1])] = f.battle.groups[f.enemy]
	f.battle.groups[f.enemy] = []
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(100, 100), [Vector2i(110, 100)]), "another friendly unit is also excluded")
	f.battle.groups.erase(String(codes[1]))
	f.battle.groups[f.a].append(row)
	var grid := _strip(f, 0, 220)
	grid.closed[110 * 500 + 105] = 1
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(100, 100), [Vector2i(110, 100)]), "separating people never opens a footprint obstacle")
	grid.closed[110 * 500 + 105] = 0
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 1, Vector2i(60, 100), [Vector2i(20, 100)]), "raw bounds still contain the full disk")

func test_coincident_and_multiple_overlap_partners_all_require_separation() -> void:
	var f := _overlap_fixture()
	f.battle.groups[f.a][1].x_m = 100
	assert_true(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(100, 100), [Vector2i(110, 100)]))
	var walked := BattleGroups.move_row(f.repo, f.state, f.battle, f.a, 0, [Vector2i(100, 100)], 10)
	assert_eq(walked.moved_m, 0, "zero-length holding gives no travel")
	f.battle.groups[f.a][1].x_m = 60
	f.battle.groups[f.a].append({"slot": 2, "count": 1, "role": "reserve", "x_m": 140, "y_m": 100})
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(100, 100), [Vector2i(110, 100)]), "separating from the rear cannot deepen the front overlap")
	assert_true(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(100, 100), [Vector2i(100, 110)]))
	f.battle.groups[f.a][2].x_m = 160
	assert_false(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(100, 100), [Vector2i(120, 100)]), "a new blocker at 60 cannot acquire an exception")

func test_production_double_rank_physically_exits_and_has_legal_targets() -> void:
	var f := _fixture(1000)
	var production := SuiteData.repo()
	for key: String in ["army_living_cap_men", "battle_group_spacing_m", "battle_group_depth_m", "battle_line_gap_m", "battle_deploy_step_m"]:
		f.repo.balance[key] = production.balance[key]
	f.state.regiments[f.a].merge({"x_m": 5000, "y_m": 5000, "facing_deg": 0, "order": ArmySystem.ORDER_STANDBY}, true)
	f.state.regiments[f.a].erase("camp_town")
	f.state.foes[f.enemy].merge({"x_m": 9000, "y_m": 5000}, true)
	f.battle.place_x_m = 7000
	f.battle.place_y_m = 5000
	f.battle.formations.att.current = "double_rank"
	f.battle.erase("groups")
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var before := _points(f.battle.groups[f.a])
	var goals := BattleGroups.targets(f.repo, f.state, f.battle, f.a)
	assert_eq(goals.size(), 10, "production depth40 must skip the overlapping candidate rank, not lose five targets")
	for i: int in goals.size():
		for j: int in range(i + 1, goals.size()):
			assert_gte(_points(goals)[i].distance_squared_to(_points(goals)[j]), 2500)
	assert_eq(_points(f.battle.groups[f.a]), before, "query leaves native source facts unchanged")
	var replay := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	BattleGroups.deploy_day(f.repo, replay, replay.battles[0])
	var moving_front := 0
	for i: int in before.size():
		var now: Vector2i = _points(f.battle.groups[f.a])[i]
		if i % 2 == 0 and now != before[i]: moving_front += 1
		assert_lte(Vector2(before[i]).distance_to(Vector2(now)), float(production.bal("battle_deploy_step_m")))
	assert_gt(moving_front, 0, "real production front rows must physically leave their existing overlap")
	assert_eq(ArmySystem.fit_count(f.repo, f.state, f.a), 1000)
	assert_eq(SaveLoad.state_hash(f.state), SaveLoad.state_hash(replay))
	var hash_after := SaveLoad.state_hash(f.state)
	BattleGroups.follow_anchor(f.repo, f.state, f.battle, f.a)
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(SaveLoad.state_hash(f.state), hash_after)

func test_overlap_does_not_open_contact_through_a_closed_footprint() -> void:
	var f := _overlap_fixture()
	Personnel.replace(f.repo, f.state, f.enemy, 1)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	f.battle.groups[f.enemy][0].merge({"x_m": 160, "y_m": 100}, true)
	var grid := _strip(f, 0, 220)
	assert_eq(BattleGroups.engaged_counts(f.repo, f.state, f.battle, f.a).x, 101)
	grid.closed[105 * 500 + 110] = 1
	assert_eq(BattleGroups.engaged_counts(f.repo, f.state, f.battle, f.a).x, 0, "the same closed full footprint bars offensive contact")

func test_overlap_pending_round_and_dictionary_order_remain_deterministic() -> void:
	var f := _overlap_fixture()
	var before := _points(f.battle.groups[f.a])
	f.battle.pending_round = {"day": f.state.absolute_day()}
	var frozen := SaveLoad.state_hash(f.state)
	BattleGroups.move_row(f.repo, f.state, f.battle, f.a, 0, [Vector2i(110, 100)], 10)
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_points(f.battle.groups[f.a]), before)
	assert_eq(SaveLoad.state_hash(f.state), frozen)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	BattleGroups.deploy_day(f.repo, restored, restored.battles[0])
	assert_eq(SaveLoad.state_hash(restored), frozen)
	f.battle.erase("pending_round")
	restored.battles[0].erase("pending_round")
	var reversed := {}
	var codes: Array = restored.battles[0].groups.keys()
	codes.reverse()
	for code: String in codes: reversed[code] = restored.battles[0].groups[code]
	restored.battles[0].groups = reversed
	BattleGroups.move_row(f.repo, f.state, f.battle, f.a, 0, [Vector2i(110, 100)], 10)
	BattleGroups.move_row(f.repo, restored, restored.battles[0], f.a, 0, [Vector2i(110, 100)], 10)
	assert_eq(SaveLoad.state_hash(restored), SaveLoad.state_hash(f.state))

func test_coarse_pack_grid_still_routes_around_group_sized_occupancy() -> void:
	var f := _fixture(1)
	f.repo.balance["battle_group_spacing_m"] = 50.0
	f.repo.balance["army_march_grid_px"] = 1.0
	MarchPath.use(f.repo, MarchPath.build(f.repo, 4, 4, 4000, PackedByteArray([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0])))
	f.battle.groups[f.a][0].merge({"x_m": 5000, "y_m": 5000}, true)
	f.battle.groups[f.enemy] = [{"slot": 0, "count": 1, "role": "front", "x_m": 5060, "y_m": 5000}]
	var path := BattleGroups._route(f.repo, f.state, f.battle, f.a, 0, Vector2i(5000, 5000), Vector2i(5120, 5000))
	assert_false(path.is_empty(), "a 4km terrain cell cannot erase a legal 50m occupancy detour")
	assert_true(BattleGroups.sweep_clear(f.repo, f.state, f.battle, f.a, 0, Vector2i(5000, 5000), path))
	assert_lt(MarchRoute.length_from(Vector2i(5000, 5000), path), 250.0, "do not send a 120m tactical move kilometres via a pack cell centre")
