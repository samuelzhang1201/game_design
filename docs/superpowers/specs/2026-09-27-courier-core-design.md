# Courier core (sub-project A of the missive system) — design

Owner request 2026-09-27: a courier system with a Missive kanban, spy couriers,
fog of knowledge, interception and courier art. It is split into four
sub-projects, each with its own spec → plan → build:

| | Sub-project | Status |
|---|---|---|
| **A** | **Courier core** — couriers on the road network, terrain + weather speed, army orders take effect only on delivery | **this spec** |
| B | Intelligence and the Missive kanban — fog of knowledge, spy couriers and reports, four credibility columns (ground truth / highly credible / worth consulting / rumour), the wax-sealed envelope flying to the tab | next |
| C | Interception — non-player couriers and spies, two-way probabilistic interception | **deferred with enemy AI** (owner 2026-09-27) |
| D | Art — 4–5 hand-drawn courier paintings, 3D courier riders, rig, gallop | parallel to A |

The owner moved this system ahead of PRD §6 Step 8 (raid defense). The
courier later feeds RD-1's "warning heeded".

## Owner rulings (2026-09-27)

- **Approach 1**: a courier is its own engine entity carrying the order. It
  is neither a delay field on the regiment nor a generic agent framework.
- **Unlimited couriers**: one per TARGET BATCH, gone on delivery. There is no
  stable and no return ride. Owner 2026-10-10 ("军队出发的时候，同一个信使发送
  目的地和补给信息，如果信息传递的target是同一个object，只需要一个信使即可以传达
  多个信息"): a courier record carries `orders` (an Array, run in the sequence
  given; an old save's single `order` becomes `orders` of one), and an order
  for a regiment whose newest courier has not yet set out (same kind, issued
  today, no day ridden, riding to the column — never a spy, a decree, or a
  supply order bound for its town) rides WITH him (`CourierSystem.joinable`):
  one fee, one courier id, so "a higher id is newer" holds order by order,
  and ONE receipt naming every order. The march's confirm and the war room's
  sealed drafts send supply point, load and march so.
- **Couriers ride the road network**: roads are fast, trails slower, off-road
  slowest.
- **Regional weather affects speed only**, for couriers AND regiments.
- **An ordinary courier rides 160 km a day** on a road, on the plain, in
  clear weather. That is four times the cavalry's 40.
- **A offers the ordinary courier only.** The secret courier's data row
  exists (750‰ speed), but the UI does not offer it until C gives security a
  meaning.
- **ComfyUI makes two kinds of image** (for D):
  - hand-drawn UI art the player sees;
  - a 3D STRUCTURE VIEW that Claude reads to build the model FROM SCRATCH in
    Blender MCP.

  No AI 3D is used (the Hunyuan ruling of 2026-09-24).

## 1. Engine

All three classes are pure `RefCounted`, headless-testable, and use no
wall-clock and no floats in state.

### `RoadGraph` (`scripts/engine/road_graph.gd`)

- **Nodes and edges.**
  - It is built from the pack's `geography/routes.csv` rows in groups
    `roads` and `trails`; `searoutes` are left out.
  - The route polylines' vertices are snapped to a `courier_graph_snap_px`
    grid (2) and merged into nodes. This matters because routes join each
    other mid-line: by burg endpoints the network falls into dozens of
    pieces, while by shared vertices 97.3% of the 1,459 nodes form one
    component. The rest are islands.
  - Each edge keeps its length in whole metres and its group.
- **Cost.** An edge's cost is its length ÷ its speed factor. The factor is:
  - the group's per-mille from `data/road_speed.csv` (`road`, `trail`);
  - × the Elevation tier of the edge's midpoint, from `data/road_speed.csv`
    rows `tier_hills` / `tier_mountains` / `tier_peak`, using
    `Elevation.tier_of`.

  Weather is NOT in the route cost. The route is chosen once, at dispatch,
  on the static network, so the choice is deterministic and cacheable. Weather
  changes the pace along the chosen route day by day.
- **Path.** Dijkstra runs from the node nearest the origin to the node nearest
  the target.
  - Each end is joined by an `offroad` leg (a straight line, factor
    `offroad`).
  - An origin or target farther than `courier_offroad_max_km` from any node
    rides straight off-road all the way.
  - Ties are broken by node id, so the result is deterministic.
- **Cache.** The graph is cached per pack and forgotten on `load_map`, like
  `HouseArms`. It is written so that regiments can path on it later; A does
  not change how regiments move.

### `Weather` (`scripts/engine/weather.gd`)

- **Stateless.** Weather is a pure function of
  `(campaign seed, province, spell index)`, hashed. It never draws from
  `GameState.rng` and saves nothing.
- **Spells.** Weather holds for spells of `weather_spell_days` (3) days so
  that a province does not flicker daily. The spell index is the absolute day
  ÷ spell length, from `Calendar`.
- **Kinds** (`data/weather.csv`): `clear`, `rain`, `mud`, `snow`, `blizzard`.
  Each row carries:
  - `speed_permille` — first draft 1000 / 850 / 700 / 650 / 400;
  - `icon` (a `resource_icons.csv` key);
  - `label`;
  - `notes`.
- **Odds** (`data/weather_odds.csv`): one row per season × Elevation tier
  (`plains`, `hills`, `mountains`, `peak`), with a weight per kind. Winter
  mountains snow, spring lowlands mud. The province's tier is the tier of its
  seat's cell.
- **API.** `Weather.of(repo, state, province, abs_day) -> String` and
  `Weather.speed_permille(repo, kind) -> int`.

### `CourierSystem` (`scripts/engine/courier_system.gd`)

**State.** `GameState.couriers` is an Array of Dictionaries, saved whole and
walked in ascending `id` order. Each courier holds:

```
id            int, monotonic (GameState.next_courier_id, saved)
kind          "ordinary" (A); "secret" data-only; "spy" arrives in B
x_m, y_m      whole metres, the courier's position now
path          Array of [x_m, y_m, segment_kind] — the remaining route; segment_kind ∈ road|trail|offroad|sea
target        regiment code
order         {action_code, params} — ARMY_MARCH / ARMY_GARRISON as validated
issued        absolute day the order was given (supersession)
set_out       absolute day of the first ride
```

**`dispatch(repo, state, kind, regiment, order) -> Dictionary`**
- **Origin.** The player realm's `capital_burg`, if the realm still holds that
  burg's province (`MapOwnership`). Otherwise the most populous town among
  `MapManors.controlled_provinces`, `home_province` first.
- **Route.** `RoadGraph.path` to the regiment's `ArmySystem.position_of`.
- **Sea crossing.** If the target is on another landmass (another road-graph
  component, with no land path), the courier rides to the coast point nearest
  the target and crosses as a `sea` segment at `road_speed.csv` `sea` (the
  fleet's 100 km/day, as per-mille of the courier base).
- **Fee.** It charges `courier_kinds.csv` `fee_gold` as a ledger line with a
  reason ("a courier rides for <regiment>"). The order's own `order_costs.csv`
  row is charged as before, when the order is executed.

**`ride_day(repo, state) -> Array` (events for the news bar)**

It runs under `TickEngine.advance_day` and `advance`, before
`ArmySystem.march_day`. Each courier in id order:

1. **Budget.** The day's budget is `B = courier_base_km_per_day × 1000 ×
   kind‰ ÷ 1000` CLEAR-ROAD METRES. The courier spends it stretch by stretch
   along `path`, where a stretch runs from one path vertex to the next. For
   each stretch:
   - Its factor is `P = segment‰ × tier‰ × weather‰`, a product out of 10⁹:
     - the segment factor comes from `road_speed.csv`;
     - the tier factor is the Elevation tier at the stretch's start;
     - the weather factor is that of the province at the stretch's start,
       on that day.
   - If the budget covers the whole stretch, the courier finishes it and
     `ceil(stretch_m × 10⁹ ÷ P)` is taken from the budget.
   - Otherwise the courier advances `B_left × P ÷ 10⁹` metres into the
     stretch (integer division) and stops. All of this fits in int64.
2. **Re-aim.** If the target regiment has moved more than
   `courier_reaim_m` since the path was set, the courier replaces the last
   off-road leg with a straight line to the regiment's current position.
   There is no re-routing on roads, since a regiment is far slower than a
   courier.
3. **Delivery.** When the path is exhausted, the courier delivers:
   - it applies the order through `ArmySystem.set_march` / `set_garrison`,
     unless the regiment already obeys an order with a later `issued`. In that
     case this order is stale and dropped, with a news line.
   - The courier is removed.
4. **Lost target.** If the target regiment no longer exists, the courier is
   removed with an "undelivered" event.
5. **Fuse.** A courier out longer than `courier_max_days` is removed with an
   "undelivered" event.
6. **Slow-day notice.** A day whose weather factor falls below
   `courier_slow_news_permille` (500) raises a single "delayed by <weather>"
   event per courier per spell.

**`eta_days(repo, state, kind, regiment, dest) -> int`** gives the estimate
the aim ruler shows: the route and today's weather held constant. It is an
estimate and is labelled so.

### Army orders change

In `ActionSystem.execute`, the `ARMY_MARCH` / `ARMY_GARRISON` arms
(`action_system.gd` ~:414–430) no longer call `set_march` / `set_garrison`.
They call `CourierSystem.dispatch` with the validated order. Validation is
unchanged.

- **Fleets are exempt in A**: a fleet's orders still apply at once. Couriers
  to fleets are left for later, and are noted in the plan's follow-ups.
- **An order never starts the clock.** On a paused clock the courier stands
  at the origin. A regiment at the capital receives its order on the first day
  that runs.

### Weather in the march

`ArmySystem.march_day` multiplies a regiment's day by the weather
`speed_permille` of the province it stands in. `speed_km_per_day` itself
stays weather-free: the card shows the base pace and a separate weather line.
Existing speed tests are updated where they march through days.

### Determinism

- Everything is integer metres and integer per-mille.
- Couriers advance in id order.
- Weather is hashed from the seed.
- Dijkstra breaks ties by node id.
- Identical save + inputs ⇒ identical couriers. A mid-ride save and load
  round-trips exactly.

## 2. Presentation

- **Issuing.** The aim → click → COMMIT / CANCEL flow is unchanged.
  - The aim ruler gains a third reading, "courier ≈ N days"
    (`CourierSystem.eta_days`).
  - COMMIT reads "Send courier", with the fee in its tooltip
    (`data/army_route_orders.csv`).
  - The route end ring's Edit route… and Cancel march also send couriers.
- **The courier on the map.** A new `Map3DLayerCouriers` (a `Couriers` node in
  `scenes/map3d/world_map_3d.tscn`) takes its entries from a new
  `Map3DContext.couriers()`. Because no `scripts/map3d/` script may reach
  `Game`, the view hands them in.
  - It reuses `Map3DUnits`' pure helpers: camera-driven size, footprint
    seating, walk interpolation.
  - Past `map3d_unit_counter_scale` it draws a flat counter with a letter
    glyph, still clickable.
  - **Interim model:** until D delivers, `data/courier_art.csv` `model` points
    at `assets/units3d/cavalry.glb`, drawn smaller (`size`) and playing MARCH
    fast. D replaces the file named in that column and nothing else. This
    stand-in is DELIBERATE and TEMPORARY; the plan's final task checks whether
    D has landed.
- **Route.** The courier's remaining path is drawn as a thin dashed line in
  the realm's colour, finer than a regiment's march line.
- **Pending order.** Until delivery, the regiment's intended route is drawn as
  a fainter dotted line, with a small envelope mark in its end ring. On
  delivery it becomes today's dashed march line.
- **The courier card** (left column, invariant 10) is reached with a click.
  `Map3DPicker.pick_at` ranks a courier after regiment pieces and before
  settlements. The card shows:
  - the painting (`courier_art.csv` `painting`, omitted until installed, like
    every card);
  - kind;
  - the order carried and its regiment;
  - issued / estimated arrival;
  - the ground now (road / trail / off-road / sea);
  - the weather where he rides, with its factor.
- **Weather shown.**
  - Province and manor cards gain "Weather: Rain (march and couriers ×0.85)".
  - The 3D HUD marks each province whose weather is not clear with its weather
    icon at the province's label anchor. The icons are thinned by camera
    distance with the landmark marks' rule and kept off the settlement dots
    and counters.
  - The icons are new I- series art (D). Until they are installed,
    `ResourceIcon`'s glyph fallback draws them.
- **News bar.** It carries "A courier leaves the capital for <regiment>",
  "Orders delivered to <regiment>", "The courier to <regiment> is held up by
  <weather>" (once per spell), and "Orders to <regiment> undelivered".

B owns the kanban, the reports and the flying envelope; nothing of them is
in A.

## 3. Data

| File | Columns (first draft) |
|---|---|
| `data/courier_kinds.csv` | `kind, speed_permille, fee_gold, offered, notes` — ordinary 1000 / 2 / 1; secret 750 / 5 / 0 |
| `data/courier_art.csv` | `kind, model, painting, size, notes` |
| `data/road_speed.csv` | `key, permille, notes` — road 1000, trail 800, offroad 550, sea 625 (100 km ÷ 160), tier_hills 800, tier_mountains 600, tier_peak 400 |
| `data/weather.csv` | `kind, speed_permille, icon, label, notes` |
| `data/weather_odds.csv` | `season, tier, clear, rain, mud, snow, blizzard` (weights) |
| `balance.csv` | `courier_base_km_per_day` 160, `courier_graph_snap_px` 2, `courier_offroad_max_km`, `courier_reaim_m`, `courier_max_days`, `courier_slow_news_permille` 500, `weather_spell_days` 3, plus the map3d look keys for the courier layer and route line |

## 4. Tests (GUT, written before the code)

- **RoadGraph**
  - A hand-drawn fixture network gives the shortest path and cost by hand.
  - Snapping merges mid-line joins.
  - On the default pack, the capital reaches ≥ 95% of nodes.
- **Weather**
  - The same (seed, province, day) always gives the same kind.
  - The kind holds across a spell.
  - Per-season frequencies fall within tolerance over a large sample.
- **CourierSystem**
  - Hand-computed day distances on road / trail / off-road × tier × weather.
  - Delivery on the exact day.
  - A newer order supersedes an older one: the stale courier's order is
    dropped.
  - A lost target, and the fuse.
  - The capital-lost origin fallback.
  - The sea crossing.
  - A save / load mid-ride round-trips.
- **ActionSystem**
  - `ARMY_MARCH` leaves the regiment untouched and adds one courier; the
    regiment moves only from its delivery day.
  - The fee's ledger line carries its reason.
  - A fleet's order applies at once.
- **ArmySystem**: weather scales a march day by hand-computed values.
- **UI, through real input** (`verify-ui-through-real-input`):
  - `snapshot_screen --march3d fx,fy --march-confirm --march-commit` with
    `--shot-frame` at dispatch, mid-ride and delivery;
  - a click on the courier opens its card;
  - the looks go through `.claude/skills/visual-review/`.

## 5. Out of scope for A

- The secret courier in the UI (C).
- Spy couriers, reports, fog of knowledge, the kanban and the envelope (B).
- Non-player couriers and interception (C, with enemy AI).
- Couriers to fleets.
- Regiment pathfinding on `RoadGraph`.
- Weather's effect on supply, battle or harvest.
- Weather drawn in 3D (rain, snow, fog).
- The courier art (D).
