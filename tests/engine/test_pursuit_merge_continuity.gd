extends GutTest
## Alias reissues must retain the original route budget, including metres walked
## while the replacement courier is pending. 400 + 400 + 77 + 77 + 46 = 1000.
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture(flip: bool) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 9448)
	var mine := state.regiments.keys()
	mine.sort()
	var foes := state.foes.keys()
	foes.sort()
	var p1 := String(mine[0])
	var p2 := String(mine[1])
	var f1 := String(foes[0])
	var f2 := String(foes[1])
	var at := {p1: Vector2i(0, 0), f1: Vector2i(0, 3000), p2: Vector2i(5000, 20000), f2: Vector2i(80, 0)}
	for code: String in at:
		var e: Dictionary = state.foes.get(code, state.regiments.get(code, {}))
		e["x_m"] = at[code].x
		e["y_m"] = at[code].y
		Personnel.replace(repo, state, code, 40)
	var b1 := {"id": 1, "att": [f1] if flip else [p1], "def": [p1] if flip else [f1], "rounds": 1, "start_day": 5, "town": "",
		"place_x_m": 0, "place_y_m": 0, "actions": {}, "parley": {"battle_id": 1, "agreed": {}}}
	var b2 := {"id": 2, "att": [p2], "def": [f2], "rounds": 3, "start_day": 3,
		"town": "", "place_x_m": 80, "place_y_m": 0, "actions": {}, "parley": {"battle_id": 2, "agreed": {}}}
	state.battles = [b1, b2]
	state.tick = 1
	state.day = 7
	state.metrics.treasury = 100
	state.king_state.x_m = 100000000
	state.king_state.y_m = 100000000
	for b: Dictionary in state.battles:
		BattleFormation.ensure(b)
		BattleReport.enroll(state, b, String(b["att"][0]), "att")
		BattleReport.enroll(state, b, String(b["def"][0]), "def")
		BattleGroups.refresh(repo, state, b)
	return {"repo": repo, "state": state, "p1": p1, "p2": p2, "f1": f1, "f2": f2}


func _receive(f: Dictionary, id: String, extra: Dictionary = {}) -> Dictionary:
	var order := {"id": id, "unit": f.p2, "battle_id": 2, "task": "pursue",
		"target_unit": f.f2, "max_route_m": 1000}
	order.merge(extra, true)
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, order).get("status"), "pending")
	return BattleTaskSystem.deliver_task(f.repo, f.state, id)

func test_alias_reissue_keeps_pending_metres_and_stops_the_real_walk_after_json() -> void:
	for flip: bool in [false, true]:
		var f := _fixture(flip)
		assert_eq(_receive(f, "original").status, "received")
		assert_false(BattleTaskSystem.credit_pursuit(f.repo, f.state, f.p2, 400))
		assert_eq(BattleMerge.day(f.repo, f.state).size(), 1)
		assert_eq(BattleSystem.canonical(f.state, 2), 1)
		var req := ActionRequest.make("BATTLE_TASK", {"request_id": "reissue", "regiment": f.p2,
			"battle_id": 1, "task": "pursue", "target_unit": f.f2, "max_route_m": 1000})
		assert_true(ActionSystem.new(f.repo).execute(req, f.state).ok)
		assert_eq(f.state.couriers.size(), 1)
		assert_eq(BattleTaskSystem.current(f.state, f.p2).request.id, "original")
		assert_false(BattleTaskSystem.credit_pursuit(f.repo, f.state, f.p2, 400))
		f.state = GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
		assert_eq(CourierSystem._deliver(f.repo, f.state, f.state.couriers[0]).type, "delivered")
		var current := BattleTaskSystem.current(f.state, f.p2)
		assert_eq(current.pursuit.route_m, 800)
		assert_eq(current.pursuit.start_x_m, 5000)
		assert_eq(current.pursuit.start_y_m, 20000)
		assert_eq(current.request.max_route_m, 1000)
		assert_eq(f.state.unit_tasks[f.p2].orders.original.status, "replaced")
		var before: Dictionary = f.state.to_dict()
		BattleTaskSystem.deliver_task(f.repo, f.state, "original")
		assert_eq(f.state.to_dict(), before, "late delivery cannot replace the newer task")
		_walk_to_bound(f)

