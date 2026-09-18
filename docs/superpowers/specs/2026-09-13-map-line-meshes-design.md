# Map Line Meshes — Design

**Date:** 2026-09-13
**Status:** Approved by owner in chat (2026-09-13): approach A (bake per zoom), scope rivers + routes + lanes + borders + seams, acceptance "pan at 60 Hz without dropped frames".
**Scope:** Stop rebuilding the world map's line layers every frame. Each layer becomes one `ArrayMesh` in native map px, baked at the current zoom and drawn with a single `draw_mesh` in its existing place in `WorldMapView._draw`.

## Context

`dfc8f82` moved the terrain decor to one mesh over one atlas (`MarkMesh` / `MarkAtlas`), which took political panning from ~35 to ~70 fps. The line layers are now the largest per-frame costs left on the political and provinces views.

`tools/bench_map`, 1280x720, 90 frames, Apple M5 Pro, `main` at `dfc8f82`:

| step | avg | p95 | frames > 16.7 ms | largest `_draw` layers |
|---|---|---|---|---|
| political @ world | 14.0 ms | 17.1 | 9/90 | rivers 2.0, wash 1.2, pins 1.1, borders 0.7 |
| political @ home | 15.0 ms | 18.2 | 10/90 | rivers 2.1, wash 1.2, pins 1.1, borders 0.7 |
| political @ close | 14.0 ms | 16.7 | 5/90 | pins 2.1, routes 1.7, borders 1.6 |
| provinces @ world | 16.3 ms | 18.3 | 37/90 | rivers 2.0, seams 1.5, wash 1.2 |
| provinces @ home | 15.7 ms | 18.8 | 21/90 | rivers 2.0, seams 1.4, wash 1.2 |
| provinces @ close | 16.3 ms | 17.8 | 32/90 | seams 2.7, pins 2.2, routes 1.7, borders 1.5 |

Why the lines cost what they do:

- **Rivers** rebuild every visible river's tapered ribbon in screen px each frame: `_screen_polyline`, then `river_taper`, then `MapGeometry.ribbon`, then `_fill_tris`.
- **Routes** transform and stroke every road and trail with `draw_polyline` each frame, twice when there is a shoulder.
- **Borders, seams and lanes** are already cut once per zoom in native px by `MapDashCache`. A frame still transforms every point (`_view_xform() * native`), and `draw_polyline_colors(..., antialiased = true)` rebuilds the strip and its AA feather on the CPU.

All of these widths and dash lengths are in **screen** px. That is why the geometry depends on the zoom, and it is also why a pan changes nothing but the transform.

## Approach

Bake each layer at the current zoom, with widths, dashes and the AA feather converted to native px (screen px / zoom). Draw it with the view transform, the same way the decor mesh is drawn. A pan becomes five `draw_mesh` calls. A zoom rebuilds the meshes, which costs about what every frame costs today, so zooming is no worse.

Rejected alternatives:

- **B. GPU extrusion in a vertex shader.** Exact at every zoom with no rebuilds. However, a material belongs to a whole CanvasItem, so the lines would have to move into child layers and the map's draw order would need restructuring. `CUSTOM0` support in the Compatibility renderer is also unverified. This goes beyond the acceptance bar.
- **C. A plus zoom quantisation.** Rebuild only when the zoom drifts more than N%. Line widths would breathe by N%. Not needed while zooming only has to be "no worse"; the bench zoom step added here will show whether it is ever wanted.

## Components

### 1. `LineMesh` (`scripts/engine/line_mesh.gd`, `RefCounted`, engine-pure)

A builder for many lines in one mesh:

```gdscript
var lm := LineMesh.new(feather)            # feather: native px of the AA fade on each side
lm.add_line(points, half, colors)          # PackedVector2Array, PackedFloat32Array, PackedColorArray — all the same length
lm.add_dashes(entry, half, ink, pale)      # a MapDashCache entry; OFF drawn in `pale` (clear for hatching/seams)
var mesh: ArrayMesh = lm.build()           # one PRIMITIVE_TRIANGLES surface with vertex colours; no surface when empty
LineMesh.triangle_count(mesh) -> int       # test seam
```

