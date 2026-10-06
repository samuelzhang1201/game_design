extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

var data: DataRepository
var engine: TickEngine

func before_each() -> void:
	data = SuiteData.repo()
	engine = TickEngine.new(data)

## The month's settlement (spec §5): the crown's provinces in full, a share
## of the rest, less salaries and the ration — all whole gold, all from
## RealmEconomy's sums for the month that just ended.
func test_the_months_end_settles_the_three_pools() -> void:
	var s := SuiteData.campaign(data, 42)
	# The regiments stand fully supplied, so the month's refill draws on no
	# stock and the pools move only by what is settled here.
	for rc: String in s.regiments:
		s.regiments[rc]["supplies"] = ArmySystem.supply_use(data, ArmySystem.regiment(data, rc)) * 6
	# Two purses (owner 2026-09-14): the lord's own provinces in full, the
	# crown's treasury its share of the rest (RealmEconomy.purses).
	var p := RealmEconomy.purses(data, s)
	var salaries := 0
	for seat: String in s.council:
		salaries += int(float(data.seats[seat].get("salary_gold", 0)))
	assert_gt(salaries, 0, "ministers are paid")
	var people := 0
	for code: String in MapManors.controlled_provinces(data, s):
		people += int(roundf(float(WorldLedger.value_of(data, s, "economy.provinces.%s.rural_population" % code))))
		people += int(roundf(float(WorldLedger.value_of(data, s, "economy.provinces.%s.urban_population" % code))))
	var ration := int(roundf(float(people) / 1000.0 * data.bal("ration_gold_per_1000")))
	var before := {}
	for m in ["treasury", "strategic", "grain", "lord_gold", "lord_strategic", "lord_civil"]:
		before[m] = int(s.metrics[m])
	var built := MapManors.crown_building_effects(data, s)
	# The trade tolls (LEDGER M6) land in the treasury with the month.
	var tolls := 0
	for route: Dictionary in MarketSystem.routes(data, s):
		tolls += int(route["toll"])
	assert_gt(tolls, 0, "the realm trades abroad")
	s.tick = 0  # spring: no harvest
	var r := engine.advance(s)
	assert_eq(r.tick, 1)
	assert_eq(s.tick, 1)
	assert_eq(r.season, "spring")
	for d in r.metric_deltas:
		assert_ne(d["reason"], "", "every line has its reason")
	# The crown: its share of the realm and its tolls, less the court's
	# salaries and table.
	assert_eq(int(s.metrics["treasury"]), before["treasury"] + int(p["realm_share"]["tax"]) + tolls - salaries)
	assert_eq(int(s.metrics["strategic"]), before["strategic"] + int(p["realm_share"]["strategic"]))
	assert_eq(int(s.metrics["grain"]), before["grain"] + int(p["realm_share"]["civil"]) - ration)
	# The lord: his own provinces in full, and his buildings.
	assert_eq(int(s.metrics["lord_gold"]), before["lord_gold"] + int(p["lord"]["tax"]) + int(built["treasury"]))
	assert_eq(int(s.metrics["lord_strategic"]), before["lord_strategic"] + int(p["lord"]["strategic"]))
	assert_eq(int(s.metrics["lord_civil"]), before["lord_civil"] + int(p["lord"]["civil"]) + int(built["grain"]))
	assert_eq(int(s.metrics["tax_income"]), int(p["lord"]["tax"]) + int(p["realm_share"]["tax"]))
	var reasons: Array = []
	for d in r.metric_deltas:
		reasons.append(String(d["reason"]))
	for want in ["taxes of your own provinces", "the crown's share of the realm's taxes",
			"ministers' salaries", "the court's ration"]:
		assert_true(want in reasons, want)
	for m in ["treasury", "strategic", "grain", "lord_gold", "lord_strategic", "lord_civil"]:
		assert_eq(s.metrics[m], float(int(s.metrics[m])), "%s stays whole" % m)

