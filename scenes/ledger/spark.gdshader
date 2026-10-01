// scenes/ledger/spark.gdshader
// A faint electric CURRENT round each galaxy star (owner 2026-10-01: 周边带有类似
// 细微电流的感觉): one quad per star facing the camera, ADDED to what is behind
// it — a few jagged sparks in a narrow ring just outside the disc, which
// crawl round the edge and flicker, and NOTHING where no spark passes (critic,
// fix round 2: an always-on coloured rim outlined every star; the rim keeps
// the star's own pale bloom, untouched). Each spark is
// LIGHT, not ink (critic, fix round 1: a crisp grey hair read as a pencil
// scribble round a glowing star): a thin bright core inside a soft halo a few
// screen px wide, the halo in the star's own SATURATED hue and only the core
// lifted toward white, tapering out at both ends of its run; its path zigzags
// in straight jags of uneven length (never a right-angled staircase). Each
// quad is a MultiMesh instance laid exactly as its star (scale = the drawn
// radius) and moved by the same wobble (star_motion.gdshaderinc), so the
// current stays on its star. COLOR is the star's sRGB colour (turned linear
// here, Forward+ blends in linear light); INSTANCE_CUSTOM.xy is the star's
// seed, .z its weight (1 a whole star, ledger_spark_selected the selected one,
// ledger_spark_dimmed × its perceived opacity a dimmed one) and .w 1 on the
// selected star, whose current sits just outside its selection ring
// (`ring_out_px`, set by the view) in a band one ring wide (`ring_band_px`).
// Nothing is drawn inside the disc. Real
// TIME: presentation only.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled,
	world_vertex_coords;

#include "res://scenes/ledger/star_motion.gdshaderinc"

uniform float strength = 0.0;
uniform float width = 0.35;        // the sparks' ring, a share of the star's radius
uniform float arcs = 6.0;          // spark runs round the rim
uniform float speed = 0.1;         // how fast they crawl round it (turns a second)
uniform float cover = 0.45;        // the share of the rim they run along
uniform float flicker = 0.6;       // how deep they flicker (0 steady)
uniform float flicker_hz = 6.0;    // how fast
uniform float lift = 0.5;          // a spark's CORE, the star's hue this far toward white
uniform float saturation = 1.6;    // the star's colour pushed this far from grey for the halo
uniform float core_px = 0.6;       // a spark's bright core (screen px, half width)
uniform float glow_px = 2.0;       // its soft halo (screen px, the falloff)
uniform float glow = 0.55;         // the halo's light against the core's 1
uniform float jag = 0.35;          // how uneven its straight jags run (0 even)
uniform float min_px = 6.0;        // a star drawn smaller than this (radius, screen px) wears none
uniform float full_px = 14.0;      // and from this size its whole current
uniform float sel_out = 1.0;       // 1: the selected star's current sits outside its ring
uniform float ring_out_px = 0.0;   // the selection ring's outer edge past the disc (SubViewport px)
uniform float ring_band_px = 0.0;  // the selected star's sparks run within this band past it (SubViewport px)
uniform float px_per_dist = 0.001; // SubViewport px per metre at one metre (perspective)
uniform float ortho_m_per_px = 0.0;

varying vec2 v_p;      // this point in units of the star's radius from its centre
varying vec4 v_seed;
varying vec4 v_col;
varying float v_out;   // how far past the disc the sparks start, in units of the radius
varying float v_reach; // the quad's half size, in units of the radius
varying float v_band;  // the sparks' band, in units of the radius

vec3 to_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

float h1(float n) {
	return fract(sin(n * 127.1 + 311.7) * 43758.5453);
}

// Value noise along x with a period of `p` cells (periodic round the rim),
// eased between its cells: a slow, smooth swell.
float pnoise(float x, float p, float s) {
	float i = floor(x);
	float f = fract(x);
	float a = h1(mod(i, p) + s);
	float b = h1(mod(i + 1.0, p) + s);
	return mix(a, b, f * f * (3.0 - 2.0 * f));
}

