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
"""

const STAGE := """	if (wind_on > 0.0) {
		float wd_d = length(v_vertex - CAMERA_POSITION_WORLD);
		float wd_k = 1.0 - smoothstep(wind_mid_m, wind_far_m, wd_d);
		if (wd_k > 0.0) {
			// two scales: the crop's own waves near, and far out broad gusts
			// sweeping the country (wind_far_scale times as big and as fast:
			// a true-speed wave does not move a pixel at the opening zoom)
			float wd_far = smoothstep(wind_near_m * 0.5, wind_mid_m, wd_d);
			float wd_wm = wind_wave_m * mix(1.0, wind_far_scale, wd_far);
			float wd_along = dot(v_vertex.xz, wind_dir) - wind_time * wind_speed_mps * mix(1.0, wind_far_scale, wd_far);
			float wd_across = dot(v_vertex.xz, vec2(-wind_dir.y, wind_dir.x));
			vec2 wd_q = vec2(wd_along / wd_wm, wd_across / (wd_wm * 2.5));
			// a warp so the crests bend and break instead of ruling lines
			wd_q += (vec2(wx_noise(wd_q * 0.31 + vec2(3.1, 7.7)), wx_noise(wd_q * 0.31 + vec2(9.4, 1.3))) - 0.5) * 1.6;
			float wd_wave = wx_noise(wd_q) * 0.65 + wx_noise(wd_q * 2.3 + vec2(5.2, 1.9)) * 0.35;
			// gusts: a slower field that swells and slackens the waves
			float wd_gust = wx_noise(vec2(wd_along / (wd_wm * 7.0), wd_across / (wd_wm * 7.0)));
			float wd_val = (wd_wave - 0.5) * 2.0 * mix(0.35, 1.0, wd_gust);
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
			base_albedo *= 1.0 + wd_amp * wd_val;
		}
	}
"""
