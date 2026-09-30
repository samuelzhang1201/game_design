// scenes/ledger/haze.gdshader
// A cluster's haze (spec 2026-09-30-ledger-galaxy-design §5): a soft round
// glow of its colour behind it, a quad that always faces the camera, added
// to the sky — enough to name the cluster at a glance, never a wash.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 tint : source_color = vec4(0.83, 0.64, 0.3, 1.0);
uniform float strength = 0.075;

void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
}

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float a = exp(-r * r * 3.2) * (1.0 - smoothstep(0.85, 1.0, r));
	ALBEDO = tint.rgb * strength * a;
	ALPHA = 1.0;
}
