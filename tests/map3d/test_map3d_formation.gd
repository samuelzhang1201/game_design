extends GutTest
## A regiment's piece as one to six figures by headcount (owner 2026-09-27:
## 兵人模型需要有人数区分，分成6个人数等级), data/army_formations.csv.

var repo: DataRepository


func before_all() -> void:
	repo = DataRepository.load_all("res://data")


func test_six_tiers_one_to_six_figures() -> void:
	assert_eq(repo.army_formations.size(), 6)
	for i in 6:
		var row: Dictionary = repo.army_formations[i]
		assert_eq(int(row["figures"]), i + 1)
		assert_eq((row["slots"] as Array).size(), i + 1, "tier %d has one slot a figure" % (i + 1))


func test_the_tier_is_the_last_threshold_reached() -> void:
	# thresholds 0 / 1200 / 1700 / 2300 / 2900 / 3500
	assert_eq(int(Map3DFormation.tier_of(repo, 337.0)["figures"]), 1)
	assert_eq(int(Map3DFormation.tier_of(repo, 1199.0)["figures"]), 1)
	assert_eq(int(Map3DFormation.tier_of(repo, 1200.0)["figures"]), 2)
	assert_eq(int(Map3DFormation.tier_of(repo, 1732.0)["figures"]), 3)
	assert_eq(int(Map3DFormation.tier_of(repo, 2308.0)["figures"]), 4)
	assert_eq(int(Map3DFormation.tier_of(repo, 2896.0)["figures"]), 4)
	assert_eq(int(Map3DFormation.tier_of(repo, 3000.0)["figures"]), 5)
	assert_eq(int(Map3DFormation.tier_of(repo, 4564.0)["figures"]), 6)


func test_the_wedge_is_one_two_three_from_the_point() -> void:
	# a figure 0.5 m half wide, 1.5 m half long, gap 1.25: one spacing unit is
	# 1.25 m across and 3.75 m front to back
	var offs := Map3DFormation.offsets(Map3DFormation.tier_of(repo, 9999.0), Vector2(0.5, 1.5), 1.25)
	assert_eq(offs, PackedVector2Array([Vector2(0, -3.75), Vector2(-0.625, 0), Vector2(0.625, 0),
		Vector2(-1.25, 3.75), Vector2(0, 3.75), Vector2(1.25, 3.75)]))
	# the farthest slot plus one figure's own half: (1.25 + 0.5, 3.75 + 1.5)
	assert_eq(Map3DFormation.half_extent(offs, Vector2(0.5, 1.5)), Vector2(1.75, 5.25))


func test_two_stand_side_by_side() -> void:
	var offs := Map3DFormation.offsets(Map3DFormation.tier_of(repo, 1500.0), Vector2(0.5, 1.5), 1.0)
	assert_eq(offs, PackedVector2Array([Vector2(-0.5, 0), Vector2(0.5, 0)]))
