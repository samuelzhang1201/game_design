# P2-B3 — captures feed the family-loss consequence

Scope: the last of three slices closing the P2 leftover "cause-aware family
effects" (B1 `FamilyLosses.consume` #125, B2 battle rounds #127). A capture
(`PrisonerSystem`'s capture event, whose personnel move through
`MilitaryRoster.transition(repo, state, "prisoner_capture:" + id, changes, …)`)
passes the cohort changes it applied to `FamilyLosses.consume`, so a noble's
family feels a capture (`family_loss_opinion_captured_named` / `_cadre`); the
rows land in the capture's battle `family_changes` when that battle still
exists.

Approved design: P2 plan line 118; root invariant 4.

## Contract

- In the capture path (prisoner_system.gd, right after the `transition`
  succeeds and before the batches are published), call
  `FamilyLosses.consume(repo, state, "capture:" + id, request["changes"],
  {place: <the battle's place_label, else "the field">, order: <the captured
  unit's own order/action kind at capture if known, else "capture">})`.
  Implementer: read what `request` carries (battle_id, round, reason) and pick
  the most truthful order word; record it as a ruling.
- Append the returned rows to the battle's `family_changes` (guarded by
  `family_loss_ids` as B2 does) when `BattleSystem.battle_by_id(request
  .battle_id)` is not empty.
- A replayed capture returns its saved record early and never re-calls consume;
  consume's own receipt would also make a second call inert.

## Implementer rulings pending the owner

1. The order word used for a capture.
2. Rows go into the battle's `family_changes` only while the battle exists.

## Hand checks (tests/engine/test_family_losses_capture.gd)

- `family_loss_opinion_captured_cadre` set to −1 in the test; a capture of 3
  Harrow noble cadre: the Harrow court member's opinion −3, one row, reason with
  "captured" and the place.
- Replaying the same capture id: unchanged.
- A capture of commoners only: no row.

## Steps

1. Tests red. 2. Code green. 3. One sentence in the "Family losses" section of
`scripts/engine/guide/prisoners_and_reports.md`. 4. `--fast` green; one PR.

## Implementer rulings (recorded)

1. Order word is the literal `capture`: the request carries only battle_id, round and reason, and the unit's round action is no longer known (pending is gone), so "capture" is the truthful word.
2. Rows go into `family_changes` only while the battle exists (guarded by `family_loss_ids`); otherwise just the opinion move and receipt.
4. A battle record with no `town` key (bare fixtures in older prisoner tests) has no place: the context place falls back to "the field" instead of calling `place_label`.
3. A consume `{error}` (cannot occur: id is the capture id, replay returns early) is ignored; the capture still applies.
