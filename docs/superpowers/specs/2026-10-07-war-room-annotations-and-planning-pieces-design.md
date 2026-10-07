# WAR ROOM — supposed enemy pieces and the staff's annotations — design

Status: **approved 2026-10-07, style A (wax crayon)** — the owner: "按推荐做"
(every ruling in §0 as recommended). Written for the owner's items 11 and 15;
the owner answered two questions (below) and approved the rest as listed in §0.
Builds on `2026-10-07-war-room-scale-hover-design.md` (the hover slip,
`WarGround`, `ArmySystem.power_on`, the near-zoom patch) and
`2026-10-06-war-room-wooden-pieces.md` (the carved pieces).

## 0. The request, what the code has today and the recommended rulings

**Item 11** (translated): "In the war room, right-click anywhere on the map →
a 'Place enemy' button, putting an enemy wargame piece there, with a tooltip
showing its figures adjusted by the terrain bonus." **Owner's ruling when
asked**: these are PLANNING pieces (推演用棋子) — the player chooses the arm and
the headcount and places it; the tooltip shows its attack and defence on that
ground with the terrain bonus; it has NO effect on the real enemy; it is SAVED
with the save; it can be dragged and deleted.

**Item 15** (translated): the owner attached a NATO operations overlay — thick
blue curved axis-of-advance arrows with filled heads sweeping out of hatched
blue assembly areas, a red enemy forward line drawn thick with saw-tooth
"teeth" (a fortified line), red unit boxes, a dashed red line, labelled phase
lines (PL ALPHA / BRAVO / CHARLIE), an objective ring "OBJ", small numbered
blue triangles (checkpoints) — and asked to "use that blue-arrow / red-arrow
scheme on the war room's map, and also the defensive front line with the saw
teeth". **Owner's ruling when asked**: ALL HAND-DRAWN — the player gets a set
of annotation tools (blue arrow, red arrow, defensive line, objective circle)
and works the map like a staff officer.

What the code has today:

- **Right-click on open table does nothing**: `WarRoomView._gui_input` turns a
  `WarRoomGestures.RIGHT_CLICK` into `army_menu_requested` /
  `garrison_menu_requested` only when `piece_under` finds a crown piece.
  Right DRAG turns the room; a left drag on open table PANS
  (`WarRoomRake.empty_press`); a left drag from a crown piece is the rake.
- **No foreign force is ever shown** (`WarGround`, CLAUDE.md "The hover slip");
  `WarRoom.believed_hosts` is `[]`, reserved for intel P2's translucent
  believed hosts.
- **Power**: `ArmySystem.power_on(repo, state, code, stance, terrain, works)`
  needs a crown regiment with state (wounded, training, morale, and a hidden
  per-arm monthly float `float_factor`). Strength is hidden: the slip shows
  only FACTORS (×1.15), the folio a grade. **The battle formula is not
  decided** (`ArmySystem.battle_odds` is a placeholder called by its test only).
- **Drafts** are graphite strokes drawn in screen space by `WarHud`; the sheet's
  own layers are textures on the table (`ink_tex`, `fine_tex`, `intel_tex`,
  the near-zoom patch), drawn by `WarInkPainter` through the ink viewport and
  rolled up with the sheet by `WarSheetSwap`.

**Recommended rulings** (each can be overturned on its own):

1. **Two sub-projects, one spec, A then B.** **A — supposed pieces** (item
   11), **B — the staff's annotations** (item 15). They share one saved block
   (`GameState.war_plans`), one writer (`Game`), the new ground menu and the
   pick order. A is small and lands first.
