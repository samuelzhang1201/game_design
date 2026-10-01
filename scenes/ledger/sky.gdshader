// scenes/ledger/sky.gdshader
// The galaxy's night (spec 2026-09-30-ledger-galaxy-design §5): a warm black
// from foot to top, faint dust by noise, and sparse stars of two sizes.
// Seen straight down (the flat chart, flat_mode 1) the sky is laid in
// SCREEN space, or the stars streak into rays toward the pole.
shader_type sky;

uniform vec3 bg_top : source_color;
uniform vec3 bg_bottom : source_color;
uniform vec3 neb_a : source_color;
uniform vec3 neb_b : source_color;
uniform vec3 star_col : source_color;
uniform float neb_gain = 1.0;
uniform float flat_mode = 0.0;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 c = mix(bg_bottom, bg_top, d.y * 0.5 + 0.5);
	if (flat_mode > 0.5) {
		d = normalize(vec3(SCREEN_UV * vec2(1.6, 1.0) - vec2(0.8, 0.5), 0.9));
		c = mix(bg_bottom, bg_top, 0.35 + 0.3 * SCREEN_UV.y);
	}
	float n1 = fbm(d * 2.6);
	float n2 = fbm(d * 4.3 + 7.0);
	c += (neb_a * smoothstep(0.42, 0.85, n1) * 0.30 + neb_b * smoothstep(0.5, 0.9, n2) * 0.22) * neb_gain;
	vec3 g = d * 380.0;
	vec3 f = fract(g) - 0.5;
	float s = step(0.982, hash(floor(g))) * smoothstep(0.32, 0.0, length(f)) * (0.35 + 0.65 * hash(floor(g) + 3.1));
	vec3 g2 = d * 1200.0;
	vec3 f2 = fract(g2) - 0.5;
	float s2 = step(0.97, hash(floor(g2))) * smoothstep(0.3, 0.0, length(f2)) * 0.35;
	c += star_col * (s * 2.2 + s2);
	COLOR = c;
}
