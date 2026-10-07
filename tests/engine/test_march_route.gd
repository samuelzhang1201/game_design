extends GutTest
## MarchRoute (spec 2026-10-07-march-waypoints §1): a centripetal Catmull-Rom
## through the column, its waypoints and the end, sampled into whole metres —
## the line the maps draw and the column walks.


func _v(a: Array) -> Array:
	var out: Array = []
	for p: Array in a:
		out.append(Vector2i(int(p[0]), int(p[1])))
	return out


## Three points of an isosceles turn, every knot gap equal (|Δ| = 1414.2 m), so
## the centripetal curve is the uniform one: a leg's middle is
## (-P(i-1) + 9 P(i) + 9 P(i+1) - P(i+2)) / 16, the ends reflected
## (P(-1) = 2 P0 - P1 = (-1000, -1000), P(3) = 2 P2 - P1 = (3000, -1000)).
## Leg 0: (1000 + 9000 - 2000, 1000 + 9000 - 0) / 16 = (500, 625).
## Leg 1: (0 + 9000 + 18000 - 3000, 0 + 9000 + 0 + 1000) / 16 = (1500, 625).
## A chord of 1414 m at 1000 m a sample is two samples a leg.
func test_a_turn_is_sampled_through_every_point_on_hand_computed_middles() -> void:
	var pts := _v([[0, 0], [1000, 1000], [2000, 0]])
	assert_eq(MarchRoute.curve(pts, 1000), _v([[0, 0], [500, 625], [1000, 1000], [1500, 625], [2000, 0]]))


func test_legs_split_the_same_samples_by_the_leg_they_lie_on() -> void:
	var pts := _v([[0, 0], [1000, 1000], [2000, 0]])
	var legs := MarchRoute.legs(pts, 1000)
	assert_eq(legs.size(), 2)
	assert_eq(legs[0], _v([[500, 625], [1000, 1000]]), "a leg runs from after its start to its end")
	assert_eq(legs[1], _v([[1500, 625], [2000, 0]]))


func test_a_leg_shorter_than_a_sample_is_one_point_its_end() -> void:
	var pts := _v([[0, 0], [300, 0], [600, 400]])
	var legs := MarchRoute.legs(pts, 1000)
	assert_eq(legs[0], _v([[300, 0]]))
	assert_eq(legs[1], _v([[600, 400]]))


func test_points_in_a_line_stay_on_the_line() -> void:
	var pts := _v([[0, 0], [4000, 0], [9000, 0]])
	var c := MarchRoute.curve(pts, 1000)
	assert_eq(c[0], Vector2i(0, 0))
	assert_eq(c[c.size() - 1], Vector2i(9000, 0))
	var last := -1
	for p: Vector2i in c:
		assert_eq(p.y, 0, "no bend in a straight route")
		assert_gt(p.x, last, "and it only goes forward")
		last = p.x
	assert_eq(c.size(), 1 + 4 + 5, "ceil(4000 / 1000) + ceil(5000 / 1000) samples after the start")


func test_a_repeated_point_is_dropped_before_the_curve_is_drawn() -> void:
	assert_eq(MarchRoute.curve(_v([[0, 0], [0, 0], [2000, 0]]), 1000),
		MarchRoute.curve(_v([[0, 0], [2000, 0]]), 1000))
	assert_eq(MarchRoute.curve(_v([[5, 5]]), 1000), _v([[5, 5]]), "one point is itself")


func test_the_length_is_the_sum_of_the_chords() -> void:
	assert_almost_eq(MarchRoute.length_m(_v([[0, 0], [3000, 4000], [3000, 5000]])), 6000.0, 0.001)
	assert_almost_eq(MarchRoute.length_from(Vector2i(0, 0), _v([[3000, 4000], [3000, 5000]])), 6000.0, 0.001)
	assert_eq(MarchRoute.length_m([]), 0.0)


## A walk of 4000 m from (0, 0) along (3000, 4000) → (3000, 9000): 5000 m to the
## first point, so it stops 4/5 of the way: (2400, 3200).
func test_a_walk_stops_partway_along_its_first_leg() -> void:
	var out := MarchRoute.walk(Vector2i(0, 0), _v([[3000, 4000], [3000, 9000]]), 4000)
	assert_eq(out["at"], Vector2i(2400, 3200))
	assert_eq(out["path"], _v([[3000, 4000], [3000, 9000]]), "the point ahead is not yet passed")
	assert_eq(out["passed"], [])


## 7000 m: 5000 m to (3000, 4000), then 2000 m on toward (3000, 9000): (3000, 6000).
func test_a_walk_turns_the_corner_and_drops_the_point_it_passed() -> void:
	var out := MarchRoute.walk(Vector2i(0, 0), _v([[3000, 4000], [3000, 9000]]), 7000)
	assert_eq(out["at"], Vector2i(3000, 6000))
	assert_eq(out["path"], _v([[3000, 9000]]))
	assert_eq(out["passed"], _v([[3000, 4000]]))


func test_a_walk_that_lands_on_a_point_drops_it_and_stands_on_it() -> void:
	var out := MarchRoute.walk(Vector2i(0, 0), _v([[3000, 4000], [3000, 9000]]), 5000)
	assert_eq(out["at"], Vector2i(3000, 4000))
	assert_eq(out["path"], _v([[3000, 9000]]))


func test_a_walk_never_changes_the_path_it_was_given() -> void:
	var path := _v([[3000, 4000], [3000, 9000]])
	MarchRoute.walk(Vector2i(0, 0), path, 7000)
	assert_eq(path, _v([[3000, 4000], [3000, 9000]]))


## The pair form the save keeps ([[x, y], ...] whole numbers) and back.
func test_the_saved_form_is_pairs_of_whole_metres() -> void:
	var pts := _v([[1, 2], [3, 4]])
	var saved := MarchRoute.to_pairs(pts)
	assert_eq(saved, [[1, 2], [3, 4]])
	assert_true(saved[0][0] is int)
	assert_eq(MarchRoute.from_pairs([[1.0, 2.0], [3, 4]]), pts, "a JSON float reads back whole")


## The leg a point lies nearest, for a waypoint inserted where the line was
## grabbed: (1600, 500) is nearest the second leg's samples.
func test_the_nearest_leg_names_where_a_grabbed_waypoint_goes() -> void:
	var pts := _v([[0, 0], [1000, 1000], [2000, 0]])
	assert_eq(MarchRoute.nearest_leg(pts, 1000, Vector2(1600, 500)), 1)
	assert_eq(MarchRoute.nearest_leg(pts, 1000, Vector2(300, 400)), 0)
