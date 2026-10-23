extends GutTest
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const SuiteData := preload("res://tests/suite_data.gd")
const BattleScenario := preload("res://tests/fixtures/battle_scenario.gd")
const Play := preload("res://tests/invasion_play.gd")

func test_acknowledge_is_idempotent() -> void:
	var resolution_script: Variant = load("res://scripts/engine/day_resolution.gd")
	assert_not_null(resolution_script, "the day transaction protocol exists")
	if resolution_script == null:
		return
	var tx: Dictionary = resolution_script.begin(10, false)
	tx["pending_decision"] = {"token": "10:b1:0", "kind": "encounter",
		"battle_id": 1, "choices": ["continue"], "selected": ""}
	assert_eq(resolution_script.acknowledge(tx, "10:b1:0", "continue")["status"], "accepted")
	assert_eq(resolution_script.acknowledge(tx, "10:b1:0", "continue")["status"], "duplicate")
	assert_eq(resolution_script.acknowledge(tx, "wrong", "continue")["status"], "stale")

func test_begin_has_durable_transaction_defaults() -> void:
	var resolution_script: Variant = load("res://scripts/engine/day_resolution.gd")
	assert_not_null(resolution_script)
	if resolution_script == null:
		return
	var tx: Dictionary = resolution_script.begin(30, true)
	assert_eq(tx["day"], 30)
	assert_true(tx["month_end"])
	assert_eq(tx["phase"], "WORKS")
	assert_eq(tx["substep_index"], 0)
	assert_eq(tx["phase_cursor"], 0)
	assert_eq(tx["battle_ids"], [])
	assert_eq(tx["battle_index"], 0)
	assert_eq(tx["battle_step"], "")
	assert_eq(tx["substep_count"], DayResolution.DEFAULT_SUBSTEP_COUNT)
	assert_eq(tx["substep_order"], DayResolution.SUBSTEP_ORDER)
	assert_eq(tx["day_battle_order"], DayResolution.DAY_BATTLE_ORDER)
	assert_eq(tx["pending_decision"], {})
	assert_eq(tx["consumed_tokens"], [])
	assert_eq(tx["journal"], {"works": [], "arrivals": [], "couriers": [], "battles": [],
		"sieges": [], "raids": [], "supply": [], "conduct": [], "reports": []})

func test_saved_protocol_is_validated_before_resume() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var state := SuiteData.campaign(repo, 24601)
	state.day = 10
	state.day_resolution = DayResolution.begin(10, false)
	var engine := TickEngine.new(repo)
	assert_eq(DayResolution.incompatibility_reason(state.day_resolution), "")
	var changed_order := BattleScenario.roundtrip(state)
	changed_order.day_resolution["substep_order"] = ["CONTACT", "MARCH"]
	var before := SaveLoad.state_hash(changed_order)
	var result := TickEngine.new(repo).resolve_day(changed_order)
	assert_eq(result["status"], "error")
	assert_eq(result["error"], "saved tactical substep order does not match this build")
	assert_eq(SaveLoad.state_hash(changed_order), before, "incompatible transaction is left untouched")

func _march_fixture(repo: DataRepository) -> Dictionary:
	var state := SuiteData.campaign(repo, 24601)
	state.tick = 1
	state.day = 10
	state.foes.clear()
	state.ai_hosts.clear()
	for arm: String in repo.army_speed:
		repo.army_speed[arm] = 1
	for ground: String in repo.army_ground_speed:
		repo.army_ground_speed[ground] = 1000
	repo.balance["army_clearance_on"] = 0.0
	var codes: Array = state.regiments.keys()
	codes.sort()
	var code := String(codes[0])
	var entry: Dictionary = state.regiments[code]
	entry["morale"] = 100
	entry["training"] = 100
	entry["carry_days"] = 10
	entry["supplies"] = ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code, state), state) * 6
	var start := Vector2i(int(entry["x_m"]), int(entry["y_m"]))
	# Keep the pacing fixture away from town/garrison settlement slots.
	start = Vector2i(1000000, 1000000)
	entry["x_m"] = start.x
	entry["y_m"] = start.y
	entry["dest_x_m"] = start.x
	entry["dest_y_m"] = start.y
	ArmySystem.set_march_m(repo, state, code, start + Vector2i(5000, 0))
	return {"state": state, "code": code, "start": start}

func test_substep_movement_conserves_daily_metres() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var fixture := _march_fixture(repo)
	var state: GameState = fixture["state"]
	var code := String(fixture["code"])
	var start: Vector2i = fixture["start"]
	ArmySystem.set_march_m(repo, state, code, start + Vector2i(1500, 0))
	var substeps := int(repo.bal("battle_substeps"))
	var daily_metres := ArmySystem.day_walk_budget(repo, state, code)
	assert_eq(ArmySystem.day_march_m(repo, state, code), 1000, "fixture's hand-computed daily pace")
	assert_eq(daily_metres, 750, "1,500 metres at 1,000 per day keeps the old even-day pace")
	for index in substeps:
		ArmySystem.march_day(repo, state, substeps, index, true, [code], {code: daily_metres})
	assert_eq(int(state.regiments[code]["x_m"]), start.x + daily_metres,
		"remainder distribution preserves the full day's distance")

