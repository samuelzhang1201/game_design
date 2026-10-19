# P4.4c1 — integer walk/run speed and run supply increment

Scope: the pure integer contract for running: run ground speed from the walking
step of the same substep, and the per-substep run supply increment with a saved
fixed-point remainder, paid only after today's base ration is reserved. No caller
decides to run yet; no march, meal, task, data-schema or UI change.

Approved design: `2026-10-17-unit-behavior-and-battlefield-design.md` §5 (speed
120%, consumption 130% of the same duration for the actual running personnel,
base ration first, no free truncation, no overdraft), §12 (integer remainders in
the save) and §14's hand-computed fixtures. P4.4b's automatic continuation
authorizes this single slice.

## P4.4c split (each a separate PR, after the preceding merge)

1. **c1 (this)** `UnitGait.run_step_m` / `run_substep`; `army_run_speed_permille`,
   `army_run_supply_permille` in `data/army/balance.csv`.
2. **c2** a saved per-unit gait (`walk`/`run`, reason, stop condition) chosen by
   the commander only for the §5.1 reasons the engine can already see (a received
   retreat's withdrawal march, a march to join a known battle); `march_day_saved`
   scales the substep budget by `run_step_m` only for a substep `run_substep`
   affords, the base meal stays `eat_day`'s; camp packing is not shortened.
3. **c3** pursuit bounds on `BATTLE_TASK`: optional `max_route_m` and a region
   (provinces); the received task saves its start point and cumulative ROUTE
   metres (detours count, a same-meaning reissue keeps them, a new pursuit task
   restarts them); reaching either bound ends the task and the unit holds/garrisons
   awaiting orders. Bounds are checked by what the engine can already measure.
4. **c4** known-target tracking: a flank/pursuit task follows only the target's
   position as known to the recipient; on lost sight it aims at the last known
   point and runs a bounded search (range/days from CSV); failure ends the task
   with garrison-and-wait, and a re-sighting never revives it.

Group positions, movement ownership, contact feeding combat (P4.4d) and battle
merging (P4.4e) are out of every c-slice.

## c1 contract

- `run_step_m(repo, walk_m) = walk_m × army_run_speed_permille / 1000`, whole
  metres, applied after every existing walk modifier.
- `run_substep(repo, entry, base_bite, run_bite, substeps)`: `base_bite` is the
  unit's whole-day base meal still to be eaten (`day_bite`), `run_bite` the part
  of it belonging to the personnel who run. The increment numerator
  `run_supply_rem + run_bite × (army_run_supply_permille − 1000)` over
  `1000 × substeps` is charged in whole supplies; the remainder is saved as
  `entry.run_supply_rem`. If supplies are below the base, or the charge would cut
  into it, the substep walks and nothing (remainder included) changes.
- Hand checks: 100 → 120 m; 600 m is 6 walking / 5 running substeps; base 100
  costs 130 run all day, 115 half a day, 112 when only 40 of it runs; 600 m run
  costs 65 against 60 walked (1083‰); 3-a-day running pays nothing for 11
  substeps (remainder 9 900) and 1 at the 12th (remainder 800); 103 in hand with
  a 100 base runs one substep; JSON mid-day equals straight-through.

## Steps

1. `tests/engine/test_army_gait.gd` red (no class, no keys).
2. `scripts/engine/unit_gait.gd`, the two balance keys; green.
3. `battle_deployment.md` section and the engine index line; `./run_tests.sh --fast`;
   one PR.
