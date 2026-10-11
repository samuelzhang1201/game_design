extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The day's supply step (spec 2026-10-07-army-supply-lines §3.2–3.4).

var repo: DataRepository
var s: GameState
var code := ""
var town := ""

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)
	RealmEconomy.forget()
	code = ""   # GUT keeps one instance for the script's tests
	town = ""
	# an able, honest marshal: efficiency 1000, no skim, so the arithmetic is plain
	var m: Character = s.characters[String(s.council["marshal"])]
	m.skills["sk_admin"] = 16
	m.opinion = 50
	m.traits = []
	m.attributes["integrity"] = 50
	var codes: Array = s.regiments.keys()
	codes.sort()
	# in the field: camped by no town (spec 2026-10-07-army-split-and-ground
	# §4.1), so no town tops it up
	for c in codes:
		var reg := ArmySystem.regiment(repo, String(c))
		if String(reg.get("is_naval", "0")) != "1" and ArmyGround.camped_by(repo, s, String(c)) == "":
			code = String(c)
			break
	if code != "":
		town = _eligible_town()
	else:   # every regiment stands in a town: march one out into the open field
		_march_one_out(codes)
	assert_ne(town, "", "a regiment in the field with a town in reach")
	s.supply_lines[code] = SupplyLines._new_record(town, 1000, 1)
	s.supply_lines[code]["state"] = SupplyLines.FLOWING
	# every OTHER regiment carries more than it may take (ruling R4), so no
	# town refill draws on the stores or buys from a house today
	for c in codes:
		if String(c) == code:
			continue
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, String(c)), s)
		s.regiments[c]["supplies"] = ArmySystem.max_units(repo, use) + use

func after_each() -> void:
	RealmEconomy.forget()

func _eligible_town() -> String:
	var e := SupplyLines.eligibility(repo, s, code)
	var towns: Array = e.keys()
	towns.sort()
	for t: String in towns:
		if String(e[t]) == "":
			return t
	return ""

## The first land regiment that, a step out of its town onto dry land, still
## has a supply town in reach (a step may cross a bay and leave none). It
## leaves its camp (camp_town ""); a seated unit is passed over, so no seat
## is left on a unit in the field, and so is one eating under a unit a day
## (a small unit's month spread over thirty days skips some).
func _march_one_out(codes: Array) -> void:
	for c in codes:
		var reg := ArmySystem.regiment(repo, String(c))
		if String(reg.get("is_naval", "0")) == "1" or ArmyGround.seated_in(repo, s, String(c)) != "" \
				or ArmySystem.supply_use(repo, reg, s) < Calendar.DAYS_PER_TICK:
			continue
		var camp := String(s.regiments[c].get("camp_town", ""))
		var home := ArmySystem.position_of(repo, s, reg)
		for step: Vector2 in [Vector2(40.0, 0.0), Vector2(-40.0, 0.0), Vector2(0.0, 40.0), Vector2(0.0, -40.0)]:
			var cell := MapEconomy.cell_at(repo, home + step)
			if cell < 0 or MapTerrain.is_water(repo.cells[cell]):
				continue
			var mm := ArmySystem.pack_to_metres(repo, home + step)
			s.regiments[c]["x_m"] = mm.x
			s.regiments[c]["y_m"] = mm.y
			s.regiments[c]["camp_town"] = ""
			code = String(c)
			if ArmySystem.held_town_of(repo, reg, s) == "":
				town = _eligible_town()
				if town != "":
					return
			var back := ArmySystem.pack_to_metres(repo, home)
			s.regiments[c]["x_m"] = back.x
			s.regiments[c]["y_m"] = back.y
			s.regiments[c]["camp_town"] = camp
	code = ""

func _use() -> int:
	return ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code, s), s)

