extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## ARMY_MARCH / ARMY_GARRISON send a courier (spec 2026-09-27-courier-core §1).

var repo: DataRepository


## The pack's road graph is cached by map id and every test's repository
## carries the same routes and road speeds, so it is built once per script
## (and forgotten around it, so no other script's graph is read).
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


func _land_near(s: GameState, r: Dictionary) -> Vector2:
	var home: Vector2 = ArmySystem.position_of(repo, s, r)
	for i in range(3, 60):
		var probe := home + Vector2(float(i), 0.0)
		if MapEconomy.cell_at(repo, probe) >= 0:
			return probe
	return Vector2.ZERO


func test_the_order_rides_and_the_regiment_waits() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var dest := _land_near(s, r)
	if dest == Vector2.ZERO:
		return
	var home: Vector2 = ArmySystem.position_of(repo, s, r)
	var before: float = s.metrics["treasury"]
	var req := ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": dest.x, "y": dest.y})
	assert_eq(actions.validate(req, s), "")
	var out: Dictionary = actions.execute(req, s)
	assert_eq(s.couriers.size(), 1, "one courier rides")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_STANDBY, "the column waits for him")
	assert_eq(ArmySystem.position_of(repo, s, r), home, "and has not moved")
	var fee := false
	for e: Dictionary in out.get("effects", []):
		if String(e["metric"]) == "treasury" and String(e["reason"]).begins_with("a courier rides for"):
			fee = is_equal_approx(float(e["delta"]), -float(CourierSystem.fee_gold(repo, CourierSystem.ORDINARY)))
	assert_true(fee, "the fee is a ledger line with its reason")
	assert_lt(float(s.metrics["treasury"]), before)
	for day in int(repo.bal("courier_max_days")):
		CourierSystem.ride_day(repo, s)
		if s.couriers.is_empty():
			break
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH, "delivered: now it marches")


func test_king_in_command_range_delivers_army_order_without_a_courier_or_fee() -> void:
	var s := SuiteData.campaign(repo, 70)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var pos := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, r))
	var old_dest := _land_near(s, r)
	CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code,
		{"action_code": "ARMY_MARCH", "dest_x_m": ArmySystem.pack_to_metres(repo, old_dest + Vector2(8.0, 0.0)).x,
		"dest_y_m": ArmySystem.pack_to_metres(repo, old_dest + Vector2(8.0, 0.0)).y})
	s.regiments[code]["x_m"] = pos.x
	s.regiments[code]["y_m"] = pos.y
	s.regiments[code]["camp_town"] = ""
	s.king_state["x_m"] = pos.x
	s.king_state["y_m"] = pos.y
	var dest := _land_near(s, r)
	assert_ne(dest, Vector2.ZERO)
	var dest_m := ArmySystem.pack_to_metres(repo, dest)
	var treasury := float(s.metrics["treasury"])
	var req := ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": dest.x, "y": dest.y})
	assert_eq(actions.validate(req, s), "")
	var expected_days := ArmySystem.march_days_between(repo, s, code, ArmySystem.position_of(repo, s, r),
		dest, s.absolute_day())
	assert_eq(CourierSystem.arrival_days(repo, s, code, dest), expected_days,
		"a local march preview has no courier day")
	var result := actions.execute(req, s)
	assert_true(result["ok"])
	assert_eq(s.couriers.size(), 1, "the local order adds no courier")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH)
	assert_eq(float(s.metrics["treasury"]), treasury - OrderCosts.gold_of(repo, "ARMY_MARCH"))
	var old_id := int(s.couriers[0]["id"])
	assert_gt(int(s.regiments[code]["order_id"]), old_id, "a local order supersedes the waiting remote order")
	assert_true(CourierSystem.pending_for(s, code).is_empty(), "superseded courier does not delay the local order")
	for _day in int(repo.bal("courier_max_days")):
		CourierSystem.ride_day(repo, s)
		if s.couriers.is_empty():
			break
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH,
		"the older courier cannot overwrite the newer local order")
	assert_eq(int(s.regiments[code]["order_id"]), int(old_id) + 1)
	assert_eq(Vector2i(int(s.regiments[code]["dest_x_m"]), int(s.regiments[code]["dest_y_m"])), dest_m)


func test_garrison_rides_too() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	ArmySystem.set_march(repo, s, code, ArmySystem.position_of(repo, s, r) + Vector2(200.0, 0.0))
	actions.execute(ActionRequest.make("ARMY_GARRISON", {"regiment": code}), s)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH, "still marching until the courier comes")
	assert_eq(s.couriers.size(), 1)


## Fix round 1 (review finding): the courier's fee and the order's own
## always-charged cost were checked independently against the same starting
## treasury, so a chest could pass both checks and still go negative
## (e.g. treasury == fee alone let ARMY_GARRISON's own -1 gold through too).
## Pin the exact window: refused half a gold under fee + the order's own
## cost, and clear exactly at it — the same pattern MANOR_BUY already uses
## (price + needs).
func test_the_garrison_window_is_the_fee_and_the_orders_own_cost() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var req := ActionRequest.make("ARMY_GARRISON", {"regiment": String(_marcher()["regiment_code"])})
	var needs := OrderCosts.gold_of(repo, "ARMY_GARRISON") + float(CourierSystem.fee_gold(repo, CourierSystem.ORDINARY))
	s.metrics["treasury"] = needs - 0.5
	assert_string_contains(actions.validate(req, s), "courier", "half a gold under the window")
	s.metrics["treasury"] = needs
	assert_eq(actions.validate(req, s), "", "exactly at the window")


func test_the_march_window_is_the_fee_and_the_orders_own_cost() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var dest := _land_near(s, r)
	assert_ne(dest, Vector2.ZERO, "open land near the regiment")
	var req := ActionRequest.make("ARMY_MARCH", {"regiment": String(r["regiment_code"]), "x": dest.x, "y": dest.y})
	var needs := OrderCosts.gold_of(repo, "ARMY_MARCH") + float(CourierSystem.fee_gold(repo, CourierSystem.ORDINARY))
	s.metrics["treasury"] = needs - 0.5
	assert_string_contains(actions.validate(req, s), "courier", "half a gold under the window")
	s.metrics["treasury"] = needs
	assert_eq(actions.validate(req, s), "", "exactly at the window")


func test_a_fleets_orders_apply_at_once() -> void:
	var s := SuiteData.campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) == "1":
			actions.execute(ActionRequest.make("ARMY_GARRISON", {"regiment": String(r["regiment_code"])}), s)
			assert_eq(s.couriers, [], "a fleet takes no courier in sub-project A")
			return
	pass_test("this pack's realm has no fleet")
