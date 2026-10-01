// The laid sheet (spec 2026-10-01-war-room-design §2): vellum over the relief,
// contours from the vertex's REAL metres (UV2.x), the lettered grid, the paper's
// age toward the edges, and the sheet's ink texture over it all. Sharp at
// every lean: lines are drawn by fwidth, not sampled.
shader_type spatial;
render_mode cull_disabled;

uniform sampler2D ink_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 paper : source_color = vec4(0.914, 0.863, 0.753, 1.0);
uniform vec4 paper_age : source_color = vec4(0.788, 0.698, 0.541, 1.0);
uniform vec4 ink : source_color = vec4(0.169, 0.129, 0.094, 1.0);
uniform vec4 sea_ink : source_color = vec4(0.306, 0.416, 0.471, 1.0);
uniform float contour_m = 200.0;
uniform float index_every = 5.0;
uniform vec2 grid_cells = vec2(16.75, 12.125); // sheet size / grid square
uniform float tex_aspect = 0.724;              // sheet h / w: the ink texture's used height

varying float metres;

void vertex() {
	metres = UV2.x;
}

float line_at(float v, float width_px) {
	float d = abs(fract(v - 0.5) - 0.5) / max(fwidth(v), 1e-5);
	return 1.0 - clamp(d - width_px * 0.5 + 0.5, 0.0, 1.0);
}

void fragment() {
	vec3 col = paper.rgb;
	float edge = max(abs(UV.x - 0.5), abs(UV.y - 0.5)) * 2.0;
	col = mix(col, paper_age.rgb, smoothstep(0.75, 1.0, edge) * 0.6);
	if (metres <= 0.0) {
		// the sea: fine coastal hatching, fading off the shore by height-less ground
		float hatch = line_at(UV.y * 900.0, 0.8);
		col = mix(col, sea_ink.rgb, hatch * 0.35);
	} else {
		float c = line_at(metres / contour_m, 0.9);
		float idx = line_at(metres / (contour_m * index_every), 1.8);
		col = mix(col, ink.rgb, max(c * 0.45, idx * 0.8));
	}
	vec2 g = UV * grid_cells;
	float grid = max(line_at(g.x, 0.7), line_at(g.y, 0.7));
	col = mix(col, ink.rgb, grid * 0.25);
	vec4 inked = texture(ink_tex, vec2(UV.x, UV.y * tex_aspect));
	col = mix(col, inked.rgb, inked.a);
	ALBEDO = col;
	ROUGHNESS = 0.9;
}
