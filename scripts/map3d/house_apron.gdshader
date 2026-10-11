// The apron round a house's foot (owner 2026-10-12): a flat quad per house,
// scaled to its footprint plus margin (Map3DHouseApron). style 0 mottled packed
// earth, 1 running-bond brick paving; the edge fades into the ground over
// fade_m metres so the house grows out of it. Colours come from
// data/screens/map3d/map3d_aprons.csv (set by Map3DHouseApron.material_of).
shader_type spatial;
render_mode cull_disabled, depth_draw_opaque, specular_disabled;

uniform vec4 color_a : source_color = vec4(0.48, 0.39, 0.27, 1.0);
uniform vec4 color_b : source_color = vec4(0.37, 0.30, 0.20, 1.0);
uniform int style = 0;
uniform float fade_m = 1.5;
uniform float unit_m = 1.0;

varying vec2 size_m;
varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	size_m = vec2(length(MODEL_MATRIX[0].xyz), length(MODEL_MATRIX[2].xyz));
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 e = min(UV, 1.0 - UV) * size_m;
	float edge = min(e.x, e.y);
	ALPHA = smoothstep(0.0, max(fade_m, 0.01), edge);
	vec2 p = world_pos.xz;
	vec3 c;
	if (style == 1) {
		float row = floor(p.y / (unit_m * 0.5));
		float x = p.x / unit_m + 0.5 * mod(row, 2.0);
		vec2 f = fract(vec2(x, p.y / (unit_m * 0.5)));
		float mortar = step(f.x, 0.06) + step(f.y, 0.1);
		float shade = hash(vec2(floor(x), row));
		c = mix(color_a.rgb * (0.85 + 0.3 * shade), color_b.rgb, clamp(mortar, 0.0, 1.0));
	} else {
		float n = hash(floor(p / unit_m)) * 0.6 + hash(floor(p / (unit_m * 3.0))) * 0.4;
		c = mix(color_a.rgb, color_b.rgb, n);
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
