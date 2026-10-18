extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")


func test_campaign_cache_is_released_after_each_script() -> void:
	var connected := false
	for connection: Dictionary in gut.end_script.get_connections():
		var callback: Callable = connection["callable"]
		if callback.get_object() == SuiteData and callback.get_method() == "clear_campaigns":
			connected = true
	assert_true(connected, "Finished scripts must release their cached campaign snapshots")


func test_eviction_preserves_live_state_and_deterministic_rebuild() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 917)
	var before := SaveLoad.state_hash(state)
	assert_false(SuiteData._campaigns.is_empty())
	SuiteData.clear_campaigns()
	assert_true(SuiteData._campaigns.is_empty())
	assert_eq(SaveLoad.state_hash(state), before, "Eviction leaves an already returned state intact")
	var rebuilt := SuiteData.campaign(repo, 917)
	assert_eq(SaveLoad.state_hash(rebuilt), before, "A cold rebuild of the same input stays identical")
	rebuilt.metrics["treasury"] += 1
	assert_eq(SaveLoad.state_hash(state), before, "Returned campaigns remain independent")
	assert_eq(SaveLoad.state_hash(SuiteData.campaign(repo, 917)), before, "The cached snapshot remains pristine")
