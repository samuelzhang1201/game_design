# Army groups ("Form army") — design

Step 4 of the AAA UI overhaul. Owner ruling 2026-11-27: an army is a SELECTION
GROUP, not a merged force. Every regiment keeps its own march, speed, supply and
battle; orders still go to each regiment through the multi-selection paths.

## State (engine, `ArmyGroups`)

- `GameState.army_groups`: group id (String) -> `{name, members: [codes], formed_tick, formed_day}`.
  `army_group_next_id` hands out ids. `army_group_log` records every change with a reason
  (`formed`, `left`, `dissolved`, `disbanded`), capped by `army/balance.csv` `army_group_log_keep`.
  All saved whole in the JSON.
- A member is a live land regiment of the player's realm (in the roster, with state, someone
  alive). A regiment is in at most ONE group: forming takes it out of its old group.
- A group with fewer than `army_group_min_members` live members dissolves.
- `ArmyGroups.reconcile` (top of `MilitaryReorganization.reconcile`, so every day end and every
  load) drops dead or lost members; a regiment the living-cap reorganisation SPLITS leaves its group.
- The name is the first of `data/army/army_group_names.csv` not in use ("1st Army", …); all in
  use refuses with a reason.

## Writers

`Game.form_army_group(codes)` and `Game.disband_army_group(id)`, like `Game.plant_draft`: not
orders (no `OrderCosts` row, no courier, no clock) — the crown's own bookkeeping of which
regiments it commands together.

## Map and card

- Clicking a member selects the whole group (`Map3DSelection`), the clicked one first; Shift-click
  and Shift-drag are unchanged.
- The regiment card (`MapObjects.army_card` `group`) shows its group: name, total men under arms,
  members, the slowest member's march (information only), SELECT ARMY and DISBAND.
- **The army as the card's title** (owner 2026-11-27: 选中军团时把军团名做成卡片标题): while the
  selection is exactly one army, the card's title is the army's name ("1st Army"), its subtitle
  "Army of <kingdom>", the army block headed "Regiments (N)", and the clicked regiment's label
  heads its own stats below. A lone member's card keeps the regiment's title.
- With 2+ of the player's land regiments selected that are not already exactly one group, the
  card offers FORM ARMY.
- Ctrl+1..9 recall is not built (not needed for the ruling; a later step).
