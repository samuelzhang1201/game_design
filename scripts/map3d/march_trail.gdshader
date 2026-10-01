// A regiment's MARCH TRAIL (owner 2026-10-01: 当军事单位路过的时候…留下一段行走
// 印记，后逐步消失): the ground its column trod, a Map3DBorders ribbon — both
// vertices of a pair on the centreline, NORMAL the side — widened to its
// half width (UV2.y, world metres), stamped with the game time it
// was trodden (UV2.x, days) and faded out over `life_days` from `now_days`,
// which Map3DLayerTrails moves only while the clock runs. Trampled earth and
// flattened grass: darker ground broken into prints along the track, soft at
// its sides and at its tail, so it never reads as a painted road (taste:
// read by width and fade).
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 colour : source_color = vec4(0.37, 0.32, 0.21, 0.35);
// On the open fields' corn the trail is the stalks beaten DOWN, darker than
// the crop (owner 2026-10-01: a pale trail vanished on the pale corn); the
// bake's field map (Map3DLayerThemes) says where the ground is sown.
uniform vec4 crop_colour : source_color = vec4(0.25, 0.22, 0.13, 1.0);
uniform sampler2D field_map : filter_linear, repeat_disable;
uniform bool has_field_map = false;
uniform float crop_gain = 1.8;
uniform vec2 pack_origin = vec2(0.0);
uniform float field_m_per_texel = 40.0;
uniform float now_days = 0.0;
uniform float life_days = 1.0;
uniform float hold_share = 0.4;
uniform float edge_soft = 0.45;
uniform float print_m = 12.0;
uniform float print_mix = 0.55;
// the column's files: one trodden lane each, wandering, lighter between
uniform float lanes = 3.0;
uniform float lane_fill = 0.3;
uniform float lane_wander = 0.35;
uniform float rag = 0.6;
uniform float lift_px = 2.0;
uniform float px_per_dist = 0.001;

varying float v_age;
varying float v_arc;
varying float v_across;
varying float v_half;
varying vec2 v_world;

float tr_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float tr_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(tr_hash(i), tr_hash(i + vec2(1.0, 0.0)), u.x),
		mix(tr_hash(i + vec2(0.0, 1.0)), tr_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world = world.xz;
	float m_per_px = length(world - CAMERA_POSITION_WORLD) * px_per_dist;
	v_half = UV2.y;
	VERTEX += NORMAL * v_half;
	VERTEX.y += lift_px * m_per_px;
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_age = now_days - UV2.x;
	v_arc = UV.x;
	v_across = (UV.y - 0.5) * 2.0;
}

void fragment() {
	// soft, ragged sides
	float r = (tr_noise(vec2(v_arc / (print_m * 2.0), v_across * 2.0)) - 0.5) * rag;
	float edge = 1.0 - smoothstep(1.0 - edge_soft, 1.0, abs(v_across) + r);
	// the files' lanes, each wandering along the track
	float wob = (tr_noise(vec2(v_arc / (print_m * 4.0), 3.7)) - 0.5) * 2.0 * lane_wander;
	float lane = 0.5 + 0.5 * cos((v_across + wob / lanes) * 3.14159265 * lanes);
	lane = mix(lane_fill, 1.0, smoothstep(0.35, 0.9, lane));
	// the ground holds the track a while, then the grass stands up again
	float fade = 1.0 - smoothstep(life_days * hold_share, life_days, v_age);
	// prints: trampled patches along and across the track
	vec2 q = vec2(v_arc, v_across * v_half) / print_m;
	float prints = tr_noise(q) * 0.6 + tr_noise(q * 2.7 + vec2(3.1, 7.7)) * 0.4;
	prints = mix(1.0, smoothstep(0.3, 0.7, prints), print_mix);
	float sown = 0.0;
	if (has_field_map) {
		vec3 fm = texture(field_map, (v_world - pack_origin) / field_m_per_texel / vec2(textureSize(field_map, 0))).rgb;
		sown = clamp((1.0 - min(min(fm.r, fm.g), fm.b)) / 0.25, 0.0, 1.0);
	}
	ALBEDO = mix(colour.rgb, crop_colour.rgb, sown);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	// on the corn the beaten track is plainer: fewer gaps between the lanes
	float cover = mix(prints * lane, 1.0, sown * 0.6);
	ALPHA = clamp(colour.a * mix(1.0, crop_gain, sown), 0.0, 1.0) * edge * fade * cover;
}
