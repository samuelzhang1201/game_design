extends GutTest
## P4.4c3: pursuit bounds on the battle unit task. Hand-computed: a pursuit
## bounded at 1 000 m credited 400 + 400 = 800 stays received; +300 = 1 100 >=
## 1 000 bounds it at route 1 100. A reissue of the same meaning keeps the 800;
## a different max_route_m restarts at 0.
const SuiteData := preload("res://tests/suite_data.gd")

func _fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 9444)
	var codes := state.regiments.keys()
	codes.sort()
	var enemy := String(state.foes.keys()[0])
	var battle := {"id": 9444, "att": [codes[0], codes[1]], "def": [enemy], "rounds": 0,
		"town": "", "place_x_m": 0, "place_y_m": 0,
		"actions": {"att": {"kind": "hold"}, "def": {"kind": "retreat"}}}
	state.battles = [battle]
	var a := String(codes[0])
	state.regiments[a]["x_m"] = 5000
	state.regiments[a]["y_m"] = 7000
	return {"repo": repo, "state": state, "a": a, "enemy": enemy, "battle": battle}

func _order(f: Dictionary, id: String, extra := {}, task := "pursue") -> Dictionary:
	var o := {"id": id, "unit": f.a, "battle_id": 9444, "task": task}
	o.merge(extra)
	return o

func _receive(f: Dictionary, id: String, extra := {}) -> Dictionary:
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, _order(f, id, extra)).get("status"), "pending")
	return BattleTaskSystem.deliver_task(f.repo, f.state, id)

func test_format_refusals_and_canonical_region() -> void:
	var f := _fixture()
	assert_ne(BattleTaskSystem.refusal_of(f.repo, f.state, _order(f, "x", {"max_route_m": -1})), "")
	assert_ne(BattleTaskSystem.refusal_of(f.repo, f.state, _order(f, "x", {"region": "a"}, "defend")), "")
	assert_ne(BattleTaskSystem.refusal_of(f.repo, f.state, _order(f, "x", {"region": "nowhere"})), "")
	var provs: Array = f.repo.provinces.keys()
	provs.sort()
	var a := String(provs[0])
	var b := String(provs[1])
	var r := BattleTaskSystem.issue_task(f.repo, f.state, _order(f, "ok", {"region": b + "|" + a + "|" + a}))
	assert_eq(r.request.region, a + "|" + b)
	assert_eq(r.request.max_route_m, 0)

func test_route_bound_ends_the_task_and_halts_the_march() -> void:
	var f := _fixture()
	var rec := _receive(f, "p", {"max_route_m": 1000})
	assert_eq(rec.pursuit, {"start_x_m": 5000, "start_y_m": 7000, "route_m": 0})
	var e: Dictionary = f.state.regiments[f.a]
	e["order"] = ArmySystem.ORDER_MARCH
	e["dest_x_m"] = 9000
	e["dest_y_m"] = 7000
	assert_false(BattleTaskSystem.credit_pursuit(f.repo, f.state, f.a, 400))
	assert_false(BattleTaskSystem.credit_pursuit(f.repo, f.state, f.a, 400))
	assert_eq(BattleTaskSystem.current(f.state, f.a).status, "received")
	assert_eq(BattleTaskSystem.current(f.state, f.a).pursuit.route_m, 800)
	e["x_m"] = 5800
	assert_true(BattleTaskSystem.credit_pursuit(f.repo, f.state, f.a, 300))
	var cur := BattleTaskSystem.current(f.state, f.a)
	assert_eq(cur.status, "bounded")
	assert_eq(cur.pursuit.route_m, 1100)
	assert_string_contains(cur.reason, "1100 m")
	assert_eq(e["order"], ArmySystem.ORDER_GARRISON)
	assert_eq(int(e["dest_x_m"]), 5800)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	assert_eq(BattleTaskSystem.current(back, f.a).status, "bounded")
	assert_eq(BattleTaskSystem.current(back, f.a).pursuit.route_m, 1100)

func test_region_bound_holds_at_zero_metres() -> void:
	var f := _fixture()
	var here := ArmySystem.province_of(f.repo, f.state, f.state.regiments[f.a])
	var other := ""
	for p: String in f.repo.provinces:
		if p != here:
			other = p
			break
	_receive(f, "p", {"region": other})
	assert_true(BattleTaskSystem.credit_pursuit(f.repo, f.state, f.a, 0))
	assert_eq(BattleTaskSystem.current(f.state, f.a).status, "bounded")

