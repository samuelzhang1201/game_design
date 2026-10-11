# Living off the land and desertion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Crown armies in enemy land forage and plunder every day (under `plunder: allow`) or break the law when desperate; crown armies at home that are starved, demoralised or untrained lose men to desertion; a 13th military law, `desertion_penalty`, scales the loss.

**Architecture:** Three small pure engine classes (`Forage`, `Desertion`, `ArmyConduct`) and one daily call in `TickEngine._end_day`, right after `ArmySystem.hunger_day`. State lives on each regiment entry plus three `GameState` maps; every design value is a `balance.csv` key; the marshal's words are `conduct_words.csv`. The presentation is extra lines in `WarFolio`, `WarGround`, the unit and kingdom cards and the intel ink — no new scene, no new art.

**Tech Stack:** Godot 4.7, typed GDScript, GUT (`./run_tests.sh`, `--fast`), CSV under `data/`.

**Spec:** `docs/superpowers/specs/2026-10-10-foraging-and-desertion-design.md` — read it before any task; §n below means the spec's section. Its §1.1 table lists every `balance.csv` key and first-draft value (copy them verbatim into the CSV).

## Global Constraints

- Work only in `/Users/samuelzhang/game_design/.claude/worktrees/foraging-desertion` on branch `feat/foraging-desertion`. Never switch branches or stash in `/Users/samuelzhang/game_design`.
- Every commit message ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.
- Typed GDScript everywhere. Engine classes are `RefCounted` and never name `Game`, `scripts/ui/`, `scripts/llm/` (`tests/engine/test_engine_isolation.gd`).
- Determinism: integers only, no RNG, sorted iteration (regiments by code, provinces sorted) wherever order decides an outcome. State holds whole numbers and Strings only.
- Every state move that takes a reason carries one (a legitimacy line: `WorldLedger.apply(repo, state, "metrics.legitimacy", delta, reason, "conduct")`).
- Design values live in `data/balance.csv` (spec §1.1), words in `data/conduct_words.csv`; no constant a designer would tune in a script. No kingdom or pack name in code, tests or words (`repo.resolve_realm("player_realm")`, `DataRepository.default_pack_id()`).
- A test takes data from `SuiteData.repo()` / `SuiteData.campaign(repo, seed)`; override a value with `repo.balance["key"] = 12.0`. Wait with `wait_process_frames` / `wait_until`, never `wait_frames`.
- CI process (`cicd_procedure.md`): `./run_tests.sh --fast` while iterating and before every commit; CI runs the whole `./run_tests.sh` on the pull request, so the full suite is NOT run locally as routine — only to reproduce a CI failure, or for a change under `tests/ui`, `tests/map3d`, `tests/war_room` (outside `--fast`: run those test files directly). The expected error count is 2 with the gdai binaries in the worktree, else 0 (the script says which).
- The look lives in the editor: this plan adds text lines only; touch no `.tscn`/`.tres`.
- Nested `CLAUDE.md` files are capped by `tests/engine/test_claude_md_size.gd`; write current rules only, no history, no tuning numbers.
- "News" in the spec is the marshal's letter: the army's news in this codebase is a missive (`MissiveLog`), so conduct events go out as ONE `supply`-kind letter a day (`MissiveWriter.conduct_dispatch`, Task 8); no separate news-bar channel.

## Review Focus

Inputs the spec implies but a straight reading of the tasks would not test; each has its test named in the owning task.

1. A unit foraged for 12 days, then marched home before the month's end: its `forage_days` still settle at the month's last day (Task 6).
2. A unit with no fit men left, or whose `deserted` would exceed its fit men: no division by zero, `deserted` never above the fit men (Task 4).
3. Fleets (`is_naval`) and foes (`state.foes`) are never touched, a unit off every land cell reads land kind `none` (Tasks 3, 5).
4. An old save with none of the new keys loads, plays 30 days and equals a fresh run's shape (Task 2, Task 8).
5. Two units in the same province on the same day share by need in code order, the second never reads what the first took (Task 3).
6. The Havoc follower is already `desperate` or `law`: it is not restarted and files no second incident (Task 5).
7. The "Raided" hazard that foraging lays on an enemy province also drags OUR march through it (`hazard_kinds.csv`); the plan keeps that on purpose and a test pins the hazard's id and months (Task 6).

