extends GutTest
const People := preload("res://tests/fixtures/military_people.gd")
const SuiteData := preload("res://tests/suite_data.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")
const Invasion := preload("res://tests/engine/test_invasion_end_to_end.gd")
const Play := preload("res://tests/invasion_play.gd")


func _fixture() -> Dictionary:
	var repo := SuiteData.no_clearance(SuiteData.open_country(SuiteData.repo()))
	# Receipt fixtures need separate friendly ground, independent of installed art size.
	for row: Dictionary in repo.unit_footprints.values():
		row.radius_m = 20
		row.pitch_m = 80
	var state := Scenario.contact(repo, 10)
	BattleSystem.detect_contacts(repo, state)
	var battle: Dictionary = state.battles[0]
	var unit := String(battle.def[0])
	var others := Play.land_regiments(repo, 400)
	others.erase(unit)
	var other := String(others[0])
	var at := BattleSystem._at_m(repo, state, unit)
	Play.place(repo, state, other, at + Vector2i(0, 1000), ArmySystem.ORDER_STANDBY)
	assert_true(BattleSystem.join(repo, state, int(battle.id), other, "def"))
	battle.actions = {"att": {"kind": "hold"}, "def": {"kind": "hold"}}
	assert_true(BattleSystem._start_retreat(repo, state, unit, battle))
	state.regiments[unit]["withdrawal_cause"] = "withdrawn"
	return {"repo": repo, "state": state, "battle": battle, "unit": unit, "other": other, "at": at}


func _separate(f: Dictionary) -> void:
	var entry: Dictionary = f.state.regiments[f.unit]
	entry.x_m = int(f.at.x) - 30000
	assert_true(BattleGroups.follow_anchor(f.repo, f.state, f.battle, f.unit), "The separated unit takes its physical rows with it")


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
	assert_eq(f.state.military_cohorts, before["military_cohorts"], "a quiet departure causes no casualties")
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


func _line_at(f: Dictionary, code: String, at: Vector2i) -> void:
	var entry := BattleSystem._stored(f.state, code)
	entry.x_m = at.x
	entry.y_m = at.y
	var rows: Array = f.battle.groups[code]
	var points := BattleGroups.layout(f.repo, "line", rows.size(), at, 0, 80)
	for i: int in rows.size():
		rows[i].x_m = points[i].x
		rows[i].y_m = points[i].y
		rows[i].role = "front"
	f.battle.group_anchor_m[code] = [at.x, at.y]


func test_contact_observer_rejects_separation_other_hosts_and_empty_opposition() -> void:
	var f := _fixture()
	var observer := Invasion.new()
	observer.repo = f.repo
	var foe := String(f.battle.att[0])
	f.state.foes[foe]["host"] = "receipt_main"
	var at := BattleSystem._at_m(f.repo, f.state, foe)
	var reach := int(f.repo.bal("battle_contact_km") * 1000)
	_line_at(f, foe, at)
	var n := (f.battle.groups[foe] as Array).size()
	var m := (f.battle.groups[f.unit] as Array).size()
	# Inclusive edge reach = 5000 m + two 20 m radii; row parities align at 40 m.
	_line_at(f, f.unit, at + Vector2i(reach + 40, (n - m) * 40))
	_line_at(f, f.other, at + Vector2i(reach + 1000, 1000))
	assert_true(BattleGroups.placement(f.repo, f.state, f.battle).ok)
	assert_true(observer._main_in_contact(f.state, "receipt_main"), "inclusive physical boundary")
	assert_false(observer._main_in_contact(f.state, "another_host"), "other units cannot stand in for the main host")
	assert_true(BattleGroups.translate(f.repo, f.state, f.battle, f.unit, Vector2i(1, 0)))
	assert_false(observer._main_in_contact(f.state, "receipt_main"), "saved membership alone does not prove contact")
	f.battle.def.clear()
	assert_false(observer._main_in_contact(f.state, "receipt_main"), "no opposing member means no exposure")
	observer.free()


func test_contact_observer_requires_live_members_on_both_sides() -> void:
	var f := _fixture()
	var observer := Invasion.new()
	observer.repo = f.repo
	var foe := String(f.battle.att[0])
	f.state.foes[foe]["host"] = "receipt_main"
	assert_true(observer._main_in_contact(f.state, "receipt_main"))
	var no_main := Scenario.roundtrip(f.state)
	assert_false(People.move(f.repo, no_main, foe, "fit", "dead", MilitaryRoster.fit(no_main, foe), "receipt boundary").has("error"))
	assert_false(observer._main_in_contact(no_main, "receipt_main"), "a main host without fit personnel proves no contact")
	for code: String in f.battle.def:
		assert_false(People.move(f.repo, f.state, code, "fit", "dead", MilitaryRoster.fit(f.state, code), "receipt boundary:" + code).has("error"))
	assert_false(observer._main_in_contact(f.state, "receipt_main"), "opposition without fit personnel proves no contact")
	observer.free()