void vertex() {
	float r = length(MODEL_MATRIX[0].xyz);
	vec3 centre = MODEL_MATRIX[3].xyz + star_wobble(INSTANCE_CUSTOM, r, INV_VIEW_MATRIX, TIME);
	float m_per_px = ortho_m_per_px > 0.0 ? ortho_m_per_px : length(centre - CAMERA_POSITION_WORLD) * px_per_dist;
	float px_r = m_per_px / max(r, 1e-6);   // one SubViewport px in units of the radius
	float sel = INSTANCE_CUSTOM.a * sel_out;
	v_out = sel * ring_out_px * px_r;
	v_band = mix(width, min(width, ring_band_px * px_r), sel);
	v_reach = 1.0 + v_out + v_band * 1.2 + glow_px * 4.0 * px_r;
	v_p = (UV * 2.0 - 1.0) * v_reach;
	VERTEX = centre + (INV_VIEW_MATRIX[0].xyz * v_p.x + INV_VIEW_MATRIX[1].xyz * v_p.y) * r;
	v_seed = INSTANCE_CUSTOM;
	v_col = COLOR;
}

void fragment() {
	float rr = length(v_p);
	float px = max(fwidth(rr), 1e-4);   // one screen px, in units of the star's radius
	float s = floor(v_seed.x * 97.0) + floor(v_seed.y * 89.0) * 7.0;
	float dir = v_seed.x > 0.5 ? 1.0 : -1.0;
	float t = TIME;
	// where round the rim (0..1), crawling at `speed` turns a second
	float a = fract(atan(v_p.y, v_p.x) / 6.2831853 + 0.5 + dir * speed * t);
	// the runs: where a slow noise round the rim stands high, coming and going
	// as it turns over; `run` falls to 0 at both ends, so a spark tapers out
	float n = mix(pnoise(a * arcs, arcs, s), pnoise(a * arcs, arcs, s + 41.0), 0.5 + 0.5 * sin(t * 0.9 + s));
	float run = smoothstep(1.0 - cover, 1.0 - cover * 0.4, n);
	// its path: straight jags between random heights across the ring, the jags
	// of uneven length (the angle itself warped by a smooth noise)
	float fine = arcs * 5.0;
	float x = a * fine + t * 2.3;
	x += jag * (pnoise(x, fine, s + 7.0) - 0.5) * 1.8;
	float i = floor(x);
	float f = fract(x);
	float h0 = h1(mod(i, fine) + s + 13.0);
	float h_1 = h1(mod(i + 1.0, fine) + s + 13.0);
	float base = 1.0 + v_out;
	float at_r = base + v_band * (0.15 + 0.6 * mix(h0, h_1, f));
	// distance ACROSS the jag, not along the radius, so a steep jag is as
	// thick as a flat one (in screen px)
	float slope = v_band * 0.6 * (h_1 - h0) * fine / (6.2831853 * max(rr, 1e-3));
	float d = abs(rr - at_r) / sqrt(1.0 + slope * slope) / px;
	float thin = mix(0.4, 1.0, run);   // thinner toward its tapered ends
	float core = exp(-pow(d / (core_px * thin), 2.0));
	float soft = exp(-d / (glow_px * thin));
	// and it flickers: a quicker noise sliding along the rim
	float fl = pnoise(a * arcs * 2.0 + t * flicker_hz, arcs * 2.0, s + 29.0);
	float energy = run * (1.0 - flicker * (1.0 - fl * fl));
	// the star's own hue, saturated and at full value, for the halo; the core
	// lifted toward white
	vec3 c = to_linear(v_col.rgb);
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 hue = max(mix(vec3(lum), c, saturation), vec3(0.0));
	hue /= max(max(hue.r, max(hue.g, hue.b)), 1e-4);
	vec3 core_col = mix(hue, vec3(1.0), lift);
	vec3 light = energy * (core_col * core + hue * soft * glow);
	float mask = smoothstep(1.0 - px, 1.0 + px, rr) * (1.0 - smoothstep(v_reach * 0.85, v_reach, rr));
	// a speck of a star carries no current: a hair on a few px reads as a smudge
	mask *= smoothstep(min_px, max(full_px, min_px + 0.01), 1.0 / px);
	ALBEDO = light * strength * v_seed.z * mask;
	ALPHA = 1.0;
}
