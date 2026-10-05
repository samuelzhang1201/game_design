extends GutTest
## Map3DGroundEdge (visual review 2026-10-05, lever ③): the fragment's vertex
## coordinates are bent by a fine noise before Terrain3D looks its vertices
## up, so a field's edge wanders instead of stepping every 20 m. These hold
## the line it rewrites and that it rides on the tint patch's noise.

const SAMPLE := "shader_type spatial;\nrender_mode blend_mix;\n\nvoid fragment() {\n" \
	+ Map3DGroundEdge.UV_LINE + "\tvec2 uv2 = UV2;\n\tvec3 macrov = vec3(1.0);\n\t" \
	+ Map3DGroundTint.ALBEDO_LINE + "\n}\n"


func test_the_patch_bends_the_vertex_coordinates() -> void:
	var out := Map3DGroundEdge.patch(Map3DGroundTint.patch(SAMPLE))
	for u: String in ["uniform float edge_warp_m", "uniform float edge_warp_wave_m",
			"uniform float edge_warp_fine", "uniform float edge_warp_far_m", "uniform float edge_fray_m"]:
		assert_string_contains(out, u)
	assert_string_contains(out, "uv += (ew * edge_warp_m + fw * fk)")
	assert_lt(out.find("uniform float edge_warp_m"), out.find("float wx_noise("),
		"its uniforms stand with the tint's, ahead of the code")
	assert_lt(out.find("float wx_noise("), out.find("uv += (ew"), "the noise it calls is declared first")


func test_the_patch_is_kept_once() -> void:
	var once := Map3DGroundEdge.patch(Map3DGroundTint.patch(SAMPLE))
	assert_eq(Map3DGroundEdge.patch(once), once, "patching twice changes nothing")
	assert_eq(once.count("// Map3DGroundEdge:"), 2, "one uniform block, one stage")


## Without the tint's patch (no wx_noise) or without the line, the code is
## left as it is: the ground keeps Terrain3D's own edges.
func test_no_tint_or_no_line_leaves_the_code() -> void:
	assert_eq(Map3DGroundEdge.patch(SAMPLE), SAMPLE)
	var no_line := Map3DGroundTint.patch(SAMPLE.replace(Map3DGroundEdge.UV_LINE, ""))
	assert_eq(Map3DGroundEdge.patch(no_line), no_line)
