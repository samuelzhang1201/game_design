extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const Play := preload("res://tests/invasion_play.gd")
const BASE := Vector2i(10000, 10000)

func _fixture() -> Dictionary:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	repo.balance["battle_line_gap_m"] = 0
	var state := SuiteData.campaign(repo, 9477)
	state.day = 10
	state.ai_hosts.clear()
	var codes := state.regiments.keys()
	codes.sort()
	var a := ""
	for code: String in codes:
		if MapObjects.regiment_arm(repo, ArmySystem.regiment(repo, code, state)) == "infantry":
			a = code
			break
	assert_ne(a, "")
	var enemy := String(state.foes.keys()[0])
	Play.place(repo, state, a, BASE, ArmySystem.ORDER_STANDBY)
	Play.place(repo, state, enemy, BASE + Vector2i(1000, 0), ArmySystem.ORDER_STANDBY)
	for code: String in [a, enemy]:
		assert_false(Personnel.replace(repo, state, code, 50).has("error"))
		BattleSystem._stored(state, code)["supplies"] = 100000
		BattleSystem._stored(state, code)["morale"] = 100
		BattleSystem._stored(state, code)["stance"] = "hold"
	state.foes[enemy]["facing_deg"] = 180
	var battle := {"id": 9477, "att": [a], "def": [enemy], "rounds": 0, "town": "",
		"place_x_m": BASE.x + 1000, "place_y_m": BASE.y,
		"actions": {"att": {"kind": "hold"}, "def": {"kind": "hold"}}}
	state.battles = [battle]
	BattleFormation.ensure(battle)
	var raw := {"id": "flank", "unit": a, "battle_id": 9477, "task": "flank", "target_unit": enemy}
	assert_eq(BattleTaskSystem.issue_task(repo, state, raw).get("status"), "pending")
	return {"repo": repo, "state": state, "a": a, "enemy": enemy, "battle": battle}

func test_received_flank_walks_to_side_and_turning_removes_actual_benefit() -> void:
	var f := _fixture()
	f.repo.balance["battle_deploy_step_m"] = 50
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a).y, BASE.y, "pending task retains ordinary deployment")
	Play.place(f.repo, f.state, f.a, BASE, ArmySystem.ORDER_STANDBY)
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "flank").status, "received")
	for day: int in range(11, 36):
		f.state.tick = 1 + (day - 1) / 30
		f.state.day = 1 + (day - 1) % 30
		var from := BattleSystem._at_m(f.repo, f.state, f.a)
		BattleGroups.deploy_day(f.repo, f.state, f.battle)
		var to := BattleSystem._at_m(f.repo, f.state, f.a)
		assert_lte(from.distance_squared_to(to), 2500, "at most 50 real metres per day")
		assert_ne(to, BASE + Vector2i(1000, 0), "never the target centre")
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), BASE + Vector2i(1000, -100), "east-facing transverse vector tie chooses first reachable side")
	assert_true(BattleFormation.context(f.repo, f.state, f.battle, "def", f.enemy).flanked)
	var factors: Array = BattleFormation.effects(f.repo, f.state, f.battle, "def", false, f.enemy).factors
	var flanks := factors.filter(func(factor: Dictionary) -> bool: return factor.source == "formation:flank")
	assert_eq(flanks.size(), 1, "one existing factor, independent of approach days")
	if not flanks.is_empty():
		assert_eq(int(flanks[0].permille), 850, "compact rank's one 150-per-mille exposure penalty")
	f.state.foes[f.enemy]["facing_deg"] = 270
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_false(BattleFormation.context(f.repo, f.state, f.battle, "def", f.enemy).flanked, "same contact now lies directly ahead")
	var at := BattleSystem._at_m(f.repo, f.state, f.a)
	f.state.day += 1
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), at, "contact commits the approach; no automatic circling")
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, {"id": "again", "unit": f.a, "battle_id": 9477,
		"task": "flank", "target_unit": f.enemy}).status, "pending")
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "again").status, "received")
	f.state.day += 1
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), at, "synonymous receipt preserves committed contact")
	assert_false(BattleFormation.context(f.repo, f.state, f.battle, "def", f.enemy).flanked)
	f.state.battles.clear()
	f.state.foes[f.enemy].y_m += 1000
	f.state.day += 1
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_ne(f.state.regiments[f.a].order, ArmySystem.ORDER_MARCH, "leaving battle cannot revive the committed approach")