func test_non_divisible_substep_budgets_use_the_entire_daily_allowance() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var fixture := _march_fixture(repo)
	var state: GameState = fixture["state"]
	var code := String(fixture["code"])
	var start: Vector2i = fixture["start"]
	ArmySystem.set_march_m(repo, state, code, start + Vector2i(2300, 0))
	var budget := ArmySystem.day_walk_budget(repo, state, code)
	assert_eq(budget, 767, "2,300 m at 1,000 m/day is shared over three days")
	var legacy := BattleScenario.roundtrip(state)
	var legacy_code := code
	var legacy_start: Vector2i = start
	var legacy_before := Vector2i(int(legacy.regiments[legacy_code]["x_m"]), int(legacy.regiments[legacy_code]["y_m"]))
	ArmySystem.march_day(repo, legacy, 1, 0)
	assert_eq(int(legacy.regiments[legacy_code]["x_m"]) - legacy_before.x, 767,
		"legacy whole-day movement keeps its even 2,300 m / 3 day pace")
	var restored := BattleScenario.roundtrip(state)
	assert_eq(ArmySystem.day_walk_budget(repo, restored, code), budget,
		"whole-metre daily budget survives JSON save/load")
	for substep in int(repo.bal("battle_substeps")):
		ArmySystem.march_day(repo, state, int(repo.bal("battle_substeps")), substep,
			true, [code], {code: budget})
	assert_eq(int(state.regiments[code]["x_m"]), start.x + 767,
		"the ten allowances sum to the complete 767 m budget")
	assert_eq(ArmySystem.day_walk_budget(repo, state, code), 767,
		"remaining distance is redistributed evenly over two days")
	for substep in int(repo.bal("battle_substeps")):
		ArmySystem.march_day(repo, state, int(repo.bal("battle_substeps")), substep,
			true, [code], {code: 767})
	assert_eq(int(state.regiments[code]["x_m"]), start.x + 1534)
	var final_budget := ArmySystem.day_walk_budget(repo, state, code)
	assert_eq(final_budget, 766)
	var arrivals: Array = []
	for substep in int(repo.bal("battle_substeps")):
		var at_step := ArmySystem.march_day(repo, state, int(repo.bal("battle_substeps")), substep,
			true, [code], {code: final_budget})
		if not at_step.is_empty():
			assert_eq(substep, int(repo.bal("battle_substeps")) - 1)
		arrivals.append_array(at_step)
	assert_eq(arrivals, [code], "arrival is reported once, on the final fixed substep")
	assert_eq(Vector2i(int(state.regiments[code]["x_m"]), int(state.regiments[code]["y_m"])),
		start + Vector2i(2300, 0))

func test_saved_movement_cursor_accumulates_and_survives_json() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var fixture := _march_fixture(repo)
	var state: GameState = fixture["state"]
	var code := String(fixture["code"])
	var start: Vector2i = fixture["start"]
	ArmySystem.set_march_m(repo, state, code, start + Vector2i(2300, 0))
	var budget := ArmySystem.day_walk_budget(repo, state, code)
	var tx := DayResolution.begin(state.day, false, state.absolute_day(), int(repo.bal("battle_substeps")))
	tx["march_entries"] = {code: state.regiments[code].duplicate(true)}
	tx["march_budgets"] = {code: budget}
	state.day_resolution = tx
	for substep in 3:
		ArmySystem.march_day_saved(repo, state, 10, substep, tx.march_entries, tx.march_budgets)
	assert_eq(int(state.regiments[code].x_m) - start.x, 231, "first three allowances are 77 metres")
	var restored := BattleScenario.roundtrip(state)
	var paused_x := int(restored.regiments[code].x_m)
	for substep in range(3, 10):
		ArmySystem.march_day_saved(repo, restored, int(repo.bal("battle_substeps")), substep,
			restored.day_resolution["march_entries"], restored.day_resolution["march_budgets"])
	assert_eq(int(restored.regiments[code].x_m) - paused_x, 536, "remaining 767 - 231 survives JSON")
	assert_eq(int(restored.regiments[code]["x_m"]), start.x + 767)
	assert_eq(int(restored.day_resolution["march_entries"][code]["x_m"]), start.x + 767,
		"the saved cursor contains the completed movement slice")

func test_a_last_day_arrival_waits_for_its_final_fixed_substep() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var fixture := _march_fixture(repo)
	var state: GameState = fixture["state"]
	var code := String(fixture["code"])
	var start: Vector2i = fixture["start"]
	ArmySystem.set_march_m(repo, state, code, start + Vector2i(750, 0))
	var budget := ArmySystem.day_walk_budget(repo, state, code)
	assert_eq(budget, 750)
	var arrivals: Array = []
	for substep in int(repo.bal("battle_substeps")):
		var day_arrivals := ArmySystem.march_day(repo, state, int(repo.bal("battle_substeps")), substep,
			true, [code], {code: budget})
		if not day_arrivals.is_empty():
			assert_eq(substep, int(repo.bal("battle_substeps")) - 1)
		arrivals.append_array(day_arrivals)
	assert_eq(arrivals, [code])

