extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Roster := preload("res://scripts/engine/military_roster.gd")
var repo: DataRepository
var state: GameState
var code: String
var province: String
var officer := "char_captain_hale"

func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	# This fixture exercises a fresh explicit enlistment, not the opening host.
	state.military_rosters.clear()
	state.military_cohorts.clear()
	state.military_events.clear()
	state.military_migration.clear()
	repo.balance["recruitment_eligible_permille"] = 1000
	for unit: String in state.army_roster:
		var row: Dictionary = state.army_roster[unit]
		if row["kingdom_code"] == repo.resolve_realm("player_realm") and MapObjects.regiment_arm(repo, row) == "infantry":
			code = unit
			break
	var realm := repo.resolve_realm("player_realm")
	var capital := String(repo.kingdoms[realm]["capital_burg"])
	province = String(repo.burgs[capital]["province_code"])

func _recruit(id: String, person: String = "", count: int = 1) -> Dictionary:
	return {"id": id, "unit_code": code, "source_province": province,
		"source_population_field": "rural_population", "identity": "noble",
		"family_name": "Fenwick", "stage": "active", "count": count, "person_id": person}

func _assignment_available() -> bool:
	var available := Roster.new().has_method("assign_commander")
	assert_true(available, "real commander assignment boundary exists")
	return available

func _assign(target: String, person: String) -> Dictionary:
	return Roster.new().call("assign_commander", repo, state, target, person, "appointed before departure")

func test_named_commander_is_one_existing_noble_not_an_extra_person() -> void:
	Roster.mobilize(repo, state, "raise", [_recruit("named", officer), _recruit("others", "", 9)], "raised nobles")
	assert_eq(state.military_cohorts["named"].get("person_id", ""), officer)
	if not _assignment_available(): return
	var before := MilitaryPopulation.occupied(state, province)
	assert_false(_assign(code, officer).has("error"))
	assert_eq(state.military_rosters[code]["commander_id"], officer)
	assert_eq(state.military_rosters[code]["commander_cohort_id"], "named")
	assert_eq(Roster.fit(state, code), 10)
	assert_eq(MilitaryPopulation.occupied(state, province), before)
	var saved := SaveLoad.state_hash(state)
	assert_false(_assign(code, officer).has("error"))
	assert_eq(SaveLoad.state_hash(state), saved, "same appointment does not duplicate history")

func test_named_person_cannot_be_enlisted_twice_or_as_a_group() -> void:
	var before := SaveLoad.state_hash(state)
	assert_true(Roster.mobilize(repo, state, "bad", [_recruit("two", officer, 2)], "invalid enlistment").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	assert_false(Roster.mobilize(repo, state, "raise", [_recruit("one", officer)], "raised officer").has("error"))
	before = SaveLoad.state_hash(state)
	assert_true(Roster.mobilize(repo, state, "again", [_recruit("duplicate", officer)], "duplicate officer").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_ineligible_named_people_never_enter_capturable_cohorts() -> void:
	var before := SaveLoad.state_hash(state)
	for person: String in ["you", "char_queen", "char_king_osric"]:
		var row := _recruit("forbidden", person)
		row["family_name"] = state.characters[person].family_name
		assert_true(Roster.mobilize(repo, state, "invalid", [row], "attempted enlistment").has("error"), person)
		assert_eq(SaveLoad.state_hash(state), before)

func test_dead_named_person_cannot_be_raised_in_a_new_cohort() -> void:
	assert_false(Roster.mobilize(repo, state, "raise", [_recruit("one", officer)], "raised officer").has("error"))
	Roster.transition(repo, state, "death", [{"cohort_id": "one", "from": "fit", "to": "dead", "count": 1}], "killed in battle")
	var before := SaveLoad.state_hash(state)
	assert_true(Roster.mobilize(repo, state, "resurrect", [_recruit("two", officer)], "invalid re-enlistment").has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_assignment_refuses_king_councillor_foreigner_and_unenlisted_person() -> void:
	if not _assignment_available(): return
	Roster.mobilize(repo, state, "raise", [_recruit("named", officer)], "raised officer")
	for id: String in ["you", "char_king_osric", "char_queen", "char_lord_edgar"]:
		var before := SaveLoad.state_hash(state)
		assert_true(_assign(code, id).has("error"), id)
		assert_eq(SaveLoad.state_hash(state), before)
	state.council["marshal"] = officer
	var before := SaveLoad.state_hash(state)
	assert_true(_assign(code, officer).has("error"), "active council office conflicts")
	assert_eq(SaveLoad.state_hash(state), before)

func test_assignment_is_unique_and_respects_realm_and_unit_kind() -> void:
	if not _assignment_available(): return
	Roster.mobilize(repo, state, "raise", [_recruit("named", officer)], "raised officer")
	assert_false(_assign(code, officer).has("error"))
	var other := "test_other_unit"
	state.army_roster[other] = state.army_roster[code].duplicate(true)
	state.military_rosters[other] = {"commander_id": "", "cohort_ids": []}
	var before := SaveLoad.state_hash(state)
	assert_true(_assign(other, officer).has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	state.army_roster[code]["kingdom_code"] = repo.resolve_realm("raider_realm")
	assert_true(_assign(code, officer).has("error"), "appointment is revalidated, even on repeat")
	state.army_roster[code]["kingdom_code"] = repo.resolve_realm("player_realm")
	var definitions: Dictionary = repo.get("commanders")
	definitions[officer]["unit_kinds"] = "fleet"
	assert_true(_assign(code, officer).has("error"), "wrong arm is refused")

func test_captured_commander_loses_appointment_and_release_needs_new_enlistment() -> void:
	if not _assignment_available(): return
	Roster.mobilize(repo, state, "raise", [_recruit("named", officer)], "raised officer")
	_assign(code, officer)
	Roster.transition(repo, state, "capture", [{"cohort_id": "named", "from": "fit", "to": "captured_current", "count": 1}], "captured in battle")
	assert_eq(state.military_rosters[code]["commander_id"], "")
	assert_true(_assign(code, officer).has("error"))
	Roster.transition(repo, state, "release", [{"cohort_id": "named", "from": "captured_current", "to": "released", "count": 1}], "ransom fulfilled")
	assert_true(_assign(code, officer).has("error"), "civilian does not automatically return")
	assert_false(Roster.mobilize(repo, state, "reraise", [_recruit("new", officer)], "paid re-enlistment").has("error"))
	assert_false(_assign(code, officer).has("error"))
	assert_eq(Roster.fit(state, code), 1)
	var saved := SaveLoad.state_hash(state)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(SaveLoad.state_hash(state), saved)
	assert_eq(state.military_rosters[code]["commander_cohort_id"], "new")