## A town's stock set by hand, the two metrics synced to it so the day's
## reconcile has nothing to absorb (ruling R4).
func _stock(t: String, crown: int, lord: int, house: int) -> void:
	s.town_stock[t] = {"crown": crown, "lord": lord, "house": house}
	TownStores.sync_metrics(repo, s)

func _has(ev: Array, type: String, reg: String) -> bool:
	return ev.any(func(e: Dictionary) -> bool: return String(e["type"]) == type and String(e["regiment"]) == reg)

func test_a_flowing_line_draws_from_its_town_and_delivers_less_the_road() -> void:
	s.day = 5
	s.regiments[code]["supplies"] = 0
	_stock(town, 100000, 0, 0)
	var send := ArmySystem.day_bite(_use(), 5)
	var km := SupplyLines.road_km(repo, SupplyLines.road_px(repo, s, code, town))
	var keep := 1000 - SupplySystem.loss_of(repo, km)
	SupplyLines.day_step(repo, s)
	assert_eq(int(TownStores.stock_of(s, town)["crown"]), 100000 - send)
	# in thousandths: send × keep arrive, the whole units now, the rest carried
	@warning_ignore("integer_division")
	assert_eq(int(s.regiments[code]["supplies"]), send * keep / 1000)
	assert_eq(int(s.supply_lines[code]["arrive_milli"]), send * keep % 1000)

func test_the_rate_scales_the_draw() -> void:
	s.day = 5
	s.regiments[code]["supplies"] = 0
	_stock(town, 100000, 0, 0)
	s.supply_lines[code]["rate"] = 1200
	SupplyLines.day_step(repo, s)
	@warning_ignore("integer_division")
	assert_eq(100000 - int(TownStores.stock_of(s, town)["crown"]), ArmySystem.day_bite(_use() * 1200 / 1000, 5))

func test_the_draw_stops_at_thirty_days() -> void:
	s.regiments[code]["supplies"] = ArmySystem.max_units(repo, _use())
	_stock(town, 100000, 0, 0)
	SupplyLines.day_step(repo, s)
	assert_true(int(s.regiments[code]["supplies"]) <= ArmySystem.max_units(repo, _use()) + ArmySystem.day_bite(_use(), s.day))

func test_crown_then_lord_then_the_house_is_bought() -> void:
	s.day = 5
	s.regiments[code]["supplies"] = 0
	# a unit's day is a unit or two: this one four times its size, so the
	# day's draw outruns the crown's and the lord's single unit
	var row: Dictionary = s.army_roster[code]
	for arm: String in repo.world_table("military", "unit_types"):
		row[arm] = str(int(float(row.get(arm, 0))) * 4)
	var send := ArmySystem.day_bite(_use(), 5)
	assert_gt(send, 2)
	_stock(town, 1, 1, 100)
	var gold := float(s.metrics["treasury"])
	SupplyLines.day_step(repo, s)
	var st := TownStores.stock_of(s, town)
	assert_eq(int(st["crown"]), 0)
	assert_eq(int(st["lord"]), 0)
	assert_eq(int(st["house"]), 100 - (send - 2))
	assert_true(float(s.metrics["treasury"]) <= gold, "the house's goods are paid for")

func test_an_empty_treasury_buys_nothing_from_the_house() -> void:
	s.day = 5
	s.regiments[code]["supplies"] = 0
	_stock(town, 0, 0, 100)
	s.metrics["treasury"] = 0.0
	SupplyLines.day_step(repo, s)
	assert_eq(int(TownStores.stock_of(s, town)["house"]), 100)
	assert_eq(float(s.metrics["treasury"]), 0.0, "never into debt")

## The price owed but not yet charged in whole gold is part of what the
## treasury must cover: a purchase never takes it below nothing.
func test_a_purchase_never_overdraws_the_treasury() -> void:
	_stock(town, 0, 0, 100000)
	s.metrics["treasury"] = 1.0
	for d in range(1, 31):
		s.day = d
		s.regiments[code]["supplies"] = 0
		SupplyLines.day_step(repo, s)
		assert_gte(float(s.metrics["treasury"]), 0.0, "day %d" % d)

