# Crown and Council — PRD (First Playable)

| | |
|---|---|
| **Status** | Draft v1.1 — adds the random-events system |
| **Date** | 2026-08-28 |
| **Author** | Yumeng Zhang |
| **Scope** | First playable build: minimal base game loop + Council System steps 1–5 |
| **Source design** | `COUNCIL_SYSTEM.md`, `RANDOM_EVENTS.md` + data CSVs in this directory |

## 1. Vision

A text-first, LLM-narrated grand strategy game. You rule a kingdom over a ~60-year campaign, issuing orders in natural language or by clicking your ministers' suggestions. The heart of the game is the **council**: ministers with real personalities, skills, and ideologies who advise you, argue with each other, hold grudges, form factions, and — over decades — betray you or die for you. Around the council, a pool of **random events** keeps every tick capable of surprise — omens, duels, prophets, windfalls, and slow-burning story chains that give traits and relationships their moments on stage.

The core architectural bet, inherited from the design doc: **the deterministic engine decides everything; the LLM only writes the dialogue.** Suggestions, opinion changes, faction escalation, and conflict detection are all engine math. This keeps the game reproducible from a save, keeps advisors trustworthy (they never propose illegal actions), and keeps API costs proportional to drama rather than to playtime.

## 2. Goals / Non-goals

**Goals (first playable):**

- Validate the guided-council onboarding: a new player finishes year 1 with no manual.
- A council of five that visibly agrees, disagrees, and reacts to your rule.
- Frequent random events (~8/year from a 20-event pool) so no two sessions of the same campaign year feel alike, with chains that pay off ticks or years later.
- A campaign that runs, saves, and loads deterministically for at least 5 in-game years.

**Non-goals (first playable):**

- Faction stages 4–6 (conspiracy, revolt, deposition), assassination, succession, minister aging/death. These are post-MVP (§9).
- AI opponent kingdoms, map/military simulation beyond stubs.
- Steam release, key-proxy backend, monetization.
- Multiplayer (never planned).

## 3. Player and platform

- **Player:** strategy players who enjoy CK3-style character drama and King of Dragon Pass-style advisory councils, comfortable reading; solo dev playtest circle first.
- **Platform:** desktop (macOS/Windows/Linux) via **Godot 4.x**, Steam-native path later.
- **Session shape:** single-player campaign, tick-based (24 ticks/year, ≈half-month per tick), pausable, save anytime.

## 4. Core loop

```
tick advances
  → [ENGINE] concern scan: which metrics crossed a threshold in whose domain
  → [ENGINE] event roll: seeded RNG may fire one event from the random-events pool
  → [ENGINE] advisor heuristics generate concrete suggested actions (real action_codes, always legal & affordable)
  → [LLM, batched] ministers voice concerns and pitch suggestions
  → PLAYER responds — click a suggestion (zero LLM parse cost), or type freely
  → [LLM] parse free text into actions + court_reaction block
  → [ENGINE] execute + court reaction pass (opinion math, promises logged)
  → [LLM] narrate outcomes
```

## 5. Requirements — base game skeleton (P0)

The council doc assumes a base game that does not exist yet. The first playable needs this minimal host:

- **BG-1 Tick engine.** Advances game state one tick at a time; 24 ticks/year; campaign clock, season/year display.
- **BG-2 Kingdom state.** The metrics the council data already references: treasury/gold, admin capacity, tax income, legitimacy, unrest, grain stores, army quality, church opinion, peasant contentment. Simple drift/production formulas — just enough signal for advisor concern scans to fire.
- **BG-3 Action system.** Data-driven action taxonomy: `action_code`, params, admin cost, gold cost formula, cooldown, effect handler (pattern per `policy_actions_court_additions.csv`). First playable ships the 13 court actions plus a minimal set of domain actions covering what the founding five advise on (at minimum: `TAX_RATE_ADJUST`, `LEVY_RAISE`, `GRAIN_POLICY_SET`, `TARIFF_ADJUST`, `CHURCH_POLICY`, `JUSTICE_SEVERITY`, `BUILD_ECONOMIC`, `SPY_MISSION`). Full taxonomy is open design work (§10).
- **BG-4 Parse → execute → narrate.** Free-text input parsed by LLM into `{actions: [...], court_reaction: {...}}` against a strict schema; engine validates every action (legality, affordability, cooldown) and rejects anything invalid — the model can never invent an action the engine can't do.
- **BG-5 Save/load.** Entire game state serializes to one JSON save. All in-memory objects; no database.
- **BG-6 Determinism.** Single seeded RNG owned by the engine; identical save + identical inputs ⇒ identical state. LLM output never mutates state except through validated action codes and clamped enums.

## 6. Requirements — Council System and random events (P0, build order 1–5)

Build strictly in this order; each step is independently playtestable.

### Step 1 — Founding council, briefings, clickable suggestions (highest value)

