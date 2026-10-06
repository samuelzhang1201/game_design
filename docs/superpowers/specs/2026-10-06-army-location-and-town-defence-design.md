# Where a regiment stands: town, field, height — design

Owner request 2026-10-06: "我希望军事单位的地理位置数据跟随单位移动变动，准确反映当前军事单位所处的位置，如果在城市里则获得相应的城市防御加成，野外，高地等不同地理位置都应当准确反映".

**Status: APPROVED and built 2026-10-06.** Owner: "按设计说明的建议做，开局部队挪进城里
1-3 按你说的做，4. 补给暂时不动，逻辑之后更新 5. 根据地形/有路没路区分快慢加成" — §5's
questions 1–3 as recommended, supply unchanged for now, and the march paced by
the ground (§6).

Already done (same day, not part of this spec): `ArmySystem.power` reads the
ground and walls at the regiment's CURRENT position (it read the pack's
quarters), and the regiment card's "Quartered in" names the province the
regiment stands in now (`ArmySystem.province_of`).

## 1. What is wrong today

- **"In a town" is "in the town's Azgaar cell".** `ArmySystem.is_fortified`
  asks whether a walled or citadel burg shares the regiment's cell. The
  pack's cells average ~490 km² (~20 km across), so a column 10 km out in
  the fields is "behind the walls", and one 1 km from a town on the other
  side of a cell edge is not.
- **Only walls count.** A town without `walls` or `citadel` gives nothing:
  the 12th (Garestedmin) Archers stand in the middle of Garestedmin and fight
  as in the open.
- **Walls serve anyone in the cell**, an enemy column besieging the town
  included.
- **The garrison is not where the regiment is.** `SupplySystem.garrisoned_in`
  is "an explicit GARRISON order, standing anywhere in a province the crown
  controls" and names the province's CAPITAL town. Every march ends in
  `ORDER_GARRISON`, so a column halted in open country earns
  `army_morale_garrison_bonus` and the LEDGER's "garrisons in <capital>".

## 2. A regiment's place

One engine function decides where a land regiment is, from its live
position (`ArmySystem.position_of`), every day:

`ArmySystem.town_of(repo, state, reg) -> String` — the burg whose REACH
holds the regiment's position, nearest first (ties to the earlier code), ""
in the field. A burg's reach is by its `group` (capital / city / town / fort
/ village), from a new table `data/army_town_reach.csv`
(`group,reach_km,notes`; first draft: capital 3, city 2.5, town 2, fort 1.5,
village 1 — a medieval town's walls and suburbs, in the pack's km).

Everything that today asks "is it in a town" asks `town_of` instead of the
cell: the defence (§3), the garrison (§4), the card, the War Room folio, the
missive's "Ground" line. The cell stays the source of the terrain and the
height (biome, hills / mountains / peak tiers) — the ground under a town is
still that ground.

A column marching THROUGH a town is in it on the days its position lies
inside the reach; there is no "entering" event.

## 3. Town defence

The bonus is the town's, by what it has, per arm, from data. It replaces
the `fortified|<arm>` rows of `data/army_terrain.csv` with a new table
`data/army_town_defence.csv` (`works,arm,defend_permille,attack_permille,notes`),
`works` being the best the town has:

| works | infantry | archers | cavalry | artillery |
|---|---|---|---|---|
| `town` (no walls) | 1100 | 1100 | 900 | 1050 |
| `walls` | 1300 | 1250 | 1000 | 1200 |
| `citadel` | 1400 | 1350 | 1000 | 1300 |

