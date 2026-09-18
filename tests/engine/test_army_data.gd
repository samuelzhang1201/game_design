extends GutTest
## The regiment tables (owner 2026-09-17, spec 2026-09-17-regiment-state):
## biome -> terrain, terrain x arm modifiers, arm x arm matchups and the
## training grades load, and cover what the pack needs.

var repo: DataRepository

func before_all() -> void:
	repo = DataRepository.load_all("res://data")
	assert_not_null(repo, DataRepository.last_error)

func test_every_biome_of_the_pack_names_a_terrain() -> void:
	for id: int in repo.cells.values().map(func(c: Dictionary) -> int: return int(c["biome_id"])):
		assert_true(repo.army_terrain_biomes.has(id), "biome %d has a terrain" % id)

func test_terrain_rows_parse_as_permille() -> void:
	var row: Dictionary = repo.army_terrain["mountains|cavalry"]
	assert_eq(int(row["defend"]), 700)
	assert_eq(int(row["attack"]), 650)
	assert_eq(int((repo.army_terrain["fortified|infantry"] as Dictionary)["defend"]), 1300)

func test_every_arm_has_matchups() -> void:
	for arm: String in repo.world_table("military", "unit_types"):
		assert_true(repo.army_matchups.has(arm), "%s has matchups" % arm)
		assert_gt((repo.army_matchups[arm] as Array).size(), 0)
	var cav: Array = repo.army_matchups["cavalry"]
	var vs_archers: Dictionary = cav.filter(func(m: Dictionary) -> bool: return m["vs"] == "archers")[0]
	assert_eq(int(vs_archers["attack"]), 1300)

func test_training_grades_run_from_elite_to_militia() -> void:
	var labels: Array = repo.army_training_grades.map(func(g: Dictionary) -> String: return String(g["label"]))
	assert_eq(labels, ["Elite", "Well drilled", "Recruits", "Militia"])
	assert_eq(int(repo.army_training_grades[0]["above"]), 80)

func test_balance_and_icons_are_present() -> void:
	for key in ["army_start_morale", "army_start_training", "army_start_supply_months",
			"army_supply_per_head_permille", "army_wound_recovery_permille", "army_training_per_month",
			"army_float_permille", "army_training_base_permille", "army_training_step_permille",
			"army_morale_base_permille", "army_morale_step_permille", "army_strong_ratio_permille",
			"army_weak_ratio_permille"]:
		assert_true(repo.balance.has(key), key)
	assert_eq(int(repo.bal("army_start_training")), 10)
	for key in ["army_terrain", "army_morale", "army_wounded", "army_supply", "army_training", "army_strength"]:
		assert_true(repo.resource_icons.has(key), key)
