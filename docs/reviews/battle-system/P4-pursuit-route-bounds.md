# P4 pursuit route bounds

Scope: approved unit behavior spec §9, actual pursuit routes only. Prerequisite
#145 supplies group eligibility; group deployment contraction, flank, charge and
ranged geometry remain separate steps.

The route walk clips before publishing its physical stop. It checks every
polyline segment after terrain or unit-clearance detours, including the approach
to a clearance halt. Region checks split each segment at every live province
outline crossing, so concave notches, enclosed holes and outside intervals
between inside endpoints cannot be skipped. Distance and region compete; the
first reached stops the offensive movement. Rounding validates the traversed
integer-position prefix and uses an inner point when needed.

A bound retains the current task as `bounded`, holds defensively in contact and
clears the saved departure. It does not settle into a different camp slot or
remove a combatant. Target reentry does not restart it. Same-meaning receipts
retain partial distance and completed bounds; genuinely different pursuit bounds
or targets retain the existing fresh-budget behavior. Actual withdrawal remains
free to move, without spending an offensive pursuit budget. Pure previews do not
change task history, state or RNG. No save schema was added.

Hand-derived fixtures include:

- From (100,100) to (900,100), a region notch begins at x=400: both endpoints
  are inside, but the walk stops at (400,100), 300 metres along the route.
- With a 250-metre cap the same walk stops at (350,100); with a 500-metre cap
  and that notch it stops after 300 metres. A later-leg exit includes the
  already traversed leg.
- A dogleg walks 200 north + 300 east + 100 south = 600 metres, stopping at
  (400,200), rather than spending the budget on displacement from the start.
- A diagonal integer stop at offset (177,177) is 250.315 metres away and is
  refused by a 250-metre cap; (176,176), credited as 249 whole metres, fits.
- With two 20-metre clearance radii, contact west of an enemy at x=600 stops
  at x=559 (D+1), credits 459 metres from x=100, and preserves the blocker.
  An earlier pursuit boundary wins without teleporting to that contact.
- A real friendly-clearance detour spends more distance than displacement.
  Live manor reassignment updates the permissible union; multiple allowed
  provinces may share an internal seam. An enclosed hole and a slanting edge
  both stop a crossing. Mid-substep JSON/retry yields identical saved state.

Verification evidence and hashes are preserved in this worktree under
`.superpowers/p4-pursuit-route-bounds/`. The final checkpoint records exact
commands/results and the final commit. Review must independently inspect this
change and require every current-HEAD CI gate before merge.

No scene, resource, art or presentation change is included. This report is engine
acceptance evidence; it does not claim the later real-window P4 gameplay/visual
acceptance or completion of the other P4 steps.

Final local verification: 132 selected scripts, 1,466/1,466 tests passed;
the separately run merge-continuity suite passed 3/3. Both runner commands exited
0 through the shared Godot lock, retaining all parse/runtime/count/offline gates.
