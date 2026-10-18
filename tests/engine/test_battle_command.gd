extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func _person(id: String, martial: int, prestige: int) -> Character:
	var person := Character.new()
	person.id = id
	person.family_name = "Harrow"
	person.skills["sk_martial"] = martial
	person.attributes["prestige"] = prestige
	return person

func test_selection_and_valid_nomination() -> void:
	var state := GameState.new()
	state.rng = Rng.new(42)
	state.characters = {"A": _person("A", 16, 40), "B": _person("B", 15, 90), "C": _person("C", 16, 40)}
	var ids: Array[String] = ["C", "B", "A"]
	assert_eq(BattleCommand.select(state, ids, ""), "A")
	assert_eq(BattleCommand.select(state, ids, "B"), "B")
	assert_eq(BattleCommand.select(state, ids, "absent"), "")
	var empty: Array[String] = []
	assert_eq(BattleCommand.select(state, empty, ""), "")
	state.characters.A.flags.append("captured")
	assert_eq(BattleCommand.select(state, ids, "A"), "")
	assert_eq(BattleCommand.select(state, ids, ""), "C")

func test_reinforcement_keeps_available_incumbent() -> void:
	var state := GameState.new()
	state.rng = Rng.new(42)
	state.characters = {"A": _person("A", 16, 40), "D": _person("D", 20, 90)}
	var ids: Array[String] = ["A", "D"]
	assert_eq(BattleCommand.retain_or_select(state, ids, "A"), "A")
	state.characters.A.flags.append("dead")
	assert_eq(BattleCommand.retain_or_select(state, ids, "A"), "D")
	ids.erase("A")
	assert_eq(BattleCommand.retain_or_select(state, ids, "A"), "D")

func _assignment_fixture() -> Dictionary:
	var repo := SuiteData.repo()
	var state := GameState.new()
	state.rng = Rng.new(42)
	var realm := repo.resolve_realm("player_realm")
	state.characters = {"A": _person("A", 16, 40), "B": _person("B", 15, 90)}
	for person: Character in state.characters.values():
		person.kingdom = realm
	repo.commanders = {}
	for id: String in state.characters:
		repo.commanders[id] = {"character_id": id, "realm_slot": "player_realm", "eligible": "1", "unit_kinds": "infantry|fleet", "reserve_priority": "1"}
	for code: String in ["one", "two"]:
		state.army_roster[code] = {"regiment_code": code, "kingdom_code": realm, "infantry": 100, "is_naval": "0"}
		state.military_rosters[code] = {"commander_id": "", "cohort_ids": [code], "appointments": []}
		state.military_cohorts[code] = {"id": code, "unit_code": code, "identity": "noble", "family_name": "Harrow", "stage": "active", "initial": 5, "fit": 5, "wounded": 0, "captured_current": 0, "dead": 0, "released": 0, "source_province": "source", "source_population_field": "population_rural"}
	return {"repo": repo, "state": state}

func test_assignment_is_unique_and_same_family_members_can_serve() -> void:
	var fixture := _assignment_fixture()
	var repo: DataRepository = fixture.repo
	var state: GameState = fixture.state
	assert_false(BattleCommand.assign_unit(repo, state, "one", "A", "Appointed to first company").has("error"))
	var before := state.to_dict()
	assert_true(BattleCommand.assign_unit(repo, state, "two", "A", "Attempted duplicate appointment").has("error"))
	assert_eq(state.to_dict(), before)
	assert_false(BattleCommand.assign_unit(repo, state, "two", "B", "Appointed cousin to second company").has("error"))
	var total := 0
	var named := 0
	for cohort: Dictionary in state.military_cohorts.values():
		total += int(cohort.initial)
		if cohort.has("person_id"):
			named += 1
			assert_eq(cohort.initial, 1)
			assert_eq(cohort.family_name, "Harrow")
	assert_eq(total, 10, "Named commanders are carved out of the ten existing nobles")
	assert_eq(named, 2)
	assert_eq(state.military_rosters.one.appointments[0].reason, "Appointed to first company")

func test_wrong_realm_rulers_ineligible_and_no_noble_place_are_refused() -> void:
	var fixture := _assignment_fixture()
	var repo: DataRepository = fixture.repo
	var state: GameState = fixture.state
	state.characters.A.traits.append("crowned_head")
	assert_false(BattleCommand.eligible_for_unit(repo, state, "one", "A"))
	state.characters.A.traits.clear()
	repo.commanders.A.eligible = "0"
	assert_false(BattleCommand.eligible_for_unit(repo, state, "one", "A"))
	repo.commanders.A.eligible = "1"
	state.characters.A.kingdom = repo.resolve_realm("raider_realm")
	assert_false(BattleCommand.eligible_for_unit(repo, state, "one", "A"))
	state.characters.A.kingdom = repo.resolve_realm("player_realm")
	state.military_cohorts.one.family_name = "Other house"
	assert_true(BattleCommand.assign_unit(repo, state, "one", "A", "No family member in service").has("error"))
	assert_true(BattleCommand.assign_unit(repo, state, "two", "A", "").has("error"))

func test_authored_candidates_cover_both_realms_including_fleets_and_trains() -> void:
	var repo := SuiteData.repo()
	var state := GameState.new()
	state.rng = Rng.new(42)
	state.characters = CharacterFactory.build_roster(repo)
	state.army_roster = ArmySplit.split(repo).roster
	var realms: Array[String] = [repo.resolve_realm("player_realm"), repo.resolve_realm("raider_realm")]
	for code: String in state.army_roster:
		if not realms.has(String(state.army_roster[code].kingdom_code)):
			continue
		state.military_rosters[code] = {"cohort_ids": [code], "commander_id": "", "appointments": []}
		state.military_cohorts[code] = {"id": code, "unit_code": code, "identity": "noble", "family_name": "", "stage": "active", "initial": 1, "fit": 1, "wounded": 0, "captured_current": 0, "dead": 0, "released": 0}
	for realm: String in realms:
		var fleets := 0
		var trains := 0
		for code: String in state.military_rosters:
			var unit: Dictionary = state.army_roster[code]
			if String(unit.kingdom_code) == realm:
				fleets += 1 if String(unit.get("is_naval", "0")) == "1" else 0
				trains += 1 if String(unit.get("parent_code", "")) == "" and int(unit.get("artillery", 0)) > 0 else 0
		assert_gt(fleets, 0, "Realm fixture includes its fleets")
		assert_eq(trains, 1, "Realm fixture includes its pooled royal train")
	assert_eq(BattleCommand.ensure_assignments(repo, state, "Founding military appointments"), [])
	var appointed: Dictionary = {}
	for code: String in state.military_rosters:
		var id := String(state.military_rosters[code].commander_id)
		assert_ne(id, "", code)
		assert_false(appointed.has(id), code)
		appointed[id] = true
	var before := state.to_dict()
	assert_eq(BattleCommand.ensure_assignments(repo, state, "Repeated migration"), [])
	assert_eq(state.to_dict(), before, "Repeated initialization preserves identities and appointments")
