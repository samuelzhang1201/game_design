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
// (taste: read by width and fade).
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
uniform float tile_m = 6.0;
uniform float near_mpp = 0.4;
uniform float far_mpp = 1.6;
uniform float px_per_dist = 0.001;

varying float v_arc;
varying float v_across;
varying float v_far;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float m_per_px = length(world - CAMERA_POSITION_WORLD) * px_per_dist;
	float half_w = max(0.5 * width_px * m_per_px, 0.5 * width_m);
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
}

void fragment() {
	vec2 uv = vec2(v_arc, v_across) / tile_m;
	vec4 alb = has_surface ? texture(surface, uv) : vec4(colour.rgb, 0.5);
	vec4 nrm = has_surface ? texture(surface_nrm, uv) : vec4(0.5, 0.5, 1.0, 0.85);
	// Far away the road is the palette colour exactly as the unshaded track
	// drew it before (the lit flat colour read near-white through the
	// Filmic tonemap): it goes out as emission, the lit texture fades out.
	ALBEDO = alb.rgb * surface_tint * (1.0 - v_far);
	EMISSION = colour.rgb * v_far;
	NORMAL_MAP = nrm.rgb;
	NORMAL_MAP_DEPTH = 1.0 - v_far;
	ROUGHNESS = mix(nrm.a, 0.9, v_far);
	SPECULAR = 0.0;
	float edge = 1.0 - abs(UV.y * 2.0 - 1.0);
	edge += (alb.a - 0.5) * fray * (1.0 - v_far);
	ALPHA = colour.a * smoothstep(0.0, edge_soft, edge);
}
