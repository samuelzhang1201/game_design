// River water on the 3D map (spec 2026-09-18 §7). Map3DRivers lays both
// vertices of a pair on the centreline; the vertex stage widens them to the
// river's width (UV2.x, metres) or to min_px on screen far away, and lifts
// them a little so a far river is never swallowed by the relief. The
// fragment stage scrolls two ripple normals DOWNSTREAM (UV.y is metres from
// the source), mixes in the sky by fresnel, shades the mouth (UV2.y) toward
// the sea's near band, fades both edges of the ribbon so it has no hard
// rim, and (fix round 1) multiplies in COLOR.a — Map3DRivers' per-vertex
// end fade, 0 at a cut or the river's true source rising to 1, always 1 at
// the true mouth — so a split never shows as a vertical wall.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 water : source_color = vec4(0.5, 0.72, 0.87, 1.0);
uniform vec4 mouth_water : source_color = vec4(0.66, 0.77, 0.71, 1.0);
uniform vec4 sky : source_color = vec4(0.66, 0.75, 0.8, 1.0);
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float ripple_m = 60.0;
uniform float flow_m_s = 0.8;
uniform float px_per_dist = 0.001;
uniform float min_px = 1.5;
uniform float lift_px = 1.0;
uniform float edge_soft = 0.35;
uniform float opacity = 0.92;

varying float v_across;
varying float v_along;
varying float v_width;
varying float v_mouth;
varying float v_fade;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float m_per_px = length(world - CAMERA_POSITION_WORLD) * px_per_dist;
	float half_w = max(0.5 * UV2.x, 0.5 * min_px * m_per_px);
	VERTEX += NORMAL * half_w;
	VERTEX.y += lift_px * m_per_px;
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_across = UV.x;
	v_along = UV.y;
	v_width = 2.0 * half_w;
	v_mouth = UV2.y;
	v_fade = COLOR.a;
}

void fragment() {
	vec2 p = vec2((v_across - 0.5) * v_width, v_along) / ripple_m;
	vec3 n1 = texture(ripples, p + vec2(0.0, -TIME * flow_m_s / ripple_m)).xyz;
	vec3 n2 = texture(ripples, p * 1.7 + vec2(0.31, -TIME * flow_m_s * 1.3 / ripple_m)).xyz;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 base = mix(water.rgb, mouth_water.rgb, v_mouth);
	ALBEDO = mix(base, sky.rgb, fres * 0.6);
	ROUGHNESS = 0.18;
	SPECULAR = 0.5;
	float edge = smoothstep(0.0, edge_soft, 1.0 - abs(v_across * 2.0 - 1.0));
	ALPHA = opacity * edge * v_fade;
}
