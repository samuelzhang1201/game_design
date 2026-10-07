# March routes: waypoints, a bent line, the carry asked on confirm — design

Owner request 2026-10-07 (items 7, 9 and 10 of the day's brief), for the march
order on BOTH the 3D campaign map and the WAR ROOM (both run `ArmyOrderMenu`):

> 7. 右键点击军队时，不要显示携带多少补给。在点击March并选择目的地之后，弹窗询问携带多少补给，并计算消耗的天数。
> 9. 点击March并左键点击目的地后，除了Confirm和Cancel，再加一个"Add waypoint"选项，可以继续选择前进路线。
> 10. 选择目的地后，现在是一条直线和固定的虚线，我希望玩家可以抓住路线，按住左键拖动使路径弯曲——起点终点不变，但形状变成曲线。

**Status: built on feat/march-waypoints.**

## Rulings made without the owner (to confirm)

1. **The curve is a centripetal Catmull-Rom** through the column, every waypoint
   and the destination (phantom ends reflected), sampled every
   `army_route_sample_m` metres of chord per leg into WHOLE-METRE points
   (`MarchRoute`, `scripts/engine/`). The UI draws those very points, so the
   drawn line is the walked line. A march with no waypoints is not sampled at
   all: it walks the straight line exactly as before.
2. **The curve starts where the column stands when the courier reaches it.**
   For a standing column that is the line drawn on confirm; a column already
   marching re-bends its first leg from wherever it has got to (the waypoints
   and the end do not move).
3. **At most `army_march_waypoints_max` waypoints** (8). Every waypoint is
   checked as the destination is (on the map; land for a column, the sea for
   a fleet). The curve between points is not checked, as the straight line
   never was (no pathfinding yet).
4. **Fleets take routes too**: the same `set_march`, no courier.
5. **State**: a marching regiment keeps `route_m` (the curve still ahead,
   `[[x, y], …]` whole metres ending on `dest_x_m`/`dest_y_m`) and
   `waypoints_m` (the waypoints still ahead); passing a waypoint drops it. No
   save version bump: both are optional, an old save loads with straight
   marches.
6. **The confirm is a small panel, not the menu**
   (`scenes/panels/march_confirm_panel.tscn`): one row per
   `data/army_carry_loads.csv` load — days to arrive (the courier's ride and
   the march at that load's pace), the supplies a train of that load holds,
   the days they last, and **"runs short"** when the column would set out with
   fewer days of supplies than the march takes. It sets out with the full load
   when it stands in a realm town (the town tops it up), else with what it
   holds now; supply lines are not counted. The current load is pre-selected.
   Confirm / Add waypoint / Cancel.
7. **The panel does not close on a click away** (the map stays live to bend
   the route): a plain click on open ground while it stands does nothing;
   Cancel, Escape, a right click on the ground or the clock starting give the
   march up.
8. **Confirm sends the carry first, then the march**: `SUPPLY_CARRY_SET` only
   when the chosen load differs from the regiment's, its own courier and fee as
   ever. In the WAR ROOM the load rides on the march DRAFT (`carry_days`) and,
   when sealed, its carry order runs before the march; the resolutions line
   counts both orders' gold.
9. **Bending**: a left press within `map3d_route_grab_px` (the map) /
   `war_route_grab_px` (the room) of a waypoint takes it; of the line, inserts
   a waypoint there (on the leg it lies on) and takes it; dragging moves it;
   release sets it. A waypoint dropped where the regiment cannot go (the sea
   for a column, past the cap) goes back where it was and the news says why.
   A press anywhere else pans as before. The end and the start never move.
10. **Edit route…** on a committed march (or a draft) loads its remaining
    waypoints and its destination as the pending route and opens the confirm
    panel at once (no new aim); Add waypoint from there aims on from the end.
11. **The ruler and every day figure measure along the curve**
    (`ArmySystem.march_days_between` walks the sampled route).

## 1. Engine

- `MarchRoute` (pure, static): `curve(points: Array[Vector2i], step_m) ->
  Array[Vector2i]` from the first control point to the last, each control point
  exactly on it; `legs` (the same split per leg, for inserting a waypoint on the
  leg grabbed); `length_m`. Coincident control points are dropped first.
- `ArmySystem`: `set_march(repo, state, code, dest_px, waypoints_px := [])`
  (sample from where the column stands; no waypoints ⇒ no route), `set_garrison`
  and an arrival clear the route. `_march_one` walks `route_m` (else the straight
  line): each day's step is what is ahead ALONG THE ROUTE over the whole days
  left, rounded up, as before; it drops the points it passes (and a waypoint
  with its point) and never mutates an array in place (the map's day-ahead
  preview walks a copy). `march_days_between(..., waypoints_px := [], carry := -1)`
  walks the same route at a load's pace; `route_px` / `waypoints_of` read the
  route still ahead for the maps; `heading_of` faces the next point.
- `ARMY_MARCH` params gain `waypoints: [[x, y], …]` (pack px). The courier's
  order carries `waypoints_m`; `CourierSystem._deliver` passes them on;
  `arrival_days` / `days_to_arrival` measure along them.
- `WarDrafts.plant(..., waypoints_px := [], carry := -1)` keeps `waypoints_m`
  and `carry_days` on a march draft; `requests_from` returns the carry order
  (when it changes the load) then the march; `Game.review_drafts` /
  `deploy_drafts` run each draft's orders in that order.
- Balance: `army_route_sample_m`, `army_march_waypoints_max`,
  `map3d_route_grab_px`, `war_route_grab_px`, `map3d_route_handle_px`.

## 2. UI

- `ArmyOrderMenu`: the regiment menu keeps March… and the supply point rows
  (Add / Change / Withdraw); the carry rows are gone. After the destination
  click the CONFIRM PANEL opens beside it; the pending route is the menu's
  (`_waypoints`, pack px) and the map's (`aim_waypoints`), the map reporting a
  bend by `route_bent(waypoints)`.
- 3D map: `Map3DRouteEdit` (`scripts/map3d/`) takes the press near the pending
  route and drags; `Map3DHudRuler` draws the aim and the pending route as the
  curve (waypoint handles as small rings), `Map3DHudArmies` a committed route
  along `route_px`, `Map3DHudCouriers` a riding order along its waypoints.
- WAR ROOM: `WarRoomRake` draws the rake through the waypoints along the curve
  and bends the held route; pennant dashes and draft pencils follow the curve.
