# 3D map pipeline (Terrain3D)

The 3D campaign map is built from the same Azgaar pack as the 2D map
(`data/maps/<id>/`, `assets/maps/<id>/`) at **50 m per pack px** — `beria` is a
128 × 46 km world, a Terrain3D vertex every 20 m, regions of 2048. The game
shows it as the default map (`scripts/map3d/map3d_view.gd`) in the map
panel, in place of the 2D `WorldMapView` except while a 2D-only layer is on;
a checkout that has not built it shows the 2D map.

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
| `assets/map3d/<map>/bake/` | `height.r32`, `control.r32`, `color.rgba8`, `world.json`, `manor_land.csv`, `fields.png`, previews | no — `export_manor_land.gd`, `bake_world.py` |
| `assets/map3d/<map>/world.tscn`, `terrain_assets.tres`, `terrain/`, `rivers.json` | the Terrain3D scene (root metadata `map3d_world`: scale, origin, canvas, sea level, format version), its assets, region data and river courses — DATA only: sun, sky and sea are `scenes/map3d/world_map_3d.tscn`'s | no — `bake_world.py`, `build_world.gd` |
| `assets/map3d/<map>/manifest.json` | what built it (below) | no — `build_world.gd` |

`assets/map3d/<map>/` is the default; a pack can keep its build elsewhere
(`map3d_dir`, below).

