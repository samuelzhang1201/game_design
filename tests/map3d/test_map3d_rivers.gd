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


## Fix round 4: a tributary ending ON a main river fades over that river's
## LOCAL half-width, not the fixed end fade — full strength at the bank,
## gone at the centreline. Main river "m" runs along x = 0 with width 40
## (half-width 20); tributary "t" comes in from +x and ends at (0, 50).
const JOIN_TEXT := '{"rivers": [' \
	+ '{"code": "m", "points": [[0, 0, 10, 40, 0], [0, 100, 10, 40, 1]]}, ' \
	+ '{"code": "t", "points": [[200, 50, 20, 10, 0], [100, 50, 15, 10, 0], [0, 50, 10, 10, 0]]}]}'


func test_a_joined_end_fades_over_the_main_rivers_half_width() -> void:
	var courses := Map3DRivers.parse(JOIN_TEXT)
	var t: Dictionary = courses[1]
	assert_eq(t["code"], "t")
	assert_almost_eq(float(t["end_fade_m"]), 20.0, 0.001, "half the main river's width at the tip")
	# A sample is inserted at the bank, 20 m before the tip.
	var pos: PackedVector3Array = t["pos"]
	assert_eq(pos.size(), 4)
	assert_almost_eq(pos[2].x, 20.0, 0.001)
	assert_almost_eq(pos[2].y, 11.0, 0.001, "height interpolated between 15 and 10")
	var colors: PackedColorArray = Map3DRivers.ribbon_arrays([t], 80.0)[Mesh.ARRAY_COLOR]
	assert_almost_eq(colors[4].a, 1.0, 0.001, "full strength at the main river's bank")
	assert_almost_eq(colors[6].a, 0.0, 0.001, "gone at the main river's centreline")
	assert_almost_eq(colors[0].a, 0.0, 0.001, "the source still fades in")


func test_a_source_still_fades_over_end_fade() -> void:
	var courses := Map3DRivers.parse(JOIN_TEXT)
	var colors: PackedColorArray = Map3DRivers.ribbon_arrays([courses[1]], 80.0)[Mesh.ARRAY_COLOR]
	# The second sample is 100 m from the source: past the 80 m fade in.
	assert_almost_eq(colors[2].a, 1.0, 0.001)
	var short := Map3DRivers.ribbon_arrays([courses[1]], 200.0)[Mesh.ARRAY_COLOR] as PackedColorArray
	assert_almost_eq(short[2].a, 0.5, 0.001, "the source fade still follows end_fade_m")


func test_a_sea_mouth_does_not_fade_and_gets_no_join_fade() -> void:
	var courses := Map3DRivers.parse(JOIN_TEXT)
	var m: Dictionary = courses[0]
	assert_true(m["true_mouth"])
	assert_false(m.has("end_fade_m"))
	var colors: PackedColorArray = Map3DRivers.ribbon_arrays([m], 80.0)[Mesh.ARRAY_COLOR]
	assert_almost_eq(colors[-1].a, 1.0, 0.001)


func test_a_joined_end_far_from_any_river_keeps_the_end_fade() -> void:
	var text := '{"rivers": [' \
		+ '{"code": "m", "points": [[0, 0, 10, 40, 0], [0, 100, 10, 40, 1]]}, ' \
		+ '{"code": "t", "points": [[300, 50, 20, 10, 0], [200, 50, 10, 10, 0]]}]}'
	var t: Dictionary = Map3DRivers.parse(text)[1]
	assert_false(t.has("end_fade_m"), "200 m off a 40 m river is more than twice its width")


func test_clear_terrain_keeps_the_join_fade() -> void:
	var ground := func(_xz: Vector2) -> float: return 0.0
	var cleared := Map3DRivers.clear_terrain(Map3DRivers.parse(JOIN_TEXT), ground, 1.0)
	assert_almost_eq(float(cleared[1]["end_fade_m"]), 20.0, 0.001)


# --- densify (final review, owner 2026-09-18) ----------------------------------

const BEND_TEXT := '{"rivers": [{"code": "b", "points": [[0, 0, 10, 6, 0], [50, 0, 9, 10, 0], ' \
	+ '[90, 30, 8, 14, 0], [100, 80, 7, 20, 1]]}]}'


