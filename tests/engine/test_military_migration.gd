extends GutTest
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")
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


# Main-save acceptance uses the canonical import and reorganization boundaries.
func _compat_ensure(data: DataRepository, saved: GameState) -> Dictionary:
	var result := Bootstrap.migrate(data, saved)
	if result.has("error"):
		return result
	return MilitaryReorganization.reconcile(data, saved)

func _compat_fixture(elements: int = 200, crew: int = 2) -> Dictionary:
	var repo := SuiteData.repo()
	var state := GameState.new()
	state.rng = Rng.new(7)
	state.metrics = GameState.from_dict(state.to_dict()).metrics
	var provinces := repo.world_table("economy", "provinces").keys()
	provinces.sort()
	var province: String = provinces[0]
	state.world["economy.provinces.%s.rural_population" % province] = 1000
	state.world["economy.provinces.%s.urban_population" % province] = 500
	state.army_roster = {"saved": {"regiment_code": "saved", "kingdom_code": repo.resolve_realm("player_realm"),
		"province_code": province, "parent_code": "ancestor", "is_naval": "0", "is_royal": "0",
		"cavalry": str(elements), "x": "0", "y": "0", "camp_town": "", "label": "Saved"}}
	var land: Array = ArmySplit.roster_of(repo).values().filter(func(r: Dictionary) -> bool: return String(r.get("is_naval", "0")) != "1")
	state.army_roster.saved.x = String(land[0].x)
	state.army_roster.saved.y = String(land[0].y)
	state.army_roster.saved.camp_town = String(land[0].get("camp_town", ""))
	repo.world_table("military", "unit_types")["cavalry"]["crew"] = str(crew)
	state.army_roster.saved.source_parts = [{"regiment_code": "ancestor", "province_code": province, "arm": "cavalry", "equipment_count": elements, "crew_per_element": crew}]
	state.characters = CharacterFactory.build_roster(repo)
	repo.balance["recruitment_eligible_permille"] = 1000
	state.regiments = {"saved": {"dead": 10, "wounded": 20, "deserted": 5, "supplies": 101}}
	return {"repo": repo, "state": state, "province": province}

func test_main_crew_and_old_losses_are_personnel_once() -> void:
	var f := _compat_fixture()
	var s: GameState = f.state
	assert_false(_compat_ensure(f.repo, s).has("error"))
	assert_eq(MilitaryRoster.fit(s, "saved"), 365)
	assert_eq(Personnel.count(s, "saved", "wounded"), 20)
	assert_eq(Personnel.count(s, "saved", "dead"), 10)
	assert_eq(Personnel.count(s, "saved", "released"), 5)
	assert_eq(s.army_roster.saved.cavalry, "200")
	assert_eq(s.world["economy.provinces.%s.rural_population" % f.province], 1000)
	var snapshot := s.to_dict()
	assert_false(_compat_ensure(f.repo, s).has("error"))
	assert_eq(s.to_dict(), snapshot)
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(snapshot)))
	assert_false(_compat_ensure(f.repo, restored).has("error"))
	for key: String in snapshot:
		assert_eq(restored.to_dict()[key], snapshot[key], key)

func test_main_weighted_sources_are_160_rural_20_urban() -> void:
	var f := _compat_fixture(90, 2)
	var s: GameState = f.state
	s.regiments.saved = {}
	assert_false(_compat_ensure(f.repo, s).has("error"))
	assert_eq(MilitaryPopulation.occupied(s, f.province, "rural_population"), 160)
	assert_eq(MilitaryPopulation.occupied(s, f.province, "urban_population"), 20)

