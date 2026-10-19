# P4.4d3 — outside marchers keep clear of a deployment

Scope: the third slice of P4.4d. A column on the march (not in the battle)
treats a battle unit's deployed groups as the ground it occupies: the unit's
clearance radius grows to cover its groups. Units of the same battle are not
held apart by the whole-unit circle (they do not march while in it). No combat
change (d4).

Approved design: spec `2026-10-17-unit-behavior-and-battlefield-design.md` §7.2
(the existing clearance design keeps working for marches outside battle; after
contact enemies in the same battle are no longer held apart by the whole-unit
exclusion circle; outside marching units still keep clear of the deployment
area actually occupied and join through a real entrance).

## Contract

- `ArmySystem.clearance_blockers`: for a unit with saved groups in a live battle
  (`battle.groups[code]`), its radius is the larger of its arm radius
  (`army_clearance.csv`, unchanged) and the farthest group's distance from the
  unit's anchor (rounded up to whole metres) + `battle_group_spacing_m` / 2.
  Its blocker point stays the anchor. Everything else is unchanged.
- A column marching to JOIN that battle still halts on contact first (contact
  reach `battle_contact_km` is far larger), so joining is unchanged; a friendly
  column passing by goes round the larger circle.
- No new CSV key.

## Implementer rulings pending the owner

1. The deployment area is one circle round the anchor (covering every group),
   not a per-group shape: the clearance code is circle-based.
2. Record any existing clearance test whose pinned detour moved because a unit
   in it was in a battle with groups.

3. Implemented as written: only the radius changes; units of the same battle are
   not otherwise exempted from the whole-unit circle (they do not march while in
   the battle). No existing clearance test moved.
4. Real arm radii (infantry 1140) dwarf one-group layouts, so the 75 m hand check
   sets `army_clearance` to 40/100/10 in the test; the detour case places a group
   3000 m out so the grown radius (3025) exceeds the arm radius. The detour is
   seen over several days (the disc enters the walk after a few).
5. `_ahead_blockers`' key gains a hash of every battle's `groups`.
6. The doc sentence went in `regiments.md` only (d2 owns `battle_deployment.md`).

## Hand checks (tests/engine/test_deployment_clearance.gd)

- A battle unit at (0, 0) with groups at (−50, 0), (50, 0), (0, 40): farthest
  50 → radius max(arm radius, 50 + 25 = 75). With its arm radius below 75 the
  blocker radius is 75; with a larger arm radius it is unchanged.
- The same unit with no battle: radius is its arm radius.
- A friendly column whose straight walk passes 60 m from the anchor goes round
  (detour) when the unit is deployed and walks straight when it is not.

## Steps

1. Tests red. 2. Code green. 3. One sentence in `battle_deployment.md` "Battle
groups" and in `regiments.md` clearance text if it states the radius rule.
4. `--fast` green; one PR.
