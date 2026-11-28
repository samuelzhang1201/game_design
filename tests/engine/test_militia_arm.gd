extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The militia (spec 2026-11-26-militia-arm-design): townsmen under arms, cheap and quick to raise,
## weaker than the infantry in the open and worth its rows on their own walls. Hand sums from the
## spec's first-draft rows.

var repo: DataRepository


func before_each() -> void:
	repo = SuiteData.repo()


func test_militia_base_is_its_matchup_mean() -> void:
	# vs infantry (800+800)/2, archers (800+900)/2, cavalry (900+1000)/2, artillery (1000+800)/2,
	# axemen (800+700)/2, heavy infantry (700+800)/2, militia (1000+1000)/2:
	# (800 + 850 + 950 + 900 + 750 + 750 + 1000) / 7 = 6000 / 7 = 857 (whole)
	assert_eq(ArmySystem._arm_base(repo, "", "militia", 0), 857)


func test_every_other_arm_counts_its_militia_row() -> void:
	# Each arm's row against the militia joins its mean (ArmySystem._arm_base).
	# infantry: (1000 + 950 + 1250 + 1000 + 900 + 900 + (1200+1100)/2) / 7 = 7150 / 7 = 1021 (whole)
	assert_eq(ArmySystem._arm_base(repo, "", "infantry", 0), 1021)
	# archers: (1000 + 1000 + 750 + 950 + 1000 + 850 + (1300+900)/2) / 7 = 6650 / 7 = 950
	assert_eq(ArmySystem._arm_base(repo, "", "archers", 0), 950)
	# cavalry: (850 + 1250 + 1000 + 1200 + 1150 + 800 + (1300+1100)/2) / 7 = 7450 / 7 = 1064 (whole)
	assert_eq(ArmySystem._arm_base(repo, "", "cavalry", 0), 1064)
	# artillery: (900 + 850 + 700 + 1000 + 900 + 950 + (1100+700)/2) / 7 = 6200 / 7 = 885 (whole)
	assert_eq(ArmySystem._arm_base(repo, "", "artillery", 0), 885)
	# axemen: (1150 + 1000 + 800 + 1050 + 1000 + 1000 + (1300+1100)/2) / 7 = 7200 / 7 = 1028 (whole)
	assert_eq(ArmySystem._arm_base(repo, "", "axemen", 0), 1028)
	# heavy infantry: (1150 + 1100 + 1200 + 950 + 1050 + 1000 + (1300+1300)/2) / 7 = 7750 / 7 = 1107 (whole)
	assert_eq(ArmySystem._arm_base(repo, "", "heavy_infantry", 0), 1107)


func test_militia_is_weaker_than_infantry_in_the_open() -> void:
	# 1000 men, training 50 (factor 1000), morale 50 (750), no terrain:
	# militia 1,000,000 x 857 / 1000 x 750 / 1000 = 642,750 -> ceil 643;
	# infantry 1,000,000 x 1021 / 1000 x 750 / 1000 = 765,750 -> ceil 766.
	assert_eq(ArmySystem.power_of_arms(repo, {"militia": 1000}, 1000, 50, 50, "defend", "", ""), 643)
	assert_eq(ArmySystem.power_of_arms(repo, {"infantry": 1000}, 1000, 50, 50, "defend", "", ""), 766)


func test_militia_has_no_terrain_row_and_holds_works_as_the_infantry() -> void:
	for terrain: String in ["plains", "forest", "jungle", "marsh", "hills"]:
		assert_false(repo.army_terrain.has("%s|militia" % terrain), terrain + ": no militia row")
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "militia", "attack", ""), 1000)
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "militia", "defend", "town"), 1100)
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "militia", "defend", "walls"), 1300)
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "militia", "defend", "citadel"), 1400)
	# the works help only the side that holds them
	assert_eq(ArmySystem.terrain_factor(repo, "plains", "militia", "attack", "walls"), 1000)
	for works: String in ["town", "walls", "citadel"]:
		assert_eq(repo.army_town_defence["%s|militia" % works]["defend"],
			repo.army_town_defence["%s|infantry" % works]["defend"], works)


