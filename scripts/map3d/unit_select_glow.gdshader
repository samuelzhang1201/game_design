// A selected regiment piece's faint glow on the 3D map's ground (owner
// 2026-10-10: the selection is a glow under the piece, never a box or a
// number; Map3DUnitGlow): a flat quad lying on the piece's seat under its
// figures, depth-tested so they draw over it — a soft ring of warm light,
// rising from nothing at `inner` (a share of the quad's half) to its brightest
// at `peak` and fading out to the quad's rim. UV runs 0..1 across the quad.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.88, 0.6, 1.0);
// the glow's alpha at its brightest
uniform float strength : hint_range(0.0, 1.0) = 0.45;
uniform float inner : hint_range(0.0, 1.0) = 0.35;
uniform float peak : hint_range(0.0, 1.0) = 0.75;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float rise = smoothstep(inner, peak, r);
	float fall = 1.0 - smoothstep(peak, 1.0, r);
	ALBEDO = tint.rgb;
	ALPHA = rise * fall * strength * tint.a;
}
