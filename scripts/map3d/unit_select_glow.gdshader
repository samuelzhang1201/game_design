// A selected regiment piece's faint glow on the 3D map's ground (owner
// 2026-10-10: the selection is a glow under the piece, never a box or a
// number; Map3DUnitGlow): a flat quad lying on the piece's seat under its
// figures, depth-tested so they draw over it — a soft ring of warm light,
// rising from nothing at `inner` (a share of the quad's half) to its brightest
// at `peak` and fading out to the quad's rim. UV runs 0..1 across the quad.
// Owner 2026-10-12: smaller but BRIGHTER, a glow not an outline: the blend is
// PREMULTIPLIED (ALBEDO is the light added, ALPHA only a faint darkening skirt
// that lets the crest read over a bright road; one cheap quad, no extra pass),
// `gain` lifts the .tres `strength`, the crest runs hot toward white (`hot`)
// and a faint haze fills inside it. A NARROW band: `inner` (0.75) to `peak`
// (0.9) are per-piece instance uniforms set from the balance keys
// map3d_unit_glow_inner / _peak (Map3DUnitGlow). Defaults here.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_premul_alpha, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(1.0, 0.88, 0.6, 1.0);
// the glow's strength at its brightest
uniform float strength : hint_range(0.0, 1.0) = 0.45;
// the quad's half extent in metres (per piece): the band is a fixed width in
// metres measured from the SHORT half, so it is as wide at a line's ends as on its sides
instance uniform vec2 half_m = vec2(1.0, 1.0);
// the band's foot and crest, as shares of the SHORT half (per piece)
instance uniform float inner : hint_range(0.0, 1.0) = 0.75;
instance uniform float peak : hint_range(0.0, 1.0) = 0.9;
// brightness multiplier on `strength` (light can exceed 1)
uniform float gain : hint_range(0.0, 8.0) = 3.2;
// how far the crest of the band burns toward white
uniform float hot : hint_range(0.0, 1.0) = 0.55;
// the haze inside the band, as a share of the band's brightness
uniform float haze : hint_range(0.0, 1.0) = 0.25;
// the darkening skirt's alpha at its deepest
uniform float skirt : hint_range(0.0, 1.0) = 0.25;

void fragment() {
	float r = length(UV - vec2(0.5)) * 2.0;
	// s ~ 1 - (metres to the ellipse edge) / (short half): r over its gradient
	vec2 p = (UV - 0.5) * 2.0 * half_m;
	float g = length(p / (half_m * half_m)) / max(r, 1e-4);
	float s = 1.0 - (1.0 - r) / max(g, 1e-6) / min(half_m.x, half_m.y);
	float rise = smoothstep(inner, peak, s);
	float fall = 1.0 - smoothstep(peak, 1.0, s);
	float ring = rise * fall;
	float body = max(ring, haze * (1.0 - smoothstep(0.0, peak, r)) * 0.5);
	float crest = ring * ring;  // narrow bright line along the band's top
	vec3 light = mix(tint.rgb, vec3(1.0), hot * crest);
	ALBEDO = light * clamp(body * strength * gain * tint.a, 0.0, 1.0);
	// a faint dark skirt just inside the band's foot, so the crest stands off
	float dark = smoothstep(inner * 0.5, inner, s) * (1.0 - rise);
	ALPHA = clamp(dark * skirt, 0.0, 1.0);
}
