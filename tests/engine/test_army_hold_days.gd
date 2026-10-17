extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

var repo: DataRepository
var state: GameState
var code := ""

func before_each() -> void:
	repo = SuiteData.repo()
	repo.balance["camp_after_days"] = 5.0
	state = SuiteData.campaign(repo, 7)
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), state):
		if String(r.get("is_naval", "0")) != "1":
			code = String(r["regiment_code"])
			break
	var e: Dictionary = state.regiments[code]
	e["x_m"] = 10000000
	e["y_m"] = 10000000
	e["order"] = ArmySystem.ORDER_GARRISON
	e.erase("camp_town")
	e["camp_state"] = {"phase": CampSystem.NONE, "idle_days": 0, "build_progress": 0,
		"pack_start_day": -1, "move_not_before_day": -1, "last_updated_day": -1,
		"site": {"x_m": 10000000, "y_m": 10000000}}
	for town: String in state.town_seat.keys():
		if String(state.town_seat[town]) == code:
			state.town_seat.erase(town)

func test_camped_reads_only_completed_physical_state() -> void:
	var e: Dictionary = state.regiments[code]
	e["hold_days"] = 50
	assert_false(ArmySystem.camped(repo, state, code), "legacy hold counter is not a camp")
	e["camp_state"]["phase"] = CampSystem.BUILDING
	assert_false(ArmySystem.camped(repo, state, code))
	e["camp_state"]["phase"] = CampSystem.CAMPED
	assert_true(ArmySystem.camped(repo, state, code))
	e["x_m"] = 2
	assert_false(ArmySystem.camped(repo, state, code), "leaving the physical site drops camp defence")

func test_only_demonstrable_legacy_field_camps_migrate() -> void:
	var e: Dictionary = state.regiments[code]
	e["hold_days"] = 5
	e.erase("camp_state")
	CampSystem.ensure_legacy(repo, state, code)
	assert_eq(e["camp_state"]["phase"], CampSystem.CAMPED)
	assert_eq(e["camp_state"]["build_progress"], 1000)

func test_legacy_town_garrison_does_not_migrate_to_field_camp() -> void:
	var e: Dictionary = state.regiments[code]
	var town := ""
	for t: String in repo.burgs:
		if ArmyGround.holds(repo, state, repo.resolve_realm("player_realm"), t):
			town = t
			break
	assert_ne(town, "")
	e["x_m"] = ArmySystem.pack_to_metres(repo, Vector2(float(repo.burgs[town]["x"]), float(repo.burgs[town]["y"]))).x
	e["y_m"] = ArmySystem.pack_to_metres(repo, Vector2(float(repo.burgs[town]["x"]), float(repo.burgs[town]["y"]))).y
	e["hold_days"] = 5
	e.erase("camp_state")
	state.town_seat[town] = code
	CampSystem.ensure_legacy(repo, state, code)
	assert_false(e.has("camp_state"), "a town seat is not a second field camp")
