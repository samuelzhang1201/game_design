# The prologue in three acts — design

Status: APPROVED DESIGN (owner, 2026-10-05), section by section in conversation. Not built.
Scope: the story structure of the MVP's one chapter — what each act tells, the 36-month calendar, how the three arcs' beats are laid out, how the prologue's endings hand over to the rest of the chapter, and what the chapter asks of the systems still to be built. The systems themselves (factions, the chapter framework, raid defense) keep their own specs per PRD §6; this document states only what the story needs from them.

## 1. Owner rulings behind this design

| Date | Ruling |
|---|---|
| 2026-10-04 | The MVP is ONE chapter: the prologue (`docs/design/CHAPTER_0.md`, *The Bond of the Louthton*), expanded so the three arcs of PRD §7 play inside it. There is no separate Chapter 1 in the MVP. |
| 2026-10-04 | Three years, three acts. Act I is the existing twelve-month Louthton story, unchanged as the tutorial. |
| 2026-10-05 | The prologue's four endings become the **close of Act I**, not of the chapter; they decide where Act II starts. A new chapter close is written. |
| 2026-10-05 | **Staggered climaxes that converge**: the raid is Act II's mid-chapter trial, the hungry crowd is a pressure across Years 2–3, Tomas is the final climax in Year 3. No two big climaxes land in the same month. |
| 2026-10-05 | **Malvern dies as an authored beat in the winter of Year 2**, the hinge into Act III. Not an aging system (post-MVP). |
| 2026-10-05 | Acts II–III run on **fixed anchors plus state-triggered beats**, with the PRD's pacing guardrails. |
| 2026-10-05 | The third of the three riders in *The Empty Winter* wears the **Weighhouse** colours (the queen's house). |
| 2026-10-05 | **Aymer** (Tomas's son, 17) becomes a full character: a `roles.csv` row and cast art (chip + full figure). |

Unchanged hard rules: every word is authored, never model-written (`Voicer.voice_event` has no API path); forks sit on choices, never on hidden dice; an arc is telegraphed before it turns dangerous; no single event cripples a campaign; authored prose never names a kingdom (invariant 5).

## 2. Structure and calendar

A tick is a month. The chapter is 36 months.

| Act | Months | Fixed anchors | State-triggered |
|---|---|---|---|
| **I · The Bond of the Louthton** | 1–12 (Year 1) | The existing chain, unchanged; months 9–12 the harvest, the last reckoning and one of four endings as the **act close** | none — all scheduled (the tutorial) |
| **II · The Rising Wind** | 13–24 (Year 2) | m13 the act opener; **m20–21 the raid**; **m23–24 Malvern's death**, into Act III | Tomas's faction grumbling → petition → obstruction; the hungry crowd rising; warnings and readiness before the raid |
| **III · The Reckoning** | 25–36 (Year 3) | m25 the act opener (the funeral); m33 the northern letter; **m36 the chapter's deadline** | Tomas's faction conspiracy → revolt, or defused; the hungry crowd resolved |

Rules:
- **Chapter close** fires when all three arcs are resolved, or at month 36 (the deadline rule, §5.2).
- **Game over** (deposition) is possible only in Act III: the faction reaches conspiracy no earlier than month 25.
- **Guardrails** (PRD CH-5): an arc idle for 12 months is pushed one beat; no arc resolves before Year 2.
- **Empty months**: a month with a chapter beat rolls no ambient event. Acts II–III carry about 9–11 beats each, so roughly half their months belong to the random pool and to the player's own work on the map.

## 3. Act I — what changes

The 21 existing beats keep their prose and choices. Three things change.

### 3.1 The endings close the act
C0-13…C0-16 keep their text and flags. After "The reign goes on" the game shows an **Act I close card** ("Act I · The Bond of the Louthton"), and C0-20 is scheduled for month 13.

### 3.2 Who leaves the court leaves it in the engine
A new event-effect op moves a character off the court, with a reason, optionally vacating a seat (§7.1). Used by:
- **C0-13 A Just Beginning**: the Chancellor is taken; the chancellor seat is vacant. Act II asks the player to fill it — PRD Step 4's recruitment, which unlocks after Year 1.
- **C0-09 accept (the betrothal)**: Ysolde leaves for the north at C0-20 (month 13).
- **C0-14 The Compromising King**: Tomas gives up the wardenship and retires to his estates — off the office, not off the board. He stays a character and a faction leader.

### 3.3 Tomas's faction is founded at month 13, from the act close
In Act I Tomas moves only through authored beats (the withheld grain included); the faction system does not run for him. C0-20 founds his faction (§7.3) according to the ending:

| Act close | Faction starts at | Starting members | Also |
|---|---|---|---|
| **C0-16 The Empty Winter** (`coup_pending`) | **petition** (stage 2) | the three riders: Ashvale (Corina), Harrow (Edgar), Weighhouse — the Queen as a provisional member, hidden from the player until C0-27 | highest power; Edgar and Corina's feud makes the faction's cohesion low, the player's lever for `FACTION_SPLIT` |
| **C0-13 A Just Beginning** (`aymer_resentful`) | grumbling (stage 1), deepest grievance | Tomas alone; recruits later | the chancellor seat vacant; Aymer's grudge waits for Act III |
| **C0-14 The Compromising King** (`tomas_retired`) | grumbling, low power, slow | Tomas alone | the smuggling never came out: the Chancellor is still Tomas's partner and a likely insider |
| **C0-15 The Iron Crown** (`brotherhood_underground`) | grumbling | Tomas alone | its weight falls on the hungry crowd: the Brotherhood is underground |

Who holds the Louthton's keys (`c0_warden_tomas` / `c0_warden_crown` / `c0_warden_split`) adds to or takes from the faction's power: grain is leverage.

### 3.4 Prerequisite, not solved here
The bond's four figures are met almost without trying (CHAPTER_0.md §11: ~16,200 gold and ~51,800 stores from doing nothing), so *The Empty Winter* is rare. Rebalancing the bond is its own task and a prerequisite for §3.3 to play out.

## 4. Act II · The Rising Wind (months 13–24)

New beats continue the prologue's ids: Act II is C0-2x, Act III C0-3x (`c0_20` … in `data/chapter_events.csv`).

| Id | Title | When | What happens | Who |
|---|---|---|---|---|
| C0-20 | The New Year's Council | m13 · anchor | Opens Act II in four variants keyed by the act close (a `branch:` table), showing the state Year 1 left. A vacant chancellor seat opens recruitment; a betrothed Ysolde leaves for the north; the faction is founded (§3.3) | the council; **the Queen's first appearance**; Malvern, failing |
| C0-21 | The Muster in the West | m14 · anchor | Quill's muster report (`fact_raider_muster` reaches the king): **arc 3 opens**. Choices set the opening posture — scouts, an inquiry through Envoy Petra, or drills at once | Spymaster, Marshal, Petra; Osric only in the report |
| C0-22 | The Princess Comes Home | m15 · anchor | Nora returns from the army for the war council: father and daughter, stepdaughter and Queen, heir and uncle at one table. Choices: give her the western command, keep her at court as heir, or send her back to the ranks | **Nora's first appearance**, Marshal, Queen, Tomas |
| C0-23 | The Formal Petition | faction ≥ petition | Tomas and Corina put an **explicit demand** before the council, drawn from their positions (restored noble privilege, or lighter noble taxes). The clearest warning the arc gives | Tomas, Corina, Edgar |
| C0-24 | Open Obstruction | faction ≥ obstruction | Orders begin to fail. **Linked to the raid**: before the raid, levies from the faction's lands come in short | Tomas, Corina, Marshal |
| C0-25 | The Hungry Gap Again | m18 · anchor | The valley's second hungry summer: **arc 2 heats up**. Four variants by Act I — the chartered guild carries it (`c0_charter*`), a list from the cells (`c0_cassian_held`), the martyr's followers (`c0_martyr`), the underground (`brotherhood_underground`) | Cassian, Steward, Tessa, Chaplain |
| C0-26 | Sermons in the Market Towns | unrest or contentment past their lines | Cassian draws crowds again. **EV-10 joins this chain** and leaves the random pool | Cassian, Chaplain, Chancellor |
| C0-27 | The Queen's Counting-House | `coup_pending`, or the treasury short | The Weighhouse moves — a loan or a squeeze. If the third rider was theirs, the Queen chooses: her husband, her house, or both in secret | Queen, Steward, Tessa |
| C0-28 | The Spears Come | m20–21 · anchor | The raid, in four tiers (PRD RD-1); the prose names what the player did (Nora's command, Hale's walls, Edgar's levies) | Marshal, Nora, Hale, Edgar |
| C0-29 | After the Raid | m22 · anchor | The aftermath: glory (Nora's or the Marshal's prestige, Tomas held in check) or a burned border (unrest, and Tomas makes use of it). **Arc 3 resolves here** | by outcome |
| C0-30 | The Old Man's Last Night | m23–24 · anchor | Malvern dies; **Act III begins**. His bequest, one of three: the list of the faction's members (the Spymaster can now watch the conspiracy), a warning about Tomas, or a promise to guard Nora's succession | Malvern, the king, Nora |

Eleven beats, four state-triggered: about 9–11 in a given playthrough. The raid lands at m20–21, before Malvern's death and Act III, so it never meets Tomas's revolt.

## 5. Act III · The Reckoning (months 25–36)

### 5.1 Beats

| Id | Title | When | What happens | Who |
|---|---|---|---|---|
| C0-31 | The Funeral | m25 · anchor | Malvern is buried and the council realigns; the bequest takes effect; Corvin sings the lament, which shows where the crowds stand; Tomas stands at the graveside | the council, Nora, Tomas, **Corvin's first appearance**, Ysolde (home for the funeral if she went north) |
| C0-32 | The Conspiracy | faction ≥ conspiracy | Seen only if a Spymaster sits and his coverage catches it, or with Malvern's list; otherwise the next beat comes without warning. Choices: arrest, confront, concede fully, strike first | Spymaster, Tomas, Corina |
| C0-33 | His Father's Son | `aymer_resentful`, or faction ≥ conspiracy | Aymer chooses: carries his father's letters, comes over to the king, or is held as a hostage | Aymer, Tomas, Nora |
| C0-34 | Open Revolt | faction ≥ revolt | Civil war; the rebels' provinces defect. The engine decides it (faction power against legitimacy and army, PRD FS-3): won = arc 1 **crushed**; lost → C0-35 | Tomas, Marshal, Nora, Hale, Edgar |
| C0-35 | Deposition | faction ≥ deposition | **Game over**, with its own authored scene and card | Tomas, the king |
| C0-36 | Between Brothers | Tomas's opinion high and every promise kept | Arc 1 **reconciled**. One candle again, answering C0-12 | Tomas, the king |
| C0-37 | The Duke Alone | faction split or dissolved | Arc 1 **marginalized**: Tomas without allies, out of politics | Tomas, Corina, Edgar |
| C0-38 | The Valley's Answer | arc 2's resolution conditions | Arc 2 resolves in three variants: **fed** (grain and contentment held above their lines for a run of months; the lines and the run are `chapter_arcs.csv` data), **suppressed** (scars carried into the close), **co-opted** (Cassian inside the crown's order) | Cassian, Chaplain, Tessa, Ysolde |
| C0-39 | A Letter from the North | m33 · anchor | {neighbor_realm}'s queen writes; Petra takes her leave. The hook for the chapter after the MVP; the Emperor's plight is in the letter | Petra; Isabeau and the Emperor in the letter |
| C0-40 | The Chapter's Close | all arcs resolved, or m36 | One paragraph for the Act I close, one per arc outcome, one hook; the chapter-close card | all |

### 5.2 The deadline rule
- **From month 33, forced escalation**: a faction standing at obstruction or conspiracy makes its move — C0-34 is forced, so the chapter ends on its climax rather than trailing off.
- **At month 36, anything unresolved resolves**: a faction at petition or below → arc 1 *marginalized*; arc 2 by its metrics at that moment → *fed* if over its lines, else *suppressed* (written as a crowd quiet because it has to be).
- **Fairness**: deposition can only come in Act III, and only after the player has seen the petition and the obstruction. The conspiracy can be missed only by a king with no Spymaster seated and no Malvern list — the price of that empty seat (PRD FS-2, COUNCIL_SYSTEM.md §Factions).

## 6. The cast across the chapter

Every one of the 21 characters, and Aymer, has a part:

| Who | Act I | Act II | Act III |
|---|---|---|---|
| the king | every beat | every beat | every beat |
| Tomas | the Warden; the bond; the last reckoning | faction founded; petition; obstruction | conspiracy, revolt / reconciliation / isolation |
| Queen Victoria | — | **first appears** C0-20; C0-22; her choice in C0-27 | the close |
| Princess Nora | — | **first appears** C0-22; the raid | the funeral; Aymer; the revolt |
| Lady Ysolde | the ledger's margin; the betrothal | leaves (if betrothed) | the funeral; the valley's answer |
| Aymer | the corridor; the act close | — | **C0-33** |
| Chancellor | the smuggler | gone (C0-13) or Tomas's insider | — |
| Marshal | the riders; the withheld grain | muster; the raid | the revolt |
| Steward | the ledger; the gap; the harvest | the second gap; the counting-house | — |
| Spymaster | the investigation | the muster report | the conspiracy |
| Chaplain | the prisoner | the sermons | the valley's answer |
| Corina, Edgar | — | the riders; petition; obstruction; Edgar in the raid | conspiracy; isolation; revolt |
| Malvern | the tutor | **dies** C0-30 | the funeral, the bequest |
| Hale | the side chamber | the raid | the revolt |
| Cassian | the Brotherhood's voice | the second gap; the sermons | the valley's answer |
| Tessa | the charter | the second gap; the counting-house | the valley's answer |
| Corvin | — | — | **first appears** C0-31 |
| Osric | — | the muster (report); the raid | — |
| Petra | the betrothal | the inquiry (C0-21) | the letter |
| Isabeau, the Emperor | behind the ledger's seal | — | the letter (C0-39) |

## 7. What the story needs from the systems

### 7.1 Event system — small, first
- **A leave-court op** in `EventEffects`: moves a character off the court with a reason (invariant 4), optionally vacating a seat. Used by C0-13 (the Chancellor), C0-09/C0-20 (Ysolde), C0-30 (Malvern).
- **New `TriggerDsl` clauses**: a faction's stage (Tomas's faction ≥ a stage), an arc's state, and whether a character is at court.
- **Anchors need nothing new**: `chapter_events.csv` already schedules a beat by `start_tick`.
- **EV-10** is taken out of the random pool (its trigger becomes `never`) and fired by the arc-2 chain.

### 7.2 Chapter framework (PRD Step 6)
- The three arcs in `data/chapter_arcs.csv`; every resolution condition is data (CH-1).
- The guardrails, the month-33 forced escalation and the month-36 deadline rule are data, not code.
- The Chronicle (CH-3): each arc's stage and what moved it.
- Cards: the opening title card (CH-4), the Act I close card, the chapter-close card, the game-over card. Acts II and III open with their opener beats, not cards.

### 7.3 Factions (PRD Steps 5 and 7)
- An event effect can **found a faction** with a starting stage and members (C0-20), including a member hidden from the player (the Queen under `coup_pending`).
- Dwell times re-set in months so the story's windows hold: petition no earlier than m15, obstruction no earlier than m18, **conspiracy no earlier than m25**, revolt no earlier than m28. The numbers belong to the faction spec.

### 7.4 Raid defense (PRD Step 8)
- The raid is an anchor (C0-28, m20–21).
- Its tier reads Act II's preparations: C0-21's posture, C0-22's choice for Nora, C0-24's levy shortfall, and the readiness actions (RD-2).

### 7.5 Content and art
- 21 new beats: prose in `game_story/chapter_0/chapter_0_events.md`; choices, branches and outcome lines in `chapter_events.csv`, `chapter_event_choices.csv`, `chapter_branches.csv`, `templates.csv`.
- Art: 21 event illustrations (the existing `V-` pipeline), 4 cards, and **Aymer** (a `roles.csv` row, a `K-` library entry, chip and full figure).
- `CHAPTER_0.md` becomes the chapter's design document for all three acts; PRD §7 points to it and to this spec.

## 8. Phasing, in the order the systems arrive

1. **Now**: the leave-court op and the seven beats that need no new system — C0-20, C0-21, C0-22, C0-25, C0-30, C0-31, C0-39 (C0-20's faction founding waits for 2).
2. **With factions**: C0-23, C0-24, C0-32 … C0-37.
3. **With the chapter framework**: the deadline rule, C0-38, C0-40.
4. **With raid defense**: C0-28, C0-29.

PRD §6's order is unchanged; this spec is the content those steps deliver.

## 9. Testing

`tests/engine/test_chapter_zero.gd`'s exhaustive walk grows to the three acts and checks:
- every new beat is reachable;
- every outcome of every arc is reachable;
- every path closes the chapter by month 36;
- no game over before month 25;
- every deposition is preceded by the petition and the obstruction;
- same save + same inputs ⇒ same chapter (determinism).

## 10. Out of scope, recorded

- Rebalancing the bond's four figures (§3.4) and the grain crisis's numbers (arc 2 needs real pressure in C0-25).
- Re-setting event cooldowns and `action_since` windows written for half-month ticks.
- `diplomacy.csv` contradicts the story (Corwyn neutral to the player's realm; Brackmoor a vassal of Irongate); the table is written by the Azgaar import, so the fix is in Azgaar or a hand-maintained override table, not a hand edit.
- EV-19's hint that the Valorin line replaced an older one.
- EV-10 firing while Cassian is in the cells: needs a way to clear a flag, or an OR in `TriggerDsl`. Moot once EV-10 leaves the pool (§7.1).
