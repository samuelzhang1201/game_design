# Battle groups

`BattleGroups` splits each battle unit's fit personnel into representative groups of at most `battle_group_size` (the last group the remainder, units never pooled) and saves them as `battle.groups[unit] = [{slot, count, role, x_m, y_m}]` with `battle.group_facing[unit]` (whole degrees, `WarFront.facing_deg` convention: 0 = +x, y down, toward the mean anchor of the other side's units, 0 when none; an explicit unit facing takes precedence, and a received flanker faces its saved known target). Initial positions add `BattleFormation.slots` to the unit’s `x_m/y_m` anchor, scaled by `battle_group_spacing_m` across and `battle_group_depth_m` away from the enemy, rotated to facing and rounded once to whole metres. Role is `front` for slots on the foremost rank, else `reserve`. `refresh` reconciles fit counts in saved order, preserving survivors’ positions, roles, paths and IDs through losses and facing/formation changes. Only tail rows retire; growth appends reserves behind the rear. Missing rows seed once at the arrival anchor; legacy rows gain slots in array order. `group_next_slot` on each regiment/foe exceeds saved slots and never reuses IDs across departure, JSON or battles. Departed units lose rows; closed ground blocks legacy contact. `group_anchor_m[unit]` saves the committed anchor pair; row `path_m` optionally saves integer pairs. Pending rounds freeze reconciliation and deployment. Deployment lines (`BattleGroups.deployment`, pure): the axis runs from the defenders' mean anchor toward the attackers' (+x when they coincide); each side's line centre is the battle place ± axis × `battle_line_gap_m` / 2 (att on the + side); a side's units stand abreast in sorted code order, each as wide as its front groups (front count × `battle_group_spacing_m`, at least one spacing), the side centred; a unit's target anchor is the centre of its width, rounded to whole metres once. `deploy_day` (top of `prepare_day`, before the refresh, once per absolute day via the saved `battle.deployed_day`) steps every unit's anchor `x_m/y_m` toward its target by at most `battle_deploy_step_m` whole metres, stopping exactly on it. It moves both sides, but not a captured unit, one with no fit man, or one seated in a town (its walls are its line), and the whole battle stops deploying once any side is ordered to retreat or any unit is withdrawing (`battle_retreat` or `disengaging`), so the winner never closes on a falling-back side; `_start` stamps `deployed_day` so the day of contact moves nothing. `translate` commits validated deployment/charge/flank deltas once to anchor, rows, paths and snapshot. Live crown/foe withdrawal, legacy or saved, uses `follow_anchor` to move rows by the published anchor delta without moving the anchor again. Previews write no rows/snapshots; repeated synchronization is inert. Saved marches retain the consumed day/substep pair to prevent replayed movement/run costs. Merge folds rows, facings and snapshots before reconciliation, preserving charge/task progress. Contact (P4.4d4): `BattleGroups.engaged_permille` is (engaged x 1000 + (fit - engaged) x `battle_reserve_permille`) / fit, integer division, where engaged is the summed count of the unit's `front` groups within `battle_group_contact_m` (inclusive, squared whole metres) of any group of the other side; a reserve rank or a front still approaching counts only the reserve share; 1000 with no saved groups. `BattleSystem.unit_strength` lists it as `contact:engaged` (category `contact`, between `formation_terrain` and `action`, clamped like every category by `battle_strength_factor_min/max_permille`) with the reason "N of M in contact with the enemy line", so siege assaults, town battles and events inherit it.


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

Group-size migration waits while any live round remains pending. New encounters
inside a resumed legacy day seed the same legacy size as its live battles, so
merges never mix group contracts before the common safe boundary. Living-cap
work on unrelated idle units retains its private-candidate publication rules.

Successful monthly wound recovery refreshes the unit's existing battle rows in
the same settlement; surviving slots and points persist, and pending rounds
retain their frozen rows through the existing refresh guard.