func test_cartage_is_charged_in_whole_gold_and_the_rest_carried() -> void:
	s.day = 5
	s.regiments[code]["supplies"] = 0
	_stock(town, 100000, 0, 0)
	var km := SupplyLines.road_km(repo, SupplyLines.road_px(repo, s, code, town))
	var milli := ArmySystem.day_bite(_use(), 5) * km * int(repo.bal("supply_cart_milligold_per_unit_km"))
	var gold := float(s.metrics["treasury"])
	SupplyLines.day_step(repo, s)
	@warning_ignore("integer_division")
	assert_eq(int(gold - float(s.metrics["treasury"])), milli / 1000)
	assert_eq(int(s.supply_lines[code]["fee_milli"]), milli % 1000)

func test_a_riding_line_flows_on_its_ready_day() -> void:
	s.supply_lines[code]["state"] = SupplyLines.RIDING
	s.supply_lines[code]["ready_day"] = s.absolute_day() + 1
	var ev := SupplyLines.day_step(repo, s)
	assert_eq(String(s.supply_lines[code]["state"]), SupplyLines.RIDING)
	s.day += 1
	ev = SupplyLines.day_step(repo, s)
	assert_eq(String(s.supply_lines[code]["state"]), SupplyLines.FLOWING)
	assert_true(_has(ev, "opened", code))

func test_a_line_whose_town_leaves_the_realm_is_cancelled() -> void:
	var prov := String(repo.burgs[town]["province_code"])
	var other := repo.resolve_realm("raider_realm")
	MapOwnership.set_owner(repo, s, prov, other, "a test conquest")
	var ev := SupplyLines.day_step(repo, s)
	assert_true(SupplyLines.line(s, code).is_empty())
	assert_true(_has(ev, "cancelled", code))

## A foreign regiment made an enemy and stood on the middle of the line's
## road; returns it with where it stood, to be marched off again. Its
## kingdom is one whose other units, made enemies too, stand off the road.
func _cut_the_road() -> Array:
	var route := SupplyLines.road_px(repo, s, code, town)
	var realm := repo.resolve_realm("player_realm")
	@warning_ignore("integer_division")
	var mid := route[route.size() / 2]
	var dip: Dictionary = repo.world_table("political", "diplomacy")
	var army := ArmySystem.roster(repo, s)
	var codes := army.keys()
	codes.sort()
	for c: String in codes:
		var r: Dictionary = army[c]
		if String(r["kingdom_code"]) != realm:
			var key := "%s>%s" % [realm, String(r["kingdom_code"])]
			var had: Variant = dip.get(key)
			dip[key] = {"stance": "Enemy"}
			if not SupplyLines.cut_point(repo, s, route).is_empty():
				if had == null:
					dip.erase(key)
				else:
					dip[key] = had
				continue
			var was := [r, r["x"], r["y"]]
			r["x"] = mid.x
			r["y"] = mid.y
			return was
	return []

func test_a_cut_line_draws_nothing_and_says_so() -> void:
	s.regiments[code]["supplies"] = 0
	_stock(town, 100000, 0, 0)
	assert_false(_cut_the_road().is_empty(), "the pack has a foreign regiment")
	var ev := SupplyLines.day_step(repo, s)
	assert_eq(String(s.supply_lines[code]["state"]), SupplyLines.CUT)
	assert_eq(int(TownStores.stock_of(s, town)["crown"]), 100000)
	assert_true(_has(ev, "cut", code))

