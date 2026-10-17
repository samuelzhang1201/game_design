extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")

func _subject() -> GDScript:
	var path := "res://scripts/engine/military_roster.gd"
	var script: GDScript = load(path) if ResourceLoader.exists(path) else null
	assert_not_null(script, "the personnel ledger exists")
	return script

func test_commander_is_in_noble_total() -> void:
	var subject := _subject()
	if subject == null:
		return
	assert_eq(subject.composition(600, 50, 100), {"commoners": 570, "noble_troops": 29, "commander": 1})
	assert_eq(subject.composition(600, 0, 100), {"commoners": 599, "noble_troops": 0, "commander": 1})
	assert_true(subject.composition(9, 0, 100).has("error"))
	assert_true(subject.composition(600, 101, 100).has("error"))

func test_equipment_capacity_counts_crew_without_changing_equipment() -> void:
	var subject := _subject()
	if subject == null:
		return
	var repo := SuiteData.repo()
	var types := repo.world_table("military", "unit_types")
	types["test_ship"] = {"crew": "100"}
	types["test_gun"] = {"crew": "8"}
	var ship := {"test_ship": 1}
	var guns := {"test_gun": 2}
	assert_eq(subject.personnel_capacity(repo, ship), 100)
	assert_eq(subject.personnel_capacity(repo, guns), 16)
	assert_eq(ship, {"test_ship": 1})
	assert_eq(guns, {"test_gun": 2})
	assert_eq(subject.composition(100, 50, 100), {"commoners": 95, "noble_troops": 4, "commander": 1})
	assert_eq(subject.composition(16, 0, 100), {"commoners": 15, "noble_troops": 0, "commander": 1})
