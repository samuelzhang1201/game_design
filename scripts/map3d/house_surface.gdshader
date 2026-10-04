// One surface of a settlement house (owner 2026-09-25: "房屋墙壁和房顶的颜色
// 可以多样化一点，主色调不变，但可以有不同variant"). Each surface's material is
// set in its house type's scene (scenes/models/buildings/<type>.tscn, edited
// in the editor): its albedo texture, its roughness, the grime baked into its
// vertex colour, its role; double-sided. Map3DLayerHouses draws a copy that
// multiplies a WALL or ROOF surface by one of its tints (edited on the node),
// picked per house (Map3DHouses.variant_of) and handed over as the MultiMesh
// instance's custom data: r the wall variant, g the roof's.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float roughness = 0.9;
uniform bool use_vertex_color = true;
// A surface whose .glb material carries a normal map draws it (the palaces
// since 2026-09-30: Tripo's own normals, owner 宫殿…整体要清晰，有细节); every
// other house has none and draws exactly as before.
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal = false;
uniform float normal_depth = 1.0;
// 0 takes no tint (a recess, timber, slate), 1 a wall's, 2 a roof's
uniform int role = 0;
// linear multipliers, already raised from the table's sRGB hexes; the layer
// sets them on its own copy of each surface's material. A count of 0 (the
// house's own scene, opened in the editor) draws the surface as built.
uniform vec3 wall_tints[8];
uniform vec3 roof_tints[8];
uniform int wall_count = 0;
uniform int roof_count = 0;

varying flat vec3 tint;
// The weather (spec 2026-09-29-weather-visuals, Map3DLayerWeather): the
// field's (wet, mud, snow, overcast) under the house — snow lies on what faces
// up (roofs), rain darkens every surface.
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
varying vec3 w_pos;
varying vec3 w_up;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = vec3(1.0);
	if (role == 1 && wall_count > 0) {
		tint = wall_tints[clamp(int(INSTANCE_CUSTOM.r + 0.5), 0, wall_count - 1)];
	} else if (role == 2 && roof_count > 0) {
		tint = roof_tints[clamp(int(INSTANCE_CUSTOM.g + 0.5), 0, roof_count - 1)];
	}
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * albedo_color.rgb * tint;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	if (weather_on > 0.0) {
		vec2 uv = ((w_pos.xz - weather_origin) / weather_m_per_px) / (weather_step_px * vec2(textureSize(weather_now, 0)));
		vec4 wx = mix(texture(weather_now, uv), texture(weather_next, uv), weather_blend);
		c *= 1.0 - wx.r * weather_wet_dark;
		float up = smoothstep(0.3, 0.6, abs(w_up.y));  // a roof pitch, either face
		c = mix(c, weather_snow_color.rgb, clamp(wx.b * up * weather_roof_snow, 0.0, 1.0));
	}
	ALBEDO = c;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_depth;
	}
	ROUGHNESS = roughness;
	METALLIC = 0.0;
}
