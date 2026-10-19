# P4.4b9 — WAR ROOM unit task interface

Approved spec: `2026-10-17-unit-behavior-and-battlefield-design.md` §§4.1–4.3.

The player-facing slice after merged P4.4b8 (PR102): the WAR ROOM's docked folio
of a selected battlefield unit issues the public `BATTLE_TASK` and
`BATTLE_TASK_CANCEL` for that one unit. It closes P4.4b; P4.4c (walk/run costs,
search/pursuit bounds), P4.4d (group positions, contact) and P4.4e (contact-only
merge) remain.

- **Engine (pure, read-only)**: `BattlePresentation.task_view(repo, state, code)` —
  empty unless the unit is the crown's and stands on an active battlefield; else
  the battle id and place, the task / target / formation choices (`behaviors.csv`,
  the opposing side's units still able to fight, `formations.csv` after "keep the
  current deployment"), and the ledger's status: the received task, every pending
  one (courier riding or awaiting delivery) and the newest terminal refusal with
  its reason. `BattlePresentation.task_quote(repo, state, code, task, target,
  formation)` (task `cancel` → `BATTLE_TASK_CANCEL`) returns the exact params to
  send (a fresh `request_id` from the unit's issued sequence), the
  `ActionSystem.validate` reason, the filing gold (`OrderCosts`) and the courier
  fee (`ActionSystem._fee_for`: none when local or joining a courier already
  waiting), and whether it is delivered here.
- **UI**: `WarFolioPanel` fills an editor-authored `%TaskOrders` block on the
  docked page (header, status, three drop-downs, the quote line, Send task /
  Cancel task), shown only while `task_view` is non-empty; Send runs the quoted
  request through `Game.try_execute`; a refusal is written in the quote line,
  a sent task reads Pending once the page refreshes. No code under
  `scripts/war_room/` changes (it never reads `Game`).
- **Look**: the nodes, their theme kinds (`FolioHeader` /
  `FolioValue` / `FolioTab`) and fixed words are authored through the editor
  (gdai MCP), never by text-editing the `.tscn`.

Owned: `battle_presentation.gd`, `war_folio_panel.gd`, `war_folio.tscn`, the
presentation and folio tests, `scripts/war_room/CLAUDE.md` (the folio rule),
`battle_deployment.md` (UI pointer), `tools/snapshot_screen.gd`'s
`--battle-case field` / `--war-task` shot flags and their line in `guide/shots.md`,
and this plan. No ActionSystem, CSV, save
schema or BattleTaskSystem change.

- [x] Red: `task_view` is empty for a unit off any battlefield and for a foe;
  lists the seven tasks, only fighting opponents, the four formations; status
  reads pending then received across a real courier and local delivery;
  `task_quote` cost equals the treasury actually spent by executing its params
  (filing + courier when new; filing only when joining or local) and its reason
  equals `ActionSystem.validate` for an unsuitable formation.
- [x] Implement the two pure functions.
- [x] Author `%TaskOrders` in `war_folio.tscn` through the editor; wire it in
  `WarFolioPanel`; a UI test drives the real buttons and sees the task pending.
- [x] visual-review: real-window shot of the WAR ROOM with a battlefield unit's
  docked folio (`tools/snapshot_screen.gd --resolution`), critic pass recorded.
- [x] Run presentation / folio / war room UI tests and `--fast`; one PR.

Layout ruling (visual review): five shots at 2560x1600 through the real window
(`--battle-case field --war-task`): v1 labelled rows under the page (51% of the
height, chevrons far from their words), v2 beside the figure (the figure grew
into a monument, words clipped), v3 a two-column grid (words clipped), v4 drop-downs
flowing at their words' width; an independent critic ranked v4 first and asked
for the price before the buttons and a tighter block — done. Final: ~46% of the
height at 2560x1600, clear of the tool roll at 1280x720. Left open: the
drop-downs and Cancel task share the drill tabs' `FolioTab` kind and the theme's
grey chevron, so they read a little like headings (a `paper_theme.tres` look
ruling for the owner, not this slice).
