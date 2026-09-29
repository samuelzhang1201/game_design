# Weather visuals on the 3D map — design (2026-09-29, overnight, owner asleep)

Owner: "出个天气视觉效果的方案，并实施…按照你的建议做". Today `Weather` (per province,
per `weather_spell_days` 3-day spell, stateless hash) changes SPEED only and is
shown only as a HUD glyph (`Map3DHudWeather`). This makes the weather VISIBLE,
presentation only (invariant 2: nothing here feeds the engine).

## Decisions (made without the owner, to confirm)
1. **Regional, not per-province-hard.** A low-res weather FIELD (1 texel = 16 pack
   px), each land texel the weather of its cell's province (`MapManors.province_of`
   with state, so annexation follows), blurred over land only (sea texels take the
   land average, so coasts keep their weather), sampled linearly and domain-warped
   by noise in the shader: a front, never the province outline ("nothing ends on a
   hard cut").
2. **Four ground channels, data per kind** — `data/weather.csv` gains columns
   `overcast, wet, mud, snow, rainfall, snowfall` (0..1). Ground RGBA =
   (wet, mud, snow, overcast); a second RG texture = (rainfall, snowfall).
3. **Ground, in the Terrain3D patch** (`Map3DGroundTint`, the same ALBEDO line;
   `w_normal`, `v_vertex`, `roughness` and `mat.albedo_height.a` are in scope there):
   overcast dims and slightly flattens colour; wet darkens and lowers `roughness`
   (a sheen); mud warms toward `terrain_palette` `weather_mud`; snow covers flat
   ground first (by `w_normal.y`), rocks/texture highs poking through, patchy by
   noise at light cover, colour `terrain_palette` `weather_snow`, never blown out.
   Every strength a `balance.csv` `map3d_weather_*` key.
4. **Spells cross-fade**: the current and the NEXT spell's fields (the hash makes
   the next computable) blend over the last `map3d_weather_blend_days` of a spell,
   driven by `Game.day_progress` like the sun — a front arriving, not a switch.
   One field build per spell (~9k texels, a few ms).
5. **Clouds follow the weather**: `Map3DCloudField` gets an optional weight so new
   clouds favour overcast ground (byte-identical without it — existing tests);
   a cloud over bad weather is darker and a little denser (instance COLOR.rgb in
   `cloud_deck.gdshader`); cloud shadows unchanged (owner ruled them faint).
6. **Precipitation**: two `GPUParticles3D` (rain streaks, snow flakes) in the
   authored scene under `Viewport/Weather`, a `particles` process shader emitting in
   a box round the camera target sized by camera distance (constant screen size),
   alpha from the fall texture at each particle, world-anchored (panning does not
   drag them); only nearer than `map3d_weather_fall_view_m`; light (the sun ruling:
   never cover the map); emitting only while the clock runs, like the clouds; count
   per tier (`graphics_quality.csv` column `weather_particles`); blizzard = dense,
   fast, slanted snow + heavy overcast.
7. HUD glyphs STAY (removing information needs the owner).
8. Tool hook: the view takes a weather override for `snapshot_screen --weather KIND`
   so each kind can be shot; visual review per the skill (before / 2–3 variants /
   crops / independent critic) at near and far zoom.

## Build order
field (pure, tested) → CSV columns + loader → ground patch + `Map3DLayerWeather`
(uniforms, cross-fade) → clouds → particles → snapshot flag → visual review →
bench (`tools/map3d/bench.gd`, the tier gates) → CLAUDE.md / taste notes.

## Status
Implemented 2026-09-29 on branch `weather-visuals` (CLAUDE.md "The weather is
DRAWN"). Changes from the plan above, after the look check and an independent
critic: the field is 8 px with ONE halving (provinces are tiny: 13 cells at the
median), the warp is 900 m, not 2.5 km, so a province keeps its own weather;
the houses take the snow and the rain too; the clouds turn wholly slate from an
overcast of 0.6 up; snow sits below white, lightly on steep ground, and a
blizzard adds a grey veil; mud is a dark umber (ochre read as drought); the
falling weather stops at 13 km (a flake far out read as a settlement dot).
Open: the bench's absolute numbers could not be read that night (the GPU was
shared with ComfyUI and Chrome; even the weather-off run read 32 fps) — the
weather's rows were within the noise of the same run. Re-run
`tools/map3d/bench.gd --quality high --size 3024x1964 --weather rain,snow,blizzard`
on a quiet machine.
