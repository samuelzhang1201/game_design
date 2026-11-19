# Player siege step 1: the siege record — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the enemy's siege figures off the host minds (`GameState.ai_hosts`) into one saved record per besieged town (`GameState.sieges`). The siege must play exactly as it does today.

**Architecture:**
- A new static helper `SiegeRecord` (`scripts/engine/siege_record.gd`, `RefCounted`) owns the records: it opens and joins them, lets hosts leave, and runs the one-time migration.
- `SiegeSystem` keeps its logic. It now reads and writes the record where it used to touch the mind fields, and `_adopt` is deleted because a shared record has nothing to adopt.
- `BattleSystem` reads the assault flag through `SiegeSystem.assault_armed`.
- An old save converts at the end of `EnemyAi.ensure_deployments`, which already runs after every repository-backed load and before every settlement.

**Tech Stack:** Godot 4.7 GDScript (typed), GUT, `./run_tests.sh`.

**Spec:** `docs/superpowers/specs/2026-11-18-player-siege-design.md` — §3 (the record) and §11 step 1. Engine rules: `scripts/engine/guide/siege.md`, `scripts/engine/guide/battle_and_ai.md`.

## Global Constraints

- Every field is whole (int) or a string. Positions are not stored. Absent keys load empty.
- No random numbers, no wall-clock. Hosts are iterated in `EnemyAi.host_codes` order.
- Record ids are `"s<n>"` from the saved `GameState.siege_next_id`, starting at `"s1"`. There is one record per town.
- Engine-pure: nothing under `scripts/engine/` names a `scripts/ui/` class. Never edit the pinned `army_system.gd`, `unit_bodies.gd`, `body_motion.gd`, `march_path.gd` or `war_front.gd`.
- Behaviour is identical. Every existing siege, raid, invasion and defeat test keeps its expected values; only the line that reads or writes a figure changes (from the mind to the record).
- The main checkout `/Users/samuelzhang/game_design` is shared. Work in your own worktree, and hold the mkdir test lock around every Godot test run.
- The PR body carries the lines `prd_step: Step 8`, `player_outcome: groundwork for the player's own sieges; the enemy's siege plays as before` and `wired: false`. If `harness-checks` reports it as the sixth unwired PR, ask the owner for an `owner_approval:` line. Do not invent one.

## Decisions this plan makes (the spec leaves them open)

- **Fields written in step 1:** `town`, `attacker`, `defender`, `hosts`, `task_id` (`""`), `opened_day`, `days`, `integrity`, `progress`, `assault`, `assault_due`, `starved`. Later steps add their own fields.
- **`progress` is transitional.** It is the 0..1000 bar on `main` today. Step 10 removes it, so add a one-line note to spec §3.
- **`integrity`** is written only when the record opens: 1000 when the town's burg features include `walls` or `citadel`, else 0. On migration it is `1000 − progress` for a walled town. Nothing moves it in step 1.
- **`attacker`** is `SiegeSystem._kingdom_of(host)`. **`defender`** is `MapOwnership.owner_of(repo, state, <the burg's province_code>)` when the record opens.
- **The mind keeps `siege_id` only.** It replaces `siege_town` and, like `siege_town` today, stays set until the siege's end has been told.
- **Leaving a siege:**
  - When a host leaves SIEGE or DEPLOYING (`EnemyAi.set_mode`), it is removed from the record's `hosts`.
  - When `hosts` becomes empty, the figures reset to 0. This is today's `clear`.
  - A record is erased once no mind's `siege_id` names it.
  - Known difference: if a lead host leaves while another besieger stays, the figures now stay with the town. Today they are lost. `follow_main` sends a reserve home on the same day, so no test or ordinary play reaches this case.
- **`assault`** is one flag on the record. `assault_armed(state, host)` is true only for a host in the record's `hosts`. A host joins in `_siege_day`, so a late arrival is armed from the next day, as today. The line `mind["assault"] = 0` in `EnemyAi._update_deployment` is deleted.

## Review Focus

