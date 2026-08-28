extends GutTest

var data: DataRepository
var sys: ActionSystem
var gen: SuggestionGenerator

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	sys = ActionSystem.new(data)
	gen = SuggestionGenerator.new(data, sys)

func test_no_concerns_when_healthy() -> void:
	var s := GameState.new_campaign(data, 42)
	assert_eq(ConcernScanner.scan(s, data).size(), 0)

func test_low_grain_flags_steward_sorted_by_severity() -> void:
	var s := GameState.new_campaign(data, 42)
	s.metrics["grain"] = 10.0     # threshold 30 -> severe
	s.metrics["treasury"] = 95.0  # threshold 100 -> mild
	var concerns := ConcernScanner.scan(s, data)
	assert_eq(concerns.size(), 2)
	assert_eq(concerns[0]["metric"], "grain")
	assert_eq(concerns[0]["seat"], "steward")
	assert_gt(concerns[0]["severity"], concerns[1]["severity"])

func test_suggestions_valid_and_bounded() -> void:
	var s := GameState.new_campaign(data, 42)
	s.metrics["grain"] = 10.0
	s.metrics["unrest"] = 55.0
	var concerns := ConcernScanner.scan(s, data)
	var sugs := gen.generate(s, concerns)
	assert_between(sugs.size(), 2, 3)
	for sug in sugs:
		assert_eq(sys.validate(sug["request"], s), "", sug["request"].action_code + " must validate")
		assert_ne(sug["tradeoff"], "")

func test_quiet_tick_still_offers_something() -> void:
	var s := GameState.new_campaign(data, 42)
	var sugs := gen.generate(s, [])
	assert_between(sugs.size(), 2, 3)
