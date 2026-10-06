# Where a regiment stands: town, field, height — design

Owner request 2026-10-06: "我希望军事单位的地理位置数据跟随单位移动变动，准确反映当前军事单位所处的位置，如果在城市里则获得相应的城市防御加成，野外，高地等不同地理位置都应当准确反映".

**Status: DRAFT — awaiting the owner's ruling on §5.** Nothing here is built.

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
  thread. The card says "Encamped in the field".
- Supply is unchanged: a column standing anywhere in a province the crown
  controls still draws through the province capital with no road loss
  (`SupplySystem.stronghold_of`) — that is the supply rule, not the defence
  rule. (§5 asks whether to tighten it too.)

## 5. For the owner to rule

1. **Reach sizes** (§2): 3 / 2.5 / 2 / 1.5 / 1 km by group, or another
   measure (e.g. by population)?
2. **Defence numbers** (§3): the table above as the first draft?
3. **Starting positions**: most pack regiments stand 7–13 km from their
   namesake town (the 6th at Walbover 13 km), so under §2 they open the game
   in the field. Move the player's land regiments onto their namesake towns
   at the start? Then the crown's banner (`MapObjects.royal_regiment`, the
   land regiment nearest the capital) would go to whichever stands IN the
   capital — the 11th (Walbover) Archers stand 14 km out, so the 6th keeps
   it only if it moves in and the 11th does not.
4. **Supply** (§4): keep "anywhere in a controlled province draws through
   its capital", or require standing in a held town?
5. **March speed by ground** (raised in the same conversation, not asked
   for): a march today runs at one pace over every ground, road or not.
   A separate spec if wanted.

## 6. Tests (when built)

- `town_of`: at a burg's point → that burg; just inside / just outside its
  reach; two reaches overlapping → the nearer; a marched position, not the
  pack's.
- Defence: per works tier per arm, defender only, the holder only (a foreign
  column in the town gets 1000).
- Garrison: GARRISON in a held town → that town + morale bonus; GARRISON in
  the field → "" and no bonus; arrival in the field → field camp.
- Hand-computed `power` for one regiment in the field, in an unwalled town
  and behind walls.
