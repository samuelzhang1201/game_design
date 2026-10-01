// The pen line round the figure: the back faces pushed out along the normal
// (an inverted hull), drawn in ink — the drawing's contour.
shader_type spatial;
render_mode unshaded, cull_front;

uniform vec4 ink : source_color = vec4(0.169, 0.129, 0.094, 1.0);
uniform float width = 0.012;

void vertex() {
	VERTEX += NORMAL * width;
}

void fragment() {
	ALBEDO = ink.rgb;
}
