extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")

func _fixture(gap := 700, people := 50) -> Dictionary:
	var repo := SuiteData.open_country(SuiteData.repo())
	var state := SuiteData.campaign(repo, 9461)
	var codes := state.regiments.keys()
	codes.sort()
	var a := String(codes[0])
	var enemy := String(state.foes.keys()[0])
	var mounted := ""
	for arm: String in repo.world_table("military", "unit_types"):
		if repo.world_table("military", "unit_types")[arm].type == "mounted":
			mounted = arm
	for arm: String in repo.world_table("military", "unit_types"):
		state.army_roster[a][arm] = "0"
	state.army_roster[a][mounted] = str(people)
	repo.world_table("military", "unit_types")[mounted].crew = "1"
	Personnel.replace(repo, state, a, people)
	Personnel.replace(repo, state, enemy, 50)
	for code: String in [a, enemy]:
		var e := BattleSystem._stored(state, code)
		e["x_m"] = 1000 if code == enemy else 1000 + gap
		e["y_m"] = 1000
		e["supplies"] = 100000
		e["morale"] = 100
		e.erase("camp_town")
		e["order"] = ArmySystem.ORDER_STANDBY
	var battle := {"id": 9461, "att": [a], "def": [enemy], "rounds": 0,
		"town": "", "place_x_m": 1050, "place_y_m": 1000,
		"actions": {"att": {"kind": "attack"}, "def": {"kind": "hold"}}}
	state.battles = [battle]
	BattleFormation.ensure(battle)
	BattleRules.freeze(repo, state, battle)
	battle.formations.att.current = "line"
	battle.formations.def.current = "line"
	BattleGroups.refresh(repo, state, battle)
	return {"repo": repo, "state": state, "a": a, "enemy": enemy, "battle": battle}

func _context(f: Dictionary) -> Dictionary:
	return BattleSystem.combat_context(f.repo, f.state, f.battle, "def")

func _move(f: Dictionary) -> void:
	f.state.day += 1
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	BattleGroups.refresh(f.repo, f.state, f.battle)

func test_stationary_cavalry_attacks_without_shock() -> void:
	var f := _fixture(100)
	assert_eq(_context(f).kind, "melee", "an attack order supplies no actual momentum")
	_move(f)
	assert_eq(_context(f).kind, "melee", "contact cannot manufacture run-up")

func test_actual_six_hundred_metre_approach_earns_one_impact() -> void:
	var f := _fixture()
	assert_eq(_context(f).kind, "melee")
	_move(f)
	# Gap 700 - contact 100 = 600 metres actually ridden; no foe movement credit.
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), Vector2i(1100, 1000))
	assert_eq(_context(f).kind, "shock")
	assert_eq(int(_context(f).loss_permille), 1250)
	var e := BattleSystem._stored(f.state, f.a)
	assert_eq(int(e.get("charge", {}).get("runup_m", -1)), 600)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_context(f).kind, "shock", "refresh does not consume an unsettled impact")

func test_short_approach_is_melee() -> void:
	var f := _fixture(399)
	_move(f)
	assert_eq(_context(f).kind, "melee", "299 metres is shorter than the 300 metre run-up")

func test_blocked_ground_earns_no_runup() -> void:
	var f := _fixture(2700)
	f.repo.balance["army_march_grid_px"] = 1
	MarchPath.use(f.repo, MarchPath.build(f.repo, 5, 3, 1000,
		PackedByteArray([0,0,255,0,0, 0,0,255,0,0, 0,0,255,0,0])))
	_move(f)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), Vector2i(3700, 1000))
	assert_eq(_context(f).kind, "melee")
	MarchPath.forget()

func test_law_bars_shock_but_keeps_ordinary_attack() -> void:
	var f := _fixture()
	f.battle["parley"] = {"agreed": {"tactics": {"policy": "restrained"}}}
	_move(f)
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "attack")
	assert_eq(_context(f).kind, "melee")

func test_casualty_bins_and_json_preserve_earned_movement() -> void:
	var f := _fixture(3700, 51)
	_move(f)
	var e := BattleSystem._stored(f.state, f.a)
	assert_gt(int(e.get("charge", {}).get("runup_m", 0)), 0)
	var saved: Dictionary = e.get("charge", {}).duplicate(true)
	Personnel.move(f.repo, f.state, f.a, "fit", "dead", 1)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(e.get("charge"), saved, "51 -> 50 is not a fresh charge")
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	var back := f.duplicate()
	back.state = restored
	back.battle = restored.battles[0]
	_move(f)
	_move(back)
	assert_eq(SaveLoad.state_hash(f.state), SaveLoad.state_hash(restored))
	assert_eq(_context(f).kind, "shock")

func _fixed_losses(f: Dictionary, rate: int) -> void:
	for tier: Dictionary in f.repo.battle_outcomes:
		tier.attacker_loss_permille = rate
		tier.defender_loss_permille = rate
		tier.attacker_morale = 0
		tier.defender_morale = 0
		tier.wounded_share_permille = 0
		tier.rout = "none"

