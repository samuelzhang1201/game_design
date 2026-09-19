# HEIGHTS on the 3D map, and height in war — design

Owner request 2026-09-19. Remakes the HEIGHTS tab on the 3D map (a height
heat map, the high and low points marked with their height, a tooltip on each)
and makes height count in war: the higher side of a fight fights better, and a
regiment standing high burns supplies faster.

This is item 5 of the migration list in `2026-09-18-map3d-default-design.md`,
the last 2D-only layer. Deleting the 2D map (`WorldMapView` and its layers,
the 2D bakes, `map3d_default`, `force_map3d_scene`, `--map2d`, tests moved off
2D, and what a fresh clone without a built scene shows) is the NEXT spec, its
own change (owner 2026-09-19: the 2D map is no longer wanted, no fallback).

## Owner rulings

- Combat advantage is the **relative height difference** between the two
  sides, not absolute altitude.
- The existing arm × terrain table (`army_terrain.csv`: horse up a mountain,
  bows on hills) stays; the height factor multiplies on top of it.
- Supply use goes up in **tiers**, not a curve.
- Landmarks are **local extremes filtered by prominence**, thinned by zoom.
- Landmarks are **named after the nearest town**.
- HEIGHTS has no 2D path any more.

## 1. The measure

`Elevation` (`scripts/engine/`, pure, `RefCounted`, cached, forgotten on
`load_map`) is the one place height is turned into numbers.

- `metres_of_cell(repo, id) -> int` = `(height − elevation_sea_level) ×
  elevation_m_per_unit`, whole metres. `balance.csv`: `elevation_sea_level` 20,
  `elevation_m_per_unit` 30 — the values `tools/map3d/bake_world.py` has
  hardcoded as `SEA_LEVEL` / `LAND_M_PER_UNIT`; the bake reads them from
  `balance.csv` instead, so the ground and the engine share one measure.
- The engine and every number the player reads use the CELL height. The 3D
  mesh's synthesized ridges are look only and never enter the simulation.
- `tier_of(repo, height) -> Dictionary` `{tier, supply_permille}`: the first
  row of `data/army_height_supply.csv` (`tier,min_height,supply_permille,notes`),
  read highest first, whose `min_height` the cell height reaches:

  | tier      | min_height | supply_permille |
  |-----------|-----------:|----------------:|
  | plains    | 0          | 1000            |
  | hills     | 45         | 1300            |
  | mountains | 62         | 1700            |
  | peak      | 72         | 2200            |

  The lines are the biome bands' (`map_biome_hill/mountain/peak_height`), so
  the rock and the snow on the ground are where the tiers change.
- `local_edge_m(repo, id) -> int`: the cell's metres minus the mean metres of
  its neighbours out to `landmark_ring` rings (tooltip only).

## 2. Height in war (`ArmySystem`)

- `elevation_of(repo, reg) -> int`: `Elevation.metres_of_cell` of the cell
  under the regiment; 0 for a fleet or off the land.
- `height_factor(repo, delta_m) -> int` (per mille) =
  `1000 + clamp(delta_m × army_height_bonus_permille_per_100m / 100,
  −army_height_bonus_cap_permille, +army_height_bonus_cap_permille)`.
  Draft: 40 per 100 m, cap 300 (±30%, reached at 750 m).
- `battle_odds`: `a = power(attacker, "attack") × height_factor(Δ) / 1000`,
  `d = power(defender, "defend") × height_factor(−Δ) / 1000`, where
  `Δ = elevation_of(attacker) − elevation_of(defender)`. The higher side gains
  whichever stance it is in, and the lower side loses by the same amount.
  `battle_odds` stays marked PLACEHOLDER; height is its first settled factor.
- `supply_use(repo, reg)` = the current headcount use × the tier's
  `supply_permille` / 1000 (a fleet is not scaled). `settle_month`, the card's
  `−N / mo` and the march's supply score all read it.
- **One set of lines.** `terrain_of` currently makes hills at
  `manor_focus_high_height` 52 and mountains at `manor_focus_peak_height` 63.
  It reads `Elevation.tier_of` instead: hills from 45, mountains from 62, and
  peak counts as `mountains` for `army_terrain.csv`. Some regiments that read
  Plains now read Hills; that change is intended.
- The regiment card gains `army_height`: `1340 m · Hills · supply ×1.3`, with
  the formula in its tooltip (a `resource_icons.csv` row; its icon art is
  queued, not generated, per the art rules).
- No new state; nothing is saved.

## 3. Landmarks

