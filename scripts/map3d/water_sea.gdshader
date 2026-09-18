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

varying vec2 v_xz;

void vertex() {
	v_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = (v_xz - pack_origin) / m_per_px / pack_px;
	vec2 uv_clamped = clamp(uv, vec2(0.0), vec2(1.0));
	// How far uv sits outside [0,1] on each axis (0 inside the canvas),
	// turned into pack px — added onto the sampled edge distance so `d`
	// keeps climbing past the canvas boundary instead of snapping straight
	// to the outside branch's flat cap, which read as a hard 1px seam.
	vec2 overshoot_uv = max(vec2(0.0), -uv) + max(vec2(0.0), uv - vec2(1.0));
	float beyond_px = length(overshoot_uv * pack_px);
	float d = texture(sea_distance, uv_clamped).r * 255.0 + beyond_px;
	vec3 c = mix(sea_near.rgb, sea_nearer.rgb, smoothstep(band_near - soft, band_near + soft, d));
	c = mix(c, sea_far.rgb, smoothstep(band_nearer - soft, band_nearer + soft, d));
	c = mix(c, sea_deep.rgb, smoothstep(band_far - soft, band_far + soft, d));
	c = mix(c, sky.rgb, smoothstep(horizon_fade_start_px, horizon_fade_end_px, d));
	float near_w = 1.0 - smoothstep(ripple_lod_near_m, ripple_lod_far_m, length(VERTEX));
	vec2 p = v_xz / ripple_m;
	vec3 n1 = texture(ripples, p + vec2(TIME * drift_m_s / ripple_m, 0.0)).xyz;
	vec3 n2 = texture(ripples, p * 0.61 + vec2(0.0, TIME * drift_m_s * 0.7 / ripple_m)).xyz;
	vec3 far_n = normalize(n1 + n2 - 1.0);
	vec2 q = v_xz / ripple_near_m;
	vec3 m1 = texture(ripples, q + vec2(TIME * drift_m_s / ripple_near_m, 0.0)).xyz;
	vec3 m2 = texture(ripples, q * 0.57 + vec2(0.0, -TIME * drift_m_s * 0.8 / ripple_near_m)).xyz;
	vec3 near_n = normalize(m1 + m2 - 1.0);
	vec3 n = normalize(mix(far_n, near_n, near_w));
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.4;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	vec3 band = mix(c, sky.rgb, fres * fresnel_sky_mix);
	// The palette colours arrive RAW (a Color uniform set from GDScript
	// passes straight through under GL Compatibility), and the environment's
	// Filmic tonemap LIFTS a flat EMISSION colour (0.5 -> 162/255), more in
	// the darker channels. A per-channel gamma (> 1 darkens the darker
	// channels more) undoes that lift well enough to land back near the flat
	// 2D hex (final review, owner 2026-09-18: fitted by sampling rendered
	// bands against the palette at 24 km; the gamma is fitted to THIS
	// tonemap — change the tonemap and refit it).
	vec3 lifted = pow(clamp(band, vec3(0.0001), vec3(1.0)), vec3(emission_gamma));
	// A ripple's slope toward or away from the light, -1..1: lights and
	// darkens the emitted colour a little, up close only.
	float slope = clamp((n.x - n.y) * 2.0, -1.0, 1.0);
	lifted *= 1.0 + ripple_emission_gain * near_w * slope;
	float share = mix(emission_share, emission_share_near, near_w);
	ALBEDO = band * (1.0 - share);
	EMISSION = lifted * share;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	// The noise tile holds about eight bumps: one every shore_warp_m.
	float warp = texture(ripples, v_xz / (shore_warp_m * 8.0)).x * 2.0 - 1.0;
	ALPHA = smoothstep(0.0, shore_fade_px, d + warp * shore_warp_px);
}
