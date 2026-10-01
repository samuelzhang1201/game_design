// A painted tin miniature (owner 2026-10-01, spec 2026-10-01-war-room-design
// §3): the model's own albedo posterised into a few flat paint colours, its
// raised edges worn through to grey tin, under a thin varnish. The levels,
// the wear and the tin colour are bound from balance.csv / war_palette.csv
// by WarPieces; the defaults here only keep an unbound material sane.
shader_type spatial;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform bool has_tex = true;
uniform float levels = 5.0;
uniform vec4 tin : source_color = vec4(0.62, 0.62, 0.60, 1.0);
uniform float wear = 0.55;

void fragment() {
	vec3 base = albedo_tint.rgb;
	if (has_tex) {
		base *= texture(albedo_tex, UV).rgb;
	}
	vec3 painted = floor(base * levels + 0.5) / levels;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	float edge = clamp(length(fwidth(NORMAL)) * 6.0, 0.0, 1.0);
	float worn = clamp(max(edge, rim * 0.6) * wear, 0.0, 1.0);
	ALBEDO = mix(painted, tin.rgb, worn);
	METALLIC = mix(0.05, 0.85, worn);
	ROUGHNESS = mix(0.38, 0.28, worn);   // the varnish
	SPECULAR = 0.5;
}
