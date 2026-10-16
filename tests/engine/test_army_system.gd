extends GutTest
const Personnel := preload("res://tests/engine/personnel_helpers.gd")
const SuiteData := preload("res://tests/suite_data.gd")
## ArmySystem (owner 2026-09-17, spec 2026-09-17-regiment-state §2-3): the
## player's regiments carry morale, supplies and training; personnel cohorts
## hold the wounded, and the
## month's end returns wounded to the ranks; each day eats its share of supplies.

var repo: DataRepository

func before_all() -> void:
	repo = SuiteData.repo()

func _mine() -> Array:
	return MapObjects.regiments_of(repo, repo.resolve_realm("player_realm"))

func _other_code() -> String:
	var mine := repo.resolve_realm("player_realm")
	var army := ArmySystem.roster(repo)
	var codes := army.keys()
	codes.sort()
	for c: String in codes:
		if String(army[c]["kingdom_code"]) != mine:
			return c
	return ""

func test_a_new_campaign_seeds_only_the_players_regiments() -> void:
	var s := SuiteData.campaign(repo, 7)
	assert_eq(s.regiments.size(), _mine().size())
	var r: Dictionary = _mine()[0]
	var entry: Dictionary = s.regiments[String(r["regiment_code"])]
	assert_eq(int(entry["morale"]), 70)
	assert_eq(int(entry["training"]), 10)
	assert_eq(ArmySystem.wounded_count(repo, s, String(r["regiment_code"])), 0)
	# heads x 100 / 1000 a month (scaled by the cell's height tier), times
	# army_start_supply_days (20) of the 30 days of a month, in a 20-day load
	@warning_ignore("integer_division")
	assert_eq(int(entry["supplies"]), (ArmySystem.supply_use(repo, r, s) * 20 + 29) / 30)
	assert_eq(int(entry["carry_days"]), 20)
	assert_false(s.regiments.has(_other_code()))

## A fresh regiment reads the days it was given: 20 in hand of its 20-day load,
## never 19 for the whole-unit floor.
func test_a_fresh_regiment_has_the_days_it_was_given() -> void:
	var s := SuiteData.campaign(repo, 7)
	var n := 0
	for r: Dictionary in _mine():
		var code := String(r["regiment_code"])
		var use := ArmySystem.supply_use(repo, r, s)
		if String(r.get("is_naval", "0")) == "1" or use < 30:
			continue
		n += 1
		assert_eq(ArmySystem.days_in_hand(int(s.regiments[code]["supplies"]), use), 20, code)
	assert_gt(n, 0, "some land regiment of the realm")

func test_wound_recovery_is_a_share_with_a_floor_of_one() -> void:
	assert_eq(ArmySystem.wound_recovery(repo, 0), 0)
	assert_eq(ArmySystem.wound_recovery(repo, 3), 1, "200 per mille of 3 is 0, floored up to 1")
	assert_eq(ArmySystem.wound_recovery(repo, 250), 50)

func test_the_month_returns_wounded_and_the_days_eat_the_supplies() -> void:
	var s := SuiteData.campaign(repo, 7)
	var r: Dictionary = _mine()[0]
	var code := String(r["regiment_code"])
	var use := ArmySystem.supply_use(repo, r, s)
	assert_false(Personnel.move(repo, s, code, "fit", "wounded", 250).has("error"))
	s.regiments[code]["supplies"] = use + 5
	# Morale follows the stores in hand as the month turns (spec
	# 2026-09-30-ledger-supply-design §4); the month itself is eaten a day at
	# a time (owner 2026-09-30: 军事单位的补给要每天都在以一定速率减少).
	var naval := String(r.get("is_naval", "0")) == "1"
	var mark1 := ArmySystem.morale_mark(repo, ArmySystem.supply_score(repo, use + 5, use), false)
	var morale1 := 70 if naval else ArmySystem.drift_morale(70, mark1, int(repo.bal("army_morale_drift_per_month")))
	var mark2 := ArmySystem.morale_mark(repo, ArmySystem.supply_score(repo, 5, use), false)
	var expected := morale1 if naval else ArmySystem.drift_morale(morale1, mark2, int(repo.bal("army_morale_drift_per_month")))
	ArmySystem.settle_month(repo, s)
	assert_eq(ArmySystem.wounded_count(repo, s, code), 200)
	assert_eq(int(s.regiments[code]["supplies"]), use + 5, "the month's end spends nothing itself")
	var last := use + 5
	for d in range(1, Calendar.DAYS_PER_TICK + 1):
		s.day = d
		ArmySystem.eat_day(repo, s)
		var now := int(s.regiments[code]["supplies"])
		assert_true(now <= last, "day %d eats, never adds" % d)
		last = now
	assert_eq(int(s.regiments[code]["supplies"]), 5, "the thirty days eat exactly a month")
	s.tick += 1
	ArmySystem.settle_month(repo, s)
	for d in range(1, Calendar.DAYS_PER_TICK + 1):
		s.day = d
		ArmySystem.eat_day(repo, s)
	assert_eq(int(s.regiments[code]["supplies"]), 0, "supplies stop at zero")
	assert_eq(int(s.regiments[code]["morale"]), expected, "morale follows the stores (spec 2026-09-30-ledger-supply-design §4)")


