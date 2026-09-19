// A settlement on the 3D map (placeholder, owner 2026-09-18): a hollow ring
// of constant SCREEN size, a billboard facing the camera, drawn without the
// depth test so it reads over a ridge like a pin. A QuadMesh of 1x1 is
// grown in the vertex stage to the ring's size at its distance (the
// px_per_dist sum border_line.gdshader uses); the fragment stage cuts an
// anti-aliased stroke with a dark keyline so a pale ring holds on pale
// ground.
//
// Fix round 1 (owner 2026-09-18): at a near, steep-angle zoom the camera
// still sees to the horizon, so every ring in the frustum was drawing,
// unoccluded (no depth test) — hundreds of far rings, proven by bench (see
// task-3-report.md). Each tier now carries max_view_m (camera-to-settlement
// distance): the ring fades out from fade_start x max_view_m
// (balance.csv map3d_ring_fade_start, which Map3DView.pick_at reads too, so
// a ring that has begun to fade is no longer picked) and the vertex stage
// collapses the quad to zero size at/beyond it, so a culled ring costs no
// fill at all, not just zero alpha.
shader_type spatial;
render_mode unshaded, cull_disabled, blend_mix, depth_draw_never, depth_test_disabled,
	shadows_disabled, fog_disabled;

uniform vec4 colour : source_color = vec4(1.0);
uniform vec4 keyline : source_color = vec4(0.08, 0.08, 0.08, 0.8);
uniform float dot_px = 0.0;    // the solid dot's diameter, window px (owner 2026-09-19)
uniform float ring_px = 14.0;  // outer diameter, window px; 0 = no ring
uniform float line_px = 2.0;   // stroke, window px
uniform float lift_px = 3.0;
uniform float px_per_dist = 0.001;
uniform float max_view_m = 1000000.0;  // beyond this, gone
uniform float fade_start = 0.8;  // share of max_view_m where the fade begins

varying vec2 v_px;    // this fragment's offset from the centre, window px
varying vec4 v_tint;  // the instance's own colour (MANORS: its manor's house), alpha 0 = none
varying float v_fade;  // distance fade, 1 near, 0 at/beyond max_view_m

void vertex() {
	vec3 centre = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	float dist = length(centre - CAMERA_POSITION_WORLD);
	float m_per_px = dist * px_per_dist;
	v_fade = 1.0 - smoothstep(fade_start * max_view_m, max_view_m, dist);
	v_tint = COLOR;
	// Beyond max_view_m the ring is already fully faded: collapse the quad
	// to zero size so it costs no fill, not merely zero alpha.
	float box_px = (dist < max_view_m) ? max(ring_px, dot_px) + 4.0 : 0.0;  // +4 for the keyline/AA edge
	v_px = VERTEX.xy * box_px;
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 world = centre + (right * VERTEX.x + up * VERTEX.y) * box_px * m_per_px;
	world.y += lift_px * m_per_px;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(world, 1.0);
}

void fragment() {
	float r = length(v_px);
	// The solid dot (every settlement since 2026-09-19), anti-aliased.
	float disc = clamp(0.5 * dot_px - r + 0.5, 0.0, 1.0);
	float stroke = 0.0;
	float key = 0.0;
	if (ring_px > 0.0 && line_px > 0.0) {
		float mid = 0.5 * ring_px - 0.5 * line_px;
		float d = abs(r - mid) - 0.5 * line_px;  // px outside the stroke (<0 inside)
		stroke = clamp(0.5 - d, 0.0, 1.0);
		key = clamp(1.5 - d, 0.0, 1.0) * keyline.a;
	}
	// Under MANORS a dot wears its manor's house colour (owner 2026-09-19),
	// ringed in the dark keyline so it holds on ground tinted the same hue.
	bool tinted = v_tint.a > 0.5;
	vec3 fill = tinted ? v_tint.rgb : colour.rgb;
	if (tinted) {
		key = max(key, clamp(1.5 - (r - 0.5 * dot_px), 0.0, 1.0) * keyline.a);
	}
	float ink = max(stroke, disc);
	ALBEDO = mix(keyline.rgb, tinted && disc > stroke ? fill : colour.rgb, ink);
	ALPHA = max(ink * colour.a, key) * v_fade;
}
