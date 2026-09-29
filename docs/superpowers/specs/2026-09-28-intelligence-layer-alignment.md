# The intelligence layer — alignment with Crown and Council

Status: ALIGNMENT DRAFT (2026-09-28). This is the owner's proposal
"情报层战斗系统设计 — Our Grand Ages" (Sep 25, 2026, @Samuel), restated
against THIS repository: what already exists, the gaps, and the shape it
takes here. It is not yet an implementation plan. Each phase in §8 gets
its own spec and plan when it starts.

The proposal's thesis is unchanged. Combat does not set the game apart by
how battles resolve. It sets it apart through the information layer between
the player and the field. The player never sees the true battlefield, only
reports. Those reports are late, imprecise, and bent in a direction by the
person who wrote them. The core decision stops being "how do I fight" and
becomes "whom do I believe, and what will I pay to know".

## Owner rulings (2026-09-28)

1. **The intelligence layer is in the Chapter 1 MVP.** It is required, not
   a stretch goal. PRD §6/§7 must be amended (§9).
2. **The player's OWN army is blurred too.** A regiment is drawn where the
   last report that has REACHED the court puts it, not where it truly
   stands (§5.5).
3. **Raid defense is the entry point** (confirmed 2026-09-29, §6).
4. **There is no physical fog** (owner 2026-09-29: 游戏并没有所谓物理实体
   '迷雾'，地图始终是亮的开的，只是信息被模糊化了). The map is always lit
   and open everywhere: ground, towns, roads, borders and houses are never
   darkened, shrouded or hidden. What is blurred is INFORMATION: where a
   host stands, how many it has, what a place holds. Wherever this document
   says "blur", it means a figure, a position or a piece, never the land.
5. **The tutorial is required** (owner 2026-09-29). Chapter 0 teaches the
   layer (§6).

## 1. The proposal's baseline vs this repository

The proposal was written against a different baseline. These corrections
apply wherever it is read.

| Proposal says | This repository |
|---|---|
| "Our Grand Ages" | Crown and Council |
| Command → Sim → `GroundTruthEvent[]` | `ActionSystem` / `Game.try_execute` → `TickEngine.advance_day` / `advance` → state + `WorldLedger` lines. There is no event stream to annotate; §5.1 adds one. |
| 80 nations, 1000 provinces, 200 years, an AI-vs-AI harness | The `beria` pack: 8 nations, a reign of about 60 years, no enemy AI. Capacity is not a concern (§7). |
| "The camera does not rotate" | The 3D camera turns (right-drag, `Map3DCameraRig.turn_by`) and eases back to north. The war-table metaphor survives. The WAR ROOM screen can hold north. |
| 41 traits | 45 in `data/character_traits.csv`, plus per-character attributes (`ambition`, `loyalty`, `integrity`, `boldness`, `sk_martial`, `sk_intrigue`, ...). |
| 32–128 px sprites | A 3D map with 3D wargame pieces. Paper, seals and board art come from the Flux pipeline (`missive_art.csv`). |
| `rng.stream(&"intel")` | Invariant 2 allows one seeded stream. The layer draws hash-derived values from (seed, subject, source, day), as `Weather` does, so intelligence rolls never shift the economy's draws (§5.2). |
| "Chapter 1 'Grey Wheat Winter' is fully scripted" | Chapter 0 (the prologue and tutorial, `CHAPTER_0.md`) is fully scripted. Chapter 1 is PRD §7's three arcs. |

## 2. What already exists

| Proposal layer | Exists as | Verdict |
|---|---|---|
| Transit (couriers, delay, roads, season) | `CourierSystem`: Dijkstra on `RoadGraph`, stretch kind × height tier × `Weather`, orders apply on delivery, stale orders set aside | ✅ Outbound only (gap G3) |
| Scouts | `SpySystem` (`SPY_SEND`): one quality roll, estimates with width and bias | ⚠️ Anonymous, bias not directional (G2) |
| The letter pile | The Missive board (`MissiveScreen`, `MissiveLog`, four columns, a reading desk, flying envelopes) | ✅ The form is right |
| The map does not show the truth | `Map3DContext.regiments()` draws only the player's regiments; `dev` draws all | ✅ For enemies (they are simply absent) |
| Tiers of knowledge | `Intel.level` full / general / basic; `Intel.fact` shows words or the newest estimate | ⚠️ Newest wins (G4) |
| "Who lied" learning loop | `ClaimLedger` (kept / caught, `lie_caught_trust_penalty`), `SourceTrust`, `KnowledgeBase` with a `source`, `Belief.score` | ⚠️ Built for dialogue only |
| Trait-driven reliability | `honest` (`truthful_advice`), `treacherous` (`double_agent`), `venal`, `bold`, `cautious`, `paranoid`, `vain`, `schemer`, `blunt`... | ⚠️ Data only: no code reads `truthful_advice` or `double_agent` |
| Seats | `council_seats.csv`: 9 seats including `spymaster` (`SPY_MISSION`, not wired to `SpySystem`) | ⚠️ |
| LLM writes structured voice | Invariant 1; missives call no model | ✅ The same philosophy |
| WAR ROOM | A placeholder tab (`BottomBar.PLACEHOLDER_TABS`) | Room for it (§5.9) |