func test_short_diagonal_arrival_settles_instead_of_stalling() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var fixture := _march_fixture(repo)
	var state: GameState = fixture["state"]
	var code := String(fixture["code"])
	var start: Vector2i = fixture["start"]
	ArmySystem.set_march_m(repo, state, code, start + Vector2i(1, 1))
	assert_eq(ArmySystem.day_walk_budget(repo, state, code), 2,
		"ceil(sqrt(2)) permits the rounded final metre")
	var arrivals: Array = []
	for substep in int(repo.bal("battle_substeps")):
		arrivals.append_array(ArmySystem.march_day(repo, state, int(repo.bal("battle_substeps")), substep,
			true, [code], {code: 2}))
	assert_eq(arrivals, [code])
	assert_eq(ArmySystem.order_of(repo, state, code), ArmySystem.ORDER_GARRISON)

	var saved := {code: state.regiments[code].duplicate(true)}
	var near_diagonal := start + Vector2i(2, 2)
	ArmySystem.set_march_m(repo, state, code, near_diagonal)
	saved[code] = state.regiments[code].duplicate(true)
	var final_budget := ArmySystem.day_walk_budget(repo, state, code)
	assert_eq(final_budget, 2)
	var final_arrivals: Array = []
	for substep in int(repo.bal("battle_substeps")):
		final_arrivals.append_array(ArmySystem.march_day_saved(repo, state,
			int(repo.bal("battle_substeps")), substep, saved, {code: final_budget}))
	assert_eq(final_arrivals, [code])

func test_zero_daily_pace_does_not_move_in_substeps() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var fixture := _march_fixture(repo)
	var state: GameState = fixture["state"]
	var code := String(fixture["code"])
	var start: Vector2i = fixture["start"]
	for arm: String in repo.army_speed:
		repo.army_speed[arm] = 0
	assert_eq(ArmySystem.day_march_m(repo, state, code), 0)
	var substeps := int(repo.bal("battle_substeps"))
	for index in substeps:
		ArmySystem.march_day(repo, state, substeps, index)
	assert_eq(Vector2i(int(state.regiments[code]["x_m"]), int(state.regiments[code]["y_m"])), start)

