// scenes/ledger/spark.gdshader
// A faint electric CURRENT round each galaxy star (owner 2026-10-01: 周边带有类似
// 细微电流的感觉): one quad per star facing the camera, added to what is behind
// it — a soft glow hugging the rim and a few fine filaments in a narrow ring
// just outside the disc, which crawl round the edge and flicker. Each quad is
// a MultiMesh instance laid exactly as its star (scale = the drawn radius) and
// moved by the same wobble (star_motion.gdshaderinc), so the current stays on
// its star. COLOR is the star's sRGB colour (turned linear here, Forward+
// blends in linear light), lifted toward white by `lift`; INSTANCE_CUSTOM.xy
// is the star's seed and .z its weight (1 a whole star, ledger_spark_selected
// the selected one, ledger_spark_dimmed a dimmed one). Nothing is drawn
// inside the disc. Real TIME: presentation only.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled,
	world_vertex_coords;

#include "res://scenes/ledger/star_motion.gdshaderinc"

uniform float strength = 0.0;
uniform float width = 0.35;        // the ring's width, a share of the star's radius
uniform float arcs = 6.0;          // filaments round the rim
uniform float speed = 0.1;         // how fast they crawl round it (turns a second)
uniform float cover = 0.45;        // the share of the rim they run along
uniform float flicker = 0.6;       // how deep they flicker (0 steady)
uniform float flicker_hz = 6.0;    // how fast
uniform float halo = 0.25;         // the soft glow hugging the rim, beside the filaments
uniform float lift = 0.5;          // the star's colour this far toward white
uniform float min_px = 6.0;        // a star drawn smaller than this (radius, screen px) wears none
uniform float full_px = 14.0;      // and from this size its whole current

varying vec2 v_p;      // this point in units of the star's radius from its centre
varying vec4 v_seed;
varying vec4 v_col;

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float h1(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

// Value noise along x with a period of `p` cells: periodic round the rim.
float pnoise(float x, float p, float s) {
	float i = floor(x);
	float f = fract(x);
	float a = h1(mod(i, p) + s);
	float b = h1(mod(i + 1.0, p) + s);
	return mix(a, b, f * f * (3.0 - 2.0 * f));
}

void vertex() {
	float r = length(MODEL_MATRIX[0].xyz);
	float reach = 1.0 + width * 1.8;
	v_p = (UV * 2.0 - 1.0) * reach;
	vec3 centre = MODEL_MATRIX[3].xyz + star_wobble(INSTANCE_CUSTOM, r, INV_VIEW_MATRIX, TIME);
	VERTEX = centre + (INV_VIEW_MATRIX[0].xyz * v_p.x + INV_VIEW_MATRIX[1].xyz * v_p.y) * r;
	v_seed = INSTANCE_CUSTOM;
	v_col = COLOR;
}

void fragment() {
	float rr = length(v_p);
	float reach = 1.0 + width * 1.8;
	float px = max(fwidth(rr), 1e-4);   // one screen px, in units of the star's radius
	float s = floor(v_seed.x * 97.0) + floor(v_seed.y * 89.0) * 7.0;
	float dir = v_seed.x > 0.5 ? 1.0 : -1.0;
	float t = TIME;
	// where round the rim (0..1), crawling at `speed` turns a second
	float a = fract(atan(v_p.y, v_p.x) / 6.2831853 + 0.5 + dir * speed * t);
	// the filaments: short runs where a slow noise round the rim stands high,
	// coming and going as that noise turns over
	float n = mix(pnoise(a * arcs, arcs, s), pnoise(a * arcs, arcs, s + 41.0), 0.5 + 0.5 * sin(t * 0.9 + s));
	float arc = smoothstep(1.0 - cover, 1.0 - cover * 0.4, n);
	// each a jagged hair: it jumps across the ring in short fine steps
	float fine = arcs * 7.0;
	float wig = pnoise(a * fine + t * 2.3, fine, s + 13.0);
	float at_r = 1.0 + width * (0.2 + 0.55 * wig);
	float thin = max(width * 0.1, px * 0.6);   // never thinner than a hair of the screen
	float line = exp(-pow((rr - at_r) / thin, 2.0)) * min(1.0, width * 0.1 / thin + 0.4);
	// and flickers: a quicker noise sliding along the rim
	float fl = pnoise(a * arcs * 2.0 + t * flicker_hz, arcs * 2.0, s + 29.0);
	float spark = line * arc * (1.0 - flicker * (1.0 - fl * fl));
	float glow = halo * exp(-max(rr - 1.0, 0.0) / (width * 0.45));
	float k = (spark + glow) * smoothstep(1.0 - px, 1.0 + px, rr) * (1.0 - smoothstep(reach * 0.85, reach, rr));
	// a speck of a star carries no current: a hair on a few px reads as a smudge
	k *= smoothstep(min_px, max(full_px, min_px + 0.01), 1.0 / px);
	ALBEDO = mix(to_linear(v_col.rgb), vec3(1.0), lift);
	ALPHA = clamp(strength * v_seed.z * k, 0.0, 1.0);
}
