// The apron round a house's foot (owner 2026-10-12: 房屋脚下加上一点点小小的过渡):
// a grid draped on the ground under each house (Map3DHouseApron, merged per
// settlement by Map3DLayerAprons). style 0 mottled packed earth, 1 running-bond
// brick paving; the edge fades into the ground over fade_m metres so the house
// grows out of it. The look (colours, style, sizes, mortar) is the material's,
// authored in scenes/map3d/materials/apron_*.tres; the code sets only lift_px
// (map3d_aprons.csv, scaled to the SubViewport) and px_per_dist (the camera).
// The brick and the mottle are antialiased by fwidth and settle to their mean
// colour once a unit is smaller than a pixel. The weather is the houses' own
// (house_surface.gdshader's weather_* uniforms, set by Map3DLayerWeather on
// every house material): rain darkens it, snow covers it.
shader_type spatial;
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_disabled;

uniform vec4 color_a : source_color = vec4(0.48, 0.39, 0.27, 1.0);
uniform vec4 color_b : source_color = vec4(0.37, 0.30, 0.20, 1.0);
uniform int style = 0;
uniform float fade_m = 1.5;
uniform float unit_m = 1.0;
// the mortar's half width across a brick's length and its height, as a share of each
uniform vec2 mortar = vec2(0.03, 0.05);
uniform float lift_px = 1.5;
uniform float px_per_dist = 0.001;

uniform highp sampler2D weather_now : filter_linear, repeat_disable;
uniform highp sampler2D weather_next : filter_linear, repeat_disable;
uniform float weather_on = 0.0;
uniform float weather_blend = 0.0;
uniform vec2 weather_origin = vec2(0.0);
uniform float weather_m_per_px = 50.0;
uniform float weather_step_px = 8.0;
uniform vec4 weather_snow_color : source_color = vec4(0.91, 0.93, 0.94, 1.0);
uniform float weather_roof_snow = 0.85;
uniform float weather_wet_dark = 0.22;

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += lift_px * length(world_pos - CAMERA_POSITION_WORLD) * px_per_dist;
}

void fragment() {
	vec2 e = min(UV, 1.0 - UV) * UV2;
	ALPHA = smoothstep(0.0, max(fade_m, 0.01), min(e.x, e.y));
	vec2 p = world_pos.xz;
	vec3 c;
	if (style == 1) {
		vec2 q = p / vec2(unit_m, unit_m * 0.5);
		vec2 w = fwidth(q);
		float row = floor(q.y);
		float x = q.x + 0.5 * mod(row, 2.0);
		vec2 f = fract(vec2(x, q.y));
		vec2 d = min(f, 1.0 - f);
		vec2 m = 1.0 - smoothstep(mortar - w, mortar + w, d);
		float shade = hash(vec2(floor(x), row));
		c = mix(color_a.rgb * (0.85 + 0.3 * shade), color_b.rgb, max(m.x, m.y));
		vec3 mean = mix(color_a.rgb, color_b.rgb, 2.0 * (mortar.x + mortar.y));
		c = mix(c, mean, smoothstep(0.25, 0.6, max(w.x, w.y)));
	} else {
		vec2 q = p / unit_m;
		float n = hash(floor(q)) * 0.6 + hash(floor(q / 3.0)) * 0.4;
		c = mix(color_a.rgb, color_b.rgb, n);
		vec2 w = fwidth(q);
		c = mix(c, mix(color_a.rgb, color_b.rgb, 0.5), smoothstep(0.5, 1.2, max(w.x, w.y)));
	}
	if (weather_on > 0.0) {
		vec2 uv = ((p - weather_origin) / weather_m_per_px) / (weather_step_px * vec2(textureSize(weather_now, 0)));
		vec4 wx = mix(texture(weather_now, uv), texture(weather_next, uv), weather_blend);
		c *= 1.0 - wx.r * weather_wet_dark;
		c = mix(c, weather_snow_color.rgb, clamp(wx.b * weather_roof_snow, 0.0, 1.0));
	}
	ALBEDO = c;
	ROUGHNESS = 1.0;
}
