# Terrain From Data — Design

**Date:** 2026-09-11
**Status:** Approved by owner in chat ("go", 2026-09-11) section by section.
**Scope:** Remove the Azgaar PNG render as the map background. The game draws the terrain itself from the Azgaar JSON's cell geometry, imported into pack tables by the existing GDScript importer. Everything the game already draws over the terrain (political wash, borders, seams, labels, pins, armies) is unchanged.

## Owner rulings (2026-09-11)

1. **Look:** a stylized relief map. Biome-tinted land with relief shading from cell heights, a smoothed coastline, a depth-graded sea, lakes, rivers and roads. All from data; no terrain art needed. Texture passes (paper grain, hillshade) can be layered over it later.
2. **One tool, one coordinate space.** The terrain data is written by `tools/import_azgaar.gd`, in the JSON's native coordinates, like every other pack table. The Python converter under `assets/azgaar_godot_assets/` and its cropped 1.6× outputs are not used by the game; the folder stays as a reference only.
3. **Rendering:** a vector mesh (approach A). All cells are triangulated once into a single `ArrayMesh` with vertex colours and drawn with one `draw_mesh` per frame. Not a baked texture, not the README's id-texture shader.

## Context

Today the map's only picture is `assets/maps/beria/world_map.png` (41 MB), a terrain-only Azgaar export. Because Azgaar's PNG export captures the current view, the pack carries `render_scale` / `render_offset_*` in `data/maps.csv`, measured by `tools/calibrate_render.py` and guarded by a test. The importer also needs the PNG present, checks its dimensions, and copies it. Everything else on the map — the political wash, kingdom borders, province seams, labels, settlement art, regiments — is already drawn by `WorldMapView` from pack tables.

The Azgaar JSON has what a terrain layer needs: 4833 Voronoi cells (3500 land) with vertex lists, heights 0–100 (sea below 20), biome ids, neighbour lists, and a feature id that says whether water is ocean or lake; 9.9k vertices, each listing its adjacent cells; 12 islands and 4 lakes as features.

## Architecture

```
Azgaar JSON ──▶ tools/import_azgaar.gd ──▶ data/maps/<id>/geography/vertices.csv   (new)
                     (no PNG needed)          data/maps/<id>/geography/cells.csv      (new)
                                              data/maps/<id>/geography/coasts.csv     (new)
                                              assets/maps/<id>/world_*_index.png     (unchanged)

data/terrain_palette.csv (hand-authored colours) + balance.csv (relief, light, widths)

DataRepository.load_map ──▶ repo.cells / repo.vertices / repo.coasts / repo.terrain_palette
MapTerrain (pure)       ──▶ build(repo) -> {vertices, colors, indices} in native coordinates
WorldMapView            ──▶ ArrayMesh built once; per frame: sea fill, draw_mesh(transform),
                            coast + lake strokes, rivers, routes, then the existing overlays
MapDetailPanel          ──▶ the place preview draws the same mesh through a small clipped Control
```

No save, RNG, or LLM change. The terrain is static reference geometry; ownership still lives in `GameState.province_owner` and is painted over it exactly as before.

## 1. Importer output

`tools/import_azgaar.gd` writes three new tables under `<pack>/geography/`, all in native map coordinates, two decimals like the other tables:

