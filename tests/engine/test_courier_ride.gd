extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A day's ride and delivery (spec 2026-09-27-courier-core §1). Every
## height tier and the weather are forced so the hand sums hold. Since
## 2026-10-02 (owner: a one-day courier arrives as the day ENDS) he rides
## EVENLY: each day what is left over the whole days it takes (day_pace).

var repo: DataRepository


## The pack's road graph is cached by map id and every test's repository
## carries the same routes and road speeds (this script's own, set below),
## so it is built once per script
## (and forgotten around it, so no other script's graph is read).
func before_all() -> void:
	RoadGraph.forget()


func before_each() -> void:
	repo = SuiteData.flat_ground(SuiteData.repo())
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
		"orders": [order], "issued": 1, "aim_x_m": 0, "aim_y_m": 0, "days": 0, "day_m": 0, "slow_spell": -1}
	s.couriers.append(c)
	s.next_courier_id = maxi(s.next_courier_id, id)
	return c


func test_a_days_ride_by_hand() -> void:
	var s := SuiteData.campaign(repo, 7)
	var c := _courier(s, 1, _marcher(), [[100000, 0, "road"], [400000, 0, "offroad"]],
		{"action_code": "ARMY_GARRISON"})
	# The whole road: 100 km of road costs 100,000 and 300 km across country
	# at 500‰ costs 600,000 — 700,000, five days at 160,000 a day, so he rides
	# 700,000 / 5 = 140,000 a day and ends on the fifth day's end.
	assert_eq(CourierSystem.day_pace(repo, s, c, s.absolute_day() + 1), 140000)
	assert_eq(CourierSystem.days_left(repo, s, c), 5)
	# Day 1: the road's 100,000, then 40,000 at 500‰ carries him 20 km more.
	# His setting out is said when the day begins (setting_out), not here.
	assert_eq(CourierSystem.ride_day(repo, s), [], "nothing to say at the first day's end")
	assert_eq(Vector2i(int(c["x_m"]), int(c["y_m"])), Vector2i(120000, 0))
	assert_eq(int(c["day_m"]), 120000)
	assert_eq(CourierSystem.days_left(repo, s, c), 4, "one day fewer, every day")
	# Days 2-4: 560,000 left over 4 days, then 420,000 over 3, 280,000 over 2:
	# 140,000 = 70 km across country each.
	for i in 3:
		CourierSystem.ride_day(repo, s)
	assert_eq(int(c["x_m"]), 330000)
	assert_eq(CourierSystem.days_left(repo, s, c), 1)
	# Day 5: the last 70 km cost exactly the day's 140,000; he arrives as it ends.
	var ev := CourierSystem.ride_day(repo, s)
	assert_eq(ev.size(), 1)
	assert_eq(String(ev[0]["type"]), "delivered")
	assert_eq(s.couriers, [], "gone on delivery")


