// River water on the 3D map (spec 2026-09-18 §7). Map3DRivers lays both
// vertices of a pair on the centreline; the vertex stage widens them to the
// river's width (UV2.x, metres) or to min_px on screen far away, and lifts
// them a little so a far river is never swallowed by the relief. The
// fragment stage scrolls two ripple normals DOWNSTREAM (UV.y is metres from
// the source), mixes in the sky by fresnel, shades the mouth (UV2.y) toward
// the sea's near band, fades both edges of the ribbon so it has no hard
// rim, and (fix round 1) multiplies in COLOR.a — Map3DRivers' per-vertex
// end fade, 0 at a cut or the river's true source rising to 1, always 1 at
// the true mouth — so a split never shows as a vertical wall.
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
render_mode blend_mix, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec4 water : source_color = vec4(0.5, 0.72, 0.87, 1.0);
uniform vec4 mouth_water : source_color = vec4(0.66, 0.77, 0.71, 1.0);
uniform vec4 sky : source_color = vec4(0.66, 0.75, 0.8, 1.0);
uniform sampler2D ripples : hint_normal, filter_linear_mipmap, repeat_enable;
uniform float ripple_m = 60.0;
uniform float flow_m_s = 0.8;
uniform float px_per_dist = 0.001;
uniform float min_px = 1.5;
uniform float lift_px = 1.0;
uniform float edge_soft = 0.35;
uniform float edge_soft_floor = 0.06;
uniform float opacity = 0.92;
uniform float emission_share = 0.85;
uniform float emission_gamma = 1.3;

varying float v_across;
varying float v_along;
varying float v_width;
varying float v_mouth;
varying float v_fade;
varying float v_soft_scale;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float m_per_px = length(world - CAMERA_POSITION_WORLD) * px_per_dist;
	float drawn_half_w = max(0.5 * UV2.x, 0.5 * min_px * m_per_px);
	VERTEX += NORMAL * drawn_half_w;
	VERTEX.y += lift_px * m_per_px;
	NORMAL = vec3(0.0, 1.0, 0.0);
	v_across = UV.x;
	v_along = UV.y;
	v_width = 2.0 * drawn_half_w;
	v_mouth = UV2.y;
	v_fade = COLOR.a;
	v_soft_scale = clamp(UV2.x / max(v_width, 0.0001), edge_soft_floor, 1.0);
}

void fragment() {
	vec2 p = vec2((v_across - 0.5) * v_width, v_along) / ripple_m;
	vec3 n1 = texture(ripples, p + vec2(0.0, -TIME * flow_m_s / ripple_m)).xyz;
	vec3 n2 = texture(ripples, p * 1.7 + vec2(0.31, -TIME * flow_m_s * 1.3 / ripple_m)).xyz;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.6;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 base = mix(water.rgb, mouth_water.rgb, v_mouth);
	vec3 tinted = mix(base, sky.rgb, fres * 0.6);
	vec3 lifted = pow(clamp(tinted, vec3(0.0001), vec3(1.0)), vec3(emission_gamma));
	ALBEDO = tinted * (1.0 - emission_share);
	EMISSION = lifted * emission_share;
	ROUGHNESS = 0.18;
	SPECULAR = 0.5;
	float edge = smoothstep(0.0, edge_soft * v_soft_scale, 1.0 - abs(v_across * 2.0 - 1.0));
	ALPHA = opacity * edge * v_fade;
}