func _walk_to_bound(f: Dictionary) -> void:
	var repo: DataRepository = f.repo
	var state: GameState = f.state
	SuiteData.flat_ground(repo)
	for arm: String in repo.army_speed:
		repo.army_speed[arm] = 1
	repo.balance["army_clearance_on"] = 0.0
	Personnel.replace(repo, state, f.p2, 30000)
	var entry: Dictionary = state.regiments[f.p2]
	entry.merge({"morale": 100, "training": 100, "carry_days": 10, "supplies": 1000,
		"x_m": 1000000, "y_m": 1000000, "dest_x_m": 1000000, "dest_y_m": 1000000}, true)
	state.tick = 1
	state.day = 10
	state.battles.clear() # after disengagement, the received pursuit uses the ordinary march
	ArmySystem.set_march_m(repo, state, f.p2, Vector2i(1002300, 1000000))
	var tx := DayResolution.begin(state.day, false, state.absolute_day(), int(repo.bal("battle_substeps")))
	tx["march_entries"] = {f.p2: entry.duplicate(true)}
	tx["march_budgets"] = {f.p2: ArmySystem.day_walk_budget(repo, state, f.p2)}
	state.day_resolution = tx
	for i: int in range(10):
		ArmySystem.march_day_saved(repo, state, 10, i, tx["march_entries"], tx["march_budgets"])
	assert_eq(int(entry.x_m) - 1000000, 200, "the third substep clips to the remaining 46 m of the original budget")
	assert_eq(entry.order, ArmySystem.ORDER_GARRISON)
	assert_eq(BattleTaskSystem.current(state, f.p2).status, "bounded")
	assert_eq(BattleTaskSystem.current(state, f.p2).pursuit.route_m, 1000)

func test_alias_reissue_canonical_region_keeps_progress_but_new_limits_or_target_restart() -> void:
	var f := _fixture(true)
	var codes: Array = f.repo.provinces.keys()
	codes.sort()
	f.state.regiments[f.p2]["province_code"] = String(codes[0])
	var here := ArmySystem.province_of(f.repo, f.state, f.state.regiments[f.p2])
	var other := String(codes[0]) if String(codes[0]) != here else String(codes[1])
	var region := here + "|" + other if here < other else other + "|" + here
	_receive(f, "original", {"region": region})
	assert_false(BattleTaskSystem.credit_pursuit(f.repo, f.state, f.p2, 800))
	BattleMerge.day(f.repo, f.state)
	var same := _receive(f, "same", {"battle_id": 1,
		"region": other + "|" + here + "|" + other})
	assert_eq(same.pursuit.route_m, 800)
	assert_eq(same.request.region, region)
	var outside := ""
	for code: String in codes:
		if code != here and code != other:
			outside = code
			break
	assert_ne(outside, "")
	f.state.regiments[f.p2].merge({"x_m": 100000000, "y_m": 100000000,
		"province_code": outside, "order": ArmySystem.ORDER_MARCH}, true)
	assert_true(BattleTaskSystem.credit_pursuit(f.repo, f.state, f.p2, 0))
	assert_eq(BattleTaskSystem.current(f.state, f.p2).status, "bounded")
	assert_eq(f.state.regiments[f.p2].order, ArmySystem.ORDER_GARRISON)
	assert_eq(BattleTaskSystem.combat_action(f.repo, f.state, f.state.battles[0], f.p2).kind, "hold")
	for patch: Dictionary in [{"max_route_m": 2000}, {"region": other}, {"target_unit": f.f1}]:
		f.state.regiments[f.p2]["province_code"] = here
		f.state.regiments[f.p2]["x_m"] = 5000
		f.state.regiments[f.p2]["y_m"] = 20000
		_receive(f, "base_" + str(patch), {"region": region})
		assert_false(BattleTaskSystem.credit_pursuit(f.repo, f.state, f.p2, 10))
		var changed := {"region": region}
		changed.merge(patch, true)
		var fresh := _receive(f, "new_" + str(patch), changed)
		assert_eq(fresh.pursuit.route_m, 0)

func test_a_distinct_battle_starts_a_new_pursuit() -> void:
	var f := _fixture(false)
	_receive(f, "original")
	assert_false(BattleTaskSystem.credit_pursuit(f.repo, f.state, f.p2, 400))
	f.state.battles[1]["id"] = 3 # another encounter, with no alias connecting the two
	f.state.regiments[f.p2]["x_m"] = 6000
	var fresh := _receive(f, "new_battle", {"battle_id": 3})
	assert_eq(fresh.status, "received")
	assert_eq(fresh.pursuit.route_m, 0)
	assert_eq(fresh.pursuit.start_x_m, 6000)
