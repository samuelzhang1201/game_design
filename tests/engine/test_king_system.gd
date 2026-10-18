extends GutTest

func test_route_advances_by_saved_day_and_stops_at_destination() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 991)
	state.king_state = {"x_m": 1000, "y_m": 2000, "route": [], "follow_code": "",
		"travel_state": "stationary", "last_advanced_day": 0}
	var result := KingSystem.set_route(repo, state, [Vector2i(21000, 2000)], "the king rides east")
	assert_eq(result.get("status"), "ok")
	var before := KingSystem.position(state)
	KingSystem.step_day(repo, state)
	assert_ne(KingSystem.position(state), before)
	assert_eq(state.king_state.get("last_advanced_day"), state.absolute_day())
	var moved := KingSystem.position(state)
	KingSystem.step_day(repo, state)
	assert_eq(KingSystem.position(state), moved, "the same day cannot advance twice")
	for i in 100:
		state.day += 1
		KingSystem.step_day(repo, state)
	assert_eq(KingSystem.position(state), Vector2i(21000, 2000))
	assert_eq(state.king_state.get("travel_state"), "stationary")


func test_follow_requires_rendezvous_and_then_tracks_actual_unit() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 992)
	var code := String(state.regiments.keys()[0])
	var target_m := ArmySystem.pack_to_metres(repo, Vector2(31.0, 2.0))
	state.regiments[code]["x_m"] = target_m.x
	state.regiments[code]["y_m"] = target_m.y
	state.regiments[code]["camp_town"] = ""
	state.king_state = {"x_m": 1000, "y_m": 2000, "route": [], "follow_code": "",
		"travel_state": "stationary", "last_advanced_day": 0}
	var result := KingSystem.follow(repo, state, code)
	assert_eq(result.get("status"), "ok")
	assert_eq(state.king_state.get("travel_state"), "rendezvous")
	var army_position := ArmySystem.pack_to_metres(repo,
		ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code, state)))
	assert_ne(KingSystem.position(state), army_position)
	for i in 100:
		state.day += 1
		KingSystem.step_day(repo, state)
		if state.king_state.get("travel_state") == "following":
			break
	assert_eq(state.king_state.get("travel_state"), "following")
	state.regiments[code]["x_m"] += 5000
	state.day += 1
	KingSystem.step_day(repo, state)
	army_position = ArmySystem.pack_to_metres(repo,
		ArmySystem.position_of(repo, state, ArmySystem.regiment(repo, code, state)))
	assert_eq(KingSystem.position(state), army_position)


func test_follow_rejects_a_unit_in_town_and_clears_when_target_is_removed() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 998)
	var code := String(state.regiments.keys()[0])
	state.regiments[code]["x_m"] = 30000
	state.regiments[code]["y_m"] = 2000
	state.regiments[code]["camp_town"] = "some_town"
	state.king_state = {"x_m": 1000, "y_m": 2000, "route": [], "follow_code": "",
		"travel_state": "stationary", "last_advanced_day": 0}
	assert_eq(KingSystem.follow(repo, state, code).get("status"), "error")
	state.regiments[code]["camp_town"] = ""
	assert_eq(KingSystem.follow(repo, state, code).get("status"), "ok")
	state.army_roster.erase(code)
	state.day += 1
	KingSystem.step_day(repo, state)
	assert_eq(String(state.king_state.get("follow_code", "")), "")


func test_presence_uses_only_actual_battle_distance() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 993)
	state.king_state = {"x_m": 1000, "y_m": 2000, "route": [], "follow_code": "",
		"travel_state": "stationary", "last_advanced_day": 0}
	state.battles = [{"id": 73, "place_x_m": 2000, "place_y_m": 2000}]
	assert_true(KingSystem.present(repo, state, 73), "the configured radius includes its edge")
	state.current_location = "some-other-place"
	assert_true(KingSystem.present(repo, state, 73), "prose location cannot alter physical presence")
	state.battles[0]["place_x_m"] = 2001
	assert_false(KingSystem.present(repo, state, 73), "one metre outside the radius is absent")
	assert_false(KingSystem.present(repo, state, 74), "screen selection cannot invent presence")


