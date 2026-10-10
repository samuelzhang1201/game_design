// A selected piece's faint glow on the WAR ROOM's table (WarPieces.show_selected;
// owner 2026-10-10: 只要玩家点选的单位下方有一个淡淡的光圈即可): a flat quad
// lying under the piece, a soft ring of light on the table just beyond the
// plinth's edge (`edge`, the plinth's share of the quad's half, set per
// piece): rising from the edge to its brightest `gap` further out, then
// fading `outer_soft` over the table. `tint` is the side's colour,
// lightened (per piece); `strength` is how faint the whole glow is. UV runs
// 0..1 across the quad.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

instance uniform vec4 tint : source_color = vec4(0.75, 0.85, 1.0, 1.0);
instance uniform float edge = 0.75;
// the glow's alpha at its brightest
uniform float strength : hint_range(0.0, 1.0) = 0.3;
// how far past the plinth's edge the ring is brightest, and how far it then
// fades over the table, in shares of the quad's half
uniform float gap : hint_range(0.0, 1.0) = 0.12;
uniform float outer_soft : hint_range(0.0, 1.0) = 0.3;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float peak = edge + gap;
	float rise = smoothstep(edge, peak, r);
	float fall = 1.0 - smoothstep(peak, min(peak + outer_soft, 1.0), r);
	ALBEDO = tint.rgb;
	ALPHA = rise * fall * strength * tint.a;
}
