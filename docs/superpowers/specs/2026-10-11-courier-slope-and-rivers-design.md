# Couriers and supply wagons: slopes, water and rivers (2026-10-11)

## Owner rulings (2026-10-11, binding)

1. Couriers detour steep slopes (cells steeper than `army_max_slope`) as marches do; so do supply wagons, whose line rides the courier's road.
2. Crossing water is fine: water is NOT a barrier to a courier or a supply wagon. Armies are untouched (they keep the land grid).
3. Rivers, lakes and the sea count as routes in courier / supply route-finding, at 80% of road pace: `data/road_speed.csv` has `river,800` and `sea,800`. The route is the FASTEST by the existing time cost (Dijkstra), never "network at any cost".
4. Drawn road and trail edges that cross cells steeper than the limit are detoured (route-finding only; the 3D roads stay as drawn).

## Design

- `MarchPath.of_pack(repo, water_open)`: with `water_open` water cells are open and only a scarp closes. `water_runs(a, b)` cuts a straight leg into land and water runs.
- `RoadGraph.courier_of_pack` = routes then rivers (kind `river`, snapped to the same vertices), each edge whose chord meets a closed cell replaced by `MarchPath.road`'s way round as `offroad` / `sea` stretches, cost the sum of the stretches (tier 1000 on water). An edge with no way round keeps the drawn line. `RoadGraph.of_pack` (drawn network) is unchanged and still serves trade.
- `RoadGraph.across` plans the legs off the network (and a re-aimed courier's tail) on the open grid. `SupplyLines.road_between_px` is just the courier's road.

## Defaults chosen

Only route-finding detours (3D roads unchanged). A detour stretch rides at `offroad` / `sea` pace. The same courier piece crosses water. River pace is the same both ways; the height tier applies. Long detours are kept (Dijkstra avoids them when a faster way exists). Trade stays on the drawn roads. The sea stays straight legs (no sea network).
