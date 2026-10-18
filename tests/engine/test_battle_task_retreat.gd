extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")
const Play := preload("res://tests/invasion_play.gd")

func _fixture() -> Dictionary:
	var repo := SuiteData.no_clearance(SuiteData.open_country(SuiteData.repo()))
	var state := Scenario.contact(repo, 10)
	BattleSystem.detect_contacts(repo, state)
	var battle: Dictionary = state.battles[0]
	var unit := String(battle.def[0])
	var codes := Play.land_regiments(repo, 400)
	codes.erase(unit)
	var other := String(codes[0])
	var at := BattleSystem._at_m(repo, state, unit)
	Play.place(repo, state, other, at, ArmySystem.ORDER_STANDBY)
	battle.def.append(other)
	battle.actions = {"att": {"kind": "hold"}, "def": {"kind": "hold"}}
	for code: String in battle.att + battle.def:
		var entry := BattleSystem._stored(state, code)
		entry.morale = 100
		entry.supplies = 10000
	return {"repo": repo, "state": state, "battle": battle, "unit": unit, "other": other, "at": at}

func _issue(f: Dictionary, id: String, task := "retreat") -> void:
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, {"id": id, "unit": f.unit,
		"battle_id": int(f.battle.id), "task": task}).get("status"), "pending")

func _receive(f: Dictionary, id: String) -> void:
	assert_eq(BattleTaskSystem.deliver_task(f.repo, f.state, id).get("status"), "received")

func _fight(f: Dictionary) -> Dictionary:
	var events: Array = []
	return BattleSystem._fight(f.repo, f.state, f.battle, events)

func test_receipt_starts_only_recipient_real_route_and_preserves_packing() -> void:
	var f := _fixture()
	var entry: Dictionary = f.state.regiments[f.unit]
	entry.camp_state = {"phase": CampSystem.CAMPED, "site": {"x_m": f.at.x, "y_m": f.at.y}}
	_issue(f, "withdraw")
	_fight(f)
	assert_false(bool(entry.get("battle_retreat", false)), "pending is inert")
	f.state.day += 1
	_receive(f, "withdraw")
	_fight(f)
	assert_true(bool(entry.get("battle_retreat", false)))
	assert_eq(String(entry.order), ArmySystem.ORDER_MARCH)
	assert_false(bool(f.state.regiments[f.other].get("battle_retreat", false)))
	assert_eq(BattleOrders.kind(f.battle, "def"), "hold")
	assert_true(f.unit in f.battle.def, "receipt cannot remove physical contact")
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.unit), f.at)
	ArmySystem.march_day(f.repo, f.state)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.unit), f.at)
	f.state.day += 1
	ArmySystem.march_day(f.repo, f.state)
	assert_eq(BattleSystem._at_m(f.repo, f.state, f.unit), f.at, "a complete packing day")
	f.state.day += 1
	ArmySystem.march_day(f.repo, f.state)
	assert_ne(BattleSystem._at_m(f.repo, f.state, f.unit), f.at)
	_fight(f)
	assert_false(f.unit in f.battle.def, "real separation removes only this unit")
	assert_true(f.other in f.battle.def)

func test_cancel_and_replacement_do_not_reverse_physical_withdrawal_or_repeat_losses() -> void:
	var f := _fixture()
	_issue(f, "withdraw")
	_receive(f, "withdraw")
	_fight(f)
	assert_true(bool(f.state.regiments[f.unit].get("battle_retreat", false)))
	var entry: Dictionary = f.state.regiments[f.unit]
	var food := int(entry.supplies)
	var morale := int(entry.morale)
	var destination := Vector2i(int(entry.dest_x_m), int(entry.dest_y_m))
	_issue(f, "cancel", "cancel")
	_receive(f, "cancel")
	assert_true(BattleTaskSystem.current(f.state, f.unit).is_empty())
	_issue(f, "attack", "advance")
	_receive(f, "attack")
	f.state.day += 1
	_fight(f)
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.unit).kind, "retreat")
	assert_eq(int(entry.supplies), food)
	assert_eq(int(entry.morale), morale)
	assert_eq(Vector2i(int(entry.dest_x_m), int(entry.dest_y_m)), destination)
	assert_eq((f.battle.get("withdrawal_costs", []) as Array).size(), 1)

func test_unreachable_retreat_stays_exposed_without_cost_and_retries_after_json() -> void:
	var f := _fixture()
	_issue(f, "withdraw")
	_receive(f, "withdraw")
	var towns: Dictionary = f.repo.burgs
	f.repo.burgs = {}
	var before: Dictionary = f.state.regiments[f.unit].duplicate(true)
	_fight(f)
	assert_false(bool(f.state.regiments[f.unit].get("battle_retreat", false)))
	assert_true(f.unit in f.battle.def)
	assert_eq(int(f.state.regiments[f.unit].supplies), int(before.supplies))
	assert_eq(int(f.state.regiments[f.unit].morale), int(before.morale))
	assert_string_contains(String(f.state.regiments[f.unit].get("withdrawal_reason", "")), "No reachable")
	var twin := Scenario.roundtrip(f.state)
	f.repo.burgs = towns
	f.state.day += 1
	twin.day += 1
	var events: Array = []
	_fight(f)
	BattleSystem._fight(f.repo, twin, twin.battles[0], events)
	assert_true(bool(f.state.regiments[f.unit].get("battle_retreat", false)))
	assert_eq(SaveLoad.state_hash(twin), SaveLoad.state_hash(f.state))

