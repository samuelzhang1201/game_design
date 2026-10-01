class_name Map3DGroundWind
extends RefCounted
## The wind's stage in the patched Terrain3D shader (owner 2026-09-30:
## 草缓缓的随风摇摆…麦穗摇曳), spliced in by Map3DGroundTint.patch: waves of
## light and shade rolling down the wind over the crops (bake/fields.png's
## sown share) and, fainter, open level grass away from the woods — near, the
## crop's own waves; far out, broad gusts map3d_wind_far_scale times as big
## and as fast, so the wind still reads at the opening zoom (owner: 我并没有
## 看到麦浪和树摇 — the first cut was gone by 9 km). Map3DLayerWind advances
## wind_time only while the clock runs. Runs after the woods' stage and
## before the weather's, whose uniforms it reads.
##
## The SHEEN (owner 2026-09-30: 草地随风飘扬的质感 — blades cannot be drawn: at
## the closest zoom a screen pixel is a metre of ground): a crest is grass
## laid over by the gust, showing its paler, greyer side — strongest where the
## wind blows AWAY from the eye, so the stalks lie over toward the far side
## and turn their backs to it — and a trough stands a little deeper and
## greener. Near, fine STREAKS combed down the wind give the turf its grain,
## drifting slower than the waves and faded out before they alias.

const UNIFORMS := """
// The WIND (owner 2026-09-30: 草缓缓的随风摇摆…麦穗摇曳): waves of light and
// shade rolling down the wind over the crops (bake/fields.png's sown share)
// and, fainter, the open grass; stalks bent by a gust show their lighter
// side. Map3DLayerWind advances wind_time only while the clock runs; a wet or
// overcast province blows harder; it fades out with the camera's distance.
uniform float wind_on = 0.0;
uniform float wind_time = 0.0;
uniform vec2 wind_dir = vec2(1.0, 0.0);
uniform float wind_speed_mps = 6.0;
uniform float wind_wave_m = 60.0;
uniform float wind_field_amp = 0.12;
uniform float wind_grass_amp = 0.05;
uniform float wind_near_m = 1500.0;
uniform float wind_far_m = 9000.0;
uniform float wind_storm_gain = 1.2;
uniform float wind_far_scale = 8.0;
uniform float wind_mid_m = 5000.0;
uniform float wind_far_amp = 1.0;
uniform float wind_sheen_amp = 0.0;
uniform float wind_sheen_sat = 0.4;
uniform float wind_sheen_lift = 0.25;
uniform float wind_sheen_facing = 0.5;
uniform float wind_trough_sat = 0.6;
uniform float wind_streak_amp = 0.0;
uniform float wind_streak_m = 24.0;
uniform float wind_streak_across = 0.15;
uniform float wind_sheen_warm = 0.0;
uniform float wind_band_rise = 0.12;
uniform float wind_band_fall = 2.5;
uniform float wind_band_warp = 0.8;
uniform float wind_gust_len = 5.0;
uniform float wind_gust_width = 2.5;
uniform float wind_gust_cover = 0.35;
uniform float wind_dash_len = 2.5;
uniform float wind_dash_cover = 0.4;

// One set of waves over the grass (owner 2026-09-30: 看上去就像是雾气飘过一下，
// 不像是草地的起伏 — round soft blobs read as mist): thin crests ACROSS the
// wind, each rising fast and falling slowly behind like a rolling ripple,
// bent and broken by noise, and only where a gust is passing, so they come
// in runs rather than everywhere at once. along/across in metres, wm the
// wavelength, fw the pixel footprint in wavelengths (fwidth, taken by the
// caller); returns the wave (-0.15..1.1) and the gust (0..1).
vec2 wd_waves(float along, float across, float wm, float fw) {
	float x = along / wm;
	float y = across / wm;
	x += (wx_noise(vec2(y * 0.35, x * 0.12) + vec2(3.1, 7.7)) - 0.5) * wind_band_warp;
	float b = fract(x);
	float crest = smoothstep(0.0, wind_band_rise, b) * pow(1.0 - b, wind_band_fall)
		/ pow(1.0 - wind_band_rise, wind_band_fall);
	// each crest is broken into long tapering pieces along its length,
	// neighbours unlike, so the lines never run on like furrows or terraces
	crest *= smoothstep(wind_dash_cover, wind_dash_cover + 0.35,
		wx_noise(vec2(x * 0.55 + 3.7, y / wind_dash_len)));
	float gust = smoothstep(wind_gust_cover, wind_gust_cover + 0.3,
		wx_noise(vec2(along / (wm * wind_gust_len), y / wind_gust_width) + vec2(5.3, 2.1)));
	float aa = 1.0 - smoothstep(0.12, 0.3, fw);
	// LIGHT crests over grass left as it is: a darkened trough far out read
	// as cloud shadow (critic 2026-09-30)
	return vec2((crest - 0.12) * 1.25 * gust * aa, gust);
}
"""