## The pool stops at empty, and the stop is a ledger line like any other
## (CLAUDE.md invariant 4): a court that eats more than the realm makes
## leaves the stores at exactly 0, with the write-off given its reason.
func test_the_civil_pool_cannot_fall_below_empty() -> void:
	var s := SuiteData.campaign(data, 42)
	s.metrics["grain"] = 0.0
	var was: float = data.bal("ration_gold_per_1000")
	data.balance["ration_gold_per_1000"] = 1000000.0
	var r := engine.advance(s)
	data.balance["ration_gold_per_1000"] = was
	assert_eq(s.metrics["grain"], 0.0, "the stores stand at empty, not below")
	var written_off := 0.0
	for d in r.metric_deltas:
		if String(d["reason"]) == "the stores cannot fall below empty":
			written_off = float(d["delta"])
	assert_gt(written_off, 0.0, "what could not be eaten is a line with a reason")

func test_the_harvest_is_civil_goods_in_autumn() -> void:
	var s := SuiteData.campaign(data, 42)
	s.tick = 6  # advance() settles month 6 and makes it 7: autumn
	var before := int(s.metrics["lord_civil"])
	var r := engine.advance(s)
	var harvest := 0
	for d in r.metric_deltas:
		if String(d["reason"]) == "the harvest comes in":
			harvest = int(d["delta"])
	assert_gt(harvest, 0)
	assert_gt(int(s.metrics["lord_civil"]), before, "the harvest fills the lord's own stores")

func test_the_day_step_warms_a_bucket() -> void:
	var s := SuiteData.campaign(data, 42)
	RealmEconomy.forget()
	engine.advance_day(s)
	assert_gt(RealmEconomy.compute_count, 0, "a day computes its bucket")
	assert_lt(RealmEconomy.compute_count, 20, "not the realm")

func test_the_pools_start_with_months_of_the_crowns_own_production() -> void:
	var s := SuiteData.campaign(data, 42)
	var p := RealmEconomy.purses(data, s)
	var st := int(data.bal("start_strategic_months"))
	var cv := int(data.bal("start_civil_months"))
	assert_eq(int(s.metrics["lord_strategic"]), int(p["lord"]["strategic"]) * st)
	assert_eq(int(s.metrics["lord_civil"]), int(p["lord"]["civil"]) * cv)
	assert_eq(int(s.metrics["strategic"]), int(p["realm_share"]["strategic"]) * st)
	assert_eq(int(s.metrics["grain"]), int(p["realm_share"]["civil"]) * cv)
	assert_gt(int(s.metrics["lord_gold"]), 0, "the lord starts with what his towns hold")

func test_outcomes_drain_into_next_report() -> void:
	var s := SuiteData.campaign(data, 42)
	engine.advance(s)
	engine.actions.execute(ActionRequest.make("TAX_RATE_ADJUST", {"delta": 1}), s)
	var r := engine.advance(s)
	assert_eq(r.outcomes.size(), 1)
	assert_eq(s.recent_outcomes.size(), 0)
	assert_eq(r.outcomes[0]["action_code"], "TAX_RATE_ADJUST")

## The crown's own provinces pay their taxes in full (spec §5; the month's
## line itself is test_the_months_end_settles_the_three_pools): the manors
## the crown buys pay from the month they give it the province.
func test_the_crowns_provinces_pay_their_taxes_each_month() -> void:
	var s := SuiteData.campaign(data, 42)
	var expected := int(RealmEconomy.realm(data, s)["crown"]["tax"])
	assert_gt(expected, 0, "the crown holds tax-paying manors")
	# Buying every manor of another province of the realm makes it the
	# crown's, and from the next month it pays in full too.
	var realm := data.resolve_realm("player_realm")
	var taken := ""
	for province: String in MapOwnership.provinces_of(data, s, realm):
		if not MapManors.crown_controls(data, s, province) \
				and not MapManors.manors_of_province(data, province).is_empty():
			taken = province
			break
	assert_ne(taken, "", "the realm holds a province the crown does not")
	for cell: int in MapManors.manors_of_province(data, taken):
		MapManors.set_owner(data, s, cell, MapManors.crown(s), "bought")
	assert_true(MapManors.crown_controls(data, s, taken))
	var grown := int(RealmEconomy.realm(data, s)["crown"]["tax"])
	assert_gt(grown, expected, "the province joined the crown's own taxes")
	var r2 := engine.advance(s)
	var found := false
	for d in r2.metric_deltas:
		if d["metric"] == "lord_gold" and String(d["reason"]) == "taxes of your own provinces":
			found = true
			assert_eq(int(d["delta"]), grown)
	assert_true(found, "your own provinces' taxes are a line of the lord's purse")

