extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## ARMY_MARCH through waypoints (spec 2026-10-07-march-waypoints §1): every
## point checked as the end is, the courier carrying them in whole metres, the
## days measured along the curve; the war room's draft keeps them and the load.

var repo: DataRepository


func before_all() -> void:
	RoadGraph.forget()


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _marcher() -> Dictionary:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(repo, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return r
	return {}


## The first land (or sea, `sea` true) point `dir` px steps from `from`, from 3 steps out.
func _probe(from: Vector2, dir: Vector2, sea := false) -> Vector2:
	for i in range(3, 80):
		var p := from + dir * float(i)
		if (MapEconomy.cell_at(repo, p) >= 0) != sea:
			return p
	return Vector2(-1, -1)


func _route(s: GameState, r: Dictionary) -> Dictionary:
	var home: Vector2 = ArmySystem.position_of(repo, s, r)
	return {"wp": _probe(home, Vector2(0.7, 0.7)), "to": _probe(home, Vector2(1, 0))}


func _march(code: String, to: Vector2, wps: Array) -> ActionRequest:
	var pairs: Array = []
	for w: Vector2 in wps:
		pairs.append([w.x, w.y])
	return ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": to.x, "y": to.y, "waypoints": pairs})


func test_waypoints_are_checked_as_the_end_is() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var rt := _route(s, r)
	assert_true(rt["wp"].x >= 0.0 and rt["to"].x >= 0.0, "land about the regiment")
	assert_eq(actions.validate(_march(code, rt["to"], [rt["wp"]]), s), "")
	assert_eq(actions.validate(_march(code, rt["to"], [Vector2(-5, 3)]), s), "That waypoint is off the map")
	var sea := _probe(ArmySystem.position_of(repo, s, r), Vector2(1, 0), true)
	for d: Vector2 in [Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		if sea.x < 0.0:
			sea = _probe(ArmySystem.position_of(repo, s, r), d, true)
	if sea.x >= 0.0:
		assert_eq(actions.validate(_march(code, rt["to"], [sea]), s),
			"%s cannot march through the sea" % String(r["label"]))
	var many: Array = []
	for i in int(repo.bal("army_march_waypoints_max")) + 1:
		many.append(rt["wp"])
	assert_eq(actions.validate(_march(code, rt["to"], many), s),
		"A march takes at most %d waypoints" % int(repo.bal("army_march_waypoints_max")))
	assert_eq(actions.validate_place(_march(code, rt["to"], [Vector2(-5, 3)]), s), "That waypoint is off the map",
		"a draft is refused for a place no seal could send it to")


func test_the_courier_carries_the_waypoints_and_delivers_the_route() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var rt := _route(s, r)
	actions.execute(_march(code, rt["to"], [rt["wp"]]), s)
	assert_eq(s.couriers.size(), 1)
	var order: Dictionary = s.couriers[0]["order"]
	var wm := ArmySystem.pack_to_metres(repo, rt["wp"])
	assert_eq(order["waypoints_m"], [[wm.x, wm.y]], "whole metres on the courier")
	var promised := CourierSystem.days_to_arrival(repo, s, code)
	assert_eq(promised, CourierSystem.arrival_days(repo, s, code, rt["to"], Vector2(-1, -1), -1, [rt["wp"]]),
		"the arrival read off a riding order counts its route")
	assert_gte(promised, CourierSystem.arrival_days(repo, s, code, rt["to"]), "never shorter than the straight line")
	var engine := TickEngine.new(repo)
	for i in int(repo.bal("courier_max_days")) + 1:
		if s.couriers.is_empty():
			break
		engine.advance_day(s)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH)
	assert_true(s.regiments[code].has("route_m"), "delivered, it marches its route")


func test_a_march_without_waypoints_carries_none() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var rt := _route(s, r)
	actions.execute(ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": rt["to"].x, "y": rt["to"].y}), s)
	assert_false((s.couriers[0]["order"] as Dictionary).has("waypoints_m"))


func test_a_draft_keeps_its_waypoints_and_its_load() -> void:
	var s := SuiteData.campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var rt := _route(s, r)
	var carry := ArmySystem.carry_of(repo, s.regiments[code])
	var other := 30 if carry != 30 else 10
	WarDrafts.plant(repo, s, code, WarDrafts.MARCH, rt["to"], [rt["wp"]], other)
	var d := WarDrafts.of(s, code)
	var wm := ArmySystem.pack_to_metres(repo, rt["wp"])
	assert_eq(d["waypoints_m"], [[wm.x, wm.y]])
	assert_eq(int(d["carry_days"]), other)
	assert_eq(WarDrafts.waypoints_px(repo, d), PackedVector2Array([ArmySystem.metres_to_pack(repo, wm)]))
	var reqs := WarDrafts.requests_from(repo, s, code, d)
	assert_eq(reqs.size(), 2, "the load first, then the march")
	assert_eq((reqs[0] as ActionRequest).action_code, "SUPPLY_CARRY_SET")
	assert_eq(int((reqs[0] as ActionRequest).params["days"]), other)
	assert_eq((reqs[1] as ActionRequest).action_code, "ARMY_MARCH")
	assert_eq((reqs[1] as ActionRequest).params["waypoints"].size(), 1)
	WarDrafts.plant(repo, s, code, WarDrafts.MARCH, rt["to"], [], carry)
	assert_eq(WarDrafts.requests_from(repo, s, code, WarDrafts.of(s, code)).size(), 1,
		"the load it already carries is no order")
	assert_false(WarDrafts.of(s, code).has("waypoints_m"), "a straight draft keeps none")
	WarDrafts.plant(repo, s, code, WarDrafts.MARCH, rt["to"], [rt["wp"]], other)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(WarDrafts.of(back, code)["waypoints_m"], [[wm.x, wm.y]], "a draft's route survives the save")
	assert_true(WarDrafts.of(back, code)["waypoints_m"][0][0] is int)