func test_main_split_preserves_first_id_inventory_and_typed_references() -> void:
	var f := _compat_fixture(601, 2)
	var s: GameState = f.state
	s.battles = [{"att": ["saved"], "def": [], "id": 7, "ended": true}]
	s.war_drafts = {"saved": {"order": "halt"}}
	s.law_in_force = {"unit:saved": {"camp": {"value": "on"}}}
	s.supply_lines = {"saved": {"fee_milli": 13, "m_bought": {"house": 7}}}
	s.couriers = [{"id": 2, "target": "saved", "orders": [{"action_code": "ARMY_HALT", "regiment": "saved"}], "kind": "ordinary"}]
	s.regiments.saved.order_id = 9
	s.regiments.saved.inventory = {"swords": 11}
	s.regiments.saved.inventories = {"grain": 13}
	s.regiments.saved.reserve_milli = 17
	s.metrics.treasury = 87
	s.ai_hosts = {"host": {"unit_codes": ["saved"], "target_id": "town"}}
	s.war_plans.strokes = {"front": {"codes": ["saved"], "name": "saved"}}
	assert_false(_compat_ensure(f.repo, s).has("error"))
	var ids: Array = s.military_migration.get("living_unit_mapping", {}).get("saved", ["saved"])
	assert_eq(ids.size(), 2)
	assert_eq(ids[0], "saved")
	assert_eq(int(s.army_roster[ids[0]].cavalry), 301)
	assert_eq(int(s.army_roster[ids[1]].cavalry), 300)
	assert_eq(s.battles[0].att, ["saved"], "ended battle is immutable history")
	assert_eq(s.ai_hosts.host.unit_codes, ids)
	assert_eq(s.ai_hosts.host.target_id, "town")
	assert_eq(s.war_plans.strokes.front.codes, ids)
	assert_eq(s.war_plans.strokes.front.name, "saved")
	assert_eq(s.war_drafts.size(), 1)
	assert_eq(s.law_in_force["unit:" + ids[1]], s.law_in_force["unit:" + ids[0]], "split inherits saved laws")
	s.law_in_force["unit:" + ids[1]].camp.value = "off"
	assert_eq(s.law_in_force["unit:" + ids[0]].camp.value, "on", "each descendant keeps independent law history")
	assert_eq(s.supply_lines[ids[0]].fee_milli + s.supply_lines[ids[1]].fee_milli, 13)
	assert_eq(s.regiments[ids[0]].supplies + s.regiments[ids[1]].supplies, 101)
	assert_eq(s.regiments[ids[0]].inventory.swords, 6, "594:593 living people split eleven swords6:5")
	assert_eq(s.regiments[ids[1]].inventory.swords, 5)
	assert_eq(s.regiments[ids[0]].inventories.grain + s.regiments[ids[1]].inventories.grain, 13)
	assert_eq(s.regiments[ids[0]].reserve_milli + s.regiments[ids[1]].reserve_milli, 17)
	assert_eq(s.couriers.size(), 1, "the original paid rider remains singular")
	assert_false(s.couriers[0].has("recipient_queue"))
	assert_false(s.regiments[ids[1]].has("order_id"))
	assert_eq(s.metrics.treasury, 87)
	assert_eq(MilitaryRoster.fit(s, ids[0]) + MilitaryRoster.fit(s, ids[1]), 1167)

func test_main_transaction_preserves_cursor_then_reorganizes_once() -> void:
	var f := _compat_fixture(301, 2)
	var s: GameState = f.state
	s.day_resolution = {"phase": "battles", "cursor": 1, "participants": ["saved"]}
	var transaction := s.day_resolution.duplicate(true)
	assert_false(_compat_ensure(f.repo, s).has("error"))
	assert_eq(s.army_roster.keys(), ["saved"])
	assert_eq(s.day_resolution, transaction)
	assert_true(bool(s.military_migration.get("organization_pending", false)))
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_false(_compat_ensure(f.repo, restored).has("error"))
	assert_eq(restored.day_resolution, transaction)
	s.day_resolution = {}
	restored.day_resolution = {}
	assert_false(_compat_ensure(f.repo, s).has("error"))
	assert_false(_compat_ensure(f.repo, restored).has("error"))
	for key: String in s.to_dict():
		assert_eq(restored.to_dict()[key], s.to_dict()[key], key)
	assert_eq(s.military_migration.get("organization_version", 0), 1)
	assert_false(bool(s.military_migration.get("organization_pending", false)))

func test_main_handcomputed_large_split_preserves_capacity_and_nobles() -> void:
	var f := _compat_fixture(1268, 2)
	var s: GameState = f.state
	s.regiments.saved = {}
	assert_false(_compat_ensure(f.repo, s).has("error"))
	var ids: Array = s.military_migration.get("living_unit_mapping", {}).get("saved", ["saved"])
	var elements: Array = []
	var people: Array = []
	for id: String in ids:
		elements.append(int(s.army_roster[id].cavalry))
		people.append(MilitaryRoster.fit(s, id))
		var nobles := 0
		for cohort_id: String in s.military_rosters[id].cohort_ids:
			var cohort: Dictionary = s.military_cohorts[cohort_id]
			if cohort.get("person_id", "") != "": nobles += int(cohort.fit)
		assert_eq(nobles, 1 if id == "saved" else 0, id)
	assert_eq(elements, [317, 317, 317, 317])
	assert_eq(people, [634, 634, 634, 634])

