// scenes/ledger/star_motion.gdshaderinc
// A galaxy star's slight WOBBLE (owner 2026-10-01: 轻微小幅度晃动): each star
// drifts in a Lissajous loop round its layout place, in the plane facing the
// camera (so the flat chart's straight-down camera sees it too), its
// amplitude `wobble_share` of its DRAWN radius (the instance's scale; owner
// 2026-10-01, 晃动幅度也可以更大更明显: large enough to read as motion, so
// link.gdshader moves each link's ends by this same formula), the selected
// star's `wobble_selected_share` (seed.w 1: it keeps inside its gold ring),
// its period between `wobble_period_min` and `_max` s and its phases from its
// id's hash (INSTANCE_CUSTOM.xy, LedgerStarMotion.seed_of), so each star
// breathes on its own and the chart never shakes as one. Shared by
// star.gdshader, star_faint.gdshader, spark.gdshader and link.gdshader — one
// formula, so a star's current and its links stay on its star. Real TIME: presentation only (the LEDGER
// holds the game clock while it is open). wobble_share 0 holds every star still.

uniform float wobble_share = 0.0;
uniform float wobble_selected_share = 0.0;
uniform float wobble_period_min = 3.0;
uniform float wobble_period_max = 6.0;
uniform float wobble_ratio = 1.3;

// The wobble's offset in world metres, for a star of drawn radius `r`.
vec3 star_wobble(vec4 seed, float r, mat4 inv_view, float t) {
	float share = mix(wobble_share, wobble_selected_share, clamp(seed.w, 0.0, 1.0));
	if (share <= 0.0) {
		return vec3(0.0);
	}
	float period = mix(wobble_period_min, wobble_period_max, seed.y);
	float w = 6.2831853 / max(period, 0.001);
	float phase_x = 6.2831853 * seed.x;
	float phase_y = 6.2831853 * fract(seed.x * 7.13 + seed.y * 3.71);
	vec2 o = vec2(sin(w * t + phase_x), sin(w * wobble_ratio * t + phase_y));
	return (inv_view[0].xyz * o.x + inv_view[1].xyz * o.y) * share * r;
}