func test_a_regiment_in_a_realm_town_is_topped_up_free() -> void:
	s.supply_lines.clear()
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		var reg := ArmySystem.regiment(repo, String(c))
		var held := SupplyLines.home_town(repo, s, String(c))
		if held == "" or String(c) == code or String(reg.get("is_naval", "0")) == "1":
			continue
		s.regiments[c]["supplies"] = 0
		_stock(held, 100000, 0, 0)
		var gold := float(s.metrics["treasury"])
		SupplyLines.day_step(repo, s)
		var use := ArmySystem.supply_use(repo, reg, s)
		@warning_ignore("integer_division")
		var want := (use * ArmySystem.carry_of(repo, s.regiments[c]) + 29) / 30 + ArmySystem.day_bite(use, s.day)
		assert_eq(int(s.regiments[c]["supplies"]), mini(want, ArmySystem.max_units(repo, use) + ArmySystem.day_bite(use, s.day)))
		# once the day's meal is eaten the regiment reads the days it carries, not one short
		ArmySystem.eat_day(repo, s)
		if use >= 30:
			assert_eq(ArmySystem.days_in_hand(int(s.regiments[c]["supplies"]), use), ArmySystem.carry_of(repo, s.regiments[c]))
		assert_eq(float(s.metrics["treasury"]), gold, "no cartage inside a town")
		return
	pending("no regiment stands in a realm town on this pack")

func test_a_line_follows_a_marching_column() -> void:
	var before := SupplyLines.road_km(repo, SupplyLines.road_px(repo, s, code, town))
	var at := ArmySystem.position_of(repo, s, ArmySystem.regiment(repo, code)) + Vector2(60.0, 0.0)
	var m := ArmySystem.pack_to_metres(repo, at)
	s.regiments[code]["x_m"] = m.x
	s.regiments[code]["y_m"] = m.y
	SupplyLines.day_step(repo, s)
	assert_false(SupplyLines.line(s, code).is_empty(), "out of range, the line still runs")
	assert_ne(SupplyLines.road_km(repo, SupplyLines.road_px(repo, s, code, town)), before)

## An ORDERED line waits on its courier; a courier lost on the road (or one
## no longer riding at all) leaves nothing to wait for (Task 6's deferral).
func _order_point() -> void:
	s.supply_lines.erase(code)
	s.metrics["treasury"] = 1000.0
	var req := ActionRequest.make("SUPPLY_POINT_SET", {"regiment": code, "town": town, "rate": 1000})
	var actions := ActionSystem.new(repo)
	assert_eq(actions.validate(req, s), "")
	actions.execute(req, s)

func test_an_ordered_line_waits_while_its_courier_rides() -> void:
	_order_point()
	var ev := SupplyLines.day_step(repo, s)
	assert_eq(String(SupplyLines.line(s, code).get("state", "")), SupplyLines.ORDERED)
	assert_false(_has(ev, "cancelled", code))

## Final review 2: a lost courier is not a lost town — its own letter.
func test_an_ordered_line_whose_courier_is_lost_says_the_orders_never_came() -> void:
	_order_point()
	s.couriers.clear()
	var ev := SupplyLines.day_step(repo, s)
	assert_true(SupplyLines.line(s, code).is_empty())
	assert_true(_has(ev, "order_lost", code))
	assert_false(_has(ev, "cancelled", code), "the town is still ours")
	var m := MissiveWriter.supply_dispatch(repo, s, ev.filter(func(e: Dictionary) -> bool:
		return String(e["type"]) == "order_lost"))
	assert_eq(String((m["facts"] as Array)[0]["text"]), "The supply orders for %s never reached %s." % [
		String(ArmySystem.regiment(repo, code)["label"]), String(repo.burgs[town]["label"])])

