# Player siege step 3: sides generalised — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The siege record's `attacker` / `defender` drive the siege. A crown besieger (a record listing crown `units`) uses the same day, the same capture and the same occupation as an enemy host, and so can take back a town the enemy occupies. The enemy's siege of the crown plays exactly as before.

**Architecture:**
- **Occupation leaves the host minds.** It becomes one saved entry per occupied town, `GameState.occupations[town]`, for either side. `SiegeSystem.holder_of(town)` is the occupier if there is one, else the province owner. `ArmyGround.holds`, `EnemyAi.target_held` and `SiegeRecord._open`'s defender all read it.
- **`SiegeSystem` reads the record's sides.**
  - The besieging units are the hosts' stationed columns plus the record's `units`.
  - The defenders are `defenders_of(town)`: the crown's garrison when the crown holds the town, else the holder's foes standing at the town.
  - One `_siege_day` runs a record. The leading host runs an AI record (as now), and `settle_day` runs each crown record after the hosts.
  - The fall goes through one `_occupy`. Its attacker either takes back an occupation of its own town (liberation) or occupies afresh.
- **`BattleSystem._detect` mirrors the no-contact rule.** A crown besieger does not fight the town's defenders until the record's `assault` flag is up. Once it is up, the contact is the town battle with the crown attacking.

**Tech Stack:** Godot 4.7 GDScript (typed), GUT, `./run_tests.sh`.

**Spec:** `docs/superpowers/specs/2026-11-18-player-siege-design.md` — §3, §5, §7, §11 row 3. Step 1's record: `docs/superpowers/plans/2026-11-19-player-siege-step1-record.md`. Engine rules: `scripts/engine/guide/siege.md`, `battle_and_ai.md`, `raid_and_defeat.md`.

## Split (spec §11 row 3 is two PRs)

- **3a (this plan, this PR):**
  - the sides on the record;
  - occupation for either side, with liberation symmetric;
  - the crown record's day;
  - the mirrored no-contact rule and the crown-attacking town battle;
  - `ArmyGround.holds` reading the holder.

  This is the done-criterion fixture: a foe-held occupied town retaken through the shared path, with the occupation and liberation reasons asserted.
- **3b (next PR):**
  - the crown's control stops at its own realm (`MapManors.controlled_provinces` and its readers, §7);
  - the capture-gains block (`TOWN_TAKEN` opinion, the sack, `GameState.town_takes`, §7).

  It is independent of 3a's internals. The crown can take nothing in ordinary play until step 12, so leaving it for the next PR leaks nothing.

## Global Constraints

- Whole numbers and strings in the save. No random number, no wall-clock. Hosts in `EnemyAi.host_codes` order, records and units in code order.
- Every manor move goes through `MapManors.set_owner` with a reason. `MapOwnership` is never touched (owner ruling 4).
- Engine-pure. Never edit the pinned `army_system.gd`, `unit_bodies.gd`, `body_motion.gd`, `march_path.gd` or `war_front.gd`.
- The enemy's siege of the crown keeps its values. Every existing siege, raid, invasion and defeat test passes unchanged, except the lines that read occupation off the host mind (`ai_hosts[h]["occupied"]`); those now read `occupations[town]["cells"]`.
- A crown record has no assault timer. Its `assault` rises only from `assault_due`, which only a future order (step 12, `SIEGE_ASSAULT`) or a test sets (spec §4.4: no assault without an order).
- PR body lines: `prd_step: Step 8`, `player_outcome: groundwork for the player's own sieges — a crown besieger can retake an occupied town through the enemy's siege rules; the enemy's siege plays as before`, `wired: false`, `GUT_INCLUDE: gameplay`.

## Decisions this plan makes

- **The occupation's home.** It goes in `GameState.occupations[town]`, not on the siege record. Spec §7 says "kept on the siege record", but a counter-siege of an occupied town needs its own record while the occupation is still live (one record a town). Spec §7 gets a one-line note.
  - The entry is `{town, occupier, from, house, host, by, day, cells}`, all whole numbers and strings:
    - `occupier` and `from` are kingdom codes;
    - `house` is the house the manors went to;
    - `host` is the capturing host ("" for the crown);
    - `by` is the taker's words for reasons;
    - `cells` maps a cell string to the house before.
