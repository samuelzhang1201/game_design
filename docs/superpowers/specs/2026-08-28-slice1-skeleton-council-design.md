# Slice 1 — Walking Skeleton + Council Step 1 + Free Text: Design

Status: approved in brainstorming 2026-08-28 (sections A–D). Parent: `PRD.md` (Draft v1.1).
Scope source: PRD BG-1…BG-6 + CS-1.1…CS-1.5, free-text parse included.

## 1. Goal

The smallest playable Crown and Council: launch the game, live through year 1 (24 ticks)
with the five founding ministers briefing you every tick, act by clicking suggestions or
typing orders, save/load deterministically. Pixel-art presentation from day one.
Playtestable end-to-end without an API key (template voice, click input).

**Out of scope for slice 1:** opinion drift from ideology signatures (slice 2), debates
(slice 3), recruitment (slice 4), factions (slice 5), random events pool (after slice 2),
Assisted/Independent phase content (framework ships, content later).

## 2. Architecture

Four parts; dependencies point strictly downward. Nothing below `ui/` imports a Node.

```
ui/        council scene (pixel presentation, input, transcript)
llm/       OpenAIClient · PromptBuilder · ResponseValidator · Voicer
engine/    pure RefCounted simulation — the only writer of game state
data/      CSV tables — the only home of design numbers
```

### 2.1 Data layer

- `data/` holds the four existing CSVs plus two new ones:
  - `balance.csv` — every tunable constant (drift rates, thresholds, costs). No design
    number is ever a literal in a script.
  - `templates.csv` — template-tier voice lines, tinted by trait (slice 1 ships enough
    for briefings and outcome narration).
- `DataRepository` (autoload) parses all CSVs at boot into typed, read-only dictionaries.
  **Fail-loud:** a malformed row aborts startup naming file + row; never a silent default.
- At implementation, `policy_actions_court_additions.csv` is joined by
  `policy_actions_domain.csv` for the eight slice-1 domain actions (same schema).

### 2.2 Engine layer (`scripts/engine/`, all RefCounted, zero Node imports)

| Module | Responsibility |
|---|---|
| `Rng` | Wraps one `RandomNumberGenerator` seeded at campaign start; the only randomness source. Serialized (seed + state) into the save. |
| `GameState` | Kingdom metrics, tick counter, council roster, characters, promises, log. Plain data + queries; no rules. |
| `TickEngine` | `advance() -> TickReport`. Runs metric drift, concern scan, suggestion generation. |
| `ActionSystem` | Validates an `ActionRequest` (exists, affordable, off cooldown, legal target) and executes its effect handler. The **only** mutation path into `GameState` besides tick drift. |
| `ConcernScanner` | Compares metrics to `balance.csv` thresholds; maps each breach to the owning seat. |
| `SuggestionGenerator` | Utility heuristics per seat → 2–3 concrete `ActionRequest`s (always valid); ideologically biased per minister, deliberately not optimal. |
| `CharacterFactory` | Builds ministers from data: base attributes/skills + trait modifiers from `character_traits.csv`. |
| `SaveLoad` | `GameState` ⇄ one JSON file (`user://saves/`). Round-trip is lossless, including Rng state. |

**TickReport** (the engine→voicing contract): tick number, season, metric deltas with
reason strings, concerns `[{seat, metric, severity}]`, suggestions
`[{seat, action_request, tradeoff_data}]`, outcome records from last turn's actions.
Fully deterministic; two runs with the same seed and inputs produce identical reports.

### 2.3 LLM layer (`scripts/llm/`)

| Module | Responsibility |
|---|---|
| `OpenAIClient` | HTTPRequest wrapper for the OpenAI HTTP API (verify current endpoint shape at implementation); model + key from config; timeout 20s; one retry. |
| `PromptBuilder` | TickReport → briefing prompt (batched, all speaking ministers, persona blocks, recent-line memory); player text → parse prompt with strict JSON schema. |
| `ResponseValidator` | Parses model JSON → typed `{actions: [ActionRequest], court_reaction}` ; rejects anything off-schema. Court-reaction `tone` clamped to the enum, deltas ±3. |
| `Voicer` | Tier router: `template` (offline, from `templates.csv`, trait-tinted) → `luna` (routine) → `terra` (briefings). Slice 1 uses template + luna + terra only. Missing key or any failure ⇒ template tier. |

Config: `user://config.json` (git-ignored): `api_key`, `model_parse`, `model_voice`,
`offline_mode`. Model IDs live only here + one defaults table.

### 2.4 UI layer — pixel presentation

- Base viewport **640×360**, `canvas_items` stretch with integer scaling,
  nearest-neighbor filtering, 2D pixel snap.
- One council scene: metrics strip (top), scrolling court transcript (center), input row
  (bottom: 2–3 suggestion buttons + free-text box + End Turn).
- Readable pixel font for body text (text-heavy game — legibility over tininess);
  hover on any metric/opinion delta shows its reason string.
- `assets/`: placeholder 48×48 pixel portraits for the five ministers + one
  council-chamber backdrop. Flat, swappable; real art later without code changes.

## 3. Turn flow and failure handling

Turn-gated: the next tick never starts until the player acts, so LLM latency hides in
reading time. The engine never awaits the LLM.

1. `TickEngine.advance()` → TickReport (instant, deterministic).
2. `Voicer` renders the briefing async; UI shows suggestion buttons immediately.
3. Player clicks (skip to 5) or types (4).
4. Parse call → `ResponseValidator` → engine validation. Off-schema or invalid actions
   are rejected in-fiction: *"The Chancellor frowns — the council doesn't follow."*
   Free retry; no state change.