func test_delivery_applies_the_order_on_that_day_and_not_before() -> void:
	var s := SuiteData.campaign(repo, 7)
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
	var s := SuiteData.campaign(repo, 7)
	var code := _marcher()
	# id 1 (march) has far to go; id 2 (garrison, newer) arrives first.
	_courier(s, 1, code, [[400000, 0, "road"]], {"action_code": "ARMY_MARCH", "dest_x_m": 5000, "dest_y_m": 5000})
	_courier(s, 2, code, [[10000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	assert_eq(_types(CourierSystem.setting_out(repo, s, 0)), ["set_out", "set_out"], "both set out")
	var first := CourierSystem.ride_day(repo, s)
	assert_eq(_types(first), ["delivered"], "the newer arrives as the first day ends")
	assert_eq(int(first[0]["courier"]), 2)
	var later: Array = []
	for i in 3:
		later.append_array(CourierSystem.ride_day(repo, s))
	assert_eq(String(later[0]["type"]), "stale", "the older order is set aside")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_GARRISON, "the newer order stands")


func test_a_vanished_regiment_leaves_the_orders_undelivered() -> void:
	var s := SuiteData.campaign(repo, 7)
	_courier(s, 1, "no_such_regiment", [[10000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	var ev := CourierSystem.ride_day(repo, s)
	assert_eq(String(ev[0]["type"]), "lost")
	assert_eq(s.couriers, [])


func test_the_fuse() -> void:
	var s := SuiteData.campaign(repo, 7)
	repo.balance["courier_max_days"] = 2.0
	_courier(s, 1, _marcher(), [[9000000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	assert_eq(CourierSystem.ride_day(repo, s), [])
	assert_eq(CourierSystem.ride_day(repo, s), [])
	assert_eq(String(CourierSystem.ride_day(repo, s)[0]["type"]), "fuse")
	assert_eq(s.couriers, [])


func test_bad_weather_slows_him_and_is_announced_once_a_spell() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _marcher()
	# He rides on land so the weather applies: from the regiment's own spot.
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)))
	_skies("blizzard")
	var c := _courier(s, 1, code, [[at.x + 900000, at.y, "road"]], {"action_code": "ARMY_GARRISON"})
	c["x_m"] = at.x
	c["y_m"] = at.y
	var ev := CourierSystem.ride_day(repo, s)
	assert_eq(_types(ev), ["slow"])
	assert_eq(String(ev[0]["weather"]), "blizzard")
	# 900 km of road at 400‰ costs 2,250,000: 15 days at 160,000, so he rides
	# 2,250,000 / 15 = 150,000 a day — x 400‰ = 60 km in a blizzard, the
	# tiers forced to 1000.
	assert_eq(int(c["x_m"]) - at.x, 60000)
	assert_eq(CourierSystem.ride_day(repo, s), [], "said once for the spell")


func test_a_courier_catches_a_column_on_the_march() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _marcher()
	var reg := ArmySystem.regiment(repo, code)
	var home: Vector2 = ArmySystem.position_of(repo, s, reg)
	var far := home + Vector2(300.0, 0.0)
	ArmySystem.set_march(repo, s, code, far)
	CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	for day in int(repo.bal("courier_max_days")):  # advance_day's order: the march, then the ride
		ArmySystem.march_day(repo, s)
		CourierSystem.ride_day(repo, s)
		if s.couriers.is_empty():
			break
	assert_eq(s.couriers, [], "he caught them")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_GARRISON)
	assert_lt(ArmySystem.position_of(repo, s, reg).distance_to(home), 300.0, "halted short of where they were going")


func test_a_ride_survives_a_save_mid_road() -> void:
	var s := SuiteData.campaign(repo, 7)
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


## Spec §2's news line (fix round 1, 2026-09-28): once, as the day he rides
## begins (owner 2026-10-02: 游戏开始信使出发 — said at the day's end, a
## one-day courier left and delivered in the same breath); "the capital" only
## when he rode from it. GameRoot asks while the clock runs, past the last id
## it has said.
func test_he_is_seen_to_leave_the_capital_once() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _marcher()
	var c := CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code, {"action_code": "ARMY_GARRISON"})
	var ev := CourierSystem.setting_out(repo, s, 0)
	assert_eq(_types(ev), ["set_out"], "he sets out as his first day begins")
	assert_eq(int(ev[0]["courier"]), int(c["id"]))
	assert_eq(int(ev[0]["capital"]), 1, "dispatch put him on the capital's spot")
	var label := String(ArmySystem.regiment(repo, code)["label"])
	assert_eq(CourierSystem.headline(repo, ev[0]), "A courier leaves the capital for %s." % label)
	assert_eq(CourierSystem.setting_out(repo, s, int(c["id"])), [], "said once")
	assert_eq(c, s.couriers[0], "nothing written")
	assert_false(_types(CourierSystem.ride_day(repo, s)).has("set_out"), "never at a day's end")
	assert_eq(CourierSystem.setting_out(repo, s, 0), [], "on the road: no longer setting out")


func test_a_courier_not_from_the_capital_just_rides() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _marcher()
	_courier(s, 1, code, [[100000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	var ev := CourierSystem.setting_out(repo, s, 0)
	assert_eq(int(ev[0]["capital"]), 0)
	var label := String(ArmySystem.regiment(repo, code)["label"])
	assert_eq(CourierSystem.headline(repo, ev[0]), "A courier rides for %s." % label)


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
	var s := SuiteData.campaign(repo, 7)
	var c := _courier(s, 1, _marcher(), [[100000, 0, "road"], [400000, 0, "offroad"]],
		{"action_code": "ARMY_GARRISON"})
	var before: Dictionary = c.duplicate(true)
	var day := CourierSystem.ride_ahead(repo, s, c)
	var ahead: Array = day["points"]
	assert_eq(ahead, [Vector2i(100000, 0), Vector2i(120000, 0)], "the waypoint he passes, then where the day leaves him")
	assert_eq(day["share"], 1.0, "a whole day on the road")
	assert_false(bool(day["ends"]), "he rides on tomorrow")
	assert_eq(c, before, "the courier is untouched")
	assert_eq(s.couriers.size(), 1)
	CourierSystem.ride_day(repo, s)
	assert_eq(Vector2i(int(c["x_m"]), int(c["y_m"])), ahead.back(), "the day ends where the preview did")


func test_ride_ahead_on_the_delivery_day_ends_on_the_column() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _marcher()
	_courier(s, 1, code, [[50000, 0, "road"]], {"action_code": "ARMY_GARRISON"})
	var day := CourierSystem.ride_ahead(repo, s, s.couriers[0])
	assert_eq(day["points"], [Vector2i(50000, 0), Vector2i(50000, 0)])
	# 50 km of road costs 50,000 of the day's 160,000: one day, so he rides
	# 50,000 that day, at an even pace to its end (owner 2026-10-02)
	assert_eq(float(day["share"]), 1.0, "the whole day, never a dash in part of it")
	assert_true(bool(day["ends"]), "the day delivers as it ends: the map fades him out then")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_STANDBY)
	assert_eq(s.couriers.size(), 1, "a preview delivers nothing")


## Owner 2026-10-02: the courier arrives as the day ENDS, after the columns
## march — so the column stands the whole day its order reaches it
## (day_ahead_of: where it stands) and marches on it from the next day, which
## day_ahead_of then previews exactly as advance_day's order of events (the
## calendar, the columns, the couriers) plays it.
func test_an_order_delivered_today_is_marched_on_from_tomorrow() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _marcher()
	ArmySystem.ensure(repo, s)
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)))
	var dest := at + Vector2i(500000, 0)
	var c := _courier(s, 1, code, [[at.x, at.y, "road"]],
		{"action_code": "ARMY_MARCH", "dest_x_m": dest.x, "dest_y_m": dest.y})
	c["x_m"] = at.x - 10000
	c["y_m"] = at.y
	assert_eq(CourierSystem.day_ahead_of(repo, s, code), at, "the column stands the day its courier rides")
	assert_true(bool(CourierSystem.ride_ahead(repo, s, c)["ends"]), "he delivers as that day ends")
	s.day += 1  # advance_day's order: the calendar, the columns, the couriers
	ArmySystem.march_day(repo, s)
	CourierSystem.ride_day(repo, s)
	assert_eq(s.couriers, [], "delivered at the day's end")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH)
	assert_eq(ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code))), at,
		"it has not moved yet")
	var ahead := CourierSystem.day_ahead_of(repo, s, code)
	assert_ne(ahead, at, "the next day it marches")
	s.day += 1
	ArmySystem.march_day(repo, s)
	CourierSystem.ride_day(repo, s)
	assert_eq(ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code))), ahead)


