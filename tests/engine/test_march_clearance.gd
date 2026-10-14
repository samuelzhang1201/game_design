extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The geometry of unit clearance (spec 2026-10-14-unit-clearance-and-scouting-
## design §a-b), hand-computed for C 1400: R8 = ceil(1400 / cos 22.5) = 1516, its
## 45 degree part round(1516 * 0.7071) = 1072, an edge's midpoint 1516 * cos 22.5
## = 1400.6 from the centre.

const C := 1400


func test_octagon_round_a_blocker() -> void:
	assert_eq(MarchClearance.r8(C), 1516)
	var o := MarchClearance.octagon(Vector2i(10000, 0), C)
	assert_eq(o, [Vector2i(11516, 0), Vector2i(11072, 1072), Vector2i(10000, 1516), Vector2i(8928, 1072),
		Vector2i(8484, 0), Vector2i(8928, -1072), Vector2i(10000, -1516), Vector2i(11072, -1072)])
	var mid := (Vector2(o[0]) + Vector2(o[1])) / 2.0
	assert_almost_eq(mid.distance_to(Vector2(10000, 0)), 1400.62, 0.01)


func test_right_detour_round_one_blocker() -> void:
	var d := MarchClearance.detour(Vector2i(0, 0), [Vector2i(20000, 0)], [Vector2i(10000, 0)], C)
	assert_eq(d["kind"], "route")
	assert_eq(d["path"], [Vector2i(8484, 0), Vector2i(8928, 1072), Vector2i(10000, 1516),
		Vector2i(11072, 1072), Vector2i(11516, 0), Vector2i(20000, 0)])
	# both sides are 4 x 1160 = 4640 metres: the tie goes to the right (+y heading east)
	assert_eq(MarchClearance.length_of([Vector2i(8484, 0), Vector2i(8928, 1072), Vector2i(10000, 1516),
		Vector2i(11072, 1072), Vector2i(11516, 0)]), 4640)


func test_a_clump_is_gone_round_as_one() -> void:
	var centres := [Vector2i(10000, 0), Vector2i(12000, 0)]
	assert_eq(MarchClearance.clump(0, centres, C), [0, 1])
	assert_eq(MarchClearance.clump(0, [Vector2i(10000, 0), Vector2i(14000, 0)], C), [0], "4000 apart is two blockers")
	var d := MarchClearance.detour(Vector2i(0, 0), [Vector2i(20000, 0)], centres, C)
	assert_eq(d["path"], [Vector2i(8484, 0), Vector2i(8928, 1072), Vector2i(10000, 1516),
		Vector2i(12000, 1516), Vector2i(13072, 1072), Vector2i(13516, 0), Vector2i(20000, 0)])


func test_the_shorter_side_wins() -> void:
	# a blocker 300 m south of the line: the north side is 3992, the south 5290
	var d := MarchClearance.detour(Vector2i(0, 0), [Vector2i(20000, 0)], [Vector2i(10000, 300)], C)
	assert_eq(d["path"], [Vector2i(8608, 0), Vector2i(8928, -772), Vector2i(10000, -1216),
		Vector2i(11072, -772), Vector2i(11392, 0), Vector2i(20000, 0)])
	assert_eq(MarchClearance.length_of([Vector2i(8608, 0), Vector2i(8928, -772), Vector2i(10000, -1216),
		Vector2i(11072, -772), Vector2i(11392, 0)]), 3992)


func test_both_sides_closed_waits() -> void:
	var shut := func(_a: Vector2i, _b: Vector2i) -> bool: return false
	var d := MarchClearance.detour(Vector2i(0, 0), [Vector2i(20000, 0)], [Vector2i(10000, 0)], C, shut)
	assert_eq(d["kind"], "wait")
	assert_eq(d["at"], Vector2i(8484, 0))


func test_one_side_closed_takes_the_other() -> void:
	var no_south := func(a: Vector2i, b: Vector2i) -> bool: return a.y <= 0 and b.y <= 0
	var d := MarchClearance.detour(Vector2i(0, 0), [Vector2i(20000, 0)], [Vector2i(10000, 0)], C, no_south)
	assert_eq(d["kind"], "route")
	assert_eq(d["path"][1], Vector2i(8928, -1072), "the north side, the south being closed")


func test_halt_point_is_clear_of_the_disc() -> void:
	assert_eq(MarchClearance.halt_point(Vector2i(0, 0), Vector2i(10000, 0), Vector2i(10000, 0), C), Vector2i(8600, 0))
	assert_eq(MarchClearance.halt_point(Vector2i(0, 0), Vector2i(3000, 4000), Vector2i(3000, 4000), C), Vector2i(2160, 2880))
	for i in 40:
		var q := Vector2i(7000 + i * 13, 3100 + i * 71)
		var p := MarchClearance.halt_point(Vector2i(0, 0), q, q, C)
		assert_gte(MarchClearance.dist2(p, q), C * C, "rounding never leaves the halt inside the disc")


func test_first_entry_names_the_disc_and_the_distance() -> void:
	var e := MarchClearance.first_entry(Vector2i(0, 0), [Vector2i(20000, 0)], [Vector2i(10000, 3000), Vector2i(10000, 0)], C)
	assert_eq(int(e["index"]), 1, "the one on the line; the other is 3000 m off it")
	assert_eq(e["at"], Vector2i(8600, 0))
	assert_almost_eq(float(e["dist"]), 8600.0, 0.01)
	assert_true(MarchClearance.first_entry(Vector2i(0, 0), [Vector2i(20000, 0)], [Vector2i(10000, 1400)], C).is_empty(),
		"a pass at exactly C is legal")
	assert_true(MarchClearance.first_entry(Vector2i(10000, 800), [Vector2i(20000, 800)], [Vector2i(10000, 0)], C).is_empty(),
		"a unit already inside the disc is not stopped by it here (the caller drops it)")
