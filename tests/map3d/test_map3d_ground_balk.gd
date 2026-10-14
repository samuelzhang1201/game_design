extends GutTest
## Map3DGroundBalk (visual review 2026-10-05): the fields' balks and hedges
## drawn along bake/field_edges.png, spliced with the tint's stages.

const SAMPLE := "shader_type spatial;\nrender_mode blend_mix;\n\nvoid fragment() {\n" \
	+ Map3DGroundEdge.UV_LINE + "\tvec3 macrov = vec3(1.0);\n\t" + Map3DGroundTint.ALBEDO_LINE + "\n}\n"


func test_the_tint_patch_carries_the_balks() -> void:
	var out := Map3DGroundTint.patch(SAMPLE)
	assert_string_contains(out, "uniform highp sampler2D field_edges")
	assert_string_contains(out, "texture(field_edges, buv)")
	assert_lt(out.find("texture(field_map"), out.find("texture(field_edges, buv)"), "after the fields' own colour")


## The line is looked up where the ground was (the edge warp's uv), so it runs
## along the drawn rim.
func test_the_balk_reads_the_warped_position() -> void:
	assert_string_contains(Map3DGroundBalk.STAGE, "(uv - UV) * _vertex_spacing")


## The rim per pixel re-runs Terrain3D's own accumulate_material with the
## corners weighted by coverage, before the tint (mat already normalised).
func test_the_rim_reaccumulates_before_the_tint() -> void:
	var out := Map3DGroundTint.patch(SAMPLE)
	assert_string_contains(out, "uniform float field_rim")
	# each corner weighed by the side of the edge the pixel lies on — its own
	# ground's distances plus, the others' minus (fields told apart by the edge
	# map's id, visual review 2026-10-14)
	assert_string_contains(out, "side += weights[j] * (rg[j] == rg[k] ? rk[j] : -rk[j])")
	assert_string_contains(out, "wk[k] = r_mixed ? weights[k] * smoothstep(-raa, raa, side) : weights[k]")
	assert_string_contains(out, "color_map = mix(color_map, rcm / w_all, field_rim)", "the field's tint weighted alike")
	assert_string_contains(out, "strip_ang = (ra[k] - 1.0) / 254.0 * 3.14159265", "the strips take the field's own direction")
	assert_lt(out.find("if (bilerp && field_rim > 0.0)"), out.find("vec3 base_albedo ="), "before the tint reads mat")
	assert_lt(out.find("float strip_ang = -1.0"), out.find("if (strip_ang >= 0.0)"), "declared before the strips read it")
	assert_lt(out.find("fwidth(rd)"), out.find("if (bilerp && field_rim > 0.0)"), "derivatives outside every branch")
