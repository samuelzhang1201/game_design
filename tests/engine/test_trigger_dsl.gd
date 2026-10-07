extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = SuiteData.repo()
	s = SuiteData.campaign(data, 42)
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
		var use := ArmySystem.supply_use(data, ArmySystem.regiment(data, String(c)), s)
		s.regiments[c]["supplies"] = ArmySystem.max_units(data, use)
	assert_false(TriggerDsl.evaluate("host_hungry", s, data))

## Final review 8: hungry is under army_supply_low_days days in hand (spec
## 2026-10-07-army-supply-lines §3.7), the same line the morale loss starts at.
func test_host_hungry_is_under_the_low_days() -> void:
	var low := int(data.bal("army_supply_low_days"))
	var codes: Array = s.regiments.keys()
	codes.sort()
	var land := ""
	for c in codes:
		var reg := ArmySystem.regiment(data, String(c))
		s.regiments[c]["supplies"] = ArmySystem.max_units(data, ArmySystem.supply_use(data, reg, s))
		if land == "" and String(reg.get("is_naval", "0")) != "1":
			land = String(c)
	var use := ArmySystem.supply_use(data, ArmySystem.regiment(data, land), s)
	var at_low := 0
	while ArmySystem.days_in_hand(at_low, use) < low:
		at_low += 1
	s.regiments[land]["supplies"] = at_low
	assert_false(TriggerDsl.evaluate("host_hungry", s, data), "%d days is not hungry" % low)
	s.regiments[land]["supplies"] = at_low - 1
	assert_true(TriggerDsl.evaluate("host_hungry", s, data), "under %d days is" % low)
