extends GutTest

var data: DataRepository
var engine: TickEngine

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	engine = TickEngine.new(data)

func test_advance_increments_and_reports() -> void:
	var s := GameState.new_campaign(data, 42)
	var r := engine.advance(s)
	assert_eq(r.tick, 1)
	assert_eq(s.tick, 1)
	assert_eq(r.season, "spring")
	assert_gt(r.metric_deltas.size(), 0)
	for d in r.metric_deltas:
		assert_ne(d["reason"], "")

## The month's settlement (spec §5): the crown's provinces in full, a share
## of the rest, less salaries and the ration — all whole gold, all from
## RealmEconomy's sums for the month that just ended.
func test_the_months_end_settles_the_three_pools() -> void:
	var s := GameState.new_campaign(data, 42)
	var e := RealmEconomy.realm(data, s)
	var share := data.bal("crown_share_permille") / 1000.0
	var expect := {}
	for k in ["tax", "strategic", "civil"]:
		var own := int(e["crown"][k])
		expect[k] = own + int(roundf(share * float(int(e["realm"][k]) - own)))
	var salaries := 0
	for seat: String in s.council:
		salaries += int(float(data.seats[seat].get("salary_gold", 0)))
	assert_gt(salaries, 0, "ministers are paid")
	var people := 0
	for code: String in MapManors.controlled_provinces(data, s):
		people += int(roundf(float(WorldLedger.value_of(data, s, "economy.provinces.%s.rural_population" % code))))
		people += int(roundf(float(WorldLedger.value_of(data, s, "economy.provinces.%s.urban_population" % code))))
	var ration := int(roundf(float(people) / 1000.0 * data.bal("ration_gold_per_1000")))
	var t0 := int(s.metrics["treasury"])
	var st0 := int(s.metrics["strategic"])
	var cv0 := int(s.metrics["grain"])
	var built := MapManors.crown_building_effects(data, s)
	s.tick = 0  # spring: no harvest
	var r := engine.advance(s)
	assert_eq(int(s.metrics["treasury"]), t0 + expect["tax"] - salaries + int(built["treasury"]))
	assert_eq(int(s.metrics["strategic"]), st0 + expect["strategic"])
	assert_eq(int(s.metrics["grain"]), cv0 + expect["civil"] - ration + int(built["grain"]))
	assert_eq(int(s.metrics["tax_income"]), expect["tax"])
	var reasons: Array = []
	for d in r.metric_deltas:
		reasons.append(String(d["reason"]))
	for want in ["taxes of the crown's provinces", "the crown's share of the realm's taxes",
			"ministers' salaries", "the court's ration"]:
		assert_true(want in reasons, want)
	for m in ["treasury", "strategic", "grain"]:
		assert_eq(s.metrics[m], float(int(s.metrics[m])), "%s stays whole" % m)

## The pool stops at empty, and the stop is a ledger line like any other
## (CLAUDE.md invariant 4): a court that eats more than the realm makes
## leaves the stores at exactly 0, with the write-off given its reason.
func test_the_civil_pool_cannot_fall_below_empty() -> void:
	var s := GameState.new_campaign(data, 42)
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
	var s := GameState.new_campaign(data, 42)
	s.tick = 6  # advance() settles month 6 and makes it 7: autumn
	var before := int(s.metrics["grain"])
	var r := engine.advance(s)
	var harvest := 0
	for d in r.metric_deltas:
		if String(d["reason"]) == "the harvest comes in":
			harvest = int(d["delta"])
	assert_gt(harvest, 0)
	assert_gt(int(s.metrics["grain"]), before, "the harvest outweighs the ration")

func test_the_day_step_warms_a_bucket() -> void:
	var s := GameState.new_campaign(data, 42)
	RealmEconomy.forget()
	engine.advance_day(s)
	assert_gt(RealmEconomy.compute_count, 0, "a day computes its bucket")
	assert_lt(RealmEconomy.compute_count, 20, "not the realm")

func test_the_pools_start_with_months_of_the_crowns_own_production() -> void:
	var s := GameState.new_campaign(data, 42)
	var e := RealmEconomy.realm(data, s)
	assert_eq(int(s.metrics["strategic"]), int(e["crown"]["strategic"]) * int(data.bal("start_strategic_months")))
	assert_eq(int(s.metrics["grain"]), int(e["crown"]["civil"]) * int(data.bal("start_civil_months")))

func test_outcomes_drain_into_next_report() -> void:
	var s := GameState.new_campaign(data, 42)
	engine.advance(s)
	engine.actions.execute(ActionRequest.make("TAX_RATE_ADJUST", {"delta": 1}), s)
	var r := engine.advance(s)
	assert_eq(r.outcomes.size(), 1)
	assert_eq(s.recent_outcomes.size(), 0)
	assert_eq(r.outcomes[0]["action_code"], "TAX_RATE_ADJUST")

