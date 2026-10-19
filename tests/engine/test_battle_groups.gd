extends GutTest
## P4.4d1: representative 50-person groups and their saved whole-metre positions.
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

func test_counts_table() -> void:
	assert_eq(BattleGroups.counts(0), [] as Array[int])
	assert_eq(BattleGroups.counts(1), [1] as Array[int])
	assert_eq(BattleGroups.counts(49), [49] as Array[int])
	assert_eq(BattleGroups.counts(50), [50] as Array[int])
	assert_eq(BattleGroups.counts(51), [50, 1] as Array[int])
	assert_eq(BattleGroups.counts(800).size(), 16)
	assert_eq(BattleGroups.counts(1000).size(), 20)
	assert_eq(BattleGroups.counts(10000).size(), 200)

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
	Personnel.replace(f.repo, f.state, f.a, 120)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var g: Array = f.battle.groups[f.a]
	assert_eq(_counts(g), [50, 50, 20])
	assert_eq(g.map(func(x: Dictionary) -> String: return String(x.role)), ["front", "reserve", "front"])
	assert_eq(int(f.battle.group_facing[f.a]), 90)
	assert_eq(int(f.battle.group_facing[f.enemy]), 270)
	Personnel.move(f.repo, f.state, f.a, "fit", "dead", 30)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_counts(f.battle.groups[f.a]), [50, 40])

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
