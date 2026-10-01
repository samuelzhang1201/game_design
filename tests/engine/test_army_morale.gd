extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Morale follows the stores (spec 2026-09-30-ledger-supply-design §4).

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = SuiteData.repo()
	s = SuiteData.campaign(data, 42)
	RealmEconomy.forget()

func after_each() -> void:
	RealmEconomy.forget()

func test_the_mark_rises_with_the_stores() -> void:
	assert_eq(ArmySystem.morale_mark(data, 0, false), 20)
	assert_eq(ArmySystem.morale_mark(data, 500, false), 47)
	assert_eq(ArmySystem.morale_mark(data, 1000, false), 75)
	assert_eq(ArmySystem.morale_mark(data, 1000, true), 80, "a garrison stands a little taller")

func test_morale_drifts_toward_its_mark_and_stops_there() -> void:
	assert_eq(ArmySystem.drift_morale(70, 47, 6), 64)
	assert_eq(ArmySystem.drift_morale(40, 47, 6), 46)
	assert_eq(ArmySystem.drift_morale(45, 47, 6), 47)
	assert_eq(ArmySystem.drift_morale(47, 47, 6), 47)

func test_a_fed_regiment_climbs_a_starving_one_sinks() -> void:
	var codes: Array = []
	for c in s.regiments.keys():
		if String(ArmySystem.regiment(data, String(c)).get("is_naval", "0")) != "1":
			codes.append(String(c))
	codes.sort()
	var fed: String = codes[0]
	var starving: String = codes[1]
	var use := ArmySystem.supply_use(data, ArmySystem.regiment(data, fed))
	s.regiments[fed]["supplies"] = use * 3
	s.regiments[fed]["morale"] = 60
	s.regiments[starving]["supplies"] = 0
	s.regiments[starving]["morale"] = 60
	ArmySystem.settle_month(data, s)
	assert_eq(int(s.regiments[fed]["morale"]), 66, "full stores: the mark is 75, one step of 6")
	assert_eq(int(s.regiments[starving]["morale"]), 54, "empty stores: the mark is 20")

func test_the_words_name_the_stores() -> void:
	assert_eq(ArmySystem.morale_word(data, 1000), "well fed")
	assert_eq(ArmySystem.morale_word(data, 500), "on short rations")
	assert_eq(ArmySystem.morale_word(data, 0), "starving")


## Minor6 (final review): the stores' word belongs to the MORALE row, once.
func test_the_morale_row_names_the_stores() -> void:
	var codes: Array = []
	for c in s.regiments.keys():
		if String(ArmySystem.regiment(data, String(c)).get("is_naval", "0")) != "1":
			codes.append(String(c))
	codes.sort()
	var code: String = codes[0]
	s.regiments[code]["supplies"] = 0
	var tips := {}
	for st: Dictionary in MapObjects.army_card(data, code, s)["stats"]:
		tips[String(st["key"])] = String(st["tooltip"])
	assert_string_contains(tips["army_morale"], "starving")
	assert_false(tips["army_supply_line"].contains("starving"), "said once, on the morale row")