func test_distant_opponents_never_grant_flank_and_real_side_contact_does() -> void:
	var f := _fixture()
	f.state.foes[f.enemy]["facing_deg"] = 0
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_false(BattleFormation.context(f.repo, f.state, f.battle, "def", f.enemy).flanked)
	BattleGroups.translate(f.repo, f.state, f.battle, f.a,
		BASE + Vector2i(1000, -100) - BattleSystem._at_m(f.repo, f.state, f.a))
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_true(BattleFormation.context(f.repo, f.state, f.battle, "def", f.enemy).flanked)

func test_hand_derived_route_chooses_reachable_side_and_rejects_severed_ground() -> void:
	var repo := SuiteData.repo()
	repo.balance["army_march_grid_px"] = 1
	var slopes := PackedByteArray()
	slopes.resize(20 * 20)
	slopes.fill(0)
	# Target (1000,1000), facing west: first side is north (1000,900).
	# Block that endpoint. South is reachable by two 100+500 metre legs.
	slopes[9 * 20 + 10] = MarchPath.WATER
	MarchPath.use(repo, MarchPath.build(repo, 20, 20, 100, slopes))
	var known := {"x_m": 1000, "y_m": 1000, "radius_m": 0, "facing_deg": 180}
	var path := BattleTaskSystem.flank_route(repo, Vector2i(500, 1000), known)
	assert_false(path.is_empty())
	if not path.is_empty():
		assert_eq(path.back(), Vector2i(1000, 1100))
		assert_eq(int(MarchRoute.length_from(Vector2i(500, 1000), path)), 600)
	# Neither side is on the recipient's connected land component.
	for y: int in 20:
		slopes[y * 20 + 7] = MarchPath.WATER
	MarchPath.use(repo, MarchPath.build(repo, 20, 20, 100, slopes))
	assert_eq(BattleTaskSystem.flank_route(repo, Vector2i(500, 1000), known), [])
	MarchPath.forget()

func test_unseen_position_and_facing_cannot_change_known_route_or_search() -> void:
	var f := _fixture()
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "flank").status, "received")
	f.state.battles.clear()
	BattleTaskSystem.track_day(f.repo, f.state)
	var first := BattleTaskSystem.current(f.state, f.a)
	assert_eq(int(first.flank.known.facing_deg), 180)
	assert_eq(int(f.state.regiments[f.a].dest_y_m), BASE.y - 100)
	f.state.foes[f.enemy].x_m = BASE.x + 50000
	f.state.foes[f.enemy].facing_deg = 0
	f.state.day += 1
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	restored.foes[f.enemy].x_m = BASE.x + 90000
	restored.foes[f.enemy].facing_deg = 90
	BattleTaskSystem.track_day(f.repo, f.state)
	BattleTaskSystem.track_day(f.repo, restored)
	assert_eq(BattleTaskSystem.current(f.state, f.a), BattleTaskSystem.current(restored, f.a))
	assert_eq(f.state.regiments[f.a], restored.regiments[f.a])
	assert_eq(BattleTaskSystem.current(f.state, f.a).flank.known, first.flank.known)
	var task := BattleTaskSystem.current(f.state, f.a)
	var last: Array = task.flank.path_m.back()
	Play.place(f.repo, f.state, f.a, Vector2i(int(last[0]), int(last[1])), ArmySystem.ORDER_GARRISON)
	# Simulate having walked every saved corner; search starts at the side point.
	f.state.unit_tasks[f.a].orders.flank.flank.path_m = []
	f.state.day += 1
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_eq(BattleTaskSystem.current(f.state, f.a).track.phase, "search")
	f.state.day += int(f.repo.bal("battle_search_days")) + 1
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_eq(BattleTaskSystem.current(f.state, f.a).status, "search_failed")

