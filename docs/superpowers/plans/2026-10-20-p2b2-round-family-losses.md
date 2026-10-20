# P2-B2 — battle rounds feed the family-loss consequence

Scope: the second of three slices closing the P2 leftover "cause-aware family
effects and their P4 context hooks" (B1 = `FamilyLosses.consume`, merged in
#125). Every resolved battle round passes the personnel it actually moved to
`FamilyLosses.consume`, once per unit, with the battle's place and that unit's
order; the applied rows land in `battle.family_changes`, which `BattleReport`
already reads (battle_report.gd ~141). B3 does capture.

Approved design: P2 plan line 118 (losses by family; reasons name the
battlefield, the loss and the order; re-settling the same round never applies
twice); root invariant 4 (a reason on every opinion change).

## Contract

- `MilitaryRoster._apply_transition` also saves the cohort-level `changes` it
  applied in its receipt's result (`military_events[event_id].result.changes`,
  the `{cohort_id, from, to, count}` rows `FamilyLosses.consume` takes). A
  replayed receipt returns them too; an old receipt without them reads as none.
- `BattleSystem` round settlement (right after `apply_round` succeeds, at the
  `"battle:%d:round:%d"` call): read the round's personnel receipt
  (`event_id + ":personnel"`), group its changes by the cohort's `unit_code`,
  and for each unit in sorted code order call
  `FamilyLosses.consume(repo, state, "battle:%d:round:%d:%s" % [id, n, code],
  that unit's changes, {place: place_label(...), order: <that unit's action
  kind from pending.unit_actions, else its side's context kind>})`; append the
  returned rows (skip an `{error}` — record why it cannot happen) to
  `b.family_changes` (create as `[]`).
- A retried/replayed round re-calls consume with the same id and request: it
  returns the saved rows and applies nothing; the rows must not be appended
  twice (guard: skip appending when the battle already holds rows for that
  loss id — implementer: pick the cleanest guard and state it).
- Check what row shape `BattleReport` expects from `family_changes` and match
  it (adapt the report reader only if it expects something else; record).

## Implementer rulings pending the owner

1. One consume per unit per round (its own order in the reason).
2. Order word = the unit's action kind; place = `place_label`.
3. The append guard against a replayed round.

### Recorded rulings

- Rulings 1-3 as above. Guard: `battle.family_loss_ids` (consume ids already appended), saved with the battle.
- Order word = `pending.unit_actions[code].kind`, else the side context kind.
- Rows are consume's `{family, person, delta, reason}` appended as is; `BattleReport` copies them verbatim, so no reader change. `battle_report_panel.gd` reads `name` (falls back to "Family standing"): left alone, a UI follow-up for the owner.
- Tests use noble cadre cohorts (dead_cadre = dead_named = -2), not a named commander; named shares consume's code path (covered in test_family_losses.gd).
- No existing assertion adapted unless listed in the final report.

## Hand checks (tests/engine/test_family_losses_battle.gd)

- A battle round (hand-built battle, tier forced so a named noble commander of
  a Harrow cohort dies; `family_loss_opinion_dead_named` set to −2 in the test):
  the Harrow court member's opinion falls by 2; `b.family_changes` has one row
  whose reason contains the battle's place label and the unit's order.
- Re-running the same round id (same-day retry path): opinion unchanged, still
  one row.
- A round killing only commoners: no row.
- JSON roundtrip of the state between the round and the retry: same result.

## Steps

1. Tests red. 2. Code green. 3. One sentence added to the "Family losses"
section of `scripts/engine/guide/prisoners_and_reports.md`. 4. `--fast` green
(+ simulation, gameplay); one PR.
