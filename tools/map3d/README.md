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
| `assets/3D/terrain/model_wip/polyhaven/` | Poly Haven 4K `.blend` texture sets and `models/` (CC0) | no — local download, `.gdignore` |
| `assets/3D/terrain/model_wip/ambientcg/` | ambientCG Rock023 cliff (CC0), `asset_licenses.txt` | no — local download |
| `assets/3D/terrain/textures/` | packed Terrain3D texture pairs (`*_alb_ht`, `*_nrm_rgh`, 2048 px) | **yes** (owner 2026-10-02: a pull runs the game) — `pack_textures.py` |
| `assets/3D/terrain/trees/` | tree impostor cards + `trees.json` | no — `render_impostors.py` |
| `assets/3D/buildings/` | the settlement house meshes (`<type>/<type>.glb`, each type's references in its `model_wip/`) + `houses.json` | **yes** — `make_houses.py`; committed like the terrain build itself, so a fresh clone sees settlements |
| `assets/3D/terrain/<map>/bake/` | `height.r32`, `control.r32`, `color.rgba8` (the build's raw inputs), `height_war.r16` (the WAR ROOM's half-float heights), `world.json`, `manor_land.csv`, `fields.png`, `woods.png`, `trees.bin`, `houses.csv`, previews | **yes** but the three raw inputs (git-ignored: `build_world.gd` reads them once) — `export_manor_land.gd`, `bake_world.py` |
| `scenes/map3d/worlds/<map>.tscn` (owner 2026-10-04: every scene is under `scenes/`, `assets/` holds none) + `assets/3D/terrain/<map>/terrain_assets.tres`, `terrain/`, `rivers.json` | the Terrain3D scene (root metadata `map3d_world`: scale, origin, canvas, sea level, format version), its assets, region data and river courses — DATA only: sun, sky and sea are `scenes/map3d/world_map_3d.tscn`'s | **yes** — `bake_world.py`, `build_world.gd` |
| `assets/3D/terrain/<map>/manifest.json` | what built it (below) | **yes** — `build_world.gd` |

`assets/3D/terrain/<map>/` is the default for the build's DATA; a pack can keep it
elsewhere (`map3d_dir`, below). The world SCENE is always
`scenes/map3d/worlds/<map>.tscn` (`DataRepository.map3d_scene_of`), and
`Map3DWorldLoader.data_dir(scene)` is the one place that finds its data from it
(a world anywhere else, a test fixture, keeps its data beside it).

Runtime game code is `scripts/map3d/` — `Map3DGeometry` (pure: pack px ↔
metres, the camera rig's pose, zoom, tilt, pan, ray to ground),
`Map3DBorders` (pure: live outlines and seams as draped ribbons,
`border_line.gdshader` keeping them a constant screen width) and `Map3DView`,
the map panel's view (there is no 3D tab: the 3D map is the default map). It
is a COORDINATOR over `Map3DContext` — what every piece shares — with one
script per layer under `scenes/map3d/world_map_3d.tscn` and a rig, input,
picker, selection and HUD piece beside them: lazy load, the SubViewport
rendering only while shown, settlements placed from live data by
`data/map3d_settlements.csv`. Tests are in `tests/map3d/` and use a fixture
scene, never the built pack (which a test may not assume is current). Camera values are `balance.csv`
`map3d_*`; the look assets are `scenes/map3d/materials/*.tres`.

## Rebuilding from a clean checkout

**One pack, one command:** `tools/map3d/build_pack.sh [--map ID]` (default:
`data/maps.csv`'s `is_default` pack) runs steps 3–5 below in order —
`export_manor_land.gd`, `bake_world.py`, `build_world.gd` — then
`bake_layers.gd` (see Baked layers), with `GDAI_MCP_SERVER_PORT=3999` set,
stops at the first failure, and ends with `manifest.json` and `layers/`
written. Steps 1–2 (sources and the packed textures) are
shared by every pack and built once. The steps one by one:

1. **Sources** — download the Poly Haven sets named in `pack_textures.py`
   into `assets/3D/terrain/model_wip/polyhaven/` and Rock023 into
   `assets/3D/terrain/model_wip/ambientcg/`. The snow line's `snow_02`, the roads'
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
   `cells.csv` plus its own ridges and, since 2026-09-24, TERRACES
   (`bake_world.terrace`, `map3d_bake.csv` `terrace_*`: the high ground over
   260 m folded into plateaus and escarpments, look only — the engine's
   heights stay the cells'), NOT from `world_relief.png` (read only
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
   `field_*`, `hedge_*`, `footprint_*`, `manor_jitter_*`. It also writes `bake/fields.png` (RGB each field's own colour multiplier, A its strip direction, `FIELD_MAP_STEP` vertices a texel), read at runtime — not imported — for the terrain shader's furrows and far fade (`Map3DGroundTint`, `scenes/map3d/ground_look.tres` `furrow_*` / `field_fade*`). **The same pass now also places every settlement's houses** (spec 2026-09-20 §1; `tools/map3d/bake_houses.py`, called from `sow_patchwork` right where the land mask, each burg's population and footprint radius already live, so "never in the sea" is structural) and writes `bake/houses.csv` (world metres, no `y`, plus `rank`, `height_scale`, `stretch` and the `wall` / `roof` tint indices of the settlement's palettes; tuned by `map3d_bake.csv`'s `house_*` keys and `data/map3d_houses.csv`'s type table) — see "House meshes" below for the models those rows place.
5. **Scene** — `GDAI_MCP_SERVER_PORT=3999 Godot --headless --path . -s tools/map3d/build_world.gd [-- --map ID]`
   (~2 s, no editor; every tool defaults to `data/maps.csv`'s `is_default` pack). Nothing visual is baked into the scene beyond the
   terrain: headless, a MultiMesh saves without its transforms, which is one
   reason settlements are placed at runtime.
   `-- --material-only` re-applies `build_terrain.gd`'s material (`apply_material`:
   dual scaling FIRST, then `SHADER_PARAMS`) and texture tiles (`apply_tiles`) to
   the committed `scenes/map3d/worlds/<map>.tscn` / `terrain_assets.tres` without the raw inputs (2026-10-04;
   a save from script mode drops the `.tres`'s `uid=` lines — restore them from git).
6. **Look / measure** — `Godot --path . -s tools/map3d/shoot.gd -- --camera CameraMid --out /tmp/x.png`;
   the acceptance bench drives the real view —
   `GDAI_MCP_SERVER_PORT=3999 Godot --path . res://scenes/tools/map3d/bench.tscn -- --size WxH` —
   median/mean/p95 frame time per zoom against an 8 ms budget (60 fps; exits
   3 over it).
7. Trees (optional, owner: no trees) — `render_impostors.py` in Blender, then
   `plant_trees.gd`.

## House meshes

Settlements stand as clusters of real house meshes (spec 2026-09-20), not the
former black dots. The models are a separate, replaceable layer from where
the bake places them (above): a headless Blender script, in the shape of
`render_impostors.py` —

```
blender -b --factory-startup --python tools/map3d/make_houses.py
```

— reads `data/map3d_houses.csv` (the type table: mesh, role, weight,
footprint, height, roof key, min settlement group) and each type's roof/wall
colours from `data/terrain_palette.csv` (converted sRGB → linear before
Blender's Principled BSDF, which treats Base Color as linear — the values
render lifted to a near-white otherwise), and writes one low-poly `.glb` per
type plus `houses.json` (each type's footprint and height in metres — echoed
from the CSV, not independently measured off the generated mesh; see Open
items below for why that matters — and its triangle count) into
`assets/3D/buildings/`. **These files are
committed** — see "Where things live" above — so a fresh clone shows
settlements with no Blender install. It is NOT part of `build_pack.sh`
(Blender is a separate dependency from the pipeline's headless Godot chain)
and needs re-running only when `data/map3d_houses.csv` or the roof/wall
colours in `data/terrain_palette.csv` change (~1 minute for all 14 types).

### The shipped meshes are HAND-MODELLED in Blender (2026-09-24)

All 14 types are built by `tools/map3d/blender_houses/` (`kit.py` +
`buildings.py`, run through the Blender MCP; Poly Haven CC0 textures by
`textures.py`) — see its README. Every `<type>.glb.import` sets
`meshes/force_disable_compression=true` (multi-surface meshes; see that
README). `scale_houses.py` scales a built mesh's vertices to the table's
`footprint_m` and writes the measured `width_m` / `depth_m` / `height_m` /
`tris` back into `data/map3d_houses.csv` and `houses.json`;
`census_house_meshes.py` reports holes and flipped faces (read-only).

**No AI 3D for the houses** (owner 2026-09-24): Hunyuan3D was removed over its licence
(it excludes the EU, the UK and South Korea) — the local model, its ComfyUI
nodes and workflows, the reference meshes and every tool of that pipeline
(`retopo_houses.py`, `decimate_houses.py`, `dilate_house_atlas.py`,
`align_house_source.py`, `project_house_texture.py`, `restart_comfy.sh`) are
gone. ComfyUI's job ends at the IMAGE: `gen_house_refs.py` renders the
photoreal reference pictures (`assets/imagegen/house_ref_prompts.csv`, on
`generate.py`'s presets, into `assets/3D/buildings/<type>/model_wip/<type>_ref.png`; `cottage_a`'s is the
owner's own and is never overwritten without `--force`) that the houses are
modelled against. A building is SIMPLE REALISM, never toy; roofs are tile or
slate, never thatch.

**After replacing any `.glb`, run `Godot --headless --path . --import`**, or
the game keeps loading the previous `.scn` and you will shoot the old mesh.
Godot's glTF importer EXTRACTS each embedded texture to a loose file beside
the `.glb` (`gltf/embedded_image_handling=1`, each imported as Basis Universal,
`compress/mode=4`) and they are COMMITTED: each house type is a scene,
`scenes/models/buildings/<type>.tscn`, inheriting its `.glb`, whose surfaces wear
`house_surface.gdshader` materials referencing those files (owner 2026-10-04;
`house_models.tres` names the scenes). A new house type therefore needs its
scene made in the editor (New Inherited Scene from the `.glb`, a
`house_surface` material per surface with its texture, roughness and `role`
— 1 wall, 2 tile roof, 0 untinted) and entered in `house_models.tres`;
`test_map3d_house_scenes.gd` fails until it is. A re-exported `.glb` keeps its
scene's materials as long as its surfaces keep their order.

## The manifest

`build_world.gd` writes `manifest.json` into the data dir once the scene
has saved: `format_version` (`Map3DWorldLoader.FORMAT_VERSION`, 2 = data
only), `meta` (the root's `map3d_world`), `built_at` (UTC) and `steps_hash`
(`Map3DWorldLoader.steps_hash()`, the md5 of `data/map3d_bake.csv` +
`data/map3d_fields.csv` + `data/map3d_houses.csv`, joined 2026-09-20 so a
changed house type table reports the build stale too).
`Map3DWorldLoader.status(scene_path)` reads it
before the view loads anything, and the view's notice says honestly why
there is no 3D map and what to run:

| state | when | the view |
|---|---|---|
| `ok` | the manifest's version is the game's and its meta matches the scene's root | loads (a changed `steps_hash` only warns once: rebuild to see the new tables) |
| `legacy` | no `manifest.json` (a build before 2026-09-20; every test fixture) | loads, warns once |
| `missing` | no `scenes/map3d/worlds/<map>.tscn` | "has not been built" + `build_pack.sh --map ID` |
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

`data/maps.csv`'s `map3d_dir` column says where a pack's 3D build DATA lives (a
`res://` path; empty means `res://assets/3D/terrain/<id>`). The game reads it
through `DataRepository.map3d_dir(id)` (`Map3DView.scene_path_for`), the
GDScript tools through the static `DataRepository.map3d_dir_of(id)`
(`build_terrain.gd` `root()`, `export_manor_land.gd`, `shoot.gd`) and the
Python tools through `tools/packs.py` `map3d_dir(id)` (`bake_world.py`'s
`bake/`). The shared `assets/3D/terrain/textures/`, `model_wip/` and `trees/` do not
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
GDAI_MCP_SERVER_PORT=3999 Godot --path . res://scenes/tools/map3d/bench.tscn -- \
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

**Still or panning** (`--pan`, final review 2026-09-20). Without `--pan` the
camera stands STILL for the whole row, so everything the view cuts once per
camera pose — the output badges, the army counters, the kingdom names, the
landmark marks, the hover pick and the HUD's own redraw — is computed on the
row's first frame and never again: a still number prices the GPU and the
clock, not the per-move CPU. `--pan` pans the ground a little EVERY measured
frame (through the rig's own `pan_by`, the drag's path) and asks for a hover
pick at a wandering pointer, so all of it is paid per frame as it is while the
player drags the map; the pan oscillates, so the framing stays where the row
put it. A run is one or the other, and its rows are labelled `[pan]` (and
`[manors]` / `[heights]` / `[military]` for a `--layer` run) so one `--out`
CSV can hold them all.
**`--out` must land under `tools/map3d/baselines/` (which carries its own
`.gdignore`) or a scratch path — a bare CSV anywhere else under `res://`
gets auto-imported as a Translation resource and litters the folder with
`.import` / `.translation` sidecars, same trap as `data/`'s (see CLAUDE.md).**

Gates, run 2026-09-20 on the dev machine (Apple Silicon, GL Compatibility;
`tools/map3d/baselines/bench_runs.csv` has the full per-layer breakdown).
**STILL camera** — the GPU and the clock, none of the per-move CPU:

| tier | size | budget | WORST (all on) | WORST (`--layer manors`) | WORST (`--layer heights`) |
|---|---|---|---|---|---|
| high | 3024×1964 | 8.00 ms | 6.87 ms | 7.01 ms | 6.95 ms |
| medium | 1920×1080 | 6.00 ms | 2.46 ms | 2.57 ms | 2.49 ms |
| low | 1920×1080 | 4.00 ms | 1.47 ms | 1.49 ms | 1.47 ms |

**PANNING** (`--pan`, added in the final review of 2026-09-20 — the same
machine, later the same day, with the Godot editor open; `high` re-measured
still at 7.34 ms in that session, so read the pan column against 7.34, not
against 6.87):

| tier | size | budget | WORST (all on, `--pan`) | WORST (`--layer manors --pan`) |
|---|---|---|---|---|
| high | 3024×1964 | 8.00 ms | **9.05 ms — OVER** | **12.30 ms — OVER** |
| medium | 1920×1080 | 6.00 ms | 3.42 ms | not measured |
| low | 1920×1080 | 4.00 ms | 2.50 ms | not measured |

**Forward+ (2026-09-24, the look route's Phase 0/1 — supersedes the two
tables above for today's renderer).** The map left GL Compatibility for
Forward+ (owner), tilted its camera (more ground in view), and gained SSAO
(now faded over the whole view: Godot's default 50–300 m fade had switched
it off on every map view), depth haze and AgX. Two things change how to read
the bench: Godot's Metal backend gives no GPU timestamps, and **macOS holds a
windowed Metal app at the display's refresh whatever the vsync mode**, so on
this Mac no row reads under ~8.33 ms (120 Hz) — a row at that floor means
"holds the refresh", not a cost. Budgets moved with it (graphics_quality.csv
notes): low / medium 8.5 ms (hold the floor), high 12, ultra 12.5 ms.

| tier | size | budget | still near / mid / far | pan near / mid / far |
|---|---|---|---|---|
| ultra | 3024×1964 | 12.5 ms | 11.51 / 11.05 / 10.32 | 11.46 / 11.01 / 10.54 |
| high | 3024×1964 | 12 ms | 11.12 / 9.87 / 9.46 | 11.14 / 10.32 / 9.82 |
| medium | 1920×1080 | 8.5 ms | at the floor | at the floor |
| low | 1920×1080 | 8.5 ms | at the floor | at the floor |

Priced at `high`, near (`--tier` overrides one tier column): SSAO ~1.9 ms,
MSAA 4x ~1.2 ms, houses ~2.5 ms, sun shadows ~2 ms; `ssao_quality` barely
matters and `render_scale` 0.85 takes 11.1 → 9.5 ms (the frame is fill-bound
at Retina size). Found on the way: a drag cost ~48 ms a frame at mid/far under
EITHER renderer since the houses' 5×5 ground sampling of 2026-09-24 — every
visible house re-sampled on each rebuild; the seat is now kept per house.

**(Compatibility, 2026-09-20:) The `high` tier does not clear its 8 ms budget while the map is being
dragged.** It is reported, not tuned away (the owner decides whether the
budget, the tier's contents or the per-move work moves): a drag costs ~1.7 ms
a frame on top of the still figure with no theme up, and ~5 ms with MANORS up
— the manor edges and the ground tint push the draw calls from 433 to 699,
and the HUD's own per-move share is ~1.6 ms of it. 110 fps and 81 fps are
still comfortably playable; what the numbers say is that the 60 fps gate has
no headroom left at `high` on a machine well above the tier's floor, which the
still figures had hidden. Memoising the badges and the counters per camera
pose (the same final review) already took 0.5–1.0 ms a frame off the MANORS
pan figure (12.81 → 12.30 ms mid, 8.78 → 7.80 ms far).

Every still gate passed with wide headroom on this machine (an Apple Silicon
GPU, well above every tier's target hardware), so no tier's CSV row was
tuned. As the spec notes (§4): this is the M5 Pro to Iris Xe / low-end APU
gap — **one real run on an integrated-GPU machine is recommended before
shipping**, since a GPU actually AT a tier's floor may not clear its budget
by the same margin.

## Open items before the 3D map ships

- `build_terrain.gd`'s look constants (textures, material, sky, sea) still
  live in the script, not a CSV; `data/map3d_bake.csv` moved the bake's
  shore, coast-edge, beach and river numbers out of `bake_world.py`, but the
  remaining bake constants (ridges, biome mix, far colours) are still in
  `bake_world.py`.
- The `low` tier's `world` column still reads `full`: the optional LITE
  terrain build (a coarser heightmap and a smaller control map for an
  integrated GPU, Task 23 of the 2026-09-20 refactor plan) was SKIPPED and
  never built. Until it exists, `low` differs from `high` only in the render
  scale, the shadows, the clouds, the mesh and the line steps.
- **The bench's headline numbers were STILL-camera numbers** until
  2026-09-20's `--pan` (above), and `high` does not clear its budget while
  the map is dragged (9.05 ms plain, 12.30 ms under MANORS, against 8.00 ms).
  Nothing was retuned: the owner decides whether the budget, the tier's
  contents or the per-move work gives.
- **House clusters add measured cost, honestly reported.** Under `--pan`
  (the drag figure — see "Still or panning" above) the `high` tier's worst
  frame with the house layer on is 10.93 ms against its 8.00 ms budget —
  still over, on top of the pre-existing 9.05 ms plain / 12.30 ms under
  MANORS this file already records above (still-camera *with* houses clears
  at 6.49 ms; the cost is draw calls, +70–80, not the ~11k added triangles —
  real house geometry is 20–52 triangles each). **Every one of those pan
  numbers, houses included, was measured with a Godot editor resident on the
  same GPU** (open on `world_map_3d.tscn` for part of the session), so they
  were flagged as likely pessimistic.
  **Re-measured 2026-09-20 with no editor resident** (`GDAI_MCP_SERVER_PORT=3999
  /Applications/Godot.app/Contents/MacOS/Godot --path . res://scenes/tools/map3d/bench.tscn
  -- --size 3024x1964 --quality high --layer houses [--pan]`, after a full
  `build_pack.sh` rebuild so the world matched the house-table changes): the
  editor-closed number is **not** better — `--pan` gave a worst frame of
  **14.63 ms** and, run again immediately after, **15.07 ms** (both far-zoom,
  against the near-zoom worst the editor-resident run reported), clearing
  10.93 ms further, not clearing it; the still-camera worst was **6.87 ms**,
  close to the editor-resident 6.49 ms. So the editor was not hiding cost
  here — with it gone the `high` tier is worse over budget while dragging
  (14.6–15.1 ms vs. 10.93 ms, both against 8.00 ms), and about the same
  standing still (6.87 ms vs. 6.49 ms). Old (editor-resident) and new
  (editor-closed) numbers are both kept above for comparison; nothing was
  retuned to close the gap either way.
- **The generated house meshes are narrower than the CSV claims they are.**
  `make_houses.py`'s `join_and_normalise()` scales a mesh uniformly by
  `min(footprint_m / span, height_m / tall)`, so a tall, narrow type is
  bounded by its height ratio and comes out narrower than its footprint —
  measured `townhouse_c` at 8.50 m against a claimed 11.00 m footprint, and
  `church_tower` at 16.39 m against a claimed 22.00 m. `bake_houses.py`'s own
  overlap test uses the CSV's `footprint_m`, not the mesh's real size, so
  houses are spaced as if they were up to a quarter wider than they actually
  render. Not fixed this round; whoever resumes the density work should
  either measure the real mesh bounds after generation (`houses.json`
  already carries `footprint_m` and `height_m`, but they are the CSV's
  claimed values, not measured ones) or stop scaling non-uniformly-bounded
  types down in the first place.
  **RESOLVED 2026-09-21 (density v5), by the first of those two routes.**
  The meshes (then Hunyuan3D retopos; hand-modelled since 2026-09-24) are scaled uniformly to `footprint_m` on
  their long horizontal axis, and `data/map3d_houses.csv` carries `width_m`
  and `depth_m` — the mesh's own measured spans, written back by
  `tools/map3d/scale_houses.py` exactly as `height_m` is.
  `bake_houses.half_extents()` packs against those, so a house reserves its
  real rectangle rather than a square of its long side. That square was the
  larger half of this finding: it gave a 14 × 10 m cottage a 14 × 14 m plot,
  i.e. ~37% of every settlement's ground spent on air, which read as a loose
  scatter no `house_m2_each_*` could tighten.
- **`house_frontage_share` leaked well past its target during this branch's
  work** (measured 60–72% against a 0.45 target: the uncapped top-up ran
  `_frontage_pass(enforce_quota=False)` before `_infill_pass(enforce_quota=False)`,
  so infill's own shortfall — routine, since frontage places first and
  already holds the near-lane ground — went back to frontage's untried
  candidates instead of infill's). **This is fixed as of commit `3af24da`**
  (the pass order was swapped, infill's uncapped pass now runs first), with
  a regression test in `tools/map3d/test_bake_houses.py`; recorded here only
  because the work ledger's own entry still called it "OPEN, not yet
  dispatched" at the time it was written.
- `house_road_align_m` and the routes parameter named in the original spec
  were removed as dead code during the lane redesign: a house's yaw comes
  from its own lane, not the pack's drawn roads, so a real road can run into
  a settlement whose invented lanes do not meet it at the edge. The owner
  explicitly chose "no streets" (through-roads) this round; revisit if that
  changes.
- Compare Compatibility vs Forward+ on the target PC (without trees
  Compatibility measured 5.0 vs 8.4 ms at 1440p).


## Woods and aerial ground (look route, 2026-09-30)

- **Woods** are `bake_trees.py` (run by `build_pack.sh` after `bake_world.py`;
  numpy, ~2 s): tree CLUMPS on a jittered grid by each biome's woodedness
  (`data/map3d_trees.csv`), gathered by a grove noise into woods with an edge,
  conifers and broadleaves in patches of one kind, never in water, on a sown
  field, a road, a river bank, a settlement, a cliff or above the tree line
  (`test_bake_trees.py` checks the built pack). It writes `bake/trees.bin`
  (x, y, z, yaw, scale, kind) and `bake/woods.png` (the canopy's share per
  40 m texel). `Map3DLayerTrees` draws the clumps — `Map3DTreeMesh`'s
  procedural low-poly crowns, two levels of detail — as one MultiMesh per 2 km
  square, kind, variant and level, shown by Godot's own visibility ranges
  (`map3d_tree_near_m` / `_far_m`): built once at load, nothing per frame.
  Past the far range the ground's canopy tint (`Map3DGroundTint`'s woods
  stage, `ground_look.tres` `wood_*`) carries the wood. Measured primitive cost on high:
  ~+2.5 M near, ~+1.9 M mid.
- **Sky occlusion** (`bake_relief_ao.py`, visual review 2026-10-05): from
  `bake/height_war.r16`, how much of the sky each 40 m texel sees (horizon
  search along `data/map3d_bake.csv` `relief_ao_dirs` directions out to
  `relief_ao_radii_m`, blurred by `relief_ao_blur_texels`), written to
  `bake/relief_ao.png` on the woods grid. `Map3DGroundRelief`'s stage
  darkens the ground by it (`ground_look.tres` `relief_ao`, 0 off): the
  valleys and a terrace's foot read darker, with no direction, so the turning
  sun is never contradicted. One texture fetch; `test_bake_relief_ao.py`.
- **Aerial ground layers** (`aerial_meadow`, `aerial_canopy`,
  `aerial_upland`) replace `leafy_grass` and `rocky_trail` — see
  `assets/3D/terrain/model_wip/aerial/README.md`. `pack_aerial.py` makes a picture seamless
  (an offset cross-fade that keeps its contrast, after taking out the
  photograph's own slow light) and writes the two maps AND their `.import`
  with the VRAM compression every Terrain3D layer must share.