func test_day_ahead_of_a_garrison_is_where_it_stands() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _marcher()
	var at := ArmySystem.pack_to_metres(repo, ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)))
	assert_eq(CourierSystem.day_ahead_of(repo, s, code), at)


## Owner 2026-10-02, through the engine's own day (TickEngine.advance_day): an
## order given on day d whose courier is shown "N days" is delivered as the
## Nth day ends — not before — and the column marches from the next day.
func test_the_shown_days_are_day_ends_through_the_tick_engine() -> void:
	var s := SuiteData.campaign(repo, 7)
	var engine := TickEngine.new(repo)
	var code := _marcher()
	var reg := ArmySystem.regiment(repo, code)
	var home: Vector2 = ArmySystem.position_of(repo, s, reg)
	# far enough that the courier needs several days (a column marches ~10 km a day)
	repo.balance["courier_base_km_per_day"] = 20.0
	repo.balance["courier_max_days"] = 1000.0
	var eta := CourierSystem.eta_days(repo, s, CourierSystem.ORDINARY, code)
	assert_gt(eta, 1, "a trip of several days")
	CourierSystem.dispatch(repo, s, CourierSystem.ORDINARY, code,
		{"action_code": "ARMY_MARCH", "dest_x_m": int(ArmySystem.pack_to_metres(repo, home).x) + 100000,
		"dest_y_m": int(ArmySystem.pack_to_metres(repo, home).y)})
	for day in eta - 1:
		engine.advance_day(s)
		assert_eq(s.couriers.size(), 1, "still riding at the end of day %d of %d" % [day + 1, eta])
		assert_eq(CourierSystem.days_left(repo, s, s.couriers[0]), eta - day - 1, "one day fewer each day")
	engine.advance_day(s)
	assert_eq(s.couriers, [], "delivered as day %d ends" % eta)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH)
	assert_eq(ArmySystem.position_of(repo, s, reg), home, "the column has not marched on its delivery day")
	engine.advance_day(s)
	assert_ne(ArmySystem.position_of(repo, s, reg), home, "it marches from the next day")


