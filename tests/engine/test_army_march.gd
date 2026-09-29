extends GutTest
## The march (owner 2026-09-22): a regiment carries a LIVE position in whole
## metres, ARMY_MARCH sends it somewhere, and every day under the clock it
## covers ArmySystem.day_step_m until it arrives and falls back to garrison.

var repo: DataRepository


func before_all() -> void:
	repo = DataRepository.load_all("res://data")
	# Force clear skies so every hand-sum march still holds (task 7, owner 2026-09-27)
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 1, "rain": 0, "mud": 0, "snow": 0, "blizzard": 0}
	Weather.forget()


func _mine() -> Array:
	return MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))


## A regiment with real arms, so base_pace_km is not zero.
func _marcher() -> Dictionary:
	for r: Dictionary in _mine():
		if ArmySystem.base_pace_km(repo, r) > 0 and String(r.get("is_naval", "0")) != "1":
			return r
	return {}


func test_a_new_campaign_seats_every_regiment_where_the_pack_put_it() -> void:
	var s := GameState.new_campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var home := Vector2(float(r["x"]), float(r["y"]))
	assert_almost_eq(ArmySystem.position_of(repo, s, r).x, home.x, 0.001)
	assert_almost_eq(ArmySystem.position_of(repo, s, r).y, home.y, 0.001)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_STANDBY)
	assert_eq(ArmySystem.heading_of(repo, s, code), Vector2.ZERO, "a standing regiment faces nowhere")


func test_the_pack_measure_is_what_a_metre_means() -> void:
	# beria: distance_scale 1 km to the pack pixel, so a pixel is 1000 m.
	var k := ArmySystem.metres_per_pack_px(repo)
	assert_eq(k, int(round(float(repo.map_info.get("distance_scale", "1")) * 1000.0)))
	assert_eq(ArmySystem.pack_to_metres(repo, Vector2(3.0, 4.0)), Vector2i(3 * k, 4 * k))


func test_a_day_of_marching_covers_the_regiments_own_pace() -> void:
	var s := GameState.new_campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var home: Vector2 = ArmySystem.position_of(repo, s, r)
	var step := ArmySystem.day_step_m(repo, s, code)
	assert_gt(step, 0, "a banner with arms marches")
	# pace_tenths is TENTHS of a km a day, so the step is that times 100 m.
	assert_eq(step, ArmySystem.pace_tenths(repo, ArmySystem.base_pace_km(repo, r),
		ArmySystem.supply_score(repo, int(s.regiments[code]["supplies"]),
			ArmySystem.supply_use(repo, r)),
		int(s.regiments[code]["morale"]), int(s.regiments[code]["training"])) * 100)

	# Send it due east, far enough that it cannot arrive in one day.
	var far := home + Vector2(float(step) / float(ArmySystem.metres_per_pack_px(repo)) * 3.0, 0.0)
	ArmySystem.set_march(repo, s, code, far)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_MARCH)
	assert_eq(ArmySystem.heading_of(repo, s, code), Vector2.RIGHT, "it faces the way it was sent")

	var arrived := ArmySystem.march_day(repo, s)
	assert_eq(arrived, [], "three days out, it arrives on none of them")
	var moved := ArmySystem.position_of(repo, s, r).distance_to(home) \
		* float(ArmySystem.metres_per_pack_px(repo))
	assert_almost_eq(moved, float(step), 1.0, "one day is one step")


func test_it_stops_dead_on_the_spot_it_was_sent_to_and_garrisons() -> void:
	var s := GameState.new_campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var home: Vector2 = ArmySystem.position_of(repo, s, r)
	var step := ArmySystem.day_step_m(repo, s, code)
	# Half a day away: it must land ON the destination, never overshoot.
	var near := home + Vector2(float(step) * 0.5 / float(ArmySystem.metres_per_pack_px(repo)), 0.0)
	ArmySystem.set_march(repo, s, code, near)
	var arrived := ArmySystem.march_day(repo, s)
	assert_eq(arrived, [code], "it reports the day it arrives")
	assert_almost_eq(ArmySystem.position_of(repo, s, r).x, near.x, 0.0011)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_STANDBY,
		"arriving, it stands by: a garrison is an order (owner 2026-09-29)")
	assert_eq(ArmySystem.march_day(repo, s), [], "and it does not arrive twice")


func test_garrison_halts_a_column_where_it_has_got_to() -> void:
	var s := GameState.new_campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var home: Vector2 = ArmySystem.position_of(repo, s, r)
	var step := float(ArmySystem.day_step_m(repo, s, code))
	var k := float(ArmySystem.metres_per_pack_px(repo))
	ArmySystem.set_march(repo, s, code, home + Vector2(step * 5.0 / k, 0.0))
	ArmySystem.march_day(repo, s)
	var half_way: Vector2 = ArmySystem.position_of(repo, s, r)
	ArmySystem.set_garrison(repo, s, code)
	ArmySystem.march_day(repo, s)
	assert_eq(ArmySystem.position_of(repo, s, r), half_way, "halted means halted")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_GARRISON)