func test_successful_impact_requires_real_disengagement_and_regrouping_before_renewal() -> void:
	var f := _fixture()
	_fixed_losses(f, 0)
	_move(f)
	var result := BattleSystem.step_battle(f.repo, f.state, 9461)
	assert_eq(result.status, "complete")
	assert_eq(result.events[0].contexts.def.kind, "shock")
	assert_eq(_context(f).kind, "melee", "the successful round consumes its impact")
	var hash_after := SaveLoad.state_hash(f.state)
	BattleSystem.step_battle(f.repo, f.state, 9461)
	assert_eq(SaveLoad.state_hash(f.state), hash_after)
	_move(f)
	# 100 m contact + 300 m run-up = real 400 m gap after disengaging.
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), Vector2i(1400, 1000))
	assert_eq(_context(f).kind, "melee")
	_move(f)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), Vector2i(1400, 1000), "one actual regroup day")
	_move(f)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), Vector2i(1100, 1000))
	assert_eq(_context(f).kind, "shock")

func test_failed_round_freezes_movement_and_impact_through_json_retry() -> void:
	var f := _fixture()
	_fixed_losses(f, 100)
	_move(f)
	var cohort := ""
	for id: String in f.state.military_rosters[f.enemy].cohort_ids:
		if int(f.state.military_cohorts[id].fit) > 0: cohort = id
	var origin := String(f.state.military_cohorts[cohort].source_population_field)
	f.state.military_cohorts[cohort].source_population_field = "invalid"
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9461).status, "error")
	assert_eq(f.battle.pending_round.contexts.def.kind, "shock")
	# 100 per mille x 1250 / 1000 = 125; 50 defenders x 125 / 1000 = 6 dead.
	assert_eq(int(f.battle.pending_round.tier.defender_loss_permille), 125)
	var frozen := SaveLoad.state_hash(f.state)
	BattleSystem.prepare_day(f.repo, f.state)
	assert_eq(SaveLoad.state_hash(f.state), frozen)
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9461).status, "error")
	assert_eq(SaveLoad.state_hash(f.state), frozen)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	f.state.military_cohorts[cohort].source_population_field = origin
	restored.military_cohorts[cohort].source_population_field = origin
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9461).status, "complete")
	assert_eq(BattleSystem.step_battle(f.repo, restored, 9461).status, "complete")
	assert_eq(SaveLoad.state_hash(f.state), SaveLoad.state_hash(restored))
	assert_eq(Personnel.count(f.state, f.enemy, "dead"), 6)
	assert_eq(_context(f).kind, "melee")

func test_captured_rider_cannot_retain_earned_shock() -> void:
	var f := _fixture()
	_move(f)
	f.state.regiments[f.a]["captured"] = true
	assert_eq(_context(f).kind, "melee")

func test_friendly_group_blocks_the_actual_charge_corridor() -> void:
	var f := _fixture()
	var codes: Array = f.state.regiments.keys()
	codes.sort()
	var ally := String(codes[1])
	Personnel.replace(f.repo, f.state, ally, 50)
	f.state.regiments[ally]["x_m"] = 1400
	f.state.regiments[ally]["y_m"] = 1000
	f.battle.att.append(ally)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	BattleCharge.move(f.repo, f.state, f.battle, f.a, f.enemy)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), Vector2i(1700, 1000))
	assert_eq(int(f.state.regiments[f.a].charge.runup_m), 0)
	assert_eq(_context(f).kind, "melee")

func test_enemy_closing_distance_supplies_no_momentum() -> void:
	var f := _fixture()
	f.state.foes[f.enemy].x_m = 1600
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(_context(f).kind, "melee")
	BattleCharge.move(f.repo, f.state, f.battle, f.a, f.enemy)
	assert_eq(int(f.state.regiments[f.a].charge.runup_m), 0)
	assert_eq(_context(f).kind, "melee")

func test_diagonal_approach_reaches_contact_in_whole_metres() -> void:
	var f := _fixture()
	f.state.regiments[f.a].y_m = 1700
	BattleGroups.refresh(f.repo, f.state, f.battle)
	BattleCharge.move(f.repo, f.state, f.battle, f.a, f.enemy)
	assert_eq(_context(f).kind, "shock", "rounding must not strand the rider just outside contact")

func test_shock_losses_apply_only_to_contacted_opponent() -> void:
	var f := _fixture()
	_fixed_losses(f, 100)
	_move(f)
	var others: Array = f.state.foes.keys().filter(func(code: String) -> bool: return code != f.enemy)
	assert_false(others.is_empty())
	var distant := String(others[0])
	Personnel.replace(f.repo, f.state, distant, 50)
	var e := BattleSystem._stored(f.state, distant)
	e["x_m"] = 1000
	e["y_m"] = 3000
	e["morale"] = 100
	f.battle.def.append(distant)
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def", f.enemy).kind, "shock")
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def", distant).kind, "melee")
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9461).status, "complete")
	assert_eq(Personnel.count(f.state, f.enemy, "dead"), 6)
	assert_eq(Personnel.count(f.state, distant, "dead"), 5)

