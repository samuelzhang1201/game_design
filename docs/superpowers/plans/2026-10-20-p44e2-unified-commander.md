# P4.4e2 — one commander per side when battles merge

Scope: the second slice of P4.4e (after e1's `BattleMerge`). A merge is the one
moment two command relations unify: each side of the surviving battle picks ONE
battlefield commander from the two sources' commanders; afterwards the existing
rule holds (`BattleCommand.update_battle`: a fit incumbent stays, an ordinary
reinforcement never re-elects, only incapacity hands over).

Approved design: spec `2026-10-17-unit-behavior-and-battlefield-design.md`
§11.2: each side picks a unified commander; a valid explicit battlefield
appointment wins; if both sources have one, the implementation default is the
appointment with the newer order sequence, then the stable person id; with no
valid explicit appointment, the original design's military ability, prestige,
stable id (`BattleCommand.select`); the one not chosen commands his own unit;
merging is one selection, ordinary reinforcement does not re-select, the
unified commander is replaced only when incapacitated; units' own tasks stay,
formations, agreements and personal roles are not reset.

## Contract

- `BattleCommand.unify(repo, state, survivor, source: Dictionary, side_map:
  Dictionary) -> Dictionary` (called by `BattleMerge._merge` right after the
  union; `source` = the absorbed battle's saved `sources[id]` record,
  `side_map` = absorbed side → survivor side by allegiance):
  - per survivor side: candidates = the survivor's `commanders[side]` and the
    source's `commanders[mapped]`, each kept only if still eligible for a unit
    now on that side (`MilitaryCommanders.eligible_for_unit` against the
    unit whose roster names him — as `update_battle` checks).
  - explicit nominees: `commander_nominees[side]` of either battle (survivor's
    own, source's mapped). If one valid nominee exists he is chosen. If both,
    the one whose battle carries the higher `commander_nominee_seq[side]`
    (absent = 0), ties → the smaller person id.
  - else `BattleCommand.select(state, candidates, "")`.
  - writes `survivor.commanders[side]` and, when a nominee won,
    `survivor.commander_nominees[side]` (+ its seq); records
    `{side, chosen, from: [both ids], reason}` in `survivor.command_unions`.
- Absorbed pending general warrants whose issuer is not the unified commander
  are refused at delivery by the existing issuer check (no new code; test it).
- No CSV key.

## Implementer rulings pending the owner

1. `commander_nominee_seq` is the sequence of an explicit appointment (no
   action sets nominees yet; the field defaults to 0).
2. Candidates are only the two sources' commanders, not every unit's officer
   (the merge unifies two command relations).
3. A pending warrant from the commander not chosen is refused at delivery.

## Hand checks (tests/engine/test_battle_command_unify.gd)

- Survivor att commander A (sk_martial 5), absorbed crown-side commander B
  (sk_martial 7) → B; `command_unions` row names both.
- Equal martial, prestige 3 vs 4 → the higher prestige; equal everything →
  smaller id.
- Absorbed side has nominee C (seq 2), survivor nominee A (seq 1) → C; only
  survivor nominee → A even when B has better martial.
- After the merge a reinforcement joining keeps the unified commander
  (`update_battle`).
- A general warrant from the losing commander, pending at merge, is refused on
  delivery.

## Steps

1. Tests red. 2. Code green. 3. One sentence on the unified commander in the
merging paragraph of `scripts/engine/guide/battle_and_ai.md`. 4. `--fast` green;
one PR.

## Implementer rulings (added during build)

4. The side map is derived from the absorbed battle's first unit per side via `BattleSystem._side_for` (allegiance).
5. A nominee only counts if still an eligible candidate (a source commander of one of the two battles); an invalid nominee is ignored and the default selection runs.
6. If no candidate is eligible for a side, the survivor's commanders for that side are left untouched and no `command_unions` row is written.
7. `commander_nominee_seq` is also carried under `sources[<id>]` (added to `SOURCE_KEYS`).
8. No existing assertion adapted.
