extends GutTest
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const SuiteData := preload("res://tests/suite_data.gd")
const H := preload("res://tests/engine/conduct_helpers.gd")
## The marshal's report (spec 2026-10-10-foraging-and-desertion §3.3, §4): the
## conduct events of a day as ONE supply-kind letter, filed by the engine.

var repo: DataRepository
var state: GameState


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 11)
	for t in range(0, 12):
		state.tick = t
		if Forage.season_permille(repo, state) == 1000:
			break
	state.day = 1
	state.forage_stripped.clear()
	state.conduct_marks.clear()
	state.hazards.clear()


func _reports() -> Array:
	return state.missives.filter(func(m: Dictionary) -> bool: return String(m["title"]) == "Marshal's report")


func _place(c: String, province: String) -> void:
	var cells: Array = MapManors.manors_of_province(repo, province, state)
	var m := ArmySystem.pack_to_metres(repo, MapTerrain.cell_center(repo, repo.cells[int(cells[0])]))
	state.regiments[c]["x_m"] = m.x
	state.regiments[c]["y_m"] = m.y


## Stand `c` in the province, camped by no town (a town would feed it).
func _place_in_field(c: String, province: String) -> void:
	_place(c, province)
	state.regiments[c]["camp_town"] = ""
	assert_eq(ArmyGround.camped_by(repo, state, c), "")


func _fed(c: String) -> void:
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c, state), state)
	state.regiments[c]["supplies"] = ArmySystem.max_units(repo, use)
	state.regiments[c]["morale"] = 90
	state.regiments[c]["training"] = 90


func test_letter_for_each_event_type() -> void:
	var c := H.land_unit(repo, state)
	var prov := H.foreign_province(repo, state)
	var kingdom := MapOwnership.owner_of(repo, state, prov)
	var events: Array = [
		{"type": "forage_unlawful", "regiment": c, "province": prov, "kingdom": kingdom},
		{"type": "forage_incident", "regiment": c, "province": prov, "kingdom": kingdom},
		{"type": "forage_havoc", "regiment": c, "province": prov},
		{"type": "stripped_bare", "regiment": c, "province": prov},
		{"type": "deserting", "regiment": c, "lost": 3},
		{"type": "deserting_big", "regiment": c}]
	var m := MissiveWriter.conduct_dispatch(repo, state, events)
	assert_eq(String(m["kind"]), "supply")
	assert_eq(String(m["title"]), "Marshal's report")
	assert_eq(String(m["subject"]["code"]), c)
	assert_eq((m["facts"] as Array).size(), 6)
	var label := String(ArmySystem.regiment(repo, c, state)["label"])
	var plabel := String(repo.provinces[prov]["label"])
	var klabel := String(repo.kingdoms[kingdom]["label"])
	assert_eq(String(m["facts"][0]["text"]), String(repo.conduct_words["forage_unlawful"]) % [label, plabel])
	assert_eq(String(m["facts"][1]["text"]), String(repo.conduct_words["forage_incident"]) % [label, plabel, klabel])
	assert_eq(String(m["facts"][2]["text"]), String(repo.conduct_words["forage_havoc"]) % [plabel])
	assert_eq(String(m["facts"][4]["text"]), String(repo.conduct_words["deserting"]) % [label])
	for f: Dictionary in m["facts"]:
		assert_false(String(f["text"]).contains("%"), "no unfilled placeholder")
	assert_false(String(repo.conduct_words["deserting_big"]).contains("%d"))
	assert_false(String(repo.conduct_words["deserting_big"]).contains("5"), "no number in the words")


func test_stripped_bare_event_names_the_last_taker() -> void:
	var units := H.land_units(repo, state)
	var first := String(units[0])
	var last := String(units[1])
	var prov := H.home_province(repo, state)
	var row: Dictionary = state.army_roster[first]
	for arm: String in repo.world_table("military", "unit_types"):
		if row.has(arm):
			row[arm] = "0"
	row["infantry"] = "1000"
	repo.balance["army_supply_per_head_permille"] = 10000 # Same 10000 monthly commoner demand within the cap.
	assert_false(Personnel.replace(repo, state, first, 1000).has("error"))
	state.regiments[first]["supplies"] = 0
	state.regiments[first]["carry_days"] = 30
	state.regiments[first]["forage"] = "desperate"
	_fed(last)   # no need: takes nothing, but is a taker of the day all the same
	H.set_food(repo, prov, 90)
	state.forage_stripped[prov] = 899
	# 90 x 30 x 101 / 1000 = 272, day 1 = 9, 9 x 500 / 2700 = 1 -> 900
	var ev := ArmyConduct.take_day(repo, state, prov, [last, first])
	assert_eq(ev.size(), 1)
	assert_eq(String(ev[0]["regiment"]), last, "the last taker in code order")


func test_engine_files_one_letter_a_day() -> void:
	var units := H.land_units(repo, state)
	var a := String(units[0])
	var prov := H.foreign_province(repo, state)
	H.set_stance(repo, MapOwnership.owner_of(repo, state, prov), "Enemy")
	state.day = 1
	for c: String in units:
		_fed(c)
		_place(c, H.home_province(repo, state))
	var engine := TickEngine.new(repo)
	engine.advance_day(state)
	assert_eq(_reports().size(), 0, "a quiet day files none")
	_place_in_field(a, prov)
	var row: Dictionary = state.law_in_force.get(LawSystem.UNIT_PREFIX + a, {})
	row["plunder"] = {"value": "forbid", "decree_id": 1}
	state.law_in_force[LawSystem.UNIT_PREFIX + a] = row
	state.regiments[a]["supplies"] = 0
	state.regiments[a]["morale"] = 50
	state.regiments[a]["training"] = 50
	H.set_food(repo, prov, 9)
	engine.advance_day(state)
	assert_eq(_reports().size(), 1, "one letter for the day")
	assert_eq(String(_reports()[0]["kind"]), "supply")
	assert_eq(String(_reports()[0]["subject"]["code"]), a)
	assert_false(engine.day_conduct.is_empty())


func test_old_save_plays_a_month() -> void:
	var d := state.to_dict()
	for k: String in ["forage_stripped", "grievance", "conduct_marks"]:
		d.erase(k)
	for c: String in (d["regiments"] as Dictionary):
		for k: String in ["forage", "forage_days", "deserted", "desert_rem"]:
			(d["regiments"][c] as Dictionary).erase(k)
	var old := GameState.from_dict(d)
	var engine := TickEngine.new(repo)
	for i in range(Calendar.DAYS_PER_TICK - 1):
		engine.advance_day(old)
	engine.advance(old)
	assert_eq(old.tick, state.tick + 1)
	assert_true(old.forage_stripped is Dictionary)
	for c: String in old.regiments:
		assert_gte(int(old.regiments[c].get("supplies", 0)), 0)