2. **The in-game word is "supposed"** ("a supposed host", tag "supposed ·
   2,000 foot"); the code's word is **plan** (`WarPlans`). "Ghost" stays
   intel P2's word for a believed host.
3. **Plans are the player's paper, nothing more.** No engine rule reads
   `war_plans` (only `WarGround`'s read-only reading of a supposed piece):
   no effect on the real enemy, AI, intel, fights, supply, drafts, the
   resolutions scroll, the clock or the news. Saved whole in the one JSON save,
   in whole metres; they last for the campaign until the player removes them.
4. **A supposed piece is ONE arm and a headcount and a side.** Arms: the four
   land arms (infantry, archers, cavalry, artillery). A mixed host is several
   pieces. **No fleet in this spec**: on water the menu row is disabled with
   its reason ("A supposed host stands on land").
5. **The side** is a foreign kingdom of the pack or **Unknown**. It sets the
   plinth's lacquer and one rule: a supposed host in a town its side holds
   fights from the works, exactly as our regiments do (`WarGround`'s rule).
   Unknown never has works. The form's default is the ground's holder when
   foreign, else the side chosen last this session, else Unknown.
6. **Its quality is assumed, not chosen**: training `war_plan_training`
   (10, what every regiment starts at) and morale `war_plan_morale` (75, a
   fed regiment), the hidden float at 1000 — the planner cannot know it.
   The slip says "assumed recruits". A grade chooser is a later step if wanted.
7. **Its look: the same carved piece of its arm, in PALE BOXWOOD**, on a plinth
   lacquered in the side's colour (Unknown: `plan_unknown`, a sable black), its
   paper tag written in PENCIL. Dark oak stays the crown's real regiments;
   translucent stays intel P2's believed hosts — three finishes, three
   meanings, readable at the opening view (mock A).
8. **The tooltip is the hover slip** — a supposed piece is the one piece the
   slip reads, since it has no card. "Figures adjusted by the terrain" are
   written as **men on this ground**: heads × the ground factor ("Defends as
   2,300 (×1.15 hills)"), never raw power. With a crown regiment chosen it
   adds the height between them and both sides on this ground, side by side
   — **no odds and no verdict while the battle formula is open**.
9. **Click** rings it in chalk and pins its slip; **no card** in the left
   column (the column holds facts; a supposition is not one). **Drag** moves
   it (the plotter's hand, not the rake). **Right-click**: Edit… / Remove.
   **Delete / Backspace** removes the chosen one.
10. **The march only READS supposed pieces**: during a rake, the slip at the
    arrow's tip within `war_plan_contact_km` of a supposed piece adds the
    side-by-side lines. Nothing blocks, warns or alters a draft.
11. **Annotations are hand-drawn only**; nothing is drawn for the player.
    **First cut: four kinds** — the **axis arrow**, the **front line** (with
    teeth), the **objective ring** and the **phase line** (the front's line
    without teeth plus a label: nearly free, and the reference's most
    prominent remaining element). **Second cut**: the hatched **area**
    (assembly area) and numbered **checkpoints**, then labels on arrows.
12. **Three sticks in the cup**: a **woad-blue wax crayon** (ours), a
    **minium-red wax crayon** (theirs — red lead, the scribes' own red) and
    the **sepia pen** (neutral). The colour is chosen apart from the kind, so
    a blue front line (our own defence) or a red arrow (their expected thrust)
    is one pick away. Phase lines and objectives default to the pen.
13. **The finish is wax crayon on parchment (mock A)**, the pigment skipping
    on the paper's tooth, the edge pressed a shade darker; the pen kinds are
    plain sepia ink. Crayon reads from the opening distance and can never be
    mistaken for the survey's own ink. Ink-and-wash (mock B) is the
    alternative: finer, but it reads as part of the printed sheet.
14. **NATO's translation**: an axis arrow is a broad band widening to a filled
    head, its tail notched like a pennon; a fortified line is a thick line
    with saw teeth (palisade stakes) on the side it FACES (drawn on the
    drawer's right, flipped by a menu row); NATO's dashed = expected — any line
    kind takes a **Dashed** toggle; phase lines are a dashed pen line lettered
    at both ends ("Line I", "Line II"… by default); OBJ is a double ring
    lettered in small capitals ("Obj. A"…); red unit boxes are the supposed
    pieces themselves.
15. **The tool roll**: a leather strip at the view's lower left (an authored
    scene, always within reach whatever the lean or the turn — a 3D crayon cup
    on the table can leave the view): **hand · blue · red · pen | arrow ·
    front · ring · phase line | supposed piece · scraper**. Keys `1`–`4` the
    kinds, `Esc` lays the stick down (WASD stays the pan). The ground menu's
    **Draw ›** row picks the same tools. A crayon cup on the table may join the
    room's art later as dressing.
16. **Drawing**: with a stick in hand, a left press-drag-release draws freehand;
    the drag is smoothed to at most `war_plan_points_max` control points and
    drawn as a smooth curve through them; **Shift** draws it straight. The
    objective is a compass: press at the centre, drag out the radius. A phase
    line and an objective ask for their name on release (prefilled). The
    stick STAYS in hand until `Esc` or the hand. While a stick is in hand a left
    drag draws, never pans (the middle button, two fingers and WASD still pan;
    a right drag still turns) and the hover slip is off.
17. **Editing** with the hand: a click on a stroke chooses it — chalk handles
    on its control points; a handle drags a point, the body drags the whole;
    right-click: Name… / Colour › / Dashed / Flip teeth / Remove; Delete
    removes. The **scraper** (vellum was scraped with a knife) removes what it
    is clicked on, a stroke or a supposed piece. **Undo / redo** (Cmd/Ctrl+Z,
    Shift for redo) over this session's plan edits, `war_plan_undo_max` deep,
    not saved.
18. **Stored in pack coordinates, not per sheet**: whole metres
    (`ArmySystem.pack_to_metres`), so a stroke shows on every sheet it crosses,
    collars included. Widths are table millimetres — a crayon's width on the
    table — the same on every sheet (all sheets share one scale).
19. **Strokes are painted INTO a table texture** (`plan_tex`), like the
    intelligence layer, so they lie on the parchment under the candles and roll
    up with the sheet; the near-zoom patch paints them too, so they stay crisp
    leaning in. The stroke being drawn or dragged and a chosen stroke's handles
    are drawn by `WarHud` in screen space until release.
20. **Drafts stay graphite** — an order pencilled is not an idea crayoned — but
    their lines share the annotation's geometry (`WarPlanGeometry`), so the
    multi-waypoint routes being added now bend through their waypoints and end
    in the same head. Whether a draft wears the blue crayon is one palette key
    (`pencil`) for the owner to try later.
21. **Caps**: `war_plan_pieces_max` supposed pieces and `war_plan_strokes_max`
    strokes a campaign; at the cap the form and the tools say so.
22. **Clearing** is per sheet from the ground menu ("Clear supposed pieces on
    D4", "Clear drawings on D4"), each asking once.
23. **The 3D map shows none of it**: plans live in the room.

## 1. A — supposed pieces

### 1.1 State (engine)

- **`GameState.war_plans`**: `{"pieces": {id: piece}, "strokes": {id:
  stroke}, "next_id": int, "rev": int}`, whole numbers and strings only,
  through `_encode_values` / `_decode_values` like `war_drafts`; an old save
  without the key loads empty. `rev` rises on every write (the caches' key).
- **A piece**: `{arm, heads, side, x_m, y_m, facing_deg}` — `side` a kingdom
  code or `"unknown"`; `facing_deg` whole degrees. Ids are `"p<n>"`.
- **`WarPlans`** (`scripts/engine/war_plans.gd`, pure, static):
  `refusal(repo, state, arm, heads, side, at_px) -> String` ("A supposed host
  stands on land", "The table holds N supposed hosts already", an unknown arm
  or side); `place(...) -> String` (the id, "" if refused; heads clamped and
  stepped by `war_plan_heads_*`); `move_piece`, `edit_piece`, `remove(state,
  id) -> bool`, `clear(repo, state, kind, rect) -> int`, `pieces_in(repo,
  state, rect) -> Array`, `at_px(repo, item) -> Vector2`, `bump(state)`.
- **`Game`** is the only writer: `place_plan_piece`, `move_plan_piece`,
  `edit_plan_piece`, `remove_plan`, `clear_plans`, each emitting a new
  **`plans_changed`** signal — not `state_changed`, so a crayon stroke does not
  refresh the council, the 3D map and the margin.

### 1.2 The figures (engine)

- **`ArmySystem.power_of_arms(repo, arms: Dictionary, training: int, morale:
  int, stance, terrain, works, float_code := "", tick := 0) -> int`**: the body
  of `power_on` with heads per arm given, no wounded, and the float at 1000
  when `float_code` is empty. `power_on` calls it with the regiment's fit heads
  and its code — a pure refactor, its figures locked by the existing test.
- **`WarGround.plan_reading(repo, state, piece: Dictionary, code: String) ->
  Dictionary`**: the place, ground, height, road, town and weather at the
  piece (the reading's own facts); its works (only in a town its side holds);
  `defend_f` / `attack_f` = `power_of_arms` here over the same on open plains
  with no works (per mille, as `_factor`); `defend` / `attack` = heads ×
  factor, whole. With a crown regiment chosen (`code`): its label, the height
  between them (`height_factor`), **ours** = its fit heads × its attack
  factor on the supposed piece's ground (no works) × the height factor,
  **theirs** = heads × defend factor × the inverse height factor, and the
  march days there (`march_days_between`). The factor's ratio cancels training,
  morale and wounds, so nothing hidden of ours is shown beyond what the slip
  already gives.
- **`WarGround.plan_lines(repo, r) -> Array`** — the slip's lines (§1.4).

### 1.3 The look (presentation)

- **`WarPlanPieces`** (`scripts/war_room/war_plan_pieces.gd`, a `Node3D`
  `%PlanPieces` beside `%Pieces` in `scenes/war_room/war_room.tscn`): each
  supposed piece is its arm's scene from `GameArt.WAR_PIECES` (artillery the
  trebuchet), scaled to `war_piece_plinth_mm` and seated as `WarPieces` seats
  (its seat helpers made static and shared), turned to `facing_deg`. Rebuilt
  only when its signature (arm, side) changes; moved otherwise.
- **`wood_piece.gdshader`** gains `instance uniform float blank` (0 oak, 1
  boxwood): the albedo is pulled toward `plan_boxwood` keeping the grain's
  light and dark, so every piece of an arm still shares ONE material. The
  lacquer is `MapPalette.color_of(side).darkened(war_base_darken)`, Unknown
  `plan_unknown`.
- **The tag**: the paper slip of `WarPieces._tag`, its words in `pencil`:
  "supposed · 2,000 foot" (the arm's short word — foot, bows, horse, guns —
  as new rows `arm_<arm>` of `data/war_order_words.csv`); shown within
  `war_tag_view_m` like the others.
- **Facing**: placed facing the nearest crown piece on the sheet (none: north);
  a drag turns it to the drag's way.

### 1.4 The slip

`WarRoomView` emits **`plan_hovered(id, screen_px)`** after the same dwell
(`war_hover_delay_s` within `war_hover_still_px`) over a supposed piece;
`WarRoomScreen` fills `%HoverSlip` from `WarGround.plan_lines`. Lines (mock A):

```
SUPPOSED HOST — CORWYN FOOT               (title)
2,000 infantry · assumed recruits
Hills · 412 m · on a trail
Behind the walls of Walbover (theirs)     (only in a town its side holds)
Defends as 2,300 (×1.15 hills)
Attacks as 1,900 (×0.95)
Weather: rain
—
1ST (AXBRIGH) REGIMENT AGAINST IT         (rubric; a crown regiment chosen)
It attacks from 80 m below (×0.96)
Theirs 2,300 · ours 5,950 on this ground
About 6 days' march
```

The CLAUDE.md rule "never a foreign force" stands for REAL forces; a supposed
piece is the player's own paper.

### 1.5 Placing, moving, removing

- **The ground menu**: a right CLICK on open table emits
  **`ground_menu_requested(pack_px, screen_px)`** (the branch that does nothing
  today); on a supposed piece **`plan_menu_requested(id, screen_px)`**. The
  screen opens **`%GroundMenu`**, a `PopupMenu` in `war_room_screen.tscn` in the
  `Orders` menu's theme: *Place a supposed enemy here…* · *Draw ›* (B) · — ·
  *Clear supposed pieces on D4* · *Clear drawings on D4* (B). Not offered while
  a march or a supply pick is aimed (the aim owns the ground), in board mode or
  under the folio. Its rows run deferred after the hide (the PopupMenu trap,
  as `ArmyOrderMenu._after_hide`).
- **The Place form**: `scenes/war_room/war_plan_form.tscn` +
  `scripts/ui/war_plan_form.gd`, the key slip's parchment and label kinds,
  beside the point and kept in the view: the four arms as inked icons
  (`WarInkIcon`), the heads (a spin box stepped by `war_plan_heads_step` and
  quick buttons 500 / 1,000 / 2,000 / 5,000), the side (a list of the foreign
  kingdoms by name and Unknown), and the would-be piece's two figure lines
  read live from `WarGround.plan_reading`; **Place** / **Cancel**, Escape
  cancels. The same form edits a placed piece (Edit…). It emits; the screen
  calls `Game`.
- **The tool roll's piece slot**: a click on the table opens the form there.
- **Drag**: a left press on a supposed piece that moves `war_rake_min_px` lifts
  it: the node follows the pointer (presentation) and turns to the way it
  moves; release on the table → `Game.move_plan_piece`; off the table → it
  goes back. Never the rake, never a pan.
- **Remove**: the menu's Remove, Delete / Backspace on the chosen piece, or the
  scraper.

### 1.6 The pick order (left click and right click)

Edge arrow → pennant → crown piece → supposed piece → a chosen stroke's handle
→ a stroke (with the hand) → index chart → the ground (an armed march's
destination, else the ground menu on a right click). A stick in hand takes the
left press for drawing before everything but the edge arrows and the chart.

## 2. B — the staff's annotations

### 2.1 Data

**`data/war_plan_kinds.csv`** (new): `kind, label, tool_key, gesture, head,
teeth, pen, name_default, cut, notes`.

| kind | gesture | head | teeth | pen | name_default | cut |
|---|---|---|---|---|---|---|
| arrow | path | 1 | 0 | 0 | | 1 |
| front | path | 0 | 1 | 0 | | 1 |
| phase | path | 0 | 0 | 1 | Line {roman} | 1 |
| objective | ring | 0 | 0 | 1 | Obj. {letter} | 1 |
| area | loop | 0 | 0 | 0 | | 2 |
| checkpoint | point | 0 | 0 | 0 | {n} | 2 |

`pen` 1: the kind defaults to the sepia pen and is drawn as ink, not crayon.
A kind whose `cut` is not yet built has no slot.

### 2.2 State

A stroke in `war_plans.strokes`: `{kind, colour ("blue" | "red" | "ink"),
dashed (0/1), flip (0/1), name, pts: [[x_m, y_m], …], r_m}` — `pts` at most
`war_plan_points_max`, `r_m` the objective's radius. Ids `"s<n>"`. `WarPlans`
gains `draw(repo, state, kind, colour, pts_px, r_px, name) -> String`,
`reshape`, `shift`, `restyle`, `strokes_in(repo, state, rect)` (by bounding
box, collars included), each refusing past `war_plan_strokes_max` or with a
name longer than `war_plan_name_chars`. Undo is presentation's: the screen
keeps the before and after of each `Game` call.

### 2.3 Geometry (pure)

**`WarPlanGeometry`** (`scripts/war_room/war_plan_geometry.gd`, static,
headless-tested), in any 2D frame:

- `simplify(points, tolerance)` — Ramer–Douglas–Peucker, then thinned to
  `war_plan_points_max`;
- `curve(ctrl, step)` — a centripetal Catmull-Rom through every control point;
- `arrow(curve, tail_w, neck_w, head_len, head_w) -> {band, head}` — the band
  widening tail→neck, the filled head on the last tangent, the pennon notch;
- `teeth(curve, every, base, height, side) -> Array` — triangles on one side;
- `dashes(curve, dash, gap)`; `hit(curve, at, width) -> float`; `bounds`.

The same geometry draws a draft's multi-waypoint route (ruling 20).

### 2.4 The tools and gestures

**`WarPlanTool`** (`scripts/war_room/war_plan_tool.gd`, `RefCounted`, the
state machine, so `WarRoomView` — already long — only routes events to it):
the stick (`hand`, `blue`, `red`, `ink`), the kind, the stroke in progress
(samples every `war_plan_sample_px` of pointer travel, in pack px), the chosen
stroke and handle. It emits through the view: `plan_drawn(kind, colour, pts,
r)`, `plan_reshaped(id, pts)`, `plan_shifted(id, offset)`; the screen calls
`Game`. A drag shorter than `war_plan_min_len_px` draws nothing.

- **The tool roll** (`scenes/war_room/war_tool_roll.tscn`,
  `scripts/war_room/war_tool_roll.gd`): leather and brass after the leave
  prompt's window, each slot an inked glyph (a `@tool` drawn glyph with
  `@export`ed fields, as `WarMarkGlyph`), the stick and the kind ringed in
  brass; hidden in board mode and under the folio.
- **Cursor**: the stick's own small cursor while in hand.
- **Names**: a phase line or an objective asks for its name in a one-line
  parchment box at the release point, prefilled by `name_default` (the next
  free numeral or letter on the campaign); Enter keeps, Escape keeps the
  default. Focus blocks WASD as every text box does.

### 2.5 Painting

- **`WarPlanInk.strokes(repo, state, sheet, tex_px) -> Dictionary`** (pure,
  `scripts/war_room/`): every stroke whose bounds touch the sheet's rect, in
  texture px, with widths from table mm (`tex_px / (table width mm)`): the
  crayon polygons (arrow band and head, front line and teeth), the pen lines,
  the dashes, the names and their places.
- **`WarInkPainter`** gains a plan mode: crayon polygons are drawn TEXTURED
  with the wax tooth (`assets/2D/war_room/plan/wax_tooth.tres`, a seamless
  noise authored in the editor, UVs in table mm × `war_plan_tooth_scale`) and
  modulated by the colour, the edge stroked again a shade darker; pen strokes
  plain; names in the room's lettering (phase lines italic, objectives small
  capitals).
- **`WarRoomInk.plan_for`** paints `plan_tex` (`war_plan_texture_px`) through
  the ink viewport, cached by `(sheet, war_plans.rev)`, queued behind the sheet
  ink and the intel layer exactly as `_paint_intel` queues; `war_table.gdshader`
  samples `plan_tex` over the intel layer. A plan edit repaints only it.
- **The near-zoom patch** draws the plan strokes in its window too, so a
  crayon line is crisp leaning in.
- **Live**: the stroke being drawn, a dragged stroke or handle, and the chosen
  stroke's chalk handles are `WarHud`'s, at full colour in screen space; on
  release the texture is repainted and the HUD's copy dropped.

### 2.6 With the drafts and the waypoints

The march-waypoints work (another branch, now) gives a draft several bendable
legs. This spec asks of it only that its route be drawn through
`WarPlanGeometry.curve` and end in its `arrow` head, in `pencil`. A draft
stays a draft: an annotation never becomes an order, and a draft is never
drawn into `plan_tex`.

## 3. Data

**`data/war_palette.csv`** gains: `plan_blue` (woad / azurite, ~`#2E4C86`),
`plan_red` (minium, ~`#B02E1C` — warmer than `rubric` and `hazard_ink`),
`plan_boxwood` (~`#E8D2A0`), `plan_unknown` (~`#28241F`). The pen uses `ink`;
handles `chalk`.

**`data/balance.csv`** keys (first draft; set at the visual review):

| key | value | meaning |
|---|---|---|
| `war_plan_pieces_max` | 40 | supposed pieces a campaign |
| `war_plan_heads_min` / `_max` / `_step` / `_default` | 100 / 20000 / 100 / 1000 | the form's headcount |
| `war_plan_training` | 10 | a supposed host's assumed training (every regiment starts at 10) |
| `war_plan_morale` | 75 | its assumed morale (`army_morale_fed`) |
| `war_plan_blank` | 1.0 | boxwood's share on a supposed piece (`wood_piece` `blank`) |
| `war_plan_contact_km` | 3 | a rake's tip this near a supposed piece reads it |
| `war_plan_strokes_max` | 120 | strokes a campaign |
| `war_plan_points_max` | 16 | control points a stroke keeps |
| `war_plan_sample_px` | 4 | pointer travel between samples, design px |
| `war_plan_simplify_px` | 6 | the smoothing's tolerance, design px at the drawing zoom |
| `war_plan_min_len_px` | 24 | a shorter drag draws nothing |
| `war_plan_arrow_tail_mm` / `_neck_mm` | 4 / 8 | the axis band's width at its tail and neck |
| `war_plan_arrow_head_mm` / `_head_w_mm` | 14 / 20 | the head's length and width |
| `war_plan_front_mm` | 2.5 | a front line's crayon width |
| `war_plan_tooth_every_mm` / `_base_mm` / `_h_mm` | 6 / 3.5 / 3 | the teeth |
| `war_plan_pen_mm` | 0.8 | a pen line's width |
| `war_plan_dash_mm` / `_gap_mm` | 5 / 2 | dashes |
| `war_plan_ring_min_mm` | 6 | the smallest objective |
| `war_plan_name_mm` / `war_plan_name_chars` | 5 / 24 | lettering height; a name's length |
| `war_plan_texture_px` | 4096 | `plan_tex`'s width |
| `war_plan_tooth_scale` | 1.6 | wax tooth cells per table mm |
| `war_plan_edge_dark` | 0.78 | the pressed edge's shade |
| `war_plan_handle_px` | 7 | a chalk handle, design px |
| `war_plan_undo_max` | 30 | undo depth, this session |
| `war_plan_area_hatch_mm` / `war_plan_checkpoint_mm` | 3 / 5 | second cut |

## 4. Tests

- **`WarPlans`** by hand: place and refusal (sea, cap, unknown arm or side),
  heads clamped and stepped, move / edit / remove / clear by sheet rect, whole
  metres through the save (`SuiteData.campaign` goes through the save format),
  an old save without the key, `rev` rising; strokes likewise (points cap,
  name length, bounds on two sheets).
- **`ArmySystem.power_of_arms`**: `power_on`'s figures unchanged (the existing
  lock); 2,000 infantry and 2,000 cavalry on hills and in a citadel, worked by
  hand from `army_terrain.csv`, `army_town_defence.csv`, `army_matchups.csv`.
- **`WarGround.plan_reading` / `plan_lines`**: men on this ground by hand;
  works only in its side's town, never for Unknown; the side-by-side lines
  with a regiment chosen and never an odds or a verdict; the reading writes
  nothing.
- **Isolation and determinism**: two campaigns from one seed, one with plans,
  settle 3 months to the same state but for `war_plans`; no engine file but
  `war_plans.gd` / `war_ground.gd` / `game_state.gd` names `war_plans`; the
  existing scans (`scripts/war_room/` names no `Game.`).
- **`WarPlanGeometry`**: the curve passes every control point; RDP keeps the
  ends and drops collinear points; the head ends at the last point on the last
  tangent; tooth count `floor(length / every)`, the flip moves them across;
  hit distances.
- **`WarPlanInk`**: a stroke crossing two sheets appears on both, in each
  one's px; mm → px.
- **Real input** (`tools/snapshot_screen.gd`): `--war-plan-place fx,fy`
  (right click, the menu row, the form), `--war-plan-draw kind,colour,fx,fy;…`
  (a stick from the roll, a real press-drag-release), `--war-plan-hover` (the
  slip by a resting pointer) — never a harness shortcut.
- **Visual review** (`visual-review`, real-window shots, an independent critic,
  1.6 / 0.5 / 0.12 m): the boxwood piece against oak on parchment, the crayon
  against the sheet's ink, the teeth's size, lettering; the tool roll and the
  form.
- **Bench**: the plan repaint's frame spike and `plan_tex`'s memory at each
  tier; a repaint is an edit's, not a frame's.

## 5. Order of work

**A**: A1 engine (`war_plans` state, `WarPlans`, `power_of_arms`,
`WarGround.plan_*`, `Game` writers) → A2 the look (`blank`, `WarPlanPieces`,
the tag) → A3 the ground menu, the form, the slip, the drag → review. **B**:
B1 data, state and `WarPlanGeometry` → B2 `WarPlanInk`, the painter's plan
mode, `plan_tex` and the patch → B3 the tool roll, `WarPlanTool`, editing,
undo → review → B4 the second cut (area, checkpoints, arrow names, the key
slip's "staff's marks"). Each step lands on its own; each is a plan of its own.

## 6. Not in this spec

A supposed fleet; a quality chooser; supposed pieces as real intel (P2's
believed hosts); odds, a verdict or a simulated fight (the battle formula is
open); plans on the 3D map; sharing a plan as a missive to a general (a later
idea: a sealed annotated sheet sent by courier); a 3D crayon cup.

## 7. Documents that change when this lands

`scripts/war_room/CLAUDE.md` gains a short "Plans" section (supposed pieces,
the staff's marks, the tool roll, the pick order) and its hover-slip rule
names the supposed piece; `scripts/engine/CLAUDE.md` names `WarPlans` and
`power_of_arms`; `docs/design/DATA_ARCHITECTURE.md` lists `war_plans` in
`GameState`; `.claude/skills/visual-review/taste.md` takes the owner's ruling
on the finish (crayon or ink and wash) and on boxwood.

## 8. Concept mocks

Drawn by a small PIL script (no generation): a parchment patch with contours,
a walled town, woods, a road and a river; a hatched blue assembly area, two
blue axis arrows with checkpoints, a red toothed front, a red dashed expected
thrust, a sepia phase line "Line II", the objective "Obj. A", our dark-oak
piece on blue lacquer, two boxwood supposed pieces (red lacquer; Unknown in
sable) with pencilled tags.

- **A — wax crayon**, with the supposed piece's slip and the tool roll — the
  owner's pick, kept as `docs/references/war_room/plans_style_A_crayon.png`.
- **B — ink and wash**, with the ground menu (not chosen; not kept).