func test_a_redirect_delivered_on_a_march_day_keeps_the_old_walk_for_today() -> void:
	var s := SuiteData.campaign(repo, 7)
	var engine := TickEngine.new(repo)
	engine.advance(s)
	repo.balance["army_clearance_on"] = 0.0
	var code := _marcher()
	var reg := ArmySystem.regiment(repo, code)
	var home := ArmySystem.position_of(repo, s, reg)
	var old_dest := home + Vector2(500.0, 0.0)
	ArmySystem.set_march(repo, s, code, old_dest)
	var control := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	var at := ArmySystem.pack_to_metres(repo, home)
	var new_dest := at + Vector2i(0, 500000)
	repo.balance["courier_base_km_per_day"] = 100000.0
	var courier := _courier(s, s.next_courier_id + 100, code, [[at.x, at.y, "road"]], {"action_code": "ARMY_MARCH",
		"dest_x_m": new_dest.x, "dest_y_m": new_dest.y})
	courier["x_m"] = at.x - 10000
	courier["y_m"] = at.y
	s.couriers = [courier]
	var report := engine.advance(s)
	var control_engine := TickEngine.new(repo)
	control_engine.advance(control)
	assert_eq(report.status, "complete")
	assert_true(s.couriers.is_empty(), "the one-day courier has delivered")
	var entry: Dictionary = s.regiments[code]
	assert_eq(Vector2i(int(entry["x_m"]), int(entry["y_m"])),
		Vector2i(int(control.regiments[code]["x_m"]), int(control.regiments[code]["y_m"])),
		"today uses the route saved at phase start")
	assert_eq(Vector2i(int(entry["dest_x_m"]), int(entry["dest_y_m"])), new_dest,
		"the courier's redirected order is in force for tomorrow")


