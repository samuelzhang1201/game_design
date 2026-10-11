extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Foraging and desertion, data layer (spec 2026-10-10-foraging-and-desertion §1, §4).

const KEYS: Array[String] = [
	"forage_start_days", "forage_start_morale", "forage_start_training",
	"forage_start_days_obey", "forage_start_morale_obey", "forage_start_training_obey",
	"forage_stop_days", "forage_stop_morale", "forage_supply_per_food_unit",
	"forage_spring_permille", "forage_summer_permille", "forage_autumn_permille", "forage_winter_permille",
	"forage_share_permille", "forage_strip_k", "forage_recover_permille", "forage_bare_permille",
	"forage_word_rich_permille", "forage_word_fair_permille",
	"forage_hazard_strip_permille", "forage_hazard_strip_permille_protected",
	"forage_morale_month", "forage_training_month", "forage_training_floor", "forage_harass_permille",
	"forage_protect_cut_permille", "forage_incident_legitimacy",
	"forage_grievance_month", "forage_grievance_month_protected",
	"desert_morale", "desert_training", "desert_supply_days", "desert_permille_per_day",
	"desert_mult_fine", "desert_mult_lenient", "desert_mult_hanging",
	"desert_news_cumulative_permille",
]

## Task 8's dispatch keys and the number of %s each text carries.
const WORDS: Dictionary = {
	"forage_unlawful": 2, "forage_incident": 3, "forage_havoc": 1,
	"stripped_bare": 1, "deserting": 1, "deserting_big": 1,
	"hazard_label": 1,
}

var repo: DataRepository

func before_each() -> void:
	repo = SuiteData.repo()

func _rows(law: String, value: String) -> Array:
	var out: Array = []
	for r in repo.law_effects:
		if String(r["law_code"]) == law and String(r["value"]) == value:
			out.append(r)
	return out

func test_balance_keys_exist() -> void:
	for k in KEYS:
		assert_true(repo.balance.has(k), "army/balance.csv has " + k)
	assert_eq(repo.bal("forage_start_days"), 3.0)
	assert_eq(repo.bal("desert_mult_hanging"), 400.0)
	assert_eq(repo.bal("forage_winter_permille"), 300.0)

func test_law_is_the_thirteenth_military_law() -> void:
	assert_eq(LawSystem.codes_on(repo, "military").size(), 13)
	var d: Dictionary = LawSystem.def(repo, "desertion_penalty")
	assert_eq(d["values"], ["fine", "lenient", "hanging"])
	assert_eq(d["default"], "fine")
	assert_eq(d["kind"], "choice")
	assert_eq(d["group"], "discipline")
	assert_eq(d["scope"], "camp")

func test_effect_rows() -> void:
	assert_eq(_rows("desertion_penalty", "fine").size(), 0)
	var len_rows := _rows("desertion_penalty", "lenient")
	assert_eq(len_rows.size(), 1)
	assert_eq(String(len_rows[0]["channel"]), "morale_mark")
	assert_eq(float(len_rows[0]["amount"]), 1.0)
	var hang := _rows("desertion_penalty", "hanging")
	assert_eq(hang.size(), 3)
	var by: Dictionary = {}
	for r in hang:
		by[String(r["channel"])] = r
	assert_eq(float(by["peasant_contentment"]["amount"]), -0.3)
	assert_eq(float(by["legitimacy"]["amount"]), -0.2)
	assert_eq(float(by["morale_mark"]["amount"]), -1.0)
	for r in len_rows + hang:
		assert_eq(String(r["timing"]), "monthly")
		assert_ne(String(r["reason"]), "", "every effect has a reason")
		var want := "unit" if String(r["channel"]) == "morale_mark" else "army"
		assert_eq(String(r["share"]), want)

func test_every_conduct_word_has_its_placeholders() -> void:
	for k in WORDS:
		assert_true(repo.conduct_words.has(k), "conduct_words has " + k)
		var text := String(repo.conduct_words.get(k, ""))
		assert_eq(text.count("%s"), WORDS[k], k + " placeholders")