func test_actual_day_delivery_json_and_retry_preserve_integer_approach() -> void:
	var f := _fixture()
	f.repo.balance["battle_deploy_step_m"] = 50
	for tier: Dictionary in f.repo.battle_outcomes:
		tier.attacker_loss_permille = 0
		tier.defender_loss_permille = 0
		tier.attacker_morale = 0
		tier.defender_morale = 0
		tier.rout = "none"
	var courier := {"target": f.a}
	var order := {"action_code": "BATTLE_TASK", "unit_task_id": "flank"}
	assert_eq(CourierSystem._deliver_one(f.repo, f.state, courier, order).type, "delivered")
	var received: Dictionary = f.state.unit_tasks.duplicate(true)
	CourierSystem._deliver_one(f.repo, f.state, courier, order)
	assert_eq(f.state.unit_tasks, received)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	var engine := TickEngine.new(f.repo)
	var replay := TickEngine.new(f.repo)
	assert_ne(Play.day(engine, f.state, true).status, "error")
	assert_ne(Play.day(replay, restored, true).status, "error")
	assert_eq(SaveLoad.state_hash(f.state), SaveLoad.state_hash(restored))
	var floats: Array = []
	Play.floats_in(BattleTaskSystem.current(restored, f.a).flank, "flank", floats)
	assert_eq(floats, [], "saved approach contains whole geometry and path coordinates")
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), BASE + Vector2i(0, -50))
	var before: Dictionary = f.state.to_dict()
	var battle := BattleSystem.battle_by_id(f.state, 9477)
	BattleGroups.deploy_day(f.repo, f.state, battle)
	# DayResolution publishes a candidate; always use its current battle object.
	var after: Dictionary = f.state.to_dict()
	BattleGroups.deploy_day(f.repo, f.state, battle)
	assert_eq(f.state.to_dict(), after)
	assert_ne(before, after)

func test_deep_wedge_approach_ends_at_actual_side_group_contact() -> void:
	var f := _fixture()
	assert_false(Personnel.replace(f.repo, f.state, f.enemy, 800).has("error"))
	f.battle.formations.def.current = "wedge"
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "flank").status, "received")
	for day: int in range(11, 21):
		f.state.day = day
		BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_gt(BattleGroups.engaged_counts(f.repo, f.state, f.battle, f.a, f.enemy).x, 0)
	assert_true(BattleFormation.context(f.repo, f.state, f.battle, "def", f.enemy).flanked)

func test_failed_round_keeps_contact_factors_through_turn_and_json_retry() -> void:
	var f := _fixture()
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "flank").status, "received")
	BattleGroups.translate(f.repo, f.state, f.battle, f.a,
		BASE + Vector2i(1000, -100) - BattleSystem._at_m(f.repo, f.state, f.a))
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_true(BattleFormation.context(f.repo, f.state, f.battle, "def", f.enemy).flanked)
	for tier: Dictionary in f.repo.battle_outcomes:
		tier.attacker_loss_permille = 1000
		tier.defender_loss_permille = 1000
		tier.rout = "none"
	var cohort := ""
	for id: String in f.state.military_rosters[f.enemy].cohort_ids:
		if int(f.state.military_cohorts[id].fit) > 0:
			cohort = id
			break
	assert_ne(cohort, "")
	var origin := String(f.state.military_cohorts[cohort].source_population_field)
	f.state.military_cohorts[cohort].source_population_field = "invalid"
	var events: Array = []
	assert_true(BattleSystem._fight(f.repo, f.state, f.battle, events).has("error"))
	var pending: Dictionary = f.battle.pending_round.duplicate(true)
	var draw: Dictionary = f.state.rng.to_dict()
	f.state.foes[f.enemy].facing_deg = 270
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_true(BattleSystem._fight(f.repo, f.state, f.battle, events).has("error"))
	assert_eq(f.battle.pending_round, pending, "turn cannot rewrite an uncommitted earlier round")
	assert_eq(f.state.rng.to_dict(), draw)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	f.state.military_cohorts[cohort].source_population_field = origin
	restored.military_cohorts[cohort].source_population_field = origin
	var replay: Array = []
	BattleSystem._fight(f.repo, f.state, f.battle, events)
	BattleSystem._fight(f.repo, restored, BattleSystem.battle_by_id(restored, 9477), replay)
	assert_eq(SaveLoad.state_hash(f.state), SaveLoad.state_hash(restored))
	assert_eq(f.state.rng.to_dict(), draw)

