extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## A regiment's piece as three, six or nine figures by its strength (owner
## 2026-09-30: 满员 3×3, 减员 前中后 1/2/3, 残兵 前后排 1/2), data/army_formations.csv.

var repo: DataRepository


func before_all() -> void:
	repo = SuiteData.repo()


func test_three_tiers_three_six_nine_figures() -> void:
	assert_eq(repo.army_formations.size(), 3)
	for i in 3:
		var row: Dictionary = repo.army_formations[i]
		assert_eq(int(row["figures"]), 3 * (i + 1))
		assert_eq((row["slots"] as Array).size(), 3 * (i + 1), "tier %d has one slot a figure" % i)


func test_the_tier_is_the_last_threshold_reached() -> void:
	# thresholds 0 / 334 / 667 per mille fit
	assert_eq(int(Map3DFormation.tier_of(repo, 0)["figures"]), 3)
	assert_eq(int(Map3DFormation.tier_of(repo, 333)["figures"]), 3)
	assert_eq(int(Map3DFormation.tier_of(repo, 334)["figures"]), 6)
	assert_eq(int(Map3DFormation.tier_of(repo, 666)["figures"]), 6)
	assert_eq(int(Map3DFormation.tier_of(repo, 667)["figures"]), 9)
	assert_eq(int(Map3DFormation.tier_of(repo, 1000)["figures"]), 9)


func test_full_strength_is_three_ranks_of_three() -> void:
	# a figure 0.5 m half wide, 1.5 m half long, gap 1.0: one spacing unit is
	# 1 m across and 3 m front to back
	var offs := Map3DFormation.offsets(Map3DFormation.tier_of(repo, 1000), Vector2(0.5, 1.5), 1.0)
	assert_eq(offs, PackedVector2Array([Vector2(-1, -3), Vector2(0, -3), Vector2(1, -3),
		Vector2(-1, 0), Vector2(0, 0), Vector2(1, 0),
		Vector2(-1, 3), Vector2(0, 3), Vector2(1, 3)]))
	assert_eq(Map3DFormation.half_extent(offs, Vector2(0.5, 1.5)), Vector2(1.5, 4.5))


func test_depleted_is_one_two_three_from_the_front() -> void:
	# a figure 0.5 m half wide, 1.5 m half long, gap 1.25: one spacing unit is
	# 1.25 m across and 3.75 m front to back
	var offs := Map3DFormation.offsets(Map3DFormation.tier_of(repo, 500), Vector2(0.5, 1.5), 1.25)
	assert_eq(offs, PackedVector2Array([Vector2(0, -3.75), Vector2(-0.625, 0), Vector2(0.625, 0),
		Vector2(-1.25, 3.75), Vector2(0, 3.75), Vector2(1.25, 3.75)]))
	# the farthest slot plus one figure's own half: (1.25 + 0.5, 3.75 + 1.5)
	assert_eq(Map3DFormation.half_extent(offs, Vector2(0.5, 1.5)), Vector2(1.75, 5.25))


func test_rank_depth_spreads_the_ranks_only() -> void:
	var offs := Map3DFormation.offsets(Map3DFormation.tier_of(repo, 1000), Vector2(0.5, 1.5), 1.0, 1.6)
	assert_eq(offs[0], Vector2(-1, -4.8))
	assert_eq(offs[4], Vector2(0, 0))
	assert_eq(offs[8], Vector2(1, 4.8))
	# the man-at-arms' ranks stand further apart than his files (seen from the
	# front they hid each other), the horse's no closer than its own length
	assert_gt(Map3DFormation.rank_depth(repo.army_art["infantry"]), 1.0)
	assert_gte(Map3DFormation.rank_depth(repo.army_art["cavalry"]), 1.0)


func test_remnants_are_one_in_front_two_behind() -> void:
	var offs := Map3DFormation.offsets(Map3DFormation.tier_of(repo, 100), Vector2(0.5, 1.5), 1.0)
	assert_eq(offs, PackedVector2Array([Vector2(0, -1.5), Vector2(-0.5, 1.5), Vector2(0.5, 1.5)]))


func test_strength_is_fit_men_per_mille_of_the_headcount() -> void:
	var state := GameState.new()
	var code := ""
	for reg: Dictionary in MapObjects.regiments_of(repo, repo.resolve_realm("player_realm")):
		if ArmySystem.headcount(repo, reg) > 0:
			code = String(reg["regiment_code"])
			break
	assert_ne(code, "", "the player's realm has a regiment")
	var heads := ArmySystem.headcount(repo, ArmySystem.regiment(repo, code))
	assert_eq(ArmySystem.fit_permille(repo, state, code), 1000, "no state yet: as it would start")
	ArmySystem.ensure(repo, state)
	state.regiments[code]["wounded"] = heads / 2
	@warning_ignore("integer_division")
	assert_eq(ArmySystem.fit_permille(repo, state, code), (heads - heads / 2) * 1000 / heads)
	assert_eq(int(Map3DFormation.tier_of(repo, ArmySystem.fit_permille(repo, state, code))["figures"]), 6)
	state.regiments[code]["wounded"] = heads * 10
	assert_eq(ArmySystem.fit_permille(repo, state, code), 0, "the wounded are held to the headcount")
