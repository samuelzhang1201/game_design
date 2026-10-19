extends GutTest
## P4.4c4: known-target tracking and the limited search for a received flank /
## pursuit task (spec 2026-10-17-unit-behavior-and-battlefield-design §9). Flat
## ground, the player_sight_km of 12 km (12 000 m) and battle_search_days 2 and
## battle_search_range_m 8 000. Unit at (1 000 000, 1 000 000); a foe 5 000 m
## east is seen (25e6 <= 144e6): the unit aims at it. The foe 20 000 m away is
## not (4e8 > 1.44e8): the unit keeps the old point. On the point on day D the
## search runs to D + 2; day D + 3 is past it. In search a foe 6 000 m from the
## point is within 8 000 (follow), 9 000 m is not (still search).
const SuiteData := preload("res://tests/suite_data.gd")
const BASE := Vector2i(1000000, 1000000)

func _fixture(task := "pursue") -> Dictionary:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var state := SuiteData.campaign(repo, 9444)
	state.tick = 1
	state.day = 10
	state.battles.clear()
	state.ai_hosts.clear()
	var enemy := String(state.foes.keys()[0])
	var codes: Array = state.regiments.keys()
	codes.sort()
	var a := String(codes[0])
	var battle := {"id": 9444, "att": [a], "def": [enemy], "rounds": 0, "town": "",
		"place_x_m": 0, "place_y_m": 0, "actions": {"att": {"kind": "hold"}, "def": {"kind": "retreat"}}}
	state.battles = [battle]
	var e: Dictionary = state.regiments[a]
	e["x_m"] = BASE.x
	e["y_m"] = BASE.y
	e["dest_x_m"] = BASE.x
	e["dest_y_m"] = BASE.y
	e["order"] = ArmySystem.ORDER_GARRISON
	var f := {"repo": repo, "state": state, "a": a, "enemy": enemy}
	_place_foe(f, BASE + Vector2i(5000, 0))
	var order := {"id": "t1", "unit": a, "battle_id": 9444, "task": task, "target_unit": enemy}
	assert_eq(BattleTaskSystem.issue_task(repo, state, order).get("status"), "pending")
	assert_eq(BattleTaskSystem.deliver_task(repo, state, "t1").get("status"), "received")
	state.battles.clear()   # the unit stands in no battle now
	return f

func _place_foe(f: Dictionary, at: Vector2i) -> void:
	f.state.foes[f.enemy]["x_m"] = at.x
	f.state.foes[f.enemy]["y_m"] = at.y

func _track(f: Dictionary) -> Dictionary:
	return BattleTaskSystem.current(f.state, f.a).get("track", {})

func _next_day(f: Dictionary) -> void:
	f.state.day += 1
	BattleTaskSystem.track_day(f.repo, f.state)

func _dest(f: Dictionary) -> Vector2i:
	var e: Dictionary = f.state.regiments[f.a]
	return Vector2i(int(e["dest_x_m"]), int(e["dest_y_m"]))

## the unit stands on its saved point, as after the march's arrival
func _arrive(f: Dictionary) -> void:
	var e: Dictionary = f.state.regiments[f.a]
	e["x_m"] = int(_track(f)["x_m"])
	e["y_m"] = int(_track(f)["y_m"])
	e["order"] = ArmySystem.ORDER_GARRISON
	e["dest_x_m"] = e["x_m"]
	e["dest_y_m"] = e["y_m"]

func test_a_seen_target_is_followed_and_saved() -> void:
	var f := _fixture()
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_eq(_dest(f), BASE + Vector2i(5000, 0))
	assert_eq(f.state.regiments[f.a]["order"], ArmySystem.ORDER_MARCH)
	var t := _track(f)
	assert_eq([t.x_m, t.y_m, t.phase, t.day], [BASE.x + 5000, BASE.y, "follow", f.state.absolute_day()])

func test_out_of_sight_it_keeps_the_saved_point_and_never_reads_the_truth() -> void:
	var f := _fixture()
	BattleTaskSystem.track_day(f.repo, f.state)
	_place_foe(f, BASE + Vector2i(20000, 0))
	_next_day(f)
	assert_eq(_dest(f), BASE + Vector2i(5000, 0))
	assert_eq(int(_track(f).x_m), BASE.x + 5000)
	assert_eq(_track(f).phase, "follow")

func test_the_target_is_seen_from_the_recipient_alone() -> void:
	var f := _fixture()
	f.state.regiments[f.a]["x_m"] = BASE.x - 8000   # 13 000 m from the foe
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_true(_track(f).is_empty(), "no sighting, no snapshot, no march")
	assert_eq(f.state.regiments[f.a]["order"], ArmySystem.ORDER_GARRISON)

func test_tracking_is_once_a_day() -> void:
	var f := _fixture()
	BattleTaskSystem.track_day(f.repo, f.state)
	_place_foe(f, BASE + Vector2i(7000, 0))
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_eq(_dest(f), BASE + Vector2i(5000, 0))

