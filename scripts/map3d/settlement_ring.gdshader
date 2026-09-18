// A settlement on the 3D map (placeholder, owner 2026-09-18): a hollow ring
// of constant SCREEN size, a billboard facing the camera, drawn without the
// depth test so it reads over a ridge like a pin. A QuadMesh of 1x1 is
// grown in the vertex stage to the ring's size at its distance (the
// px_per_dist sum border_line.gdshader uses); the fragment stage cuts an
// anti-aliased stroke with a faint dark keyline so a pale ring holds on
// pale ground.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled,
	shadows_disabled, fog_disabled;

uniform vec4 colour : source_color = vec4(1.0);
uniform vec4 keyline : source_color = vec4(0.08, 0.08, 0.08, 0.55);
uniform float ring_px = 14.0;  // outer diameter, window px
uniform float line_px = 2.0;   // stroke, window px
uniform float lift_px = 3.0;
uniform float px_per_dist = 0.001;

varying vec2 v_px;  // this fragment's offset from the centre, window px

void vertex() {
	vec3 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float m_per_px = length(centre - CAMERA_POSITION_WORLD) * px_per_dist;
	float box_px = ring_px + 4.0;  // room for the keyline and the AA edge
	v_px = VERTEX.xy * box_px;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = centre + (right * VERTEX.x + up * VERTEX.y) * box_px * m_per_px;
	world.y += lift_px * m_per_px;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float r = length(v_px);
	float mid = 0.5 * ring_px - 0.5 * line_px;
	float d = abs(r - mid) - 0.5 * line_px;  // px outside the stroke (<0 inside)
	float stroke = clamp(0.5 - d, 0.0, 1.0);
	float key = clamp(1.5 - d, 0.0, 1.0) * keyline.a;
	ALBEDO = mix(keyline.rgb, colour.rgb, stroke);
	ALPHA = max(stroke * colour.a, key);
}
