# LEDGER — the realm as a star chart — design

Status: draft for the owner's review, 2026-09-30. It replaces the look and
the layout of the LEDGER view (spec `2026-09-30-ledger-ontology-design.md`
§6.2–6.3: three floating discs, type spheres at hand-set places, brass and
glass). The engine's meaning — belief not truth, the governor as reporter,
orders, audits, strands, loops, gauges — is unchanged. **Default** marks a
choice the owner has not ruled on; each can be overruled at review.

## 1. What the owner asked for (2026-09-30)

- After three reference images (a 3D "big data" cluster graph, a 3D
  character network, a 2D knowledge graph): "我个人更喜欢第一个的3d效果，不同
  颜色的cluster反应现在不同的tab，展现在一个类似宇宙星空的空间中，把你现在的
  那些球球变小些，加上亮色的颜色，但是要有些反光，交界处也有渐变。第三张图有点
  类似2d的view可供玩家选择。"
- "实例数量不是问题，我们可以更多的要素！"
- Neon read as off-style; asked for palettes that suit the game. A throwaway
  prototype showed four; **palette D** was chosen: "配色选D".
- "经济团采用行省为最小单位吧" — the economy's smallest unit is the PROVINCE.

So the LEDGER becomes **one galaxy**: every object of the realm the crown
knows of is a small bright star, each tab is a coloured cluster of stars in
a night sky, links run between them and shade from one cluster's colour to
the other's, and the player can lay the whole chart flat in 2D.

## 2. What stays, what goes

**Stays** (read, not re-built): `Ledger`'s belief rules (`_believed`,
`_account`, `_claimed`, audits, strands, `Intel` levels, ink, yellowing),
`LedgerResolvers`' readers, `Ledger.actions_for` / `params_of` /
`order_text`, `LedgerCards`, the left column's card and list, orders
through `Game.try_execute`, `LedgerOrbit` (camera numbers), `LedgerPick`
(ray picking), `LedgerHud`'s gauges, the loops, the court's "one web at a
time" rule (taste.md, 2026-09-30), and the rule that nothing under
`scripts/ledger3d/` reads `Game`.

**Goes**: the three layer discs (`disc.gdshader`, `_build_discs`, every
`ledger_disc_*` key), layer heights (`ledger_layer_gap_m`,
`LedgerLayout.layer_y`), the type level as the screen's opening view
(`Ledger._type_level`, `ledger_object_types.csv` `x` / `z`), one
MeshInstance per thread (`thread.gdshader`), and the brass-and-glass
palette of variant A. What is removed is removed in the last task, once
nothing calls it.

## 3. The galaxy snapshot (engine, pure)

`Ledger.galaxy(repo, state, opened: Dictionary) -> Dictionary` returns the
snapshot shape the view already reads (`nodes`, `links`, `loops`, `day`),
with `lens` = `"galaxy"` and every node carrying a `cluster`.

- **Nodes.** Every instance of every `live` type that lists its instances
  (`LedgerResolvers.instances`), every live type that has none as ONE node
  (`type:gold`, `type:civil_goods`, `type:strategic_goods`…),
  and every `planned` type as ONE ghost node (`type:enemy_host`,
  `type:faction`, `type:source`) with its planned links, grey and dashed as
  today.
- **Clusters are data**: a new `cluster` column in
  `ledger_object_types.csv` — economy, war, court or intelligence — and a
  new `data/ledger_clusters.csv` (cluster, label, palette key, 3D anchor
  `x,y,z`, 2D anchor `x2,z2`, the lens chip it answers to). The province and
  the town sit in **economy** (owner: the economy is counted by province).
- **Links** are the union of every instance's EGO (the readers already
  answer per id, so no reader changes): a worklist starts from every listed
  instance and reads each live link row touching its type with
  `{"id": …}`; a node a link discovers is queued in turn — EXCEPT a
  foldable one (a manor, building or town) outside a controlled or opened
  province, whose links are recorded but not expanded (it only folds into
  its province). A row both of whose types have no instances (pool to pool:
  `trade_gold`, `rations`) is read at the type level once. Measured
  2026-09-30 on the default pack after six months: 799 reads, 632 nodes,
  1,196 links in ~175 ms — ~136 ms of it `holds` scanning every cell once
  per house; `LedgerResolvers` therefore builds ONE house → manors index
  per memo (`begin_memo`) and `_holds` reads it.
