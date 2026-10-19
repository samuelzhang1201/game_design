# P2-B1 — the family-loss consequence (pure)

Scope: the first of three slices closing the P2 leftover "cause-aware family
effects and their P4 context hooks" (`docs/reviews/battle-system/P2.md`
Remaining; plan `2026-10-16-battle-system/02-roster-and-recruitment.md` line
118). This slice is the pure, replay-safe consequence; B2 hooks it into battle
rounds, B3 into capture. Today `BattleReport` reads `battle["family_changes"]`
(battle_report.gd:141) but nothing writes it.

Approved design (plan line 118): named commander and noble cadre losses produce
relationship consequences recorded by family; the reason names the battlefield,
the loss and the order; re-settling the same round never applies twice; fixture
family loss of 1 person → relationship −2 (the coefficient is for the hand test
only — production values live in data). Root invariant 4: every opinion change
carries a reason at creation.

## Contract

- `FamilyLosses.consume(repo, state, loss_id: String, changes: Array, context:
  Dictionary) -> Array` in new `scripts/engine/family_losses.gd`:
  - `changes`: cohort-level personnel transitions as `MilitaryRoster` records
    them (`{unit_code, cohort id, from, to, count}` — implementer: use the exact
    shape `_apply_transition` produces). Only NOBLE cohorts (identity `noble`)
    moving `fit`/`wounded` → `dead` or → `captured_current` count; wounded
    transitions do not.
  - cause = `dead` or `captured`; kind = `named` (the cohort has a `person_id`)
    or `cadre`. Grouped by the cohort's `family_name` (empty family → skipped).
  - For each family, every Character of that family in the PLAYER's realm (court
    members/characters bound to the family; implementer: find the existing
    family → characters lookup used by prisoner disposition), in id order:
    `Character.change_opinion` (or the existing opinion API) by
    `count × bal("family_loss_opinion_<cause>_<kind>")`, reason
    `"<amount>: <family> lost <count> <kind> (<cause>) at <context.place> under
    <context.order>"`.
  - Returns the applied rows `{family, person, delta, reason}` (sorted).
  - Replay guard: `state.military_events["family:" + loss_id]` saves
    `{request, result}`; the same request returns the saved result unchanged;
    a different request under the same id returns `{error}` and changes
    nothing.
- CSV `data/battle/balance.csv`: `family_loss_opinion_dead_named`,
  `_dead_cadre`, `_captured_named`, `_captured_cadre` (first drafts −3, −2, −2,
  −1, notes saying first draft).

## Implementer rulings pending the owner

1. Amount per head by cause and kind; no per-family cap per battle.
2. Wounded nobles do not count.
3. Only the player realm's families are affected (foreign families toward their
   own ruler are not modelled here).
4. A dead named commander's Character is not marked dead here (open question
   for the owner).

## Hand checks (tests/engine/test_family_losses.gd)

- Key `_dead_cadre` set to −2 in the test; family Harrow with one member at
  opinion 10; one Harrow noble cadre fit → dead: opinion 8, one row, reason
  contains the place and the order.
- Same loss_id again: still 8; also after `GameState` JSON roundtrip.
- A commoner death: no change. A wounded noble: no change.
- Two Harrow members: both −2.
- Same loss_id with a different request: `{error}`, state hash unchanged.

## Steps

1. Tests red. 2. Code + CSV green. 3. One paragraph in
`scripts/engine/guide/battle_and_ai.md` (or the guide that covers personnel)
and the engine `CLAUDE.md` index. 4. `--fast` green; one PR.

## Implementation notes (recorded)

Additional implementer rulings pending the owner:

5. `consume` returns `Variant`: the applied rows `Array`, or `{error}` for a rejected request (the contract's `-> Array` cannot carry the error).
6. Row shape B2/B3 must pass is the `MilitaryRoster` transition row `{cohort_id, from, to, count}` (not `unit_code`); `context` is `{place, order}`. Cohorts are looked up in `state.military_cohorts`; a missing cohort is skipped.
7. Family members are Characters with `family_name == family` and `kingdom == resolve_realm("player_realm")`; opinion moves via `Character.change_opinion(delta, reason, state.tick)`.
8. Per family, one row per (member, cause+kind slot) so each reason names its own count; zero-valued keys apply nothing.
9. The replay key is `military_events["family:" + loss_id]` with `{request: {changes, context}, result: rows}`; an empty `loss_id` is an error.
10. Hand check of the 2-head case: 2 x -2 = -4, so opinion 10 -> 6 for each of the two Harrow members.
