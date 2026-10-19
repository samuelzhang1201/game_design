# P4.4b8 — public task formation parameter

Approved spec: `2026-10-17-unit-behavior-and-battlefield-design.md` §§4.1–4.3.

One public slice after merged P4.4b7 (PR100): `BATTLE_TASK` accepts an optional
`formation` and passes it into the existing unit-task warrant. Issue and receipt
reuse BattleTaskSystem's BattleFormation.refusal/request; ActionSystem adds no
formation formula, no second filing charge and no second courier fee. An empty
or absent formation leaves the received deployment untouched. Unknown or
unsuitable formations refuse before any mutation; exact retries return the saved
outcome; reuse with a different formation fails.

Owned: action_system.gd, policy_actions_domain.csv notes, test_battle_task_dispatch.gd,
battle_deployment guide and this plan. No UI, map, save schema, CSV cost or
BattleTaskSystem change. The WAR ROOM task interface and its visual review are
the next slice; P4.4b is incomplete until then.

- [x] Red: a paid remote task with a formation reforms only its recipient on
  courier receipt, costs one filing plus one courier; local receipt reforms at
  once; unknown/unsuitable formation and non-text formation refuse atomically;
  a retry with another formation is refused.
- [x] Allow `formation` in `_validate_task` and `_task_warrant` for BATTLE_TASK only.
- [x] Run task/formation/dispatch/courier/save focused tests and `--fast`; one PR.
