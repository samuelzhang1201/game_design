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
## every 20 m): in a cell whose corners belong to more than one ground —
## a field and the land outside it, or two fields side by side (the edge map's
## A, each field's id; 2026-10-14: the edges between furlongs still stepped) —
## Terrain3D's own accumulate_material runs again with each corner weighted by
## how far the pixel lies on that corner's side: for corner k, the corners'
## distances to their own edges summed bilinearly, plus for corners of k's
## ground and minus for the rest, crosses zero along the edge as a curve. Its
## sampling, detiling and height blend unchanged. Spliced before the tint's
## first line, where mat is already normalised.
const RIM := """	vec2 rxz = v_vertex.xz + (uv - UV) * _vertex_spacing;
	vec2 ruv = ((rxz - pack_origin) / balk_vertex_m + 0.5) / vec2(textureSize(field_edges, 0));
	float rd = (texture(field_edges, ruv).r * 255.0 - balk_zero) / balk_per_m;
	float raa = max(fwidth(rd), 0.3);  // derivatives outside every branch
	// the strips' direction and sown share at this pixel, by the field it lies
	// in (Map3DGroundStrips; -1: read the field map instead)
	float strip_ang = -1.0;
	float strip_sown = 0.0;
	if (bilerp && field_rim > 0.0) {   // field_rim 0: no edge map (Map3DGroundBalk.apply)
		float rk[4];   // each corner's metres to its own ground's edge
		float rg[4];   // each corner's ground: its field's id, 0 outside every field
		float ra[4];   // each corner's strip direction byte, 0 unsown
		bool r_mixed = false;
		for (int k = 0; k < 4; k++) {
			vec2 ip = fma(_region_locations[index[k].z], vec2(_region_size), vec2(index[k].xy)) * _vertex_spacing;
			vec4 rt = texelFetch(field_edges, ivec2(round((ip - pack_origin) / balk_vertex_m)), 0);
			float sk = (rt.r * 255.0 - balk_zero) / balk_per_m;
			rk[k] = abs(sk);
			rg[k] = sk >= 0.0 ? round(rt.a * 255.0) : 0.0;
			ra[k] = sk >= 0.0 ? round(rt.g * 255.0) : 0.0;
			r_mixed = r_mixed || rg[k] != rg[0];
		}
		float wk[4];
		for (int k = 0; k < 4; k++) {
			float side = 0.0;
			for (int j = 0; j < 4; j++) {
				side += weights[j] * (rg[j] == rg[k] ? rk[j] : -rk[j]);
			}
			wk[k] = r_mixed ? weights[k] * smoothstep(-raa, raa, side) : weights[k];
		}
		float w_all = 0.0;
		float w_sown = 0.0;
		float w_best = -1.0;
		for (int k = 0; k < 4; k++) {
			w_all += wk[k];
			if (ra[k] > 0.0) {
				w_sown += wk[k];
				if (wk[k] > w_best) {
					w_best = wk[k];
					strip_ang = (ra[k] - 1.0) / 254.0 * 3.14159265;
				}
			}
		}
		strip_ang = max(strip_ang, 0.0);
		strip_sown = w_sown / max(w_all, 1e-5);
		if (r_mixed) {
			material rm = material(vec4(0.0), vec4(0.0), 0., 0., 0.);
			vec4 rcm = vec4(0.0);  // the colour map (each field's tint) weighted alike
			for (int k = 0; k < 4; k++) {
				accumulate_material(base_ddx, base_ddy, wk[k], index[k],
					control[k], t_weights[k], texture_ids[k], index_normal[k], h[k], rm);
				rcm += (index[k].z > -1 ? texelFetch(_color_maps, index[k], 0) : COLOR_MAP_DEF) * wk[k];
			}
			if (rm.total_weight > 0.0) {
				mat.albedo_height = mix(mat.albedo_height, rm.albedo_height / rm.total_weight, field_rim);
			}
			if (w_all > 0.0) {
				color_map = mix(color_map, rcm / w_all, field_rim);
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
