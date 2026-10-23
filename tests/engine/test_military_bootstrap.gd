extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Roster := preload("res://scripts/engine/military_roster.gd")
var repo: DataRepository
var state: GameState
var province: String

func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	state.military_cohorts.clear()
	state.military_rosters.clear()
	state.military_events.clear()
	state.military_migration.clear()
	state.army_roster.clear()
	state.regiments.clear()
	state.foes.clear()
	repo.balance["recruitment_eligible_permille"] = 1000
	repo.balance["army_noble_start_permille"] = 50
	repo.balance["army_noble_cap_permille"] = 100
	province = MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm"))[0]
	state.world[_path(province, "rural_population")] = 1000
	state.world[_path(province, "urban_population")] = 500
	repo.commanders = {"char_captain_hale": repo.commanders["char_captain_hale"].duplicate(true)}

func _path(origin: String, field: String) -> String:
	return "economy.provinces.%s.%s" % [origin, field]

func _source(origin: String, arm: String, count: int, crew: int) -> Dictionary:
	return {"regiment_code": "source_" + origin, "province_code": origin,
		"arm": arm, "equipment_count": count, "crew_per_element": crew}

func _unit(code: String, arm: String, count: int, parts: Array) -> Dictionary:
	return {"regiment_code": code, "kingdom_code": repo.resolve_realm("player_realm"),
		"province_code": province, "arm": arm, arm: str(count),
		"is_naval": "0", "source_parts": parts}

func _initialize() -> Dictionary:
	var path := "res://scripts/engine/military_bootstrap.gd"
	assert_true(FileAccess.file_exists(path), "campaign troops need a complete personnel initialization")
	if not FileAccess.file_exists(path):
		return {"error": "missing military bootstrap"}
	var service: RefCounted = load(path).new()
	return service.call("initialize", repo, state)

func _counts(field: String, value: String) -> int:
	var total := 0
	for cohort: Dictionary in state.military_cohorts.values():
		if cohort.get(field, "") == value:
			total += int(cohort["initial"])
	return total

func test_initial_cavalry_uses_personnel_and_weighted_population_origins() -> void:
	var arms := repo.world_table("military", "unit_types")
	arms["cavalry"]["crew"] = "2"
	arms["cavalry"]["rural_rate"] = "0.12"
	arms["cavalry"]["urban_rate"] = "0.03"
	state.army_roster["u"] = _unit("u", "cavalry", 90, [_source(province, "cavalry", 90, 2)])
	assert_false(_initialize().has("error"))
	assert_eq(Roster.fit(state, "u"), 180)
	assert_eq(_counts("source_population_field", "rural_population"), 160)
	assert_eq(_counts("source_population_field", "urban_population"), 20)
	assert_eq(_counts("identity", "noble"), 9)
	assert_eq(int(state.army_roster["u"]["cavalry"]), 90)
	assert_eq(state.military_rosters.get("u", {}).get("commander_id", ""), "char_captain_hale")
	assert_eq(int(WorldLedger.value_of(repo, state, _path(province, "rural_population"))), 1000)
	assert_eq(int(WorldLedger.value_of(repo, state, _path(province, "urban_population"))), 500)

func test_pooled_train_retains_each_contributing_province() -> void:
	var second := ""
	for p: String in repo.provinces:
		if p != province:
			second = p
			break
	state.world[_path(second, "urban_population")] = 1000
	var arms := repo.world_table("military", "unit_types")
	arms["artillery"]["crew"] = "8"
	arms["artillery"]["rural_rate"] = "0"
	arms["artillery"]["urban_rate"] = "0.01"
	state.army_roster["train"] = _unit("train", "artillery", 5,
		[_source(province, "artillery", 2, 8), _source(second, "artillery", 3, 8)])
	assert_false(_initialize().has("error"))
	assert_eq(Roster.fit(state, "train"), 40)
	assert_eq(_counts("source_province", province), 16)
	assert_eq(_counts("source_province", second), 24)
	assert_eq(_counts("source_population_field", "rural_population"), 0)

