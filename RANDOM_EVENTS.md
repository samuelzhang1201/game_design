# Random Events — Crown and Council

Status: Draft v1. Starter pool of 20 events + triggering rules. MVP scope (see PRD §6.5).

---

## Your event seeds — ADD IDEAS HERE

<!-- PLACEHOLDER: drop raw ideas below, one line each. Format is free — a title,
     a sentence, half a thought, anything. Claude will expand each into a fully
     spec'd event (trigger, weight, choices, effects, chain) in the pool below. -->

- (your idea here)
- (your idea here)

---

## Triggering rules

All event selection is **engine math on the seeded RNG stream — the LLM never decides what happens, only how it reads.** Same save + same seed ⇒ same events on the same ticks.

**The per-tick roll.**

1. At most **one event per tick**, rolled after the concern scan so events and council briefings can reference each other.
2. Base chance **35% per tick** (≈8 events/year — "frequent" without drowning the council). If no event has fired for **6 consecutive ticks**, the next roll is forced (pity timer, also deterministic).
3. Build the **eligible set**: every event whose `trigger` conditions are true, whose `cooldown` has elapsed, and whose `once` flag is unspent. Sample by `weight`.
4. If the eligible set is empty, nothing fires — never pad with an ill-fitting event.

**Event anatomy** (one row per event when this converts to `data/events.csv` at implementation):

| Field | Meaning |
|---|---|
| `event_id` | `ev_snake_case` |
| `category` | `court` · `realm` · `folk` · `church` · `windfall` · `personal` |
| `trigger` | Condition expression over game state (metrics, season, traits present at court, recent actions). `always` = any tick. |
| `weight` | Relative sampling weight; state modifiers allowed (e.g. ×2 if unrest > 50) |
| `cooldown` | Min ticks before this event can repeat (default 96 ≈ 4 years) |
| `once` | If set, fires at most once per campaign |
| `choices` | 2–3 options, each a bundle of concrete engine effects (gold, metric deltas, opinion deltas **with reason strings**, trait/relation changes, scheduled follow-ups) |
| `signature` | Ideology signature per choice — minister reactions come free through the existing opinion-drift math, no special code |
| `voice` | `template` (no API call) · `mini` (routine scene) · `flagship` (rare set-piece) |
| `chain` | Follow-up events scheduled N ticks out, conditioned on the choice made |

**Design rules** (inherited from `COUNCIL_SYSTEM.md`, non-negotiable):

- **No unforeseeable catastrophes.** A single event may sting; it may never cripple. Severe consequences only arrive at the *end of a chain* the player saw start and chose to ignore.
- **Choices are buttons first** (zero LLM parse cost), free text always allowed.
- **Ministers react through the standard opinion math.** Every choice carries a signature; a pious Chaplain resents your comet-scoffing for the same deterministic reason he resents a church tax. Reason strings on every delta.
- **Repetition guard:** cooldowns + `once` flags + the recent-line memory in the voicing prompt. Roughly a third of the pool should be `once` set-pieces so campaigns stay surprising.
- Where a state check adds flavor (a `bold` ruler option, a `silver_tongued` minister interjecting), gate the *option's availability* on the trait — never roll hidden dice the player can't see.

---

## Starter pool (20)

### EV-01 · A Gift of Geese — `folk · template`
**Trigger:** `always`, weight 2. **Scene:** A farmer whose boundary dispute your courts settled walks the length of the hall and presents you with two geese, "for the fairest lord since the old king." The court holds its breath to see what you do.
**Choices:** ① Accept with thanks — peasant contentment +2, `humble`/`compassionate` ministers +2 *(approves: humility)*. ② Feast the court on them tonight — small gold cost, court opinion +2, `vain` ministers delighted. ③ Decline curtly — peasant contentment −2, legitimacy −1.

### EV-02 · The Steward's New Cloak — `court · mini · chain-starter`
**Trigger:** Steward seated ≥ 24 ticks, weight 3 (×3 if Steward has `venal`). **Scene:** Your Steward arrives at council in a fur-lined cloak worth half a village's yearly tax. He says it was a bargain.
**Choices:** ① Have him investigated (`CHARACTER_INVESTIGATE`, free this once) — if `venal`: skimming exposed, recover gold, his opinion −20 *(resents: accused)*; if `honest`: it was his mother's inheritance — opinion −10, `integrity`-heavy ministers −4 *(disapproves: baseless accusation)*. ② Say nothing — if `venal`, treasury leak worsens quietly (chain: EV-02b "The Missing Tithe" in ~24 ticks). ③ Compliment it publicly — his opinion +8, but if `venal` the skimming grows bolder.

