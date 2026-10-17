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
	s.event_state["last_action_tick"]["LAW_tariff_rate"] = 3
	assert_true(TriggerDsl.evaluate("action_since=LAW_tariff_rate:24", s, data))
	s.tick = 40
	assert_false(TriggerDsl.evaluate("action_since=LAW_tariff_rate:24", s, data))
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

func _give_unique_trait(person_id: String, trait_code: String) -> void:
	assert_true(data.traits.has(trait_code), "fixture uses an authored trait")
	assert_true(s.characters.has(person_id), "fixture uses a campaign person")
	for person: Character in s.characters.values(): person.traits.erase(trait_code)
	s.characters[person_id].traits.append(trait_code)

func test_trait_at_court_excludes_unappointed_people_even_of_the_royal_family() -> void:
	for person_id: String in ["char_king_osric", "char_captain_hale", "char_princess"]:
		_give_unique_trait(person_id, "maimed")
		assert_false(TriggerDsl.evaluate("trait_at_court=maimed", s, data), person_id + " is not at court merely by existing")
		assert_true(TriggerDsl.evaluate("trait_of=" + person_id + ":maimed", s, data), "explicit person queries retain their meaning")

func test_trait_at_court_tracks_current_appointment_not_stale_character_seat() -> void:
	var minister := String(s.council["marshal"])
	_give_unique_trait(minister, "maimed")
	assert_true(TriggerDsl.evaluate("trait_at_court=maimed", s, data))
	s.council.erase("marshal")
	assert_eq(s.characters[minister].seat, "marshal", "old character seat deliberately remains")
	assert_false(TriggerDsl.evaluate("trait_at_court=maimed", s, data), "dismissal removes presence immediately")
	_give_unique_trait("char_envoy_petra", "maimed")
	s.council["marshal"] = "char_envoy_petra"
	assert_true(TriggerDsl.evaluate("trait_at_court=maimed", s, data), "an appointed foreign minister is at court")

func test_trait_at_court_includes_king_and_tolerates_missing_records() -> void:
	_give_unique_trait("you", "maimed")
	assert_true(TriggerDsl.evaluate("trait_at_court=maimed", s, data))
	# Duplicate membership and dangling references can occur in old saves.
	s.council["marshal"] = "you"
	s.council["chancellor"] = "you"
	s.council["spymaster"] = "absent_person"
	assert_true(TriggerDsl.evaluate("trait_at_court=maimed", s, data))
	s.characters.erase("you")
	assert_false(TriggerDsl.evaluate("trait_at_court=maimed", s, data))