`Elevation.landmarks(repo) -> Array` of
`{cell, kind ("high"|"low"), metres, prominence, lod, name, pos}`, biggest
prominence first (ties by cell id), so the biggest point is named first and
drawn first:

- A **high** point is a land cell higher than every neighbour; a **low** point
  a land cell (not lake, not sea) lower than every neighbour.
- Prominence = |metres − mean metres of the cells out to `landmark_ring`
  (draft 2) rings|. Below `landmark_min_prominence_m` (tuned 100) it is
  dropped.
- `lod` 0..2 by `landmark_lod_mid_m` / `landmark_lod_far_m` (tuned 300 /
  560): the prominence at or above which a landmark still shows at the far
  zooms.
- **Names**: `data/landmark_names.csv` (`kind,pattern`), e.g.
  `high,Mount {town}` / `{town} Fell` / `{town} Crag` / `{town} Heights`,
  `low,{town} Vale` / `{town} Hollow` / `{town} Basin`. `{town}` is the
  nearest burg. The pattern is picked by a hash of the cell id; on a clash
  the next pattern is tried, then the next-nearest town. An optional pack
  table `data/maps/<id>/landmark_name_overrides.csv` (`cell_id,name`) wins.
  Everything is computed at load, deterministic, and never saved.

## 4. The 3D map

- `GameRoot._sync_map_view` drops `and not _height_view`; HEIGHTS stays on
  the 3D map. `set_map3d_theme` takes `"heights"` beside `"manors"`, and the
  two stay mutually exclusive (`set_height_view` / `set_manor_view`).
  MILITARY can stand over HEIGHTS.
- **Heat**: `Map3DGroundTint.patch` also adds `heat_mix` and six `heat_N`
  colour uniforms from `terrain_palette.csv`. Under HEIGHTS the ALBEDO mixes
  `map3d_heat_tint` (draft 0.85) toward the ramp at the fragment's WORLD
  height (the vertex's y from the terrain, 0 at the waterline, top stop at
  `elevation_m_per_unit × (100 − elevation_sea_level)`), lit by the relief
  like the ground. The sea keeps its bands. The test that holds the ALBEDO
  line also holds `heat_mix`.
- **Legend**: `Map3DHud` draws a vertical ramp bottom-left with metre ticks
  and the three tier lines labelled.
- **Marks**: ▲ for high and ▽ for low, with `2130 m` beside each, drawn on
  the HUD at a constant screen size (`map3d_landmark_*_px`). The `lod` level
  shows by the camera's distance (`map3d_landmark_lod_*_m`); a mark that
  would overlap a settlement dot, a regiment counter or a bigger landmark is
  dropped.
- **Hover**: `hover_pick` picks a landmark within `map3d_pick_px` before a
  settlement, and the tooltip reads:

  ```
  Mount Charton
  2130 m · Peak · Cold desert
  Harhamburgh province — House Ward
  Garrison: supply ×2.2 (peak)
  840 m above the land around — +30% in a fight against it
  ```

  (the last line's percentage is `height_factor(local_edge_m) − 1000`). A
  click opens the same facts as a card in the left column
  (`MapObjects.landmark_lines`, the lines payload; `object_selected` with
  kind `landmark`). Hovering elsewhere still sends the country card.
- The 2D `show_heights` / `heat_mesh` are not touched and are left for the
  2D-deletion spec.

## 5. Testing

- `tests/engine/test_elevation.gd`: the metres; each tier's edges (44/45,
  61/62, 71/72); extremes and prominence on a hand-built grid; the LOD; a name
  clash moving to the next pattern; an override winning.
- `tests/engine/test_army_system.gd`: `height_factor` at Δ 0, +500, ±1000
  (capped); `supply_use` per tier and not for a fleet; `battle_odds` symmetric
  when the two sides swap ground; `terrain_of` at the new lines.
- `tests/map3d/`: the patched shader carries `heat_mix`; `"heights"` keeps
  the 3D view; landmark LOD filtering; the hover payload.
- Visual: the `visual-review` loop — `snapshot_screen --layer heights` at far,
  mid and near zoom, plus `--hover3d` on a peak — and `tools/map3d/bench.gd`
  inside its 8 ms budget.

## 6. Documentation

CLAUDE.md: the 3D map paragraph says HEIGHTS draws on 3D (heat, landmarks,
tooltips) and that the migration list's one remaining step is deleting the 2D
map; the bottom-bar paragraph drops "HEIGHTS alone is 2D"; the regiment
paragraph gains the height factor and the supply tiers.
`2026-09-17-regiment-state-design.md` gets a pointer to this spec.