### EV-03 · Duel at Dawn — `court · mini`
**Trigger:** two courtiers with `temper` > 60 or trait `wrathful`, weight 3. **Scene:** An insult over seating precedence, gloves thrown; a duel is set for dawn and half the court has money on it.
**Choices:** ① Forbid it — both parties −4 *(resents: honor denied)*, court order preserved. ② Allow it — winner gains `honoured`-style glow, loser risks `maimed` or `disgraced` (weighted heavily toward wounded pride, per the no-rage-quit rule). ③ Decree it be settled by wrestling before the whole court — both −2 dignity, court opinion +3, the story gets retold for years (recurrence guard: `once`).

### EV-04 · The Marshal's Parrot — `folk · mini · once · chain-starter`
**Trigger:** Marshal seated, year 2+. **Scene:** A returning sea captain gifts the Marshal a parrot — which, it emerges at council, has learned to repeat fragments of whatever it hears. The Spymaster wants it strangled today. The court adores it.
**Choices:** ① Keep it — court opinion +3; chain: in ~12 ticks the bird recites something compromising at the worst moment (small scandal, random minister −5). ② Give it to the church as a curiosity — Chaplain +4, Spymaster +2 *(approves: caution)*. ③ Strangle it — Spymaster +4, court opinion −3, `compassionate` ministers −3.

### EV-05 · A Petition of One — `realm · mini`
**Trigger:** unrest > 30 or `JUSTICE_SEVERITY` recently raised, weight 3. **Scene:** An old widow slips past the heralds and kneels before the throne: the local reeve has been taxing her village twice and pocketing the difference. The Chancellor stiffens — petitions have a *process*.
**Choices:** ① Hear her now — peasant contentment +3, legitimacy +1, Chancellor −3 *(resents: process bypassed)*; reeve punished (small gold recovered). ② Send it through channels — Chancellor +2; chain: 50/50 the case dies in paperwork → village grievance (+unrest in that province). ③ Hang the reeve by sundown, unexamined — `tax_incidence −40, centralism +30` signature; bold, popular, and `integrity`-heavy ministers −4 *(disapproves: no trial)*.

### EV-06 · Rats in the Granary — `realm · template`
**Trigger:** grain stores below threshold, autumn ticks, weight 4. **Scene:** The granary master reports droppings, gnawed sacks, and a cat found dead of overwork.
**Choices:** ① Buy grain abroad — gold cost, problem solved. ② Ration through winter — peasant contentment −4, grain stretched. ③ Borrow from church stores — grain solved, Chaplain −3 and `orthodoxy +20` signature debt: the church will mention this favor again (chain: repayment request in spring).

### EV-07 · The Salt Road Bandits — `realm · mini · chain-starter`
**Trigger:** any tariff/tax raised within last 24 ticks, weight 3. **Scene:** Merchants petition: bandits now work the coast road — the same road they've been using to route around your salt duty. They want patrols; they do not want to discuss why they were on that road.
**Choices:** ① Fund patrols — gold upkeep, trade income +, merchants +. ② Raise the tariff to pay for the patrols — the irony is not lost on anyone; trade income short-term +, smuggling worsens (chain: EV-07b black market grows). ③ Hire the bandits as toll-keepers — `cynical` ministers +4 *(approves: realpolitik)*, `integrity`-heavy ministers −5, cheap, and genuinely effective. Story gold.

### EV-08 · The Two-Headed Calf — `folk · mini · once`
**Trigger:** year 1+, weight 2. **Scene:** A calf with two heads is born in a border village. By the time the news reaches court it has become an omen: *two heads, two kings.* The Chaplain wants it burned. Your Steward notes, mildly, that scholars in the capital would pay to study it.
**Choices:** ① Burn it publicly — church opinion +3, `orthodoxy +40` signature, scholars sigh. ② Send it to the scholars — `orthodoxy −40`, small prestige with the learned, Chaplain −4 *(disapproves: omen indulged)*. ③ Eat it at a feast to show contempt for superstition — `bold` option; court half-scandalized, half-delighted; legitimacy +1 if it lands, peasant murmurs either way.

### EV-09 · The Bridge That Fell — `realm · mini · chain-starter`
**Trigger:** any `BUILD_ECONOMIC` completed within last 48 ticks, weight 3. **Scene:** The new bridge went down under a wool cart — one drowned ox, no drowned people, and a very awkward question: the builder swears he built to the plans he was paid for. The plans he was paid for appear to have been… economized.
**Choices:** ① Full inquiry — someone at court skimmed the works budget (deterministic pick: `venal` trait holder if present); exposure + recovery, their faction affinity +. ② Rebuild quietly, ask nothing — gold cost, court relieved, the skimmer emboldened (chain: next build 20% over cost). ③ Make the builder eat the cost — cheap, unjust; builders' guild remembers (future build costs +10%), `integrity` ministers −3.

