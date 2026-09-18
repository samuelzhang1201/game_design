extends GutTest
## Map3DRivers: rivers.json -> one ribbon mesh. Each point becomes two
## vertices at the centreline, their NORMAL the side to widen toward (the
## shader widens them), UV.x across (0 / 1), UV.y metres along, UV2 (width,
## mouth), COLOR.a the end fade (fix round 1). clear_terrain (fix round 3)
## lifts a point whose flat cross-section would otherwise dip below the
## real terrain at its centre or either edge.

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


## Fix round 3: a tributary now ends ON its main river's course instead of
## short of it, but the bake only sets mouth > 0 on a course that truly
## reaches the sea — a joined tributary's mouth stays 0.0 all the way to its
## last sample. That join point must NOT read as a true mouth (which would
## skip the end fade and leave it at full opacity, a bright sliver poking
## into the river it joins): it has to fade out like any other cut end.
func test_a_joined_tributary_end_is_not_a_true_mouth_and_fades() -> void:
	var text := '{"rivers": [{"code": "h", "points": ' \
		+ '[[0, 0, 10, 6, 0], [100, 0, 10, 6, 0], [200, 0, 10, 6, 0]]}]}'
	var courses := Map3DRivers.parse(text)
	assert_eq(courses.size(), 1)
	assert_false(courses[0]["true_mouth"],
		"mouth is 0 throughout: this course joins another river, it never reaches the sea")
	var arrays := Map3DRivers.ribbon_arrays(courses, 50.0)
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_almost_eq(colors[-1].a, 0.0, 0.001, "the joined end fades out instead of staying at full opacity")


## A river whose LAST sample's mouth field is > 0 is still read as a true
## mouth (unchanged behaviour, guards against a regression where the fix
## above over-corrects and fades every ending).
func test_a_sea_ending_river_is_still_a_true_mouth() -> void:
	var courses := Map3DRivers.parse(JSON_TEXT)
	assert_true(courses[0]["true_mouth"])


## Fix round 3: the ribbon is flat across its width and built only at the
## bake's own sparse points, but the ground under it is not — on a steep,
## narrow-sampled tributary the terrain can clear the centreline while
## still rising above the water at one edge (measured on knutshambe: centre
## +3.25m, its own right edge -0.38m at the same point). clear_terrain lifts
## a point to clear the highest of its centre/left/right ground samples.
func test_clear_terrain_lifts_a_point_whose_edge_dips_below_ground() -> void:
	var text := '{"rivers": [{"code": "i", "points": ' \
		+ '[[0, 0, 10, 20, 0], [100, 0, 10, 20, 1]]}]}'
	var courses := Map3DRivers.parse(text)
	# Flat ground at 0 except a ridge to 15 right under the first point's
	# own RIGHT edge (side is -Z here; a 20m-wide river reaches 10m either
	# way) — well above the river's own baked 10m water level.
	var ground := func(xz: Vector2) -> float:
		return 15.0 if absf(xz.x) < 1.0 and xz.y < 0.0 else 0.0
	var cleared := Map3DRivers.clear_terrain(courses, ground, 2.0)
	var pos: PackedVector3Array = cleared[0]["pos"]
	assert_almost_eq(pos[0].y, 17.0, 0.01, "lifted to clear the ridge under its own edge, plus the margin")
	assert_almost_eq(pos[1].y, 10.0, 0.01, "flat ground under the second point: its baked height already clears it")


func test_clear_terrain_is_a_no_op_without_a_height_fn() -> void:
	var courses := Map3DRivers.parse(JSON_TEXT)
	assert_same(Map3DRivers.clear_terrain(courses, Callable(), 5.0), courses)