func test_densify_steps_every_segment_and_keeps_the_samples_on_the_curve() -> void:
	var c: Dictionary = Map3DRivers.parse(BEND_TEXT)[0]
	var orig: PackedVector3Array = c["pos"]
	var d := Map3DRivers.densify(c, 12.0)
	var pos: PackedVector3Array = d["pos"]
	# Segments 50, 50, 50.99 m -> ceil(/12) = 5, 5, 5 pieces, plus the end.
	assert_eq(pos.size(), 16)
	assert_eq((d["width"] as PackedFloat32Array).size(), 16)
	assert_eq((d["mouth"] as PackedFloat32Array).size(), 16)
	for k in orig.size():
		assert_eq(pos[k * 5], orig[k], "sample %d stays exactly on the curve" % k)
	for i in range(1, pos.size()):
		var step := Vector2(pos[i].x - pos[i - 1].x, pos[i].z - pos[i - 1].z).length()
		assert_true(step <= 12.5, "no gap over the step (got %.2f at %d)" % [step, i])
	# Width and height are linear between samples; the curve bends the path.
	assert_almost_eq((d["width"] as PackedFloat32Array)[7], lerpf(10.0, 14.0, 0.4), 0.001)
	assert_almost_eq(pos[7].y, lerpf(9.0, 8.0, 0.4), 0.001)
	var chord := Vector2(50, 0).lerp(Vector2(90, 30), 0.4)
	assert_gt(Vector2(pos[7].x, pos[7].z).distance_to(chord), 0.5, "the ribbon bends, not a ruled chord")
	assert_true(d["true_mouth"], "the course's own keys are kept")


func test_a_densified_ribbon_keeps_its_end_fades() -> void:
	var courses := Map3DRivers.parse(BEND_TEXT)
	var arrays := Map3DRivers.ribbon_arrays(courses, 20.0, 12.0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(verts.size(), 32, "two vertices per densified point")
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 15 * 6)
	assert_almost_eq(colors[0].a, 0.0, 0.001, "the source still fades in")
	assert_almost_eq(colors[2].a, 0.5, 0.02, "about 10 m of arc (the curve bends) of a 20 m fade")
	assert_almost_eq(colors[-1].a, 1.0, 0.001, "the true mouth never fades")


func test_a_densified_joined_end_still_fades_over_the_main_rivers_half_width() -> void:
	var t: Dictionary = Map3DRivers.parse(JOIN_TEXT)[1]
	var colors: PackedColorArray = Map3DRivers.ribbon_arrays([t], 80.0, 5.0)[Mesh.ARRAY_COLOR]
	assert_almost_eq(colors[-1].a, 0.0, 0.001, "gone at the main river's centreline")
	var pos: PackedVector3Array = Map3DRivers.densify(t, 5.0)["pos"]
	var bank := -1
	for i in pos.size():
		if is_equal_approx(pos[i].x, 20.0) and is_equal_approx(pos[i].z, (t["pos"] as PackedVector3Array)[2].z):
			bank = i
	assert_gt(bank, -1, "the inserted bank sample is kept")
	assert_almost_eq(colors[bank * 2].a, 1.0, 0.001, "full strength at the bank")


func test_split_strips_still_share_their_cut_vertex_when_densified() -> void:
	var text := '{"rivers": [{"code": "f", "points": ' \
		+ '[[0, 0, 10, 6, 0], [50, 0, 10, 6, 0], [100, 0, 10, 6, 0], [150, 0, 50, 6, 0], ' \
		+ '[200, 0, 50, 6, 0], [250, 0, 50, 6, 1]]}]}'
	var courses := Map3DRivers.parse(text, 5.0)
	var a: PackedVector3Array = Map3DRivers.densify(courses[0], 12.0)["pos"]
	var b: PackedVector3Array = Map3DRivers.densify(courses[1], 12.0)["pos"]
	assert_eq(a[-1], b[0], "the cut vertex is shared")


# --- the sea mouth's run-out (owner 2026-10-05: a square stub on the sand) -----

