// The folio's figure as a fight-book drawing (owner 2026-10-01, spec §4): no
// colour, sepia hatching by the light on vellum — dense where the light falls
// away, none where it falls full. Screen-space strokes, so it reads as drawn.
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec4 ink : source_color = vec4(0.169, 0.129, 0.094, 1.0);
uniform vec4 paper : source_color = vec4(0.914, 0.863, 0.753, 1.0);
uniform vec3 light_dir = vec3(-0.5, 0.7, -0.5);   // from the figure's front (it faces -Z), above and to one side
uniform float stroke_px = 5.0;

void fragment() {
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float lit = clamp(dot(n, normalize(light_dir)), 0.0, 1.0);
	vec2 p = FRAGCOORD.xy / stroke_px;
	float h1 = step(0.5, fract(p.x + p.y));
	float h2 = step(0.5, fract(p.x - p.y));
	float dark = 0.0;
	if (lit < 0.55) dark = h1;
	if (lit < 0.25) dark = max(dark, h2);
	ALBEDO = mix(paper.rgb, ink.rgb, dark * 0.85);
}