func test_a_day_bites_its_share_and_the_month_sums_exactly() -> void:
	for use: int in [0, 1, 29, 30, 31, 1000, 12345]:
		var total := 0
		for d in range(1, Calendar.DAYS_PER_TICK + 1):
			var b := ArmySystem.day_bite(use, d)
			assert_true(b >= 0)
			total += b
		assert_eq(total, use, "a month of %d" % use)
	assert_eq(ArmySystem.day_bite(300, 1), 10, "a steady rate: 300 a month is 10 a day")


## The map's yellow bar is the stores against a full train, so it falls every day.
func test_the_yellow_bar_falls_day_by_day() -> void:
	var s := SuiteData.campaign(repo, 7)
	# the first land unit that eats at least a unit every day
	var r: Dictionary = {}
	for u: Dictionary in _mine():
		if String(u.get("is_naval", "0")) != "1" and ArmySystem.supply_use(repo, u) >= Calendar.DAYS_PER_TICK:
			r = u
			break
	assert_false(r.is_empty(), "the realm has a unit that eats every day")
	var code := String(r["regiment_code"])
	var use := ArmySystem.supply_use(repo, r, s)
	# the carried days in whole units, rounded UP so the bar reads full
	@warning_ignore("integer_division")
	s.regiments[code]["supplies"] = (use * ArmySystem.carry_of(repo, s.regiments[code]) + Calendar.DAYS_PER_TICK - 1) / Calendar.DAYS_PER_TICK
	var bar := ArmySystem.bars_of(repo, s, code).y
	assert_eq(bar, 1000, "a full load")
	s.day = 1
	ArmySystem.eat_day(repo, s)
	assert_lt(ArmySystem.bars_of(repo, s, code).y, bar, "one day later it has fallen")


func test_supply_use_is_the_base_scaled_by_the_cells_height_tier() -> void:
	var r: Dictionary = _mine()[0]
	var heads := int(MapObjects.regiment_size(repo, r))
	@warning_ignore("integer_division")  # the formula's own whole per-mille
	assert_eq(ArmySystem.supply_use(repo, r),
		heads * 100 * int(ArmySystem.height_tier(repo, r)["supply_permille"]) / 1_000_000)

func test_wounded_never_exceed_the_headcount() -> void:
	var s := SuiteData.campaign(repo, 7)
	var r: Dictionary = _mine()[0]
	var code := String(r["regiment_code"])
	var heads := int(MapObjects.regiment_size(repo, r))
	var before := s.military_cohorts.duplicate(true)
	assert_true(Personnel.move(repo, s, code, "fit", "wounded", heads * 10).has("error"))
	assert_eq(s.military_cohorts, before, "an impossible loss is rejected atomically")
	assert_false(Personnel.move(repo, s, code, "fit", "wounded", heads).has("error"))
	ArmySystem.settle_month(repo, s)
	assert_lte(ArmySystem.wounded_count(repo, s, code), heads)
	assert_gte(ArmySystem.wounded_count(repo, s, code), 0)

func test_training_is_capped_at_100() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_mine()[0]["regiment_code"])
	s.regiments[code]["training"] = 100
	var saved: float = repo.balance["army_training_per_month"]
	repo.balance["army_training_per_month"] = 5.0
	ArmySystem.settle_month(repo, s)
	repo.balance["army_training_per_month"] = saved
	assert_eq(int(s.regiments[code]["training"]), 100)

func test_state_of_reads_without_writing() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_mine()[0]["regiment_code"])
	s.regiments.erase(code)
	var view := ArmySystem.state_of(repo, s, code)
	assert_eq(int(view["training"]), 10, "the starting state stands in")
	assert_false(s.regiments.has(code), "a read never seeds")
	assert_true(ArmySystem.state_of(repo, s, _other_code()).is_empty())
	ArmySystem.ensure(repo, s)
	assert_true(s.regiments.has(code), "ensure fills an old save in")

func test_the_state_survives_a_save() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_mine()[0]["regiment_code"])
	assert_false(Personnel.move(repo, s, code, "fit", "wounded", 12).has("error"))
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(ArmySystem.wounded_count(repo, back, code), 12)
	assert_eq(int(back.regiments[code]["morale"]), 70)

func test_the_tick_settles_the_regiments() -> void:
	var s := SuiteData.campaign(repo, 7)
	var code := String(_mine()[0]["regiment_code"])
	assert_false(Personnel.move(repo, s, code, "fit", "wounded", 250).has("error"))
	TickEngine.new(repo).advance(s)
	assert_eq(ArmySystem.wounded_count(repo, s, code), 200)