func test_the_clock_marches_it_a_day_at_a_time() -> void:
	var s := GameState.new_campaign(repo, 7)
	var engine := TickEngine.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var home: Vector2 = ArmySystem.position_of(repo, s, r)
	var step := float(ArmySystem.day_step_m(repo, s, code))
	var k := float(ArmySystem.metres_per_pack_px(repo))
	ArmySystem.set_march(repo, s, code, home + Vector2(step * 2.0 / k, 0.0))
	engine.advance_day(s)
	assert_eq(engine.day_arrivals, [], "day one, still on the road")
	engine.advance_day(s)
	assert_eq(engine.day_arrivals, [code], "day two, it is there")
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_STANDBY)


func test_the_months_last_day_is_a_day_on_the_road_too() -> void:
	# owner 2026-09-24 (行进速度必须和给定的速度相符): the thirtieth day's end
	# runs the TICK rather than advance_day, and until then the regiments
	# stood still on it — 29 days' march in every 30. Over a month boundary
	# a column must cover exactly one day_step_m per day, the tick included.
	var s := GameState.new_campaign(repo, 7)
	var engine := TickEngine.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var home: Vector2 = ArmySystem.position_of(repo, s, r)
	var step := float(ArmySystem.day_step_m(repo, s, code))
	var k := float(ArmySystem.metres_per_pack_px(repo))
	ArmySystem.set_march(repo, s, code, home + Vector2(step * 1000.0 / k, 0.0))
	s.day = Calendar.DAYS_PER_TICK - 1
	engine.advance_day(s)   # day 30
	engine.advance(s)       # the tick: day 1 of the next month
	var gone := (ArmySystem.position_of(repo, s, r).x - home.x) * k
	assert_almost_eq(gone, step * 2.0, 1.0, "two days, two days' march")


func test_the_same_orders_from_the_same_save_give_the_same_march() -> void:
	# Architecture invariant 2: identical save + identical inputs => identical
	# state. The position is whole metres precisely so this survives the JSON.
	var a := GameState.new_campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var k := float(ArmySystem.metres_per_pack_px(repo))
	var step := float(ArmySystem.day_step_m(repo, a, code))
	var dest: Vector2 = ArmySystem.position_of(repo, a, r) + Vector2(step * 3.7 / k, step * 2.3 / k)
	ArmySystem.set_march(repo, a, code, dest)
	for i in 3:
		ArmySystem.march_day(repo, a)
	var b := GameState.from_dict(a.to_dict())
	for i in 4:
		ArmySystem.march_day(repo, a)
		ArmySystem.march_day(repo, b)
	assert_eq(int(b.regiments[code]["x_m"]), int(a.regiments[code]["x_m"]))
	assert_eq(int(b.regiments[code]["y_m"]), int(a.regiments[code]["y_m"]))


func test_an_old_save_with_no_position_is_seated_where_the_pack_put_it() -> void:
	var s := GameState.new_campaign(repo, 7)
	var r := _marcher()
	var code := String(r["regiment_code"])
	# What a save written before the march existed holds.
	s.regiments[code] = {"morale": 70, "wounded": 0, "supplies": 12, "training": 10}
	ArmySystem.ensure(repo, s)
	assert_true(s.regiments[code].has("x_m"), "ensure seats it")
	assert_almost_eq(ArmySystem.position_of(repo, s, r).x, float(r["x"]), 0.001)
	assert_eq(ArmySystem.order_of(repo, s, code), ArmySystem.ORDER_STANDBY)


func test_the_orders_validate_against_the_regiment_and_the_ground() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var home: Vector2 = ArmySystem.position_of(repo, s, r)

	var bad := ActionRequest.new()
	bad.action_code = "ARMY_MARCH"
	bad.params = {"regiment": "no_such_regiment", "x": home.x, "y": home.y + 5.0}
	assert_string_contains(actions.validate(bad, s), "No such regiment")

	var off := ActionRequest.new()
	off.action_code = "ARMY_MARCH"
	off.params = {"regiment": code, "x": -20.0, "y": 5.0}
	assert_string_contains(actions.validate(off, s), "off the map")

	var here := ActionRequest.new()
	here.action_code = "ARMY_MARCH"
	here.params = {"regiment": code, "x": home.x, "y": home.y}
	assert_string_contains(actions.validate(here, s), "already there")

	var theirs := ActionRequest.new()
	theirs.action_code = "ARMY_GARRISON"
	for other: Dictionary in repo.world_table("military", "regiments").values():
		if String(other["kingdom_code"]) != repo.resolve_realm("player_realm"):
			theirs.params = {"regiment": String(other["regiment_code"])}
			break
	assert_string_contains(actions.validate(theirs, s), "not yours to command")