| table | columns | notes |
|---|---|---|
| `vertices.csv` | `vertex_id,x,y` | one row per `pack.vertices` entry |
| `cells.csv` | `cell_id,vertex_ids,height,biome_id,water,neighbor_ids` | one row per `pack.cells` entry. `vertex_ids` and `neighbor_ids` are `\|`-separated ids. `height` is Azgaar's 0–100. `water` is `""` for land (`h >= 20`), `ocean` or `lake` from the feature's `type` for water |
| `coasts.csv` | `kind,feature_id,loop,points` | closed loops as `x y\|x y\|...`. `kind` is `land` (the outline of all land cells: every island's shore, plus an inner loop wherever a lake sits inside land) or `lake` (each lake feature's own shore; `feature_id` is the lake's feature id, 0 for `land`). Built with the existing `_cell_group_loops`. A lake shore therefore appears twice, once per kind; the view draws both in the same colour, so nothing shows |

The importer no longer needs a PNG: the PNG discovery (`_newest_render`), the dimension check, `_png_dimensions`, `render_scale`, and the `world_map.png` copy are removed. The `--png` flag is removed. The three hit-test bitmaps are still generated at native resolution.

Deterministic as before: same JSON ⇒ byte-identical CSVs.

## 2. Hand-authored design values

**`data/terrain_palette.csv`** (`key,color,notes`), loaded into `repo.terrain_palette` by `DataRepository.load_all`:

- `biome_1` … `biome_12` — the game's own muted land tint per Azgaar biome id (Azgaar's `biomes.csv` colours are generated and too saturated; the generated table is never hand-edited).
- `sea_deep`, `sea_shallow`, `lake`, `coast_line`, `river`, `road`, `trail`.

A biome without a row falls back to the `biomes.csv` colour, so a re-export with a new biome still draws.

**`data/balance.csv`** new keys (all read through `repo.bal`):

| key | meaning |
|---|---|
| `map_relief_strength` | how much a slope facing the light brightens / away darkens |
| `map_relief_min`, `map_relief_max` | clamp on the shade factor |
| `map_light_x`, `map_light_y` | light direction (toward the light), normalised at use; default north-west |
| `map_altitude_gain` | extra brightening from sea level to the summit |
| `map_sea_depth_gamma` | exponent on `h/20` for the deep→shallow gradient |
| `map_coast_width` | coast stroke width in screen px |
| `map_river_min_px`, `map_river_width_scale` | river stroke: `max(min_px, width_scale × width)` where `width` is the river row's width |
| `map_road_width`, `map_trail_width` | route stroke widths in screen px |
| `map_trail_min_scale` | view scale at/above which trails and sea routes draw (roads always draw) |

Removed: `map_calibration_window_px`, `map_calibration_water_brightness`, `map_calibration_min_hit_share`.

## 3. Engine — `MapTerrain` (`scripts/engine/map_terrain.gd`, `RefCounted`)

Pure functions over a `DataRepository`; no Nodes, no RNG, so GUT pins the formulas headless.

`static func build(repo: DataRepository) -> Dictionary` returns `{"vertices": PackedVector2Array, "colors": PackedColorArray, "indices": PackedInt32Array}` in native coordinates, ready for `ArrayMesh.add_surface_from_arrays(PRIMITIVE_TRIANGLES, ...)`.

**Triangulation.** Each cell is a fan around its own centre. The centre is the mean of the cell's vertices (Voronoi cells are convex, so a fan is valid). Per cell: one centre vertex plus one ring vertex per polygon vertex; triangles `(centre, ring[i], ring[i+1])`. Ring vertices are per cell (not shared), so a cell's ring colour can differ from its neighbour's.

**Colours.**

- `cell_color(repo, cell) -> Color`:
  - land: `tint(biome) × shade(cell)`, where `tint` is `terrain_palette.biome_<id>` (fallback: `biomes.csv` colour), and
    `shade = clamp(1 + strength × dot(slope, light), relief_min, relief_max) × (1 + altitude_gain × (h − 20) / 80)`.
    `slope = Σ_n (h_n − h_c) · unit(p_n − p_c) / N` over the cell's neighbours (a 2-D vector pointing uphill; `p` is the cell centre, `N` the neighbour count; a cell with no neighbours has slope zero). `light` is the normalised `(map_light_x, map_light_y)`.
  - ocean: `lerp(sea_deep, sea_shallow, (h / 20)^gamma)`.
  - lake: `lake`.
