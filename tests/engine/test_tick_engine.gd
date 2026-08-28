extends GutTest

var TickEngineClass = preload("res://scripts/engine/tick_engine.gd")
var TickReportClass = preload("res://scripts/engine/tick_report.gd")

var data
var engine

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	engine = TickEngine.new(data)

func test_advance_increments_and_reports() -> void:
	var s = GameState.new_campaign(data, 42)
	var r = engine.advance(s)
	assert_eq(r.tick, 1)
	assert_eq(s.tick, 1)
	assert_eq(r.season, "spring")
	assert_gt(r.metric_deltas.size(), 0)
	for d in r.metric_deltas:
		assert_ne(d["reason"], "")

func test_tax_income_formula() -> void:
	var s = GameState.new_campaign(data, 42)
	engine.advance(s)
	# income = tax_rate(5) * admin_capacity * 0.8 + tariff_rate(3) * 3.0 + road bonus(0)
	var chancellor = s.characters[s.council["chancellor"]]
	var cap = data.bal("admin_base") + chancellor.skills["sk_admin"] * 0.10
	var expected = 5.0 * cap * data.bal("tax_income_factor") + 3.0 * data.bal("tariff_income_factor")
	assert_almost_eq(s.metrics["tax_income"], expected, 0.001)

func test_grain_seasonal() -> void:
	var s = GameState.new_campaign(data, 42)
	s.tick = 11  # advance() makes it 12 -> autumn
	var g0 = s.metrics["grain"]
	engine.advance(s)
	assert_gt(s.metrics["grain"], g0)  # harvest
	s.tick = 19  # -> 20, winter
	var g1 = s.metrics["grain"]
	engine.advance(s)
	assert_lt(s.metrics["grain"], g1)

func test_outcomes_drain_into_next_report() -> void:
	var s = GameState.new_campaign(data, 42)
	engine.advance(s)
	engine.actions.execute(ActionRequest.make("TAX_RATE_ADJUST", {"delta": 1}), s)
	var r = engine.advance(s)
	assert_eq(r.outcomes.size(), 1)
	assert_eq(s.recent_outcomes.size(), 0)
	assert_eq(r.outcomes[0]["action_code"], "TAX_RATE_ADJUST")
