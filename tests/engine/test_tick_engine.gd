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

func test_tax_income_formula() -> void:
	var s := GameState.new_campaign(data, 42)
	engine.advance(s)
	# income = tax_rate(5) * admin_capacity * 0.8 + tariff_rate(3) * 3.0 + road bonus(0)
	var chancellor: Character = s.characters[s.council["chancellor"]]
	var capacity_bonus_per_skill: float = float(data.seats["chancellor"]["capacity_bonus_per_skill"])
	var cap: float = data.bal("admin_base") + chancellor.skills["sk_admin"] * capacity_bonus_per_skill
	var expected: float = 5.0 * cap * data.bal("tax_income_factor") + 3.0 * data.bal("tariff_income_factor")
	assert_almost_eq(s.metrics["tax_income"], expected, 0.001)

func test_grain_seasonal() -> void:
	var s := GameState.new_campaign(data, 42)
	s.tick = 6  # advance() makes it 7 -> autumn (1-based season blocks)
	var g0: float = s.metrics["grain"]
	engine.advance(s)
	assert_gt(s.metrics["grain"], g0)  # harvest
	s.tick = 9  # -> 10, winter
	var g1: float = s.metrics["grain"]
	engine.advance(s)
	assert_lt(s.metrics["grain"], g1)

func test_outcomes_drain_into_next_report() -> void:
	var s := GameState.new_campaign(data, 42)
	engine.advance(s)
	engine.actions.execute(ActionRequest.make("TAX_RATE_ADJUST", {"delta": 1}), s)
	var r := engine.advance(s)
	assert_eq(r.outcomes.size(), 1)
	assert_eq(s.recent_outcomes.size(), 0)
	assert_eq(r.outcomes[0]["action_code"], "TAX_RATE_ADJUST")

## Manor rents (MANOR_SYSTEM.md §3): each tick the crown's manors pay their
## rent into the treasury, as its own line with its own reason, and the
## figure is what MapManors says it is. Buying a manor raises next tick's.
func test_the_crowns_manors_pay_rent_each_tick() -> void:
	var s := GameState.new_campaign(data, 42)
	var expected := MapManors.crown_rents(data, s)
	assert_gt(expected, 0.0, "the crown holds rent-paying manors")
	var r := engine.advance(s)
	assert_almost_eq(s.metrics["manor_rents"], expected, 0.001)
	var found := false
	for d in r.metric_deltas:
		if d["metric"] == "treasury" and String(d["reason"]).contains("manor"):
			found = true
			assert_almost_eq(float(d["delta"]), expected, 0.001)
	assert_true(found, "the rents are a treasury line of their own")
	assert_lt(expected, s.metrics["tax_income"], "rents supplement the taxes, they do not replace them")
	# A manor bought pays from the next tick.
	var realm := data.resolve_realm("player_realm")
	var bought := -1
	for province: String in MapOwnership.provinces_of(data, s, realm):
		for cell: int in MapManors.manors_of_province(data, province):
			if not MapManors.is_crowns(data, s, cell):
				bought = cell
				break
		if bought >= 0:
			break
	assert_true(MapManors.set_owner(data, s, bought, MapManors.crown(s), "bought"))
	engine.advance(s)
	assert_almost_eq(s.metrics["manor_rents"], expected + MapManors.rent_of(data, s, bought), 0.001)

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
