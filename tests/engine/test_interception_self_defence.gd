extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const Play := preload("res://tests/invasion_play.gd")
const BASE := Vector2i(10000, 10000)

func _fixture() -> Dictionary:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	repo.balance["battle_line_gap_m"] = 0
	repo.balance["battle_deploy_step_m"] = 50
	for tier: Dictionary in repo.battle_outcomes:
		tier.attacker_loss_permille = 0
		tier.defender_loss_permille = 0
		tier.attacker_morale = 0
		tier.defender_morale = 0
		tier.rout = "none"
	var state := SuiteData.campaign(repo, 9478)
	state.day = 10
	state.ai_hosts.clear()
	var codes := state.regiments.keys()
	codes.sort()
	var a := ""
	for code: String in codes:
		if MapObjects.regiment_arm(repo, ArmySystem.regiment(repo, code, state)) == "infantry":
			a = code
			break
	var enemies := state.foes.keys()
	enemies.sort()
	assert_gte(enemies.size(), 2)
	var target := String(enemies[0])
	var interceptor := String(enemies[1])
	for code: String in [a, target, interceptor]:
		assert_false(Personnel.replace(repo, state, code, 50).has("error"))
		Play.place(repo, state, code, BASE, ArmySystem.ORDER_STANDBY)
		var entry := BattleSystem._stored(state, code)
		entry["supplies"] = 100000
		entry["morale"] = 100
		entry["stance"] = "hold"
	Play.place(repo, state, target, BASE + Vector2i(1000, 0), ArmySystem.ORDER_STANDBY)
	Play.place(repo, state, interceptor, BASE + Vector2i(0, -50), ArmySystem.ORDER_STANDBY)
	state.foes[target]["facing_deg"] = 180
	var battle := {"id": 9478, "att": [a], "def": [target, interceptor], "rounds": 0, "town": "",
		"place_x_m": BASE.x + 1000, "place_y_m": BASE.y,
		"actions": {"att": {"kind": "attack"}, "def": {"kind": "attack"}}}
	state.battles = [battle]
	BattleFormation.ensure(battle)
	var raw := {"id": "flank", "unit": a, "battle_id": 9478, "task": "flank", "target_unit": target}
	assert_eq(BattleTaskSystem.issue_task(repo, state, raw).get("status"), "pending")
	assert_eq(CourierSystem._deliver_one(repo, state, {"target": a},
		{"action_code": "BATTLE_TASK", "unit_task_id": "flank"}).type, "delivered")
	BattleGroups.refresh(repo, state, battle)
	return {"repo": repo, "state": state, "a": a, "target": target, "interceptor": interceptor, "battle": battle}

func test_interceptor_holds_real_flank_then_clearing_resumes_original_approach() -> void:
	var f := _fixture()
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "hold")
	var engine := TickEngine.new(f.repo)
	assert_eq(Play.day(engine, f.state, true).status, "complete")
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), BASE, "50 m contact pauses the 50 m daily approach")
	var task := BattleTaskSystem.current(f.state, f.a)
	assert_eq(task.request.target_unit, f.target)
	assert_eq(task.status, "received")
	assert_true(task.get("obstruction", {}).get("active", false))
	assert_eq(task.get("obstruction", {}).get("units", []), [f.interceptor])
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	for state: GameState in [f.state, restored]:
		var b := BattleSystem.battle_by_id(state, 9478)
		BattleGroups.translate(f.repo, state, b, f.interceptor,
			Vector2i(BASE.x, BASE.y - 5000) - BattleSystem._at_m(f.repo, state, f.interceptor))
		BattleGroups.refresh(f.repo, state, b)
		assert_eq(Play.day(TickEngine.new(f.repo), state, true).status, "complete")
		assert_eq(BattleSystem._at_m(f.repo, state, f.a), BASE + Vector2i(0, -50), "resume first known side leg; never aim at the interceptor")
		var resumed := BattleTaskSystem.current(state, f.a)
		assert_eq(resumed.request.target_unit, f.target)
		assert_false(resumed.get("obstruction", {}).get("active", true))
	assert_eq(SaveLoad.state_hash(f.state), SaveLoad.state_hash(restored))

