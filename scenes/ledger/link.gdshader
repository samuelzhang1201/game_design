// scenes/ledger/link.gdshader
// The galaxy's links (spec 2026-09-30-ledger-galaxy-design §5), from
// LedgerLinkMesh: each vertex sits at its end of the link and knows the other
// end (CUSTOM0.xyz) and its side (CUSTOM0.w); the vertex stage pushes it
// across the view by half the link's width in SCREEN px (CUSTOM1.x) plus its
// strand's shift (CUSTOM1.y), so a link keeps its weight at every zoom — the
// border_line.gdshader practice. COLOR is sRGB (turned linear here, Forward+
// blends in linear light), its alpha the drawn opacity; light runs along a
// flow at its speed (UV2.x), a planned link is dashed (UV2.y), a running
// loop glows (CUSTOM1.z: 1 virtuous, 2 vicious). Every number is a uniform.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled,
	world_vertex_coords;

uniform float px_per_dist = 0.001;
uniform float ortho_m_per_px = 0.0;
uniform float pulses = 4.0;
uniform float dashes_per_m = 0.5;
uniform float edge_soft = 0.35;
uniform vec4 glow_virtuous : source_color = vec4(0.95, 0.82, 0.48, 1.0);
uniform vec4 glow_vicious : source_color = vec4(0.69, 0.2, 0.16, 1.0);

varying float v_speed;
varying float v_dashed;
varying float v_glow;
varying float v_len;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	vec3 here = VERTEX;
	vec3 there = CUSTOM0.xyz;
	vec3 dir = there - here;
	v_len = length(dir);
	dir = v_len > 1e-5 ? dir / v_len : vec3(1.0, 0.0, 0.0);
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - here);
	vec3 across = cross(dir, to_cam);
	across = length(across) < 1e-4 ? vec3(0.0, 1.0, 0.0) : normalize(across);
	float m_per_px = ortho_m_per_px > 0.0 ? ortho_m_per_px : length(here - CAMERA_POSITION_WORLD) * px_per_dist;
	VERTEX += across * (CUSTOM0.w * 0.5 * CUSTOM1.x + CUSTOM1.y) * m_per_px;
	v_speed = UV2.x;
	v_dashed = UV2.y;
	v_glow = CUSTOM1.z;
}

void fragment() {
	float along = UV.x;
	if (v_dashed > 0.5 && fract(along * v_len * dashes_per_m) > 0.5) {
		discard;
	}
	vec3 c = to_linear(COLOR.rgb);
	float light = 0.0;
	if (v_speed > 0.0) {
		light = smoothstep(0.8, 1.0, fract(along * pulses - TIME * v_speed));
		c = mix(c, vec3(1.0, 0.95, 0.82), light * 0.8);
	}
	if (v_glow > 0.5) {
		vec3 g = v_glow > 1.5 ? glow_vicious.rgb : glow_virtuous.rgb;
		c = mix(c, g, 0.55 + 0.45 * sin(TIME * 1.6));
	}
	float edge = 1.0 - abs(UV.y * 2.0 - 1.0);
	ALBEDO = c;
	ALPHA = clamp((COLOR.a + light * 0.3 * COLOR.a) * smoothstep(0.0, edge_soft, edge), 0.0, 1.0);
}
