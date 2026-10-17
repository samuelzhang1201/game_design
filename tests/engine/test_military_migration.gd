extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Bootstrap := preload("res://scripts/engine/military_bootstrap.gd")
const Roster := preload("res://scripts/engine/military_roster.gd")
var repo: DataRepository
var state: GameState
var province: String
var second: String

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
	var provinces := MapOwnership.provinces_of(repo, state, repo.resolve_realm("player_realm"))
	province = provinces[0]
	second = provinces[1]
	for p: String in [province, second]:
		state.world[_path(p, "rural_population")] = 1000
		state.world[_path(p, "urban_population")] = 500
	repo.commanders = {"char_captain_hale": repo.commanders["char_captain_hale"].duplicate(true)}

func _path(p: String, field: String) -> String:
	return "economy.provinces.%s.%s" % [p, field]

func _unit(code: String, arm: String, count: int) -> Dictionary:
	return {"regiment_code": code, "kingdom_code": repo.resolve_realm("player_realm"),
		"province_code": province, "arm": arm, arm: str(count), "is_naval": "0",
		"source_parts": [{"regiment_code": "old_source", "province_code": province,
			"arm": arm, "equipment_count": count,
			"crew_per_element": int(repo.world_row("military", "unit_types", arm)["crew"])}]}

func _legacy() -> void:
	state.army_roster["old_unit"] = _unit("old_unit", "cavalry", 200)
	state.regiments["old_unit"] = {"dead": 10, "wounded": 20, "deserted": 5,
		"x_m": 123, "y_m": 456, "supplies": 237, "order": "march", "dest_x_m": 999,
		"route_m": [[123, 456], [999, 456]], "loot": {"grain": 17}}

func _migrate() -> Dictionary:
	var service := Bootstrap.new()
	assert_true(service.has_method("migrate"), "old saves need a personnel migration boundary")
	if not service.has_method("migrate"): return {"error": "migration unavailable"}
	return service.call("migrate", repo, state)

func _count(status: String, field := "", value := "") -> int:
	var total := 0
	for cohort: Dictionary in state.military_cohorts.values():
		if field == "" or cohort.get(field, "") == value: total += int(cohort[status])
	return total

func test_saved_cavalry_losses_are_people_not_equipment_crews() -> void:
	_legacy()
	var units := state.army_roster.duplicate(true)
	var live := state.regiments.duplicate(true)
	var world := state.world.duplicate(true)
	assert_false(_migrate().has("error"))
	assert_eq(_count("initial"), 400)
	assert_eq(_count("fit"), 365)
	assert_eq(_count("wounded"), 20)
	assert_eq(_count("dead"), 10)
	assert_eq(_count("released"), 5)
	assert_eq(state.army_roster, units)
	assert_eq(state.regiments, live)
	assert_eq(state.world, world, "historical deaths never get charged to population again")
	assert_eq(_count("initial", "person_id", "char_captain_hale"), 1)
	assert_eq(_count("fit", "person_id", "char_captain_hale"), 1)
	assert_true(bool(state.military_migration.get("organization_pending", false)))

func test_no_fit_survivor_means_no_invented_living_commander() -> void:
	_legacy()
	state.regiments["old_unit"].merge({"dead": 380, "wounded": 15, "deserted": 5}, true)
	assert_false(_migrate().has("error"))
	assert_eq(_count("fit"), 0)
	assert_eq(_count("dead"), 380)
	assert_eq(_count("initial"), 400)
	assert_eq(state.military_rosters.get("old_unit", {}).get("commander_id", ""), "")
	for cohort: Dictionary in state.military_cohorts.values(): assert_false(cohort.has("person_id"))

func test_pending_transaction_and_legacy_ids_are_untouched() -> void:
	_legacy()
	state.day_resolution = {"day": 9, "phase": "battles", "cursor": 2,
		"participants": ["old_unit"], "decision": {"acknowledged": false}}
	var journal := state.day_resolution.duplicate(true)
	var day := state.day
	var tick := state.tick
	assert_false(_migrate().has("error"))
	assert_eq(state.day_resolution, journal)
	assert_eq(state.day, day)
	assert_eq(state.tick, tick)
	assert_eq(state.army_roster.keys(), ["old_unit"])
	assert_true(bool(state.military_migration.get("organization_pending", false)))