func test_region_containing_the_unit_does_not_bound() -> void:
	var f := _fixture()
	var here := ArmySystem.province_of(f.repo, f.state, f.state.regiments[f.a])
	_receive(f, "p", {"region": here})
	assert_false(BattleTaskSystem.credit_pursuit(f.repo, f.state, f.a, 10))
	assert_eq(BattleTaskSystem.current(f.state, f.a).status, "received")

func test_reissue_keeps_metres_only_when_the_meaning_is_the_same() -> void:
	var f := _fixture()
	_receive(f, "p1", {"max_route_m": 1000})
	BattleTaskSystem.credit_pursuit(f.repo, f.state, f.a, 800)
	var same := _receive(f, "p2", {"max_route_m": 1000})
	assert_eq(same.pursuit.route_m, 800)
	var other := _receive(f, "p3", {"max_route_m": 2000})
	assert_eq(other.pursuit.route_m, 0)

func test_bounded_pursuit_holds_in_battle() -> void:
	var f := _fixture()
	_receive(f, "p", {"max_route_m": 100})
	f.state.battles[0]["actions"]["att"]["kind"] = "attack"
	assert_eq(BattleTaskSystem.combat_action(f.repo, f.state, f.battle, f.a).kind, "attack")
	BattleTaskSystem.credit_pursuit(f.repo, f.state, f.a, 100)
	var act := BattleTaskSystem.combat_action(f.repo, f.state, f.battle, f.a)
	assert_eq(act.kind, "hold")
	assert_string_contains(act.reason, "bound")

## The march hook: 767 m today over ten substeps is 77 × 7 + 76 × 3, so a 300 m
## bound is reached on substep 4 (4 × 77 = 308 >= 300) and the walk stops at 308.
func test_march_day_saved_stops_the_walk_at_the_bound() -> void:
	var f := _fixture()
	var repo: DataRepository = f.repo
	var state: GameState = f.state
	SuiteData.flat_ground(repo)
	for arm: String in repo.army_speed:
		repo.army_speed[arm] = 1
	repo.balance["army_clearance_on"] = 0.0
	var code: String = f.a
	var Personnel := load("res://tests/engine/personnel_helpers.gd")
	Personnel.replace(repo, state, code, 30000)
	var entry: Dictionary = state.regiments[code]
	entry["morale"] = 100
	entry["training"] = 100
	entry["carry_days"] = 10
	entry["supplies"] = 1000
	var start := Vector2i(1000000, 1000000)
	entry["x_m"] = start.x
	entry["y_m"] = start.y
	entry["dest_x_m"] = start.x
	entry["dest_y_m"] = start.y
	state.tick = 1
	state.day = 10
	ArmySystem.set_march_m(repo, state, code, start + Vector2i(2300, 0))
	_receive(f, "p", {"max_route_m": 300})
	state.battles.clear()   # a unit in a fight does not march; the bound is credited by the walk alone
	var tx := DayResolution.begin(state.day, false, state.absolute_day(), int(repo.bal("battle_substeps")))
	tx["march_entries"] = {code: state.regiments[code].duplicate(true)}
	tx["march_budgets"] = {code: ArmySystem.day_walk_budget(repo, state, code)}
	state.day_resolution = tx
	for i in range(10):
		ArmySystem.march_day_saved(repo, state, 10, i, tx["march_entries"], tx["march_budgets"])
	assert_eq(int(state.regiments[code]["x_m"]) - start.x, 308)
	assert_eq(BattleTaskSystem.current(state, code).status, "bounded")
	assert_eq(state.regiments[code]["order"], ArmySystem.ORDER_GARRISON)

func test_an_old_saved_request_without_bounds_still_retries_by_id() -> void:
	var f := _fixture()
	var rec := BattleTaskSystem.issue_task(f.repo, f.state, _order(f, "old", {}, "defend"))
	assert_eq(rec.status, "pending")
	# an older save's request has no bound fields
	for ledger: Dictionary in f.state.unit_tasks.values():
		var request: Dictionary = ledger["orders"]["old"]["request"]
		request.erase("max_route_m")
		request.erase("region")
	var again := BattleTaskSystem.issue_task(f.repo, f.state, _order(f, "old", {}, "defend"))
	assert_eq(again.get("status"), "pending", "the exact retry returns the saved record")
