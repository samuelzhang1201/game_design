// The title screen's painted page by candlelight (owner 2026-09-28, second
// critique): the pale, unsaturated PAPER darkens to a warm brown while the
// inked, coloured figures keep most of their value — a flat multiply over the
// whole page read as a muddy veil. Every number is screens/ui/balance.csv ui_menu_*.
shader_type canvas_item;

uniform float paper_dim = 0.4;
uniform float ink_dim = 0.9;
uniform float warm = 0.55;
uniform vec2 paper_lum = vec2(0.70, 0.86);
uniform vec2 paper_sat = vec2(0.10, 0.28);

void fragment() {
	vec4 c = texture(TEXTURE, UV);
	float l = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	float hi = max(c.r, max(c.g, c.b));
	float lo = min(c.r, min(c.g, c.b));
	float sat = hi > 0.0 ? (hi - lo) / hi : 0.0;
	float paper = smoothstep(paper_lum.x, paper_lum.y, l) * (1.0 - smoothstep(paper_sat.x, paper_sat.y, sat));
	vec3 candle = vec3(1.0, (1.0 + warm) * 0.5, warm);
	vec3 k = mix(vec3(ink_dim), paper_dim * candle, paper);
	COLOR = vec4(c.rgb * k, c.a) * COLOR;
}