- **The fold** (owner: province is the economy's smallest unit). A type with
  a new `fold_to` column (`manor`, `building`, `town` → `province`) never
  stands as its own star unless its province is OPENED. Each link touching
  a folded node is re-pointed to its province (`MapManors.province_of`, live
  state, so an annexed manor folds into its new province); links that then
  coincide (same type, same ends) MERGE: `count` sums; the flow sums while
  every merged account is exact at one Intel level, else the merged figure
  is the lowest level's words; a link folded onto itself is dropped. The
  province node carries `folded: {manor: N, town: M, building: K}` for its
  size and its card.
- **Opening a province** (`opened` = the province ids the player unfolded,
  view state, never saved): its manors, towns and buildings stand as their
  own stars round it, with their own links; the rest stay folded.
- **Budget**: ≤ 60 ms warm on the default pack after six months of play
  (≈ 110 stars and 160 links folded; ≈ 650 and 1,200 with every province
  open), measured by a test on the real pack.

## 3b. Nodes and edges can be added, changed or removed at any time

Owner 2026-09-30: "另外要保证接口，我可以随时添加，修改，减少nodes和edges". The
galaxy is an OPEN schema; nothing about a particular type is written in the
view or the layout.

- **A new kind of node** is one row of `ledger_object_types.csv`: its
  `cluster`, its `fold_to` (or none), its `instances` list, and a new `star`
  column — `pool` (one fixed-size star for the whole type) or `instance`
  (sized by its links, or, on a province, by what it folds). A kind whose
  instances come from live state names a reader in `LedgerResolvers`; a
  kind whose instances are simply WRITTEN DOWN names the list `static`.
- **A new kind of edge** is one row of `ledger_link_types.csv`: its ends,
  lenses, status, its reader, and a new `look` column that alone decides
  how it is drawn — `flow` (width by the believed flow, shaded between the
  two clusters, light running along it), `tie` (warm or cold by sentiment),
  `kin` (kin gold) or `structure` (a thin line by count). The view's
  `KIN_TYPES` and every `court_relations` check go; it reads `look`.
- **Single nodes and edges, in data only.** `data/ledger_static_nodes.csv`
  (`node_id,type_id,label,note`) and `data/ledger_static_links.csv`
  (`link_id,from,to,flow,note`) are read by the generic `static` instance
  list and the generic `static` reader: a node of any type whose row says
  `instances` = `static`, an edge of any link type whose row says `resolver`
  = `static`, between two static nodes or a static node and any live one
  (`character:you`, `province:<code>` …). Adding a row adds it; editing a
  row changes it; deleting a row removes it — with no code. A static
  node's label and note are its card; a static edge's flow is the crown's
  own figure (`full`).
- **Removing** a kind is deleting its row; `Ledger.validate` names every
  link type, static node or static edge left pointing at it, once, when
  the LEDGER opens (as today). A static edge whose live end no longer
  exists (the character died) is simply not drawn.
- **When**: the tables are read with the rest of `data/` when the game
  starts; a change shows on the next start. (Reloading them while the game
  runs is out of scope.)
- **A contract test** holds this: it adds a type, a link type, two static
  nodes and a static edge to the loaded tables in memory, and asserts the
  galaxy returns them, the layout places them in their cluster and the
  view draws a star and a link for them; then it removes the rows and
  asserts they are gone.

## 4. The layout (pure)

`LedgerGalaxyLayout` (`scripts/ledger3d/`, `RefCounted`, no nodes):

- **Forces**: every pair repels in proportion to the two stars' sizes; a
  link is a spring (`ledger_galaxy_spring`, rest `ledger_galaxy_rest_m`),
  weaker across clusters (`ledger_galaxy_cross_spring`); every star is
  pulled home to its cluster's anchor (`ledger_galaxy_home`), an opened
  manor to its province's star instead.
- **Deterministic**: a new star's first place is its cluster anchor plus an
  offset hashed from its id (no RNG), passes run over ids in sorted order,
  so one snapshot always lays out the same way (invariant 2 does not bind
  the view, but a stable picture does).
- **Warm and incremental**: `step(passes)` advances the layout; a star keeps
  its place across snapshots, so a monthly refresh moves only what changed.
  The view runs `ledger_galaxy_passes_per_frame` until
  `ledger_galaxy_passes` are done, so the chart visibly SETTLES over about
  half a second when it opens or a province opens — and then stops.
- **2D** is the same model in the plane, from the 2D anchors; switching
  eases every star between its two places over `ledger_galaxy_mode_ease_s`.
- **Dragging a star** pins it where the pointer holds it for this viewing
  (today's `_dragged`); the rest ease round it. Never saved.
- O(n²) a pass; at ≈ 650 stars that is within the frame budget spread over
  the settle (§9). A grid cut-off for the repulsion is added only if the
  bench says so.

## 5. The look — palette D

Every colour is `ledger_palette.csv`, every number `balance.csv`
`ledger_*`; the view's own `WorldEnvironment` (authored in
`scenes/ledger/ledger_view.tscn`, not built in code) carries the sky, glow
and tonemap, so the map's environment is untouched.

| Key | Colour | Meaning |
|---|---|---|
| `sky_top` / `sky_bottom` | `#120E0B` / `#070605` | the warm black night |
| `nebula_a` / `nebula_b` | `#3A2A1A` / `#1A2230` | faint dust clouds |
| `stars` | `#F0E2C4` | the background stars |
| `cluster_economy` | `#D4A24C` | brass |
| `cluster_war` | `#C24A3C` | gules |
| `cluster_court` | `#9066C0` | purpure |
| `cluster_intelligence` | `#5E8CCB` | steel-azure |

- **The sky**: `sky.gdshader` — sparse stars of two sizes and faint dust by
  noise, in sky space for 3D and in screen space for 2D (seen straight down,
  sky-space stars streak into rays; the prototype showed it).
- **A cluster's haze**: one soft radial glow of its colour behind each
  cluster, sized by its spread (`ledger_haze_strength` ≈ 0.075,
  `ledger_haze_scale` ≈ 3.4 × its mean radius) — enough to name the cluster
  at a glance, never a wash over the sky (the prototype's first try was).
- **Stars**: ONE `MultiMesh` of small spheres, each in its cluster's colour
  (planned: grey `sphere_planned`), lit by emission plus a real specular
  (`ledger_star_metallic`, `_roughness`) and a rim, so up close a star reads
  as polished metal or glass, far out as a point of light; its size by kind —
  pools and hubs largest, a folded province by how much it folds, an
  instance by its links — between `ledger_star_min` and `_max`.
- **Links**: ONE ribbon mesh facing the camera at a constant SCREEN width
  (the `border_line.gdshader` practice), `link.gdshader`:
  - width by weight (flow, or a merged link's count), log scale, between
    `ledger_link_min_px` and `_max_px`;
  - colour shaded from the source's cluster to the target's — except a
    court tie, which keeps its meaning (`thread_pos` / `thread_neg` /
    `thread_kin`), and a planned link (`thread_planned`, dashed);
  - ink (alpha) is credibility, yellowing is age, light runs along a flow at
    its speed, a running loop glows — all as today;
  - strands (accounts differ) are parallel ribbons offset in screen px;
  - every fade is PERCEIVED opacity (`pow(fade, 2.2)`, taste.md 2026-09-30).

## 6. Interaction

- **Opening the LEDGER stops the clock and it stays stopped until the player
  starts it again** (owner 2026-10-01: the chart reflects the present). While
  it is open nothing starts the clock (Space, the play buttons), so the chart
  is read again only after an order, DEV MODE or a province opened or closed;
  closing it starts nothing.
- **Tabs are clusters.** Economy / War / Court / Intelligence fly the camera
  (`ledger_galaxy_fly_s`) to frame that cluster and dim the others' stars
  and haze to `ledger_galaxy_other_fade`; links leaving it stay lit at its
  end. **All** frames the whole galaxy, nothing dimmed, and is where the
  screen opens. (Default: today's tabs filter the graph; here nothing is
  ever hidden, only dimmed.)
- **Hover** names a star and puts its card's first line in a tooltip; it
  draws nothing (owner 2026-09-12: only a clicked object is ringed).
- **Click** a star: a thin gold ring (`focus_ring`) round it, its web lit at
  full weight and `ledger_focus_width` × wider, everything else at
  `ledger_focus_fade`, its neighbours named, its card in the left column.
  Click empty sky: clear.
- **At rest the player's own web of ties is lit in every tab** (a controller
  ruling of Task 8: in All the court's ties would otherwise tangle again; the
  existing `EGO_AT_REST` rule); **at rest elsewhere** a link crossing clusters stands
  back at `ledger_cross_rest_fade` so the clusters read first.
- **Double-click a province** opens it (its manors, towns and buildings
  settle round it); double-click it again closes it. Double-click any other
  star frames its web. The breadcrumb reads "Realm › Economy › Walbover".
- **Right-click**: the orders menu, as today.
- **Drag**: right-drag turns, left-drag on empty sky pans, left-drag on a
  star pins it, wheel and pinch zoom about the pointer — as today.
- **2D / 3D**: a button beside Front. 2D is an orthographic camera looking
  straight down on the flat layout; turning is off, panning and zoom stay.
  The choice is remembered for the session only.

## 7. Names

`LedgerHud` draws, cut once per camera pose:

- each cluster's title, "Economy · 32", in its colour lightened toward the
  label ink, set outward from the galaxy's middle over its cluster;
- star names for: the selected star and its neighbours, the hovered star,
  and the `ledger_label_hubs` largest stars in view — two sizes, the larger
  for the selected star and the hubs;
- the rule the critic asked for: a name never sits on a star's drawn disc
  or on another name (the cull gains the projected star discs as
  obstacles); a name that cannot be placed is dropped, lowest rank first.
- The gauges (supplies, morale, stock) keep their row under a name.

## 8. Code

| Piece | Where | Job |
|---|---|---|
| `Ledger.galaxy`, `_fold` | `scripts/engine/ledger.gd` | the snapshot (§3) |
| resolvers' `all` branches | `scripts/engine/ledger_resolvers.gd` | one read per link row |
| `cluster`, `fold_to`, `star` columns; `look` column; `ledger_clusters.csv`; `ledger_static_nodes.csv`, `ledger_static_links.csv` | `data/` | clusters, folding, look and single nodes and edges as data (§3b) |
| `LedgerGalaxyLayout` | `scripts/ledger3d/ledger_galaxy_layout.gd` | forces, warm start, 2D (§4) |
| `LedgerLinkMesh` | `scripts/ledger3d/ledger_link_mesh.gd` | pure ribbon arrays for every link and strand |
| `LedgerView3D` | `scripts/ledger3d/ledger_view_3d.gd` | coordinator: stars, links, haze, camera, input, signals |
| shaders | `scenes/ledger/sky.gdshader`, `star.gdshader`, `link.gdshader`, `haze.gdshader` | the look (§5) |
| scene | `scenes/ledger/ledger_view.tscn` | environment, sky, glow, the Stars / Links / Haze nodes, authored |
| `LedgerScreen` | `scripts/ui/ledger_screen.gd` | tabs → clusters, open / close a province, 2D/3D, breadcrumb |
| `LedgerHud` | `scripts/ledger3d/ledger_hud.gd` | titles, names with star obstacles (§7) |

`tools/snapshot_screen.gd` gains `--ledger-mode 2d` and
`--ledger-open PROVINCE` so every state can be shot by real clicks.

## 9. Performance

- Snapshot ≤ 60 ms warm (§3); layout ≤ 4 ms a frame while settling and
  nothing once settled; the drawn LEDGER holds the display refresh at
  1920×1080 on the `high` tier with every province open.
- Measured by a probe in the plan's last task on the real pack; a miss is
  fixed before merge (the grid cut-off, fewer passes a frame), not waived.

## 10. Tests (written before the code)

- `galaxy`: every live instance appears once, in its cluster; planned types
  as ghosts; no manor / town / building stands unless its province is
  opened; opening one province shows exactly its manors; a folded manor
  outside a controlled or opened province is never expanded; a merged link's
  `count` is the number it stands for; flows sum only within one Intel
  level; a link folded onto itself is gone; an annexed manor folds into its
  NEW province; the house → manors index gives `_holds` the same links as
  the scan; the galaxy's time is within budget.
- Layout: same snapshot → same places; a star keeps its place across a
  snapshot that did not touch it; clusters settle apart (every centroid
  farther from every other than the sum of their spreads); an opened
  manor settles within 3 × `ledger_galaxy_rest_m` of its province; 2D has
  every y = 0.
- Link mesh: a court tie keeps its meaning colour; a cross-cluster link
  shades end to end; a planned link is dashed; strands are offset; width
  follows weight.
- Screen: a tab dims the others and frames its own; a double-click opens
  and closes a province; 2D/3D swaps the camera; the card and orders work as
  before; the audit letter's "Open the LEDGER" lands on its flow's cluster.
- `scripts/ledger3d/*.gd` never names `Game.` (the existing scan).

## 11. The look is settled by the visual-review loop

Every look value above is a starting point from the prototype. Each look
task shoots through the real window, brackets its values, and passes an
independent critic against taste.md before the owner sees it. When built,
taste.md gains the ruling: *the LEDGER is a star chart — a warm black night,
one cluster per tab in brass, gules, purpure and steel-azure, small stars
with a real shine, links shading between clusters, read one web at a time*;
it replaces the palette part of the 2026-09-30 "orrery of brass and glass"
ruling and keeps its "one web at a time".

## 12. Out of scope

- Bundling many cross-cluster links into one weighted thread (the critic's
  suggestion): the province fold already cut 1,196 links to 160; revisit if
  opened provinces make it noisy.
- Foreign realms as their own clusters (the fog shows them only as basic
  facts today); the battle milestone M4 lights `enemy_host` in War.
- Any change to what the LEDGER means, costs or orders.
