extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A front's drafts through the engine (spec 2026-10-11-war-room-front-line-
## design §1, the architect's T1.3–T1.5): the march and its hold ride ONE
## courier, the hold is parked on the column and taken where the march
## arrives, a newer order drops it, and it all saves as whole ints.

var repo: DataRepository


func before_all() -> void:
	RoadGraph.forget()


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _near(v: Vector2, want: Vector2, what := "") -> void:
	assert_almost_eq(v.x, want.x, 0.0001, what)
	assert_almost_eq(v.y, want.y, 0.0001, what)


func _mine() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.base_pace_km(repo, r) > 0:
			return String(r["regiment_code"])
	return ""


func _front_draft(s: GameState, code: String, dx_px: float) -> Dictionary:
	var here := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code, s))
	WarDrafts.plant(repo, s, code, WarDrafts.MARCH, here + Vector2(dx_px, 0), [], -1, "", 0,
		{"stance": "hold", "facing": 90}, "f1")
	return WarDrafts.of(s, code)


func _deliver(s: GameState) -> void:
	for day in int(repo.bal("courier_max_days")):
		CourierSystem.ride_day(repo, s)
		if s.couriers.is_empty():
			return


func _arrive(s: GameState, code: String) -> void:
	for day in 60:
		if ArmySystem.order_of(repo, s, code) != ArmySystem.ORDER_MARCH:
			return
		ArmySystem.march_day(repo, s)
		BattleSystem.settle_stances(s)


func test_the_draft_stands_for_a_march_and_a_hold_on_one_courier() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _mine()
	s.metrics["treasury"] = 1000.0
	var d := _front_draft(s, code, 20.0)
	assert_eq(d["hold"], {"stance": "hold", "facing": 90})
	assert_eq(String(d["front"]), "f1")
	var reqs := WarDrafts.requests_from(repo, s, code, d)
	assert_eq(reqs.map(func(r: ActionRequest) -> String: return r.action_code), ["ARMY_MARCH", "ARMY_STANCE"])
	assert_eq(reqs[1].params["stance"], "hold")
	assert_eq(int(reqs[1].params["facing"]), 90)
	assert_true(bool(reqs[1].params["on_arrival"]))
	var actions := ActionSystem.new(repo)
	for r: ActionRequest in reqs:
		assert_eq(actions.validate(r, s), "", r.action_code + " is legal")
		actions.execute(r, s)
	assert_eq(s.couriers.size(), 1, "the hold rides the march's courier")
	var orders: Array = s.couriers[0]["orders"]
	assert_eq(orders.map(func(o: Dictionary) -> String: return String(o["action_code"])), ["ARMY_MARCH", "ARMY_STANCE"])
	assert_true(bool(orders[1]["on_arrival"]))
	assert_eq(int(orders[1]["facing"]), 90)
	var fee := float(CourierSystem.fee_gold(repo, CourierSystem.ORDINARY))
	assert_almost_eq(float(s.metrics["treasury"]), 1000.0 - 2.0 - 1.0 - fee, 0.001,
		"the march's 2, the stance's 1 and ONE fee")


func test_local_arrival_hold_keeps_its_march_link_and_new_stance_order_id() -> void:
	var s := SuiteData.campaign(repo, 71)
	var code := _mine()
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code, s)))
	s.king_state["x_m"] = at.x
	s.king_state["y_m"] = at.y
	s.metrics["treasury"] = 1000.0
	var actions := ActionSystem.new(repo)
	for req: ActionRequest in WarDrafts.requests_from(repo, s, code, _front_draft(s, code, 20.0)):
		assert_eq(actions.validate(req, s), "")
		actions.execute(req, s)
	actions.execute(ActionRequest.make("ARMY_STANCE", {"regiment": code, "stance": "evade"}), s)
	actions.execute(ActionRequest.make("ARMY_STANCE", {"regiment": code, "stance": "hold",
		"facing": 90, "on_arrival": true}), s)
	assert_true(s.couriers.is_empty(), "all commands are delivered locally")
	assert_true(s.regiments[code].has("hold_after"))
	assert_gt(int(s.regiments[code]["hold_after"]["id"]), int(s.regiments[code]["stance_order_id"]))
	assert_eq(int(s.regiments[code]["hold_after"]["id"]), s.next_courier_id)
	assert_eq(String(s.regiments[code]["stance_next"]), "evade", "the new hold waits for arrival")
	_arrive(s, code)
	BattleSystem.settle_stances(s)
	assert_eq(String(s.regiments[code]["stance"]), "hold", "the newer arrival hold activates")


func test_a_halt_with_a_hold_takes_it_at_once() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _mine()
	var here := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code, s))
	WarDrafts.plant(repo, s, code, WarDrafts.GARRISON, here, [], -1, "", 0, {"stance": "hold", "facing": 270}, "f1")
	var reqs := WarDrafts.requests_from(repo, s, code, WarDrafts.of(s, code))
	assert_eq(reqs.map(func(r: ActionRequest) -> String: return r.action_code), ["ARMY_GARRISON", "ARMY_STANCE"])
	assert_false(reqs[1].params.has("on_arrival"))
	var actions := ActionSystem.new(repo)
	for r: ActionRequest in reqs:
		actions.execute(r, s)
	_deliver(s)
	assert_false(s.regiments[code].has("hold_after"))
	assert_eq(String(s.regiments[code]["stance_next"]), "hold")
	assert_eq(int(s.regiments[code]["facing_deg"]), 270)
	BattleSystem.settle_stances(s)
	assert_eq(String(s.regiments[code]["stance"]), "hold")
	_near(ArmySystem.facing_of(s, code), Vector2(0, -1), "faces north")


