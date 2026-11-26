extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The axemen (spec 2026-11-18-axemen-arm-design): shock foot that break shield walls and gates and
## fold under horse. Hand sums from the spec's first-draft rows.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_axe_base_is_its_matchup_mean() -> void:
	# ((1300+1000)/2 + (1100+900)/2 + (900+700)/2 + (1200+900)/2 + (1000+1000)/2 + (1100+900)/2
	# + (1300+1100)/2) / 7
	# = (1150 + 1000 + 800 + 1050 + 1000 + 1000 + 1200) / 7 = 7200 / 7 = 1028 (whole; the last term is its
	# militia row, spec 2026-11-26-militia-arm-design)
	assert_eq(ArmySystem._arm_base(repo, "", "axemen", 0), 1028)


func test_infantry_base_counts_its_axe_row() -> void:
	# (1000 + 950 + 1250 + 1000 + (1000+800)/2 + (900+900)/2 + (1200+1100)/2) / 7 = 7150 / 7 = 1021 (whole)
	# (the last terms are its heavy-infantry row, spec 2026-11-20-heavy-infantry-arm-design, and its militia row)
	assert_eq(ArmySystem._arm_base(repo, "", "infantry", 0), 1021)


func test_axe_forest_and_jungle() -> void:
	assert_eq(ArmySystem.terrain_factor(repo, "forest", "axemen", "attack", ""), 1150)
	assert_eq(ArmySystem.terrain_factor(repo, "jungle", "axemen", "defend", ""), 1000)


func test_axe_walls_defence() -> void:
	# plains has no axemen row (1000), walls 1150 for the holder: 1000 * 1150 / 1000
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "axemen", "defend", "walls"), 1150)


func test_axe_recruits_in_three_days() -> void:
	assert_eq(int(repo.recruitment["axemen"]["build_days"]), 3)
	assert_eq(int(repo.recruitment["axemen"]["equipment_gold_per_element"]), 1)


func test_every_land_arm_has_its_rows() -> void:
	var split_arms: Array = repo.army_split.map(func(r: Dictionary) -> String: return String(r["arm"]))
	for arm: String in repo.world_table("military", "unit_types"):
		if String(repo.world_table("military", "unit_types")[arm]["type"]) == "naval":
			continue
		assert_gt(int(repo.army_speed.get(arm, 0)), 0, arm + " army_speed")
		assert_true(repo.army_scouting.has(arm), arm + " army_scouting")
		assert_true(repo.army_clearance.has(arm), arm + " army_clearance")
		assert_true(repo.unit_footprints.has(arm), arm + " unit_footprints")
		assert_true(arm in split_arms, arm + " army_split")
		assert_true(repo.army_art.has(arm), arm + " army_art")


func test_axe_has_its_own_figure_and_stand_in_art() -> void:
	# The hand-axe soldier is installed (spec step 4); until the painting, the war room's piece
	# and the sounds exist, those are the infantry's.
	assert_eq(GameArt.path(GameArt.ARMY_MODELS, "axemen"), "res://scenes/models/units/axemen.tscn")
	for table: String in [GameArt.ARMY_PAINTINGS, GameArt.WAR_PIECES,
			GameArt.UNIT_SOUNDS, GameArt.UNIT_SETTLE_SOUNDS]:
		assert_ne(GameArt.path(table, "infantry"), "", table + " has infantry")
		assert_eq(GameArt.path(table, "axemen"), GameArt.path(table, "infantry"), table)
