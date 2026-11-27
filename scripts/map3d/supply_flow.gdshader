// A FLOWING supply line (Map3DSupplyLines; owner 2026-10-07: a solid gold
// line with a sense of flow): a matte ochre-gold core in a thin umber edge
// that holds it on water, grass and sand alike (no glow, no streaks), with
// umber chevrons wider than the line drifting town -> army, so the way the
// supplies go reads even with the clock paused. Laid like the borders
// (Map3DBorders.ribbon_arrays): vertex pairs at one ground point pushed apart
// by `width_px` SCREEN px along NORMAL and lifted `lift_px` (over the woods'
// crowns); UV.x is the metres along the line from the town, UV.y 0..1 across.
// A mark is `dash_px` long every `dash_px + gap_px` screen px, moving
// `flow_px_s` screen px a real second (TIME); `mark_kind` 0 draws none,
// 1 a chevron pointing at the army.
// `width_px`, `lift_px`, `dash_px` and `gap_px` are design px, scaled to the
// SubViewport by Map3DLayerLines (PX_PARAMS); `px_per_dist` is set by it too.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

// the gold core
uniform vec4 colour : source_color = vec4(0.74, 0.58, 0.27, 1.0);
// the umber edge round the core
uniform vec4 halo : source_color = vec4(0.25, 0.17, 0.07, 0.9);
// the travelling marks
uniform vec4 mark : source_color = vec4(0.25, 0.17, 0.07, 1.0);
uniform float width_px = 14.0;
uniform float lift_px = 10.0;
// the core's share of the half-width
uniform float core_share : hint_range(0.0, 1.0) = 0.25;
// the edge band's outer share of the half-width (past it only the marks draw)
uniform float edge_share : hint_range(0.0, 1.0) = 0.36;
// a chevron's stroke, screen px
uniform float mark_stroke_px = 3.0;
uniform int mark_kind : hint_range(0, 1) = 1;
// how far across the half-width a mark reaches
uniform float mark_share : hint_range(0.0, 1.0) = 1.0;
uniform float dash_px = 8.0;
uniform float gap_px = 44.0;
uniform float flow_px_s = 18.0;
// 2 * tan(fov / 2) / viewport height: metres per screen px per metre away.
uniform float px_per_dist = 0.001;

varying float v_arc_px;
varying float v_half_px;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float m_per_px = length(world - CAMERA_POSITION_WORLD) * px_per_dist;
	VERTEX += NORMAL * (0.5 * width_px * m_per_px);
	VERTEX.y += lift_px * m_per_px;
	v_arc_px = UV.x / max(m_per_px, 0.0001);
	v_half_px = 0.5 * width_px;
}

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float aa = max(fwidth(across), 0.0001);
	// the edge: a thin band round the core out to edge_share, its outside anti-aliased
	float wash = halo.a * (1.0 - smoothstep(edge_share - aa, edge_share + aa, across));
	float core = colour.a * (1.0 - smoothstep(core_share - aa, core_share + aa, across));
	// the marks, in screen px about the period's middle (a > 0 toward the army)
	float period = max(dash_px + gap_px, 1.0);
	float a = mod(v_arc_px - TIME * flow_px_s, period) - 0.5 * period;
	float t = across * v_half_px;
	float reach = mark_share * v_half_px;
	float m = 0.0;
	if (mark_kind == 1) {
		// a V whose tip leads: its arms run back `dash_px` over `reach` across
		float d = abs(a + dash_px * t / max(reach, 0.001));
		float pw = max(fwidth(a), 0.0001);
		m = (1.0 - smoothstep(0.5 * mark_stroke_px - pw, 0.5 * mark_stroke_px + pw, d)) * (1.0 - smoothstep(reach - 0.5, reach + 0.5, t));
	}
	m *= mark.a;
	// over: edge, then core, then mark
	vec3 rgb = halo.rgb;
	float al = wash;
	rgb = mix(rgb, colour.rgb, core / max(core + al * (1.0 - core), 0.0001));
	al = core + al * (1.0 - core);
	rgb = mix(rgb, mark.rgb, m / max(m + al * (1.0 - m), 0.0001));
	al = m + al * (1.0 - m);
	ALBEDO = rgb;
	ALPHA = al;
}
