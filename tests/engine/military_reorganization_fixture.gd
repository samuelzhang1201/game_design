extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Roster := preload("res://scripts/engine/military_roster.gd")
var repo: DataRepository
var state: GameState
var original: String

func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	SuiteData.open_country(repo)
	var codes := state.regiments.keys()
	codes.sort()
	for code: String in codes:
		if MapObjects.regiment_arm(repo, state.army_roster[code]) == "cavalry":
			original = code
			break
	var unit: Dictionary = state.army_roster[original].duplicate(true)
	var officer: String = state.military_rosters[original].commander_id
	var family: String = state.characters[officer].family_name
	var origin: String = unit.source_parts[0].province_code
	state.army_roster = {original: unit}
	state.regiments = {original: state.regiments[original].duplicate(true)}
	state.foes.clear()
	state.battles.clear()
	state.ai_hosts.clear()
	state.town_seat.clear()
	state.military_cohorts.clear()
	state.military_rosters = {original: {"commander_id": officer, "commander_cohort_id": "officer", "cohort_ids": []}}
	state.military_migration = {"version": 1, "organization_version": 1, "organization_pending": false,
		"unit_mapping": {"historical": [original]}}
	for arm: String in repo.world_table("military", "unit_types"):
		unit[arm] = "0"
	unit.cavalry = "1001"
	unit.source_parts = [{"regiment_code": "saved_source", "province_code": origin, "arm": "cavalry", "equipment_count": 1001,
		"crew_per_element": int(repo.world_row("military", "unit_types", "cavalry").crew)}]
	_add("officer", 1, 0, 0, 0, 0, officer, family)
	_add("common", 0, 1000, 77, 31, 12)
	state.regiments[original].supplies = 101
	state.unit_prize_gold = {original: 101}

func _add(id: String, fit: int, wounded: int, captured := 0, dead := 0, released := 0, person := "", family := "") -> void:
	var cohort := {"id": id, "unit_code": original, "identity": "noble" if person != "" else "commoner", "family_name": family,
		"stage": "active", "source_province": state.army_roster[original].source_parts[0].province_code,
		"source_population_field": "rural_population", "initial": fit + wounded + captured + dead + released,
		"fit": fit, "wounded": wounded, "captured_current": captured, "dead": dead, "released": released,
		"origin_reason": "Saved paid people"}
	if person != "": cohort.person_id = person
	state.military_cohorts[id] = cohort
	state.military_rosters[original].cohort_ids.append(id)

func _reconcile() -> Dictionary:
	return MilitaryReorganization.reconcile(repo, state)

func _children() -> Array:
	return state.military_migration.get("living_unit_mapping", {}).get(original, [])
