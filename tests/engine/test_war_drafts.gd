extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The WAR ROOM's drafts (spec 2026-10-02-war-room-v2 §3.1): pencilled orders,
## saved, one per regiment, set aside by a real order.

var repo: DataRepository
var state: GameState
var code := ""


func before_each() -> void:
	repo = SuiteData.repo()
	state = SuiteData.campaign(repo, 42)
	code = ""
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.base_pace_km(repo, r) > 0:
			code = String(r["regiment_code"])
			break


func _somewhere() -> Vector2:
	return ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code)) + Vector2(20, 0)


func test_a_draft_is_planted_in_whole_metres_and_replaces_the_last() -> void:
	WarDrafts.plant(repo, state, code, "march", _somewhere())
	var d := WarDrafts.of(state, code)
	assert_eq(String(d["order"]), "march")
	assert_true(d["dest_x_m"] is int and d["dest_y_m"] is int)
	assert_almost_eq(WarDrafts.dest_px(repo, d).distance_to(_somewhere()), 0.0, 0.01)
	WarDrafts.plant(repo, state, code, "garrison", Vector2.ZERO)
	assert_eq(String(WarDrafts.of(state, code)["order"]), "garrison")
	assert_eq(WarDrafts.codes(state), [code], "one draft a regiment")


func test_strike_and_any() -> void:
	assert_false(WarDrafts.any(state))
	WarDrafts.plant(repo, state, code, "march", _somewhere())
	assert_true(WarDrafts.any(state))
	assert_true(WarDrafts.strike(state, code))
	assert_false(WarDrafts.strike(state, code), "nothing left to strike")
	assert_false(WarDrafts.any(state))


func test_a_draft_stands_for_its_real_order() -> void:
	WarDrafts.plant(repo, state, code, "march", _somewhere())
	var req := WarDrafts.request_of(repo, state, code)
	assert_eq(req.action_code, "ARMY_MARCH")
	assert_eq(String(req.params["regiment"]), code)
	assert_almost_eq(Vector2(float(req.params["x"]), float(req.params["y"])).distance_to(_somewhere()), 0.0, 0.01)
	var held := WarDrafts.of(state, code)
	assert_eq(WarDrafts.request_from(repo, code, held).action_code, "ARMY_MARCH")
	WarDrafts.plant(repo, state, code, "garrison", Vector2.ZERO)
	assert_eq(WarDrafts.request_of(repo, state, code).action_code, "ARMY_GARRISON")


func test_drafts_survive_a_save_and_a_load() -> void:
	WarDrafts.plant(repo, state, code, "march", _somewhere())
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	assert_eq(WarDrafts.codes(back), [code])
	assert_eq(int(WarDrafts.of(back, code)["dest_x_m"]), int(WarDrafts.of(state, code)["dest_x_m"]))
	assert_true(WarDrafts.of(back, code)["dest_x_m"] is int, "whole metres survive JSON")


func test_an_old_save_has_no_drafts() -> void:
	var d := state.to_dict()
	d.erase("war_drafts")
	assert_eq(GameState.from_dict(d).war_drafts, {})


func test_a_real_order_sets_the_draft_aside_and_says_so() -> void:
	WarDrafts.plant(repo, state, code, "march", _somewhere())
	var actions := ActionSystem.new(repo)
	var req := ActionRequest.make("ARMY_GARRISON", {"regiment": code})
	assert_eq(actions.validate(req, state), "")
	var out := actions.execute(req, state)
	assert_false(WarDrafts.any(state))
	var said := (out["effects"] as Array).filter(func(e: Dictionary) -> bool: return String(e.get("metric", "")) == "war_draft")
	assert_eq(said.size(), 1)


func test_an_order_with_no_draft_says_nothing_of_drafts() -> void:
	var out := ActionSystem.new(repo).execute(ActionRequest.make("ARMY_GARRISON", {"regiment": code}), state)
	assert_true((out["effects"] as Array).all(func(e: Dictionary) -> bool: return String(e.get("metric", "")) != "war_draft"))
