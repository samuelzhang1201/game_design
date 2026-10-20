# P4 ranged fire geometry

Step `p4-ranged-fire-geometry`, implementation `01a159bb-ea0d-7dd0-9cd9-2f1a3894d671`.
Dispatcher `01a15959-7582-7233-9637-1f0f9d090d70` alone owns successor dispatch.
Base: charge #152, `4a02549eeecd7f73c738b52ab27815427826083e`.

## Scope and decision

Pure `BattleRanged` geometry feeds `BattleSystem`'s existing contact factor and
incoming casualty contexts. Groups use inclusive squared reach, a forward cone,
and friendly group discs intersecting the open shot segment. Own rear ranks can
be obstructed by their front ranks. Actual per-target eligibility is checked
before the existing personnel plan freezes, including negative morale exposure. Existing side/task authority, local
sight, bilateral protections, reserves and withdrawal remain constraints.

Ranged personnel at close contact defend through the existing melee contact
path. No extra animation clock, saved projectile, target truth cache, or second
casualty writer. Mixed equipment combines its personnel shares; non-ranged
contact and charge retain their existing semantics.

## Acceptance evidence

- RED: an attack at 5km retained 32 power; the new test expected zero.
- Additional RED cases reproduced uncommitted reserve fire, endpoint-disc
  obstruction, missing close defensive strength, designated-target interference
  with local defence, and morale damage without any eligible shot.
- Earlier targeted run: 11 scripts, 118 tests, 712 assertions passed using
  `godot_lock.sh ./run_tests.sh` and explicit ranged/contact/charge, task combat,
  task retreat, terms, save, resolve, strength, data-layout and guide-size files.
- Actual full fire: 50 fit targets × (100 tier × 800 ranged / 1000) / 1000
  = 4 dead. Fully obstructed fire: zero dead and zero negative morale.
  Half of a 100-person double rank firing: 100 × 100 × 800 × 500 / 1000³
  = 4 dead. A remote ally of an exposed enemy receives zero ranged casualties.
- A failed atomic write freezes per-target losses/morale/actions; deployment and
  retries are inert, and repaired live/JSON-restored commits have identical state
  hashes. Existing actual charge and agreement assertions remain passing.
- Three fixture-only additions were conflict-checked and reserved by the dispatcher:
  `test_battle_terms_scope.gd`, `test_battle_task_retreat.gd` and
  `test_battle_duration.gd`. They explicitly use
  melee equipment to retain their original pure agreement/retreat arithmetic;
  their assertions and expected values are unchanged.
- Frozen implementation/test/guide/data input SHA256:
  `e7997484d32fdaa0165058235b502ed3b85ca72670a09b0791dcf3cd4528752d`.
  Complete commands/logs and per-file inputs live in the worktree checkpoint.
- The expanded battle run reproduced a pursuit regression caused by overriding
  its received attack with close hold. Pursuit now retains its existing attack
  and region semantics; its original boundary assertions pass unchanged.
- A production `prepare_day` → `step_battle` test reproduced deployment forcing
  every archer into melee. Active ranged deployment now offsets the ordinary
  line by half the reach/line-gap difference, using the existing move budget
  and passability. Clear fire then causes the hand-derived four casualties.
- Latest focused run: 5 scripts / 75 tests / 386 assertions passed, including
  production firing, duration, pursuit bounds, deployment and charge.
- Final combined frozen-input verification: **35 scripts / 369 tests / 3024
  assertions passed**, runner exit 0, 141.81 seconds. Independent Review and all
  required CI remain required on the PR's current HEAD.

## Deferred acceptance

Cross-battle actual ranged-fire merging is a separate dependent step. Distinct
prepare/fire/reprepare timing and machinery deploy/load/aim/fire/reset plus
movement-rate suppression remain §8.4 gaps; this PR implements geometric fire
eligibility only. The geometric corridor is a conservative direct-fire model;
indirect trajectories, height/terrain projectile occlusion, and model-level
projectiles are outside this step. No visual assets or presentation change.