func test_protected_unit_withdrawal_does_not_protect_fighting_allies() -> void:
	var f := _fixture()
	_issue(f, "withdraw")
	_receive(f, "withdraw")
	f.battle.actions.att.kind = "attack"
	f.battle.parley = {"agreed": {"safe_withdrawal": {"policy": "protect"}}}
	for context: String in ["ranged", "shock"]:
		f.repo.balance["battle_context_" + context + "_permille"] = 1000
	var withdrawing := MilitaryRoster.fit(f.state, f.unit)
	var holding := MilitaryRoster.fit(f.state, f.other)
	_fight(f)
	assert_eq(MilitaryRoster.fit(f.state, f.unit), withdrawing, "agreement protects actual withdrawal")
	@warning_ignore("integer_division")
	var lost := holding * 100 / 1000
	assert_eq(MilitaryRoster.fit(f.state, f.other), holding - lost, "100 per mille applies only to the holding ally")

func test_failed_round_and_json_retry_preserve_single_withdrawal_cost() -> void:
	var f := _fixture()
	_issue(f, "withdraw")
	_receive(f, "withdraw")
	f.battle.actions.att.kind = "attack"
	var cohort := String(f.state.military_rosters[f.other].cohort_ids[0])
	var origin := String(f.state.military_cohorts[cohort].source_population_field)
	f.state.military_cohorts[cohort].source_population_field = "invalid"
	assert_true(_fight(f).has("error"))
	assert_true(bool(f.state.regiments[f.unit].get("battle_retreat", false)))
	var entry: Dictionary = f.state.regiments[f.unit].duplicate(true)
	var pending: Dictionary = f.battle.pending_round.duplicate(true)
	var rng: Dictionary = f.state.rng.to_dict()
	assert_true(_fight(f).has("error"))
	assert_eq(f.state.regiments[f.unit], entry)
	assert_eq(f.battle.pending_round, pending)
	assert_eq(f.state.rng.to_dict(), rng)
	var twin := Scenario.roundtrip(f.state)
	f.state.military_cohorts[cohort].source_population_field = origin
	twin.military_cohorts[cohort].source_population_field = origin
	var events: Array = []
	_fight(f)
	BattleSystem._fight(f.repo, twin, twin.battles[0], events)
	assert_eq(SaveLoad.state_hash(twin), SaveLoad.state_hash(f.state))
	assert_eq((f.battle.get("withdrawal_costs", []) as Array).size(), 1)
	var final_hash := SaveLoad.state_hash(f.state)
	_fight(f)
	assert_eq(SaveLoad.state_hash(f.state), final_hash)

func test_frozen_round_waits_to_start_newly_received_retreat() -> void:
	var f := _fixture()
	_issue(f, "withdraw")
	f.battle.pending_round = {"unit_actions": {f.unit: {"kind": "hold", "task_id": "", "reason": "Frozen hold"}}}
	_receive(f, "withdraw")
	BattleSystem._exits(f.repo, f.state, f.battle, "none", 500)
	assert_false(bool(f.state.regiments[f.unit].get("battle_retreat", false)))
	f.battle.pending_round = {"roll": 17}
	BattleSystem._exits(f.repo, f.state, f.battle, "none", 500)
	assert_false(bool(f.state.regiments[f.unit].get("battle_retreat", false)), "legacy rounds also keep their actions")
	f.battle.erase("pending_round")
	BattleSystem._exits(f.repo, f.state, f.battle, "none", 500)
	assert_true(bool(f.state.regiments[f.unit].get("battle_retreat", false)))

func test_cancellation_before_execution_and_live_incapacity_prevent_start() -> void:
	var f := _fixture()
	_issue(f, "withdraw")
	_receive(f, "withdraw")
	_issue(f, "cancel", "cancel")
	_receive(f, "cancel")
	_fight(f)
	assert_false(bool(f.state.regiments[f.unit].get("battle_retreat", false)))
	f.state.day += 1
	_issue(f, "again")
	_receive(f, "again")
	f.state.regiments[f.unit].captured = true
	_fight(f)
	assert_false(bool(f.state.regiments[f.unit].get("battle_retreat", false)))
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.unit).kind, "hold")

func test_retreating_recipient_does_not_cancel_allied_attack_or_pay_attack_supplies() -> void:
	var f := _fixture()
	_issue(f, "withdraw")
	_receive(f, "withdraw")
	assert_eq(BattleTaskSystem.issue_task(f.repo, f.state, {"id": "ally", "unit": f.other,
		"battle_id": int(f.battle.id), "task": "advance"}).get("status"), "pending")
	_receive(f, "ally")
	_fight(f)
	assert_eq(BattleSystem.unit_action(f.repo, f.state, f.battle, f.other).kind, "attack")
	assert_eq(int(f.battle.rounds), 1)
	var costs: Array = f.state.military_events.values().filter(func(e: Dictionary) -> bool:
		return e.get("request", {}).get("kind") == "battle_round")
	assert_eq(costs.size(), 1, "one atomic round writer")
	@warning_ignore("integer_division")
	var abandoned := 10000 * int(f.repo.bal("battle_retreat_supply_loss_permille")) / 1000
	assert_eq(int(f.state.regiments[f.unit].supplies), 10000 - abandoned, "only existing withdrawal supply loss")
