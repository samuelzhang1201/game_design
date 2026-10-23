extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func test_new_campaign_initializes_real_personnel_before_deploying() -> void:
	var repo := SuiteData.repo()
	var state := GameState.new_campaign(repo, 42)
	assert_not_null(state)
	if state == null:
		return
	assert_eq(state.military_rosters.size(), state.army_roster.size(), "every country has real personnel before play")
	for code: String in state.army_roster:
		assert_gt(MilitaryRoster.fit(state, code), 0, "a deployed unit cannot be a placeholder without personnel")
		assert_lte(MilitaryRoster.assigned_living(state, code), int(repo.bal("army_living_cap_men")))
		if not state.army_roster[code].has("organization_parent") or state.army_roster[code]["organization_parent"] == code:
			assert_ne(String(state.military_rosters.get(code, {}).get("commander_id", "")), "")
		else:
			assert_eq(String(state.military_rosters[code].get("commander_id", "")), "", "no invented officer on a partition child")

func test_missing_commander_pool_refuses_campaign_without_partial_armies() -> void:
	var repo := SuiteData.repo()
	repo.commanders.clear()
	assert_null(GameState.new_campaign(repo, 42))
	assert_false(GameState.campaign_error.is_empty())

func _single_source(arm: String, equipment: int) -> DataRepository:
	var repo := SuiteData.repo()
	var rows := repo.world_table("military", "regiments")
	var source: Dictionary = {}
	for row: Dictionary in rows.values():
		if (String(row.get("is_naval", "0")) == "1") == (arm == "fleet"):
			source = row.duplicate(true)
			break
	for kind: String in repo.world_table("military", "unit_types"): source[kind] = "0"
	source[arm] = str(equipment)
	rows.clear()
	rows[String(source.regiment_code)] = source
	repo.raid_hosts.clear()
	repo.balance.recruitment_eligible_permille = 1000
	return repo

func test_opening_all_arms_preserve_source_people_equipment_and_seed() -> void:
	for example: Array in [["infantry", 2500, 1, [625, 625, 625, 625]],
		["infantry", 1001, 1, [501, 500]], ["artillery", 313, 8, [626, 626, 626, 626]],
		["fleet", 25, 100, [625, 625, 625, 625]]]:
		var repo := _single_source(example[0], example[1])
		repo.world_row("military", "unit_types", example[0])["crew"] = str(example[2])
		var state := GameState.new_campaign(repo, 42)
		assert_not_null(state, GameState.campaign_error)
		if state == null: continue
		var sizes: Array = []
		var equipment := 0
		var provenance := 0
		var officers := 0
		var royals := 0
		for code: String in state.army_roster:
			sizes.append(MilitaryRoster.living(state, code))
			equipment += int(state.army_roster[code].get(example[0], 0))
			for part: Dictionary in state.army_roster[code].source_parts: provenance += int(part.equipment_count)
			if state.military_rosters[code].get("commander_id", "") != "": officers += 1
			if state.army_roster[code].get("is_royal", "0") == "1": royals += 1
		assert_eq(sizes, example[3])
		assert_eq(equipment, int(example[1]))
		assert_eq(provenance, equipment)
		assert_eq(officers, 1)
		assert_eq(royals, 0 if example[0] in ["fleet", "artillery"] else 1)
		var occupied := 0
		for cohort: Dictionary in state.military_cohorts.values(): occupied += int(cohort.initial)
		assert_eq(occupied, int(example[1]) * int(example[2]))
		assert_eq(SaveLoad.state_hash(GameState.new_campaign(repo, 42)), SaveLoad.state_hash(state))
		assert_eq(SaveLoad.state_hash(GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())), false)), SaveLoad.state_hash(state))

func test_opening_refuses_when_no_legal_camp_exists() -> void:
	var repo := _single_source("infantry", 100)
	var row: Dictionary = repo.world_table("military", "regiments").values()[0]
	var town := String(repo.kingdoms[row.kingdom_code].capital_burg)
	row.x = repo.burgs[town].x
	row.y = repo.burgs[town].y
	repo.balance.army_slot_max_rings = 0
	assert_null(GameState.new_campaign(repo, 42), "no fallback onto illegal or occupied ground")
