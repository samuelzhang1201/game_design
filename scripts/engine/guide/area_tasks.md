<!-- Area-task execution; engine and root invariants apply. -->
# Area tasks

Issuing, preview and courier revision contracts are in `regiments.md`.

`ArmyTasks.step_day` runs before TickEngine freezes daily movement. A unit
follows its newest received task; a pending replacement has no authority. A
received recall also prevents an older task from reactivating. Revision
snapshots carry an integer issuance `sequence` across tasks; older saves without
it use issued day and task ID as the stable fallback. Search travel
uses the received circle, existing march/camp gates and `MarchPath.joins`;
disconnected ground cannot invoke the ordinary march's straight-line fallback.
If the centre is unavailable, the target is the nearest reachable integer point
to the centre inside an intersecting grid cell, with row-major ties.

Per-unit `travel_day`/`travel_revision`, `phase` and `reason` are saved on the
task. Day retries do not duplicate history or restart packing. A travel-owned
march records `travel_task_id` on the regiment; a delivered recall clears that
march and its saved departure without teleporting the column. A battle gates
further search aims and saves `paused_battle`; it does not authorize an automatic
post-battle capability/return decision. A newly received revision can restart.

Entering the circle saves `awaiting_search`, with no coverage or completed
result. Search footprints, re-search, discovery/reporting and encounter policy
are the dependent P6.1d2 executor; supply/return and battle recovery are P6.1f.
See `docs/superpowers/plans/2026-10-20-p61d1-search-travel.md` for the remaining
acceptance. Arrival is never evidence that the area was searched.
