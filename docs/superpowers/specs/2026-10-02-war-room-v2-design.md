# WAR ROOM v2 — a room you can turn in, sheets by the graticule, orders sealed and sent — design

Status: designed with the owner 2026-10-02 (brainstorm, every section
approved). Builds on `2026-10-01-war-room-design.md` (the plotting room as
merged, 939ac32); where the two disagree this one wins, and §8 lists what of
the old spec it replaces.

## 0. The owner's request and rulings

The request (2026-10-02), ten points:

1. The room is a 3D scene that TURNS, the way the main map turns.
2. Import `mapCoordinates` from the Azgaar JSON; replace the index chart's
   sheets with smaller cells cut by the coordinates; choosing a cell tosses
   a 3D war piece onto it, casually.
3. Lay the map at a larger scale — a smaller area over the same table, so
   more detail and more marks show.
4. The candles are ugly: remodel them with more detail, an animated flame,
   light and shadow that waver.
5. A rake on each side of the table.
6. The room is too bare: furniture round the walls — tables, chairs,
   barrels, weapon racks, banners, armour dropped on the floor, bottles,
   bandages, rubbish.
7. Entering the WAR ROOM rolls the left column's report up and the room
   widens over where the column was.
8. A DEPLOY button bottom right (a sealed secret scroll, animated): the
   meeting's resolutions go out as couriers to the regiments.
9. A tool box on the table: pens, a ruler, pins.
10. Beside the table, a board on a wooden easel — the Missive board, its
    material and shape the Missive screen's board, notes pinned on it; the
    player can bring the view round to face it.

The rulings, in the order they were asked:

1. **Four sub-projects, in order A → B → C → D**, one spec (this one):
   A camera and layout, B graticule and scale, C Deploy, D the room's art.
   The art goes last: it depends on the angles A opens and on the owner's
   Blender and picks.
2. **The turn is the main map's** (A-1): free 360° yaw, pitch by distance,
   the same mouse and keys.
3. **The left column rolls up and unrolls only to show a card** (A-2,
   option A): invariant 10 keeps; the room is full width most of the time.
4. **The board is reached by a click that flies the camera to it** (A-3,
   option A); its notes are the REAL missives and a click on one opens it on
   the Missive screen.
5. **The board's face is the Missive screen itself**, rendered into a
   SubViewport (approach 1), not rebuilt in 3D: one layout, never two.
6. **Sheets are graticule cells of `war_sheet_deg` = 20°** (B-1), a balance
   key. Every whole-degree cell is 7.1 : 5.16 ≈ 1.376 : 1 on this pack — the
   table's 1.4 : 1.
7. **The tossed war piece's look is chosen from reference art** (B-2,
   option D) in sub-project D; B uses a stand-in.
8. **All four kinds of detail** (B-3): terrain, settlements and manors,
   roads and water, military intelligence.
9. **War-room orders are DRAFTS until Deploy** (C-1, option A), each then
   run as the real order with its own courier and fee.
10. **Leaving the room with drafts ASKS** (C-2, option B): Deploy / Discard
    / Keep; kept drafts are state and saved.
11. **Deploy unrolls the resolutions for review before the seal** (C-3,
    option A).
