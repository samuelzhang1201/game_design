# Army split and ground: pure-arm units that each hold their own ground — design

Owner request 2026-10-07 (item 14 of the fourteen-item army brief; supply,
items 1–7, is `2026-10-07-army-supply-lines-design.md`; laws and
foraging/desertion are sub-projects of their own):

> 14. 把开局军队拆分成 40 支左右、每支 300–1000 人的部队，不新增兵力。

**Status: BUILT 2026-10-08 on feat/army-split (not yet merged); the slot pitch and the look await the visual review.**
The owner's answers, in order:

- split rule A — "有多少人就是多少人，不要因为不到300就合为一队。只要纯兵种部队，所有单位在地图上不要重叠，就近放在一起即可。数量marker也不要重叠";
- artillery B — one royal artillery train per kingdom;
- the cap — "okay 600";
- scope A — every kingdom;
- ground —
  > 每个城镇只能有一只城镇驻军，其他驻军则需要城外，不合成计数牌，推翻10 月 6 日的规则，每支部队真的占一块地。几支部队开往同一个目的地时，各自自动落在相邻的位置上，像排兵布阵。更真实
- outside the walls A — the suburbs ring feeds but does not shelter;
- the seat A — first come first in, the largest infantry at the start, a swap order;
- formation A — hex rings by arm;
- royal A — a fixed household unit;
- where the split happens — **方案三** (at campaign start, into the save);
- old saves — refused, no migration;
- multi-select — "多选放进这次".

**Build order.** War-system work ahead of its PRD §6 place, by the owner's
direct request (2026-10-07), like the supply sub-project.

## 1. What changes

| Today | After |
|---|---|
| A kingdom's army is its pack regiments, mixed arms (kelvarn: 12 land regiments of 500–2,000 men) | Every regiment is split into PURE-ARM units of at most `army_split_cap_men`, each its own piece (kelvarn: 41 land units, one royal artillery train, two fleets; about 336 units across the pack) |
| The army is read from the pack (`repo.regiments`) | The army is a ROSTER in the save (`state.army_roster`), split once at campaign start; the pack's `regiments.csv` is only the split's input |
| A regiment standing within a town's reach is IN the town (walls, garrison morale, free supply) | ONE unit per town holds its SEAT (walls, garrison morale, free supply); others within the reach CAMP in the suburbs (free supply only); beyond it is the field |
| The regiments quartered in a town are drawn as one garrison counter | No garrison counter: every unit is its own piece on its own ground (overturns the taste ruling of 2026-10-06) |
| Several regiments sent to one point stand on top of each other | Each settles into the nearest free slot of a hex ring around that point, by arm |
| The crown goes to the land regiment nearest the capital | The crown goes to a fixed household unit (`is_royal`) |
| One regiment is ordered at a time | Shift-click / box-select several units; one order sends a courier to each |

Unchanged: the headcount (no unit is added or lost by the split), every
formula on a regiment row (power, pace, supply use, morale, training),
fleets, couriers, supply lines, combat, straight-line marching.

## 2. The roster (state)

### 2.1 `GameState.army_roster` (saved)

`unit_code -> row`. A row has the SAME SHAPE as a `military/regiments.csv` row:

- `regiment_code`, `kingdom_code`, `province_code`, `label`;
- `x`, `y`: the start position, pack px;
- `infantry`, `archers`, `cavalry`, `artillery`, `fleet`, `is_naval`.

It adds two columns:

- `parent_code`: the pack regiment it came from, or `""` for a royal train;
- `is_royal`: `"1"` for the household unit, else `"0"`.

Every kingdom's units are in it, not only the player's. Because a row keeps the old shape, every formula that reads a regiment row works on a unit unchanged. A pure-infantry unit is a regiment whose other arms are 0.

`state.regiments`, the player's per-unit morale, stores, orders and position, keeps its meaning, keyed by unit code.

### 2.2 `GameState.town_seat` (saved)

`town_code -> unit_code`: at most one unit per town. A town missing from it has an empty seat. §3 defines it.

### 2.3 Save version

`SAVE_VERSION` goes from 5 to 6. `SaveLoad` refuses a save below 6, and the load screen says the army's organisation changed and a new campaign is needed. There is no migration.

### 2.4 The one way in

New in `ArmySystem`:

- `roster(repo, state) -> Dictionary`, the roster;
- `regiment(repo, state, code) -> Dictionary`, one unit.

