# P4 — commander choice when hurrying to a known battle

Authorization: continue remaining P4 work serially through actual acceptance,
one independently testable PR and one implementation/Review pair at a time.
Approved behavior: `2026-10-17-unit-behavior-and-battlefield-design.md` §5.

## This step

An eligible appointed unit commander chooses whether to run on the existing
`join_battle` march. Use the existing `sk_martial` and `boldness` values:
`sk_martial * army_run_martial_weight + boldness >= army_run_min_score`.
Both tuning keys belong to `army/balance.csv`. The initial weight normalizes
the military skill's scale against the personality attribute. This is an
implementation tuning choice, not an owner-specified balance formula.

Recheck the live appointment, eligibility and score each fixed substep. Below
threshold or without an eligible commander, continue the ordered route walking.
A willing commander still needs the existing known-battle reason and must pay
the existing run increment after reserving base food. No new RNG draw, saved
field, order, cost writer or clock. Existing gait reasons and stopping records
continue to describe the run; JSON saves already carry character attributes.

Scope: UnitGait, its army balance keys, gait march tests and the battle deployment
guide. Callers are ArmySystem's two refresh sites and its existing pays_run site.
Withdrawal and received pursuit behavior stay outside this slice. Known key-point
urgency, further gait contexts and all geometry/visual acceptance remain later work.

## Acceptance and checks

1. Fail then pass hand-computed threshold cases exercising real march displacement
   and supply: ability and boldness each independently change the choice.
2. Unavailable/missing commander and a changed score drop a prior voluntary run;
   a missing battle reason still walks. Config values influence the choice.
3. Mid-day JSON restoration equals uninterrupted execution. Existing run supply,
   camp packing, withdrawal and delivered pursuit tests pass.
4. Targeted GUT via the shared local Godot lock; final bounded engine-military
   regression plus data-layout/isolation checks on frozen inputs. Required CI
   remains authoritative; no routine full local suite or balance sweep.
5. Commit this step, create its PR and hand off once to its unique Review. That
   Review fixes in scope and merges only after current-HEAD required checks pass.
   Only then create one next implementation for pursuit region/group eligibility,
   scoped from the approved spec and current main. Preserve the user's continuing
   P4 authorization through each subsequent one-to-one handoff until acceptance.
