extends GutTest
## P4.4d1: representative 100-person groups and their saved whole-metre positions.
## Hand-computed: spacing 50 m, depth 40 m (data/battle/balance.csv).
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 9445)
	var codes := state.regiments.keys()
	codes.sort()
	var a := String(codes[0])
	var enemy := String(state.foes.keys()[0])
	state.regiments[a]["x_m"] = 1000
	state.regiments[a]["y_m"] = 2000
	state.foes[enemy]["x_m"] = 1000
	state.foes[enemy]["y_m"] = 4000
	var battle := {"id": 9445, "att": [a], "def": [enemy], "rounds": 0,
		"town": "", "place_x_m": 1000, "place_y_m": 3000, "actions": {}}
	state.battles = [battle]
	BattleFormation.ensure(battle)
	return {"repo": repo, "state": state, "a": a, "enemy": enemy, "battle": battle}

func _counts(groups: Array) -> Array:
	return groups.map(func(x: Dictionary) -> int: return int(x.count))

func test_configured_hundred_fit_counts() -> void:
	var repo := SuiteData.repo()
	assert_eq(int(repo.bal("battle_group_size")), 100)
	assert_eq(BattleGroups.counts(101, int(repo.bal("battle_group_size"))), [100, 1] as Array[int])
	assert_eq(BattleGroups.counts(1000, int(repo.bal("battle_group_size"))).size(), 10)

func test_counts_table() -> void:
	assert_eq(BattleGroups.counts(0, 100), [] as Array[int])
	assert_eq(BattleGroups.counts(1, 100), [1] as Array[int])
	assert_eq(BattleGroups.counts(49, 100), [49] as Array[int])
	assert_eq(BattleGroups.counts(50, 100), [50] as Array[int])
	assert_eq(BattleGroups.counts(51, 100), [51] as Array[int])
	assert_eq(BattleGroups.counts(800, 100).size(), 8)
	assert_eq(BattleGroups.counts(1000, 100).size(), 10)
	assert_eq(BattleGroups.counts(10000, 100).size(), 100)

func test_layout_line_rotated() -> void:
	var repo := SuiteData.repo()
	# facing 0 (+x): across = +y, back = -x; slots x -1,0,1 at 50 m
	assert_eq(BattleGroups.layout(repo, "line", 3, Vector2i(0, 0), 0),
		[Vector2i(0, -50), Vector2i(0, 0), Vector2i(0, 50)] as Array[Vector2i])
	# facing 90 (+y): across = -x
	assert_eq(BattleGroups.layout(repo, "line", 3, Vector2i(0, 0), 90),
		[Vector2i(50, 0), Vector2i(0, 0), Vector2i(-50, 0)] as Array[Vector2i])
	assert_eq(BattleGroups.layout(repo, "line", 1, Vector2i(10, 20), 0), [Vector2i(10, 20)] as Array[Vector2i])

func test_double_rank_depth_is_behind_the_front() -> void:
	var repo := SuiteData.repo()
	# double_rank 3 groups, facing 0: slots (-0.5,0), (-0.5,1), (0.5,0) -> (0,-25), (-40,-25), (0,25)
	assert_eq(BattleGroups.layout(repo, "double_rank", 3, Vector2i(0, 0), 0),
		[Vector2i(0, -25), Vector2i(-40, -25), Vector2i(0, 25)] as Array[Vector2i])

func test_refresh_groups_follow_fit_count() -> void:
	var f := _fixture()
	Personnel.replace(f.repo, f.state, f.a, 240)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var g: Array = f.battle.groups[f.a]
	assert_eq(_counts(g), [100, 100, 40])
	assert_eq(g.map(func(x: Dictionary) -> String: return String(x.role)), ["front", "reserve", "front"])
	assert_eq(int(f.battle.group_facing[f.a]), 90)
	assert_eq(int(f.battle.group_facing[f.enemy]), 270)
	Personnel.move(f.repo, f.state, f.a, "fit", "dead", 60)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_counts(f.battle.groups[f.a]), [100, 80])