func test_new_battle_does_not_replace_flank_with_side_attack_or_deployment() -> void:
	var f := _fixture()
	f.battle.id = 9479
	f.battle.def = [f.interceptor]
	BattleGroups.refresh(f.repo, f.state, f.battle)
	var action := BattleSystem.unit_action(f.repo, f.state, f.battle, f.a)
	assert_eq(action.kind, "hold", "an interception battlefield cannot inherit its side attack")
	assert_eq(action.task_id, "flank")
	assert_false(action.has("pursuit_target"))
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), BASE)
	assert_eq(BattleTaskSystem.current(f.state, f.a).request.target_unit, f.target)

func test_search_exhaustion_cancellation_and_withdrawal_never_resume_old_flank() -> void:
	var f := _fixture()
	f.state.unit_tasks[f.a].orders.flank.status = "search_failed"
	f.state.unit_tasks[f.a].orders.flank.reason = "The finite search found nothing"
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "hold")
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), BASE)
	f.state.battles.clear()
	f.state.day += 1
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_ne(f.state.regiments[f.a].order, ArmySystem.ORDER_MARCH)
	assert_eq(BattleTaskSystem.current(f.state, f.a).status, "search_failed")
	f.state.battles = [f.battle]
	f.state.unit_tasks[f.a].orders.flank.status = "received"
	f.state.regiments[f.a]["battle_retreat"] = true
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "retreat")
	f.state.regiments[f.a].erase("battle_retreat")
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, {"id": "cancel", "unit": f.a,
		"battle_id": 9478, "task": "cancel"}).status, "pending")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "cancel").status, "received")
	f.state.battles.clear()
	f.state.day += 1
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_eq(BattleTaskSystem.current(f.state, f.a), {})
	assert_ne(f.state.regiments[f.a].order, ArmySystem.ORDER_MARCH)

func test_only_actual_contact_obstructs_and_withdrawing_interceptor_grants_no_pursuit() -> void:
	var f := _fixture()
	for offset: int in [101, 100]:
		BattleGroups.translate(f.repo, f.state, f.battle, f.interceptor,
			BASE + Vector2i(0, -offset) - BattleSystem._at_m(f.repo, f.state, f.interceptor))
		BattleGroups.refresh(f.repo, f.state, f.battle)
		var before: Dictionary = f.state.to_dict()
		assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.a).kind, "hold" if offset == 100 else "attack")
		assert_eq(f.state.to_dict(), before, "contact/action queries never write receipts or RNG")
	f.state.foes[f.interceptor]["battle_retreat"] = true
	var action := BattleSystem.unit_action(f.repo, f.state, f.battle, f.a)
	assert_eq(action.kind, "attack", "original flank may continue when interceptor withdraws")
	assert_false(action.has("pursuit_target"))
	assert_eq(BattleSystem.combat_context(f.repo, f.state, f.battle, "def", f.interceptor).kind, "withdrawal")

func test_failed_personnel_round_freezes_self_defence_through_clearance_and_json_retry() -> void:
	var f := _fixture()
	for tier: Dictionary in f.repo.battle_outcomes:
		tier.attacker_loss_permille = 1000
		tier.defender_loss_permille = 1000
	var cohort := ""
	for id: String in f.state.military_rosters[f.interceptor].cohort_ids:
		if int(f.state.military_cohorts[id].fit) > 0:
			cohort = id
			break
	var origin := String(f.state.military_cohorts[cohort].source_population_field)
	f.state.military_cohorts[cohort].source_population_field = "invalid"
	var events: Array = []
	assert_true(BattleSystem._fight(f.repo, f.state, f.battle, events).has("error"))
	var pending: Dictionary = f.battle.pending_round.duplicate(true)
	var task := BattleTaskSystem.current(f.state, f.a)
	var draw: Dictionary = f.state.rng.to_dict()
	assert_eq(pending.unit_actions[f.a].kind, "hold")
	assert_true(task.get("obstruction", {}).get("active", false))
	f.state.foes[f.interceptor].y_m -= 5000
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_true(BattleSystem._fight(f.repo, f.state, f.battle, events).has("error"))
	assert_eq(f.battle.pending_round, pending)
	assert_eq(BattleTaskSystem.current(f.state, f.a), task)
	assert_eq(f.state.rng.to_dict(), draw)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	for state: GameState in [f.state, restored]:
		state.military_cohorts[cohort].source_population_field = origin
		assert_false(BattleSystem._fight(f.repo, state, BattleSystem.battle_by_id(state, 9478), []).has("error"))
	assert_eq(SaveLoad.state_hash(f.state), SaveLoad.state_hash(restored))
	assert_eq(f.state.rng.to_dict(), draw)

