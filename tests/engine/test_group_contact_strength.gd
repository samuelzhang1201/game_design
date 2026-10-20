extends GutTest
## P4.4d4: a unit's strength counts its fit people by whether their group is in
## contact. Hand-computed with battle_group_contact_m 100, battle_reserve_permille 500.
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture(gap_m: int) -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 9447)
	var codes := state.regiments.keys()
	codes.sort()
	var a := String(codes[0])
	var enemy := String(state.foes.keys()[0])
	state.regiments[a]["x_m"] = 0
	state.regiments[a]["y_m"] = 0
	state.foes[enemy]["x_m"] = gap_m
	state.foes[enemy]["y_m"] = 0
	var battle := {"id": 9447, "att": [a], "def": [enemy], "rounds": 0,
		"town": "", "place_x_m": 0, "place_y_m": 0, "actions": {}}
	state.battles = [battle]
	BattleFormation.ensure(battle)
	battle["formations"]["att"]["current"] = "double_rank"
	# This fixture isolates melee contact; mixed/ranged output has its own geometry tests.
	for arm: String in repo.world_table("military", "unit_types"):
		state.army_roster[a][arm] = "0"
	state.army_roster[a]["infantry"] = "120"
	Personnel.replace(repo, state, a, 120)
	BattleGroups.refresh(repo, state, battle)
	return {"repo": repo, "state": state, "a": a, "enemy": enemy, "battle": battle}

func test_front_groups_in_reach_fight_in_full() -> void:
	var f := _fixture(60)
	# groups 50 front, 50 reserve, 20 front: engaged 70 -> (70 * 1000 + 50 * 500) / 120 = 791
	assert_eq(BattleGroups.engaged_permille(f.repo, f.state, f.battle, f.a), 791)

func test_no_enemy_in_reach_is_all_reserve() -> void:
	var f := _fixture(5000)
	# (0 + 120 * 500) / 120 = 500
	assert_eq(BattleGroups.engaged_permille(f.repo, f.state, f.battle, f.a), 500)

func test_no_groups_is_full_strength_and_no_factor() -> void:
	var f := _fixture(60)
	f.battle.erase("groups")
	assert_eq(BattleGroups.engaged_permille(f.repo, f.state, f.battle, f.a), 1000)
	var s := BattleSystem.unit_strength(f.repo, f.state, f.a, Callable(), true, [f.enemy])
	for factor: Dictionary in s["factors"]:
		assert_ne(factor["source"], "contact:engaged")

func test_unit_strength_lists_the_factor() -> void:
	var f := _fixture(60)
	var s := BattleSystem.unit_strength(f.repo, f.state, f.a, Callable(), true, [f.enemy])
	var found := {}
	for factor: Dictionary in s["factors"]:
		if factor["source"] == "contact:engaged":
			found = factor
	assert_eq(found["permille"], 791)
	assert_eq(found["reason"], "70 of 120 in contact with the enemy line")
