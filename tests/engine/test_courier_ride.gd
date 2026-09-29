extends GutTest
## A day's ride and delivery (spec 2026-09-27-courier-core §1). Every
## height tier and the weather are forced so the hand sums hold.

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	RoadGraph.forget()
	Weather.forget()
	repo.road_speed = {"road": 1000, "trail": 800, "offroad": 500, "sea": 625,
		"tier_plains": 1000, "tier_hills": 1000, "tier_mountains": 1000, "tier_peak": 1000}
	_skies("clear")


func after_all() -> void:
	RoadGraph.forget()


func _skies(kind: String) -> void:
	for key in repo.weather_odds:
		var w: Dictionary = {}
		for k: String in repo.weather_kinds:
			w[k] = 1 if k == kind else 0
		repo.weather_odds[key] = w


func _marcher() -> String:
	for r: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(repo, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return String(r["regiment_code"])
	return ""


## A hand-built courier on a straight road, re-aim switched off.
func _courier(s: GameState, id: int, code: String, path: Array, order: Dictionary) -> Dictionary:
	repo.balance["courier_reaim_m"] = 1.0e12
	var c := {"id": id, "kind": "ordinary", "x_m": 0, "y_m": 0, "path": path, "target": code,
		"order": order, "issued": 1, "aim_x_m": 0, "aim_y_m": 0, "days": 0, "day_m": 0, "slow_spell": -1}
	s.couriers.append(c)
	s.next_courier_id = maxi(s.next_courier_id, id)
	return c


func test_a_days_ride_by_hand() -> void:
	var s := GameState.new_campaign(repo, 7)
	var c := _courier(s, 1, _marcher(), [[100000, 0, "road"], [400000, 0, "offroad"]],
		{"action_code": "ARMY_GARRISON"})
	# Day 1: 160,000 of budget. 100 km of road costs 100,000; 60,000 left at
	# 500‰ across country carries him 30 km more.
	assert_eq(CourierSystem.ride_day(repo, s), [{"type": "set_out", "courier": 1,
		"regiment": String(c["target"]), "weather": "", "capital": 0}], "he sets out, and says so")
	assert_eq(Vector2i(int(c["x_m"]), int(c["y_m"])), Vector2i(130000, 0))
	assert_eq(int(c["day_m"]), 130000)
	# Days 2-4: 80 km each across country.
	for i in 3:
		CourierSystem.ride_day(repo, s)
	assert_eq(int(c["x_m"]), 370000)
	# Day 5: 30 km left costs 60,000; he arrives and delivers.
	var ev := CourierSystem.ride_day(repo, s)
	assert_eq(ev.size(), 1)
	assert_eq(String(ev[0]["type"]), "delivered")
	assert_eq(s.couriers, [], "gone on delivery")


func test_delivery_applies_the_order_on_that_day_and_not_before() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	var dest := Vector2i(123000, 456000)
	_courier(s, 1, code, [[200000, 0, "road"]], {"action_code": "ARMY_MARCH", "dest_x_m": dest.x, "dest_y_m": dest.y})
	CourierSystem.ride_day(repo, s)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_STANDBY, "still on the road")
	CourierSystem.ride_day(repo, s)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH)
	assert_eq(ArmySystem.pack_to_metres(repo, ArmySystem.destination_of(repo, s, code)), dest)
	assert_eq(int(s.regiments[code]["order_id"]), 1)


