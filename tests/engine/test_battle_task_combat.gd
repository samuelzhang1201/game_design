extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func _fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 9443)
	state.day = 30
	var codes := state.regiments.keys()
	codes.sort()
	var enemy := String(state.foes.keys()[0])
	var battle := {"id": 9443, "att": [codes[0], codes[1]], "def": [enemy], "rounds": 0,
		"town": "", "place_x_m": 0, "place_y_m": 0,
		"actions": {"att": {"kind": "hold"}, "def": {"kind": "hold"}}}
	state.battles = [battle]
	for code: String in battle.att + battle.def:
		BattleSystem._stored(state, code)["supplies"] = 100000
		BattleSystem._stored(state, code)["morale"] = 100
	return {"repo": repo, "state": state, "a": String(codes[0]), "b": String(codes[1]),
		"enemy": enemy, "battle": battle}

func _issue(f: Dictionary, id: String, task: String, unit := "") -> void:
	var result := BattleTaskSystem.issue_task(f.repo, f.state, {"id": id,
		"unit": f.a if unit == "" else unit, "battle_id": 9443, "task": task})
	assert_eq(result.get("status"), "pending", str(result))

func _receive(f: Dictionary, id: String) -> void:
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, id).get("status"), "received")

func _action_factor(f: Dictionary, code: String) -> Dictionary:
	var strength := BattleSystem.unit_strength(f.repo, f.state, code, Callable(), false)
	for factor: Dictionary in strength.get("factors", []):
		if factor.category == "action": return factor
	return {}

func test_received_task_changes_only_recipient_and_cancellation_waits_for_receipt() -> void:
	var f := _fixture()
	_issue(f, "advance", "advance")
	assert_eq(_action_factor(f, f.a).source, "order:hold")
	_receive(f, "advance")
	assert_eq(_action_factor(f, f.a).source, "order:attack")
	assert_eq(_action_factor(f, f.b).source, "order:hold")
	_issue(f, "defend", "defend")
	assert_eq(_action_factor(f, f.a).source, "order:attack")
	_receive(f, "defend")
	assert_eq(_action_factor(f, f.a).source, "order:hold")
	_issue(f, "again", "flank")
	_receive(f, "again")
	_issue(f, "cancel", "cancel")
	assert_eq(_action_factor(f, f.a).source, "order:attack")
	_receive(f, "cancel")
	assert_eq(_action_factor(f, f.a).source, "order:hold")

func test_live_terms_and_charge_law_block_only_actual_actions() -> void:
	var f := _fixture()
	_issue(f, "charge", "charge")
	_receive(f, "charge")
	assert_eq(_action_factor(f, f.a).source, "order:attack")
	f.battle["parley"] = {"agreed": {"tactics": {"policy": "restrained"}}}
	assert_eq(_action_factor(f, f.a).source, "order:hold")
	f.battle.erase("parley")
	_issue(f, "advance", "advance")
	_receive(f, "advance")
	f.battle["parley"] = {"agreed": {"ceasefire": {"policy": "protect"}}}
	var events: Array = []
	BattleSystem._fight(f.repo, f.state, f.battle, events)
	assert_eq(f.battle.rounds, 0)
	assert_eq(events, [])

func test_mixed_round_uses_unit_power_morale_and_extra_supplies_once_after_json() -> void:
	var f := _fixture()
	_issue(f, "advance", "advance")
	_receive(f, "advance")
	var before_a := int(f.state.regiments[f.a].supplies)
	var before_b := int(f.state.regiments[f.b].supplies)
	var reg := ArmySystem.regiment(f.repo, f.a, f.state)
	var bite := ArmySystem.day_bite(ArmySystem.supply_use(f.repo, reg, f.state), f.state.day)
	@warning_ignore("integer_division")
	var extra := (bite * int(f.repo.battle_orders.attack.extra_supply_permille) + 999) / 1000
	var expected: int = BattleSystem.unit_strength(f.repo, f.state, f.a, Callable(), true, [f.enemy]).power \
		+ BattleSystem.unit_strength(f.repo, f.state, f.b, Callable(), false, [f.enemy]).power
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	var events: Array = []
	var replay_events: Array = []
	BattleSystem._fight(f.repo, f.state, f.battle, events)
	BattleSystem._fight(f.repo, restored, BattleSystem.battle_by_id(restored, 9443), replay_events)
	assert_eq(f.battle.rounds, 1)
	if events.is_empty(): return
	assert_eq(events[0].att_power, expected)
	assert_eq(events[0].costs.size(), 1)
	assert_eq(int(f.state.regiments[f.a].supplies), before_a - extra)
	assert_eq(int(f.state.regiments[f.b].supplies), before_b)
	assert_eq(SaveLoad.state_hash(restored), SaveLoad.state_hash(f.state), "whole JSON state including the terminal report")
	var saved: Dictionary = f.state.to_dict()
	BattleSystem._fight(f.repo, f.state, f.battle, events)
	assert_eq(f.state.to_dict(), saved)