func test_marching_into_the_sea_is_refused() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var code := String(_marcher()["regiment_code"])
	# A corner of the canvas the land grid does not cover.
	var wet := Vector2(1.0, 1.0)
	if MapEconomy.cell_at(repo, wet) >= 0:
		return  # this pack has land in the corner; nothing to assert
	var req := ActionRequest.new()
	req.action_code = "ARMY_MARCH"
	req.params = {"regiment": code, "x": wet.x, "y": wet.y}
	assert_string_contains(actions.validate(req, s), "cannot march into the sea")


func test_the_order_runs_and_charges_its_cost() -> void:
	var s := GameState.new_campaign(repo, 7)
	var actions := ActionSystem.new(repo)
	var r := _marcher()
	var code := String(r["regiment_code"])
	var home: Vector2 = ArmySystem.position_of(repo, s, r)
	# Somewhere on land a little away: walk out from home until the cell changes.
	var dest := home
	for i in range(1, 40):
		var probe := home + Vector2(float(i), 0.0)
		if MapEconomy.cell_at(repo, probe) >= 0:
			dest = probe
	if dest == home:
		return  # nowhere on land to send it in this pack
	var req := ActionRequest.new()
	req.action_code = "ARMY_MARCH"
	req.params = {"regiment": code, "x": dest.x, "y": dest.y}
	assert_eq(actions.validate(req, s), "")
	var before: float = s.metrics["treasury"]
	actions.execute(req, s)
	assert_eq(s.couriers.size(), 1, "the order rides by courier (2026-09-27)")
	assert_lt(s.metrics["treasury"], before, "every order carries a cost (invariant 8)")


func test_the_weather_where_it_stands_scales_its_day() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := String(_marcher()["regiment_code"])
	var step := ArmySystem.day_step_m(repo, s, code)
	var saved := repo.weather_odds.duplicate(true)
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 0, "rain": 0, "mud": 0, "snow": 0, "blizzard": 1}
	Weather.forget()
	@warning_ignore("integer_division")
	assert_eq(ArmySystem.day_march_m(repo, s, code), step * 400 / 1000, "a blizzard: 400‰")
	repo.weather_odds = saved


## Final review I2 (spec §1): the card shows the base pace and a separate
## weather line, and its "days out" and the aim ruler's figure are one
## function, ArmySystem.march_days, today's weather where it stands in.
func test_in_rain_the_card_the_days_out_and_the_ruler_agree() -> void:
	var s := GameState.new_campaign(repo, 7)
	var code := String(_marcher()["regiment_code"])
	var step := ArmySystem.day_step_m(repo, s, code)
	var saved := repo.weather_odds.duplicate(true)
	for key in repo.weather_odds:
		repo.weather_odds[key] = {"clear": 0, "rain": 1, "mud": 0, "snow": 0, "blizzard": 0}
	Weather.forget()
	# five clear days of road in rain at 850‰: 5 / 0.85 = 5.9 -> 6 days
	assert_eq(ArmySystem.march_days(repo, s, code, float(step * 5)), 6)
	var here := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code))
	ArmySystem.set_march(repo, s, code, here + Vector2(37.0, 0.0))
	var left := 37.0 * float(ArmySystem.metres_per_pack_px(repo))
	assert_eq(ArmySystem.days_out(repo, s, code), ArmySystem.march_days(repo, s, code, left),
		"the card's days out is the ruler's figure")
	var card := MapObjects.army_card(repo, code, s)
	var weather: Dictionary = {}
	var march: Dictionary = {}
	for st: Dictionary in card["stats"]:
		if String(st["key"]) == "army_weather":
			weather = st
		if String(st["key"]) == "army_march":
			march = st
	var days := ArmySystem.days_out(repo, s, code)
	assert_eq(String(march.get("text", "")), "%d day%s out" % [days, "" if days == 1 else "s"])
	var tip := String(march.get("tooltip", ""))
	assert_string_contains(tip, "clear weather")
	assert_true(tip.ends_with("in today's weather"), "a whole sentence: " + tip)
	assert_eq(String(weather.get("text", "")), "Rain ×0.85", "the weather is its own line")
	assert_true(repo.resource_icons.has("army_weather"), "with its icon row")
	var ruler := FileAccess.get_file_as_string("res://scripts/map3d/map3d_hud_ruler.gd")
	assert_string_contains(ruler, "ArmySystem.march_days(", "the aim ruler counts the same days")
	assert_false(ruler.contains("day_step_m"), "not the weather-free pace")
	repo.weather_odds = saved
	Weather.forget()
