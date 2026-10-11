// River water on the 3D map (spec 2026-09-18 §7). Map3DRivers lays both
// vertices of a pair on the centreline; the vertex stage widens them to the
// river's width (UV2.x, metres) or to min_px on screen far away, and lifts
// them a little so a far river is never swallowed by the relief. The
// fragment stage scrolls two ripple normals DOWNSTREAM (UV.y is metres from
// the source), mixes in the sky by fresnel, shades the mouth (UV2.y) toward
// the sea's near band, fades both edges of the ribbon so it has no hard
// rim, and (fix round 1) multiplies in COLOR.a — Map3DRivers' per-vertex
// end fade, 0 at a cut or the river's true source rising to 1, falling to 0
// again only over the true mouth's run-out into the sea — so a split never
// shows as a vertical wall.
//
// `water` / `mouth_water` / `sky` are terrain_palette hex, set RAW (final
// review, owner 2026-09-18: a Color uniform set from GDScript passes
// straight through under GL Compatibility; the environment's Filmic
// tonemap is what lifts a flat emissive colour, and emission_gamma > 1 is
// fitted to it, as on the sea). Fix round 1: at a far zoom the min-px floor widens a
// thin river on screen, but edge_soft was a FIXED FRACTION of whatever
// width got drawn — so a heavily widened thread faded almost its whole
// width and read as a thin, near-black line (the darkened riverbed ground
// underneath, `river_wet_darken`, showing through a barely-opaque
// ribbon). v_soft_scale is real width / drawn width (1 when never
// widened), so the fade shrinks to the thread's true edge in screen terms
// and a min-width river keeps an opaque core. That alone still read dark at
// 24km (sampled ~(24,55,83) against the river hex's ~(127,184,221)): the
// ribbon's own ALBEDO, fully relit like the sea's first pass was, comes out
// far dimmer than the flat colour once its NORMAL_MAP is a few ripple
// cycles per pixel at that distance (a near-random, often grazing normal
// per pixel, not the mippped-flat average a wider surface gets) — so most
// of its light scatters away from the camera instead of back at it. Same
// medicine as the sea: most of the colour goes out through EMISSION
// (unlit, immune to the ripple normal's lighting response) with a gamma
// fitted to the environment's Filmic tonemap, and only a small ALBEDO/SPECULAR
// share is left to catch a highlight.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled;

// The sea's water, which a river turns into over its last stretch.
#include "res://scripts/map3d/water_sea.gdshaderinc"

uniform vec4 water : source_color = vec4(0.5, 0.72, 0.87, 1.0);
uniform vec4 mouth_water : source_color = vec4(0.66, 0.77, 0.71, 1.0);
uniform vec4 sky : source_color = vec4(0.66, 0.75, 0.8, 1.0);
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float ripple_m = 60.0;
uniform float flow_m_s = 0.8;
uniform float px_per_dist = 0.001;
uniform float min_px = 1.5;
// The floor grows with the river (critic 2026-10-06: one-width ribbons — at
// the opening zoom a screen px is ~25 m and most courses are narrower, so
// every one drew at the same floor, source to mouth). A river of floor_ref_m
// gets min_px; the floor scales as (width / floor_ref_m)^floor_gamma, held
// within floor_lo..floor_hi of min_px, so a main river reads broad and its
// upper course thin. Under one px the thread is drawn a px wide but fainter
// by its coverage, never below thin_alpha_min: a small river thins, it does
// not vanish.
uniform float floor_ref_m = 60.0;
uniform float floor_gamma = 0.0;
uniform float floor_lo = 1.0;
uniform float floor_hi = 1.0;
uniform float thin_alpha_min = 1.0;
uniform float lift_px = 1.0;
uniform float edge_soft = 0.35;
uniform float edge_soft_floor = 0.06;
uniform float opacity = 0.92;
uniform float emission_share = 0.85;
uniform float emission_gamma = 1.3;
// Near-zoom water (final review, owner 2026-09-18): the look numbers are
// data (screens/map3d/balance.csv map3d_river_*), the sky mix matches the sea's so both
// read as one water, the ripples modulate the EMISSION as on the sea, and a
// world-space noise wobbles the bank fade so a river's edge is soft and
// irregular up close rather than ruled. The wobble and the ripple
// modulation fade out with camera distance over the SEA's LOD distances
// (lod_near_m -> lod_far_m) so a far thread stays a clean line.
uniform float fresnel_sky_mix = 0.25;
uniform float fresnel_power = 4.0;
uniform float roughness = 0.18;
uniform float specular = 0.5;
uniform float normal_depth = 0.6;
uniform float ripple_emission_gain = 0.1;
uniform float bank_wobble_m = 40.0;
uniform float bank_wobble_amp = 0.15;
uniform float lod_near_m = 1500.0;
uniform float lod_far_m = 8000.0;
// Natural water near (owner 2026-09-24, look route Phase 3): the sea's
// `natural` share, a natural river colour and mouth, lit like the sea.
uniform float natural = 0.0;
uniform vec4 nat_water : source_color = vec4(0.2, 0.37, 0.42, 1.0);
uniform vec4 nat_mouth : source_color = vec4(0.27, 0.44, 0.43, 1.0);
uniform float nat_emission_share = 0.15;
// Falls (visual review 2026-10-05): where a river drops off a cliff its
// ribbon lay down the cliff face as a wide translucent blue sheet, which
// read as paint smeared over the bridge in front of it. Where the water
// falls more than fall_grade_from (rise over run along the river), it turns
// to white water and narrows to fall_width of its breadth by fall_grade_to —
// up close only (the ripples' LOD), where a fall is big enough to read.
uniform float fall_grade_from = 0.4;
uniform float fall_grade_to = 0.9;
uniform vec4 fall_foam : source_color = vec4(0.88, 0.91, 0.9, 1.0);
uniform float fall_width = 0.55;
uniform float fall_opacity = 0.8;
// how far toward the foam a full fall turns (the river's own water shows through)
uniform float fall_foam_mix = 0.7;
uniform float fall_streaks = 6.0;  // streaks across a fall's width
// The wet bank: its share of the half-width from each edge, colour and strength.
uniform float bank_share = 0.35;
uniform vec4 bank_color : source_color = vec4(0.2, 0.17, 0.11, 1.0);
uniform float bank_mix = 0.0;
uniform float depth_mix = 0.0;  // how much darker the channel's middle is