func test_visible_wounded_only_target_ends_flank_without_routing_empty_groups() -> void:
	var f := _fixture()
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "flank").status, "received")
	f.state.battles.clear()
	assert_false(Personnel.move(f.repo, f.state, f.enemy, "fit", "wounded", 50).has("error"))
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_eq(BattleTaskSystem.current(f.state, f.a).status, "completed")
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), BASE)
	assert_ne(f.state.regiments[f.a].order, ArmySystem.ORDER_MARCH)

func test_visible_moving_column_facing_comes_from_observed_displacement() -> void:
	var f := _fixture()
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "flank").status, "received")
	f.state.battles.clear()
	f.state.foes[f.enemy].erase("facing_deg")
	BattleTaskSystem.track_day(f.repo, f.state)
	f.state.foes[f.enemy].y_m += 500
	f.state.day += 1
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_eq(int(BattleTaskSystem.current(f.state, f.a).flank.known.facing_deg), 90)

func test_old_battle_task_cannot_turn_groups_in_a_new_battle() -> void:
	var f := _fixture()
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "flank").status, "received")
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	f.state.day += 1
	BattleGroups.deploy_day(f.repo, f.state, f.battle)
	assert_eq(BattleTaskSystem.current(f.state, f.a).flank.phase, "contact")
	f.battle.id = 9478
	f.state.regiments[f.a].facing_deg = 180
	BattleGroups.refresh(f.repo, f.state, f.battle)
	assert_eq(int(f.battle.group_facing[f.a]), 180)
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, {"id": "new-battle", "unit": f.a,
		"battle_id": 9478, "task": "flank", "target_unit": f.enemy}).status, "pending")
	var received := BattleTaskSystem.deliver_task(f.repo, f.state, "new-battle")
	assert_eq(received.status, "received")
	assert_ne(received.get("flank", {}).get("phase", ""), "contact", "old battlefield contact cannot latch a fresh battlefield receipt")

func test_field_side_route_uses_saved_substep_budget_and_json_continuity() -> void:
	var f := _fixture()
	f.state.foes[f.enemy].x_m = BASE.x + 8000
	assert_eq(CourierSystem._deliver_one(f.repo, f.state, {"target": f.a},
		{"action_code": "BATTLE_TASK", "unit_task_id": "flank"}).type, "delivered")
	f.state.battles.clear()
	f.state.regiments[f.a].erase("camp_state")
	f.state.regiments[f.a].erase("departure")
	BattleTaskSystem.track_day(f.repo, f.state)
	assert_eq(int(f.state.regiments[f.a].dest_x_m), BASE.x)
	assert_eq(int(f.state.regiments[f.a].dest_y_m), BASE.y - 100)
	f.state.day_resolution = DayResolution.begin(f.state.day, false, f.state.absolute_day(), 4)
	f.state.day_resolution["march_entries"] = {f.a: f.state.regiments[f.a].duplicate(true)}
	f.state.day_resolution["march_budgets"] = {f.a: 80}
	ArmySystem.march_day_saved(f.repo, f.state, 4, 0, f.state.day_resolution.march_entries, f.state.day_resolution.march_budgets)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.a), BASE + Vector2i(0, -20), "80 / 4 = 20 m, across the front first")
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	for state: GameState in [f.state, restored]:
		ArmySystem.march_day_saved(f.repo, state, 4, 1, state.day_resolution.march_entries, state.day_resolution.march_budgets)
		assert_eq(BattleSystem._at_m(f.repo, state, f.a), BASE + Vector2i(0, -40))
	assert_eq(SaveLoad.state_hash(f.state), SaveLoad.state_hash(restored))

func test_flank_interrupts_unfinished_charge_but_preserves_regroup_obligation() -> void:
	for phase: String in ["approach", "impact"]:
		var f := _fixture()
		assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, "flank").status, "received")
		var entry: Dictionary = f.state.regiments[f.a]
		entry["charge"] = {"phase": phase, "runup_m": 600}
		BattleGroups.deploy_day(f.repo, f.state, f.battle)
		if phase == "approach":
			assert_false(entry.has("charge"), "interrupted run-up is not banked through a flank task")
		else:
			assert_eq(entry.charge.phase, "disengage", "an impact still owes actual disengagement and regrouping")
