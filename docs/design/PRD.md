# Crown and Council — PRD (Chapter 1 MVP)

| | |
|---|---|
| **Status** | Draft v2.0 — MVP redefined as a complete Chapter 1 (supersedes v1.1's "first playable"). Owner 2026-09-18: the MVP is a **complete first chapter with every feature, all of its art and all of its gameplay** — nothing placeholder, nothing "for later" inside Chapter 1 |
| **Date** | 2026-09-04 (statuses and facts re-aligned with the code and `CLAUDE.md` on 2026-09-18) |
| **Author** | Yumeng Zhang |
| **Scope** | Chapter 1, fully functional and fully illustrated: base loop + Council System through faction stage 6 (Tomas only) + chapter framework + raid defense + all chapter-1 art |
| **Source design** | `docs/design/COUNCIL_SYSTEM.md`, `docs/design/MANOR_SYSTEM.md`, `RANDOM_EVENTS.md` (repository root), `game_story/chapter_0/game_start.md` + the data CSVs in `data/` (all paths from the repository root) |

## 1. Vision

A text-first, LLM-narrated grand strategy game. You rule a kingdom over a ~60-year campaign, issuing orders in natural language or by clicking your ministers' suggestions. The heart of the game is the **council**: ministers with real personalities, skills, and ideologies who advise you, argue with each other, hold grudges, form factions, and — over decades — betray you or die for you. Around the council, a pool of **random events** keeps every tick capable of surprise.

The campaign is told in **chapters**: authored story arcs that open, escalate, and resolve on top of the simulation. The MVP is **Chapter 1 complete** — not a systems demo. A player should be able to sit down, play the opening of a reign from coronation to the resolution of its three founding crises (~2–3 game years, ≈2–3 real hours), see every play method the game offers, see finished art everywhere art belongs, and reach an authored chapter close that makes them want Chapter 2.

The core architectural bet is unchanged: **the deterministic engine decides everything; the LLM only writes the dialogue.** Suggestions, opinion changes, faction escalation, raid outcomes, and chapter-arc resolution are all engine math. Chapters are authored content and trigger rules on top of that math — never model improvisation.

## 2. Goals / Non-goals

**Goals (Chapter 1 MVP):**

- A complete, self-contained Chapter 1: three authored arcs (§7) that open in the coronation narration, escalate through events and factions, and each reach an explicit resolution, capped by a chapter-close scene.
- **All play methods present and finished:** guided briefings and clickable suggestions, free-text orders, one-on-one conversations at locations, movement between locations, random events with choices, council debates, recruitment, the relationship graph and info tabs, the interactive world map, factions through **stage 6** (scoped to Duke Tomas's faction), and raid defense.
- **Full art:** every chapter-1 character has final full-body art; every chapter-1 event scene has an illustration; the chapter has title and closing cards. No placeholders visible in a chapter-1 playthrough.
- A campaign that runs, saves, and loads deterministically across the whole chapter.
- Losing is real: Tomas can depose you (chapter-1 game over with an authored scene).

**Non-goals (Chapter 1 MVP):**

- Chapter 2+ content (the close screen sets hooks; nothing past the close is playable).
- Succession, heirs, aging, minister death by age; assassination (stage-4+ mechanic, still post-MVP — Tomas's conspiracy resolves through revolt/deposition, not the knife).
- Faction stages 4–6 for any faction other than Tomas's.
- Seat unlocks beyond the founding five; AI opponent kingdoms; military simulation beyond the raid-defense resolution (§7.4). *(Note 2026-09-18: the regiments already carry morale, wounded, supplies and training, settled monthly — `ArmySystem`, owner 2026-09-17, `docs/superpowers/specs/2026-09-17-regiment-state-design.md` — and the manor economy of `docs/design/MANOR_SYSTEM.md` was built ahead of the chapter steps; neither is a battle simulation.)*
- Steam release, key-proxy backend, monetization, multiplayer.

## 3. Player and platform

- **Player:** strategy players who enjoy CK3-style character drama and King of Dragon Pass-style advisory councils, comfortable reading; solo dev playtest circle first.
- **Platform:** desktop (macOS/Windows/Linux) via **Godot 4.x**, Steam-native path later.
- **Session shape:** single-player campaign, save anytime. A tick is a **month of 30 days** (12 ticks/year; owner 2026-09-14, `Calendar.DAYS_PER_TICK`). Time runs **day by day** on the top bar's clock (`||` pause, `>` play, `2x`, `4x`); there is **no End Turn** — play is the only switch, the thirtieth day's end is the tick, and an event stops the clock and opens the council. Chapter 1 spans ~24–36 months depending on how fast the player resolves the arcs.

## 4. Core loop

```
the clock runs (play / 2x / 4x); each day
  → [ENGINE] building works advance; the month's economy is computed a bucket a day
the thirtieth day ends the month = the tick
  → [ENGINE] settlement: manor lines summed into provinces and the realm, paid into the crown's and the lord's purses
  → [ENGINE] regiments' month, metric drift, relationship drift, claims and promises falling due
  → [ENGINE] concern scan: which metrics crossed a threshold in whose domain
  → [ENGINE] chapter-arc tracker: arc stage transitions, chapter-close check   (not yet built)
  → [ENGINE] event roll: seeded RNG may fire one event (chapter-chain events take priority);
             an event stops the clock and opens the council
  → [ENGINE] advisor heuristics generate concrete suggested actions (real action_codes, always legal & affordable)
  → [LLM, batched] ministers voice concerns and pitch suggestions (templates when low-stakes or offline)
  → PLAYER responds — click a suggestion or a manor order on a map card (zero LLM cost), or type freely
  → [LLM] ONE call: free text → {narrative, impacts: {actions, world, court_reaction}}
  → [ENGINE] execute + court reaction pass (opinion math, promises logged);
             the narrative and the ledger lines that actually applied print together
```

## 5. Requirements — base game skeleton (P0)

- **BG-1 Tick engine.** Advances game state one tick at a time; a tick is a month (12 ticks/year, 30 days each); the clock steps `GameState.day` through `Game.advance_day` and the month's end runs the tick; season/year/day display. *Built (`TickEngine`, `Calendar`).*
- **BG-2 Kingdom state.** The metrics the council data references: treasury/gold, admin capacity, tax income, legitimacy, unrest, grain stores, army quality, church opinion, peasant contentment. Simple drift/production formulas — just enough signal for advisor concern scans to fire. *Built, and grown past the "just enough" bar: gold and goods now come from the **manor economy** (`ManorEconomy` / `RealmEconomy`, `docs/design/MANOR_SYSTEM.md`, spec `docs/superpowers/specs/2026-09-14-economy-and-staging-design.md`) — whole gold rounded once at the manor, settled monthly into **two purses**: the crown's (`treasury`, `strategic`, `grain` = civil goods) and the lord's (`lord_gold`, `lord_strategic`, `lord_civil`) for the provinces the player's house controls.*
- **BG-3 Action system.** Data-driven action taxonomy: `action_code`, params, admin cost, gold cost formula, cooldown, effect handler (pattern per `policy_actions_court_additions.csv`). Ships the 13 court actions plus the domain actions the founding five advise on (at minimum: `TAX_RATE_ADJUST`, `LEVY_RAISE`, `GRAIN_POLICY_SET`, `TARIFF_ADJUST`, `CHURCH_POLICY`, `JUSTICE_SEVERITY`, `BUILD_ECONOMIC`, `SPY_MISSION`). Full taxonomy is open design work (§11). *Status: all eight domain actions (`data/policy_actions_domain.csv`) execute; of the court actions `COUNCIL_CONSULT` and `CHARACTER_REWARD` / `_PUNISH` / `_CONFIDE` execute, while `COUNCIL_DEBATE_RULE`, `RECRUIT_COURTIER`, `CHARACTER_INVESTIGATE`, `FACTION_NEGOTIATE` / `_SPLIT`, `COURT_MARRIAGE`, `GUARD_ADJUST` and `SEAT_UNLOCK` are data rows with no handler yet. Added since: the manor orders `MANOR_BUY` / `_SELL` / `_BUILD` / `_DEMOLISH` / `_FOCUS` / `_RUSH` / `_SEIZE` and `GOODS_BUY` / `_SELL`, run from the map cards without the model. Every order carries a cost from `data/order_costs.csv`.*
- **BG-4 Parse → execute → narrate.** Free-text input parsed by LLM in one call into `{narrative, impacts: {actions, world, court_reaction}}` against a strict schema; the engine validates every action, clamps every world delta to `data/world_schema.csv`, and rejects anything else — the model can never invent an action the engine can't do or move a field the schema does not list. The narrative and the ledger of what applied print together (owner ruling 2026-09-09). *Built (`Voicer.order`, `ResponseValidator`, `OrderPipeline`).*
- **BG-5 Save/load.** Entire game state — including chapter-arc state — serializes to one JSON save. All in-memory objects; no database. *Built (`SaveLoad`; chapter-arc state waits on Step 6).*
- **BG-6 Determinism.** Single seeded RNG owned by the engine; identical save + identical inputs ⇒ identical state. LLM output never mutates state except through validated action codes and clamped enums. *Built (`Rng`); real time lives only in `GameRoot._process`, never below `Game`.*

## 6. Requirements — Council System, events, and build order

Build strictly in this order; each step is independently playtestable. Steps 1–5 are the v1.1 scope; steps 6–10 are new with this revision.

**Status (2026-09-18, from the code):** Step 1 built except the scaffolding phases; Step 2 built; Steps 3–9 not built (Step 4's relationship graph is); the random-events pool built; Step 10 partly (cast art done). Between the steps, work went into the map, the manor economy, the regiments and the UI (see `CLAUDE.md`).

### Step 1 — Founding council, briefings, clickable suggestions

- **CS-1.1** Five founding seats from `council_seats.csv` (unlock_year 0): Chancellor, Marshal, Steward, Spymaster, Chaplain, each with domain, skills, vacancy/obstruction effects.
- **CS-1.2** Fixed starting characters with attributes (0–100), skills (0–20), ideology (−100…+100 on 5 axes), and traits from `character_traits.csv`.
- **CS-1.3** Engine concern scan per tick: threshold breaches mapped to the seat whose domain owns the metric.
- **CS-1.4** Suggestions are engine-generated `action_code`s with real params — always legal, always affordable. LLM voices them; clicking one executes with zero parse cost.
- **CS-1.5** Scaffolding phases with settings override: **Guided** (year 1) → **Assisted** (years 2–5) → **Independent** (year 5+).

*Status: CS-1.1–1.4 built (`data/council_seats.csv`, `data/founding_council.csv`, `ConcernScanner`, `SuggestionGenerator`); CS-1.5 not yet built.*

### Step 2 — Opinion drift from ideology distance

- **CS-2.1** Every action carries an ideology signature; `opinion_delta = alignment × policy_sensitivity × (1 − pragmatism/100)`. Deterministic — no LLM judgment.
- **CS-2.2** **Readable causality is a P0 requirement:** every opinion change stores a hover-inspectable reason string.
- **CS-2.3** Parser `court_reaction` block: `tone` enum with clamped deltas (±3 max); `promises` logged with deadlines. Kept promises: large boost. **Broken promises: the single largest opinion penalty in the game.**

*Status: built (`OpinionDrift`, `Character.change_opinion` with reasons, `ResponseValidator` tones, promises in `GameState.promises` — `promise_kept_opinion` 15 / `promise_broken_opinion` −25 in `data/balance.csv`).*

### Step 3 — Council debates

- **CS-3.1** Engine detects clashes; both ministers voice positions in one batched LLM call; player rules via `COUNCIL_DEBATE_RULE`.

*Status: not yet built (`COUNCIL_DEBATE_RULE` is a data row only).*

### Step 4 — Recruitment

- **CS-4.1** Candidate pool + `RECRUIT_COURTIER` unlocks after year 1.
- **CS-4.2** Relationship graph per `character_relation` with deterministic formation rules.

*Status: CS-4.1 not yet built (`RECRUIT_COURTIER` is a data row only). CS-4.2 partly: `RelationshipGraph` seeds edges from `data/relationships.csv`, drifts them monthly and shows them on the RELATIONSHIP tab; formation of new edges is not built.*

### Step 5 — Factions through stage 3

- **CS-5.1** Faction formation; power and cohesion formulas per design doc.
- **CS-5.2** Escalation stages 1–3 from `faction_escalation.csv` (grumbling → petition → obstruction) with dwell times. **Telegraphing is a hard rule.**
- **CS-5.3** Counters: `FACTION_NEGOTIATE`, `FACTION_SPLIT`, `CHARACTER_REWARD/PUNISH/CONFIDE`, concessions.
- **CS-5.4** Stage-3 obstruction gets loud, explicit in-fiction signalling.

*Status: not yet built (`data/faction_escalation.csv` exists; no faction engine).*

### Random events pool (P0 — ambient layer under the chapter chains)

Full design in `RANDOM_EVENTS.md`.

- **EV-1** Data-driven pool (20 ambient events in `data/events.csv` + `data/event_choices.csv`). Per-tick roll on the seeded RNG: 35% base chance, max one event per tick, a pity timer that forces one after 3 quiet months (`event_base_chance` / `event_pity_ticks` in `data/balance.csv`; it was 6 half-month ticks), weight-sampled from the eligible set (triggers, cooldowns, `once` flags). Chapter-chain events (EC-1) take roll priority.
- **EV-2** Choices are buttons bundling concrete engine effects; every choice carries an ideology signature so minister reactions flow through the opinion-drift math with reason strings.
- **EV-3** Fairness rule: no single event may cripple a campaign; severe outcomes only arrive at the end of a visible, chosen-into chain. Trait-gated options are shown/hidden deterministically — never hidden dice.
- **EV-4** Event scene prose is **authored, never model-written** (`StorySource` reads `RANDOM_EVENTS.md` verbatim); events therefore cost no API calls to present.

*Status: EV-1–EV-4 built (`EventSystem`, `TriggerDsl`, `EventEffects`). An event stops the clock and is shown in the audience window on the council stage.*

### Step 6 — Chapter framework (new)

- **CH-1** Arc tracker: chapter arcs (§7.1) live in data (`data/chapter_arcs.csv` + stage rows), each with engine-checkable stage-advance and resolution conditions over metrics, faction state, event-chain outcomes, and character states. No arc logic hardcoded in scripts.
- **CH-2** Chapter close: when all three arcs are resolved (any mix of outcomes), the engine fires the authored chapter-close scene — a full-screen title card + narration summarizing how each arc ended (outcome-keyed authored prose, model never writes it). A lost chapter (deposition, §7.3) fires the game-over close instead.
- **CH-3** Arc visibility: the info tabs gain a CHRONICLE view listing each arc, its current stage, and what has moved it — same readable-causality rule as opinions.
- **CH-4** Chapter title card on campaign start ("Chapter One — <name>") after the opening narration.
- **CH-5** Pacing guardrails: arcs cannot all resolve before year 2 (dwell minimums), and the chapter forces escalation beats if an arc has idled for a year (tunable in data).

*Status: not yet built (no `data/chapter_arcs.csv`). The opening narration from `game_story/chapter_0/game_start.md` is built; the title card is not.*

### Step 7 — Faction stages 4–6, Tomas only (new; was post-MVP)

- **FS-1** Stages 4–6 from `faction_escalation.csv` (conspiracy → revolt → deposition) enabled only for a faction led by `char_duke_tomas` (data flag on the faction row, not a code special case: `stage_cap` column per faction seed).
- **FS-2** Conspiracy (stage 4) is hidden **unless a Spymaster sits and his `SPY_MISSION` coverage catches it** — the mechanical price of an empty or hostile Spymaster seat, spelled out in-fiction the first time it matters.
- **FS-3** Revolt (stage 5) and deposition (stage 6) resolve deterministically from faction power vs. crown legitimacy + army quality; every threshold telegraphed at stage 4+ through the Chronicle and minister warnings.
- **FS-4** Deposition = chapter-1 game over with an authored scene. All existing counters (CS-5.3) plus `CHARACTER_PUNISH` (arrest/exile) remain the player's tools; crushing, marginalizing, or genuinely reconciling Tomas are all valid arc resolutions (§7.1).

*Status: not yet built.*

### Step 8 — Raid defense (new)

- **RD-1** A thin, deterministic raid resolution — not a wargame: when the {raider_realm} arc's raid beat fires, outcome tier = f(army quality, levies raised, fortification/readiness actions taken, warning heeded) → {repelled clean, repelled with losses, border burned, disaster}. Formula in data, hand-computed GUT fixtures.
- **RD-2** Readiness actions (`LEVY_RAISE`, `FORTIFY_BORDER`, `MUSTER_DRILL` — the latter two added to the action set) are useful *before* the raid and visibly referenced by the outcome narration ("the levies Hale drilled all winter held the ford").
- **RD-3** Every outcome is survivable; "disaster" scars metrics and the Chronicle but never ends the campaign (the fairness rule EV-3 extended to raids).

*Status: not yet built. `LEVY_RAISE` executes; `FORTIFY_BORDER` and `MUSTER_DRILL` do not exist yet. The regiment state (`ArmySystem`: morale, wounded, supplies, training) is built and is the natural input for RD-1.*

### Step 9 — Chapter-1 event chains (new)

- **EC-1** Each arc gets an authored event chain in `RANDOM_EVENTS.md` (same format contract: `### EV-NN`, `**Scene:**` prose displayed verbatim, spec'd triggers/choices/signatures): ~4–6 chained events per arc plus the existing 20-event ambient pool. Chain events take roll priority over ambient events (§4).
- **EC-2** Chain events reference arc stage in their triggers (via the trigger DSL) so story beats land in order and react to how the player has treated the arc so far.
- **EC-3** All chain prose is authored, never model-written — unchanged hard rule.

*Status: not yet built; `RANDOM_EVENTS.md` holds the 20 ambient events only.*

### Step 10 — Art integration pass (new)

- **AR-1 Cast art.** Final full-body portrait for **all 16 characters in `roles.csv`** — the five ministers (Chaplain gets his own art, ending the courier duplicate), the royal family (queen, princess, Duke Tomas, Lady Ysolde), court and city figures (Hale, Corina, Edgar, Malvern, Tessa, Cassian, Corvin), and the foreign cast (Osric, Isabeau, Petra, Emperor Constans). *Status: done for the whole cast of 21 (`data/founding_council.csv` + `data/roles.csv`). The pipeline is now the Flux one (`assets/flux/`): one library `K-` entry per character in `docs/references/art_prompt_library.md`, `assets/flux/cast_art.csv`, `install_map_art.py cast` → `assets/portraits/<id>.png` (chip) and `assets/portraits/full/<id>.png` (figure), colour kept; the earlier `tools/clean_portrait_art.py` route is superseded.*
- **AR-2 Event art.** One illustration per chapter-1 chain event and per ambient event used in chapter 1, shown in the event popup where the placeholder frame sits today. Same pipeline; a shared default per event category is acceptable as fallback during development but **no placeholder may be visible at MVP sign-off**. *Status: not yet built — events stand in the CK3-style audience window with the round-table portrait, no illustration.*
- **AR-3 Chapter cards.** Chapter-1 title card, chapter-close card (variant art or tinting per major outcome mix is a stretch goal; one card minimum), and the game-over (deposition) card. *Status: not yet built.*
- **AR-4** The world map is done and interactive in all gameplay screens, and is the standing bar for art finish: nothing shipped in chapter 1 should look less finished than the map view. *Status (2026-09-18): there is no render PNG any more (owner 2026-09-11) — the game draws the Azgaar pack's cells itself, the ground in satellite-photograph biome tiles lit by the pack's height (owner 2026-09-17), aerial-photograph settlements, banded sea, dashed borders, and generated house arms; a 3D MAP tab shows the same world as a Terrain3D landscape with clickable towns and provinces and live borders (owner 2026-09-18, `scripts/map3d/`). The UI around it is a dark theme after Crusader Kings III (owner 2026-09-15).*

## 7. Chapter 1 — "The Crown Unsettled" (working title)

Chapter 1 is the authored opening situation of `game_story/chapter_0/game_start.md`, played to resolution. It opens at coronation and closes when all three arcs resolve (or the crown falls).

### 7.1 The three arcs

| Arc | Opens | Escalates through | Resolutions (any counts) |
|---|---|---|---|
| **The Half-Brother** — Duke Tomas covets the throne | Coronation narration; Tomas's opinion and ambition | Faction stages 1–6 (FS-1): grievance → petition → obstruction → conspiracy → revolt | Reconciled (opinion + kept promises), marginalized (faction dissolved/split, Tomas isolated), crushed (conspiracy exposed and punished), **or you are deposed — game over** |
| **The Hungry Crowd** — food crisis, Cassian's demonstrations | Low grain + unrest narration; Cassian's rallies | Grain/contentment metrics, protest events, Cassian chain (prophet events), justice/grain actions | Fed (grain + contentment restored ≥ thresholds for N ticks), suppressed (unrest crushed — lasting contentment/church scars carried into the close), or co-opted (Cassian chain's reconciliation ending) |
| **Spears in the West** — {raider_realm} prepares to raid | Quill's muster report (`fact_raider_muster`) | Warning events, readiness actions (RD-2), diplomatic feelers via Petra/envoys | Raid resolved at any RD-1 tier; or deterred entirely (readiness above threshold before the raid beat — the hardest, most expensive resolution) |

### 7.2 Chapter-close scene

Outcome-keyed authored prose (CH-2): one paragraph per arc reflecting its resolution, then a hook paragraph for Chapter 2 ({neighbor_realm} and the puppet Emperor are watching). Deposition instead shows the game-over card (AR-3) with its own authored scene.

### 7.3 What chapter 1 deliberately does not resolve

{neighbor_realm}/{empire_realm} (Isabeau's designs), the Emperor's fate, succession, Malvern's decline, the Chancellor's graft file — these are seeded, referenced, and left loaded for later chapters.

## 8. LLM integration

**Provider:** OpenAI API, raw HTTP from Godot (`HTTPRequest`); no official GDScript SDK exists.

**Model tiers** (GPT-5.6 family after the July 2026 price cuts; re-verify before implementation). The tier defaults live in `OpenAIClient.load_config` (`model_parse` / `model_order` `gpt-5.6-luna`, `model_voice` `gpt-5.6-terra`, `model_flagship` `gpt-5.6-sol`) and are overridden by `.env` (`LLM_MODEL` for all tiers or `LLM_MODEL_PARSE` / `_ORDER` / `_VOICE` / `_FLAGSHIP`; `.env.example` documents the keys) and then by `user://config.json`:

| Call | Model | Frequency | Notes |
|---|---|---|---|
| Free-text order → narrative + impacts JSON | `gpt-5.6-luna` ($0.20/$1.20 per MTok), `LLM_MODEL_ORDER` | every free-text turn | One call; strict two-part schema; replaces the old parse + converse pair |
| Routine narration | `gpt-5.6-luna` | most ticks | Template-voiced with **no LLM at all** when low-stakes |
| Council briefing | `gpt-5.6-terra` ($2/$12) | ~40% of ticks | One batched call, all speaking ministers |
| Debate scene | `gpt-5.6-terra` | ~5% of ticks | One call, both sides — *not yet built (Step 3)* |
| Event scenes | — | — | **Authored prose, never model-written** (hard rule; scenes live in `RANDOM_EVENTS.md`) |
| Faction petition / conspiracy warning | `gpt-5.6-terra` | rare | *not yet built (Steps 5, 7)* |
| Confrontation / revolt / deposition / chapter close framing | authored + `gpt-5.6-sol` ($5/$30) for surrounding court reaction only | rare, high stakes | Close/game-over prose itself is authored (CH-2). *The flagship tier is configured but nothing calls it yet.* |

**Cost posture:** clicked suggestions and event-choice buttons cost nothing to parse; low-stakes lines are trait-tinted templates. Chapter chains add authored scenes, not API calls.

**Key handling:** developer API key in local git-ignored config (`.env` / `user://config.json`), fail-closed offline mode (a missing key, or `CC_FORCE_OFFLINE=1` as `run_tests.sh` sets, forces offline; offline, lines fall back to templates). A key-proxy backend remains a **hard pre-release requirement**.

## 9. Success metrics and kill criteria

Validated with ~5 fresh playtesters on the Chapter 1 MVP:

- **Success:** a new playtester (a) finishes Chapter 1 in one or two sittings without coaching, (b) can retell all three arcs and how theirs ended, (c) issues free-text orders — not only clicks — before the chapter ends, and (d) asks what happens in Chapter 2.
- **Play-method coverage signal:** across 5 testers, every play method (suggestions, free text, conversations, movement, events, debates, recruitment, faction counters, raid readiness, map) gets used unprompted by at least one tester; any method nobody touches is cut or reworked, not polished.
- **Kill criteria (unchanged bets):** advice routinely skipped or samey → council redesign before more content. Events clicked through unread or repeating → tune pool before growing it.
- **Chapter kill criterion:** testers stall mid-chapter not knowing what an arc wants from them → the Chronicle/telegraphing (CH-3, CS-5.2) is failing; fix readability before adding content.
- **Guardrail:** advisors stay *ideologically biased*, never optimal.

## 10. Post-MVP roadmap (explicitly out of Chapter 1)

1. **Chapter 2+**: {neighbor_realm}/{empire_realm} arc, the Emperor, escalating faction play for the full cast.
2. **Assassination** under the five hard rules from the design doc.
3. **Aging, death, inheritance**; succession as the answer to deposition beyond chapter 1.
4. **Faction stages 4–6 for all factions** (chapter 1 caps them to Tomas's).
5. **Seat unlocks** beyond the founding five.
6. **AI opponent kingdoms**; broader map/economy/military sim; Steam packaging + key-proxy backend. *(Parts of the map/economy/military sim have already been built — the manor economy, the regiment state, territory as state — see §2 non-goals note.)*

## 11. Open questions (owed answers before/while building)

**Answered by the owner, 2026-09-18** (after the documents were re-aligned with the code):

- **Build order:** §6 stands unchanged and strict, even though the map, the manor economy, the regiments and the UI were built ahead of Steps 3–9.
- **MVP:** a complete first chapter — every feature, all art, all gameplay (Status, above).
- **Event cooldowns** are to be **redesigned**: the draft's `cooldown_ticks` were written for half-month ticks and now read as years of months (`RANDOM_EVENTS.md`).
- **DAY_RUN** (the end-turn calendar screen, unreachable since End Turn went) is **removed** from the game.
- **Nations:** the design counts **8** kingdoms; the size of the action set is not decided yet.
- **Queen Isabeau's direction** ("north" in the story, "eastern border" in `relationships.csv`) waits for the owner's map update.
- **Model configuration** stays as it is (defaults in `OpenAIClient.load_config`, overlaid by `.env` and `user://config.json`).

Still open:

- Full base-game action taxonomy and effect formulas — needs its own design doc (the manor orders are specified in `docs/design/MANOR_SYSTEM.md`); `FORTIFY_BORDER`/`MUSTER_DRILL` (RD-2) land with it.
- Arc condition specifics: exact thresholds/dwell times for CH-1/CH-5 and the §7.1 resolution tests (tune in playtest; live in `chapter_arcs.csv`).
- Chapter-1 chain authoring: ~12–18 new spec'd events (EC-1) — seeds start in `RANDOM_EVENTS.md`'s inbox.
- Economy formulas for BG-2 metrics (currently "just enough signal"). *Largely answered for gold and goods by the manor economy (`docs/superpowers/specs/2026-09-14-economy-and-staging-design.md`); of its §7 the play button and the removal of End Turn are built, while staged orders, the command log and the month-end council are not.*
- Exact concern-scan thresholds per metric (tune in playtest).
- Art budget/schedule: ~~16 portraits~~ (done: 21) + ~20 event illustrations + 3 cards through the AI-art pipeline — owner throughput is the constraint (§12).

## 12. Risks

| Risk | Mitigation |
|---|---|
| Dialogue repetition | Template variety, recent-line memory, event-specific references (§8) |
| Advisor tyranny (players just click) | Ideologically biased advice, never optimal advice (§9) |
| Unreadable causality | Reason strings everywhere; Chronicle for arcs (CS-2.2, CH-3) |
| Obstruction/conspiracy reads as a bug | Loud in-fiction signalling; conspiracy visibility rule spelled out in-fiction (CS-5.4, FS-2) |
| Faction 4–6 complexity creep | Hard-scoped to Tomas's faction via data `stage_cap`; deterministic revolt math (FS-1/FS-3) |
| Chapter pacing (arcs resolve too fast/slow) | Dwell minimums + idle-escalation beats in data, tuned in playtest (CH-5) |
| Art pipeline bottleneck | Category-fallback event art during development; portrait list frozen at 16; AR-2 sign-off rule keeps placeholders out of the release, not out of dev builds |
| A random event or raid ruins a campaign | Fairness rule EV-3 extended to raids (RD-3); only Tomas's stage 6 ends the game, always telegraphed |
| LLM breaks determinism | Engine validates all model output (BG-4/BG-6); event/chapter prose is authored, never generated |
| Scope creep past the chapter | §2 non-goals; anything not needed by the three arcs waits for Chapter 2 |
| Model lineup/pricing churn | Model IDs live in one config table, re-checked at implementation time (§8) |
