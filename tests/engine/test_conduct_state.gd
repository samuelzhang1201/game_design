extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The saved state of foraging and desertion (spec 2026-10-10-foraging-and-
## desertion §2): three maps on GameState and a `deserted` term in fit_heads.

var repo: DataRepository
var s: GameState

func before_each() -> void:
	repo = SuiteData.repo()
	s = SuiteData.campaign(repo, 42)

func test_fit_heads_takes_the_deserted() -> void:
	assert_eq(ArmySystem.fit_heads(1000, {"wounded": 100, "dead": 50, "deserted": 30}), 820)
	assert_eq(ArmySystem.fit_heads(1000, {"wounded": 100, "dead": 50}), 850, "an old state: none deserted")
	assert_eq(ArmySystem.fit_heads(1000, {"wounded": 700, "dead": 200, "deserted": 600}), 0, "never below nothing")

func test_new_maps_round_trip() -> void:
	var prov: String = String(repo.provinces.keys()[0])
	var realm := repo.resolve_realm("player_realm")
	var code: String = String(s.regiments.keys()[0])
	s.forage_stripped[prov] = 250
	s.grievance[realm] = 7
	s.conduct_marks["mark_a"] = 11
	s.regiments[code]["forage"] = "law"
	s.regiments[code]["forage_days"] = 4
	SuiteData.set_losses(s, code, {"deserted": 12})
	s.regiments[code]["desert_rem"] = 3
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))
	assert_eq(back.forage_stripped, {prov: 250})
	assert_eq(back.grievance, {realm: 7})
	assert_eq(back.conduct_marks, {"mark_a": 11})
	assert_eq(back.regiments[code]["forage"], "law")
	assert_eq(back.regiments[code]["forage_days"], 4)
	assert_eq(back.regiments[code]["deserted"], 12)
	assert_eq(back.regiments[code]["desert_rem"], 3)
	assert_eq(typeof(back.forage_stripped[prov]), TYPE_INT)

func test_old_save_loads_empty() -> void:
	var d := s.to_dict()
	d.erase("forage_stripped")
	d.erase("grievance")
	d.erase("conduct_marks")
	var back := GameState.from_dict(JSON.parse_string(JSON.stringify(d)))
	assert_true(back.forage_stripped.is_empty())
	assert_true(back.grievance.is_empty())
	assert_true(back.conduct_marks.is_empty())
	assert_eq(back.regiments.keys(), s.regiments.keys())