func test_no_partial_people_when_commander_pool_is_short() -> void:
	state.army_roster["a"] = _unit("a", "infantry", 100, [_source(province, "infantry", 100, 1)])
	state.army_roster["b"] = _unit("b", "infantry", 100, [_source(province, "infantry", 100, 1)])
	var before := SaveLoad.state_hash(state)
	assert_true(_initialize().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_repeated_initialization_after_json_does_not_enlist_twice() -> void:
	state.army_roster["u"] = _unit("u", "infantry", 100, [_source(province, "infantry", 100, 1)])
	assert_false(_initialize().has("error"))
	var before := SaveLoad.state_hash(state)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_false(_initialize().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	assert_eq(Roster.fit(state, "u"), 100)

func test_every_real_unit_has_a_unique_eligible_commander_without_extra_heads() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	assert_false(_initialize().has("error"))
	assert_eq(state.military_rosters.size(), state.army_roster.size())
	var assigned: Dictionary = {}
	for code: String in state.army_roster:
		var person := String(state.military_rosters.get(code, {}).get("commander_id", ""))
		if person != "":
			assert_false(assigned.has(person), "no commander can occupy two military units")
			assigned[person] = true
		assert_lte(Roster.living(state, code), int(repo.bal("army_living_cap_men")))
	assert_eq(assigned.size(), ArmySplit.opening_sources(repo)["roster"].size())

func test_invalid_origin_and_partial_initialization_are_atomic() -> void:
	state.army_roster["u"] = _unit("u", "infantry", 100, [_source("unknown", "infantry", 100, 1)])
	var before := SaveLoad.state_hash(state)
	assert_true(_initialize().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	state.military_rosters["partial"] = {"cohort_ids": []}
	before = SaveLoad.state_hash(state)
	assert_true(_initialize().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_completed_marker_cannot_hide_missing_cohort() -> void:
	state.army_roster["u"] = _unit("u", "infantry", 100, [_source(province, "infantry", 100, 1)])
	assert_false(_initialize().has("error"))
	var ids: Array = state.military_rosters["u"]["cohort_ids"]
	state.military_cohorts.erase(ids[0])
	var before := SaveLoad.state_hash(state)
	assert_true(_initialize().has("error"), "a marker is not proof of a complete roster")
	assert_eq(SaveLoad.state_hash(state), before)

func test_opening_partitions_personnel_before_capped_mobilization() -> void:
	state.world[_path(province, "rural_population")] = 10000
	state.world[_path(province, "urban_population")] = 10000
	for count: int in [2500, 1001]:
		state.army_roster = {"u": _unit("u", "infantry", count, [_source(province, "infantry", count, 1)])}
		var capital: Dictionary = repo.burgs[repo.kingdoms[repo.resolve_realm("player_realm")].capital_burg]
		state.army_roster["u"].merge({"x": capital.x, "y": capital.y, "camp_town": "", "is_royal": "1"})
		state.military_cohorts.clear()
		state.military_rosters.clear()
		state.military_events.clear()
		state.military_migration.clear()
		var result := _initialize()
		assert_false(result.has("error"), str(result))
		var living: Array = []
		var officers := 0
		for code: String in state.army_roster:
			living.append(Roster.living(state, code))
			if state.military_rosters[code].get("commander_id", "") != "": officers += 1
		assert_eq(living, [625, 625, 625, 625] if count == 2500 else [501, 500])
		assert_eq(_counts("source_province", province), count)
		assert_eq(officers, 1, "partition never invents officers or extra people")

func test_opening_bad_provenance_refuses_without_reservations() -> void:
	for parts: Array in [[_source(province, "infantry", 99, 1)], [_source(province, "infantry", 100, 2)]]:
		state.army_roster = {"u": _unit("u", "infantry", 100, parts)}
		var before := SaveLoad.state_hash(state)
		assert_true(_initialize().has("error"))
		assert_eq(SaveLoad.state_hash(state), before)

func test_opening_never_consolidates_below_cap_sources() -> void:
	repo.commanders = SuiteData.repo().commanders
	state.army_roster = {"u": _unit("u", "infantry", 400, [_source(province, "infantry", 400, 1)]),
		"v": _unit("v", "infantry", 400, [_source(province, "infantry", 400, 1)])}
	assert_false(_initialize().has("error"))
	assert_eq(state.army_roster.size(), 2)
	assert_eq(Roster.living(state, "u"), 400)
	assert_eq(Roster.living(state, "v"), 400)
