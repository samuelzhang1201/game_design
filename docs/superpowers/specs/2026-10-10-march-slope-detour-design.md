# March slope: columns go round ground too steep to climb — design

Owner request 2026-10-10 (item 7 of the day's brief):

> 我看到有时候军队可以直接移动跨越一个很高的山坡，这是不合理的，不是那么陡峭的山地可以，但是如果山坡斜度超过一定限制，军队必须走最近的绕道

**Status: built on feat/march-slope; the visual review of a bent route is in the report.**

## Rulings made without the owner (to confirm)

1. **The slope is the slope the 3D map DRAWS.** The engine's pack cells (~1 km)
   carry none of the Terrain3D relief's scarps (`bake_world.py` terraces), so a
   new bake, `tools/map3d/bake_march_grid.py` (run by `build_pack.sh` after
   `bake_world.py`), reads the build's `bake/height_war.r16` and writes the
   pack's `data/maps/<id>/geography/march_grid.png`: one 8-bit cell per
   `army_march_grid_px` (4 pack px = 200 m of the 3D world = 10 vertices), the
   steepest rise per run in hundredths, 255 for water. The heights are blurred
   over `army_march_slope_smooth_m` (40 m) and differenced across
   `army_march_slope_run_m` (120 m), the sea held at the waterline so a shore
   is no cliff. A cell is water when fewer than `army_march_land_min_permille`
   of its vertices stand above the waterline (rivers stay fordable). The engine
   never reads `assets/3D`.
2. **The limit: `army_max_slope` = 1000 per mille (45° as drawn).** Measured on
   the default pack: at 1.0 the terrace scarps that ring the plateaus block
   (broken by the softened stretches, so every plateau is still reachable), the
   ridged mountains and every gentle hill do not; land cells' median steepest
   slope is 0.35. 3,821 of 45,791 land cells (8.3%) are closed; the main land
   stays one piece of open ground. The threshold lives in the engine, so a
   change needs no rebake.
3. **"最近的绕道" = the SHORTEST way round, by distance alone.** The ground's
   pace (roads, forest) is not in the choice: a road-weighted search would pick
   a longer detour than the nearest, and reading every cell's ground cost 0.8 s.
   The march still walks each day at the ground's pace where it stands.
4. **Water is closed to a land column** (the same grid): a march across a bay
   now goes round it. A fleet is never routed.
5. **Only a blocked march is routed.** A straight line that crosses no closed
   cell walks as ever and stores no route. The ends' own cells never block (a
   town on a scarp); a march from or to a closed cell starts from the nearest
   open cell within `army_march_snap_cells`. No way round (another island, a
   walled pocket) walks the straight line, silently.
6. **Waypoints**: each curve leg that crosses a closed cell is replaced by the
   way round between its two control points; the waypoint stays on the road.
7. **The foes and a beaten column's retreat** go through the same road
   (`ArmySystem.aim_entry`); a host re-aimed at the same end keeps its road.

## Engine

- `MarchPath` (`scripts/engine/march_path.gd`, RefCounted, cached per pack and
  `army_max_slope`, forgotten by `load_map`): `clear` (cells a line touches,
  Amanatides–Woo, corners count both sides), `road(from, to)` (A* on Godot's
  `AStarGrid2D`, eight ways, a diagonal only past two open sides, step 5 /
  diagonal 7 and an octile estimate — whole numbers far below 2^24, so the
  float search adds them exactly on every machine — then pulled taut by line
  of sight, galloping then halving), the open ground's pieces so a road to
  another piece is known none at once, the found cell paths cached.
- `ArmySystem.route_m_of(repo, from, waypoints, to, naval)` is the one road
  maker for `set_march_m`, `march_days_between`, `curve_px` and `aim_entry`;
  `_path_of` ignores a route that no longer ends on the destination.
- Cost: the grid loads in ~30 ms and its A* builds in ~50 ms the first time a
  road is needed; a road then takes ~0.6 ms mean, 3 ms worst on the pack.
- Tests: `tests/engine/test_march_path.gd`; mechanics tests walk straight
  through `SuiteData.open_country` (in `flat_ground`).

## Map

- Every plan line (`curve_px`: the aim ruler, the confirm panel's distance, a
  riding courier's order, the war room's arrows) and every committed route
  (`route_px`) draws the road round.
- The 3D piece walks its day through the route's corners it passes
  (`CourierSystem.day_path_of`, `Map3DUnits.along_day`, `MarchRoute.along`), not
  the chord over the scarp.

## Consequence to rule on

With no orders, the prologue's invasion now loses Castleton on every seed tried
(1–5, 11): the raiders' real road to Walbover is too long for their stores, so
they raid Altnesbury, live off the plunder and take Castleton, then HOLD it.
Before, no town fell. `test_raid`'s three-month bound now counts a HOLD host as
done.
