extends GutTest
## P4.4d2: deployment lines own a battle unit's movement. Hand-computed with
## battle_line_gap_m 100, battle_deploy_step_m 2500, spacing 50 (data/battle/balance.csv).
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture() -> Dictionary:
	var repo := SuiteData.open_country(SuiteData.repo())   # straight steps; the water test lays its own grid
	for row: Dictionary in repo.unit_footprints.values():
		row.radius_m = 20
		row.pitch_m = 80
	var state := SuiteData.campaign(repo, 9446)
	state.town_seat.clear()  # Mobile-column cases; the fixed-seat regression assigns a real held seat.
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

func test_diagonal_deployment_uses_a_positive_step_inside_the_integer_budget() -> void:
	var f := _fixture()
	for code: String in [f.a, f.enemy]:
		assert_false(Personnel.replace(f.repo, f.state, code, 100).has("error"))
	f.state.regiments[f.a].y_m = 4000
	f.state.regiments[f.a].facing_deg = 225
	f.state.foes[f.enemy].facing_deg = 45
	var from := _at(f, f.a)
	f.state.day += 1
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	var delta := _at(f, f.a) - from
	var budget := int(f.repo.bal("battle_deploy_step_m"))
	assert_gt(delta.length_squared(), 0, "Rounding a diagonal cannot stall every daily step")
	assert_lte(delta.length_squared(), budget * budget)


func test_unequal_installed_fronts_reach_contact_without_overlapping() -> void:
	var f := _fixture()
	f.repo.unit_footprints = SuiteData.repo().unit_footprints.duplicate(true)
	for code: String in [f.a, f.enemy]:
		var fit := 201 if code == f.a else 1000
		for arm: String in f.repo.world_table("military", "unit_types"):
			f.state.army_roster[code][arm] = "0"
		f.state.army_roster[code].is_royal = "0"
		f.state.army_roster[code].infantry = str(fit)
		assert_false(Personnel.replace(f.repo, f.state, code, fit).has("error"))
	assert_true(BattleGroups.refresh(f.repo, f.state, f.battle))
	for day: int in 4:
		f.state.day += 1
		BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_true(BattleGroups.placement(f.repo, f.state, f.battle).ok)
	assert_gt(BattleGroups.engaged_counts(f.repo, f.state, f.battle, f.a).x, 0,
		"Staggered 201/1000 fronts must reach actual contact at installed scale")
	assert_gt(BattleGroups.engaged_counts(f.repo, f.state, f.battle, f.enemy).x, 0)
	var anchors: Dictionary = f.battle.group_anchor_m.duplicate(true)
	f.state.day += 1
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(f.battle.group_anchor_m, anchors, "Contact stays admitted instead of oscillating back to the nominal line")


func _at(f: Dictionary, code: String) -> Vector2i:
	return BattleSystem._at_m(f.repo, f.state, code)

func test_targets_and_two_day_approach() -> void:
	var f := _fixture()
	var t: Dictionary = BattleGroups.deployment(f.repo, f.state, f.battle)
	assert_eq(t[f.enemy], Vector2i(-70, 0))
	assert_eq(t[f.a], Vector2i(70, 0))
	f.state.day = 5
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_at(f, f.a), Vector2i(1500, 0))
	assert_eq(_at(f, f.enemy), Vector2i(-70, 0))
	f.state.day = 6
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_at(f, f.a), Vector2i(70, 0))

func test_stationary_seat_front_reserves_its_actual_occupied_radius() -> void:
	var f := _fixture()
	f.repo.unit_footprints = SuiteData.repo().unit_footprints.duplicate(true)
	for code: String in [f.a, f.enemy]:
		for arm: String in f.repo.world_table("military", "unit_types"): f.state.army_roster[code][arm] = "0"
		f.state.army_roster[code].infantry = "100"
		f.state.army_roster[code].is_royal = "0"
		Personnel.replace(f.repo, f.state, code, 100)
	var kingdom := String(f.state.army_roster[f.a].kingdom_code)
	for town: String in f.repo.burgs:
		if ArmyGround.holds(f.repo, f.state, kingdom, town):
			f.state.town_seat = {town: f.a}
			break
	assert_ne(ArmyGround.seated_in(f.repo, f.state, f.a), "")
	f.battle.place_x_m = 4000
	f.state.day = 5
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	# Fixed front4000-927; opposing centre=4000-927-100-927=2046.
	assert_eq(_at(f, f.a), Vector2i(4000, 0))
	assert_eq(_at(f, f.enemy), Vector2i(2046, 0))
	assert_gt(BattleGroups.engaged_counts(f.repo, f.state, f.battle, f.enemy).x, 0)

