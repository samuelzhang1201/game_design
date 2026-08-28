# Slice 2 — Opinion Drift + Promises + Random Events: Design

Status: draft for approval. Parent: `PRD.md` v1.1 (§6 Step 2 + Random events pool), `COUNCIL_SYSTEM.md` (drift formula, promises), `RANDOM_EVENTS.md` (triggering rules + 20 events).
Base: `main` @ 979e479 (slice 1 complete: engine, council screen, LLM layer, determinism harness).

## 1. Goal

Ministers visibly react to how you rule (deterministic ideology-distance opinion drift with
hover-readable reasons), promises are kept or broken with the game's largest opinion swings,
and roughly every third tick something unexpected happens — an event from the 20-event pool,
with clickable choices whose consequences run through the same opinion math. Campaigns stop
being spreadsheets and start accumulating history.

**Out of scope:** debates (slice 3), recruitment + relationship graph (slice 4), factions
(slice 5). Event choices whose designed effects need relations (`debt`, `friend` links) ship
with opinion-based stand-ins, marked `# slice-4 upgrade` in the data.

## 2. Ideology signatures + opinion drift (PRD CS-2.1/2.2)

### 2.1 Data: `data/action_signatures.csv`

Every drift-relevant action variant carries a signature over the 5 axes (−100…+100).

```csv
action_code,variant,centralism,militarism,orthodoxy,tax_incidence,expansionism,notes
TAX_RATE_ADJUST,delta_pos,10,0,0,-30,0,raising tax burdens the commons
TAX_RATE_ADJUST,delta_neg,-5,0,0,30,0,
TARIFF_ADJUST,delta_pos,0,0,0,15,-15,tariffs squeeze trade
TARIFF_ADJUST,delta_neg,0,0,0,-10,15,
LEVY_RAISE,,0,40,0,-10,10,
GRAIN_POLICY_SET,mode=ration,10,0,0,-15,0,
GRAIN_POLICY_SET,mode=release,0,0,0,20,0,
GRAIN_POLICY_SET,mode=market,0,0,0,0,0,
CHURCH_POLICY,mode=endow,0,0,50,0,0,
CHURCH_POLICY,mode=tithe,10,0,-50,0,0,
JUSTICE_SEVERITY,delta_pos,30,0,10,-10,0,
JUSTICE_SEVERITY,delta_neg,-20,0,-5,10,0,
BUILD_ECONOMIC,,0,-20,0,0,-10,butter over guns
SPY_MISSION,,20,5,0,0,0,
CHARACTER_PUNISH,,20,0,0,0,0,asserting royal authority
COUNCIL_CONSULT,,0,0,0,0,0,
CHARACTER_REWARD,,0,0,0,0,0,interpersonal; direct deltas already exist
CHARACTER_CONFIDE,,0,0,0,0,0,
```

`variant` matching (engine): empty = always; `delta_pos`/`delta_neg` = sign of `params.delta`;
`mode=<v>` = param equality. First matching row wins; no match = zero signature (no drift).

### 2.2 The drift function (engine, `OpinionDrift`)

On every `ActionSystem.execute` (and every event-choice application):

```
alignment      = dot(signature, char.ideology_axes) / (L1_norm(signature) × 100)   # ∈ [−1, 1]
opinion_delta  = round(alignment × sensitivity/100 × (1 − pragmatism/100) × bal(opinion_drift_scale))
```

- `opinion_drift_scale` = 20 (new balance key). Worked example: pious Odo (orthodoxy +70,
  sensitivity 80, pragmatism 30) on `CHURCH_POLICY mode=tithe` (orthodoxy −50):
  alignment = −0.70 → delta = −0.70 × 0.8 × 0.7 × 20 ≈ **−8**.
- Applied to **all seated council members**, skipping zero deltas.
- Reason string (CS-2.2): `"<label> (<opposes|approves>, <dominant axis>)"` where dominant
  axis maximizes `|sig_axis × ideo_axis|`. E.g. `−8: tithed the church (opposes, orthodoxy)`.
- Fully deterministic; no RNG.

### 2.3 UI

Minister portraits gain an opinion number; hovering it shows the last 5 `opinion_log`
entries (reason strings). No new screens.

## 3. Promises resolved (PRD CS-2.3 remainder)

Slice 1 logs promises; slice 2 makes them matter.

- **Constraint added to the parse prompt:** `promise_code` MUST be a legal `action_code`;
  `tick_due` defaults to made_tick + bal(promise_default_ticks)=24 when the model omits it.
  The validator rejects unknown promise codes (fail-closed, consistent with actions).
- **Kept:** that action executes with `target == character_id` (or untargeted actions: just
  executes) before `tick_due` → `+bal(promise_kept_opinion)=15`, reason
  `"a promise kept: <label>"`, status `kept`.
- **Broken:** `tick_due` passes unfulfilled → `bal(promise_broken_opinion)=−25` (the game's
  largest single penalty), reason `"a promise broken: <label>"`, status `broken`, and a
  permanent `grudge` flag on the character (surfaced in later slices as faction affinity).
- Checked in `TickEngine.advance` (deterministic); TemplateVoicer lines for both outcomes.

## 4. Random events engine (PRD EV-1…EV-4, RANDOM_EVENTS.md)

### 4.1 Data

**`data/events.csv`** — one row per event:
`event_id, category, trigger, weight, cooldown_ticks, once, voice, title_key`
- `trigger` DSL: `always` | clauses joined by `&`: `metric<NN`, `metric>NN`, `season=autumn`,
  `year>=N`, `trait_at_court=venal`, `seat_filled=marshal`, `action_since=TARIFF_ADJUST:24`
  (executed within last N ticks). Engine evaluator, unit-tested per clause.
