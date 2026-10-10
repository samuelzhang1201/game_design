// scenes/ledger/star_faint.gdshader
// A DIMMED galaxy star (Task 11 fix round 1, F1): the chosen cluster's
// others, the stars off the selected web, a planned (ghost) star. It fades
// TOWARD THE SKY: the same colour, emission, specular and rim as a whole
// star (star.gdshader), blended at its instance alpha read as the EYE reads
// it (pow 2.2) — never darkened, so it is never darker than what is behind
// it, and its specular pin fades with it. It writes no depth: the haze and
// the links behind it still show through.
shader_type spatial;
render_mode specular_schlick_ggx, blend_mix, depth_draw_never, world_vertex_coords;

#include "res://scenes/ledger/star_motion.gdshaderinc"

uniform float emit = 1.4;
uniform float rim_gain = 1.6;
uniform float metal = 0.35;
uniform float rough = 0.22;
// The generated MATCAP (owner 2026-10-10: the ledger's art drawn by Comfy,
// `L-01`..`L-03`, tools/ledger/ledger_art_prep.py): a sphere's VALUE looked
// up by the view-space normal and tinted with the cluster's colour, its
// brightest highlights going toward white. matcap_mix 0 is the plain shine.
uniform sampler2D matcap : source_color, hint_default_white, filter_linear_mipmap;
uniform float matcap_mix = 0.0;
uniform float matcap_gain = 2.2;
uniform float matcap_white = 0.6;

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
	vec3 shine = c * emit + c * rim * rim_gain;
	float m = texture(matcap, NORMAL.xy * vec2(0.5, -0.5) + 0.5).r;
	vec3 painted = c * m * matcap_gain + vec3(pow(m, 4.0)) * matcap_white;
	ALBEDO *= 1.0 - matcap_mix;
	SPECULAR = 0.5 * (1.0 - matcap_mix);
	EMISSION = mix(shine, painted, matcap_mix);
	ALPHA = pow(clamp(col.a, 0.0, 1.0), 2.2);
}