func test_encounter_blocks_before_losses_and_resumes_after_roundtrip() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var state := BattleScenario.moving_contact(repo, 10)
	# This journal fixture needs an active melee attacker, independent of ranged geometry.
	for code: String in state.foes:
		var fit := ArmySystem.fit_count(repo, state, code)
		_infantry_equipment(repo, state, code, fit)
	var first_march := ""
	for code: String in state.regiments:
		if String(state.regiments[code].get("order", "")) == ArmySystem.ORDER_MARCH:
			first_march = code
			break
	var unrelated := ""
	for code: String in state.regiments:
		var regiment := ArmySystem.regiment(repo, code, state)
		if code != first_march and not regiment.is_empty() \
				and String(regiment.get("is_naval", "0")) != "1" and ArmySystem.base_pace_km(repo, regiment) > 0:
			unrelated = code
			break
	var unrelated_start := Vector2i(1000000, 1000000)
	state.regiments[unrelated]["x_m"] = unrelated_start.x
	state.regiments[unrelated]["y_m"] = unrelated_start.y
	ArmySystem.set_march_m(repo, state, unrelated, unrelated_start + Vector2i(100000, 0))
	state.regiments[unrelated]["carry_days"] = 10
	state.regiments[unrelated]["supplies"] = ArmySystem.supply_use(repo,
		ArmySystem.regiment(repo, unrelated, state), state) * 6
	var unrelated_budget := ArmySystem.day_walk_budget(repo, state, unrelated)
	var p_start := -1
	for code: String in state.regiments:
		if String(state.regiments[code].get("order", "")) == ArmySystem.ORDER_MARCH:
			p_start = int(state.regiments[code]["x_m"])
			break
	var foe_start := int(state.foes[String(state.foes.keys()[0])]["x_m"])
	var engine := TickEngine.new(repo)
	var result := engine.resolve_day(state)
	assert_eq(result["status"], "blocked")
	assert_eq(state.day, 10, "the calendar remains on the blocked day")
	assert_lt(int(state.day_resolution["substep_index"]), int(repo.bal("battle_substeps")),
		"the encounter pauses before advancing to later movement substeps")
	assert_eq(state.day_resolution["substep_count"], int(repo.bal("battle_substeps")),
		"the transaction saves the table-configured fixed substep count")
	assert_eq(state.day_resolution["battle_step"], "fighting",
		"the saved cursor pauses after substep contact and before that battle's first round")
	assert_eq(state.battles.size(), 1)
	var battle: Dictionary = state.battles[0]
	var p := String((battle["def"] as Array)[0])
	var f := String((battle["att"] as Array)[0])
	var blocked_p := int(state.regiments[p]["x_m"])
	var blocked_f := int(state.foes[f]["x_m"])
	assert_eq(blocked_p, p_start + 1000, "the player completes the daily movement budget before contact")
	assert_eq(blocked_f, foe_start - 1000, "the foe completes the daily movement budget before contact")
	assert_eq(int(state.foes[f]["x_m"]), int(state.regiments[p]["x_m"]))
	assert_eq(int(battle["rounds"]), 0, "no battle round before confirmation")
	assert_eq(int(state.day_resolution["march_entries"][unrelated]["x_m"]),
		int(state.regiments[unrelated]["x_m"]), "the unrelated column's saved cursor matches its moved state")
	var pending: Dictionary = state.day_resolution["pending_decision"]
	var battle_id := int(pending["battle_id"])
	var p_before: Dictionary = state.regiments[p].duplicate(true)
	var f_before: Dictionary = state.foes[f].duplicate(true)
	var blocked_hash := SaveLoad.state_hash(state)
	assert_eq(engine.resolve_day(state)["status"], "blocked")
	assert_eq(SaveLoad.state_hash(state), blocked_hash, "re-polling a blocked transaction has no effects")
	assert_eq(int(p_before.get("dead", 0)) + int(p_before.get("wounded", 0)), 0)
	assert_eq(int(f_before.get("dead", 0)) + int(f_before.get("wounded", 0)), 0)
	var loaded := BattleScenario.roundtrip(state)
	var loaded_tx: Dictionary = loaded.day_resolution
	assert_eq(DayResolution.acknowledge(loaded_tx, String(pending["token"]), "continue")["status"], "accepted")
	var resumed := TickEngine.new(repo).resolve_day(loaded)
	assert_eq(resumed["status"], "complete")
	var battle_rounds: Array = (resumed["journal"]["battles"] as Array).filter(
		func(event: Dictionary) -> bool: return String(event.get("kind", "")) == "round" and int(event.get("battle_id", -1)) == battle_id)
	assert_eq(battle_rounds.size(), 1)
	assert_eq(int(battle_rounds[0]["substep_index"]), int(pending["substep_index"]),
		"the confirmed battle round is journaled in the contact substep before the cursor advances")
	assert_eq(loaded.day, 11)
	assert_gt(Personnel.count(loaded, p, "dead") + Personnel.count(loaded, p, "wounded"), 0,
		"the acknowledged encounter now resolves exactly one battle round")
	assert_eq(int((loaded.day_resolution if not loaded.day_resolution.is_empty() else {}).get("day", 10)), 10)
	assert_eq(loaded.foes[f]["x_m"], f_before["x_m"], "resuming does not move the contacted unit twice")
	assert_eq(loaded.regiments[p]["x_m"], p_before["x_m"], "the player's contact move is not repeated either")
	assert_eq(int(loaded.regiments[unrelated]["x_m"]) - unrelated_start.x, unrelated_budget,
		"resuming does not replay the unrelated column's blocked substep")
	var second_copy := BattleScenario.roundtrip(state)
	DayResolution.acknowledge(second_copy.day_resolution, String(pending["token"]), "continue")
	TickEngine.new(repo).resolve_day(second_copy)
	DayResolution.acknowledge(state.day_resolution, String(pending["token"]), "continue")
	engine.resolve_day(state)
	assert_eq(SaveLoad.state_hash(loaded), SaveLoad.state_hash(second_copy),
		"JSON continuation matches a second deterministic continuation")
	assert_eq(SaveLoad.state_hash(loaded), SaveLoad.state_hash(state),
		"JSON continuation matches the uninterrupted live transaction")


## P1's synthetic paid handler uses the real saved token protocol; P4 owns
## the production event/finance handler and must repeat this acceptance.
func _paid_fixture_continue(state: GameState, token: String) -> Dictionary:
	var tx: Dictionary = state.day_resolution
	if token == String(tx.get("pending_decision", {}).get("token", "")) \
			and int(state.metrics["treasury"]) < 7:
		return {"status": "unaffordable"}
	var result := DayResolution.acknowledge(tx, token, "continue")
	if String(result["status"]) == "accepted":
		state.metrics["treasury"] -= 7
		(tx["journal"]["reports"] as Array).append({"kind": "fixture_fee", "token": token, "gold": -7})
	return result


