shader_type spatial;
render_mode cull_disabled;
uniform sampler2D flag_texture : source_color, filter_linear_mipmap_anisotropic;
uniform float wave_amplitude = 0.12;
uniform float sag = 0.14;
uniform float cloth_width = 1.4;
uniform float wave_speed = 1.8;
uniform float wave_frequency = 8.0;
void vertex() {
	float pin = UV.x * UV.x;
	float phase = UV.x * wave_frequency - TIME * wave_speed + VERTEX.y;
	VERTEX.z += sin(phase) * wave_amplitude * pin;
	VERTEX.y -= sag * pin;
	float dx = wave_amplitude * (2.0 * UV.x * sin(phase) + pin * cos(phase) * wave_frequency) / cloth_width;
	float dy = wave_amplitude * pin * cos(phase);
	NORMAL = normalize(vec3(-dx, -dy, 1.0));
}
void fragment() {
	ALBEDO = texture(flag_texture, UV).rgb;
	ROUGHNESS = 0.98;
}

// Thin cloth receives light on both faces, including the leeward face.
void light() {
	float diffuse = 0.25 + 0.75 * abs(dot(NORMAL, LIGHT));
	DIFFUSE_LIGHT += diffuse * ATTENUATION * LIGHT_COLOR / PI;
}
