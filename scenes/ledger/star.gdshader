// scenes/ledger/star.gdshader
// A galaxy star (spec 2026-09-30-ledger-galaxy-design §5): one MultiMesh of
// spheres, each instance's COLOR its cluster's sRGB colour. Emission plus a
// real specular and a rim, so close in a star reads as polished metal or
// glass and far out as a point of light under the view's glow.
// This is a WHOLE star, opaque, hiding what stands behind it; a dimmed star
// is drawn by star_faint.gdshader instead (Task 11 fix round 1, F1: dimmed
// on an opaque sphere it was a black disc with a white pin over the haze).
shader_type spatial;
render_mode specular_schlick_ggx, world_vertex_coords;

#include "res://scenes/ledger/star_motion.gdshaderinc"

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
	// the slight wobble (star_motion.gdshaderinc): the instance's scale is the
	// star's drawn radius
	VERTEX += star_wobble(INSTANCE_CUSTOM, length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX, TIME);
}

void fragment() {
	vec3 c = to_linear(col.rgb);
	ALBEDO = c * 0.55;
	METALLIC = metal;
	ROUGHNESS = rough;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.4);
	EMISSION = c * emit + c * rim * rim_gain;
}
