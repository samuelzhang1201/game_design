# Battle groups

`BattleGroups` splits each battle unit's fit personnel into representative groups of at most `battle_group_size` (the last group the remainder, units never pooled) and saves them as `battle.groups[unit] = [{slot, count, role, x_m, y_m}]` with `battle.group_facing[unit]` (whole degrees, `WarFront.facing_deg` convention: 0 = +x, y down, toward the mean anchor of the other side's units, 0 when none; an explicit unit facing takes precedence, and a received flanker faces its saved known target). Initial positions add `BattleFormation.slots` to the unit’s exact `x_m/y_m` anchor, using the shared calibrated metre pitch across and away from the enemy, rotated to facing and rounded once to whole metres. Role is `front` for slots on the foremost rank, else `reserve`. `refresh` reconciles fit counts in saved order, preserving survivors’ positions, roles, paths and IDs through losses and facing/formation changes. Only tail rows retire; growth appends reserves behind the rear. Missing rows seed once around the arrival anchor; legacy rows gain slots in array order. `group_next_slot` on each regiment/foe exceeds saved slots and never reuses IDs across departure, JSON or battles. Departed units lose rows; closed ground blocks legacy contact. `group_anchor_m[unit]` saves the committed anchor pair; row `path_m` optionally saves integer pairs. Pending rounds freeze reconciliation and deployment. Deployment lines (`BattleGroups.deployment`, pure): the axis runs from the defenders' mean anchor toward the attackers' (+x when they coincide); each side's line centre is the battle place ± axis × (the sum of both sides’ largest figure radii plus `battle_line_gap_m`) / 2 (att on the + side); a side's units stand abreast in sorted code order, each as wide as its front groups (front count × the calibrated `BattleGroups.pitch`, at least one pitch), the side centred; a unit's target anchor is the centre of its width, rounded to whole metres once. `deploy_day` (top of `prepare_day`, once per absolute day via saved `battle.deployed_day`) moves saved rows toward terrain-constrained targets in side/code/slot order, each with one `battle_deploy_step_m` budget. The rounded mean of actual rows becomes the summary anchor and its `group_anchor_m` snapshot; it never translates the rows again. It moves both sides, but not a captured unit, one with no fit man, or one seated in a town (its walls are its line), and the whole battle stops deploying once any side is ordered to retreat or any unit is withdrawing (`battle_retreat` or `disengaging`), so the winner never closes on a falling-back side; `_start` stamps `deployed_day` so the day of contact moves nothing. `translate` commits validated deployment/charge/flank deltas once to anchor, rows, paths and snapshot. Live crown/foe withdrawal, legacy or saved, uses `follow_anchor` to move rows by the published anchor delta without moving the anchor again. Previews write no rows/snapshots; repeated synchronization is inert. Saved marches retain the consumed day/substep pair to prevent replayed movement/run costs. Merge folds rows, facings and snapshots before reconciliation, preserving charge/task progress. Contact (P4.4d4): `BattleGroups.engaged_permille` is (engaged x 1000 + (fit - engaged) x `battle_reserve_permille`) / fit, integer division, where engaged is the summed count of the unit's `front` groups within an actual footprint-edge gap of `battle_group_contact_m` (inclusive; the squared centre bound adds both calibrated radii) of any group of the other side; a reserve rank or a front still approaching counts only the reserve share; 1000 with no saved groups. `BattleSystem.unit_strength` lists it as `contact:engaged` (category `contact`, between `formation_terrain` and `action`, clamped like every category by `battle_strength_factor_min/max_permille`) with the reason "N of M in contact with the enemy line", so siege assaults, town battles and events inherit it.


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

`refresh` validates newborn full footprints against terrain and existing groups.
Blocked native positions reuse the terrain allocator around the factual unit anchor;
new growth remains reserve and surviving rows stay fixed. If any new slot has no
legal position, no candidate rows, counts or slot identities are published. New
contact and reinforcement membership publish only after successful reconciliation.

