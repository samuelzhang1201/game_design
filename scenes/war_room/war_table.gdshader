// The laid sheet (spec 2026-10-01-war-room-design §2): vellum over the relief,
// contours from the vertex's REAL metres (UV2.x), the sea hatched only in a
// coastal band by its distance off the shore (COLOR.r, built from the grid;
// the relief has no depth below the waterline), the shore itself found from
// UV2.y, the unclamped metres: negative at sea, so it falls between vertices),
// the lettered grid, the paper's age toward the edges, two fold creases, and
// the sheet's ink texture over it all. Sharp at every lean: lines are drawn by fwidth, not sampled, and fade as they
// crowd. Every number is a uniform bound at lay from data/balance.csv war_*;
// every line term is computed OUTSIDE any branch (fwidth in a branch is
// undefined) and selected by weight.
shader_type spatial;
render_mode cull_disabled;

// The ink texture is the painter's SubViewport readback: PREMULTIPLIED, in sRGB
// bytes (measured), so it is read raw (no source_color) and un-premultiplied
// and linearised here.
uniform sampler2D ink_tex : filter_linear_mipmap_anisotropic, hint_default_transparent;
uniform vec4 paper : source_color = vec4(0.914, 0.863, 0.753, 1.0);
uniform vec4 paper_age : source_color = vec4(0.788, 0.698, 0.541, 1.0);
uniform vec4 ink : source_color = vec4(0.169, 0.129, 0.094, 1.0);
uniform vec4 sea_ink : source_color = vec4(0.306, 0.416, 0.471, 1.0);
uniform float contour_m = 200.0;
uniform float index_every = 5.0;
uniform float contour_alpha = 0.45;
uniform float contour_index_alpha = 0.8;
uniform float contour_px = 0.9;
uniform float contour_index_px = 1.8;
uniform float sea_hatch_per_m = 500.0;
uniform float sea_hatch_alpha = 0.35;
uniform float sea_hatch_px = 0.8;
uniform float grid_alpha = 0.25;
uniform float grid_px = 0.7;
uniform float line_crowd_k = 2.0;
uniform float paper_age_from = 0.75;
uniform float paper_age_mix = 0.6;
uniform float paper_roughness = 0.9;
uniform float crease_alpha = 0.12;
uniform float crease_px = 1.5;
uniform vec2 grid_cells = vec2(16.75, 12.125); // sheet size / grid square
uniform vec2 grid_phase = vec2(0.0);           // the grid stays on whole degrees whatever the collar
uniform float tex_aspect = 1.0;                // the share of the ink texture's height the sheet fills
uniform vec2 table_m = vec2(1.4, 1.0);         // the sheet's width and depth in table metres

varying float metres;
varying float raw_metres;
varying float shore_t;

void vertex() {
	metres = UV2.x;
	raw_metres = UV2.y;
	shore_t = COLOR.r;
}

// A line at every integer of v, `width_px` wide, faded as lines crowd.
float line_at(float v, float width_px) {
	float fw = max(fwidth(v), 1e-5);
	float d = abs(fract(v - 0.5) - 0.5) / fw;
	float crowd = clamp(1.0 - fw * line_crowd_k, 0.0, 1.0);
	return (1.0 - clamp(d - width_px * 0.5 + 0.5, 0.0, 1.0)) * crowd;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec3 col = paper.rgb;
	float edge = max(abs(UV.x - 0.5), abs(UV.y - 0.5)) * 2.0;
	col = mix(col, paper_age.rgb, smoothstep(paper_age_from, 1.0, edge) * paper_age_mix);

	// land or sea, with a soft shore from the interpolated unclamped metres
	float shore = max(fwidth(raw_metres), 1e-3);
	float land = smoothstep(-shore, shore, raw_metres);

	float c = line_at(metres / contour_m, contour_px);
	float idx = line_at(metres / (contour_m * index_every), contour_index_px);
	float contour = max(c * contour_alpha, idx * contour_index_alpha) * land;
	col = mix(col, ink.rgb, contour);

	// the sea's hatching: diagonal lines in table metres, strongest at the shore
	float hatch = line_at((UV.x * table_m.x + UV.y * table_m.y) * sea_hatch_per_m, sea_hatch_px);
	float shallow = 1.0 - clamp(shore_t, 0.0, 1.0);
	col = mix(col, sea_ink.rgb, hatch * shallow * sea_hatch_alpha * (1.0 - land));

	vec2 g = UV * grid_cells + grid_phase;
	float grid = max(line_at(g.x, grid_px), line_at(g.y, grid_px));
	col = mix(col, ink.rgb, grid * grid_alpha);

	// the sheet's two fold creases, at its vertical and horizontal middle
	float crease = max(line_at(UV.x + 0.5, crease_px), line_at(UV.y + 0.5, crease_px));
	col *= 1.0 - crease * crease_alpha;

	vec4 inked = texture(ink_tex, vec2(UV.x, UV.y * tex_aspect));
	vec3 straight = srgb_to_linear(inked.rgb / max(inked.a, 1e-4));
	col = col * (1.0 - inked.a) + straight * inked.a;
	ALBEDO = col;
	ROUGHNESS = paper_roughness;
}
