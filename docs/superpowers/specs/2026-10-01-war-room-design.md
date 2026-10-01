# WAR ROOM — the plotting table — design

Status: designed with the owner 2026-10-01 (brainstorm, every section
approved). Replaces the WAR ROOM placeholder page (owner 2026-09-17) and
gives shape to `2026-09-28-intelligence-layer-alignment.md` §5.9 ("WAR ROOM
stops being a placeholder"). The enemy half of the owner's request — ghost
pieces placed by intelligence, made solid on contact — is DEFERRED to intel
P1/P2 (owner ruling 9 below); this spec leaves the interface for it.

## 0. The owner's request and rulings

The request (2026-10-01): a hard-core military map after Palantir Gotham;
clicking a unit shows a moving line drawing performing tactical actions and
breaks the unit down — arms and armour, morale, supply, terrain; enemy
pieces placed by our intelligence, translucent, standing for what we
BELIEVE of the enemy's size and place, made solid like ours only when our
army truly meets them; both sides static wargame pieces ON BASES, set down
by hand and moved by pushing them with a rake.

The rulings, in the order they were asked:

1. **A physical operations room** — a 3D room with the map table at its
   middle (not a separate vector board, not a mode of the 3D map).
2. **Medieval language throughout** — Gotham lends the DENSITY and
   ORGANISATION of information, never its look: ink, vellum, brass, wax
   crayon; no cold glow. This agrees with intel §5.9 (confidence is ink
   weight, age is yellowing, no bars or radars for confidence).
3. **The table top is vellum over a relief**, drawn in ink: contours, grid,
   roads, rivers, borders.
4. **One theatre at a time** — sheets are swapped, not one long table.
5. **A numbered map series** — the world cut into equal sheets at one
   scale, an index chart on the wall, places written "III · C7".
6. **The rake is two hands.** The PLAYER's rake gives orders (an ink arrow
   and an order pennant; the piece does not move). The PLOTTER's rake moves
   a piece to where we KNOW it stands. A piece never lies.
7. **The dossier is an open folio** over the room: the moving ink figure
   and the exploded view on the left page, the data on the right.
8. **Single-figure drill**: the chief arm's figure plays the current
   order's action, drill tabs play the others, a small drawing per arm, a
   dotted formation diagram.
9. **Enemies wait for P1/P2.** This build shows the crown's own regiments
   only; ghosts and contact come with the raid host.
10. **Painted tin miniatures** — the same `.glb` figures under a
    painted-miniature shader, 9 / 6 / 3 of them on one base.

The 2026-09-27 ruling "撤除所有底座" stands for the 3D MAP's walking
pieces; bases exist only on the war-room table.

## 1. The room and the camera

- `WarRoomScreen` (`scripts/ui/`) lies exactly over the map panel, as
  `LedgerScreen` does (`GameRoot` fits it to the map's rect; the 3D map
  stops rendering under it). The left column keeps its role (invariant 10):
  clicking a piece puts the regiment's card there; the right column (the
  council) is untouched.
- `scripts/war_room/` never reads the `Game` autoload, like `scripts/map3d/`
  and `scripts/ledger3d/`; the screen hands it data and runs its orders.
  The test that scans `scripts/map3d/*.gd` for `Game.` covers this folder
  too.
- **The room**: a stone chamber seen from a standing officer's place; the
  table fills about seven tenths of the frame. At its edges: iron
  candlesticks at the table's corners, the sheet index chart on the far
  wall (clickable, §2), the rake leaning on the table's edge, cold light
  from a window. Warm candle light and the cool window light. No people:
  the plotter appears only as his rake.
- **The camera** opens oblique over the whole sheet. The wheel and a
  trackpad pinch lean in about the pointer, close enough to read a base's
  brass plate; a two-finger or middle drag pans within the sheet; yaw is
  held within `war_cam_yaw_max_deg` 30 either side, so the room is built
  only where it can be seen. Every value `balance.csv` `war_cam_*`.
- **Time** runs as on every screen of play: the top bar's clock, Space
  pauses and resumes. The 2026-09-27 ruling holds: a march is ordered only
  on a PAUSED clock. The plotter updates the pieces once a day.
- **Performance**: its own SubViewport at window px × the tier's
  `render_scale` (`Map3DQuality`), never a SubViewportContainer; a war-room
  row in `tools/map3d/bench.gd` (or a sibling bench) against each tier's
  `bench_budget_ms`.

## 2. The sheets and the table