- **Offsets.** At each point the offset follows the bisector of the two legs, the same rule as `MapGeometry.ribbon`, so the band neither pinches nor tears at a bend. Factor that step out of `ribbon` into `MapGeometry.ribbon_edges(pts, half) -> [left, right]` so the two cannot drift apart. `ribbon` keeps its signature and its tests.
- **Geometry per line.** Each line emits three strips:
  - the core, between left and right at `half[i]`;
  - one feather strip on each side, from the core edge out to `half[i] + feather`, with the outer vertices at the point's colour and alpha 0.
  - This matches what an antialiased `draw_polyline` looks like at one screen px of fade.
- **Triangle order is draw order.** Lines added later are drawn over earlier ones.
- **Dashes.** `add_dashes` walks the entry's `points` / `phase`:
  - consecutive non-`JUMP` vertices form one continuous line whose per-vertex colour comes from its phase (`ON` → ink, `OFF` → pale);
  - a `JUMP` vertex ends the current line;
  - no triangle ever bridges a jump.
- **Degenerate input is skipped.** Lines with fewer than 2 points, and zero-length legs (they would give a NaN normal), produce nothing.

### 2. `MapLineLayers` (`scripts/ui/map_line_layers.gd`, `RefCounted`)

A keyed cache of the view's line meshes:

```gdscript
func mesh(key: String, zoom: float, sig: int, build: Callable) -> ArrayMesh   # build: () -> ArrayMesh, called only on a miss
func clear() -> void
var builds := 0                                                                # test seam
```

- **Invalidation.** An entry is rebuilt when its `zoom` or its `sig` differs from the one it was built with. Entries are independent, so a hover change rebuilds the borders and nothing else.
- **Placement.** The view owns one instance and exposes it as `line_layers()`, mirroring `dash_cache()`.

### 3. `WorldMapView` changes

`_draw()`'s layer order does not change. Each function below keeps its early returns and visibility rules and swaps its per-frame stroking for one `draw_mesh(mesh, null, _view_xform())` when the mesh has a surface.

| function | mesh key(s) | sig | baked from |
|---|---|---|---|
| `_draw_rivers` | `rivers` | 0 | every river: `river_curve`, `river_taper(n, half_max, gamma)` with `half_max = max(map_river_min_px, k·sqrt(discharge)·zoom) / 2 / zoom`, colour `river` at `map_river_alpha` |
| `_draw_routes` | `roads`, `trails` | 0 | every route of the group, smoothed by `route_curve`: shoulder first (`width·(1 + 2·soft)`, alpha `·soft_alpha`), body second, widths `/ zoom` |
| `_draw_routes` | `lanes` | `_ownership_sig()` (as today) | `_dashes.cut_lazy("lanes", ...)`, `add_dashes` with pale = clear |
| `_draw_state_borders` | `borders` | `hash([_ownership_sig(), hovered_kingdom()])` | every kingdom's `border:` dash entry, dark/pale at `map_state_border_width`; the hovered one is added LAST, in `hover_border` at `map_hover_border_width`, so it lies over its neighbours' shared edges |
| `_draw_province_seams` | `seams` | `_ownership_sig()` | every kingdom's `seams:` dash entry, pale = clear |

- **Visibility stays per frame and never rebuilds.** Trails and lanes need `view_scale() >= map_trail_min_scale`; seams need `_seams_shown()`. This is why roads and trails are separate meshes.
- **No viewport culling in the draw path.** The GPU clips off-screen triangles. `visible_rivers()` / `visible_river_count()` / `visible_seam_count()` remain bbox computations for the tests and for anything else that asks.
- **Palette and balance values are baked into vertex colours at build time.** They are data loaded once, so no sig covers them.

### 4. Balance value (`data/balance.csv`)

`map_line_feather_px,1.0,"world map: the antialiasing fade on each side of every baked line (rivers, routes, lanes, borders, seams), in screen px — baked as native px at the zoom the line was built for"`

## Data flow

