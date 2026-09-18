// The 3D map's borders and seams (Map3DBorders): a ribbon of vertex pairs at
// the same ground point, NORMAL carrying each one's side. The vertex stage
// pushes them apart by `width_px` SCREEN pixels and lifts them `lift_px`
// off the ground at that distance, so a line keeps its weight at every zoom
// and stays above the relief between its samples; the fragment stage cuts
// dashes of `dash_px` / `gap_px`, alternating colour_a and colour_b (a clear
// colour_b draws plain dashes, an opaque one a chequered ribbon). `edge_soft`
// fades the ribbon out toward both sides over that share of its half-width
// (0 a hard edge; roads use it for their soft shoulder).
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 colour_a : source_color = vec4(0.18, 0.23, 0.27, 1.0);
uniform vec4 colour_b : source_color = vec4(1.0, 1.0, 1.0, 0.0);
uniform float width_px = 3.0;
uniform float lift_px = 2.0;
uniform float dash_px = 8.0;
uniform float gap_px = 8.0;
uniform float edge_soft = 0.0;
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
	vec4 c = colour_a;
	float period = dash_px + gap_px;
	if (dash_px > 0.0 && mod(v_arc_px, period) >= dash_px) {
		c = colour_b;
	}
	ALBEDO = c.rgb;
	ALPHA = c.a;
	if (edge_soft > 0.0) {
		ALPHA *= smoothstep(0.0, edge_soft, 1.0 - abs(UV.y * 2.0 - 1.0));
	}
}
