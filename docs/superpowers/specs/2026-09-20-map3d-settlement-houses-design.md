# Settlements as 3D house clusters on the 3D map

Owner, 2026-09-20: "现在的主要目标是定居点，之前的定居点美术我都不满意。我希望生成
房屋的3D模型，定居点根据其大小，有不同种类的房屋3d模型组成一个簇落。成不规则围绕
中心展开。记住，定居点的房屋模型不可以出现在海上。定居点和地图要无缝衔接，和谐一体，
定居点周边和地图上的地形要有一定距离的缓冲过渡".

A settlement stops being a symbol and becomes a place: real house meshes
standing on the Terrain3D ground, a cluster whose size comes from the burg's
population, irregular around a centre, thinning outward into the built ground
the bake already lays down.

## Owner rulings that govern this work

- **The 2026-09-16 ruling "procedural Blender towns were abandoned after five
  rounds; do not retry" is OVERRULED** (owner 2026-09-20: "推翻它，这次是真3D地图").
  That ruling was about rendering 3D towns down to a 2D sprite pasted on the
  2D map. Houses standing on Terrain3D under the scene's own sun is a
  different thing. `.claude/skills/visual-review/taste.md` is amended to say
  so; the part of it that still holds is **no base plates** — the grass disc
  under those towns was the first thing rejected, and nothing here may
  reintroduce one.
- **The black dots are a placeholder and are removed entirely** (owner
  2026-09-20: "黑点/黑点+圆圈本就是暂时的placeholder，给我完全替换掉"), reversing
  `data/map3d_settlements.csv`'s 2026-09-19 ruling. What stands at campaign
  zoom instead is an OPEN QUESTION (§8).
- **Houses are read at the cluster scale, not the building scale** (owner
  2026-09-20, "保持 800m：看簇落形状就够"): `map3d_zoom_min_m` stays 800, where
  an 8 m house is 9 px on a 1280×720 window and 17 px at 2560×1440. What must
  read is the cluster's outline, the roof colours, and a landmark silhouette
  standing above the rest. Detail below that is wasted.
- **Models are generated, and are a replaceable layer** (owner 2026-09-20,
  "先 Blender 生成，不好看再换资产库"): the placement, clustering, transition
  and LOD system must not depend on where the meshes came from.
- **Centre landmark, thinning outward; no streets, no walls** (owner
  2026-09-20). `burgs.csv`'s `walls|citadel` features stay unused for now.

## 1. Where house positions are generated — `tools/map3d/bake_world.py`

House positions are computed in the bake's Python, beside the village
footprints, NOT in Godot.

`sow_patchwork()` (`tools/map3d/bake_world.py`) already holds everything the
placement needs: the land mask, each burg's population and footprint radius
(`footprint_radius_m`), the fray noise, and the farm mask that already excludes
the footprint. Generating houses there makes "never in the sea", "never on a
field" and "inside the built ground" *structural* rather than a check bolted on
afterwards. Nothing downstream can place a house the footprint did not claim.

### Output: `<map3d_dir>/bake/houses.csv`

```
burg_code,rank,x_m,z_m,yaw_deg,type,scale
```

- `x_m`, `z_m` — world metres (the same frame `Map3DGeometry.pack_to_world`
  produces), so the runtime does no coordinate maths.
- **No `y`.** Rivers are carved into the heightmap, so the only truthful ground
  height is the built terrain's; the runtime samples it with
  `Map3DContext.height_at()` at load.
- `type` — a row of `data/map3d_houses.csv`.
- `rank` — the order houses appear as the settlement grows, 0 first. The
  runtime shows the first N by the burg's CURRENT people. A village promoted to
  a town by `data/settlement_growth.csv` therefore sprouts more houses **with no
  re-bake**; the bake always emits the cluster at its maximum size.
- `scale` — per-instance size jitter, plus the edge taper of §4.
- `yaw_deg` — §4.

### Placement per burg

1. `r_foot = footprint_radius_m(population)` — the existing function, unchanged.
2. `r_house = house_radius_ratio * r_foot` (§4). Houses live only inside
   `r_house`; the ring out to `r_foot` is deliberately empty.
3. Candidates on a jittered grid at `house_spacing_m`, seeded from the burg
   code so a re-bake places the same village.
