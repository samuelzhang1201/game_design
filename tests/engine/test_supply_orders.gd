extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Supply orders ride by courier (spec 2026-10-07-army-supply-lines §4).

var repo: DataRepository
var s: GameState
var actions: ActionSystem
var engine: TickEngine

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	actions = ActionSystem.new(repo)
	engine = TickEngine.new(repo)
	s.metrics["treasury"] = 1000.0

func _land() -> String:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			return String(c)
	return ""

func _eligible(code: String) -> String:
	var e := SupplyLines.eligibility(repo, s, code)
	var towns: Array = e.keys()
	towns.sort()
	for t: String in towns:
		if String(e[t]) == "":
			return t
	return ""

func _run_until_no_couriers() -> void:
	for i in int(repo.bal("courier_max_days")) + 1:
		if s.couriers.is_empty():
			return
		engine.advance_day(s)

func test_set_rides_to_the_town_and_opens_the_line_on_delivery() -> void:
	var code := _land()
	var town := _eligible(code)
	var req := ActionRequest.make("SUPPLY_POINT_SET", {"regiment": code, "town": town, "rate": 1200})
	assert_eq(actions.validate(req, s), "")
	actions.execute(req, s)
	assert_eq(s.couriers.size(), 1)
	var c: Dictionary = s.couriers[0]
	var b: Dictionary = repo.burgs[town]
	assert_eq(Vector2i(int(c["aim_x_m"]), int(c["aim_y_m"])),
		ArmySystem.pack_to_metres(repo, Vector2(float(b["x"]), float(b["y"]))), "he rides for the town")
	assert_eq(String(SupplyLines.line(s, code).get("state", "")), SupplyLines.ORDERED)
	_run_until_no_couriers()
	var ln := SupplyLines.line(s, code)
	assert_true(String(ln["state"]) in [SupplyLines.RIDING, SupplyLines.FLOWING])
	assert_eq(String(ln["town"]), town)
	assert_eq(int(ln["rate"]), 1200)

func test_refusals() -> void:
	var code := _land()
	assert_ne(actions.validate(ActionRequest.make("SUPPLY_POINT_SET",
		{"regiment": code, "town": _eligible(code), "rate": 900}), s), "", "a rate not in the table")
	assert_ne(actions.validate(ActionRequest.make("SUPPLY_POINT_CLEAR", {"regiment": code}), s), "",
		"no line to withdraw")
	assert_ne(actions.validate(ActionRequest.make("SUPPLY_CARRY_SET", {"regiment": code, "days": 12}), s), "",
		"12 days is not a load")
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if String(r.get("is_naval", "0")) == "1":
			assert_ne(actions.validate(ActionRequest.make("SUPPLY_CARRY_SET",
				{"regiment": String(r["regiment_code"]), "days": 20}), s), "", "a fleet carries no train")
			break

func test_carry_rides_to_the_regiment_and_sets_the_load() -> void:
	var code := _land()
	actions.execute(ActionRequest.make("SUPPLY_CARRY_SET", {"regiment": code, "days": 30}), s)
	assert_eq(ArmySystem.carry_of(repo, s.regiments[code]), 20, "not before he arrives")
	_run_until_no_couriers()
	assert_eq(ArmySystem.carry_of(repo, s.regiments[code]), 30)

func test_clear_ends_the_line_when_its_courier_reaches_the_town() -> void:
	var code := _land()
	actions.execute(ActionRequest.make("SUPPLY_POINT_SET", {"regiment": code, "town": _eligible(code), "rate": 1000}), s)
	_run_until_no_couriers()
	actions.execute(ActionRequest.make("SUPPLY_POINT_CLEAR", {"regiment": code}), s)
	assert_false(SupplyLines.line(s, code).is_empty(), "the wagons run until he arrives")
	_run_until_no_couriers()
	assert_true(SupplyLines.line(s, code).is_empty())

func _order_set(code: String, town: String, rate: int) -> Dictionary:
	actions.execute(ActionRequest.make("SUPPLY_POINT_SET", {"regiment": code, "town": town, "rate": rate}), s)
	return s.couriers[s.couriers.size() - 1]