**The series** (all generated from the pack; no pack is named; values
`balance.csv` `war_*`):
- Sheets of `war_sheet_w_km` 640 × `war_sheet_h_km` 465 overlapping their
  neighbours by `war_sheet_overlap_km` 40 — on beria (2560 × 929 km) a
  4 × 2 series. A sheet with no land is skipped.
- Numbered in Roman numerals row by row from the north-west; named after
  the KINGDOM with the most land on it by the starting border ("Sheet III ·
  <kingdom label>").
- Grid squares of `war_grid_km` 40: columns lettered A.., rows numbered
  1..; a place is written `III · C7`, and the folio, missives and pennants
  use that form.
- Sheet measurements are in the pack's own measure (`map_info.csv`
  `distance_scale` / `distance_unit`), like the 3D map's scale bar.

**The table**:
- A sheet lies on a table about 1.4 × 1.0 m (`war_table_w_m`). The relief
  mesh samples the pack's height field over the sheet at about 256 × 186
  (`war_relief_grid`), exaggerated `war_relief_exaggeration` so the hills
  read on a table. The sea is flat, hatched in ink along the coast.
- **In the shader** (`war_table.gdshader`, sharp at every zoom): contours
  every `war_contour_m` 200 m, every fifth heavier; the grid; the paper's
  yellowing and fold creases.
- **Drawn once into a texture when a sheet is laid** (`war_sheet_texture_px`
  4096, cached by the live ownership signature): roads solid, trails
  dashed, rivers in faded blue ink, kingdom borders dot-dash with a pale
  watercolour band of the kingdom's colour inside (`MapPalette.color_of`),
  province seams fine dashes, towns as ink rings sized by tier with
  hand-lettered names, peaks ▲ with heights (`Elevation.landmarks`). The
  borders are `MapOwnership`'s live outlines, so a conquest redraws the
  sheet the next time it is laid.
- The margin carries the sheet's title, a scale bar on the 1-2-5 ladder
  (`MapGeometry.nice_step`), a compass rose and a legend.

**Changing sheets**: a click on the wall's index chart (the island's outline
with every sheet's frame) or on a small ink arrow at a sheet's edge
("→ IV") rolls the sheet up and lays the other, about 0.6 s
(`war_sheet_swap_s`). The room opens on the sheet holding the home
province (`MapManors.home_province`); the last sheet seen is remembered for
the session, not saved. A regiment on another sheet is listed in the margin
("3rd Regiment → IV"), and a click lays that sheet.

## 3. The pieces and the rake

**A piece** stands for each land regiment of the crown. A fleet has no
model: it is a flat tin token engraved with waves.
- **The base**: `war_piece_base_mm` 40 × 40 mm (about 18 km of the sheet),
  wood painted the realm's colour, a brass plate at the front with the
  regiment's label, the house's arms on its side (`HouseArms`).
- **The figures**: the `.glb` of the regiment's largest arm among
  infantry, archers and cavalry (`army_art.csv` `model`), 9 / 6 / 3 of them
  by `army_formations.csv` (`ArmySystem.fit_permille`), laid out by
  `Map3DFormation`.
- **The pose is frozen, by order**: a marching regiment frozen mid-stride,
  a garrison behind its raised shield, standby at ease — a frame sampled
  from the clip (`war_pose_frame_*`), never played. One glance says what a
  regiment is doing.
- **The finish**: `tin_miniature.gdshader` on the same model — the albedo
  posterised into flat painted colours, raised edges worn to grey tin, a
  thin varnish gloss.
- **Seated** level on the highest relief under its four corners: a thing
  set down by hand does not tilt.
- **The tag**: a paper slip on a pin beside it, inked "6,448 · stores 3 mo"
  — ink and yellowing, no coloured bars.

**Where a piece stands**: only `WarRoom.believed_position(repo, state,
reg)`. Today it is `ArmySystem.position_of`; intel P2 makes it the last
ARRIVED report's place (§5.5 there) without touching the table. The plotter
checks once a day: a piece that has moved is pushed there by his rake over
`war_plot_push_s` 0.5 s, facing the way it is pushed.

**A click** draws a chalk ring round the base, puts the regiment's card in
the left column and opens the folio (§4).

**The player's rake** (on a paused clock only):
1. Press on a piece and drag: the rake appears at the pointer; the piece
   does NOT move. An ink arrow runs from the piece to the pointer, reading
   the distance and the days at the regiment's own pace in its middle (the
   same maths as `MapRuler` and `Map3DHudRuler._draw_aim`).