func test_second_battle_does_not_replay_first() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var state := BattleScenario.moving_two_battles(repo, 10)
	repo.battle_outcomes.assign([{"tier": "hand_made", "eff_min": 0, "eff_max": 1000,
		"attacker_loss_permille": 100, "defender_loss_permille": 100,
		"wounded_share_permille": 500, "attacker_morale": 0, "defender_morale": 0, "rout": "none"}])
	for stance: String in repo.battle_stances:
		repo.battle_stances[stance]["retreat_odds_permille"] = 0
		repo.battle_stances[stance]["retreats_on_contact"] = false
	for table: Dictionary in [state.regiments, state.foes]:
		for code: String in table:
			if String(table[code].get("order", "")) != ArmySystem.ORDER_MARCH:
				continue
			_infantry_equipment(repo, state, code, 100)
			assert_false(Personnel.replace(repo, state, code, ArmySystem.personnel_capacity(repo, state.army_roster[code])).has("error"))
	# One pair fights in substep zero; the other still marches to later contact.
	var player := String(Play.land_regiments(repo, 1)[0])
	var foe := String(state.foes.keys()[0])
	var spot := Vector2i(int(state.regiments[player]["x_m"]), int(state.regiments[player]["y_m"]))
	for entry: Dictionary in [state.regiments[player], state.foes[foe]]:
		entry["x_m"] = spot.x
		entry["y_m"] = spot.y
		entry["dest_x_m"] = spot.x
		entry["dest_y_m"] = spot.y
		entry["order"] = ArmySystem.ORDER_GARRISON
	state.metrics["treasury"] = 100.0
	var engine := TickEngine.new(repo)
	var first := engine.resolve_day(state)
	assert_eq(first["status"], "blocked")
	var first_id := int(state.day_resolution["pending_decision"]["battle_id"])
	var first_token := String(state.day_resolution["pending_decision"]["token"])
	DayResolution.acknowledge(state.day_resolution, first_token, "continue")
	var second := engine.resolve_day(state)
	assert_eq(second["status"], "blocked")
	var second_id := int(state.day_resolution["pending_decision"]["battle_id"])
	var second_token := String(state.day_resolution["pending_decision"]["token"])
	assert_ne(second_id, first_id)
	assert_gt(int(second["decision"]["substep_index"]), int(first["decision"]["substep_index"]))
	var first_battle := BattleSystem.battle_by_id(state, first_id)
	var second_battle := BattleSystem.battle_by_id(state, second_id)
	assert_eq(int(first_battle["rounds"]), 1, "the earlier battle already fought before the later encounter")
	for code: String in first_battle["att"] + first_battle["def"]:
		var entry := ArmySystem.state_of(repo, state, code)
		assert_eq(ArmySystem.fit_count(repo, state, code), 90)
		assert_eq(Personnel.count(state, code, "wounded"), 5)
		assert_eq(Personnel.count(state, code, "dead"), 5)
	assert_eq(int(second_battle["rounds"]), 0, "the pending battle has not fought")
	for code: String in second_battle["att"] + second_battle["def"]:
		var entry := ArmySystem.state_of(repo, state, code)
		assert_eq(ArmySystem.fit_count(repo, state, code), 100)
	assert_eq(state.metrics["treasury"], 100.0)
	var loaded := BattleScenario.roundtrip(state)
	var results: Array = []
	for branch: GameState in [state, loaded]:
		var pending_hash := SaveLoad.state_hash(branch)
		assert_eq(TickEngine.new(repo).resolve_day(branch)["status"], "blocked")
		assert_eq(SaveLoad.state_hash(branch), pending_hash, "polling the second pause changes nothing")
		assert_eq(_paid_fixture_continue(branch, "stale-token")["status"], "stale")
		assert_eq(branch.metrics["treasury"], 100.0)
		branch.metrics["treasury"] = 6.0
		var poor_hash := SaveLoad.state_hash(branch)
		assert_eq(_paid_fixture_continue(branch, second_token)["status"], "unaffordable")
		assert_eq(SaveLoad.state_hash(branch), poor_hash, "failed payment does not consume the decision")
		branch.metrics["treasury"] = 100.0
		assert_eq(_paid_fixture_continue(branch, second_token)["status"], "accepted")
		assert_eq(branch.metrics["treasury"], 93.0)
		var paid_hash := SaveLoad.state_hash(branch)
		assert_eq(_paid_fixture_continue(branch, second_token)["status"], "duplicate")
		assert_eq(SaveLoad.state_hash(branch), paid_hash, "retrying a paid choice charges nothing")
		var complete := TickEngine.new(repo).resolve_day(branch)
		assert_eq(complete["status"], "complete")
		assert_eq(branch.metrics["treasury"], 93.0)
		var rounds: Array = (complete["journal"]["battles"] as Array).filter(
			func(event: Dictionary) -> bool: return String(event.get("kind", "")) == "round")
		for id: int in [first_id, second_id]:
			assert_eq(rounds.filter(func(event: Dictionary) -> bool: return int(event["battle_id"]) == id).size(), 1)
		var fees: Array = (complete["journal"]["reports"] as Array).filter(
			func(event: Dictionary) -> bool: return String(event.get("kind", "")) == "fixture_fee")
		assert_eq(fees.size(), 1, "the paid decision has one durable fee record")
		results.append(complete)
	assert_eq(results[0]["journal"], results[1]["journal"], "second-pause JSON preserves battle and fee journals")
	assert_eq(state.rng.to_dict(), loaded.rng.to_dict())
	assert_eq(SaveLoad.state_hash(state), SaveLoad.state_hash(loaded))


