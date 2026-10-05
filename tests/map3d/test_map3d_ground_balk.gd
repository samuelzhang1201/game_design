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
	assert_string_contains(out, "float wk = weights[k] * (rk[k] >= 0.0 ? rcov : 1.0 - rcov)")
	assert_string_contains(out, "color_map = mix(color_map, rcm / rcw, field_rim)", "the field's tint weighted alike")
	assert_lt(out.find("if (field_rim > 0.0 && bilerp)"), out.find("vec3 base_albedo ="), "before the tint reads mat")
	assert_lt(out.find("fwidth(rd)"), out.find("if (field_rim > 0.0"), "derivatives outside every branch")