5. `ActionSystem.execute()` → outcome records → narration (template or luna).
6. End Turn → next tick.

Degradation ladder: any LLM failure (timeout, refusal, bad JSON after one retry) drops
that call to template voice / click-only for the turn and shows a quiet "couriers
delayed" indicator. The game is never blocked by the API. No key ⇒ permanent offline
mode, fully playable.

## 4. Slice-1 content

### 4.1 Founding ministers (fixed start; traits from `character_traits.csv`)

| Seat | Character | Traits | Ideology sketch | Role in the drama |
|---|---|---|---|---|
| Chancellor | **Aldwin Reeve**, a clerk you raised | `lowborn`, `gifted_admin`, `honest`, `patient` | centralism +40, tax_incidence +20 | Tutorial voice; loyal, plainspoken, process-minded |
| Marshal | **Ser Brandt of Harrow** | `noble_born`, `born_soldier`, `bold`, `wrathful` | militarism +70, expansionism +50, centralism −20 | The biased hawk; over-recommends force |
| Steward | **Mirella of the Weighhouse** | `merchant_family`, `shrewd_trader`, `blunt`, `cynical` | militarism −60, expansionism −40 | Counts the cost of everything; Brandt's natural opponent |
| Spymaster | **Quill** | `lowborn`, `schemer`, `paranoid` | centralism +50, orthodoxy −30 | Sees plots everywhere, including ones that don't exist |
| Chaplain | **Father Odo** | `clergy_trained`, `pious`, `compassionate` | orthodoxy +70, militarism −30 | Conscience of the council; resists harshness |

Exact attribute/skill/ideology numbers land in a `founding_council.csv` during
implementation (data-driven rule). Personas are built to seed later slices: Brandt×Mirella
and Brandt×Odo are debate pairs (slice 3); Quill's paranoia feeds event/consult flavor.

### 4.2 Actions

- 8 domain actions (PRD BG-3): `TAX_RATE_ADJUST`, `LEVY_RAISE`, `GRAIN_POLICY_SET`,
  `TARIFF_ADJUST`, `CHURCH_POLICY`, `JUSTICE_SEVERITY`, `BUILD_ECONOMIC`, `SPY_MISSION`.
- 4 court actions that work without factions: `COUNCIL_CONSULT`, `CHARACTER_REWARD`,
  `CHARACTER_PUNISH`, `CHARACTER_CONFIDE`.
- Reward/punish/confide/tone apply direct opinion deltas **with reason strings** — the
  reason-string pipe (CS-2.2) ships in slice 1; ideology-signature drift arrives in slice 2.

### 4.3 Metrics and drift (v0 formulas; constants in `balance.csv`)

Treasury, tax income, admin capacity, legitimacy, unrest, grain stores, army quality,
church opinion, peasant contentment. Per tick: tax income from rate × admin capacity;
grain seasonal (harvest in autumn ticks, drain in winter); unrest/contentment respond to
tax rate, grain shortage, justice severity; legitimacy and church opinion drift toward
baselines; army quality decays slowly. Deliberately simple — just enough signal for
concerns to fire and trade-offs to be real.

### 4.4 Guided phase (year 1)

Chancellor opens every tick: seasonal framing, top concern, 2–3 suggestions with explicit
numbers and a one-line trade-off each; after execution, a plain explanation of what moved
and why. Phase framework (`Guided/Assisted/Independent` + settings override) ships;
Assisted/Independent content comes with later slices.

## 5. Testing and determinism

- **GUT**, headless: `/Applications/Godot.app/Contents/MacOS/Godot --headless -s addons/gut/gut_cmdln.gd`.
- Unit tests with hand-computed expected values for: every drift formula, action
  validation/execution, trait application in `CharacterFactory`, concern thresholds,
  suggestion validity (every generated suggestion must pass `ActionSystem` validation).
- `ResponseValidator` tests use canned model outputs (valid, malformed, hostile,
  off-schema). **No live API calls anywhere in the test suite**; `OpenAIClient` is
  faked at the `Voicer`/parse boundary.
- **Determinism harness:** run 48 ticks with a scripted input sequence and fixed seed,
  twice, in one process and across save/load; assert identical serialized state hashes.
  This test is permanent and gates every future slice.
- One UI smoke test: scene loads, a tick renders, a suggestion click executes.

## 6. Acceptance criteria

1. Fresh launch → play through year 1 (24 ticks) using both clicks and free text.
2. Guided briefings fire every tick; clicked suggestions execute with zero API calls.
3. "Raise the salt tariff by two points" (and similar) parses, validates, executes;
   nonsense is rejected in-fiction without state change.
4. Save at any tick, reload → identical state; twin-run determinism test green.
5. With no API key, the full loop works in template voice, click-only.
6. Pixel presentation: integer-scaled 640×360, pixel font, portraits + backdrop visible.
7. All GUT tests pass headless.

## 7. Build order within the slice

1. Repo scaffold: git init, `.gitignore`, Godot 4.7 project, pixel render settings, GUT.
2. Data layer: `DataRepository` + CSV parsing + fail-loud validation (tests first).
3. Engine core: `Rng` → `GameState` → drift → `ActionSystem` → concern scan →
   suggestions → `SaveLoad` → determinism harness. All headless, all TDD.
4. Template voicing + council scene: playable offline build (milestone: first playtest).
5. LLM layer: client, parse path with validator fixtures, briefing voicing; degradation
   ladder. (milestone: free-text playtest).
