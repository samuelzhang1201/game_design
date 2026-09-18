# ECONOMY and MANORS on the 3D map — the ground, the edges, the manor pick

Owner, 2026-09-18/19: "经济map和manor map，我要这两个tab被点击的时候，能否出现在3d地图上".
Part of the 3D migration (spec `2026-09-18-map3d-default-design.md`, list items
3 and 5). The two themes' map elements split into three sub-projects; the
owner chose to do the FIRST only and decide on the others after seeing it:

1. **This spec** — the manor cells coloured on the 3D ground, their edges,
   and picking a manor on the 3D map (its card and every manor order).
2. Not now — ECONOMY's output badges (good icon, category ring, units).
3. Not now — MANORS' estate drawings standing on the ground, and the
   settlement rings tinted by their manor.

## Behaviour

- `GameRoot._sync_map_view`'s 2D-only layers shrink to HEIGHTS and
  MILITARY: with ECONOMY or MANORS lit, the map panel stays on the 3D map.
  GameRoot also hands the 3D view the theme — `set_theme("")`,
  `"economy"` or `"manors"` (the two are exclusive already). The 2D map still
  gets `show_economy` / `show_manors` as now, so falling back to 2D (no
  built scene, or HEIGHTS/MILITARY taken over) shows the same theme.
- The left column is unchanged: EconomyPanel / the Manor Master.
- Under a theme the ground wears each manor's colour, computed by the SAME
  functions the 2D map uses (below), the cell edges are ruled in, and the
  borders, seams, rivers, roads, rings, kingdom names and hover stay on top.
- A click on the land under a theme picks the MANOR
  (`{"kind": "manor", "cell": id}`, what the 2D map returns in these layers):
  the gold outline goes round the cell and `object_selected` opens the manor
  card through the existing `MapDetailPanel` — buy, sell, build, work, all as
  on the 2D map. A settlement ring still wins over the land under it.
- Hover under a theme names the manor beside the cursor
  (`MapObjects.label_of` knows manors); the country card follows the
  manor's province's holder, as `WorldMapView._state_of` does.
- No theme: the ground is exactly as it is today.

## One palette for both maps — `ManorPalette`

`WorldMapView.cell_province`, `cell_owner`, `manor_color`,
`working_manor_color`, `house_manor_color` and `_province_shaded` move,
unchanged in what they compute, into a pure static class
`scripts/engine/manor_palette.gd` (`ManorPalette`, `RefCounted`, every
function taking `repo: DataRepository, state: GameState, cell_id: int`).
`WorldMapView` keeps thin instance wrappers (its tests and callers keep
working) that call it. A cell's province is `MapManors.province_of` (which
honours `state.manor_province`) — the migration first checks it agrees with
the 2D map's centre-pixel lookup on every land cell of the default pack; if
any cell disagrees the old lookup moves with the palette instead, so the 2D
map's colours do not change.

## The ground tint — Terrain3D's own shader, patched at runtime

Compatibility has no decals, and a draped overlay mesh z-fights on steep
ground and floats unlit; Terrain3D's colormap is ~15 M texels, seconds to
rewrite in GDScript. So the tint goes into the terrain's own shader:

- On `_load`, if the world has a `Terrain3D`, the view sets its material's
  `shader_override_enabled`, reads the default code Terrain3D generates for
  the build's settings, and hands it to the pure
  `Map3DGroundTint.patch(code: String) -> String`
  (`scripts/map3d/map3d_ground_tint.gd`). The patch:
  - adds `uniform highp sampler2D cell_index : filter_nearest, repeat_disable;`,
    `uniform highp sampler2D cell_lut : filter_nearest, repeat_disable;`,
    `uniform float tint_mix = 0.0;`, `uniform vec2 pack_origin;`,
    `uniform float m_per_px = 50.0;`, `uniform ivec2 lut_size;`;
  - rewrites the one line `ALBEDO = mat.albedo_height.rgb * color_map.rgb * macrov;`
    to compute that albedo as before, then: pack px =
    `(v_vertex.xz - pack_origin) / m_per_px`; cell id =
    `texelFetch(cell_index, px, 0)`'s `R + G * 256` (the importer's
    encoding; white is water); colour = `texelFetch(cell_lut,
    ivec2(id % lut_size.x, id / lut_size.x), 0)`; the albedo mixed toward it
    by `tint_mix * colour.a` (out-of-range ids and pixels mix nothing).
  - returns `""` when the ALBEDO line is not found — the view then leaves
    the override off, the ground plain, and pushes one warning.