12. **The art is MIXED by source** (D-1, option A): Poly Haven CC0 scans
    for generic props, Tripo (the owner's paid plan) for medieval specifics,
    hand-modelled in the owner's Blender for simple exact shapes; every
    reference on Z-Image AND Qwen side by side for the owner to pick.
13. **The two rakes MOVE** (D-2, option A): the player's rake follows a
    raking order, the plotter's pushes a piece to where we know it stands.

## 1. A — the camera and the layout

### 1.1 The turn (ruling 2)

- `WarCamera` loses its yaw clamp: `yaw_deg` wraps through 360°.
  `war_cam_yaw_max_deg` goes.
- Pitch follows distance as on the 3D map (`Map3DGeometry.pitch_for`'s
  shape, not its numbers): `war_cam_pitch_near_deg` close in (more oblique),
  `war_cam_pitch_far_deg` stepped back (more overhead); `war_cam_pitch_deg`
  goes.
- Input, matching `Map3DInput`:
  - right DRAG turns (`war_cam_turn_deg_per_px`); a right CLICK (under
    `CLICK_SLOP`) is still the piece's order menu;
  - left DRAG from empty table pans; left drag from a piece is still the rake
    (`war_rake_min_px`); a left click still picks;
  - wheel and trackpad pinch zoom about the pointer; two-finger drag and the
    middle button pan; WASD / arrows pan the view (`war_key_pan_speed`).
- The compass rose on the KEY slip (`WarMarginKey`) already turns with the
  yaw; a click on it eases the yaw back to 0 (the sheet's foot, the
  officer's default) over `war_cam_north_s`.
- The target stays clamped to the table. The camera is kept inside the room:
  where the orbit would put it beyond a wall less `war_cam_wall_clear_m`,
  the distance is shortened (`WarCamera.clear_distance`, pure).

### 1.2 The left column rolls up (ruling 3)

- On open, the steward's report (the left column) ROLLS UP over
  `war_report_roll_s`: its visible height shrinks upward with a drawn roller
  at its lower edge, until only the roller hangs at the column's top.
  `WarRoomScreen`'s rect grows left over the column's place at the same
  time: the room runs from the column's left edge to the map's right edge;
  the council column is untouched. `GameRoot._fit_war_room` takes the wide
  rect while the room is open.
- A picked piece UNROLLS the roller just tall enough for the regiment's card
  (`WarTable.fit_report`'s measure), lying over the room's left; the margin
  slip (regiments on other sheets) steps right while it is down. Clearing
  the pick or closing the folio rolls it back up.
- Closing the room narrows it and unrolls the report as it was.
- Under the leather chrome (`ui_war_table` 0) there is no paper: the column
  slides up and fades instead; everything else is the same.
- During the animation the room's SubViewport keeps its size and the
  TextureRect stretches; the viewport is resized once, when the animation
  ends.

### 1.3 The board view (rulings 4, 5)

- **The board**: a wooden easel beside the table (D's model; A a plain
  frame stand-in) holding a panel whose texture is a SubViewport rendering
  `MissiveScreen` in a new BOARD-ONLY mode (desk hidden: the wood, the
  carved frame, the four columns of notes, the plaques), from the live
  `MissiveLog`. It renders only while the board is in view, and again when
  a missive arrives.
- **Fly there**: from the table, hovering the board shows "Study the
  board"; a click flies the camera over `war_board_fly_s` to a fixed pose
  square in front of it (`WarCamera.board_pose`, pure). There the wheel
  leans between `war_board_min_m` and `war_board_max_m` and a left drag pans
  in the board's plane; no turn.
- **A note**: the ray's hit on the panel becomes a UV, the UV a point in
  the SubViewport, and the click is pushed into it as real input; the note
  clicked opens the Missive screen with that letter selected
  (`MissiveScreen.select`). Closing the Missive screen returns to the room
  in the board view.
- **Back**: Escape or "Back to the table" flies the camera back to the pose
  it left.
- The clock runs while the board is studied, as in the room.

## 2. B — the graticule and the scale

### 2.1 The coordinates (ruling 6)

- `tools/import_azgaar.gd` writes `mapCoordinates` into `map_info.csv`:
  `lat_total`, `lat_n`, `lat_s`, `lon_total`, `lon_w`, `lon_e`. Beria's
  `map_info.csv` gains the six rows by hand (beria: 180 / 90 / -90 / 360 /
  -180 / 180); no re-import.
- `MapCoords` (pure, `scripts/engine/`): pack px ↔ (lat, lon) and the
  graticule cell of a point. A pack without the rows falls back to the whole
  globe over the map, and `DataRepository` warns once.

### 2.2 The sheets

- `WarSheets` cuts the map by `war_sheet_deg` (20°: beria 18 × 9, 76 cells
  with land). Only cells with land are sheets; a sea cell is drawn faint on
  the index chart and cannot be chosen.
- A sheet's id is its column letter and row number on the index grid from
  the north-west (`D4`); its title the kingdom with the most land on it.
  `war_sheet_w_km`, `_h_km` and `_overlap_km` go.
- The graticule is the sheet's NEAT LINE. Outside it a collar of
  `war_sheet_collar_km` shows the neighbouring ground in faint ink, which
  does the old overlap's work: a march over the edge stays in view. The ink
  arrows at the edges still lay the neighbouring cell.
- The grid inside a sheet is every `war_grid_deg` (2°: ~14 × 10 km),
  lettered and numbered within the sheet; a place reads
  `D4 · c7 · 23°N 51°E`. `war_grid_km` goes.

### 2.3 The index chart and the toss (ruling 7)

- The chart on the table's north band becomes the 18 × 9 graticule over the
  island: sea cells faint, land cells chosen by a click.
- A click TOSSES the theatre marker: thrown from the camera's side in an
  arc, tumbling, landing at a random point inside the cell, bouncing once or
  twice and coming to stand; then the laid sheet rolls up and the new one is
  laid. The marker stays on that cell; the next choice picks it up and
  tosses it again.
- `WarToss` (pure, `scripts/war_room/`): the arc, the spin, the bounces,
  from a start pose, a landing point and a seed (`war_toss_*`), sampled by
  time. Presentation only — never saved, never touching `GameState.rng`; its
  seed is the presentation's own.
- The marker's look comes from D (ruling 7); until then a plain turned
  piece in the war palette stands in.

### 2.4 More detail (ruling 8)

The ink is drawn at the sheet's own scale; every mark has its
`war_ink_*` size and palette row.

- **Terrain**: the relief comes from the built Terrain3D heightmap (50 m a
  pack px) sampled through a `height_fn` the SCREEN hands the view (from
  `Map3DWorldCache`; `scripts/war_room/` still never reads `Game`); without
  a built world, `world_relief.png` as today. Contours at an interval scaled
  to the sheet (`war_contour_m`). Peaks and hollows (`Elevation.landmarks`)
  marked ▲ / ▽ with their metres. Woods (the bake's `woods.png`) as inked
  tree stipple.
- **Settlements and manors**: every settlement its tier's symbol and its
  name; walls drawn round a walled town, an anchor at a port; manor
  boundaries in a fine dashed line, manor names.
- **Roads and water**: roads and trails in two weights; bridges and fords
  marked; rivers from source to mouth thickening by discharge, named
  (`rivers.csv` `label`).
- **Intelligence** — only what we KNOW, through `Intel`: each supply line
  dashed from depot to regiment, fading with its loss; couriers on the road
  and the road ahead of them; this spell's weather marks; a spy report as a
  dashed ring of its estimate at its point, its source and date beside it.
- **Two ink layers**: the base sheet, cached by (sheet, ownership
  signature) as today; the intelligence on its own transparent texture,
  redrawn once a day (or on an order), never the base.

### 2.5 Cost

Sampling the heights for a sheet (~100–200 ms) is hidden in the
`war_sheet_swap_s` roll. `tools/war_room/bench.tscn` is re-run per tier at
each step that adds geometry or ink.

## 3. C — Deploy

### 3.1 Drafts (ruling 9)

- In the room, COMMIT no longer runs `ARMY_MARCH`: it plants a DRAFT — a
  pennant drawn translucent, its line in pencil, its slip "draft". No fee,
  no courier. A draft can be re-aimed (Edit route…) or withdrawn (Cancel
  march); a new draft for a regiment replaces its old one.
- Drafts are made only on a paused clock, as the aim is today.
- `GameState.war_drafts`: `{regiment code: {order, dest_x_m, dest_y_m,
  tick, day}}`, saved (`_encode_values` / `_decode_values`).
- An order given to the same regiment on the 3D map voids its draft, and
  the news bar says so.
- The main map's orders are unchanged: they still run at once.

### 3.2 Leaving with drafts (ruling 10)

Any way out of the room — the close button, Escape, another tab, quitting
the game — with drafts standing asks: **Deploy** (opens §3.3), **Discard**
(drafts cleared), **Keep** (they stay in `war_drafts`, saved, and are on the
table next time).

### 3.3 The scroll (ruling 11)

- Bottom right of the room: a rolled scroll tied with a ribbon, greyed when
  there are no drafts.
- A click unrolls it in the middle of the room: "Resolutions of the
  council", one line per draft — regiment → destination, days, the
  courier's fee — and the total; a line the purse cannot meet is red with
  its reason.
- **Seal and send**: wax drips, the crown's seal (`HouseArms`) presses, the
  scroll rolls, is tied and flies off (`EnvelopeFlight`'s manner). Then
  every draft runs through `Game.try_execute` in regiment code order as the
  real `ARMY_MARCH` / `ARMY_GARRISON` (one courier, one fee each); a draft
  refused stays a draft with its reason on its slip; the rest become the
  solid "courier riding" pennants of today.
- **Not yet** rolls it away; the drafts stand.
- Deploy works on a running clock too.

## 4. D — the room's art

Every piece: references on Z-Image and Qwen-Image-2512 side by side, the
owner picks, then modelled; in the owner's open Blender through the MCP,
never headless; to a game budget (`3d-model-build-up` §7); installed as
`assets/3D/war_room/<name>/<name>.glb`, its source and licence in the
README; sources in its `model_wip/`. After each batch: visual-review shots
and a bench run.

| piece | source | notes |
|---|---|---|
| candlesticks ×4 | Tripo | wrought iron, drips, a heap of tallow, wick, rust |
| candle flame | code | `candle_flame.gdshader`: a camera-facing card per candle, teardrop outer flame, blue core, noise that twists and stretches it, each candle its own phase |
| rakes ×2 | hand | left and right of the table |
| side tables, chairs, barrels, crates, bottles | Poly Haven CC0 | along the walls; bottles on the floor |
| weapon rack, armour on the floor, banners (the crown's arms) | Tripo | tall things only against the walls |
| bandages, scraps, rubbish | hand / Poly Haven | low, on the floor |
| tool box | Tripo + hand | an open wooden box: quills, an ink pot, a brass ruler, dividers, a jar of pins; on a corner of the table off the sheet |
| board easel | hand | wooden; holds §1.3's panel |
| theatre marker | Tripo or hand, by the owner's pick | §2.3 |

- **Candle light that wavers**: each candlestick's light varies its energy
  and colour by noise and shifts its position by millimetres, so shadows
  sway — most in the key candle's (`war_candle_flicker_*`); shadow counts
  per tier stay `graphics_quality.csv`'s.
- **The rakes move** (ruling 13): at rest each leans against its side of
  the table. A raking order slides the nearer rake onto the table, its head
  following the pointer, and back on COMMIT / CANCEL. The plotter's daily
  push uses the other rake, for pieces in view only, one after another,
  skipped past `war_plot_rake_max` pieces. `war_rake_*`; presentation only.
- **Nothing hides the table**: tall pieces stand only at the walls, low
  ones under the table top, so no turn of the camera puts furniture between
  it and the sheet.

## 5. Components

| unit | where | what |
|---|---|---|
| `MapCoords` | `scripts/engine/` | pack px ↔ lat/lon, graticule cells (pure) |
| `WarSheets` | `scripts/engine/` | graticule sheets, ids, places (rewritten) |
| `WarCamera` | `scripts/war_room/` | free yaw, pitch by distance, wall clearance, board pose (pure) |
| `WarRoomGestures` | `scripts/war_room/` | the main map's mouse and keys |
| `WarToss` | `scripts/war_room/` | the marker's flight (pure) |
| `WarIndexChart` | `scripts/war_room/` | the graticule chart and its pick |
| `WarIntelInk` | `scripts/war_room/` | the intelligence layer's drawing |
| `WarBoard` | `scripts/war_room/` | the easel's panel, its SubViewport and click forwarding |
| `WarRakes` | `scripts/war_room/` | the two rakes' motion |
| `WarCandles` | `scripts/war_room/` | flicker; replaces `WarRoomLights`' static setup |
| `WarDrafts` | `scripts/engine/` | drafts in state: plant, replace, void, list (pure) |
| `WarDeployScroll` | `scripts/ui/` | the scroll, the review, the seal and send |
| `WarReportRoll` | `scripts/ui/war_table/` | the column's roll and unroll |
| `MissiveScreen` | `scripts/ui/` | gains a board-only mode |

`scripts/war_room/` still never reads `Game` (the scan test covers it).

## 6. When something is missing

- No `mapCoordinates` rows: the whole globe over the map, a warning once.
- No built world: the relief from `world_relief.png`.
- No `woods.png`: no tree stipple.
- No art for a D piece: the scene keeps today's piece, or none.
- No missives: the board shows its empty columns.

## 7. Tests

- GUT, hand-computed values: `MapCoords` round trips and cells; `WarSheets`
  on beria (18 × 9, 76 sheets, ids, a place's text); `WarCamera` wrap,
  pitch at both ends, wall clearance, board pose; `WarToss` lands inside its
  cell and comes to rest; `WarDrafts` plant / replace / void, save round
  trip; Deploy runs each draft once, in code order, and a refused one stays.
- `snapshot_screen.gd`, by real input: `--war-turn DEG`, `--war-cell D4`
  (the toss), `--war-board`, `--war-board-click fx,fy`, `--war-deploy
  [review|seal]`, `--war-leave` (the prompt).
- `tools/war_room/bench.tscn` per tier after B and after each D batch.

## 8. What this replaces in the 2026-10-01 spec

- §1 the yaw clamp and fixed pitch; the left column's card is now the
  unrolling roller.
- §2 the 4 × 2 Roman-numbered series, its overlap and the 40 km grid; the
  index chart's frames and numerals.
- §3 COMMIT running `ARMY_MARCH` directly in the room (now a draft); the
  one rake on the right margin.
- §8 the four candlesticks as modelled; Ruling 24's chart on the north band
  stays, redrawn.

## 9. Order of work

A (camera, roll, board view with a stand-in frame) → B (coordinates,
sheets, chart and toss with a stand-in marker, detail) → C (drafts, the
leave prompt, the scroll) → D (art, batch by batch, each shown before it is
installed).

## 10. Out of scope

Enemy ghosts (still intel P2, `WarRoom.believed_hosts`); walking about the
room; drafts on the 3D map; pathfinding.

## 11. Documents that change when this lands

`CLAUDE.md`'s WAR ROOM paragraph; `assets/3D/war_room/README.md`;
`balance.csv` (the keys named above, the retired ones removed);
`tools/NEW_MAP.md` (the coordinates rows).
