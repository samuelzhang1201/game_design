# WAR ROOM scale and hover — the sheet at twice the scale, fine print for the leaning officer, and the ground read under the pointer — design

Status: designed with the owner 2026-10-06/07 (brainstorm, every section
approved). Builds on `2026-10-02-war-room-v2-design.md` (sheets by the
graticule, §2) and `2026-10-06-army-location-and-town-defence-design.md`
(terrain, towns, roads and the ground's pace). Where this spec and v2
disagree, this one wins; §8 lists what it replaces.

## 0. The owner's request and rulings

The request (2026-10-06): the WAR ROOM's map can be magnified further and
show more detail and more data, with a mouse tooltip; look in the map's
JSON for what is worth putting up for battle, the economy and tactics.

The survey of the Azgaar export and the pack tables split the candidates
into three tiers; the owner chose to start with **P1** (this spec):
everything P1 shows is already computed by the engine. P2 (zones and
markers as a tactical layer) and P3 (strategic goods, foraging, trade
flows) are later specs (§7).

What the sample shots showed before the design was settled (real-window
shots at 1.6 / 0.5 / 0.12 m on the home sheet, and a top-down mock of
Axbrigh from the pack's own data):

- At the opening distance an ink texel is ~3 screen px; the ink softens
  from ~0.5 m (~1.0 m on a Retina window) and is ~4× magnified at the
  closest lean, 0.12 m.
- At the closest lean it is **the piece, not the blur, that hides the
  map**: a base (~4.6 km of ground at 20° sheets) fills the screen.
- **The data is sparse close up**: an Azgaar cell is ~22 km, the height
  bake one sample every 400 m. Within 40 km of Axbrigh there are two
  towns, three trails, no woods and gentle ground. Leaning in reveals no
  hidden data; what it can add is fine print and finer contours.

The rulings, in the order they were asked:

1. **The slip reads the ground FOR THE CHOSEN REGIMENT** (option A): with
   a piece chosen it gives that regiment's defend / attack factor there,
   its pace and the days to get there; with none, the ground alone.
2. **The slip shows after a dwell, beside the pointer** (option A); during
   a rake it follows the arrow's tip and reads the destination.
3. **A near-zoom detail patch with fine print** (option A of three: a
   detail patch over the view, not a bigger single texture, not a tile
   quadtree).
4. **Both the larger scale and the patch** (option C, after the sample):
   the sheet first goes to half the ground (`war_sheet_deg` 20 → 10); the
   patch follows only if the shots at the closest lean still show soft
   ink (§2's gate).

## 1. The scale (sub-project 1a, first)

- `war_sheet_deg` 20 → **10**: a sheet is ~71 × 52 km on beria (each
  whole-degree cell 7.1 × 5.16 km), on the same 1.4 m table, so the map
  scale doubles and an ink texel is ~17 m of ground instead of ~35 m. The
  overview from the opening distance shows twice the detail; a piece's
  base (table metres, unchanged) covers half the ground it did.
- **Ids past Z.** The series is 36 × 18 cells on beria; `WarSheets.id_of`
  writes the column as `A…Z, AA…AJ` (spreadsheet style), so `AB12`. The
  lower-case grid reference within a sheet is unchanged.
- **The grid inside a sheet** (`war_grid_deg`) is set at the visual
  review; the default is **1°** (~7 × 5 km squares, 10 × 10 a sheet),
  keeping a place reference about as fine against the sheet as 2° was.
- **The index chart** keeps its size on the table: 36 × 18 cells of
  ~2.2 cm. Its column letters and row numbers are written every second
  cell (`war_chart_label_every`), every cell still a target.
- **Keys that follow the scale**, recalibrated at the visual review, each
  in `balance.csv`: `war_ink_wood_step_km` (the woods are sampled by
  ground distance, so their density on the table would fall to a quarter),
  `war_sea_hatch_reach_m`, `war_sheet_collar_km`. `war_relief_grid` stays
  (already finer than the 400 m bake). `war_ink_*_px` stay (texture px on
  a texture of the same size: the lines keep their size on the table).
- **The margin slip** (regiments on other sheets) lists more sheets; it
  scrolls rather than grows.
- **Unchanged**: the save (drafts are whole metres, not sheet-relative),
  the engine, `WarRoom.believed_position`, the camera's limits
  (`war_cam_min_m` stays 0.12 — leaning closer only enlarges the piece).

## 2. The detail patch (sub-project 1b, gated)

**The gate.** After 1a and 3 have landed, shoot the closest lean (0.12 m)
on a 1920 × 1200 window and on a Retina-scale window. If an ink texel is
not coarser than a screen px there, the patch is NOT built; the fine print
and the near contours (§3) carry the near view alone. Otherwise:

- **`WarDetailInk`** (`scripts/war_room/`, pure `RefCounted`) answers:
  the level for a camera distance (0 none, 1 / 2 / 3 for ×2 / ×4 / ×8,
  thresholds `war_detail_level_m`), the patch's rect in sheet px (the view
  times `war_detail_cover`, snapped to a grid so small pans redraw
  nothing), and whether the patch must be redrawn (the view's centre left
  the patch's inner `war_detail_inner` share, the level changed, or the
  sheet's ownership key — `WarSheetInk.cache_key` — turned).
- **`WarSheetInk.strokes()` takes a window**: a sub-rect and a scale; only
  strokes touching the window are kept, in the patch texture's px, widths
  and lettering scaled by the level so everything keeps its size on the
  table and the patch meets the whole sheet's ink without a seam.
- **A dedicated, resident `%DetailViewport`** of `war_detail_texture_px`
  (2048, ~16 MB) whose `ViewportTexture` the shader samples directly — no
  `get_image` read-back, so a redraw while panning does not stall. It is
  set to `UPDATE_ONCE` only to redraw, at most once a frame, the old patch
  (or the whole sheet's ink) showing meanwhile; it is shrunk to 2 × 2 when
  the room closes.
- **`war_table.gdshader`**: `detail_tex`, `detail_uv` (the patch's rect in
  the table's UV), `detail_on`; inside `detail_uv` the patch replaces the
  ink and the fine print, cross-fading over `war_detail_feather` at its
  edge.

## 3. Fine print

What a leaning officer reads that the overview never shows. Only PUBLIC,
STATIC facts of the map — nothing an intelligence report would have to
tell (that is the slip's, §4, and goes through `Intel`).

1. **A town's second line**: size · works · souls · height —
   `city · citadel · 14,061 souls · 961 m` (`political/burgs.csv` `group`,
   `features`, `population`, `elevation_m`).
2. **Route names** along a route's middle run, turned with it and never
   upside down (`geography/routes.csv` `label`, unused until now).
3. **The minor peaks and hollows**: `Elevation.landmarks` with `lod > 0`,
   which the painter skips today.
4. **Index contour figures** in rubric every `war_fine_contour_label_km`
   along the index contours: a pure `WarSheetInk.contour_figures()` finds
   the crossings on `WarBake`'s heights, the same heights the shader
   contours.
5. **Near contours**: the shader's `contour_m` eases from its 200 m at the
   opening distance to `war_contour_near_m` (50 m) at the closest lean;
   the view writes the interval each frame from the camera's distance.

**How it is drawn.** A second sheet texture, **`fine_tex`**, the ink's
size, painted by `WarInkPainter` in a "fine" mode and cached exactly as
the ink (`WarRoomInk`, the same key, the laid sheet and one more). The
shader fades it in by the camera's distance, from nothing at
`war_fine_far_m` to whole at `war_fine_near_m`, so the overview never shows
fine print as a grey smudge. A fine box that would touch a town's or a
manor's name is left out (the manors' clearance, `war_ink_manor_clear_px`).
With the patch (§2), the patch draws ink and fine print together and
replaces both over its rect. Sizes are `war_fine_*_px` keys; colours are
`war_palette`'s `ink` and `rubric` (no new colours).

Cost: one more texture (~48 MB with mipmaps) and one more draw in the
frame a sheet is laid; the bench counts both (§5).

## 4. The hover slip

### 4.1 The reading (engine, pure)

**`WarGround`** (`scripts/engine/war_ground.gd`), static and read-only:
`reading(repo, state, at: Vector2, code: String) -> Dictionary` gathers the
facts at a pack point, `lines(repo, reading) -> Array` sets them as the
slip's lines (`{text, kind}`), so both are tested headless.

- **The place**: `Intel.place_label` (manor · province · the holder).
- **The ground**: `ArmySystem.terrain_at`; the height by the engine's
  `Elevation` (the figure the fight uses — it can differ from the
  contours' by a few metres, and the fight's figure wins); `road_at`;
  `town_at` with its works and holder.
- **The weather** today: `Weather.at` (the intelligence ink already shows
  the weather over every province on a sheet, so it is not gated).
- **With a regiment chosen** (`code` non-empty):
  - **Defend / attack** as a factor: `ArmySystem.power` is split into
    `power_on(repo, state, code, stance, terrain, works)`, which `power()`
    calls with the regiment's own ground — a pure refactor, `power()`'s
    figures unchanged and locked by a test. The factor is `power_on` here
    over `power_on` on open plains, no works. Works count only in a town
    the regiment's own kingdom holds (`held_town_of`'s rule).
  - **Height**: here less where the regiment stands now, through
    `height_factor` — "60 m below its ground now (×0.98)".
  - **Pace**: the ground's factor (`ground_permille`), km a day
    (`day_march_at`, weather in) and the days to get there
    (`march_days_between` from where it stands).
  - **A fleet** over land: one line, "A fleet cannot go ashore".
- **No foreign force is shown**: a town of ours lists our regiments in
  garrison there; a foreign town says nothing of its garrison. Enemy
  forces on the table are intel P2's (`WarRoom.believed_hosts`).

### 4.2 The slip (presentation)

- **`WarRoomView`** emits `ground_hovered(pack_px, screen_px)` once the
  pointer has rested on open table for `war_hover_delay_s` within
  `war_hover_still_px`, and `hover_cleared` when it moves. It still never
  reads `Game`; **`WarRoomScreen`** asks `WarGround` and hands the lines to
  the slip.
- **The slip** is `scenes/war_room/war_hover_slip.tscn` with
  `scripts/ui/war_hover_slip.gd`: a parchment card whose look is authored
  in the editor (theme label kinds, no code styles), set below and right
  of the pointer and flipped to stay inside the view, `mouse_filter`
  ignore. Its width is `war_hover_width_px`; lines wrap.
- **During a rake** it follows the arrow's tip with no dwell, refreshed at
  most once a frame, and reads the destination; the days line is left out
  (the arrow's reading carries it).
- **No slip** over a piece or a pennant (each has its own card on a
  click), while the camera turns or pans, during a toss or a sheet's
  roll, in board mode, under the folio or an open popup, or while a text
  box has focus.
- It writes nothing: no state, no clock (the room holds the clock anyway),
  no save.

## 5. Tests, performance, review

**GUT** (expected values by hand, before the code):

- `WarSheets` at 10°: the series' size, ids past Z (`AA`), `sheet_of`,
  `grid_ref`, neighbours. Existing tests whose expectations assume 20°
  sheets are brought to the new key.
- `ArmySystem.power_on`: `power()` unchanged across the split; hand cases
  on fixture regiments — archers alone on open hills defend ×1.15 and
  attack ×1.05 (the `army_terrain.csv` row), and a mixed regiment whose
  factor is worked by hand from its arms' bases (each arm's share of the
  power, not of the heads: `_arm_base` differs by arm and month).
- `WarGround.reading` / `lines`: terrain, road, works only in a town of its
  own kingdom, the height wording, the fleet line, no regiment section
  without a choice, never a foreign garrison.
- `WarSheetInk.contour_figures` on a made-up height grid: figures lie on
  their contour and keep their spacing; the fine print's clearance.
- If the patch is built: `WarDetailInk`'s level, rect and redraw rule.
- The isolation scans still pass (`scripts/war_room/` names no `Game.`;
  the engine names no ui class).

**Real input.** `tools/snapshot_screen.gd` gains `--war-hover fx,fy`: real
pointer motion to that share of the view, a wait of `war_hover_delay_s`,
then the moment — the slip and the rake's slip are verified by real-window
shots, never by a harness shortcut.

**Performance.** The war room bench at each tier, before and after: the
opening frame time, the spike of the frame a sheet is laid (the fine
print's extra draw), video memory (+~48 MB; +~16 MB with the patch).
`WarGround.reading` runs once per dwell; its worst case (a
`march_days_between` walked to `army_march_days_cap`) stays under
`war_hover_budget_ms`.

**Visual review** (the `visual-review` skill, real-window shots, an
independent critic, before / after): the 10° sheet at 1.6 / 0.5 / 0.12 m —
ink weight, the woods' density, the sea hatching, the index chart's
lettering; the fine print's fade distances; the slip's look, wrapping and
flip.

## 6. Order of work and documents

1a the scale → 3 fine print → 4 the slip → the gate's shots → 1b the
patch if the gate calls for it. Each step lands on its own.

`scripts/war_room/CLAUDE.md` is brought up to date in "The sheets" and
"Ink" and gains a short "The hover slip" section; every new key carries its
note in `balance.csv`.

New keys: `war_chart_label_every`, `war_contour_near_m`, `war_fine_far_m`,
`war_fine_near_m`, `war_fine_contour_label_km`, `war_fine_*_px`,
`war_hover_delay_s`, `war_hover_still_px`, `war_hover_width_px`,
`war_hover_budget_ms`; with the patch `war_detail_level_m`,
`war_detail_cover`, `war_detail_inner`, `war_detail_texture_px`,
`war_detail_feather`. Changed: `war_sheet_deg`, `war_grid_deg`,
`war_ink_wood_step_km`, `war_sea_hatch_reach_m`, `war_sheet_collar_km`.

## 7. Not in this spec

- **P2, a tactical layer**: `society/zones.csv` (invasion, rebels, plague,
  eruption, avalanche, fault, flood, tsunami, proselytism — imported, read
  by nothing; a starting state or an event's hook, never a permanent mark)
  and `geography/markers.csv` (brigands, pirates, encounters, monsters,
  bridges, battlefields, mines, inns, lighthouses), each inked and read in
  the slip; the cells' unimported `haven` / `harbor` / `conf` (harbours,
  landings, confluences); `political/campaigns.csv` for old battlefields.
- **P3, the economy**: strategic goods by place (`production.csv` with the
  goods' `military` tag), foraging from the markets' food stocks and
  prices, the trade flows (`deals.csv`) summed onto the roads.
- Not wanted at all: the export's own `treasury` / `product` figures (the
  game's economy is `ManorEconomy`), `transports`, `journeys`,
  `measurers`, the biomes' `cost` (the engine's `ground_permille` stands).

## 8. What this replaces

- v2 ruling 6 / §2.2: `war_sheet_deg` = 20° → 10° (beria 18 × 9 → 36 × 18
  cells), ids past Z, the grid's default 2° → 1°.