## The ORDERED line's own courier lost while a newer point still rides: that
## point is the order now waited on.
func test_a_pending_point_still_riding_is_waited_on_when_the_first_is_lost() -> void:
	_order_point()
	var first := int(s.couriers[0]["id"])
	var req := ActionRequest.make("SUPPLY_POINT_SET", {"regiment": code, "town": town, "rate": 800})
	var actions := ActionSystem.new(repo)
	assert_eq(actions.validate(req, s), "")
	actions.execute(req, s)
	var second := int((SupplyLines.line(s, code)["pending"] as Dictionary)["order_id"])
	s.couriers = s.couriers.filter(func(c: Dictionary) -> bool: return int(c["id"]) != first)
	var ev := SupplyLines.day_step(repo, s)
	var ln := SupplyLines.line(s, code)
	assert_false(_has(ev, "cancelled", code))
	assert_eq(String(ln["state"]), SupplyLines.ORDERED)
	assert_eq(int(ln["order_id"]), second)
	assert_eq(int(ln["rate"]), 800)
	assert_false(ln.has("pending"))

## A CLEAR sent after the SET is lost: the SET still riding is waited on.
func test_a_lost_clear_leaves_the_set_awaited() -> void:
	_order_point()
	var set_id := int(s.couriers[0]["id"])
	var req := ActionRequest.make("SUPPLY_POINT_CLEAR", {"regiment": code})
	var actions := ActionSystem.new(repo)
	assert_eq(actions.validate(req, s), "")
	actions.execute(req, s)
	var clear_id := int(SupplyLines.line(s, code)["order_id"])
	assert_ne(clear_id, set_id)
	s.couriers = s.couriers.filter(func(c: Dictionary) -> bool: return int(c["id"]) != clear_id)
	SupplyLines.day_step(repo, s)
	var ln := SupplyLines.line(s, code)
	assert_eq(String(ln.get("state", "")), SupplyLines.ORDERED)
	assert_eq(int(ln["order_id"]), set_id)

func test_a_pending_point_whose_courier_is_lost_is_dropped() -> void:
	s.metrics["treasury"] = 1000.0
	var req := ActionRequest.make("SUPPLY_POINT_SET", {"regiment": code, "town": town, "rate": 800})
	var actions := ActionSystem.new(repo)
	assert_eq(actions.validate(req, s), "")
	actions.execute(req, s)
	assert_true(SupplyLines.line(s, code).has("pending"))
	SupplyLines.day_step(repo, s)
	assert_true(SupplyLines.line(s, code).has("pending"), "kept while its courier rides")
	s.couriers.clear()
	SupplyLines.day_step(repo, s)
	var ln := SupplyLines.line(s, code)
	assert_false(ln.has("pending"))
	assert_eq(String(ln["state"]), SupplyLines.FLOWING, "the running line runs on")

func test_low_and_empty_are_said_once() -> void:
	s.supply_lines.clear()
	s.regiments[code]["supplies"] = 0
	var ev := SupplyLines.warn_day(repo, s)
	assert_true(_has(ev, "empty", code))
	ev = SupplyLines.warn_day(repo, s)
	assert_false(_has(ev, "empty", code), "said once until it recovers")

## Said off what the host has left once it has eaten the day: a regiment
## eating its last day is empty that very day.
func test_the_tick_warns_after_the_host_eats() -> void:
	s.supply_lines.clear()
	s.day = 5
	s.regiments[code]["supplies"] = ArmySystem.day_bite(_use(), 5)
	# the ground it stands on may feed it (foraging): that is not this test
	repo.balance["forage_supply_per_food_unit"] = 0
	var engine := TickEngine.new(repo)
	engine.advance_day(s)
	assert_eq(int(s.regiments[code]["supplies"]), 0)
	assert_true(_has(engine.day_supply, "empty", code))

func test_a_town_running_short_is_said_once() -> void:
	_stock(town, 1, 0, 0)
	var ev := SupplyLines.warn_day(repo, s)
	assert_true(_has(ev, "town_low", code))
	ev = SupplyLines.warn_day(repo, s)
	assert_false(_has(ev, "town_low", code), "said once until it recovers")
	_stock(town, 1000000, 0, 0)
	SupplyLines.warn_day(repo, s)
	_stock(town, 1, 0, 0)
	assert_true(_has(SupplyLines.warn_day(repo, s), "town_low", code), "short again: said again")

