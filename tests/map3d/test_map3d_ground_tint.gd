extends GutTest
## Map3DGroundTint (owner 2026-09-19): the ECONOMY / MANORS colours go into
## Terrain3D's OWN shader, patched at runtime, so the tint is lit by the
## relief and the sun like the ground it colours. The patch rewrites one line
## of the code Terrain3D generates; these tests hold that line to exist.

const SAMPLE := "shader_type spatial;\nrender_mode blend_mix,depth_draw_opaque;\n\nuniform float x = 1.0;\n\nvoid fragment() {\n\tvec3 macrov = vec3(1.0);\n\t" \
	+ Map3DGroundTint.ALBEDO_LINE + "\n}\n"


func test_the_patch_adds_the_tint_uniforms_after_the_render_mode() -> void:
	var out := Map3DGroundTint.patch(SAMPLE)
	for u: String in ["uniform highp sampler2D cell_index", "uniform highp sampler2D cell_lut",
			"uniform float tint_mix", "uniform vec2 pack_origin", "uniform float m_per_px",
			"uniform ivec2 lut_size"]:
		assert_string_contains(out, u)
	assert_gt(out.find("uniform highp sampler2D cell_index"), out.find("render_mode"),
		"after the render mode, where uniforms may stand")
	assert_lt(out.find("uniform highp sampler2D cell_index"), out.find("void fragment"))


func test_the_patch_mixes_the_albedo_toward_the_cells_colour() -> void:
	var out := Map3DGroundTint.patch(SAMPLE)
	assert_false(out.contains(Map3DGroundTint.ALBEDO_LINE), "the plain albedo line is gone")
	assert_string_contains(out, "texelFetch(cell_index")
	assert_string_contains(out, "texelFetch(cell_lut")
	assert_string_contains(out, "ALBEDO = mix(")


## The field map (owner 2026-09-19): furrows along each estate's strips up
## close, the crops' colour eased back far out.
func test_the_patch_reads_the_field_map() -> void:
	var out := Map3DGroundTint.patch(SAMPLE)
	for u: String in ["uniform highp sampler2D field_map", "uniform float furrow_m",
			"uniform float furrow_depth", "uniform float field_fade",
			"uniform float field_fade_near_m", "uniform float field_fade_far_m",
			"uniform float field_m_per_texel"]:
		assert_string_contains(out, u)
	assert_string_contains(out, "texture(field_map", "sampled, filtered, at the ground point")
	assert_string_contains(out, "fwidth(", "the furrows fade before they alias")


func test_code_without_the_albedo_line_is_not_patched() -> void:
	assert_eq(Map3DGroundTint.patch("shader_type spatial;\nvoid fragment() {}\n"), "")


func test_the_lut_is_128_wide() -> void:
	assert_eq(Map3DGroundTint.lut_size(4832), Vector2i(128, 38))
	assert_eq(Map3DGroundTint.lut_size(127), Vector2i(128, 1))
	assert_eq(Map3DGroundTint.lut_size(128), Vector2i(128, 2))


func test_terrain3ds_own_shader_carries_the_albedo_line() -> void:
	var t := Terrain3D.new()
	add_child_autofree(t)
	t.material.shader_override_enabled = true
	await wait_process_frames(1)
	var shader: Shader = t.material.shader_override
	assert_not_null(shader, "Terrain3D fills the override with its generated code")
	if shader == null:
		return
	assert_string_contains(shader.code, Map3DGroundTint.ALBEDO_LINE,
		"the addon's line the patch rewrites — re-check the patch after an addon update")
	assert_ne(Map3DGroundTint.patch(shader.code), "")