```
_draw
 └─ _draw_rivers / _draw_routes / _draw_state_borders / _draw_province_seams
     └─ line_layers().mesh(key, _zoom, sig, build)
          hit  → the kept ArrayMesh                        (every pan frame)
          miss → build(): MapDashCache entries / curves → LineMesh → ArrayMesh
     └─ draw_mesh(mesh, null, _view_xform())
```

`MapDashCache` keeps doing the cutting. `MapLineLayers` sits one step later and keeps the triangles.

## Error handling

- A pack without rivers, routes or province borders gives empty meshes. The draw functions skip `draw_mesh` for a mesh with no surface, and nothing crashes on a stripped pack.
- `_zoom` is clamped by `_zoom_min()` and is never 0. `LineMesh` still guards `feather` and `half` against non-finite values by treating them as 0.

## Tests (GUT, headless, written before the code)

**`tests/engine/test_line_mesh.gd`** (hand-computed):

- Straight line `(0,0)→(10,0)`, `half` 2, feather 1, white:
  - core vertices at y = ±2;
  - feather outer vertices at y = ±3 with alpha 0;
  - 6 triangles (3 strips × 1 segment × 2).
- 90° bend `(0,0)→(10,0)→(10,10)`, `half` 1:
  - at the bend `(10,0)` the direction is `normalize((1,0)+(0,1)) = (√½, √½)`, and Godot's `orthogonal()` of that is `(√½, −√½)`;
  - so the bend's core vertices are `(10+√½, −√½)` and `(10−√½, √½)`, matching today's `MapGeometry.ribbon`, which does not miter-scale.
- `add_dashes` on a hand-built entry with a `JUMP` pair: no triangle has vertices from both sides of the jump.
- `add_dashes` colours: an `ON` vertex carries ink, an `OFF` vertex carries pale.
- Empty input, a 1-point line and a zero-length leg: no surface / no NaN vertices.
- `MapGeometry.ribbon` output is unchanged after the `ribbon_edges` extraction; the existing test stays green.

**`tests/ui/test_world_map_view.gd`**:

- `test_a_pan_builds_no_line_mesh_but_a_zoom_or_conquest_does`, mirroring `test_a_pan_cuts_no_dashes_but_a_zoom_or_conquest_does`:
  - a pan leaves `line_layers().builds` unchanged;
  - a zoom raises it;
  - `MapOwnership.set_owner` raises it.
- `test_hovering_a_kingdom_rebuilds_only_the_borders`: after warm-up, `hover_state(sid)` plus a redraw adds exactly one build.
- All existing river, route, seam, border and dash tests stay green unchanged. The suite must report a clean error count (`./run_tests.sh`).

**`tools/bench_map.gd`**:

- Adds a **ZOOM** step per view: the zoom oscillates by `ZOOM_STEP` around the home zoom every frame for the step's frames, with the hover probe as in PAN.
- Baseline is recorded before the first code commit. Every commit message carries the before/after lines.

**Acceptance**:

- political and provinces PAN at world / home / close: p95 < 16.7 ms.
- ZOOM avg is no worse than the baseline.
- `tools/snapshot_map` at `--zoom 1.0` and `--zoom 3.0`, before and after, compared side by side for line weight and AA. Differences beyond the feather's softness are bugs.

## Build order (one commit each, after the manor-decor work in `.claude/worktrees/map-sea-rivers` has landed on `main`; new worktree from that `main`)

1. `bench_map` ZOOM step, and the baseline recorded.
2. `MapGeometry.ribbon_edges` extraction + `LineMesh` + `tests/engine/test_line_mesh.gd`.
3. `MapLineLayers` + rivers baked, with the view test for pan/zoom builds.
4. Roads, trails and lanes baked.
5. Borders (with hover) and seams baked, with the hover test; `map_line_feather_px` in `balance.csv`.
6. CLAUDE.md: a sentence beside the MarkMesh note saying the line layers are baked per zoom by `LineMesh` / `MapLineLayers`.

## Out of scope

- The economy view (manor mesh edges, badges): the next target named in `dfc8f82`.
- Pins, kingdom labels, the political wash and the hover probe.
- Shader-extruded lines (approach B) and zoom quantisation (approach C).
- Coast lines: `map_coast_width` is 0 and they draw nothing.