- **A retake is a liberation.** The attacker of a capture can be the occupation's `from`, besieging its occupier. Each manor the occupier's house still holds then returns to its house before, with the reason `liberated: <taker> retook <town> from <occupation.by>`, and the occupation ends. No fresh occupation is made, and the crown's house takes nothing from its own lords.
- **The crown's words.** The crown is `<player realm>'s royal army` (`SiegeSystem.side_label`). Its ruling house is `MapManors.crown(state)`, and an AI kingdom's stays `_house_of`.
- **Crown events.** They are `siege_ours_begin`, `siege_ours_day`, `siege_ours_repulsed`, `siege_ours_taken`, `siege_ours_lifted` and `siege_ours_liberated`. `SiegeSystem.news` drops every `siege_ours_*`: the crown's own letters ride by `king_report` courier in step 12 (§9). An AI host's events are unchanged.
- **The defenders of a town the crown does not hold** are the holder's foes standing (not marching) at the town (`at_town`) with fit men, in code order. In step 3 that means the occupying host's columns. Step 4 adds woken units and militia. Such a town never starves (`starving` false), since its stores are step 6.
- **When the enemy's columns hold an occupied town the crown retakes**, every host in HOLD at that town goes RETREAT ("the town was taken back", `_go_home`) inside the capture. No `DefeatSystem` cost applies, because the crown lost nothing.
- **A crown occupation ends** when the town's manor is no longer `house`'s, or when no crown land unit with fit men stands at the town (`at_town`). The reason is `liberated: <by> left <town>`, and the event is `siege_ours_liberated`.
- **Old saves.** A mind's `occupied` / `occupied_house` become `occupations[target_id]`, with `host` set to that host, at the end of `SiegeRecord.migrate`. The keys are erased, and a second run changes nothing.
- **`BodyBattle._start`** (the candidate day) mirrors the deferral and the storming town exactly as `_detect` does.

## Review Focus

1. **A reserve HOLDing beside its main host goes home.** The town stays occupied, because only the occupation's `host` liberates. Test: Task 2, `test_reserve_leaving_does_not_free_the_town`.
2. **A crown besieger standing in the field beside a HOLD host's column with the flag down** gets no battle. A relief-style crown unit outside the record does get one. Test: Task 4.
3. **The flag is up but the crown unit stands in the outer ring, outside the town's reach.** The contact is still the town battle at the town, with the crown attacking (the crown's record names the town). Test: Task 4, which asserts `town` and `att`.
4. **A save mid-occupation** round-trips with the same `state_hash`, and an old mind-held occupation migrates once. Test: Task 1.
5. **The crown retakes a town while the enemy's assault battle is somehow still listed there.** The battle is called off with the crown's side as the winner. Test: Task 3 asserts that no battle remains at the town after the fall.

---

### Task 1: `GameState.occupations`, `holder_of`, and the AI occupation moved off the minds

**Files:**
- Modify: `scripts/engine/game_state.gd` (the field beside `sieges`, plus `to_dict` / `from_dict`), `scripts/engine/siege_system.gd`, `scripts/engine/siege_record.gd`, `scripts/engine/army_ground.gd` (`holds`), `scripts/engine/enemy_ai.gd` (`target_held`)
- Test: `tests/engine/test_siege_sides.gd` (new); `tests/engine/test_siege.gd` and `test_invasion_end_to_end.gd` (their occupation reads only)

**Interfaces — Produces:**
- `GameState.occupations: Dictionary`, saved through `_encode_values` / `_decode_values`. An absent one loads as `{}`.
- `SiegeSystem.holder_of(repo, state, town) -> String`
- `SiegeSystem.occupation_of_host(state, host) -> Dictionary`
- `SiegeSystem.occupier_of(state, cell) -> String`, which now returns the occupier KINGDOM, "" for none
- `SiegeRecord.migrate` also moves `occupied` / `occupied_house`

- [ ] Test `test_capture_writes_one_occupation`: after the existing hand siege falls, `s.occupations[town]` has `occupier` raider, `from` player, `host` main, and `cells` equal to `taken_cells` mapped to their houses before. `holder_of(town)` is the raider, `ArmyGround.holds(raider, town)` is true, `holds(player, town)` is false, and the mind has no `occupied` key.
- [ ] Test `test_old_mind_occupation_migrates_once`: a mind in HOLD with `occupied` {cell: house} and `occupied_house` migrates to `occupations[target_id]`. A second `migrate` leaves the same dict.
- [ ] Test `test_reserve_leaving_does_not_free_the_town`.
- [ ] Implement: `capture` writes `occupations[town]`; `_hold_day` / `_liberate` / `settle_day` read it through `occupation_of_host`; `holds` and `target_held` read `holder_of`; `_open`'s defender is `holder_of`. Change the four occupation reads in `test_siege.gd` / `test_invasion_end_to_end.gd`.
- [ ] Run `./run_tests.sh --test tests/engine/test_siege_sides.gd`, then `--test tests/engine/test_siege.gd` and `test_siege_record.gd`. Expect all to pass.

### Task 2: The sides on the record — besiegers, defenders, one `_siege_day`

**Interfaces — Produces:**
- `SiegeRecord.open_units(repo, state, town, attacker, units: Array, task_id) -> String`. It opens the town's record (or joins it when its attacker is the same) with `units` in code order and returns the id. It refuses an attacker unlike the record's with "".
- `SiegeSystem.defenders_of(repo, state, town) -> Array`
- `SiegeSystem.stationed(repo, state, id) -> Array`, the besieging unit codes stationed at the town
- `SiegeSystem.record_active(repo, state, id) -> bool`
- `at_town` / `deployed_at` work for a crown unit (through `BattleSystem._at_m` / `_stored`)
- `garrison_fit`, `defend_power` and `starving` read `defenders_of`, and `attack_power` adds the record's stationed `units`

- [ ] Test `test_crown_record_day_gain_is_the_shared_formula`:
  - Setup: the main host occupies a town, and one crown unit is stationed at it under an open crown record.
  - `settle_day` gives one `siege_ours_begin` and one `siege_ours_day`.
  - A is `ArmySystem.power(crown unit, "attack")` and D is the sum of `power(foe column, "defend")`. Gain = `siege_rate × A / (A + D)` (integer), and progress and days are 1 day's worth on the record.
  - No `siege_ours_*` is in `SiegeSystem.news`.
- [ ] Test `test_crown_record_has_no_assault_timer`: after `siege_assault_days` days, `assault_due` and `assault` are still 0.
- [ ] Implement `_siege_day(repo, state, id, lead, battle_events, events)`, with `lead` "" for a crown record. For a crown record: no `ensure_for`, no `march_host`, and on a lost town the record closes with `siege_ours_lifted`.
- [ ] Run the siege suites (`test_siege`, `test_siege_deployment`, `test_siege_record`, `test_siege_sides`). Expect all to pass with unchanged values.

### Task 3: Capture through `_occupy` — the retake fixture

**Interfaces — Produces:** `SiegeSystem._occupy(repo, state, town, attacker, defender, by, host, events) -> String` (the reason used). `side_label(repo, state, id) -> String`.

- [ ] Test `test_foe_held_town_is_retaken_through_the_shared_path`:
  - The main host takes town T, and the test asserts the `taken by <raider>'s main host: siege of T` reason.
  - A crown unit is stationed at T under a crown record, and the record's progress is set to 1000.
  - One `settle_day` then gives:
    - every cell back to its house before, with `manor_log` reason `liberated: <player>'s royal army retook T from <raider>'s main host`;
    - `occupations` without T and no record at T;
    - the main host RETREAT with a `host_mode` why "the town was taken back";
    - `target_held(T)` true;
    - one `siege_ours_taken`, no `defeat_*` event, and no battle at T.
