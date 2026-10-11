// A BROKEN supply line on the WAR ROOM's sheet (WarSupplyFlow.broken_lines;
// owner 2026-10-11): a FRONT line — its town ahead of the column — inked as
// dark dashes from its town along the road, stopping short of the column's
// piece, and a solid tick across the road where it breaks. The mesh is the
// flowing line's ribbon (WarSupplyFlow.ribbon): two vertices at each point
// ON the line, NORMAL the side each grows toward, pushed `width_m` apart and
// lifted `lift_m` off the sheet; UV.x the metres along the line from the
// town, UV.y 0..1 across. A dash is `dash_m` long every `dash_m + gap_m`; a
// NEGATIVE UV.x (the tick) is drawn whole. Still — nothing flows on a broken
// line. Table metres, so it lies on the sheet like its ink.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, shadows_disabled, fog_disabled;

uniform vec4 colour : source_color = vec4(0.17, 0.11, 0.06, 0.9);   // dark umber ink
uniform float width_m = 0.003;
uniform float lift_m = 0.0006;
uniform float dash_m = 0.012;
uniform float gap_m = 0.007;

void vertex() {
	VERTEX += NORMAL * (0.5 * width_m);
	VERTEX.y += lift_m;
	NORMAL = vec3(0.0, 1.0, 0.0);
}

void fragment() {
	float across = abs(UV.y * 2.0 - 1.0);
	float aa = max(fwidth(across), 0.0001);
	float period = max(dash_m + gap_m, 0.0001);
	if (UV.x >= 0.0 && mod(UV.x, period) >= dash_m) {
		discard;
	}
	ALBEDO = colour.rgb;
	ALPHA = colour.a * smoothstep(1.0, 1.0 - aa * 1.5, across);
}
