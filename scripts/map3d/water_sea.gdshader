// The 3D map's sea (spec 2026-09-18 §8, fix round 1 owner 2026-09-18): the
// 2D map's four bands by distance from the shore — the pack's
// world_sea_distance.png, every pixel its distance to land in pack px, 0 on
// land — found by mapping world XZ back to pack px; slow drifting ripples;
// the sky by fresnel; and a fade to clear at the shore so the smooth coast
// shows through the shallows. One plane, one draw call, no depth texture.
//
// Fix round 1: the first pass read as saturated tropical cyan against the
// 2D map's muted scheme — a spatial material's ALBEDO is fully relit (sun +
// sky ambient + a specular highlight), which brightens and desaturates a
// flat band colour well past what it reads as on the unlit 2D map. Most of
// the band colour now goes out through EMISSION (a straight, unlit
// passthrough — matches the flat 2D paint) and only a small share through
// ALBEDO/SPECULAR (emission_share, roughness, specular, all balance.csv),
// so the water still catches a highlight and shows the ripple normal map
// without being relit into a different colour. The canvas-edge seam (a
// hard 1px jump where world_sea_distance.png's valid area ends and the
// extended plane begins, caught by the independent visual critic) is fixed
// by clamping the sample to the canvas and adding the straight-line
// distance beyond it, so `d` grows continuously past the edge instead of
// jumping straight to the 255 cap; past horizon_fade_px it also mixes
// toward the sky colour so the extended plane reads as haze, not a wall of
// flat colour, if it is ever framed.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, shadows_disabled;

// The water's maths, shared with the rivers' mouths.
#include "res://scripts/map3d/water_sea.gdshaderinc"

uniform sampler2D sea_distance : filter_linear, repeat_disable;
uniform vec2 pack_origin = vec2(0.0);
uniform vec2 pack_px = vec2(2560.0, 929.0);
uniform float m_per_px = 50.0;
uniform vec4 sea_near : source_color;
uniform vec4 sea_nearer : source_color;
uniform vec4 sea_far : source_color;
uniform vec4 sea_deep : source_color;
uniform vec4 sky : source_color;
uniform float band_near = 12.0;
uniform float band_nearer = 55.0;
uniform float band_far = 200.0;
uniform float soft = 8.0;
uniform float shore_fade_px = 0.8;
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float ripple_m = 900.0;
uniform float drift_m_s = 6.0;
uniform float emission_share = 0.85;
uniform float emission_gamma = 1.0;
uniform float roughness = 0.55;
uniform float specular = 0.12;
uniform float fresnel_sky_mix = 0.25;
uniform float horizon_fade_start_px = 1500.0;
uniform float horizon_fade_end_px = 6000.0;
// Near-zoom water (final review, owner 2026-09-18): up close the 900 m
// ripple is flat for a whole screen and the sea read as milky jade. A
// second, fine ripple layer (ripple_near_m) crossfades in as the camera
// comes closer than ripple_lod_far_m, fully in by ripple_lod_near_m; the
// ripples also modulate the EMISSION (ripple_emission_gain) — emission is
// most of the colour, so without this they only showed in the small lit
// share — and the lit share grows up close (emission_share_near) so the
// sun's highlight reads. All of it is weighted by the same near factor, so
// the far bands (24 km) are exactly what they were.
uniform float ripple_near_m = 40.0;
uniform float ripple_lod_near_m = 1500.0;
uniform float ripple_lod_far_m = 8000.0;
uniform float ripple_emission_gain = 0.1;
uniform float emission_share_near = 0.6;
// The shore's alpha fade reads `d` off a 50 m-per-texel distance map, so up
// close the waterline is a chain of straight 50 m facets. A fixed world
// noise warps `d` by up to shore_warp_px (pack px) before the fade — a
// stopgap until a finer coast coverage map exists.
uniform float shore_warp_px = 0.5;
uniform float shore_warp_m = 160.0;
// NATURAL WATER NEAR, BANDS FAR (owner 2026-09-24, the look route's Phase 3,
// spec 2026-09-24-map3d-humankind-look-gap §2.6): `natural` (0..1, set by
// the layer from the camera's distance) crossfades the flat bands into
// natural water — a continuous shallow -> mid -> deep gradient by distance
// from the shore, mostly LIT (a small emission share, a glossy surface) so
// it takes the sun's highlight and the sky's reflection, with a line of
// drifting foam along the shore. At natural 0 the bands are exactly what
// they were.
uniform float natural = 0.0;
uniform vec4 nat_shallow : source_color = vec4(0.24, 0.5, 0.52, 1.0);
uniform vec4 nat_mid : source_color = vec4(0.12, 0.33, 0.45, 1.0);
uniform vec4 nat_deep : source_color = vec4(0.06, 0.18, 0.29, 1.0);
uniform float nat_shallow_px = 2.0;
uniform float nat_mid_px = 20.0;
uniform float nat_deep_px = 90.0;
uniform float nat_warp_px = 3.0;
uniform float nat_emission_share = 0.35;
uniform float nat_roughness = 0.18;
uniform float nat_specular = 0.5;
uniform float nat_fresnel_sky_mix = 0.45;
uniform vec4 foam : source_color = vec4(0.93, 0.95, 0.93, 1.0);
uniform float foam_px = 0.7;
uniform float foam_strength = 0.6;
// The colours' distance smoothed over a ring this many pack px out (0: raw).
uniform float smooth_px = 0.0;
// How far a ripple's slope lights and darkens the natural water up close.
uniform float nat_ripple_gain = 0.0;
// Wind lanes on the open water: how far they lift toward the sky, and their size.
uniform float nat_sheen = 0.0;
uniform float nat_sheen_m = 2400.0;
uniform float nat_sheen_far_m = 4000.0;  // gone by this camera distance