- Centre vertex colour = `cell_color(cell)`.
- Ring vertex colour = mean of `cell_color` over the vertex's adjacent cells **of the same class as this cell** (land with land, water with water; `ocean` and `lake` are both water). So relief and biome blend smoothly inside a landmass, and the shore stays a crisp edge. A vertex's adjacent cells come from the cell rows: the importer does not write the vertex→cells list; `MapTerrain` builds `vertex_id -> [cell_id]` once from `cells.csv` (`vertex_ids`).

**Coast rings.** `repo.coasts` rows carry `polyline` (PackedVector2Array) set at load, like routes and rivers. The view smooths each ring with `MapGeometry.smooth_closed` (same steps key as kingdom borders, `map_border_smoothing_steps`) and caches the result; kingdom borders therefore sit on the drawn shore.

## 4. Data loading — `DataRepository`

- `load_all`: `terrain_palette.csv` → `terrain_palette: Dictionary` (`key -> hex string`).
- `load_map`: `geography/vertices.csv` → `vertices: Dictionary` (`vertex_id (int) -> Vector2`); `geography/cells.csv` → `cells: Dictionary` (`cell_id (int) -> row`, with `vertex_ids` and `neighbor_ids` parsed to `PackedInt32Array` at load); `geography/coasts.csv` → `coasts: Array[Dictionary]` with `polyline` parsed. All registered in `world_tables["geography"]` like the other geography tables. Absent tables load empty (a pack without terrain still loads; the map view then stays hidden, as it did without a PNG).
- Removed: `map_texture_path`, `render_scale`, `render_offset`. `data/maps.csv` loses `map_texture`, `render_scale`, `render_offset_x`, `render_offset_y`; the required-columns check drops `map_texture`.
- Map size comes from `map_info.csv` (`width`, `height`), already loaded.

## 5. View — `WorldMapView`

- `_ready`: `_terrain_mesh` is an `ArrayMesh` built from `MapTerrain.build`; `_map_size` is `Vector2(map_info.width, map_info.height)`. `visible = _terrain_mesh != null`. Every use of `_map_texture.get_size()` becomes `_map_size`.
- `_draw` order: `draw_rect(frame, sea_deep)`; `draw_mesh(_terrain_mesh, null, Transform2D(0.0, Vector2(_zoom, _zoom), 0.0, _offset))`; `_draw_coasts()` (land rings then lake rings, `coast_line` colour, `map_coast_width`, only rings touching the frame, same culling helper as borders); `_draw_rivers()` (`river` colour, width per §2, frame-culled by the row's `bbox`); `_draw_routes()` (`road` always, `trail` and `searoutes` at/above `map_trail_min_scale`); then the existing overlays in their current order.
- Coordinates: `map_to_screen(p) = _offset + p * _zoom`; `screen_to_map(s) = (s − _offset) / _zoom`; `view_scale() = _zoom`. `_render_scale`, `_cal_scale`, `_cal_offset` are deleted.
- Rivers and routes are now drawn by the game. The 2026-09-09 ruling not to trace them was because the render printed them; with no render there is nothing else to print them. Hover and card behaviour for lines is unchanged.
- Test seams: `visible_river_count()` (rivers whose bbox touches the frame), `terrain_mesh()`.

## 6. Detail panel preview — `MapDetailPanel`

`_set_preview(center)` no longer cuts an atlas from the PNG. A small `TerrainPreview` Control (in `map_detail_panel.gd`) draws the view's mesh and the coast rings with a transform that centres `center` in its rect at a fixed scale (`PREVIEW_SPAN` native px across, as today), `clip_contents = true`. The mesh is built once per panel from `MapTerrain.build` (or handed in by the screen, if it already has the view's — either is fine; the panel must not reach into the view).

## 7. Removals