## 3. Gaps, most severe first

- **G1: No ground truth worth hiding.** `ArmySystem.battle_odds` is called
  by nothing but its test. There is no battle event, and there is no enemy
  AI. Foreign regiments stand still (`spy_system.gd:130`). Observation has
  nothing to observe. The proposal says "do not change the Sim", but our Sim
  has no hostile movement at all.
- **G2: Sources are anonymous, and bias is symmetric noise.** A spy's report
  is one quality roll. Bias applies only to rumours, as `randi_range(-b, b)`.
  No person stands behind a claim, so no personality bends it.
- **G3: Information does not travel back.** A spy's report and a delivery
  receipt reach the crown on the day the courier ARRIVES AT HIS TARGET
  (courier-core ruling: "he never rides back"). Orders travel; knowledge
  teleports. Ruling 2 cannot be met without a return leg.
- **G4: Belief is "newest wins".** `Intel._latest` keeps only the newest
  missive for each subject. Two contradicting letters sit on the board, but
  every card shows one of them and nothing says they disagree.
- **G5: Regiments have no commanders.** `regiments.csv` has no commander
  and no code links a regiment to a character. There can be no boastful
  general, and no Interpretation layer.
- **G6: Own pieces are drawn at the TRUE position**, walking the engine's
  next day (`CourierSystem.day_ahead_of`, `Map3DUnits.along_day`). This
  contradicts ruling 2.
- **G7: No debrief.** Nothing sets claims beside the truth afterwards. The
  board caps each column at 40 letters, so an old claim a debrief needs can
  already be gone.
- **G8: No interception (sub-project C).** It is deferred with enemy AI and
  has no spec.

## 4. Positioning (context, not mechanics)

- **The model is Palantir Gotham's COGNITIVE model**: multi-source fusion,
  provenance, timeliness, contradiction. The Missive board is already
  Gotham's Target Workbench shape: a kanban of stages. The council proposing
  legal `action_code`s for the player to approve is AIP's "three courses of
  action, human approves". The game INVERTS Gotham's promise. Gotham sells
  certainty. The game is about having none.
- **Never name Palantir or Gotham in anything public.** There is the
  trademark. There are also the company's controversies in 2023–2026:
  immigration-enforcement contracts, surveillance warnings, the Maven
  strikes. Say "you never see the true battlefield" and "every report has
  an author".
- **The moat is not hidden information itself.** EU5 speaks of
  information delay.
  Espiocracy, a Cold War intelligence grand strategy game, is announced for
  2027. The moat is **people as sources, with directional bias, exposed in a
  debrief**. No shipped game combines the two: Suzerain's biased ministers
  are hand-scripted, and Paradox reports never lie. Build those two hardest.
- **The audience is CK3 × Suzerain × Radio General**, not the modern mil-sim
  crowd of Command: Modern Operations. Pure command-delay titles sit at
  250–2,000 Steam reviews. Narrative-wrapped imperfect information reaches
  about 11k (Suzerain).
- **Two known failure modes in the market:**
  - Order delay divides players; Grand Tactician added an off switch.
  - Uncertainty without feedback reads as blank; Radio Commander was
    criticised for it.
  - The answers are the blur-level setting (§5.5) and the debrief (§5.7).

## 5. The shape here

### 5.1 Ground truth: sightings

The simulation stays as it is. Each day, `TickEngine.advance_day` also
emits **sightings**: engine-side records of what happened and where. It
returns them the way it returns `day_arrivals`, never inside the tick's
return value.

