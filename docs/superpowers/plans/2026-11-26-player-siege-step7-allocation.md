# Player siege step 7: the men pool and allocation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Spec §11 row 7 (§3 activation, §4 "The men pool"). Each siege day the besiegers have a pool of men who can work; the record's `alloc` splits it over the five tactics in whole men, never more than the pool; a shrinking pool cuts the plan in a fixed order with a reason; an AI host plans by its doctrine. The blockade (step 6) now closes entries only with the men allocated to it.

**Architecture:** One new pure class, `SiegeTactics` (`scripts/engine/siege_tactics.gd`). `SiegeRecord._open` adds `alloc` ({} = no plan received yet) and `history` ([]). `SiegeSystem._siege_day` calls `SiegeTactics.day` once per active record, just before `SiegeBlockade.day`. `SiegeBlockade.close` spends the blockade's men (`SiegeTactics.men_for`) instead of every stationed fit man.

**Tech Stack:** Godot 4.7 GDScript, GUT.

**Spec:** `docs/superpowers/specs/2026-11-18-player-siege-design.md` §3, §4, §11 row 7. P6.2's fixtures: `docs/superpowers/plans/2026-10-16-battle-system/06-area-tasks-and-sieges.md`.

## Global Constraints

- Pinned, never edited: `army_system.gd`, `unit_bodies.gd`, `body_motion.gd`, `march_path.gd`, `war_front.gd`.
- Every number is data: the doctrine columns `siege_blockade_permille`, `siege_mine_permille`, `siege_bombard_permille`, `siege_ladders_permille`, `siege_engines_permille` in `data/battle/ai_doctrines.csv` (each row sums to 1000; `data/tables.csv` already lists the table).
- Whole men, fixed orders (tactics `blockade, mine, bombard, ladders, engines`; the cut `engines, ladders, mine, bombard, blockade`), no random number.
- Old saves: a record with no `alloc` or `history` reads them empty.
- Out of scope (later rows): `SIEGE_PLAN` and its words (row 12), what mine / bombard / ladders / engines men do (rows 8–10), the folio page (row 13).
- `wired: true`: the AI hosts' and the crown's sieges plan and blockade by the pool every day.

## Implementer's calls (for the owner to check)

- An AI commander plans afresh each day from its doctrine over that day's pool (`TownStores.apportion`, largest remainder), so an arrival adds men from its day and a loss never needs a cut. The cut order matters for a plan that stands: the crown's.
- A crown record with no plan received (`alloc` {}) blockades with its whole pool, as step 6 did. Men the crown's plan leaves out stand idle.
- The pool counts the men of the assault at the town; a battle anywhere else ("a field battle elsewhere") takes its units' men out.
- A cut is a line in the record's `history` ({day, kind `alloc_cut`, tactic, from, to, reason}); it raises no event and no letter (the crown's letters are row 12).
- First-draft doctrine: the main host gives most to the blockade, the raider and reserve all of it. While rows 8–10 are unbuilt the other tactics' men do nothing.

---

### Task 1: The data

**Files:** `data/battle/ai_doctrines.csv`, `scripts/engine/data_repository.gd`, `tests/engine/test_battle_data.gd`.

- [ ] Five `siege_*_permille` columns, the notes cell saying what they mean.
- [ ] Loaded into each `repo.ai_doctrines` row; a data test: each row's five sum to 1000.

### Task 2: The pool and the plan

**Files:** `scripts/engine/siege_tactics.gd` (new), `scripts/engine/siege_record.gd`. Test `tests/engine/test_siege_tactics.gd`.

- `men_of(repo, state, code, town)`: fit men less prisoner guards (`PrisonerBurden.guard_count`), 0 while the unit fights a battle not at `town`.
- `pool(repo, state, id)`: `men_of` over `SiegeSystem.stationed`.
- `refusal(alloc, pool) -> String`: "" when every key is a tactic, every value a whole non-negative number and the sum ≤ pool.
- `allocate(repo, state, id, alloc) -> Dictionary`: `{alloc}` stored with all five keys, or `{error}` with the plan kept.
- `cut(alloc, pool) -> Array`: the excess taken in the cut order; one {tactic, from, to} a tactic cut.
- [ ] Tests: P6.2's 300-men fixture (mine 120 + engines 100 + blockade 80 legal; ladders 1 more refused, the plan kept); the cut order on a loss (300 → 150: engines 100 → 0, ladders, mine 120 → 70, blockade kept); a wounded man and a man in a battle elsewhere leave the pool.

### Task 3: The day

**Files:** `scripts/engine/siege_tactics.gd`, `scripts/engine/siege_system.gd`, `scripts/engine/siege_blockade.gd`. Test `tests/engine/test_siege_tactics.gd`.

- `plan(doctrine, pool) -> Dictionary`: the doctrine's per-mille over the pool, whole men summing to it.
- `day(repo, state, id)`: an AI record re-plans by its leading host's doctrine (`EnemyAi.doctrine_of`); a crown record with a plan is cut to the pool, each cut logged in `history` with its reason.
- `men_for(repo, state, id, tactic)`: the plan's men; with no plan the whole pool blockades.
- `SiegeBlockade.close` spends the blockade's men, each unit giving at most what is left of them.
- [ ] Tests: staggered arrival (100 stationed, 200 on the march: pool 100 and the doctrine's plan of 100; arrived, 300; a 1000-man column far off never counts); a blockade of 0 closes nothing.

### Task 4: The run, the guide, the PR

- [ ] Bounded runs: `test_siege_tactics`, `test_siege*`, `test_battle_data`, `test_raid`, `test_invasion_end_to_end`.
- [ ] `scripts/engine/guide/siege.md`: the men pool paragraph; the blockade paragraph spends the blockade's men.
- [ ] PR: `prd_step: Step 8`, `player_outcome:`, `wired: true`, `GUT_INCLUDE: gameplay`.
