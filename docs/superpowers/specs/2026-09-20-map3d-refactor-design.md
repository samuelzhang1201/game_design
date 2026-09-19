# The 3D world map, modular, swappable and fast on ordinary machines — design

Owner 2026-09-19 (overnight; "不要问我问题，全部按照你的建议做" — every call
below is the implementer's, logged for the owner to reverse):

> Refactor the 3D world map so it is modular — the script is far too big. Set
> up the architecture so it is scalable and map data swaps easily; performance
> must suit most players' computers, not only the dev machine. Use the gdai MCP
> to set up nodes and their config, import assets where possible, so clicking a
> node in the editor shows the real picture — today everything is empty because
> the scenes are built purely in code.

Starts after the HEIGHTS plan and the border-look plan have landed (both edit
`map3d_view.gd`). Survey: `scratchpad` survey of 2026-09-19, summarised here.

## 0. Today

`scripts/map3d/map3d_view.gd` is ~2,100 lines and ~19 jobs (camera rig and
input, SubViewport, world loading, settlements, rivers, sea, sun, clouds,
borders and lines, themes/ground tint, roads and bridges, ruler, labels,
badges, armies, landmarks, pick/hover/selection, test seams). The pure helpers
around it are already small and tested (Geometry, Borders, Rivers, Bridges,
CloudField, GroundTint). Every node is made in code, so the editor shows an
empty Control. Every screen switch frees the view, reloads the 44 MB world and
recompiles the patched Terrain3D shader. Hover picking and the HUD re-project
all 684 settlements (and every manor) with a `get_height` each, per move. The
last bench worst is 6.4 ms on an M5 Pro at 3024×1964 — an integrated GPU is an
estimated 8–15× slower.

## 1. Shape

One authored scene, `scenes/map3d/world_map_3d.tscn`, built in the editor
through the gdai MCP, whose root keeps `class_name Map3DView` and its whole
public API (signals, statics, seams — the survey lists them; a test pins them
first). Under it, one small script per job, none over ~250 lines, the root a
coordinator of ~300–400 lines:

```
Map3DView (Control)                       coordinator, public API, forwarders
├─ Viewport (SubViewport)                 name kept
│  ├─ WorldSlot (Node3D)                  the pack's built world instanced here
│  ├─ Environment (WorldEnvironment)      authored .tres (sky, Filmic, fog)
│  ├─ Sun (DirectionalLight3D)            authored
│  ├─ CameraRig (Map3DCameraRig) └ RigCamera
│  ├─ Sea (Map3DLayerSea)                 water_sea.tres
│  ├─ Rivers (Map3DLayerRivers)           water_river.tres
│  ├─ Bridges                             owned by Map3DLayerRoads
│  ├─ Lines (Map3DLayerLines)             ribbon host: Roads, Trails, ManorEdges,
│  │                                      Seams, Kingdoms(+Band, Halo), Hover, Selection
│  ├─ Clouds (Map3DLayerClouds) └ Shadows
│  └─ Markers (Map3DLayerSettlements) └ <Group>…, Selected
├─ Display (TextureRect ← Viewport)
├─ Notice (Label)
├─ Hud (Map3DHud) └ Labels, Landmarks, HeatLegend, Badges, Armies, Compass, Needle, ScaleBar, Ruler
└─ Tooltip (Label, chip style)
```

Node names the tests and tools use are kept (`Viewport`, `Markers/<Group>`,
`Clouds`, `Rivers`, `Lines/<name>`, `Hud`).

**`Map3DContext`** (RefCounted) is the one thing the layers share: `repo`,
`meta`, `camera`, `terrain`, `state()`, `height_at(xz)`, `to_world` /
`to_pack`, `project(world)`, `ground_at(pos)`, `render_scale()`,
`viewport_px_scale()`, `metres_per_pixel()`, `quality`, and ground points
cached ONCE at load (`burg_ground`, `cell_ground`) — the data never moves, so
no per-frame `get_height`. Signal `camera_moved`; the HUD refreshes from it.
Layers never reach for the `Game` autoload (the HUD does today) — they take the
context, which is also what lets them run as `@tool` in the editor.

Layer scripts: `Map3DWorldLoader`, `Map3DCameraRig`, `Map3DInput`,
`Map3DLayerLines`, `Map3DLayerBorders`, `Map3DLayerThemes` (MANORS + HEIGHTS),
`Map3DLayerRivers`, `Map3DLayerSea`, `Map3DLayerRoads`,
`Map3DLayerSettlements`, `Map3DLayerClouds`, `Map3DPicker`, `Map3DSelection`,
and HUD children `Map3DHudLabels` / `Badges` / `Armies` / `Landmarks` /
`Ruler`. The view forwards every existing public call, so screens, GameRoot,
tools and tests change nothing on day one.

## 2. Editor authoring (the owner's ask)

Authored in the scene through the gdai MCP: the whole node tree, Control
anchors, SubViewport flags, the Display's ViewportTexture, Notice and Tooltip
(StyleBox), WorldEnvironment + Environment `.tres`, the Sun, the camera's
defaults, HUD children with anchors, and the materials as `.tres` files
showing real textures in the inspector (road, bridge stone, river, sea with
its NoiseTexture2D ripple, cloud deck and cloud shadow — two files, the
Compatibility alpha-scissor trap — border line, settlement ring, selection
ring).

**Ruling — CSV vs inspector:** a `.tres` holds STRUCTURE and LOOK ASSETS
(shader, textures, samplers, render priority); every tuned NUMBER stays in
`data/*.csv` and is bound at load (CLAUDE.md's rule stands). The editor
preview applies the same CSV values, so what the editor shows is what the game
shows. *Cost if wrong:* the owner may want to tune in the inspector; moving a
number from CSV to `.tres` later is per-key and cheap.

**Ruling — git-ignored textures:** `assets/map3d/textures/` is git-ignored
(293 MB). Commit 512 px preview copies under `assets/map3d_preview/` and point
the committed `.tres` at them; the loader swaps in the full-resolution
texture when present. *Cost if wrong:* ~10 MB in git.

Runtime-generated content (borders, seams, hover, selection, manor edges,
settlement MultiMeshes, theme LUT, clouds, HUD layout, terrain) keeps a named
node in the scene. Rivers, roads and bridges are static per pack, so the build
bakes them to `assets/map3d/<id>/layers/*.res` (ArrayMesh saves headless;
MultiMesh does not); the runtime prefers the baked mesh when its manifest
hash matches, else builds as now. Each layer node is `@tool` with an
`@export var preview := false` (and `preview_pack` on the root): in the editor
it loads the repo itself (FileAccess, no autoload), instances the pack's
world, and shows its mesh — children added without `owner`, so nothing
generated is saved into the `.tscn`. With no built pack, a small authored
placeholder mesh in the layer's material stands in (editor only).

## 3. Swapping map data

- The build holds DATA only: Terrain3D + root meta + `rivers.json` + fields +
  baked layers + `manifest.json` (`format_version`, meta, built_at, the step
  keys' hash). Sun, Environment and Sea leave the build (the loader ignores
  them in an old build, so old builds and fixtures keep working); the
  framing cameras move into `shoot.gd`.
- `data/maps.csv` gains an optional `map3d_dir` (default
  `res://assets/map3d/<map_id>`), read through `DataRepository`.
- `tools/map3d/build_pack.sh --map ID` runs the whole chain
  (export_manor_land → bake_world.py → build_world.gd → bake layers). A new
  pack = its data tables + its assets + one `maps.csv` row + this command.
- The notice says why there is no 3D map: `missing`, `stale` (manifest
  version or meta mismatch — rebuild), `bad`; a missing optional input warns
  once.
- **A world cache** (`Map3DWorldCache`, keyed by scene path, cleared on
  `load_map`): a screen switch re-parents the loaded world instead of
  reloading it; one patched material per world (the shared-material MANORS
  bug is the regression to guard).

## 4. Ordinary machines

`data/graphics_quality.csv` — tiers `low / medium / high / ultra`:

| tier | render scale | aniso | sun shadows | cloud shadows | clouds | Terrain3D mesh size/LODs | line/road/river step m | HUD Hz |
|---|---|---|---|---|---|---|---|---|
| low | 0.67 | 4x | off | off | 4 | 32 / 5 | 300 / 50 / 30 | 30 |
| medium | 0.85 | 8x | 2 splits, 30 km, 2048 | off | 8 | 48 / 6 | 200 / 35 / 18 | 60 |
| high | 1.0 | 16x | 4 splits, 60 km, 4096 | on | 10 | 48 / 7 | 150 / 25 / 12 | ∞ |
| ultra | 1.0, MSAA 2x | 16x | as high | on | 10 | 64 / 8 | as high | ∞ |

`Map3DQuality` (pure: `row`, `detect(adapter, vendor)`) auto-detects on first
run — Intel UHD/Iris/Xe, AMD APU "Radeon Graphics", llvmpipe → low; base Apple
M-series, GTX ≤ 10xx, MX → medium; else high — and `user://settings.cfg`
`graphics/quality` (with a pause-menu option) overrides it. Render scale runs
through `ctx.viewport_px_scale()`, split from the design→window scale (every
projection and px uniform; round-trip tests hold it). CPU fixes at every tier:
cached ground points; one projected-settlement list per camera pose shared by
pick, counters and HUD; badges/counters skipped when their layer is off; the
world cache.

Bench: `tools/map3d/bench.gd --quality low|medium|high --render-scale`, also
printing draw calls and primitives. Gates: high ≤ 8 ms at 3024×1964 (as
today); medium ≤ 6 ms and low ≤ 4 ms at 1920×1080 on the dev machine — ~8–10×
headroom, the M5 Pro to Iris Xe gap. One real run on an integrated-GPU
machine is recommended before shipping.

A **lite terrain build** (40 m vertex, ~¼ memory) for the low tier is
optional and last.

## 5. Order (each step green, mechanical moves first)

0. API safety-net test (every public name, signal, node path) + bench
   baseline.
1. `Map3DContext`; 2. cached ground points; 3. `Map3DLayerLines`;
4. layer extractions one commit each (rivers+sea+sun, clouds, roads+bridges,
   settlements, borders, themes); 5. camera rig + input; 6. picker +
   selection; 7. HUD children, no `Game` in the HUD;
8. the authored scene via the gdai MCP (same names; `create()` instantiates
   it); 9. Sun/Environment/Sea into the scene, build emits data only;
10. pack plumbing (`map3d_dir`, manifest, notices, build_pack.sh, docs);
11. quality tiers + bench gates; 12. world cache; 13. baked layers + `@tool`
   previews; 14. (optional) lite build.

## 6. Risks

Test coupling to private handlers (`_gui_input`, `_process`) and to
`line_mesh()` returning null for an empty line; the render-scale split (the
likeliest pick bug — round-trip tests); a patched material shared between
views; the Compatibility traps (cloud shaders apart, raw colour uniforms,
TextureRect not SubViewportContainer); `@tool` code touching autoloads or
crashing the editor (terrain preview behind an explicit toggle); gdai edits
while the editor holds a stale scene (reopen before edit, commit per step);
`world.tscn` saves `dual_scale_*` / `tri_scale_reduction` as null — dual
scaling may be silently off; fixing it changes look and cost, so it gets a
visual review of its own.