func test_a_cleared_road_restores_the_line_once() -> void:
	_stock(town, 100000, 0, 0)
	var was := _cut_the_road()
	assert_false(was.is_empty(), "the pack has a foreign regiment")
	SupplyLines.day_step(repo, s)
	assert_eq(String(s.supply_lines[code]["state"]), SupplyLines.CUT)
	var r: Dictionary = was[0]
	r["x"] = was[1]
	r["y"] = was[2]
	s.regiments[code]["supplies"] = 0
	var ev := SupplyLines.day_step(repo, s)
	assert_eq(String(s.supply_lines[code]["state"]), SupplyLines.FLOWING)
	assert_eq(ev.filter(func(e: Dictionary) -> bool: return String(e["type"]) == "restored").size(), 1)
	assert_eq(String(s.supply_lines[code]["cut_by"]), "")
	# a unit's day is a unit or two, under a unit once the road has thinned
	# it (the rest carried): the draw is what shows the wagons rolling
	assert_gt(int(s.supply_lines[code]["m_drawn"]), 0, "the wagons roll again")
	assert_false(_has(SupplyLines.day_step(repo, s), "restored", code), "said once")

## The remainders are carried (fix round 1): a small regiment's month of
## draws, under a clumsy, skimming marshal, comes to what the plan projects.
func test_a_month_of_small_draws_comes_to_the_plan() -> void:
	var m: Character = s.characters[String(s.council["marshal"])]
	m.traits = ["venal"]
	m.skills["sk_admin"] = 4
	_stock(town, 100000, 0, 0)
	s.regiments[code]["supplies"] = 0
	var rows := SupplySystem.plan(repo, s)
	assert_eq(rows.size(), 1)
	var row: Dictionary = rows[0]
	assert_lt(int(row["efficiency"]), 1000)
	assert_gt(int(row["skim"]), 0)
	@warning_ignore("integer_division")
	assert_eq(ArmySystem.day_bite(_use(), 1) * int(row["skim"]) / 1000, 0, "a day's skim is under a unit")
	for d in range(1, Calendar.DAYS_PER_TICK + 1):
		s.day = d
		SupplyLines.day_step(repo, s)
	var ln := SupplyLines.line(s, code)
	assert_eq(int(ln["m_drawn"]), int(row["need"]))
	assert_almost_eq(float(ln["m_arrived"]), float(row["delivered"]), 2.0)
	assert_almost_eq(float(ln["m_claimed"]), float(row["claimed"]), 2.0)
	assert_gt(int(ln["m_skim"]), 0)
	@warning_ignore("integer_division")
	assert_almost_eq(float(ln["m_skim"]), float(int(row["need"]) * int(row["skim"]) / 1000), 1.0)
	assert_lt(int(ln["m_arrived"]), int(ln["m_claimed"]))

func test_a_refill_that_buys_from_a_house_is_counted_on_the_regiment() -> void:
	s.supply_lines.clear()
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		var reg := ArmySystem.regiment(repo, String(c))
		var held := SupplyLines.home_town(repo, s, String(c))
		if held == "" or String(c) == code or String(reg.get("is_naval", "0")) == "1":
			continue
		s.regiments[c]["supplies"] = 0
		_stock(held, 0, 0, 100000)
		s.metrics["treasury"] = 100000.0
		SupplyLines.day_step(repo, s)
		var e: Dictionary = s.regiments[c]
		assert_gt(int(e.get("m_buy", 0)), 0)
		assert_eq(100000.0 - float(s.metrics["treasury"]), float(e["m_buy"]), "the gold paid")
		var units := 0
		for h: String in e["m_bought"]:
			units += int(e["m_bought"][h])
		assert_eq(units, 100000 - int(TownStores.stock_of(s, held)["house"]), "the units bought, by house")
		return
	pending("no regiment stands in a realm town on this pack")

