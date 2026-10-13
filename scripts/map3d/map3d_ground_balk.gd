class_name Map3DGroundBalk
extends RefCounted
## The fields' BALKS and hedges as lines (visual review 2026-10-05: field edges
## read jagged, like a mask). Terrain3D can only change a texture from vertex
## to vertex, so a field's rim steps every 20 m; tools/map3d/bake_world.py
## writes each field's SIGNED distance to its own edge at the vertices
## (bake/field_edges.png, negative outside), and this stage draws a line along it — bilinearly
## sampled, so the line runs smooth through the steps and hides them: a pale
## grass balk between furlongs. The HEDGES are their own line (spec
## 2026-10-13-open-field-layout §3b, owner 2026-10-13: hedges where they stood
## — round the crofts, the open field's outside, the meadows, never between
## furlongs): bake/hedge_lines.png holds three signed distances (one per rank
## level, bake_world.hedge_map), the hedge where the least |distance| after
## each one's bilinear sample is under half `hedge_m`. It reads the ground's
## edge-warped position, so the line follows the drawn rim (Map3DGroundEdge).
## The ground look's `balk_*` and `hedge_*` (0 off).

const UNIFORMS := """
// Map3DGroundBalk: bake/field_edges.png, one byte per vertex, the metres to a field's edge.
uniform highp sampler2D field_edges : filter_linear, repeat_disable;
uniform float balk = 0.0;
uniform float balk_m = 6.0;
uniform float balk_per_m = 2.0;
uniform float balk_zero = 128.0;  // the byte of a field's edge: inside above, outside below
uniform float balk_vertex_m = 20.0;
uniform vec4 balk_color : source_color = vec4(0.42, 0.45, 0.24, 1.0);
uniform float balk_far_m = 9000.0;
uniform float field_rim = 0.0;
// bake/hedge_lines.png, RGB a signed distance per rank level (as field_edges).
uniform highp sampler2D hedge_lines : filter_linear, repeat_disable;
uniform float hedge = 0.0;
uniform float hedge_m = 9.0;
uniform vec4 hedge_color : source_color = vec4(0.22, 0.28, 0.12, 1.0);
uniform float hedge_far_m = 16000.0;
"""

## The fields' RIM per pixel (visual review 2026-10-06: field edges stepped
## every 20 m): in a cell whose corners lie on both sides of a field's edge,
## Terrain3D's own accumulate_material runs again with each corner weighted by
## the pixel's coverage (the signed edge map) — its sampling, detiling and
## height blend unchanged, only the edge drawn as the curve the map holds.
## Spliced before the tint's first line, where mat is already normalised.
const RIM := """	vec2 rxz = v_vertex.xz + (uv - UV) * _vertex_spacing;
	vec2 ruv = ((rxz - pack_origin) / balk_vertex_m + 0.5) / vec2(textureSize(field_edges, 0));
	float rd = (texture(field_edges, ruv).r * 255.0 - balk_zero) / balk_per_m;
	float raa = max(fwidth(rd), 0.3);  // derivatives outside every branch
	if (field_rim > 0.0 && bilerp) {
		float rk[4];
		bool r_in = false;
		bool r_out = false;
		for (int k = 0; k < 4; k++) {
			vec2 ip = fma(_region_locations[index[k].z], vec2(_region_size), vec2(index[k].xy)) * _vertex_spacing;
			rk[k] = texelFetch(field_edges, ivec2(round((ip - pack_origin) / balk_vertex_m)), 0).r * 255.0 - balk_zero;
			r_in = r_in || rk[k] >= 0.0;
			r_out = r_out || rk[k] < 0.0;
		}
		if (r_in && r_out) {
			float rcov = smoothstep(-raa, raa, rd);
			material rm = material(vec4(0.0), vec4(0.0), 0., 0., 0.);
			vec4 rcm = vec4(0.0);  // the colour map (each field's tint) weighted alike
			float rcw = 0.0;
			for (int k = 0; k < 4; k++) {
				float wk = weights[k] * (rk[k] >= 0.0 ? rcov : 1.0 - rcov);
				accumulate_material(base_ddx, base_ddy, wk, index[k],
					control[k], t_weights[k], texture_ids[k], index_normal[k], h[k], rm);
				rcm += (index[k].z > -1 ? texelFetch(_color_maps, index[k], 0) : COLOR_MAP_DEF) * wk;
				rcw += wk;
			}
			if (rm.total_weight > 0.0) {
				mat.albedo_height = mix(mat.albedo_height, rm.albedo_height / rm.total_weight, field_rim);
			}
			if (rcw > 0.0) {
				color_map = mix(color_map, rcm / rcw, field_rim);
			}
		}
	}
"""

