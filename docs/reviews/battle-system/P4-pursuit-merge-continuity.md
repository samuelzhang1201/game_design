# P4: pursuit continuity across battle aliases

Scope: `BattleTaskSystem.deliver_task` and `test_pursuit_merge_continuity.gd`.
Approved behavior: 2026-10-17 unit behavior spec §9, §11, §14. A same-meaning
pursuit reissue keeps accumulated route metres across battle merging; a changed
target or bound starts a fresh task. Issuance remains pending until delivery.

The received and replacement requests identify the same battlefield when their
IDs resolve through `BattleSystem.canonical` to the same survivor. Compare that
identity before the existing task/target/maximum/normalized-region comparison.
Keep stored request IDs intact for exact retries and provenance. No schema,
merge, authority, sequence, courier, or terminal-task behavior changes.

Regression exercises actual group-contact merging with the crown on either
survivor side, a replacement sent through ActionSystem and delivered through
CourierSystem after JSON, and progress credited while the courier is pending.
The real saved march must stop at the original budget: 400 + 400 + three 77 m
substeps = 1031 m, crossing 1000 m after only 231 m of the new day's walk.
Normalized region reordering preserves progress; leaving that region halts and
holds. Changing only maximum, region, or target starts at zero.

This does not implement the separate full-route/group region geometry work.
No visual changes.
