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
uniform vec4 neat_uv = vec4(0.0, 0.0, 1.0, 1.0); // the sheet's neat line in the table's UV (v2 B)
uniform float collar_ink = 0.35;   // ink and contours beyond the neat line, as a share
uniform float collar_shade = 0.12; // the collar's paper a touch darker
uniform float neat_px = 1.6;       // the neat line's rule, screen px
uniform float neat_gap_px = 4.0;   // its inner hairline, screen px inside it
// parchment (owner 2026-10-02: 羊皮纸风格): blotches of the aged colour, a
// fine grain, a few foxing spots and a darker, burnt rim — all procedural in
// the sheet's own table metres, so every sheet wears the same skin
uniform float parchment_mottle = 0.45;     // the blotches' pull toward paper_age
uniform float parchment_blotch_m = 0.22;   // a blotch's size, table metres
uniform float parchment_grain = 0.05;      // the fibre grain's strength
uniform float parchment_fox = 0.25;        // the foxing spots' strength
uniform float parchment_rim = 0.35;        // the burnt rim's darkening at the very edge
uniform float sea_wash = 0.12;             // the sea washed this share toward sea_ink
// the graticule (owner 2026-10-02: 战术地图加上经纬度的格子): grid_cells counts
// grid_deg squares; the neat line's band is chequered a degree at a time
uniform float grid_deg = 2.0;
uniform vec4 grid_ink : source_color = vec4(0.608, 0.173, 0.122, 1.0); // faded rubric: apart from the seams' sepia
uniform float neat_band_alpha = 0.85;
// the intelligence layer (v2 B Task 9): premultiplied sRGB bytes, as ink_tex
uniform sampler2D intel_tex : filter_linear_mipmap_anisotropic, hint_default_transparent;
// the fine print (spec 2026-10-07-war-room-scale-hover §3): premultiplied sRGB
// bytes as ink_tex, faded in by the camera's distance (WarNear.fine_alpha)
uniform sampler2D fine_tex : filter_linear_mipmap_anisotropic, hint_default_transparent;
uniform float fine_alpha = 0.0;
uniform float fine_texels_per_px = 1.6;   // fine print fades where a screen px spans more texels than this

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

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float a = 0.5;
	float v = 0.0;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.03 + vec2(17.1, 9.7);
		a *= 0.5;
	}
	return v;
}

vec3 srgb_to_linear(vec3 c) {
	return mix(pow((c + 0.055) * (1.0 / 1.055), vec3(2.4)), c * (1.0 / 12.92), lessThan(c, vec3(0.04045)));
}

