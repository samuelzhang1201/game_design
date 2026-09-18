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
uniform sampler2D weights_3 : filter_linear, repeat_disable;
// The pack's baked height field (MapIndex.bake_relief): an aerial photo
// carries no relief of its own, so the ground is lit by the SLOPE of this
// (owner 2026-09-17, choice B).
uniform sampler2D relief : filter_linear, repeat_disable;
uniform sampler2DArray tiles : filter_linear_mipmap, repeat_enable;
// Native px covered by the whole field, so a native position becomes UV.
uniform vec2 field_px = vec2(2560.0, 929.0);
// Native px one tile spans.
uniform float tile_px = 128.0;
// TILE LOD (owner 2026-09-17). One tile size cannot serve both ends: at the
// closest zoom 128 native px is a 0.92x minification (sharp) but the whole
// world then repeats it 13.6x across the screen and the ground reads as a
// chequerboard; 384 is clean at world zoom (4.5x) but a 2.75x magnification
// up close (soft). So the shader samples the SAME tile at two densities and
// crossfades by the view's zoom: dense when close, coarse when far.
uniform float tile_px_far = 384.0;
uniform float lod_near_zoom = 4.0;   // at/above this zoom: purely `tile_px`
uniform float lod_far_zoom = 1.8;    // at/below this zoom: purely `tile_px_far`
uniform float view_zoom = 1.0;       // screen px per native px, set by BiomeLayer
uniform float alpha = 0.45;
uniform float shade = 0.0;        // 0 = flat ground, 1 = full shading
uniform float shade_px = 40.0;    // native px between the slope samples
uniform float gain = 40.0;        // how steeply a small height difference reads
uniform vec2 light = vec2(-0.7, -0.7);  // toward the light: from the north-west
// SURFACE FOLLOWS THE LAND (owner 2026-09-17). In a real satellite image the
// cover is a RESULT of the topography: bare rock and scree on steep faces,
// snow on the high flats, green in the sheltered low ground. The tiles alone
// are laid by BIOME ID and know nothing of the height field, which is what
// makes the ground read as painted rather than photographed. The high-ground
// bands already follow HEIGHT (MapIndex.raise_high_ground), but nothing has
// ever followed SLOPE, so a steep face at middling altitude still wears
// grassland. Both strengths default to 0: an unset shader is what it was.
uniform float rock_slope_lo = 0.02;
uniform float rock_slope_hi = 0.10;
uniform float rock_strength = 0.0;
uniform float snow_height = 0.80;
uniform float snow_soft = 0.06;
uniform float snow_strength = 0.0;
// A steep face at sea level is a BEACH, not a cliff. Land meets sea across a
// height cliff, so slope alone rimmed every shoreline and lake edge in rock;
// altitude is what separates a coast from a mountain face.
uniform float rock_height_lo = 0.35;
uniform float rock_height_hi = 0.55;
// SETTLEMENT EARTH HALO (owner 2026-09-17). A town does not stand on
// untouched forest: it stands in worked ground — trodden earth, yards, tracks
// — that fades outward into the countryside. Drawing the settlement art
// straight onto green is what made it read as a sticker. `settlement` is the
// baked distance in km to the nearest town's worked ground.
uniform sampler2D settlement : filter_linear, repeat_disable;
uniform float town_fade_px = 0.0;   // km over which the earth fades out; 0 = off
uniform float town_earth_strength = 0.0;
uniform vec3 town_earth = vec3(0.68, 0.60, 0.49);

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
		// LOD: blend the near and far tilings so neither end is compromised.
		float lod = clamp((view_zoom - lod_far_zoom) / max(lod_near_zoom - lod_far_zoom, 0.001), 0.0, 1.0);
		vec2 uv_near = native / tile_px;
		vec2 uv_far = native / tile_px_far;
		vec4 w0 = texture(weights_0, f);
		vec4 w1 = texture(weights_1, f);
		vec4 w2 = texture(weights_2, f);
		vec4 w3 = texture(weights_3, f);
		vec4 c = vec4(0.0);
		float sum = 0.0;
		c += w0.r * mix(texture(tiles, vec3(uv_far, 0.0)), texture(tiles, vec3(uv_near, 0.0)), lod); sum += w0.r;
		c += w0.g * mix(texture(tiles, vec3(uv_far, 1.0)), texture(tiles, vec3(uv_near, 1.0)), lod); sum += w0.g;
		c += w0.b * mix(texture(tiles, vec3(uv_far, 2.0)), texture(tiles, vec3(uv_near, 2.0)), lod); sum += w0.b;
		c += w0.a * mix(texture(tiles, vec3(uv_far, 3.0)), texture(tiles, vec3(uv_near, 3.0)), lod); sum += w0.a;
		c += w1.r * mix(texture(tiles, vec3(uv_far, 4.0)), texture(tiles, vec3(uv_near, 4.0)), lod); sum += w1.r;
		c += w1.g * mix(texture(tiles, vec3(uv_far, 5.0)), texture(tiles, vec3(uv_near, 5.0)), lod); sum += w1.g;
		c += w1.b * mix(texture(tiles, vec3(uv_far, 6.0)), texture(tiles, vec3(uv_near, 6.0)), lod); sum += w1.b;
		c += w1.a * mix(texture(tiles, vec3(uv_far, 7.0)), texture(tiles, vec3(uv_near, 7.0)), lod); sum += w1.a;
		c += w2.r * mix(texture(tiles, vec3(uv_far, 8.0)), texture(tiles, vec3(uv_near, 8.0)), lod); sum += w2.r;
		c += w2.g * mix(texture(tiles, vec3(uv_far, 9.0)), texture(tiles, vec3(uv_near, 9.0)), lod); sum += w2.g;
		c += w2.b * mix(texture(tiles, vec3(uv_far, 10.0)), texture(tiles, vec3(uv_near, 10.0)), lod); sum += w2.b;
		c += w2.a * mix(texture(tiles, vec3(uv_far, 11.0)), texture(tiles, vec3(uv_near, 11.0)), lod); sum += w2.a;
		c += w3.r * mix(texture(tiles, vec3(uv_far, 12.0)), texture(tiles, vec3(uv_near, 12.0)), lod); sum += w3.r;
		c += w3.g * mix(texture(tiles, vec3(uv_far, 13.0)), texture(tiles, vec3(uv_near, 13.0)), lod); sum += w3.g;
		c += w3.b * mix(texture(tiles, vec3(uv_far, 14.0)), texture(tiles, vec3(uv_near, 14.0)), lod); sum += w3.b;
		c += w3.a * mix(texture(tiles, vec3(uv_far, 15.0)), texture(tiles, vec3(uv_near, 15.0)), lod); sum += w3.a;
		if (sum <= 0.001) {
			COLOR = vec4(0.0);
		} else {
			// The bake normalises over land; 8-bit rounding and bilinear
			// sampling drift the sum a little, so it is normalised again.
			c /= sum;
			// The land's own slope and height decide what grows here, BEFORE the
			// light falls on it. Sampled outside the hillshade block because the
			// surface depends on them even when the lighting is turned off.
			if (rock_strength > 0.001 || snow_strength > 0.001) {
				vec2 s_uv = vec2(shade_px) / field_px;
				float sx = texture(relief, f + vec2(s_uv.x, 0.0)).r
					- texture(relief, f - vec2(s_uv.x, 0.0)).r;
				float sy = texture(relief, f + vec2(0.0, s_uv.y)).r
					- texture(relief, f - vec2(0.0, s_uv.y)).r;
				float steep = smoothstep(rock_slope_lo, rock_slope_hi, length(vec2(sx, sy)));
				float hgt = texture(relief, f).r;
				// Rock needs BOTH steepness and height: without the second term every
				// shoreline is a height cliff and wears a rim of gravel.
				float rocky = steep * smoothstep(rock_height_lo, rock_height_hi, hgt);
				// layer i = biome i+1: 13 is mountain rock, 14 is peak snow.
				vec4 rock = mix(texture(tiles, vec3(uv_far, 13.0)), texture(tiles, vec3(uv_near, 13.0)), lod);
				vec4 snow = mix(texture(tiles, vec3(uv_far, 14.0)), texture(tiles, vec3(uv_near, 14.0)), lod);
				c.rgb = mix(c.rgb, rock.rgb, rocky * rock_strength);
				// Snow settles on high ground that is not a cliff face.
				float high = smoothstep(snow_height - snow_soft, snow_height + snow_soft, hgt);
				c.rgb = mix(c.rgb, snow.rgb, high * (1.0 - rocky) * snow_strength);
			}
			// Relief: the height field's slope against the light. A face
			// turned toward the light brightens, one turned away darkens,
			// flat ground is left alone — so the photograph gets landforms
			// without any of the map's own symbols.
			// The worked ground round a town, laid BEFORE the light so the earth is
			// lit with the land instead of sitting on top of it as a flat patch.
			if (town_fade_px > 0.001 && town_earth_strength > 0.001) {
				float town_km = texture(settlement, f).r * 255.0;
				float worked = 1.0 - smoothstep(0.0, town_fade_px, town_km);
				c.rgb = mix(c.rgb, town_earth, worked * town_earth_strength);
			}
			if (shade > 0.001) {
				// Classic hillshade: the height field's own normal against the
				// light, flat ground normalised to 1.0 so `shade` alone says how
				// far the ground may brighten or darken. The first try multiplied
				// the light term by clamp(length(slope) * gain) and fell into a
				// saturation trap — under a gain of ~10 it read as nothing, over
				// it as dirty patches, with no usable range between.
				vec2 step_uv = vec2(shade_px) / field_px;
				float hx = texture(relief, f + vec2(step_uv.x, 0.0)).r
					- texture(relief, f - vec2(step_uv.x, 0.0)).r;
				float hy = texture(relief, f + vec2(0.0, step_uv.y)).r
					- texture(relief, f - vec2(0.0, step_uv.y)).r;
				vec3 n = normalize(vec3(-hx * gain, -hy * gain, 1.0));
				vec3 l = normalize(vec3(light.x, light.y, 0.6));
				float flat_lit = normalize(vec3(0.0, 0.0, 1.0)).z * l.z;
				float lit = dot(n, l) / max(flat_lit, 0.001);
				c.rgb *= clamp((1.0 - shade) + shade * lit, 0.0, 2.0);
			}
			COLOR = vec4(c.rgb, c.a * alpha);
		}
	}
}
