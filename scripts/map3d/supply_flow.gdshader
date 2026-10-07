// A FLOWING supply line (Map3DSupplyLines, owner 2026-10-07: 补给线变成实心的
// 金色线，带流动感): a solid gold ribbon from its town to the column, edged
// by a dark hairline, with brighter streaks running along it from the town
// toward the army. Laid like the borders (Map3DBorders.ribbon_arrays): vertex
// pairs at one ground point pushed apart by `width_px` SCREEN px along NORMAL
// and lifted `lift_px` (over the woods' crowns); UV.x is the metres along the line from the town, UV.y
// 0..1 across it. A streak is `dash_px` long every `dash_px + gap_px` screen
// px, brightest at its head (the army's side) and fading back toward the
// town, moving `flow_px_s` screen px a real second (TIME). `width_px`,
// `lift_px`, `dash_px` and `gap_px` are design px, scaled to the SubViewport
// by Map3DLayerLines (PX_PARAMS); `px_per_dist` is set by it too.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 colour : source_color = vec4(0.859, 0.639, 0.2, 1.0);
uniform vec4 glow : source_color = vec4(1.0, 0.95, 0.75, 1.0);
uniform vec4 edge : source_color = vec4(0.17, 0.12, 0.08, 0.85);
uniform float width_px = 6.0;
uniform float lift_px = 10.0;
// the hairline's share of the half-width, each side
uniform float edge_share : hint_range(0.0, 1.0) = 0.36;
uniform float dash_px = 26.0;
uniform float gap_px = 54.0;
uniform float flow_px_s = 60.0;
// how much of the core a streak's head lights (0 none)
uniform float glow_strength : hint_range(0.0, 1.0) = 0.85;
// 2 * tan(fov / 2) / viewport height: metres per screen px per metre away.
uniform float px_per_dist = 0.001;

varying float v_arc_px;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float m_per_px = length(world - CAMERA_POSITION_WORLD) * px_per_dist;
	VERTEX += NORMAL * (0.5 * width_px * m_per_px);
	VERTEX.y += lift_px * m_per_px;
	v_arc_px = UV.x / max(m_per_px, 0.0001);
}

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float aa = max(fwidth(across), 0.0001);
	// the streaks: a ramp up to a head that moves from the town to the army
	float period = max(dash_px + gap_px, 1.0);
	float phase = mod(v_arc_px - TIME * flow_px_s, period);
	float streak = phase < dash_px ? phase / max(dash_px, 0.001) : 0.0;
	streak = streak * streak * smoothstep(dash_px, dash_px - 3.0, phase);
	vec3 core = mix(colour.rgb, glow.rgb, glow_strength * streak);
	// the dark hairline at both sides, its inner edge anti-aliased
	float inner = 1.0 - edge_share;
	float on_edge = smoothstep(inner - aa, inner + aa, across);
	ALBEDO = mix(core, edge.rgb, on_edge);
	ALPHA = mix(colour.a, edge.a, on_edge) * smoothstep(1.0, 1.0 - aa * 1.5, across);
}