func test_the_tick_engine_runs_the_day_and_keeps_its_events() -> void:
	var engine := TickEngine.new(repo)
	s.supply_lines[code]["state"] = SupplyLines.RIDING
	s.supply_lines[code]["ready_day"] = s.absolute_day()
	engine.advance_day(s)
	assert_true(_has(engine.day_supply, "opened", code))
	assert_eq(String(SupplyLines.line(s, code)["state"]), SupplyLines.FLOWING)

## A land regiment of the realm standing in a realm town that is not the
## depot, other than the line's regiment, that eats at least a unit every
## day (a small unit's month spread over thirty days skips some); "" with none.
func _quartered_off_the_depot() -> String:
	var dep := TownStores.depot(repo, s)
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		var held := SupplyLines.home_town(repo, s, String(c))
		var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, String(c), s), s)
		if String(c) != code and held != "" and held != dep and use >= Calendar.DAYS_PER_TICK:
			return String(c)
	return ""

## Its own town run dry (final review 1), a regiment quartered there takes
## the rest of its load from the depot — crown, then lord, never a house's
## stock there — free of cartage, and the dispatch says so once.
func test_a_regiment_whose_town_is_dry_is_fed_from_the_depot() -> void:
	s.supply_lines.clear()
	var c := _quartered_off_the_depot()
	if c == "":
		pending("no regiment stands in a realm town other than the depot")
		return
	var held := SupplyLines.home_town(repo, s, c)
	var dep := TownStores.depot(repo, s)
	s.town_stock[held] = {"crown": 0, "lord": 0, "house": 0}
	s.town_stock[dep] = {"crown": 3, "lord": 100000, "house": 100000}
	TownStores.sync_metrics(repo, s)
	s.regiments[c]["supplies"] = 0
	var gold := float(s.metrics["treasury"])
	var ev := SupplyLines.day_step(repo, s)
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c), s)
	var bite := ArmySystem.day_bite(use, s.day)
	@warning_ignore("integer_division")
	var want := mini((use * ArmySystem.carry_of(repo, s.regiments[c]) + 29) / 30 + bite,
		ArmySystem.max_units(repo, use) + bite)
	assert_eq(int(s.regiments[c]["supplies"]), want, "topped up in full")
	var st := TownStores.stock_of(s, dep)
	assert_eq(int(st["crown"]), 0, "the crown's first")
	assert_eq(int(st["lord"]), 100000 - (want - 3), "then the lord's")
	assert_eq(int(st["house"]), 100000, "no house's stock is bought at the depot")
	assert_eq(float(s.metrics["treasury"]), gold, "no cartage, no purchase")
	var dry: Array = ev.filter(func(e: Dictionary) -> bool: return String(e["type"]) == "town_dry")
	assert_eq(dry.size(), 1)
	assert_eq(String(dry[0]["regiment"]), c)
	assert_eq(String(dry[0]["town"]), held)
	assert_eq(String(dry[0]["depot"]), dep)
	assert_eq(String(SupplyLines.refill_of(repo, s, c)["from"]), dep)
	ArmySystem.eat_day(repo, s)
	assert_false(_has(SupplyLines.day_step(repo, s), "town_dry", c), "said once while it lasts")
	# the town restocked feeds it again; run dry once more, it is said again
	_stock(held, 100000, 0, 0)
	ArmySystem.eat_day(repo, s)
	SupplyLines.day_step(repo, s)
	assert_eq(String(SupplyLines.refill_of(repo, s, c)["from"]), held)
	_stock(held, 0, 0, 0)
	ArmySystem.eat_day(repo, s)
	assert_true(_has(SupplyLines.day_step(repo, s), "town_dry", c), "dry again: said again")

