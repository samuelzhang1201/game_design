# Random Events — Beyond the King's Words

Status: Built — the 30 events below are live (`data/story/events.csv`, `data/story/event_choices.csv`, `EventSystem`). MVP scope (see `docs/design/PRD.md` §6, "Random events pool"). **This file is loaded at runtime:** `StorySource` reads each `### EV-NN` heading and the prose after the Scene label on that line, and the game shows that prose verbatim. Keep the headings and the Scene labels intact; the Trigger text on the same line is design description only (the implemented trigger is the CSV's). The heading's TITLE — between the `·` and the trailing `— \`tags\`` — is what the audience window's banner shows, so it is authored here too, not in `templates.csv`.

---

## Your event seeds — ADD IDEAS HERE

<!-- PLACEHOLDER: drop raw ideas below, one line each. Format is free — a title,
     a sentence, half a thought, anything. Claude will expand each into a fully
     spec'd event (trigger, weight, choices, effects, chain) in the pool below. -->

- (your idea here)
- (your idea here)

---

## Triggering rules

All event selection is **engine math on the seeded RNG stream — the LLM never decides what happens, and never writes how it reads.** Every event story is the fixed, authored Scene prose below; `Voicer.voice_event` has no path to the API and no event prompt exists. Same save + same seed ⇒ same events on the same ticks. `EventSystem` is the only consumer of `state.rng` in the council slice.

**The monthly roll.** A tick is a MONTH of 30 days; the clock runs day by day under play/pause and the month's end is the tick (owner 2026-09-14: no End Turn).

1. At most **one event per tick (month)**, rolled at the month's end after the concern scan and the suggestions, so events and council briefings can reference each other. A rolled event **stops the clock** and opens the council, where it plays in the audience window; while it waits, no further event is rolled.
2. **Chains first:** a scheduled follow-up whose due tick has come fires before any roll.
3. Base chance **35% per month** (`story/balance.csv` `event_base_chance`; ≈4–5 events a year with the pity timer). After **3 quiet months** (`event_pity_ticks`) the next roll is forced (pity timer, also deterministic).
4. Build the **eligible set**: every event whose `trigger` holds, whose cooldown has elapsed, and whose `once` flag is unspent. Sample by `weight`.
5. If the eligible set is empty, nothing fires — never pad with an ill-fitting event. An event whose every choice is gated off is skipped too.

**Event anatomy** — `data/story/events.csv` (one row per event) and `data/story/event_choices.csv` (one row per choice):

| Field | Meaning |
|---|---|
| `event_id` | `ev_NN`, matching the `### EV-NN` heading here. A scripted chapter's beats live in `data/story/chapter_events.csv` instead, with their own document — see `docs/design/CHAPTER_0.md`; they share this anatomy exactly, and only differ in being fired by id off a chain rather than sampled by weight |
| `category` | `court` · `realm` · `folk` · `church` · `windfall` · `personal` |
| `trigger` | `TriggerDsl` clauses joined by `&`, any of them negatable with a leading `!`: `always`, `never` (chained only — a scripted chapter beat), `season=<Season>`, `year>=N`, `trait_at_court=<trait>`, `trait_of=<seat or character id>:<trait>` (ONE person's), `seat_filled=<seat>`, `action_since=<ACTION>:<ticks>`, `flag=<flag>`, `<metric><N>` / `<metric>>N` |
| `weight` | Relative sampling weight (a constant; state modifiers are not built) |
| `cooldown_ticks` | Min months before this event can repeat (96 on most rows — written for half-month ticks, 8 years now that a tick is a month; to be redesigned, owner 2026-09-18) |
| `once` | `1` = fires at most once per campaign |
| `voice` | Every row is `template`: the Scene prose is shown as written. The `mini` / `flagship` tags in the headings below are the original draft's voicing plan, superseded 2026-08-31 (owner: every event story is fixed, authored text) |
| `title_key` | The event's title string |
| choice `effects` | `;`-joined ops, applied by `EventEffects`: `metric:<m>:<d>[:reason]`, `gold:<d>[:reason]`, `opinion:<seat or id>:<d>:<reason>`, `attribute:<who>:<attr>:<d>:<reason>`, `rel:<from>:<to>:<d>:<reason>`, `world:<path>:<d>:<reason>` (schema-listed deltas, clamped and logged), `flag:<name>`, `schedule:<event_id>:<ticks>` (a chain), `branch:<branch_id>` (a fork: the first rule of `data/story/chapter_branches.csv` whose `requires` holds, at that rule's own delay) |
| choice signature | The five ideology columns per choice — minister reactions come free through the opinion-drift math, no special code |
| choice `requires` | Optional trigger expression gating the option (e.g. EV-17's "Stand and take it" needs `trait_at_court=bold`) |

**Design rules** (inherited from `docs/design/COUNCIL_SYSTEM.md`, non-negotiable):

- **No unforeseeable catastrophes.** A single event may sting; it may never cripple. Severe consequences only arrive at the *end of a chain* the player saw start and chose to ignore.
- **Choices are buttons first** (zero LLM parse cost), free text always allowed.
- **Ministers react through the standard opinion math.** Every choice carries a signature; a pious Chaplain resents your comet-scoffing for the same deterministic reason he resents a church tax. Reason strings on every delta.
- **Repetition guard:** cooldowns + `once` flags (there is no voicing prompt — the prose is fixed, so variety comes from the pool itself). Roughly a third of the pool should be `once` set-pieces so campaigns stay surprising.
- Where a state check adds flavor (a `bold` ruler option, a `silver_tongued` minister interjecting), gate the *option's availability* on the trait — never roll hidden dice the player can't see.

---

## Starter pool (20)

### EV-01 · A Gift of Geese — `folk · template`
**Trigger:** `always`, weight 2. **Scene:** A farmer whose boundary dispute your courts settled walks the length of the hall and presents you with two geese, "for the fairest lord since the old king." The court holds its breath to see what you do.
**Choices:** ① Accept with thanks — peasant contentment +2, `humble`/`compassionate` ministers +2 *(approves: humility)*. ② Feast the court on them tonight — small gold cost, court opinion +2, `vain` ministers delighted. ③ Decline curtly — peasant contentment −2, legitimacy −1.

### EV-02 · The Steward's New Cloak — `court · mini · chain-starter`
**Trigger:** Steward seated ≥ 24 ticks, weight 3 (×3 if Steward has `venal`). **Scene:** Your Steward arrives at council in a fur-lined cloak worth half a village's yearly tax, and calls it a bargain.
**Choices:** ① Have the Steward investigated (`CHARACTER_INVESTIGATE`, free this once) — if `venal`: skimming exposed, recover gold, the Steward's opinion −20 *(resents: accused)*; if `honest`: it was a mother's inheritance — opinion −10, `integrity`-heavy ministers −4 *(disapproves: baseless accusation)*. ② Say nothing — if `venal`, treasury leak worsens quietly (chain: EV-02b "The Missing Tithe" in ~24 ticks). ③ Compliment it publicly — the Steward's opinion +8, but if `venal` the skimming grows bolder.

### EV-03 · Duel at Dawn — `court · mini`
**Trigger:** two courtiers with `temper` > 60 or trait `wrathful`, weight 3. **Scene:** An insult over seating precedence, gloves thrown; a duel is set for dawn and half the court has money on it.
**Choices:** ① Forbid it — both parties −4 *(resents: honor denied)*, court order preserved. ② Allow it — winner gains `honoured`-style glow, loser risks `maimed` or `disgraced` (weighted heavily toward wounded pride, per the no-rage-quit rule). ③ Decree it be settled by wrestling before the whole court — both −2 dignity, court opinion +3, the story gets retold for years (recurrence guard: `once`).

### EV-04 · The Marshal's Parrot — `folk · mini · once · chain-starter`
**Trigger:** Marshal seated, year 2+. **Scene:** A returning sea captain gifts the Marshal a parrot — which, it emerges at council, has learned to repeat fragments of whatever it hears. The Spymaster wants it strangled today. The court adores it.
**Choices:** ① Keep it — court opinion +3; chain: in ~12 ticks the bird recites something compromising at the worst moment (small scandal, random minister −5). ② Give it to the church as a curiosity — Chaplain +4, Spymaster +2 *(approves: caution)*. ③ Strangle it — Spymaster +4, court opinion −3, `compassionate` ministers −3.

### EV-05 · A Petition of One — `realm · mini`
**Trigger:** unrest > 30 or the severity of justice recently raised, weight 3. **Scene:** An old widow slips past the heralds and kneels before the throne: the local reeve has been taxing her village twice and pocketing the difference. The Chancellor stiffens — petitions have a *process*.
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
**Trigger:** unrest > 40 or peasant contentment < 40, weight 3. The preacher is `char_prophet_cassian`, the man the opening narration and the prologue already name, so the choices move his opinion. **Scene:** Cassian the Barefoot — the preacher the Louthton calls by name — is drawing crowds in the market towns. His sermon is simple: God made the harvest, so who exactly does the crown think it's taxing? The Chaplain demands his arrest. The crowds grow either way.
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

## Development pool (10)

Threshold events for the development axes (`docs/superpowers/specs/2026-10-12-development-axes-design.md` §7): each fires off the crossing flag `DevelopmentSystem.move` raises, once per campaign, and is authored prose like the rest. A foreign crossing is named by the neighbour's SLOT (`dev_foreign_neighbor_realm_<axis>_up_1`).

### EV-21 · A Bombard at the Arsenal — `realm · template · once`
**Trigger:** Renaissance tier 1 reached. weight 50. **Scene:** The master smith at the arsenal has cast a bombard, a great bronze throat that took three tries and a ruined furnace to pour. He asks you to come and see it fired. The Marshal is already there, walking round it twice; the Steward has brought a ledger and is not looking at the gun at all.
**Choices:** ① Fire it before the court. ② Fund a second foundry. ③ Call it a costly toy.

### EV-22 · Scholars at Court — `realm · template · once`
**Trigger:** Renaissance tier 2 reached. weight 50. **Scene:** Three scholars have come to your hall unasked, with books under their arms and a quarrel between them over the shape of the world. They want a room, a stipend, and leave to teach the sons of the burghers. The Chancellor finds them tiresome and useful in about equal measure.
**Choices:** ① Take them under your patronage. ② Let them teach at the cathedral school. ③ Send them on their way.

### EV-23 · The Guilds Ask for a Charter — `realm · template · once`
**Trigger:** Renaissance tier 3 reached. weight 50. **Scene:** The masters of the great guilds come to the hall in their best gowns and ask for a charter: their own courts, their own measures, their own seal. They have counted the gold they bring the treasury and mention it twice. The older lords at the back of the hall have counted it too, and say nothing.
**Choices:** ① Grant the charter. ② Grant it at a price. ③ Refuse; the seal is the crown's.

### EV-24 · The Bread Riots — `realm · template · once`
**Trigger:** The realm has fallen out of Renaissance tier 1. weight 50. **Scene:** The new looms are idle, the founders have gone, and the clever men who kept the town's accounts have taken their books elsewhere. The market runs short on a Tuesday and by Wednesday there are bakers' windows broken in the lower town. The realm has lost what it had learned, and the crowd knows only that bread is dear.
**Choices:** ① Open the granaries. ② Send the watch in. ③ Say it will pass.

### EV-25 · A Tournament on the Green — `realm · template · once`
**Trigger:** Chivalry tier 1 reached. weight 50. **Scene:** The young knights of the shire have asked leave to hold a tournament on the green below the castle. They have found banners from somewhere and each has a lady whose favour he claims to wear. The Marshal says it will train the lances. The Steward says it will eat the pantry.
**Choices:** ① Host it and give the prize. ② Allow it, at their own cost. ③ Forbid it as idle waste.

### EV-26 · A Ransom in the Old Way — `realm · template · once`
**Trigger:** Chivalry tier 2 reached. weight 50. **Scene:** A knight of yours is taken in a border skirmish. His captor does not threaten him; he sends word politely that a ransom of the customary size will do, and that your man dines at his own table in the meantime. The Marshal says that is how it is done. The Steward asks how much 'customary' is.
**Choices:** ① Pay the ransom in full. ② Haggle, as one gentleman to another. ③ Let him stay where he is.

### EV-27 · The Knights Renew Their Oaths — `realm · template · once`
**Trigger:** Chivalry tier 3 reached. weight 50. **Scene:** At midsummer the knights of the realm ask to renew their oaths in a body, kneeling in the great hall with their swords laid across their palms. It is a handsome sight and an expensive one: each will want a gift of horse or harness, and each will remember what he gets.
**Choices:** ① Give each a gift of harness. ② Take the oaths and give your thanks. ③ Bind them to the muster-roll.

### EV-28 · The Archers Go Unpaid — `realm · template · once`
**Trigger:** The realm has fallen out of Chivalry tier 1. weight 50. **Scene:** Fewer of the young men ride, and fewer of the old ones can afford to. The knights complain of the price of a charger; the archers, who were sneered at on the green last spring, complain louder because they were not paid. The heavy horse is thinner than it was and the Marshal is counting heads again.
**Choices:** ① Pay the archers their arrears. ② Subsidise the heavy horse. ③ Accept a lighter host.

### EV-29 · An Embassy of Learned Men — `realm · template · once`
**Trigger:** {neighbor_realm} crosses into Renaissance tier 1. weight 50. **Scene:** An embassy from {neighbor_realm} arrives with a train of carts and, among the carts, a printing-press wrapped in oilcloth, which they present with every courtesy as a gift between friends. The envoy speaks well of their new schools. The Spymaster, at your elbow, murmurs that he would like to know who taught the envoy to speak so well.
**Choices:** ① Accept the gift and the friendship. ② Accept it, and take it apart. ③ Thank them and send it back.

### EV-30 · A Border Incident at the Joust — `realm · template · once`
**Trigger:** {neighbor_realm} crosses into Chivalry tier 1. weight 50. **Scene:** A tourney at the court of {neighbor_realm} ends badly: one of your knights, a guest, is unhorsed and calls the blow foul, and the host's champion calls him a liar. Word of it has crossed the border faster than the knights have. A marriage is hinted at in the same letter, as a way of making it all graceful.
**Choices:** ① Let your knight demand satisfaction. ② Answer with a marriage offer. ③ Recall your knight quietly.

---

## Coverage notes

- **Voicing:** as drafted, 3 template, 15 mini, 2 flagship (EV-10 debate, EV-19 orphan). As built, all 20 are `template` — authored prose, no API call (owner 2026-08-31), consistent with the cost posture in PRD §8.
- **Chain-starters:** 7 events are drafted to schedule follow-ups. As built, one chain exists: EV-02 "Say nothing" schedules EV-18 in 24 months (`schedule:ev_18:24`). The follow-ups named above (EV-02b, EV-07b, …) have no entries or scenes yet — each needs a `### EV-NN` entry here and rows in the CSVs before it can fire.
- **Triggers:** `events.csv` implements a simplified form of several triggers written above (e.g. EV-11 fires on `season=winter` with no coastal check; EV-14 on `seat_filled=steward&year>=2`, not on a `merchant_family` candidate). The CSV is what runs.
- **Every seat gets events in its domain**; `venal`, `honest`, `bold`, `vain`, `wrathful`, `cynical`, `pious`, `merchant_family`, `noble_born` traits all have at least one moment to matter.
- Implemented as `data/story/events.csv` + `data/story/event_choices.csv` with generic effect ops (`EventEffects`) rather than per-event handlers, per the data-driven convention in `CLAUDE.md`; a test asserts all 20 ids resolve to a Scene here.
