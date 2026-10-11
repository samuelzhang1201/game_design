extends GutTest
const SuiteData := preload("res://tests/suite_data.gd")
## WarFront (spec 2026-10-11-war-room-front-line-design §1), the architect's
## hand-computed tables T1.1 / T1.2: posts at the middles of equal lengths,
## facing the chord's normal on the teeth's side; 0 east, 90 south, 180 west,
## 270 north.


func _line(pairs: Array) -> Array:
	return MarchRoute.from_pairs(pairs)


func _check(posts: Array, want: Array) -> void:
	assert_eq(posts.size(), want.size())
	for k in mini(posts.size(), want.size()):
		assert_eq(posts[k]["dest_m"], Vector2i(want[k][0], want[k][1]), "post %d place" % k)
		assert_eq(posts[k]["facing_deg"], want[k][2], "post %d facing" % k)


func test_a_straight_east_front_for_three() -> void:
	var p := _line([[0, 0], [30000, 0]])
	_check(WarFront.split(p, 0, 3), [[5000, 0, 90], [15000, 0, 90], [25000, 0, 90]])
	_check(WarFront.split(p, 1, 3), [[5000, 0, 270], [15000, 0, 270], [25000, 0, 270]])


func test_a_straight_south_front_for_two() -> void:
	var p := _line([[0, 0], [0, 20000]])
	_check(WarFront.split(p, 0, 2), [[0, 5000, 180], [0, 15000, 180]])
	_check(WarFront.split(p, 1, 2), [[0, 5000, 0], [0, 15000, 0]])


func test_an_l_shaped_front_faces_each_chord() -> void:
	var p := _line([[0, 0], [10000, 0], [10000, 10000]])
	_check(WarFront.split(p, 0, 2), [[5000, 0, 90], [10000, 5000, 180]])
	_check(WarFront.split(p, 0, 3), [[3333, 0, 90], [10000, 0, 135], [10000, 6667, 180]])
	_check(WarFront.split(p, 0, 4), [[2500, 0, 90], [7500, 0, 90], [10000, 2500, 180], [10000, 7500, 180]])


func test_a_diagonal_front_for_one() -> void:
	var p := _line([[0, 0], [10000, -10000]])
	_check(WarFront.split(p, 0, 1), [[5000, -5000, 45]])
	_check(WarFront.split(p, 1, 1), [[5000, -5000, 225]])


func test_nothing_for_no_regiment_or_no_length() -> void:
	assert_eq(WarFront.split(_line([[0, 0], [10000, 0]]), 0, 0).size(), 0)
	assert_eq(WarFront.split(_line([[5, 5], [5, 5]]), 0, 2).size(), 0)
	assert_eq(WarFront.split([], 0, 2).size(), 0)


func test_facing_round_trips_and_reads_as_a_compass_point() -> void:
	assert_almost_eq(WarFront.facing_vector(90).y, 1.0, 0.0001)
	assert_almost_eq(WarFront.facing_vector(180).x, -1.0, 0.0001)
	assert_eq(WarFront.facing_deg(Vector2(0, -1)), 270)
	assert_eq(WarFront.compass_words(90), "S (180°)")
	assert_eq(WarFront.compass_words(270), "N (0°)")
	assert_eq(WarFront.compass_words(0), "E (90°)")
	assert_eq(WarFront.compass_words(135), "SW (225°)")


func test_assign_takes_the_stroke_in_pack_px_and_orders_by_place_along_it() -> void:
	var repo := SuiteData.repo()
	var k := ArmySystem.metres_per_pack_px(repo)
	var stroke := {"pts": [[10 * k, 10 * k], [40 * k, 10 * k]], "flip": 0}
	# B stands west, A east, C in the middle: posts go B, C, A along the line
	var pos := {"A": Vector2(38 * k, 12 * k), "B": Vector2(12 * k, 8 * k), "C": Vector2(25 * k, 20 * k)}
	var got := WarFront.assign(repo, stroke, ["A", "B", "C"], pos)
	assert_eq(got.size(), 3)
	assert_eq(got[0]["code"], "B")
	assert_eq(got[1]["code"], "C")
	assert_eq(got[2]["code"], "A")
	assert_eq(got[0]["dest_m"], Vector2i(15 * k, 10 * k))
	assert_eq(got[1]["dest_m"], Vector2i(25 * k, 10 * k))
	assert_eq(got[2]["dest_m"], Vector2i(35 * k, 10 * k))
	for g: Dictionary in got:
		assert_eq(g["facing_deg"], 90)
	var flipped := WarFront.assign(repo, {"pts": stroke["pts"], "flip": 1}, ["A"], pos)
	assert_eq(flipped[0]["facing_deg"], 270)
	assert_eq(flipped[0]["dest_m"], Vector2i(25 * k, 10 * k))


func test_assign_breaks_a_tie_by_code() -> void:
	var repo := SuiteData.repo()
	var k := ArmySystem.metres_per_pack_px(repo)
	var stroke := {"pts": [[0, 0], [20 * k, 0]], "flip": 0}
	var same := {"Z": Vector2(10 * k, 5 * k), "M": Vector2(10 * k, -5 * k)}
	var got := WarFront.assign(repo, stroke, ["Z", "M"], same)
	assert_eq(got[0]["code"], "M")
	assert_eq(got[1]["code"], "Z")
	assert_eq(WarFront.assign(repo, stroke, [], same).size(), 0)