func test_main_invalid_crew_and_small_remnant_do_not_drop_equipment() -> void:
	var f := _compat_fixture(1, 0)
	var s: GameState = f.state
	assert_true(_compat_ensure(f.repo, s).has("error"))
	assert_eq(s.army_roster.saved.cavalry, "1")
	assert_true(s.military_cohorts.is_empty())
	f = _compat_fixture(1, 2)
	s = f.state
	s.regiments.saved = {"wounded": 1}
	assert_false(_compat_ensure(f.repo, s).has("error"))
	assert_eq(MilitaryRoster.fit(s, "saved"), 1)
	assert_eq(Personnel.count(s, "saved", "wounded"), 1)
	assert_eq(s.army_roster.saved.cavalry, "1")

func test_main_legacy_train_estimates_saved_garrison_once_and_records_it() -> void:
	for pending: bool in [false, true]:
		var f := _compat_fixture()
		var s: GameState = f.state
		f.repo.world_table("military", "unit_types").artillery.crew = "8"
		var train: Dictionary = s.army_roster.saved.duplicate(true)
		train.regiment_code = "old_train"
		train.cavalry = "0"
		train.artillery = "2"
		train.erase("source_parts")
		s.army_roster.old_train = train
		s.regiments.old_train = {"dead": 2, "wounded": 3, "deserted": 1, "captured_current": 1, "supplies": 17}
		s.metrics.treasury = 87
		var world := s.world.duplicate(true)
		if pending: s.day_resolution = {"phase": "battles", "cursor": 1}
		var result := _compat_ensure(f.repo, s)
		assert_false(result.has("error"))
		if result.has("error"): return
		if pending: assert_eq(s.day_resolution, {"phase": "battles", "cursor": 1})
		assert_eq(MilitaryRoster.fit(s, "old_train"), 9)
		for pair: Array in [["dead", 2], ["wounded", 3], ["released", 1], ["captured_current", 1]]:
			assert_eq(Personnel.count(s, "old_train", pair[0]), pair[1])
		var event: Dictionary = s.military_events[s.military_migration.event_id]
		assert_true(String(event.request.reason).contains("estimated"))
		assert_true(String(event.request.reason).contains(f.province))
		var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
		assert_false(_compat_ensure(f.repo, restored).has("error"))
		if pending:
			s.day_resolution = {}
			restored.day_resolution = {}
			assert_false(_compat_ensure(f.repo, s).has("error"))
			assert_false(_compat_ensure(f.repo, restored).has("error"))
		var part: Dictionary = s.army_roster.old_train.source_parts[0]
		assert_eq(part.province_code, f.province)
		assert_eq(part.origin_basis, "estimated_saved_garrison")
		assert_true(String(part.origin_reason).contains(f.province))
		assert_true(String(s.military_migration.get("organization_reason", "")).contains("estimated"))
		assert_eq(part.equipment_count, 2)
		assert_eq(part.crew_per_element, 8)
		assert_eq(s.army_roster.old_train.artillery, "2")
		assert_eq(s.regiments.old_train.supplies, 17)
		assert_eq(s.metrics.treasury, 87)
		assert_eq(s.world, world, "saved deaths and estimated service do not debit population again")
		assert_eq(s.military_events[s.military_migration.event_id], event)
		for key: String in s.to_dict(): assert_eq(restored.to_dict()[key], s.to_dict()[key], key)
		var snapshot := s.to_dict()
		assert_false(_compat_ensure(f.repo, s).has("error"))
		assert_eq(s.to_dict(), snapshot)

func test_main_legacy_train_without_valid_saved_garrison_remains_a_conflict() -> void:
	var f := _compat_fixture()
	var s: GameState = f.state
	s.army_roster.saved.cavalry = "0"
	s.army_roster.saved.artillery = "2"
	s.army_roster.saved.province_code = ""
	s.army_roster.saved.camp_town = ""
	s.army_roster.saved.erase("source_parts")
	var before := s.army_roster.duplicate(true)
	assert_true(_compat_ensure(f.repo, s).has("error"))
	assert_true(s.military_migration.is_empty(), "failed import publishes no markers")
	assert_eq(s.army_roster, before)
	assert_true(s.military_cohorts.is_empty())

