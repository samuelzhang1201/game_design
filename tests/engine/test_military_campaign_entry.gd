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
		assert_ne(String(state.military_rosters.get(code, {}).get("commander_id", "")), "")

func test_missing_commander_pool_refuses_campaign_without_partial_armies() -> void:
	var repo := SuiteData.repo()
	repo.commanders.clear()
	assert_null(GameState.new_campaign(repo, 42))
	assert_false(GameState.campaign_error.is_empty())
