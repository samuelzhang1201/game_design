extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
var repo: DataRepository
var campaign: GameState
var code: String
var previous_repo: DataRepository

func before_each() -> void:
	previous_repo = Game.data
	Game.restart()
	repo = SuiteData.repo()
	campaign = SuiteData.campaign(repo, 42)
	SuiteData.open_country(repo)
	var codes := campaign.regiments.keys()
	codes.sort()
	for unit: String in codes:
		if MapObjects.regiment_arm(repo, campaign.army_roster[unit]) == "cavalry" \
				and not campaign.military_migration.get("living_unit_mapping", {}).has(unit):
			code = unit
			break
	var row: Dictionary = campaign.army_roster[code]
	row["cavalry"] = str(int(row["cavalry"]) + 600)
	row["source_parts"][0]["equipment_count"] = int(row["source_parts"][0]["equipment_count"]) + 600
	var id: String = campaign.military_rosters[code].cohort_ids.filter(func(cohort_id: String) -> bool:
		return not campaign.military_cohorts[cohort_id].has("person_id") and campaign.military_cohorts[cohort_id].identity == "commoner")[0]
	campaign.military_cohorts[id].fit += 1001
	campaign.military_cohorts[id].initial += 1001
	campaign.military_migration["organization_pending"] = true
	campaign.foes.clear()
	campaign.ai_hosts.clear()
	campaign.battles.clear()
	Game.data = repo

func after_each() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://organization_hooks.json"))
	Game.restart()
	Game.data = previous_repo

func test_load_reorganizes_before_publishing_and_second_load_is_stable() -> void:
	var initial_people := MilitaryRoster.living(campaign, code)
	assert_true(SaveLoad.save_game(campaign, "user://organization_hooks.json"))
	assert_true(Game.load_campaign("user://organization_hooks.json"), Game.load_error)
	assert_false(bool(Game.state.military_migration.get("organization_pending", true)))
	var total := 0
	for unit: String in Game.state.military_migration.get("living_unit_mapping", {}).get(code, []):
		assert_lte(MilitaryRoster.living(Game.state, unit), 1000)
		total += MilitaryRoster.living(Game.state, unit)
	assert_eq(total, initial_people)
	assert_true(Game.save_campaign("user://organization_hooks.json"))
	var before := SaveLoad.state_hash(Game.state)
	assert_true(Game.load_campaign("user://organization_hooks.json"), Game.load_error)
	assert_eq(SaveLoad.state_hash(Game.state), before)

func test_day_boundary_reconciles_pending_organization_before_day_work() -> void:
	var engine := TickEngine.new(repo)
	var result := engine.resolve_day(campaign)
	assert_eq(result.get("status"), "complete", str(result))
	assert_false(bool(campaign.military_migration.get("organization_pending", true)))
	assert_true(campaign.military_migration.get("living_unit_mapping", {}).has(code))

func test_invalid_organization_load_keeps_existing_reign() -> void:
	Game.state = SuiteData.campaign(repo, 7)
	var current := Game.state
	repo.balance["army_slot_max_rings"] = 0
	assert_true(SaveLoad.save_game(campaign, "user://organization_hooks.json"))
	assert_false(Game.load_campaign("user://organization_hooks.json"))
	assert_same(Game.state, current)
	assert_false(Game.load_error.is_empty())
