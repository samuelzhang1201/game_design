# P4.4c3 — pursuit bounds on the unit task

Scope: item 3 of `2026-10-19-p44c1-gait-arithmetic.md`. A pursuit unit task
(`task` whose `battle_behaviors.csv` `legal_action` is `pursue`) may carry a
farthest ROUTE distance and a region (provinces). The received task saves its
start point and the metres the unit actually walks; the first bound reached ends
the task and the unit holds where it stands awaiting new orders. No pursuit
movement is added here (c4 aims the pursuer at its known target); the bounds are
checked on what the engine already measures: the metres `ArmySystem.
march_day_saved` really walks and the province the unit stands in.

Approved design: spec `2026-10-17-unit-behavior-and-battlefield-design.md` §2
rule 11, §4 (one primary task), §9 last two paragraphs (route metres from where
it actually starts, detours count, a same-meaning reissue keeps the metres, a
new pursuit task restarts them; at the bound while still engaged it stops
advancing and defends, never teleports out; a bound never blocks self-defence;
re-entry does not restart a finished task), §12 (start point, metres and region
saved).

## Contract

- **Request fields** (`BattleTaskSystem._canonical` / `_format_error`):
  `max_route_m` (whole metres, int ≥ 0; 0 = no distance bound) and `region`
  (String: province codes joined by `|`, sorted and de-duplicated by
  `_canonical`; "" = no region bound). Both default (old saves and old requests
  canonicalize to 0 / ""). Either one set on a task whose `legal_action` is not
  `pursue` is refused ("Only a pursuit carries pursuit bounds."). An unknown
  province code is refused. `BATTLE_TASK` (ActionSystem) passes the two optional
  params through; `BATTLE_TASK_CANCEL` takes neither.
- **Progress** saved on the received record: `pursuit = {start_x_m, start_y_m,
  route_m}`, written at `deliver_task` from the unit's position when the
  received task is a pursuit. A received pursuit that replaces a current
  received pursuit with the SAME meaning (same battle, target_unit, max_route_m
  and region) copies the old record's `pursuit` (keeps start and metres); any
  other replacement starts fresh.
- **Credit**: `march_day_saved`, after a unit's substep walk, credits the metres
  it really travelled that substep (`travelled[0]`, detours included) to its
  current received pursuit via `BattleTaskSystem.credit_pursuit(repo, state,
  code, metres)`, which then checks the bounds: `route_m >= max_route_m` (when
  > 0) or the unit's province now (`ArmySystem.province_of`) not in `region`
  (when set). The province check also runs when 0 metres were walked.
- **Reaching a bound**: the record transitions to status `bounded` with the
  reason ("Pursuit reached its farthest route distance: N m" / "Pursuit reached
  its region's edge: <province>"); `current_id` stays on it. A unit that is
  marching halts where it stands (`BattleSystem._halt`: garrison, awaiting
  orders). In a battle, `combat_action` returns `hold` for a current `bounded`
  pursuit of that battle (defends, no pursuit, no withdrawal is started). A
  later re-sighting or re-entry never revives it; only a new received task
  replaces it.
- **Self-defence** is unchanged: a bounded unit still fights back as `hold`.

## Implementer rulings pending the owner

1. Region is checked on the unit's centre province, not its group positions
   (groups arrive in P4.4d).
2. A bounded pursuit holds rather than clearing the task, so the side's general
   order does not silently restart an attack.
3. The bounds sit on the existing `BATTLE_TASK`, not a new action.
4. The credit hook sits at the END of the per-unit block in `march_day_saved`
   (before `UnitGait.refresh`), not right after `day_walked_m`: the arrival and
   publish branches below it would otherwise overwrite the halt with the saved
   march. A bound also retires today's saved march (`_retire_saved_march`) so the
   remaining substeps do not keep walking.
5. A bounded record answers `hold` only for its own battle; a fight elsewhere
   falls back to the side action. Old pending requests lacking the new fields
   cannot be retried by id (their stored request differs from the canonical one).
6. A unit in a live battle does not march in `march_day_saved`, so the walk test
   clears the battles after receipt; the bound is credited by the walk alone.

## Hand checks (tests/engine/test_pursuit_bounds.gd)

- Format: `max_route_m` -1 refused; a `hold` task with `region` refused; region
  "b|a|a" canonicalizes to "a|b".
- A received pursuit with `max_route_m` 1 000 credited 400 + 400 stays received
  (route 800); + 300 → `bounded` at route 1 100 and the unit (marching) is
  garrisoned at its current position.
- Region: the unit's province not in the region → `bounded` with 0 metres.
- Same-meaning reissue keeps route 800; a different max_route_m restarts at 0.
- JSON roundtrip keeps `pursuit` and `bounded`.
- `combat_action` for a bounded pursuit returns kind `hold`.

## Steps

1. Tests red. 2. Code green. 3. `scripts/engine/guide/battle_deployment.md`
"Delivered unit pursuit" section: one paragraph on bounds. 4. `--fast` green;
one PR.