func test_later_substep_reinforcement_joins_after_round_and_fights_next_day() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var state := BattleScenario.moving_contact(repo, 10)
	# This journal fixture needs an active melee attacker, independent of ranged geometry.
	for code: String in state.foes:
		var fit := ArmySystem.fit_count(repo, state, code)
		_infantry_equipment(repo, state, code, fit)
	var codes := Play.land_regiments(repo, 2)
	var player := String(Play.land_regiments(repo, 1)[0])
	var foe := String(state.foes.keys()[0])
	var contact := Vector2i(1000000, 1000000)
	state.regiments[player]["x_m"] = contact.x
	state.regiments[player]["y_m"] = contact.y
	state.regiments[player]["order"] = ArmySystem.ORDER_GARRISON
	state.regiments[player]["dest_x_m"] = contact.x
	state.regiments[player]["dest_y_m"] = contact.y
	state.foes[foe]["x_m"] = contact.x
	state.foes[foe]["y_m"] = contact.y
	state.foes[foe]["order"] = ArmySystem.ORDER_GARRISON
	state.foes[foe]["dest_x_m"] = contact.x
	state.foes[foe]["dest_y_m"] = contact.y
	var reinforcement := String(codes.filter(func(code: String) -> bool: return code != player)[0])
	Play.place(repo, state, reinforcement, contact + Vector2i(200, 0), ArmySystem.ORDER_MARCH)
	state.regiments[reinforcement]["carry_days"] = 10
	state.regiments[reinforcement]["supplies"] = ArmySystem.supply_use(repo,
		ArmySystem.regiment(repo, reinforcement, state), state) * 6
	ArmySystem.set_march_m(repo, state, reinforcement, contact)
	var engine := TickEngine.new(repo)
	var blocked := engine.resolve_day(state)
	assert_eq(blocked["status"], "blocked")
	var token := String(blocked["decision"]["token"])
	DayResolution.acknowledge(state.day_resolution, token, "continue")
	var first_day := engine.resolve_day(state)
	assert_eq(first_day["status"], "complete")
	var battle_id := int(state.battles[0]["id"])
	var rounds_day_one: Array = (first_day["journal"]["battles"] as Array).filter(
		func(event: Dictionary) -> bool: return int(event.get("battle_id", -1)) == battle_id and String(event.get("kind", "")) == "round")
	var joins_day_one: Array = (first_day["journal"]["battles"] as Array).filter(
		func(event: Dictionary) -> bool: return int(event.get("battle_id", -1)) == battle_id and String(event.get("kind", "")) == "join" and String(event.get("code", "")) == reinforcement)
	assert_eq(rounds_day_one.size(), 1)
	assert_eq(joins_day_one.size(), 1, "the reinforcement arrives after the battle already fought today")
	assert_gt(int(joins_day_one[0]["substep_index"]), int(rounds_day_one[0]["substep_index"]))
	var second_day := engine.resolve_day(state)
	assert_eq(second_day["status"], "complete")
	var rounds_day_two: Array = (second_day["journal"]["battles"] as Array).filter(
		func(event: Dictionary) -> bool: return int(event.get("battle_id", -1)) == battle_id and String(event.get("kind", "")) == "round")
	assert_eq(rounds_day_two.size(), 1)
	assert_true(reinforcement in (rounds_day_two[0]["att"] as Array)
		or reinforcement in (rounds_day_two[0]["def"] as Array),
		"the joined regiment is present in the next day's combat participants")


func test_month_end_blocks_before_settlement() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var state := BattleScenario.moving_contact(repo, Calendar.DAYS_PER_TICK)
	for seat: String in repo.seats:
		(repo.seats[seat] as Dictionary)["salary_gold"] = 0
	var seat_codes: Array = state.council.keys()
	seat_codes.sort()
	(repo.seats[String(seat_codes[0])] as Dictionary)["salary_gold"] = 7
	state.metrics["treasury"] = 100.0
	var engine := TickEngine.new(repo)
	var blocked := engine.resolve_day(state, true)
	assert_eq(blocked.status, "blocked")
	assert_eq(state.tick, 1)
	assert_eq(state.day, Calendar.DAYS_PER_TICK)
	assert_eq(state.metrics["treasury"], 100.0, "no monthly settlement while the encounter is pending")
	DayResolution.acknowledge(state.day_resolution, blocked.decision["token"], "continue")
	var settled := engine.resolve_day(state, true)
	assert_eq(settled.status, "complete")
	assert_eq(state.tick, 2)
	assert_eq(state.day, 1)
	var salary_lines: Array = settled.report.metric_deltas.filter(func(line: Dictionary) -> bool:
		return String(line.get("reason", "")) == "ministers' salaries")
	assert_eq(salary_lines.size(), 1, "monthly salary settles once after the day resumes")
	assert_eq(int(salary_lines[0]["delta"]), -7, "the salary ledger applies the hand-computed seven-gold cost")

