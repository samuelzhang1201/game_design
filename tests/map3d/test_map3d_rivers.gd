extends GutTest
## Map3DRivers: rivers.json -> one ribbon mesh. Each point becomes two
## vertices at the centreline, their NORMAL the side to widen toward (the
## shader widens them), UV.x across (0 / 1), UV.y metres along, UV2 (width,
## mouth), COLOR.a the end fade (fix round 1).

const JSON_TEXT := '{"rivers": [{"code": "a", "points": [[0, 0, 10, 6, 0], [100, 0, 9, 40, 0], [200, 0, 8, 80, 1]]}]}'


func test_parse_reads_positions_widths_and_mouth() -> void:
	var courses := Map3DRivers.parse(JSON_TEXT)
	assert_eq(courses.size(), 1)
	var c: Dictionary = courses[0]
	assert_eq((c["pos"] as PackedVector3Array)[1], Vector3(100, 9, 0))
	assert_eq((c["width"] as PackedFloat32Array)[2], 80.0)
	assert_eq((c["mouth"] as PackedFloat32Array)[2], 1.0)
	assert_true(c["true_mouth"], "the only strip carries the river's own last sample")


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
## tens of metres between two consecutive samples (Task 6 review). Fix round
## 1: the split must stay CONTINUOUS — the point where the rise crosses the
## threshold ends the strip before it AND starts the strip after it, so the
## two strips share that exact vertex and no length of the river is lost.
func test_a_big_rise_splits_the_course_but_stays_continuous() -> void:
	var text := '{"rivers": [{"code": "b", "points": ' \
		+ '[[0, 0, 10, 6, 0], [50, 0, 9, 10, 0], [60, 0, 40, 8, 0], [120, 0, 38, 20, 1]]}]}'
	var courses := Map3DRivers.parse(text)
	assert_eq(courses.size(), 2, "one split, two strips")
	var first: PackedVector3Array = courses[0]["pos"]
	var second: PackedVector3Array = courses[1]["pos"]
	assert_eq(first.size(), 3, "points 0, 1, 2 — the strip ends ON the jump point")
	assert_eq(first[2], Vector3(60, 40, 0))
	assert_eq(second.size(), 2, "the jump point again, then the rest of the river")
	assert_eq(second[0], first[2], "the two strips share the split vertex: no gap")
	assert_eq(second[1], Vector3(120, 38, 0))
	assert_eq(courses[1]["code"], "b#2")
	assert_false(courses[0]["true_mouth"])
	assert_true(courses[1]["true_mouth"], "the second strip carries the river's real end")


func test_a_small_rise_does_not_split() -> void:
	var text := '{"rivers": [{"code": "c", "points": ' \
		+ '[[0, 0, 10, 6, 0], [50, 0, 10.5, 6, 0], [100, 0, 11, 6, 1]]}]}'
	assert_eq(Map3DRivers.parse(text).size(), 1)


func test_a_custom_threshold_is_honoured() -> void:
	var text := '{"rivers": [{"code": "d", "points": ' \
		+ '[[0, 0, 10, 6, 0], [50, 0, 10, 6, 0], [100, 0, 11, 6, 0], [150, 0, 11, 6, 1]]}]}'
	assert_eq(Map3DRivers.parse(text).size(), 1, "1m rise under the default 10m threshold")
	var split := Map3DRivers.parse(text, 0.5)
	assert_eq(split.size(), 2, "but over a stricter 0.5m threshold")
	assert_eq((split[0]["pos"] as PackedVector3Array)[-1], (split[1]["pos"] as PackedVector3Array)[0],
		"still continuous")


## Two genuine lake jumps back to back (the pack's own perstowbo has exactly
## this shape at threshold 10.0): every strip must still be at least 2
## points — continuity means a split can never leave a 1-point orphan to
## drop, which is what used to tear a ~170m gap in the river.
func test_back_to_back_splits_keep_continuity_with_no_one_point_strips() -> void:
	var text := '{"rivers": [{"code": "e", "points": ' \
		+ '[[0, 0, 5.3, 6, 0], [50, 0, 19.5, 6, 0], [100, 0, 107.45, 6, 0], [150, 0, 113.46, 6, 1]]}]}'
	var courses := Map3DRivers.parse(text)
	assert_eq(courses.size(), 3)
	for c: Dictionary in courses:
		assert_gte((c["pos"] as PackedVector3Array).size(), 2, "never a 1-point strip")
	assert_eq((courses[0]["pos"] as PackedVector3Array)[-1], (courses[1]["pos"] as PackedVector3Array)[0])
	assert_eq((courses[1]["pos"] as PackedVector3Array)[-1], (courses[2]["pos"] as PackedVector3Array)[0])
	assert_false(courses[0]["true_mouth"])
	assert_false(courses[1]["true_mouth"])
	assert_true(courses[2]["true_mouth"])


## The end-fade channel (COLOR.a): 0 at every cut (a strip's own start, since
## even the river's true source fades the same way, and a non-mouth strip's
## end), full at the true mouth even though it is also a strip's "end".
func test_the_end_fade_is_zero_at_every_cut_and_one_at_the_true_mouth() -> void:
	var text := '{"rivers": [{"code": "f", "points": ' \
		+ '[[0, 0, 10, 6, 0], [50, 0, 10, 6, 0], [100, 0, 10, 6, 0], [150, 0, 50, 6, 0], ' \
		+ '[200, 0, 50, 6, 0], [250, 0, 50, 6, 1]]}]}'
	var courses := Map3DRivers.parse(text, 5.0)
	assert_eq(courses.size(), 2)
	var arrays := Map3DRivers.ribbon_arrays(courses, 20.0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	# Course 0: points at index 0,1,2,3 (4 points, 8 vertices) — the strip
	# ends ON the jump point (150, 50).
	assert_almost_eq(colors[0].a, 0.0, 0.001, "the true source fades in from nothing")
	assert_almost_eq(colors[6].a, 0.0, 0.001, "the cut end (the jump point) fades to nothing")
	# Course 1: points at index 3,4,5 (3 points, 6 vertices), starting at
	# vertex 8 (course 0 drew 4 points * 2).
	assert_almost_eq(colors[8].a, 0.0, 0.001, "the cut start (the same jump point) fades in")
	assert_almost_eq(colors[12].a, 1.0, 0.001, "the true mouth never fades")


func test_a_zero_length_tangent_keeps_a_sane_side_vector() -> void:
	var text := '{"rivers": [{"code": "g", "points": ' \
		+ '[[10, 10, 5, 6, 0], [10, 10, 5, 6, 0], [50, 10, 5, 6, 1]]}]}'
	var arrays := Map3DRivers.ribbon_arrays(Map3DRivers.parse(text))
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	for n: Vector3 in normals:
		assert_false(is_nan(n.x) or is_nan(n.y) or is_nan(n.z), "no NaN from a coincident pair")
