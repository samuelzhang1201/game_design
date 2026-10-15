extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
const Roster := preload("res://scripts/engine/military_roster.gd")

func test_commander_is_in_noble_total() -> void:
	assert_eq(Roster.composition(600, 50, 100), {"commoners": 570, "noble_troops": 29, "commander": 1})
	assert_eq(Roster.composition(600, 0, 100), {"commoners": 599, "noble_troops": 0, "commander": 1})
	assert_eq(Roster.composition(600, 100, 100), {"commoners": 540, "noble_troops": 59, "commander": 1})

func test_integer_composition_respects_supplied_cap() -> void:
	assert_eq(Roster.composition(19, 100, 100), {"commoners": 18, "noble_troops": 0, "commander": 1})
	assert_eq(Roster.composition(5, 200, 200), {"commoners": 4, "noble_troops": 0, "commander": 1})
	assert_true(Roster.composition(9, 0, 100).has("error"))
	assert_true(Roster.composition(600, 101, 100).has("error"))
	assert_true(Roster.composition(10, 0, 50).has("error"))

func test_invalid_composition_inputs_are_refused() -> void:
	for args: Array in [[0, 0, 100], [-1, 0, 100], [600, -1, 100], [600, 0, -1], [600, 0, 1001], [600, 0, 0]]:
		assert_true(Roster.composition(args[0], args[1], args[2]).has("error"), str(args))

func test_capacity_counts_crews_without_changing_equipment() -> void:
	var repo := SuiteData.repo()
	var units := repo.world_table("military", "unit_types")
	units["fleet"]["crew"] = "100"
	units["artillery"]["crew"] = "8"
	units["infantry"]["crew"] = "1"
	var equipment := {"fleet": 1, "artillery": 2, "infantry": 30, "regiment_code": "test", "wounded": 3}
	var before := equipment.duplicate(true)
	assert_eq(Roster.personnel_capacity(repo, {"fleet": 1}), 100)
	assert_eq(Roster.personnel_capacity(repo, {"artillery": 2}), 16)
	assert_eq(Roster.personnel_capacity(repo, equipment), 146)
	assert_eq(Roster.personnel_capacity(repo, equipment), 146)
	assert_eq(equipment, before)
	assert_eq(Roster.personnel_capacity(repo, {}), 0)
	assert_eq(Roster.composition(100, 50, 100), {"commoners": 95, "noble_troops": 4, "commander": 1})
	assert_eq(Roster.composition(16, 0, 100), {"commoners": 15, "noble_troops": 0, "commander": 1})