func test_main_authored_multi_source_train_never_moves_all_crew_to_capital() -> void:
	var f := _compat_fixture(0, 2)
	var s: GameState = f.state
	var provinces: Array = f.repo.world_table("economy", "provinces").keys()
	provinces.sort()
	var other: String = provinces[1]
	s.world["economy.provinces.%s.rural_population" % other] = 1000
	s.world["economy.provinces.%s.urban_population" % other] = 500
	var row: Dictionary = s.army_roster.saved
	row.artillery = "2"
	f.repo.world_table("military", "unit_types").artillery.crew = "8"
	row.source_parts = [{"regiment_code": "a", "province_code": f.province, "arm": "artillery", "equipment_count": 1, "crew_per_element": 8},
		{"regiment_code": "b", "province_code": other, "arm": "artillery", "equipment_count": 1, "crew_per_element": 8}]
	s.regiments.saved = {}
	assert_false(_compat_ensure(f.repo, s).has("error"))
	assert_eq(MilitaryRoster.fit(s, "saved"), 16)
	assert_eq(MilitaryPopulation.occupied(s, f.province), 8)
	assert_eq(MilitaryPopulation.occupied(s, other), 8)
	assert_eq(s.army_roster.saved.artillery, "2")
	assert_false(String(s.military_events[s.military_migration.event_id].request.reason).contains("estimated"))
	for part: Dictionary in s.army_roster.saved.source_parts:
		assert_false(part.has("origin_basis"), "recorded source provenance stays recorded")

func test_main_new_campaign_all_player_and_raider_units_have_one_counted_commander() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 71)
	assert_eq(state.military_migration.get("organization_version", 0), 1)
	var named: Dictionary = {}
	var checked := 0
	for code: String in state.army_roster:
		var row: Dictionary = state.army_roster[code]
		if String(row.kingdom_code) not in [repo.resolve_realm("player_realm"), repo.resolve_realm("raider_realm")]: continue
		checked += 1
		var roster: Dictionary = state.military_rosters.get(code, {})
		var commander := String(roster.get("commander_id", ""))
		assert_ne(commander, "", code)
		assert_false(named.has(commander), code)
		named[commander] = true
		var matches := 0
		for id: String in roster.get("cohort_ids", []):
			var cohort: Dictionary = state.military_cohorts[id]
			if String(cohort.get("person_id", "")) == commander:
				matches += 1
				assert_eq(cohort.identity, "noble")
				assert_eq(cohort.initial, 1)
		assert_eq(matches, 1, code)
	assert_gt(checked, 0)

func test_main_living_halves_are_independent_of_equipment_crews() -> void:
	var f := _compat_fixture(7, 8)
	var s: GameState = f.state
	f.repo.balance["army_living_cap_men"] = 25
	s.regiments.saved = {}
	assert_false(_compat_ensure(f.repo, s).has("error"))
	var elements: Array = []
	var people: Array = []
	for id: String in s.military_migration.get("living_unit_mapping", {}).get("saved", ["saved"]):
		elements.append(int(s.army_roster[id].cavalry))
		people.append(MilitaryRoster.fit(s, id))
	assert_eq(elements, [2, 2, 2, 1])
	assert_eq(people, [14, 14, 14, 14])

func test_main_one_ship_crew_hundred_preserves_one_ship_and_personnel() -> void:
	var f := _compat_fixture(0, 2)
	var s: GameState = f.state
	f.repo.world_table("military", "unit_types")["fleet"] = {"crew": "100", "rural_rate": "0.12", "urban_rate": "0.03"}
	s.army_roster.saved.is_naval = "1"
	s.army_roster.saved.fleet = "1"
	s.army_roster.saved.source_parts = [{"regiment_code": "ancestor", "province_code": f.province, "arm": "fleet", "equipment_count": 1, "crew_per_element": 100}]
	s.regiments.saved = {}
	assert_false(_compat_ensure(f.repo, s).has("error"))
	assert_eq(s.army_roster.saved.fleet, "1")
	assert_eq(MilitaryRoster.fit(s, "saved"), 100)
	var snapshot := s.to_dict()
	assert_false(_compat_ensure(f.repo, s).has("error"))
	assert_eq(s.to_dict(), snapshot)