func test_new_target_cannot_skip_regroup_after_an_impact() -> void:
	var f := _fixture()
	_fixed_losses(f, 0)
	_move(f)
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9461).status, "complete")
	var others: Array = f.state.foes.keys().filter(func(code: String) -> bool: return code != f.enemy)
	var next := String(others[0])
	Personnel.replace(f.repo, f.state, next, 50)
	f.state.foes[next]["x_m"] = 2000
	f.state.foes[next]["y_m"] = 1000
	f.battle.def.append(next)
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, {"id": "new-target", "unit": f.a,
		"battle_id": 9461, "task": "charge", "target_unit": next}).status, "pending")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "new-target").status, "received")
	BattleGroups.refresh(f.repo, f.state, f.battle)
	f.state.day += 1
	BattleCharge.move(f.repo, f.state, f.battle, f.a, next)
	assert_eq(_context(f).kind, "melee", "changing the opponent cannot bypass disengagement and regrouping")

func test_supply_shortfall_cannot_pay_for_a_charge() -> void:
	var f := _fixture()
	f.state.day = 29   # whole monthly food has a positive bite on its final day
	var reg := ArmySystem.regiment(f.repo, f.a, f.state)
	assert_gt(ArmySystem.day_bite(ArmySystem.supply_use(f.repo, reg, f.state), 30), 0)
	f.state.regiments[f.a].supplies = 0
	_move(f)
	assert_eq(_context(f).kind, "melee")
	assert_false(f.state.regiments[f.a].has("charge"), "unfunded side attack cannot prepare a charge")

func test_actual_battle_merge_preserves_unit_momentum_and_daily_move_guard() -> void:
	var f := _fixture(3700, 51)
	_move(f)
	var codes: Array = f.state.regiments.keys()
	codes.sort()
	var ally := String(codes[1])
	var foes: Array = f.state.foes.keys().filter(func(code: String) -> bool: return code != f.enemy)
	var enemy := String(foes[0])
	Personnel.replace(f.repo, f.state, ally, 50)
	Personnel.replace(f.repo, f.state, enemy, 50)
	f.state.regiments[ally]["x_m"] = 1000
	f.state.regiments[ally]["y_m"] = 1000
	f.state.foes[enemy]["x_m"] = 2200
	f.state.foes[enemy]["y_m"] = 1000
	var other := {"id": 9462, "att": [ally], "def": [enemy], "rounds": 0,
		"town": "", "place_x_m": 1000, "place_y_m": 1000, "actions": {}}
	BattleFormation.ensure(other)
	BattleRules.freeze(f.repo, f.state, other)
	BattleGroups.refresh(f.repo, f.state, other)
	f.state.battles.append(other)
	var charge: Dictionary = f.state.regiments[f.a].charge.duplicate(true)
	assert_eq(BattleMerge.day(f.repo, f.state).size(), 1)
	assert_eq(f.state.battles.size(), 1)
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(f.state.regiments[f.a].charge, charge)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), Vector2i(2200, 1000))

func test_turning_toward_a_moved_enemy_must_earn_fresh_forward_runup() -> void:
	var f := _fixture(3700)
	_move(f)
	# 2500 m west has been ridden; the same enemy is now only 300 m south.
	f.state.foes[f.enemy]["x_m"] = 2200
	f.state.foes[f.enemy]["y_m"] = 1300
	BattleGroups.refresh(f.repo, f.state, f.battle)
	f.state.day += 1
	BattleCharge.move(f.repo, f.state, f.battle, f.a, f.enemy)
	assert_eq(_context(f).kind, "melee", "a new 200 m approach cannot borrow the old westward run-up")

func test_diagonal_displacement_cannot_exceed_the_daily_budget() -> void:
	var f := _fixture(3700)
	f.state.regiments[f.a]["y_m"] = 4700
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var from := BattleSystem._at_m(f.repo, f.state, f.a)
	BattleCharge.move(f.repo, f.state, f.battle, f.a, f.enemy)
	var movement := BattleSystem._at_m(f.repo, f.state, f.a) - from
	assert_gt(movement.length_squared(), 0)
	assert_lte(movement.length_squared(), 6250000, "2500 squared, including whole-metre quantization")
	assert_eq(_context(f).kind, "melee")

func test_hold_cannot_erase_the_need_to_regroup_after_impact() -> void:
	var f := _fixture()
	_fixed_losses(f, 0)
	_move(f)
	assert_eq(BattleSystem.step_battle(f.repo, f.state, 9461).status, "complete")
	f.battle.actions.att = {"kind": "hold"}
	_move(f)
	# The enemy opens a gap while our cavalry holds at its line, without regrouping.
	f.state.foes[f.enemy].x_m = 400
	f.battle.actions.att = {"kind": "attack"}
	BattleGroups.refresh(f.repo, f.state, f.battle)
	f.state.day += 1
	BattleCharge.move(f.repo, f.state, f.battle, f.a, f.enemy)
	assert_eq(_context(f).kind, "melee", "resuming attack must still regroup before a fresh approach")
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), Vector2i(1100, 1000), "no fresh approach before regrouping")