2. Release: **COMMIT / CANCEL** — the same `ArmyOrderMenu` and
   `data/army_route_orders.csv` as the 3D map. Only COMMIT runs
   `ARMY_MARCH` through `Game.try_execute` (the screen does; the view only
   signals).
3. A committed order plants a **pennant** at the destination, its slip
   dated, and the arrow turns dashed. The slip reads "courier riding" until
   the courier's receipt (`MissiveLog`, A's deliveries), then "order
   received"; the pennant is struck when the piece reaches it.
4. On a paused clock a click on a pennant offers Edit route… / Cancel march
   (`ARMY_GARRISON`), as the 3D map's route end ring does.
5. While the clock runs a drag does nothing and the tooltip gives
   `army_route_orders.csv`'s reason.
6. A destination must lie on the laid sheet; the overlap covers a border
   march.

## 4. The folio

- A two-page manuscript opens centred over the room, the table dimmed
  behind it; ×, Escape or a click outside closes it. The left column's card
  stays.
- **The left page — the ink figure**: a SubViewport holding the chief
  arm's `.glb` under `ink_drawing.gdshader` (an inverted-hull outline,
  screen-space hatching by light, sepia ink on vellum), looping the clip of
  the regiment's current order.
  - **Drill tabs** from `data/war_drills.csv` (key, clip, label, arms);
    a row whose clip the model lacks is not shown (`Map3DUnits.clip_named`),
    so a clip added later in Blender (the infantry's ATTACK) appears by
    itself.
  - **The arms**: a small still ink drawing per arm in the regiment with
    its headcount; artillery, which has no model, draws a glyph. A click
    puts that arm's figure on the page.
  - **The formation**: 9 / 6 / 3 ink dots, the front marked.
  - **Take apart**: a button beside the tabs swaps the figure for an
    EXPLODED view — helmet, plate, shield, spear moving outward over
    `war_explode_s`, each on a leader line with its name and note
    (`data/war_equipment.csv`). The parts come from a STATIC per-arm model
    exported from Blender, `assets/3D/units/<arm>/<arm>_parts.glb`, its
    objects named as the CSV names them; the runtime only moves them. (The
    game's skinned mesh does not give a shader its bone indices, so it
    cannot be taken apart at runtime.)
- **The right page — the data**, sections from
  `data/war_folio_sections.csv`, headers in rubric small capitals, the body
  in the reading face (`UiPalette.role_font`), whole figures grouped by
  thousands (`UiPalette.format_int`):

  | Section | Rows |
  |---|---|
  | Composition | headcount by arm; fit and wounded; formation tier |
  | Arms | each arm's weapon, armour and shield (`war_equipment.csv`); matchups (`army_matchups.csv`: "good against … / wary of …") |
  | Morale | value and word (`army_morale_words.csv`), the mark and why (stores, garrison bonus — `ArmySystem.morale_mark`), the month's drift |
  | Supply | months in hand, the daily bite (`ArmySystem.day_bite`), the line (km, % lost, from which town — `SupplySystem.plan`), the marshal governing it and his factors line (`Governance.factors`) |
  | Ground | grid reference, biome, height, tier, supply use × (`army_height_supply.csv`), the terrain's effect on each arm (`army_terrain.csv`), today's weather (`Weather`) |
  | March | pace km/day (`ArmySystem.speed_km_per_day`), readiness and its four parts, the order, destination and arrival |

  Training stays hidden: its grade word only (`army_training_grades.csv`).
  Every figure passes through `Intel` — exact for the crown's own today, so
  P2's blur reaches the folio unchanged. No history curves: nothing stores
  history.

## 5. Components

**Pure** (`RefCounted`, headless, GUT):
- `WarSheets` — the series: sheets, overlap, sea sheets skipped, names,
  neighbours, `sheet_of(px)`, `grid_ref(px)` → `"III · C7"`.
- `WarRoom` — `believed_position(repo, state, reg)` (today `position_of`)
  and `believed_hosts(repo, state)` (today `[]`: **the interface P2 fills**
  with ghost hosts — position, strength range, source, age — which the
  table will draw translucent over an ink ring of uncertainty and make
  solid on contact).
- `WarFolio` — `sections(repo, state, reg)`: every section's rows as
  `{label, text}`, through `Intel`.

**The view** (`scripts/war_room/`, no `Game`): `war_room_view.gd` the
coordinator over the table (relief + `war_table.gdshader`), the sheet ink
painter, the pieces (`tin_miniature.gdshader`), the rakes and arrows, the
camera, and the folio's figure (`ink_drawing.gdshader`). The room is an
AUTHORED scene, `scenes/war_room/war_room.tscn` (memory: scenes over
code-built nodes), its look in `scenes/war_room/materials/*.tres` holding
shaders and textures only — every tuned number is data, bound at load.

**The screen**: `scripts/ui/war_room_screen.gd` + its scene; WAR ROOM leaves
`BottomBar.PLACEHOLDER_TABS` and `info_screen.gd`'s placeholder case goes.
A headless run cannot render 3D, so `tests/pre_run.gd` holds the room's 3D
scene unloaded (`war_room_3d` 0), as it does `map3d_default`.

**Data**: `balance.csv` `war_*`; `data/war_palette.csv` (ink, rubric,
paper, sea ink, river ink, chalk); `data/war_drills.csv`;
`data/war_equipment.csv`; `data/war_folio_sections.csv`.

**Shots**: `tools/snapshot_screen.gd --war-room [--war-sheet N]
[--war-piece CODE] [--war-folio DRILL|explode] [--war-drag fx,fy]`, every
step a real input (memory: verify UI through real input).

## 6. When something is missing

- The room's art missing: the screen shows a notice naming what is absent.
- A `_parts.glb` missing: no Take-apart button.
- A drill's clip missing: no tab.
- A regiment on no sheet (at sea, off the series): drawn on the nearest
  sheet.
- An empty sheet (no regiment of ours): the table still lays; the margin
  says so.

## 7. Tests

- `WarSheets`: sheet count and overlap on a hand-sized fixture and on the
  default pack; a sea-only sheet skipped; `grid_ref` against hand-computed
  places; names from the starting border.
- `WarRoom.believed_position` equals `ArmySystem.position_of` today;
  `believed_hosts` is empty.
- `WarFolio.sections` for a fixture regiment against hand-computed rows.
- Drill tabs filtered by the clips a model has.
- Data integrity: every `war_equipment.csv` arm exists, every
  `war_drills.csv` clip names a known clip, every section key resolves.
- The rake through real input: a drag and COMMIT on a paused clock runs
  `ARMY_MARCH`; a drag on a running clock is refused with the reason; the
  pennant's slip turns on the receipt.
- WAR ROOM is no longer a placeholder; `scripts/war_room/` holds no `Game.`.

## 8. Art (each piece shown to the owner before it is installed)

**The look is Qwen-Image-2512's** (owner 2026-10-01, from a Z-Image /
Qwen pair of concept pictures of the room and the folio): the room after
Qwen's — the vellum RAISED over the relief, red-painted bases with brass
plates and pinned paper tags standing ON the map, a planted pennant, the
rake at the table's edge, a wall index chart of numbered sheets; the folio
after Qwen's left page — the exploded parts drawn apart in a row, the
dotted formation and the drill tabs beneath — with a whole standing figure
rather than a bust, and no face (a closed helm). Later reference passes
run on Qwen only unless the owner asks again; their prompts carry what the
concepts lacked: ONE sheet on the table, not the whole island, and dense
ink contours and a lettered grid on the relief.

