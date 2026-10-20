extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture(gap := 300, people := 100) -> Dictionary:
	var repo := SuiteData.open_country(SuiteData.repo())
	var state := SuiteData.campaign(repo, 9463)
	var codes := state.regiments.keys()
	codes.sort()
	var a := String(codes[0])
	var friend := String(codes[1])
	var enemy := String(state.foes.keys()[0])
	for code: String in [a, friend, enemy]:
		for arm: String in repo.world_table("military", "unit_types"):
			state.army_roster[code][arm] = "0"
		state.army_roster[code]["archers" if code == a else "infantry"] = str(people)
		Personnel.replace(repo, state, code, people)
		var e := BattleSystem._stored(state, code)
		e["x_m"] = 20000 if code == friend else 1000 + (gap if code == enemy else 0)
		e["y_m"] = 1000
		e["supplies"] = 100000
		e["morale"] = 100
		e.erase("camp_town")
		e["order"] = ArmySystem.ORDER_STANDBY
	var battle := {"id": 9463, "att": [a], "def": [enemy], "rounds": 0,
		"town": "", "place_x_m": 1050, "place_y_m": 1000,
		"actions": {"att": {"kind": "attack"}, "def": {"kind": "hold"}}}
	state.battles = [battle]
	BattleFormation.ensure(battle)
	BattleRules.freeze(repo, state, battle)
	battle.formations.att.current = "line"
	battle.formations.def.current = "line"
	BattleGroups.refresh(repo, state, battle)
	return {"repo": repo, "state": state, "a": a, "friend": friend, "enemy": enemy, "battle": battle}

func _power(f: Dictionary) -> int:
	return int(BattleSystem.unit_strength(f.repo, f.state, f.a, Callable(), true, [f.enemy]).power)

func test_out_of_range_has_no_ranged_power() -> void:
	var f := _fixture(5000)
	assert_eq(_power(f), 0, "An attack warrant cannot shoot across five kilometres")

func _shots(f: Dictionary, target := "") -> Dictionary:
	return BattleRanged.counts(f.repo, f.state, f.battle, f.a, target)

func _fixed_losses(f: Dictionary) -> void:
	for tier: Dictionary in f.repo.battle_outcomes:
		tier.attacker_loss_permille = 100
		tier.defender_loss_permille = 100
		tier.attacker_morale = 0
		tier.defender_morale = 0
		tier.wounded_share_permille = 0
		tier.rout = "none"

func test_inclusive_reach_and_forward_cone_edges() -> void:
	var f := _fixture()
	var origin := Vector2i(1000, 1000)
	var face := Vector2i(1000, 0)
	var friends: Array[Vector2i] = []
	assert_true(BattleRanged.clear_shot(f.repo, origin, origin + Vector2i(400, 0), face, friends))
	assert_false(BattleRanged.clear_shot(f.repo, origin, origin + Vector2i(401, 0), face, friends))
	# 200^2 + 200^2 = 80000 < 400^2; lateral / forward = 1 exactly.
	assert_true(BattleRanged.clear_shot(f.repo, origin, origin + Vector2i(200, 200), face, friends))
	assert_false(BattleRanged.clear_shot(f.repo, origin, origin + Vector2i(199, 200), face, friends))
	assert_false(BattleRanged.clear_shot(f.repo, origin, origin + Vector2i(-200, 0), face, friends))
	assert_false(BattleRanged.clear_shot(f.repo, origin, origin + Vector2i(100, 0), face, friends), "Close contact uses defence")

func test_friendly_disc_tangent_blocks_but_outside_or_behind_does_not() -> void:
	var f := _fixture()
	var face := Vector2i.RIGHT
	var friends: Array[Vector2i] = [Vector2i(150, 20)]
	# Cross product = 20*300; squared equals 20^2 * 300^2 at tangency.
	assert_false(BattleRanged.clear_shot(f.repo, Vector2i.ZERO, Vector2i(300, 0), face, friends))
	friends[0].y = 21
	assert_true(BattleRanged.clear_shot(f.repo, Vector2i.ZERO, Vector2i(300, 0), face, friends))
	friends[0] = Vector2i(-150, 0)
	assert_true(BattleRanged.clear_shot(f.repo, Vector2i.ZERO, Vector2i(300, 0), face, friends))
	friends[0] = Vector2i(450, 0)
	assert_true(BattleRanged.clear_shot(f.repo, Vector2i.ZERO, Vector2i(300, 0), face, friends))
	friends[0] = Vector2i(20, 20)
	assert_false(BattleRanged.clear_shot(f.repo, Vector2i.ZERO, Vector2i(180, 240), Vector2i(3, 4), friends), "Diagonal segment uses the same integer cross-product rule")