func test_arriving_on_the_point_starts_the_search() -> void:
	var f := _fixture()
	BattleTaskSystem.track_day(f.repo, f.state)
	_place_foe(f, BASE + Vector2i(20000, 0))
	_arrive(f)
	_next_day(f)
	assert_eq(_track(f).phase, "search")
	assert_eq(int(_track(f).search_until_day), f.state.absolute_day() + 2)

func _searching(f: Dictionary) -> void:
	BattleTaskSystem.track_day(f.repo, f.state)
	_place_foe(f, BASE + Vector2i(20000, 0))
	_arrive(f)
	_next_day(f)

func test_a_failed_search_ends_the_task_for_good() -> void:
	var f := _fixture()
	_searching(f)
	f.state.day += 2
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_eq(BattleTaskSystem.current(f.state, f.a).status, "received", "day +2 is not past it")
	f.state.day += 1
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_eq(BattleTaskSystem.current(f.state, f.a).status, "search_failed")
	assert_eq(f.state.regiments[f.a]["order"], ArmySystem.ORDER_GARRISON)
	assert_eq(_dest(f), BASE + Vector2i(5000, 0), "garrisoned where it stands: the point it searched")
	_place_foe(f, BASE + Vector2i(5000 + 1000, 0))
	_next_day(f)
	assert_eq(BattleTaskSystem.current(f.state, f.a).status, "search_failed")
	assert_eq(_dest(f), BASE + Vector2i(5000, 0))

func test_a_sighting_near_the_point_resumes_the_follow_a_far_one_does_not() -> void:
	var f := _fixture()
	_searching(f)
	_place_foe(f, BASE + Vector2i(5000 + 9000, 0))   # 9 000 m from the point, 9 000 from the unit: seen, too far
	_next_day(f)
	assert_eq(_track(f).phase, "search")
	assert_eq(int(_track(f).x_m), BASE.x + 5000)
	_place_foe(f, BASE + Vector2i(5000 + 6000, 0))
	_next_day(f)
	assert_eq(_track(f).phase, "follow")
	assert_eq(_dest(f), BASE + Vector2i(11000, 0))

func test_the_gait_runs_a_followed_pursuit_but_never_a_flank() -> void:
	var f := _fixture()
	BattleTaskSystem.track_day(f.repo, f.state)
	var e: Dictionary = f.state.regiments[f.a]
	UnitGait.refresh(f.repo, f.state, f.a, e)
	assert_eq(e["gait"], {"mode": "run", "reason": "pursuit", "until": "task_end"})
	_place_foe(f, BASE + Vector2i(20000, 0))
	_arrive(f)
	_next_day(f)   # search: the unit holds, the gait goes
	e["order"] = ArmySystem.ORDER_MARCH
	UnitGait.refresh(f.repo, f.state, f.a, e)
	assert_false(e.has("gait"))
	var g := _fixture("flank")
	BattleTaskSystem.track_day(g.repo, g.state)
	assert_eq(g.state.regiments[g.a]["order"], ArmySystem.ORDER_MARCH, "a flank is followed too")
	var ge: Dictionary = g.state.regiments[g.a]
	UnitGait.refresh(g.repo, g.state, g.a, ge)
	assert_false(ge.has("gait"))

func test_a_unit_in_a_battle_is_not_tracked() -> void:
	var f := _fixture()
	f.state.battles = [{"id": 9445, "att": [f.a], "def": [], "rounds": 0, "town": "",
		"place_x_m": 0, "place_y_m": 0, "actions": {}}]
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_true(_track(f).is_empty())

func test_a_reaim_of_a_packing_march_keeps_its_packing() -> void:
	var f := _fixture()
	var e: Dictionary = f.state.regiments[f.a]
	e["camp_state"] = {"phase": CampSystem.PACKING, "idle_days": 5, "build_progress": 1000,
		"pack_start_day": 3, "move_not_before_day": 4, "last_updated_day": -1, "site": {"x_m": BASE.x, "y_m": BASE.y}}
	e["order"] = ArmySystem.ORDER_MARCH
	e["dest_x_m"] = BASE.x + 900
	e["dest_y_m"] = BASE.y
	e["departure"] = {"dest_x_m": BASE.x + 900, "dest_y_m": BASE.y, "waypoints_m": [], "received_day": 3}
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_eq(_dest(f), BASE + Vector2i(5000, 0))
	assert_eq(int(e["camp_state"]["pack_start_day"]), 3)
	assert_eq(int(e["departure"]["dest_x_m"]), BASE.x + 5000)

func test_the_snapshot_survives_the_save() -> void:
	var f := _fixture()
	BattleTaskSystem.track_day(f.repo, f.state)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	var t: Dictionary = BattleTaskSystem.current(back, f.a)["track"]
	assert_eq([int(t.x_m), int(t.y_m), t.phase], [BASE.x + 5000, BASE.y, "follow"])
