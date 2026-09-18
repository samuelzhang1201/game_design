extends GutTest
## Map3DBorders: the 3D map's kingdom borders and province seams, from the
## same live outlines the 2D map draws (MapOwnership), laid on the ground as
## ribbons the border shader widens to a constant screen width.

const WORLD := {"m_per_px": 50.0, "pack_origin": [0.0, 0.0], "pack_px": [2560, 929]}


func test_a_ribbon_is_two_vertices_a_point_with_opposite_sides() -> void:
	# An L: east 10 m, then south 10 m, on ground at y = 7.
	var line := PackedVector2Array([Vector2(0, 0), Vector2(10, 0), Vector2(10, 10)])
	var arrays := Map3DBorders.ribbon_arrays([line], func(_xz: Vector2) -> float: return 7.0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var sides: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_eq(verts.size(), 6, "two per point")
	assert_eq(verts[0], Vector3(0, 7, 0))
	assert_eq(verts[1], Vector3(0, 7, 0))
	assert_eq(idx.size(), 12, "two triangles per segment")
	# Heading east, the side is north/south; the pair points opposite ways.
	assert_almost_eq(absf(sides[0].z), 1.0, 0.0001)
	assert_almost_eq(sides[0].x, 0.0, 0.0001)
	assert_eq(sides[1], -sides[0])
	# The corner's side is the mitre of east and south, still unit-length.
	assert_almost_eq(sides[2].length(), 1.0, 0.0001)
	assert_almost_eq(absf(sides[2].x), absf(sides[2].z), 0.0001)
	# u is the arc length along the line, v the side.
	assert_almost_eq(uvs[4].x, 20.0, 0.0001)
	assert_eq(uvs[0].y, 0.0)
	assert_eq(uvs[1].y, 1.0)


func test_lines_are_separate_strips() -> void:
	var a := PackedVector2Array([Vector2(0, 0), Vector2(5, 0)])
	var b := PackedVector2Array([Vector2(0, 9), Vector2(5, 9)])
	var arrays := Map3DBorders.ribbon_arrays([a, b], func(_xz: Vector2) -> float: return 0.0)
	var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	assert_eq(idx.size(), 12, "one segment each, none joining them")
	for i in range(6, 12):
		assert_true(idx[i] >= 4, "the second strip only indexes its own vertices")


func test_an_empty_set_makes_no_arrays() -> void:
	assert_true(Map3DBorders.ribbon_arrays([], func(_xz: Vector2) -> float: return 0.0).is_empty())


func test_kingdom_lines_follow_the_live_outline_in_world_metres() -> void:
	Game.start_campaign(42)
	var code := Game.data.resolve_realm("player_realm")
	var lines: Array = Map3DBorders.kingdom_lines(Game.data, Game.state, WORLD, code, 100.0)
	var loops: Array = MapOwnership.outline_of(Game.data, Game.state, code)
	assert_eq(lines.size(), loops.size(), "one line per ring")
	var ring: PackedVector2Array = lines[0]
	assert_eq(ring[0], ring[ring.size() - 1], "a ring is closed")
	for i in range(1, ring.size()):
		assert_true(ring[i - 1].distance_to(ring[i]) <= 100.0 + 0.001, "resampled to the step")
	# It lies on the pack outline scaled to metres (origin 0, 50 m per px).
	var first: PackedVector2Array = loops[0]
	var near := INF
	for p in ring:
		near = minf(near, p.distance_to(first[0] * 50.0))
	assert_lt(near, 1.0, "passes through the outline's own corner")


func test_seam_lines_cover_every_kingdoms_seams() -> void:
	Game.start_campaign(42)
	var expected := 0
	for code: String in Game.data.kingdoms:
		expected += MapOwnership.seams_of(Game.data, Game.state, code).size()
	assert_eq(Map3DBorders.seam_lines(Game.data, Game.state, WORLD, 100.0).size(), expected)
	assert_gt(expected, 0)
