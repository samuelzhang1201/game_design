class_name Map3DGroundTint
extends RefCounted
## The ground's own look and its themes, spliced into the shader Terrain3D
## generates (specs 2026-09-19-map3d-manor-themes-design, -heights): patch()
## rewrites its one ALBEDO line — fields, woods, wind, relief, weather, then
## the MANORS tint (cell id from world_cell_index.png, colour from a LUT) or
## the HEIGHTS ramp — so the relief, sun and cloud shadows still light it.
## An addon update that changes the line makes patch() return "" (tested).

const ALBEDO_LINE := "ALBEDO = mat.albedo_height.rgb * color_map.rgb * macrov;"
const LUT_WIDTH := 128  ## the LUT's width in texels: cell id → (id % 128, id / 128)

const UNIFORMS := """
// Map3DGroundTint: the MANORS manor colours (Map3DView sets these).
uniform highp sampler2D cell_index : filter_nearest, repeat_disable;
uniform highp sampler2D cell_lut : filter_nearest, repeat_disable;
uniform float tint_mix = 0.0;
uniform vec2 pack_origin = vec2(0.0);
uniform float m_per_px = 50.0;
uniform ivec2 lut_size = ivec2(128, 1);
// The bake's field map (owner 2026-09-19): RGB each field's own colour
// multiplier, A its strip direction; furrows up close, eased back far out.
uniform highp sampler2D field_map : filter_linear, repeat_disable;
uniform float field_m_per_texel = 40.0;
uniform float furrow_m = 9.0;
uniform float furrow_depth = 0.0;
// The open fields' STRIPS (owner 2026-10-01), each its own shade; strip_far_* far out.
uniform float furrow_sharp = 1.0;
uniform float strip_m = 22.0;
uniform float strip_shade = 0.0;
uniform float strip_far_m = 80.0;
uniform float strip_far_shade = 0.0;
uniform float field_fade = 0.0;
uniform float field_far_value = 1.0;
uniform float field_fade_near_m = 15000.0;
uniform float field_fade_far_m = 60000.0;
// The HEIGHTS heat (owner 2026-09-19): the ground's world height ramped
// through the ground look's heat_ramp (sRGB, turned linear below).
uniform float heat_mix = 0.0;
uniform float heat_sea_y = 0.0;
uniform float heat_top_m = 2400.0;
uniform vec4 heat_c0 = vec4(1.0);
uniform vec4 heat_c1 = vec4(1.0);
uniform vec4 heat_c2 = vec4(1.0);
uniform vec4 heat_c3 = vec4(1.0);
uniform vec4 heat_c4 = vec4(1.0);
uniform vec4 heat_c5 = vec4(1.0);
// The WOODS (look route 2026-09-30): tools/map3d/bake_trees.py's woods.png,
// R the canopy's share of a 40 m texel, G its conifer share. Under the drawn
// clumps the floor darkens toward the canopy (wood_floor); far out, where no
// clump is drawn, the canopy itself carries the wood (wood_far), mottled.
uniform highp sampler2D wood_map : filter_linear, repeat_disable;
uniform float wood_on = 0.0;
uniform float wood_m_per_texel = 40.0;
uniform float wood_floor = 0.5;
uniform float wood_far = 0.9;
uniform float wood_far_near_m = 3000.0;
uniform float wood_far_far_m = 12000.0;
uniform float wood_mottle_m = 180.0;
uniform float wood_mottle = 0.5;
uniform vec4 wood_broadleaf = vec4(0.18, 0.26, 0.12, 1.0);
uniform vec4 wood_conifer = vec4(0.12, 0.2, 0.13, 1.0);
// The weather (spec 2026-09-29-weather-visuals): Map3DWeatherField's
// (wet, mud, snow, overcast) for this spell and the next, blended by
// weather_blend; texel = weather_step_px pack px; colours raw sRGB.
uniform highp sampler2D weather_now : filter_linear, repeat_disable;
uniform highp sampler2D weather_next : filter_linear, repeat_disable;
uniform float weather_on = 0.0;
uniform float weather_blend = 0.0;
uniform float weather_step_px = 8.0;
uniform float weather_warp_m = 600.0;
uniform float weather_warp_scale_m = 3000.0;
uniform float weather_dim = 0.2;
uniform float weather_flat = 0.25;
uniform float weather_wet_dark = 0.22;
uniform float weather_wet_rough = 0.35;
uniform float weather_mud_mix = 0.35;
uniform vec4 weather_mud_color = vec4(0.43, 0.33, 0.21, 1.0);
uniform vec4 weather_snow_color = vec4(0.91, 0.93, 0.94, 1.0);
uniform float weather_snow_slope = 0.8;
uniform float weather_snow_patch_m = 420.0;
uniform float weather_snow_rough = 0.7;
uniform float weather_snow_detail = 0.35;
uniform float weather_snow_steep = 0.4;
uniform float weather_snow_soft = 0.35;
uniform float weather_snow_wood = 1.0;
uniform float weather_mud_dark = 0.18;
uniform float weather_wet_cool = 0.15;
uniform vec4 weather_wet_color = vec4(0.45, 0.5, 0.55, 1.0);
uniform float weather_haze = 0.35;
uniform vec4 weather_haze_color = vec4(0.72, 0.75, 0.77, 1.0);

float wx_hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

// Value noise in 0..1, smooth between whole-number lattice points.
float wx_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(wx_hash(i), wx_hash(i + vec2(1.0, 0.0)), u.x),
		mix(wx_hash(i + vec2(0.0, 1.0)), wx_hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

vec3 wx_linear(vec3 c) {
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}
"""

