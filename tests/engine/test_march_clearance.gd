extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## The geometry of unit clearance (spec 2026-10-14-unit-clearance-and-scouting-
## design §a-b), hand-computed for a pair clearance D 1400: R8 = ceil(1400 /
## cos 22.5) + 1 = 1517 (the metre is the margin whole-metre rounding cannot
## eat), its 45 degree part ceil(1517 * 0.7071) = 1073, an edge's midpoint 1517 *
## cos 22.5 = 1401.6 from the centre; a halt stands D + 1 off.

const C := 1400


func test_octagon_round_a_blocker() -> void:
	assert_eq(MarchClearance.r8(C), 1517)
	var o := MarchClearance.octagon(Vector2i(10000, 0), C)
	assert_eq(o, [Vector2i(11517, 0), Vector2i(11073, 1073), Vector2i(10000, 1517), Vector2i(8927, 1073),
		Vector2i(8483, 0), Vector2i(8927, -1073), Vector2i(10000, -1517), Vector2i(11073, -1073)])
	var mid := (Vector2(o[0]) + Vector2(o[1])) / 2.0
	assert_almost_eq(mid.distance_to(Vector2(10000, 0)), 1401.7, 0.1)


func test_right_detour_round_one_blocker() -> void:
	var d := MarchClearance.detour(Vector2i(0, 0), [Vector2i(20000, 0)], [Vector2i(10000, 0)], [C])
	assert_eq(d["kind"], "route")
	assert_eq(d["path"], [Vector2i(8483, 0), Vector2i(8927, 1073), Vector2i(10000, 1517),
		Vector2i(11073, 1073), Vector2i(11517, 0), Vector2i(20000, 0)])
	# both sides are 4 x 1161 = 4644 metres: the tie goes to the right (+y heading east)
	assert_eq(MarchClearance.length_of([Vector2i(8483, 0), Vector2i(8927, 1073), Vector2i(10000, 1517),
		Vector2i(11073, 1073), Vector2i(11517, 0)]), 4644)


func test_a_clump_is_gone_round_as_one() -> void:
	var centres := [Vector2i(10000, 0), Vector2i(12000, 0)]
	assert_eq(MarchClearance.clump(0, centres, [C, C]), [0, 1])
	assert_eq(MarchClearance.clump(0, [Vector2i(10000, 0), Vector2i(14000, 0)], [C, C]), [0], "4000 apart is two blockers")
	# octagons overlap up to r8 + r8 = 3034 apart: 2850 beside is one clump, 3100 not
	assert_eq(MarchClearance.clump(0, [Vector2i(10000, 0), Vector2i(12850, 0)], [C, C]), [0, 1])
	assert_eq(MarchClearance.clump(0, [Vector2i(10000, 0), Vector2i(13100, 0)], [C, C]), [0])
	var d := MarchClearance.detour(Vector2i(0, 0), [Vector2i(20000, 0)], centres, [C, C])
	assert_eq(d["path"], [Vector2i(8483, 0), Vector2i(8927, 1073), Vector2i(10000, 1517),
		Vector2i(12000, 1517), Vector2i(13073, 1073), Vector2i(13517, 0), Vector2i(20000, 0)])


func test_the_shorter_side_wins() -> void:
	# a blocker 300 m south of the line: the north side is 3992, the south 5290
	var d := MarchClearance.detour(Vector2i(0, 0), [Vector2i(20000, 0)], [Vector2i(10000, 300)], [C])
	assert_eq(d["path"], [Vector2i(8607, 0), Vector2i(8927, -773), Vector2i(10000, -1217),
		Vector2i(11073, -773), Vector2i(11393, 0), Vector2i(20000, 0)])
	assert_eq(MarchClearance.length_of([Vector2i(8607, 0), Vector2i(8927, -773), Vector2i(10000, -1217),
		Vector2i(11073, -773), Vector2i(11393, 0)]), 3996)


func test_both_sides_closed_waits() -> void:
	var shut := func(_a: Vector2i, _b: Vector2i) -> bool: return false
	var d := MarchClearance.detour(Vector2i(0, 0), [Vector2i(20000, 0)], [Vector2i(10000, 0)], [C], shut)
	assert_eq(d["kind"], "wait")
	assert_eq(d["at"], Vector2i(8483, 0))


func test_one_side_closed_takes_the_other() -> void:
	var no_south := func(a: Vector2i, b: Vector2i) -> bool: return a.y <= 0 and b.y <= 0
	var d := MarchClearance.detour(Vector2i(0, 0), [Vector2i(20000, 0)], [Vector2i(10000, 0)], [C], no_south)
	assert_eq(d["kind"], "route")
	assert_eq(d["path"][1], Vector2i(8927, -1073), "the north side, the south being closed")


func test_halt_point_is_clear_of_the_disc() -> void:
	assert_eq(MarchClearance.halt_point(Vector2i(0, 0), Vector2i(10000, 0), Vector2i(10000, 0), C), Vector2i(8599, 0))
	assert_eq(MarchClearance.halt_point(Vector2i(0, 0), Vector2i(3000, 4000), Vector2i(3000, 4000), C), Vector2i(2159, 2879),
		"D + 1 = 1401 off along the 3-4-5 road: 5000 - 1401 = 3599 -> (2159.4, 2879.2)")
	for i in 40:
		var q := Vector2i(7000 + i * 13, 3100 + i * 71)
		var p := MarchClearance.halt_point(Vector2i(0, 0), q, q, C)
		assert_gte(MarchClearance.dist2(p, q), (C + 1) * (C + 1), "rounding never leaves the halt inside the disc")


func test_first_entry_names_the_disc_and_the_distance() -> void:
	var e := MarchClearance.first_entry(Vector2i(0, 0), [Vector2i(20000, 0)], [Vector2i(10000, 3000), Vector2i(10000, 0)], [C, C])
	assert_eq(int(e["index"]), 1, "the one on the line; the other is 3000 m off it")
	assert_eq(e["at"], Vector2i(8599, 0))
	assert_almost_eq(float(e["dist"]), 8599.0, 0.01)
	assert_true(MarchClearance.first_entry(Vector2i(0, 0), [Vector2i(20000, 0)], [Vector2i(10000, 1401)], [C]).is_empty(),
		"a pass at D + 1 is legal")
	assert_false(MarchClearance.first_entry(Vector2i(0, 0), [Vector2i(20000, 0)], [Vector2i(10000, 1400)], [C]).is_empty(),
		"a pass at D itself grazes the margin")
	assert_true(MarchClearance.first_entry(Vector2i(10000, 800), [Vector2i(20000, 800)], [Vector2i(10000, 0)], [C]).is_empty(),
		"a unit inside the disc whose leg only walks away from it is let go")
	var closing := MarchClearance.first_entry(Vector2i(10000, 800), [Vector2i(10000, 100)], [Vector2i(10000, 0)], [C])
	assert_eq(closing["at"], Vector2i(10000, 800), "a leg that closes on a unit already inside stops on the spot")
