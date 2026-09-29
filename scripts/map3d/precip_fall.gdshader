// The falling rain and snow (spec 2026-09-29-weather-visuals): world-space
// particles born over a box round the camera's target (Map3DLayerPrecip sizes
// it by the camera's distance, so a drop is the same size on screen at every
// zoom) and kept only where Map3DWeatherField's fall texture says it rains
// (R) or snows (G) — a born drop tests its own spot, so panning never drags
// the weather along. One file for both: `kind` 0 rain, 1 snow.
shader_type particles;

uniform float kind = 0.0;
uniform vec3 box_center = vec3(0.0);
uniform vec2 box_half = vec2(1000.0);
uniform float box_height = 400.0;
uniform float fall_m_s = 400.0;
uniform vec2 wind_m_s = vec2(0.0);
uniform float sway_m_s = 0.0;
uniform float strength = 0.0;
uniform highp sampler2D fall_now : filter_linear, repeat_disable;
uniform highp sampler2D fall_next : filter_linear, repeat_disable;
uniform float blend = 0.0;
uniform vec2 pack_origin = vec2(0.0);
uniform float m_per_px = 50.0;
uniform float step_px = 8.0;

float fall_hash(inout uint s) {
	s = s * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return float((w >> 22u) ^ w) / 4294967295.0;
}

float fall_at(vec2 xz) {
	vec2 uv = ((xz - pack_origin) / m_per_px) / (step_px * vec2(textureSize(fall_now, 0)));
	vec2 f = mix(texture(fall_now, uv).rg, texture(fall_next, uv).rg, blend);
	return kind < 0.5 ? f.r : f.g;
}

void start() {
	uint s = NUMBER * 1973u + RANDOM_SEED * 9277u + 26699u;
	vec2 at = box_center.xz + vec2(fall_hash(s) * 2.0 - 1.0, fall_hash(s) * 2.0 - 1.0) * box_half;
	float y = box_center.y + box_height * (0.9 + 0.2 * fall_hash(s));
	TRANSFORM = mat4(1.0);
	TRANSFORM[3].xyz = vec3(at.x, y, at.y);
	VELOCITY = vec3(wind_m_s.x, -fall_m_s * (0.85 + 0.3 * fall_hash(s)), wind_m_s.y);
	// thinned by the weather under it: a drop where it does not rain is born unseen
	float keep = step(fall_hash(s), fall_at(at) * strength);
	CUSTOM = vec4(fall_hash(s), keep, 0.0, 0.0);
	COLOR = vec4(1.0, 1.0, 1.0, keep);
}

void process() {
	if (kind > 0.5) {
		float ph = CUSTOM.x * 6.2831853;
		VELOCITY.xz = wind_m_s + vec2(sin(TIME * 1.3 + ph), cos(TIME * 0.9 + ph)) * sway_m_s;
	}
	// fade in as it enters the box and out at the ground
	float life = clamp(CUSTOM.z / max(LIFETIME, 0.001), 0.0, 1.0);
	CUSTOM.z += DELTA;
	COLOR.a = CUSTOM.y * smoothstep(0.0, 0.12, life) * (1.0 - smoothstep(0.85, 1.0, life));
}
