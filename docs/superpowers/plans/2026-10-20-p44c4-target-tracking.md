# P4.4c4 — known-target tracking and the limited search

Scope: item 4 of `2026-10-19-p44c1-gait-arithmetic.md`. A crown unit whose
current RECEIVED unit task is a flank (`flank`) or a pursuit (`legal_action`
`pursue`) with a `target_unit`, and which stands in no battle, marches at the
target's position AS ITS OWN SIGHT KNOWS IT. Out of sight it aims at the last
point it saw and searches for a bounded time; failure ends the task with the
unit garrisoned where it stands awaiting orders, and a later sighting never
revives it. Builds on c3 (`pursuit` bounds credit the metres this march walks).

Approved design: spec `2026-10-17-unit-behavior-and-battlefield-design.md` §2
rule 10, §9 (follow the known enemy; on lost sight stop updating the true
coordinates, go to the last known position, search with range, time and route
policy from config, the search never reads hidden positions; failure → garrison
and wait; re-sighting only reports), §12 (known-target snapshot, time and search
budget saved), §14 (target turns, lost sight, interception and search failure
all have explicit results).

## Contract

- **The recipient's own sight**: the target (a foe with men under arms,
  `Sighting.men_of > 0`) is seen when its true position is within
  `player_sight_km` of the RECIPIENT's position (whole-metre squared distance,
  inclusive). Never the crown-wide sight, never `GameState.sightings`, never the
  player's camera.
- **Saved snapshot** on the received task record: `track = {x_m, y_m, day,
  phase: "follow" | "search", search_until_day}` (absent until the first day it
  is tracked; old saves default to no track).
- **Once a day** (`BattleTaskSystem.track_day(repo, state)`, called by
  `TickEngine` at the top of `MARCH_ORDERS_AND_ROUTE_SETUP`, before the march
  entries and budgets freeze; idempotent per absolute day via a saved
  `track.done_day`): for each crown unit in code order with such a task and in
  no battle (`BattleSystem.battle_of` empty), not captured, with a fit man:
  - seen → `track` = the target's true point, today, phase `follow`; the unit
    marches at that point (a re-aim of a marching unit never restarts camp
    packing; a camped unit packs as any local order does).
  - not seen, phase `follow` → it marches at the saved point; once it stands on
    it (arrived, order garrison at the point) the phase becomes `search` with
    `search_until_day = today + battle_search_days`.
  - phase `search`: it holds at the point. The target seen within
    `battle_search_range_m` of the saved point → back to `follow`. Today past
    `search_until_day` → the record transitions to `search_failed` ("Lost the
    target and the search found nothing"), the unit halts (`BattleSystem._halt`).
  - `search_failed`, `bounded` (c3), `replaced`, `cancelled` are terminal: never
    tracked again.
  - Contact with the target (or with an interceptor) is the existing contact
    rule: a battle starts and the unit is in it, so tracking pauses; the task
    stays received.
- **Running**: `UnitGait.refresh` gains reason `pursuit` (until `task_end`):
  a current received pursuit task in phase `follow`. Flank walks.
- **CSV**: `battle_search_days` and `battle_search_range_m` in
  `data/battle/balance.csv` with notes.

## Implementer rulings pending the owner

1. Only crown recipients track; a foe's destination stays `EnemyAi`'s.
2. The search stands at the last known point and watches (its sight covers the
   ground); no search route is walked. `battle_search_range_m` limits which
   re-sighting resumes the follow.
3. Default `battle_search_days` 2 and `battle_search_range_m` 8 000.
4. The recipient's own sight radius is `player_sight_km`; scouting sectors are
   not counted.

5. (implementer) A marching unit is re-aimed with `ArmySystem.aim_entry`, which
   never calls `CampSystem.request_departure`, so packing is not restarted (a
   saved `departure` just gets the new dest); only a standing unit goes through
   `set_march_m`, which packs a camped one as any local order does.
6. (implementer) `UnitGait` reason `pursuit` is checked after `withdrawal` and
   before `join_battle`; only a pursuit (legal_action `pursue`), not a `flank`,
   runs. Its stop condition (`task_end`) is `BattleTaskSystem.pursuing` false.
7. (implementer) "On the point" is exact whole-metre equality of the unit and the
   saved point with the unit no longer marching; a unit halted short of it by a
   blocker is re-aimed each day (no extra cap; contact or the task's own bounds
   end it).
8. (implementer) A sighting in `search` farther than the range from the point
   changes nothing (no snapshot update, search clock keeps running). A target with
   no state entry or no men is simply unseen. No sighting ever = no snapshot, no
   march (the unit keeps what it did).
9. (implementer) Search day arithmetic: `search_until_day = today + days`; fails
   when `today > search_until_day`. All hand checks held as written against the
   real engine; the red run (code reverted) failed on the missing `track_day`.

## Hand checks (tests/engine/test_target_tracking.gd)

Flat open ground fixture as in `test_unit_gait_march.gd`; a target foe placed
by hand.
- Target 5 000 m east, in sight: after `track_day` the unit's dest is the
  target's point, `track` = that point, phase follow.
- Target then moved 20 000 m away (out of 12 000 m sight): `track_day` keeps the
  old point as dest (no true coordinate read).
- Unit placed on the saved point: phase search, `search_until_day` = today + 2.
- Day + 3 with no sighting: status `search_failed`, unit garrisoned in place;
  target then placed in sight: still `search_failed`, dest unchanged.
- During search, target seen 6 000 m from the point → follow; seen 9 000 m from
  it (but within sight) → stays search.
- A pursuit in follow saves gait reason `pursuit`; a flank does not run.
- JSON roundtrip keeps `track`.

## Steps

1. Tests red. 2. Code, CSV keys green. 3. `battle_deployment.md` paragraph on
tracking and search. 4. `--fast` green; one PR.
