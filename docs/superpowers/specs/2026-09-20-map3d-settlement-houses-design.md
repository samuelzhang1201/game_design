# Settlements as 3D house clusters on the 3D map

Owner, 2026-09-20: "现在的主要目标是定居点，之前的定居点美术我都不满意。我希望生成
房屋的3D模型，定居点根据其大小，有不同种类的房屋3d模型组成一个簇落。成不规则围绕
中心展开。记住，定居点的房屋模型不可以出现在海上。定居点和地图要无缝衔接，和谐一体，
定居点周边和地图上的地形要有一定距离的缓冲过渡".

A settlement stops being a symbol and becomes a place: real house meshes
standing on the Terrain3D ground, a cluster whose size comes from the burg's
population, irregular around a centre, thinning outward into the built ground
the bake already lays down.

> **Status (2026-09-20): §1–§5 below now describe `tools/map3d/bake_houses.py`
> as it actually ships**, current as of the branch's last commit (`3af24da`).
> They did not always: the first cut was an evenly-spaced jittered grid with
> a radial density falloff, sized off each burg's population. The owner
> rejected it as scattered ("你不需要实时严格的计算房屋数量…房屋的摆放要凸显中世
> 纪那种风格，紧凑杂乱，形成巷子，高低层次不齐") and it was replaced with the
> lane-grown, ring-quota layout this document now describes, whose house
> count is a fixed TARGET per settlement GROUP, never derived from
> population. For the history of that change — what was tried, measured and
> rejected along the way — see the work ledger,
> `.superpowers/sdd/2026-09-20-map3d-settlement-houses/progress.md`. Where
> this document and the code still disagree on anything, the CODE is
> correct.

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
burg_code,rank,x_m,z_m,yaw_deg,type,scale,height_scale
```

(**corrected** — `height_scale` was missing from this document's original
header; `Map3DHouses.COLUMNS` in `scripts/map3d/map3d_houses.gd` and the
rows `bake_houses.place()` actually writes both carry all eight fields.)

- `x_m`, `z_m` — world metres (the same frame `Map3DGeometry.pack_to_world`
  produces), so the runtime does no coordinate maths.
- **No `y`.** Rivers are carved into the heightmap, so the only truthful ground
  height is the built terrain's; the runtime samples it with
  `Map3DContext.height_at()` at load.
- `type` — a row of `data/map3d_houses.csv`.
- `rank` — 0 is the centre landmark; the rest follow placement order
  (frontage before block infill) within each ring quota. **This bullet, as
  originally written, described a design that shipped differently — see the
  correction below.**
- `scale` — the HORIZONTAL edge taper of §1 point 9 plus its own jitter.
- `height_scale` — a SEPARATE, independent VERTICAL taper (§1 point 9):
  tallest at the centre, shortest at the rim, jittered per house — 高低层次
  不齐, so neighbours differ in height as well as footprint.
- `yaw_deg` — the bearing to the house's own lane (or the nearest one, for a
  block-infill house) plus jitter (§1 points 6–7).

**Correction (owner amendment 2026-09-20, after the first review; ledger
entries under Task 2 and the "OWNER AMENDMENT" section):** this bullet
originally claimed the runtime "shows the first N [houses] by the burg's
CURRENT people" and that "the bake always emits the cluster at its maximum
size", so a settlement promoted by `data/settlement_growth.csv` would sprout
more houses live, with no re-bake. Neither half of that survived:

1. **It was already false when written.** A reviewer proved with real
   `beria` populations that ground and terrain rejections (shore, slope, a
   footprint mask that frays low on an otherwise dry, flat site) leave
   `place()` 3–5% short of what the population formula asked for at
   ordinary sizes, and up to 14% short on an unlucky seed — `rows.size()`
   binds before any population-derived maximum does. Growth stayed
   monotonic; it just plateaued a few percent early.
2. **The whole population-driven mechanism it describes is gone.** The
   owner's later ruling in this same session ("你不需要实时严格的计算房屋数量，
   你只需要根据定居点种类不同生成这几种种类的定居点房屋密度即可…不需要每次都重新
   计算") replaced it: a settlement's house count is now a fixed TARGET by
   its GROUP — `house_count_village` / `_fort` / `_town` / `_city` /
   `_capital` in `data/map3d_bake.csv` (25 / 55 / 70 / 200 / 400) — decided
   once at bake time, never derived from population and never thinned live
   by it. `Map3DHouses.visible_set` instances every house the bake gave a
   settlement that is in range; it does not pick "the first N" by anything.
   A village promoted to a town by `settlement_growth.csv` therefore shows
   its PRE-growth house count until the pack is re-baked — the opposite of
   what this bullet claimed. `house_people_per_house` (§5) no longer exists.

### Placement per burg

The steps below are `tools/map3d/bake_houses.py`'s `place()` as it actually
ships, current as of the branch's last commit (`3af24da`). It replaced the
jittered grid an earlier draft of this document described; §1's `rank`
correction above has the reason why.

1. `r_foot = footprint_radius_m(population)` — unchanged, the same formula
   `bake_world.py` uses for the built-ground footprint.
2. `r_house = house_radius_ratio * r_foot` (§4). Houses live only inside
   `r_house`; the ring out to `r_foot` is deliberately empty — the owner's
   buffer.
3. **Lanes are grown first**, before anything else draws from the burg's own
   RNG stream (seeded from `blake2b(burg_code)`, not Python's salted
   `hash()`, so a re-bake is byte-identical): `lane_seeds` lanes (4 on
   `beria`) leave the centre on roughly even, jittered bearings, and each
   grows as a branching random walk (`_walk_lane`) — `lane_step_m` (20 m)
   per step, heading perturbed by up to `lane_wander_deg` (25°) each step, a
   `lane_branch_chance` (0.15) chance to fork a shorter-budgeted child lane
   at each step while `lane_max_depth` (3) still allows it — until the walk
   passes `r_house` or its own step budget runs out. This is the "巷子"
   (lanes) the owner asked for: negative space as literal geometry, not a
   density formula.
4. **The centre landmark is placed next**, its type picked by `role ==
   "landmark"` and the burg's `group`, weighted by `weight` among the types
   its `min_group` allows (capital → palace, city → church with tower, town
   / fort → church, village → chapel — §2). It stands at the burg's own
   centre when that point is land and clear of the shore buffer; otherwise a
   ring search (`_find_landmark_spot`, 11 m radial steps, 16 points per
   ring) looks outward for the nearest land that is, bounded by
   `min(house_landmark_search_m, r_house)` — the search is capped at the
   cluster's OWN radius, so a relocated landmark can never land in the
   buffer ring. **The landmark is never slope-tested** (a hillside church is
   intended) but is always land- and shore-tested; if nothing within the
   bound qualifies, the settlement gets NEITHER a landmark NOR any houses —
   an empty list (0 of 684 real burgs hit this on `beria`; two highland
   sites do find landmark ground but then fail every house candidate and
   are left landmark-only).
5. **The target house count comes from the settlement's GROUP, never its
   population**: `house_count_<group>` (`data/map3d_bake.csv` — village 25,
   fort 55, town 70, city 200, capital 400 on `beria`), split into
   `house_edge_rings` (8) concentric ring quotas by distance from the
   centre, weighted `(1 - ring's own mid-radius fraction) ^
   house_edge_falloff_gamma` so the outer rings still get a nonzero share
   instead of the fill exhausting itself in one dense core well short of
   `r_house`.
6. **Frontage pass.** Every lane is resampled every `plot_step_m` (10 m) of
   its own arc length, offering a candidate on BOTH sides, oriented to face
   the lane (`yaw = bearing - side*90`, plus `house_yaw_jitter_deg` jitter —
   never uniform random). Candidates are tried nearest-centre first, capped
   by `house_frontage_share` (0.45) of EACH ring's own quota, so lane
   frontage cannot consume a ring's whole target before block infill gets a
   turn (an earlier round measured 60–72% real frontage share against this
   0.45 target, from a pass-ordering bug fixed in `3af24da` — see §8).
7. **Block-infill pass.** A jittered grid at `plot_step_m` spacing across
   the whole `r_house` disc fills whatever each ring's quota still lacks —
   skipping any point that falls on a lane's own clear strip
   (`lane_half_width_m`, 1.75 m half-width: a real medieval lane's own
   width, deliberately NOT widened the way this project widens roads and
   rivers for visibility, plus the candidate's own half-footprint) — and
   orienting each accepted house to the NEAREST lane's bearing (or a random
   yaw where no lane reaches), never spun on its own hash.
8. **Acceptance, for every candidate in either pass (`_try_place`).** A
   candidate is kept only when ALL hold:
   - it is inside `r_house`;
   - the footprint mask there is at least `house_foot_min`;
   - it is land, dry to `house_shore_min_m` of any water
     (`house_port_shore_min_m` instead for a burg with `is_port` 1, so a
     harbour may sit at the water's edge);
   - the heightmap's slope there is at most `house_max_slope`;
   - **its own oriented rectangle comes no closer than `house_gap_m` to any
     rectangle already placed** — an oriented separating-axis (SAT) test
     over each box's own two edge normals, not a circle-distance check: two
     rotated squares can meet corner-to-corner closer than the sum of their
     half-widths along an axis, which is why an earlier circle-based
     version of this test read as gapped.
9. **Two independent tapers toward the rim, both jittered so neighbours
   differ.** At fractional radius `t = d / r_house`: `height_scale` (its OWN
   column, vertical only) runs from `house_height_max` (1.5) at the centre
   down to `house_height_min` (0.75) at the rim — 高低层次不齐, uneven
   roofs — jittered by ±30% of its own span; the horizontal `scale`
   separately runs from 1.0 down to `house_edge_scale_min` (0.75), then a
   further `uniform(0.92, 1.08)` per house. The cluster ends by getting
   shorter AND smaller, never by stopping.
10. **If a ring's quota is still short after both quota-respecting passes**
    (real terrain — a shore, a slope, a thin footprint mask — can leave a
    ring without enough valid ground), an uncapped top-up spends whatever
    room is left: infill's own uncapped pass runs FIRST, then frontage's —
    reversing that order is exactly what caused the frontage leak in point
    6. If a settlement is still short after that, a finer grid
    (`plot_step_m * house_small_site_grid_ratio`) is tried; if it is STILL
    short and the shortfall is not water or slope, `house_foot_min` is
    relaxed by `house_small_site_foot_min_ratio` as the absolute last
    resort — this never touches the slope or shore tests, so a genuinely
    steep or wet site is still correctly left short.
11. **Ranking.** The landmark, when present, is always rank 0; every other
    house is numbered 1.. dense by distance from the centre (0.. dense with
    no landmark). This is bake-time row order, not a live growth signal —
    see §1's `rank` correction above.

**What the design still promises, unchanged, and still tested:**

- **Never in the sea** —
  `tests/map3d/test_map3d_houses_bake.gd::test_no_house_stands_in_the_sea`,
  `tools/map3d/test_bake_houses.py::test_no_house_lands_on_water`.
- **Every house inside its own cluster** (never in the buffer ring) —
  `test_every_house_is_inside_its_own_cluster`,
  `test_the_buffer_ring_is_empty`.
- **Deterministic** — the same burg code places the same village every
  re-bake — `test_the_same_burg_places_the_same_village_twice`.
- **Ranks dense from 0, a landmark at rank 0** —
  `test_rank_is_dense_and_starts_at_a_landmark`,
  `test_rank_is_dense_and_grows_outward`.

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
(**corrected** — the JSON holds each type's `footprint_m`, `height_m` and
triangle count, echoed from the CSV and measured respectively; there is no
per-mesh forward-axis field, because every mesh is generated to the SAME
fixed convention instead — standing on its own origin, min Z = 0, facing
+Z — which is what lets the runtime place it with a single yaw and no
per-type correction).

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
workshop, church with tower, chapel, lord's tower house, palace.

**Correction:** every material is a flat Principled BSDF colour read from
`data/terrain_palette.csv` at generation time (`house_wall`,
`house_roof_thatch`, `house_roof_tile`) — NOT a texture. The plan this
document originally described wanted walls and stone to reuse the
already-packed `medieval_blocks_03` (the bridges' texture); the ledger
records a reviewer finding it illegible at a 9–17 px draw size, so it was
dropped in favour of the flat colours, which removes a look asset
(`scenes/map3d/materials/house.tres`) rather than adding one. §3's runtime
layer therefore sets NO material override and NO per-instance colour of its
own — each `.glb` already carries its own two coloured surfaces (wall and
roof) from generation time.

Landmark by burg `group`: capital → palace, city → church with tower, town /
fort → church, village → chapel.

## 3. Runtime — `Map3DLayerHouses`, cut once per camera pose

Follows the map's established idiom: rebuilt when the camera moves, never per
frame.

- **One `MultiMesh` per house TYPE**, not per settlement. When the camera has
  moved more than `map3d_house_rebuild_move_m`, the layer collects the burgs
  within `map3d_house_view_m` and takes EVERY house the bake gave each one
  in range — **corrected**: not "the first N by rank, N from its live
  people" as this bullet originally said. There is no live thinning by
  population at all: the bake's own `house_count_<group>` (§1 point 5)
  already fixed each settlement's count, so `Map3DHouses.visible_set` drops
  whole SETTLEMENTS (farthest first, against the instance budget below),
  never individual houses within one. Houses are bucketed by type and every
  `MultiMesh` rebuilt in one pass. Of 684 burgs only a handful are ever in
  range.
- A burg beyond `map3d_house_view_m` is not instanced at all — not culled after
  the fact.
- Instance total is capped by a new `house_budget` column in
  `data/graphics_quality.csv`; when the collected set exceeds it, the farthest
  settlements are dropped first.
- Ground height per instance from `Map3DContext.height_at()`, minus
  `house_sink_m` so the wall foot bites into the ground (§4).
- The layer takes everything from `Map3DContext`; it **must not reference the
  `Game` autoload** — `tests/map3d/` already scans `scripts/map3d/*.gd` for
  `Game.` and fails on a hit. (`Map3DContext.people_of_burg` exists but this
  layer does not call it: population drives nothing here any more.)
- **No material override, no per-instance colour.** Each type's `.glb`
  already carries two baked surfaces (wall, roof) with their own albedo
  from `data/terrain_palette.csv` (§2's correction); a shared
  `material_override` would flatten both to one colour and lose the wall
  entirely, so every `MultiMeshInstance3D` renders with the mesh's own
  materials untouched.
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

## 4. The buffer transition — the ring stands empty by construction

The owner's requirement ("定居点周边和地图上的地形要有一定距离的缓冲过渡") holds
exactly as first designed, though the mechanism that produces the falloff
inside it does not (§1 was rewritten wholesale from an evenly-spaced
jittered grid to grown lanes and ring quotas; this section originally
described the grid version). Making `r_house` clearly smaller than `r_foot`
still leaves a whole ring of built ground with no houses on it, and nothing
in the lane redesign touches that boundary — `bake_houses.place()` cannot
place a candidate past `r_house` under any of its passes, including every
top-up (§1 point 10).

| band | extent | content |
|---|---|---|
| cluster | `0 .. r_house` (`r_house = house_radius_ratio * r_foot`) | the centre landmark, the grown lane network, and every frontage/infill house; density feathers through `house_edge_rings` ring quotas weighted by `house_edge_falloff_gamma` (§1 point 5), not the flat radial falloff this document originally described — sparser and shorter toward the rim either way, never a hard cut |
| **buffer** | `r_house .. r_foot` | the footprint's trodden earth, **no houses** — yards, threshing floors, kitchen plots. This ring IS the transition |
| fade | beyond `r_foot` | the existing `footprint_fade` 0.7 fray, with the fields of `data/map3d_fields.csv` taking over |

`house_radius_ratio` was bracketed (A 0.60 / B 0.55 / C 0.40 / D 0.28) and
the owner picked **C, 0.40** ("我喜欢C，就C吧！") — RESOLVED; see §8.

Three rules against the "sticker" reading, as they actually ship:

- **A house's yaw comes from its own lane, never uniform random.** A
  frontage house faces the lane it stands against (`bearing - side*90`); a
  block-infill house takes the bearing of the NEAREST lane, or a random yaw
  only where no lane reaches at all; either way `house_yaw_jitter_deg`
  jitters it a little. Uniformly random orientation reads as scattered — the
  owner rejected exactly that on the 2D estates ("scattered and
  unreasonable"; CLAUDE.md: never place separate houses and fields by hash
  again), and, this round, rejected an even jittered-grid scatter of the
  houses themselves twice before the lane redesign landed.
- **`house_sink_m` sinks every instance** (at the runtime layer, §3) so no
  model shows a floating bottom edge on sloped ground. **No base plate, no
  ground disc, ever** — taste.md's first rejection.
- **The outer houses taper in BOTH `scale` and `height_scale`** (§1 point
  9, independent columns — `height_scale` is vertical only, `scale` is
  horizontal), so the cluster ends by getting shorter AND smaller, never by
  stopping.

## 5. Data (every tuned value in a CSV, per CLAUDE.md)

- **new** `data/map3d_houses.csv` — the type table of §2.
- `data/map3d_bake.csv` — the keys as they actually ship. **The set this
  bullet originally listed was replaced wholesale** when §1's placement was
  rewritten from a jittered grid to grown lanes and ring quotas:
  `house_core_ratio`, `house_spacing_m`, `house_density_gamma`, `house_min`,
  `house_max_<group>`, `house_edge_scale`, `house_road_align_m` and
  `house_people_per_house` do not exist in `data/map3d_bake.csv` at all any
  more. The keys that do:
  - placement: `house_radius_ratio`, `house_foot_min`, `house_max_slope`,
    `house_shore_min_m`, `house_port_shore_min_m`, `house_gap_m`.
  - the landmark: `house_landmark_search_m`.
  - house count and its ring-quota falloff: `house_count_capital` /
    `_city` / `_town` / `_fort` / `_village`, `house_edge_rings`,
    `house_edge_falloff_gamma`, `house_frontage_share`.
  - the two rim tapers: `house_height_min`, `house_height_max`,
    `house_edge_scale_min`.
  - orientation and the small-site last resorts: `house_yaw_jitter_deg`,
    `house_barn_ratio`, `house_small_site_grid_ratio`,
    `house_small_site_foot_min_ratio`.
  - the lane network itself: `lane_seeds`, `lane_step_m`,
    `lane_wander_deg`, `lane_branch_chance`, `lane_max_depth`,
    `lane_half_width_m`, `plot_step_m`.
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

## 8. Open — updated 2026-09-20 against what actually shipped

This list was written before the first shoot. Most of it did not survive
contact with the owner's review unchanged; each item below says what
happened, not just what was asked.

1. **What stands at campaign zoom — still open, and now overlapping a
   concurrent change.** The reasoning stands (a capital's footprint is 6.6 px
   at `map3d_zoom_max_m`, a village 1 px, so clusters are invisible at that
   distance) and none of options (a)/(b)/(c) were built this round. Separately,
   the owner ruled that the black dot itself is not gone after all: it is kept
   as a far-zoom-only affordance once a settlement's houses are too small to
   read, white and solid, the capital's alone with a dark centre
   (`.claude/skills/visual-review/taste.md`). That is a narrower thing than
   any of (a)/(b)/(c) — it is the OLD symbol kept at long range, not a new
   impostor, name or art symbol — and it is being implemented as a separate,
   concurrent change to `scripts/map3d/map3d_layer_settlements.gd`,
   `settlement_ring.gdshader`, `data/map3d_settlements.csv`,
   `map3d_picker.gd`, `map3d_context.gd` and `map3d_view.gd` that this
   document does not describe further and that had not landed at the time
   this correction was written. Options (a) (impostor-to-mesh crossfade) and
   (b) (HUD names) remain genuinely open if the dot-at-distance answer turns
   out not to be enough.
2. **`house_radius_ratio` — RESOLVED.** Bracketed as four variants (A 0.60,
   B 0.55, C 0.40, D 0.28) with `snapshot_screen --bal key=value`; the owner
   picked C from the crop sheet ("我喜欢C，就C吧！"): `house_radius_ratio = 0.40`
   in `data/map3d_bake.csv`, giving a capital ~381 m² of ground per house and
   a median town ~268 m², about 3× denser than the original 0.60, with every
   settlement still reaching 100% of its target house count. D (0.28) was
   tried and rejected because it could NOT be filled (a capital placed 87% of
   its target, a town 61%, three villages lost their houses entirely).
   **`house_density_gamma` — REMOVED, not merely re-tuned.** It belonged to
   the rejected jittered-grid design (even specks, no negative space) and has
   no successor of the same name; the lane-and-ring-quota system's own taper
   is `house_edge_falloff_gamma` (`data/map3d_bake.csv`), a different
   mechanism (how a FIXED ring-quota total spends itself from centre to rim
   over a network that already has lanes for negative space, not how densely
   to scatter points).
   **"The per-group house caps" — REMOVED and replaced.** `house_max_<group>`
   (a ceiling on a population-derived count) no longer exists; house count is
   now `house_count_village` / `_fort` / `_town` / `_city` / `_capital` — a
   fixed TARGET per group, independent of population (25 / 55 / 70 / 200 /
   400 on `beria`), spent across `house_edge_rings` concentric ring quotas
   (§1's correction and CLAUDE.md carry the detail).
3. **Walls — unchanged.** `burgs.csv` carries `walls|citadel`; the owner
   chose no walls this round. If revisited, the 2026-09-17 settlement-art
   ruling applies: a BROKEN stretch of old wall along one side only, never a
   closed circuit.
4. **NEW — the generated mesh is narrower than the CSV it was generated
   from.** `tools/map3d/make_houses.py`'s `join_and_normalise()` scales a
   built mesh uniformly by `min(footprint_m / span, height_m / tall)`, so a
   tall, narrow type (bounded by its height ratio) comes out narrower than
   its claimed footprint: measured `townhouse_c` at 8.50 m against a claimed
   11.00 m, `church_tower` at 16.39 m against a claimed 22.00 m — 12–25%
   narrower. `bake_houses.py`'s own overlap test places candidates using the
   CSV's `footprint_m`, not the mesh's real size, so buildings are spaced as
   if they were up to a quarter wider than they actually render. Not fixed
   this round (see `tools/map3d/README.md`'s Open items for the same note
   aimed at whoever resumes this).
5. **NEW — `house_frontage_share` leaked past its target, and this was
   fixed in the branch's final commit.** Measured 60–72% against a 0.45
   target (`stotreso` 61.3%, `carden` 67.7%, `staptonsey` 72.0%): the
   uncapped top-up ran `_frontage_pass(enforce_quota=False)` before
   `_infill_pass(enforce_quota=False)`, so whenever infill could not spend
   its own ring share — routine, since frontage places first and already
   holds the near-lane ground — the shortfall went back to frontage instead
   of infill. **This is fixed as of commit `3af24da`** (the fallback order
   was swapped; a regression test lives in `tools/map3d/test_bake_houses.py`).
   Recorded here because the work ledger's own entry for this defect still
   read "OPEN, not yet dispatched" — the ledger and the code disagree, and
   the code, which carries the fix and its test, is correct.
6. **NEW — `house_road_align_m` and the spec's own "nearest route point" idea
   did not survive.** §4 as originally written said a house's yaw biases
   toward "the nearest route point when one passes within
   `house_road_align_m`"; the shipped code has no such key and no reference
   to the pack's `routes` table at all — yaw comes only from the house's own
   grown lane. A drawn road can therefore run into a settlement whose
   invented lane network does not meet it at the edge. Deferred, not fixed:
   the owner explicitly chose "no streets" (through-roads connecting to the
   wider map) for this round, so it may be exactly what is wanted; revisit
   if that changes.