func test_king_report_courier_tracks_king_and_survives_save_restore() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 995)
	var battle_id := 77
	var battle_place := Vector2i(120000, 85000)
	state.king_state["x_m"] = 0
	state.king_state["y_m"] = 0
	var report := CourierSystem.dispatch_king_report(repo, state, battle_id,
		{"battle_id": battle_id, "place_x_m": battle_place.x, "place_y_m": battle_place.y})
	assert_eq(Vector2i(report["x_m"], report["y_m"]), battle_place)
	assert_eq(report["kind"], CourierSystem.KING_REPORT)
	var first_route: Array = report["path"].duplicate(true)
	CourierSystem.ride_day(repo, state)
	assert_gt(state.couriers.size(), 0)
	var courier: Dictionary = state.couriers[0]
	var current := Vector2i(int(courier["x_m"]), int(courier["y_m"]))
	assert_ne(current, battle_place, "the report rides from the battle point")
	state.king_state["x_m"] = 480000
	state.king_state["y_m"] = 310000
	var expected := CourierSystem.path_between(repo,
		ArmySystem.metres_to_pack(repo, current),
		ArmySystem.metres_to_pack(repo, Vector2i(480000, 310000)))
	courier["aim_x_m"] = -1
	courier["aim_y_m"] = -1
	CourierSystem.ride_day(repo, state)
	if not state.couriers.is_empty():
		courier = state.couriers[0]
		assert_eq(courier["aim_x_m"], 480000)
		assert_eq(courier["aim_y_m"], 310000)
		assert_ne(courier["path"], first_route, "a moved king causes a new route from the rider")
		assert_eq(courier["path"], expected, "the route starts at the rider's actual position")
		var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
		assert_eq(restored.couriers, state.couriers)
		assert_eq(restored.king_state, state.king_state)
	else:
		assert_true(MissiveLog.column(state, "credible").any(
			func(m: Dictionary) -> bool: return String(m["kind"]) == "king_report"),
			"a courier arriving during retarget still files the report")


func test_king_report_dispatch_uses_battle_event_after_battle_is_removed() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 996)
	var battle_id := 78
	var place := Vector2i(180000, 90000)
	state.battles = []
	var courier := CourierSystem.dispatch_king_report(repo, state, battle_id,
		{"battle_id": battle_id, "place_x_m": place.x, "place_y_m": place.y})
	assert_eq(Vector2i(int(courier.get("x_m", -1)), int(courier.get("y_m", -1))), place,
		"finished battle coordinates carried by the day's events remain usable")
	assert_eq(state.couriers.size(), 1)


func test_king_report_carries_authored_facts_without_dispatch_fee() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 999)
	var facts := [MissiveLog.exact("casualties", "Our losses", 3)]
	var courier := CourierSystem.dispatch_king_report(repo, state, 82,
		{"battle_id": 82, "place_x_m": 100000, "place_y_m": 100000,
		"report": {"title": "Battle of the Ford", "facts": facts}})
	assert_eq(courier["orders"][0]["report"]["facts"], facts)
	var treasury := float(state.metrics["treasury"])
	CourierSystem._deliver(repo, state, courier)
	assert_eq(float(state.metrics["treasury"]), treasury, "report delivery has no automatic fee")
	var letters := MissiveLog.column(state, "credible")
	var received: Dictionary = letters.filter(func(m: Dictionary) -> bool:
		return String(m["kind"]) == "king_report")[0]
	assert_eq(received["title"], "Battle of the Ford")
	assert_eq(received["facts"], facts)


func test_tick_transaction_does_not_repeat_king_movement_after_encounter_pause() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 994)
	state.day = 16
	state.king_state = {"x_m": 1000, "y_m": 2000, "route": [], "follow_code": "",
		"travel_state": "stationary", "last_advanced_day": 0}
	var dest := Vector2i(21000, 2000)
	KingSystem.set_route(repo, state, [dest], "a test journey")
	var engine := TickEngine.new(repo)
	var host: Dictionary = repo.raid_hosts[0]
	var mine := String(state.regiments.keys()[0])
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state,
		ArmySystem.regiment(repo, mine, state)))
	var home_px := ArmySystem.metres_to_pack(repo, at)
	var foe_px := Vector2(home_px.x + 0.2, home_px.y)
	var foe_m := ArmySystem.pack_to_metres(repo, foe_px)
	host["appear_day"] = state.absolute_day() - 10
	host["start_x"] = int(round(foe_px.x))
	host["start_y"] = int(round(foe_px.y))
	EnemyAi.spawn(repo, state, host)
	for code: String in state.foes:
		state.foes[code]["x_m"] = foe_m.x
		state.foes[code]["y_m"] = foe_m.y
		state.foes[code]["dest_x_m"] = foe_m.x
		state.foes[code]["dest_y_m"] = foe_m.y
		state.foes[code]["camp_town"] = ""
	var pos := KingSystem.position(state)
	var daily_budget := KingSystem.daily_budget(repo, state)
	var blocked := engine.resolve_day(state)
	assert_eq(blocked.get("status"), "blocked")
	assert_eq(KingSystem.position(state), pos + Vector2i(daily_budget / 10, 0), "the king spends only the substeps completed before contact")
	var held := state.to_dict()
	assert_eq(engine.resolve_day(state).status, "blocked")
	assert_eq(state.to_dict(), held, "pause polls spend no royal movement")
	var restored := GameState.from_dict(JSON.parse_string(JSON.stringify(state.to_dict())))
	state = restored
	engine = TickEngine.new(repo)
	engine.resolve_decision(state, String(restored.day_resolution["pending_decision"]["token"]), "continue")
	engine.resolve_day(state)
	assert_eq(KingSystem.position(state), pos + Vector2i(daily_budget, 0), "resume spends the remaining substeps exactly once")


