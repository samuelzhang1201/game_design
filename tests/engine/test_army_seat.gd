extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## ARMY_SEAT (spec 2026-10-07-army-split-and-ground §4.5) and the seat's refill rule.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()
	RoadGraph.forget()
	Weather.forget()


func after_all() -> void:
	RoadGraph.forget()


func _setup() -> Dictionary:
	var s := SuiteData.campaign(repo, 5)
	s.metrics["treasury"] = 10000.0
	var town := String(repo.kingdoms[repo.resolve_realm("player_realm")]["capital_burg"])
	var camper := ""
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), s):
		var c := String(r["regiment_code"])
		if ArmyGround.camped_by(repo, s, c) == town and ArmyGround.seated_in(repo, s, c) == "":
			camper = c
			break
	return {"s": s, "town": town, "camper": camper, "seat": ArmyGround.seat_of(repo, s, town)}


## Ride every courier home: days until none is left on the road.
func _ride_all(s: GameState) -> void:
	for i in 200:
		if s.couriers.is_empty():
			return
		@warning_ignore("return_value_discarded")
		CourierSystem.ride_day(repo, s)


func _seat_req(code: String) -> ActionRequest:
	return ActionRequest.make("ARMY_SEAT", {"regiment": code})


func test_a_camped_unit_may_take_the_seat() -> void:
	var x := _setup()
	assert_ne(String(x["camper"]), "", "the capital has a camp")
	assert_eq(ActionSystem.new(repo).validate(_seat_req(String(x["camper"])), x["s"]), "")


func test_the_seated_unit_and_a_field_unit_are_refused() -> void:
	var x := _setup()
	var actions := ActionSystem.new(repo)
	assert_ne(actions.validate(_seat_req(String(x["seat"])), x["s"]), "")
	var s: GameState = x["s"]
	s.regiments[String(x["camper"])]["camp_town"] = ""
	assert_ne(actions.validate(_seat_req(String(x["camper"])), s), "")


func test_the_courier_swaps_the_two() -> void:
	var x := _setup()
	var s: GameState = x["s"]
	var camp_at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, String(x["camper"]), s))
	var out := ActionSystem.new(repo).execute(_seat_req(String(x["camper"])), s)
	assert_eq(s.couriers.size(), 1, "one courier rides")
	assert_eq(ArmyGround.seat_of(repo, s, String(x["town"])), String(x["seat"]), "nothing moves until he arrives")
	assert_true(out.has("effects"))
	_ride_all(s)
	assert_eq(ArmyGround.seat_of(repo, s, String(x["town"])), String(x["camper"]))
	assert_eq(ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, String(x["seat"]), s)), camp_at)
	assert_eq(ArmyGround.camped_by(repo, s, String(x["seat"])), String(x["town"]))
	assert_eq(ArmyGround.seated_in(repo, s, String(x["seat"])), "")


func test_seat_order_on_an_empty_seat_takes_it() -> void:
	var x := _setup()
	var s: GameState = x["s"]
	@warning_ignore("return_value_discarded")
	ActionSystem.new(repo).execute(_seat_req(String(x["camper"])), s)
	s.town_seat.erase(String(x["town"]))
	_ride_all(s)
	assert_eq(ArmyGround.seat_of(repo, s, String(x["town"])), String(x["camper"]))


func test_it_lapses_when_the_unit_has_left() -> void:
	var x := _setup()
	var s: GameState = x["s"]
	@warning_ignore("return_value_discarded")
	ActionSystem.new(repo).execute(_seat_req(String(x["camper"])), s)
	s.regiments[String(x["camper"])]["camp_town"] = ""
	var events: Array = []
	for i in 200:
		if s.couriers.is_empty():
			break
		events.append_array(CourierSystem.ride_day(repo, s))
	assert_true(events.any(func(e: Dictionary) -> bool: return String(e["type"]) == "lapsed"))
	assert_eq(ArmyGround.seat_of(repo, s, String(x["town"])), String(x["seat"]))
	assert_string_contains(CourierSystem.headline(repo, {"type": "lapsed", "regiment": String(x["camper"])}), "lapsed")


func test_a_seat_courier_never_moves_the_arrival() -> void:
	var x := _setup()
	var s: GameState = x["s"]
	@warning_ignore("return_value_discarded")
	ActionSystem.new(repo).execute(_seat_req(String(x["camper"])), s)
	assert_eq(CourierSystem.pending_for(s, String(x["camper"])), {}, "a seat order is not the march")


func test_take_seat_swaps_and_refuses_a_field_unit() -> void:
	var x := _setup()
	var s: GameState = x["s"]
	var town := String(x["town"])
	var camper := String(x["camper"])
	var seat := String(x["seat"])
	assert_true(ArmyGround.take_seat(repo, s, seat), "the holder already holds it")
	assert_eq(ArmyGround.seat_of(repo, s, town), seat)
	assert_true(ArmyGround.take_seat(repo, s, camper))
	assert_eq(ArmyGround.seat_of(repo, s, town), camper)
	assert_eq(ArmyGround.camped_by(repo, s, seat), town)
	s.regiments[seat]["camp_town"] = ""
	assert_false(ArmyGround.take_seat(repo, s, seat), "a unit in the field has no seat to take")
	assert_eq(ArmyGround.seat_of(repo, s, town), camper)


## ArmyGround.refill: the camp unit with the most infantry steps in, ties to
## the earlier code; with no infantry anywhere, the largest unit.
func test_refill_prefers_infantry_then_the_earlier_code_then_the_larger() -> void:
	var x := _setup()
	var s: GameState = x["s"]
	var town := String(x["town"])
	var camped: Array = []
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"), s):
		var c := String(r["regiment_code"])
		if ArmyGround.camped_by(repo, s, c) == town:
			camped.append(c)
	camped.sort()
	assert_gte(camped.size(), 3, "the capital's seat and two camps at least")
	var a := String(camped[0])
	var b := String(camped[1])
	# only a and b camp round the town; the seat is emptied
	for c: String in camped:
		if c != a and c != b:
			s.regiments[c]["camp_town"] = ""
	s.town_seat.erase(town)
	var arms: Array = repo.world_table("military", "unit_types").keys()
	var rows := func(ia: int, ib: int, other_a: int, other_b: int) -> void:
		for unit: String in arms:
			s.army_roster[a][unit] = 0
			s.army_roster[b][unit] = 0
		s.army_roster[a]["infantry"] = ia
		s.army_roster[b]["infantry"] = ib
		s.army_roster[a]["archers"] = other_a
		s.army_roster[b]["archers"] = other_b
		s.town_seat.erase(town)
	# more infantry wins even against a far larger unit: b 200 foot beats a 100 foot + 900 archers
	rows.call(100, 200, 900, 0)
	assert_eq(ArmyGround.refill(repo, s, town), b)
	# equal infantry: the earlier code
	rows.call(150, 150, 0, 500)
	assert_eq(ArmyGround.refill(repo, s, town), a)
	# no infantry at all: the larger unit (b 300 archers against a 100)
	rows.call(0, 0, 100, 300)
	assert_eq(ArmyGround.refill(repo, s, town), b)
	assert_eq(ArmyGround.seat_of(repo, s, town), b, "and it holds the seat")
