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
	s.tick = 12  # advance() makes it 13 -> autumn (1-based season blocks)
	var g0: float = s.metrics["grain"]
	engine.advance(s)
	assert_gt(s.metrics["grain"], g0)  # harvest
	s.tick = 19  # -> 20, winter
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
