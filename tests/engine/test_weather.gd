extends GutTest
## Regional weather (spec 2026-09-27-courier-core §1): stateless, hashed from
## (seed, province, spell), drawn from data/weather_odds.csv.

var repo: DataRepository


func before_each() -> void:
	repo = DataRepository.load_all("res://data")
	Weather.forget()


func _a_province() -> String:
	var codes := repo.provinces.keys()
	codes.sort()
	return String(codes[0])


## Every season and tier rolls `kind` and nothing else.
func _skies(kind: String) -> void:
	for key in repo.weather_odds:
		var w: Dictionary = {}
		for k: String in repo.weather_kinds:
			w[k] = 1 if k == kind else 0
		repo.weather_odds[key] = w


func test_the_same_seed_province_and_day_give_the_same_weather() -> void:
	var s := GameState.new_campaign(repo, 7)
	var p := _a_province()
	for day in [1, 50, 200, 333]:
		assert_eq(Weather.of(repo, s, p, day), Weather.of(repo, s, p, day))


func test_weather_holds_across_a_spell() -> void:
	repo.balance["weather_spell_days"] = 3.0
	assert_eq(Weather.spell_of(repo, 1), 0)
	assert_eq(Weather.spell_of(repo, 3), 0)
	assert_eq(Weather.spell_of(repo, 4), 1)
	var s := GameState.new_campaign(repo, 7)
	var p := _a_province()
	assert_eq(Weather.of(repo, s, p, 4), Weather.of(repo, s, p, 6), "days 4-6 are one spell")


func test_the_odds_decide() -> void:
	var s := GameState.new_campaign(repo, 7)
	_skies("blizzard")
	assert_eq(Weather.of(repo, s, _a_province(), 10), "blizzard")
	_skies("clear")
	assert_eq(Weather.of(repo, s, _a_province(), 10), "clear")


func test_no_province_is_clear() -> void:
	var s := GameState.new_campaign(repo, 7)
	assert_eq(Weather.of(repo, s, "", 10), Weather.CLEAR)
	assert_eq(Weather.of(repo, null, _a_province(), 10), Weather.CLEAR)


func test_a_seasons_frequencies_follow_its_odds() -> void:
	# Summer on the plains is 75 clear in 100. Over ~2,000 summer spells of
	# one province the share must land within 5 points of it.
	var s := GameState.new_campaign(repo, 11)
	var plains := ""
	var codes := repo.provinces.keys()
	codes.sort()
	for c: String in codes:
		if Weather.tier_of_province(repo, c) == "plains":
			plains = c
			break
	assert_ne(plains, "", "the pack has a lowland province")
	var clear := 0
	var total := 0
	for year in 67:
		for spell in 30:
			if Weather.of(repo, s, plains, 360 * year + 91 + 3 * spell) == "clear":
				clear += 1
			total += 1
	assert_almost_eq(float(clear) / float(total), 0.75, 0.05)


func test_speeds_and_words() -> void:
	assert_eq(Weather.speed_permille(repo, "rain"), 850)
	assert_eq(Weather.speed_permille(repo, "no_such"), 1000, "unknown weather does not slow anyone")
	assert_eq(Weather.describe_kind(repo, "clear"), "Clear")
	assert_eq(Weather.describe_kind(repo, "rain"), "Rain (march and couriers ×0.85)")