func test_main_pending_supply_metadata_and_desertion_remainder_are_conserved() -> void:
	var f := _compat_fixture(601, 2)
	var state: GameState = f.state
	state.supply_lines = {"saved": {"pending": {"town": "depot", "rate": 750, "order_id": 7}}}
	state.regiments.saved.desert_rem = 13
	state.couriers = [{"id": 7, "target": "saved", "orders": [{"action_code": "SUPPLY_POINT_SET"}]}]
	assert_false(_compat_ensure(f.repo, state).has("error"))
	var remainder := 0
	for code: String in state.military_migration.get("living_unit_mapping", {}).get("saved", ["saved"]):
		remainder += int(state.regiments[code].desert_rem)
		assert_eq(state.couriers.size(), 1)
		if code == "saved":
			assert_eq(state.supply_lines[code].pending, {"town": "depot", "rate": 750, "order_id": 7})
		else:
			assert_false(state.supply_lines[code].has("pending"))
		assert_false(state.couriers[0].has("recipient_queue"))
	assert_eq(remainder, 13)

func _main_v7_save() -> Dictionary:
	_legacy()
	assert_false(_migrate().has("error"))
	var saved := state.to_dict()
	saved.version = 7
	saved.erase("military_migration")
	saved.military_organization_version = 1
	saved.military_migration_pending = false
	saved.military_unit_aliases = {"ancestor": ["old_unit"]}
	saved.military_conflicts = []
	for roster: Dictionary in saved.military_rosters.values():
		roster.erase("commander_cohort_id")
	for field: String in ["military_rosters", "military_cohorts", "military_events"]:
		saved[field] = GameState._encode_values(saved[field])
	return saved

func test_main_v7_import_preserves_identity_receipts_and_completed_organization() -> void:
	var saved := _main_v7_save()
	var cohort_id := ""
	for id: String in saved.military_cohorts:
		if int(GameState._decode_values(saved.military_cohorts[id].fit)) >= 10 and not saved.military_cohorts[id].has("person_id"):
			cohort_id = id
			break
	assert_ne(cohort_id, "")
	var changes := [{"cohort_id": cohort_id, "from": "fit", "to": "dead", "count": 10}]
	var receipt := {"kind": "transition", "payload": changes, "reason": "recorded battle loss", "tick": 1}
	saved.military_events["saved-loss"] = GameState._encode_values(receipt)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(saved)))
	var equipment: Dictionary = GameState._whole(state.army_roster)
	var cohorts := state.military_cohorts.duplicate(true)
	var treasury: float = state.metrics.treasury
	var result := _migrate()
	assert_false(result.has("error"), str(result))
	if result.has("error"): return
	assert_eq(state.army_roster, equipment)
	assert_eq(state.military_cohorts, cohorts, "derive appointment reference without enlisting another officer")
	assert_false(state.military_migration.get("organization_pending", true))
	assert_eq(state.military_migration.get("unit_mapping"), {"ancestor": ["old_unit"]})
	assert_eq(state.metrics.treasury, treasury)
	var before := state.to_dict()
	assert_false(Roster.transition(repo, state, "saved-loss", changes, "recorded battle loss").has("error"))
	assert_eq(state.to_dict(), before)
	changes[0].count = 11
	assert_true(Roster.transition(repo, state, "saved-loss", changes, "recorded battle loss").has("error"))
	assert_eq(state.to_dict(), before)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_false(_migrate().has("error"))
	for key: String in before:
		assert_eq(state.to_dict()[key], before[key], key)

func test_main_v7_malformed_import_does_not_publish_partial_conversion() -> void:
	var saved := _main_v7_save()
	saved.military_cohorts.values()[0].initial = "i999999"
	state = GameState.from_dict(saved)
	var before := state.to_dict()
	assert_true(_migrate().has("error"))
	assert_eq(state.to_dict(), before)

