extends GutTest
const Commanders := preload("res://scripts/engine/military_commanders.gd")
const SuiteData := preload("res://tests/suite_data.gd")

func _needs(repo: DataRepository) -> Dictionary:
	var result: Dictionary = {}
	var cap := int(repo.bal("army_split_cap_men"))
	for row: Dictionary in repo.world_table("military", "regiments").values():
		var realm := String(row["kingdom_code"])
		if not result.has(realm): result[realm] = {"new": 0, "legacy": 0, "guns": false}
		if String(row["is_naval"]) == "1":
			result[realm]["new"] += 1
			result[realm]["legacy"] += 1
			continue
		if int(row["artillery"]) > 0: result[realm]["guns"] = true
		for arm: String in ["infantry", "archers", "cavalry"]:
			var crew := int(repo.world_row("military", "unit_types", arm)["crew"])
			var count := int(row[arm])
			result[realm]["new"] += ArmySplit.shares(count, cap / crew).size()
			# Older saves already split equipment at cap. Re-splitting must
			# preserve every old unit, not repool its elements into fewer units.
			for old_count: int in ArmySplit.shares(count, cap):
				result[realm]["legacy"] += ArmySplit.shares(old_count, cap / crew).size()
	for realm: String in result:
		if result[realm]["guns"]:
			result[realm]["new"] += 1
			result[realm]["legacy"] += 1
	for realm: String in result: result[realm]["new"] = 0
	for unit: Dictionary in ArmySplit.opening_sources(repo)["roster"].values():
		result[String(unit["kingdom_code"])]["new"] += ArmySplit.halves(MilitaryRoster.personnel_capacity(repo, unit), int(repo.bal("army_living_cap_men"))).size()
	return result

func test_every_realm_has_unique_eligible_active_and_reserve_commanders() -> void:
	var repo := SuiteData.repo()
	var people := CharacterFactory.build_roster(repo)
	var needs := _needs(repo)
	var names: Dictionary = {}
	for realm: String in needs:
		var active := 0
		var reserve := 0
		for id: String in repo.commanders:
			var row: Dictionary = repo.commanders[id]
			if repo.resolve_realm(row["realm_slot"]) != realm: continue
			assert_true(repo.realm_bindings.has(row["realm_slot"]), "stable realm slot: " + id)
			assert_true(people.has(id), "authored character: " + id)
			if not people.has(id): continue
			var person: Character = people[id]
			assert_eq(person.kingdom, realm)
			assert_ne(person.family_name, "")
			assert_eq(person.seat, "")
			assert_ne(person.category, "player")
			assert_false(person.traits.has("crowned_head"))
			assert_false(names.has(person.display_name), "unique readable name")
			names[person.display_name] = true
			assert_gt(int(person.attributes["age"]), 17)
			assert_gt(int(person.attributes["health"]), 0)
			assert_eq(String(row["eligible"]), "1")
			if String(row.get("pool_role", "")) == "reserve": reserve += 1
			else: active += 1
			if realm in [repo.resolve_realm("player_realm"), repo.resolve_realm("raider_realm")]:
				assert_eq(String(row["portrait_key"]), id)
			else: assert_eq(String(row["portrait_key"]), "")
			for trait_code: String in person.traits: assert_true(repo.traits.has(trait_code))
		assert_gte(active, maxi(needs[realm]["new"], needs[realm]["legacy"]), "full new / saved roster " + realm)
		var expected_reserve := 4
		if realm == repo.resolve_realm("player_realm"): expected_reserve = 64
		elif realm == repo.resolve_realm("raider_realm"): expected_reserve = 84
		assert_eq(reserve, expected_reserve, "explicitly authored replacement officers " + realm)
		# Every slot can be staffed even after all non-specialists are used.
		for arm: String in ["infantry", "archers", "cavalry", "artillery", "fleet"]:
			var count := 0
			for row: Dictionary in repo.commanders.values():
				if repo.resolve_realm(row["realm_slot"]) == realm and arm in String(row["unit_kinds"]).split("|"):
					count += 1
			var needed := 0
			for unit: Dictionary in ArmySplit.roster_of(repo).values():
				if unit["kingdom_code"] == realm and MapObjects.regiment_arm(repo, unit) == arm: needed += 1
			assert_gte(count, needed, realm + ": " + arm)
		print("COMMANDER_POOL ", realm, " new=", needs[realm]["new"], " legacy=", needs[realm]["legacy"], " active=", active, " reserve=", reserve)