func test_json_repeat_validates_without_reimporting_or_reappointing() -> void:
	_legacy()
	assert_false(_migrate().has("error"))
	var before := SaveLoad.state_hash(state)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_false(_migrate().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_partial_or_invalid_saved_ledger_refuses_atomically() -> void:
	_legacy()
	state.military_rosters["partial"] = {"cohort_ids": []}
	var before := SaveLoad.state_hash(state)
	assert_true(_migrate().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	state.military_rosters.clear()
	state.regiments["old_unit"]["dead"] = 401
	before = SaveLoad.state_hash(state)
	assert_true(_migrate().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	state.regiments["old_unit"]["dead"] = 1.5
	before = SaveLoad.state_hash(state)
	assert_true(_migrate().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_late_invalid_source_does_not_publish_earlier_cohorts_or_people() -> void:
	_legacy()
	state.characters.erase("char_captain_hale")
	var bad := _unit("zz_invalid", "infantry", 100)
	bad["source_parts"][0]["province_code"] = "unknown_province"
	state.army_roster["zz_invalid"] = bad
	var before := SaveLoad.state_hash(state)
	assert_true(_migrate().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_missing_source_uses_known_parent_not_current_station() -> void:
	_legacy()
	state.army_roster["old_unit"].erase("source_parts")
	state.army_roster["old_unit"]["parent_code"] = "saved_parent"
	var original := _unit("saved_parent", "cavalry", 400)
	original["province_code"] = second
	repo.world_table("military", "regiments")["saved_parent"] = original
	assert_false(_migrate().has("error"))
	assert_eq(_count("initial", "source_province", second), 400)
	assert_eq(_count("initial", "source_province", province), 0)
	assert_eq(int(state.army_roster["old_unit"]["cavalry"]), 200)
	assert_eq(state.army_roster["old_unit"]["province_code"], province)

func test_pooled_saved_guns_reconstruct_proportions_without_adding_pack_guns() -> void:
	var originals := repo.world_table("military", "regiments")
	originals.clear()
	var a := _unit("source_a", "artillery", 2)
	var b := _unit("source_b", "artillery", 3)
	b["province_code"] = second
	originals["source_a"] = a
	originals["source_b"] = b
	var train_code := ""
	for definition: Dictionary in repo.army_split:
		if bool(definition["pooled"]): train_code = repo.resolve_realm("player_realm") + "_" + String(definition["code_word"])
	var train := _unit(train_code, "artillery", 3)
	train.erase("source_parts")
	train["is_royal"] = "0"
	state.army_roster[train_code] = train
	assert_false(_migrate().has("error"))
	assert_eq(_count("initial"), 24)
	assert_eq(_count("initial", "source_province", province), 8)
	assert_eq(_count("initial", "source_province", second), 16)
	assert_eq(int(state.army_roster[train_code]["artillery"]), 3)

func test_unknown_source_refuses_instead_of_claiming_current_station() -> void:
	_legacy()
	state.army_roster["old_unit"].erase("source_parts")
	var before := SaveLoad.state_hash(state)
	assert_true(_migrate().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_population_conflict_keeps_soldiers_and_uses_documented_pack_weights() -> void:
	state.army_roster["old_unit"] = _unit("old_unit", "cavalry", 90)
	state.world[_path(province, "rural_population")] = 0
	state.world[_path(province, "urban_population")] = 0
	var opening := repo.world_row("economy", "provinces", province)
	opening["rural_population"] = "1000"
	opening["urban_population"] = "500"
	assert_false(_migrate().has("error"))
	assert_eq(_count("initial"), 180)
	assert_eq(_count("initial", "source_population_field", "rural_population"), 160)
	assert_eq(_count("initial", "source_population_field", "urban_population"), 20)
	assert_true(bool(state.military_migration.get("recruitment_blocked", false)))
	assert_gt((state.military_migration.get("conflicts", []) as Array).size(), 0)
	assert_eq(int(WorldLedger.value_of(repo, state, _path(province, "rural_population"))), 0)

func test_missing_pool_people_are_added_without_resetting_existing_characters() -> void:
	_legacy()
	state.characters.erase("char_captain_hale")
	state.characters["char_princess"].opinion = -73
	var princess: Dictionary = state.characters["char_princess"].to_dict()
	assert_false(_migrate().has("error"))
	assert_true(state.characters.has("char_captain_hale"))
	assert_eq(state.characters["char_princess"].to_dict(), princess)

func test_current_version_marker_does_not_hide_broken_personnel_conservation() -> void:
	_legacy()
	assert_false(_migrate().has("error"))
	if state.military_cohorts.is_empty(): return
	var id: String = state.military_cohorts.keys()[0]
	state.military_cohorts[id]["initial"] += 1
	var before := SaveLoad.state_hash(state)
	assert_true(_migrate().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_zero_eligible_urban_origin_uses_pack_weights_even_with_rural_residents() -> void:
	state.army_roster["old_unit"] = _unit("old_unit", "artillery", 5)
	state.world[_path(province, "urban_population")] = 0
	assert_false(_migrate().has("error"))
	assert_eq(_count("initial", "source_population_field", "urban_population"), 40)
	assert_eq(_count("initial", "source_population_field", "rural_population"), 0)
	assert_true(bool(state.military_migration.get("recruitment_blocked", false)))

func test_completed_marker_checks_origin_and_commander_integrity() -> void:
	_legacy()
	assert_false(_migrate().has("error"))
	if state.military_cohorts.is_empty(): return
	var saved := state.to_dict()
	var id: String = state.military_cohorts.keys()[0]
	state.military_cohorts[id]["source_province"] = "unknown_province"
	var before := SaveLoad.state_hash(state)
	assert_true(_migrate().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	state = GameState.from_dict(saved)
	state.military_rosters["old_unit"]["commander_id"] = "you"
	before = SaveLoad.state_hash(state)
	assert_true(_migrate().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_source_equipment_totals_cannot_hide_a_changed_arm_or_crew() -> void:
	_legacy()
	state.army_roster["old_unit"]["source_parts"][0]["crew_per_element"] = 1
	var before := SaveLoad.state_hash(state)
	assert_true(_migrate().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)
	state.army_roster["old_unit"]["source_parts"][0]["crew_per_element"] = 2
	state.army_roster["old_unit"]["source_parts"][0]["equipment_count"] = 199
	before = SaveLoad.state_hash(state)
	assert_true(_migrate().has("error"))
	assert_eq(SaveLoad.state_hash(state), before)

func test_actual_legacy_equipment_roster_migrates_all_realms_without_reorganizing() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	state.military_rosters.clear()
	state.military_cohorts.clear()
	state.military_events.clear()
	state.military_migration.clear()
	state.regiments.clear()
	state.foes.clear()
	# Old saves split cavalry equipment at the same cap as infantry.
	var cavalry := repo.world_row("military", "unit_types", "cavalry")
	var crew: Variant = cavalry["crew"]
	cavalry["crew"] = "1"
	ArmySplit.forget()
	state.army_roster = ArmySplit.split(repo)["roster"]
	cavalry["crew"] = crew
	ArmySplit.forget()
	var saved_ids := state.army_roster.keys()
	for unit: Dictionary in state.army_roster.values(): unit.erase("source_parts")
	var saved_equipment := state.army_roster.duplicate(true)
	var migrated := _migrate()
	assert_false(migrated.has("error"), str(migrated))
	if migrated.has("error"): return
	assert_eq(state.army_roster.keys(), saved_ids)
	var assigned: Dictionary = {}
	for code: String in saved_ids:
		assert_eq(Roster.fit(state, code), Roster.personnel_capacity(repo, saved_equipment[code]))
		var person := String(state.military_rosters.get(code, {}).get("commander_id", ""))
		assert_ne(person, "", code)
		assert_false(assigned.has(person), "one officer per saved unit")
		assigned[person] = true
		var after: Dictionary = state.army_roster[code].duplicate(true)
		after.erase("source_parts")
		assert_eq(after, saved_equipment[code], "only reconstructed provenance may be added")
	assert_true(bool(state.military_migration.get("organization_pending", false)))
