# Development axes: Renaissance and Chivalry (2026-10-12)

Status: design, awaiting owner review. Scope: sub-projects A (the two axes) and B (rulers' preference, AI realms). Sub-project C (the equipment system) is out of scope here; §9 lists what A leaves for it.

## 1. Owner's words (the brief)

- **Renaissance (文艺复兴):** weapons gain power and efficiency, bombards (射石炮) improve, the free market improves; religious stability weakens and the people's obedience falls, so protests follow and the player must placate them.
- **Chivalry (骑士精神):** army morale, fighting strength and spirit improve, taxation improves, officials' loyalty, religious stability and the people's obedience rise; but it has a cost (the design proposes it, §4).
- Development is carried out by decreeing laws and policies, and rests on a set of measured data. Past a threshold, events come from an event pool per axis and change the game and the relations between characters.
- Every major character has a hidden development preference. For an AI realm whose ruler has one, the realm develops accordingly.
- From this: military units' people and equipment are modelled apart; weapons, uniforms, formations and tactic options are attachments on a unit; each weapon gets its own document; the owner wants realism. (Sub-project C.)

Rulings from the brainstorm (owner, 2026-10-12):
- The two axes are **independent measures**, not one slider. A realm can hold both.
- Chivalry's costs: **rejection of ranged weapons and gunpowder, the field bound by honour, heavy cavalry's high upkeep.** Nothing else is added.
- A score **drifts monthly by the laws in force**; it is not bought with points.

## 2. State

- `GameState.development`: per realm `{renaissance:int, chivalry:int}`, each 0..1000 (whole numbers; no floats in the save, invariants 2 and 7).
- Per realm and axis: the confirmed tier, and the set of tiers whose event has fired (so a tier fires once, and hysteresis can hold a tier).
- Every change to a score goes through one function that takes a reason string (invariant 4).

## 3. Data (all in `data/`, none in scripts)

| Table | Holds |
|---|---|
| `development_axes.csv` | per axis and tier: lower bound, hysteresis width, label |
| `development_tier_effects.csv` | per axis and tier: the modifiers, in the channel vocabulary of `law_effects.csv`, each with a reason; plus `unlock` rows (§9) |
| `law_effects.csv` | two new channels, `dev_renaissance` and `dev_chivalry`: the monthly drift each law value gives |
| `data/realm/balance.csv` | start scores, the monthly decay of an untended score, thresholds of the preference match (§6) |
| `data/council/character_traits.csv` | two new columns, `dev_renaissance` and `dev_chivalry` (−100..100) |

New tables are listed in `data/tables.csv`. No tuning number lives in this spec; each is a named key.

New channels the tier effects need beyond the existing ones: firearm and bombard power, the cost and friction of adopting a new weapon, ranged-arm effectiveness, heavy-cavalry upkeep, and the honour bounds on battlefield options. Each is a channel in the same vocabulary, consumed by the system it names (`BattleSystem`, `ArmySystem`, `OrderCosts`).

## 4. The two axes

| | Renaissance | Chivalry |
|---|---|---|
| Gains | bombard and firearm power and cost efficiency, the free market (tariff, merchant income, output), craftsmen and scholars | morale, fighting strength (heavy-cavalry charge above all), tax collection, officials' loyalty, church opinion, the people's obedience |
| Costs | church opinion falls; the people's obedience falls, so unrest and protest | ranged arms and gunpowder are shunned: the cost and friction of adopting them rise and their effectiveness falls; the field is bound by honour: fewer tactic options (no ambush, no killing prisoners, a truce to keep), so wars drag; heavy cavalry costs much to raise and keep |
| Placating | decrees on the existing `church_opinion` / `peasant_contentment` / `unrest` channels: relief, church endowment, tolerance, feast days | none; the cost is carried in the budget and the gap to rivals' arms |

The two axes pull on different things, so a realm can raise both and pay both costs.

## 5. How a score moves

1. Each law value contributes a monthly drift on each axis through the new channels. The existing military laws `quarter`, `ransom`, `truce_days`, `envoys` feed the chivalry channel.
2. Candidate new laws (to be finalised in the plan): Renaissance side: patronage of scholars, guild charter, arsenal decree, tolerance edict; Chivalry side: knightly orders, tournaments, heavy-cavalry levy.
3. Buildings, characters (a patron, a master of horse) and event effects may add or subtract, each with a reason.
4. An untended score decays slowly toward its start by the balance key.
5. The month-end settlement sums the drifts in a fixed order, clamps to 0..1000, then looks up the tier. Every drift line and every tier modifier carries a reason shown in the LEDGER.

A tier is held with hysteresis: it changes only when the score passes the bound by the table's width, so a score sitting on a bound does not flicker.

## 6. Rulers' hidden preference (B)

- A character's preference on each axis is the sum of their traits' two new columns, clamped to −100..100. No separate stored number.
- It is **hidden**. The player sees it only through behaviour: the laws that ruler decrees, court talk, and intel (the existing intel layer).
- **Court relations.** An official's opinion of a ruler moves with how close their preferences are, and with which law the ruler decrees: a decree on an axis the official favours or opposes carries an opinion delta with a reason (invariant 4), through the existing ideology-signature path. The player's own ministers therefore split by which axis the player pushes.
- **AI realms.** Only the player's realm has laws, an economy and couriers; a foreign realm has a ruler (a `Character` with the `crowned_head` trait and the realm's code as `kingdom`), regiments and `EnemyAi`. So a foreign realm holds the same two scores but has **no `LAW_SET` state**: each month its score takes one step toward a target set by its ruler's preference (target and step are `balance.csv` keys; the step is a whole number, so the move is deterministic). The step carries a reason naming the ruler. The tier effects and the threshold events of §4 and §7 read a foreign realm's score the same way as the player's. The model only voices; the engine decides (invariant 1). (Revised during planning, 2026-10-12: the first draft had the AI decree laws.)
- A change of ruler changes the target laws. Succession itself is post-MVP; this design only reads the preference from "the current ruler".

