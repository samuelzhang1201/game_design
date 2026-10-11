extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## One courier per target batch (owner 2026-10-10: 同一个信使发送目的地和补给信息，
## 如果信息传递的target是同一个object，只需要一个信使): the march's supply point, load
## and march ride as ONE courier to the regiment, for one fee, run in sequence
## on delivery under one id, with one receipt (ground truth); a courier record
## holds `orders`, and an old save's single `order` loads as `orders` of one.

var repo: DataRepository
var s: GameState
var actions: ActionSystem


func before_all() -> void:
	RoadGraph.forget()


func after_all() -> void:
	RoadGraph.forget()


func before_each() -> void:
	repo = SuiteData.repo()
	Weather.forget()
	s = SuiteData.campaign(repo, 42)
	s.couriers.clear()
	s.missives.clear()
	actions = ActionSystem.new(repo)
	s.metrics["treasury"] = 1000.0


func _land() -> String:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		var r := ArmySystem.regiment(repo, String(c))
		if String(r.get("is_naval", "0")) != "1" and ArmySystem.base_pace_km(repo, r) > 0:
			return String(c)
	return ""


func _eligible(code: String) -> String:
	var e := SupplyLines.mark_ahead(repo, s, code, SupplyLines.eligibility(repo, s, code))
	var towns: Array = e.keys()
	towns.sort()
	for t: String in towns:
		if String(e[t]) == "":
			return t
	return ""


func _dest(code: String) -> Vector2:
	var home: Vector2 = ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code))
	for i in range(3, 60):
		var probe := home + Vector2(float(i), 0.0)
		if MapEconomy.cell_at(repo, probe) >= 0:
			return probe
	return Vector2.ZERO


## The march's confirm: supply point (with_column), load, march.
func _march_batch(code: String, town: String, dest: Vector2) -> Array:
	return [
		ActionRequest.make("SUPPLY_POINT_SET", {"regiment": code, "town": town, "rate": 1000, "with_column": true}),
		ActionRequest.make("SUPPLY_CARRY_SET", {"regiment": code, "days": 10}),
		ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": dest.x, "y": dest.y}),
	]


func _ride_out() -> Array:
	var events: Array = []
	for i in int(repo.bal("courier_max_days")) + 1:
		if s.couriers.is_empty():
			break
		events.append_array(CourierSystem.ride_day(repo, s))
	return events


func test_the_march_batch_is_one_courier_one_fee() -> void:
	var code := _land()
	var town := _eligible(code)
	var dest := _dest(code)
	if town == "" or dest == Vector2.ZERO:
		pending("no town or ground in reach")
		return
	var before := float(s.metrics["treasury"])
	var own_costs := 0.0
	for req: ActionRequest in _march_batch(code, town, dest):
		assert_eq(actions.validate(req, s), "", req.action_code)
		assert_true(bool(actions.execute(req, s).get("ok", false)), req.action_code)
		own_costs += OrderCosts.gold_of(repo, req.action_code)
	assert_eq(s.couriers.size(), 1, "one courier carries all three")
	var c: Dictionary = s.couriers[0]
	assert_eq(CourierSystem.orders_of(c).map(func(o: Dictionary) -> String: return String(o["action_code"])),
		["SUPPLY_POINT_SET", "SUPPLY_CARRY_SET", "ARMY_MARCH"], "in the order given")
	assert_eq(String(CourierSystem.first_order(c).get("to_town", "")), "", "the warrant rides to the column")
	var reg_at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)))
	assert_eq(Vector2i(int(c["aim_x_m"]), int(c["aim_y_m"])), reg_at, "he rides for the regiment")
	assert_almost_eq(before - float(s.metrics["treasury"]),
		own_costs + float(CourierSystem.fee_gold(repo, CourierSystem.ORDINARY)), 0.001, "one fee")
	assert_eq(int(SupplyLines.line(s, code)["order_id"]), int(c["id"]), "the line waits on his id")
	assert_eq(String(SupplyLines.line(s, code)["state"]), SupplyLines.ORDERED)
	assert_eq(CourierSystem.pending_for(s, code), c, "he is the march's courier")
	var events := _ride_out()
	var day := s.absolute_day()
	assert_true(s.couriers.is_empty())
	var ev: Dictionary = events.back()
	assert_eq(String(ev["type"]), "delivered")
	var ln := SupplyLines.line(s, code)
	assert_eq(String(ln["state"]), SupplyLines.RIDING, "the wagons leave the town on his delivery")
	var days := SupplyLines.wagon_days(repo, SupplyLines.road_km(repo, SupplyLines.road_px(repo, s, code, town)))
	assert_eq(int(ln["ready_day"]), day + days, "ready the wagon days after his delivery day")
	assert_eq(SupplyLines.set_out_events(events), [{"type": "set_out", "regiment": code, "town": town, "days": days}])
	assert_eq(ArmySystem.carry_of(repo, s.regiments[code]), 10)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH)
	assert_eq(int(s.regiments[code]["order_id"]), int(c["id"]))
	var receipts: Array = s.missives.filter(func(m: Dictionary) -> bool: return String(m["kind"]) == "receipt")
	assert_eq(receipts.size(), 1, "one receipt")
	var r: Dictionary = receipts[0]
	assert_eq(String(r["column"]), "truth")
	var said: Array = (r["facts"] as Array).filter(func(f: Dictionary) -> bool: return String(f["label"]) == "Orders") \
		.map(func(f: Dictionary) -> String: return String(f["text"]))
	assert_eq(said, ["Supply from %s at 1.0×" % String(repo.burgs[town]["label"]), "Carry 10 days", "March"])
	var letter := MissiveWriter.supply_dispatch(repo, s, SupplyLines.set_out_events(events))
	assert_eq(String(letter["column"]), "truth")
	assert_string_contains(String(letter["facts"][0]["text"]), "set out from %s" % String(repo.burgs[town]["label"]))


