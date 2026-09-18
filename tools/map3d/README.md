# 3D map pipeline (Terrain3D)

The 3D campaign map is built from the same Azgaar pack as the 2D map
(`data/maps/<id>/`, `assets/maps/<id>/`) at **50 m per pack px** — `beria` is a
128 × 46 km world, a Terrain3D vertex every 20 m, regions of 2048. The game
shows it on the **3D MAP** bottom-bar tab (`scripts/map3d/map3d_view.gd`),
which swaps it into the map panel in place of the 2D `WorldMapView`; a
checkout that has not built it shows a notice pointing here.

Plugin: `addons/terrain_3d/` (Terrain3D 1.0.2, committed). Renderer: GL
Compatibility (see the traps below).

## Where things live

| Path | What | In git |
|---|---|---|
| `tools/map3d/` | the pipeline scripts (this folder) | yes |
| `assets/map3d/sources/polyhaven/` | Poly Haven 4K `.blend` texture sets and `models/` (CC0) | no — local download, `.gdignore` |
| `assets/map3d/sources/ambientcg/` | ambientCG Rock023 cliff (CC0), `asset_licenses.txt` | no — local download |
| `assets/map3d/textures/` | packed Terrain3D texture pairs (`*_alb_ht`, `*_nrm_rgh`, 2048 px) | no — `pack_textures.py` |
| `assets/map3d/trees/` | tree impostor cards + `trees.json` | no — `render_impostors.py` |
| `assets/map3d/<map>/bake/` | `height.r32`, `control.r32`, `color.rgba8`, `world.json`, previews | no — `bake_world.py` |
| `assets/map3d/<map>/world.tscn`, `terrain_assets.tres`, `terrain/` | the Terrain3D scene (root metadata `map3d_world`: scale, origin, canvas, sea level), its assets and region data | no — `build_world.gd` |

Runtime game code is `scripts/map3d/` — `Map3DGeometry` (pure: pack px ↔
metres, the camera rig's pose, zoom, tilt, pan) and `Map3DView` (the tab's
view: lazy load, SubViewport rendering only while shown, settlements placed
from live data by `data/map3d_settlements.csv`) — with tests in
`tests/map3d/` that use a fixture scene, never the git-ignored build. Camera
values are `balance.csv` `map3d_*`.

## Rebuilding from a clean checkout

1. **Sources** — download the Poly Haven sets named in `pack_textures.py`
   into `assets/map3d/sources/polyhaven/` and Rock023 into
   `assets/map3d/sources/ambientcg/`. Tree models (only if planting trees):
   `python3 tools/map3d/fetch_polyhaven.py fir_tree_01 ...`
2. **Textures** — `Blender -b --factory-startup --python tools/map3d/pack_textures.py`
   (numpy in Blender; GDScript per pixel on 4K took >10 min).
3. **Bake** — `python3 tools/map3d/bake_world.py` (~2 s). Height comes from
   `cells.csv` plus its own ridges, NOT from `world_relief.png`, whose 2D-tuned
   detail is a 660 m bump every 800 m at this scale.
4. **Scene** — `GDAI_MCP_SERVER_PORT=3999 Godot --headless --path . -s tools/map3d/build_world.gd`
   (~2 s, no editor). Nothing visual is baked into the scene beyond the
   terrain: headless, a MultiMesh saves without its transforms, which is one
   reason settlements are placed at runtime.
5. **Look / measure** — `Godot --path . -s tools/map3d/shoot.gd -- --camera CameraMid --out /tmp/x.png`;
   `tools/map3d/bench.gd` for frame times.
6. Trees (optional, owner: none yet) — `render_impostors.py` in Blender, then
   `plant_trees.gd`.

## Known traps (macOS, GL Compatibility)

- `Terrain3DData` only initialises inside the tree ("Data not initialized").
- `import_images` slices from a region corner — pad to whole regions.
- `world_background` FLAT/NOISE repeats the map to the horizon — use NONE.
- A fresh `Terrain3DMaterial` saves null shader params (flat grey at runtime);
  `build_terrain.gd` sets every one explicitly.
- BPTC ("high_quality") textures are unsupported → grey terrain; keep
  `high_quality=false` in the textures' `.import`.
- `reload_scene_from_path` on the open terrain scene crashed Apple's GL
  shader compiler.
- A second Godot process steals the editor's gdai port 3571: launch tools with
  `GDAI_MCP_SERVER_PORT=3999`.
- The editor camera needs `editors/3d/default_z_far` ≈ 400000 at this scale.
- gdai `execute_editor_script` times out after 5 s while the script runs on:
  write a marker file at the end and poll for it.

## Open items before the 3D map ships

- `build_terrain.gd`'s look constants (textures, material, sky, sea) still
  live in the script, not in CSVs.
- Settlements are placeholder discs; trees are off; the view is look-only —
  no hover, click, card, borders or labels yet.
- Compare Compatibility vs Forward+ on the target PC (without trees
  Compatibility measured 5.0 vs 8.4 ms at 1440p).
