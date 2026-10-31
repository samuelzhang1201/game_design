extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")
const Invasion := preload("res://tests/engine/test_invasion_end_to_end.gd")
const Play := preload("res://tests/invasion_play.gd")


func _fixture() -> Dictionary:
	var repo := SuiteData.no_clearance(SuiteData.open_country(SuiteData.repo()))
	var state := Scenario.contact(repo, 10)
	BattleSystem.detect_contacts(repo, state)
	var battle: Dictionary = state.battles[0]
	var unit := String(battle.def[0])
	var others := Play.land_regiments(repo, 400)
	others.erase(unit)
	var other := String(others[0])
	var at := BattleSystem._at_m(repo, state, unit)
	Play.place(repo, state, other, at, ArmySystem.ORDER_STANDBY)
	assert_true(BattleSystem.join(repo, state, int(battle.id), other, "def"))
	battle.actions = {"att": {"kind": "hold"}, "def": {"kind": "hold"}}
	assert_true(BattleSystem._start_retreat(repo, state, unit, battle))
	state.regiments[unit]["withdrawal_cause"] = "withdrawn"
	return {"repo": repo, "state": state, "battle": battle, "unit": unit, "other": other, "at": at}


func _separate(f: Dictionary) -> void:
	var entry: Dictionary = f.state.regiments[f.unit]
	entry.x_m = int(f.at.x) - 30000


func test_partial_withdrawal_without_an_attack_has_one_public_receipt() -> void:
	var f := _fixture()
	_separate(f)
	var saved := Scenario.roundtrip(f.state)
	var before: Dictionary = f.state.to_dict()
	var supplies: int = f.state.regiments[f.unit].supplies
	var out := BattleSystem.step_battle(f.repo, f.state, int(f.battle.id))
	assert_eq(out.status, "complete")
	assert_false(f.unit in f.battle.def, "the separated unit really leaves")
	assert_true(f.other in f.battle.def, "contact still holds the other unit")
	assert_eq(f.state.battles.size(), 1, "partial withdrawal does not end the battle")
	assert_eq(int(f.battle.rounds), 0, "no artificial combat round")
	assert_eq(f.state.to_dict()["rng"], before["rng"], "no draw without an attack")
	assert_eq(f.state.regiments[f.unit].supplies, supplies)
	var events: Array = out.events
	assert_eq(events.size(), 1, "a real departure cannot disappear on a quiet day")
	if events.is_empty():
		return
	assert_eq(events[0].kind, "withdrawal")
	assert_eq(events[0].left, [{"code": f.unit, "side": "def", "why": "withdrawn"}])
	assert_eq(events[0].day, f.state.absolute_day())
	var resumed := BattleSystem.step_battle(f.repo, saved, int(f.battle.id))
	assert_eq(resumed.events, events, "saving before separation settlement retains the same receipt")
	assert_eq(SaveLoad.state_hash(saved), SaveLoad.state_hash(f.state))
	assert_eq(f.battle.report_events, events, "the saved journal carries the receipt")
	var letter := MissiveWriter.battle_report(f.repo, f.state, events)
	assert_eq((letter.get("facts", []) as Array).size(), 1, "the public letter reports departure, not combat")
	var twin := Scenario.roundtrip(f.state)
	assert_eq(SaveLoad.state_hash(twin), SaveLoad.state_hash(f.state))
	assert_eq(BattleSystem.step_battle(f.repo, twin, int(f.battle.id)).events, [], "JSON retry cannot duplicate it")
	assert_eq(BattleSystem.step_battle(f.repo, f.state, int(f.battle.id)).events, [], "same-day retry is inert")


func test_contact_without_separation_has_no_departure_receipt() -> void:
	var f := _fixture()
	var out := BattleSystem.step_battle(f.repo, f.state, int(f.battle.id))
	assert_true(f.unit in f.battle.def, "retreat intent grants no contact immunity")
	assert_eq(out.events, [])
	assert_eq(int(f.battle.rounds), 0)


func test_last_departure_uses_the_existing_end_receipt_only() -> void:
	var f := _fixture()
	f.battle.def.erase(f.other)
	_separate(f)
	var out := BattleSystem.step_battle(f.repo, f.state, int(f.battle.id))
	assert_eq(f.state.battles.size(), 0)
	assert_eq(out.events.size(), 1)
	assert_eq(out.events[0].kind, "end")
	assert_eq(out.events[0].left, [{"code": f.unit, "side": "def", "why": "withdrawn"}])


func test_contact_observer_rejects_separation_other_hosts_and_empty_opposition() -> void:
	var f := _fixture()
	var observer := Invasion.new()
	observer.repo = f.repo
	var foe := String(f.battle.att[0])
	f.state.foes[foe]["host"] = "receipt_main"
	var at := BattleSystem._at_m(f.repo, f.state, foe)
	var reach := int(f.repo.bal("battle_contact_km") * 1000)
	for code: String in f.battle.def:
		f.state.regiments[code]["x_m"] = at.x + reach
		f.state.regiments[code]["y_m"] = at.y
	assert_true(observer._main_in_contact(f.state, "receipt_main"), "inclusive physical boundary")
	assert_false(observer._main_in_contact(f.state, "another_host"), "other units cannot stand in for the main host")
	for code: String in f.battle.def:
		f.state.regiments[code]["x_m"] += 1
	assert_false(observer._main_in_contact(f.state, "receipt_main"), "saved membership alone does not prove contact")
	f.battle.def.clear()
	assert_false(observer._main_in_contact(f.state, "receipt_main"), "no opposing member means no exposure")
	observer.free()