varying vec2 v_xz;

float sea_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Value noise in 0..1, smooth between whole-number lattice points.
float sea_value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(sea_hash(i), sea_hash(i + vec2(1.0, 0.0)), u.x),
		mix(sea_hash(i + vec2(0.0, 1.0)), sea_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	v_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float d = sea_shore_px(sea_distance, v_xz, pack_origin, pack_px, m_per_px);
	// the colours read a smoothed distance (no 50 m contour steps); the
	// waterline keeps the sharp one, which the river's mouth shares
	float ds = mix(d, sea_shore_px_smooth(sea_distance, v_xz, pack_origin, pack_px, m_per_px, smooth_px),
		smoothstep(0.0, smooth_px * 2.0, d));
	vec3 c = sea_bands(ds, sea_near.rgb, sea_nearer.rgb, sea_far.rgb, sea_deep.rgb, sky.rgb,
		vec4(band_near, band_nearer, band_far, soft), vec2(horizon_fade_start_px, horizon_fade_end_px));
	float near_w = 1.0 - smoothstep(ripple_lod_near_m, ripple_lod_far_m, length(VERTEX));
	vec3 n = sea_ripple_normal(ripples, v_xz, TIME, ripple_m, ripple_near_m, drift_m_s, near_w);
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.4;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	vec3 band = mix(c, sky.rgb, fres * fresnel_sky_mix);
	// natural water: a continuous gradient by distance from the shore
	vec3 cn = sea_natural(ripples, v_xz, ds, nat_shallow.rgb, nat_mid.rgb, nat_deep.rgb,
		vec4(nat_shallow_px, nat_mid_px, nat_deep_px, nat_warp_px));
	cn = mix(cn, sky.rgb, fres * nat_fresnel_sky_mix);
	// wind lanes: broad slicks of calmer, brighter water drifting over the
	// sea, the way open water reads from a height (two slow octaves)
	vec2 sq = v_xz / nat_sheen_m + vec2(TIME * 0.0006, TIME * 0.0002);
	float sheen = sea_value_noise(sq * vec2(1.0, 2.6)) * 0.65 + sea_value_noise(sq * 2.3 + vec2(5.2, 1.7)) * 0.35;
	// up close only: farther out the lanes shrink into a mottle like cloud shadow
	float near_k = 1.0 - smoothstep(nat_sheen_far_m * 0.4, nat_sheen_far_m, length(VERTEX));
	cn = mix(cn, sky.rgb, nat_sheen * near_k * smoothstep(0.35, 0.8, sheen) * smoothstep(nat_shallow_px, nat_mid_px, ds));
	// foam: a broken line along the shore, drifting with the ripples
	float foam_noise = texture(ripples, v_xz / 220.0 + vec2(TIME * 0.004, 0.0)).x;
	float foam_break = texture(ripples, v_xz / 1800.0).y;
	float foam_line = (1.0 - smoothstep(0.0, foam_px, d)) * smoothstep(0.45, 0.8, foam_noise)
		* smoothstep(0.35, 0.65, foam_break);
	cn = mix(cn, foam.rgb, clamp(foam_line * foam_strength, 0.0, 1.0));
	// The palette colours arrive RAW (a Color uniform set from GDScript
	// passes straight through under GL Compatibility), and the environment's
	// Filmic tonemap LIFTS a flat EMISSION colour (0.5 -> 162/255), more in
	// the darker channels. emission_gamma (> 1 darkens the darker channels
	// more) undoes that lift well enough to land back near the flat 2D hex
	// (final review, owner 2026-09-18: fitted by sampling rendered bands
	// against the palette at 24 km; refit it if the tonemap changes).
	float slope = clamp((n.x - n.y) * 2.0, -1.0, 1.0);
	vec3 albedo;
	vec3 emission;
	float rough;
	float spec;
	sea_light(band, cn, natural, near_w, slope, emission_gamma, ripple_emission_gain,
		vec3(emission_share, emission_share_near, nat_emission_share),
		vec4(roughness, nat_roughness, specular, nat_specular), albedo, emission, rough, spec);
	// up close the natural water's own light follows its ripples: a lit
	// share alone, under one even sky, left the sea a flat plastic sheet
	float rk = 1.0 + nat_ripple_gain * slope * natural * near_w;
	ALBEDO = albedo * rk;
	EMISSION = emission * rk;
	ROUGHNESS = rough;
	SPECULAR = spec;
	ALPHA = sea_shore_alpha(ripples, v_xz, d, shore_fade_px, shore_warp_px, shore_warp_m);
}