func test_the_hold_waits_for_the_arrival() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _mine()
	s.metrics["treasury"] = 1000.0
	var actions := ActionSystem.new(repo)
	for r: ActionRequest in WarDrafts.requests_from(repo, s, code, _front_draft(s, code, 20.0)):
		actions.execute(r, s)
	_deliver(s)
	var e: Dictionary = s.regiments[code]
	assert_eq(String(e["order"]), ArmySystem.ORDER_MARCH)
	assert_eq(e["hold_after"], {"stance": "hold", "facing": 90, "id": int(e["order_id"])})
	assert_eq(String(e["stance"]), "steady")
	assert_false(e.has("stance_next"))
	assert_false(e.has("facing_deg"))
	assert_eq(ArmySystem.facing_of(s, code), Vector2.ZERO, "no facing while marching")
	_arrive(s, code)
	assert_eq(String(e["order"]), ArmySystem.ORDER_GARRISON, "arrived and holding its ground")
	assert_false(e.has("hold_after"))
	assert_eq(int(e["facing_deg"]), 90)
	assert_eq(String(e["stance"]), "hold", "settled at the day's end")
	_near(ArmySystem.facing_of(s, code), Vector2(0, 1), "faces south")
	_near(ArmySystem.piece_heading(repo, s, code), Vector2(0, 1), "the piece turns to it")


func test_a_newer_march_drops_the_hold_and_a_newer_stance_wins() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _mine()
	s.metrics["treasury"] = 1000.0
	var actions := ActionSystem.new(repo)
	for r: ActionRequest in WarDrafts.requests_from(repo, s, code, _front_draft(s, code, 20.0)):
		actions.execute(r, s)
	_deliver(s)
	var e: Dictionary = s.regiments[code]
	assert_true(e.has("hold_after"))
	# (a) a plain march delivered mid-way: no front
	var here := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code, s))
	actions.execute(ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": here.x + 25.0, "y": here.y}), s)
	_deliver(s)
	assert_false(e.has("hold_after"))
	_arrive(s, code)
	assert_eq(String(e["stance"]), "steady")
	assert_false(e.has("facing_deg"))
	# (b) a newer stance (evade) mid-way: the arrival keeps evade, takes the facing
	var t := SuiteData.campaign(repo, 7)
	t.metrics["treasury"] = 1000.0
	for r: ActionRequest in WarDrafts.requests_from(repo, t, code, _front_draft(t, code, 20.0)):
		actions.execute(r, t)
	_deliver(t)
	actions.execute(ActionRequest.make("ARMY_STANCE", {"regiment": code, "stance": "evade"}), t)
	_deliver(t)
	BattleSystem.settle_stances(t)
	assert_eq(String(t.regiments[code]["stance"]), "evade")
	_arrive(t, code)
	assert_eq(String(t.regiments[code]["stance"]), "evade", "the newer stance order wins")
	assert_eq(int(t.regiments[code]["facing_deg"]), 90, "the facing is taken all the same")
	# (d) a battle's halt drops a parked hold
	var u := SuiteData.campaign(repo, 7)
	u.metrics["treasury"] = 1000.0
	for r: ActionRequest in WarDrafts.requests_from(repo, u, code, _front_draft(u, code, 20.0)):
		actions.execute(r, u)
	_deliver(u)
	assert_true(u.regiments[code].has("hold_after"))
	BattleSystem._halt(u, code)
	assert_false(u.regiments[code].has("hold_after"))


func test_a_facing_must_be_a_whole_degree_and_it_all_saves() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _mine()
	var actions := ActionSystem.new(repo)
	for bad: int in [360, -1]:
		assert_string_contains(actions.validate(ActionRequest.make("ARMY_STANCE",
			{"regiment": code, "stance": "hold", "facing": bad}), s), "No such facing")
	assert_eq(actions.validate(ActionRequest.make("ARMY_STANCE", {"regiment": code, "stance": "hold", "facing": 359}), s), "")
	s.regiments[code]["facing_deg"] = 90
	s.regiments[code]["hold_after"] = {"stance": "hold", "facing": 90, "id": 3}
	_front_draft(s, code, 20.0)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())), false)
	assert_eq(typeof(back.regiments[code]["facing_deg"]), TYPE_INT)
	assert_eq(back.regiments[code]["hold_after"], {"stance": "hold", "facing": 90, "id": 3})
	assert_eq(typeof(back.regiments[code]["hold_after"]["id"]), TYPE_INT)
	assert_eq(back.war_drafts[code]["hold"], {"stance": "hold", "facing": 90})
	assert_eq(typeof(back.war_drafts[code]["hold"]["facing"]), TYPE_INT)
	assert_eq(String(back.war_drafts[code]["front"]), "f1")
