// The sea's water as functions, shared by water_sea.gdshader (the sea
// itself) and water_river.gdshader (a river turns into this water over its
// last stretch, owner 2026-10-05: 把入海口附近的河水颜色渐变成海水颜色), so a
// river's mouth and the sea around it are computed by the same code and
// cannot drift apart. Every value comes in as an argument; the sea's own
// uniforms are the source of truth (water_sea.tres), and Map3DLayerRivers
// copies them into the river's material.

// Distance from the shore in pack px at a world XZ: the pack's
// world_sea_distance.png (0 on land), clamped to the canvas with the
// straight-line distance beyond it added, so `d` keeps climbing past the
// canvas boundary instead of snapping to a flat cap (a hard 1px seam).
float sea_shore_px(sampler2D sea_distance, vec2 xz, vec2 pack_origin, vec2 pack_px, float m_per_px) {
	vec2 uv = (xz - pack_origin) / m_per_px / pack_px;
	vec2 uv_clamped = clamp(uv, vec2(0.0), vec2(1.0));
	vec2 overshoot_uv = max(vec2(0.0), -uv) + max(vec2(0.0), uv - vec2(1.0));
	float beyond_px = length(overshoot_uv * pack_px);
	return texture(sea_distance, uv_clamped).r * 255.0 + beyond_px;
}

// The same distance smoothed over a ring of taps `r` pack px out: the map
// holds whole px (50 m, 8 bits), so a gradient read straight off it draws
// its contours as 50 m stair-steps; the ring's mean runs smooth between them.
float sea_shore_px_smooth(sampler2D sea_distance, vec2 xz, vec2 pack_origin, vec2 pack_px, float m_per_px,
		float r) {
	float d = sea_shore_px(sea_distance, xz, pack_origin, pack_px, m_per_px) * 2.0;
	float w = 2.0;
	for (int i = 0; i < 8; i++) {
		float a = float(i) * 0.7853982 + 0.39;
		d += sea_shore_px(sea_distance, xz + vec2(cos(a), sin(a)) * r * m_per_px, pack_origin, pack_px, m_per_px);
		w += 1.0;
	}
	return d / w;
}

// The far zoom's four flat bands by distance from the shore, hazing to the
// sky past the horizon fade. bands = (near, nearer, far, soft) in pack px;
// horizon = (start, end) in pack px.
vec3 sea_bands(float d, vec3 near, vec3 nearer, vec3 far, vec3 deep, vec3 sky, vec4 bands, vec2 horizon) {
	vec3 c = mix(near, nearer, smoothstep(bands.x - bands.w, bands.x + bands.w, d));
	c = mix(c, far, smoothstep(bands.y - bands.w, bands.y + bands.w, d));
	c = mix(c, deep, smoothstep(bands.z - bands.w, bands.z + bands.w, d));
	return mix(c, sky, smoothstep(horizon.x, horizon.y, d));
}

// The near zoom's natural water: shallow -> mid -> deep by distance from
// the shore, the distance warped by a slow world noise past the shallows.
// px = (shallow, mid, deep, warp) in pack px.
vec3 sea_natural(sampler2D ripples, vec2 xz, float d, vec3 shallow, vec3 mid, vec3 deep, vec4 px) {
	float dw = d + (texture(ripples, xz / 30000.0).x * 2.0 - 1.0) * px.w * step(px.x, d);
	vec3 cn = mix(shallow, mid, smoothstep(0.0, px.y, dw - px.x));
	return mix(cn, deep, smoothstep(px.y, px.z, dw));
}

// The sea's ripple normal at a world XZ: a slow far swell (ripple_m) and a
// fine near chop (ripple_near_m) crossfaded by near_w, both drifting.
vec3 sea_ripple_normal(sampler2D ripples, vec2 xz, float time, float ripple_m, float ripple_near_m,
		float drift_m_s, float near_w) {
	vec2 p = xz / ripple_m;
	vec3 n1 = texture(ripples, p + vec2(time * drift_m_s / ripple_m, 0.0)).xyz;
	vec3 n2 = texture(ripples, p * 0.61 + vec2(0.0, time * drift_m_s * 0.7 / ripple_m)).xyz;
	vec3 far_n = normalize(n1 + n2 - 1.0);
	vec2 q = xz / ripple_near_m;
	vec3 m1 = texture(ripples, q + vec2(time * drift_m_s / ripple_near_m, 0.0)).xyz;
	vec3 m2 = texture(ripples, q * 0.57 + vec2(0.0, -time * drift_m_s * 0.8 / ripple_near_m)).xyz;
	vec3 near_n = normalize(m1 + m2 - 1.0);
	return normalize(mix(far_n, near_n, near_w));
}

// The sea's opacity at the shore: clear on land, whole fade_px out, the
// distance warped by a fixed world noise (up to warp_px, one bump every
// warp_m) so the 50 m texels of the distance map do not facet the
// waterline. A river's mouth takes the rest (1 - this), so river and sea
// hand over at the same line.
float sea_shore_alpha(sampler2D ripples, vec2 xz, float d, float fade_px, float warp_px, float warp_m) {
	// The noise tile holds about eight bumps: one every warp_m.
	float warp = texture(ripples, xz / (warp_m * 8.0)).x * 2.0 - 1.0;
	return smoothstep(0.0, fade_px, d + warp * warp_px);
}

// The sea's light from its two colours, each already mixed with the sky by
// fresnel (and the natural one foamed): the banded colour goes out mostly
// through EMISSION with a gamma fitted to the Filmic tonemap (the palette
// arrives RAW, and the tonemap lifts a flat emissive colour), the natural
// water as itself, mostly lit. share = (emission_share, emission_share_near,
// nat_emission_share); finish = (roughness, nat_roughness, specular,
// nat_specular). Out: albedo, emission, roughness, specular.
void sea_light(vec3 band, vec3 cn, float natural, float near_w, float slope, float emission_gamma,
		float ripple_emission_gain, vec3 share, vec4 finish,
		out vec3 albedo, out vec3 emission, out float rough, out float spec) {
	vec3 lifted = pow(clamp(band, vec3(0.0001), vec3(1.0)), vec3(emission_gamma));
	lifted = mix(lifted, cn, natural);
	band = mix(band, cn, natural);
	// A ripple's slope toward or away from the light, -1..1: lights and
	// darkens the emitted colour a little, up close only.
	lifted *= 1.0 + ripple_emission_gain * near_w * slope;
	float s = mix(mix(share.x, share.y, near_w), share.z, natural);
	albedo = band * (1.0 - s);
	emission = lifted * s;
	rough = mix(finish.x, finish.y, natural);
	spec = mix(finish.z, finish.w, natural);
}