## The crown's own provinces pay their taxes in full (spec §5), as a
## treasury line of their own with its own reason; the manors the crown
## buys pay from the month they give it the province.
func test_the_crowns_provinces_pay_their_taxes_each_month() -> void:
	var s := GameState.new_campaign(data, 42)
	var expected := int(RealmEconomy.realm(data, s)["crown"]["tax"])
	assert_gt(expected, 0, "the crown holds tax-paying manors")
	var r := engine.advance(s)
	var found := false
	for d in r.metric_deltas:
		if d["metric"] == "treasury" and String(d["reason"]) == "taxes of the crown's provinces":
			found = true
			assert_eq(int(d["delta"]), expected)
	assert_true(found, "the crown's own taxes are a treasury line of their own")
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
	for d in r2.metric_deltas:
		if d["metric"] == "treasury" and String(d["reason"]) == "taxes of the crown's provinces":
			assert_eq(int(d["delta"]), grown)

## The day (owner 2026-09-13): advance_day steps the works and the day;
## the thirtieth day's end is a tick, which resets the day and steps the
## works again, so a work takes exactly its build_days days.
func test_days_step_works_and_the_thirtieth_is_a_tick() -> void:
	var s := GameState.new_campaign(data, 42)
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
	for i in days - 1:
		assert_eq(engine.advance_day(s), [], "day %d" % (i + 2))
	assert_eq(engine.advance_day(s), [{"cell": cell, "building": "palisade"}], "done on its last day")
	var finished_at_day := s.absolute_day()
	for i in Calendar.DAYS_PER_TICK - 1 - days:
		assert_eq(engine.advance_day(s), [])
	assert_eq(s.day, Calendar.DAYS_PER_TICK)
	assert_eq(engine.advance_day(s), [], "the day does not pass the tick's end on its own")
	assert_eq(s.day, Calendar.DAYS_PER_TICK)
	var r := engine.advance(s)
	assert_eq(s.tick, 2)
	assert_eq(s.day, 1)
	assert_eq(s.absolute_day(), Calendar.DAYS_PER_TICK + 1)
	assert_eq(r.finished_works, [])
	assert_eq(finished_at_day, 1 + days, "it stood on the day its days were up")
	assert_eq(MapManors.buildings_of(s, cell), ["palisade"])

## A work longer than a month survives the tick (owner 2026-09-14): the day
## count carries across a GameState.day rollover to 1 and a tick increment,
## so a building started in one tick can finish in the next.
func test_a_work_longer_than_a_month_survives_the_tick() -> void:
	var s := GameState.new_campaign(data, 42)
	engine.advance(s)
	assert_eq(s.tick, 1)
	assert_eq(s.day, 1)
	var cell := -1
	for c: int in MapManors.manors_of_house(data, s, MapManors.crown(s), data.resolve_realm("player_realm")):
		cell = c
		break
	assert_gt(cell, -1)
	var days := int(float(data.manor_buildings["chapel"]["build_days"]))
	assert_gt(days, Calendar.DAYS_PER_TICK, "a chapel outlasts a month")
	assert_true(MapManors.start_work(data, s, cell, "chapel", "test"))
	assert_eq(MapManors.work_days_left(s, cell, "chapel"), days)
	for i in Calendar.DAYS_PER_TICK - 1:
		assert_eq(engine.advance_day(s), [], "day %d" % (i + 2))
	assert_eq(s.day, Calendar.DAYS_PER_TICK)
	assert_eq(MapManors.work_days_left(s, cell, "chapel"), days - (Calendar.DAYS_PER_TICK - 1))
	var r := engine.advance(s)
	assert_eq(s.tick, 2)
	assert_eq(s.day, 1)
	assert_eq(r.finished_works, [], "still under construction after the tick")
	assert_eq(MapManors.work_days_left(s, cell, "chapel"), days - Calendar.DAYS_PER_TICK,
		"the day count carried across the tick boundary, one day fewer than before advance()")
	for i in days - Calendar.DAYS_PER_TICK - 1:
		assert_eq(engine.advance_day(s), [])
	assert_eq(engine.advance_day(s), [{"cell": cell, "building": "chapel"}],
		"finishes on its last day, in the tick after the one it began in")
	assert_eq(s.tick, 2, "it finished without a further tick passing")
	assert_eq(s.absolute_day(), 1 + days, "it stands on the day its days are up")
	assert_eq(MapManors.buildings_of(s, cell), ["chapel"])

## A finished building works each tick (owner 2026-09-13): a market's tolls
## are a treasury line of their own.
func test_the_crowns_buildings_pay_each_tick() -> void:
	var s := GameState.new_campaign(data, 42)
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
		if d["metric"] == "treasury" and String(d["reason"]).contains("buildings"):
			found = true
			assert_almost_eq(float(d["delta"]), tolls, 0.001)
	assert_true(found, "the tolls are a line of their own")
