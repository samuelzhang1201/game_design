# P4 known key-point gait

Scope: the remaining approved unit-behavior §5.1 run context, inside UnitGait;
no movement caller, task, route, charge, P6, scene or resource change.

Ruling: an existing received march into a town's reach is intent to reach that
known strategic point. A positive unit sighting from sight or a spy in that same
town, no older than ghost_keep_days, supplies the contest evidence. Rumours and
hidden foe truth do not. The crown's stored sightings are never given to foes.
The existing town footprint defines the point; no new urgency tuning is needed.
This bounded implementation covers towns, not a new arbitrary strategic-point
order system.

The saved gait records key_point / town_clear and the town code. Each substep
rechecks the march destination, known evidence and live willing commander;
existing withdrawal, pursuit and join-battle selection comes first. Camp packing,
base feeding and actual integer 120% pace / 130% time-based feeding remain in
the existing march pipeline.

Acceptance: hand-computed movement and supply; mid-day JSON continuation;
ordinary safe marching; stale/rumour/empty/outside evidence; unwilling/missing
commander; base-only food; hidden enemy changes; existing gait regressions.

Verification: TDD red (3 expected missing-context failures; all existing tests
passed), then final bounded run under the shared Godot lock:

`./run_tests.sh --test tests/engine/test_unit_gait_march.gd --test tests/engine/test_army_gait.gd --test tests/engine/test_camp_system.gd --test tests/engine/test_military_save.gd --test tests/engine/test_engine_isolation.gd --test tests/engine/test_claude_md_size.gd`

Exit 0; 6 scripts, 58 tests, 591 assertions. Runner parse/runtime/count/error
gates passed. Full local suite was not run; current-HEAD CI and sole independent
Review are required before merge. Guide is 29,938 characters, under its cap.
Evidence logs: `/tmp/p4-key-point-red2.log`, `/tmp/p4-key-point-final.log`.

Implementation: 01a15993-a73d-7a10-aa97-dad97f311c38. Unique Review assigned in
the worktree checkpoint and PR description at handoff. Only dispatcher
01a15959-7582-7233-9637-1f0f9d090d70 may create successors.

Limit: this context covers known contested towns using the crown's stored sight
and spy information. It adds no arbitrary-point urgency, hostile-side observer
system or P6 capability. No visual resources changed; no visual pass required.


## Independent Review

Review: 01a15999-0cb7-7e52-88b1-dc6e0d9a7532. Traced the actual march
callers, town knowledge gate, sight/spy writers, gait selection and food/save
paths. Found and fixed one priority bug: a saved key-point gait survived an
incoming withdrawal, authorized pursuit or known-battle context. Town urgency
is now reselected after those contexts every substep, without changing their
existing continuation rules. The regression failed in all three cases before
the fix (26/27 tests passed); the same cases pass after it.

Final bounded command is the six-script command above, rerun under the shared
Godot lock after the fix. Exit 0; 6 scripts, 59 tests, 612 assertions. Log:
`/tmp/p4-key-point-review-final.log`. Knowledge uses only stored positive unit
observations and existing known-town lookup; foe observers cannot read crown
sightings. Existing Sighting retention semantics remain a dependency.
No route/charge files, scenes or resources changed. Full local suite omitted.
Merge still requires all current-HEAD CI checks to pass.