### EV-10 · The Wandering Prophet — `church · mini · chain-starter`
**Trigger:** unrest > 40 or peasant contentment < 40, weight 3. **Scene:** A barefoot preacher is drawing crowds in the market towns. His sermon is simple: God made the harvest, so who exactly does the crown think it's taxing? The Chaplain demands his arrest. The crowds grow either way.
**Choices:** ① Arrest him — unrest spike now, crowds disperse over ~8 ticks; risk of martyr chain if contentment stays low. ② Ignore him — he becomes a standing grievance-feeder (faction formation pressure +) until conditions improve. ③ Debate him yourself, in public — set-piece; outcome deterministic on your legitimacy + Chaplain's `sk_diplomacy`: win = legitimacy +3 and the crowd's respect, lose = he quotes you for a decade. `flagship` voice — this is a moment that matters.

### EV-11 · The Unclaimed Cargo — `windfall · mini`
**Trigger:** coastal province owned, storm season, weight 2. **Scene:** A storm beaches a merchantman on your coast. Salvage law is clear: the cargo — silk and silver — is yours. Three days later its owner arrives, ruined and on his knees.
**Choices:** ① Keep it all — gold ++, `integrity` ministers −3, foreign merchants note it (trade income small −). ② Return it — merchant becomes a devoted contact abroad (chain: trade opportunity in ~48 ticks), `honest` ministers +4. ③ Keep half as "salvage fee" — gold +, nobody fully happy, nobody truly wronged; the pragmatist's option.

### EV-12 · A Vein of Silver — `windfall · mini · once`
**Trigger:** year 2+, weight 2. **Scene:** Miners chasing a played-out seam break into a fresh vein of silver — directly beneath land held by one of your noble courtiers, who learns of it roughly an hour after you do.
**Choices:** ① Crown claims the mine — gold income ++, `centralism +50, tax_incidence +30` signature; the noble −15 *(resents: land seized)*, `noble_born` ministers −5. ② Split the proceeds — gold income +, noble +8, everyone watches how you treat your own. ③ Waive the crown's share entirely — noble +20 and a `debt` relation formed (he owes you, and the graph remembers), treasury gets nothing.

### EV-13 · The Chaplain's Manuscript — `church · mini · once`
**Trigger:** Chaplain seated ≥ 48 ticks. **Scene:** A treatise is circulating in the seminaries, unsigned but unmistakably in your Chaplain's hand. If he is `pious`: it scolds the crown for worldliness, by name. If `cynical`: it is quietly, dangerously reformist. Either way, it is *good* — which is the problem.
**Choices:** ① Suppress it — Chaplain −8 *(resents: censored)*, church opinion stabilized. ② Endorse it publicly — Chaplain +10, `orthodoxy` signature swings by its content (±40), the hierarchy takes notes. ③ Laugh it off at dinner — nothing moves now; the manuscript keeps circulating (chain: it resurfaces in a faction demand if orthodoxy grievance forms).

### EV-14 · An Offer of Marriage — `court · mini`
**Trigger:** courtier with `merchant_family` in candidate pool or at court, weight 2. **Scene:** The house of a shipping magnate offers a dowry that would refloat your treasury — in exchange for marrying into one of your noble courtiers' families. The noble in question would rather drown.
**Choices:** ① Arrange it (`COURT_MARRIAGE`) — gold ++, kinship link formed (grievance transmits along it, per the relation rules), the noble −10 *(resents: blood cheapened)*, `noble_born` ministers −3, merchant favor +. ② Decline gracefully — nothing lost, merchant family notes the snub. ③ Counter-offer a lesser cousin — half the dowry, a tenth of the outrage.