func test_legacy_advance_saves_its_month_compatibility_intent_once() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var state := SuiteData.campaign(repo, 24601)
	state.tick = 1
	state.day = 10
	var engine := TickEngine.new(repo)
	var report := engine.resolve_day(state, true)
	assert_eq(report.status, "complete")
	assert_eq(state.tick, 2, "one legacy advance handles one day and that day's month")
	assert_eq(state.day, 1)
	assert_eq(state.absolute_day(), 31)
	assert_eq(state.day_resolution, {}, "the single transaction clears after both phases")

func test_legacy_advance_blocked_transaction_keeps_month_intent_across_json() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var state := BattleScenario.moving_contact(repo, 10)
	var first_engine := TickEngine.new(repo)
	var blocked := first_engine.resolve_day(state, true)
	assert_eq(blocked.status, "blocked")
	assert_true(state.day_resolution["month_end"])
	var loaded := BattleScenario.roundtrip(state)
	var token := String(loaded.day_resolution["pending_decision"]["token"])
	assert_eq(DayResolution.acknowledge(loaded.day_resolution, token, "continue")["status"], "accepted")
	var resumed := TickEngine.new(repo).resolve_day(loaded, true)
	assert_eq(resumed.status, "complete")
	assert_eq(loaded.tick, 2)
	assert_eq(loaded.day, 1)
	assert_eq(loaded.absolute_day(), 31)


func test_ordinary_day_transaction_keeps_its_boundary_when_advance_resumes_it() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	repo.battle_events.clear() # Isolate month settlement from commander-paid battlefield choices.
	var state := BattleScenario.moving_contact(repo, 10)
	state.metrics["treasury"] = 100.0
	var engine := TickEngine.new(repo)
	var blocked := engine.resolve_day(state)
	assert_eq(blocked["status"], "blocked")
	assert_false(state.day_resolution["month_end"])
	assert_false(state.day_resolution.has("settle_month_compat"))
	DayResolution.acknowledge(state.day_resolution, String(blocked["decision"]["token"]), "continue")
	var resumed := engine.resolve_day(state, true)
	assert_eq(resumed.status, "complete")
	assert_eq(state.tick, 1, "resuming a saved ordinary day does not settle the month")
	assert_eq(state.day, 11)
	assert_eq(state.metrics["treasury"], 100.0)
	assert_true((resumed.report == null or resumed.report.metric_deltas.is_empty()), "no monthly ledger lines run for this saved day")

func test_royal_budget_is_apportioned_once_and_survives_midday_json() -> void:
	var data := SuiteData.open_country(SuiteData.repo())
	var state := SuiteData.campaign(data, 42)
	state.king_state = {"x_m": 0, "y_m": 0, "route": [[3001, 0]], "follow_code": "", "travel_state": "travelling", "last_advanced_day": 0}
	var tx := DayResolution.begin(1, false)
	for index in 3:
		tx.substep_index = index
		KingSystem.step_substep(data, state, tx)
	assert_eq(tx.king_budget, 3001)
	assert_eq(KingSystem.position(state), Vector2i(901, 0), "301 + 300 + 300")
	state.day_resolution = tx
	var loaded := BattleScenario.roundtrip(state)
	for branch: GameState in [state, loaded]:
		for index in range(3, 10):
			branch.day_resolution.substep_index = index
			KingSystem.step_substep(data, branch, branch.day_resolution)
		assert_eq(KingSystem.position(branch), Vector2i(3001, 0))
		var before := branch.to_dict()
		KingSystem.step_substep(data, branch, branch.day_resolution)
		assert_eq(branch.to_dict(), before, "retry of the last substep spends no budget twice")
	assert_eq(loaded.to_dict(), state.to_dict())

func test_king_follows_column_at_every_contact_boundary() -> void:
	var data := SuiteData.flat_ground(SuiteData.repo())
	var fixture := _march_fixture(data)
	var state: GameState = fixture.state
	var code: String = fixture.code
	state.regiments[code]["camp_town"] = ""
	state.king_state = {"x_m": fixture.start.x, "y_m": fixture.start.y, "route": [], "follow_code": code, "travel_state": "following", "last_advanced_day": 0}
	var tx := DayResolution.begin(state.day, false)
	var budget := ArmySystem.day_walk_budget(data, state, code)
	for index in 10:
		ArmySystem.march_day(data, state, 10, index, true, [code], {code: budget})
		tx.substep_index = index
		KingSystem.step_substep(data, state, tx)
		assert_eq(KingSystem.position(state), Vector2i(int(state.regiments[code].x_m), int(state.regiments[code].y_m)), "king synchronized before contact %d" % index)