4. A candidate is kept when ALL hold:
   - the footprint mask at that point is above `house_foot_min`;
   - it is land (the bake's own `land` mask);
   - the final heightmap's slope there is under `house_max_slope` — this is
     what keeps houses off carved river banks and cliffs;
   - it is at least `house_shore_min_m` from water. A burg with `is_port` 1
     uses `house_port_shore_min_m` instead, so a harbour may sit on the water's
     edge;
   - a Bernoulli draw against the density falloff (§4) passes;
   - it does not overlap an already-placed house's `footprint_m`.
5. The centre landmark is placed first, at the burg's own position, its type
   chosen by `group` (§2).
6. Ranking: the landmark is rank 0; the rest are ranked by distance from the
   centre, so a growing settlement grows OUTWARD.
7. A burg whose kept count falls below `house_min` (a village on a crag) keeps
   its best candidates by relaxing the density draw only — never the land,
   water or slope tests.

### The blocky-noise conflict

`footprint_block_m` / `footprint_block_depth` currently paint light-and-dark
blocks into the colour map to *suggest* roofs and yards. With real roofs
standing there, that reads as roofs painted on the ground beside real roofs.
The bake must therefore fade the block noise to zero inside `r_house` (leaving
plain trodden earth under the houses) and keep it in the buffer ring, where it
correctly reads as yards and threshing floors.

## 2. Models — `tools/map3d/make_houses.py`, committed to git

A headless Blender script, in the shape of the existing
`tools/map3d/render_impostors.py`:

```
blender -b --factory-startup --python tools/map3d/make_houses.py
```

It writes `assets/map3d_houses/<type>.glb` and `assets/map3d_houses/houses.json`
(each mesh's size in metres and its forward axis).

**These files are committed.** They are a few hundred triangles and ~20 KB
each. `assets/map3d/` is git-ignored in full — putting them there would make
Blender a prerequisite for seeing a settlement on a fresh clone. Committing
them follows the precedent of `assets/map3d_preview/`, whose 512 px stand-ins
exist so a checkout without the git-ignored texture packs still draws.

The script is NOT part of `tools/map3d/build_pack.sh` — that is a headless
Godot chain, and Blender is a separate dependency. It is documented as its own
step in `tools/map3d/README.md`, as `fetch_polyhaven.py` already is.

### The type table — `data/map3d_houses.csv`

```
type,mesh,role,weight,footprint_m,height_m,roof,min_group,notes
```

- `role` — `landmark` (one per settlement, at the centre), `house`, `barn`
  (the small outlying kind, §4).
- `weight` — relative frequency among its role.
- `min_group` — the smallest settlement group this type appears in, so a
  village gets cottages and a barn while a capital also gets the palace.
- `roof` — the key of a roof colour in `data/terrain_palette.csv`. At 9–17 px
  the roof colour is most of what reads, so it is data, not baked into the mesh.

First set: thatched cottage ×3 variants, tiled house ×3, longhouse, barn,
workshop, church with tower, chapel, lord's tower house, palace. Walls and
stone reuse the already-packed `medieval_blocks_03` (the bridges' texture);
thatch and tile get flat materials.

Landmark by burg `group`: capital → palace, city → church with tower, town /
fort → church, village → chapel.

## 3. Runtime — `Map3DLayerHouses`, cut once per camera pose

Follows the map's established idiom: rebuilt when the camera moves, never per
frame.

- **One `MultiMesh` per house TYPE**, not per settlement. When the camera has
  moved more than `map3d_house_rebuild_move_m`, the layer collects the burgs
  within `map3d_house_view_m`, takes each one's first N houses by `rank`
  (N from its live people), buckets them by type, and rebuilds every
  `MultiMesh` in one pass. Of 684 burgs only a handful are ever in range.
- A burg beyond `map3d_house_view_m` is not instanced at all — not culled after
  the fact.
- Instance total is capped by a new `house_budget` column in
  `data/graphics_quality.csv`; when the collected set exceeds it, the farthest
  settlements are dropped first.
- Ground height per instance from `Map3DContext.height_at()`, minus
  `house_sink_m` so the wall foot bites into the ground (§4).
- The layer takes everything from `Map3DContext`; it **must not reference the
  `Game` autoload** — `tests/map3d/` already scans `scripts/map3d/*.gd` for
  `Game.` and fails on a hit. Live people come through the context.
- Houses are opaque geometry and sort by depth, so they need no
  `Map3DPriority` slot; the ribbons (borders, seams, roads, rivers) keep their
  own ordering unchanged and draw over the ground as they do today.
- Shadows are what sell "standing on the ground"; on the `low` tier, which has
  no sun shadows at all, there are none, and that is accepted.

### What is removed

`Map3DLayerSettlements`' dot `MultiMesh`es and the `dot_px` / `ring_px` /
`line_px` columns of `data/map3d_settlements.csv` go. The **selected** gold ring
stays — it is interaction feedback, not art. Picking (`Map3DContext`'s
`projected_settlements` / `settlement_rects`, `map3d_pick_px`) keeps working off
the burg's own projected position, which never depended on the dot's existence.

## 4. The buffer transition — four bands, no hard edge anywhere

The owner's requirement ("定居点周边和地图上的地形要有一定距离的缓冲过渡") is met by
making the house radius clearly smaller than the footprint radius, leaving a
whole ring of built ground with no houses on it.

| band | extent | content |
|---|---|---|
| core | `0 .. house_core_ratio * r_house` | the centre landmark and the densest houses |
| thinning | `.. r_house` | density falls as `(1 - t) ^ house_density_gamma`; past `house_barn_ratio` only `barn`-role types appear, and `scale` tapers by `house_edge_scale` |
| **buffer** | `r_house .. r_foot` | the footprint's trodden earth, **no houses** — yards, threshing floors, kitchen plots. This ring IS the transition |
| fade | beyond `r_foot` | the existing `footprint_fade` 0.7 fray, with the fields of `data/map3d_fields.csv` taking over |

`house_radius_ratio` starts at 0.60 and is settled by a bracket shoot (§8).

Three rules against the "sticker" reading:

- **Yaw has a weak bias, never uniform random.** Each house's `yaw_deg` is the
  bearing to the cluster centre (or to the nearest route point when one passes
  within `house_road_align_m`) plus a jitter of `house_yaw_jitter_deg`.
  Uniformly random orientation reads as scattered — the owner rejected exactly
  that on the 2D estates ("scattered and unreasonable"; CLAUDE.md: never place
  separate houses and fields by hash again).
- **`house_sink_m` sinks every instance** so no model shows a floating bottom
  edge on sloped ground. **No base plate, no ground disc, ever** — taste.md's
  first rejection.
- **The outer houses taper in scale**, so the cluster ends by getting smaller
  rather than by stopping.

## 5. Data (every tuned value in a CSV, per CLAUDE.md)

- **new** `data/map3d_houses.csv` — the type table of §2.
- `data/map3d_bake.csv` — `house_radius_ratio`, `house_core_ratio`,
  `house_barn_ratio`, `house_spacing_m`, `house_density_gamma`,
  `house_foot_min`, `house_max_slope`, `house_shore_min_m`,
  `house_port_shore_min_m`, `house_min`, `house_max_<group>`,
  `house_edge_scale`, `house_yaw_jitter_deg`, `house_road_align_m`,
  `house_people_per_house`.
- `data/balance.csv` — `map3d_house_view_m`, `map3d_house_fade_m`,
  `map3d_house_rebuild_move_m`, `map3d_house_sink_m`.
- `data/graphics_quality.csv` — new column `house_budget` (low tier low).
- `data/map3d_settlements.csv` — `dot_px` / `ring_px` / `line_px` removed.
- `data/terrain_palette.csv` — the roof colours named by `map3d_houses.csv`.

## 6. Staleness

`houses.csv` is a product of `bake_world.py`, so it rides the existing world
manifest: `Map3DWorldLoader.steps_hash()` already md5s `data/map3d_bake.csv`
and `data/map3d_fields.csv`, and `data/map3d_houses.csv` is added to it, so a
changed house table reports the build `stale` and names `build_pack.sh`. A
build whose `bake/houses.csv` is missing warns once through `warn_once` and
draws no houses — the same contract as the other optional bake inputs.

`Map3DLayerBake` is NOT involved: house transforms are data from the Python
bake, not geometry built by a `scripts/map3d/` builder, so there is no
`GEOMETRY_MD5` to keep.

## 7. Tests

- **new** `tests/map3d/test_map3d_houses.gd`:
  - **every house in beria's `houses.csv` is on land** — `Map3DPicker.cell_at`
    of its pack px is >= 0, asserted over the whole file. This is the owner's
    hard requirement and must be a test, not an eyeball.
  - every house is within its burg's `r_house`, and no house is inside the
    buffer ring.
  - every `mesh` named by `data/map3d_houses.csv` exists on disk (the same
    shape as the existing "every named texture exists" test).
  - `rank` is dense from 0 per burg, and rank 0 is a `landmark` role.
  - the layer respects `house_budget` and instances nothing past
    `map3d_house_view_m`.
- `tools/map3d/test_bake_world.py`: the placement's Python unit tests —
  determinism (two runs byte-identical), the land/slope/shore rejections, the
  density falloff, the empty buffer ring.
- `tools/map3d/bench.gd`: a `--layer houses` row, judged under `--pan` (the
  honest measure) against the tier's `bench_budget_ms`.
- The whole suite must still report the expected error count (`./run_tests.sh`).

## 8. Open — the owner's to rule, with the shoot already planned

1. **What stands at campaign zoom.** At `map3d_zoom_max_m` 150 000 a screen px
   is ~172 m: a capital's 1.1 km footprint is 6.6 px and a village is 1 px, so
   clusters are invisible there. The owner asked to see samples of all three
   candidates ("以上每一种你给我个sample看看"); option (a) cannot be shot before
   the clusters exist, because it *is* the cluster seen from far away. So once
   §1–§4 are in, shoot a three-way comparison at the same camera pose (~40 km)
   with crops, per `.claude/skills/visual-review/`:
   a. the cluster rendered to an impostor card (the precedent is
      `tools/map3d/render_impostors.py`, which already does this for trees),
      crossfading to the real meshes as the camera closes, with a minimum
      screen size so a city stays findable;
   b. names only, standing on the HUD like the kingdom names, sized and gated
      by tier;
   c. a proper art symbol per tier, fading out as the meshes fade in.
2. **`house_radius_ratio`, `house_density_gamma`, and the per-group house
   caps** — bracketed with `snapshot_screen --bal key=value` and picked by the
   owner from a crop sheet.
3. **Walls.** `burgs.csv` carries `walls|citadel`; the owner chose no walls this
   round. If revisited, the 2026-09-17 settlement-art ruling applies: a BROKEN
   stretch of old wall along one side only, never a closed circuit.