1. **An old save mid-siege** (a mind with `siege_progress` 250, `siege_days` 4, `assault` 1) loads to a record with progress 250, days 4, assault 0 and assault_due 1. Loading twice changes nothing. Test: Task 3.
2. **A reserve that sat down first, then its main host joins:** one record, days and progress continue, and no second `siege_begin`. Test: the existing `test_progress_follows_the_lead_host` (Task 2).
3. **Records do not leak:** after a siege is lifted and told, no record remains for that town, and a new siege there opens a fresh `"s<n+1>"`. Test: Task 2.
4. **A save mid-siege** round-trips through JSON with the same `SaveLoad.state_hash`, and its ints stay ints. Test: Task 1.
5. **A mind with stray legacy keys** that is in no siege (`"assault": 0` in `test_battle_save`'s fixture) loses those keys and gets no record. A non-siege mind with `siege_town` set gets a record with empty `hosts`, so the lift is still told once. Test: Task 3.

---

### Task 1: The record in `GameState` and `SiegeRecord`'s core

**Files:**
- Create: `scripts/engine/siege_record.gd`
- Modify: `scripts/engine/game_state.gd` (fields near `ai_hosts` at ~350; `to_dict` ~521; `from_dict` ~707)
- Test: `tests/engine/test_siege_record.gd`

**Interfaces — Produces:**
- `GameState.sieges: Dictionary` (id → record) and `GameState.siege_next_id: int`. Both are saved with `_encode_values` / `_decode_values` like `ai_hosts`, and absent ones load as `{}` and `0`.
- `SiegeRecord.ensure_for(repo: DataRepository, state: GameState, host: String) -> Dictionary`. For a host in DEPLOYING or SIEGE whose `target_kind` is town:
  - It returns the live record of the town (`state.sieges[id]` by reference), opening one if the town has none.
  - It adds `host` to `hosts` if missing, keeping code order.
  - It sets `mind["siege_id"]`.
  - It returns `{}` for any other host.
- `SiegeRecord.of_town(state: GameState, town: String) -> String` gives the id, or `""`.
- `SiegeRecord.of_host(state: GameState, host: String) -> Dictionary` gives the record the mind's `siege_id` names, or `{}`.
- `SiegeRecord.leave(state: GameState, host: String) -> void` takes the host out of `hosts`, and when `hosts` is empty sets `progress`, `days`, `assault`, `assault_due` and `starved` to 0. It keeps `siege_id`.
- `SiegeRecord.drop(state: GameState, host: String) -> void` erases `mind["siege_id"]`. It then erases the record if `hosts` is empty and no other mind names it.
- `SiegeRecord.walled(repo: DataRepository, town: String) -> bool` is true when burg `features` (split on `|`) contains `walls` or `citadel`.

- [ ] **Step 1: Write the failing tests** in `tests/engine/test_siege_record.gd` (extends `GutTest`; data from `SuiteData.repo()` / `SuiteData.campaign(repo, 7)`; pick a host with `Play.host(repo, "main")` (load `Play` as `test_siege.gd` does) and a walled and an open crown town from `repo.burgs` features):
  - `test_first_record_is_s1_and_one_per_town`: put two hosts in SIEGE before the same walled town and call `ensure_for` on each.
    - `of_town(s, town) == "s1"` and `s.siege_next_id == 1`.
    - `hosts` equals the two codes in code order.
    - `integrity == 1000`, `progress == 0`, `days == 0`, `task_id == ""`.
    - `attacker` is the raider realm's code and `defender` is the player realm's.
  - `test_open_town_has_no_integrity`: an open town gives `integrity == 0`.
  - `test_leave_resets_only_when_empty`:
    - Set `progress = 300`, `days = 5`. After `leave(main)`, progress is 300 and the reserve is still in `hosts`.
    - After `leave(reserve)`, progress, days, assault, assault_due and starved are all 0.
  - `test_drop_erases_when_no_mind_names_it`: after `leave` and `drop` for both hosts, `s.sieges.is_empty()`. A new `ensure_for` gives `"s2"`.
  - `test_round_trip`:
    - Set progress 412 and days 9 on an opened record.
    - `GameState.from_dict(JSON.parse_string(JSON.stringify(s.to_dict())))` gives the same `sieges` and `siege_next_id`, and `typeof(days) == TYPE_INT`.
    - `SaveLoad.state_hash` is equal before and after.
  - `test_absent_keys_load_empty`: a `to_dict()` with `sieges` and `siege_next_id` erased loads as `{}` and `0`.
- [ ] **Step 2: Run them and see them fail**: `./run_tests.sh --test tests/engine/test_siege_record.gd`. Expected: a parse error on `SiegeRecord`, or failures.
- [ ] **Step 3: Implement** the fields and the functions above. `opened_day` is `state.absolute_day()`. Record ids come from `siege_next_id += 1` and then `"s%d"`.
- [ ] **Step 4: Run them again**. Expected: all pass.
- [ ] **Step 5: Commit**: `git add scripts/engine/siege_record.gd scripts/engine/siege_record.gd.uid scripts/engine/game_state.gd tests/engine/test_siege_record.gd tests/engine/test_siege_record.gd.uid && git commit -m "Siege record: GameState.sieges and SiegeRecord core"`

### Task 2: `SiegeSystem` and its readers use the record

**Files:**
- Modify: `scripts/engine/siege_system.gd`:
  - header comment;
  - `clear`;
  - `settle_day`, `capture`, `follow_main`, `_siege_day`, `_fall` and `_lifted`;
  - delete `_adopt`.
- Modify: `scripts/engine/enemy_ai.gd`:
  - `set_mode` (~750) calls `SiegeSystem.clear(state, host_code)`;
  - the new-mind literal (~94) drops `"siege_progress": 0`;
  - `_update_deployment` (~1045) drops `mind["assault"] = 0`.
- Modify: `scripts/engine/army_ground.gd:756`, where the candidate mind literal drops `"siege_progress": 0`.
- Modify: `scripts/engine/battle_system.gd:425`, where `int(h.get("assault", 0)) == 1` becomes `SiegeSystem.assault_armed(state, host)`.
- Modify: `scripts/engine/game_state.gd:349`, the `ai_hosts` comment, which now names `siege_id` and points to `sieges`.
- Test: change only the lines that touch a figure in these tests:
  - `tests/engine/test_siege.gd`
  - `test_siege_deployment.gd`
  - `test_defeat.gd`
  - `test_army_clearance.gd`
  - `test_battle_lifecycle.gd`
  - `test_enemy_ai_targets.gd`
  - `test_enemy_spawn.gd`

**Interfaces — Consumes:** Task 1's `SiegeRecord`. **Produces:**
- `SiegeSystem.clear(state: GameState, host: String) -> void`, which is `SiegeRecord.leave`.
- `SiegeSystem.assault_armed(state: GameState, host: String) -> bool`.
- `SiegeSystem.record_of(state: GameState, host: String) -> Dictionary`, which is `SiegeRecord.of_host`. Tests read figures through it.

**Mapping:**

| Today | After this task |
|---|---|
| `mind["siege_progress"]`, `["siege_days"]`, `["assault_due"]`, `["starved"]` | the record's `progress`, `days`, `assault_due`, `starved` |
| the per-host `assault` loops | the record's `assault` |
| `mind["siege_town"] = town` | `SiegeRecord.ensure_for` |
| `…["siege_town"] = ""` | `SiegeRecord.drop` |
| `_lifted` reads `siege_town` | reads `of_host(...)["town"]` before calling `drop` |
| `_adopt(state, h, hosts)` | `ensure_for` for every host in `hosts` |
| `capture`'s `days` and `progress` | read from the record |

`_siege_day` calls `ensure_for` on the lead host first and then on each host in `hosts`, so the record exists before any figure is read.

- [ ] **Step 1: Add the new failing test** `test_lifted_siege_leaves_no_record` to `tests/engine/test_siege.gd`:
  - Set a siege for two days.
  - Send the host home with `EnemyAi.set_mode(s, main, "RETREAT", "test", [])` and settle a day.
  - Exactly one `siege_lifted` event, `SiegeRecord.of_town(s, town) == ""`, and `s.ai_hosts[main].has("siege_id")` is false.
  - A new siege at the town opens `"s2"`.
- [ ] **Step 2: Change the existing tests mechanically.**
  - Every read `s.ai_hosts[h]["siege_progress" | "siege_days" | "assault" | "assault_due" | "starved"]` becomes `SiegeSystem.record_of(s, h)["progress" | "days" | "assault" | "assault_due" | "starved"]`.
  - Every write before a settle becomes `SiegeRecord.ensure_for(repo, s, h)["progress"] = …`.
  - A `.get(…, 0)` read on a host that keeps no record stays a `.get(…, 0)` on `record_of(…)`.
  - In `test_one_siege_a_town_with_the_reserve_beside_its_main_host` and `test_progress_follows_the_lead_host`, the "the reserve keeps none" lines become an assertion that `record_of(s, reserve)` and `record_of(s, main)` are the same id. Every expected number stays as it is.
- [ ] **Step 3: Run the changed tests and see them fail**: `./run_tests.sh --test tests/engine/test_siege.gd` and `--test tests/engine/test_siege_deployment.gd`. Expected: failures on `record_of` and on the new test.
- [ ] **Step 4: Implement** the mapping above. `grep -rnE 'siege_progress|siege_days|siege_town|assault_due|"starved"|\["assault"\]' scripts` must then show only the migration (Task 3), the legacy branch of `ensure_deployments` (enemy_ai ~1020) and `missive_writer.gd`'s local `siege_town` variable.
- [ ] **Step 5: Run the affected suites**:
  - `./run_tests.sh --category engine-military`
  - the seven changed test files one by one with `--test`, including `tests/engine/test_invasion_end_to_end.gd`, which is unchanged

  Expected: all pass with their expected values unchanged.
- [ ] **Step 6: Commit** the engine files and the changed tests: "Siege: SiegeSystem reads and writes GameState.sieges".

### Task 3: Migration of an old save, and the guides

**Files:**
- Modify: `scripts/engine/siege_record.gd` (add `migrate`), and `scripts/engine/enemy_ai.gd` (`ensure_deployments`, which calls `SiegeRecord.migrate(repo, state)` as its last line)
- Modify: `tests/ui/test_game_campaign_validation.gd:62-64`, where the three reads go through `SiegeSystem.record_of(Game.state, host)` with the same values (250, 4, 0) plus `assault_due == 1`
- Modify the guides:
  - `scripts/engine/guide/siege.md`: the "One siege a town" bullet describes the record and `siege_id`, and the record fields are listed in the guide's own words.
  - `scripts/engine/guide/battle_and_ai.md:45`: "retaining progress and days" now names the record.
- Modify the spec, `docs/superpowers/specs/2026-11-18-player-siege-design.md`:
  - §3: one line saying `progress` is transitional and removed in step 10.
  - §11 step 1 "Done when": "the existing siege, raid and invasion tests keep their expected values (their figure reads move to the record)".
- Test: `tests/engine/test_siege_record.gd`

**Interfaces — Produces:** `SiegeRecord.migrate(repo: DataRepository, state: GameState) -> void`.

What `migrate` does for each host in `EnemyAi.host_codes` order whose mind has any of the keys `siege_progress`, `siege_days`, `siege_town`, `assault`, `assault_due` or `starved`:
1. **The mind is in DEPLOYING or SIEGE before a town.** Call `ensure_for`. The record takes the larger of its own figure and the mind's for `progress`, `days`, `assault_due` and `starved`. A mind `assault` of 1 becomes `assault_due` 1, and the record's `assault` is 0. For a walled town, `integrity` = `1000 − progress`.
2. **The mind is in another mode and `siege_town` is not empty.** Open a record for that town with empty `hosts`, and set `siege_id`, so `_lifted` still tells it once.
3. **Any other mind.** Nothing is opened.

In every case, erase the six keys. When at least one mind converted, write `state.military_migration["siege_record"] = {"day": state.absolute_day(), "minds": <count>, "reason": "siege figures moved from ai_hosts to GameState.sieges (player siege spec §3)"}`. Check that `from_dict` keeps an unknown `military_migration` key; if it does not, add `siege_record` to what it keeps.

- [ ] **Step 1: Write the failing tests** in `tests/engine/test_siege_record.gd`:
  - `test_old_mind_converts_once`:
    - Start from a SIEGE mind on a walled town with `siege_progress` 250, `siege_days` 4, `assault` 1, `starved` 1.
    - After `migrate`: `record_of` has progress 250, days 4, assault 0, assault_due 1, starved 1 and integrity 750.
    - The mind has none of the six keys, and `military_migration["siege_record"]["minds"] == 1`.
    - A second `migrate` leaves `SaveLoad.state_hash` unchanged.
  - `test_reserve_and_main_minds_merge`: both minds carry figures (main 100 / 2 days, reserve 180 / 3 days). They give one record with progress 180 and days 3, matching today's `_adopt`.
  - `test_stray_keys_no_record`: an ADVANCE mind with `"assault": 0` loses the key, `s.sieges.is_empty()`, and no `siege_record` marker is written.
  - `test_pending_lift_kept`: a RETREAT mind with `siege_town` set gives a record with empty `hosts`. The next `SiegeSystem.settle_day` has exactly one `siege_lifted` event for that town and leaves `s.sieges` empty.
- [ ] **Step 2: Run them and see them fail**: `./run_tests.sh --test tests/engine/test_siege_record.gd`.
- [ ] **Step 3: Implement** `migrate` and the call at the end of `ensure_deployments`. The call goes after the legacy branch, which still reads and writes the mind's `assault` and `assault_due`.
- [ ] **Step 4: Run the checks**:
  - `./run_tests.sh --test tests/engine/test_siege_record.gd`
  - `--test tests/ui/test_game_campaign_validation.gd`
  - `--test tests/engine/test_battle_save.gd`
  - then `./run_tests.sh --base origin/main`, the categories the diff selects

  Expected: all pass. The guide-size test passes: `tests/engine/test_claude_md_size.gd` caps the guides.
- [ ] **Step 5: Commit** the migration, the test changes, the guides and the spec lines: "Siege record: migrate old saves; guides". Open the PR against `main` with the body lines from Global Constraints. Merge only when every required check on HEAD is green.
