extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The heavy infantry (spec 2026-11-20-heavy-infantry-arm-design): plate-armoured foot, slow and
## dear, hard to break and hardest behind walls. Hand sums from the spec's first-draft rows.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_heavy_base_is_its_matchup_mean() -> void:
	# vs infantry (1100+1200)/2, archers (1000+1200)/2, cavalry (1100+1300)/2, artillery (1100+800)/2,
	# axemen (1100+1000)/2, heavy (1000+1000)/2, militia (1300+1300)/2:
	# (1150 + 1100 + 1200 + 950 + 1050 + 1000 + 1300) / 7 = 7750 / 7 = 1107 (whole)
	assert_eq(ArmySystem._arm_base(repo, "", "heavy_infantry", 0), 1107)


func test_every_other_arm_counts_its_heavy_row() -> void:
	# Each arm's row against heavy infantry joins its mean (ArmySystem._arm_base); the last term of each
	# sum is its militia row (spec 2026-11-26-militia-arm-design).
	# infantry: (1000 + 950 + 1250 + 1000 + 900 + (900+900)/2 + 1150) / 7 = 7150 / 7 = 1021 (whole)
	assert_eq(ArmySystem._arm_base(repo, "", "infantry", 0), 1021)
	# archers: (1000 + 1000 + 750 + 950 + 1000 + (900+800)/2 + 1100) / 7 = 6650 / 7
	assert_eq(ArmySystem._arm_base(repo, "", "archers", 0), 950)
	# cavalry: (850 + 1250 + 1000 + 1200 + 1150 + (800+800)/2 + 1200) / 7 = 7450 / 7 = 1064 (whole)
	assert_eq(ArmySystem._arm_base(repo, "", "cavalry", 0), 1064)
	# artillery: (900 + 850 + 700 + 1000 + 900 + (1200+700)/2 + 900) / 7 = 6200 / 7 = 885 (whole)
	assert_eq(ArmySystem._arm_base(repo, "", "artillery", 0), 885)
	# axemen: (1150 + 1000 + 800 + 1050 + 1000 + (1100+900)/2 + 1200) / 7 = 7200 / 7 = 1028 (whole)
	assert_eq(ArmySystem._arm_base(repo, "", "axemen", 0), 1028)


func test_heavy_is_poor_in_rough_ground() -> void:
	assert_eq(ArmySystem.terrain_factor(repo, "jungle", "heavy_infantry", "defend", ""), 700)
	assert_eq(ArmySystem.terrain_factor(repo, "marsh", "heavy_infantry", "attack", ""), 800)
	assert_eq(ArmySystem.terrain_factor(repo, "forest", "heavy_infantry", "defend", ""), 900)
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "heavy_infantry", "attack", ""), 1000)


func test_heavy_is_best_behind_works() -> void:
	# plains has no heavy row (1000); the works multiply the holder's factor.
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "heavy_infantry", "defend", "town"), 1150)
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "heavy_infantry", "defend", "walls"), 1350)
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "heavy_infantry", "defend", "citadel"), 1450)
	# forest 900 behind walls 1350: 900 * 1350 / 1000 = 1215
	assert_eq(ArmySystem.terrain_factor(repo, "forest", "heavy_infantry", "defend", "walls"), 1215)
	# the works help only the side that holds them
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "heavy_infantry", "attack", "walls"), 1000)
	for works: String in ["town", "walls", "citadel"]:
		assert_gt(int(repo.army_town_defence["%s|heavy_infantry" % works]["defend"]),
			int(repo.army_town_defence["%s|infantry" % works]["defend"]), works)


func test_heavy_only_regiment_marches_sixteen_km_a_day() -> void:
	# A regiment marches at its SLOWEST arm (army_speed.csv: heavy 16, infantry 20, artillery 12).
	assert_eq(ArmySystem.base_pace_km(repo, {"heavy_infantry": 600}), 16)
	assert_eq(ArmySystem.base_pace_km(repo, {"heavy_infantry": 600, "infantry": 900, "cavalry": 50}), 16,
		"heavy infantry slows a mixed host")
	assert_eq(ArmySystem.base_pace_km(repo, {"heavy_infantry": 600, "artillery": 4}), 12)
	assert_eq(ArmySystem.base_pace_km(repo, {"infantry": 900, "heavy_infantry": 0}), 20, "none present: the infantry's pace")


func test_heavy_scouts_twelve_km() -> void:
	assert_eq(int(repo.army_scouting["heavy_infantry"]["scout_km"]), 12)
	assert_eq(int(repo.army_scouting["heavy_infantry"]["arc_deg"]), 120)


func test_heavy_is_dear_and_slow_to_raise() -> void:
	var row: Dictionary = repo.recruitment["heavy_infantry"]
	assert_eq(int(row["build_days"]), 8)
	assert_eq(int(row["equipment_gold_per_element"]), 3)
	for column: String in ["commoner_gold", "noble_gold", "commander_gold", "requires_port"]:
		assert_eq(int(row[column]), int(repo.recruitment["infantry"][column]), column + " as the infantry's")


func test_heavy_has_every_land_arm_row() -> void:
	var arm := "heavy_infantry"
	assert_true(repo.world_table("military", "unit_types").has(arm), "unit_types")
	assert_true(repo.army_clearance.has(arm), "army_clearance")
	assert_true(repo.unit_footprints.has(arm), "unit_footprints")
	assert_true(repo.army_art.has(arm), "army_art")
	assert_true(repo.army_split.any(func(r: Dictionary) -> bool: return String(r["arm"]) == arm), "army_split")
	assert_eq(String(repo.war_order_words.get("arm_" + arm, "")), "heavy foot")
	assert_eq(String(repo.cluster_arms[arm]["counts_as"]), "infantry")
	assert_gt(WarFolio.kit_of(repo, arm).size(), 0, "war_equipment")
	assert_false(BodyMotion._loco_policy(repo, arm).is_empty(), "an installed locomotion certificate")


func test_heavy_draws_its_own_soldier_and_borrows_the_rest() -> void:
	# The plate soldier is installed; its painting, war piece and sounds are still the infantry's.
	assert_eq(GameArt.path(GameArt.ARMY_MODELS, "heavy_infantry"), "res://scenes/models/units/heavy_infantry.tscn")
	for table: String in [GameArt.ARMY_PAINTINGS, GameArt.WAR_PIECES,
			GameArt.UNIT_SOUNDS, GameArt.UNIT_SETTLE_SOUNDS]:
		assert_ne(GameArt.path(table, "infantry"), "", table + " has infantry")
		assert_eq(GameArt.path(table, "heavy_infantry"), GameArt.path(table, "infantry"), table)