- [ ] Test `test_crown_occupation_and_liberation_reasons`:
  - The crown takes an undefended raider town: its unit is at the gate, there are no defenders, and the town falls the first day.
  - Each taken cell's reason is `taken by <player>'s royal army: siege of <town>`, and its house is `MapManors.crown(s)`.
  - Once the unit marches away, `settle_day` gives `liberated: <player>'s royal army left <town>` and one `siege_ours_liberated`.
- [ ] Implement `_occupy` and the crown side of the fall; `_crown_hold_day` runs each crown occupation after the records.
- [ ] Run the siege suites and the raid / defeat / invasion tests. Expect all to pass.

### Task 4: The mirrored no-contact rule and the crown-attacking town battle

**Interfaces — Produces:**
- `SiegeSystem.investing(repo, state, code) -> String`: the town a crown unit besieges in an active record, "" otherwise.
- `SiegeSystem.storming(repo, state, code) -> String`: that town when the record's `assault` is 1.
- `BattleSystem.contact_skeleton_candidate(..., town, crown_storms := false)`: with `crown_storms`, the crown attacks at the town.

- [ ] Test `test_crown_besieger_does_not_fight_the_defenders_before_the_assault`: `BattleSystem.detect_contacts` starts no battle with the flag down. A crown unit not in the record, placed at the same spot, does start one (`town` "").
- [ ] Test `test_raised_flag_gives_the_town_battle_with_the_crown_attacking`: `rec.assault_due = 1`, `assault = 1`. The battle's `town` is T, `att` is [crown unit] and `def` holds the foe column.
- [ ] Implement in `BattleSystem._detect`, guarded by "any record has units" so the quiet day pays nothing. Mirror the same in `BodyBattle._start`.
- [ ] Run `test_siege_sides`, `test_siege`, `test_battle*`, `test_body_battle_enter`. Expect all to pass.

### Task 5: Guides, then the whole diff

- [ ] `scripts/engine/guide/siege.md`: the sides, `holder_of`, `occupations`, the crown record's day (no timer), the retake as liberation, the `siege_ours_*` events, the mirrored contact. `battle_and_ai.md` contact line: the mirror. `regiments.md` holds-line: "a town is held by its holder (an occupier holds what it occupies)". Spec §7 note on where the occupation lives.
- [ ] `tests/engine/test_claude_md_size.gd` passes.
- [ ] Under the mkdir lock: `./run_tests.sh --base origin/main`. Expect green.
- [ ] Commit, push, open the PR with the body lines above.
