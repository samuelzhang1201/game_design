# WAR ROOM front line: a drawn line becomes a held line (design)

**Owner 2026-10-11**: 帮我分析下 war room 战略地图中建立防线的那个 icon 能如何融合入游戏，目前就是画一道线而已没有任何功能（我的想法是建立防线后，大地图士兵会横过来排开，做出防线动作，同时有扎营模型？） — then, on the three-step proposal: 防线按你的三步做. No combat bonus was granted: a front only batches existing orders.

Architect's plan 2026-10-11 (read-only pass over the engine) is the source of the numbers below.

## §1 A blue front becomes drafts (step 1)

- Drawing a BLUE `front` stroke with our land regiments selected (`WarPlanInput.sel`, the fleets left out; all fleets: refused "Fleets are ordered on the map", the mark still drawn) plants ONE draft per regiment at once (`Game.plant_front`), no confirm: the resolutions scroll is the review (ruling 1a). The crayon arrows and pennants show them as any draft.
- `WarFront` (pure, `scripts/engine/`): the stroke's curve (`MarchRoute.curve` on its whole-metre `pts`, `army_route_sample_m`) cut into N equal lengths; post k is the middle of length k; its facing is the normal of the length's CHORD on the teeth's side (`flip` 0: `(-dir.y, dir.x)`, the drawer's right; 1: the left), a whole degree 0..359 in the pack's y-down frame (0 east, 90 south, 180 west, 270 north — `WarPlans` pieces' `facing_deg` convention).
- **Assignment** (ruling 2): regiments take posts in the order of their position's arc length along the line (projection; ties by code), so columns never cross. A refused regiment leaves its post empty.
- The draft is a MARCH to the post with `hold = {stance: "hold", facing}` and `front` = the stroke id; within 1 pack px of its post, a GARRISON draft with `hold`. `WarDrafts.requests_from` adds `ARMY_STANCE {stance, facing, on_arrival}` after the march, which rides the SAME courier (`CourierSystem.joinable`) — gold −2 march, −1 stance, one fee.
- **Delivery**: `on_arrival` parks the stance on the entry as `hold_after = {stance, facing, id}`; the day the march ARRIVES (`ArmySystem.march_day`) it becomes `stance_next` + `facing_deg` (newest stance order wins by id), and `BattleSystem.settle_stances` makes it the stance from the next day — in keeping with "a march that arrives garrisons where it stops". A new march, `aim_entry`, `set_garrison` or a battle's halt drops `hold_after` (ruling 3: caught on the road, no hold); a new march also clears `facing_deg`.
- State (whole ints, saved in `regiments` / `war_drafts`): `facing_deg`, `hold_after`, the draft's `hold` and `front`. `ArmySystem.facing_of` reads it (ZERO while marching); `piece_heading` = `heading_of` while marching, else `facing_of` — the room's piece and the 3D piece turn to it.
- Edit route… keeps the draft's `hold`; a new arrow drawn for the selection drops it. Flipping, reshaping or scraping the stroke leaves the drafts as they are (ruling 5).

## §2 The 3D map shows the line (step 2)

- `data/battle_stances.csv` gains `formation` (hold `line`, others `block`) and `stand_clip` (hold `DEFEND`); `data/army_formations.csv` gains `line_slots` (3: one rank; 6 and 9: one rank, ruling 6). `Map3DFormation.layout_of` picks the stance's layout when the regiment is not marching; `Map3DUnits.action_for` plays `stand_clip` (DEFEND, falling back to GARRISON when the model lacks it); the layer rebuilds a piece when its figures OR layout change, and re-reads the wanted yaw each frame so a facing set at day's end turns the piece without a camera move.

## §3 A camp after N days (step 3)

- `balance.csv` `camp_after_days` (5; 0 never). `regiments[code].hold_days` counts days settled in `hold`, not marching, in no battle, capped at the key (`ArmySystem.hold_day`, in `TickEngine` after the raids' day); a march, a stance change or a battle resets it. `ArmySystem.camped` = reached the cap, in the field only (ruling 4: not beside a town's seat).
- Art: `assets/3D/buildings/camp/camp.glb` → `scenes/models/buildings/camp.tscn`, ArtTable `assets/3D/buildings/camp_models.tres` key `camp` (`GameArt.CAMP_MODELS`), made in the editor when the model exists; `Map3DLayerUnits` seats it `camp_back_m` behind the line (`Map3DUnits.behind`) — a missing table or file is no error.

## Tests
Hand-computed in `tests/engine/test_war_front.gd`, `test_war_drafts.gd`, `test_army_stance_order.gd`, `tests/map3d/test_map3d_formation.gd` (the architect's tables T1.1–T3.4).