func test_main_v7_active_battle_import_resumes_engagement_without_replaying_round() -> void:
	repo = SuiteData.repo()
	state = Scenario.contact(repo, 10)
	BattleSystem.prepare_day(repo, state)
	var battle: Dictionary = state.battles[0]
	battle.rounds = 2
	battle.last_resolved_day = 9
	for field: String in ["actions", "parley", "formations"]:
		battle.erase(field)
	var battle_id := int(battle.id)
	var saved := state.to_dict()
	saved.erase("military_migration")
	saved.military_organization_version = 1
	saved.military_migration_pending = false
	saved.military_unit_aliases = {}
	saved.military_conflicts = []
	for roster: Dictionary in saved.military_rosters.values():
		roster.erase("commander_cohort_id")
	for field: String in ["military_rosters", "military_cohorts", "military_events"]:
		saved[field] = GameState._encode_values(saved[field])
	var tx := DayResolution.begin(10, false, 10)
	tx.protocol_version = 3
	tx.substep_protocol_version = 3
	tx.substep_order = DayResolution.LEGACY_SUBSTEP_ORDER.duplicate()
	tx.phase = "FIXED_TACTICAL_SUBSTEPS"
	tx.phase_cursor = DayResolution.PHASES.find(tx.phase)
	tx.substep_index = 6
	tx.processed_battle_ids = [battle_id]
	saved.day_resolution = GameState._encode_values(tx)
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(saved)))
	var live := state.regiments.duplicate(true)
	var foes := state.foes.duplicate(true)
	var cursor := state.day_resolution.duplicate(true)
	var rng := state.rng.to_dict()
	var result := _migrate()
	assert_false(result.has("error"), str(result))
	if result.has("error"): return
	var imported: Dictionary = state.battles[0]
	assert_eq(BattleOrders.kind(imported, "att"), "attack", "saved main engagement retains its active fighting default")
	assert_eq(BattleOrders.kind(imported, "def"), "hold")
	assert_ne(String(imported.actions.att.reason), "")
	assert_ne(String(imported.actions.def.reason), "")
	assert_true(imported.has("parley"))
	assert_true(imported.has("formations"))
	for key: String in battle:
		assert_eq(imported[key], battle[key], key)
	assert_eq(state.regiments, live, "import spends no carried supply or movement")
	assert_eq(state.foes, foes, "foreign carried supply and movement are also preserved")
	assert_eq(state.day_resolution, cursor, "processed battle and substep cursors remain authoritative")
	assert_eq(state.rng.to_dict(), rng)
	var canonical := state.to_dict()
	state = GameState.from_dict(JSON.parse_string(JSON.stringify(canonical)))
	assert_false(_migrate().has("error"))
	assert_eq(state.to_dict(), canonical)
	var engine := TickEngine.new(repo)
	var foe: String = state.battles[0].att[0]
	var food_before := int(state.foes[foe].supplies)
	assert_eq(engine.resolve_day(state).status, "complete")
	assert_eq(int(state.foes[foe].supplies), food_before, "host-less contact fixture spends no enemy meal or replayed prior attack supply cost")
	assert_eq(int(state.battles[0].rounds), 2, "the already processed saved round never replays")
	assert_eq(state.day, 11)
	var before_next: Dictionary = state.military_cohorts.duplicate(true)
	var next_day := engine.resolve_day(state)
	assert_eq(next_day.status, "complete")
	assert_eq(int(state.battles[0].rounds), 3, "the next legal day actually engages")
	assert_ne(state.military_cohorts, before_next, "engagement applies its actual personnel losses")

func test_main_v7_malformed_receipt_refuses_before_publishing_any_candidate() -> void:
	var saved := _main_v7_save()
	var cohort_id := ""
	for id: String in saved.military_cohorts:
		if int(GameState._decode_values(saved.military_cohorts[id].fit)) > 0:
			cohort_id = id
			break
	assert_ne(cohort_id, "")
	var valid_request := {"kind": "transition", "changes": [
		{"cohort_id": cohort_id, "from": "fit", "to": "dead", "count": 1}], "reason": "saved loss"}
	for request: Variant in [valid_request, []]:
		var candidate: Dictionary = saved.duplicate(true)
		candidate.military_events.bad = GameState._encode_values({"request": request, "result": 42})
		state = GameState.from_dict(JSON.parse_string(JSON.stringify(candidate)))
		var before := state.to_dict()
		var before_hash := SaveLoad.state_hash(state)
		assert_true(_migrate().has("error"), "malformed receipt is refused at import")
		assert_eq(state.to_dict(), before, "no converted receipts, appointments or markers publish")
		assert_eq(SaveLoad.state_hash(state), before_hash)
