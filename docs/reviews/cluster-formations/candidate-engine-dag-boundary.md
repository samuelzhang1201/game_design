# Candidate engine / rendering dependency boundary

Date: 2026-11-01. Step `CF-ENGINE-DAG-BOUNDARY`; implementation
`01a196db-0451-7ea2-be0f-478414fa23d4`, dispatcher
`01a17398-42c1-7583-8d3f-7b15e877586c`. The unique document Review is assigned
through the dispatcher before handoff. Scope is this document and the existing
cluster-formations plan only. No product implementation, dispatch, visual pass,
active-contract amendment or retirement is authorized by this result.

## Decision and frozen sources

For **future unregistered candidate steps**, remove render/art completion as a
blanket predecessor of pure CF05/CF06 engine work. Keep actual engine interfaces,
time/payment/ownership boundaries and contract acceptance as predecessors.
This is a necessary-dependency finding, not proof that battle integration is
already implementable. Contracts come first; any newly identified prerequisite
must itself be registered and accepted before dependent product work starts.
Rendering and engine branches converge before atomic production activation.

Audited source: main `6ef550a1b4266d8c551f40da3ee6e4e46d5b6606`.
GitHub merge facts checked read-only for:

- [#187 staging boundary](https://github.com/samuelzhang1201/game_design/pull/187),
  merge `4ac809c8a5884ed161ee320e84080d7ea853a9c0`;
- [#194 candidate march](https://github.com/samuelzhang1201/game_design/pull/194),
  merge `4dbade74dc08d7988fbbd68ba34fd915021b008f`;
- [#199 candidate placement](https://github.com/samuelzhang1201/game_design/pull/199),
  merge `8ce7f666ec5262d91576dae0ce7242591ea15085`;
- [#202 locomotion contract](https://github.com/samuelzhang1201/game_design/pull/202),
  merge `9ccb4bd0decd9bc0df379057ee7fc210351a9fec`;
- [#203 LOCO-TIME](https://github.com/samuelzhang1201/game_design/pull/203),
  merge `441b62bed05013876a845fcc63dc30f987b1f64c`.

The approved [spec](../../superpowers/specs/2026-10-25-cluster-formations-design.md)
§3.2 requires common body occupancy, lawful physical contact and direct fire;
§8 requires existing personnel, laws, orders and saves; §9 retains all twelve
completion gates. These requirements bind engine data and eventual visible
behavior, without requiring a renderer callback to decide contact or damage.
The [#202 contract](cf04c-locomotion-contract.md) explicitly permits injected
test certification for TIME and separates time, march, art, certificates,
policies and consumer. This finding applies that boundary to future engine
contracts; it does not change #202 or the original production Task CF05/CF06.

## Concrete source / dependency evidence

All names below refer to the frozen main source, not open PR product patches.

- `scripts/engine/unit_bodies.gd`: `rows` returns copied rows from the one
  battle or regiment/foe owner; `home_slots`/`footprint` use repository data.
  A renderer does not produce these facts. Candidate migration/validation and
  transfer remain explicit, and a frozen or partial result is not a battle input.
- `scripts/engine/body_motion.gd`: `plan_locomotion_candidate` builds and
  reserves timed operations from repository, state, intents and explicit cursor;
  `commit_locomotion_candidate` revalidates the full plan and returns a detached
  candidate. `_loco_policy` checks the two per-arm rows against the exact
  certificate, radius, clips and all-turns declaration. Planning checks every
  non-naval unit, including stationary peers. `_loco_context` binds footprints,
  balance, policies, terrain and diplomacy. No GLB/scene, rig or render receipt
  is read; art enters through a required validated data contract, not a callback.
- `scripts/engine/guide/body_marches.md` and
  `tests/engine/test_body_motion.gd::_loco_fixture` explicitly distinguish
  test-injected certificates from installed support. Therefore pure candidate
  math can be tested before art certification. This permission does not certify
  a real campaign, and its small-radius fixture cannot satisfy production-radius
  battle, road or formation acceptance. Future contracts must retain real radii
  for those cases and reject absent/mismatched/unsupported policies.
- `ArmySystem.plan_body_march_candidate` / `commit_body_march_candidate` and
  `TickEngine.begin_body_march_candidate` / `step_body_march_candidate` remain
  **v1** on this baseline. `UnitBodies.validate_march_candidate` and
  `DayResolution.body_march_incompatibility_reason` require version 1 and an idle
  v4 MARCH boundary. TIME's nonempty boundary requires version 2. Thus #203
  alone cannot compose into the frozen march, much less a pending battle round.
  [#206 LOCO-MARCH](https://github.com/samuelzhang1201/game_design/pull/206)
  was OPEN/unmerged at audit; no patch was consumed or assumed accepted.
  Placement's `march_complete` admission also delegates to the saved march
  validator; accepted #199 is not by itself proof of v2 boundary composition.
  Future contracts must check the actual merged integration, including this seam.
- `BattleGroups.translate` writes an anchor then `follow_anchor` shifts rows
  and paths; `deploy_day` uses its own deployment step. `BattleCharge.move`
  and `BattleTaskSystem.deploy_flank` use that movement chain and update run-up
  or task progress. These are real future writer/budget integration work, not
  APIs already made safe by TIME or render. `TickEngine._resolve_battles`
  performs march, reconciliation, contact and battle steps in the saved order;
  adding battle movement must not give a unit another daily/slice allowance.
- `BattleGroups.engaged_counts` reads saved groups, counts, terrain, actions and
  contact distance; current `engaged_permille` includes reserve contribution.
  `BattleSystem.unit_strength` sends that and `BattleRanged.counts` into
  `BattleStrength.unit/combine`, whose category clamps make zero-contact
  handling a real formula boundary. `BattleRanged.clear_shot/counts` reads
  position/facing, reach/cone, friendly obstruction and lawful targets;
  `BattleMerge.mergeable/_ranged_contact` reads actual groups, party-scoped
  compatibility and ranged eligibility. None reads rendered pose or art clips.
  Future damage must consume the accepted physical rows/contact contract,
  not old reserve damage or a visual collision query.

The scanned engine files have no executable map3d/UI/LLM, GLB or animation
dependency. An ArmySystem comment mentioning Map3DFormation is not a call.
Absence of such a call supports removing a rendering edge only; it does not
prove the missing battle boundary, physical reach or round protocol works.

## Readiness DAG and scope locks

These are future boundaries, not registered task IDs or product API designs.
Every step still needs one dispatcher, exact files, implementation/unique Review,
worktree/branch and accepted predecessors checked at registration.

1. **CF05-CONTRACT** can lock its candidate interface against accepted
   foundation/planner, #194/#199/#202/#203 without render completion. It must
   define exact entry/result/receipt shapes, sole row ownership and lifecycle
   transfer, lawful contact, terrain/radius use, shared march/deploy/charge/flank/
   retreat budget and paid-cost/run-up rules, pending-round/JSON resume, raw
   rejection/atomicity, exact owned paths and executable tests. It must identify
   any additional engine prerequisite before product registration. It cannot
   silently widen the idle MARCH validator or change a frozen v1 transaction.
2. **CF06-CONTRACT** follows accepted CF05-CONTRACT so it can bind a precise
   contact/count output, legal target and round boundary. Lock exact candidate
   damage/fire APIs, raw schema and owned files, zero-contact/partial-group
   hand calculations, inclusive reach ±1 metre, facing/terrain/friendly-envelope
   occlusion, nonduplicated factors, military-law protection, frozen loss/RNG/
   personnel settlement and retry tests. This is not the implementation of those
   algorithms. Shared plan/guide ownership serializes the two document steps.
3. **CF05 candidate implementation** waits for its accepted contract, actual
   accepted LOCO-MARCH merge, accepted placement and every additional engine
   prerequisite identified in the contract. Split any oversized writer/lifecycle
   work before registration. **CF06 implementation** waits for its accepted
   contract and actual accepted CF05 product outputs. No open PR dependency,
   copied unmerged code or candidate-as-production dispatch is permitted.
4. **Art/render branch** retains #202: each arm's clips and necessary separately
   registered solver/transition/scene prerequisites → full continuous per-arm
   contact/envelope certificate; each certificate plus LOCO-MARCH → its policy
   installation; all five policies/certificates plus march and necessary runtime
   helpers → v2 consumer, also blocked on lawful resolution of PR201 ownership.
   Artillery has its own certification even with the infantry placeholder.
   Shared policy CSV/test paths remain serial. No installed-support claim can
   be based on fixture data or finite pose samples.
5. **Activation convergence** waits for both branches and all other P4 writers,
   boot/load and staging prerequisites to be accepted. Changed policy/certificate
   digests or repository balance invalidate affected receipt/basis evidence;
   rerun relevant checks on the final real inputs. There is no edge from consumer
   back to engine contract, nor from activation back to passive foundation.

Current ownership also prevents casually parallelizing engine implementations.
CF05/CF06 source scopes overlap `scripts/engine/battle_groups.gd`,
`scripts/engine/battle_system.gd` and the battle-groups guide; run them serially.
LOCO-MARCH owns UnitBodies/ArmySystem/TickEngine/DayResolution and the body-marches
guide. Any future battle contract requiring those paths must wait and register
the exact additions; it cannot edit the original pair's files. Rendering and
engine may proceed independently only with disjoint registered files, including
guides, tests, fixtures and CSVs. These rules add no owners to active PRs.

## Acceptance preserved and handoff

All twelve spec §9 items remain required: ten bodies/exact personnel/fixed
footprint; full-radius sweeps through turns and reload; eight eligibility sets;
independent/slowest/local budgets; actual delivery/version/king; vulnerable
assembly/stable old line; reform/expansion/unique membership; all eight normal,
blocked and member-loss cases; physical melee/direct fire/occlusion/explained
nonduplicated bonuses; save/speed/camera/cost/personnel determinism; reproducible
formation-vs-none/countered outcomes; actual 3D-map visuals/performance.

Preserve every existing CF05/CF06 assertion and regression in the plan, military
law and bilateral parties, real run-up/shared budget, once-only costs and RNG,
pending-round/frozen-JSON semantics and personnel conservation. The inherited
**55 failures and 6 risky/pending** remain failed/pending evidence (frozen input
`19bd7a5b9deb50a1bb1820aac2348e9e20adb8400484d1e3ab6e0729da2fbfb5`),
not fixture-only or accepted. Actual unchanged road-contact and defeat
continuation, real campaign placement/new boot/save/load, legitimate old saves
in place, corruption/future rejection with file/live state unchanged, military
reorganization and save determinism must be resolved and verified on final inputs.
No radius/scale reduction, hidden physics, range compensation, assertion change,
feature flag, permanent fallback or test/CI threshold waiver is introduced.

Final activation switches **every** writer together: opening/AI spawn, growth/
recruit/split, settlement/arrival/march, battle enter/merge/withdraw/end/cancel,
damage reconciliation, load publication and live render bridges. No subset
becomes production first. All arms' continuous contact/envelope proof, actual
near/far pause/1x/4x and FPS visual-review plus performance are mandatory in the
live world after convergence. CF01's 17 sampled poses do not replace them.

PR201 was OPEN/draft at audit, R1 FAILED remains preserved with its original
implementation `01a1959a-e085-7a33-a7d7-278585c178ba` and unique Review
`01a195a8-dce9-78a2-9818-fa5be7306096`. Explicit terminal authorization remains
pending. This document neither retires it, releases claims, fixes/reviews its
patch nor counts it as an accepted dependency. All active immutable contracts
and owners remain as registered.

Document acceptance: frozen-source/API/callgraph trace, no dependency cycle,
scope/link/requirement self-check, whitespace, selector and workflow-native
Python/shell/config/guide checks, unique independent Review and required
current-HEAD documentation CI. No Godot/Blender was run; no product, native-window
or performance acceptance is claimed. Implementation hands back only this
bounded document PR and ends after its fixed-pair review/merge; it starts no CF05.
