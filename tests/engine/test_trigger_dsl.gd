extends GutTest

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)
	s.tick = 3

func test_always_and_metrics() -> void:
	assert_true(TriggerDsl.evaluate("always", s, data))
	s.metrics["grain"] = 10.0
	assert_true(TriggerDsl.evaluate("grain<30", s, data))
	assert_false(TriggerDsl.evaluate("grain>30", s, data))
	assert_true(TriggerDsl.evaluate("grain<30&unrest>-1", s, data))
	assert_false(TriggerDsl.evaluate("grain<30&treasury<1", s, data))

func test_season_year_seat_trait() -> void:
	assert_true(TriggerDsl.evaluate("season=spring", s, data))
	assert_false(TriggerDsl.evaluate("season=winter", s, data))
	assert_false(TriggerDsl.evaluate("year>=2", s, data))
	s.tick = 30
	assert_true(TriggerDsl.evaluate("year>=2", s, data))
	assert_true(TriggerDsl.evaluate("seat_filled=marshal", s, data))
	assert_false(TriggerDsl.evaluate("seat_filled=admiral", s, data))
	assert_true(TriggerDsl.evaluate("trait_at_court=paranoid", s, data))   # Quill
	# The story rework (game_start.md) makes the Chancellor venal — greedy,
	# cunning, devious — so venal IS at court now; maimed is held by no one.
	assert_true(TriggerDsl.evaluate("trait_at_court=venal", s, data))
	assert_false(TriggerDsl.evaluate("trait_at_court=maimed", s, data))

func test_action_since_and_flags() -> void:
	s.event_state["last_action_tick"]["TARIFF_ADJUST"] = 3
	assert_true(TriggerDsl.evaluate("action_since=TARIFF_ADJUST:24", s, data))
	s.tick = 40
	assert_false(TriggerDsl.evaluate("action_since=TARIFF_ADJUST:24", s, data))
	assert_false(TriggerDsl.evaluate("flag=black_market", s, data))
	s.event_state["flags"].append("black_market")
	assert_true(TriggerDsl.evaluate("flag=black_market", s, data))

func test_host_hungry_reads_the_regiments() -> void:
	for c in s.regiments.keys():
		s.regiments[c]["supplies"] = 0
	assert_true(TriggerDsl.evaluate("host_hungry", s, data))
	for c in s.regiments.keys():
		s.regiments[c]["supplies"] = 1000000
	assert_false(TriggerDsl.evaluate("host_hungry", s, data))
