// The 3D map's clouds (owner 2026-09-18): flat quads high over the land,
// a soft noise alpha (CloudLayer.cloud_texture, the 2D clouds' own), lit by
// the sun so their undersides read, faded by the field (COLOR.a) and by
// nearness so a camera under the deck is never blinded. The shadow-only
// twin is a SEPARATE shader (cloud_shadow.gdshader, fix below) — never
// merge them back into one file gated by a `shadow_pass` uniform: under
// this GL Compatibility build, a shader that references
// ALPHA_SCISSOR_THRESHOLD anywhere is pushed into an alpha-scissor pipeline
// for the WHOLE material, even in a branch that never runs (`if (shadow_pass)`
// false at runtime) — it is a static, not a dynamic, switch. That silently
// killed this shader's own blended paint pass (proven: identical shader
// minus the shadow branch's ALPHA_SCISSOR_THRESHOLD line rendered fine;
// putting it back, even as plain dead code behind `if (false)`, was enough
// to blank the whole deck at every zoom, fully faded in, no error emitted).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_lambert, specular_disabled;

uniform sampler2D shape : source_color, filter_linear_mipmap, repeat_disable;
uniform float opacity = 0.6;
uniform float near_fade_m = 6000.0;
uniform float near_fade_start_ratio = 0.3;
uniform float emission_share = 0.0;

// VERTEX in fragment() is not a usable view-space position for a MultiMesh
// instance here (fix, owner 2026-09-18, Task 9: it read near zero for every
// cloud, so a first near-fade pass using length(VERTEX) zeroed ALPHA
// everywhere) — MODEL_MATRIX already carries the per-instance transform in
// vertex(), so the world position is found there instead and carried down
// as a varying.
varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float a = texture(shape, UV).a * COLOR.a;
	float dist = length(world_pos - CAMERA_POSITION_WORLD);
	ALBEDO = vec3(0.97);
	EMISSION = ALBEDO * emission_share;
	ALPHA = a * opacity * smoothstep(near_fade_m * near_fade_start_ratio, near_fade_m, dist);
}
