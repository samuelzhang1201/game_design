extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

## Losing any of these fields would release reserved people or replay a paid event.
func test_personnel_and_pending_recruitment_survive_json() -> void:
	var raw := SuiteData.campaign(SuiteData.repo(), 42).to_dict()
	var fields := {
		"military_rosters": {"unit": {"commander_id": "noble", "cohort_ids": ["cohort"]}},
		"military_cohorts": {"cohort": {"id": "cohort", "fit": 80, "wounded": 20,
			"captured_current": 60, "dead": 40, "released": 10, "stage": "active"}},
		"military_events": {"battle:1:loss": {"changes": [{"count": 40}], "result": {"status": "applied"}}},
		"recruitment_projects": {"project": {"cohort_ids": ["gathering"], "completion_day": 12}},
		"military_migration": {"version": 1, "pending": true, "unit_map": {"unit": ["unit", "unit_2"]}},
	}
	for key: String in fields:
		raw[key] = fields[key]
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(raw)))
	assert_not_null(loaded)
	for key: String in fields:
		assert_eq(loaded.get(key), fields[key], key)
		assert_eq(loaded.to_dict().get(key), fields[key], key + " serializes")

func test_old_save_starts_with_empty_personnel_facts() -> void:
	var raw := SuiteData.campaign(SuiteData.repo(), 42).to_dict()
	for key: String in ["military_rosters", "military_cohorts", "military_events", "recruitment_projects", "military_migration"]:
		raw.erase(key)
	var loaded := GameState.from_dict(raw)
	for key: String in ["military_rosters", "military_cohorts", "military_events", "recruitment_projects", "military_migration"]:
		assert_eq(loaded.get(key), {}, key + " awaits repository-aware migration")