// One water at the mouth (owner 2026-10-05: 把入海口附近的河水颜色渐变成海水颜色).
// Tinting the river toward the sea's near colour (mouth_water / nat_mouth)
// was not enough: at the playing zoom the sea is natural water — mostly lit
// and glossy, darkening from the shore outward, with its own drifting
// ripple — while the river emitted half its flat colour and flowed, so its
// run-out into the sea read as a grey plume. Over the mouth's ramp (UV2.y,
// from mouth_sea_from to 1 at the run-out's tip) the river's whole surface
// — colour, light, ripple, opacity — turns into the sea's own, computed by
// the sea's code (water_sea.gdshaderinc) at the river's own XZ. Every sea_*
// uniform is the sea's, copied from water_sea.tres by Map3DLayerRivers;
// only mouth_sea_from and mouth_opacity are the river's (from 0.2: the
// critic's pick of 0.2 / 0.5 / 0.8 — 0.8 left a lighter band at the shore).
// It runs on into the sea as the sea's own water and needs no handover at
// the waterline: giving way to the sea there (by the sea's shore fade, then
// only where the sea was opaque and over sunk ground) showed the sea's own
// speckled shore band across the mouth, and before the river wore the sea's
// swell and shelf, a flat tongue past it (critic 2026-10-06). The run-out's
// own fade (Map3DRivers) ends it, out over the water.
uniform float mouth_sea_from = 0.2;
uniform float mouth_opacity = 1.0;
uniform sampler2D sea_distance : filter_linear, repeat_disable;
uniform vec2 sea_pack_origin = vec2(0.0);
uniform vec2 sea_pack_px = vec2(2560.0, 929.0);
uniform float sea_m_per_px = 50.0;
uniform vec4 sea_near : source_color;
uniform vec4 sea_nearer : source_color;
uniform vec4 sea_far : source_color;
uniform vec4 sea_deep : source_color;
uniform float sea_band_near = 12.0;
uniform float sea_band_nearer = 55.0;
uniform float sea_band_far = 200.0;
uniform float sea_soft = 8.0;
uniform float sea_horizon_fade_start_px = 1500.0;
uniform float sea_horizon_fade_end_px = 6000.0;
uniform float sea_ripple_m = 900.0;
uniform float sea_ripple_near_m = 40.0;
uniform float sea_drift_m_s = 6.0;
uniform float sea_ripple_emission_gain = 0.1;
uniform float sea_emission_share = 0.85;
uniform float sea_emission_share_near = 0.6;
uniform float sea_emission_gamma = 1.0;
uniform float sea_roughness = 0.55;
uniform float sea_specular = 0.12;
uniform float sea_fresnel_sky_mix = 0.25;
uniform vec4 sea_nat_shallow : source_color;
uniform vec4 sea_nat_mid : source_color;
uniform vec4 sea_nat_deep : source_color;
uniform float sea_nat_shallow_px = 2.0;
uniform float sea_nat_mid_px = 20.0;
uniform float sea_nat_deep_px = 90.0;
uniform float sea_nat_warp_px = 3.0;
uniform float sea_nat_emission_share = 0.35;
uniform float sea_nat_roughness = 0.18;
uniform float sea_nat_specular = 0.5;
uniform float sea_nat_fresnel_sky_mix = 0.45;
uniform float sea_smooth_px = 0.0;
uniform float sea_nat_ripple_gain = 0.0;
uniform float sea_nat_sheen = 0.0;
uniform float sea_nat_sheen_m = 2400.0;
uniform float sea_nat_sheen_far_m = 4000.0;
uniform vec4 sea_nat_shelf : source_color = vec4(0.3, 0.46, 0.4, 1.0);
uniform float sea_nat_shelf_px = 6.0;
uniform float sea_nat_shelf_mix = 0.0;
uniform float sea_nat_shelf_far_m = 9000.0;