func test_empty_tasked_unit_falls_back_without_stopping_other_tasked_unit() -> void:
	var f := _fixture()
	_issue(f, "a", "advance")
	_receive(f, "a")
	_issue(f, "b", "advance", f.b)
	_receive(f, "b")
	f.state.regiments[f.a].supplies = 0
	var events: Array = []
	BattleSystem._fight(f.repo, f.state, f.battle, events)
	assert_eq(f.battle.rounds, 1)
	assert_eq(events[0].costs.size(), 1)
	if events.is_empty(): return
	assert_eq(events[0].costs[0].code, f.b)
	assert_eq(_action_factor(f, f.a).source, "order:hold")

func test_task_morale_uses_existing_hold_reduction_once() -> void:
	var f := _fixture()
	_issue(f, "advance", "advance")
	_receive(f, "advance")
	for code: String in [f.a, f.b]:
		f.state.regiments[code].stance = "steady"
	for tier: Dictionary in f.repo.battle_outcomes:
		tier.attacker_morale = -10
		tier.defender_morale = -10
		tier.rout = "none"
	var events: Array = []
	BattleSystem._fight(f.repo, f.state, f.battle, events)
	assert_eq(int(f.state.regiments[f.a].morale), 90, "attack: -10 * 1000 / 1000")
	assert_eq(int(f.state.regiments[f.b].morale), 92, "hold: -10 * 800 / 1000")

func test_failed_personnel_commit_keeps_task_actions_draw_and_costs_through_json() -> void:
	var f := _fixture()
	_issue(f, "advance", "advance")
	_receive(f, "advance")
	for tier: Dictionary in f.repo.battle_outcomes:
		tier.attacker_loss_permille = 1000
		tier.defender_loss_permille = 1000
		tier.rout = "none"
	var cohort := String(f.state.military_rosters[f.enemy].cohort_ids[0])
	var origin := String(f.state.military_cohorts[cohort].source_population_field)
	f.state.military_cohorts[cohort].source_population_field = "invalid"
	var food := int(f.state.regiments[f.a].supplies)
	var events: Array = []
	assert_true(BattleSystem._fight(f.repo, f.state, f.battle, events).has("error"))
	assert_eq(int(f.state.regiments[f.a].supplies), food)
	var draw: Dictionary = f.state.rng.to_dict()
	var pending: Dictionary = f.battle.pending_round.duplicate(true)
	assert_true(BattleSystem._fight(f.repo, f.state, f.battle, events).has("error"))
	assert_eq(f.state.rng.to_dict(), draw)
	assert_eq(f.battle.pending_round, pending)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	f.state.military_cohorts[cohort].source_population_field = origin
	restored.military_cohorts[cohort].source_population_field = origin
	var replay: Array = []
	BattleSystem._fight(f.repo, restored, BattleSystem.battle_by_id(restored, 9443), replay)
	BattleSystem._fight(f.repo, f.state, f.battle, events)
	assert_eq(SaveLoad.state_hash(restored), SaveLoad.state_hash(f.state), "whole JSON state including the terminal report")
	assert_eq(f.state.rng.to_dict(), draw)
	assert_eq(int(f.state.regiments[f.a].supplies), food - int(pending.costs[0].supplies))

