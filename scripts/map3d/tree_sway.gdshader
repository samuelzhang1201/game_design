shader_type spatial;
// The woods' clumps (Map3DTreeMesh) swaying in the wind (owner 2026-09-30):
// each crown leans down the wind and back on its own phase, more the higher
// up the tree, the trunk's foot still. Map3DLayerWind sets wind_time (it
// runs only while the clock does) and the rest from the world's Wind node.
// Colour is the mesh's vertex colour times the instance's tint, both sRGB:
// Forward+ hands COLOR over unconverted, so it is turned linear here.
//
// FOLIAGE, not plastic (owner 2026-10-01: 树木一旦把标尺拉到20km以下就非常丑非常
// 假): every crown is broken into LEAF CLUMPS by a world-space noise
// (leaf_m across) that darkens the gaps and tilts the normal, faded out where
// a pixel covers more than a clump so it never shimmers far away; each crown
// takes its own hue, held WARM — olive to yellow-green (hue_bias, hue_spread):
// a teal crown on the golden grass read as a second picture pasted on — and the
// whole wood is held to a natural saturation (saturation); no specular.
// The look is scenes/map3d/materials/tree_sway.tres (edited in the inspector).

uniform float wind_time = 0.0;
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float sway_m = 0.6;
uniform float sway_height_m = 30.0;
uniform float sway_hz = 0.25;
uniform float flutter = 0.35;
uniform float roughness_value = 1.0;
uniform float specular_value = 0.0;
uniform float leaf_m = 2.4;
uniform float leaf_contrast = 0.45;
uniform float leaf_bump = 0.55;
uniform float hue_spread = 0.04;
uniform float hue_bias = -0.03;   // negative turns green toward yellow-olive, positive toward teal
uniform float saturation = 0.8;
uniform float value_gain = 1.0;

varying vec3 w_pos;
varying flat float crown_hash;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
		mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y);
	float b = mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
		mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y);
	return mix(a, b, f.z);
}

vec3 hue_turn(vec3 c, float a) {
	// rotate about the grey axis (Rodrigues)
	const vec3 k = vec3(0.57735);
	float ca = cos(a);
	return c * ca + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - ca);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float k = clamp(VERTEX.y / sway_height_m, 0.0, 1.0);
	k *= k;
	// each tree its own phase (its spot, quantised to a crown's size), and a
	// travelling term so a gust visibly rolls through the wood
	float ph = dot(floor(wp.xz / 7.0), vec2(1.71, 2.37)) + dot(wp.xz, wind_dir) * 0.015;
	float t = wind_time * sway_hz * 6.2831853 + ph;
	float lean = 0.55 + 0.45 * sin(t);
	float side = sin(t * 1.7 + ph * 0.5) * flutter;
	vec3 dir_m = normalize((inverse(mat3(MODEL_MATRIX)) * vec3(wind_dir.x, 0.0, wind_dir.y)));
	vec3 perp_m = normalize((inverse(mat3(MODEL_MATRIX)) * vec3(-wind_dir.y, 0.0, wind_dir.x)));
	// the model is scaled by its instance: sway_m is world metres at the top
	float s = length(MODEL_MATRIX[0].xyz);
	VERTEX += (dir_m * lean + perp_m * side) * sway_m * k / max(s, 0.0001);
	w_pos = wp;
	// one hue per crown: the crown's own cell (crowns stand >= 6.5 m apart)
	crown_hash = hash13(vec3(floor(wp.xz / 6.5), 7.0) + MODEL_MATRIX[3].xyz * 0.013);
}

void fragment() {
	vec3 c = COLOR.rgb;
	// a crown of its own hue and a little of its own value
	c = clamp(hue_turn(c, (hue_bias + (crown_hash - 0.5) * 2.0 * hue_spread) * 6.2831853), 0.0, 1.0);
	float grey = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(grey), c, saturation) * value_gain * (0.88 + 0.24 * crown_hash);
	// leaf clumps: two octaves of world noise, gone once a pixel spans a clump
	float px = length(fwidth(w_pos));
	float fade = 1.0 - smoothstep(leaf_m * 0.35, leaf_m * 0.9, px);
	vec3 q = w_pos / leaf_m;
	float n = vnoise(q) * 0.65 + vnoise(q * 2.13 + 11.7) * 0.35;
	c *= 1.0 + (n - 0.55) * 2.0 * leaf_contrast * fade;
	ALBEDO = to_linear(clamp(c, 0.0, 1.0));
	vec3 tilt = vec3(vnoise(q + 3.1), vnoise(q + 7.7), vnoise(q + 13.3)) - 0.5;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(tilt, 0.0)).xyz * leaf_bump * 2.0 * fade);
	ROUGHNESS = roughness_value;
	SPECULAR = specular_value;
}