## A true mouth is clipped to the land, so it stopped on the beach short of
## the sea's water line. It runs on past its last sample along its final
## direction by mouth_extend_w × its local width, at the sea's water height:
## whole to its halfway point (so it reaches the waterline whole, where the
## shader hands it to the sea), then fading to nothing at its tip.
func test_a_true_mouth_runs_on_into_the_sea_and_fades_out() -> void:
	# Flows +X; the last sample sits at x 200, water 8, width 80.
	var arrays := Map3DRivers.ribbon_arrays(Map3DRivers.parse(JSON_TEXT), 20.0, 0.0, 1.0, 5.0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var uv2: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	assert_eq(verts.size(), 10, "two more point pairs past the mouth")
	assert_eq((arrays[Mesh.ARRAY_INDEX] as PackedInt32Array).size(), 24, "four quads")
	assert_almost_eq(colors[4].a, 1.0, 0.001, "full strength at the last sample")
	assert_almost_eq(verts[6].x, 240.0, 0.001, "halfway")
	assert_almost_eq(verts[6].y, 5.0, 0.001, "at the sea's water height")
	assert_almost_eq(colors[6].a, 1.0, 0.001, "still whole halfway")
	assert_almost_eq(verts[8].x, 280.0, 0.001, "one local width on along the final direction")
	assert_almost_eq(verts[8].z, 0.0, 0.001)
	assert_almost_eq(verts[8].y, 5.0, 0.001)
	assert_almost_eq(colors[8].a, 0.0, 0.001, "gone at the tip")
	assert_almost_eq(colors[9].a, 0.0, 0.001)
	assert_almost_eq(uv[8].y, 280.0, 0.001, "metres along carry on")
	assert_eq(uv2[8], Vector2(80, 1), "its width, and wholly the mouth's water")


func test_the_run_out_follows_the_last_segments_direction() -> void:
	var text := '{"rivers": [{"code": "d", "points": [[0, 0, 10, 10, 0], [30, 40, 6, 20, 1]]}]}'
	var arrays := Map3DRivers.ribbon_arrays(Map3DRivers.parse(text), 20.0, 0.0, 0.5, 5.0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	# Direction (0.6, 0.8), half of a 20 m width = 10 m on to the tip.
	assert_almost_eq(verts[6].x, 36.0, 0.001)
	assert_almost_eq(verts[6].z, 48.0, 0.001)


func test_only_a_true_mouth_runs_on() -> void:
	var courses := Map3DRivers.parse(JOIN_TEXT)
	var joined: Dictionary = courses[1]
	var plain := Map3DRivers.ribbon_arrays([joined], 80.0)
	var asked := Map3DRivers.ribbon_arrays([joined], 80.0, 0.0, 1.0, 5.0)
	assert_eq((asked[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(),
		(plain[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), "a joined end is not extended")
	var mouthless := Map3DRivers.ribbon_arrays(Map3DRivers.parse(JSON_TEXT), 20.0, 0.0, 0.0, 5.0)
	assert_eq((mouthless[Mesh.ARRAY_VERTEX] as PackedVector3Array).size(), 6, "0 = no run-out")


func test_a_densified_mouth_runs_on_from_its_last_sample() -> void:
	var arrays := Map3DRivers.ribbon_arrays(Map3DRivers.parse(BEND_TEXT), 20.0, 12.0, 1.0, 5.0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
	assert_eq(verts.size(), 36, "the densified 16 points and two past the mouth")
	assert_almost_eq(colors[-5].a, 1.0, 0.001, "the last sample keeps full strength")
	assert_almost_eq(colors[-3].a, 1.0, 0.001, "and so does the halfway point")
	assert_almost_eq(colors[-1].a, 0.0, 0.001)
	assert_almost_eq(verts[-1].y, 5.0, 0.001)
	# The final sample (100, 80) and the one before on the curve set the direction.
	assert_almost_eq(verts[-1].z, 80.0 + 20.0 * (verts[-5].z - verts[-7].z) \
		/ Vector2(verts[-5].x - verts[-7].x, verts[-5].z - verts[-7].z).length(), 0.01)


## Godot draws a clockwise triangle as its front face. The ribbon was wound
## the other way, so the camera above saw every triangle's back: on the
## double-sided water Godot then flips the normal, and the river's lit share
## was lit from below (owner 2026-10-05: dark where its mouth turns into the
## mostly lit sea). Widened as the shader widens them, every triangle must
## be clockwise seen from above — its winding normal points down.
func test_the_ribbon_faces_up() -> void:
	var arrays := Map3DRivers.ribbon_arrays(Map3DRivers.parse(BEND_TEXT), 20.0, 12.0, 0.5, 5.0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var index: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	for t in range(0, index.size(), 3):
		var p: Array = []
		for k in 3:
			p.append(verts[index[t + k]] + normals[index[t + k]] * 5.0)
		var wound: Vector3 = ((p[1] as Vector3) - (p[0] as Vector3)).cross((p[2] as Vector3) - (p[0] as Vector3))
		assert_lt(wound.y, 0.0, "triangle %d is clockwise from above" % (t / 3))


## The river's mouth turns into the sea's water by the sea's own uniforms,
## copied by name (Map3DLayerRivers.SEA_WATER): a rename on either side
## would silently leave the river's copy at its default.
func test_every_sea_uniform_the_mouth_copies_exists_on_both_sides() -> void:
	var sea_names: Array = []
	for u: Dictionary in (load("res://scripts/map3d/water_sea.gdshader") as Shader).get_shader_uniform_list():
		sea_names.append(u["name"])
	var river_names: Array = []
	for u: Dictionary in (load("res://scripts/map3d/water_river.gdshader") as Shader).get_shader_uniform_list():
		river_names.append(u["name"])
	var pack := ["pack_origin", "pack_px", "m_per_px", "sea_distance"]
	for k: String in Map3DLayerRivers.SEA_WATER + pack:
		assert_has(sea_names, k, "the sea has %s" % k)
		assert_has(river_names, Map3DLayerRivers.river_name_of(k), "the river has its copy of %s" % k)