func test_live_unit_law_and_stale_battle_task_are_isolated() -> void:
	var f := _fixture()
	_issue(f, "a", "charge")
	_receive(f, "a")
	_issue(f, "b", "charge", f.b)
	_receive(f, "b")
	f.state.law_in_force["unit:" + f.a] = {"battle_tactics": {"value": "restrained", "decree_id": 100}}
	assert_eq(_action_factor(f, f.a).source, "order:hold")
	assert_eq(_action_factor(f, f.b).source, "order:attack")
	f.battle.id = 9444
	assert_eq(_action_factor(f, f.b).source, "order:hold")

func test_missing_or_captured_target_suspends_attack_without_mutating_task() -> void:
	var f := _fixture()
	var sent := BattleTaskSystem.issue_task(f.repo, f.state, {"id": "target", "unit": f.a,
		"battle_id": 9443, "task": "flank", "target_unit": f.enemy})
	assert_eq(sent.status, "pending")
	_receive(f, "target")
	var before: Dictionary = f.state.unit_tasks.duplicate(true)
	f.state.foes[f.enemy].captured = true
	assert_eq(_action_factor(f, f.a).source, "order:hold")
	f.state.foes[f.enemy].captured = false
	f.battle.def.clear()
	assert_eq(_action_factor(f, f.a).source, "order:hold")
	assert_eq(f.state.unit_tasks, before)

func test_actual_retreat_cannot_resume_attack_from_a_task() -> void:
	var f := _fixture()
	_issue(f, "a", "advance")
	_receive(f, "a")
	f.battle.actions.att.kind = "attack"
	f.state.regiments[f.a].battle_retreat = true
	assert_eq(_action_factor(f, f.a).source, "order:retreat")

func test_received_attack_uses_reserved_recipient_and_hold_excludes_its_attack_cost() -> void:
	var f := _fixture()
	_issue(f, "advance", "advance")
	_receive(f, "advance")
	var expected: int = BattleSystem.unit_strength(f.repo, f.state, f.a, Callable(), true).power
	f.battle["reserves"] = {f.a: {"reason": "Held until ordered forward"}}
	assert_eq(BattleSystem.side_power(f.repo, f.state, [f.a], Callable(), false), expected)
	f.battle.erase("reserves")
	_issue(f, "defend", "defend")
	_receive(f, "defend")
	f.battle.actions.att.kind = "attack"
	var events: Array = []
	BattleSystem._fight(f.repo, f.state, f.battle, events)
	events = events.filter(func(event: Dictionary) -> bool: return event.kind == "round")
	assert_eq(events.size(), 1)
	if events.is_empty(): return
	assert_eq(events[0].costs.size(), 1)
	assert_eq(events[0].costs[0].code, f.b)

func test_task_attack_does_not_authorize_pursuit_context() -> void:
	var f := _fixture()
	_issue(f, "advance", "advance")
	_receive(f, "advance")
	f.battle.actions.def.kind = "retreat"
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def").kind, "withdrawal")

func test_legacy_pending_round_keeps_side_effects_and_new_plan_freezes_received_action() -> void:
	var f := _fixture()
	_issue(f, "advance", "advance")
	_receive(f, "advance")
	f.battle["pending_round"] = {"roll": 53}
	assert_eq(_action_factor(f, f.a).source, "order:hold", "old plans did not execute unit tasks")
	f.battle.pending_round["unit_actions"] = {f.a: {"kind": "attack", "task_id": "advance", "reason": "Frozen received advance"}}
	_issue(f, "defend", "defend")
	_receive(f, "defend")
	assert_eq(_action_factor(f, f.a).source, "order:attack", "receipt cannot rewrite a planned round")
	f.battle.erase("pending_round")
	assert_eq(_action_factor(f, f.a).source, "order:hold", "the next round uses the new receipt")

func test_holding_cavalry_cannot_supply_an_infantry_tasks_shock_context() -> void:
	var f := _fixture()
	var arms: Dictionary = f.repo.world_table("military", "unit_types")
	var mounted := ""
	var foot := ""
	for arm: String in arms:
		if arms[arm].type == "mounted": mounted = arm
		if arms[arm].type == "melee": foot = arm
	assert_ne(mounted, "")
	if foot == "": foot = "infantry"
	arms[mounted].crew = "1"
	arms[foot].crew = "1"
	for code: String in [f.a, f.b]:
		for arm: String in arms:
			f.state.army_roster[code][arm] = "0"
		f.state.army_roster[code][mounted if code == f.a else foot] = "600"
	f.repo.balance["battle_context_arm_threshold_permille"] = 400
	_issue(f, "foot", "advance", f.b)
	_receive(f, "foot")
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def").kind, "melee",
		"holding mounted personnel do not contribute to an attack context")
	_issue(f, "mounted", "advance", f.a)
	_receive(f, "mounted")
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def").kind, "shock",
		"600 of 1200 now attack mounted: 500 per mille exceeds 400")

