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
