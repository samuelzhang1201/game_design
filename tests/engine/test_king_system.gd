extends GutTest

const SuiteData := preload("res://tests/suite_data.gd")

func test_new_campaign_saves_the_kings_capital_position_in_metres() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 31)
	var realm := repo.resolve_realm("player_realm")
	var capital := String(repo.kingdoms[realm]["capital_burg"])
	var burg: Dictionary = repo.burgs[capital]
	var expected := ArmySystem.pack_to_metres(repo, Vector2(float(burg["x"]), float(burg["y"])))
	var saved: Dictionary = state.to_dict()
	assert_true(saved.has("king_state"), "king location is part of the single save")
	var loaded := GameState.from_dict(JSON.parse_string(JSON.stringify(saved)))
	assert_eq(KingSystem.position(loaded), expected, "the king begins at the bound capital and survives JSON")

func test_order_courier_starts_at_the_saved_king_position() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 32)
	var saved: Dictionary = state.to_dict()
	var current := Vector2i(1000, 2000)
	saved["king_state"] = {"x_m": current.x, "y_m": current.y, "route": [],
		"follow_code": "", "travel_state": "stationary", "last_advanced_day": 0}
	state = GameState.from_dict(saved)
	var regiment := ""
	for row: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(repo, row) > 0 and String(row.get("is_naval", "0")) != "1":
			regiment = String(row["regiment_code"])
			break
	var courier := CourierSystem.dispatch(repo, state, CourierSystem.ORDINARY, regiment,
		{"action_code": "ARMY_GARRISON"})
	assert_eq(Vector2i(int(courier["x_m"]), int(courier["y_m"])), current,
		"the dispatch snapshots the king's actual position")