---

### Task 1: Data — balance keys, words, the 13th law

**Files:**
- Modify: `data/balance.csv` (the spec §1.1 keys, one row each with a `notes` cell citing the spec), `data/laws.csv`, `data/law_effects.csv`, `data/law_words.csv`, `scripts/engine/data_repository.gd` (load `conduct_words.csv`)
- Create: `data/conduct_words.csv` (`key,text`), `tests/engine/test_conduct_data.gd`
- Modify: any test that counts the military laws (`tests/engine/test_law_military.gd`, `test_law_system.gd`, the laws-screen test) from 12 to 13

**Interfaces:**
- Produces: `repo.conduct_words: Dictionary` (key → text, `%s` placeholders); the law `desertion_penalty` (military, group `discipline`, `choice`, values `fine|lenient|hanging`, default `fine`, scope `camp`, `gold_cost` 0, `cooldown_ticks` 2); the `desert_mult_fine|lenient|hanging` and every spec §1.1 key.

- [ ] **Step 1: Write the failing test** `test_conduct_data.gd`: `test_balance_keys_exist` (every §1.1 key, `repo.bal(key)` does not assert, spot-check `forage_start_days == 3`, `desert_mult_hanging == 400`); `test_law_is_the_thirteenth_military_law` (`LawSystem.codes_on(repo, "military").size() == 13`, `LawSystem.def(repo, "desertion_penalty")` values `["fine","lenient","hanging"]`, default `fine`); `test_effect_rows` (`lenient` has morale_mark +1 unit; `hanging` has peasant_contentment −0.3, legitimacy −0.2, morale_mark −1; `fine` has none; contentment and legitimacy rows are `share=army`, the morale row `share=unit`, timing `monthly`, each with a reason); `test_every_conduct_word_has_its_placeholders` (each key listed in Task 8's table exists and its `%s` count matches).
- [ ] **Step 2: Run** `./run_tests.sh --fast` for the file; expect FAIL (keys missing).
- [ ] **Step 3: Add** the rows; load the table in `data_repository.gd` beside `law_words`; add the law's label/value words to `law_words.csv` in the same style as its neighbours; fix the counting tests.
- [ ] **Step 4: Run** the fast suite; expect PASS.
- [ ] **Step 5: Commit** `feat(conduct): balance keys, words and the desertion_penalty law`.

---

### Task 2: State and save

**Files:**
- Modify: `scripts/engine/game_state.gd` (three maps, `to_dict`/`from_dict`), `scripts/engine/army_system.gd` (`fit_heads`)
- Create: `tests/engine/test_conduct_state.gd`

**Interfaces:**
- Produces: `GameState.forage_stripped: Dictionary` (province → ‰, non-zero only), `GameState.grievance: Dictionary` (kingdom → points), `GameState.conduct_marks: Dictionary` (key → month index); regiment-entry keys read with defaults, never required: `forage` ("" | "law" | "desperate"), `forage_days` (int), `deserted` (int), `desert_rem` (int). `ArmySystem.fit_heads(heads, st)` = heads − wounded − dead − `deserted`, floored at 0.

- [ ] **Step 1: Write the failing test:** `test_fit_heads_takes_the_deserted` (`fit_heads(1000, {wounded:100, dead:50, deserted:30}) == 820`; a state with no `deserted` key reads 850; never below 0); `test_new_maps_round_trip` (set one entry in each map and one regiment's four keys, `GameState.from_dict(to_dict())` equal); `test_old_save_loads_empty` (a dict without the three keys loads with `{}` and the regiments untouched).
- [ ] **Step 2: Run;** expect FAIL.
- [ ] **Step 3: Implement** beside `law_cooldown` in `game_state.gd` (the `_encode_values`/`_decode_values` pattern) and in `fit_heads`. Check `scripts/engine/army_split.gd` for any copy of `wounded`/`dead` into a child entry and apportion `deserted` the same way (grep showed none; if still none, say so in the commit body).
- [ ] **Step 4: Run** the fast suite; PASS.
- [ ] **Step 5: Commit** `feat(conduct): state and save for foraging and desertion`.

---

### Task 3: `Forage` — capacity, land kind, shares

**Files:**
- Create: `scripts/engine/forage.gd`, `tests/engine/conduct_helpers.gd` (static test helpers), `tests/engine/test_forage.gd`

**Interfaces (all `static`, in `Forage`):**
- `food_units(repo, province: String) -> int` — sum of `units` over the economy `production` rows whose burg has `province_code == province` and whose good's `goods.csv` `tags` contain `food`; cached per repo instance (`forget()` clears).
- `monthly_capacity(repo, state, province) -> int` = `food_units × forage_supply_per_food_unit × <season permille of Calendar.season_of_day(state.absolute_day())> / 1000`, one integer division.
- `day_capacity(repo, state, province, day: int) -> int` — `C = monthly × (1000 − stripped) / 1000`; `(C×d/30 − C×(d−1)/30) × forage_share_permille / 1000`, `d` clamped 1..30.
- `land_kind(repo, state, province) -> String` — `"home"` when `MapOwnership.owner_of(...)` is the player's realm, else by `Intel.stance_of` of the owner: Enemy → `"enemy"`; Neutral, Suspicion, Unknown → `"grey"`; Suzerain, Vassal → `"none"`; province `""` → `"none"`.
- `cut_permille(repo, state, code) -> int` — `1000 −` `forage_protect_cut_permille` for each of `protect_church`, `protect_women` that `LawSystem.value(repo, state, law, code) == "on"`.
- `shares(repo, state, province, codes: Array, day: int) -> Dictionary` — `{code: units}`: each of `codes` (sorted) gets `min(need, day_capacity × need / Σneed)` then `× cut_permille / 1000`, remainder to none; `need = ArmySystem.max_units(...)` bound by its `carry_days` (`ArmySystem.carry_of` days × daily use) `−` its `supplies`, ≥ 0.
- `strip(repo, state, province, taken: int) -> void` — adds `taken × forage_strip_k / monthly_capacity` (floor; 0 capacity adds 0) to `forage_stripped`, clamped 0..1000.

`conduct_helpers.gd` offers `set_food(repo, province, units)` (removes the province's food rows, adds one row of `units` of a food good) and `land_unit(repo, state)` (first non-naval regiment code) used by Tasks 3–8.

- [ ] **Step 1: Write the failing tests** (set `forage_supply_per_food_unit` 30, summer 1000, `forage_share_permille` 1000, `forage_strip_k` 500; a province with `set_food(.., 9)` in summer): `test_food_units_counts_only_food_tagged` (adding a food row of 7 and a non-food row of 5 raises it by exactly 7); `test_monthly_capacity_by_season` (summer 270, spring 600‰ → 162, winter 300‰ → 81); `test_daily_capacities_sum_to_the_month` (30 days, 9 each at full, sum 270; at 500‰ stripped sum 135 with day 1 = 4, day 2 = 5); `test_land_kind` (the crown's own province `home`; a pack province whose stance row is Enemy `enemy`; a Neutral one `grey`; Suzerain/Vassal `none`; `""` none — pick provinces by reading `diplomacy` through `Intel.stance_of`, never by name); `test_shares_proportional_to_need` (day capacity 9, needs 60 and 30 → 6 and 3; needs 60 and 2 → 8 and 0; one unit with need 4 gets 4); `test_protect_laws_cut_the_yield` (need 60 alone, capacity 9, both laws on, `forage_protect_cut_permille` 100 → 9 × 800 / 1000 = 7); `test_strip_arithmetic` (taking 9 of monthly 270 with k 500 → 16‰; clamped at 1000; zero capacity adds nothing).
- [ ] **Step 2: Run;** expect FAIL (no `Forage`).
- [ ] **Step 3: Implement** `forage.gd` with the signatures above and the helpers.
- [ ] **Step 4: Run** `./run_tests.sh --fast`; PASS. (Review Focus 5: the shares test also calls `shares` for two codes and asserts the second's number does not change when the first's `supplies` changes after the call.)
- [ ] **Step 5: Commit** `feat(conduct): Forage — capacity, land kind, shares`.

---

### Task 4: `Desertion`

**Files:**
- Create: `scripts/engine/desertion.gd`, `tests/engine/test_desertion.gd`

**Interfaces (`Desertion`, static):**
- `conditions(repo, state, code) -> int` — how many of `morale < desert_morale`, `training < desert_training`, `ArmySystem.days_in_hand(supplies, use) <= desert_supply_days` hold (0 for a unit with no use).
- `multiplier_permille(repo, state, code) -> int` — `desert_mult_<LawSystem.value(repo, state, "desertion_penalty", code)>`.
- `daily_loss(repo, state, code) -> int` — mutates `desert_rem`/`deserted` of `state.regiments[code]` and returns the men lost: `units = fit × (desert_permille_per_day × 100 × n × mult / 1000) + desert_rem`; `lost = units / 100000`, `desert_rem = units % 100000`; `lost` never above `fit`; `deserted += lost`. 0 and untouched for a unit with `n == 0`, no fit men, or a fleet.

- [ ] **Step 1: Write the failing tests** (a land unit hand-set to 1000 fit heads via `repo`'s roster, supplies set so days in hand are as stated): `test_conditions_counts_each_line` (0, 1, 2, 3); `test_loss_by_conditions_and_law` (n=1 fine → 3 men; n=2 lenient → 12 men; n=3 hanging → 3 men and `desert_rem == 60000`); `test_small_unit_remainder` (100 fit, n=1 fine: days 1–3 lose 0 with `desert_rem` 30000/60000/90000, day 4 loses 1 with 20000 left); `test_no_fit_men` (fit 0 → 0, no error; `deserted` can never exceed the fit men, Review Focus 2); `test_fleet_untouched`.
- [ ] **Step 2: Run;** expect FAIL.
- [ ] **Step 3: Implement.** Fit men = `ArmySystem.fit_heads(headcount, entry)`.
- [ ] **Step 4: Run** `--fast`; PASS.
- [ ] **Step 5: Commit** `feat(conduct): Desertion — the daily loss`.

---

### Task 5: `ArmyConduct` — switching, incidents, Havoc

**Files:**
- Create: `scripts/engine/army_conduct.gd`, `tests/engine/test_army_conduct_switch.gd`

**Interfaces (`ArmyConduct`, static):**
- `lines(repo, state, code) -> Dictionary` — `{days, morale, training}` start lines, the `_obey` set when `LawSystem.value(.., "obey_command", code) == "on"`.
- `wants(repo, state, code, kind: String) -> String` — the unit's new `forage` value from its current one (spec §3.3 steps 3–4): enemy + `plunder` `allow` → `"law"`; else off → `"desperate"` when any start line is crossed (grey: only supply days 0), `"desperate"` → `""` when days ≥ `forage_stop_days` AND morale ≥ `forage_stop_morale`; `"law"` with `plunder` now `forbid` is treated as off and re-judged; `home` and `none` → `""`.
- `lay_hazard(repo, state, province: String) -> void` — idempotent: hazard id `forage_<province>`, kind `Raided`, cells `MapManors.manors_of_province(repo, province, state)`, label `"plundered by the crown's host"`, start `state.tick`, end `state.tick + Hazards.kind_of(repo, "Raided").months`, source `"forage"`; nothing when it already stands.
- `mark_once(repo, state, key: String) -> bool` — true the first time `key` is seen this month (`GameState.conduct_marks[key] = state.tick`), false after.
- `switch(repo, state, code, province, kind) -> Array` — applies `wants`, and on an unlawful start (`""` → `"desperate"`) returns/does: the `forage_unlawful` (enemy) or `forage_incident` (grey) event `{type, regiment, province, kingdom}`, legitimacy −`forage_incident_legitimacy` once per unit per month (`mark_once("incident:"+code)`; reason `"<unit> plundered <province> against the law"`), and for grey land the "Raided" hazard (`lay_hazard`) and the grievance (`mark_once("grievance:"+kingdom)` → `grievance[kingdom] += forage_grievance_month`, `_protected` with `protect_women` on); Havoc: with `no_havoc` not `on`, every OTHER crown land unit in the same province with `forage == ""` becomes `desperate` with a `forage_havoc` event for the province (one per province per day) and no legitimacy line.

- [ ] **Step 1: Write the failing tests** (a unit hand-placed in a province of the right land kind by `conduct_helpers`; defaults of the keys): `test_allow_is_on_in_enemy_land` (`plunder` allow → `"law"` every day); `test_each_line_starts_a_forbid_unit` (supply days 2, then morale 24, then training 4 → `desperate`; all fine → `""`); `test_stop_needs_both` (desperate at days 10 morale 39 stays; days 10 morale 40 stops); `test_obey_command_lowers_the_lines` (a line starts a unit when the value is BELOW it: without `obey_command` days 2 starts, with it days 2 does not and days 1 does; morale 24 starts, with it 20 does not and 19 does; training 4 starts, with it 3 does not and 2 does); `test_grey_land_only_at_zero_supply` (days 1 no; 0 yes, with the incident, legitimacy −3 and one `grievance` of 10, or 5 with `protect_women` on); `test_none_and_home_never` (Suzerain/Vassal province and home: `""`); `test_incident_once_per_unit_per_month` (stop, restart the next day: no second −3, no second event; advance `state.tick` and it charges again); `test_havoc_spreads_unless_forbidden` (two units in one province: `no_havoc` off → both desperate, legitimacy −3 once; `no_havoc` on → only the first); `test_follower_not_restarted` (Review Focus 6: a follower already `"law"` stays `"law"`, no event).
- [ ] **Step 2: Run;** expect FAIL.
- [ ] **Step 3: Implement** the four functions. Legitimacy through `WorldLedger.apply` with a reason (invariant 4); unit labels from `ArmySystem.regiment(...)["label"]`.
- [ ] **Step 4: Run** `--fast`; PASS.
- [ ] **Step 5: Commit** `feat(conduct): ArmyConduct switching, incidents and Havoc`.

---

### Task 6: `ArmyConduct` — taking, stripping, the hazard, the month's settlement

**Files:**
- Modify: `scripts/engine/army_conduct.gd`
- Create: `tests/engine/test_army_conduct_take.gd`

**Interfaces:**
- `take_day(repo, state, province, codes: Array) -> Array` — for the units foraging in `province`: `Forage.shares(..., state.day)`, add to each `supplies` (never past `max_units`), `forage_days += 1`; then `Forage.strip`; when stripping first passes `forage_hazard_strip_permille` (or `_protected` with `protect_church` on for any taker) call `lay_hazard` (Task 5); crossing `forage_bare_permille` returns one `stripped_bare` event `{type, province}` per crossing (`mark_once("bare:"+province+":"+tick)` is NOT used — the crossing itself is detected as before ≤ bare < after).
- `settle_month(repo, state) -> void` — only when `state.day == Calendar.DAYS_PER_TICK`: for each regiment (code order) with `forage_days = d > 0`: `morale += forage_morale_month × d / 30` (cap 100), `training −= forage_training_month × d / 30` (floor 0), `wounded += fit × forage_harass_permille × d / 30000`; `forage_days = 0`. Then every province in `forage_stripped` (sorted) recovers `forage_recover_permille`, clamped 0..1000, zeros erased; `conduct_marks` entries of an older month dropped.

- [ ] **Step 1: Write the failing tests** (a province with `set_food(.., 9)`, summer, share 1000, k 500, one unit with need 60): `test_take_adds_supplies_and_strips` (day capacity 9 → supplies +9, `forage_days` 1, `forage_stripped == 16`); `test_take_never_past_the_carry_cap`; `test_stripped_land_yields_less` (second day at 16‰: monthly 270 × 984 / 1000 = 265, day share 8 or 9 per the exact formula — assert the formula's number); `test_hazard_past_half_stripped` (stripped 500 → hazard `forage_<province>` exists, kind `Raided`, `end == tick + months`; with `protect_church` on it waits for 750); `test_bare_news_once_per_crossing` (before 899 after 905 → one event; again at 950 → none); `test_month_settlement_partial_month` (d = 12, morale 50 → +1 (4×12/30=1), training 10 → 8 (3×12/30=1; assert exactly the integer formula), wounded on 1000 fit = 1000×10×12/30000 = 4); `test_settle_runs_after_marching_home` (Review Focus 1: a unit with `forage_days` 12 that is now in home land still settles on day 30); `test_recovery_erases_zeros` (stripped 100 recovers to 0 and the key is gone; 950 → 1000 clamp not needed, 1000 − 100 = 900); `test_hazard_drags_the_march_too` (Review Focus 7: `Hazards.pace_permille` at a point inside the province is 800 while the hazard stands).
- [ ] **Step 2: Run;** expect FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run** `--fast`; PASS.
- [ ] **Step 5: Commit** `feat(conduct): foraging yield, stripping, hazard and month settlement`.

---

### Task 7: `ArmyConduct.day_step` — the whole day, with desertion

**Files:**
- Modify: `scripts/engine/army_conduct.gd`
- Create: `tests/engine/test_army_conduct_day.gd`

**Interfaces:**
- `day_step(repo, state) -> Array` — spec §3.3 in order, land units of `state.regiments` in code order (skip `is_naval`, `state.foes`, entries with no use): find `province = ArmySystem.province_of(...)` and `kind = Forage.land_kind(...)`; `home` → `forage = ""` and `Desertion.daily_loss` (event `deserting` `{type, regiment, lost}` via `mark_once("desert_news:"+code)`; event `deserting_big` once via `mark_once("desert_big:"+code)` when `deserted × 1000 > desert_news_cumulative_permille × ArmySystem.headcount`); else `switch`; then `take_day` per province (provinces in sorted order, units in code order); finally `settle_month`. Returns the events (each `{type, regiment, ...}`), never mutates anything but `state`.

- [ ] **Step 1: Write the failing tests:** `test_day_order_and_events` (one unit at home starving with `desertion_penalty` fine, one in enemy land with forbid and 0 days: one `deserting` and one `forage_unlawful`, events in code order, supplies of the second rose); `test_desertion_news_once_a_month_and_big_once` (loss over days: one `deserting` event across 10 days, `deserting_big` exactly once when cumulative passes 5%); `test_fleet_and_foe_untouched` (Review Focus 3); `test_month_end_settles_on_day_30` (day 30 call changes morale/training for foragers; day 29 does not); `test_twenty_four_months_twice_identical` (a campaign run 24 months from one seed twice through `TickEngine`, comparing `to_dict()` of `regiments`, `forage_stripped`, `grievance`, `conduct_marks` — this one needs Task 8's wiring, so write it here, mark it `pending("needs Task 8")` until then, un-pend it in Task 8).
- [ ] **Step 2: Run;** expect FAIL.
- [ ] **Step 3: Implement** `day_step`.
- [ ] **Step 4: Run** `--fast`; PASS (the 24-month test pending).
- [ ] **Step 5: Commit** `feat(conduct): ArmyConduct.day_step`.

---

### Task 8: Wire it into the day; the marshal's letter

**Files:**
- Modify: `scripts/engine/tick_engine.gd` (`day_conduct`; call after `ArmySystem.hunger_day`, before `SupplyLines.warn_day`; reset in the tick-0 branch), `scripts/engine/missive_writer.gd` (`conduct_dispatch`), `scripts/engine/missive_log.gd` only if a kind list needs it
- Modify: `data/conduct_words.csv`; `tests/engine/test_army_conduct_day.gd` (un-pend the 24-month test); create `tests/engine/test_conduct_missives.gd`

**Interfaces:**
- `TickEngine.day_conduct: Array` — the last day's conduct events.
- `MissiveWriter.conduct_dispatch(repo, state, events: Array) -> Dictionary` — a `supply`-kind letter ("Marshal's report") with one fact per event, text from `repo.conduct_words`; first event's regiment is the subject. Keys: `forage_unlawful` (`%s` unit, `%s` province), `forage_incident` (unit, province, kingdom label), `forage_havoc` (province), `stripped_bare` (province), `deserting` (unit), `deserting_big` (unit). Texts from spec §4 ("is out of bread and has taken to plunder…", "…against the law", "they will remember it", "Havoc…", "stripped bare", "men slip away…", "a twentieth…"); no kingdom named in a word, the label is filled at runtime.

- [ ] **Step 1: Write the failing test** `test_conduct_missives.gd`: `test_letter_for_each_event_type` (build one event of each type, `conduct_dispatch` gives a letter of kind `supply` with the filled text, no `%s` left); `test_engine_files_one_letter_a_day` (a unit forced desperate at day end → exactly one new missive that day, none on a quiet day); `test_old_save_plays_a_month` (Review Focus 4: strip the new keys from a saved dict, load, run 30 days).
- [ ] **Step 2: Run;** expect FAIL.
- [ ] **Step 3: Implement** the call, the writer, the words; un-pend the determinism test.
- [ ] **Step 4: Run** `./run_tests.sh --fast`; PASS with the expected error count.
- [ ] **Step 5: Commit** `feat(conduct): daily call and the marshal's letter`.

---

### Task 9: Presentation — folio, hover slip, kingdom card, intel ink

**Files:**
- Modify: `scripts/engine/war_folio.gd` (`_supply`: the state word; a "Deserted" row; its "under arms" counts at ~lines 64 and 164 and `map_objects.gd` ~943 are heads − dead and must also subtract `deserted`), `scripts/engine/war_ground.gd` (the forage line), `scripts/engine/map_objects.gd` (the unit card's supply line, the kingdom card's grievance line), the intel-ink drawing that names a province (find it with `grep -rn "intel" scripts/war_room`; add "Stripped" for `Forage.stripped_bare(...)`); `data/conduct_words.csv`
- Modify: `scripts/engine/forage.gd` — `word_of(repo, state, province) -> String` ("rich" ≥ 750 of a full day, "fair" ≥ 400, "thin" > 0, "stripped" 0 — thresholds as `balance.csv` keys `forage_word_rich_permille`, `_fair_permille`, share of the full unstripped summer day) and `stripped_bare(repo, state) -> Array` (sorted provinces above `forage_bare_permille`)
- Create: `tests/engine/test_conduct_lines.gd`

**Interfaces:**
- Folio supply section: row `("Foraging", "living off the land (law)" | "(desperate)")` when `forage != ""`; row `("Deserted", "N")` when `deserted > 0`. Hover slip in enemy or grey land: `"Forage: <word> (N a day)"`, with a unit chosen `"would feed it N of M a day"`; at home `"Our own land — not foraged"`. Kingdom card: `"Grievance: N"` only when `GameState.grievance[kingdom] > 0`. The unit card's headcount already uses `fit_heads`.

- [ ] **Step 1: Write the failing tests** (real engine functions, no scene): `test_folio_rows` (the two rows appear only when set); `test_slip_lines` (enemy, grey, home each give the line above; `word_of` at the four thresholds); `test_kingdom_card_grievance`; `test_stripped_bare_list`; `test_words_all_used` (every `conduct_words.csv` key appears in `scripts/` — a source scan like `test_law_guard.gd`).
- [ ] **Step 2: Run;** expect FAIL.
- [ ] **Step 3: Implement** the lines; follow each file's existing row/section idiom.
- [ ] **Step 4: Run** `--fast`; PASS.
- [ ] **Step 5: Commit** `feat(conduct): folio, slip, kingdom card and intel-ink lines`.

---

### Task 10: Documentation

**Files:**
- Create: `scripts/engine/guide/foraging_and_desertion.md`
- Modify: `scripts/engine/CLAUDE.md` (Topic guides line naming `Forage`, `Desertion`, `ArmyConduct`; the Laws bullet "twelve military laws" → thirteen), `scripts/ui/CLAUDE.md` and `scripts/war_room/CLAUDE.md` (one line each for the new rows), `data/CLAUDE.md` (`conduct_words.csv`, the new law), `docs/design/DATA_ARCHITECTURE.md` if it lists the state maps

- [ ] **Step 1:** Write the guide as the rule stands now (day order, states, who reads which law, what is saved), no tuning numbers, no owner quotes.
- [ ] **Step 2:** `./run_tests.sh --fast` — `test_claude_md_size.gd` passes.
- [ ] **Step 3: Commit** `docs(conduct): foraging and desertion guide`.

---

### Task 11: Whole-branch check, review and visual review

- [ ] **Step 1:** `./run_tests.sh --fast` passes, and the `tests/ui` files this branch touched are run directly (the whole suite is CI's job on the pull request; run it locally only to reproduce a CI failure).
- [ ] **Step 2:** One fresh reviewer on the whole branch against the spec; fix the findings in one commit.
- [ ] **Step 3:** Shoot the added lines with `tools/snapshot_screen.gd --resolution WxH` (real window, never `--headless` for 3D): a unit card and folio with the state word and the deserted row, the war-room hover slip in enemy land, the kingdom card with a grievance, the intel ink "Stripped"; run the `visual-review` skill over them. Fix text that crowds a name.
- [ ] **Step 4:** Update the memory note `army-supply-and-war-subprojects.md` (B phase I done; phase II prisoners open). **Landing happens only on the owner's word, and through a pull request**: push `feat/foraging-desertion` and open a PR against `main`; the `gut-tests` check (full suite) must be green before merge; no direct push to `main`.
