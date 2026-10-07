extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Days in hand, the carried load and hunger (spec 2026-10-07-army-supply-lines §3.6–3.7).

var repo: DataRepository
var s: GameState

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)

func _land() -> String:
	var codes: Array = s.regiments.keys()
	codes.sort()
	for c in codes:
		if String(ArmySystem.regiment(repo, String(c)).get("is_naval", "0")) != "1":
			return String(c)
	return ""

func test_days_in_hand_is_supplies_over_a_thirtieth_of_the_month() -> void:
	assert_eq(ArmySystem.days_in_hand(300, 300), 30)
	assert_eq(ArmySystem.days_in_hand(149, 300), 14)   # 149*30/300 = 14.9 -> 14
	assert_eq(ArmySystem.days_in_hand(0, 300), 0)
	assert_eq(ArmySystem.max_units(repo, 300), 300)    # 30 days of 300 a month

func test_the_supply_score_is_full_from_the_low_mark_up() -> void:
	# use 300 a month = 10 a day; low mark 5 days = 50 units
	assert_eq(ArmySystem.supply_score(repo, 50, 300), 1000)
	assert_eq(ArmySystem.supply_score(repo, 300, 300), 1000)
	assert_eq(ArmySystem.supply_score(repo, 25, 300), 500)
	assert_eq(ArmySystem.supply_score(repo, 0, 300), 0)
	assert_eq(ArmySystem.supply_score(repo, 10, 0), 1000, "a banner that eats nothing never runs short")

func test_the_stores_bar_reads_days_against_the_carried_load() -> void:
	# 20 days carried; 150 units of 300 a month = 15 days -> 750
	assert_eq(ArmySystem.stores_permille(repo, 150, 300, 20), 750)
	assert_eq(ArmySystem.stores_permille(repo, 300, 300, 20), 1000, "capped")

func test_a_heavier_load_marches_slower() -> void:
	assert_eq(ArmySystem.load_permille(repo, 10), 1000)
	assert_eq(ArmySystem.load_permille(repo, 30), 850)
	var code := _land()
	s.regiments[code]["carry_days"] = 10
	var light := ArmySystem.day_step_m(repo, s, code)
	s.regiments[code]["carry_days"] = 30
	var heavy := ArmySystem.day_step_m(repo, s, code)
	assert_eq(heavy, light * 850 / 1000)

func test_a_new_regiment_starts_with_twenty_days_and_the_default_load() -> void:
	var code := _land()
	var reg := ArmySystem.regiment(repo, code)
	var st := ArmySystem.starting_state(repo, reg)
	var use := ArmySystem.supply_use(repo, reg)
	@warning_ignore("integer_division")  # rounded UP: it reads the 20 days it was given
	assert_eq(int(st["supplies"]), (use * 20 + 29) / 30)
	assert_eq(int(st["carry_days"]), 20)

func test_an_old_entry_gets_a_load_and_is_clamped_to_thirty_days() -> void:
	var code := _land()
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code), s)
	s.regiments[code].erase("carry_days")
	s.regiments[code]["supplies"] = use * 4      # four months, the old refill
	ArmySystem.ensure(repo, s)
	assert_eq(int(s.regiments[code]["carry_days"]), 20)
	assert_eq(int(s.regiments[code]["supplies"]), ArmySystem.max_units(repo, use))

func test_hunger_costs_morale_every_day_under_five_days() -> void:
	var code := _land()
	var use := ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code), s)
	s.regiments[code]["morale"] = 60
	s.regiments[code]["supplies"] = use * 4 / 30          # 4 days: hungry
	ArmySystem.hunger_day(repo, s)
	assert_eq(int(s.regiments[code]["morale"]), 59)
	s.regiments[code]["supplies"] = 0                     # starving
	ArmySystem.hunger_day(repo, s)
	assert_eq(int(s.regiments[code]["morale"]), 56)
	s.regiments[code]["supplies"] = use * 6 / 30          # fed: no daily loss
	ArmySystem.hunger_day(repo, s)
	assert_eq(int(s.regiments[code]["morale"]), 56)

## Final review 13: a regiment that eats nothing (no one under arms, or a
## use of 0) never starves, whatever it carries.
func test_a_regiment_that_eats_nothing_never_starves() -> void:
	var code := _land()
	repo.balance["army_supply_per_head_permille"] = 0
	assert_eq(ArmySystem.supply_use(repo, ArmySystem.regiment(repo, code), s), 0)
	s.regiments[code]["morale"] = 60
	s.regiments[code]["supplies"] = 0
	ArmySystem.hunger_day(repo, s)
	assert_eq(int(s.regiments[code]["morale"]), 60)

## Final review 11: the old save's migration is idempotent — a second ensure
## (the load's, then the month's) changes nothing.
func test_ensure_twice_is_ensure_once() -> void:
	var code := _land()
	s.regiments[code].erase("carry_days")
	s.regiments[code]["supplies"] = 1000000
	ArmySystem.ensure(repo, s)
	var once: Dictionary = s.regiments.duplicate(true)
	ArmySystem.ensure(repo, s)
	assert_eq(s.regiments, once)