func test_save_roundtrip_and_old_battle_migrates() -> void:
	var f := _fixture()
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var back: Dictionary = JSON.parse_string(JSON.stringify(f.battle))
	assert_eq(int(back.group_facing[f.a]), 90)
	assert_eq(back.groups[f.a].size(), f.battle.groups[f.a].size())
	assert_eq(int(back.groups[f.a][0].x_m), int(f.battle.groups[f.a][0].x_m))
	f.battle.erase("groups")
	f.battle.erase("group_facing")
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_true(f.battle.groups.has(f.a))

func test_departed_unit_loses_its_entry() -> void:
	var f := _fixture()
	BattleGroups.refresh(f.repo, f.state, f.battle)
	f.battle.def.clear()
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_false(f.battle.groups.has(f.enemy))

func _points(rows: Array) -> Array:
	return rows.map(func(row: Dictionary) -> Vector2i: return Vector2i(int(row.x_m), int(row.y_m)))

func test_refresh_keeps_physical_rows() -> void:
	var f := _fixture()
	Personnel.replace(f.repo, f.state, f.a, 100)
	f.battle["groups"] = {f.a: [
		{"count": 50, "role": "front", "x_m": 200, "y_m": 200, "path_m": [[210, 200]]},
		{"count": 50, "role": "reserve", "x_m": 160, "y_m": 200}]}
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_points(f.battle.groups[f.a]), [Vector2i(200, 200), Vector2i(160, 200)])
	assert_eq(f.battle.groups[f.a][0].get("path_m", []), [[210, 200]])
	assert_eq(f.battle.groups[f.a].map(func(row: Dictionary) -> int: return int(row.get("slot", -1))), [0, 1])
	var frozen := JSON.stringify(f.state.to_dict())
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(JSON.stringify(f.state.to_dict()), frozen)
	f.state.regiments[f.a]["facing_deg"] = 180
	f.battle.formations.att.current = "line"
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_points(f.battle.groups[f.a]), [Vector2i(200, 200), Vector2i(160, 200)])

func test_count_boundary_keeps_surviving_positions() -> void:
	var f := _fixture()
	Personnel.replace(f.repo, f.state, f.a, 240)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var before := _points(f.battle.groups[f.a])
	Personnel.move(f.repo, f.state, f.a, "fit", "dead", 39)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_counts(f.battle.groups[f.a]), [100, 100, 1])
	assert_eq(_points(f.battle.groups[f.a]), before)
	Personnel.move(f.repo, f.state, f.a, "fit", "dead", 1)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_counts(f.battle.groups[f.a]), [100, 100])
	assert_eq(_points(f.battle.groups[f.a]), before.slice(0, 2))
	Personnel.replace(f.repo, f.state, f.a, 301)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_points(f.battle.groups[f.a]).slice(0, 2), before.slice(0, 2))
	assert_eq(f.battle.groups[f.a].map(func(row: Dictionary) -> int: return int(row.get("slot", -1))), [0, 1, 3, 4])

func test_pending_round_freezes_reconciliation() -> void:
	var f := _fixture()
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var before: Dictionary = f.battle.duplicate(true)
	f.battle["pending_round"] = {"roll": 17}
	Personnel.move(f.repo, f.state, f.a, "fit", "dead", 1)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(f.battle.groups, before.groups)

func test_translate_and_follow_anchor_apply_exactly_once() -> void:
	var f := _fixture()
	Personnel.replace(f.repo, f.state, f.a, 100)
	f.state.regiments[f.a].x_m = 200
	f.state.regiments[f.a].y_m = 200
	f.battle["groups"] = {f.a: [
		{"count": 50, "role": "front", "x_m": 200, "y_m": 200, "path_m": [[210, 200]]},
		{"count": 50, "role": "reserve", "x_m": 160, "y_m": 200}]}
	BattleGroups.translate(f.repo, f.state, f.battle, f.a, Vector2i(30, 40))
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), Vector2i(230, 240))
	assert_eq(_points(f.battle.groups[f.a]), [Vector2i(230, 240), Vector2i(190, 240)])
	assert_eq(f.battle.groups[f.a][0].path_m, [[240, 240]])
	var before := JSON.stringify(f.state.to_dict())
	BattleGroups.follow_anchor(f.repo, f.state, f.battle, f.a)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(JSON.stringify(f.state.to_dict()), before)
	f.state.regiments[f.a].x_m = 260
	f.state.regiments[f.a].y_m = 280
	BattleGroups.follow_anchor(f.repo, f.state, f.battle, f.a)
	assert_eq(_points(f.battle.groups[f.a]), [Vector2i(260, 280), Vector2i(220, 280)])
	assert_eq(f.battle.group_anchor_m[f.a], [260, 280])