func test_admitted_deployment_axis_is_stable_during_a_side_approach() -> void:
	var f := _fixture()
	assert_true(BattleGroups.refresh(f.repo, f.state, f.battle))
	var targets := BattleGroups.deployment(f.repo, f.state, f.battle)
	assert_true(BattleGroups.translate(f.repo, f.state, f.battle, f.a, Vector2i(0, 1000)))
	assert_eq(BattleGroups.deployment(f.repo, f.state, f.battle), targets,
		"A flanking anchor cannot rotate every other unit's deployment target")

func test_abreast_clearance_uses_actual_rows_instead_of_nominal_slot_count() -> void:
	var f := _fixture()
	var codes: Array = f.state.regiments.keys()
	codes.sort()
	var friend := String(codes[1])
	Personnel.replace(f.repo, f.state, f.a, 200)
	Personnel.replace(f.repo, f.state, f.enemy, 100)
	Personnel.replace(f.repo, f.state, friend, 100)
	f.state.regiments[friend].x_m = 4000
	f.state.regiments[friend].y_m = 2000
	f.battle.att.append(friend)
	assert_true(BattleGroups.refresh(f.repo, f.state, f.battle))
	f.battle.deployment_axis_deg = 0  # Hand calculation projects actual rows onto the fixedY cross-axis.
	f.battle.groups[f.a][0].y_m = -400
	f.battle.groups[f.a][1].y_m = 400
	var targets := BattleGroups.deployment(f.repo, f.state, f.battle)
	# Actual half-widths420 and20 plus100 clear metres require540 between centres.
	assert_eq(targets[friend].y - targets[f.a].y, 540)

func test_two_units_abreast_across_the_axis() -> void:
	var f := _fixture()
	var codes: Array = f.state.regiments.keys()
	codes.sort()
	var b := String(codes[1])
	f.state.regiments[b]["x_m"] = 4000
	f.state.regiments[b]["y_m"] = 0
	f.battle.att.append(b)
	Personnel.replace(f.repo, f.state, f.a, 240)
	Personnel.replace(f.repo, f.state, b, 240)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var t: Dictionary = BattleGroups.deployment(f.repo, f.state, f.battle)
	# Each occupied width=80+2*20=120;100m gap gives centres +/-110, forward20+50=70.
	var ys := [t[f.a].y, t[b].y]
	ys.sort()
	assert_eq(ys, [-110, 110])
	assert_eq(t[f.a].x, 70)

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
	assert_eq(_at(f, f.a), Vector2i(70, 0))

func test_retreat_order_stops_both_sides() -> void:
	var f := _fixture()
	f.battle.actions = {"def": {"kind": "retreat"}}
	f.state.day = 5
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_at(f, f.a), Vector2i(4000, 0))
	assert_eq(_at(f, f.enemy), Vector2i(0, 0))

func test_a_step_across_water_is_not_taken() -> void:
	var f := _fixture()
	# five 1 000 m cells along x, the middle one (2 000..2 999) water: the
	# attacker's 2 500 m step from 4 000 to 1 500 would cross it, so it waits.
	f.repo.balance["army_march_grid_px"] = 1.0
	MarchPath.use(f.repo, MarchPath.build(f.repo, 5, 1, 1000, PackedByteArray([0, 0, 255, 0, 0])))
	f.state.day = 5
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	MarchPath.forget()
	assert_eq(_at(f, f.a), Vector2i(4000, 0))
	assert_eq(_at(f, f.enemy), Vector2i(-70, 0), "the defender's dry step is taken")

func test_deployment_translates_existing_rows_once() -> void:
	var f := _fixture()
	Personnel.replace(f.repo, f.state, f.a, 100)
	f.battle["groups"] = {f.a: [
		{"count": 50, "role": "front", "x_m": 4000, "y_m": 200},
		{"count": 50, "role": "reserve", "x_m": 3960, "y_m": 200}]}
	f.battle.place_y_m = 200  # The existing physical rows lie on this horizontal battle line.
	f.state.day = 5
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(_at(f, f.a), Vector2i(1500, 0))
	var expected := [Vector2i(1500, 200), Vector2i(1460, 200)]
	assert_eq((f.battle.groups[f.a] as Array).map(func(row: Dictionary) -> Vector2i:
		return Vector2i(int(row.x_m), int(row.y_m))), expected)
	var before: Dictionary = f.battle.duplicate(true)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(f.battle, before)
