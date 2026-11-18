extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The axemen (spec 2026-11-18-axemen-arm-design): shock foot that break shield walls and gates and
## fold under horse. Hand sums from the spec's first-draft rows.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_axe_base_is_its_matchup_mean() -> void:
	# ((1300+1000)/2 + (1100+900)/2 + (900+700)/2 + (1200+900)/2 + (1000+1000)/2) / 5
	# = (1150 + 1000 + 800 + 1050 + 1000) / 5 = 1000
	assert_eq(ArmySystem._arm_base(repo, "", "axemen", 0), 1000)


func test_infantry_base_unchanged() -> void:
	# No "infantry vs axemen" row yet: (1000 + 950 + 1250 + 1000) / 4 = 1050
	assert_eq(ArmySystem._arm_base(repo, "", "infantry", 0), 1050)


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
