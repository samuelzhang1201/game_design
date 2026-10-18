extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func _fixture() -> Dictionary:
	var repo := SuiteData.repo()
	SuiteData.open_country(repo)
	var state := SuiteData.campaign(repo, 551)
	var codes: Array = state.regiments.keys()
	codes.sort()
	var code := String(codes[0])
	var extra := String(codes[1])
	for unit: String in [code, extra]:
		for id: String in state.military_rosters[unit].cohort_ids:
			state.military_cohorts.erase(id)
		state.military_rosters[unit] = {"commander_id": "", "cohort_ids": [unit + ":common", unit + ":noble"]}
		for identity: String in ["common", "noble"]:
			var count := (540 if identity == "common" else 60) if unit == code else (90 if identity == "common" else 10)
			var id := unit + ":" + identity
			state.military_cohorts[id] = {"id": id, "unit_code": unit, "stage": "active",
				"source_province": state.army_roster[unit].province_code,
				"source_population_field": "rural_population", "family_name": "",
				"identity": "commoner" if identity == "common" else "noble", "initial": count,
				"fit": count, "wounded": 0, "dead": 0, "captured_current": 0, "released": 0}
	var enemy := String(state.foes.keys()[0])
	var battle := {"id": 5551, "att": [code], "def": [enemy], "rounds": 0,
		"start_day": state.absolute_day(), "place_x_m": 0, "place_y_m": 0, "town": ""}
	state.battles.append(battle)
	return {"repo": repo, "state": state, "code": code, "extra": extra, "enemy": enemy, "battle": battle}

func test_600_and_700_unique_participants_and_wounded_captives() -> void:
	var report: GDScript = load("res://scripts/engine/battle_report.gd")
	assert_not_null(report)
	if report == null:
		return
	var f := _fixture()
	report.enroll(f.state, f.battle, f.code, "att")
	var id := String(f.code) + ":common"
	assert_false(MilitaryRoster.transition(f.repo, f.state, "600-losses", [
		{"cohort_id": id, "from": "fit", "to": "wounded", "count": 78},
		{"cohort_id": id, "from": "fit", "to": "dead", "count": 35},
		{"cohort_id": String(f.code) + ":noble", "from": "fit", "to": "wounded", "count": 12},
		{"cohort_id": String(f.code) + ":noble", "from": "fit", "to": "dead", "count": 5}], "Authored conservation example").has("error"))
	var prisoners: GDScript = load("res://scripts/engine/prisoner_system.gd")
	assert_false(prisoners.capture(f.repo, f.state, {"capture_id": "example-60", "battle_id": 5551,
		"round": 1, "participants": {f.enemy: 1}, "reason": "Sixty intercepted survivors",
		"changes": [{"cohort_id": id, "from": "fit", "to": "captured_current", "count": 37},
			{"cohort_id": id, "from": "wounded", "to": "captured_current", "count": 18},
			{"cohort_id": String(f.code) + ":noble", "from": "fit", "to": "captured_current", "count": 3},
			{"cohort_id": String(f.code) + ":noble", "from": "wounded", "to": "captured_current", "count": 2}]}).has("error"))
	var totals: Dictionary = report.tally(f.state, f.battle)["att"]
	assert_eq(totals, {"participants": 600, "fit": 430, "wounded": 70, "dead": 40, "captured": 60, "released": 0})
	assert_eq(report.tally(f.state, f.battle, "commoner").att, {"participants": 540, "fit": 390, "wounded": 60, "dead": 35, "captured": 55, "released": 0})
	assert_eq(report.tally(f.state, f.battle, "noble").att, {"participants": 60, "fit": 40, "wounded": 10, "dead": 5, "captured": 5, "released": 0})
	report.enroll(f.state, f.battle, f.extra, "att")
	report.enroll(f.state, f.battle, f.extra, "att")
	var second: Dictionary = report.tally(f.state, f.battle)["att"]
	assert_eq(second.participants, 700)
	assert_eq(second.fit + second.wounded + second.dead + second.captured + second.released, 700)
	var first: Dictionary = report.snapshot(f.repo, f.state, 5551)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	var controllers: Array[String] = [f.extra]
	assert_false(prisoners.holder_defeated(f.repo, restored, f.enemy, controllers, "rescue-for-snapshot").has("error"))
	assert_eq(report.snapshot(f.repo, restored, 5551), first, "The historical snapshot survives later civilian release and save/load")