- `voice`: `template` | `mini` | `flagship` — mini/flagship route through `Voicer` (template
  fallback offline, as briefings already do); template renders directly.

**`data/event_choices.csv`** — one row per choice:
`event_id, choice_id, label, centralism, militarism, orthodoxy, tax_incidence, expansionism, effects, requires`
- The 5 axis columns are the choice's ideology signature → minister reactions come free via
  `OpinionDrift` (PRD EV-2).
- `effects` — semicolon-joined ops from a small vocabulary (engine `EventEffects` executor):
  `metric:<name>:<±N>`, `opinion:<char|seat>:<±N>:<reason>`, `gold:<±N>`,
  `schedule:<event_id>:<delay_ticks>`, `promise:<seat>:<action_code>:<due>`, `flag:<name>`
  (campaign flags for chain conditions), `trait_gate` effects deferred.
- `requires` — optional trait/state gate for showing the choice (`ruler_flag`, `trait_at_court=X`),
  shown/hidden deterministically (EV-3: never hidden dice).
- Both CSVs load fail-loud through `DataRepository` with real required columns + `.import` sidecars.

**Content:** all 20 events from `RANDOM_EVENTS.md` (EV-01…EV-20), template voice lines added
to `templates.csv` (`event_<id>` scene line + `event_<id>_<choice>` outcome line each).
Effects that need absent systems are simplified per §1 and commented in the CSV.
7 chain-starters keep their chains where expressible now (EV-02b, EV-07b, EV-15 follow-up as
scheduled events with their own rows); chains needing factions/relations get `flag:` markers
that later slices read.

### 4.2 Engine: `EventSystem` (RefCounted)

Runs inside `TickEngine.advance`, after the concern scan, before suggestions (per PRD §4 loop):

1. Decrement pity counter; process due `scheduled_events` first (chains fire regardless of roll).
2. Else roll `state.rng.chance(bal(event_base_chance)=0.35)`; force-fire at
   `bal(event_pity_ticks)=6` consecutive quiet ticks.
3. Eligible set = trigger true ∧ cooldown elapsed ∧ `once` unspent; weight-sample via
   `state.rng.pick_weighted`. Empty set → nothing (never pad).
4. Fired event lands on the TickReport (`report.event = {event_id, choices: [...]}`);
   **max one per tick**. GameState gains `event_state` (cooldowns, once-flags, pity, scheduled,
   flags) — serialized in the save.
5. Player picks a choice (button; free text may also select — parse prompt lists active choice ids);
   `EventSystem.apply_choice` executes effects + signature drift, records outcome for narration.
   The event blocks End Turn until resolved (a pending event is part of the turn).

**Determinism:** the roll consumes `state.rng` — twin-run harness must stay green with events
firing; `test_different_seeds_diverge` now genuinely diverges through event outcomes (comment
updated to reflect it finally earning its name). The 48-tick determinism script gains scripted
event choices (deterministic: same events fire at same ticks under a fixed seed).

### 4.3 UI

Event scene renders in the transcript (title + scene text via voice tier), choices as buttons
below it (suggestions hidden while an event is pending), End Turn disabled until resolved.
Choice outcome narrated (template outcome line + effect reason lines, same as actions).

## 5. LLM integration deltas

- Parse prompt: adds active event choice ids + the promise_code-must-be-action_code rule.
- New pseudo-action `EVENT_CHOICE` (params: `{choice_id}`) so free text can resolve a pending
  event ("hire the bandits"): validator accepts it only while an event is pending and the
  choice_id is active; `Game` routes it to `EventSystem.apply_choice` instead of `ActionSystem`.
- `Voicer.voice_event(event, state, data, cb)` — mini tier for `voice=mini`, flagship model
  (config `model_flagship`, default `gpt-5.6-sol`) for the two `flagship` events; template
  fallback identical to briefings. Config gains `model_flagship` key (defaulted, git-ignored).

## 6. Testing

- Every formula TDD'd with hand-computed values: alignment/drift (Odo −8 worked example +
  a pragmatist near-zero case), promise kept/broken, trigger DSL clauses, weight sampling
  (deterministic under seeded Rng), effects vocabulary ops, choice gating.
- Determinism harness extended: scripted 48-tick run with events + choices, twin-run hash
  equal; mid-run save/load unchanged; different seeds diverge.
- Event data lint test: every `event_id` in choices CSV exists in events CSV; every template
  key referenced exists; every `schedule:` target exists; all 20 events + ≥2 choices each.
- UI: pending event blocks End Turn; choice click applies effects and re-enables.
- No live API calls; mini/flagship routing tested via FakeClient.

## 7. Build order (slice-2 tasks)

1. `action_signatures.csv` + signature matcher + `OpinionDrift` (TDD, worked examples).
2. Wire drift into `ActionSystem.execute`; portrait opinion display + hover log.
3. Promise resolution (validator constraint, tick check, voicer lines).
4. Trigger DSL evaluator + `EventEffects` vocabulary (pure, heavily unit-tested).
5. `EventSystem` core (roll/pity/cooldown/schedule/apply_choice) + GameState.event_state +
   determinism harness extension.
6. Event data: all 20 events + choices CSVs + template lines + lint test.
7. UI: event panel, choice buttons, End Turn gating.
8. LLM: voice_event tiers + parse-prompt updates.
9. Final polish: slice-1 parked cleanup (leaked client in `use_client_for_tests`/`_exit_tree`),
   `concern_army_low` 50→45 (Marshal tick-1 complaint), acceptance run.
