// The sea as four flat bands by distance from the shore (owner 2026-09-13,
// after the reference chart): near, nearer, far, deep, each edge a soft fade,
// over a fixed wave grain. TEXTURE is the pack's world_sea_distance.png —
// every pixel its distance to land in native px, 0 on land, capped at 255 —
// so the bands follow the coast at any zoom with nothing drawn per cell.
// SeaLayer sets every uniform from terrain_palette.csv and balance.csv.
shader_type canvas_item;

uniform vec4 sea_near : source_color = vec4(0.77, 0.90, 0.97, 1.0);
uniform vec4 sea_nearer : source_color = vec4(0.64, 0.83, 0.95, 1.0);
uniform vec4 sea_far : source_color = vec4(0.51, 0.74, 0.91, 1.0);
uniform vec4 sea_deep : source_color = vec4(0.39, 0.66, 0.86, 1.0);
// Band edges in native px from the shore, and the half-width of each fade.
uniform float band_near = 10.0;
uniform float band_nearer = 40.0;
uniform float band_far = 150.0;
uniform float soft = 6.0;
// The wave grain: a seamless noise tile, stretched into horizontal streaks.
uniform sampler2D waves : repeat_enable, filter_linear;
uniform float wave_alpha = 0.12;
// Native px covered by one tile of the grain (width, height).
uniform vec2 wave_scale = vec2(576.0, 96.0);
// Native px covered by the whole field, so UV becomes native px.
uniform vec2 field_px = vec2(2560.0, 929.0);

void fragment() {
	float d = texture(TEXTURE, UV).r * 255.0;
	vec3 c = mix(sea_near.rgb, sea_nearer.rgb, smoothstep(band_near - soft, band_near + soft, d));
	c = mix(c, sea_far.rgb, smoothstep(band_nearer - soft, band_nearer + soft, d));
	c = mix(c, sea_deep.rgb, smoothstep(band_far - soft, band_far + soft, d));
	// The grain is centred on 0.5: it darkens the troughs and lightens the
	// crests by wave_alpha at most, and averages out to the band's own tint.
	float w = texture(waves, UV * field_px / wave_scale).r;
	c *= 1.0 + wave_alpha * (w - 0.5) * 2.0;
	COLOR = vec4(c, 1.0);
}