## A regiment its own town fills reads that town as its feeder.
func test_a_regiment_its_town_fills_is_fed_by_that_town() -> void:
	s.supply_lines.clear()
	var c := _quartered_off_the_depot()
	if c == "":
		pending("no regiment stands in a realm town other than the depot")
		return
	var held := SupplyLines.home_town(repo, s, c)
	_stock(held, 100000, 0, 0)
	s.regiments[c]["supplies"] = 0
	assert_false(_has(SupplyLines.day_step(repo, s), "town_dry", c))
	assert_eq(SupplyLines.refill_of(repo, s, c), {"town": held, "from": held})

## Its own town and the depot both dry (owner 2026-10-07, option A), a
## regiment quartered in a realm town draws the CROWN's stock of the other
## realm towns, nearest first — never their lord's or a house's, and free.
func test_a_dry_town_and_depot_draw_the_crowns_stores_nearest_first() -> void:
	s.supply_lines.clear()
	var c := _quartered_off_the_depot()
	if c == "":
		pending("no regiment stands in a realm town other than the depot")
		return
	var held := SupplyLines.home_town(repo, s, c)
	var dep := TownStores.depot(repo, s)
	var order: Array = TownStores.nearest_first(repo, s, held).filter(func(t: String) -> bool: return t != dep)
	assert_gt(order.size(), 2, "two other realm towns")
	var near := String(order[0])
	var far := String(order[order.size() - 1])
	var at := Vector2(float(repo.burgs[held]["x"]), float(repo.burgs[held]["y"]))
	assert_lt(at.distance_to(Vector2(float(repo.burgs[near]["x"]), float(repo.burgs[near]["y"]))),
		at.distance_to(Vector2(float(repo.burgs[far]["x"]), float(repo.burgs[far]["y"]))), "the near town is nearer")
	for t: String in TownStores.realm_towns(repo, s):
		s.town_stock[t] = {"crown": 0, "lord": 0, "house": 0}
	s.town_stock[near] = {"crown": 1, "lord": 100000, "house": 100000}
	_stock(far, 100000, 100000, 100000)
	s.regiments[c]["supplies"] = 0
	var gold := float(s.metrics["treasury"])
	var ev := SupplyLines.day_step(repo, s)
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, c), s)
	var bite := ArmySystem.day_bite(use, s.day)
	@warning_ignore("integer_division")
	var want := mini((use * ArmySystem.carry_of(repo, s.regiments[c]) + 29) / 30 + bite,
		ArmySystem.max_units(repo, use) + bite)
	assert_eq(int(s.regiments[c]["supplies"]), want, "topped up in full")
	assert_eq(TownStores.stock_of(s, near), {"crown": 0, "lord": 100000, "house": 100000}, "the nearer town's crown first")
	assert_eq(TownStores.stock_of(s, far), {"crown": 100000 - (want - 1), "lord": 100000, "house": 100000},
		"then the farther one's crown; no lord's, no house's")
	assert_eq(float(s.metrics["treasury"]), gold, "no cartage, no purchase")
	assert_eq(int(s.metrics["strategic"]), TownStores.gold_of_units(repo, TownStores.total(s, "crown")))
	var dry: Array = ev.filter(func(e: Dictionary) -> bool: return String(e["type"]) == "town_dry")
	assert_eq(dry.size(), 1)
	assert_true(bool(dry[0]["realm"]), "the realm's other towns fed it")
	assert_eq(SupplyLines.refill_of(repo, s, c), {"town": held, "from": ""})
	assert_string_contains(SupplyLines.refill_words(repo, s, c), "fed from the realm's stores")
	# the nearer town restocked, it alone feeds the next day's top-up
	_stock(near, 100000, 0, 0)
	ArmySystem.eat_day(repo, s)
	SupplyLines.day_step(repo, s)
	assert_eq(int(TownStores.stock_of(s, far)["crown"]), 100000 - (want - 1), "the farther town untouched")
	assert_lt(int(TownStores.stock_of(s, near)["crown"]), 100000)
