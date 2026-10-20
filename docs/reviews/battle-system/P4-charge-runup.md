# P4 charge run-up

Step `p4-charge-runup`; dispatcher `01a15959-7582-7233-9637-1f0f9d090d70`.
Implementation `01a1597b-4383-7ae2-91cf-490b86f886f4`; sole Review assigned at handoff.

Cavalry now earns the existing shock casualty context by moving through a
passable, unoccupied group corridor into actual front contact. Standing at
contact, receiving an attack order, or the opponent approaching grants no
momentum. The default minimum actual run-up is 300 metres, in battle balance.
No new strength multiplier or gait rule is added.

The unit entry keeps integer origin/last position, run-up, impact day, target
phase and whole-degree approach heading; personnel regrouping cannot recreate momentum. Successful atomic
settlement consumes impact. Another impact requires real disengagement,
regrouping, and another approach. A failed casualty plan freezes movement and
retains its impact context through JSON and retry. Per-opponent loss rates
prevent an impact from raising casualties for another, distant unit.

Hand checks: gap 700 minus contact 100 gives 600 actual run-up; gap 399 gives
299 and no shock. Gap 100 gives no movement credit. Renewal separates to gap
400, spends a day regrouping, then rides 300 back to gap 100. The existing
1250 per-mille shock scale changes a 100 per-mille casualty tier to 125;
50 contacted defenders lose 6, whereas 50 distant defenders lose 5.

Final local validation: 19 affected GUT scripts, 197 tests and 1,350 assertions
passed through `run_tests.sh` under the shared Godot lock. The dedicated charge
script includes 18 contracts, with observed RED-to-GREEN cases for stationary
shock, diagonal contact, incapacity, changing targets and changing approach
direction. Save/retry tests preserve the exact state hash and frozen RNG.

Frozen input hashes, exact commands, exit codes and logs are recorded in the
worktree-local handoff checkpoint. Required current-HEAD CI and the sole
independent Review remain the merge gate.

Limit: blocked straight corridors wait; this step adds no charge detour planner.
No visual assets or presentation logic change; animation contributes no result.