func test_own_front_rank_obstructs_rear_without_reserve_output() -> void:
	var f := _fixture()
	f.battle.formations.att.current = "double_rank"
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_shots(f), {"firing": 50, "melee": 0, "fit": 100})
	assert_eq(BattleRanged.active_permille(_shots(f)), 500)
	var strength := BattleSystem.unit_strength(f.repo, f.state, f.a, Callable(), true, [f.enemy])
	var factor := {}
	for row: Dictionary in strength.factors:
		if row.source == "contact:ranged": factor = row
	assert_eq(factor.get("permille"), 500)
	assert_string_contains(factor.get("reason", ""), "50 firing")

func _block(f: Dictionary) -> void:
	f.battle.att.append(f.friend)
	f.state.regiments[f.friend].x_m = 1150
	f.state.army_roster[f.friend].infantry = "0"
	f.state.army_roster[f.friend].archers = "50"
	BattleGroups.refresh(f.repo, f.state, f.battle)
	f.battle.group_facing[f.friend] = 180

func test_friendly_unit_blocks_actual_power_and_casualties() -> void:
	var clear := _fixture(300, 50)
	_fixed_losses(clear)
	assert_eq(_shots(clear).firing, 50)
	assert_gt(_power(clear), 0)
	assert_eq(BattleSystem.step_battle(clear.repo, clear.state, 9463).status, "complete")
	# 100 tier * 800 ranged / 1000 = 80 per mille; 50 * 80 / 1000 = 4.
	assert_eq(Personnel.count(clear.state, clear.enemy, "dead"), 4)
	var blocked := _fixture(300, 50)
	_fixed_losses(blocked)
	_block(blocked)
	assert_eq(_shots(blocked).firing, 0)
	assert_eq(_power(blocked), 0)
	assert_eq(BattleSystem.step_battle(blocked.repo, blocked.state, 9463).status, "complete")
	assert_eq(Personnel.count(blocked.state, blocked.enemy, "dead"), 0)

func test_partial_fire_reduces_actual_losses_once() -> void:
	var f := _fixture()
	_fixed_losses(f)
	f.battle.formations.att.current = "double_rank"
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9463).status, "complete")
	# 100 tier * 800 ranged * 500 firing / 1000^2 = 40; 100 people -> 4 dead.
	assert_eq(Personnel.count(f.state, f.enemy, "dead"), 4)
	var hash_after := SaveLoad.state_hash(f.state)
	BattleSystem.step_battle(f.repo, f.state, 9463)
	assert_eq(SaveLoad.state_hash(f.state), hash_after)

func test_out_of_range_cannot_inflict_actual_damage() -> void:
	var f := _fixture(5000)
	_fixed_losses(f)
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9463).status, "complete")
	assert_eq(Personnel.count(f.state, f.enemy, "dead"), 0)

func test_local_sight_and_designated_target_do_not_read_hidden_enemy() -> void:
	var f := _fixture()
	f.repo.balance.player_sight_km = 0
	assert_eq(_shots(f).firing, 0)
	f.repo.balance.player_sight_km = 12
	assert_eq(_shots(f, f.friend).firing, 0, "A friend is no enemy target")
	assert_gt(_shots(f).firing, 0)
	f.state.foes[f.enemy].captured = true
	assert_eq(_shots(f).firing, 0)

func test_close_enemy_defends_and_withdrawal_cannot_fire() -> void:
	var f := _fixture(100, 50)
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "hold")
	assert_eq(_shots(f), {"firing": 0, "melee": 50, "fit": 50})
	assert_gt(_power(f), 0, "Legal melee defence survives suppression of shooting")
	f.battle.actions.att.kind = "retreat"
	assert_eq(_shots(f).firing, 0)
	assert_eq(_shots(f).melee, 0)

func test_ceasefire_and_protected_withdrawal_forbid_fire() -> void:
	var f := _fixture()
	f.battle.parley = {"agreed": {"ceasefire": {"policy": "protect"}}}
	assert_eq(_shots(f).firing, 0)
	f.battle.parley = {"agreed": {"safe_withdrawal": {"policy": "protect"}}}
	f.battle.actions.def.kind = "retreat"
	assert_eq(_shots(f).firing, 0)

func test_failed_round_and_json_freeze_fire_eligibility_and_casualties() -> void:
	var f := _fixture(300, 50)
	_fixed_losses(f)
	var cohort := ""
	for id: String in f.state.military_rosters[f.enemy].cohort_ids:
		if int(f.state.military_cohorts[id].fit) > 0: cohort = id
	var origin := String(f.state.military_cohorts[cohort].source_population_field)
	f.state.military_cohorts[cohort].source_population_field = "invalid"
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9463).status, "error")
	assert_eq(int(f.battle.pending_round.tier.unit_loss_permille[f.enemy]), 80)
	var frozen := SaveLoad.state_hash(f.state)
	BattleSystem.prepare_day(f.repo, f.state)
	assert_eq(SaveLoad.state_hash(f.state), frozen)
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9463).status, "error")
	assert_eq(SaveLoad.state_hash(f.state), frozen)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	f.state.military_cohorts[cohort].source_population_field = origin
	restored.military_cohorts[cohort].source_population_field = origin
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9463).status, "complete")
	assert_eq(BattleSystem.step_battle(f.repo, restored, 9463).status, "complete")
	assert_eq(Personnel.count(f.state, f.enemy, "dead"), 4)
	assert_eq(SaveLoad.state_hash(f.state), SaveLoad.state_hash(restored))

