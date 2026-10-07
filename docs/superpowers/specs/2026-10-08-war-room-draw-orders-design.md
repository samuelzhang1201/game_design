# WAR ROOM — orders are drawn: a two-sided tool roll, the blue arrow as the march, fronts that face each other, the supply town after the destination — design

Owner request 2026-10-08 (translated):

> The tool roll on the map splits into two ROWS: the upper one RED, for
> operating the enemy / supposed enemy; the lower one BLUE, for operating our
> side. The player must first choose enemy or ours before they can draw.
> 1. Remove the current behaviour where clicking a military unit shows march
>    etc. options identical to the big map — it duplicates. Remove the current
>    arrow + dashed-line way of giving orders. Instead, ALL orders are given by
>    DRAWING A BLUE ARROW: the system derives the route from the path the
>    player draws, and after confirming lays the waypoints for the march.
>    After the route is drawn, the supply window pops up to choose the carry
>    and show the estimates.
> 2. Both sides' front lines must face each other: the saw-tooth direction
>    must be adjustable so it points at the enemy.
> 3. The supply town can also be chosen after the destination is fixed, and a
>    BOLD DASHED supply route is shown, pointing to the arrow's destination.

The owner then REFINED point 1 (same night, translated): to draw a blue
march-route arrow the player must FIRST SELECT one or several of our units
(Shift+click adds, or a left-drag BOX round several), then draw; the red arrow
likewise — a selected supposed piece, or a spot the spies' reports reveal,
shown as a dashed ANIMATED hint (marching ants). Rulings 6-8, 11 and 16-18
below are written to that refinement.

The owner said "no questions tonight": every ruling below was made without
him and is listed for him to overturn one by one. Builds on
`2026-10-07-war-room-annotations-and-planning-pieces-design.md` (the plans),
`2026-10-07-march-waypoints-design.md` (routes, the confirm panel) and
`2026-10-07-army-supply-lines-design.md` (supply points).

## Rulings (made without the owner, to confirm)

1. **The roll is two rows in one leather strip**, bottom-left as before. A
   shared HAND slot stands on the left, the height of both rows. Upper row
   RED (theirs): its crayon stick (the row's badge), arrow, front, phase
   line, objective, | supposed piece, scraper. Lower row BLUE (ours): its
   crayon stick, arrow, front, phase line, objective, | scraper. The row a
   slot is in is the SIDE and the colour of what it draws; there is no pen
   choice any more.
2. **Choose a side first.** With the hand (nothing picked) nothing draws.
   The side's row is lit and the other dimmed; no row is lit until a side is
   chosen. Keys: `1`–`4` the kinds ON THE CURRENT SIDE (with no side yet the
   news says to choose one), **Tab** switches side (taking the same kind on
   the other side; with nothing in hand it lights the other row and takes its
   last kind), `Esc` lays the stick down. A row's stick picks that side with
   its last kind.
3. **The sepia pen is retired as a stick**: no new ink stroke is drawn. Ink
   strokes already saved keep rendering, keep their menu and can be recoloured
   to red or blue (the Colour rows offer only the two sides). Phase lines and
   objectives are drawn as pen lines in the side's colour.
4. **The scraper is side-aware**: the red one scrapes red marks, ink marks and
   supposed pieces; the blue one blue marks and ink marks.
5. **The ground menu loses its Draw rows** (the roll is always in reach):
   Place a supposed enemy here… · — · Clear supposed pieces on D4 · Clear
   drawings on D4. The supposed piece is placed from the red row's slot (click
   → the Place form) or that menu row.
