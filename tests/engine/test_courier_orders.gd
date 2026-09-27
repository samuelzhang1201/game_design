extends GutTest
## ARMY_MARCH / ARMY_GARRISON send a courier (spec 2026-09-27-courier-core §1).

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	RoadGraph.forget()
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
	var s := GameState.new_campaign(repo, 7)
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
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_GARRISON, "the column waits for him")
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


func test_garrison_rides_too() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	ArmySystem.set_march(repo, s, code, ArmySystem.position_of(repo, s, r) + Vector2(200.0, 0.0))
	actions.execute(ActionRequest.make("ARMY_GARRISON", {"regiment": code}), s)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH, "still marching until the courier comes")
	assert_eq(s.couriers.size(), 1)


func test_a_chest_too_thin_for_the_courier_is_refused() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var code := String(_marcher()["regiment_code"])
	# ARMY_GARRISON's own cost is 1 gold (order_costs.csv); the fee is more
	# than what is left over it.
	s.metrics["treasury"] = float(CourierSystem.fee_gold(repo, CourierSystem.ORDINARY)) - 0.5
	assert_string_contains(actions.validate(ActionRequest.make("ARMY_GARRISON", {"regiment": code}), s), "courier")


## Fix round 1 (review finding): the courier's fee and the order's own
## always-charged cost were checked independently against the same starting
## treasury, so a chest could pass both checks and still go negative
## (e.g. treasury == fee alone let ARMY_GARRISON's own -1 gold through too).
## Pin the exact window: refused half a gold under fee + the order's own
## cost, and clear exactly at it — the same pattern MANOR_BUY already uses
## (price + needs).
func test_a_garrison_chest_half_a_gold_under_the_full_window_is_refused() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var code := String(_marcher()["regiment_code"])
	var needs := OrderCosts.gold_of(repo, "ARMY_GARRISON") + float(CourierSystem.fee_gold(repo, CourierSystem.ORDINARY))
	s.metrics["treasury"] = needs - 0.5
	assert_string_contains(actions.validate(ActionRequest.make("ARMY_GARRISON", {"regiment": code}), s), "courier")


func test_a_garrison_chest_exactly_at_the_full_window_validates() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var code := String(_marcher()["regiment_code"])
	var needs := OrderCosts.gold_of(repo, "ARMY_GARRISON") + float(CourierSystem.fee_gold(repo, CourierSystem.ORDINARY))
	s.metrics["treasury"] = needs
	assert_eq(actions.validate(ActionRequest.make("ARMY_GARRISON", {"regiment": code}), s), "")


func test_a_march_chest_half_a_gold_under_the_full_window_is_refused() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var dest := _land_near(s, r)
	if dest == Vector2.ZERO:
		return
	var needs := OrderCosts.gold_of(repo, "ARMY_MARCH") + float(CourierSystem.fee_gold(repo, CourierSystem.ORDINARY))
	s.metrics["treasury"] = needs - 0.5
	assert_string_contains(actions.validate(ActionRequest.make("ARMY_MARCH",
		{"regiment": code, "x": dest.x, "y": dest.y}), s), "courier")


func test_a_march_chest_exactly_at_the_full_window_validates() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var dest := _land_near(s, r)
	if dest == Vector2.ZERO:
		return
	var needs := OrderCosts.gold_of(repo, "ARMY_MARCH") + float(CourierSystem.fee_gold(repo, CourierSystem.ORDINARY))
	s.metrics["treasury"] = needs
	assert_eq(actions.validate(ActionRequest.make("ARMY_MARCH",
		{"regiment": code, "x": dest.x, "y": dest.y}), s), "")


func test_a_fleets_orders_apply_at_once() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) == "1":
			actions.execute(ActionRequest.make("ARMY_GARRISON", {"regiment": String(r["regiment_code"])}), s)
			assert_eq(s.couriers, [], "a fleet takes no courier in sub-project A")
			return
	pass_test("this pack's realm has no fleet")