## The day (owner 2026-09-13): advance_day steps the works and the day;
## the thirtieth day's end is a tick, which resets the day and steps the
## works again, so a work takes exactly its build_days days.
func test_days_step_works_and_the_thirtieth_is_a_tick() -> void:
	var s := SuiteData.campaign(data, 42)
	engine.advance(s)
	assert_eq(s.tick, 1)
	assert_eq(s.day, 1)
	assert_eq(s.absolute_day(), 1)
	var cell := -1
	for c: int in MapManors.manors_of_house(data, s, MapManors.crown(s), data.resolve_realm("player_realm")):
		cell = c
		break
	assert_gt(cell, -1)
	var days := int(float(data.manor_buildings["palisade"]["build_days"]))
	assert_lt(days, Calendar.DAYS_PER_TICK, "a palisade is done within a month")
	assert_true(MapManors.start_work(data, s, cell, "palisade", "test"))
	# LEDGER M5: the province's artisans can speed a work along, so how many
	# CALLS to advance_day it actually takes is work_speed_permille's, not
	# build_days' own count — compute it the same way test_artisans.gd does.
	var province := MapManors.province_of(data, cell, s)
	var speed := MapManors.work_speed_permille(data, s, province)
	var need := int(ceil(float(days) * 1000.0 / float(speed)))
	for i in need - 1:
		assert_eq(engine.advance_day(s), [], "day %d" % (i + 2))
	assert_eq(engine.advance_day(s), [{"cell": cell, "building": "palisade"}], "done on its last day")
	var finished_at_day := s.absolute_day()
	for i in Calendar.DAYS_PER_TICK - 1 - need:
		assert_eq(engine.advance_day(s), [])
	assert_eq(s.day, Calendar.DAYS_PER_TICK)
	assert_eq(engine.advance_day(s), [], "the day does not pass the tick's end on its own")
	assert_eq(s.day, Calendar.DAYS_PER_TICK)
	var r := engine.advance(s)
	assert_eq(s.tick, 2)
	assert_eq(s.day, 1)
	assert_eq(s.absolute_day(), Calendar.DAYS_PER_TICK + 1)
	assert_eq(r.finished_works, [])
	assert_eq(finished_at_day, 1 + need, "it stood on the day its artisans had it done")
	assert_eq(MapManors.buildings_of(s, cell), ["palisade"])