func test_real_field_encounter_pauses_task_and_keeps_known_target_geometry() -> void:
	var f := _fixture()
	f.state.foes[f.target].x_m = BASE.x + 8000
	f.state.battles.clear()
	BattleTaskSystem.track_day(f.repo, f.state)
	var known: Dictionary = BattleTaskSystem.current(f.state, f.a).flank.known.duplicate(true)
	BattleSystem.detect_contacts(f.repo, f.state)
	var encounter := BattleSystem.battle_of(f.state, f.a)
	assert_false(encounter.is_empty())
	assert_ne(int(encounter.get("id", -1)), 9478)
	assert_eq(BattleSystem.unit_action(f.repo, f.state, encounter, f.a).kind, "hold")
	assert_eq(Play.day(TickEngine.new(f.repo), f.state, true).status, "complete")
	var task := BattleTaskSystem.current(f.state, f.a)
	assert_true(task.get("obstruction", {}).get("active", false))
	assert_eq(task.request.target_unit, f.target)
	assert_eq(task.flank.known, known, "interception cannot use other columns' knowledge to rewrite the route")
	var replay := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	for state: GameState in [f.state, replay]:
		var before: Dictionary = state.unit_tasks.duplicate(true)
		CourierSystem._deliver_one(f.repo, state, {"target": f.a}, {"action_code": "BATTLE_TASK", "unit_task_id": "flank"})
		assert_eq(state.unit_tasks, before, "redelivery cannot clear the obstruction or replace the target")
		var b := BattleSystem.battle_of(state, f.a)
		var opponent := "att" if BattleRules.side_of(b, f.a) == "def" else "def"
		b.actions[opponent] = {"kind": "retreat"}
		Play.place(f.repo, state, f.interceptor, BASE + Vector2i(0, -10000), ArmySystem.ORDER_STANDBY)
		BattleSystem._stored(state, f.interceptor)["battle_retreat"] = true
		assert_eq(Play.day(TickEngine.new(f.repo), state, true).status, "complete")
		assert_true(BattleSystem.battle_of(state, f.a).is_empty(), "actual separation ends the interception")
		assert_eq(Play.day(TickEngine.new(f.repo), state, true).status, "complete")
		assert_false(BattleTaskSystem.current(state, f.a).get("obstruction", {}).get("active", true))
		assert_eq(BattleTaskSystem.current(state, f.a).request.target_unit, f.target)
	assert_eq(SaveLoad.state_hash(f.state), SaveLoad.state_hash(replay))

func test_delivered_replacement_owns_the_unit_after_interception_clears() -> void:
	var f := _fixture()
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_true(BattleTaskSystem.current(f.state, f.a).get("obstruction", {}).get("active", false))
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, {"id": "defend", "unit": f.a,
		"battle_id": 9478, "task": "defend"}).status, "pending")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "defend").status, "received")
	f.state.foes[f.interceptor].y_m -= 5000
	f.state.battles.clear()
	f.state.day += 1
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_eq(BattleTaskSystem.current(f.state, f.a).request.id, "defend")
	assert_eq(f.state.unit_tasks[f.a].orders.flank.status, "replaced")
	assert_ne(f.state.regiments[f.a].order, ArmySystem.ORDER_MARCH)