### EV-15 · The King's Double — `folk · mini · once · chain-starter`
**Trigger:** legitimacy > 40 (it's affectionate mockery, not sedition), year 2+. **Scene:** A tavern actor has been doing *you* — the walk, the pauses, the way you rub your ring when the Steward talks — and he is, reportedly, extremely good. Half the court has secretly been to see it.
**Choices:** ① Punish him — `temper` satisfied, court opinion −3, peasant contentment −2, the act becomes underground and sharper. ② Ignore it — nothing now; the act mellows into fondness (legitimacy +1 over time). ③ Hire him for the ceremonies you hate — court opinion +4, `vain` ministers scandalized then envious; chain: in ~24 ticks a visiting dignitary addresses the wrong king (`once` set-piece, pure comedy, small diplomatic wrinkle).

### EV-16 · Night of the Comet — `folk · template · once`
**Trigger:** any tick, year 1+. **Scene:** A comet hangs over the capital for a week. Every minister has an opinion; every one of them is delivered to you with total confidence. (Template voicing showcase: each line tinted by `piety` — the pious see judgment, the `cynical` see a rock.)
**Choices:** ① Call for prayers (`HOLD_FESTIVAL`, vigil mode) — church opinion +3, `orthodoxy +30` signature, small gold cost. ② Commission the scholars to chart it — `orthodoxy −30`, the learned +, Chaplain mutters. ③ Say nothing and let it pass — the ministers' recorded predictions quietly become ammunition: whoever guessed rightest gains a little standing at council.

### EV-17 · The Hunt Gone Wrong — `personal · mini · once`
**Trigger:** autumn tick, Marshal or `bold` courtier at court. **Scene:** A boar hunt in your honor. The beast breaks the line and comes straight at the royal party — and for one long second, everyone is watching to see what you do.
**Choices:** ① Stand and take it — `bold` option; glory (legitimacy +2, Marshal +6 *(approves: courage)*), small chance of a wound (weighted to minor, per the no-rage-quit rule). ② Let the huntsmen handle it — sensible; a courtier saves you and a `friend` relation forms with him (the graph remembers who stood their ground). ③ You were never in danger, because you skipped the hunt for paperwork — Chancellor +3, Marshal −3 *(disapproves: softness)*, the court jokes about it for a season.

### EV-18 · A Debt Comes Due — `realm · mini`
**Trigger:** any outstanding `LOAN_TAKE`, treasury below threshold, weight 4. **Scene:** Your lender's agent arrives — polite, apologetic, and immovable. The house that holds your paper has troubles of its own, and it is calling in loans. Yours is the largest.
**Choices:** ① Pay in full — treasury −−, credit intact, future loan terms improve. ② Renegotiate — Steward's `sk_steward` sets the terms you get; interest up, crisis deferred. ③ Default — gold kept, future loans near-impossible, and the lender's family enters the relation graph with a grievance that does not decay quickly. The Steward puts his head in his hands.

### EV-19 · The Orphan of the Old Line — `personal · flagship · once · chain-starter`
**Trigger:** year 3+, legitimacy < 60. **Scene:** A monastery writes: they shelter a child, seven years old, whom the villagers swear is the grandson of the king your line replaced. The abbot believes them. The child, they add, is gentle, and good at letters, and knows nothing.
**Choices:** ① Take him as a ward — `compassion` +, court murmurs; long chain: he grows up at your court over decades — loyal heir-adjacent asset or a claimant your enemies court, steered by how you treat him (post-MVP chain hooks into factions/succession). ② Leave him to the monastery, watched — safe, cold; Spymaster approves, `compassionate` ministers −2. ③ Exile the child abroad — the problem leaves; the story of it stays (legitimacy −2, `integrity` ministers −4). *The one event in the pool that plants a decades-long fuse — visibly, per the telegraphing rule.*

### EV-20 · The Feast of Fools — `court · mini · once-per-4-years`
**Trigger:** winter tick, court opinion < 70, weight 2. **Scene:** The old custom: one day a year, a jester rules from the throne and the king pours the wine. The Chancellor calls it a waste of a working day. The Chancellor is outvoted by everyone, including, historically, most kings.
**Choices:** ① Hold it — gold cost, court opinion +5, peasant contentment +2; the jester issues one real mock-decree (engine picks a small reversible policy tweak — keep it for a year and the court adores you, reverse it at no cost). ② Hold it, but you stay on the throne — misses the point; half the benefit, `humble` ministers −2 *(disapproves: pride)*. ③ Cancel the custom — Chancellor +3, everyone else −2, and the jester's farewell couplet about you is, regrettably, memorable.

---

## Coverage notes

- **Voicing spread:** 3 template (free), 15 mini, 2 flagship (EV-10 debate, EV-19 orphan) — consistent with the cost posture in PRD §7.
- **Chain-starters:** 7 events schedule follow-ups, so campaigns accumulate history instead of resetting each tick.
- **Every seat gets events in its domain**; `venal`, `honest`, `bold`, `vain`, `wrathful`, `cynical`, `pious`, `merchant_family`, `noble_born` traits all have at least one moment to matter.
- At implementation this converts to `data/events.csv` + `data/event_choices.csv` + per-event effect handlers, per the data-driven convention in `CLAUDE.md`.