- `assets/maps/beria/world_map.png` + `.import`.
- `tools/calibrate_render.py`.
- Importer: PNG discovery, dimension check, copy, `--png`, `render_scale`.
- `data/maps.csv`: four columns (§4). `balance.csv`: three calibration keys (§2).
- `DataRepository`: three fields (§4). `WorldMapView`: three fields (§5).
- Tests: `test_map_data.test_render_calibration_puts_the_coast_on_the_render_coastline`, `test_map_data.test_index_bitmap_matches_map_and_kingdoms`'s render-size half, `test_map_pack.test_render_calibration_is_usable`, `test_world_map_view.test_the_calibration_is_applied_to_the_render_mapping`, and the calibration wording of `test_screen_and_map_coordinates_round_trip_through_the_calibration` (kept as a plain round-trip).
- `CLAUDE.md`: the render / zoom-reset / calibration paragraph is rewritten to describe the data-driven terrain and the three new tables.

Kept: the three hit-test bitmaps and `MapIndex` / `MapObjects.object_at` (geometry never goes stale; ownership is looked up); the raw Azgaar JSON under the pack folder (it is the source); `assets/azgaar_godot_assets/` as a reference, not loaded.

## 8. Tests (written before the implementation)

**`tests/engine/test_map_terrain.gd`** (hand-built fixture repos, a few cells each):

- a flat cell (all neighbours at its height) has `shade == 1 × altitude term`;
- a cell whose only higher neighbour lies toward the light is brighter than flat; toward the opposite side, darker (hand-computed with `strength`, `light` from the fixture's balance rows);
- the shade clamps at `map_relief_min` / `map_relief_max`;
- ocean colour is `sea_deep` at `h = 0` and `sea_shallow` at `h = 20`, and monotone between; a lake cell is `lake`;
- a ring vertex shared by a land cell and an ocean cell takes, on the land cell's fan, the mean of the land neighbours only (and on the ocean cell's fan, the water neighbours only);
- `build` returns `indices.size() % 3 == 0`, `colors.size() == vertices.size()`, and one centre plus one ring vertex per polygon vertex per cell.

**`tests/engine/test_map_data.gd`** (the committed pack):

- `cells.csv`, `vertices.csv`, `coasts.csv`, `terrain_palette.csv` load; every cell's vertex ids and neighbour ids resolve; every land cell's `biome_id` is in `biomes.csv`; every water cell's `water` is `ocean` or `lake`;
- every coast loop has ≥ 3 points; the number of `lake` loops equals the pack's lake count, and the number of `land` loops is at least the island count (the land outline also has one inner loop per lake that lies inside a landmass; both counts are read from the JSON at review time and pinned as numbers with a comment naming the export);
- the player realm's capital pixel is land in the state bitmap (existing) and the capital's nearest cell is a land cell.

**`tests/ui/test_world_map_view.gd`:**

- coordinates round-trip through `map_to_screen` / `screen_to_map` (replaces the two calibration tests);
- `terrain_mesh()` is non-null and its AABB covers `(0, 0)–(width, height)`;
- `visible_river_count()` is 0 before homing on a 1×1 view and > 0 after zooming into the realm's capital;
- every other existing test passes unchanged (they hang off `Game.data` and the bitmaps, not the PNG).

**`tests/ui/test_map_detail_panel.gd`:** the preview is visible for a place with a centre and hidden without one (adapted from today's atlas assertion).

## 9. Migration

1. Write tests (§8), then `MapTerrain`, the loader changes, the importer changes.
2. Run the importer against the committed JSON: `Godot --headless --path . --script res://tools/import_azgaar.gd`. Commit the three new tables.
3. Switch the view and the panel; delete the PNG, the calibration tool, the columns, the keys, the tests, and update `CLAUDE.md`.
4. `./run_tests.sh` green ("Errors 2" only).

## Out of scope

Terrain textures, paper grain or shader post-processing over the mesh; cell-level gameplay (movement, A*); any change to hit-testing, ownership, labels, pins, or armies; deleting `assets/azgaar_godot_assets/`.