const STAGE := """	if (wind_on > 0.0) {
		float wd_d = length(v_vertex - CAMERA_POSITION_WORLD);
		float wd_k = 1.0 - smoothstep(wind_mid_m, wind_far_m, wd_d);
		if (wd_k > 0.0) {
			// two scales: the crop's own waves near, and far out broad gusts
			// sweeping the country (wind_far_scale times as big and as fast:
			// a true-speed wave does not move a pixel at the opening zoom)
			float wd_far = smoothstep(wind_near_m * 0.5, wind_mid_m, wd_d);
			float wd_across = dot(v_vertex.xz, vec2(-wind_dir.y, wind_dir.x));
			float wd_pa = dot(v_vertex.xz, wind_dir);
			float wd_wmf = wind_wave_m * wind_far_scale;
			vec2 wd_n = wd_waves(wd_pa - wind_time * wind_speed_mps, wd_across, wind_wave_m,
				fwidth(wd_pa / wind_wave_m));
			vec2 wd_f = wd_waves(wd_pa - wind_time * wind_speed_mps * wind_far_scale, wd_across, wd_wmf,
				fwidth(wd_pa / wd_wmf));
			float wd_val = mix(wd_n.x, wd_f.x, wd_far);
			float wd_gust = mix(wd_n.y, wd_f.y, wd_far);
			vec2 wd_fuv = (v_vertex.xz - pack_origin) / field_m_per_texel / vec2(textureSize(field_map, 0));
			vec3 wd_ft = max(texture(field_map, wd_fuv).rgb, vec3(0.2));
			float wd_sown = clamp((1.0 - min(min(wd_ft.r, wd_ft.g), wd_ft.b)) / 0.25, 0.0, 1.0);
			float wd_grass = smoothstep(0.8, 0.93, w_normal.y);
			if (wood_on > 0.0) {
				vec2 wd_wuv = (v_vertex.xz - pack_origin) / wood_m_per_texel / vec2(textureSize(wood_map, 0));
				wd_grass *= 1.0 - clamp(texture(wood_map, wd_wuv).r * 2.0, 0.0, 1.0);
			}
			float wd_storm = 1.0;
			if (weather_on > 0.0) {
				vec2 wd_uv = (v_vertex.xz - pack_origin) / m_per_px / (weather_step_px * vec2(textureSize(weather_now, 0)));
				vec4 wd_wx = mix(texture(weather_now, wd_uv), texture(weather_next, wd_uv), weather_blend);
				wd_storm += wind_storm_gain * clamp(max(wd_wx.r, wd_wx.a * 0.7), 0.0, 1.0) * (1.0 - wd_wx.b);
			}
			float wd_amp = max(wind_field_amp * wd_sown, wind_grass_amp * wd_grass) * wd_k * wd_storm * mix(1.0, wind_far_amp, wd_far);
			float wd_t = wd_amp * wd_val;
			if (wind_sheen_amp <= 0.0) {
				base_albedo *= 1.0 + wd_t;
			} else {
				// the sheen: a crest turns the grass's pale side up, most when
				// the wind blows away from the eye; a trough stands deeper
				vec2 wd_eye = v_vertex.xz - CAMERA_POSITION_WORLD.xz;
				wd_eye /= max(length(wd_eye), 1.0);
				float wd_face = mix(1.0 - wind_sheen_facing, 1.0, dot(wind_dir, wd_eye) * 0.5 + 0.5);
				float wd_lum = dot(base_albedo, vec3(0.2126, 0.7152, 0.0722));
				vec3 wd_sheen = mix(vec3(wd_lum), base_albedo, wind_sheen_sat) * (1.0 + wind_sheen_lift)
					* vec3(1.0 + wind_sheen_warm, 1.0 + wind_sheen_warm * 0.6, 1.0 - wind_sheen_warm);
				float wd_dip = max(-wd_t, 0.0);
				base_albedo = mix(vec3(wd_lum), base_albedo, 1.0 + wd_dip * wind_trough_sat) * (1.0 - wd_dip);
				base_albedo = mix(base_albedo, wd_sheen, clamp(max(wd_t, 0.0) * wd_face * wind_sheen_amp, 0.0, 1.0));
			}
			if (wind_streak_amp > 0.0) {
				// the grain: streaks combed down the wind, near only, gone
				// before a streak is narrower than two pixels
				float wd_mpp = length(fwidth(v_vertex.xz));
				float wd_sw = wind_streak_m * wind_streak_across;
				float wd_vis = 1.0 - smoothstep(wd_sw * 0.25, wd_sw * 0.6, wd_mpp);
				if (wd_vis > 0.0) {
					float wd_sa = dot(v_vertex.xz, wind_dir) - wind_time * wind_speed_mps * 0.35;
					vec2 wd_sq = vec2(wd_sa / wind_streak_m, wd_across / wd_sw);
					wd_sq.y += (wx_noise(wd_sq * vec2(0.4, 0.08)) - 0.5) * 3.0;
					float wd_st = wx_noise(wd_sq) * 0.6 + wx_noise(wd_sq * vec2(1.7, 2.3) + vec2(4.3, 8.1)) * 0.4;
					float wd_on = max(wd_sown, wd_grass) * wd_k * wd_vis;
					base_albedo *= 1.0 + (wd_st - 0.5) * 2.0 * wind_streak_amp * wd_on * mix(0.6, 1.0, wd_gust);
				}
			}
		}
	}
"""