func test_each_target_requires_its_own_fire_geometry() -> void:
	var f := _fixture(300, 50)
	_fixed_losses(f)
	var distant := String(f.state.foes.keys()[1])
	f.state.foes[distant].x_m = 6000
	f.state.foes[distant].y_m = 1000
	Personnel.replace(f.repo, f.state, distant, 50)
	f.battle.def.append(distant)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	f.battle.group_facing[f.a] = 0
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9463).status, "complete")
	assert_eq(Personnel.count(f.state, f.enemy, "dead"), 4)
	assert_eq(Personnel.count(f.state, distant, "dead"), 0, "An in-range enemy does not expose its remote ally")

func test_designated_target_does_not_authorize_shooting_someone_else() -> void:
	var f := _fixture(300, 50)
	var distant := String(f.state.foes.keys()[1])
	f.state.foes[distant].x_m = 6000
	f.state.foes[distant].y_m = 1000
	f.battle.def.append(distant)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var request := {"id": "ranged-designated", "unit": f.a, "battle_id": 9463,
		"task": "advance", "target_unit": distant, "source": "player"}
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, request).status, "pending")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "ranged-designated").status, "received")
	assert_eq(_shots(f).firing, 0)

func test_uncommitted_reserve_cannot_fire() -> void:
	var f := _fixture(300, 50)
	f.battle.reserves = {f.a: true}
	assert_eq(_shots(f).firing, 0)
	assert_eq(BattleRanged.incoming_permille(f.repo, f.state, f.battle, "def", f.enemy), 0)

func test_disc_extending_inside_either_endpoint_blocks() -> void:
	var f := _fixture()
	var friends: Array[Vector2i] = [Vector2i(-10, 0)]
	assert_false(BattleRanged.clear_shot(f.repo, Vector2i.ZERO, Vector2i(300, 0), Vector2i.RIGHT, friends))
	friends[0] = Vector2i(310, 0)
	assert_false(BattleRanged.clear_shot(f.repo, Vector2i.ZERO, Vector2i(300, 0), Vector2i.RIGHT, friends))
	friends[0] = Vector2i(-20, 0)
	assert_true(BattleRanged.clear_shot(f.repo, Vector2i.ZERO, Vector2i(300, 0), Vector2i.RIGHT, friends), "Touching only the excluded endpoint does not block")

func test_close_contact_uses_defensive_strength_and_actual_melee_losses() -> void:
	var f := _fixture(100, 50)
	_fixed_losses(f)
	f.battle.actions.def.kind = "attack"
	var strength := BattleSystem.unit_strength(f.repo, f.state, f.a, Callable(), true, [f.enemy])
	assert_true(strength.factors.any(func(row: Dictionary) -> bool: return row.source == "stance:defence"))
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9463).status, "complete")
	assert_eq(Personnel.count(f.state, f.enemy, "dead"), 5, "50 fit * 100 melee / 1000")

func test_blocked_fire_cannot_rout_an_enemy_through_morale_damage() -> void:
	var f := _fixture(300, 50)
	_fixed_losses(f)
	_block(f)
	for tier: Dictionary in f.repo.battle_outcomes:
		tier.defender_morale = -10
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9463).status, "complete")
	assert_eq(int(f.state.foes[f.enemy].morale), 100)

func test_designated_remote_target_does_not_forbid_local_self_defence() -> void:
	var f := _fixture(100, 50)
	var distant := String(f.state.foes.keys()[1])
	f.state.foes[distant].x_m = 6000
	f.state.foes[distant].y_m = 1000
	f.battle.def.append(distant)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var request := {"id": "ranged-intercepted", "unit": f.a, "battle_id": 9463,
		"task": "advance", "target_unit": distant, "source": "player"}
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, request).status, "pending")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "ranged-intercepted").status, "received")
	f.battle.actions.def.kind = "attack"
	assert_eq(_shots(f).melee, 50)
	assert_eq(_shots(f).firing, 0)

func test_production_daily_deployment_retains_an_actual_firing_line() -> void:
	var f := _fixture(300, 50)
	_fixed_losses(f)
	BattleSystem.prepare_day(f.repo, f.state)
	assert_eq(_shots(f).firing, 50, "Daily deployment must not force every archer into melee")
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9463).status, "complete")
	assert_eq(Personnel.count(f.state, f.enemy, "dead"), 4)
