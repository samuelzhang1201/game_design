extends GutTest
## MapGeometry: pure helpers over the map pack's vector data (border loops,
## and later routes/rivers). Points are serialized in the CSVs as
## "x y|x y|..." in native Azgaar map coordinates.

func test_parse_points_reads_space_and_pipe_separated_pairs() -> void:
	var pts := MapGeometry.parse_points("1 2|3.5 4|720.62 69.16")
	assert_eq(pts.size(), 3)
	assert_eq(pts[0], Vector2(1, 2))
	assert_eq(pts[1], Vector2(3.5, 4))
	assert_almost_eq(pts[2].x, 720.62, 0.001)
	assert_almost_eq(pts[2].y, 69.16, 0.001)

func test_parse_points_of_empty_string_is_empty() -> void:
	assert_eq(MapGeometry.parse_points("").size(), 0)

func test_bounds_wraps_every_point() -> void:
	var r := MapGeometry.bounds(PackedVector2Array([Vector2(1, 2), Vector2(3, -1), Vector2(2, 0)]))
	assert_eq(r.position, Vector2(1, -1))
	assert_eq(r.end, Vector2(3, 2))

func test_bounds_of_nothing_is_empty() -> void:
	assert_eq(MapGeometry.bounds(PackedVector2Array()), Rect2())

func test_polyline_length_sums_the_segments() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(3, 4), Vector2(3, 10)])
	assert_almost_eq(MapGeometry.polyline_length(pts), 11.0, 0.0001)
	assert_eq(MapGeometry.polyline_length(PackedVector2Array([Vector2(1, 1)])), 0.0)

func test_distance_to_polyline_is_to_the_nearest_segment() -> void:
	var pts := PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2)])
	assert_almost_eq(MapGeometry.distance_to_polyline(Vector2(1, 1), pts), 1.0, 0.0001,
		"one unit above the first segment (and one left of the second)")
	assert_almost_eq(MapGeometry.distance_to_polyline(Vector2(5, 0), pts), 3.0, 0.0001,
		"past the corner: distance to the corner vertex")
	assert_almost_eq(MapGeometry.distance_to_polyline(Vector2(2, 1), pts), 0.0, 0.0001, "on the line")

func test_distance_to_nothing_is_infinite() -> void:
	assert_eq(MapGeometry.distance_to_polyline(Vector2.ZERO, PackedVector2Array()), INF)

## The uniform cubic B-spline through a closed polygon (Azgaar's
## curveBasisClosed): steps points per vertex, each segment's first point the
## (1, 4, 1)/6 blend of its neighbours, and the curve never leaves the hull.
func test_smooth_closed_is_the_uniform_cubic_b_spline() -> void:
	var square := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10), Vector2(0, 10)])
	var curve := MapGeometry.smooth_closed(square, 4)
	assert_eq(curve.size(), 16)
	# At t = 0 on segment i the point is (P[i-1] + 4 P[i] + P[i+1]) / 6.
	assert_almost_eq(curve[0].x, (0.0 + 4.0 * 0.0 + 10.0) / 6.0, 0.0001)
	assert_almost_eq(curve[0].y, (10.0 + 4.0 * 0.0 + 0.0) / 6.0, 0.0001)
	assert_almost_eq(curve[4].x, (0.0 + 4.0 * 10.0 + 10.0) / 6.0, 0.0001)
	for p in curve:
		assert_true(p.x >= 0.0 and p.x <= 10.0 and p.y >= 0.0 and p.y <= 10.0,
			"%s stays inside the square" % p)
	assert_eq(MapGeometry.smooth_closed(PackedVector2Array([Vector2.ZERO, Vector2.ONE]), 4).size(), 2,
		"too few points: returned as is")
