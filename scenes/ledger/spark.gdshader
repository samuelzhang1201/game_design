// scenes/ledger/spark.gdshader
// A faint electric CURRENT round each galaxy star (owner 2026-10-01: 周边带有类似
// 细微电流的感觉): one quad per star facing the camera, ADDED to what is behind
// it — a few jagged sparks in a narrow ring just outside the disc, which crawl
// round the edge and flicker, and nothing where no spark passes (the rim keeps
// the star's own bloom). A spark is light: a thin bright core lifted toward
// white inside a soft halo a few screen px wide in the star's own saturated
// hue, tapering at both ends of its run, its path straight jags of uneven
// length. Each quad is a MultiMesh instance laid exactly as its star (scale =
// the drawn radius) and moved by the same wobble (star_motion.gdshaderinc), so
// the current stays on its star. COLOR is the star's sRGB colour (turned
// linear here: Forward+ blends in linear light); INSTANCE_CUSTOM.xy is the
// star's seed, .z its weight and .w 1 on the selected star, whose current sits
// just outside its selection ring (`ring_out_px`) within one ring width
// (`ring_band_px`), both set by the view. Real TIME: presentation only.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled,
	world_vertex_coords;

#include "res://scenes/ledger/star_motion.gdshaderinc"

const float BAND_IN = 0.15;        // a spark's lowest point in its band (share of the band)
const float BAND_SPAN = 0.6;       // and how much of the band it ranges over
const float REACH_BAND = 1.2;      // the quad reaches this many bands past the sparks' base
const float REACH_GLOW = 4.0;      // and this many halo falloffs beyond
const float JAGS_PER_RUN = 5.0;    // jags round the rim per spark run
const float JAG_DRIFT = 2.3;       // how fast the jags slide (cells a second)
const float JAG_WARP = 1.8;        // how far `jag` stretches a jag's length
const float GATE_SWAP_HZ = 0.9;    // how fast the runs come and go (radians a second)
const float GATE_SOFT = 0.4;       // a run's ends fade over this share of `cover`
const float FLICKER_CELLS = 2.0;   // flicker cells per spark run
const float TAPER_THIN = 0.4;      // a spark's thickness at its tapered ends
const float EDGE_FADE = 0.85;      // the quad's last share fades out
const float SECTOR_SOFT = 0.08;    // the dark sector's edges fade over this share of the rim
const float SEED_A = 97.0;         // the seed's two hash spreads
const float SEED_B = 89.0;
const float SEED_MIX = 7.0;
const float SALT_RUNS = 41.0;      // offsets keeping each noise its own
const float SALT_WARP = 7.0;
const float SALT_JAGS = 13.0;
const float SALT_FLICKER = 29.0;

uniform float strength = 0.0;
uniform float width = 0.35;        // the sparks' ring, a share of the star's radius
uniform float arcs = 6.0;          // spark runs round the rim
uniform float speed = 0.1;         // how fast they crawl round it (turns a second)
uniform float cover = 0.45;        // the share of the rim they run along
uniform float max_cover = 0.66;    // and never more than this share: a dark sector crawls with them (critic, round 2: on a 10 px star the runs closed into a ring)
uniform float flicker = 0.6;       // how deep they flicker (0 steady)
uniform float flicker_hz = 6.0;    // how fast
uniform float lift = 0.5;          // a spark's CORE, the star's hue this far toward white
uniform float saturation = 1.6;    // the star's colour pushed this far from grey for the halo
uniform float core_px = 0.6;       // a spark's bright core (screen px, half width)
uniform float glow_px = 2.0;       // its soft halo (screen px, the falloff)
uniform float glow_share = 0.25;   // and never more than this share of the star's own radius (on a small star the halo fanned a radius wide)
uniform float glow = 0.55;         // the halo's light against the core's 1
uniform float jag = 0.35;          // how uneven its straight jags run (0 even)
uniform float min_px = 6.0;        // a star drawn smaller than this (radius, screen px) wears none
uniform float full_px = 14.0;      // and from this size its whole current
uniform float sel_out = 1.0;       // 1: the selected star's current sits outside its ring
uniform float ring_out_px = 0.0;   // the selection ring's outer edge past the disc (SubViewport px)
uniform float ring_band_px = 0.0;  // the selected star's sparks run within this band past it (SubViewport px)
uniform float px_per_dist = 0.001; // SubViewport px per metre at one metre

