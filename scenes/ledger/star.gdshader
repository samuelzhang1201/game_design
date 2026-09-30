// scenes/ledger/star.gdshader
// A galaxy star (spec 2026-09-30-ledger-galaxy-design §5): one MultiMesh of
// spheres, each instance's COLOR its cluster's sRGB colour, its alpha a
// brightness factor read as the EYE reads it (pow 2.2). Emission plus a real
// specular and a rim, so close in a star reads as polished metal or glass and
// far out as a point of light under the view's glow.
shader_type spatial;
render_mode specular_schlick_ggx;

uniform float emit = 1.4;
uniform float rim_gain = 1.6;
uniform float metal = 0.35;
uniform float rough = 0.22;

varying vec4 col;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void vertex() {
	col = COLOR;
}

void fragment() {
	vec3 c = to_linear(col.rgb);
	float a = pow(clamp(col.a, 0.0, 1.0), 2.2);
	ALBEDO = c * 0.55 * a;
	METALLIC = metal;
	ROUGHNESS = rough;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	EMISSION = (c * emit + c * rim * rim_gain) * a;
}
