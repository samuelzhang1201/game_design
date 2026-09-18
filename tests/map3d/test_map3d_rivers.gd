extends GutTest
## Map3DRivers: rivers.json -> one ribbon mesh. Each point becomes two
## vertices at the centreline, their NORMAL the side to widen toward (the
## shader widens them), UV.x across (0 / 1), UV.y metres along, UV2 (width,
## mouth).

const JSON_TEXT := '{"rivers": [{"code": "a", "points": [[0, 0, 10, 6, 0], [100, 0, 9, 40, 0], [200, 0, 8, 80, 1]]}]}'


func test_parse_reads_positions_widths_and_mouth() -> void:
	var courses := Map3DRivers.parse(JSON_TEXT)
	assert_eq(courses.size(), 1)
	var c: Dictionary = courses[0]
	assert_eq((c["pos"] as PackedVector3Array)[1], Vector3(100, 9, 0))
	assert_eq((c["width"] as PackedFloat32Array)[2], 80.0)
	assert_eq((c["mouth"] as PackedFloat32Array)[2], 1.0)


func test_the_ribbon_pairs_every_point() -> void:
	var arrays := Map3DRivers.ribbon_arrays(Map3DRivers.parse(JSON_TEXT))
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	assert_eq(verts.size(), 6)
	assert_eq(verts[0], verts[1], "both at the centreline")
	# Flowing +X: the sides are -Z and +Z.
	assert_almost_eq(normals[0].z, -1.0, 0.0001)
	assert_almost_eq(normals[1].z, 1.0, 0.0001)
	assert_eq(uv[0].x, 0.0)
	assert_eq(uv[1].x, 1.0)
	assert_almost_eq(uv[4].y, 200.0, 0.001, "metres along")
	assert_eq(uv2[2], Vector2(40, 0))
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 12, "two quads")


func test_bad_json_is_no_rivers() -> void:
	assert_eq(Map3DRivers.parse("not json").size(), 0)
	assert_eq(Map3DRivers.ribbon_arrays([]).size(), 0)


## A river leaving (or entering) a lake: the bake's water line jumps up by
## tens of metres between two consecutive samples (Task 6 review). Drawing
## that as one strip would stand a vertical wall of water between the two
## levels, so parse() breaks the course there instead — a short degenerate
## fragment (a single point either side of consecutive splits) is dropped.
func test_a_big_rise_splits_the_course_instead_of_a_wall() -> void:
	var text := '{"rivers": [{"code": "b", "points": ' \
		+ '[[0, 0, 10, 6, 0], [50, 0, 9, 10, 0], [60, 0, 40, 8, 0], [120, 0, 38, 20, 1]]}]}'
	var courses := Map3DRivers.parse(text)
	assert_eq(courses.size(), 2, "one split, two strips")
	assert_eq((courses[0]["pos"] as PackedVector3Array).size(), 2)
	assert_eq((courses[0]["pos"] as PackedVector3Array)[1], Vector3(50, 9, 0))
	assert_eq((courses[1]["pos"] as PackedVector3Array).size(), 2)
	assert_eq((courses[1]["pos"] as PackedVector3Array)[0], Vector3(60, 40, 0))
	assert_eq(courses[1]["code"], "b#2")


func test_a_small_rise_does_not_split() -> void:
	var text := '{"rivers": [{"code": "c", "points": ' \
		+ '[[0, 0, 10, 6, 0], [50, 0, 10.5, 6, 0], [100, 0, 11, 6, 1]]}]}'
	assert_eq(Map3DRivers.parse(text).size(), 1)


func test_a_custom_threshold_is_honoured() -> void:
	var text := '{"rivers": [{"code": "d", "points": ' \
		+ '[[0, 0, 10, 6, 0], [50, 0, 10, 6, 0], [100, 0, 11, 6, 0], [150, 0, 11, 6, 1]]}]}'
	assert_eq(Map3DRivers.parse(text).size(), 1, "1m rise under the default 2m threshold")
	assert_eq(Map3DRivers.parse(text, 0.5).size(), 2, "but over a stricter 0.5m threshold")
