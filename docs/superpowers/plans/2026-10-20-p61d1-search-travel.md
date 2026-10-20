# P6.1d1 — delivered search travel

Bounded split of P6.1d, approved battle-system design §13.1/.2/.6. The old
uncommitted draft remains untouched in its original Claude checkout. Only its
MarchPath connectivity hunk is reused; no old whole-file replacement.

## Delivered behavior

A received search order starts real travel through TickEngine's route setup.
Pending revisions do nothing. A unit keeps its received circle until the new
revision reaches it. Existing march and camp gates determine actual movement.
The target is the centre when reachable; otherwise the closest reachable
integer point in an intersecting march-grid cell (row-major ties). A fully
inaccessible circle fails with a reason, without a straight-line fallback.

Arrival inside the circle saves `awaiting_search`, never coverage/completion.
Battle saves `paused_battle`, without issuing more search movement; a new
received revision can explicitly restart travel. Post-battle capability and
return policy remain P6.1f. The newest received task owns each unit, including
its recall, so an older received task does not reactivate. Revision snapshots
carry an integer issuance sequence, so revising an older task can supersede a
newer task after delivery, even on the same day. Cancelling travel
clears its saved departure as well as the immediate march order.

Per-unit travel day/revision, phase and reason survive JSON. Each processed day
has a reasoned history entry; retrying the same day changes nothing. Route
selection reads terrain and the unit's received order, never hidden enemies.

## Checks

Dedicated GUT scenarios cover pending/received actual daily movement, received
revision replacement, packing deadline and JSON retry, closed-centre fallback,
disconnected ground, arrival without false search completion, battle gate and
recall, task ownership, and hidden-state independence. Regress existing task
orders/preview, MarchPath, camps and day transactions. Required CI remains all
selected functional categories; no visual files change.

## Explicit dependent work

P6.1d2 depends on this PR: actual search execution with shared stable routes,
road/ford/pass/known-intel priorities, actual sight plus scouting footprints and
dates, re-search, enemy/traces/nothing-found/incomplete reports, feasible
keep-distance and legal approach/contact with no hidden pursuit. Do not ship the
old draft's normal-sight-only, never-research or halt-as-distance shortcuts as
full search behavior. P6.1f retains supply floor, post-battle capability and safe
return lifecycle; e/g retain raid/destroy and UI. P6.1d, P6 and P4 are not complete.
