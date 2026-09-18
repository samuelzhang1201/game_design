// The 3D map's sea (spec 2026-09-18 §8): the 2D map's four bands by distance
// from the shore — the pack's world_sea_distance.png, every pixel its
// distance to land in pack px, 0 on land — found by mapping world XZ back to
// pack px; slow drifting ripples; the sky by fresnel; and a fade to clear at
// the shore so the smooth coast shows through the shallows. One plane, one
// draw call, no depth texture.
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

varying vec2 v_xz;

void vertex() {
	v_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv = (v_xz - pack_origin) / m_per_px / pack_px;
	bool inside = all(greaterThanEqual(uv, vec2(0.0))) && all(lessThanEqual(uv, vec2(1.0)));
	float d = inside ? texture(sea_distance, uv).r * 255.0 : 255.0;
	vec3 c = mix(sea_near.rgb, sea_nearer.rgb, smoothstep(band_near - soft, band_near + soft, d));
	c = mix(c, sea_far.rgb, smoothstep(band_nearer - soft, band_nearer + soft, d));
	c = mix(c, sea_deep.rgb, smoothstep(band_far - soft, band_far + soft, d));
	vec2 p = v_xz / ripple_m;
	vec3 n1 = texture(ripples, p + vec2(TIME * drift_m_s / ripple_m, 0.0)).xyz;
	vec3 n2 = texture(ripples, p * 0.61 + vec2(0.0, TIME * drift_m_s * 0.7 / ripple_m)).xyz;
	NORMAL_MAP = normalize(n1 + n2 - 1.0) * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.4;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 5.0);
	ALBEDO = mix(c, sky.rgb, fres * 0.5);
	ROUGHNESS = 0.3;
	SPECULAR = 0.4;
	ALPHA = smoothstep(0.0, shore_fade_px, d);
}