func test_successful_task_attack_commits_reserve_after_failed_round_retry() -> void:
	var f := _fixture()
	_issue(f, "advance", "advance")
	_receive(f, "advance")
	f.battle["reserves"] = {f.a: {"reason": "Awaiting commitment"}}
	for tier: Dictionary in f.repo.battle_outcomes:
		tier.attacker_loss_permille = 10
		tier.defender_loss_permille = 10
		tier.rout = "none"
	var cohort := String(f.state.military_rosters[f.enemy].cohort_ids[0])
	var origin := String(f.state.military_cohorts[cohort].source_population_field)
	f.state.military_cohorts[cohort].source_population_field = "invalid"
	var events: Array = []
	assert_true(BattleSystem._fight(f.repo, f.state, f.battle, events).has("error"))
	assert_true(f.battle.reserves.has(f.a), "failed rounds do not commit reserves")
	f.state.military_cohorts[cohort].source_population_field = origin
	BattleSystem._fight(f.repo, f.state, f.battle, events)
	assert_false(f.battle.reserves.has(f.a), "an actual attack commits this reserve")
	_issue(f, "cancel", "cancel")
	_receive(f, "cancel")
	f.battle.actions.att.kind = "attack"
	assert_gt(BattleSystem.side_power(f.repo, f.state, [f.a], Callable(), true), 0,
		"cancelling the task cannot return a committed unit to reserve")

func test_pursuit_waits_for_receipt_and_a_withdrawing_enemy() -> void:
	var f := _fixture()
	_issue(f, "pursue", "pursue")
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "hold")
	_receive(f, "pursue")
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "hold")
	f.state.foes[f.enemy].battle_retreat = true
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "attack")
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.b).kind, "hold")
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def").kind, "pursuit")
	f.state.regiments[f.a].supplies = 0
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def").kind, "withdrawal")

func test_pursuit_live_terms_control_and_cancellation_stop_authorization() -> void:
	var f := _fixture()
	_issue(f, "pursue", "pursue")
	_receive(f, "pursue")
	f.state.foes[f.enemy].battle_retreat = true
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def").kind, "pursuit")
	f.state.law_in_force["unit:" + f.a] = {"battle_tactics": {"value": "restrained", "decree_id": 100}}
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def").kind, "withdrawal")
	f.state.law_in_force.erase("unit:" + f.a)
	f.battle["parley"] = {"agreed": {"safe_withdrawal": {"policy": "protect"}}}
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def").loss_permille, 0)
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "hold")
	f.battle.erase("parley")
	_issue(f, "cancel-pursue", "cancel")
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def").kind, "pursuit")
	_receive(f, "cancel-pursue")
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def").kind, "withdrawal")

func test_designated_pursuit_does_not_chase_another_withdrawing_enemy() -> void:
	var f := _fixture()
	var second := "pursuit_other"
	f.state.foes[second] = f.state.foes[f.enemy].duplicate(true)
	f.state.military_rosters[second] = f.state.military_rosters[f.enemy].duplicate(true)
	f.battle.def.append(second)
	var sent := BattleTaskSystem.issue_task(f.repo, f.state, {"id": "target-pursue", "unit": f.a,
		"battle_id": 9443, "task": "pursue", "target_unit": f.enemy})
	assert_eq(sent.status, "pending")
	_receive(f, "target-pursue")
	f.state.foes[second].battle_retreat = true
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "hold")
	f.state.foes[f.enemy].battle_retreat = true
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def", f.enemy).kind, "pursuit")
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def", second).kind, "withdrawal")
	f.state.foes[f.enemy].captured = true
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "hold")

