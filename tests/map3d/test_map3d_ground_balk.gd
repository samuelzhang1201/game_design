extends GutTest
## Map3DGroundBalk (visual review 2026-10-05): the fields' balks and hedges
## drawn along bake/field_edges.png, spliced with the tint's stages.

const SAMPLE := "shader_type spatial;\nrender_mode blend_mix;\n\nvoid fragment() {\n" \
	+ Map3DGroundEdge.UV_LINE + "\tvec3 macrov = vec3(1.0);\n\t" + Map3DGroundTint.ALBEDO_LINE + "\n}\n"


func test_the_tint_patch_carries_the_balks() -> void:
	var out := Map3DGroundTint.patch(SAMPLE)
	assert_string_contains(out, "uniform highp sampler2D field_edges")
	assert_string_contains(out, "texture(field_edges, buv)")
	assert_lt(out.find("texture(field_map"), out.find("texture(field_edges"), "after the fields' own colour")


## The line is looked up where the ground was (the edge warp's uv), so it runs
## along the drawn rim.
func test_the_balk_reads_the_warped_position() -> void:
	assert_string_contains(Map3DGroundBalk.STAGE, "(uv - UV) * _vertex_spacing")
