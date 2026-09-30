// scenes/ledger/disc.gdshader
// A LEDGER layer's disc: a flat pool of its layer's colour that fades out
// toward its rim rather than ending on a hard edge (owner 2026-09-30, taste
// "Nothing ends on a hard cut"). Drawn on a PlaneMesh two radii square: the
// disc is the circle inscribed in its UV square. Every number is a uniform
// set from data/ledger_palette.csv and balance.csv ledger_disc_* at build.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;

uniform vec4 color : source_color = vec4(0.42, 0.31, 0.16, 0.18);
// Where the fade begins, as a share of the radius; it reaches nothing at 1.
uniform float fade_start = 0.55;

void fragment() {
	float d = length(UV * 2.0 - 1.0);
	if (d >= 1.0) {
		discard;
	}
	ALBEDO = color.rgb;
	ALPHA = color.a * (1.0 - smoothstep(fade_start, 1.0, d));
}
