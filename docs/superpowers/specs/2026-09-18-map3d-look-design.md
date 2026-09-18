# 3D map: zoom, ground, water, HUD, clouds — design

Owner request 2026-09-18. The 3D MAP tab (`scripts/map3d/`, pipeline in
`tools/map3d/`) gets:

1. zoom by trackpad as well as wheel, and closer (800 m);
2. the `assets/map3d/textures` materials visibly rendering their detail;
3. natural transitions between those materials;
4. no blur up close;
5. settlements as hollow rings (placeholder);
6. a scale bar bottom-right and a compass top-left, like the 2D map's;
7. clouds drifting while time runs — more of them than on the 2D map;
8. good-looking rivers (and, with them, the sea);
9. **at least 60 fps**;
10. **no trees** (owner: none).

Approach chosen: stay on Terrain3D's standard material and fix the DATA the
bake gives it (option A), not a custom 16-layer terrain shader.

## Baseline (measured 2026-09-18)

`tools/map3d/bench.gd`, Apple M5 Pro, GL Compatibility, 2560×1440, vsync off,
the build's CameraMid: **4.4 ms (227 fps)**, 324 draw calls; sun shadows
~1.4 ms of it (3.0 ms off; one cascade 3.5 ms); the terrain ~3.4 ms.

Observed faults: the colour map (16 % macro darkening over a far-colour
multiplier) hides the materials; blend weights come from 50 m biome pixels,
so near view shows round, soft-edged rock blotches; the shoreline is the 50 m
land mask upscaled — a visible staircase; the one dual-scaled texture
switches at 100–170 m, nearer than the camera ever comes;
no rivers are drawn at all; the sea is a flat opaque plane; the view ignores
trackpad gestures; the nearest zoom is 2.5 km.

## 1. Camera and input (`Map3DView`, `Map3DGeometry`)

- `map3d_zoom_min_m` 2500 → **800**. Pitch ramp unchanged.
- `InputEventMagnifyGesture` zooms by its factor; `InputEventPanGesture` pans
  by `delta × map3d_trackpad_pan_px` — the same events `WorldMapView`
  handles (`world_map_view.gd` ~1899).
- **Zoom is anchored at the cursor**: the ground point under the pointer
  stays under it (as on the 2D map). Pure helpers, tested:
  `Map3DGeometry.zoomed_by(distance, factor, min_d, max_d)` and
  `Map3DGeometry.zoom_about(target, anchor, old_d, new_d) -> Vector2`, the
  new target (it moves toward the anchor by `1 − new_d / old_d`).

## 2. Settlements: hollow rings

- The discs become one camera-facing quad per settlement (a MultiMesh per
  group, as now) drawn by `settlement_ring.gdshader`: an anti-aliased SDF ring,
  the quad scaled in the vertex shader to a CONSTANT SCREEN SIZE with the
  same `px_per_dist` sum as `border_line.gdshader`.
- `data/map3d_settlements.csv` columns `diameter_m,height_m` →
  `ring_px,line_px`: capital 28/3, city 20/2.5, town 14/2, fort 14/2,
  village 9/1.5 (design px, × the render scale); `color` stays.
- No depth test (a pin shows over a ridge, as in CK3); render priority over
  the lines. The quad sits on `_height_at` of its burg.
- The clicked settlement's ring is drawn thicker in `map3d_selection` gold
  (a separate one-instance MultiMesh). Pick radius = max(ring's screen
  radius, `map3d_pick_px`).

## 3. HUD: scale bar and compass (`Map3DHud`, new)

A Control child of `Map3DView` over the display, mouse-transparent except
the compass rect.

