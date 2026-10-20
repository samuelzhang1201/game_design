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
