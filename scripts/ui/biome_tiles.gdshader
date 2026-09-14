// THE BIOMES LAYER (experiment 2026-09-14): every land pixel is a MIX of the
// biome ground tiles around it, weighted by the pack's baked weight maps
// (world_biome_weights_N.png: biome 4N+1..4N+4 in R,G,B,A, each the share of
// that biome in the land within map_biome_blur_px of the point — so the
// weights already cross-fade one biome into the next over a couple of cells
// and no cell edge survives; owner: the tiles must sink into the map with
// no shape to be seen). `tiles` is a Texture2DArray, layer i = biome i+1,
// sampled in the map's own px so the sheet repeats in native space.
// `biome_index` is the pack's per-pixel biome id (white = water): a pixel
// that is not land draws nothing, so lakes and the shore stay crisp — the
// mesh is the land mesh, so the sea never gets this far anyway.
// BiomeLayer sets every uniform from the repository and balance.csv.
shader_type canvas_item;

uniform sampler2D biome_index : filter_nearest, repeat_disable;
uniform sampler2D weights_0 : filter_linear, repeat_disable;
uniform sampler2D weights_1 : filter_linear, repeat_disable;
uniform sampler2D weights_2 : filter_linear, repeat_disable;
uniform sampler2DArray tiles : filter_linear_mipmap, repeat_enable;
// Native px covered by the whole field, so a native position becomes UV.
uniform vec2 field_px = vec2(2560.0, 929.0);
// Native px one tile spans.
uniform float tile_px = 128.0;
uniform float alpha = 0.45;

varying vec2 native;

void vertex() {
	// The mesh is in native map px and the node is scaled to the view.
	native = VERTEX;
}

void fragment() {
	vec2 f = native / field_px;
	vec4 idx = texture(biome_index, f);
	bool water = idx.r > 0.99 && idx.g > 0.99 && idx.b > 0.99;
	int id = int(idx.r * 255.0 + 0.5);
	if (water || id < 1) {
		COLOR = vec4(0.0);
	} else {
		vec2 uv = native / tile_px;
		vec4 w0 = texture(weights_0, f);
		vec4 w1 = texture(weights_1, f);
		vec4 w2 = texture(weights_2, f);
		vec4 c = vec4(0.0);
		float sum = 0.0;
		c += w0.r * texture(tiles, vec3(uv, 0.0)); sum += w0.r;
		c += w0.g * texture(tiles, vec3(uv, 1.0)); sum += w0.g;
		c += w0.b * texture(tiles, vec3(uv, 2.0)); sum += w0.b;
		c += w0.a * texture(tiles, vec3(uv, 3.0)); sum += w0.a;
		c += w1.r * texture(tiles, vec3(uv, 4.0)); sum += w1.r;
		c += w1.g * texture(tiles, vec3(uv, 5.0)); sum += w1.g;
		c += w1.b * texture(tiles, vec3(uv, 6.0)); sum += w1.b;
		c += w1.a * texture(tiles, vec3(uv, 7.0)); sum += w1.a;
		c += w2.r * texture(tiles, vec3(uv, 8.0)); sum += w2.r;
		c += w2.g * texture(tiles, vec3(uv, 9.0)); sum += w2.g;
		c += w2.b * texture(tiles, vec3(uv, 10.0)); sum += w2.b;
		c += w2.a * texture(tiles, vec3(uv, 11.0)); sum += w2.a;
		if (sum <= 0.001) {
			COLOR = vec4(0.0);
		} else {
			// The bake normalises over land; 8-bit rounding and bilinear
			// sampling drift the sum a little, so it is normalised again.
			c /= sum;
			COLOR = vec4(c.rgb, c.a * alpha);
		}
	}
}