Runtime game code is `scripts/map3d/` — `Map3DGeometry` (pure: pack px ↔
metres, the camera rig's pose, zoom, tilt, pan, ray to ground),
`Map3DBorders` (pure: live outlines and seams as draped ribbons,
`border_line.gdshader` keeping them a constant screen width) and `Map3DView` (the tab's
view: lazy load, SubViewport rendering only while shown, settlements placed
from live data by `data/map3d_settlements.csv`) — with tests in
`tests/map3d/` that use a fixture scene, never the git-ignored build. Camera
values are `balance.csv` `map3d_*`.

## Rebuilding from a clean checkout

**One pack, one command:** `tools/map3d/build_pack.sh [--map ID]` (default:
`data/maps.csv`'s `is_default` pack) runs steps 3–5 below in order —
`export_manor_land.gd`, `bake_world.py`, `build_world.gd` — then
`bake_layers.gd` (see Baked layers), with `GDAI_MCP_SERVER_PORT=3999` set,
stops at the first failure, and ends with `manifest.json` and `layers/`
written. Steps 1–2 (sources and the packed textures) are
shared by every pack and built once. The steps one by one:

1. **Sources** — download the Poly Haven sets named in `pack_textures.py`
   into `assets/map3d/sources/polyhaven/` and Rock023 into
   `assets/map3d/sources/ambientcg/`. The snow line's `snow_02`, the roads'
   `rocky_trail_02` and the bridges' `medieval_blocks_03` (2026-09-19; the
   first snow, `snow_field_aerial`, read blue-grey and blotchy) are 4K JPEGs
   from the Poly Haven API (`https://api.polyhaven.com/files/<id>`: Diffuse,
   Displacement, nor_gl, Rough), written to
   `<id>_4k.blend/textures/<id>_{diff,disp,nor_gl,rough}_4k.jpg` — the same
   layout the Blender MCP's Poly Haven download leaves; `pack_textures.py`
   takes a set's maps as EXR/PNG or JPEG, and `-- <key>` packs one set. The
   road and bridge sets are not terrain layers: `Map3DView` loads their
   packed pairs itself and draws flat colours without them. A new layer's
   `.import` must copy the others' `[params]` (VRAM `compress/mode=2`): the
   texture array wants one format. Tree models (only if planting trees):
   `python3 tools/map3d/fetch_polyhaven.py fir_tree_01 ...`
2. **Textures** — `Blender -b --factory-startup --python tools/map3d/pack_textures.py`
   (numpy in Blender; GDScript per pixel on 4K took >10 min).
3. **Manor land** — `GDAI_MCP_SERVER_PORT=3999 Godot --headless --path . -s tools/map3d/export_manor_land.gd [-- --map ID]`
   writes `bake/manor_land.csv` (each manor's starting chief good, decided
   by the game's own `MapManors.default_focus`) for the bake's fields.
   Without it every manor is sown as `*` (kitchen gardens only).
4. **Bake** — `python3 tools/map3d/bake_world.py [--map ID]` (~12 s), tuned by
   `data/map3d_bake.csv` (coast supersample and edge warp, the beach mix,
   river widths and carving — the numbers moved out of the script; the rest
   is still in `bake_world.py` itself, see Open items). Height comes from
   `cells.csv` plus its own ridges, NOT from `world_relief.png` (read only
   for the open sea), whose 2D-tuned detail is a 660 m bump every 800 m at
   this scale. The same pass carves rivers into that heightmap and writes
   each course, source to mouth, to `rivers.json` beside the built scene,
   for `Map3DRivers` to draw at runtime. The bake's pure functions have
   their own test: `python3 tools/map3d/test_bake_world.py`.
   **The patchwork** (owner 2026-09-19, "make the ground read like a
   satellite map"; `sow_patchwork`): village footprints (built ground by
   the square root of the people, thinning outward), strip FIELDS round
   every settlement within their chief good's reach (`data/map3d_fields.csv`:
   crops by share, a bake texture and a darkening tint each), laid per
   manor in its own orientation, staggered like brickwork, noise-warped,
   sown densest near the village and thinning outward, soft hedges; and
   every manor cell its own slight shade. Its noise has its own random
   stream, so the rest of the look is untouched; `map3d_bake.csv`
   `field_*`, `hedge_*`, `footprint_*`, `manor_jitter_*`. It also writes `bake/fields.png` (RGB each field's own colour multiplier, A its strip direction, `FIELD_MAP_STEP` vertices a texel), read at runtime — not imported — for the terrain shader's furrows and far fade (`Map3DGroundTint`, balance `map3d_furrow_*` / `map3d_field_fade*`).
5. **Scene** — `GDAI_MCP_SERVER_PORT=3999 Godot --headless --path . -s tools/map3d/build_world.gd [-- --map ID]`
   (~2 s, no editor; every tool defaults to `data/maps.csv`'s `is_default` pack). Nothing visual is baked into the scene beyond the
   terrain: headless, a MultiMesh saves without its transforms, which is one
   reason settlements are placed at runtime.
6. **Look / measure** — `Godot --path . -s tools/map3d/shoot.gd -- --camera CameraMid --out /tmp/x.png`;
   the acceptance bench drives the real view —
   `GDAI_MCP_SERVER_PORT=3999 Godot --path . res://tools/map3d/bench.tscn -- --size WxH` —
   median/mean/p95 frame time per zoom against an 8 ms budget (60 fps; exits
   3 over it).
7. Trees (optional, owner: no trees) — `render_impostors.py` in Blender, then
   `plant_trees.gd`.

## The manifest

`build_world.gd` writes `manifest.json` beside `world.tscn` once the scene
has saved: `format_version` (`Map3DWorldLoader.FORMAT_VERSION`, 2 = data
only), `meta` (the root's `map3d_world`), `built_at` (UTC) and `steps_hash`
(`Map3DWorldLoader.steps_hash()`, the md5 of `data/map3d_bake.csv` +
`data/map3d_fields.csv`). `Map3DWorldLoader.status(scene_path)` reads it
before the view loads anything, and the view's notice says honestly why
there is no 3D map and what to run:

| state | when | the view |
|---|---|---|
| `ok` | the manifest's version is the game's and its meta matches the scene's root | loads (a changed `steps_hash` only warns once: rebuild to see the new tables) |
| `legacy` | no `manifest.json` (a build before 2026-09-20; every test fixture) | loads, warns once |
| `missing` | no `world.tscn` | "has not been built" + `build_pack.sh --map ID` |
| `stale` | another `format_version`, or a manifest meta that is not the scene's | "built by an older pipeline" + rebuild |
| `bad` | a manifest that is not a JSON object, a scene root without `map3d_world`, or a scene that will not instance | "damaged" + rebuild |

The optional inputs — `rivers.json`, `bake/fields.png`, the packed road and
bridge textures, the pack's `sea_texture` — each warn ONCE when missing
(`Map3DWorldLoader.warn_once`) and the map draws without them.

## Baked layers

Rivers, roads, trails and bridges never move, so the build bakes their
meshes (spec 2026-09-20 §2): `GDAI_MCP_SERVER_PORT=3999 Godot --headless
--path . -s tools/map3d/bake_layers.gd [-- --map ID]`, run by `build_pack.sh`
after `build_world.gd`, opens the built world and saves one `ArrayMesh` per
layer into `<map3d_dir>/layers/<layer>_<step set>.res` — one set per
distinct step set of `data/graphics_quality.csv` (`road_step_mul` and
`river_step_mul`, e.g. `r100_v100` for high/ultra, `r140_v150` medium,
`r200_v250` low) — and `layers/manifest.json`, the key each set was baked
under (`Map3DLayerBake`). The key covers `Map3DLayerBake.KEYS` (the balance
numbers the geometry depends on: the road and river steps, the river split,
clearance and end fade, the road and trail widths, the route smoothing and
every `map3d_bridge_*` but `max_view_m`, which is only the material's fade),
the md5 of `rivers.json` and of the pack's `geography/routes.csv`, the world
manifest's `built_at` and the step set. The view uses a set only when it is
COMPLETE (all four files) and its key matches today's inputs; otherwise it
builds the layers at load as before, so a stale bake is never drawn — only
slower to open. Materials are never baked: colours, widths in px and the
shaders' numbers are read at load. After changing any of those inputs, run
`bake_layers.gd` again (or the whole `build_pack.sh`). The key cannot see
the geometry CODE (an exported build need not ship the scripts), so a change
to any script in `Map3DLayerBake.GEOMETRY_SOURCES` fails
`test_map3d_layer_bake.gd` until you bump `Map3DLayerBake.FORMAT`, update
`GEOMETRY_MD5` and re-run `bake_layers.gd`. A view that finds a stale
`layers/` warns once and builds at load.

## `map3d_dir`

`data/maps.csv`'s `map3d_dir` column says where a pack's 3D build lives (a
`res://` path; empty means `res://assets/map3d/<id>`). The game reads it
through `DataRepository.map3d_dir(id)` (`Map3DView.scene_path_for`), the
GDScript tools through the static `DataRepository.map3d_dir_of(id)`
(`build_terrain.gd` `root()`, `export_manor_land.gd`, `shoot.gd`) and the
Python tools through `tools/packs.py` `map3d_dir(id)` (`bake_world.py`'s
`bake/`). The shared `assets/map3d/textures/`, `sources/` and `trees/` do not
move with it.

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
- A shader that references `ALPHA_SCISSOR_THRESHOLD` anywhere — even in a
  branch that never runs — pushes the WHOLE material into an alpha-scissor
  pipeline under Compatibility and silently blanks its blended rendering, no
  error emitted: keep a shadow-only variant in its own file rather than one
  shader gated by a uniform (cloud_deck.gdshader / cloud_shadow.gdshader).
- A `Color` shader uniform set from GDScript passes STRAIGHT THROUGH under
  GL Compatibility (measured: 0.5 renders as 128/255 under a Linear
  tonemap, with or without `source_color`) — hand a `terrain_palette` hex
  in raw, never `srgb_to_linear()`'d. What moves an unshaded or EMISSION
  colour is the environment's Filmic tonemap, which LIFTS it (0.5 -> 162),
  more in the darker channels: fit the emission to the tonemap
  (`map3d_sea_emission_gamma` / `map3d_river_emission_gamma` > 1, sampled
  against the palette) and refit if the tonemap changes.
- Terrain3D's `mipmap_bias` material param is a DERIVATIVE MULTIPLIER, not a
  mip-level offset like a texture import's own bias field — 1.0 is neutral,
  under 1.0 sharpens (`build_terrain.gd` uses 0.85).

## Performance tiers

`data/graphics_quality.csv` holds four rows — `low`, `medium`, `high`,
`ultra` — each a render scale, shadow/cloud/mesh settings and the step
multipliers for lines, roads and rivers (`Map3DQuality`). A first run
detects a tier from the GPU's name (integrated Intel/AMD, llvmpipe → low;
base Apple M-series, GTX ≤ 10xx, MX → medium; else high); the pause menu's
Graphics button cycles auto → low → medium → high → ultra → auto and saves
the choice to `user://settings.cfg`.

The bench (`tools/map3d/bench.gd`) gates each tier against its own row:

```
GDAI_MCP_SERVER_PORT=3999 Godot --path . res://tools/map3d/bench.tscn -- \
    --size 3024x1964 --quality high --out tools/map3d/baselines/bench_runs.csv
```

`--quality low|medium|high|ultra` forces the tier before the view loads
(`Map3DQuality.forced`); `--render-scale X` overrides just the render scale
on top of it; `--out FILE` appends every row (size, tier, label, median/
mean/p95 ms, draw calls, primitives) to a CSV; `--layer manors|heights|
military` lights that bottom-bar tab first, so a theme's ground and HUD are
priced too. The budget is the tier row's `bench_budget_ms`; a WARNING prints
if `--size` does not match the row's own `bench_size` (the gate is only
meaningful at the size it names). Exit 0 at or under budget, 3 over it.
**`--out` must land under `tools/map3d/baselines/` (which carries its own
`.gdignore`) or a scratch path — a bare CSV anywhere else under `res://`
gets auto-imported as a Translation resource and litters the folder with
`.import` / `.translation` sidecars, same trap as `data/`'s (see CLAUDE.md).**

Gates, run 2026-09-20 on the dev machine (Apple Silicon, GL Compatibility;
`tools/map3d/baselines/bench_runs.csv` has the full per-layer breakdown):

| tier | size | budget | WORST (all on) | WORST (`--layer manors`) | WORST (`--layer heights`) |
|---|---|---|---|---|---|
| high | 3024×1964 | 8.00 ms | 6.87 ms | 7.01 ms | 6.95 ms |
| medium | 1920×1080 | 6.00 ms | 2.46 ms | 2.57 ms | 2.49 ms |
| low | 1920×1080 | 4.00 ms | 1.47 ms | 1.49 ms | 1.47 ms |

All nine gates passed with wide headroom on this machine (an Apple Silicon
GPU, well above every tier's target hardware), so no tier's CSV row needed
tuning. As the spec notes (§4): this is the M5 Pro to Iris Xe / low-end APU
gap — **one real run on an integrated-GPU machine is recommended before
shipping**, since a GPU actually AT a tier's floor may not clear its budget
by the same margin.

## Open items before the 3D map ships

- `build_terrain.gd`'s look constants (textures, material, sky, sea) still
  live in the script, not a CSV; `data/map3d_bake.csv` moved the bake's
  shore, coast-edge, beach and river numbers out of `bake_world.py`, but the
  remaining bake constants (ridges, biome mix, far colours) are still in
  `bake_world.py`.
- Settlements are placeholder rings; no hover tooltip, no kingdom labels, no
  army counters yet.
- Compare Compatibility vs Forward+ on the target PC (without trees
  Compatibility measured 5.0 vs 8.4 ms at 1440p).