func test_a_courier_on_the_road_takes_no_more_orders() -> void:
	var code := _land()
	var dest := _dest(code)
	actions.execute(ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": dest.x, "y": dest.y}), s)
	CourierSystem.ride_day(repo, s)
	if s.couriers.is_empty():
		pending("delivered in a day")
		return
	actions.execute(ActionRequest.make("SUPPLY_CARRY_SET", {"regiment": code, "days": 10}), s)
	assert_eq(s.couriers.size(), 2, "he has set out: a courier of its own")


func test_a_lone_supply_point_rides_to_the_town_unless_a_courier_waits() -> void:
	var code := _land()
	var town := _eligible(code)
	if town == "":
		pending("no town in reach")
		return
	actions.execute(ActionRequest.make("SUPPLY_POINT_SET", {"regiment": code, "town": town, "rate": 1000}), s)
	assert_eq(String(CourierSystem.first_order(s.couriers[0]).get("to_town", "")), town, "to the town")
	s.couriers.clear()
	s.supply_lines.clear()
	actions.execute(ActionRequest.make("ARMY_STANCE", {"regiment": code, "stance": "hold"}), s)
	var before := float(s.metrics["treasury"])
	actions.execute(ActionRequest.make("SUPPLY_POINT_SET", {"regiment": code, "town": town, "rate": 1000}), s)
	assert_eq(s.couriers.size(), 1, "rides with the stance's courier")
	assert_eq(String(CourierSystem.order_with(s.couriers[0], ["SUPPLY_POINT_SET"]).get("to_town", "")), "")
	assert_almost_eq(before - float(s.metrics["treasury"]), OrderCosts.gold_of(repo, "SUPPLY_POINT_SET"), 0.001,
		"no second fee")


func test_a_multi_order_courier_survives_the_save() -> void:
	var code := _land()
	var town := _eligible(code)
	var dest := _dest(code)
	if town == "" or dest == Vector2.ZERO:
		pending("no town or ground in reach")
		return
	for req: ActionRequest in _march_batch(code, town, dest):
		actions.execute(req, s)
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.couriers.size(), 1)
	assert_eq(JSON.stringify(CourierSystem.orders_of(back.couriers[0])), JSON.stringify(CourierSystem.orders_of(s.couriers[0])))
	assert_false((back.couriers[0] as Dictionary).has("order"))


func test_an_old_save_courier_loads_with_orders_of_one() -> void:
	var code := _land()
	actions.execute(ActionRequest.make("ARMY_GARRISON", {"regiment": code}), s)
	var d: Dictionary = s.to_dict()
	var raw: Dictionary = JSON.parse_string(JSON.stringify(d))
	for c: Dictionary in raw["couriers"]:
		c["order"] = (c["orders"] as Array)[0]
		c.erase("orders")
	var old := GameState.from_dict(raw)
	assert_eq(old.couriers.size(), 1)
	assert_false((old.couriers[0] as Dictionary).has("order"))
	assert_eq(String(CourierSystem.first_order(old.couriers[0])["action_code"]), "ARMY_GARRISON")
	assert_eq(CourierSystem.pending_for(old, code), old.couriers[0], "read as a halt")
