# Development Axes (Renaissance and Chivalry) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two independent per-realm development scores (Renaissance, Chivalry) that laws drift monthly, that give tier modifiers and tier-crossing events, and that foreign realms move toward their ruler's hidden preference.

**Architecture:** One new engine class `DevelopmentSystem` (`RefCounted`, static functions over `DataRepository` + `GameState`) owns scores, tiers, drift, tier effects, preference and the AI step. The player's laws feed it through new `dev_*` channels in `law_effects.csv`; `TickEngine.advance` settles it right after the camp laws' month. Tier crossings set `event_state["flags"]` entries that the existing `flag=` trigger clause reads, so `EventSystem` is unchanged.

**Tech Stack:** Godot 4.7 GDScript (typed), GUT, CSV tables under `data/realm/` and `data/council/`.

**Spec:** `docs/superpowers/specs/2026-10-12-development-axes-design.md` (§6 revised during planning: foreign realms have no laws, so they take a monthly step toward a target from the ruler's preference).

**Where to work:** a worktree off `main` (the main checkout is shared and dirty); land through a PR. Per commit run `./run_tests.sh --fast`. A single file: `CC_FORCE_OFFLINE=1 /Applications/Godot.app/Contents/MacOS/Godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests/engine -gselect=<file stem> -gexit`.

## Global Constraints

- Typed GDScript; sim classes `RefCounted`; nothing under `scripts/engine/` names `scripts/ui/` or `scripts/llm/` or `Game`.
- Scores are whole numbers 0..1000; no floats in state; all arithmetic integer with one rounding per line; fixed iteration order (axes `renaissance` then `chivalry`; realms sorted by code).
- Every score move and every tier modifier line carries a non-empty reason string.
- No tuning number in scripts: each is a `data/realm/balance.csv` key. Tests set the keys they use in their own `SuiteData.repo()` copy.
- Authored prose never names a kingdom: `{player_realm}`, `{raider_realm}`, `{neighbor_realm}`, `{empire_realm}`.
- Event prose is hand-written, shown verbatim; no model writes an event. Keep `### EV-NN` headings and `**Scene:**` labels intact.
- Tests take data from `tests/suite_data.gd` (`SuiteData.repo()`, `SuiteData.campaign(repo, seed)`), wait with `wait_process_frames`/`wait_until`.
- New tables are listed in `data/tables.csv` and described in `data/CLAUDE.md`; the engine rules go in a new `scripts/engine/guide/development.md` (the engine `CLAUDE.md` is near its size cap) with one index line there.
- Axis ids: `renaissance`, `chivalry`. Tier ids 0..3: budding, rising, flourishing, zenith.

## Review Focus

- A save from before this feature (no `development` key) loads with the start scores, not an error. (Task 2)
- A score pinned at 0 or 1000 stays clamped and logs no zero-delta line. (Task 3)
- A score oscillating across a tier bound inside the hysteresis width never re-fires that tier's event. (Task 7)
- A foreign realm with no `crowned_head` ruler holds its score and raises no error. (Task 6)
- A realm with no cavalry gets no upkeep line (not a zero line). (Task 4)
- Save → load mid-campaign keeps scores, confirmed tiers and the crossing flags bit-exact. (Task 2)

## File Structure

| File | Responsibility |
|---|---|
| `scripts/engine/development_system.gd` (new) | scores, tiers, drift, decay, tier-effect lookup, preference, AI step, monthly settle |
| `scripts/engine/game_state.gd` | the `development` field, save/load, start seeding |
| `scripts/engine/data_repository.gd` | load the two new tables |
| `scripts/engine/tick_engine.gd` | call `DevelopmentSystem.settle_month` once per month |
| `scripts/engine/army_system.gd` | per-arm power factor from tier effects |
| `scripts/engine/law_system.gd` / `action_system.gd` | honour-bound refusals; decree opinion hook |
| `data/realm/development_axes.csv`, `development_tier_effects.csv` (new) | tiers and their effects |
| `data/realm/laws.csv`, `law_effects.csv`, `law_words.csv`, `balance.csv` | new laws, `dev_*` rows, keys |
| `data/realm/action_signatures.csv`, `order_costs.csv` | rows for the new law values |
| `data/council/character_traits.csv` | two preference columns |
| `data/story/events.csv`, `event_choices.csv`, `RANDOM_EVENTS.md` | the event pools |
| `tests/engine/test_development_*.gd` (new) | one file per task |
| `scripts/engine/guide/development.md` (new) | the rules as they stand |

---

### Task 1: Data tables, loader, trait columns

**Files:**
- Create: `data/realm/development_axes.csv`, `data/realm/development_tier_effects.csv`
- Modify: `data/tables.csv`, `scripts/engine/data_repository.gd` (next to the `law_effects` load, line ~866), `data/realm/balance.csv`, `data/council/character_traits.csv`, `data/CLAUDE.md`
- Test: `tests/engine/test_development_data.gd`

**Interfaces:**
- Produces: `DataRepository.development_axes: Array` (rows `axis,tier,min_score,hysteresis,label`), `DataRepository.development_tier_effects: Array` (rows `axis,tier,channel,target,amount,timing,reason`, `amount` a number or balance key, `-key` negated, as `LawEffects.amount_of`), trait columns `dev_renaissance`/`dev_chivalry` readable as ints on each `character_traits` row; balance keys `dev_start_renaissance`, `dev_start_chivalry`, `dev_decay_per_month`, `dev_ai_target_per_pref`, `dev_ai_step`, `dev_decree_opinion_per_100`, `dev_cavalry_upkeep_per_head`.

- [ ] **Step 1: Write the failing test** `test_development_data.gd`: `test_axes_cover_both_axes_and_four_tiers` (each axis has tiers 0..3, `min_score` strictly increasing, first is 0, hysteresis ≥ 0), `test_tier_effect_rows_are_well_formed` (channel in the allowed set `{metric names in world_schema, "arm_power_permille","cavalry_upkeep_permille","adopt_permille","flag","unlock"}`; `timing` is `monthly` for metric channels; every `amount` resolves through `LawEffects.amount_of`; reason non-empty), `test_trait_columns_present` (every trait row parses both columns as ints in −100..100), `test_balance_keys_exist`.
- [ ] **Step 2: Run it; expect FAIL** (no table, no keys).
- [ ] **Step 3: Author the tables.** Axes rows: bounds 0/250/500/750, hysteresis 20, labels Budding/Rising/Flourishing/Zenith for both axes. Tier effects (spec §4), at least these per axis, rising with tier: Renaissance — `arm_power_permille` on `artillery` (and `archers` firearms later), `treasury` monthly from the free market, `church_opinion` and `peasant_contentment` monthly negatives, `unrest` monthly positive from tier 2, `adopt_permille` negative (cheaper adoption), `unlock` rows `bombard` (tier 1) and `arquebus` (tier 2); Chivalry — `morale_mark` is a law channel so use `arm_power_permille` on `cavalry` and `infantry`, `treasury` (tax collection), `church_opinion` and `peasant_contentment` positive, `arm_power_permille` on `archers` and `artillery` NEGATIVE, `adopt_permille` positive (dearer adoption), `cavalry_upkeep_permille` positive, `flag` `honour_bound` from tier 2. Reasons are short English phrases naming the axis and tier. Add trait columns with values: pious/chivalric traits positive on `dev_chivalry`, scholarly/mercantile positive on `dev_renaissance`, most traits 0; `crowned_head` 0. Balance keys with values chosen for a month-scale game (start scores 100; decay 1; ai step 5; ai target per pref 5; decree opinion 6; cavalry upkeep 2).
- [ ] **Step 4: Implement** the two loads in `data_repository.gd` with `_load_if_present` exactly like `law_effects`; register both in `data/tables.csv`; one paragraph in `data/CLAUDE.md`.
- [ ] **Step 5: Run the test; expect PASS.** Run `./run_tests.sh --fast`; expect no new failures (the trait table's extra columns must not break `test_character_factory.gd`; if the factory iterates columns, pass them through).
- [ ] **Step 6: Commit** `feat(dev): development tables, trait preference columns and balance keys`.

---

### Task 2: `DevelopmentSystem` core: state, tiers, save

**Files:**
- Create: `scripts/engine/development_system.gd`
- Modify: `scripts/engine/game_state.gd` (field near `law_decree` line ~405; `to_dict`/`from_dict` near lines 486 and 605; the new-campaign seeding near `LawSystem.seed(data, s)` line 99)
- Test: `tests/engine/test_development_state.gd`

**Interfaces:**
- Produces:
  - `GameState.development: Dictionary` — realm code → `{renaissance:int, chivalry:int, tier_renaissance:int, tier_chivalry:int}`; saved with `_encode_values`, absent in old saves → seeded.
  - `DevelopmentSystem.AXES := ["renaissance", "chivalry"]`
  - `static func realms(repo, state) -> Array` — the four slot realm codes sorted (player first not required; sorted by code).
  - `static func seed(repo, state) -> void` — every realm gets `dev_start_<axis>`, tier 0; called from new-campaign and from `Game.load_campaign`'s migration path the same way `LawSystem.ensure` is (find the caller; add the call beside it).
  - `static func score(state, realm: String, axis: String) -> int`
  - `static func tier(state, realm, axis) -> int` (the confirmed tier)
  - `static func tier_for(repo, axis: String, score: int, confirmed: int) -> int` — hysteresis rule: rises to tier n when `score >= min_score(n)`; falls from tier t when `score < min_score(t) - hysteresis(t)`; moves at most to the tier the score implies.
  - `static func move(repo, state, realm, axis, delta: int, reason: String) -> Dictionary` — clamps 0..1000, returns `{axis, realm, delta (the applied one), reason, from_tier, to_tier}`; `{}` when the applied delta is 0. It updates the confirmed tier and, on a change, sets flags (Task 7 reads them): `dev_<axis>_up_<n>` / `dev_<axis>_down_<n>` in `state.event_state["flags"]` for the player's realm, `dev_foreign_<realm>_<axis>_up_<n>` / `_down_<n>` for others.

- [ ] **Step 1: Failing tests:** `test_seed_gives_every_realm_start_scores_and_tier_zero`; `test_tier_for_hysteresis` (bounds 0/250/500/750, width 20: confirmed 1 and score 240 → 1; 229 → 0; confirmed 0 and 249 → 0; 250 → 1; confirmed 1 and score 760 → 3 in one step); `test_move_clamps_and_returns_applied_delta` (score 995, +10 → 1000, delta 5; score 3, −10 → 0, delta −3; score 1000, +5 → `{}`); `test_move_sets_crossing_flag_once_per_crossing` (player realm 240→260 sets `dev_renaissance_up_1`; foreign realm sets the `dev_foreign_` form); `test_save_round_trip_keeps_development` (new campaign, move scores and tiers, `to_dict` → `from_dict` equal); `test_old_save_without_development_loads_seeded` (delete the key from the dict before `from_dict`, then the load path seeds it).
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement** per the signatures. `move` writes the reason into `state.development_log` (an Array of the returned dicts, capped by the balance key already used for similar logs, or unbounded if none exists — match how `opinion_log` is handled); save it too.
- [ ] **Step 4: Run the file, then `./run_tests.sh --fast`; expect PASS.** The save-format test `test_battle_save`/determinism tests must still pass.
- [ ] **Step 5: Commit** `feat(dev): DevelopmentSystem scores, tiers with hysteresis, save`.

---

### Task 3: Law drift, new laws, monthly settle

**Files:**
- Modify: `data/realm/laws.csv`, `law_effects.csv`, `law_words.csv`, `action_signatures.csv`, `order_costs.csv` (only if `LAW_SET` rows need none, verify), `scripts/engine/development_system.gd`, `scripts/engine/tick_engine.gd` (after the `LawEffects.month_lines` loop, line ~230), `scripts/engine/law_effects.gd` (skip `dev_*` channels in `apply_lines`'s metric write if they reach it; they must not), `data/CLAUDE.md`
- Test: `tests/engine/test_development_drift.gd`

**Interfaces:**
- Consumes: Task 2's `move`, `score`, `realms`.
- Produces: `static func law_drift(repo, state, axis: String) -> Array` — for the PLAYER realm, the lines `{delta:int, reason:String}` from every `law_effects` row whose `channel == "dev_" + axis`, `timing == "monthly"`, evaluated on the law's value in force (`LawSystem.decreed(repo, state, law)`); a row of a `range` law has a blank `value` and pays `amount × (value in force − the law's default)` per month, and its reason says so. None of the seven new laws is a range law, so only a later range law uses this branch; `static func settle_month(repo, state) -> Array` — player realm: per axis, the drift lines in file order via `move`, then the decay line (`score` moves toward `dev_start_<axis>` by `min(dev_decay_per_month, |score − start|)`, reason "untended: the old ways return"), then foreign realms (Task 6 adds that call); returns all applied `{metric?, axis, realm, delta, reason}` lines. `TickEngine.advance` calls it once per month, after the camp laws' month, and files the lines under one outcome `DEVELOPMENT` in `state.recent_outcomes` (same shape as `LawEffects.apply_lines`' `LAW_EFFECTS` outcome, `effects` entries `{metric: axis name, delta, reason}`).

New laws (rows in the three law tables like the existing ones; `scope` `province` for civil, `camp` for military; `cooldown_ticks` 4; `cost_ops` an opinion cost on the matching seat, as the existing laws do): `patronage` (economy; none|scholars|court), `guild_charter` (economy; none|granted), `arsenal_decree` (military; none|bombards), `tolerance` (politics; none|edict), `knightly_orders` (military, group chivalry; off|on), `tournaments` (military, group chivalry; off|on), `heavy_levy` (military, group chivalry; off|on). Drift rows: Renaissance — `patronage=scholars` +, `patronage=court` ++, `guild_charter=granted` +, `arsenal_decree=bombards` +, `tolerance=edict` + (and its `church_opinion` monthly row negative); Chivalry — `quarter=give` +, `ransom=ransom` +, `truce_days=on` +, `envoys=on` +, `knightly_orders=on` ++, `tournaments=on` +, `heavy_levy=on` +. Amounts are numbers in the CSV (law-effect amounts are rows, not hardcoded script values). `law_words.csv` gets the labels. `action_signatures.csv` gets a row per new value (ideology axes: knightly laws `militarism`/`orthodoxy` positive, renaissance laws `centralism` and `expansionism` as fits).

- [ ] **Step 1: Failing tests** (set keys in the test repo; hand values: start 100, decay 2): `test_drift_sums_law_rows_in_file_order` (score 140; `patronage=scholars` +4 and `guild_charter=granted` +2 in force → after `settle_month` 140 + 4 + 2 − 2 = 144, three lines each with a reason); `test_decay_never_overshoots_start` (score 101, decay 2, no laws → 100, line delta −1); `test_untouched_realm_at_start_logs_nothing` (score 100 → no lines); `test_pinned_at_bounds_logs_no_zero_line` (score 1000 and drift +5 → 1000, no line for the clamped zero; score 0 with decay toward a start above it moves up); `test_default_laws_drift_nothing`; `test_settle_month_runs_in_tick` (advance one month on a campaign with `knightly_orders=on` decreed → chivalry score rose and a `DEVELOPMENT` outcome sits in the report's `outcomes`); `test_dev_channel_does_not_touch_metrics` (a metrics snapshot before/after has no key named `dev_*`).
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Author** the law rows and implement `law_drift`/`settle_month`; wire the tick; guard `LawEffects` so `dev_*` channels are never written to `state.metrics`.
- [ ] **Step 4: Run the file, then `./run_tests.sh --fast`; expect PASS** (law tests such as `test_law_system.gd` count laws, so update any hard-coded law count they assert).
- [ ] **Step 5: Commit** `feat(dev): laws drift the axes monthly; seven new laws`.

---

### Task 4: Tier effects: monthly lines, arm power, cavalry upkeep

**Files:**
- Modify: `scripts/engine/development_system.gd`, `scripts/engine/army_system.gd` (`power_on` line 527, `power_of_arms` line 544), `scripts/engine/tick_engine.gd`
- Test: `tests/engine/test_development_effects.gd`

**Interfaces:**
- Consumes: Task 1's tier-effect rows, Task 2's `tier`.
- Produces:
  - `static func effect_rows(repo, state, realm, channel: String) -> Array` — the rows of both axes at the realm's CONFIRMED tier, only that tier's own rows (the table lists the full modifier for each tier, so tiers do not add up).
  - `static func month_lines(repo, state) -> Array` — the player realm's `{metric, delta:float, reason}` lines for every monthly metric-channel row (amounts via `LawEffects.amount_of`, one rounding to tenths like `LawEffects`), plus the cavalry upkeep line `{metric:"treasury", delta:-gold, reason}` where `gold = dev_cavalry_upkeep_per_head × cavalry_heads × (sum of cavalry_upkeep_permille) / 1000` rounded once to whole gold; no line when `cavalry_heads == 0` or `gold == 0`. `TickEngine.advance` applies them through `_apply` right after `settle_month`.
  - `static func arm_permille(repo, state, realm) -> Dictionary` — arm → `1000 + sum of arm_power_permille` rows (min 0). `ArmySystem.power_of_arms` gains the optional last parameter `dev_permille: Dictionary = {}` and multiplies each arm's contribution by its permille / 1000 in the same integer pipeline (one rounding at the existing point); `power_on` passes `DevelopmentSystem.arm_permille` for the regiment's realm (find or add `ArmySystem.realm_of(repo, code) -> String`: the player realm for the crown's regiments, else the raider realm).
  - `static func flag(repo, state, realm, name: String) -> bool` and `static func unlocked(repo, state, realm) -> Array` (ids from `unlock` rows at tiers ≤ confirmed tier) — consumed by Task 8's honour bound and by the future equipment system.

- [ ] **Step 1: Failing tests** (test repo tier rows set by the test): `test_month_lines_follow_confirmed_tier` (renaissance tier 2 rows `church_opinion −0.5`, `treasury +10` → exactly those two lines, with reasons; tier 0 → none); `test_cavalry_upkeep_whole_gold` (400 cavalry heads, key 2, permille 500 → 2 × 400 × 500 / 1000 = 400 gold, one line `−400`); `test_no_cavalry_no_upkeep_line`; `test_arm_permille_sums_and_floors` (+100 and −50 on `artillery` → 1050; −1200 → 0); `test_power_of_arms_scales_one_arm` (an artillery-only host: power with `{"artillery": 1100}` equals `roundi(base × 1.1)` computed by the same integer path; with `{}` equals base); `test_ranged_penalty_hits_archers_only`.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement.** The factor is applied inside `power_of_arms` to the arm's term before summing, so there is exactly one rounding; leave default `{}` so every existing caller (war room slip, enemy supposition) is unchanged.
- [ ] **Step 4: Run the file, `test_army_power.gd`, then `./run_tests.sh --fast`; expect PASS.**
- [ ] **Step 5: Commit** `feat(dev): tier modifiers reach the ledger, arm power and cavalry upkeep`.

---

### Task 5: Hidden preference and decree opinions

**Files:**
- Modify: `scripts/engine/development_system.gd`, `scripts/engine/action_system.gd` (the `LAW_SET` branch near line 696, after a successful decree)
- Test: `tests/engine/test_development_preference.gd`

**Interfaces:**
- Produces: `static func preference(repo, character: Character, axis: String) -> int` — sum of the character's traits' `dev_<axis>` columns, clamped −100..100; `static func decree_opinions(repo, state, law: String, value: String) -> Array` — for every council `Character` (not the player), if the decreed row has a `dev_<axis>` drift of sign `s` (sum of that law value's rows), `delta = roundi(preference × s × dev_decree_opinion_per_100 / 100.0)`; each non-zero one is applied with `change_opinion(delta, reason, state.tick)` and returned as `{character_id, delta, reason}`; reason reads `decreed <law label> (favours/opposes <axis> development)`. `ActionSystem` calls it after a successful `LAW_SET` and adds the results to the order's `drift` list so the screens show them.

- [ ] **Step 1: Failing tests:** `test_preference_sums_and_clamps` (traits with +60 and +70 → 100; with +60 and −90 → −30; no traits → 0); `test_decree_opinion_for_favouring_and_opposing_ministers` (preference +50, drift sign +, key 6 → +3; preference −50 → −3; preference 0 → no change and no log line); `test_decree_reason_is_nonempty`; `test_undecreed_or_neutral_law_changes_no_opinion` (e.g. `tax_rate`); `test_preference_is_not_in_save_state` (the number is derived: `Character.to_dict` has no preference key).
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement** both functions and the single call in the `LAW_SET` branch.
- [ ] **Step 4: Run the file, `test_law_orders.gd`, then `./run_tests.sh --fast`; expect PASS.**
- [ ] **Step 5: Commit** `feat(dev): rulers' hidden development preference and decree opinions`.

---

### Task 6: Foreign realms follow their ruler

**Files:**
- Modify: `scripts/engine/development_system.gd`
- Test: `tests/engine/test_development_ai.gd`

**Interfaces:**
- Consumes: `move`, `preference`, `realms`.
- Produces: `static func ruler_of(repo, state, realm: String) -> Character` — the character with trait `crowned_head` whose `kingdom` equals the realm code (lowest id if several); `null` when none or the realm is the player's; `static func ai_lines(repo, state) -> Array` — for each foreign realm (sorted), each axis: `target = clampi(dev_start_<axis> + preference × dev_ai_target_per_pref, 0, 1000)`, `step = min(dev_ai_step, |target − score|)` toward the target, applied with `move` and reason `<ruler name> favours <axis>` / `turns from <axis>`; `settle_month` (Task 3) appends these lines after the player's.

- [ ] **Step 1: Failing tests:** `test_ai_steps_toward_target` (start 100, preference +80, per-pref 5 → target 500; score 100, step 10 → 110; at 497 → 500, not 507); `test_negative_preference_steps_down` (preference −20 → target 0; score 100 → 90); `test_zero_preference_holds_at_start`; `test_realm_without_ruler_holds_and_does_not_error`; `test_ruler_lookup_uses_kingdom_and_crowned_head` (the loaded pack's three foreign rulers resolve; the player realm → null); `test_same_seed_same_scores_after_twelve_months` (two campaigns from one save advance twelve months, scores equal); `test_ai_lines_carry_reasons`.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement.** Rulers' traits come from the roster the campaign already holds in `state.characters`; set the preference columns of the foreign rulers' traits in Task 1's CSV so the three realms differ (one leans each way, one neutral) — pick values by the characters' lines in `data/council/roles.csv` (a warlord leans chivalry; the schemer queen leans renaissance).
- [ ] **Step 4: Run the file, then `./run_tests.sh --fast`; expect PASS.**
- [ ] **Step 5: Commit** `feat(dev): foreign realms drift toward their ruler's preference`.

---

### Task 7: Threshold event pools

**Files:**
- Modify: `data/story/events.csv`, `data/story/event_choices.csv`, `RANDOM_EVENTS.md`, `scripts/engine/development_system.gd` (only to confirm flag names)
- Test: `tests/engine/test_development_events.gd`

**Interfaces:**
- Consumes: Task 2's crossing flags (`dev_<axis>_up_<n>`, `dev_<axis>_down_<n>`, `dev_foreign_<realm>_<axis>_up_<n>`).
- Produces: ten events with ids continuing the existing `ev_NN` numbering: per axis three tier-up events (flags `_up_1`, `_up_2`, `_up_3`) and one decline event (`_down_1`), all with `once=1`, trigger `flag=<flag>`, `weight` high enough to win the roll when eligible, category `realm`; plus one foreign-crossing event per axis (trigger `flag=dev_foreign_{neighbor_realm}_<axis>_up_1`, neighbour realm slot written the way existing rows write realm slots). Each has two or three choices with `effects` in the existing `EventEffects` op grammar, every choice with an `OpinionDrift` signature row and a cost (copy the pattern of the nearest existing realm-category event rows).

- [ ] **Step 1: Failing tests:** `test_every_dev_event_resolves_in_random_events_md` (each new id has an authored title and scene); `test_each_event_has_a_reachable_trigger_flag` (every flag named in a trigger is one `DevelopmentSystem.move` can set); `test_crossing_makes_the_event_eligible_once` (move renaissance 240→260 on a campaign, roll with the rng forced eligible → the tier-1 event can fire; after it fires, it is in `event_state["once"]`); `test_oscillation_inside_hysteresis_does_not_refire` (260 → 240 → 260 sets the flag once; the event fires once); `test_decline_event_fires_on_fall`; `test_no_prose_names_a_kingdom` (scene text has no code from `realm_bindings.csv`).
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Write the events** in the register of the existing `### EV-NN` entries: title, trigger line, a short Scene (what the court sees: a bombard founded at the arsenal, a tournament on the green, the church bell tolling against the new learning, a ransom paid in the old manner), choices. The decline events say what the realm lost. Foreign ones: an embassy, a border incident, a marriage offer, at the neighbour's court. All prose is authored here; nothing for the model to write.
- [ ] **Step 4: Run the file, `test_story_source` (or the existing test that asserts every event id resolves), then `./run_tests.sh --fast`; expect PASS.**
- [ ] **Step 5: Commit** `feat(dev): renaissance and chivalry event pools`.

---

### Task 8: Honour bound, guide, size guards

**Files:**
- Modify: `scripts/engine/law_system.gd` (the refusal path used by `decree`, line ~472), `data/realm/law_words.csv` (refusal words), `scripts/engine/CLAUDE.md` (one index line), `docs/design/PRD.md` (a status line under BG-3 if its §6 build order lists laws)
- Create: `scripts/engine/guide/development.md`
- Test: `tests/engine/test_development_honour.gd`

**Interfaces:**
- Consumes: `DevelopmentSystem.flag(repo, state, realm, "honour_bound")`.
- Produces: `LawSystem.decree` refuses `ransom=execute` and `quarter=refuse` when the player's realm has the `honour_bound` flag (a chivalry tier-2 row), returning the same refusal shape the law system already uses for a law on cooldown, with a word from `law_words.csv` (`honour_bound_refusal`). Only options that exist today are bound; ambush and similar are bound when those tactic options are built.

- [ ] **Step 1: Failing tests:** `test_executing_prisoners_refused_at_honour_bound` (set chivalry tier 2 → `decree(repo, state, "ransom", "execute")` is refused with the word; at tier 1 it succeeds); `test_quarter_refuse_refused_at_honour_bound`; `test_other_laws_unaffected`; `test_flag_off_below_tier`.
- [ ] **Step 2: Run; expect FAIL.**
- [ ] **Step 3: Implement the refusal; write `scripts/engine/guide/development.md`** — the rules as they stand (state, tiers with hysteresis, drift and decay, the `dev_*` channels, tier-effect channels, who consumes each, preference, foreign steps, crossing flags, honour bound, the `unlock` rows left for the equipment system) with no tuning numbers (name the keys) and no history; add its one-line entry to the engine `CLAUDE.md` Topic guides list naming `DevelopmentSystem`.
- [ ] **Step 4: Run the file, `test_claude_md_size.gd`, then `./run_tests.sh --fast`; expect PASS.**
- [ ] **Step 5: Commit** `feat(dev): honour bound on killing prisoners; development guide`. Then open the PR against `main` (CI's `gut-tests` is the gate).

---

## Self-review notes

- Spec coverage: §2 state → T2; §3 data → T1; §4 axes → T1/T4; §5 drift → T3; §6 preference and AI → T5/T6; §7 events → T7; §8 invariants → Global Constraints and each task's determinism tests; §9 `unlock` rows → T1/T4; §11 tests → each task; honour-bound option from §4 → T8.
- Known limits, to show the owner: tactic options that do not exist yet (ambush, fight-only-at-parity) are not bound; "adopt" channel rows are written but nothing reads them until the equipment system; the civil law `tolerance` reuses the existing church and contentment channels.