## 7. Events

- An upward crossing of a tier bound draws one event from that axis's pool for that tier, once per realm per tier. A downward crossing draws from a decline pool.
- The pools are two new sections of `RANDOM_EVENTS.md` (Renaissance, Chivalry). Each entry keeps the `### EV-NN` heading and `**Scene:**` prose the runtime parses, and adds an axis and tier label line. **Every event's prose is hand-written; no model writes an event.**
- The draw uses the engine's one seeded RNG. Choices carry action signatures and costs like any event choice.
- AI realms reach the same thresholds; their events produce only visible diplomatic or war consequences (an embassy, a border incident, a marriage offer).

## 8. Determinism and the invariants

- Integer arithmetic throughout; a fixed iteration order over realms, axes and laws; the settlement runs inside `Game.advance_day` at the month's end and reads no wall clock.
- The simulation classes stay `RefCounted` and name no `scripts/ui/` or `scripts/llm/` class (invariant 3).
- Prose never names a kingdom: events say `{player_realm}`, `{neighbor_realm}` and so on (invariant 5).
- Each executed order that changes a law already carries a cost through `order_costs.csv` (invariant 8).

## 9. The interface left for the equipment system (C)

- `development_tier_effects.csv` may hold `unlock` rows pointing at an equipment or formation id. With no equipment system built they are valid and unread.
- The adoption penalty of Chivalry (§4) is already a channel; C reads it when a unit takes a ranged or gunpowder attachment.

## 10. Out of scope

- The equipment, uniform, formation and tactic attachments, their 3D models, and one document per weapon (sub-project C, its own brainstorm, spec and plan).
- Succession and aging of rulers.
- The look of the development panel (goes through `visual-review` when built).

## 11. Tests (hand-computed, per the project rule)

- Drift: a given law set and start scores give an exact score after one and after twelve months.
- Tier lookup with hysteresis: a score crossing a bound upward then back inside the width keeps the tier.
- Preference: a given trait set sums and clamps to the exact preference; the opinion delta of a decree matches the signature formula.
- Event draw: a fixed seed draws the same event; a tier fires once; a decline crossing draws from the decline pool.
- AI law selection: a ruler with a given preference ends on the expected law values; same save and inputs give the same state.
- Every score change in the ledger carries a non-empty reason.
- Save round trip keeps scores, tiers and fired tiers.

## 12. Open items for the owner

1. Tier names and how many tiers (the design assumes four: budding, rising, flourishing, zenith).
2. The final list of new laws (§5.2).
3. How fast an AI realm moves its laws toward its ruler's preference.