(defend per mille; attack 1000 throughout — first draft, `walls` keeps
today's `fortified` values; cavalry is worse in streets than in the open.)
A town with both walls and a citadel counts as `citadel`.

- It multiplies onto the terrain factor, for the DEFENDER only, as
  `fortified` does today.
- **Only the side that holds the town gets it**: the town's province owner
  (`MapOwnership.owner_of`) must be the regiment's kingdom. A foreign
  column in your town is in the field.
- `ArmySystem.is_fortified` becomes `ArmySystem.works_of(repo, state, reg)
  -> String` ("" / town / walls / citadel); `terrain_label` reads
  "Plains — in Garestedmin" / "Hills — behind the walls of Walbover".

## 4. Garrison

- `SupplySystem.garrisoned_in` becomes: an explicit GARRISON order AND
  `town_of` is a town the regiment's kingdom holds. It names THAT town, not
  the province capital.
- A GARRISON order (or a march's arrival) in open country is a **field
  camp**: the column stands, with no garrison morale and no "garrisons in"
  thread. The War Room folio's order reads "Encamped in the field".
- Supply is unchanged: a column standing anywhere in a province the crown
  controls still draws through the province capital with no road loss
  (`SupplySystem.stronghold_of`) — that is the supply rule, not the defence
  rule. (§5 asks whether to tighten it too.)

## 5. The owner's rulings (2026-10-06)

1. **Reach sizes**: 3 / 2.5 / 2 / 1.5 / 1 km by group, as drafted.
2. **Defence numbers**: the table in §3, as the first draft.
3. **Starting positions**: every LAND regiment of every kingdom is quartered
   in a town of its own province — the town its label names when that town
   is in the province, else the province's town nearest its old quarters — on
   land of the province BESIDE the town's point, never on it: the first in
   the pack's order at half the town's reach, the rest at 0.8 of it, each on
   the bearing farthest from those already there. Beside, so the town's dot
   stays clickable and the first stands nearer the capital than the rest:
   the crown's banner flies over the regiment the capital is named for (the
   6th at Walbover, 1.5 km out; the 11th Archers 2.4 km). The drawn towns
   (bake/houses.csv) spread past the reach — Walbover's houses to 6 km — so a
   quartered piece stands among the houses, as a garrison does. On the map a
   counter yields the click to a town's dot or badge nearer the pointer; the
   War Room keeps every piece where the map draws it (owner 2026-10-02), so
   two regiments in one town stand within one base there and the nearer
   hides the other. Fleets keep their stations. A re-import of the pack must keep this (the importer does
   not yet place regiments in towns).
4. **Supply**: unchanged for now — anywhere in a controlled province draws
   through its capital; to be revisited.
5. **March speed by ground**: built, §6.

## 6. The ground's pace

A march's day reads the ground where the column stands that day
(`ArmySystem.ground_permille`, data `data/army_ground_speed.csv`, per mille
of the base pace, which `data/army_speed.csv` quotes on open plain off the
road):

- **On a road or trail** — within `army_road_reach_m` (1.5 km) of one of the
  pack's roads or trails (`ArmySystem.road_at`): the road's row (road 1250,
  trail 1100) times the height tier's (`tier_plains` 1000, `tier_hills` 850,
  `tier_mountains` 650, `tier_peak` 450): a road beats the forest and the
  marsh, but still climbs.
- **Off the road**: the terrain's row (`ArmySystem.terrain_at`: plains 1000,
  desert and tundra 850, forest 750, hills 700, jungle and marsh 600,
  mountains 450).
- The day's metres are `day_step_m` × the weather × the ground
  (`ArmySystem.day_march_at`). The march stays straight-line; it is not
  routed onto the roads.
- **Arrival figures walk the route**: `ArmySystem.march_days_between` runs
  the march day by day exactly as `march_day` will (the weather is a seeded
  function of the day), so days out, the aim ruler and the courier's arrival
  day are the day it arrives — while its stores, which also set its pace,
  hold.
- The card and the War Room folio show the pace with its ground ("road
  ×1.25", "forest ×0.75").

## 7. Tests

`tests/engine/test_army_towns.gd`, plus the march / speed / courier tests run
on flat ground (`SuiteData.flat_ground`) so they keep testing their own
mechanics.

## 8. Tests planned at the draft

- `town_of`: at a burg's point → that burg; just inside / just outside its
  reach; two reaches overlapping → the nearer; a marched position, not the
  pack's.
- Defence: per works tier per arm, defender only, the holder only (a foreign
  column in the town gets 1000).
- Garrison: GARRISON in a held town → that town + morale bonus; GARRISON in
  the field → "" and no bonus; arrival in the field → field camp.
- Hand-computed `power` for one regiment in the field, in an unwalled town
  and behind walls.
