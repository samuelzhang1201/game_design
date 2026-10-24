# Battle groups

`BattleGroups` splits each battle unit's fit personnel into representative groups of at most `battle_group_size` (the last group the remainder, units never pooled) and saves them as `battle.groups[unit] = [{slot, count, role, x_m, y_m}]` with `battle.group_facing[unit]` (whole degrees, `WarFront.facing_deg` convention: 0 = +x, y down, toward the mean anchor of the other side's units, 0 when none; an explicit unit facing takes precedence, and a received flanker faces its saved known target). Initial positions add `BattleFormation.slots` to the unit’s `x_m/y_m` anchor, scaled by `battle_group_spacing_m` across and `battle_group_depth_m` away from the enemy, rotated to facing and rounded once to whole metres. Role is `front` for slots on the foremost rank, else `reserve`. `refresh` reconciles fit counts in saved order, preserving survivors’ positions, roles, paths and IDs through losses and facing/formation changes. Only tail rows retire; growth appends reserves behind the rear. Missing rows seed once at the arrival anchor; legacy rows gain slots in array order. `group_next_slot` on each regiment/foe exceeds saved slots and never reuses IDs across departure, JSON or battles. Departed units lose rows; closed ground blocks legacy contact. `group_anchor_m[unit]` saves the committed anchor pair; row `path_m` optionally saves integer pairs. Pending rounds freeze reconciliation and deployment. Deployment lines (`BattleGroups.deployment`, pure): the axis runs from the defenders' mean anchor toward the attackers' (+x when they coincide); each side's line centre is the battle place ± axis × `battle_line_gap_m` / 2 (att on the + side); a side's units stand abreast in sorted code order, each as wide as its front groups (front count × `battle_group_spacing_m`, at least one spacing), the side centred; a unit's target anchor is the centre of its width, rounded to whole metres once. `deploy_day` (top of `prepare_day`, once per absolute day via saved `battle.deployed_day`) moves saved rows toward terrain-constrained targets in side/code/slot order, each with one `battle_deploy_step_m` budget. The rounded mean of actual rows becomes the summary anchor and its `group_anchor_m` snapshot; it never translates the rows again. It moves both sides, but not a captured unit, one with no fit man, or one seated in a town (its walls are its line), and the whole battle stops deploying once any side is ordered to retreat or any unit is withdrawing (`battle_retreat` or `disengaging`), so the winner never closes on a falling-back side; `_start` stamps `deployed_day` so the day of contact moves nothing. `translate` commits validated deployment/charge/flank deltas once to anchor, rows, paths and snapshot. Live crown/foe withdrawal, legacy or saved, uses `follow_anchor` to move rows by the published anchor delta without moving the anchor again. Previews write no rows/snapshots; repeated synchronization is inert. Saved marches retain the consumed day/substep pair to prevent replayed movement/run costs. Merge folds rows, facings and snapshots before reconciliation, preserving charge/task progress. Contact (P4.4d4): `BattleGroups.engaged_permille` is (engaged x 1000 + (fit - engaged) x `battle_reserve_permille`) / fit, integer division, where engaged is the summed count of the unit's `front` groups within `battle_group_contact_m` (inclusive, squared whole metres) of any group of the other side; a reserve rank or a front still approaching counts only the reserve share; 1000 with no saved groups. `BattleSystem.unit_strength` lists it as `contact:engaged` (category `contact`, between `formation_terrain` and `action`, clamped like every category by `battle_strength_factor_min/max_permille`) with the reason "N of M in contact with the enemy line", so siege assaults, town battles and events inherit it.


**Group-size boundary migration.** `MilitaryReorganization.reconcile` checks live
battles independently of completed living-cap organization. Its private candidate
calls `BattleGroups.migrate_size` before publication: saved slot order is consumed
into configured-size groups, retaining the first surviving row's slot, point,
role and optional path. Other slots retire permanently; `group_next_slot` never
falls. Exact fit totals, integer points/paths, unique slots and facing are
validated before any candidate is published. `saved_size` validates the known
version and its matching size; saved metadata cannot override the configured
current people-per-group rule. One invalid battle rolls back the
whole candidate. Completed battles carry `group_size_version`, `group_size_men`
and a causal reason. Repeated migration and JSON loads are inert. A pending day
or round retains its frozen rows and saved size until the safe boundary; ordinary
refresh preserves their partial rows rather than regrouping them.

A living-cap partition of already current-size rows marks regrouping only inside
that private candidate, so a group crossing a child boundary is consumed into
canonical child groups before publication. The transient flag is removed by the
same boundary migration; it never turns ordinary refresh into regrouping.

Flank target snapshots use the target battle’s saved group size while its legacy
transaction remains frozen; nonbattle targets use the configured current size.

Group-size migration waits while any live round remains pending. New encounters
inside a resumed legacy day seed the same legacy size as its live battles, so
merges never mix group contracts before the common safe boundary. Living-cap
work on unrelated idle units retains its private-candidate publication rules.

Successful monthly wound recovery refreshes the unit's existing battle rows in
the same settlement; surviving slots and points persist, and pending rounds
retain their frozen rows through the existing refresh guard.

## Terrain capacity and physical travel

`targets` is pure and consumes existing saved slots. Reachable native formation points remain
where their full footprints fit; a blocked slot folds without displacing legal
slots or another unit’s native targets. Native front points stay inside the
contiguous legal frontage. When terrain constrains the side, the requested
frontage bounds a contiguous set of lanes, chosen centre-out with the negative
side first on ties. Both centred and half-pitch placements are tested; closed
lateral gaps are never jumped. Overflow targets deepen by `battle_group_depth_m`,
with no duplicate occupied target and no personnel changes. A blocked or
unreachable footprint leaves its row at its actual arrival/rear point. Desired
targets may remain beyond a transient friendly queue; they grant no movement or
reserve promotion. Reserve admission belongs to its separate contact rule.

`sweep_clear` validates every cell intersecting the full swept disk/capsule,
including enclosed cells and end caps, using half `battle_group_spacing_m` as
radius. Raw grid bounds and closed endpoints are checked before clamped lookup;
boundary tangency is legal. Occupancy uses strict spacing against all other rows,
including the unit's reserves; a rigid sweep (`slot=-1`) excludes only its own
mutually translated rows. Charge and flank use this same predicate, retaining
their existing phase, run-up, contact and receipt writers.

Ordinary travel tries a clear budgeted direct step, then a private expanded
terrain/occupancy grid through the existing march router. Its resolution is no
coarser than the group radius, confined to the route/occupied-field box and
aligned to the factual source; a coarse pack cell cannot erase a group-sized
detour. Rejected centre-only
shortcuts fall back to validated cell-centre legs. Disconnected `[to]` fallbacks
are rejected; no cached pack grid is changed. `move_row` validates full terrain
connectivity and the actual swept step, rounds inward to budget, and persists
only integer point/path pairs. It moves no anchor. A temporarily blocked route
waits without spending a second budget; pending rounds freeze all these writes.

Existing same-unit saved overlap can leave only by strict physical separation:
valid distinct positive-count slots must already overlap at the actual committed
source point. Every still-overlapping nonzero leg has nonnegative outward dot
product, so squared distance strictly increases. On reaching normal spacing,
ordinary full swept occupancy resumes; reentry is rejected. Arbitrary query
origins, new/cross-unit/enemy overlap, terrain and bounds have no exception.
No saved exemption, source relocation, data/budget change or combat/admission
privilege is introduced. Candidate native front points are reserved first;
conflicting rear targets try further configured-depth positions, leaving saved
source rows untouched. Contact uses the same complete terrain footprint.