Sighting kinds for Chapter 1:
- `host_seen`: a regiment or raid host at a point, with its heads, arms and
  heading.
- `host_passed`: a host crossed a road stretch or a province.
- `clash`: two hosts met, with sizes, losses and outcome.
- `burned`: a manor was raided.

Every sighting names its **observable fields** and each field's
**difficulty**. That is the proposal's "observability metadata", present
from the first line of code. Sightings are ground truth. They are archived
(§5.7) and never shown to the player except in the debrief and in DEV MODE.

### 5.2 Observation and Distortion: claims

**Observation** is deterministic. For each sighting, it asks who was placed
to see it, and what share of the fields that person gets. By distance and
role, candidates are:
- a regiment's commander;
- a spy sent there;
- the province's house (its lord);
- a town's merchants, through the guild;
- the church, through the parish.

**Distortion** turns an observation into a **claim**. A claim is a missive
with a `source` (a character id, or a class such as `merchants` or
`hired_scout`), `subject`, `fields`, `observed_day`, `arrived_day`,
`confidence` (0..1000), and `distortions` (codes; hidden until the
debrief).

Reliability is whole permille computed from what already exists:
- a base value;
- the source's skill for the subject (`sk_martial` for arms, `sk_intrigue`
  for plots, `sk_steward` for stores);
- `integrity`;
- `loyalty`;
- trait terms;
- a large penalty when the claim IMPLICATES the source (his own defeat, his
  faction's friend).

All weights live in `balance.csv` `intel_*`.

Directional biases are a new table, `data/intel_distortions.csv`. Its
conditions are written in the `TriggerDsl` language, so no bias is code:

| code | When (existing traits and attributes) | Effect |
|---|---|---|
| `glory` | (`vain` or `bold` or `ambition` ≥ 60) and the source fought | own gains ×1300–2000‰, own losses ×500‰ |
| `blame` | (`schemer` or `integrity` < 35) and a defeat | cause rewritten: "no relief came", "the ground was against us" |
| `silence` | `treacherous`, `loyalty` < 30, or the subject is the source's faction or friend | no claim at all |
| `hedge` | `cautious` | figures rounded against the crown, "at least..." |
| `alarm` | `paranoid`, a first battle, or morale broken | enemy size ×1500–3000‰; `paranoid` may invent a sighting |
| `honest_dull` | skill for the subject ≤ 5 | no direction, but a wide estimate |

Chapter 1's cast already covers the table, with no new traits needed:
- **Ser Brandt**, marshal (`bold|wrathful`, ambition 55, integrity 45): `glory`.
- **Quill**, spymaster (`paranoid|schemer`): `alarm`, sometimes an
  invented host.
- **Captain Hale** (`blunt|loyal_devoted|humble`, integrity 65): accurate.
- **Duke Tomas** (loyalty 25, `amb_ruthless`): `silence` whenever the raid
  serves his faction.
- **Lord Edgar**, a border lord (`blunt|bold|veteran`): close to true, with
  a slight `glory`.

The `truthful_advice` and `double_agent` flags finally get readers.

The rule the proposal ends on still holds: **a bias must be learnable.** The
same source with the same traits in the same situation bends the same way.
Only its magnitude is drawn, from the hash (§1).

### 5.3 Transit: the return leg

A claim is written where the source stands. It reaches the court only when
its messenger has ridden `CourierSystem`'s roads to the capital, at the same
pace, weather and fees as the outbound courier.

This OVERTURNS courier-core's "he never rides back" for REPORTS:
- a spy rides home with his report;
- a commander sends a rider;
- a delivery receipt comes back with the man who delivered it.

The Missive board fills when letters ARRIVE, and the envelope flies then.
Loss and interception wait for sub-project C, which this layer pulls into
the MVP only as far as §6 needs.

### 5.4 Belief: accounts may disagree

Belief is DERIVED: rebuilt from the claims that have arrived, and not saved
on its own. The one exception is the player's own verdicts ("archived",
"I believe this one"), which are saved state.

For each subject it keeps EVERY live claim, not the newest:
- **Cards keep the 2026-09-28 ruling.** The headline is the newest
  estimate, with its source and date.
- **A card may now also carry "Accounts differ"** with the others listed
  beneath it, each with its source.
- **The system never picks the true one. The player does.**

The ghost states are the proposal's:
- FRESH, then CORROBORATED;
- DECAYING, then CONTESTED;
- STALE (?), then ARCHIVED, or FRESH again.