`targets` is pure and consumes existing saved slots. Reachable native formation points remain
where their full footprints fit; a blocked slot folds without displacing legal
slots or another unit’s native targets. Native front points stay inside the
contiguous legal frontage. When terrain constrains the side, the requested
frontage bounds a contiguous set of lanes, chosen centre-out with the negative
side first on ties. Both centred and half-pitch placements are tested; closed
lateral gaps are never jumped. Overflow targets deepen by the calibrated depth pitch,
with no duplicate occupied target and no personnel changes. A blocked or
unreachable footprint leaves its row at its actual arrival/rear point. Desired
targets may remain beyond a transient friendly queue; they grant no movement or
reserve promotion. Reserve admission belongs to its separate contact rule.

`sweep_clear` validates every cell intersecting the full swept disk/capsule,
including enclosed cells and end caps, using the unit’s calibrated figure radius. Each arm’s full-piece clearance in
`army_clearance.csv` and the maximum nominal figure count in `army_formations.csv`
derive the circumscribed figure radius as `ceil(clear_m * sqrt(2 / figures))`,
with half the configured group spacing as its floor. Pitch is at least the
figure diameter on both axes; configured spacing/depth remain minima. The
ordinary compact block keeps its existing calibrated presentation; a held line
and tactical shapes expand around their exact anchor using this metre geometry.
`army_clearance_on = 0` retains explicitly configured geometry for isolated
fixtures. Saved `group_radius_m` records each unit’s positive integer radius;
refresh preserves pending transactions and never moves surviving saved rows.
Old rows use the same strict existing-overlap exit, without teleporting them.
 Raw grid bounds and closed endpoints are checked before clamped lookup;
boundary tangency is legal. Occupancy uses the sum of the two calibrated radii against all other rows,
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

Contact and charge approach measure the configured contact reach between the
occupied group surfaces. The two side lines include their front radii in their
gap; no model-size, damage, personnel, budget or clock value changes. Flank sight
snapshots retain the actual saved points and their occupied radius. Unit clearance
covers the farthest actual group plus its radius, so a wider line holds wider
real ground rather than becoming a display-only offset.

## Unit clearance and held formations