6. **The BLUE ARROW is the selection's march, and nothing else.** It is
   live only while one or more of our regiments are selected (ruling 16);
   greyed with "Select a unit first…" otherwise. Its start is free. A blue
   arrow is never an annotation any more (no plain-arrow slot: the roll stays
   small; old saves' blue arrows still render). Land regiments only — a fleet
   is not selected by the box; fleets are ordered on the 3D map.
7. **The stroke becomes the route** (`WarOrderSketch.fit`, pure): the samples
   (pack px) smoothed by Ramer–Douglas–Peucker at `war_order_fit_px` screen px
   (its pack-px equivalent at the zoom it was drawn), coarsened until at most
   `army_march_waypoints_max` points remain before the tip, rounded to WHOLE
   METRES, points closer than `army_route_sample_m` dropped; the tip is the
   destination. Each selected regiment JOINS the drawn path at the control
   point nearest it (`WarOrderSketch.route_for`): its waypoints are the path's
   points from there on, the joining point left out when it stands within
   `war_order_join_km` of it; nearer the tip than any bend, it marches
   straight there. A drag shorter than `war_plan_min_len_px` draws nothing.
8. **A refused point**: a waypoint a regiment cannot be sent to (the sea for
   a column) is DROPPED for it and the route kept without it, the news saying
   so; a refused destination (or the regiment's own refusal: the paused-clock
   rule, nobody under arms) leaves that regiment OUT — listed greyed on the
   confirm with the engine's reason. When all are refused the news says the
   first reason and nothing opens.
9. **The confirm panel opens at once** with those routes (`ArmyOrderMenu.
   plan_group`): the carry rows (with several regiments: the LAST arrival,
   the trains' supplies summed, the WORST shortfall — `MarchPlan.group_rows`),
   ONE load for all, then one row a regiment (its own arrival and supplies at
   the load pressed, "runs N days short"; a tick to leave it out — the next
   leads when the lead is unticked; a refused one greyed with its reason), and
   the Supply from row (ruling 13), applying to all. Add waypoint is hidden in
   the room (draw again instead); the route can still be BENT on the table
   (drag the line or a waypoint ring). Confirm pencils the DRAFT (the room's
   rule stands: drafts, sealed by the resolutions scroll); Cancel / Escape /
   a right click give it up. Confirm pencils ONE draft PER REGIMENT
   (`WarDrafts` is one a regiment), each with its own waypoints, the shared
   end, the load (when it changes that regiment's) and the supply town (when
   it is not already that regiment's line).
10. **The pending order is drawn as a BLUE CRAYON ARROW along the curve the
    column will walk** (`ArmySystem.curve_px` → `WarPlanInk.add` in the live
    plan HUD): the drawn line is the walked line; its waypoints are rings to
    bend. Once pencilled, a draft stays GRAPHITE with its pale pennant (an
    order pencilled is not an idea crayoned — the previous spec's ruling 20).
11. **Removed from the room**: the player's rake (a drag from a piece no
    longer arms a march; it pans like a drag on open table) and every order
    menu on a piece (March… / Garrison… on a right click, the garrison's list
    on a left one). A right click on one of our pieces does nothing. KEPT: the
    plotter's rake, the pennants and their route menu (Edit route…, Strike the
    draft, Cancel march / halt), which is how a march is halted or re-drawn:
    Edit route… reopens the confirm with that regiment's draft as the pending
    blue arrow. A sheet rolling gives a pending march up.
12. **Fronts face each other.** A front's teeth stand on its FACING side. At
    draw time the facing is chosen (`WarPlans.facing_flip`, pure): the side of
    the line on which the nearest OPPOSING thing lies — for a red front the
    blue strokes' points and our pieces, for a blue front the red strokes'
    points and the supposed pieces; with none, the drawer's LEFT. Its menu
    keeps **Flip the teeth** and gains **Face the enemy** (the same choice made
    again now). With the hand, a chosen front shows a chalk FACING HANDLE at
    its middle — a small arrow pointing where the teeth point: a click flips
    it, a drag released on the other side of the line turns it there.
13. **Supply from, after the destination** (`MarchConfirmPanel`, shared by the
    3D map and the room): a "Supply from" list — the regiment's current supply
    town first (preselected, "no change"), or "No supply point" when it has
    none, then every realm town that may supply it — and one line of figures
    for the town chosen: road km to the march's END, wagon days, % lost on the
    road, gold a day. A town may be chosen when the engine would take it NOW
    (`SupplyLines.eligibility`: the order is validated from where the column
    stands when it is sealed) AND its wagons reach the march's end within
    `supply_point_max_days` (`SupplyLines.march_eligibility`); a refused town
    is greyed with its reason. The rate is the current line's, else
    `supply_rate_default` (1×). While the panel stands, the eligible towns are
    lit on the table / map (`supply_pick`) and a click on a lit town chooses
    it. Land regiments of the realm only (a fleet has no row). The panel
    never withdraws a supply point (the map's Withdraw row does).
14. **The supply route preview is BOLD, DASHED and GOLD**, from the chosen
    town along the roads to the march's destination (`supply_preview`): in the
    room drawn by `WarHud` in screen px (`war_supply_route_px`,
    `war_supply_route_dash_px`, palette `supply_route`), clearly apart from the
    thin flowing ribbon of a line in being; on the 3D map the supply pick's
    own dashed preview (`supply_preview.tres`).
15. **Confirm sends the supply point with the march.** On the 3D map:
    SUPPLY_POINT_SET (its own courier and fee), then the load, then the march,
    each validated first. In the room the DRAFT carries `supply_town` and
    `supply_rate` as it carries `carry_days`; sealed, it runs supply point,
    load, march — each its own courier and fee — and the resolutions line,
    measured by running them, counts their gold and names the town ("…, supplied
    from Walbover").

16. **Selection.** One selection at a time, of one side: ours (blue — the
    regiments' codes; a town's garrison piece selects its every regiment) or
    theirs (red — supposed pieces and intel hints). A click selects (on our
    piece it also opens its folio docked, as before); Shift-click toggles; a
    Shift-drag from open table boxes every piece of the lit side (ours with
    none lit) in a dashed chalk marquee — Shift, because a plain left drag
    must keep panning (WASD pans too); a box opens no book. A click on open
    table or Escape lets it go. Selected pieces wear a ring in their side's
    colour over a chalk halo. Selecting lights that side's row.
17. **The red arrow is drawn FOR something**: a selected supposed piece or
    intel hint; the stroke records it (`of`) and goes when its supposed piece
    is removed. With nothing red selected the red arrow is greyed. The other
    kinds (front, phase line, objective) need no selection.
18. **Intel hints** (`WarRoom.intel_hints`, pure): every spy report that has
    come in whose `troops_foreign` span reaches `war_intel_hint_min_heads`
    foreign men (the newest about a place standing for it), then
    `WarRoom.believed_hosts` (empty until intel P2 brings real enemy hosts) —
    only what a report said, never a garrison the crown was not told of. Each
    is a red ring of MARCHING ANTS on the HUD (`war_intel_hint_*`; the dashes
    walk round every frame, never baked into the sheet's ink), concentric with
    the intel layer's static spy-report ring; a click selects it.
19. **Drafts stay graphite** with their pale pennants once pencilled; only the
    pending march (on its confirm) is the blue crayon arrow.

## 1. Engine (pure, tested)

- `WarPlans.facing_flip(repo, pts_px, targets) -> int` (0 the drawer's right,
  1 the left: the stored `flip`) and `WarPlans.opposing_points(repo, state,
  colour, ours_px, except_id) -> Array`; `WarPlans.draw(..., flip := -1)`
  stores a facing (−1: 0).
- `SupplyLines.road_between_px(repo, town, to_px)` (the courier's road from a
  town to any point; `road_px` is it to the column) and
  `SupplyLines.march_eligibility(repo, state, code, dest_px) -> {town: why}`.
- `WarRoom.intel_hints` / `hint_of`; `MarchPlan.group_rows`.
- `WarDrafts.plant(..., supply_town := "", supply_rate := 0)`;
  `requests_from` → SUPPLY_POINT_SET (when a town is named and differs from
  the line's), SUPPLY_CARRY_SET (when the load changes), ARMY_MARCH.
  `Game.review_drafts` adds the town to its line (`supply`).

## 2. The room

- `WarOrderSketch` (`scripts/war_room/`, pure): `fit(repo, from_px, samples,
  tol_px) -> {dest, waypoints}` in whole-metre pack px.
- `WarPlanTool`: `side` (`""`, `red`, `blue`), `pick(side, kind)`,
  `switch_side()`; the release hands back the raw samples too.
- `WarPlanInput`: the selection (`sel_side`, `sel`, Shift, the box); a blue
  arrow is the selection's ORDER stroke — its release emits
  `order_drawn(codes, samples, tol)`, while drawing `order_aimed` feeds the
  tip's slip; a red arrow carries `of`; the pending march's blue crayon in the
  live layer; the front's facing handle; intel hints picked.
- `WarRoomView`: `aim_group`, `supply_pick`, `supply_preview` (the map
  contract's names), `sheet_rolling`; `WarRoomPointer` (was the rake) keeps
  the left button's picks, the pan and the route bend, and draws the HUD's
  marks — `rake_started`, `rake_dropped`, `army_menu_requested`,
  `garrison_menu_requested`, `cancel_rake`, `rake_reading` are gone.
- `WarRoomScreen` fits the stroke, joins each regiment, calls
  `ArmyOrderMenu.plan_group`.

## 3. Data

- `balance.csv`: `war_order_fit_px`, `war_order_join_km`,
  `war_order_feeder_mm`, `supply_rate_default`, `war_supply_route_px`,
  `war_supply_route_dash_px`, `war_supply_lit_px`, `war_plan_facing_px`,
  `war_select_ring_ratio`, `war_select_ring_px`, `war_select_box_dash_px`,
  `war_intel_hint_min_heads`, `war_intel_hint_px`, `war_intel_hint_dash_px`,
  `war_intel_hint_speed_px`, `war_intel_hint_line_px`.
- `war_palette.csv`: `supply_route`.
- `army_supply_orders.csv`: `march_none`, `march_keep`, `march_figures`,
  `pick_far_end`.
- `army_route_orders.csv` / news: the drop and refusal lines are written in
  `WarRoomScreen` from the engine's own reasons.
