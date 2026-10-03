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
	assert_string_contains(out, "mix(base_albedo, tint_linear, tint_mix * tint.a)")


## The field map (owner 2026-09-19): furrows along each estate's strips up
## close, the crops' colour eased back far out.
## Owner 2026-10-04 (拉近尽头manor交界处会有很明显的锯齿形): a manor's edge is
## not the index's 50 m staircase — four texels weighed, the meeting line
## anti-aliased over a screen px.
func test_the_manor_edge_is_smoothed_not_stepped() -> void:
	var out := Map3DGroundTint.patch(SAMPLE)
	assert_string_contains(out, "mt_w[i] = ")
	assert_string_contains(out, "fwidth(d)")
	assert_false(out.contains("ivec2 tint_px = ivec2(floor("), "no single nearest texel any more")

func test_the_patch_reads_the_field_map() -> void:
	var out := Map3DGroundTint.patch(SAMPLE)
	for u: String in ["uniform highp sampler2D field_map", "uniform float furrow_m",
			"uniform float furrow_depth", "uniform float field_fade",
			"uniform float field_fade_near_m", "uniform float field_fade_far_m",
			"uniform float field_m_per_texel"]:
		assert_string_contains(out, u)
	assert_string_contains(out, "texture(field_map", "sampled, filtered, at the ground point")
	assert_string_contains(out, "fwidth(", "the furrows fade before they alias")


## The built world's terrain material is shared by every view that loads it
## (the council screen's, then the court's): the second must find the code
## already patched and keep it, not take the patch for a failure and switch
## the tint off (the owner saw no tint in the game, 2026-09-19).
func test_patched_code_is_patched_already() -> void:
	var once := Map3DGroundTint.patch(SAMPLE)
	assert_true(Map3DGroundTint.is_patched(once))
	assert_false(Map3DGroundTint.is_patched(SAMPLE))
	assert_eq(Map3DGroundTint.patch(once), once, "patching twice changes nothing")


func test_code_without_the_albedo_line_is_not_patched() -> void:
	assert_eq(Map3DGroundTint.patch("shader_type spatial;\nvoid fragment() {}\n"), "")


## The HEIGHTS heat ramp (owner 2026-09-19, spec 2026-09-19-map3d-heights):
## the ground's world height mixed toward the ground look's heat_ramp.
func test_the_patch_carries_the_heat_ramp() -> void:
	var code := "shader_type spatial;\nrender_mode blend_mix;\nvoid fragment() {\n\t" \
		+ Map3DGroundTint.ALBEDO_LINE + "\n}\n"
	var out := Map3DGroundTint.patch(code)
	assert_string_contains(out, "uniform float heat_mix")
	assert_string_contains(out, "uniform vec4 heat_c5")
	assert_string_contains(out, "heat_mix > 0.0")


## The heat stops arrive as the palette's raw sRGB (a Color uniform passes
## straight through under GL Compatibility; a source_color hint left them
## unconverted and the lowland read a washed mint, Task 7): the ramp is blended
## in sRGB like the 2D map and turned linear in the shader, as the LUT is.
func test_the_heat_ramp_is_turned_linear_in_the_shader() -> void:
	var code := "shader_type spatial;\nrender_mode blend_mix;\nvoid fragment() {\n\t" \
		+ Map3DGroundTint.ALBEDO_LINE + "\n}\n"
	var out := Map3DGroundTint.patch(code)
	assert_false(out.contains("heat_c0 : source_color"), "no source_color on the stops")
	assert_string_contains(out, "pow((heat + 0.055) / 1.055, vec3(2.4))")


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
	assert_ne(Map3DGroundTint.patch(Map3DGroundTint.patch(shader.code)), "", "a second view reads the patched code and keeps the tint")
