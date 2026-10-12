# The development axes (`DevelopmentSystem`)

Spec: `docs/superpowers/specs/2026-10-12-development-axes-design.md`. Every realm that fills a slot (`DevelopmentSystem.SLOTS`) has a Renaissance and a Chivalry score. All numbers named below live in `data/realm/balance.csv` (keys `dev_*`), `development_axes.csv`, `development_tier_effects.csv` and `law_effects.csv`.

## State

- `GameState.development[realm]` holds, per axis, a whole score (0..`SCORE_MAX`) and the CONFIRMED tier (`tier_<axis>`). `DevelopmentSystem.seed` fills missing entries (start from `dev_start_<axis>`, tier 0); `ensure` does it for an old save.
- `GameState.development_log` records every move with its reason. A score changes only through `DevelopmentSystem.move(repo, state, realm, axis, delta, reason)`, clamped to the range; a move of 0 returns `{}` and logs nothing.
- Realms are keyed by kingdom code. Authored text and flags name the SLOT, never a code.

## Tiers

`tier_for(repo, axis, score, confirmed)` cuts the score by `development_axes.csv` with hysteresis: a score rises to tier n at `min_score(n)` and falls from tier t only when it is below `min_score(t)` minus that tier's `hysteresis`. A confirmed tier changes only inside `move`; every tier effect reads the confirmed tier.

## The month

`TickEngine.advance` runs, once a month: law drift, then decay, then the foreign realms' steps (all in `settle_month`), then `month_lines` (the tier rows' monthly metric lines and cavalry upkeep, so a tier reached this month pays this month).

- **Law drift** (`law_drift`): a `law_effects.csv` row on channel `dev_<axis>` (monthly) moves the player's score by its amount while that value is in force. Only a law the crown has DECREED counts (`decree_id` above 0); an undecreed default drifts nothing. Renaissance is fed by the laws `patronage`, `guild_charter`, `arsenal_decree` and `tolerance`; Chivalry by `quarter`, `ransom`, `truce_days`, `envoys`, `knightly_orders`, `tournaments` and `heavy_levy`.
- **Decay** (`decay_line`): after the drift, each score moves toward `dev_start_<axis>` (not toward 0) by at most `dev_decay_per_month`, never past the start.
- **Foreign steps** (`ai_lines`): per realm in sorted code order, then axis order, a realm with a ruler (`ruler_of`) steps toward clamp(`dev_start_<axis>` + preference x `dev_ai_target_per_pref`) by at most `dev_ai_step`. `ruler_of` is the lowest-id `crowned_head` whose `kingdom` is the realm's code OR a slot that resolves to it (the roster stores slots). A realm with no ruler does not move. The player's realm has no ruler and never steps.
- `settle_month` returns the player's and the foreign lines alike; only the player's are filed as the one `DEVELOPMENT` outcome in `recent_outcomes`.

## Tier effects (`development_tier_effects.csv`)

The numeric channels list each tier's FULL modifier (rows of other tiers do not add); `flag` and `unlock` rows instead persist upward from the tier they appear at. A row is `permanent` or `monthly`. Channels and who consumes each:

- `arm_power_permille` (target = arm) -> `DevelopmentSystem.arm_permille` -> `ArmySystem.power_of_arms`; a state-less host gets 1000 for every arm.
- `cavalry_upkeep_permille` -> `month_lines`: a treasury line, whole gold, one rounding, scaled by `dev_cavalry_upkeep_per_head` and the player's cavalry heads.
- Monthly metric channels (`treasury`, `church_opinion`, `peasant_contentment`, `unrest` ...) -> `month_lines` -> the ledger with the row's reason.
- `adopt_permille` and `unlock` -> nothing reads them yet; they are left for the equipment system (`unlocked` lists the unlock targets reached).
- `flag` (`honour_bound`) -> `DevelopmentSystem.flag` -> `LawSystem.refusal_of`: at a tier carrying the flag, a decree of `ransom` = `execute` or `quarter` = `refuse` is refused (key `honour_bound`, words `refusal_honour_bound` in `law_words.csv`). No other option is bound.

## Preference (hidden)

A ruler's lean is the sum of his traits' `dev_<axis>` columns in `traits.csv`, clamped to -100..100, DERIVED on every read (`preference`), never stored and never shown. It sets a foreign target and a minister's reaction.

## Decree opinions

`ActionSystem` calls `DevelopmentSystem.decree_opinions` after a `LAW_SET` executes (not on a re-send), a hook apart from the order's own opinion signature. For each axis the decree shifts (`decree_sign`: the sum of that value's monthly `dev_<axis>` drift), every seated minister takes roundi(preference x sign x `dev_decree_opinion_per_100` / 100), with a reason naming the law and axis. A delta of 0 is skipped.

## Crossing flags

`move` sets one flag per tier crossed, into `event_state.flags`:

- player: `dev_<axis>_up_<n>` (n = the tier reached) and `dev_<axis>_down_<n>` (n = the tier left);
- foreign: `dev_foreign_<slot>_<axis>_up_<n>` / `..._down_<n>`, one set per slot the realm fills (the code when it fills none).

A jump over several tiers sets a flag for each tier crossed.

## Events

`ev_21`..`ev_30` (`data/story/events.csv`, scenes in `RANDOM_EVENTS.md`) trigger on those flags: ev_21..ev_24 Renaissance up 1..3 and down 1, ev_25..ev_28 Chivalry the same, ev_29 and ev_30 the neighbour crossing into tier 1 of each axis. All are authored `template` prose; nothing is model-written.
