# 3D map pipeline (Terrain3D)

The 3D campaign map is built from the same Azgaar pack as the 2D map
(`data/maps/<id>/`, `assets/maps/<id>/`) at **50 m per pack px** — `beria` is a
128 × 46 km world, a Terrain3D vertex every 20 m, regions of 2048. It started
as the spike of 2026-09-17/18 and is not yet read by the game: the 2D
`WorldMapView` stays the playable map until the 3D one replaces it.

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
| `assets/map3d/<map>/world.tscn`, `terrain_assets.tres`, `terrain/` | the Terrain3D scene, its assets and region data | no — `build_terrain.gd` |

Runtime game code for the 3D map belongs in `scripts/map3d/`, its scenes in
`scenes/map3d/`, its tests in `tests/map3d/` — engine-pure where it can be,
like the rest of the project (CLAUDE.md invariants).

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
4. **Scene** — in the editor (gdai `execute_editor_script`): `build_scene()`,
   open `assets/map3d/<map>/world.tscn`, `import_into(<its Terrain3D>, <root>)`,
   save. Load the script source into a fresh GDScript — the editor caches it.
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

- `build_terrain.gd` hardcodes `PLAYER_REALM` and its constants; move them to
  `realm_bindings.csv` / `balance.csv` (CLAUDE.md invariant 5, "values in CSVs").
- Settlements are placeholder discs; trees are off.
- Compare Compatibility vs Forward+ on the target PC (without trees
  Compatibility measured 5.0 vs 8.4 ms at 1440p).