- The room, table, candlesticks, rake and wall chart: modelled in the
  OWNER's Blender through the MCP (memory: work in the owner's Blender),
  Poly Haven CC0 textures; reference pictures on Qwen-Image-2512 (above). Meshes committed
  under `assets/3D/war_room/`, sources in its `model_wip/`, so a fresh clone
  shows the room with no Blender.
- The per-arm `_parts.glb`: split in Blender from the Tripo sources of the
  infantry and the cavalry.

## 9. Order of work

1. Sheets, table, ink (`WarSheets`, relief, both ink layers, margin).
2. Room, camera, screen (the tab, the overlay, a stand-in room).
3. Tin pieces and the plotter's rake.
4. The player's rake: arrow, COMMIT, pennant.
5. The folio's right page (`WarFolio`).
6. The ink figure and the drill tabs.
7. Take apart (`_parts.glb`).
8. The room's final art.

## 10. Out of scope

Enemy ghosts and contact (intel P1/P2, through `WarRoom.believed_hosts`);
battle (LEDGER M4); the debrief wall (intel P3); sound.

## 11. Documents that change when this lands

`CLAUDE.md` (the WAR ROOM entry, the thematic tabs paragraph, the layout's
`scripts/war_room/`); `2026-09-28-intelligence-layer-alignment.md` §5.9 (the
WAR ROOM is a physical plotting table; ghosts are translucent tin on it).