`regiment(repo, code)` gains the `state` argument. When `state` is null (the editor, the war room's and the 3D map's previews, some tests), both fall back to `ArmySplit.split(repo)`, cached per repo like the town grid.

A guard test fails on any read of the pack table under `scripts/` other than `ArmySplit`'s: `repo.regiments`, or `world_table("military", "regiments")`. `MapObjects.regiments_of` and `Map3DContext.regiments()` read the roster.

## 3. The split (`scripts/engine/army_split.gd`, pure)

`ArmySplit.split(repo) -> Dictionary` (the roster) is deterministic: the same pack always gives the same roster. It is called once by the new-campaign path, and the result is written to `state.army_roster`.

The numbers live in a new table, `data/army_split.csv` (key, value, notes):

- `cap_men` 600;
- `arm_order` `infantry|archers|cavalry`;
- `start_ring_infantry` 1, `start_ring_archers` 2, `start_ring_cavalry` 3;
- `slot_spacing_m` (set in the visual review, §7);
- `max_rings` (the farthest ring searched for a free slot);
- `blocked_terrain` `mountains`.

### 3.1 The rule

For each land regiment of the pack, in `regiment_code` order:

1. **Split by arm.** For each arm in `arm_order` with men > 0, make `n = ceil(men / cap_men)` units. The men are split as evenly as possible: the sizes differ by at most one, the larger first. Fewer than 300 men is still one unit; nothing merges.
   - Example: 2nd Somerlis's 1,268 horse makes three units of 423, 423 and 422 men.
2. **Codes and labels.**
   - Code: `<parent>_foot`, `<parent>_archers`, `<parent>_horse`. When `n > 1`, add `_1`..`_n`.
   - Label: the parent's label plus Foot / Archers / Horse, plus I..n when `n > 1`.
   - A parent with a single arm keeps its label: "12th Garestedmin Archers" stays as it is, with a numeral only when it splits.
3. **Artillery.** All of a kingdom's artillery, summed over its regiments, makes ONE unit: `<kingdom>_royal_train`, "Royal Train of <kingdom label>", at the capital, with `parent_code` `""`.
   - kelvarn's train has 75 men.
   - A kingdom with no artillery has no train.
4. **Fleets** pass through unchanged: same code, same row.
5. **The royal household.** Take the land regiment nearest the capital; ties go to the earlier code. Its largest horse unit (by men, ties by code) is `is_royal = "1"`. With no horse, use its largest foot unit; with no foot, its largest unit.
   - The flag never moves: the crown marches with that unit.
   - The royal train is the crown's but is not `is_royal`: it is drawn as artillery.

Totals:

| | Land units | Royal train | Fleets | Total |
|---|---|---|---|---|
| kelvarn | 41 | 1 | 2 | 44 |
| whole pack | | | | 336 |

A test holds that the men of every arm, summed per kingdom, are equal before and after the split.

### 3.2 Start positions

The split also places every unit (§4.3), so a roster row's `x`, `y` is its starting ground and no two units stand on one slot. The seats are filled as §4.4 says and written into the new campaign's `state.town_seat`.

## 4. Ground (`scripts/engine/army_ground.gd`, pure statics)

Only STANDING land units hold ground: those not under a march order. A unit on the march holds none, so columns pass through each other. Fleets never hold ground.

### 4.1 Seat, suburbs, field

