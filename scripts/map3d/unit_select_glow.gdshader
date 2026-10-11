// A selected regiment piece's faint glow on the 3D map's ground (owner
// 2026-10-10: the selection is a glow under the piece, never a box or a
// number; Map3DUnitGlow): a flat quad lying on the piece's seat under its
// figures, depth-tested so they draw over it — a soft ring of warm light,
// rising from nothing at `inner` (a share of the quad's half) to its brightest
// at `peak` and fading out to the quad's rim. UV runs 0..1 across the quad.
// Owner 2026-10-12: smaller but BRIGHTER, a glow not an outline: the blend is
// ADDITIVE (light on the ground, one cheap quad, no extra pass), `gain` lifts
// the .tres `strength`, the ring's crest runs hot toward white (`hot`) and a
// faint haze fills inside it. Defaults here; the .tres need not name them.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_add, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.88, 0.6, 1.0);
// the glow's alpha at its brightest
uniform float strength : hint_range(0.0, 1.0) = 0.45;
uniform float inner : hint_range(0.0, 1.0) = 0.35;
uniform float peak : hint_range(0.0, 1.0) = 0.75;
// brightness multiplier on `strength` (additive light can exceed 1)
uniform float gain : hint_range(0.0, 8.0) = 3.2;
// how far the crest of the ring burns toward white
uniform float hot : hint_range(0.0, 1.0) = 0.55;
// the haze inside the ring, as a share of the ring's brightness
uniform float haze : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	float rise = smoothstep(inner, peak, r);
	float fall = 1.0 - smoothstep(peak, 1.0, r);
	float ring = rise * fall;
	float body = max(ring, haze * (1.0 - smoothstep(0.0, peak, r)) * 0.5);
	float crest = ring * ring;  // narrow bright line along the ring's top
	ALBEDO = mix(tint.rgb, vec3(1.0), hot * crest);
	ALPHA = clamp(body * strength * gain * tint.a, 0.0, 1.0);
}