const TINTED_ALBEDO := """vec3 base_albedo = mat.albedo_height.rgb * color_map.rgb * macrov;
	if (furrow_depth > 0.0 || field_fade > 0.0) {
		vec2 fuv = (v_vertex.xz - pack_origin) / field_m_per_texel / vec2(textureSize(field_map, 0));
		vec4 fm = texture(field_map, fuv);
		vec3 ftint = max(fm.rgb, vec3(0.2));
		// far out the fields' colour gives way, the straw eased: a tone, not a speckle
		float far_k = smoothstep(field_fade_near_m, field_fade_far_m,
			length(v_vertex - _camera_pos)) * field_fade;
		base_albedo /= mix(vec3(1.0), ftint, far_k);
		base_albedo *= mix(1.0, field_far_value, far_k * clamp((1.0 - min(min(ftint.r, ftint.g), ftint.b)) / 0.25, 0.0, 1.0));
		// up close, furrows on sown ground, gone before they shrink to a pixel
		float sown = clamp((1.0 - min(min(ftint.r, ftint.g), ftint.b)) / 0.25, 0.0, 1.0);
		float ang = fm.a * 3.14159265;
		float ph = dot(v_vertex.xz, vec2(-sin(ang), cos(ang))) / furrow_m;
		float aa = 1.0 - smoothstep(0.3, 0.6, fwidth(ph));
		float stripe = pow(0.5 + 0.5 * sin(ph * 6.2831853), furrow_sharp);
		base_albedo *= 1.0 - furrow_depth * sown * aa * stripe;
		if (strip_shade > 0.0) {
			float sp = dot(v_vertex.xz, vec2(-sin(ang), cos(ang))) / strip_m;
			float sa = dot(v_vertex.xz, vec2(cos(ang), sin(ang))) / (strip_m * 9.0);
			float sh = wx_hash(vec2(floor(sp), floor(sa + wx_hash(vec2(floor(sp), 3.7)))));
			float saa = 1.0 - smoothstep(0.15, 0.4, fwidth(sp));
			base_albedo *= 1.0 + strip_shade * sown * saa * (sh - 0.5) * 2.0;
			// farther out, broader bands of its strips carry the furlong's grain
			float sp2 = sp * strip_m / strip_far_m;
			float sh2 = wx_hash(vec2(floor(sp2), floor(sa * strip_m / strip_far_m + 7.3)));
			base_albedo *= 1.0 + strip_far_shade * sown * (1.0 - smoothstep(0.2, 0.5, fwidth(sp2)))
				* (1.0 - saa) * (sh2 - 0.5) * 2.0;
		}
	}
	float canopy_k = 0.0;  // the wood's share here, for the snow below
	if (wood_on > 0.0) {
		vec2 wuv0 = (v_vertex.xz - pack_origin) / wood_m_per_texel / vec2(textureSize(wood_map, 0));
		vec4 wd = texture(wood_map, wuv0);
		float w_far = smoothstep(wood_far_near_m, wood_far_far_m, length(v_vertex - _camera_pos));
		float w_mott = wx_noise(v_vertex.xz / wood_mottle_m) * 0.6
			+ wx_noise(v_vertex.xz / (wood_mottle_m * 0.37) + vec2(7.1, 2.9)) * 0.4;
		vec3 canopy = mix(wx_linear(wood_broadleaf.rgb), wx_linear(wood_conifer.rgb), wd.g)
			* (1.0 + wood_mottle * (w_mott - 0.5) * 2.0);
		float w_k = clamp(wd.r * mix(wood_floor, wood_far, w_far), 0.0, 1.0);
		base_albedo = mix(base_albedo, canopy, w_k);
		canopy_k = clamp(wd.r, 0.0, 1.0);
	}
	// @WIND (Map3DGroundWind.STAGE, then Map3DGroundRelief.STAGE)
	// The weather under the themes: the ground's own look, which a theme's
	// tint then mixes over, like the relief and the sun.
	if (weather_on > 0.0) {
		vec2 wq = v_vertex.xz / weather_warp_scale_m;
		vec2 warp = vec2(wx_noise(wq), wx_noise(wq + vec2(17.3, 5.1))) * 2.0 - 1.0;
		vec2 wpx = (v_vertex.xz + warp * weather_warp_m - pack_origin) / m_per_px;
		vec2 wuv = wpx / (weather_step_px * vec2(textureSize(weather_now, 0)));
		vec4 wx = mix(texture(weather_now, wuv), texture(weather_next, wuv), weather_blend) * weather_on;
		float lum = dot(base_albedo, vec3(0.2126, 0.7152, 0.0722));
		// mud: a dark umber at the ground's own value, a little darker again
		vec3 mud = wx_linear(weather_mud_color.rgb);
		mud *= lum / max(dot(mud, vec3(0.2126, 0.7152, 0.0722)), 0.001);
		base_albedo = mix(base_albedo, mud, clamp(wx.g * weather_mud_mix, 0.0, 1.0));
		base_albedo *= 1.0 - wx.g * weather_mud_dark;
		// rain: darker, cooler (toward a wet blue-grey at the ground's value), a sheen
		vec3 cool = wx_linear(weather_wet_color.rgb);
		cool *= lum / max(dot(cool, vec3(0.2126, 0.7152, 0.0722)), 0.001);
		base_albedo = mix(base_albedo, cool, wx.r * weather_wet_cool);
		base_albedo *= 1.0 - wx.r * weather_wet_dark;
		roughness = mix(roughness, weather_wet_rough, wx.r);
		// snow: the flat first, steep ground only lightly; light snow lies in
		// patches, and the texture's high points (stones, tussocks) show
		// through until it is deep; its edge is a soft ramp, not a line
		float flat_k = mix(weather_snow_steep, 1.0,
			smoothstep(weather_snow_slope - 0.2, weather_snow_slope + 0.1, w_normal.y));
		float patchy = wx_noise(v_vertex.xz / weather_snow_patch_m);
		float edge = patchy * 0.6 + mat.albedo_height.a * 0.4;
		float snow = smoothstep(edge - weather_snow_soft, edge + weather_snow_soft, wx.b * flat_k * 1.3)
			* mix(1.0, weather_snow_wood, canopy_k);  // seen from above, a wood stays dark
		// the ground's own light and dark show through the snow a little —
		// fields, woods and tracks under it — so a snowbound land keeps its map
		float under = clamp(lum / 0.12, 0.55, 1.25);
		vec3 snow_col = wx_linear(weather_snow_color.rgb) * mix(1.0, under, weather_snow_detail)
			* (0.95 + 0.05 * patchy);
		base_albedo = mix(base_albedo, snow_col, snow);
		roughness = mix(roughness, weather_snow_rough, snow);
		// the overcast last, over the snow too: a flat, dimmer light (a
		// snowfall under a grey sky is darker than snow in the sun) ...
		float lum2 = dot(base_albedo, vec3(0.2126, 0.7152, 0.0722));
		base_albedo = mix(base_albedo, vec3(lum2), wx.a * weather_flat);
		base_albedo *= 1.0 - wx.a * weather_dim;
		// ... and a blizzard veils it in grey: told from a snowfall by its
		// overcast against its snow (1 to 0.6), a ratio that holds out to the
		// cell's rim, where the overcast alone fades and left dark blotches
		float storm = smoothstep(0.75, 0.95, wx.a / max(wx.b, 0.01)) * clamp(wx.b * 1.5, 0.0, 1.0);
		float haze = storm * weather_haze;
		base_albedo = mix(base_albedo, wx_linear(weather_haze_color.rgb), haze);
	}
	vec4 tint = vec4(0.0);
	if (tint_mix > 0.0) {
		// The manor under the point, its edge SMOOTH (owner 2026-10-04: 拉近尽头
		// manor交界处会有很明显的锯齿形): the four index texels round the point,
		// each id's bilinear weight summed, the heaviest id's colour against the
		// next one's, the line where their weights meet anti-aliased over one
		// screen px — the index's 50 m staircase becomes the curve it stands for.
		vec2 mt_p = (v_vertex.xz - pack_origin) / m_per_px - 0.5;
		ivec2 mt_b = ivec2(floor(mt_p));
		vec2 mt_f = fract(mt_p);
		ivec2 index_size = textureSize(cell_index, 0);
		if (mt_b.x >= -1 && mt_b.y >= -1 && mt_b.x < index_size.x && mt_b.y < index_size.y) {
			int mt_id[4];
			float mt_w[4];
			for (int i = 0; i < 4; i++) {
				ivec2 o = ivec2(i & 1, i >> 1);
				ivec2 q = clamp(mt_b + o, ivec2(0), index_size - ivec2(1));
				vec3 c = texelFetch(cell_index, q, 0).rgb;
				mt_id[i] = int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256;
				mt_w[i] = (o.x == 1 ? mt_f.x : 1.0 - mt_f.x) * (o.y == 1 ? mt_f.y : 1.0 - mt_f.y);
			}
			float best = -1.0, second = -1.0;
			int best_id = -1, second_id = -1;
			for (int i = 0; i < 4; i++) {
				if (mt_id[i] == best_id || mt_id[i] == second_id) { continue; }
				float w = 0.0;
				for (int j = 0; j < 4; j++) { w += mt_id[j] == mt_id[i] ? mt_w[j] : 0.0; }
				if (w > best) { second = best; second_id = best_id; best = w; best_id = mt_id[i]; }
				else if (w > second) { second = w; second_id = mt_id[i]; }
			}
			int lut_n = lut_size.x * lut_size.y;
			vec4 t_best = best_id < lut_n ? texelFetch(cell_lut, ivec2(best_id % lut_size.x, best_id / lut_size.x), 0) : vec4(0.0);
			vec4 t_second = second_id < 0 ? t_best : (second_id < lut_n
				? texelFetch(cell_lut, ivec2(second_id % lut_size.x, second_id / lut_size.x), 0) : vec4(0.0));
			float d = best - max(second, 0.0);
			float k = clamp(0.5 + 0.5 * d / max(fwidth(d), 1e-4), 0.5, 1.0);
			tint = mix(t_second, t_best, k);
		}
	}
	// The LUT holds the palette's sRGB bytes, read raw by texelFetch; the
	// albedo is linear (Terrain3D samples its own textures as source_color).
	vec3 tint_linear = mix(tint.rgb / 12.92, pow((tint.rgb + 0.055) / 1.055, vec3(2.4)),
		step(vec3(0.04045), tint.rgb));
	vec3 tinted = mix(base_albedo, tint_linear, tint_mix * tint.a);
	if (heat_mix > 0.0) {
		float t = clamp((v_vertex.y - heat_sea_y) / heat_top_m, 0.0, 1.0) * 5.0;
		vec3 heat = mix(heat_c0.rgb, heat_c1.rgb, clamp(t, 0.0, 1.0));
		heat = mix(heat, heat_c2.rgb, clamp(t - 1.0, 0.0, 1.0));
		heat = mix(heat, heat_c3.rgb, clamp(t - 2.0, 0.0, 1.0));
		heat = mix(heat, heat_c4.rgb, clamp(t - 3.0, 0.0, 1.0));
		heat = mix(heat, heat_c5.rgb, clamp(t - 4.0, 0.0, 1.0));
		// The stops are the palette's sRGB bytes, passed raw (a Color uniform
		// goes straight through under GL Compatibility): turned linear here,
		// as the LUT is above, after the ramp is blended in sRGB like the 2D map.
		heat = mix(heat / 12.92, pow((heat + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), heat));
		tinted = mix(tinted, heat, heat_mix);
	}
	ALBEDO = tinted;"""