func test_a_redirect_rebuilds_tomorrows_waypoint_route_from_todays_final_position() -> void:
	for old_distance: int in [750, 2300]:
		var s := SuiteData.campaign(repo, 7)
		s.tick = 1
		s.day = 10
		s.foes.clear()
		s.ai_hosts.clear()
		repo.balance["army_clearance_on"] = 0.0
		for arm: String in repo.army_speed:
			repo.army_speed[arm] = 1
		for ground: String in repo.army_ground_speed:
			repo.army_ground_speed[ground] = 1000
		var code := _marcher()
		var entry: Dictionary = s.regiments[code]
		entry["morale"] = 100
		entry["training"] = 100
		entry["carry_days"] = 10
		entry["supplies"] = ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code, s), s) * 6
		var start := Vector2i(1000000, 1000000) # away from town settlement slots
		entry["x_m"] = start.x
		entry["y_m"] = start.y
		ArmySystem.set_march_m(repo, s, code, start + Vector2i(old_distance, 0))
		var moved := 750 if old_distance == 750 else 767 # ceil(2300 / 3)
		var today_end := start + Vector2i(moved, 0)
		var waypoint := today_end + Vector2i(0, 3000)
		var dest := today_end + Vector2i(0, 5000)
		var courier := _courier(s, s.next_courier_id + 100, code, [[start.x, start.y, "road"]],
			{"action_code": "ARMY_MARCH", "dest_x_m": dest.x, "dest_y_m": dest.y,
			"waypoints_m": [[waypoint.x, waypoint.y]]})
		courier["x_m"] = start.x - 10
		courier["y_m"] = start.y
		s.couriers = [courier]
		assert_eq(TickEngine.new(repo).resolve_day(s)["status"], "complete")
		assert_true(s.couriers.is_empty(), "the redirect was delivered")
		assert_eq(Vector2i(int(entry["x_m"]), int(entry["y_m"])), today_end,
			"both an arrival and an unfinished old march keep today's old movement")
		assert_eq(entry.get("waypoints_m"), [[waypoint.x, waypoint.y]], "tomorrow still visits the ordered waypoint")
		# JSON must preserve the pending order, with its road starting at today's actual finish.
		s = GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
		assert_eq(TickEngine.new(repo).resolve_day(s)["status"], "complete")
		entry = s.regiments[code]
		assert_eq(Vector2i(int(entry["x_m"]), int(entry["y_m"])), today_end + Vector2i(0, 1000),
			"the new straight north route starts here, never via yesterday's curve samples")
		assert_eq(entry.get("waypoints_m"), [[waypoint.x, waypoint.y]])


## Owner 2026-10-02 (显示一个总的到达日): ONE arrival figure — the courier's
## ride, then the march at today's pace — wherever days are shown.
func test_the_arrival_day_is_the_ride_and_then_the_march() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := _marcher()
	var reg := ArmySystem.regiment(repo, code)
	var here := ArmySystem.position_of(repo, s, reg)
	var dest := here + Vector2(40.0, 0.0)
	var ride := CourierSystem.eta_days(repo, s, CourierSystem.ORDINARY, code)
	var march := ArmySystem.march_days(repo, s, code, 40.0 * float(ArmySystem.metres_per_pack_px(repo)))
	assert_gt(march, 0)
	assert_eq(CourierSystem.arrival_days(repo, s, code, dest),
		(ride if CourierSystem.carries_orders(reg) else 0) + march)
	# a march order on the road: his days left, then the march
	var m := ArmySystem.pack_to_metres(repo, dest)
	var c := _courier(s, 1, code, [[0, 0, "road"], [160000 * 2 + 5, 0, "road"]],
		{"action_code": "ARMY_MARCH", "dest_x_m": m.x, "dest_y_m": m.y})
	var left := CourierSystem.days_left(repo, s, c)
	assert_eq(CourierSystem.days_to_arrival(repo, s, code), left + march,
		"the card counts the courier still riding")
	# a halt riding: bound nowhere
	c["orders"] = [{"action_code": "ARMY_GARRISON"}]
	assert_eq(CourierSystem.days_to_arrival(repo, s, code), 0)

