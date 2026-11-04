# CF04c production encounter continuity contract

Date: 2026-11-04. Documentation prerequisite only; no production activation or
player-fix claim. Source baseline is `48dd7d78379f32179ac4d200daa6fc81ad911c14`
(accepted LG02 #248). Accepted render contract #200 and locomotion contract #202,
the approved `2026-10-25-cluster-formations-design.md` §3.1/§8/§9 and original
owner proposal SHA256
`69595c59bea9408035a691c9bc6c765fea61b277ea4e08a17be666ad17459426`
are binding inputs. This document freezes their production seam, not a new body
store, renderer, clock, formation design or animation framework.

Sole dispatcher: `01a17398-42c1-7583-8d3f-7b15e877586c`.
Implementation: `01a1a711-4263-73f2-a04b-242a8103ea57`; unique Review:
`01a1a712-e736-7b21-9cd9-b9d5a14329e7`. This pair owns only this new document.
Future file lists below are registration proposals, not active claims or dispatch.

## Verified current source and callers

The following inventory describes the baseline, not already installed behavior.

- `scripts/map3d/map3d_formation.gd`: `fit_tier`, `slots_of`, `layout_of` and
  `offsets` derive ordinary representatives from tactical `BattleFormation`
  slots, extents, gap and depth. They do not consume persistent nonbattle points.
- `scripts/map3d/map3d_battle_groups.gd`: `sample` admits through
  `ctx.regiments()` but falls back outside a battle; `sync`/`place` consume saved
  battle rows at reference scale. Its slot cache cannot preserve destroyed
  ordinary children.
- `scripts/map3d/map3d_layer_units.gd`: `_piece_of` calls `_drop` when switching
  ordinary/`physical_groups`; `_drop` frees nodes and clears shown position,
  tracking and yaw. Fixing only this rebuild leaves two coordinate authorities.
- `scripts/engine/battle_groups.gd`: `refresh` seeds new rows from current
  tactical slots and footprint pitch. Initial overlap handling may compute
  deployment, relayout rows and change anchors before publication. `join` also
  refreshes. This is accepted LG02 occupancy repair, not encounter continuity.
  `battle_system.gd` starts/ends battles; `battle_merge.gd` transfers membership.
  Their ordinary lifecycle cannot be treated as an accepted body transaction.
- `scripts/engine/unit_bodies.gd`: `home_slots` supplies the fixed non-tactical
  template; `rows` copies the unique owner's bodies.
  `transfer_battle_candidate(repo, source, unit, from_battle_id, to_battle_id,
  to_side, boundary)` stages exact ownership on a detached candidate. It checks
  sole ownership, allegiance and lifecycle boundary; enrollment needs contact,
  exit needs advance, and pending decisions defer. It is not a production
  join/exit API. The enclosing transaction must seal its outer receipt.
- `scripts/engine/army_system.gd`: explicit march/battle candidate plan/commit
  entrances reuse `BodyMotion`; selected deployment/flank/charge contributions
  require providers. `army_ground.gd` owns ordinary leave/settle/arrival writes.
  `scripts/engine/tick_engine.gd` has explicit candidate march entrances, but
  ordinary day resolution does not activate them. Every ordinary writer must
  be covered before cutover, not just encounter start.
- `scripts/ui/game.gd`: `load_campaign` runs `MilitaryBootstrap.migrate` and
  `MilitaryReorganization.reconcile` before assigning `state`; it does not
  activate UnitBodies. Campaign creation and the real `Game.advance_day` bridge
  must participate in admission/publication. `military_reorganization.gd`
  currently reconciles legacy organization, not this production continuity.
- `scripts/engine/body_motion.gd`: `_loco_policy` requires positive per-arm
  turn/contact policy and radius-bound MARCH/PIVOT_LEFT/PIVOT_RIGHT certificate
  with `all_turns=true`. Installed root balance has no such policy rows.
  Test-injected certificates are numerical evidence only. The body-marches
  guide explicitly records no installed tactical providers or production callers.
- `scripts/map3d/map3d_context.gd` and `map3d_view.gd` supply admitted context and
  presentation time. The eventual bridge must supply exact committed slice time,
  not whole-day share or a renderer-generated movement plan.

Frozen proposal line references are historical hints; the symbols above were
checked on this baseline. Archived 6.795x/5.063x ratios are not current-window
measurements or visual acceptance. No code/art/physical PASS follows from this
inventory.

## One authority before, at and after contact

Production uses one persisted body world: nonbattle `body_groups` and canonical
battle `groups[unit]` are mutually exclusive owners of the same rows, through
existing UnitBodies validation. There is no parallel ordinary layout authority.
The admitted renderer copies those rows before, during and after battle.

An ownership-only start/contact/join/merge/exit preserves, for every surviving
`(unit, slot)`, exact integer point, facing, count, home slot, path and cursor.
It preserves anchor metadata, reference scale, model node instance and animation
phase; owner container/battle membership may change. Hash canonical rows by
stable identity independent of storage container and assert equality across the
transfer. No slot renumber/reuse, path reset, facing correction or anchor fallback
is allowed. Zero fit is a validated initialized empty set, not a missing-body
fallback. 1000/901/900/1/0 fit means 10/10/9/1/0 active representatives; residual
counts remain exact and loss cannot compress survivors into a smaller clump.
Reinforcements admit only genuinely new bodies into legal free space.

Contact grants exactly zero movement budget. It cannot call formation seeding,
re-deploy to resolve overlap, or move an anchor to make membership legal.
A later deployment is actual validated movement at the ordinary clock and budget.
No legal placement means atomic wait/reject with a reason; state, personnel,
costs, RNG, paths and source save remain unchanged. Contact itself cannot cure an
already invalid physical world. Physical disc radii, pitch lower bounds and
model scale stay unchanged; every traversed sweep, terrain edge and occupied
neighbor still validates, including blocked gaps and stationary peers.

Use `UnitBodies.home_slots` as the stable internal return template. Ordinary
formation/stance commands cannot reshape it into line/wedge/diamond or award old
front/reserve slot bonuses. Existing commands and bonuses follow the approved
compatibility boundary (§8); no silent renamed tactical layout survives here.
Real local contact and lawful ranged geometry still determine who contributes.
This repair does not require implementing all eight cluster formations.

Preserve LG02's actual-position melee/ranged/direct-damage guards, lawful
self-defence, occlusion and nonduplicated strength accounting. Render-only easing,
delaying physical mode until attack, enlarging ordinary visual pitch alone or
keeping nodes while reseeding rows cannot satisfy this contract.

## Initial materialization and compatibility failure

A fresh campaign may legally materialize its initial bodies before its first
frame, validating the complete world and fixed template. That is initial
admission, not runtime transfer. Once admitted, march, garrison, arrival,
withdrawal, losses and reinforcement all maintain the same authority.

Load into a detached state. Validate body schema/version, unique owners,
identities/counts, full physical realization and pending day/round proofs before
publication. A valid current save retains exact bodies and controls. A legacy
save missing a legal realization must not be silently spread on encounter entry,
reseeded in the renderer, overwritten, partially published or auto-advanced.
Return explicit compatibility/admission failure and preserve the original save.
Any separately approved repair must run at its explicit safe boundary, conserve
personnel/equipment/costs, validate the whole candidate and publish atomically;
this document supplies neither an automatic repair algorithm nor new permission.
LG02's existing legacy migration remains its accepted boundary, not evidence
that arbitrary v2 realization is legal. Unsupported required arms, missing
policies/providers, stale receipts, malformed rows and closed placement fail
admission; excluding cavalry to claim an infantry+cavalry fix is forbidden.

## Minimal future adapters and literal ownership

Register each bounded adapter separately with one implementation/Review pair,
current accepted dependencies and conflict-free literal files. No step below is
dispatched by this document. Existing APIs/arithmetic are reused; no extra helper
layer or second row store is proposed. Engine tests below exist on this baseline. The projection fixture/tests belong to
the retained PR201 scope and are absent here; reuse them only after lawful
resolution. Any necessary additional path requires explicit registration.

1. **Lifecycle and compatibility adapter, inactive until cutover.** Proposed files:
   `scripts/engine/unit_bodies.gd`, `scripts/engine/battle_groups.gd`,
   `scripts/engine/battle_system.gd`, `scripts/engine/battle_merge.gd`,
   `scripts/engine/military_reorganization.gd`,
   `scripts/engine/guide/cluster_formations.md`,
   `scripts/engine/guide/battle_groups.md`,
   `tests/engine/test_body_battle_boundary.gd`,
   `tests/engine/test_battle_save.gd`, `tests/engine/test_battle_groups.gd`.
   Preconditions: accepted sealed B-CONTACT interface and this contract;
   overlapping active claims must first be lawfully resolved. Reuse its contact
   transaction, UnitBodies transfer and closed-motion proof. B-CONTACT's own
   `body_battle_contact.gd`/UID/test paths are not implicitly owned here.
   Acceptance: zero-delta transfer at all lifecycle edges, exact survivor/anchor/
   cursor conservation, JSON/retry equivalence, pending-decision deferral and
   complete failure rollback. Static ownership tests need no new pivot art.
   This adapter alone must not route ordinary live campaigns into body mode.
2. **Production driver and ordinary writers, inactive until cutover.** Proposed files:
   `scripts/engine/army_system.gd`, `scripts/engine/army_ground.gd`,
   `scripts/engine/tick_engine.gd`, `scripts/ui/game.gd`,
   `tests/engine/test_body_marches.gd`, `tests/engine/test_body_placement.gd`,
   `tests/ui/test_game_campaign_validation.gd`.
   Preconditions: accepted lifecycle adapter plus selected movement providers,
   installed policies/certificates for every required arm and accepted timing
   APIs. Their installation is an existing separate dependency, not hidden work
   in these files. Acceptance: creation/load/march/garrison/arrival/withdrawal
   share one validated candidate and one publication, ordinary clock/supply/move
   budget, exact pending-day/round retry and source-save preservation. No ordinary
   legacy writer can remain an alternate authority for an admitted body world.
3. **Continuous admitted projection, inactive until cutover.** Proposed files:
   `scripts/map3d/map3d_battle_groups.gd`,
   `scripts/map3d/map3d_layer_units.gd`, `scripts/map3d/map3d_formation.gd`,
   `scripts/map3d/map3d_context.gd`, `scripts/map3d/map3d_view.gd`,
   `scripts/map3d/CLAUDE.md`, `tests/map3d/test_body_paths.gd`,
   `tests/map3d/test_body_paths.gd.uid`,
   `tests/map3d/test_map3d_battle_groups.gd`,
   `tools/map3d/body_paths_fixture.gd`,
   `tools/map3d/body_paths_fixture.gd.uid`.
   Preconditions: lawful PR201 ownership/acceptance resolution, accepted driver
   timing and admitted body contract. Reuse the existing fixture and candidate
   projection; same child keyed by `(unit,slot)` consumes admitted copied rows
   across owners at exact production slice time. Preserve phase/scale and
   endpoint-on-load behavior without replaying an old path. Acceptance includes
   hidden/ghost admission guards: no hidden enemy path/control reads, currently
   observed foes expose only allowed current pose; no Game access in map layers.
   No new capture framework or scene/art edit is authorized.

These lists are a minimum seam inventory, not a single broad implementation PR.
An adapter may be subdivided further by the sole dispatcher when acceptance or
claims demand it; do not split an atomic invariant across independently active
runtime paths. All adapters remain unreachable from ordinary dispatch until the
single production publication boundary can install them together.

## Acyclic activation and retained blockers

Order: accepted #200/#202/#248 and this document -> reconcile accepted B-CONTACT
and existing provider/policy completion records -> lifecycle adapter -> driver
adapter -> projection adapter -> atomic production cutover and its own Review.
Policy/provider prerequisites and lawful map ownership resolution may progress
independently; both must precede the adapters that consume them. No adapter's
acceptance depends on the later cutover being enabled. Adapter test fixtures
remain isolated; final acceptance uses the ordinary production path.

PR201 HEAD `9744b457757fa1a79fa4db7d4183f613fd9ff711` retains its original
pair, eight claims, failed R1 and immutable v1/no-production-callers acceptance.
This contract does not turn v1 into v2, waive R1, release claims, retire the step,
replace an owner or authorize an overlapping successor. #202's same blocker
remains. The original pair must resolve that boundary lawfully with explicit
human authority where required; no registry rewrite is allowed. PR201 merge and
pivot certification are not prerequisites for writing this document. A sealed
zero-motion transfer is separately testable without pivot art; complete live
march/contact/battle/exit requires the real installed policy/provider chain.

Cutover is a separately registered small activation step after all adapters are
accepted. Its literal owned-file list must be extracted from their actual
remaining activation call sites and registered before Start; this document
cannot honestly predeclare a source diff that does not yet exist. Its acceptance
is fixed below. It must enable lifecycle, ordinary writers and admitted projection
as one runtime boundary, failing closed before any live state is published when
one prerequisite is absent. Never activate lifecycle or driver alone while
legacy ordinary projection/writers still disagree. The dispatcher alone creates
successors; no circular requirement that this contract first fix the game.

## Eventual player-fix evidence and this document's acceptance

On a normal fresh campaign and formal save/load (no fixture opt-in), test
infantry and cavalry at 1000/901/900/1/0 fit before contact, contact, join, merge
and exit. Record canonical row hashes, anchors, cursor/path, node instance,
reference scale and phase. Ownership-only changes have exactly zero XZ/facing
displacement and no node replacement; actual clock slices have only their
committed displacement. Loss/reinforcement and stance/formation changes preserve
survivors and add no internal tactical bonuses.

Test terrain/neighbor/closed-gap rejection, all physical sweeps and actual
contact/fire/damage at displayed points. Whole-save replay/JSON retry and pending
round/day resume must be deterministic, once only, without extra move/supply
budget, personnel/cost/RNG changes on failure or source-save overwrite. Preserve
all twelve approved §9 gates; no physical/visual/performance PASS is inherited.

After the shared Godot reservation is free, the activation pair captures real
window continuous before/after entry/exit, near/far, pause/1x/4x on frozen current
inputs, native crops and independent unique Review critique. Reuse existing
snapshot/fixture/benchmark tools and retained #200/#202 timing, locomotion and
performance obligations. No archived ratio, static ownership test, headless 3D
or dormant candidate replaces ordinary live-window acceptance.

This document PR is accepted only for a source-checked complete before/contact/
after contract, literal adapter inventory, explicit compatibility failures and
acyclic atomic activation order. Run dedicated harness/config/guide/selector
checks and whitespace validation, then all required current-HEAD CI and unique
Review. No Godot, art, product code, runtime tests or production activation is
part of this documentation step. The encounter defect remains until the later
registered production cutover passes its own full acceptance.
