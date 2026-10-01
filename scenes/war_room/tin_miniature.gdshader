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
uniform float edge_gain = 6.0;       // how sharply a turn in the normal reads as a raised edge
uniform float rim_power = 3.0;       // the grazing rim's falloff
uniform float rim_weight = 0.6;      // the rim's share of the wear beside the edges
uniform float paint_metallic = 0.05;
uniform float tin_metallic = 0.85;
uniform float paint_roughness = 0.38;   // the varnish
uniform float tin_roughness = 0.28;
uniform float specular = 0.5;

void fragment() {
	vec3 base = albedo_tint.rgb;
	if (has_tex) {
		base *= texture(albedo_tex, UV).rgb;
	}
	vec3 painted = floor(base * levels + 0.5) / levels;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);
	float edge = clamp(length(fwidth(NORMAL)) * edge_gain, 0.0, 1.0);
	float worn = clamp(max(edge, rim * rim_weight) * wear, 0.0, 1.0);
	ALBEDO = mix(painted, tin.rgb, worn);
	METALLIC = mix(paint_metallic, tin_metallic, worn);
	ROUGHNESS = mix(paint_roughness, tin_roughness, worn);
	SPECULAR = specular;
}
