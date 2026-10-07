// A FLOWING supply line on the WAR ROOM's sheet (WarSupplyFlow; owner
// 2026-10-07: 补给线变成实心的金色线，带流动感): a solid gold ribbon from its
// town to the column, edged by a dark hairline, brighter streaks running along
// it toward the army — the 3D map's supply line in the table's own measure.
// The mesh lays two vertices at each point ON the line, NORMAL the side each
// grows toward; they are pushed `width_m` apart and lifted `lift_m` off the
// sheet. UV.x is the metres along the line from the town, UV.y 0..1 across.
// A streak is `dash_m` long every `dash_m + gap_m`, brightest at its head
// (the army's side), moving `flow_m_s` a real second (TIME). All in table
// metres, so the line lies on the sheet like its ink.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, shadows_disabled, fog_disabled;

uniform vec4 colour : source_color = vec4(0.859, 0.639, 0.2, 1.0);   // #DBA333, the 3D map's gold
uniform vec4 glow : source_color = vec4(0.949, 0.784, 0.376, 1.0);  // #F2C860
uniform vec4 edge : source_color = vec4(0.227, 0.165, 0.078, 0.9);  // #3A2A14 at 90%
uniform float width_m = 0.004;
uniform float lift_m = 0.0006;
// the hairline's share of the half-width, each side
uniform float edge_share : hint_range(0.0, 1.0) = 0.3;
uniform float dash_m = 0.018;
uniform float gap_m = 0.036;
uniform float flow_m_s = 0.03;
// how much of the core a streak's head lights (0 none)
uniform float glow_strength : hint_range(0.0, 1.0) = 0.85;

void vertex() {
	VERTEX += NORMAL * (0.5 * width_m);
	VERTEX.y += lift_m;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float aa = max(fwidth(across), 0.0001);
	float period = max(dash_m + gap_m, 0.0001);
	float phase = mod(UV.x - TIME * flow_m_s, period);
	float streak = phase < dash_m ? phase / max(dash_m, 0.00001) : 0.0;
	streak = streak * streak * smoothstep(dash_m, dash_m * 0.85, phase);
	vec3 core = mix(colour.rgb, glow.rgb, glow_strength * streak);
	float inner = 1.0 - edge_share;
	float on_edge = smoothstep(inner - aa, inner + aa, across);
	ALBEDO = mix(core, edge.rgb, on_edge);
	ALPHA = mix(colour.a, edge.a, on_edge) * smoothstep(1.0, 1.0 - aa * 1.5, across);
}