func test_unknown_protocol_cannot_mutate_any_saved_state() -> void:
	var data := SuiteData.repo()
	var state := SuiteData.campaign(data, 42)
	state.day_resolution = DayResolution.begin(state.day, false)
	state.day_resolution.protocol_version = 999
	var before := state.to_dict()
	assert_eq(TickEngine.new(data).resolve_day(state).status, "error")
	assert_eq(state.to_dict(), before)

func test_main_v3_mid_march_cursor_continues_without_replaying_metres() -> void:
	var data := SuiteData.flat_ground(SuiteData.repo())
	var fixture := _march_fixture(data)
	var state: GameState = fixture.state
	var code: String = fixture.code
	ArmySystem.set_march_m(data, state, code, fixture.start + Vector2i(2300, 0))
	var tx := DayResolution.begin(state.day, false, state.absolute_day())
	tx.protocol_version = 3
	tx.substep_protocol_version = 3
	tx.substep_order = DayResolution.LEGACY_SUBSTEP_ORDER.duplicate()
	tx.phase = "FIXED_TACTICAL_SUBSTEPS"
	tx.phase_cursor = DayResolution.PHASES.find("FIXED_TACTICAL_SUBSTEPS")
	tx.march_entries = {code: state.regiments[code].duplicate(true)}
	tx.march_budgets = {code: 767}
	for index in 3:
		ArmySystem.march_day_saved(data, state, 10, index, tx.march_entries, tx.march_budgets)
	tx.substep_index = 3
	state.day_resolution = tx
	assert_eq(int(state.regiments[code].x_m) - fixture.start.x, 231)
	var loaded := BattleScenario.roundtrip(state)
	for branch: GameState in [state, loaded]:
		assert_eq(TickEngine.new(data).resolve_day(branch).status, "complete")
		assert_eq(int(branch.regiments[code].x_m) - fixture.start.x, 767)
		assert_eq(branch.day, 11)
	assert_eq(loaded.to_dict(), state.to_dict())

func test_unversioned_started_feature_day_keeps_its_completed_work() -> void:
	var data := SuiteData.repo()
	var state := BattleScenario.contact(data, 10)
	var fights := BattleSystem.prepare_day(data, state)
	var token := "%d:encounter:%d" % [state.absolute_day(), int(state.battles[0].id)]
	var tx := {"day": state.absolute_day(), "month_end": false, "phase": "encounters",
		"battle_ids": state.battles.map(func(b: Dictionary) -> int: return int(b.id)), "battle_index": 0,
		"battle_step": "", "pending_decision": {}, "consumed_tokens": [],
		"journal": {"works": [{"fixture": "already completed"}], "arrivals": [], "couriers": [],
			"battles": fights, "sieges": [], "raids": [], "supply": [], "conduct": [], "ai": []}}
	state.day_resolution = tx
	var engine := TickEngine.new(data)
	assert_eq(engine.resolve_day(state).status, "blocked")
	assert_eq(state.day_resolution.phase, "encounters")
	var loaded := BattleScenario.roundtrip(state)
	for branch: GameState in [state, loaded]:
		var runner := TickEngine.new(data)
		assert_eq(runner.resolve_decision(branch, token, "continue").status, "accepted")
		var complete := runner.resolve_day(branch)
		assert_eq(complete.status, "complete")
		assert_eq(complete.journal.works, [{"fixture": "already completed"}])
	assert_eq(loaded.to_dict(), state.to_dict())

func test_saved_battle_cursor_past_end_is_refused_atomically_in_v3_and_v4() -> void:
	var data := SuiteData.repo()
	for version in [3, 4]:
		var state := BattleScenario.contact(data, 10)
		BattleSystem.prepare_day(data, state)
		var tx := DayResolution.begin(10, false, 10)
		tx.protocol_version = version
		tx.substep_protocol_version = version
		tx.substep_order = DayResolution.LEGACY_SUBSTEP_ORDER.duplicate() if version == 3 else DayResolution.SUBSTEP_ORDER.duplicate()
		tx.phase = "FIXED_TACTICAL_SUBSTEPS"
		tx.phase_cursor = DayResolution.PHASES.find(tx.phase)
		tx.substep_index = 9
		tx.battle_step = "fighting"
		tx.battle_ids = [int(state.battles[0].id)]
		tx.battle_index = 2
		tx.pending_decision = {}
		state.day_resolution = tx
		var before := state.to_dict()
		assert_eq(TickEngine.new(data).resolve_day(state).status, "error", "v%d invalid saved battle index" % version)
		assert_eq(state.to_dict(), before, "v%d refusal precedes all mutation" % version)


func _infantry_equipment(repo: DataRepository, state: GameState, code: String, men: int) -> void:
	var row: Dictionary = state.army_roster[code]
	for arm: String in repo.world_table("military", "unit_types"):
		row[arm] = "0"
	row.infantry = str(men)
	var source: Dictionary = row.source_parts[0].duplicate(true)
	source.arm = "infantry"
	source.equipment_count = men
	source.crew_per_element = int(repo.world_row("military", "unit_types", "infantry").crew)
	row.source_parts = [source]
