# Player siege step 6: blockade by entries and stores — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spec §11 row 6 (§4.1). A besieged town has real entries that the besiegers close with men; its food falls by what the closed entries keep out; at no food the defenders go hungry, and a starving garrison yields under the laws.

**Architecture:** One new pure class, `SiegeBlockade` (`scripts/engine/siege_blockade.gd`). `SiegeRecord._open` sets the record's `entries` and `stores`. `SiegeSystem._siege_day` calls `SiegeBlockade.day` once per active record, after the assault and before the day's gain. It closes entries, camps the closing units, moves a foreign town's stores, and starves its defenders. When a starving garrison yields, the town falls (`_fall`). `TownStores.deposit_month` gates a besieged crown town's inflow by its open share. `SupplyLines.siege_cut` cuts only a line whose road passes a closed entry.

**Tech Stack:** Godot 4.7 GDScript, GUT.

**Spec:** `docs/superpowers/specs/2026-11-18-player-siege-design.md` §3, §4.1, §11 row 6.

## Global Constraints

- Pinned, never edited: `army_system.gd`, `unit_bodies.gd`, `body_motion.gd`, `march_path.gd`, `war_front.gd`. `ArmySystem.hunger_day` already starves a crown garrison off its own supplies. A foreign town's defenders are foes, which `hunger_day` never reads, so `SiegeBlockade` takes the same `army_morale_starving_day` from them.
- Every number is data: `battle/balance.csv` `siege_entry_km`, `siege_entry_reach_m`, `siege_blockade_men_per_entry`, `siege_civil_need_permille`, `siege_yield_morale`; `data/battle/siege_tactics.csv` (`works,stores_days`); `data/battle/siege_entries.csv` (`group,entry_share`).
- Old saves: a record with no `entries` gets them on its first day; a foreign one with no `stores` key opens its stores that day.
- Out of scope (later rows): the men pool and `alloc` (row 7: until then every fit man stationed at the town blockades), terms and `SiegeTerms.relieved` (row 11), relief hosts (row 14), the UI and the 3D camps (rows 13, 15).
- `wired: true`: the invasion run reads the new day (camps move, the crown town's month is gated).

## Implementer's calls (for the owner to check)

- The entry shares are their own table, `siege_entries.csv`, beside `siege_tactics.csv` (by works). The spec names one table; a works-keyed table and a route-group-keyed table do not share a key.
- The countryside entry stands at the town's point. Any besieger stationed at the town (`deployed_at`) closes it, and no supply line passes it.
- An entry's point is on its route, `siege_entry_km` from the route's end nearest the town.
- A unit closes one entry at most. It cannot split its men between two.
- A closing unit that does not yet stand within `siege_entry_reach_m` of its entry camps at the free slot nearest the entry (`ArmyGround.free_slot`, the way `_spread_foe` places a host's columns). It does not move while it fights a battle or while it carries bodies (`body_groups`).
- A crown town's withheld month (the closed share of the crown's and the lord's units) lands in the nearest other realm town. The house's withheld share is lost. A realm whose only town is besieged keeps it in that town.
- The yield reads `own_surrender` of the first defender and `quarter` of the first stationed besieger, in code order, the way the sack reads `plunder`.

---

### Task 1: The data

**Files:** `data/battle/balance.csv`, `data/battle/siege_tactics.csv` (new), `data/battle/siege_entries.csv` (new), `data/tables.csv`, `scripts/engine/data_repository.gd`.

- [ ] Keys with notes: `siege_entry_km` 3, `siege_entry_reach_m` 2000, `siege_blockade_men_per_entry` 200, `siege_civil_need_permille` 1, `siege_yield_morale` 30.
- [ ] `siege_tactics.csv`: town 30, walls 60, citadel 90 days. `siege_entries.csv`: roads 400, trails 200, searoutes 300, countryside 300.
- [ ] Loaded as `repo.siege_tactics` (works → {stores_days}) and `repo.siege_entries` (group → share).

### Task 2: Entries and stores at open

**Files:** `scripts/engine/siege_blockade.gd` (new), `scripts/engine/siege_record.gd`. Test `tests/engine/test_siege_blockade.gd`.

- `entries_of(repo, town) -> Dictionary`: entry id (route code, or `countryside`) → {group, x_m, y_m, inflow_share, closed_by ""}. The raw shares are normalised to 1000 by `TownStores.apportion`.
- `need(repo, state, id) -> int`: the defenders' daily ration (`ArmySystem.day_bite` of each defender's `supply_use`) plus population × `siege_civil_need_permille` / 1000.
- `_open`, after the levy: `entries` and `stores` (a crown defender: 0, unused; else need × `stores_days` of the town's works).
- [ ] Tests: the shares sum to 1000; a town with no route has the countryside entry alone; each route entry stands `siege_entry_km` along its route.

### Task 3: The day — closing, camping, stores, hunger

**Files:** `scripts/engine/siege_blockade.gd`, `scripts/engine/siege_system.gd`. Test `tests/engine/test_siege_blockade.gd`.

- `close(repo, state, id)`: the entries but sea entries, by share descending then id, take the stationed besiegers (`SiegeSystem.stationed`) in code order until each has `siege_blockade_men_per_entry` fit men. An entry short of men stays open, and so does every entry after it. The closing units camp at the entry. `closed_by` is the first of them within reach after camping, else "".
- `open_share(rec) -> int`: the sum of the open entries' shares.
- `stores_day(stores, need, open_share) -> int` = max(0, stores − need + need × open_share / 1000).
- `day(repo, state, id) -> Dictionary`: close; for a foreign town, the stores move and at 0 every defender foe loses `army_morale_starving_day`. Returns {open_share, stores, starving, yield}.
- `SiegeSystem.starving` for a foreign town reads the record's stores at 0 with defenders standing.
- [ ] Tests: P6.2's fixture (100, 10, 400 → 94 on day 1, 40 on day 10; fully closed 0 on day 10, never below); 100 men close no entry of a town with more entries than they can hold, and the town keeps every share; `test_relief_requires_an_open_route`: a relief unit beside the town reopens nothing, and the entry reopens only once its closing unit is gone.

### Task 4: The crown town's inflows

**Files:** `scripts/engine/town_stores.gd`, `scripts/engine/supply_lines.gd`. Test `tests/engine/test_siege_blockade.gd`.

- `deposit_month`: a town with an active record takes each pool × open_share / 1000. The crown's and the lord's withheld units go to the nearest other realm town.
- `siege_cut(repo, state, code, route := [])`: cut only when the line's road passes within `siege_entry_reach_m` of a closed road entry (never the countryside, never the sea); `at` is that entry's point.
- [ ] Tests: half the share closed → half the month; a line whose road passes no closed entry flows; one that passes it is cut.

### Task 5: Yielding by hunger

**Files:** `scripts/engine/siege_blockade.gd`, `scripts/engine/siege_system.gd`. Test `tests/engine/test_siege_blockade.gd`.

- `yields(repo, state, id) -> bool`: starving, the defenders' mean morale < `siege_yield_morale`, the first defender's `own_surrender` is `allow` and the first stationed besieger's `quarter` is `give`.
- `hand_over(repo, state, id) -> Dictionary`: every defender's fit and wounded become the first stationed besieger's captives (`PrisonerSystem.capture`, id `siege_yield:<id>:<day>`, reason `<town> yielded to hunger`). Then `_fall`.
- [ ] Tests: a starving foreign garrison under low morale is captured, and the town is the crown's occupation; under `quarter refuse` it holds on, still starving.

### Task 6: The run, the guide, the PR

- [ ] Bounded runs: `test_siege_blockade`, `test_siege*`, `test_raid`, `test_invasion_end_to_end`, `test_supply*`.
- [ ] `tools/sim_invasion.gd --acknowledge-encounters` (none, weak, strong; seed 11). Update the pins and the `siege_assault_days` note if the days move.
- [ ] `scripts/engine/guide/siege.md`: the blockade paragraph; the hunger paragraph says what now starves a foreign town.
- [ ] PR: `prd_step: Step 8`, `player_outcome:`, `wired: true`, `GUT_INCLUDE: gameplay`.

## Follow-ups (not §4.1)

- From step 5: the militia that break at 988/1000 leave a town that never falls; a large militia fights on after its town has fallen; the militia's storm is a field battle.
