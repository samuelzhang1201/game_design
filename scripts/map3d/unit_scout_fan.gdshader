// A marching crown unit's scouting fan on the 3D map's ground (spec
// 2026-10-14-unit-clearance-and-scouting-design (d); Map3DUnitScout): a faint
// pale fill over the whole sector, feathered at the apex and the rim, and a
// brighter wedge sweeping back and forth across it like a lookout's glance.
// UV.x is the share of the arc, -1..1 (the heading is 0); UV.y the share of
// the radius, 0..1. The look is the .tres; `half_arc` (radians) and `phase`
// are per fan instance uniforms (the phase hashed from the regiment's code).
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled, blend_mix;

uniform vec4 colour : source_color = vec4(1.0, 0.95, 0.8, 1.0);
// the fill's alpha over the whole arc
uniform float fill_alpha : hint_range(0.0, 1.0) = 0.06;
// the sweeping wedge's alpha at its brightest
uniform float wedge_alpha : hint_range(0.0, 1.0) = 0.18;
// the wedge's half width, in degrees
uniform float wedge_width_deg : hint_range(0.5, 30.0) = 5.0;
// the share of the radius over which the fill rises from the apex / falls off at the rim
uniform float apex_feather : hint_range(0.0, 1.0) = 0.12;
uniform float rim_feather : hint_range(0.0, 1.0) = 0.3;
// the share of the arc, at either side, over which the fill falls off
uniform float edge_feather : hint_range(0.0, 1.0) = 0.1;
// seconds for the wedge to sweep there and back
uniform float period_s : hint_range(0.5, 20.0) = 3.5;

instance uniform float half_arc = 1.0471976;
instance uniform float phase : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float u = UV.x;
	float v = UV.y;
	float radial = smoothstep(0.0, max(apex_feather, 1e-4), v) * (1.0 - smoothstep(1.0 - rim_feather, 1.0, v));
	float side = 1.0 - smoothstep(1.0 - edge_feather, 1.0, abs(u));
	float shape = radial * side;
	float theta = half_arc * sin(6.2831853 * (TIME / period_s + phase));
	float off = abs(u * half_arc - theta);
	float wedge = 1.0 - smoothstep(0.0, radians(wedge_width_deg), off);
	ALBEDO = colour.rgb;
	ALPHA = clamp((fill_alpha + wedge_alpha * wedge) * shape * colour.a, 0.0, 1.0);
}