## `code` with the tint uniforms after its render_mode (or shader_type) line
## and its ALBEDO line mixing toward the manor's colour; "" when the line is
## not there.
static func patch(code: String) -> String:
	# The built world's material is shared by every view that loads it: a
	# second view finds the first one's patch, which is its patch too.
	if is_patched(code):
		return code
	if not code.contains(ALBEDO_LINE):
		return ""
	var lines := code.split("\n")
	var at := -1
	for i in lines.size():
		var l := lines[i].strip_edges()
		if l.begins_with("render_mode"):
			at = i
			break
		if at < 0 and l.begins_with("shader_type"):
			at = i
	if at < 0:
		return ""
	lines.insert(at + 1, UNIFORMS + Map3DGroundWind.UNIFORMS + Map3DGroundRelief.UNIFORMS + Map3DGroundBalk.UNIFORMS)
	return "\n".join(lines).replace(ALBEDO_LINE, Map3DGroundBalk.RIM + TINTED_ALBEDO.replace(
		"\t// @WIND (Map3DGroundWind.STAGE, then Map3DGroundRelief.STAGE)\n",
		Map3DGroundBalk.STAGE + Map3DGroundWind.STAGE + Map3DGroundRelief.STAGE))


## Whether `code` already carries the tint (a view loaded the world before).
static func is_patched(code: String) -> bool:
	return code.contains("// Map3DGroundTint:")


## The LUT's size for ids 0..max_id: LUT_WIDTH wide, as many rows as needed.
static func lut_size(max_id: int) -> Vector2i:
	return Vector2i(LUT_WIDTH, maxi(1, ceili(float(max_id + 1) / LUT_WIDTH)))