- **CS-1.1** Five founding seats from `council_seats.csv` (unlock_year 0): Chancellor, Marshal, Steward, Spymaster, Chaplain, each with domain, skills, vacancy/obstruction effects.
- **CS-1.2** Fixed starting characters with attributes (0–100), skills (0–20), ideology (−100…+100 on 5 axes), and traits from `character_traits.csv` (traits modify attributes/skills and nudge ideology).
- **CS-1.3** Engine concern scan per tick: threshold breaches mapped to the seat whose domain owns the metric.
- **CS-1.4** Suggestions are engine-generated `action_code`s with real params from the same utility heuristics future AI opponents will use — always legal, always affordable. LLM voices them; clicking one executes with zero parse cost.
- **CS-1.5** Scaffolding phases with settings override (player can stay Guided forever):
  - **Guided** (year 1): Chancellor opens every tick, 2–3 suggestions with explicit numbers and plain-language trade-offs; post-execution explanation of what moved and why.
  - **Assisted** (years 2–5): concerns raised without pre-filled parameters.
  - **Independent** (year 5+): ministers speak only on threshold breach, disagreement, or `COUNCIL_CONSULT`.

### Step 2 — Opinion drift from ideology distance

- **CS-2.1** Every action carries an ideology signature. On execution: `alignment = dot(action_signature, character_ideology) / magnitude`; `opinion_delta = alignment × policy_sensitivity × (1 − pragmatism/100)`. Deterministic — no LLM judgment.
- **CS-2.2** **Readable causality is a P0 requirement, not polish:** every opinion change stores a hover-inspectable reason string, e.g. `−8: revoked noble tax exemption (opposes, centralism)`.
- **CS-2.3** Parser `court_reaction` block: `tone` enum (`respectful|neutral|curt|flattering|threatening|dismissive`) with clamped deltas (±3 max); `promises` logged with deadlines. Kept promises: large boost. **Broken promises: the single largest opinion penalty in the game**, permanently raising faction affinity.

### Step 3 — Council debates

- **CS-3.1** Engine detects clashes (opposing ideology signs on an axis + both high `temper`); both ministers voice positions in one batched LLM call; player rules via `COUNCIL_DEBATE_RULE`. Picking a side swings both opinions; refusing costs a little with both.

### Step 4 — Recruitment

- **CS-4.1** Candidate pool + `RECRUIT_COURTIER` unlocks after year 1. Better candidates cost more and want more.
- **CS-4.2** Relationship graph per `character_relation` (types: kin, spouse, friend, rival, mentor, debt, blood_feud) with the deterministic formation rules from the design doc (rivalry, friendship; blood feud lands post-MVP with kin-execution).

### Step 5 — Factions through stage 3 (STOP here for first playable)

- **CS-5.1** Faction formation (≥2 characters sharing a grievance axis, loyalty below / ambition above threshold; `kin_of_king` or `amb_ruthless` can seed alone). Power and cohesion formulas per design doc.
- **CS-5.2** Escalation stages 1–3 from `faction_escalation.csv` (grumbling → petition → obstruction) with dwell times. **Telegraphing is a hard rule:** stage 2 always visible, always states the demand explicitly.
- **CS-5.3** Counters: `FACTION_NEGOTIATE`, `FACTION_SPLIT`, `CHARACTER_REWARD/PUNISH/CONFIDE`, concessions.
- **CS-5.4** Stage-3 obstruction (orders failing) gets loud, explicit in-fiction signalling so it reads as mechanic, not bug.

### Random events pool (P0 — buildable any time after Step 2)

Full design in `RANDOM_EVENTS.md`. Events make ticks unpredictable and give traits, seats, and the opinion system moments to matter.

- **EV-1** Data-driven pool (ships with 20 events; converts to `data/events.csv` + `data/event_choices.csv` at implementation). Per-tick roll on the seeded RNG: 35% base chance, max one event per tick, 6-tick pity timer, weight-sampled from the eligible set (triggers, cooldowns, `once` flags).
- **EV-2** Choices are buttons bundling concrete engine effects; every choice carries an ideology signature so minister reactions flow through the existing opinion-drift math with reason strings — no special-case code.
- **EV-3** Fairness rule: no single event may cripple a campaign; severe outcomes only arrive at the end of a visible, chosen-into chain. Trait-gated options are shown/hidden deterministically — never hidden dice.
- **EV-4** Voicing follows the cost posture: template tier free, mini model for routine scenes, flagship only for rare set-pieces (2 of 20 in the starter pool).

## 7. LLM integration

**Provider:** OpenAI API, raw HTTP from Godot (`HTTPRequest`); no official GDScript SDK exists.

**Model tiers** (current lineup as of Aug 2026 — GPT-5.6 family after the July price cuts; re-verify before implementation):

