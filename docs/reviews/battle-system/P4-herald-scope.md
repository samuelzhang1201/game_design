# P4 herald agreement scope

One correction to `BattlePresentation.map_snapshot`: before the first combat round,
keep one herald per crown side only when a current crown unit and a current opposing
unit are the original opposite parties of an active carried herald-safety agreement.
The herald follows the first qualifying crown unit. Existing signal keys, models,
physical offsets, crown-only permission and combat-round gate remain intact.

The old survivor-only `_policy` read lost absorbed-source protection and could attach
protection to an unrelated ally. The correction reuses `BattleRules._binds`; shared
agreement, merge, law, capture and task code are unchanged.

## Evidence

Base: `ead78e3430a0848e332dd11bce9a102e8e6adf6c`.

- `evidence/P4-herald-scope/red.log`: original production code, new behavioral tests;
  two tests failed (absorbed-source herald absent; departed party replaced by ally).
- `evidence/P4-herald-scope/green.log`: final source and tests, runner exit 0;
  four scripts, 30 tests, 209 assertions. Command below uses the shared Godot lock.
- Cases cover both source-survival orders and attack/defence orientations, an
  unrelated earlier-sorted ally, inclusive expiry day and expiry next day, combat
  rounds, original party/counterparty departure, foreign permission, unchanged
  state hash on repeated projection and JSON round-trip equivalence.

```sh
/Users/samuelzhang/game_design-wt/godot_lock.sh ./run_tests.sh \
  --test tests/engine/test_herald_agreement_scope.gd \
  --test tests/engine/test_battle_presentation.gd \
  --test tests/engine/test_battle_report_details.gd \
  --test tests/map3d/test_map3d_battle_signals.gd
```

SHA-256 final inputs:

```text
f0cffa107f904d6ca1a933b2a34cc376911567976f6f9bb93954bc2b9753f880  scripts/engine/battle_presentation.gd
26545f35182ef51c9ec320a74bded7238b2ef6fdb3cb2c10f381cf8c61f18fe1  tests/engine/test_herald_agreement_scope.gd
```

## Remaining delivery gates

No art/layout tuning or model regeneration. The visual-review principle relevant
here is that objects and signals belong to their real place in the world. Automated
signal-consumer tests verify real-piece following, hidden-piece suppression and
terrain grounding; these do not constitute real-window visual review. Real-window
merged-case comparison/crops and independent critique remain for the sole Review
before merge, along with independent code review and required current-HEAD CI.
No full campaign or balance run was requested or performed.
