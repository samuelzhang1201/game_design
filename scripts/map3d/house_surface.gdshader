// One surface of a settlement house (owner 2026-09-25: "房屋墙壁和房顶的颜色
// 可以多样化一点，主色调不变，但可以有不同variant"). Each surface's material is
// set in its house type's scene (scenes/models/buildings/<type>.tscn, a
// ship's scenes/models/ships/<type>.tscn, edited in the editor): its albedo
// texture, its roughness, the grime baked into its
// vertex colour, its role; double-sided. Map3DLayerHouses draws a copy that
// multiplies a WALL or ROOF surface by one of its tints (edited on the node),
// picked per house (Map3DHouses.variant_of) and handed over as the MultiMesh
// instance's custom data: r the wall variant, g the roof's, b the trim's.
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
uniform vec3 wall_tints[24];
uniform vec3 roof_tints[24];
uniform vec3 trim_tints[8];
uniform int wall_count = 0;
uniform int roof_count = 0;
// the TRIM (timber, slate, every role 0 surface) takes one of these, hashed
// per house into instance custom b; a count of 0 leaves it as built
uniform int trim_count = 0;

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
// A MOORED SHIP rides the swell (owner 2026-10-04: 要有在海上停泊时随海浪飘荡的感觉).
// A ship's scene sets bob_on; every vertex is then turned about the origin —
// the waterline, which the layer floats on the sea — by a slow roll about the
// hull's long axis (X) and a smaller pitch about its beam (Z), and lifted by a
// heave, each wave's phase hashed from the instance's own place so no two ships
// in a harbour rock together. Every other surface keeps bob_on 0 and is untouched.
uniform float bob_on = 0.0;
uniform float bob_roll_deg = 2.5;
uniform float bob_pitch_deg = 1.0;
uniform float bob_heave_m = 0.3;
uniform float bob_period_s = 7.0;

// A fortification's weathering, per pixel (owner 2026-10-14: 墙面污迹 — the
// grime baked into the vertex colour is off on the walls, and a few vertices
// a 24 m module could not carry it): a damp stain rising from the ground to
// about stain_foot_m of the model's own height, its top edge ragged, and rain
// streaks running down stain_streak_len_m from stain_streak_top_m. Its noise
// runs on the world position, so identical modules do not repeat it. 0: off.
uniform float stain_foot = 0.0;
uniform float stain_foot_m = 5.0;
uniform vec4 stain_foot_color : source_color = vec4(0.55, 0.52, 0.40, 1.0);
uniform float stain_streak = 0.0;
uniform float stain_streak_m = 1.4;
uniform float stain_streak_top_m = 12.0;
uniform float stain_streak_len_m = 7.0;
varying float l_up;   // the vertex's own height over the model's ground (z = 0 in the bake)

float stain_hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float stain_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(stain_hash(i), stain_hash(i + vec2(1.0, 0.0)), u.x),
		mix(stain_hash(i + vec2(0.0, 1.0)), stain_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	if (bob_on > 0.0) {
		vec2 at = MODEL_MATRIX[3].xz;
		float t = TIME * 6.2831853 / bob_period_s + fract(sin(dot(at, vec2(12.9898, 78.233))) * 43758.5453) * 6.2831853;
		float roll = radians(bob_roll_deg) * sin(t) * bob_on;
		float pitch = radians(bob_pitch_deg) * sin(t * 0.71 + 1.7) * bob_on;
		mat3 rx = mat3(vec3(1.0, 0.0, 0.0), vec3(0.0, cos(roll), sin(roll)), vec3(0.0, -sin(roll), cos(roll)));
		mat3 rz = mat3(vec3(cos(pitch), sin(pitch), 0.0), vec3(-sin(pitch), cos(pitch), 0.0), vec3(0.0, 0.0, 1.0));
		VERTEX = rx * rz * VERTEX + vec3(0.0, bob_heave_m * bob_on * sin(t * 1.23 + 0.4), 0.0);
		NORMAL = rx * rz * NORMAL;
	}
	l_up = VERTEX.y;
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_up = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	tint = vec3(1.0);
	if (role == 1 && wall_count > 0) {
		tint = wall_tints[clamp(int(INSTANCE_CUSTOM.r + 0.5), 0, wall_count - 1)];
	} else if (role == 2 && roof_count > 0) {
		tint = roof_tints[clamp(int(INSTANCE_CUSTOM.g + 0.5), 0, roof_count - 1)];
	} else if (role == 0 && trim_count > 0) {
		tint = trim_tints[clamp(int(INSTANCE_CUSTOM.b + 0.5), 0, trim_count - 1)];
	}
}

void fragment() {
	vec3 c = texture(albedo_tex, UV).rgb * albedo_color.rgb * tint;
	if (use_vertex_color) {
		c *= COLOR.rgb;
	}
	if (stain_foot > 0.0 || stain_streak > 0.0) {
		// one horizontal coordinate that runs along any face: the world's x + z
		float along = w_pos.x * 0.7071 + w_pos.z * 0.7071;
		// the footing below the ground line (bared on a downhill side) is its
		// lowest course stretched 8 m: the texture's blurred mean there, not its
		// stretched stripes (critic 2026-10-14: a near-black barcode skirt)
		// mottled like rubble and earth banked against it, darker as it goes down
		float rubble = 0.62 + 0.45 * stain_noise(vec2(along / 1.1, l_up / 0.8))
			+ 0.25 * (stain_noise(vec2(along / 0.35, l_up / 0.3)) - 0.5);
		vec3 bank = textureLod(albedo_tex, UV, 7.0).rgb * albedo_color.rgb * tint * rubble
			* mix(0.55, 0.8, smoothstep(-6.0, 0.0, l_up));
		c = mix(c, bank, smoothstep(0.5, -1.0, l_up) * step(0.0, stain_foot - 0.001));
		float edge = stain_foot_m * (0.45 + 1.1 * stain_noise(vec2(along / 6.0, 3.1))
			+ 0.3 * (stain_noise(vec2(along / 1.8, 7.7)) - 0.5));
		// the damp climbs unevenly: its top edge broken in height as well
		float rise = l_up + (stain_noise(vec2(along / 1.3, l_up / 0.9)) - 0.5) * 1.6;
		float foot = 1.0 - smoothstep(edge * 0.2, edge, rise);
		c = mix(c, c * stain_foot_color.rgb, clamp(foot * stain_foot, 0.0, 1.0));
		float col = stain_noise(vec2(along / stain_streak_m, 11.3)) * stain_noise(vec2(along / (stain_streak_m * 3.7), 5.9));
		float down = clamp((l_up - (stain_streak_top_m - stain_streak_len_m * (0.5 + col))) / stain_streak_len_m, 0.0, 1.0);
		c *= 1.0 - stain_streak * smoothstep(0.18, 0.45, col) * down * step(l_up, stain_streak_top_m + 0.5);
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