func test_actions_validate_cost_and_execute_physical_king_orders() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 995)
	var actions := ActionSystem.new(repo)
	var target := Vector2i(21000, 2000)
	var request := ActionRequest.make("KING_MOVE", {"x_m": target.x, "y_m": target.y})
	var treasury := int(state.metrics["treasury"])
	assert_eq(actions.validate(request, state), "")
	var moved := actions.execute(request, state)
	assert_true(moved["ok"])
	assert_eq(int(state.metrics["treasury"]), treasury - 1)
	assert_eq(state.king_state.get("travel_state"), "travelling")
	assert_ne(actions.validate(ActionRequest.make("KING_MOVE", {"x_m": 1.5, "y_m": 2000}), state), "")
	var code := String(state.regiments.keys()[0])
	state.regiments[code]["camp_town"] = ""
	assert_eq(actions.validate(ActionRequest.make("KING_FOLLOW", {"regiment": code}), state), "")


func test_safe_departure_keeps_existing_route_when_no_reachable_refuge_exists() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 996)
	var battle_at := ArmySystem.pack_to_metres(repo, Vector2(31.0, 2.0))
	state.king_state = {"x_m": battle_at.x, "y_m": battle_at.y, "route": [[9000, 2000]], "follow_code": "",
		"travel_state": "stationary", "last_advanced_day": 0}
	var route_before: Array = state.king_state["route"].duplicate(true)
	repo.burgs.clear()
	var code := String(state.regiments.keys()[0])
	var army_before: Dictionary = state.regiments[code].duplicate(true)
	state.battles = [{"id": 97, "att": [code], "def": [], "start_day": state.absolute_day(),
		"rounds": 0, "place_x_m": battle_at.x, "place_y_m": battle_at.y, "town": ""}]
	var battle_before := state.battles.duplicate(true)
	var result := KingSystem.safe_departure(repo, state, 97)
	assert_eq(result.get("status"), "error")
	assert_eq(state.king_state["route"], route_before)
	assert_eq(state.regiments[code], army_before)
	assert_eq(state.battles, battle_before)


func test_successful_safe_departure_changes_only_the_king_route() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 1000)
	var capital := String(repo.kingdoms[repo.resolve_realm("player_realm")]["capital_burg"])
	var burg: Dictionary = repo.burgs[capital]
	var refuge := ArmySystem.pack_to_metres(repo, Vector2(float(burg["x"]), float(burg["y"])))
	var at := refuge + Vector2i(1, 0)
	state.king_state = {"x_m": at.x, "y_m": at.y, "route": [], "follow_code": "",
		"travel_state": "stationary", "last_advanced_day": 0}
	var code := String(state.regiments.keys()[0])
	state.battles = [{"id": 100, "att": [code], "def": [], "start_day": state.absolute_day(),
		"rounds": 0, "place_x_m": at.x, "place_y_m": at.y, "town": ""}]
	var army_before := state.regiments.duplicate(true)
	var battle_before := state.battles.duplicate(true)
	assert_true(KingSystem.present(repo, state, 100))
	assert_eq(KingSystem.safe_departure(repo, state, 100).get("status"), "ok")
	assert_eq(KingSystem.position(state), at, "the king starts his escape from his own physical position")
	assert_eq(state.regiments, army_before)
	assert_eq(state.battles, battle_before, "a protected withdrawal does not settle the battle")
	assert_gt((state.king_state["route"] as Array).size(), 0)
	var last: Array = state.king_state["route"].back()
	assert_eq(Vector2i(int(last[0]), int(last[1])), refuge)


