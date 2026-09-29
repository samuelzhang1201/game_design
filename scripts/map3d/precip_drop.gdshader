// A drop of the falling weather (spec 2026-09-29-weather-visuals): a rain
// streak stood along its fall and turned to face the camera, or a soft snow
// flake facing it — sized in world metres by Map3DLayerPrecip from the
// camera's distance, so it holds its size on screen. Unlit and faint: it
// dresses the weather, it never covers the map (the sun ruling).
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled, skip_vertex_transform;

uniform float kind = 0.0;
uniform vec4 tint : source_color = vec4(0.8, 0.85, 0.9, 1.0);
uniform float opacity = 0.3;
// Unlit colour goes through the AgX tonemap at the map's exposure, which
// greys a plain white below the sunlit snow under it: the gain lifts it back.
uniform float gain = 1.0;
uniform float length_m = 40.0;
uniform float width_m = 4.0;
uniform vec3 fall_dir = vec3(0.0, -1.0, 0.0);

void vertex() {
	vec3 centre = MODEL_MATRIX[3].xyz;
	vec3 to_cam = normalize(CAMERA_POSITION_WORLD - centre);
	vec3 up = normalize(-fall_dir);
	vec3 side = normalize(cross(up, to_cam));
	float h = kind < 0.5 ? length_m : width_m * 1.5;  // a flake a touch streaked by its fall
	vec3 world = centre + side * VERTEX.x * width_m + up * VERTEX.y * h;
	VERTEX = (VIEW_MATRIX * vec4(world, 1.0)).xyz;
}

void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float a = kind < 0.5
		? (1.0 - abs(q.x)) * smoothstep(1.0, 0.2, abs(q.y)) * (0.55 + 0.45 * (1.0 - q.y) * 0.5)
		: pow(max(1.0 - length(q), 0.0), 1.6);
	ALBEDO = tint.rgb * gain;
	ALPHA = a * opacity * COLOR.a;
}