A ghost's uncertainty radius is `base(source) + speed(host) × days since
seen`, in whole metres. A column of horse therefore spreads faster than
foot.

### 5.5 The map draws belief (rulings 2 and 4)

- **The land is never hidden.** There is no shroud, no darkened or
  greyed-out region and no "unexplored" state. The whole map stays lit and
  open at every zoom, abroad as at home. Only the PIECES and the FIGURES
  carry uncertainty: where a host is drawn, how solid it looks, the ring
  under it, and the words and ranges on its card.
- **Own regiments.** A regiment is exact and live, walking the day as now,
  only when the blur-level setting allows it. Otherwise it stands where its
  last ARRIVED report put it:
  - its figures fade with the report's age;
  - a chip reads "3rd Regiment · 4 days ago · the ford";
  - no walking is extrapolated.

  The engine still moves the true regiment, and orders still resolve
  against its TRUE position, so a courier finds the column where it is.
- **Enemy hosts.** A ghost: the same `.glb` piece, translucent, over its
  uncertainty ring. Two contradicting claims mean two ghosts, each wearing
  its source.
- **Lost hosts.** A STALE ghost becomes a question mark at the last known
  place until the player archives it.
- **The blur-level setting** (`intel_blur_level`, a pause-menu setting
  saved with the campaign; it blurs only the player's own regiments, since
  foreign hosts are always known only by report):
  - **0 (Clear):** own regiments live. The difficulty the market asked
    for: an off switch.
  - **1 (Home, recommended default):** own regiments live inside provinces
    the crown CONTROLS (the steward's riders are constant there), blurred
    outside.
  - **2 (Full):** every own regiment blurred, except one the king rides
    with (post-MVP).
- **DEV MODE** additionally draws the truth as a red wireframe beside every
  ghost. The playtests and the Distortion work need this.
- **The MARCH aim** starts at the BELIEVED position. The ruler says so, and
  the days it reads are an estimate.

### 5.6 Orders: intent and interpretation (after the MVP core)

MVP orders stay `ARMY_MARCH` / `ARMY_GARRISON` through couriers. Two
additions:
- The commander receiving a stale order acts by a trait table, the mirror
  of §5.2:
  - obey: `loyal_devoted` with low skill;
  - improvise: `veteran` with `sk_martial` ≥ 10;
  - ask back: `cautious`;
  - press on: `bold`;
  - drag his feet: low opinion.

  He reports his choice and his reason.
- **"The best general disobeys you and is right."** This must truly happen.
  Free-text conditional orders parsed by the model ("hold the ford unless
  their main body turns south") come after the MVP and are always validated
  into engine intents, never invented actions (invariant 1).

### 5.7 The debrief

When the truth comes out (the raid resolved, a host found, a later spy's
exact count), the WAR ROOM shows a **debrief**:
- each claim received, pinned by date beside the sighting it described;
- who inflated, who kept silent, whose letter came too late.

It draws on an uncapped **claim archive** (`GameState.intel_claims`, kept
apart from the board's 40-per-column cap; claims older than
`intel_archive_years` are reduced to their debrief line).

Every exposure:
- writes a permanent line on the source's card (a new `record_log`, a
  reason string like every other log: "Reported a 300-man skirmish as a
  great victory, summer of year 1");
- goes through `ClaimLedger` → `SourceTrust`;
- tells the source he was caught, as an opinion delta with its reason
  (invariant 4).

The player may act on it: dismiss, punish, shame, or keep him and say
nothing. These are existing `CHARACTER_*` actions.

### 5.8 Countermeasures: at least two ways to shrink each uncertainty

Every one is an order with an `order_costs` row (invariant 8).

| Unknown | A | B | C |
|---|---|---|---|
| Where the host is | `SPY_SEND` (exists) | `INTEL_ASK_GUILD`: Tessa's merchants, gold, slow, low precision | wait for the border lord's letter (free, passive) |
| How many | a spy sent closer (the risk arrives with C) | `INTEL_ASK_CHURCH`: Father Odo's parishes, church standing | compare the letters (time only) |
| Whether a report is true | a second source | the source's `record_log` (free) | `ARMY_ATTACH_OBSERVER`: a trusted courtier rides with the column (the commander's opinion) |
| Where our own column is | `ARMY_REPORT_CADENCE`: a rider every N days (fees; slower march) | a spy to our own column | the king takes the field (post-MVP: live truth there, delay everywhere else) |

### 5.9 Look

The proposal's §7 stands, translated to our dark CK3 UI:
- no percentages, bars or radars for confidence;
- confidence is ink weight;
- age is paper yellowing;
- disagreement is two letters laid side by side;
- each source kind has its own hand, as new `ui_fonts.csv` roles.

The Missive board is the letter pile. **WAR ROOM stops being a
placeholder.** It holds the belief map, north-up, with ghosts, wax-crayon
rings and the debrief wall. Art follows `no-klein`: Z-Image and Qwen side by
side for the owner.

### 5.10 The LLM

Reports are TEMPLATE prose first: `TemplateVoicer` lines keyed by
distortion code × the source's traits. The model may later re-voice a claim
from its fields, distortions and persona. It never decides a field, and a
template is always the fallback.

The proposal's abandon condition 4 is adopted: if template reports read well
enough, no model call is added.

## 6. Raid defense is the entry point (owner 2026-09-29)

PRD Step 8 already requires ONE hostile force in Chapter 1: the
{raider_realm} raid of the "Spears in the West" arc. Today RD-1 is only a
formula fired at the raid beat, with an outcome tier from army quality,
levies, readiness and "warning heeded". The PRD also puts AI opponent
kingdoms OUT of MVP scope.

The shape:
- **The raid becomes a real host on the map.** It is a regiment of
  {raider_realm} with a thin SCRIPTED plan, not a kingdom AI:

  muster → march along `RoadGraph` toward a target → strike → withdraw

  Its targets and timings are data. It emits sightings (§5.1) each day. That
  closes G1 inside the MVP's scope.
- **"Warning heeded" stops being a flag.** It becomes computed from the
  player's actual dispositions against the truth: where the crown's
  regiments stood when the host struck.
- **RD-1's tier formula stays**, with that as an input. RD-3 (every outcome
  survivable) is unchanged.
- **The arc supplies every source the layer needs:**
  - Quill's muster report (`fact_raider_muster`, already authored);
  - Brandt at the head of the army;
  - Hale's levies;
  - the border lords;
  - the guild's merchants;
  - a feint that one source swallows.
- **The arc ends in the first debrief.**

This is the proposal's P3 acceptance ("deceived → fail → exposed in the
debrief") placed exactly where the MVP already needs a battle, with no
kingdom AI and no wargame.

### 6.1 The tutorial (ruling 5)

Chapter 0 is the tutorial (`CHAPTER_0.md`). It teaches the layer once, in
full, before Chapter 1's raid leans on it, so the player has seen the loop
before it costs anything.

The loop it must teach:
1. **A letter has an author.** The first misleading letter comes from a
   person whose traits explain the lie.
2. **You can pay to know.** The first spy ride: sent from the map, the
   report riding home late.
3. **Accounts differ.** Two sourced letters disagree on one card, and the
   map shows two ghosts.
4. **The truth comes out.** The first debrief, with the source's permanent
   record line, and a choice of what to do about him.

It stays a CHAIN on the existing event system, calls no model, and keeps
Chapter 0's scripted pacing. Where possible it hangs on beats that already
point this way rather than adding new ones:
- **C0-03S "Ashes on the Louthton"** already has the Marshal report a
  burned valley "as though it were a victory". It becomes the first
  `glory` letter, a real sourced claim on the board.
- **C0-03L / C0-03A** already turn on what Quill brings back or keeps. They
  become the first spy report riding home, and the spymaster's own
  `silence`.
- **The debrief** needs a short new beat, when the burned valley's true
  toll arrives by a second source.

The exact beats, their `chapter_events.csv` rows, and whether the tutorial
stages its own small incident or borrows the raider's scouts are for the
tutorial's own spec. That spec follows P3, whose mechanics it shows.

## 7. Capacity (the proposal's P0 estimate)

- About 4–6 observers per sighting.
- A raid runs about 60 days, with 1–3 sightings a day.
- That gives at most about 1,000 claims, about 200 of which reach court.

At about 300 bytes of JSON a claim, a campaign's archive is well under 1 MB
before §5.7's reduction. The single-file save (invariant 7) is safe.

## 8. Phases

| Phase | Content | Accepted when |
|---|---|---|
| **P0** (follows sub-project B) | Missives carry a `source`; `Intel` keeps every claim per subject and cards show "Accounts differ"; the uncapped claim archive; the return leg (§5.3); the paper prototype (§10); the LEDGER's L1 (split strands, accounts differ) | A card shows two sourced, disagreeing estimates; a spy's report arrives days after he saw it |
| **P1** | Sightings (§5.1); Observation + `intel_distortions.csv`; commanders on regiments (`GameState` seeded from a hand-maintained `data/maps/<id>/commander_bindings.csv`); DEV MODE truth overlay | A GUT test, fixed seed: Brandt reports a 200-man feint as 600+ with `glory` recorded |
| **P2** | The scripted raid host (§6); belief rendering with the land always lit: own-regiment blur (§5.5), ghosts, rings, stale markers; `intel_blur_level` | Two ghosts from two sources stand on the map, and the true host (DEV) is elsewhere; no part of the ground is dimmed |
| **P3** | Template report prose; countermeasure orders (§5.8); the WAR ROOM debrief; `record_log`; RD-1 fed by dispositions; the LEDGER's M3 audit (`LEDGER_AUDIT`) beside the countermeasures | Chapter 1's raid plays through: deceived → struck → exposed |
| **P3T** | The Chapter 0 tutorial (§6.1): its own spec, chain rows, prose, art | A new reign meets all four steps of the loop before tick 11, with no model call |
| **P4** (after the MVP) | The Interpretation layer (§5.6); free-text intent orders; C's interception; the king in the field | — |

## 9. Documents that must change

- **PRD §2 / §3 / §6 Step 8.** The intelligence layer joins the MVP scope.
  Step 8 becomes "Raid defense and the intelligence layer" (RD-1..3 plus
  P1–P3). The scripted raid host is stated as NOT an AI opponent kingdom.
  §7.1's "Spears in the West" row gains the host and the debrief.
- **Build order** (PRD §6 is strict). P0 extends the just-merged sub-project
  B and can go now. P1–P3 land at Step 8. The owner confirms the placement.
- **`2026-09-27-courier-core-design.md`.** The "never rides back" ruling
  becomes "never rides back with an ORDER; a report rides home".
- **`2026-09-28-missive-board-and-spies-design.md`.** Cards may show
  "Accounts differ"; arrival is the return leg's.
- **`CHAPTER_0.md` and `chapter_0_events.md`.** The tutorial beats (§6.1).
- **`CLAUDE.md`.** Three new rulings:
  - the map draws BELIEF, not state (ruling 2);
  - there is no physical fog, and the land is always lit (ruling 4);
  - no numeric confidence appears in the intelligence UI.

  `Intel`'s "fog of knowledge" wording there means blurred figures and was
  never a visual fog.

## 10. Paper prototype, recast with our cast

Run before P1, with 2 players and 2 rounds. On a 1-page map: the west road,
the ford, the capital, the eastern manors. The player commands three
regiments of 400 each.

The truth: {raider_realm} has 1,200 men, 200 of them horse, under Osric.
- Day 1: a feint of 200 on the west road; the main body turns to the ford.
- Day 4: the host reaches the ford.
- Day 6: the ford is held or it is not.

The reports:

| Day | Arrives |
|---|---|
| 1 | Brandt: "Their vanguard, some eight hundred, struck us on the west road; we hold gloriously." (`glory`) |
| 3 | Hale: "A great deal of dust on the ford road these three days. More men than I could count." (`honest_dull`, the right direction) |
| 4 | Brandt: "Their main body is still before me; three assaults thrown back. Send men!" |
| any | Tessa's merchants, if paid 2 gold: exact, three days late |

Also: a spy costs 1 gold (at most 3); orders take 1 day to arrive; a march
takes 2. Observe and judge as the proposal's §9 says. The pass is blame
landing on a PERSON ("Brandt, you liar"). The fail is blame landing on the
system ("how could I have known"). On a fail, fall back to the mild variant:
the key question always has one reliable report for sale.

## 11. Abandon conditions (carried over)

1. **Both paper rounds fail:** the mild variant. There is always one
   reliable report to buy at a decision point; uncertainty affects detail,
   not direction.
2. **P1's logs show biases players cannot infer from traits:** collapse to
   three reliability grades.
3. **The archive outgrows the save by an order of magnitude:** reduce harder
   (§5.7).
4. **Template reports already read well enough:** do not add the model.

## Open questions for the owner

- **The default blur level:** 1 (Home) is recommended.
- **P0 now, or with Step 8?**
