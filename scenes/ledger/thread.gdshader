// scenes/ledger/thread.gdshader
// A LEDGER thread (spec 2026-09-30 §6.3): gold wire whose ink is its
// credibility, with light running from the link's source to its end at a
// speed set by its believed flow; dashed and dark when not yet built; a
// slow glow while its loop runs. Every number is a uniform set from
// data/ledger_palette.csv and balance.csv ledger_* at build time.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

uniform vec4 color : source_color = vec4(0.88, 0.73, 0.42, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.85, 0.5, 1.0);
uniform float ink = 1.0;
// How much of the thread shows as the EYE reads it (focus and rest fades):
// Forward+ blends in linear light, where alpha 0.25 of a bright wire on the
// dark ground still reads about half as bright, so it is turned linear here.
uniform float fade = 1.0;
uniform float speed = 0.0;
uniform float pulses = 4.0;
uniform float dashed = 0.0;
uniform float dashes = 14.0;
uniform float glow = 0.0;

void fragment() {
	// CylinderMesh lays its SIDE over the top half of the UV square: V runs
	// 0 at its top (+Y, the link's end) to 0.5 at its bottom (the source).
	// The view builds threads without caps, so this is the whole wire.
	float along = 1.0 - 2.0 * UV.y;
	if (dashed > 0.5 && fract(along * dashes) > 0.5) {
		discard;
	}
	float light = 0.0;
	if (speed > 0.0) {
		light = smoothstep(0.8, 1.0, fract(along * pulses - TIME * speed));
	}
	vec3 c = mix(color.rgb, vec3(1.0, 0.95, 0.82), light * 0.8);
	c = mix(c, glow_color.rgb, glow * (0.55 + 0.45 * sin(TIME * 1.6)));
	ALBEDO = c;
	ALPHA = clamp((ink * color.a + light * 0.3) * pow(fade, 2.2), 0.0, 1.0);
}
