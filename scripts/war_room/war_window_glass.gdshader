shader_type spatial;
render_mode unshaded, cull_disabled;
// The WAR ROOM's leaded window (spec 2026-10-13-war-room-sunlit-chamber): small
// panes of uneven greenish crown glass in dark lead cames, the bright day
// outside seen blurred through them. Unshaded and brighter than 1 so the glow
// blooms the panes and never the cames. Its look: war_window_glass.tres.

uniform sampler2D lead : filter_linear_mipmap;   // white where glass, dark on the cames
uniform vec3 day : source_color = vec3(1.0, 0.93, 0.8);   // the outside's light
uniform vec3 field : source_color = vec3(0.62, 0.7, 0.5);  // the land low in the panes
uniform float horizon = 0.28;      // UV.y from the bottom where sky meets land
uniform float bright = 4.5;        // panes' brightness, over the glow threshold
uniform vec3 green : source_color = vec3(0.86, 0.94, 0.82);   // crown glass at its thickest
uniform float uneven = 0.35;       // how much the panes vary
uniform float sun_side = 0.4;      // brighter toward the sun's upper corner (+: left)
uniform vec3 came : source_color = vec3(0.025, 0.024, 0.028);

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	float glass = smoothstep(0.35, 0.7, texture(lead, UV).r);
	// uneven glass: a slow swell per pane and a fine ripple
	float w = noise(UV * vec2(8.0, 16.0)) * 0.65 + noise(UV * vec2(29.0, 58.0)) * 0.35;
	vec3 tint = mix(green, vec3(1.0), mix(1.0, w, uneven));
	// the outside, out of focus: day above the horizon, the land below, a soft seam
	float up = 1.0 - UV.y;
	vec3 view = mix(field, day, smoothstep(horizon - 0.08, horizon + 0.08, up + (w - 0.5) * 0.06));
	float toward = clamp(up + (0.5 - UV.x) * sun_side, 0.0, 1.0);
	vec3 pane = view * tint * bright * mix(0.8, 1.15, toward) * (0.85 + 0.3 * w);
	ALBEDO = mix(came, pane, glass);
}
