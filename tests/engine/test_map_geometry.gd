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