- **Scale bar, bottom-right**: metres per px at the target
  (`Map3DGeometry.metres_per_pixel`), stated in the 3D WORLD's own metres
  (50 m per pack px, the owner's campaign scale) — NOT `map_info.csv`'s
  `distance_scale`, which gives the 2D sheet 1 km per pack px and would make
  the bar lie by 20× — as m or km on `MapGeometry.nice_step`'s 1-2-5, drawn
  with the 2D map's `map_scale_bar_*` keys and colour so both maps match.
  Recomputed on every zoom. The bar-length sum is a pure, tested function.
- **Compass, top-left**: `CompassLayer` draws the oak wheel and turns it
  while time runs, exactly as on the 2D map (fallback: the vector rose);
  over it a **north needle** (vector: a gold lozenge, dark outline,
  `map3d_compass_needle_*`) turned clockwise by the yaw. **Clicking the compass** eases
  the yaw back to 0 over `map3d_compass_reset_s` (0.4 s).

## 4. Clouds (`Map3DClouds`, new, under the SubViewport)

- Flat, horizontal quads at `map3d_cloud_height_m` (3500 m), each
  `map3d_cloud_size_min_m`..`_max_m` (3–8 km) across, one MultiMesh (one draw
  call), textured by a soft-edged noise alpha generated once at load by
  `FastNoiseLite` (look-only generator seeded by `map3d_cloud_seed`, never
  the engine's stream), a few variants picked by UV offset.
- Drift downwind (`map3d_cloud_wind_deg`) at `map3d_cloud_speed_m_s` × the
  clock speed, only while the clock runs; fade out on pause over
  `map3d_cloud_fade_s`; spawned upwind of the visible ground, retired
  downwind; at most `map3d_cloud_max` **24** (2D: 8), `map3d_cloud_alpha`.
- **Shadows**: a shadow-only twin (alpha scissor, `SHADOW_CASTING_SETTING_
  SHADOWS_ONLY`) cast by the scene's sun, so they show within its 60 km
  shadow distance (near and mid zoom) and not at the farthest. Fallback if
  that fails or costs too much under Compatibility: a dark translucent quad
  on the ground offset along the sun direction.
- The camera may pass below the cloud deck at near zoom; clouds fade by
  camera distance inside `map3d_cloud_near_fade_m` so they never fill the
  screen.
- The drift, spawn, retire and fade logic is a pure `Map3DCloudField`
  (RefCounted), tested without frames; the node only draws it.

## 5. Performance: ≥ 60 fps is an acceptance gate

- **Criterion**: the in-game `Map3DView` (not the build's cameras), in a
  **3024×1964 window** on this Mac, at near (800 m), mid (24 km) and far
  (110 km) zoom, with rivers, sea, clouds, cloud shadows and rings on and the
  clock at 4x: ≥ 60 fps at every stop, and **≤ 8 ms per frame on this
  machine** — half the budget left for weaker Steam PCs.
- `tools/map3d/bench.gd` is rewritten to measure THROUGH `Map3DView` at the
  three zooms, printing frame time and draw calls, each new feature
  switchable off to price it. The tree toggles go (no trees). Run after each
  feature lands; over budget is fixed on the spot.
- Levers held in reserve: cloud shadows → ground decal; sun cascades 4 → 2;
  rivers merged into one mesh, far stretches a screen-width line; no
  depth-texture reads in the water shaders.
- Not a GUT test (frame time is machine-bound); an acceptance item with the
  numbers pasted into the commit/PR.

## 6. Ground: materials, transitions, sharpness (`bake_world.py`, `build_terrain.gd`)

- **Coast without steps**: the land mask is rasterised from the pack's shore
  loops (`geography/coasts.csv`: `land` loops filled, `lake` loops cut) straight
  onto the 20 m vertex grid with 4× supersampling to a coverage value, not
  upscaled from 50 m pixels; shore height goes smoothly from +`SHORE_M` to
  −`SHORE_M` across the coverage; the sea shader fades along it (§8).
- **Broken edges**: biome weights are sampled at domain-warped positions
  (noise of 300–1200 m wavelength, `EDGE_WARP_M` amplitude), so borders
  interlock instead of reading as blurred blobs.
- **Blend byte**: the ratio of the top two weights goes through a smoothstep
  into 0..255 with seeded dither — no contour banding.
- **Height blending**: `blend_sharpness` 0.5 → ~0.85, using the displacement
  in `_alb_ht`'s alpha, so grass grows into rock cracks rather than
  cross-fading.
- **Transition width per pair**: grass↔forest wide (~400 m), grass↔rock and
  rock↔cliff narrow (~60 m, an outcrop), sand only along the shore
  (≤ 100 m inland, ≤ 40 m high).
- **Colour map steps back**: macro depth 16 % → 6 %, hue drift 10 % → 4 %;
  near view shows the material's own colour, far view keeps the mottle.
- **Sharpness**: Terrain3D's `mipmap_bias` is a DERIVATIVE MULTIPLIER
  (range 0.5–1.5, 1.0 neutral — read from the shader in the plugin binary),
  so it goes 1.0 → 0.85, slightly sharper, not to 0; the terrain's samplers
  are already `filter_linear_mipmap_anisotropic`, so the project's
  `rendering/textures/default_filters/anisotropic_filtering_level` goes to
  4 (16×); `dual_scaling` on for the grass (texture 1) with near/far at
  1200/4000 m — the current 100/170 m is closer than the camera ever comes. Textures stay
  2048 px: at 800 m a screen px is ~0.6 m of ground, a texel ~0.08 m.
- The bake rules this touches move from constants into
  `data/map3d_bake.csv` (key,value,notes), read by `bake_world.py`; the rest
  of the README's "constants in scripts" item stays open.

## 7. Rivers

- **Carved beds** (`bake_world.py`): each river of `geography/rivers.csv`,
  in its order (source → mouth), resampled to 20 m; bed height along the
  course = min(ground, upstream bed − `RIVER_MIN_DROP_M` per step), so it
  always runs downhill; a U cross-section by distance to the centreline —
  bed across the water width, banks easing out over `RIVER_BANK_M`. Plains
  barely show a cut; mountains get gorges. The carved centreline heights
  are written to `bake/rivers.json` for the mesh.
- **Width**: `width_m = clamp(k·√discharge, RIVER_MIN_W_M 20, RIVER_MAX_W_M
  250)` at the mouth, grown from 0 at the source as `t^γ`
  (`map_river_taper_gamma`, the 2D rule).
- **Banks**: `dirt_floor` wet band within `RIVER_WET_M` of the water, colour
  map darkened 15 %. (No separate mouth sand: the beach band and the sea's
  near band already meet there.)
- **Water**: `Map3DRivers` (pure, tested) builds ONE ribbon ArrayMesh for all
  rivers from `rivers.json` — UV.x across (0..1), UV.y along (metres).
  `water_river.gdshader`: two normal maps scrolled along UV.y, fresnel toward
  the sky colour, alpha fading at the edges by UV.x (no hard edge), and the
  vertex shader widens to at least `map3d_river_min_px` on screen, so a
  river reads as a thin line at 110 km. Colour: `terrain_palette.csv`
  `river`, the sea's family.
- **Mouth**: the last `RIVER_MOUTH_M` widen and shade to the near-shore sea
  colour, so the river runs into the sea rather than stopping at it.
- The normal map is a seamless `NoiseTexture2D` (`as_normal_map`) made at
  load — no new art.

## 8. Sea

- The flat plane gets `water_sea.gdshader`: four depth bands by distance to
  shore sampled from the pack's existing `world_sea_distance.png` (the 2D
  map's own bake and bands — `terrain_palette.csv` `sea_near` / `sea_nearer`
  / `sea_far` / `sea_deep`, `map_sea_band_*_px` converted to metres), a
  slowly drifting normal map, fresnel, and alpha fading at the shore to
  meet §6's smooth coast. One mesh, one draw call, no depth texture.
- The sea floor keeps its soil and sand, faintly seen through the fade.

## Testing

- GUT, pure: `zoomed_by`, `zoom_about`, scale-bar length, compass
  needle angle and reset easing, `Map3DRivers` ribbon (vertex count, widths
  tapering source→mouth, minimum width, UVs), cloud spawn/retire and pause
  fade (`Map3DCloudField`, no frames needed).
- GUT, view (fixture scene, never the git-ignored build): gestures change
  distance/target; rings are placed per group with the CSV's sizes; the HUD
  exists with a scale bar and compass; clicking the compass resets yaw.
- Python bake: a smoke run printing coverage/river stats; previews in
  `bake/` looked at.
- Visual: `tools/snapshot_screen.gd --screen root --layer "3d map"` at near,
  mid and far (a `--zoom3d M` argument added for this).
- Performance: §5.

## Out of scope

Trees; kingdom labels, hover tooltips and army counters on the 3D map;
settlement models; Forward+ comparison; moving the remaining bake constants.