func test_surrender_captures_all_100_with_king_and_camp() -> void:
	var f := _fixture()
	var common: Dictionary = f.state.military_cohorts[String(f.code) + ":common"]
	common.initial = 90
	common.fit = 70
	common.wounded = 20
	f.state.military_cohorts[String(f.code) + ":noble"].initial = 10
	f.state.military_cohorts[String(f.code) + ":noble"].fit = 10
	f.battle.parley = {"agreed": {"surrender": {"policy": "accept"}}}
	f.state.king_state.x_m = 0
	f.state.king_state.y_m = 0
	f.state.regiments[f.code].camp_state = {"phase": "camped", "site_x_m": 0, "site_y_m": 0}
	var outcome := BattleOrders._surrender(f.repo, f.state, f.battle, "att", "100-survivors")
	assert_true(outcome.get("accepted", false))
	assert_eq(MilitaryRoster.living(f.state, f.code), 0)
	var prisoners: GDScript = load("res://scripts/engine/prisoner_system.gd")
	assert_not_null(prisoners)
	if prisoners == null:
		return
	var held: Dictionary = prisoners.held_counts(f.state, f.enemy)
	assert_eq(held.total, 100)
	assert_eq(held.nobles, 10)
	assert_eq(held.wounded, 20)
	assert_eq(String(f.state.king_state.travel_state), "safe_departure")
	assert_true(f.battle.att.is_empty())
	assert_eq(String(f.state.regiments[f.code].camp_state.phase), "camped")

func test_shared_meal_phase_charges_current_holder_once() -> void:
	var f := _fixture()
	var ai: GDScript = load("res://scripts/engine/enemy_ai.gd")
	assert_true(ai.has_method("eat_day"))
	if not ai.has_method("eat_day"):
		return
	var host := String(f.state.foes[f.enemy].host)
	f.state.ai_hosts[host].mode = EnemyAi.MODE_RETREAT
	f.state.day = 30
	var enemy_before := int(f.state.foes[f.enemy].supplies)
	EnemyAi.step_day(f.repo, f.state)
	assert_eq(int(f.state.foes[f.enemy].supplies), enemy_before, "AI anticipates its meal without charging before surrender")
	var prisoners: GDScript = load("res://scripts/engine/prisoner_system.gd")
	assert_false(prisoners.capture(f.repo, f.state, {"capture_id": "meal-captives", "battle_id": 5551,
		"round": 0, "participants": {f.enemy: 1}, "reason": "Receiving prisoners before meal",
		"changes": [{"cohort_id": String(f.code) + ":common", "from": "fit", "to": "captured_current", "count": 60}]}).has("error"))
	var expected := ArmySystem.day_bite(ArmySystem.supply_use(f.repo, ArmySystem.regiment(f.repo, f.enemy, f.state), f.state), 30)
	ai.eat_day(f.repo, f.state)
	assert_eq(int(f.state.foes[f.enemy].supplies), maxi(0, enemy_before - expected))
	ai.eat_day(f.repo, f.state)
	assert_eq(int(f.state.foes[f.enemy].supplies), maxi(0, enemy_before - expected), "Saved meal ownership is idempotent")

func test_entry_baseline_excludes_previous_dead_and_captured() -> void:
	var report: GDScript = load("res://scripts/engine/battle_report.gd")
	var f := _fixture()
	var cohort: Dictionary = f.state.military_cohorts[String(f.code) + ":common"]
	cohort.initial = 120
	cohort.fit = 100
	cohort.dead = 10
	cohort.captured_current = 10
	report.enroll(f.state, f.battle, f.code, "att")
	var totals: Dictionary = report.tally(f.state, f.battle).att
	assert_eq(totals.participants, 160, "100 entrants plus the sixty noble entrants")
	assert_eq(totals.dead, 0)
	assert_eq(totals.captured, 0)

func test_departed_personnel_do_not_take_another_battles_losses() -> void:
	var report: GDScript = load("res://scripts/engine/battle_report.gd")
	assert_true(report.has_method("leave"))
	if not report.has_method("leave"):
		return
	var f := _fixture()
	report.enroll(f.state, f.battle, f.code, "att")
	report.leave(f.state, f.battle, f.code)
	assert_false(MilitaryRoster.transfer_units(f.repo, f.state, "elsewhere-deaths", [{"unit_code": f.code,
		"from": "fit", "to": "dead", "count": 10}], "Losses after leaving this battlefield").has("error"))
	assert_eq(report.tally(f.state, f.battle).att.dead, 0)
	assert_eq(report.tally(f.state, f.battle).att.fit, 600)
	report.enroll(f.state, f.battle, f.code, "att")
	assert_false(MilitaryRoster.transfer_units(f.repo, f.state, "here-deaths", [{"unit_code": f.code,
		"from": "fit", "to": "dead", "count": 5}], "Losses after rejoining this battlefield").has("error"))
	var totals: Dictionary = report.tally(f.state, f.battle).att
	assert_eq(totals.participants, 600)
	assert_eq(totals.dead, 5)
	assert_eq(totals.fit, 595)