varying float v_across;
varying float v_along;
varying float v_width;
varying float v_mouth;
varying float v_fade;
varying float v_soft_scale;
varying vec2 v_xz;
varying float v_y;
varying float v_thin;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float m_per_px = length(world - CAMERA_POSITION_WORLD) * px_per_dist;
	float floor_px = min_px * clamp(pow(max(UV2.x, 0.01) / floor_ref_m, floor_gamma), floor_lo, floor_hi);
	float true_px = max(UV2.x / max(m_per_px, 0.0001), floor_px);
	v_thin = max(thin_alpha_min, clamp(true_px, 0.0, 1.0));
	float drawn_half_w = max(0.5 * UV2.x, 0.5 * max(floor_px, 1.0) * m_per_px);
	VERTEX += NORMAL * drawn_half_w;
	v_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
	VERTEX.y += lift_px * m_per_px;
	v_y = world.y;
	NORMAL = vec3(0.0, 1.0, 0.0);
	// The ribbon carries no tangents (Map3DRivers builds none), and a
	// NORMAL_MAP without them lights the water from a broken frame, so its
	// lit share came out dark — invisible while the river was mostly
	// emission, a dark band once its mouth turns into the mostly lit sea.
	// The sea's PlaneMesh frame: +X along, -Z across.
	TANGENT = vec3(1.0, 0.0, 0.0);
	BINORMAL = vec3(0.0, 0.0, -1.0);
	v_across = UV.x;
	v_along = UV.y;
	v_width = 2.0 * drawn_half_w;
	v_mouth = UV2.y;
	v_fade = COLOR.a;
	v_soft_scale = clamp(UV2.x / max(v_width, 0.0001), edge_soft_floor, 1.0);
}