func test_passive_king_support_is_derived_and_disappears_when_out_of_range() -> void:
	var repo := SuiteData.repo()
	var state := SuiteData.campaign(repo, 997)
	var code := String(state.regiments.keys()[0])
	var pos := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, state,
		ArmySystem.regiment(repo, code, state)))
	state.king_state = {"x_m": pos.x, "y_m": pos.y, "route": [], "follow_code": "",
		"travel_state": "stationary", "last_advanced_day": 0}
	state.battles = [{"id": 98, "att": [code], "def": [], "start_day": state.absolute_day(),
		"rounds": 0, "place_x_m": pos.x, "place_y_m": pos.y, "town": ""}]
	state.king_state["x_m"] += int(repo.bal("king_command_radius_m")) + 1
	var base := BattleSystem.side_power(repo, state, [code], func(_c: String) -> String: return "steady", true)
	state.king_state["x_m"] = pos.x
	var before_morale := int(state.regiments[code]["morale"])
	var with_king := BattleSystem.side_power(repo, state, [code], func(_c: String) -> String: return "steady", true)
	assert_gt(with_king, base)
	assert_eq(int(state.regiments[code]["morale"]), before_morale, "support is not accumulated in saved morale")
	for i in 10:
		assert_gt(BattleSystem.side_power(repo, state, [code], func(_c: String) -> String: return "steady", true), base)
	assert_eq(int(state.regiments[code]["morale"]), before_morale)
	state.king_state["x_m"] += int(repo.bal("king_command_radius_m")) + 1
	assert_eq(KingSystem.morale_support(repo, state, code), 0)
	assert_eq(BattleSystem.side_power(repo, state, [code], func(_c: String) -> String: return "steady", true), base)

const SuiteData := preload("res://tests/suite_data.gd")
const Scenario := preload("res://tests/fixtures/battle_scenario.gd")
const Play := preload("res://tests/invasion_play.gd")


func test_day_resolution_follows_the_armys_actual_same_day_endpoint() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	for key: String in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}
	Weather.forget()
	var state := SuiteData.campaign(repo, 999)
	state.tick = 1
	state.day = 10
	state.ai_hosts.clear()
	state.foes.clear()
	Play.park_army(repo, state, Vector2i(1000, 2000))
	var code := String(Play.land_regiments(repo)[0])
	Play.place(repo, state, code, Vector2i(1000, 2000), ArmySystem.ORDER_STANDBY)
	state.regiments[code]["camp_state"] = {"phase": CampSystem.NONE}
	state.king_state = {"x_m": 1000, "y_m": 2000, "route": [], "follow_code": "",
		"travel_state": "stationary", "last_advanced_day": 0}
	assert_eq(KingSystem.follow(repo, state, code).get("status"), "ok")
	ArmySystem.set_march_m(repo, state, code, Vector2i(1100, 2000))
	assert_gt(ArmySystem.day_march_m(repo, state, code), 100)
	var result := TickEngine.new(repo).resolve_day(state)
	assert_eq(result["status"], "complete")
	assert_eq(Vector2i(int(state.regiments[code]["x_m"]), int(state.regiments[code]["y_m"])),
		Vector2i(1100, 2000))
	assert_eq(KingSystem.position(state), Vector2i(1100, 2000), "following reads today's actual march endpoint")
	assert_eq(int(state.king_state["last_advanced_day"]), 10)
	assert_eq(state.day, 11)


func test_blocked_day_advances_king_only_once_across_retry_and_json_resume() -> void:
	var repo := SuiteData.flat_ground(SuiteData.repo())
	repo.balance["king_travel_km_per_day"] = 10
	var state := Scenario.contact(repo, 10)
	state.king_state = {"x_m": 1000, "y_m": 2000, "route": [], "follow_code": "",
		"travel_state": "stationary", "last_advanced_day": 0}
	assert_eq(KingSystem.set_route(repo, state, [Vector2i(21000, 2000)],
		"the king rides east").get("status"), "ok")
	var engine := TickEngine.new(repo)
	var blocked := engine.resolve_day(state)
	assert_eq(blocked["status"], "blocked")
	assert_eq(KingSystem.position(state), Vector2i(2000, 2000), "first substep spends1000 of10000 metres")
	assert_eq(int(state.king_state["last_advanced_day"]), 0, "the paused day has not finished its royal budget")
	assert_eq(state.day, 10)
	var before_retry := SaveLoad.state_hash(state)
	assert_eq(engine.resolve_day(state)["status"], "blocked")
	assert_eq(SaveLoad.state_hash(state), before_retry)
	var loaded := Scenario.roundtrip(state)
	var resumed := TickEngine.new(repo)
	assert_eq(resumed.resolve_day(loaded)["status"], "blocked")
	assert_eq(KingSystem.position(loaded), Vector2i(2000, 2000), "the loaded pause preserves the first substep")
	assert_eq(resumed.resolve_decision(loaded, String(blocked["decision"]["token"]),
		"continue")["status"], "accepted")
	assert_eq(resumed.resolve_day(loaded)["status"], "complete")
	assert_eq(KingSystem.position(loaded), Vector2i(11000, 2000))
	assert_eq(int(loaded.king_state["last_advanced_day"]), 10)
	assert_eq(loaded.day, 11)

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