func test_a_newer_set_survives_an_older_clear() -> void:
	var code := _land()
	var town := _eligible(code)
	_order_set(code, town, 1000)
	_run_until_no_couriers()
	actions.execute(ActionRequest.make("SUPPLY_POINT_CLEAR", {"regiment": code}), s)
	var again := _order_set(code, town, 1200)
	_run_until_no_couriers()
	var ln := SupplyLines.line(s, code)
	assert_false(ln.is_empty(), "the second SET outlives the CLEAR before it")
	assert_eq(int(ln["rate"]), 1200)
	assert_eq(int(ln["order_id"]), int(again["id"]))
	assert_true(String(ln["state"]) in [SupplyLines.RIDING, SupplyLines.FLOWING])

func test_an_older_clear_arriving_first_leaves_the_new_point_waiting() -> void:
	var code := _land()
	var town := _eligible(code)
	_order_set(code, town, 1000)
	_run_until_no_couriers()
	actions.execute(ActionRequest.make("SUPPLY_POINT_CLEAR", {"regiment": code}), s)
	var clear: Dictionary = s.couriers[s.couriers.size() - 1]
	var again := _order_set(code, town, 800)
	SupplyLines.deliver(repo, s, clear)
	var ln := SupplyLines.line(s, code)
	assert_false(ln.is_empty())
	assert_eq(String(ln["state"]), SupplyLines.ORDERED, "waiting for the SET's courier")
	assert_eq(int(ln["order_id"]), int(again["id"]))
	SupplyLines.deliver(repo, s, again)
	assert_eq(String(SupplyLines.line(s, code)["state"]), SupplyLines.RIDING)
	assert_eq(int(SupplyLines.line(s, code)["rate"]), 800)

func test_a_clear_issued_before_the_set_arrives_leaves_no_line() -> void:
	var code := _land()
	_order_set(code, _eligible(code), 1000)
	actions.execute(ActionRequest.make("SUPPLY_POINT_CLEAR", {"regiment": code}), s)
	_run_until_no_couriers()
	assert_true(SupplyLines.line(s, code).is_empty())

func test_a_replacing_point_keeps_the_months_counters() -> void:
	var code := _land()
	var town := _eligible(code)
	_order_set(code, town, 1000)
	_run_until_no_couriers()
	var ln := SupplyLines.line(s, code)
	ln["m_drawn"] = 7
	ln["m_fee"] = 3
	ln["fee_milli"] = 450
	ln["m_bought"] = {"grain": 2}
	_order_set(code, town, 1200)
	_run_until_no_couriers()
	ln = SupplyLines.line(s, code)
	assert_eq(int(ln["rate"]), 1200)
	assert_eq(int(ln["m_drawn"]), 7)
	assert_eq(int(ln["m_fee"]), 3)
	assert_eq(int(ln["fee_milli"]), 450)
	assert_eq(ln["m_bought"], {"grain": 2})

func test_a_supply_courier_does_not_move_the_march_readers() -> void:
	var code := _land()
	var at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code))
	var dest := Vector2.ZERO
	var towns: Array = SupplyLines.eligibility(repo, s, code).keys()
	towns.sort()
	for t: String in towns:
		var p := Vector2(float(repo.burgs[t]["x"]), float(repo.burgs[t]["y"]))
		if p.distance_to(at) > 5.0:
			dest = p
			break
	assert_ne(dest, Vector2.ZERO, "a town to march to")
	actions.execute(ActionRequest.make("ARMY_MARCH", {"regiment": code, "x": dest.x, "y": dest.y}), s)
	var before := CourierSystem.days_to_arrival(repo, s, code)
	var march: Dictionary = CourierSystem.pending_for(s, code)
	assert_eq(String(march["order"]["action_code"]), "ARMY_MARCH")
	actions.execute(ActionRequest.make("SUPPLY_CARRY_SET", {"regiment": code, "days": 10}), s)
	assert_eq(int(CourierSystem.pending_for(s, code)["id"]), int(march["id"]), "the carry courier is not the march's")
	assert_eq(CourierSystem.days_to_arrival(repo, s, code), before)

