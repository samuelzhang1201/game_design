// The dust a marching column raises (Map3DLayerDust, owner 2026-10-07: 改成
// 扬起的一串灰尘，短距离，持续一天左右): one soft camera-facing puff per
// MultiMesh instance — its transform's origin the ground it rose from, its
// scale the puff's size in world metres; INSTANCE_CUSTOM = (the game day it
// rose, a 0..1 seed, its fade by how far behind the column it lies, unused).
// It swells and climbs as it ages over `life_days` of GAME time (`now_days`,
// set by the layer, so a paused clock holds it), thinning to nothing; where it
// meets the ground or a house it fades softly over `soft_share` of its size
// (the depth buffer) instead of cutting a line.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled;

uniform vec4 colour : source_color = vec4(0.76, 0.68, 0.53, 1.0);
// the puff's top lit, its underside this much darker (0 flat)
uniform float shade : hint_range(0.0, 1.0) = 0.3;
uniform float opacity : hint_range(0.0, 1.0) = 0.45;
uniform float life_days = 1.0;
// the share of its life it takes to rise in (a puff never pops in)
uniform float rise_in : hint_range(0.0, 1.0) = 0.08;
// its size at birth and at the end of its life, shares of its scale
uniform float start_scale = 0.55;
uniform float end_scale = 1.6;
// how high it climbs over its life, and where it starts, shares of its scale
uniform float climb = 0.35;
uniform float lift = 0.4;
uniform float soft_share = 0.15;
// how ragged its edge is (0 a round disc)
uniform float billow : hint_range(0.0, 1.0) = 0.55;
uniform float now_days = 0.0;
uniform sampler2D depth_tex : hint_depth_texture, filter_linear, repeat_disable;

varying float v_age;
varying float v_seed;
varying float v_fade;
varying float v_size;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_age = clamp((now_days - INSTANCE_CUSTOM.x) / max(life_days, 0.0001), 0.0, 1.0);
	v_seed = INSTANCE_CUSTOM.y;
	v_fade = INSTANCE_CUSTOM.z;
	float size = length(MODEL_MATRIX[0].xyz);
	float grow = 1.0 - (1.0 - v_age) * (1.0 - v_age);  // eases out: quick at first
	v_size = size * mix(start_scale, end_scale, grow);
	vec3 centre = MODEL_MATRIX[3].xyz + vec3(0.0, size * (lift + climb * grow), 0.0);
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = centre + (right * VERTEX.x + up * VERTEX.y) * v_size;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	// a ragged edge: the radius pushed in and out by noise that turns with the seed
	float n = noise(p * 2.6 + vec2(v_seed * 17.0, v_seed * 31.0 + v_age * 1.5));
	float r = length(p) / mix(1.0, 0.65 + 0.5 * n, billow);
	float body = 1.0 - smoothstep(0.25, 1.0, r);
	float life = smoothstep(0.0, rise_in, v_age) * (1.0 - v_age) * (1.0 - v_age);
	// soft where it meets the scene
	float depth = texture(depth_tex, SCREEN_UV).r;
	vec4 behind = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	float gap = (-behind.z / behind.w) - (-VERTEX.z);
	float soft = clamp(gap / max(soft_share * v_size, 0.001), 0.0, 1.0);
	ALBEDO = colour.rgb * mix(1.0, 1.0 - shade, UV.y);
	ALPHA = clamp(body * life * soft * v_fade * opacity * colour.a, 0.0, 1.0);
}