func test_authored_fields_are_valid_and_each_priority_is_stable() -> void:
	var repo := SuiteData.repo()
	var people := CharacterFactory.build_roster(repo)
	var state := GameState.new()
	state.characters = people
	for role: Dictionary in repo.founding: state.council[role["seat"]] = role["id"]
	var priorities: Dictionary = {}
	for row: Dictionary in repo.roles:
		var id := String(row["id"])
		if not repo.commanders.has(id): continue
		var definition: Dictionary = repo.commanders[id]
		assert_eq(Commanders.candidate_error(repo, state, id), "", id)
		for key: String in ["ambition", "loyalty", "integrity", "boldness", "piety", "compassion", "vanity", "temper", "pragmatism", "policy_sensitivity", "health", "wealth", "prestige", "influence"]:
			assert_true(String(row[key]).is_valid_int(), id + " integer " + key)
			assert_between(int(row[key]), 0, 100, id + " " + key)
		for key: String in CharacterFactory.SKILLS: assert_between(int(row[key]), 0, 20)
		for key: String in CharacterFactory.AXES: assert_between(int(row[key]), -100, 100)
		assert_between(int(row["opinion"]), -100, 100)
		assert_between(int(row["age"]), 18, 100)
		var priority_key := "%s:%s" % [definition["realm_slot"], definition["reserve_priority"]]
		assert_false(priorities.has(priority_key), "stable unique realm priority")
		priorities[priority_key] = true
		assert_gt(int(definition["reserve_priority"]), 0)
		assert_true(String(definition["pool_role"]) in ["active", "reserve"])
		for arm: String in String(definition["unit_kinds"]).split("|"):
			assert_true(repo.world_table("military", "unit_types").has(arm))

func test_individual_arm_qualifications_cover_legacy_units_without_using_reserves() -> void:
	var repo := SuiteData.repo()
	var cap := int(repo.bal("army_split_cap_men"))
	var needs: Dictionary = {}
	for row: Dictionary in repo.world_table("military", "regiments").values():
		var realm := String(row["kingdom_code"])
		if not needs.has(realm): needs[realm] = {"infantry": 0, "archers": 0, "cavalry": 0, "artillery": 0, "fleet": 0}
		if String(row["is_naval"]) == "1":
			needs[realm]["fleet"] += 1
			continue
		if int(row["artillery"]) > 0: needs[realm]["artillery"] = 1
		for arm: String in ["infantry", "archers", "cavalry"]:
			var crew := int(repo.world_row("military", "unit_types", arm)["crew"])
			for old_count: int in ArmySplit.shares(int(row[arm]), cap):
				needs[realm][arm] += ArmySplit.shares(old_count, cap / crew).size()
	for realm: String in needs:
		var candidates: Array = []
		for row: Dictionary in repo.commanders.values():
			if repo.resolve_realm(row["realm_slot"]) == realm and row["pool_role"] == "active": candidates.append(row)
		# Narrow specialists are matched first; each id is removed exactly once.
		candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			var a_arms := String(a["unit_kinds"]).split("|").size()
			var b_arms := String(b["unit_kinds"]).split("|").size()
			return a_arms < b_arms if a_arms != b_arms else int(a["reserve_priority"]) < int(b["reserve_priority"]))
		for arm: String in needs[realm]:
			for _i: int in int(needs[realm][arm]):
				var found := -1
				for index: int in candidates.size():
					if arm in String(candidates[index]["unit_kinds"]).split("|"):
						found = index
						break
				assert_gte(found, 0, "unique active specialist " + realm + ": " + arm)
				if found >= 0: candidates.remove_at(found)
