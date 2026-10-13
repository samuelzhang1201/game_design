shader_type spatial;
render_mode unshaded, cull_disabled;
// The WAR ROOM's lattice shadow (spec 2026-10-13-war-room-sunlit-chamber): a
// SHADOW-ONLY quad over the window's opening, cut by the lead texture, so the
// sun throws the diamond cames across what it reaches while the glass lets the
// light through. Its node casts shadows only; its look: war_window_lattice.tres.

uniform sampler2D lead : filter_linear_mipmap;   // white where glass, dark on the cames
uniform float cut = 0.5;   // the came's width at the shadow: lower is a thinner came

void fragment() {
	ALBEDO = vec3(0.0);
	ALPHA = 1.0 - texture(lead, UV).r;
	ALPHA_SCISSOR_THRESHOLD = cut;
}