const STAGE := """	if (balk > 0.0) {
		vec2 bxz = v_vertex.xz + (uv - UV) * _vertex_spacing;  // where the ground was looked up
		vec2 buv = ((bxz - pack_origin) / balk_vertex_m + 0.5) / vec2(textureSize(field_edges, 0));
		float bd = (texture(field_edges, buv).r * 255.0 - balk_zero) / balk_per_m;  // signed metres
		float baa = max(fwidth(bd), 0.5);
		float bk = smoothstep(-baa, baa, bd) * (1.0 - smoothstep(balk_m - baa, balk_m + baa, bd))
			* (1.0 - smoothstep(balk_far_m * 0.5, balk_far_m, length(v_vertex - _camera_pos)));
		base_albedo = mix(base_albedo, balk_color.rgb, bk * balk);
	}
	if (hedge > 0.0) {
		vec2 hxz = v_vertex.xz + (uv - UV) * _vertex_spacing;
		vec2 huv = ((hxz - pack_origin) / balk_vertex_m + 0.5) / vec2(textureSize(hedge_lines, 0));
		vec3 hs = (texture(hedge_lines, huv).rgb * 255.0 - balk_zero) / balk_per_m;  // signed metres per level
		float hd = min(min(abs(hs.r), abs(hs.g)), abs(hs.b));
		float haa = max(fwidth(hd), 0.5);
		float hk = (1.0 - smoothstep(hedge_m * 0.5 - haa, hedge_m * 0.5 + haa, hd))
			* (1.0 - smoothstep(hedge_far_m * 0.5, hedge_far_m, length(v_vertex - _camera_pos)));
		base_albedo = mix(base_albedo, hedge_color.rgb, hk * hedge);
	}
"""


## Hand the ground `mat` the build's edge map and the look's balks; off
## without the file.
static func apply(mat: Object, scene_path: String, look: Map3DGroundLook) -> void:
	var path := Map3DWorldLoader.data_dir(scene_path).path_join("bake/field_edges.png")  # res://, as woods.png
	var img: Image = Image.load_from_file(path) if FileAccess.file_exists(path) else null
	if img == null:
		mat.call("set_shader_param", "balk", 0.0)
		mat.call("set_shader_param", "field_rim", 0.0)
		return
	mat.call("set_shader_param", "field_edges", ImageTexture.create_from_image(img))
	for key: String in ["balk", "balk_m", "balk_color", "balk_far_m", "field_rim"]:
		mat.call("set_shader_param", key, look.get(key))
	var hpath := Map3DWorldLoader.data_dir(scene_path).path_join("bake/hedge_lines.png")
	# off in the look: the map is never read (an RGBA texture at the vertices)
	var himg: Image = Image.load_from_file(hpath) if look.hedge > 0.0 and FileAccess.file_exists(hpath) else null
	if himg == null:
		mat.call("set_shader_param", "hedge", 0.0)
		return
	mat.call("set_shader_param", "hedge_lines", ImageTexture.create_from_image(himg))
	for key: String in ["hedge", "hedge_m", "hedge_color", "hedge_far_m"]:
		mat.call("set_shader_param", key, look.get(key))
