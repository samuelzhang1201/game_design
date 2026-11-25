# Player siege step 5: re-tune the invasion for militia — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The prologue's no-orders invasion, which step 4b changed (an empty town now raises militia and is besieged, not raided), plays again as the specs intend. The keys' notes describe the new run, and the two gameplay tests pin it.

**Architecture:** Tuning only. One balance value, the key notes, two tests and the plan itself. No new mechanic and no script constant.

**Tech Stack:** Godot 4.7 GDScript, GUT, `tools/sim_invasion.gd` (headless).

**Spec:** `docs/superpowers/specs/2026-11-18-player-siege-design.md` §11 row 5 (and ruling 3). The pacing target comes from `2026-10-07-enemy-ai-and-battle-design.md` §2: 15–30, "玩家约有一周反应".

## Global Constraints

- Design values live in `data/`; every key keeps a note; no constant goes into a script.
- Do not edit the pinned files `army_system.gd`, `unit_bodies.gd`, `body_motion.gd`, `march_path.gd`, `war_front.gd`.
- Tests take their data from `SuiteData`; the run is seed 11 on the default pack.
- PR body: `prd_step: Step 8`, `player_outcome:`, `wired:`, `GUT_INCLUDE: gameplay`. Never write `owner_approval:`.

## The run, before and after (seed 11, no orders, `sim_invasion --defence none --acknowledge-encounters`)

**Before (main today):**
- Day 15: the main host and the raiders cross.
- Day 17: the main host besieges the empty open town of Redckingin, which raises 63 militia (defend 34 against an attack of 2,000–4,200).
- Day 22: the first storm (17 + 5) breaks the militia in one round.
- Day 23: the town falls. The loss is paid and the main host HOLDs it.
- Days 26–32: the raiders raid a manor.
- Day 35: every host is homeward or holding.

So the empty town gives the player 6 days after the siege's first letter, short of the week the invasion spec promises. A weak garrison falls on the same day 22.

**After (`siege_assault_days` 5 → 7):**
- The first storm comes on day 24, and the town falls on day 25, a week after the siege's first letter.
- A weak garrison falls on day 24.
- The strong walled garrison still holds; the main host turns home hungry on day 30 (it was day 29).
- The raiders and the reserve are unchanged (home or holding by day 35).

**Tried and rejected:**
- `siege_assault_days` 10: the storm on day 27 breaks the militia with progress at 988, and the town then never falls before the host starves home (day 32). That is the established-siege "no fit garrison left" path, a mechanic for step 6+, not a tuning.
- A larger open-town militia (`town_militia.csv` town rows ×3, 190 men): it holds the storm for twelve rounds, but the town falls at 1000/1000 on day 27 while it is still fighting. The fall is two days later than with 7, but the militia fight past the town's fall. Left at its first draft; offered to the owner as the alternative.

## Review Focus

- A storm owed on a day the militia already broke: the town must still fall the next day (pinned by Task 2's fall = storm + 1).
- The strong walled run must still hold and turn the host home on supply (`test_strong_walled_defence_holds_and_forces_supply_retreat`, unchanged).
- A save mid-siege (`SAVE_DAY` 20) still replays to the same state hash (the determinism tests, unchanged).

---

### Task 1: The value and its notes

**Files:**
- Modify: `data/battle/balance.csv` (`siege_assault_days` 5 → 7 and its note; `raid_supply_permille` note's run sentence)
- Modify: `data/battle/town_militia.csv` (first row's note: drop "step 5 tunes", say what the run shows)

- [ ] Set `siege_assault_days` to 7. Its note describes the no-orders run the way `raid_supply_permille`'s does: storm on day 24, fall on day 25, weak garrison on day 24, strong holds and the host goes home on day 30. Name 5 and 10 as tried.
- [ ] Rewrite `raid_supply_permille`'s run sentence to today's run: the main host no longer raids, since the empty town is besieged; the raiders raid a manor on days 26–32 and turn home on supply.
- [ ] Run `sim_invasion` (none / weak / strong) and check the days above.

### Task 2: The tests pin the run

**Files:**
- Modify: `tests/engine/test_raid.gd` (`test_raiding_keeps_a_host_in_the_field_but_not_for_ever`)
- Modify: `tests/engine/test_invasion_end_to_end.gd` (`test_weak_defence_loses_the_town_and_the_campaign_plays_on`)

- [ ] `test_raid`: record the main host's `siege_begin` day, the first battle at its town (its defender is the record's militia unit), and `siege_fallen`. Assert storm = begin + `siege_assault_days`, the storm's defender is `militia:`, fall = storm + 1, and the main host HOLDs. Keep the raid and the all-home bound.
- [ ] `test_invasion_end_to_end` weak: assert the first contact at the town = `siege_begin` + `siege_assault_days` (the owed storm).
- [ ] Run `./run_tests.sh --test tests/engine/test_raid.gd --test tests/engine/test_invasion_end_to_end.gd`, then the diff-selected `./run_tests.sh`. Expected: all pass.

### Task 3: Show the owner, then land

- [ ] Show the owner the before/after day-by-day runs in Chinese and get an OK on the value.
- [ ] Commit, push, and open one PR. Report the number to the coordinator; do not merge.
