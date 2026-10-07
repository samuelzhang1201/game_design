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
6. **A BLUE ARROW drawn FROM one of our pieces is a march order** — a piece of
   the crown's (a land regiment, a fleet, or a town's garrison piece: the
   regiment chosen from its list, else its first) whose pick reach
   (`war_pick_px`) holds the press. Any other blue arrow, and every red arrow,
   is an annotation as before. Fleets take drawn routes too (their routes are
   checked at sea, as the map checks them).
7. **The stroke becomes the route** (`WarOrderSketch.fit`, pure): the samples
   (pack px), the first replaced by where the piece stands, are smoothed by
   Ramer–Douglas–Peucker at `war_order_fit_px` screen px (its pack-px
   equivalent at the zoom it was drawn), coarsened until at most
   `army_march_waypoints_max` interior points remain, rounded to WHOLE METRES;
   the tip is the destination, the interior points the waypoints, points
   closer than `army_route_sample_m` to the one before dropped. A drag shorter
   than `war_plan_min_len_px` from a piece is a click on it (it is chosen).
8. **A refused point**: a waypoint the regiment cannot be sent to (the sea for
   a column, land for a fleet) is DROPPED and the route kept without it, the
   news saying so; a refused destination refuses the whole order, the news
   saying why (the engine's own reason). The paused-clock rule and the
   regiment's own refusals are `ArmyOrderMenu`'s as before.
9. **The confirm panel opens at once** with that route (`ArmyOrderMenu.
   plan_route`): the carry rows with arrival days, supplies and "runs N days
   short", and the new Supply from row (ruling 13). Add waypoint is hidden in
   the room (draw again instead); the route can still be BENT on the table
   (drag the line or a waypoint ring). Confirm pencils the DRAFT (the room's
   rule stands: drafts, sealed by the resolutions scroll); Cancel / Escape /
   a right click give it up.
10. **The pending order is drawn as a BLUE CRAYON ARROW along the curve the
    column will walk** (`ArmySystem.curve_px` → `WarPlanInk.add` in the live
    plan HUD): the drawn line is the walked line; its waypoints are rings to
    bend. Once pencilled, a draft stays GRAPHITE with its pale pennant (an
    order pencilled is not an idea crayoned — the previous spec's ruling 20).
11. **Removed from the room**: the player's rake (a drag from a piece no
    longer arms a march; it pans like a drag on open table) and the
    right-click order menu on a piece (March… / Garrison…). A right click on
    one of our pieces does nothing; a left click chooses it (the docked book,
    the hover slip). The garrison list still opens on a click on a town's
    garrison piece — to choose which regiment a blue arrow takes — and choosing
    a row there only chooses (no orders menu). KEPT: the plotter's rake, the
    pennants and their route menu (Edit route…, Strike the draft, Cancel
    march / halt), which is how a march is halted or re-drawn: Edit route…
    reopens the confirm with the draft's waypoints as the pending blue arrow.
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

## 1. Engine (pure, tested)

- `WarPlans.facing_flip(repo, pts_px, targets) -> int` (0 the drawer's right,
  1 the left: the stored `flip`) and `WarPlans.opposing_points(repo, state,
  colour, ours_px, except_id) -> Array`; `WarPlans.draw(..., flip := -1)`
  stores a facing (−1: 0).
- `SupplyLines.road_between_px(repo, town, to_px)` (the courier's road from a
  town to any point; `road_px` is it to the column) and
  `SupplyLines.march_eligibility(repo, state, code, dest_px) -> {town: why}`.
- `WarDrafts.plant(..., supply_town := "", supply_rate := 0)`;
  `requests_from` → SUPPLY_POINT_SET (when a town is named and differs from
  the line's), SUPPLY_CARRY_SET (when the load changes), ARMY_MARCH.
  `Game.review_drafts` adds the town to its line (`supply`).

## 2. The room

- `WarOrderSketch` (`scripts/war_room/`, pure): `fit(repo, from_px, samples,
  tol_px) -> {dest, waypoints}` in whole-metre pack px.
- `WarPlanTool`: `side` (`""`, `red`, `blue`), `pick(side, kind)`,
  `switch_side()`; the release hands back the raw samples too.
- `WarPlanInput`: a blue arrow pressed on our piece is an ORDER stroke; its
  release emits `order_drawn(code, samples, tol_px)`; while drawing it emits
  `order_aimed` for the tip's slip; the pending order's blue arrow and its
  rings are drawn in the live layer; the front's facing handle.
- `WarRoomView`: `supply_pick`, `supply_preview` (the map contract's names);
  `WarRoomRake` keeps the left button's picks, the pan and the route bend —
  the rake is gone (`rake_started`, `rake_dropped`, `army_menu_requested` in
  the room, `cancel_rake`, `rake_reading` removed).
- `WarRoomScreen` fits the stroke, refuses or drops points, calls
  `ArmyOrderMenu.plan_route`.

## 3. Data

- `balance.csv`: `war_order_fit_px`, `supply_rate_default`,
  `war_supply_route_px`, `war_supply_route_dash_px`,
  `war_supply_lit_px`, `war_plan_facing_px`.
- `war_palette.csv`: `supply_route`.
- `army_supply_orders.csv`: `march_none`, `march_keep`, `march_figures`.
- `army_route_orders.csv` / news: the drop and refusal lines are written in
  `WarRoomScreen` from the engine's own reasons.