- **Clearance** (spec `2026-10-14-unit-clearance-and-scouting-design`, owner rulings 2026-10-14 and 2026-10-15): no two LAND units with men (the crown's, the foes', the roster's others at their pack places; a fleet is exempt) stand within D = r_a + r_b of each other, r the unit’s actual occupied radius (derived from `data/army/army_clearance.csv` and its unchanged drawn formation; a royal unit reads its chief arm; `army_clearance_on` 0 turns the rule off, `SuiteData.no_clearance`). A unit in a battle with saved `groups` holds its deployment: its radius also covers the farthest group’s distance from its anchor (rounded up) plus that group’s calibrated `BattleGroups.group_radius`, so outside columns go round the ground it occupies. `MarchClearance` is the pure geometry (whole metres, every function takes D per blocker and works on the disc of D + 1: `first_entry`, `halt_point`, the octagon of radius `r8` = ceil(D / cos 22.5) + 1 with ceil'd diagonals, `hull`, `clump`, `detour`); `ArmySystem.clearance_blockers` is the record of who stands where (built for each tactical movement substep, which writes each mover's place back, crown codes then foe codes; the previews `march_ahead` / `CourierSystem.day_path_of` share one record per state, day and set of places; the forecasts `march_days_between` / `days_out` pass none, "if the road is clear"). `_march_one(…, blockers)` clips the day's walk against the others' CURRENT places inside a box round the walk. A unit the column stands inside the disc of is let go only while its next leg does not close on it; one it closes on stops an enemy-bound column on the spot. The first disc the walk enters decides: a unit AT WAR with it (`_enemies`: kingdoms at war — the crown and the raider realm, or a diplomacy `Enemy` — so the raider's STANDING roster units too, not only its hosts) anywhere on the road, or a unit within D of the destination, or a clump whose hull holds the destination, is a HALT; any other unit is gone round (an octagon round it and the STANDING units whose octagons touch its, none further than three pair radii from it, plus the units an earlier pass went round; the hull's shorter side, the right side on a tie; each leg checked on the march grid; spliced into `route_m`) or waited behind (the column stands at the hull's entry, its order stays march). An enemy is NEVER gone round. A column that waits two days running gives way (R-C): of two waiting on each other the later code stops where it stands (order garrison, `road_blocked_by`), a crown unit's stop is the news line `army_road_blocked`; the AI re-plans. A halt is an arrival: order garrison, destination here, `halted_by` (the blocker's code), `halt_day`, `halt_aim_m` (where it was bound), the parked hold dropped, `facing_deg` toward the blocker; the news bar says `army_halt_short`. A column halted before a non-enemy camps (`ArmyGround.settle` with `near_m`: the free slot nearest the halt point); before an enemy it stays where it halted. A HOST column halted by a friendly within `army_spread_reach_m` of its target takes the nearest free camp slot round the target from ring 1 (`ArmySystem._spread_foe`, `ArmyGround.free_slot`), so a host spreads round its town instead of queueing. A column just outside that circle also enters when its actual friendly blocker is inside it, the stored halt aim matches, and their current separation is no greater than their clearance radii plus `army_clearance_touch_m`; stale remote halt metadata is insufficient. The spread search uses `free_slot`'s optional `max_radius_m` to filter candidates to the target circle; other callers retain the unbounded default; `SiegeSystem.at_town` counts that reach as at the town; `EnemyAi._stands_halted` keeps a standoff (same aim, an enemy still obstructing the onward road, or a friendly blocker at a slot) from being re-aimed. `set_march_m` and `aim_entry` clear the halt fields (and the facing of a new destination); `facing_of` reads a foe's too. Camps: the lattice pitch is `army_slot_spacing_m`; actual occupied radii can require skipping adjacent rings; `ArmyGround.is_free(…, radius)` refuses within the radii's sum (half a pitch when the rule is off), `take` records a radius, `held_taken` counts marchers, a seat is taken only while no unit stands within clearance of the town's point, a seat a march empties is refilled by `ArmyGround.reconcile` once the point is clear (at once, in `leave`, with the rule off); `EnemyAi.spawn` puts a host's first unit on its assembly point and spreads the rest on the lattice. Accepted: two columns both moving may cross on screen mid-day; clearance holds at every day's end and always against standing units.

A held line’s ground expands with its calibrated metre formation around its
accurate unit anchor (`BattleGroups.figure_radius`, `pitch`, `occupied_radius`).
Ordinary compact blocks retain their visible spacing; their occupied circle
circumscribes the calibrated nominal square and expands for larger slot spans. Live battle
clearance covers the actual saved groups plus their figure radius; standing line
clearance covers its current slots. Camp allocation, march blockers and contact
read that occupied radius, never a smaller display-independent counter radius.
Miniature scale, group personnel and movement budgets remain unchanged.

Opening and automatic seat admission validate the chosen unit’s full occupied
clearance against other units before moving it onto the town point, retaining
the existing town camp terrain policy. Group births and travel still require
every complete individual footprint to clear terrain.
A blocked seat stays empty; the candidate keeps its existing legal camp.

A friendly column stopped just outside a town’s centre reach retains that town
as its camp only when its saved march aim names the same town as its blocker’s
garrison and the actual halt lies within their full clearance of its reach.
Automatic refill ranks only candidates whose actual circle can enter the seat,
excluding their own old camp from blockers. Host town arrival uses the same
occupied-surface contact boundary as battle discovery, so lawful clearance does
not strand a host outside an obsolete centre-distance threshold.