func test_battle_defeat_rescues_custody_before_removing_holder() -> void:
	var f := _fixture()
	assert_false(PrisonerSystem.capture(f.repo, f.state, {"capture_id": "held-before-defeat", "battle_id": 5551,
		"round": 0, "participants": {f.enemy: 1}, "reason": "Enemy held sixty prisoners",
		"changes": [{"cohort_id": String(f.code) + ":common", "from": "fit", "to": "captured_current", "count": 60}]}).has("error"))
	assert_false(MilitaryRoster.transfer_units(f.repo, f.state, "holder-wiped", [{"unit_code": f.enemy,
		"from": "fit", "to": "dead", "count": MilitaryRoster.fit(f.state, f.enemy)}], "The holder is wiped out").has("error"))
	assert_false(PrisonerSystem.settle_unguarded(f.repo, f.state).has("error"))
	assert_eq(int(PrisonerSystem.held_counts(f.state, f.enemy).total), 60, "An active battlefield retains controller-based settlement")
	var result := BattleSystem.step_battle(f.repo, f.state, 5551)
	assert_eq(result.status, "complete")
	assert_eq(int(PrisonerSystem.held_counts(f.state, f.enemy).total), 0)
	assert_eq(int(f.state.military_cohorts[String(f.code) + ":common"].released), 60)
	assert_true(f.state.battles.is_empty())
	assert_true(f.state.battle_records.has("5551"))

func test_outside_recovery_then_battle_deaths_never_create_negative_survivors() -> void:
	var f := _fixture()
	var id := String(f.code) + ":common"
	var report: GDScript = load("res://scripts/engine/battle_report.gd")
	var cohort: Dictionary = f.state.military_cohorts[id]
	cohort.fit = 520
	cohort.wounded = 20
	report.enroll(f.state, f.battle, f.code, "att")
	report.leave(f.state, f.battle, f.code)
	assert_false(MilitaryRoster.transition(f.repo, f.state, "outside-heal", [{"cohort_id": id,
		"from": "wounded", "to": "fit", "count": 20}], "Recovery away from this battle").has("error"))
	report.enroll(f.state, f.battle, f.code, "att")
	assert_false(MilitaryRoster.transfer_units(f.repo, f.state, "all-die-after-return", [{"unit_code": f.code,
		"from": "fit", "to": "dead", "count": 600}], "Final casualties in this battle").has("error"))
	assert_eq(report.tally(f.state, f.battle).att, {"participants": 600, "fit": 0, "wounded": 0, "dead": 600, "captured": 0, "released": 0})

func test_production_day_phases_feed_surrendered_people_only_at_the_new_holder() -> void:
	var f := _fixture()
	f.state.day = 12
	f.state.king_state.x_m = 100000000
	f.state.king_state.y_m = 100000000
	f.state.regiments[f.code].x_m = 0
	f.state.regiments[f.code].y_m = 0
	f.state.foes[f.enemy].x_m = 1000
	f.state.foes[f.enemy].y_m = 0
	f.state.ai_hosts[String(f.state.foes[f.enemy].host)].mode = EnemyAi.MODE_RETREAT
	f.state.supply_lines.clear()
	f.state.regiments[f.code].supplies = 100000
	var engine := TickEngine.new(f.repo)
	var prior_enemy := int(f.state.foes[f.enemy].supplies)
	engine._before_battles(f.state, {})
	assert_eq(int(f.state.foes[f.enemy].supplies), prior_enemy)
	f.battle.parley = {"agreed": {"surrender": {"policy": "accept"}}}
	assert_true(BattleOrders._surrender(f.repo, f.state, f.battle, "def", "foe-day-surrender").get("accepted", false))
	var expected := ArmySystem.day_bite(ArmySystem.supply_use(f.repo, ArmySystem.regiment(f.repo, f.code, f.state), f.state), 12)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	engine._after_battles(f.state)
	assert_eq(int(f.state.foes[f.enemy].supplies), prior_enemy, "Captured troops do not eat again at their former unit")
	assert_eq(int(f.state.regiments[f.code].supplies), 100000 - expected, "One combined meal includes all received captives")
	var resumed := TickEngine.new(f.repo)
	resumed._after_battles(restored)
	assert_eq(restored.regiments[f.code].supplies, f.state.regiments[f.code].supplies)
	assert_eq(restored.foes[f.enemy].supplies, f.state.foes[f.enemy].supplies)

func test_day_entry_releases_prisoners_after_the_last_guard_is_lost_outside_battle() -> void:
	var f := _fixture()
	f.state.battles.clear()
	assert_false(PrisonerSystem.capture(f.repo, f.state, {"capture_id": "noncombat-holder", "battle_id": 0,
		"round": 0, "participants": {f.enemy: 1}, "reason": "Prisoners before loss of the guards",
		"changes": [{"cohort_id": String(f.code) + ":common", "from": "fit", "to": "captured_current", "count": 60}]}).has("error"))
	assert_false(MilitaryRoster.transfer_units(f.repo, f.state, "last-guard-deserts", [{"unit_code": f.enemy,
		"from": "fit", "to": "released", "count": MilitaryRoster.fit(f.state, f.enemy)}], "Desertion removes the last fit guard").has("error"))
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(f.state.to_dict())))
	TickEngine.new(f.repo).resolve_day(f.state)
	assert_eq(int(PrisonerSystem.held_counts(f.state, f.enemy).total), 0)
	assert_eq(int(f.state.military_cohorts[String(f.code) + ":common"].released), 60)
	TickEngine.new(f.repo).resolve_day(restored)
	assert_eq(restored.prisoner_batches, f.state.prisoner_batches)
	assert_eq(restored.prisoner_events, f.state.prisoner_events)