## 600 plunder x 500 per mille = 300 strategic, once: a rout told only by a
## quiet withdrawal event is still a beaten host; a homeward withdrawal is not.
func test_a_rout_told_by_a_withdrawal_event_pays_spoils_once() -> void:
	var repo := SuiteData.repo()
	repo.balance["battle_spoils_permille"] = 500.0
	var state := SuiteData.campaign(repo, 7)
	var host := Play.host(repo, "main")
	var column := String(EnemyAi.regiments_of(state, host)[0])
	state.ai_hosts[host]["plunder"] = 600
	var strategic := float(state.metrics["strategic"])
	var event := {"kind": "withdrawal", "battle_id": 1, "town": "", "place_x_m": 0, "place_y_m": 0, "left": [{"code": column, "side": "att", "why": "withdrawn"}]}
	assert_eq(RaidSystem.settle_day(repo, state, [event]).filter(func(e: Dictionary) -> bool: return e.kind == "raid_spoils"), [], "homeward is not beaten")
	assert_eq(int(state.ai_hosts[host]["plunder"]), 600)
	event.left[0].why = "rout"
	assert_eq(RaidSystem.settle_day(repo, state, [event]).filter(func(e: Dictionary) -> bool: return e.kind == "raid_spoils").size(), 1)
	assert_eq(float(state.metrics["strategic"]), strategic + 300.0, "600 x 500 / 1000")
	assert_eq(RaidSystem.settle_day(repo, state, [event]).filter(func(e: Dictionary) -> bool: return e.kind == "raid_spoils"), [], "nothing left to pay")


## A row 5000 m from its anchor reaches 5000 m + the piece's radius; a column
## retreating from that ground keeps only its undeployed radius, so two columns
## leaving one field cannot halt each other for good.
func test_a_retreating_column_gives_up_its_deployed_clearance() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 7)
	var column := String(EnemyAi.regiments_of(state, Play.host(repo, "main"))[0])
	var undeployed := int(ArmySystem.clearance_blockers(repo, state)["r"][column])
	var entry: Dictionary = state.foes[column]
	state.battles = [{"id": 1, "att": [column], "def": [], "groups": {column: [
		{"x_m": int(entry.x_m) + 5000, "y_m": int(entry.y_m), "count": 100, "slot": 0, "role": "front"}]}}]
	var radius := int(BattleGroups.piece(repo, state, column).radius_m)
	assert_eq(int(ArmySystem.clearance_blockers(repo, state)["r"][column]), 5000 + radius, "the ground it holds")
	entry["battle_retreat"] = true
	assert_eq(int(ArmySystem.clearance_blockers(repo, state)["r"][column]), undeployed, "the ground it is leaving")


## An enemy standing on the road halts an ordinary march, but a withdrawing
## column goes round it: halted there it could neither fight nor ever leave.
func test_only_a_withdrawing_column_goes_round_an_enemy_on_its_road() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	var state := SuiteData.campaign(repo, 7)
	var host := Play.host(repo, "main")
	var column := String(EnemyAi.regiments_of(state, host)[0])
	var enemy := String(Play.land_regiments(repo, 400)[0])
	for code: String in state.army_roster.keys():
		if code != column and code != enemy:
			state.army_roster.erase(code)
			state.regiments.erase(code)
			state.foes.erase(code)
	var entry: Dictionary = state.foes[column]
	var here := Vector2i(int(entry.x_m), int(entry.y_m))
	Play.place(repo, state, enemy, here + Vector2i(20000, 0), ArmySystem.ORDER_STANDBY)
	var aim := here + Vector2i(60000, 0)
	entry.order = ArmySystem.ORDER_MARCH
	entry.dest_x_m = aim.x
	entry.dest_y_m = aim.y
	var verdict := func() -> String:
		return String(ArmySystem._clearance(repo, state, column, entry, here, [aim], 40000.0, ArmySystem.clearance_blockers(repo, state)).kind)
	assert_eq(state.ai_hosts[host].mode, "ASSEMBLE", "a host not going home")
	assert_eq(verdict.call(), "halt", "an ordinary march stands before the enemy")
	entry.battle_retreat = true
	assert_eq(verdict.call(), "detour", "a column retreating from a battle")
	entry.erase("battle_retreat")
	entry.disengaging = 1
	assert_eq(verdict.call(), "detour", "a column falling back after its battle")
	entry.erase("disengaging")
	state.ai_hosts[host].mode = "RETREAT"
	assert_eq(verdict.call(), "detour", "a column of a host going home")