func test_militia_marches_and_scouts_as_the_infantry() -> void:
	# A regiment marches at its SLOWEST arm (army_speed.csv: militia 20, heavy infantry 16).
	assert_eq(ArmySystem.base_pace_km(repo, {"militia": 500}), 20)
	assert_eq(ArmySystem.base_pace_km(repo, {"militia": 500, "heavy_infantry": 100}), 16)
	assert_eq(int(repo.army_scouting["militia"]["scout_km"]), 15)
	assert_eq(int(repo.army_scouting["militia"]["arc_deg"]), 120)


func test_militia_is_cheap_and_quick_to_raise() -> void:
	var row: Dictionary = repo.recruitment["militia"]
	assert_eq(int(row["build_days"]), 3)
	assert_lt(int(row["build_days"]), int(repo.recruitment["infantry"]["build_days"]))
	for column: String in ["commoner_gold", "noble_gold", "commander_gold", "equipment_gold_per_element", "requires_port"]:
		assert_eq(int(row[column]), int(repo.recruitment["infantry"][column]), column + " as the infantry's")


func test_militia_has_every_land_arm_row() -> void:
	var arm := "militia"
	assert_true(repo.world_table("military", "unit_types").has(arm), "unit_types")
	assert_eq(int(repo.army_clearance[arm]), int(repo.army_clearance["infantry"]), "army_clearance")
	for column: String in ["radius_m", "pitch_m", "width_m", "depth_m", "files", "ranks"]:
		assert_eq(repo.unit_footprints[arm][column], repo.unit_footprints["infantry"][column], column)
	assert_true(repo.army_art.has(arm), "army_art")
	assert_true(repo.army_split.any(func(r: Dictionary) -> bool: return String(r["arm"]) == arm), "army_split")
	assert_eq(String(repo.war_order_words.get("arm_" + arm, "")), "militia")
	assert_eq(String(repo.cluster_arms[arm]["counts_as"]), "infantry")
	assert_eq(WarFolio.kit_of(repo, arm).size(), 4, "kettle hat, tunic, round shield, short sword")


func test_the_pack_carries_a_militia_column() -> void:
	# A whole number in every row; the opening regiments that fill it are the spec's step 2
	# (data/army/game_arm_starts.csv, checked in test_army_starts.gd).
	for table: String in ["regiments", "kingdoms"]:
		var rows: Dictionary = SuiteData.repo().world_table("military", table)
		assert_gt(rows.size(), 0, table)
		for code: String in rows:
			assert_true(String(rows[code].get("militia", "")).is_valid_int(), "%s %s" % [table, code])


func test_militia_draws_the_militiaman_and_borrows_the_rest() -> void:
	# The arm's piece is the installed figure a raised town militia also wears (TownMilitia.FIGURE).
	assert_eq(GameArt.path(GameArt.ARMY_MODELS, "militia"), "res://scenes/models/units/militia.tscn")
	assert_eq(MapObjects.army_piece(repo, {"organization_arm": "militia", "is_royal": "0", "is_naval": "0"}), "militia")
	for table: String in [GameArt.ARMY_PAINTINGS, GameArt.WAR_PIECES, GameArt.UNIT_SOUNDS, GameArt.UNIT_SETTLE_SOUNDS]:
		assert_ne(GameArt.path(table, "infantry"), "", table + " has infantry")
		assert_eq(GameArt.path(table, "militia"), GameArt.path(table, "infantry"), table)


func test_the_candidate_locomotion_path_admits_the_militia() -> void:
	# The militiaman has his pivot pair and certificate (unit_locomotion.csv, body_locomotion_militia_*):
	# the opt-in v2 march candidate admits the arm like every other land arm.
	var policy := BodyMotion._loco_policy(repo, "militia")
	assert_false(policy.is_empty())
	assert_eq(int(policy.turn_q), 400000)
	assert_eq(int(policy.contact_um), 24202, "ceil(0.60e6 / 24.7922): the militiaman's own scale")
	assert_eq(int(policy.radius_m), int(repo.unit_footprints["militia"].radius_m))
