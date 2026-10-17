extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
var repo: DataRepository
var state: GameState
var province: String
var code: String
var officer: String

func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	state.military_rosters.clear()
	state.military_cohorts.clear()
	state.military_events.clear()
	state.tick = 2
	state.day = 1
	var realm := repo.resolve_realm("player_realm")
	province = MapOwnership.provinces_of(repo, state, realm)[0]
	var codes := state.regiments.keys()
	codes.sort()
	for unit: String in codes:
		if String(ArmySystem.regiment(repo, unit, state).get("is_naval", "0")) != "1":
			code = unit
			break
	var ids := repo.commanders.keys()
	ids.sort()
	for person: String in ids:
		if (state.characters[person] as Character).kingdom == realm and MilitaryCommanders.candidate_error(repo, state, person) == "":
			officer = person
			break
	assert_ne(officer, "")
	repo.balance["recruitment_eligible_permille"] = 1000
	state.world[MilitaryPopulation.path(province, "rural_population")] = 1000

func _recruit(id: String, count: int, person := "") -> Dictionary:
	return MilitaryRoster.mobilize(repo, state, "raise:" + id, [{"id": id, "unit_code": code,
		"source_province": province, "source_population_field": "rural_population", "identity": "commoner" if person == "" else "noble",
		"family_name": "" if person == "" else (state.characters[person] as Character).family_name,
		"stage": "active", "count": count, "person_id": person}], "Test enlistment")

func _release(id: String, count: int) -> void:
	for move: Array in [["fit", "captured_current"], ["captured_current", "released"]]:
		var result := MilitaryRoster.transition(repo, state, id + ":" + String(move[1]),
			[{"cohort_id": id, "from": move[0], "to": move[1], "count": count}], "Test prisoner release")
		assert_false(result.has("error"), str(result))

func _promise(id: String, count: int, until_day: int) -> void:
	state.military_cohorts[id]["civilian_promises"] = [{"count": count, "until_day": until_day,
		"reason": "Promised not to fight", "proposal_id": "release:" + id}]

func test_partial_release_restricts_source_after_conquest_and_json() -> void:
	assert_false(_recruit("source", 60).has("error"))
	_release("source", 10)
	_promise("source", 10, 0)
	MapOwnership.set_owner(repo, state, province, repo.resolve_realm("raider_realm"), "Test conquest")
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	assert_eq(MilitaryPopulation.occupied(state, province, "rural_population"), 50)
	assert_eq(MilitaryPopulation.available(repo, state, province, "rural_population"), 940, "1000 residents - 50 serving - 10 promised civilians")
	assert_eq(int(WorldLedger.value_of(repo, state, MilitaryPopulation.path(province, "rural_population"))), 1000)
	assert_eq(int(state.military_cohorts["source"]["released"]), 10)
	assert_true(_recruit("too_many", 941).has("error"))
	assert_false(_recruit("remaining", 940).has("error"))
	assert_eq(MilitaryPopulation.available(repo, state, province, "rural_population"), 0)
	assert_eq(state.military_cohorts["source"]["civilian_promises"][0]["count"], 10)

func test_expiry_is_inclusive_and_zero_or_expired_promises_do_not_reserve_people() -> void:
	assert_false(_recruit("source", 60).has("error"))
	_release("source", 10)
	_promise("source", 10, state.absolute_day())
	assert_eq(MilitaryPopulation.available(repo, state, province, "rural_population"), 940)
	state.day += 1
	assert_eq(MilitaryPopulation.available(repo, state, province, "rural_population"), 950)
	_promise("source", 0, 0)
	assert_eq(MilitaryPopulation.available(repo, state, province, "rural_population"), 950)

func test_named_promise_blocks_reenlistment_pool_and_appointment() -> void:
	assert_false(_recruit("old_officer", 1, officer).has("error"))
	_release("old_officer", 1)
	_promise("old_officer", 1, 0)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)
	var before := SaveLoad.state_hash(state)
	assert_string_contains(MilitaryCommanders.candidate_error(repo, state, officer), "Promised not to fight")
	assert_string_contains(MilitaryCommanders.candidate_error(repo, state, officer), "indefinite")
	assert_true(_recruit("new_officer", 1, officer).has("error"))
	assert_eq(SaveLoad.state_hash(state), before, "refused reenlistment changes nothing")
	var arm := String(repo.commanders[officer]["unit_kinds"]).split("|")[0]
	assert_false(RecruitmentSystem.available_commanders(repo, state, arm).has(officer))
	state.military_cohorts["old_officer"]["civilian_promises"] = []
	assert_false(_recruit("new_officer", 1, officer).has("error"))
	_promise("old_officer", 1, 0)
	before = SaveLoad.state_hash(state)
	var result := MilitaryCommanders.assign(repo, state, code, officer, "Test appointment")
	assert_true(result.has("error"))
	assert_string_contains(String(result.get("error", "")), "Promised not to fight")
	assert_eq(SaveLoad.state_hash(state), before)

func test_named_expiry_and_zero_promises_restore_service_eligibility() -> void:
	assert_false(_recruit("old_officer", 1, officer).has("error"))
	_release("old_officer", 1)
	_promise("old_officer", 1, state.absolute_day())
	var refusal := MilitaryCommanders.candidate_error(repo, state, officer)
	assert_string_contains(refusal, "Promised not to fight")
	assert_string_contains(refusal, str(state.absolute_day()))
	state.day += 1
	assert_eq(MilitaryCommanders.candidate_error(repo, state, officer), "")
	_promise("old_officer", 0, 0)
	assert_eq(MilitaryCommanders.candidate_error(repo, state, officer), "")
	assert_false(_recruit("new_officer", 1, officer).has("error"))

func test_restrictions_filter_population_fields_and_optional_field() -> void:
	assert_false(_recruit("source", 60).has("error"))
	_release("source", 10)
	_promise("source", 10, 0)
	assert_eq(MilitaryPopulation.restricted(state, province, "rural_population"), 10)
	assert_eq(MilitaryPopulation.restricted(state, province, "urban_population"), 0)
	assert_eq(MilitaryPopulation.restricted(state, province), 10)
	assert_eq(MilitaryPopulation.restricted(state, "unknown"), 0)
	assert_eq(MilitaryPopulation.service_refusal(state, ""), "")