## A work longer than a month survives the tick (owner 2026-09-14): the day
## count carries across a GameState.day rollover to 1 and a tick increment,
## so a building started in one tick can finish in the next.
func test_a_work_longer_than_a_month_survives_the_tick() -> void:
	var s := SuiteData.campaign(data, 42)
	engine.advance(s)
	assert_eq(s.tick, 1)
	assert_eq(s.day, 1)
	var cell := -1
	for c: int in MapManors.manors_of_house(data, s, MapManors.crown(s), data.resolve_realm("player_realm")):
		cell = c
		break
	assert_gt(cell, -1)
	# manor_house, not chapel (LEDGER M5): the artisans' bonus can bring a
	# work's ACTUAL length under a month even when its build_days does not,
	# and chapel's 40 no longer clears Calendar.DAYS_PER_TICK once a real
	# campaign's townsfolk are speeding it along — manor_house's 60 still
	# does. work_days_left now reads the artisans' own pace once advance_works
	# has touched the work (final fix wave, I1: ceil((days*1000-done)/speed)),
	# so its expected values below are `need`'s own figure less the real days
	# elapsed, not the plain build_days.
	var days := int(float(data.manor_buildings["manor_house"]["build_days"]))
	assert_gt(days, Calendar.DAYS_PER_TICK, "a manor house outlasts a month")
	assert_true(MapManors.start_work(data, s, cell, "manor_house", "test"))
	assert_eq(MapManors.work_days_left(data, s, cell, "manor_house"), days,
		"no done yet: the plain elapsed-days fallback")
	var province := MapManors.province_of(data, cell, s)
	var speed := MapManors.work_speed_permille(data, s, province)
	var need := int(ceil(float(days) * 1000.0 / float(speed)))
	assert_gt(need, Calendar.DAYS_PER_TICK, "it outlasts a month even at the artisans' pace")
	for i in Calendar.DAYS_PER_TICK - 1:
		assert_eq(engine.advance_day(s), [], "day %d" % (i + 2))
	assert_eq(s.day, Calendar.DAYS_PER_TICK)
	assert_eq(MapManors.work_days_left(data, s, cell, "manor_house"), need - (Calendar.DAYS_PER_TICK - 1))
	var r := engine.advance(s)
	assert_eq(s.tick, 2)
	assert_eq(s.day, 1)
	assert_eq(r.finished_works, [], "still under construction after the tick")
	assert_eq(MapManors.work_days_left(data, s, cell, "manor_house"), need - Calendar.DAYS_PER_TICK,
		"the day count carried across the tick boundary, one day fewer than before advance()")
	for i in need - Calendar.DAYS_PER_TICK - 1:
		assert_eq(engine.advance_day(s), [])
	assert_eq(engine.advance_day(s), [{"cell": cell, "building": "manor_house"}],
		"finishes on its last day, in the tick after the one it began in")
	assert_eq(s.tick, 2, "it finished without a further tick passing")
	assert_eq(s.absolute_day(), 1 + need, "it stands on the day its artisans had it done")
	assert_eq(MapManors.buildings_of(s, cell), ["manor_house"])

## A finished building works each tick (owner 2026-09-13): a market's tolls
## are a treasury line of their own.
func test_the_crowns_buildings_pay_each_tick() -> void:
	var s := SuiteData.campaign(data, 42)
	var cell := -1
	for c: int in MapManors.manors_of_house(data, s, MapManors.crown(s), data.resolve_realm("player_realm")):
		cell = c
		break
	assert_true(MapManors.build(data, s, cell, "market", "test"))
	var r := engine.advance(s)
	var tolls := float(data.manor_buildings["market"]["gold_per_tick"])
	assert_gt(tolls, 0.0)
	var found := false
	for d in r.metric_deltas:
		if d["metric"] == "lord_gold" and String(d["reason"]).contains("buildings"):
			found = true
			assert_almost_eq(float(d["delta"]), tolls, 0.001)
	assert_true(found, "the tolls are a line of their own")


## Owner 2026-10-06 (顶栏日期滞后一天): GameState.day is the day being PLAYED —
## the date the top bar shows. The reign's opening tick ends no day, so day 1
## is played; advance_day ends the running day (a column due that day arrives
## then) and only then turns the calendar.
func test_the_running_day_is_the_day_shown_and_ends_at_advance_day() -> void:
	var s := SuiteData.campaign(data, 42)
	var code := ""
	for r: Dictionary in MapObjects.regiments_of(data, data.resolve_realm("player_realm")):
		if ArmySystem.base_pace_km(data, r) > 0 and String(r.get("is_naval", "0")) != "1":
			code = String(r["regiment_code"])
			break
	var reg := ArmySystem.regiment(data, code)
	engine.advance(s)   # the reign's opening
	assert_eq([s.tick, s.day], [1, 1], "the reign opens on its first day, still to be played")
	var home: Vector2 = ArmySystem.position_of(data, s, reg)
	var step := float(ArmySystem.day_march_m(data, s, code))
	ArmySystem.set_march(data, s, code, home + Vector2(step * 0.5 / float(ArmySystem.metres_per_pack_px(data)), 0.0))
	assert_eq(ArmySystem.days_out(data, s, code), 1, "due as the day now running ends")
	assert_eq(ArmySystem.position_of(data, s, reg), home, "nothing moves before the day ends")
	engine.advance_day(s)
	assert_eq(engine.day_arrivals, [code], "it arrives as day 1 ends")
	assert_eq(s.day, 2, "and day 2 begins")