varying vec2 v_p;      // this point in units of the star's radius from its centre
varying vec4 v_seed;
varying vec4 v_col;
varying float v_out;   // how far past the disc the sparks start, in units of the radius
varying float v_reach; // the quad's half size, in units of the radius
varying float v_band;  // the sparks' band, in units of the radius
varying float v_live;  // this quad's light at all (strength × weight; 0 on a speck)

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
	vec3 centre = MODEL_MATRIX[3].xyz + star_wobble(INSTANCE_CUSTOM, length(MODEL_MATRIX[0].xyz), INV_VIEW_MATRIX, TIME);
	float m_per_px = length(centre - CAMERA_POSITION_WORLD) * px_per_dist;
	float px_r = m_per_px / max(r, 1e-6);   // one SubViewport px in units of the radius
	float sel = INSTANCE_CUSTOM.a * sel_out;
	v_out = sel * ring_out_px * px_r;
	v_band = mix(width, min(width, ring_band_px * px_r), sel);
	v_reach = 1.0 + v_out + v_band * REACH_BAND + min(glow_px, glow_share / max(px_r, 1e-6)) * REACH_GLOW * px_r;
	v_p = (UV * 2.0 - 1.0) * v_reach;
	// no light at all (strength 0, a weight of 0, a speck under min_px): the
	// quad collapses to its centre and draws no fragment
	v_live = strength * INSTANCE_CUSTOM.z * step(min_px, 1.0 / max(px_r, 1e-6));
	float size = v_live > 0.0 ? r : 0.0;
	VERTEX = centre + (INV_VIEW_MATRIX[0].xyz * v_p.x + INV_VIEW_MATRIX[1].xyz * v_p.y) * size;
	v_seed = INSTANCE_CUSTOM;
	v_col = COLOR;
}

void fragment() {
	if (v_live <= 0.0) {
		discard;
	}
	float rr = length(v_p);
	float px = max(fwidth(rr), 1e-4);   // one screen px, in units of the star's radius
	float s = floor(v_seed.x * SEED_A) + floor(v_seed.y * SEED_B) * SEED_MIX;
	float dir = v_seed.x > 0.5 ? 1.0 : -1.0;
	float t = TIME;
	// where round the rim (0..1), crawling at `speed` turns a second
	float a = fract(atan(v_p.y, v_p.x) / TAU + 0.5 + dir * speed * t);
	// the runs: where a slow noise round the rim stands high, coming and going
	// as it turns over; `run` falls to 0 at both ends, so a spark tapers out
	float n = mix(pnoise(a * arcs, arcs, s), pnoise(a * arcs, arcs, s + SALT_RUNS), 0.5 + 0.5 * sin(t * GATE_SWAP_HZ + s));
	float run = smoothstep(1.0 - cover, 1.0 - cover * GATE_SOFT, n);
	// a dark sector, (1 - max_cover) of the rim, turning with the filaments
	// from the star's own phase: the current never closes into a ring
	float sector = fract(a + v_seed.y);
	run *= 1.0 - smoothstep(max_cover - SECTOR_SOFT, max_cover, sector);
	// its path: straight jags between random heights across the band, the jags
	// of uneven length (the angle itself warped by a smooth noise)
	float fine = arcs * JAGS_PER_RUN;
	float x = a * fine + t * JAG_DRIFT;
	x += jag * (pnoise(x, fine, s + SALT_WARP) - 0.5) * JAG_WARP;
	float i = floor(x);
	float f = fract(x);
	float h0 = h1(mod(i, fine) + s + SALT_JAGS);
	float h_1 = h1(mod(i + 1.0, fine) + s + SALT_JAGS);
	float at_r = 1.0 + v_out + v_band * (BAND_IN + BAND_SPAN * mix(h0, h_1, f));
	// distance ACROSS the jag, not along the radius, so a steep jag is as
	// thick as a flat one (in screen px)
	float slope = v_band * BAND_SPAN * (h_1 - h0) * fine / (TAU * max(rr, 1e-3));
	float d = abs(rr - at_r) / sqrt(1.0 + slope * slope) / px;
	float thin = mix(TAPER_THIN, 1.0, run);
	float core = exp(-pow(d / (core_px * thin), 2.0));
	float halo = min(glow_px, glow_share / px);   // 1 / px is the radius in screen px
	float soft = exp(-d / (halo * thin));
	// and it flickers: a quicker noise sliding along the rim
	float fl = pnoise(a * arcs * FLICKER_CELLS + t * flicker_hz, arcs * FLICKER_CELLS, s + SALT_FLICKER);
	float energy = run * (1.0 - flicker * (1.0 - fl * fl));
	// the star's own hue, saturated and at full value, for the halo; the core
	// lifted toward white
	vec3 c = to_linear(v_col.rgb);
	float lum = dot(c, vec3(0.2126, 0.7152, 0.0722));
	vec3 hue = max(mix(vec3(lum), c, saturation), vec3(0.0));
	hue /= max(max(hue.r, max(hue.g, hue.b)), 1e-4);
	vec3 light = energy * (mix(hue, vec3(1.0), lift) * core + hue * soft * glow);
	float mask = smoothstep(1.0 - px, 1.0 + px, rr) * (1.0 - smoothstep(v_reach * EDGE_FADE, v_reach, rr));
	// a small star carries a fainter current: a hair on a few px reads as a smudge
	mask *= smoothstep(min_px, max(full_px, min_px + 0.01), 1.0 / px);
	ALBEDO = light * v_live * mask;
	ALPHA = 1.0;
}
