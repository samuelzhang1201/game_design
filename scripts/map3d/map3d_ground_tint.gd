class_name Map3DGroundTint
extends RefCounted
## The ECONOMY / MANORS ground on the 3D map (owner 2026-09-19, spec
## 2026-09-19-map3d-manor-themes-design): Compatibility has no decals, so
## the manor colours go into Terrain3D's OWN shader. Map3DView reads the code
## Terrain3D generates for the build's settings and patch() rewrites its one
## ALBEDO line to mix the ground toward the colour of the manor under it —
## the cell id from the pack's world_cell_index.png (R + G * 256, white is
## water), its colour from a small LUT texture (ManorPalette) — by tint_mix.
## The colour enters the albedo, so the relief, the sun and the cloud shadows
## still light it. Nothing is committed from the addon: an update that
## changes the line makes patch() return "" (tested), and the ground stays
## plain.

const ALBEDO_LINE := "ALBEDO = mat.albedo_height.rgb * color_map.rgb * macrov;"
## The LUT's width in texels: cell id → (id % 128, id / 128).
const LUT_WIDTH := 128

const UNIFORMS := """
// Map3DGroundTint: the ECONOMY / MANORS manor colours (Map3DView sets these).
uniform highp sampler2D cell_index : filter_nearest, repeat_disable;
uniform highp sampler2D cell_lut : filter_nearest, repeat_disable;
uniform float tint_mix = 0.0;
uniform vec2 pack_origin = vec2(0.0);
uniform float m_per_px = 50.0;
uniform ivec2 lut_size = ivec2(128, 1);
"""

const TINTED_ALBEDO := """vec3 base_albedo = mat.albedo_height.rgb * color_map.rgb * macrov;
	vec4 tint = vec4(0.0);
	if (tint_mix > 0.0) {
		ivec2 tint_px = ivec2(floor((v_vertex.xz - pack_origin) / m_per_px));
		ivec2 index_size = textureSize(cell_index, 0);
		if (tint_px.x >= 0 && tint_px.y >= 0 && tint_px.x < index_size.x && tint_px.y < index_size.y) {
			vec3 c = texelFetch(cell_index, tint_px, 0).rgb;
			int id = int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256;
			if (id < lut_size.x * lut_size.y) {
				tint = texelFetch(cell_lut, ivec2(id % lut_size.x, id / lut_size.x), 0);
			}
		}
	}
	// The LUT holds the palette's sRGB bytes, read raw by texelFetch; the
	// albedo is linear (Terrain3D samples its own textures as source_color).
	vec3 tint_linear = mix(tint.rgb / 12.92, pow((tint.rgb + 0.055) / 1.055, vec3(2.4)),
		step(vec3(0.04045), tint.rgb));
	ALBEDO = mix(base_albedo, tint_linear, tint_mix * tint.a);"""


## `code` with the tint uniforms after its render_mode (or shader_type) line
## and its ALBEDO line mixing toward the manor's colour; "" when the line is
## not there.
static func patch(code: String) -> String:
	if not code.contains(ALBEDO_LINE):
		return ""
	var lines := code.split("\n")
	var at := -1
	for i in lines.size():
		var l := lines[i].strip_edges()
		if l.begins_with("render_mode"):
			at = i
			break
		if at < 0 and l.begins_with("shader_type"):
			at = i
	if at < 0:
		return ""
	lines.insert(at + 1, UNIFORMS)
	return "\n".join(lines).replace(ALBEDO_LINE, TINTED_ALBEDO)


## The LUT's size for ids 0..max_id: LUT_WIDTH wide, as many rows as needed.
static func lut_size(max_id: int) -> Vector2i:
	return Vector2i(LUT_WIDTH, maxi(1, ceili(float(max_id + 1) / LUT_WIDTH)))
