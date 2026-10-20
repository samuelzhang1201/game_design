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

# Two land cells meet at x=0; the unit anchor is -20 m inside the allowed cell.
func _group_fixture(xs: Array[int]) -> Dictionary:
	var f := _fixture()
	var repo: DataRepository = f.repo
	var provinces := repo.provinces.keys()
	provinces.sort()
	f["inside"] = String(provinces[0])
	f["outside"] = String(provinces[1])
	repo.vertices.clear()
	for p: Vector2i in [Vector2i(-1000, -1000), Vector2i(0, -1000), Vector2i(0, 1000),
			Vector2i(-1000, 1000), Vector2i(1000, -1000), Vector2i(1000, 1000)]:
		repo.vertices[repo.vertices.size()] = ArmySystem.metres_to_pack(repo, p)
	repo.cells = {1: {"vertex_ids": PackedInt32Array([0, 1, 2, 3]), "height": 30.0, "biome_id": 1},
		2: {"vertex_ids": PackedInt32Array([1, 4, 5, 2]), "height": 30.0, "biome_id": 1}}
	repo.manors = {1: {"province_code": f.inside}, 2: {"province_code": f.outside}}
	MapEconomy.forget()
	repo.balance["battle_group_contact_m"] = 100
	repo.balance["battle_reserve_permille"] = 500
	f.battle.att = [f.a]
	f.state.regiments[f.a].x_m = -20
	f.state.regiments[f.a].y_m = 0
	f.state.regiments[f.a].supplies = 100000
	var groups: Array = []
	for x: int in xs:
		groups.append({"count": 50, "role": "front", "x_m": x, "y_m": 0})
	f.battle["groups"] = {f.a: groups, f.enemy: [{"count": 50, "role": "front", "x_m": 1, "y_m": 0}]}
	assert_eq(_receive(f, "group-region", {"region": f.inside}).status, "received")
	assert_eq(ArmySystem.province_of(repo, f.state, f.state.regiments[f.a]), f.inside)
	return f

func test_pursuit_contact_uses_each_group_position_across_the_region_edge() -> void:
	var f := _group_fixture([-1, 1])
	# Only the inside 50 engage: (50*1000 + 50*500)/100 = 750.
	assert_eq(BattleGroups.engaged_permille(f.repo, f.state, f.battle, f.a), 750)
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def").kind, "pursuit")

func test_outside_groups_do_not_authorize_pursuit_losses() -> void:
	var f := _group_fixture([1])
	assert_eq(BattleGroups.engaged_permille(f.repo, f.state, f.battle, f.a), 500)
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def").kind, "withdrawal")

func test_inside_group_still_engages_and_live_manor_province_controls_eligibility() -> void:
	var f := _group_fixture([-1])
	assert_eq(BattleGroups.engaged_permille(f.repo, f.state, f.battle, f.a), 1000)
	f.state.manor_province["1"] = f.outside
	assert_eq(BattleGroups.engaged_permille(f.repo, f.state, f.battle, f.a), 500)

func test_region_does_not_block_self_defence_or_change_the_receipt() -> void:
	var f := _group_fixture([1])
	f.battle.actions.def.kind = "attack"
	var receipt := BattleTaskSystem.current(f.state, f.a)
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "hold")
	assert_eq(BattleGroups.engaged_permille(f.repo, f.state, f.battle, f.a), 1000)
	assert_eq(BattleTaskSystem.current(f.state, f.a), receipt)

func test_region_contact_json_replay_preserves_integer_positions_and_receipts() -> void:
	var f := _group_fixture([-1, 1])
	var before: String = JSON.stringify(f.state.to_dict())
	var back := GameState.from_dict(JSON.parse_string(before))
	for state: GameState in [f.state, back]:
		var battle: Dictionary = state.battles[0]
		assert_eq(BattleGroups.engaged_permille(f.repo, state, battle, f.a), 750)
		assert_eq(BattleSystem.combat_context(f.repo, state, battle, "def").kind, "pursuit")
		assert_eq(BattleTaskSystem.current(state, f.a), BattleTaskSystem.current(f.state, f.a))
		assert_eq(int(battle.groups[f.a][0].x_m), -1)
		assert_eq(int(battle.groups[f.a][1].x_m), 1)
	assert_eq(JSON.stringify(f.state.to_dict()), before, "eligibility queries are read-only, including the RNG")

func test_outside_group_can_defend_against_an_interceptor_without_pursuing() -> void:
	var f := _group_fixture([1])
	var interceptor := "region_interceptor"
	f.state.foes[interceptor] = f.state.foes[f.enemy].duplicate(true)
	f.state.military_rosters[interceptor] = f.state.military_rosters[f.enemy].duplicate(true)
	f.battle.def.append(interceptor)
	f.battle.actions.def.kind = "attack"
	f.state.foes[f.enemy]["battle_retreat"] = true
	f.battle.groups[interceptor] = [{"count": 50, "role": "front", "x_m": 1, "y_m": 0}]
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "attack")
	assert_eq(BattleGroups.engaged_permille(f.repo, f.state, f.battle, f.a), 1000,
		"the out-of-region group still defends against real attacking contact")
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def", f.enemy).kind, "withdrawal",
		"self-defence contact cannot authorize pursuit of the retreating enemy")

func test_pending_action_keeps_its_received_region_through_replacement_and_json() -> void:
	var f := _group_fixture([-1])
	f.battle["pending_round"] = {"unit_actions": {f.a: BattleSystem.unit_action(f.repo, f.state, f.battle, f.a)}}
	assert_eq(_receive(f, "other-region", {"region": f.outside}).status, "received")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	assert_eq(back.battles[0].pending_round.unit_actions[f.a].pursuit_region, f.inside)
	assert_eq(BattleGroups.engaged_permille(f.repo, back, back.battles[0], f.a), 1000)
	back.battles[0].erase("pending_round")
	assert_eq(BattleGroups.engaged_permille(f.repo, back, back.battles[0], f.a), 500)

func test_region_eligible_contact_keeps_the_inclusive_whole_metre_reach() -> void:
	var f := _group_fixture([-1])
	f.battle.groups[f.enemy][0].x_m = 99
	assert_eq(BattleGroups.engaged_permille(f.repo, f.state, f.battle, f.a), 1000, "100 m is contact")
	f.battle.groups[f.enemy][0].x_m = 100
	assert_eq(BattleGroups.engaged_permille(f.repo, f.state, f.battle, f.a), 500, "101 m is beyond contact")
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def").kind, "withdrawal")