func test_retired_slots_stay_retired_across_json_and_battles() -> void:
	var f := _fixture()
	Personnel.replace(f.repo, f.state, f.a, 240)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	Personnel.move(f.repo, f.state, f.a, "fit", "dead", 40)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	var battle: Dictionary = loaded.battles[0]
	battle.att.clear()
	BattleGroups.refresh(f.repo, loaded, battle)
	battle.att.append(f.a)
	BattleGroups.refresh(f.repo, loaded, battle)
	assert_eq(battle.groups[f.a].map(func(row: Dictionary) -> int: return int(row.slot)), [3, 4])
	var next_battle := {"id": 9446, "att": [f.a], "def": [f.enemy], "actions": {}}
	loaded.battles = [next_battle]
	BattleGroups.refresh(f.repo, loaded, next_battle)
	assert_eq(next_battle.groups[f.a].map(func(row: Dictionary) -> int: return int(row.slot)), [5, 6])
	var twin := GameState.from_dict(JSON.parse_string(JSON.stringify(loaded.to_dict())))
	BattleGroups.refresh(f.repo, twin, twin.battles[0])
	assert_eq(SaveLoad.state_hash(twin), SaveLoad.state_hash(loaded))

func test_new_member_seeds_at_arrival_and_exact_people_are_conserved() -> void:
	var f := _fixture()
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var codes: Array = f.state.regiments.keys()
	codes.sort()
	var ally := String(codes[1])
	f.state.regiments[ally].x_m = 9000
	f.state.regiments[ally].y_m = 8000
	Personnel.replace(f.repo, f.state, ally, 1)
	f.battle.att.append(ally)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_points(f.battle.groups[ally]), [Vector2i(9000, 8000)])
	for people: int in [0, 1, 49, 50, 51, 800, 1000]:
		Personnel.replace(f.repo, f.state, ally, people)
		BattleGroups.refresh(f.repo, f.state, f.battle)
		assert_eq(_counts(f.battle.groups[ally]), BattleGroups.counts(people, 100))
	assert_eq(BattleGroups.counts(10000, 100).size(), 100, "pure count stress does not enlist an oversized unit")

func test_legacy_rows_cannot_gain_contact_through_closed_ground() -> void:
	var f := _fixture()
	f.repo.balance["army_march_grid_px"] = 1.0
	f.repo.balance["battle_group_contact_m"] = 30
	Personnel.replace(f.repo, f.state, f.a, 50)
	Personnel.replace(f.repo, f.state, f.enemy, 50)
	f.battle["groups"] = {
		f.a: [{"count": 50, "role": "front", "x_m": 5, "y_m": 5}],
		f.enemy: [{"count": 50, "role": "front", "x_m": 25, "y_m": 5}]}
	MarchPath.use(f.repo, MarchPath.build(f.repo, 3, 1, 10, PackedByteArray([0, 255, 0])))
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var before: Array = f.battle.groups[f.a].duplicate(true)
	assert_eq(BattleGroups.engaged_counts(f.repo, f.state, f.battle, f.a), Vector2i(0, 50))
	assert_eq(f.battle.groups[f.a], before, "invalid legacy positions remain saved facts")
	MarchPath.use(f.repo, MarchPath.build(f.repo, 3, 1, 10, PackedByteArray([0, 0, 0])))
	assert_eq(BattleGroups.engaged_counts(f.repo, f.state, f.battle, f.a), Vector2i(50, 50))
	MarchPath.forget()