- Because the colour enters the ALBEDO, the relief, the sun and the cloud
  shadows still light it.
- `cell_lut` is an `ImageTexture` (RGBA8) of `lut_size` = 128 × ceil(max id
  / 128): each land cell's `ManorPalette` colour for the theme (ECONOMY:
  `working_manor_color` for a working manor — `MapEconomy.manors` — else
  `manor_color`; MANORS: `house_manor_color`), water and unheld land clear.
  Rebuilt when the theme flips or the signature the 2D `manor_mesh` uses
  turns (province owners, manor owners, annexed manors).
- `tint_mix` is `balance.csv` `map3d_manor_tint` under a theme, 0 without;
  the value is chosen by the owner from shots at 0.6 / 0.8 / 1.0.
- `cell_index` is `world_cell_index.png` (the pack's `cell_texture`),
  imported lossless; `texelFetch` reads it exactly.

## The cell edges

`ManorEdges`, one more ribbon layer through `_set_lines`
(`border_line.gdshader`, constant screen width), from the same unique cell
edges the 2D `manor_edges()` gathers — moved with the palette as
`ManorPalette.edges(repo) -> PackedVector2Array` so both maps share it —
in world metres, resampled onto the relief. Colour `political_palette`
`manor_line`, opacity `map_manor_line_alpha` and width `map_manor_line_width`
(screen px) — the 2D map's own keys, so the two maps rule the edges alike;
render priority `PRIORITY_MANOR_EDGES`, between the roads and the seams. Built on the first theme and kept (cell
edges are geometry); shown only under a theme.

## Picking and the selected manor

- `pick_at` under a theme: rings first as now, then the ground hit's pack px
  in `world_cell_index.png` → `{"kind": "manor", "cell": id}` for a land
  cell, `{}` for water.
- `select_at` for a manor: `object_selected.emit({"title":
  MapManors.label_of(repo, id), "obj": {"kind": "manor", "cell": id}})` and
  the cell's ring of vertices drawn as the gold `Selection` line.
- `kingdom_of_pick` learns `"manor"`: `MapManors.province_of`'s holder.

## Tests

- `ManorPalette`: the 2D map's existing colour tests pass unchanged against
  the wrappers; new: each function equals the old formula on a crown cell,
  a foreign cell and a water cell; a conquest changes `manor_color`.
- `Map3DGroundTint.patch`: a sample containing the ALBEDO line gains every
  uniform and the rewritten line; a sample without it returns `""`; and the
  REAL code a fresh `Terrain3D` generates (the addon is committed; no built
  scene needed) contains the line.
- The LUT: a land cell's texel equals its `ManorPalette` colour for each
  theme; water is clear; a conquest changes it after the next refresh.
- The rule: ECONOMY / MANORS keep 3D; HEIGHTS / MILITARY still go 2D;
  `set_theme` reaches the screen's 3D view.
- On the flat fixture world (no Terrain3D — the patch is simply skipped):
  under a theme a click on open land emits the manor's `object_selected`
  and draws the Selection; hover names the manor; the edges layer is
  present under a theme and hidden without.
- Real-window shots: ECONOMY and MANORS at 24 km, and the tint at 0.6 / 0.8
  / 1.0 for the owner to pick.

## Documentation

CLAUDE.md: the 3D default paragraph (the 2D-only layers are HEIGHTS and
MILITARY), the MANORS / ECONOMY paragraphs (they draw on both maps; badges
and estates are 2D only for now), and a line on `Map3DGroundTint`.
