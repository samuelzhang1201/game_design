// The 3D map's roads and trails (owner 2026-09-19: a packed earth-and-stone
// road, Poly Haven rocky_trail_02). A Map3DBorders ribbon — both vertices
// of a pair on the centreline, NORMAL the side — widened to the road's REAL
// width in metres, or to `width_px` on screen when that is wider (far away a
// road still reads as a track). The surface is the texture laid in metres
// along the road (UV.x, arc length) and across it, lit like the ground; it
// fades to the flat palette colour as a screen px grows past `near_mpp` ..
// `far_mpp` metres, where the stones are smaller than a pixel (unlit there,
// as the flat track was). The sides
// fray by the texture's own height so a road's edge is worn, not ruled
// (taste: read by width and fade). Past the road's own edge the ribbon runs
// on `shoulder` times as wide as a worn verge: trodden earth
// (`shoulder_colour`) from `shoulder_alpha` at the road's edge down to
// nothing, so the ground grades into the road instead of meeting it at a
// line (owner 2026-10-11: 主路和背景的地面交界处太sharp了，要逐步过渡).
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 colour : source_color = vec4(0.61, 0.5, 0.35, 0.9);
uniform sampler2D surface : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D surface_nrm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool has_surface = false;
// the texture's multiplier toward the palette's tone, so near and far agree
uniform vec3 surface_tint = vec3(1.0);
uniform float width_px = 4.0;
uniform float width_m = 7.0;
uniform float lift_px = 2.0;
uniform float edge_soft = 0.5;
uniform float fray = 0.35;
// the ribbon's width over the road's own (1 = no verge)
uniform float shoulder = 1.0;
uniform float shoulder_alpha = 0.0;
uniform vec4 shoulder_colour : source_color = vec4(0.45, 0.4, 0.27, 1.0);
uniform float tile_m = 6.0;
uniform float near_mpp = 0.4;
uniform float far_mpp = 1.6;
// Far-zoom denoise (owner 2026-09-25: "进行远景降噪"): a line fades out
// between hide_from_m and hide_to_m from the camera (trails; the roads keep
// the defaults, which never hide).
uniform float hide_from_m = 1.0e9;
uniform float hide_to_m = 2.0e9;
varying float v_hide;
uniform float px_per_dist = 0.001;

varying float v_arc;
varying float v_across;
varying float v_far;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float m_per_px = length(world - CAMERA_POSITION_WORLD) * px_per_dist;
	float half_w = max(0.5 * width_px * m_per_px, 0.5 * width_m) * max(shoulder, 1.0);
	VERTEX += NORMAL * half_w;
	VERTEX.y += lift_px * m_per_px;
	// UV.y runs from the + side (0) to the - side (1); UV.x along the road
	vec3 side_plus = NORMAL * (UV.y < 0.5 ? 1.0 : -1.0);
	BINORMAL = -side_plus;
	TANGENT = normalize(cross(vec3(0.0, 1.0, 0.0), side_plus));
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_arc = UV.x;
	v_across = (UV.y - 0.5) * 2.0 * half_w;
	v_far = has_surface ? smoothstep(near_mpp, far_mpp, m_per_px) : 1.0;
	v_hide = 1.0 - smoothstep(hide_from_m, hide_to_m, length(world - CAMERA_POSITION_WORLD));
}

void fragment() {
	vec2 uv = vec2(v_arc, v_across) / tile_m;
	vec4 alb = has_surface ? texture(surface, uv) : vec4(colour.rgb, 0.5);
	vec4 nrm = has_surface ? texture(surface_nrm, uv) : vec4(0.5, 0.5, 1.0, 0.85);
	// Far away the road is the palette colour exactly as the unshaded track
	// drew it before (the lit flat colour read near-white through the
	// Filmic tonemap): it goes out as emission, the lit texture fades out.
	// t: 0 on the centreline, 1 at the ribbon's side; the road ends at r
	float r = 1.0 / max(shoulder, 1.0);
	float t = abs(UV.y * 2.0 - 1.0);
	float edge = max(1.0 - t / r, 0.0);
	edge += (alb.a - 0.5) * fray * (1.0 - v_far);
	float core = smoothstep(0.0, edge_soft, edge);
	float verge = r < 1.0 ? smoothstep(0.0, 1.0, (1.0 - t) / (1.0 - r)) : 0.0;
	verge = min(verge, 1.0) * shoulder_alpha * shoulder_colour.a;
	ALBEDO = mix(shoulder_colour.rgb, alb.rgb * surface_tint, core) * (1.0 - v_far);
	EMISSION = mix(shoulder_colour.rgb, colour.rgb, core) * v_far;
	NORMAL_MAP = nrm.rgb;
	NORMAL_MAP_DEPTH = core * (1.0 - v_far);
	ROUGHNESS = mix(nrm.a, 0.9, v_far);
	SPECULAR = 0.0;
	ALPHA = max(colour.a * core, verge) * v_hide;
}
