extends GutTest
## Governance (spec 2026-09-30-ledger-governors-design §2-3).

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = DataRepository.load_all("res://data")
	s = GameState.new_campaign(data, 42)

func _steward() -> Character:
	return s.characters[String(s.council["steward"])]

func _plain(c: Character, skill: String, value: int) -> void:
	c.skills[skill] = value
	c.opinion = 50
	c.traits = []
	c.attributes["integrity"] = 50

func test_the_seat_holder_governs_by_default() -> void:
	assert_eq(Governance.governor_of(data, s, "workshop"), String(s.council["steward"]))
	assert_eq(Governance.governor_of(data, s, "supply_line"), String(s.council["marshal"]))

func test_a_gone_governor_falls_back_to_the_seat() -> void:
	s.governors["workshop"] = "char_nobody"
	assert_eq(Governance.governor_of(data, s, "workshop"), String(s.council["steward"]))

func test_skill_sets_the_ceiling() -> void:
	_plain(_steward(), "sk_steward", 8)
	assert_eq(int(Governance.factors(data, s, "workshop")["efficiency"]), 850)
	_steward().skills["sk_steward"] = 12
	assert_eq(int(Governance.factors(data, s, "workshop")["efficiency"]), 930)
	_steward().skills["sk_steward"] = 20
	assert_eq(int(Governance.factors(data, s, "workshop")["efficiency"]), 1000, "capped")
	_steward().skills["sk_steward"] = 0
	assert_eq(int(Governance.factors(data, s, "workshop")["efficiency"]), 690)

func test_a_sour_governor_gives_less() -> void:
	_plain(_steward(), "sk_steward", 12)
	_steward().opinion = -20
	var f := Governance.factors(data, s, "workshop")
	assert_eq(int(f["efficiency"]), 830, "930 less 20 × 5")
	assert_eq(f["reasons"].size(), 2, "the skill and the opinion each give their reason")

func test_the_venal_skim_the_low_skim_less_the_honest_never() -> void:
	var c := _steward()
	_plain(c, "sk_steward", 8)
	assert_eq(Governance.skim_of(data, c), 0)
	c.traits = ["venal"]
	assert_eq(Governance.skim_of(data, c), 200)
	c.traits = []
	c.attributes["integrity"] = 20
	assert_eq(Governance.skim_of(data, c), 100)
	c.traits = ["honest"]
	assert_eq(Governance.skim_of(data, c), 0, "honest never skims, whatever his integrity")

func test_an_empty_seat_runs_at_the_floor() -> void:
	s.council.erase("steward")
	var f := Governance.factors(data, s, "workshop")
	assert_eq(String(f["governor"]), "")
	assert_eq(int(f["efficiency"]), 600)
	assert_eq(int(f["skim"]), 0)

func test_the_new_state_survives_a_save() -> void:
	s.governors["workshop"] = "char_x"
	s.skims["char_x"] = 12
	s.caught["char_x"] = [{"flow": "workshop", "day": 40, "amount": 12}]
	s.records["char_x"] = ["Caught skimming the war workshops"]
	var back := GameState.from_dict(s.to_dict())
	assert_eq(back.governors, s.governors)
	assert_eq(int(back.skims["char_x"]), 12)
	assert_eq(int(back.caught["char_x"][0]["amount"]), 12)
	assert_eq(back.records["char_x"], ["Caught skimming the war workshops"])