- **The seat.** `ArmyGround.seated_in(repo, state, code) -> String` returns the town whose seat the unit holds. That town must be one its own kingdom holds (`MapOwnership.owner_of` of the town's province).
- **The suburbs ring.** The existing reach (`data/army_town_reach.csv`, read by `ArmySystem.town_at` and `held_town_of`) now means the suburbs ring.
- **Camped.** `ArmyGround.camped_by(repo, state, code) -> String` returns the held town whose ring a standing unit is in, or "" when there is none. The seated unit counts as camped by its own town.

What each place earns:

| | Town works (walls, citadel) | Garrison morale mark | Free supply from the town (supply spec, option A top-up) |
|---|---|---|---|
| Seated | ✓ | ✓ | ✓ |
| Camped in the ring | ✗: fights on the field's terrain | ✗ | ✓ |
| Field | ✗ | ✗ | ✗: carried stores or a supply line |

The readers move as follows:

- `ArmySystem.works_of`, the morale mark, and the LEDGER's "garrisons in" thread read `seated_in`.
- The supply top-up reads `camped_by`.
- `SupplySystem.garrisoned_in` is replaced by those two.
- `ArmySystem.quartered_in` is deleted.

### 4.2 The hex rings

Around a centre point, the slots lie on a hex lattice of pitch `slot_spacing_m`, in whole metres:

- Ring 0 is the centre. Ring k has 6k slots.
- Within a ring, the slots are taken starting east and going counter-clockwise, in a fixed order.

The free slot for a unit of arm A, around a centre:

1. Take the first slot, in ring-then-index order, at ring ≥ the start ring for A that is:
   - on land: `MapEconomy.cell_at ≥ 0`;
   - not on a terrain listed in `blocked_terrain`: `ArmySystem.terrain_at`;
   - not within `slot_spacing_m / 2` of another standing land unit of any kingdom.
2. The ring-0 slot is special:
   - at a town centre it is the SEAT and never a camp slot;
   - in the field, a unit takes it when it is free, whatever its arm.
3. If nothing is free within `max_rings`, the unit stands where it arrived.

### 4.3 Settling on arrival

`ArmyGround.settle(repo, state, code)` runs on a unit's arrival day, as `ArmySystem._march_one` returns true. It walks the arrivals in code order, the same order as `march_day`. The march itself still ends on the point that was ordered. Settling then works like this:

1. **Centre.** If the ordered point lies in the ring of a town its kingdom holds, the centre is that town's point; otherwise it is the ordered point.
2. **Town centre.**
   - If the seat is empty, the unit takes the seat and stands on the town's point.
   - Otherwise it takes the free slot for its arm (§4.2).
3. **Field centre.** It takes the free slot for its arm.

The slot is fixed on ARRIVAL, not when the order is sent: first come, first in. The map slides the piece the last few hundred metres.

At the campaign start, `ArmySplit` places units with the same rule:

- **Parents.** Each pack regiment's units, in arm order, settle around a centre. The centre is the town's point when the regiment stands in a town's ring, and its own point otherwise. Kingdoms go in code order, then regiments in code order.
- **Royal trains.** Each royal train settles last, around its capital.

### 4.4 Who holds the seat

- **Campaign start.** For each town, the candidates are the land units of the town's holder camped in its ring. The seat goes to the one with the most infantry, ties by code. With no infantry it goes to the largest unit. The unit steps onto the town's point, and its slot is left empty.
- **An arrival** takes an empty seat (§4.3).
- **The seat empties** when the seated unit's march order takes effect (its courier arrives). The same day, the seat is refilled by the start rule, picking among units camped in the ring that are not on the march; the chosen unit steps in.
- **The town is lost.** At the province-owner reconcile, a seat whose town's province is no longer held by the seated unit's kingdom is cleared.

### 4.5 The swap order `ARMY_SEAT`

An ordinary action, so it has rows in:

- `action_signatures`;
- `order_costs` (gold −1, "the change of the watch");
- `policy_actions_court_additions`;
- `army_orders`.

For a land unit camped by a held town, it rides by courier from the capital like `ARMY_MARCH`. When the courier arrives:

- the unit takes the seat;
- the unit that held it, if any, takes the slot the newcomer left;
- if the newcomer is no longer camped by that town, the order lapses with a news line.

The right-click menu shows it only on a camped unit that is not seated:

- "Take the seat" (入城换防) when the seat is held;
- "Garrison the town" (入城驻守) when the seat is empty.

## 5. The map and the war room

### 5.1 3D map

- Every unit is its own piece. `MapObjects.garrisons` and `garrison_of` are deleted, along with the layer's town-counter path (`map3d_layer_units.gd`, about lines 116–118).
- A seated unit's piece stands on its town's point.
- `MapObjects.royal_regiment` is deleted. `army_piece` returns "royal" for `is_royal == "1"`.
- The royal train is drawn as artillery.
- The 3–9 figures per piece by strength are unchanged (`Map3DFormation`).

### 5.2 Nothing overlaps on screen

`Map3DDeclutter.place(boxes: Array, priority: Array) -> Array` is pure. It takes screen boxes in design px and returns a position for each one, or none for a box that hides.

- Each box starts on its anchor.
- If it touches a box already placed, it tries the offsets of a fixed outward spiral, up to `map3d_declutter_max_px`, and takes the first clear one.
- Boxes are placed in priority order: the selected units, then the royal unit, then by men (descending), then by code.

It is used in two places:

- **Far-out counters** (`map3d_hud_armies.gd`): every counter is placed, and none is hidden or merged. If the spiral runs out, the counter takes the clearest offset it found.
- **Headcount chips:** a chip that finds no clear offset hides until the camera comes closer.

### 5.3 Performance

The player's pieces go from 14 to about 44, which is about 400 animated figures instead of about 126. The plan runs the 3D bench (`tools/map3d/bench.gd`) before and after. If a gate in `scripts/map3d/CLAUDE.md` fails, pieces that are off-screen or beyond a CSV distance have their `AnimationPlayer` paused. No art changes.

### 5.4 War room

- One oak piece per unit.
- On the table's scale, nearby units are spread by the same `Map3DDeclutter`, applied only to the display; the engine's positions are unchanged.
- The war room keeps single selection.

### 5.5 Lists and letters

These lists are grouped under their parent regiment's label, with the royal household and the royal train first:

- the war folio;
- the HUD army list;
- the order menu's regiment pickers;
- the marshal's monthly supply report.

The supply letters' keep count is unchanged.

### 5.6 Multi-select (3D map)

- Shift-click toggles a unit in or out of the selection.
- A drag on empty ground draws a selection box. The box selects the player's land units whose pieces' screen boxes it touches.
- A plain click selects one unit, as today.
- The right-click menu's orders apply to every selected unit that can take them: `ARMY_MARCH`, `ARMY_GARRISON`, the supply orders and `ARMY_SEAT`. Each order is its own action, with its own courier and its own `order_costs` charge, so units farther away arrive later and settle later.
- One aimed "March…" click sends every selected unit to the same point, and §4.3 spreads them out on arrival.
- The selection lives in the map's UI state, never in `GameState`.

## 6. Guidance and taste

- `.claude/skills/visual-review/taste.md`: the 2026-10-06 rule "A garrison is its town's counter" is replaced by: every unit holds its own ground; one unit per town holds the seat, and the rest camp outside in hex rings; nothing is merged, and no counter or chip overlaps another.
- `scripts/engine/CLAUDE.md` (29,958 chars) and `scripts/map3d/CLAUDE.md` (30,066 chars) are at their caps. Each gets a short current-rule paragraph pointing here. Room is made by moving older detail into its own specs, never by adding history.
- `data/CLAUDE.md` names `army_split.csv`. `regiments.csv` is the split's input, not the live army.

## 7. Testing

**Pure functions, with hand-computed values:**

- `ArmySplit.split` on the pack's kelvarn rows:
  - Somerlis horse 423/423/422;
  - 44 units;
  - royal train 75 men;
  - the royal household is the nearest regiment's largest horse.
- Headcount per arm and kingdom is conserved across all kingdoms, and the result is deterministic across two calls.
- Codes, labels and numerals, including a pure-archer parent.
- Hex ring order, start rings by arm, blocked terrain and water skipped, ring 0 in a town vs the field, and the `max_rings` fallback.
- `Map3DDeclutter.place`:
  - no two placed boxes overlap;
  - the highest priority never moves;
  - the result is deterministic.

**Rules:**

- At start, no two standing land units lie within `slot_spacing_m / 2` of each other.
- Every town has at most one seat holder.
- First come, first in: two units reach a town on consecutive days.
- The seat refills on a march-out.
- `ARMY_SEAT` by courier swaps two units, and lapses when the newcomer has left.
- A lost town's seat is cleared.
- Works and morale go only to the seat, supply to the seat and the ring.
- Old saves (version < 6) are refused.

**Guard:** no reader of the pack regiments table under `scripts/` other than `ArmySplit`.

**Existing tests:** about 40 files read `repo.regiments`. They move to `ArmySystem.roster` and `regiment`, still deriving the kingdom and positions from the pack; none names a pack or a realm. `SuiteData.campaign` caches a split roster.

**UI, through real input:** shift-click, box drag, then the right-click menu dispatching one courier per unit (`verify-ui-through-real-input`).

**Visual** (the visual-review skill, real-window shots, never `--headless`):

- the capital's camp rings close in;
- the far-out counters spread;
- no chip overlaps another;
- `slot_spacing_m` is set here from the piece's footprint.

## 8. Build order

Each step ends with the full suite green at the expected error count.

1. `ArmySplit`, the roster in the save, save version 6, and the one way in (`roster` / `regiment`). Every reader moves; this is behaviour-neutral apart from the unit count.
2. `ArmyGround`:
   - rings, seat, settle on arrival, start placement, seat refill and loss;
   - works, morale and supply rebased on `seated_in` / `camped_by`.
3. `ARMY_SEAT`: action rows, courier effect, menu rows.
4. Map:
   - one piece per unit, no garrison counter, crown by `is_royal`;
   - `Map3DDeclutter` for counters and chips;
   - the bench and, if needed, the animation pause.
5. Multi-select and orders to the selection.
6. War room pieces and declutter, list grouping, guidance files, the taste rule, the visual review.

## 9. Not in this sub-project

- Merging units.
- Recruiting.
- Pathfinding: marching stays straight-line.
- Changes to combat.
- How foreign units are shown (unchanged: through intel).
- Multi-select in the war room.
- Laws (sub-project C), and foraging, plunder and desertion (sub-project B).

## 10. Implementation rulings

Where the build departs from the wording above, as the plan ruled it (R1-R7) and as the later tasks found it (R8-R12).

- **R1 - argument order.** `ArmySystem.regiment(repo, code, state := null)`, `ArmySystem.roster(repo, state := null)` and `MapObjects.regiments_of(repo, kingdom, state := null)` keep the existing order and append an optional state, so ~90 call sites are not touched at once; every engine call site with a `state` in scope passes it.
- **R2 - data layout.** The single key/value table becomes per-arm rows in `data/army_split.csv`, the scalars in `data/balance.csv` (`army_split_cap_men`, `army_slot_spacing_m`, `army_slot_max_rings`, `map3d_declutter_step_px`, `map3d_declutter_max_px`, `war_spread_step_m`, `war_spread_max_m`) and the blocked terrains in `data/army_camp_blocked.csv`: the repository's existing shapes, the same values.
- **R3 - camped means settled around the town.** `camped_by` reads the town a unit SETTLED around (`camp_town`), not the distance to the town, because the hex rings can reach past a village's reach and a unit settled around its town is still fed from it.
- **R4 - Shift for the box.** A plain left drag pans the camera, so the selection box is a Shift + left drag and a Shift + left click toggles one unit.
- **R5 - lists.** The war folio shows one unit at a time; grouping applies to the MILITARY panel's rows and the marshal's monthly report, through one ordering function, `ArmySystem.ordered`.
- **R6 - seat menu rows.** The seat rows are `data/army_route_orders.csv` keys `seat` and `seat_empty`, added by `ArmyOrderMenu._open_for` only for a camped unit that is not seated.
- **R7 - split cache.** `ArmySplit` caches the pack's split per repository instance and keeps at most four entries.
- **R8 - `ARMY_SEAT` stays single-unit in a multi-selection.** Two units camped by one town would both pass validation and both ride and pay for one seat.
- **R9 - `any_terrain` retry.** `ArmyGround.is_free` and `free_slot` take `any_terrain`, and both `ArmySplit._place` and `ArmyGround.settle` retry with it before keeping the arrival point; a town ringed by blocked terrain would otherwise stack its units.
- **R10 - a halted column settles.** `set_garrison` settles a column that was halted mid-march: it takes a seat or a slot and gets its `camp_town`.
- **R11 - the box takes land units only.** The Shift + drag selection box never picks a fleet.
- **R12 - `regiments_of` is sorted by code.** Callers that want the lists' order go through `ArmySystem.ordered`.
- **R13 - the household leads its list.** The royal household is a unit of its parent regiment, yet `ArmySystem.ordered` puts it first (before the royal train), so it stands apart from its regiment's other units in the lists.
- **R14 - the hover's garrison and works.** The WAR ROOM slip names the unit on a town's seat as its garrison and counts the rest of the camp ("N camped round it"). Its defend forecast gives a town's works to the unit on the seat, or to any unit of the holder while the seat is empty, since an arrival takes an empty seat (§4.3); a unit camped off the seat reads the field's terrain (§4.1).
- **R15 - a train with no capital.** A kingdom with guns but no capital keeps them: its royal train camps where its first land regiment (by code) stands, round that regiment's town when its kingdom holds it, else in the field, so the split adds and loses no man.
