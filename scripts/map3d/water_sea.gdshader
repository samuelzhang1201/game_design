// The 3D map's sea (spec 2026-09-18 §8, fix round 1 owner 2026-09-18): the
// 2D map's four bands by distance from the shore — the pack's
// world_sea_distance.png, every pixel its distance to land in pack px, 0 on
// land — found by mapping world XZ back to pack px; slow drifting ripples;
// the sky by fresnel; and a fade to clear at the shore so the smooth coast
// shows through the shallows. One plane, one draw call; near the coast it
// reads the depth buffer for the ground under it (shore_depth_m).
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
// The finer coast (owner 2026-10-06: the square grass edges beside a river's
// mouth): within shore_reach_px of the map's coast the sea is also drawn
// wherever the real ground lies under its surface — read from the depth
// buffer, whole by shore_depth_m of water — so the waterline follows the
// terrain's own 20 m contour. Off the raster alone, the carved banks beside
// a mouth sank under the sea's level where the map said land, and the land
// showed cut in 50 m blocks: a right-angled notch and a dead-straight shore.
// Near only, gone by a camera shore_depth_far_m away: far out Terrain3D
// draws a coarser mesh whose ground dipped under the beaches and drowned
// the pale shore ring the far view keeps.
uniform float shore_reach_px = 3.0;
uniform float shore_depth_m = 1.0;
uniform float shore_depth_far_m = 12000.0;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
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
// The near shelf: its colour, how far out (pack px) and strongly, gone by a camera this far.
uniform vec4 nat_shelf : source_color = vec4(0.3, 0.46, 0.4, 1.0);
uniform float nat_shelf_px = 6.0;
uniform float nat_shelf_mix = 0.0;
uniform float nat_shelf_far_m = 9000.0;

varying vec2 v_xz;

void vertex() {
	v_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	float d = sea_shore_px(sea_distance, v_xz, pack_origin, pack_px, m_per_px);
	// the colours read a smoothed distance (no 50 m contour steps); the
	// waterline keeps the sharp one, which the river's mouth shares
	float ds = sea_colour_px(sea_distance, v_xz, pack_origin, pack_px, m_per_px, d, smooth_px);
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
	cn = sea_near_shore(cn, sky.rgb, v_xz, ds, length(VERTEX), TIME, nat_shelf.rgb,
		vec3(nat_shelf_px, nat_shelf_mix, nat_shelf_far_m), vec3(nat_sheen, nat_sheen_m, nat_sheen_far_m),
		vec2(nat_shallow_px, nat_mid_px));
	// foam: a broken line along the shore, drifting with the ripples
	float foam_noise = texture(ripples, v_xz / 220.0 + vec2(TIME * 0.004, 0.0)).x;
	float foam_break = texture(ripples, v_xz / 1800.0).y;
	float foam_line = (1.0 - smoothstep(0.0, foam_px, d)) * smoothstep(0.45, 0.8, foam_noise)
		* smoothstep(0.35, 0.65, foam_break);
	// only where the map's own coast drew the sea: on the water the finer
	// coast adds (shore_depth_m) the line lay on the ground the map calls land
	foam_line *= sea_shore_alpha(ripples, v_xz, d, shore_fade_px, shore_warp_px, shore_warp_m);
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
	sea_light(band, cn, natural, near_w, slope, emission_gamma, ripple_emission_gain, nat_ripple_gain,
		vec3(emission_share, emission_share_near, nat_emission_share),
		vec4(roughness, nat_roughness, specular, nat_specular), albedo, emission, rough, spec);
	ALBEDO = albedo;
	EMISSION = emission;
	ROUGHNESS = rough;
	SPECULAR = spec;
	// the ground under this pixel (the sea is drawn only where the plane is in
	// front of it, so it lies at or under the surface), in world metres
	vec4 under = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, texture(depth_texture, SCREEN_UV).x, 1.0);
	float water_m = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).y - (INV_VIEW_MATRIX * vec4(under.xyz / under.w, 1.0)).y;
	float near_coast = smoothstep(0.0, 0.25,
		sea_shore_px_smooth(sea_distance, v_xz, pack_origin, pack_px, m_per_px, shore_reach_px))
		* (1.0 - smoothstep(shore_depth_far_m * 0.4, shore_depth_far_m, length(VERTEX)));
	ALPHA = max(sea_shore_alpha(ripples, v_xz, d, shore_fade_px, shore_warp_px, shore_warp_m),
		near_coast * smoothstep(0.0, shore_depth_m, water_m));
}