void fragment() {
	vec3 col = paper.rgb;
	float edge = max(abs(UV.x - 0.5), abs(UV.y - 0.5)) * 2.0;
	// parchment: the blotches and grain in table metres (a sheet's skin does
	// not stretch with its ratio), the foxing, the rim
	vec2 tm = UV * table_m;
	float blotch = smoothstep(0.35, 0.8, fbm(tm / max(parchment_blotch_m, 1e-3)));
	col = mix(col, paper_age.rgb, blotch * parchment_mottle);
	float grain = vnoise(tm * vec2(900.0, 260.0)) - 0.5;
	col *= 1.0 + grain * parchment_grain;
	float fox = smoothstep(0.82, 0.95, vnoise(tm * 38.0 + 3.1) * vnoise(tm * 11.0 + 7.7) * 1.6);
	col = mix(col, paper_age.rgb * 0.75, fox * parchment_fox * smoothstep(0.35, 0.95, edge));
	col = mix(col, paper_age.rgb, smoothstep(paper_age_from, 1.0, edge) * paper_age_mix);
	float rim = smoothstep(0.93, 1.0, edge + (fbm(tm * 9.0) - 0.5) * 0.05);
	col *= 1.0 - rim * parchment_rim;

	// beyond the neat line: the collar — the neighbouring ground, faint (spec §2.2)
	vec2 inside2 = step(neat_uv.xy, UV) * step(UV, neat_uv.zw);
	float inside = inside2.x * inside2.y;
	float collar = 1.0 - inside;
	float collar_k = mix(1.0, collar_ink, collar);
	col *= 1.0 - collar * collar_shade;

	// land or sea, with a soft shore from the interpolated unclamped metres
	float shore = max(fwidth(raw_metres), 1e-3);
	float land = smoothstep(-shore, shore, raw_metres);
	col = mix(col, sea_ink.rgb, (1.0 - land) * sea_wash);

	float c = line_at(metres / contour_m, contour_px);
	float idx = line_at(metres / (contour_m * index_every), contour_index_px);
	float contour = max(c * contour_alpha, idx * contour_index_alpha) * land * collar_k;
	col = mix(col, ink.rgb, contour);

	// the sea's hatching: diagonal lines in table metres, strongest at the shore
	float hatch = line_at((UV.x * table_m.x + UV.y * table_m.y) * sea_hatch_per_m, sea_hatch_px);
	float shallow = 1.0 - clamp(shore_t, 0.0, 1.0);
	col = mix(col, sea_ink.rgb, hatch * shallow * sea_hatch_alpha * (1.0 - land));

	vec2 g = UV * grid_cells + grid_phase;
	float grid = max(line_at(g.x, grid_px), line_at(g.y, grid_px));
	col = mix(col, grid_ink.rgb, grid * grid_alpha);

	// the sheet's two fold creases, at its vertical and horizontal middle
	float crease = max(line_at(UV.x + 0.5, crease_px), line_at(UV.y + 0.5, crease_px));
	col *= 1.0 - crease * crease_alpha;

	vec4 inked = texture(ink_tex, vec2(UV.x, UV.y * tex_aspect));
	vec3 straight = srgb_to_linear(inked.rgb / max(inked.a, 1e-4));
	float ink_a = inked.a * collar_k;
	col = col * (1.0 - ink_a) + straight * ink_a;
	// a uniform branch: far off the fine print is not sampled at all
	if (fine_alpha > 0.0) {
		vec4 fined = texture(fine_tex, vec2(UV.x, UV.y * tex_aspect));
		vec3 fine_straight = srgb_to_linear(fined.rgb / max(fined.a, 1e-4));
		// legible only where a screen px spans few of its texels: the far, foreshortened
		// part of an oblique view drops it instead of drawing mush
		vec2 fine_texel = vec2(UV.x, UV.y * tex_aspect) * vec2(textureSize(fine_tex, 0));
		float minify = max(length(dFdx(fine_texel)), length(dFdy(fine_texel)));
		float legible = 1.0 - smoothstep(fine_texels_per_px, fine_texels_per_px * 2.0, minify);
		float fine_a = fined.a * collar_k * fine_alpha * legible;
		col = col * (1.0 - fine_a) + fine_straight * fine_a;
	}

	// the neat line: a rule on the cell's edge and a hairline neat_gap_px inside
	// it, in screen px by fwidth (computed outside any branch)
	vec2 nu = (UV - neat_uv.xy) / max(neat_uv.zw - neat_uv.xy, vec2(1e-5));
	vec2 fwn = max(fwidth(nu), vec2(1e-6));
	vec2 d0 = min(abs(nu), abs(nu - 1.0)) / fwn;
	vec2 inb = step(vec2(0.0), nu) * step(nu, vec2(1.0));
	float rule = max((1.0 - clamp(d0.x - neat_px * 0.5, 0.0, 1.0)) * inb.y, (1.0 - clamp(d0.y - neat_px * 0.5, 0.0, 1.0)) * inb.x);
	vec2 d1 = abs(d0 - neat_gap_px);
	float hair = max((1.0 - clamp(d1.x - 0.4, 0.0, 1.0)) * inb.y, (1.0 - clamp(d1.y - 0.4, 0.0, 1.0)) * inb.x) * inside;
	col = mix(col, ink.rgb, max(rule, hair * 0.6));
	// between the rule and the hairline: a band chequered a degree at a time,
	// along the top and bottom by longitude, down the sides by latitude
	vec2 deg = (UV * grid_cells + grid_phase) * grid_deg;
	vec2 par = mod(floor(deg), 2.0);
	vec2 in_band = step(vec2(neat_px * 0.5), d0) * step(d0, vec2(neat_gap_px)) * inb.yx * inside;
	float band = max(in_band.y * par.x, in_band.x * par.y);
	col = mix(col, ink.rgb, band * neat_band_alpha);

	vec4 intel = texture(intel_tex, vec2(UV.x, UV.y * tex_aspect));
	vec3 intel_straight = srgb_to_linear(intel.rgb / max(intel.a, 1e-4));
	col = col * (1.0 - intel.a) + intel_straight * intel.a;
	ALBEDO = col;
	ROUGHNESS = paper_roughness;
}
