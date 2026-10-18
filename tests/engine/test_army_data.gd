extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The regiment tables (owner 2026-09-17, spec 2026-09-17-regiment-state):
## biome -> terrain, terrain x arm modifiers, arm x arm matchups and the
## training grades load, and cover what the pack needs.

var repo: DataRepository

func before_all() -> void:
	repo = SuiteData.repo()
	assert_not_null(repo, DataRepository.last_error)

func test_every_biome_of_the_pack_names_a_terrain() -> void:
	var biomes: Dictionary = {}
	for cell: Dictionary in repo.cells.values():
		biomes[int(cell["biome_id"])] = true
	for id: int in biomes:
		assert_true(repo.army_terrain_biomes.has(id), "biome %d has a terrain" % id)


func test_every_arm_has_matchups() -> void:
	for arm: String in repo.world_table("military", "unit_types"):
		assert_true(repo.army_matchups.has(arm), "%s has matchups" % arm)
		assert_gt((repo.army_matchups[arm] as Array).size(), 0)
		for m: Dictionary in repo.army_matchups[arm]:
			assert_gt(int(m["attack"]), 0, "%s vs %s attacks at some strength" % [arm, m["vs"]])

func test_training_grades_run_from_elite_to_militia() -> void:
	# first match wins, so the thresholds run highest first and the last
	# catches every value from 0 up
	var grades := repo.army_training_grades
	assert_gt(grades.size(), 1)
	for i in range(1, grades.size()):
		assert_lt(int(grades[i]["above"]), int(grades[i - 1]["above"]), String(grades[i]["label"]))
	assert_lt(int(grades[-1]["above"]), 0, "the lowest grade takes a fresh regiment")
	assert_eq(ArmySystem.training_grade(repo, 0), String(grades[-1]["label"]))
	assert_eq(ArmySystem.training_grade(repo, 100), String(grades[0]["label"]))

func test_balance_and_icons_are_present() -> void:
	for key in ["army_start_morale", "army_start_training", "army_start_supply_days",
			"army_supply_per_head_permille", "army_wound_recovery_permille", "army_training_per_month",
			"army_float_permille", "army_training_base_permille", "army_training_step_permille",
			"army_morale_base_permille", "army_morale_step_permille", "army_strong_ratio_permille",
			"army_weak_ratio_permille"]:
		assert_true(repo.balance.has(key), key)
	for key in ["army_terrain", "army_morale", "army_wounded", "army_supply", "army_training", "army_strength"]:
		assert_true(repo.resource_icons.has(key), key)
