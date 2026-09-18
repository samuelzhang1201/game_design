// The 3D map's cloud shadows (owner 2026-09-18, Task 9): the shadow-only
// twin of cloud_deck.gdshader's MultiMesh — same shape texture, same
// MODEL_MATRIX per instance, but its OWN shader file. It must stay separate
// from the paint shader: a shader that references ALPHA_SCISSOR_THRESHOLD
// anywhere pushes the WHOLE material into an alpha-scissor pipeline under
// this GL Compatibility build (see cloud_deck.gdshader's note), which
// blanked the paint pass entirely when the two were one file gated by a
// `shadow_pass` uniform. This shader is only ever bound to the twin
// (GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY), so it never
// draws in the colour pass — only into the sun's shadow map.
shader_type spatial;
render_mode depth_draw_opaque, cull_disabled;

uniform sampler2D shape : source_color, filter_linear_mipmap, repeat_disable;
uniform float shadow_cut = 0.35;

void fragment() {
	float a = texture(shape, UV).a * COLOR.a;
	ALBEDO = vec3(0.0);
	ALPHA = a;
	ALPHA_SCISSOR_THRESHOLD = shadow_cut;
}