| Call | Model | Frequency | Notes |
|---|---|---|---|
| Free-text parse → action JSON | `gpt-5.6-luna` ($0.20/$1.20 per MTok) | every free-text turn | Strict JSON schema; cheap tier |
| Routine narration | `gpt-5.6-luna` | most ticks | Template-voiced with **no LLM at all** when low-stakes |
| Council briefing | `gpt-5.6-terra` ($2/$12) | ~40% of ticks | One batched call, all speaking ministers |
| Debate scene | `gpt-5.6-terra` | ~5% of ticks | One call, both sides |
| Event scene (routine) | `gpt-5.6-terra` | ~30% of ticks | 15 of 20 starter events; 3 more are pure templates (no call) |
| Event set-piece | `gpt-5.6-sol` ($5/$30) | rare | 2 of 20 starter events (prophet debate, orphan of the old line) |
| Faction petition | `gpt-5.6-terra` | rare | |
| Confrontation / betrayal scene | `gpt-5.6-sol` | rare, high stakes | The "good model" moments |

**Cost posture:** clicked suggestions and event-choice buttons cost nothing to parse; low-stakes lines are trait-tinted templates. Council system adds ~30% to per-campaign API spend, not 5×; the event roll adds roughly one mini-tier scene per 3 ticks on top of that.

**Key handling:** developer API key read from a local, git-ignored config file for the first playable. A key-proxy backend is a **hard pre-release requirement** — an API key must never ship inside the Godot binary.

**Dialogue repetition mitigations:** trait-tinted template variety, recent-line memory in the prompt, ministers reference specific recent events rather than generic states.

## 8. Success metrics and kill criteria

Validated with ~5 fresh playtesters on the first playable:

- **Success:** a new playtester (a) completes year 1 without a manual or designer coaching, (b) issues free-text orders — not only clicks — by year 2, and (c) asks to keep playing.
- **Events success signal:** playtesters retell specific event moments afterward ("the parrot", "the fake king") unprompted — events are doing their job as story generators, not interruptions.
- **Kill criteria for the guided-council bet:** testers routinely skip/ignore council advice, or advice reads as samey within a single session. Either one means the council needs redesign **before** any investment in stages 4–6.
- **Events kill criterion:** testers start clicking through events without reading, or the same events recur within a session — tune frequency/cooldowns or grow the pool before adding anything else.
- **Guardrail:** advisors must be *ideologically biased*, not optimal — a militarist Marshal genuinely over-recommends war. If playtesters stop thinking and just click, advice has become too correct (advisor tyranny).

## 9. Post-MVP roadmap (explicitly out of P0)

1. **Faction stages 4–6:** conspiracy (hidden without a Spymaster — the mechanical price of the empty seat, spelled out in tutorial), open revolt, deposition.
2. **Assassination** under the five hard rules from the design doc: only reachable from stage 4, always telegraphed, always counterable, weighted toward failed/wounded outcomes, and death routes to heir succession — hard game-over only at stage 6 with no heir.
3. **Aging, death, inheritance:** sons enter the pool with `inherit_chance` traits, relationships at 50% strength including blood feuds against you; grievance persists, faction membership doesn't.
4. **Seat unlocks** beyond the founding five (`SEAT_UNLOCK`: Chief Justice, Master of Works, Admiral, Court Physician) with their tech/coastal requirements.
5. **AI opponent kingdoms** sharing the advisor utility heuristics; broader map/economy/military sim; Steam packaging + key-proxy backend.

## 10. Open questions (owed answers before/while building)

- Full base-game action taxonomy and effect formulas (BG-3 ships a minimal subset) — needs its own design doc.
- Map model: how many provinces, and how thin can province simulation be while `FORTIFY_PROVINCE`-class actions still mean something?
- Economy formulas for BG-2 metrics (currently "just enough signal").
- Godot UI layout: single throne-room/council screen vs. council + map screens.
- Exact concern-scan thresholds per metric (tune in playtest).
- Event pool growth: owner's seed ideas land in `RANDOM_EVENTS.md` ("Your event seeds" section) and get expanded into spec'd events; 20 is the floor, not the target — a 60-year campaign will want 60+.

## 11. Risks

| Risk | Mitigation |
|---|---|
| Dialogue repetition by year 15 | Template variety, recent-line memory, event-specific references (§7) |
| Advisor tyranny (players just click) | Ideologically biased advice, never optimal advice (§8) |
| Unreadable causality | Reason strings on every opinion change, built from day one (CS-2.2) |
| Obstruction reads as a bug | Loud in-fiction signalling (CS-5.4) |
| Events repeat or feel spammy | Cooldowns, `once` flags, pity-timer tuning, ~⅓ of pool as one-shot set-pieces; grow the pool from owner seeds (EV-1, §10) |
| A random event ruins a campaign | Fairness rule EV-3: single events sting but never cripple; severe outcomes only end visible chains |
| LLM breaks determinism | Engine validates all model output; model output limited to validated action codes + clamped enums (BG-4/BG-6) |
| Greenfield scope creep on the base game | Base game stays a skeleton until the council bet validates (§2 non-goals) |
| Model lineup/pricing churn | Model IDs live in one config table, re-checked at implementation time (§7) |