func test_a_town_bound_courier_is_named_by_its_town() -> void:
	var code := _land()
	var town := _eligible(code)
	var c := _order_set(code, town, 1000)
	var tl := String(repo.burgs[town]["label"])
	var rl := String(ArmySystem.regiment(repo, code)["label"])
	assert_eq(CourierCard.title(repo, s, int(c["id"])), "Courier to " + tl)
	var fields: Array = CourierCard.card(repo, s, int(c["id"]))["fields"]
	assert_eq(String(fields[0][1]), "Supply orders for " + rl)
	var e := CourierSystem.setting_out(repo, s, 0)[0] as Dictionary
	assert_eq(String(e["town"]), town)
	assert_eq(CourierSystem.headline(repo, e), "A courier %s %s with supply orders for %s." % [
		"leaves the capital for" if int(e["capital"]) == 1 else "rides for", tl, rl])
	var d := SupplyLines.deliver(repo, s, c)
	assert_eq(CourierSystem.headline(repo, d), "Supply orders for %s delivered at %s." % [rl, tl])
	actions.execute(ActionRequest.make("SUPPLY_CARRY_SET", {"regiment": code, "days": 25}), s)
	var carry: Dictionary = s.couriers[s.couriers.size() - 1]
	assert_eq(String(CourierCard.card(repo, s, int(carry["id"]))["fields"][0][1]), "Orders to carry 25 days")

## Final review 3: a new rate from the town the line already draws on keeps
## the wagons rolling — only the rate (and the order) change, no fresh ride.
func test_a_new_rate_from_the_same_town_keeps_the_line_flowing() -> void:
	var code := _land()
	var town := _eligible(code)
	for st: String in [SupplyLines.FLOWING, SupplyLines.CUT]:
		s.supply_lines.erase(code)
		s.couriers.clear()
		_order_set(code, town, 1000)
		_run_until_no_couriers()
		var ln := SupplyLines.line(s, code)
		ln["state"] = st
		ln["ready_day"] = 3
		ln["cut_by"] = "x" if st == SupplyLines.CUT else ""
		ln["m_drawn"] = 7
		ln["fee_milli"] = 450
		ln["warned"] = "town_low"
		var c := _order_set(code, town, 1200)
		assert_true(SupplyLines.line(s, code).has("pending"))
		SupplyLines.deliver(repo, s, c)
		ln = SupplyLines.line(s, code)
		assert_eq(String(ln["state"]), st, "still %s" % st)
		assert_eq(int(ln["rate"]), 1200)
		assert_eq(int(ln["order_id"]), int(c["id"]))
		assert_false(ln.has("pending"))
		assert_eq(int(ln["ready_day"]), 3)
		assert_eq(String(ln["cut_by"]), "x" if st == SupplyLines.CUT else "")
		assert_eq(int(ln["m_drawn"]), 7)
		assert_eq(int(ln["fee_milli"]), 450)
		assert_eq(String(ln["warned"]), "town_low")

## Another town is a new line: its wagons ride first.
func test_a_new_town_rides_afresh() -> void:
	var code := _land()
	var e := SupplyLines.eligibility(repo, s, code)
	var towns: Array = e.keys().filter(func(t: String) -> bool: return String(e[t]) == "")
	towns.sort()
	if towns.size() < 2:
		pending("one town in reach")
		return
	_order_set(code, String(towns[0]), 1000)
	_run_until_no_couriers()
	SupplyLines.line(s, code)["state"] = SupplyLines.FLOWING
	var c := _order_set(code, String(towns[1]), 1000)
	SupplyLines.deliver(repo, s, c)
	assert_eq(String(SupplyLines.line(s, code)["state"]), SupplyLines.RIDING)
	assert_eq(String(SupplyLines.line(s, code)["town"]), String(towns[1]))

## Final review 5: the supply courier rides to the TOWN, and the estimate the
## rate menu shows is his ride there.
func test_the_town_estimate_is_the_supply_couriers_ride() -> void:
	var code := _land()
	var e := SupplyLines.eligibility(repo, s, code)
	var towns: Array = e.keys().filter(func(t: String) -> bool: return String(e[t]) == "")
	towns.sort()
	var town := String(towns[towns.size() - 1])
	var b: Dictionary = repo.burgs[town]
	var eta := CourierSystem.eta_days_to(repo, s, CourierSystem.ORDINARY, Vector2(float(b["x"]), float(b["y"])))
	var c := _order_set(code, town, 1000)
	assert_eq(CourierSystem.days_left(repo, s, c), eta)
	assert_gt(eta, 0)
