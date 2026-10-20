# P4.4e3 — agreements keep their own parties across a merge

Scope: the third slice of P4.4e (after e1's `BattleMerge`, which keeps the
absorbed battle's `parley` verbatim under `survivor.sources[<id>]`). An agreed
term binds and protects only the units that were its parties (and the
reinforcements its own inheritance rule admits), wherever those units later
fight; it is never decided by the current battle id, and a new opponent from
another source gets no bilateral treatment it never agreed.

Approved design: spec `2026-10-17-unit-behavior-and-battlefield-design.md`
§11.3: each agreement saves its parties, bound units/realm scope, protected
objects, obligations, term and end condition; the source battle id is for
tracing only; a term protecting unit A still protects A after A moves or its
battle merges; reinforcements bear obligations by the term's inheritance rule
and old enemies cannot pose as new reinforcements to escape a promise; a new
opponent or another source's unit gets no bilateral treatment the other side
never agreed; partial terms stand; red flag, pursuit orders and a commander
change cannot break a protection; when the object cannot be confirmed, an
attack that might breach is held with a recorded reason (a legality check, not
a risk veto). §12 (scopes in the save).

## Contract

- **Parties**: `BattleRules.freeze` records `parley.parties = {att: [...],
  def: [...]}` (the sides' members at contact, sorted). A unit that later JOINS
  that same battle through `BattleSystem.join` is appended to its side's
  parties (the existing inheritance: reinforcements inherit the frozen terms).
  An old save's parley without `parties` gets them from the battle's current
  sides at the next freeze check (record as ruling).
- **On merge** (`BattleMerge._merge`): the survivor's own parley keeps its
  parties; the absorbed parley stays in `sources[id].parley` with ITS parties.
  Units absorbed are NOT added to the survivor parley's parties, and vice versa.
- **Legality** (`BattleRules.legal_actions(repo, state, battle_id, side, unit,
  target := "")`): the shared-obligation part (`_policy` terms: surrender
  accept → no red flag; tactics restrained → no charge/pursue; safe_withdrawal /
  ceasefire protect → no pursue (+ ceasefire: no attack/charge)) is applied per
  agreement: an agreement applies to `unit` when the unit is one of its parties
  AND (`target` == "" OR the target is a party on the other side of that
  agreement). Agreements = the battle's own parley + every `sources[*].parley`.
  When `target` is "" and the side's enemies include units outside the
  agreement's parties, the agreement still applies (cannot confirm the object →
  hold the possibly-breaching action) and `legal_actions` callers that record
  reasons say so (ruling).
- Own-law restrictions (`LawSystem.received` per unit) are unchanged.
- `BattleTaskSystem.combat_action` passes the task's `target_unit` as `target`.

## Implementer rulings pending the owner

1. Parties are unit codes frozen at contact plus units that join that battle.
2. With no specific target the agreement applies (conservative hold).
3. Old-save parties default to the battle's current members.

## Hand checks (tests/engine/test_battle_terms_scope.gd)

- Battle 1 (P1 vs F1) agreed `ceasefire` protect; battle 2 (P2 vs F2) none;
  merged (e1). `legal_actions(..., "P2", target "F2")` keeps attack;
  `legal_actions(..., "P1", target "F1")` has no attack; P1 targeting F2 keeps
  attack (F2 never agreed with P1); P2 targeting F1 keeps attack only if F1 is
  not a party with P2 — it is not, so attack stays (record: the protection was
  bilateral between battle-1 parties).
- P1 moved/merged into battle 2's record (survivor = 2): the ceasefire still
  binds P1 toward F1.
- A unit joining battle 1 before the merge becomes a party (inherits).
- JSON roundtrip keeps parties.

## Steps

1. Tests red. 2. Code green. 3. Update the agreements paragraph in
`scripts/engine/guide/battle_deployment.md` (first paragraph) and the merging
paragraph in `battle_and_ai.md`. 4. `--fast` green; one PR.

## Implementation notes

- Rulings 1-3 above stand. Additional rulings: 4. `legal_actions` called with no unit applies an agreement when ANY
  member of the side is a party. 5. Only `legal_actions` is scoped; the battle-level `_policy` readers
  (`unit_context` safe-withdrawal scale, surrender acceptance in `battle_orders`, noble ransom, herald safety) still read the
  battle's own parley (follow-up). 6. `BattleRules.ensure_parties` is called in `freeze`, `join` and `_merge` (before
  folding) so an old save's default is the pre-merge membership. 7. Side-level callers (`battle_events`, `battle_system`
  attack gate) pass no target and so hold conservatively.
- Adapted tests: none.
