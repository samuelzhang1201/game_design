extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## Governance (spec 2026-09-30-ledger-governors-design §2-3).

var data: DataRepository
var s: GameState

func before_each() -> void:
	data = SuiteData.repo()
	s = SuiteData.campaign(data, 42)

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

func test_a_governor_who_leaves_the_council_loses_the_flow() -> void:
	# Controller ruling (Task 1 review): a governor given a flow who no
	# longer sits on the council loses it, falling back to the seat holder,
	# same as a governor who never existed.
	var former := String(s.council["chancellor"])
	s.governors["workshop"] = former
	assert_eq(Governance.governor_of(data, s, "workshop"), former, "still on the council")
	s.council.erase("chancellor")
	assert_eq(Governance.governor_of(data, s, "workshop"), String(s.council["steward"]),
		"passed over a councillor, he loses the flow")

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
	s.skims["char_x"] = {"workshop": 12, "supply_line": 3}
	s.caught["char_x"] = [{"flow": "workshop", "day": 40, "amount": 12}]
	s.records["char_x"] = ["Caught skimming the war workshops"]
	var back := GameState.from_dict(s.to_dict())
	assert_eq(back.governors, s.governors)
	assert_eq(Governance.skimmed_on(back, "char_x", "workshop"), 12)
	assert_eq(Governance.skimmed_on(back, "char_x", "supply_line"), 3)
	assert_eq(int(back.caught["char_x"][0]["amount"]), 12)
	assert_eq(back.records["char_x"], ["Caught skimming the war workshops"])


## A save from before skims were kept per flow: his number is kept under
## "unknown" (final review I1), which no audit of a flow finds.
func test_an_old_save_keeps_a_skim_under_unknown() -> void:
	var d := s.to_dict()
	d["skims"] = {"char_x": "i12", "char_y": "i0"}
	var back := GameState.from_dict(d)
	assert_eq(back.skims, {"char_x": {"unknown": 12}})
	assert_eq(Governance.skimmers_of(back, "workshop"), [])


## A man whose skill runs past the ceiling can sulk and still run the flow
## in full: his opinion holds nothing back (the card only says so when it does).
func test_held_back_only_when_his_opinion_costs_something() -> void:
	var c: Character = s.characters[String(s.council["steward"])]
	c.skills["sk_steward"] = 20  # 850 + 12 × 20 = 1090, over the 1000 ceiling
	c.opinion = -1               # −5‰: 1085, still clamped to 1000
	var f := Governance.factors(data, s, "workshop")
	assert_eq(int(f["efficiency"]), 1000)
	assert_false(bool(f["held_back"]))
	c.opinion = -30              # −150‰: 940
	f = Governance.factors(data, s, "workshop")
	assert_eq(int(f["efficiency"]), 940)
	assert_true(bool(f["held_back"]))
