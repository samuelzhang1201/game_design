// scenes/ledger/link.gdshader
// The galaxy's links (spec 2026-09-30-ledger-galaxy-design §5), from
// LedgerLinkMesh: each vertex sits at its end of the link and knows the other
// end (CUSTOM0.xyz) and its side (CUSTOM0.w); the vertex stage pushes it
// across the view by half the link's width in SCREEN px (CUSTOM1.x) plus its
// strand's shift (CUSTOM1.y), so a link keeps its weight at every zoom — the
// border_line.gdshader practice. COLOR is sRGB (turned linear here, Forward+
// blends in linear light), its alpha the drawn opacity; light runs along a
// flow at its speed (UV2.x) as a brightening of its own colour, a planned link is dashed (UV2.y), a running
// loop glows (CUSTOM1.z: 1 virtuous, 2 vicious). Each end moves with its
// star's WOBBLE (star_motion.gdshaderinc; owner 2026-10-01, a wobble large
// enough to read would otherwise leave the link's end behind): CUSTOM2 is this
// end's star — seed, drawn radius, selected — and CUSTOM3 the far end's, each
// radius held to the screen cap the stars are drawn under (`star_cap_px`).
// Every number is a uniform.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled,
	world_vertex_coords;

#include "res://scenes/ledger/star_motion.gdshaderinc"

uniform float px_per_dist = 0.001;
uniform float star_cap_px = 1e6;   // no star is drawn with a radius over this (SubViewport px)
uniform float pulses = 4.0;
uniform float dashes_per_m = 0.5;
uniform float edge_soft = 0.35;
uniform float light_gain = 1.5;
uniform vec4 glow_virtuous : source_color = vec4(0.95, 0.82, 0.48, 1.0);
uniform vec4 glow_vicious : source_color = vec4(0.69, 0.2, 0.16, 1.0);

varying float v_speed;
varying float v_dashed;
varying float v_glow;
varying float v_len;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

// Metres per SubViewport px at a point.
float m_per_px_at(vec3 p, vec3 cam) {
	return length(p - cam) * px_per_dist;
}

// A star at `p` as its link end sees it: moved by its wobble, its radius the
// one it is drawn with (LedgerView3D._draw_r: its own, held to the screen cap).
vec3 wobbled(vec3 p, vec4 star, vec3 cam, mat4 inv_view, float t) {
	float r = min(star.z, star_cap_px * m_per_px_at(p, cam));
	return p + star_wobble(vec4(star.xy, 0.0, star.w), r, inv_view, t);
}

void vertex() {
	vec3 here = wobbled(VERTEX, CUSTOM2, CAMERA_POSITION_WORLD, INV_VIEW_MATRIX, TIME);
	vec3 there = wobbled(CUSTOM0.xyz, CUSTOM3, CAMERA_POSITION_WORLD, INV_VIEW_MATRIX, TIME);
	vec3 dir = there - here;
	v_len = length(dir);
	dir = v_len > 1e-5 ? dir / v_len : vec3(1.0, 0.0, 0.0);
	// toward the eye (LedgerView3D.seg_ends mirrors this rule)
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - here);
	vec3 across = cross(dir, to_cam);
	across = length(across) < 1e-4 ? vec3(0.0, 1.0, 0.0) : normalize(across);
	float m_per_px = m_per_px_at(here, CAMERA_POSITION_WORLD);
	VERTEX = here + across * (CUSTOM0.w * 0.5 * CUSTOM1.x + CUSTOM1.y) * m_per_px;
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
		// the running light brightens the link's OWN hue (Task 11 fix round
		// 1, F4: a mix toward white read as flat grey chips along the links)
		light = smoothstep(0.8, 1.0, fract(along * pulses - TIME * v_speed));
		c *= 1.0 + light * light_gain;
	}
	if (v_glow > 0.5) {
		vec3 g = v_glow > 1.5 ? glow_vicious.rgb : glow_virtuous.rgb;
		c = mix(c, g, 0.55 + 0.45 * sin(TIME * 1.6));
	}
	float edge = 1.0 - abs(UV.y * 2.0 - 1.0);
	ALBEDO = c;
	ALPHA = clamp((COLOR.a + light * 0.3 * COLOR.a) * smoothstep(0.0, edge_soft, edge), 0.0, 1.0);
}