func test_pursuit_round_uses_existing_attack_cost_and_json_replay() -> void:
	var f := _fixture()
	_issue(f, "pursue", "pursue")
	_receive(f, "pursue")
	var at := BattleSystem._at_m(f.repo, f.state, f.a)
	preload("res://tests/invasion_play.gd").place(f.repo, f.state, f.enemy, at, ArmySystem.ORDER_STANDBY)
	f.battle.actions.def.kind = "retreat"
	var reg := ArmySystem.regiment(f.repo, f.a, f.state)
	var bite := ArmySystem.day_bite(ArmySystem.supply_use(f.repo, reg, f.state), f.state.day)
	var food := int(f.state.regiments[f.a].supplies)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	var events: Array = []
	var replay: Array = []
	BattleSystem._fight(f.repo, f.state, f.battle, events)
	BattleSystem._fight(f.repo, restored, BattleSystem.battle_by_id(restored, 9443), replay)
	events = events.filter(func(event: Dictionary) -> bool: return event.kind == "round")
	assert_eq(events.size(), 1)
	if events.is_empty(): return
	assert_eq(events[0].contexts.def.kind, "pursuit")
	assert_eq(events[0].costs.size(), 1)
	assert_eq(int(f.state.regiments[f.a].supplies), food - BattleSystem._attack_supply(f.repo, bite))
	assert_eq(SaveLoad.state_hash(restored), SaveLoad.state_hash(f.state))

func test_targeted_pursuit_freezes_distinct_loss_rates_and_costs_after_failed_commit() -> void:
	var f := _fixture()
	f.battle.att = [f.a]
	f.battle.def = [f.enemy, f.b]
	var at := BattleSystem._at_m(f.repo, f.state, f.a)
	for code: String in f.battle.def:
		preload("res://tests/invasion_play.gd").place(f.repo, f.state, code, at, ArmySystem.ORDER_STANDBY)
	var sent := BattleTaskSystem.issue_task(f.repo, f.state, {"id": "pursue-one", "unit": f.a,
		"battle_id": 9443, "task": "pursue", "target_unit": f.enemy})
	assert_eq(sent.status, "pending")
	_receive(f, "pursue-one")
	f.battle.actions.def.kind = "retreat"
	for tier: Dictionary in f.repo.battle_outcomes:
		tier.attacker_loss_permille = 100
		tier.defender_loss_permille = 100
		tier.rout = "none"
	var cohort := String(f.state.military_rosters[f.enemy].cohort_ids[0])
	var origin := String(f.state.military_cohorts[cohort].source_population_field)
	f.state.military_cohorts[cohort].source_population_field = "invalid"
	var events: Array = []
	assert_true(BattleSystem._fight(f.repo, f.state, f.battle, events).has("error"))
	var pending: Dictionary = f.battle.pending_round.duplicate(true)
	assert_eq(int(pending.tier.unit_loss_permille[f.enemy]), 150, "100 * 1500 / 1000: designated pursued enemy")
	assert_eq(int(pending.tier.unit_loss_permille[f.b]), 60, "100 * 600 / 1000: other withdrawal")
	assert_eq(pending.unit_actions[f.a].pursuit_target, f.enemy)
	var food := int(f.state.regiments[f.a].supplies)
	var draw: Dictionary = f.state.rng.to_dict()
	_issue(f, "cancel-frozen-pursuit", "cancel")
	_receive(f, "cancel-frozen-pursuit")
	assert_true(BattleSystem._fight(f.repo, f.state, f.battle, events).has("error"))
	assert_eq(f.battle.pending_round, pending)
	assert_eq(int(f.state.regiments[f.a].supplies), food)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	f.state.military_cohorts[cohort].source_population_field = origin
	restored.military_cohorts[cohort].source_population_field = origin
	var replay: Array = []
	BattleSystem._fight(f.repo, restored, BattleSystem.battle_by_id(restored, 9443), replay)
	BattleSystem._fight(f.repo, f.state, f.battle, events)
	assert_eq(SaveLoad.state_hash(restored), SaveLoad.state_hash(f.state))
	assert_eq(f.state.rng.to_dict(), draw)
	assert_eq(int(f.state.regiments[f.a].supplies), food - int(pending.costs[0].supplies))
	assert_false(f.battle.has("pending_round"))