func test_an_older_order_arriving_late_is_set_aside() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	# id 1 (march) has far to go; id 2 (garrison, newer) arrives first.
	_courier(s, 1, code, [[400000, 0, "road"]], {"action_code": "ARMY_MARCH", "dest_x_m": 5000, "dest_y_m": 5000})
	_courier(s, 2, code, [[10000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	var first := CourierSystem.ride_day(repo, s)
	assert_eq(_types(first), ["set_out", "set_out", "delivered"], "both set out; the newer arrives")
	assert_eq(int(first[2]["courier"]), 2)
	var later: Array = []
	for i in 3:
		later.append_array(CourierSystem.ride_day(repo, s))
	assert_eq(String(later[0]["type"]), "stale", "the older order is set aside")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_GARRISON, "the newer order stands")


func test_a_vanished_regiment_leaves_the_orders_undelivered() -> void:
	var s := GameState.new_campaign(repo, 7)
	_courier(s, 1, "no_such_regiment", [[10000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	var ev := CourierSystem.ride_day(repo, s)
	assert_eq(String(ev[0]["type"]), "lost")
	assert_eq(s.couriers, [])


func test_the_fuse() -> void:
	var s := GameState.new_campaign(repo, 7)
	repo.balance["courier_max_days"] = 2.0
	_courier(s, 1, _marcher(), [[9000000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	assert_eq(_types(CourierSystem.ride_day(repo, s)), ["set_out"])
	assert_eq(CourierSystem.ride_day(repo, s), [])
	assert_eq(String(CourierSystem.ride_day(repo, s)[0]["type"]), "fuse")
	assert_eq(s.couriers, [])


func test_bad_weather_slows_him_and_is_announced_once_a_spell() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	# He rides on land so the weather applies: from the regiment's own spot.
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)))
	_skies("blizzard")
	var c := _courier(s, 1, code, [[at.x + 900000, at.y, "road"]], {"action_code": "ARMY_GARRISON"})
	c["x_m"] = at.x
	c["y_m"] = at.y
	var ev := CourierSystem.ride_day(repo, s)
	assert_eq(_types(ev), ["set_out", "slow"])
	assert_eq(String(ev[1]["weather"]), "blizzard")
	# 160,000 x 400‰ = 64 km in a blizzard, the tiers forced to 1000.
	assert_eq(int(c["x_m"]) - at.x, 64000)
	assert_eq(CourierSystem.ride_day(repo, s), [], "said once for the spell")


func test_a_courier_catches_a_column_on_the_march() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	var reg := ArmySystem.regiment(repo, code)
	var home: Vector2 = ArmySystem.position_of(repo, s, reg)
	var far := home + Vector2(300.0, 0.0)
	ArmySystem.set_march(repo, s, code, far)
	CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	for day in int(repo.bal("courier_max_days")):
		CourierSystem.ride_day(repo, s)
		if s.couriers.is_empty():
			break
		ArmySystem.march_day(repo, s)
	assert_eq(s.couriers, [], "he caught them")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_GARRISON)
	assert_lt(ArmySystem.position_of(repo, s, reg).distance_to(home), 300.0, "halted short of where they were going")


func test_a_ride_survives_a_save_mid_road() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	CourierSystem.ride_day(repo, s)
	var copy := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(copy.next_courier_id, s.next_courier_id)
	for i in 3:
		CourierSystem.ride_day(repo, s)
		CourierSystem.ride_day(repo, copy)
	assert_eq(JSON.stringify(copy.to_dict()), JSON.stringify(s.to_dict()))


func _types(events: Array) -> Array:
	var out: Array = []
	for e: Dictionary in events:
		out.append(String(e["type"]))
	return out


## Spec §2's news line (fix round 1, 2026-09-28): once, on his first day on
## the road, before anything else that day; "the capital" only when he rode
## from it.
func test_he_is_seen_to_leave_the_capital_once() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	var c := CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	var ev := CourierSystem.ride_day(repo, s)
	assert_eq(String(ev[0]["type"]), "set_out", "first that day")
	assert_eq(int(ev[0]["courier"]), int(c["id"]))
	assert_eq(int(ev[0]["capital"]), 1, "dispatch put him on the capital's spot")
	var label := String(ArmySystem.regiment(repo, code)["label"])
	assert_eq(CourierSystem.headline(repo, ev[0]), "A courier leaves the capital for %s." % label)
	assert_false(s.couriers.is_empty(), "still riding after a day")
	assert_false(_types(CourierSystem.ride_day(repo, s)).has("set_out"), "said once")


func test_a_courier_not_from_the_capital_just_rides() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	_courier(s, 1, code, [[100000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	var ev := CourierSystem.ride_day(repo, s)
	assert_eq(int(ev[0]["capital"]), 0)
	var label := String(ArmySystem.regiment(repo, code)["label"])
	assert_eq(CourierSystem.headline(repo, ev[0]), "A courier rides for %s." % label)


func test_a_courier_for_a_vanished_regiment_never_sets_out() -> void:
	var s := GameState.new_campaign(repo, 7)
	_courier(s, 1, "no_such_regiment", [[10000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	assert_eq(_types(CourierSystem.ride_day(repo, s)), ["lost"])


func test_headlines() -> void:
	var code := _marcher()
	var label := String(ArmySystem.regiment(repo, code)["label"])
	assert_eq(CourierSystem.headline(repo, {"type": "delivered", "regiment": code}), "Orders delivered to %s." % label)
	assert_string_contains(CourierSystem.headline(repo, {"type": "slow", "regiment": code, "weather": "snow"}), "snow")
	assert_string_contains(CourierSystem.headline(repo, {"type": "stale", "regiment": code}), "set aside")
	assert_string_contains(CourierSystem.headline(repo, {"type": "lost", "regiment": code}), "undelivered")
	assert_string_contains(CourierSystem.headline(repo, {"type": "fuse", "regiment": code}), "undelivered")


## Owner 2026-09-28 (he stood still a whole day after play was pressed): the
## map draws the courier riding his NEXT day, which ride_ahead previews on a
## copy — the same points the day then takes him through, nothing written.
func test_ride_ahead_previews_the_day_exactly_and_writes_nothing() -> void:
	var s := GameState.new_campaign(repo, 7)
	var c := _courier(s, 1, _marcher(), [[100000, 0, "road"], [400000, 0, "offroad"]],
		{"action_code": "ARMY_GARRISON"})
	var before: Dictionary = c.duplicate(true)
	var day := CourierSystem.ride_ahead(repo, s, c)
	var ahead: Array = day["points"]
	assert_eq(ahead, [Vector2i(100000, 0), Vector2i(130000, 0)], "the waypoint he passes, then where the day leaves him")
	assert_eq(day["share"], 1.0, "a whole day on the road")
	assert_eq(c, before, "the courier is untouched")
	assert_eq(s.couriers.size(), 1)
	CourierSystem.ride_day(repo, s)
	assert_eq(Vector2i(int(c["x_m"]), int(c["y_m"])), ahead.back(), "the day ends where the preview did")


func test_ride_ahead_on_the_delivery_day_ends_on_the_column() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	_courier(s, 1, code, [[50000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	var day := CourierSystem.ride_ahead(repo, s, s.couriers[0])
	assert_eq(day["points"], [Vector2i(50000, 0), Vector2i(50000, 0)])
	# 50 km of road costs 50,000 of the day's 160,000
	assert_almost_eq(float(day["share"]), 50000.0 / 160000.0, 0.0001, "he arrives with most of the day to spare")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_STANDBY)
	assert_eq(s.couriers.size(), 1, "a preview delivers nothing")


## The couriers ride before the columns march: the day's preview of a
## regiment (day_ahead_of) marches on an order its courier delivers that day,
## and lands where advance_day's own order of events then puts it.
func test_day_ahead_of_marches_on_an_order_delivered_that_day() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	ArmySystem.ensure(repo, s)
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)))
	var dest := at + Vector2i(500000, 0)
	var c := _courier(s, 1, code, [[at.x, at.y, "road"]],
		{"action_code": "ARMY_MARCH", "dest_x_m": dest.x, "dest_y_m": dest.y})
	c["x_m"] = at.x - 10000
	c["y_m"] = at.y
	var day := CourierSystem.day_ahead_of(repo, s, code)
	var ahead: Vector2i = day["m"]
	assert_ne(ahead, at, "the column is seen marching on the day the order reaches it")
	assert_almost_eq(float(day["from"]), 10000.0 / 160000.0, 0.0001, "from the moment the courier reaches it")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_STANDBY, "nothing written")
	assert_eq(s.couriers.size(), 1)
	s.day += 1  # advance_day's order: the calendar, the couriers, the columns
	CourierSystem.ride_day(repo, s)
	ArmySystem.march_day(repo, s)
	assert_eq(ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code))), ahead)


func test_day_ahead_of_a_garrison_is_where_it_stands() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := _marcher()
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)))
	assert_eq(CourierSystem.day_ahead_of(repo, s, code), {"m": at, "from": 0.0})
