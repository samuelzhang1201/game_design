# Armies (selection groups)

Loaded on demand from `scripts/engine/CLAUDE.md` (Topic guides).

`ArmyGroups` (spec `2026-11-27-army-groups-design.md`): an army is a named SELECTION GROUP of the crown's live land regiments, never a merged force — no rule reads it; each regiment keeps its own march, supply and battle. `GameState.army_groups` (id → name, members, formed tick/day), `army_group_next_id`, `army_group_log` (every change with its reason, capped by `army_group_log_keep`), all saved. A regiment is in at most one; forming takes it from its old one; fewer than `army_group_min_members` live members dissolves it. Names are `data/army/army_group_names.csv` in order, the first not in use. `ArmyGroups.reconcile` runs at the top of `MilitaryReorganization.reconcile` (every day end and load) and drops the dead or lost; a living-cap split leaves its army. Only `Game.form_army_group` / `disband_army_group` write it — bookkeeping, not an order (no cost row, no courier).