void fragment() {
	float near_w = 1.0 - smoothstep(lod_near_m, lod_far_m, length(VERTEX));
	vec2 p = vec2((v_across - 0.5) * v_width, v_along) / ripple_m;
	vec3 n1 = texture(ripples, p + vec2(0.0, -TIME * flow_m_s / ripple_m)).xyz;
	vec3 n2 = texture(ripples, p * 1.7 + vec2(0.31, -TIME * flow_m_s * 1.3 / ripple_m)).xyz;
	vec3 n = normalize(n1 + n2 - 1.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), fresnel_power);
	vec3 base = mix(water.rgb, mouth_water.rgb, v_mouth);
	vec3 tinted = mix(base, sky.rgb, fres * fresnel_sky_mix);
	vec3 lifted = pow(clamp(tinted, vec3(0.0001), vec3(1.0)), vec3(emission_gamma));
	vec3 nat = mix(mix(nat_water.rgb, nat_mouth.rgb, v_mouth), sky.rgb, fres * fresnel_sky_mix);
	tinted = mix(tinted, nat, natural);
	lifted = mix(lifted, nat, natural);
	float slope = clamp((n.x - n.y) * 2.0, -1.0, 1.0);
	lifted *= 1.0 + ripple_emission_gain * near_w * slope;
	float share = mix(emission_share, nat_emission_share, natural);
	// how steeply the water falls here: its height's change per metre of course
	float run = length(vec2(dFdx(v_along), dFdy(v_along)));
	float fall = smoothstep(fall_grade_from, fall_grade_to,
		length(vec2(dFdx(v_y), dFdy(v_y))) / max(run, 0.0001)) * near_w;
	tinted = mix(tinted, fall_foam.rgb, fall * fall_foam_mix);
	lifted = mix(lifted, fall_foam.rgb, fall * fall_foam_mix);
	// The sea's own surface here, and how far the river has become it (a
	// fall into the sea stays white water).
	float to_sea = smoothstep(mouth_sea_from, 1.0, v_mouth) * (1.0 - fall);
	float d = sea_shore_px(sea_distance, v_xz, sea_pack_origin, sea_pack_px, sea_m_per_px);
	vec3 sea_n = sea_ripple_normal(ripples, v_xz, TIME, sea_ripple_m, sea_ripple_near_m, sea_drift_m_s, near_w);
	float sea_fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	float ds = sea_colour_px(sea_distance, v_xz, sea_pack_origin, sea_pack_px, sea_m_per_px, d, sea_smooth_px);
	vec3 band = sea_bands(ds, sea_near.rgb, sea_nearer.rgb, sea_far.rgb, sea_deep.rgb, sky.rgb,
		vec4(sea_band_near, sea_band_nearer, sea_band_far, sea_soft),
		vec2(sea_horizon_fade_start_px, sea_horizon_fade_end_px));
	band = mix(band, sky.rgb, sea_fres * sea_fresnel_sky_mix);
	vec3 cn = sea_natural(ripples, v_xz, ds, sea_nat_shallow.rgb, sea_nat_mid.rgb, sea_nat_deep.rgb,
		vec4(sea_nat_shallow_px, sea_nat_mid_px, sea_nat_deep_px, sea_nat_warp_px));
	cn = mix(cn, sky.rgb, sea_fres * sea_nat_fresnel_sky_mix);
	cn = sea_near_shore(cn, sky.rgb, v_xz, ds, length(VERTEX), TIME, sea_nat_shelf.rgb,
		vec3(sea_nat_shelf_px, sea_nat_shelf_mix, sea_nat_shelf_far_m),
		vec3(sea_nat_sheen, sea_nat_sheen_m, sea_nat_sheen_far_m), vec2(sea_nat_shallow_px, sea_nat_mid_px));
	vec3 sea_albedo;
	vec3 sea_emission;
	float sea_rough;
	float sea_spec;
	sea_light(band, cn, natural, near_w, clamp((sea_n.x - sea_n.y) * 2.0, -1.0, 1.0),
		sea_emission_gamma, sea_ripple_emission_gain, sea_nat_ripple_gain,
		vec3(sea_emission_share, sea_emission_share_near, sea_nat_emission_share),
		vec4(sea_roughness, sea_nat_roughness, sea_specular, sea_nat_specular),
		sea_albedo, sea_emission, sea_rough, sea_spec);
	NORMAL_MAP = normalize(mix(n, sea_n, to_sea)) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = mix(normal_depth, 0.4, to_sea);
	ALBEDO = mix(tinted * (1.0 - share), sea_albedo, to_sea);
	EMISSION = mix(lifted * share, sea_emission, to_sea);
	ROUGHNESS = mix(roughness, sea_rough, to_sea);
	SPECULAR = mix(specular, sea_spec, to_sea);
	// 0 at either bank, 1 on the centreline; the wobble pushes the bank in
	// and out along the river by up to bank_wobble_amp of the half-width.
	float across = 1.0 - abs(v_across * 2.0 - 1.0);
	// a fall is narrower than its river: the bank fade moves in
	across = (across - fall * (1.0 - fall_width)) / max(1.0 - fall * (1.0 - fall_width), 0.0001);
	// The noise tile holds about eight bumps: one every bank_wobble_m.
	float wobble = texture(ripples, v_xz / (bank_wobble_m * 8.0)).x * 2.0 - 1.0;
	across += wobble * bank_wobble_amp * near_w;
	float edge = smoothstep(0.0, edge_soft * v_soft_scale + bank_wobble_amp * near_w, across);
	// deeper mid-stream: the channel darkens toward its centre, shallow and
	// a touch greener at the sides (gone where the river has become the sea)
	float deep = smoothstep(0.15, 0.9, across) * depth_mix * (1.0 - to_sea);
	ALBEDO *= 1.0 - 0.5 * deep;
	EMISSION *= 1.0 - deep;
	// a wet earthen bank inside each edge, so the water sits IN the land and
	// is not a stroke laid on it (gone where the river has become the sea)
	float bank = (1.0 - smoothstep(0.0, bank_share, across)) * bank_mix * (1.0 - to_sea);
	ALBEDO = mix(ALBEDO, bank_color.rgb, bank);
	EMISSION *= 1.0 - bank;
	// a fall's water in streaks running down it, white where it breaks
	float streak = texture(ripples, vec2(v_across * fall_streaks / 8.0, v_along / 30.0 - TIME * 0.35)).x;
	ALBEDO = mix(ALBEDO, fall_foam.rgb, fall * smoothstep(0.45, 0.75, streak) * 0.6);
	ALPHA = mix(mix(opacity, mouth_opacity, to_sea), fall_opacity, fall) * edge * v_fade
		* mix(1.0, 0.35 + 0.9 * streak, fall) * v_thin;
}
