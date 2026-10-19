extends GutTest
## P4.4d2: deployment lines own a battle unit's movement. Hand-computed with
## battle_line_gap_m 100, battle_deploy_step_m 2500, spacing 50 (data/battle/balance.csv).
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 9446)
	var codes := state.regiments.keys()
	codes.sort()
	var a := String(codes[0])
	var enemy := String(state.foes.keys()[0])
	state.regiments[a]["x_m"] = 4000
	state.regiments[a]["y_m"] = 0
	state.foes[enemy]["x_m"] = 0
	state.foes[enemy]["y_m"] = 0
	var battle := {"id": 9446, "att": [a], "def": [enemy], "rounds": 0,
		"town": "", "place_x_m": 0, "place_y_m": 0, "actions": {}}
	state.battles = [battle]
	BattleFormation.ensure(battle)
	return {"repo": repo, "state": state, "a": a, "enemy": enemy, "battle": battle}

func _at(f: Dictionary, code: String) -> Vector2i:
	return BattleSystem._at_m(f.repo, f.state, code)

func test_targets_and_two_day_approach() -> void:
	var f := _fixture()
	var t: Dictionary = BattleGroups.deployment(f.repo, f.state, f.battle)
	assert_eq(t[f.enemy], Vector2i(-50, 0))
	assert_eq(t[f.a], Vector2i(50, 0))
	f.state.day = 5
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_at(f, f.a), Vector2i(1500, 0))
	assert_eq(_at(f, f.enemy), Vector2i(-50, 0))
	f.state.day = 6
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_at(f, f.a), Vector2i(50, 0))

func test_two_units_abreast_across_the_axis() -> void:
	var f := _fixture()
	var codes: Array = f.state.regiments.keys()
	codes.sort()
	var b := String(codes[1])
	f.state.regiments[b]["x_m"] = 4000
	f.state.regiments[b]["y_m"] = 0
	f.battle.att.append(b)
	Personnel.replace(f.repo, f.state, f.a, 120)
	Personnel.replace(f.repo, f.state, b, 120)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var t: Dictionary = BattleGroups.deployment(f.repo, f.state, f.battle)
	# axis +x, att line centre (50, 0), across = y; each width 100 m
	var ys := [t[f.a].y, t[b].y]
	ys.sort()
	assert_eq(ys, [-50, 50])
	assert_eq(t[f.a].x, 50)

func test_a_withdrawal_stops_the_whole_deployment() -> void:
	var f := _fixture()
	f.state.regiments[f.a]["battle_retreat"] = true
	f.state.day = 5
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_at(f, f.a), Vector2i(4000, 0))
	assert_eq(_at(f, f.enemy), Vector2i(0, 0))
	f.state.regiments[f.a].erase("battle_retreat")
	f.state.regiments[f.a]["disengaging"] = 1
	f.state.day = 6
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_at(f, f.a), Vector2i(4000, 0))

func test_once_per_day_and_save_roundtrip() -> void:
	var f := _fixture()
	f.state.day = 5
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_at(f, f.a), Vector2i(1500, 0))
	var back: Dictionary = JSON.parse_string(JSON.stringify(f.battle))
	assert_eq(int(back.deployed_day), int(f.battle.deployed_day))
	f.battle.erase("deployed_day")   # an old save migrates: deploys again
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_at(f, f.a), Vector2i(50, 0))

func test_retreat_order_stops_both_sides() -> void:
	var f := _fixture()
	f.battle.actions = {"def": {"kind": "retreat"}}
	f.state.day = 5
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_at(f, f.a), Vector2i(4000, 0))
	assert_eq(_at(f, f.enemy), Vector2i(0, 0))
