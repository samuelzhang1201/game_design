# Chapter 0 — The Bond of the Louthton

Status: Built — the 21 entries below are live (`data/story/chapter_events.csv`, `data/story/chapter_event_choices.csv`, `data/story/chapter_branches.csv`, `EventSystem`). Design doc: `docs/design/CHAPTER_0.md`.

**This file is loaded at runtime.** `StorySource` reads each `### C0-NN` heading — the title after the `·` and the prose after the `**Scene:**` label on the Trigger line — and the game shows both verbatim. Keep the headings and the labels intact. The `**Choices:**` line is design description only; the implemented choices are the CSV's.

Chapter 0 is the tutorial. It is **entirely free of the model**: every scene is fixed authored prose (`Voicer.voice_event` has no path to the API), every choice is a button, every number is engine arithmetic. A player with no API key plays the whole chapter exactly as a player with one.

**The prologue never names a kingdom** (architecture invariant 5): `{player_realm}`, `{neighbor_realm}`, `{raider_realm}`, `{empire_realm}` are filled from `data/maps/<id>/realm_bindings.csv` at load. It *does* name provinces, manors and rivers, because those are the pack's own labels and a re-export keeps them.

---

## How the chapter runs

The chapter is a **chain**, not a pool. `GameState.new_campaign` schedules `c0_01` for tick 1; every choice either schedules the next entry a month or two out (`schedule:<id>:<ticks>`) or hands the decision to a branch table (`branch:<branch_id>:<ticks>`, `data/story/chapter_branches.csv`, first matching rule wins). Chained events fire before the monthly random roll, so a chapter beat always takes its month — and the months the chain leaves empty belong to the ordinary pool.

A tick is a month of 30 days (`Calendar`). The reign opens in **Spring, Year 1** and the chapter is settled at the **autumn harvest**, tick 9, with the last reckoning in the first month of winter.

| Tick | Date | Beat |
|---|---|---|
| 1 | Spring 1 | C0-01 The First Council |
| 2 | Spring 31 | C0-02 The Brotherhood of the Sheaf |
| 3 | Spring 61 | C0-03S/L/A or C0-04S/A — the path taken |
| 4 | Summer 1 | C0-05 The Ledger |
| 5 | Summer 31 | C0-06 The Duke's Offer — the bond is set |
| 6 | Summer 61 | C0-07 The Hungry Gap |
| 7 | Autumn 1 | C0-08 The Weavers' Charter *or* C0-08S The Prisoner |
| 8 | Autumn 31 | C0-09 The Northern Betrothal |
| 9 | Autumn 61 | C0-11H/C0-11T Harvest Day — **or** C0-10 The Withheld Grain, if the Warden kept the keys |
| 10 | Winter 1 | C0-12 The Last Reckoning (Harvest Day, if the carts were held) |
| 11 | Winter 31 | the ending (C0-12, if the carts were held) |
| 12 | Winter 61 | the ending, on the long road |

Obstruction costs a month: hold the king's tax carts and every beat after it lands a month later, and the year is read out in the first week of winter instead of on the threshing floor. The two shortcuts through C0-03 that never open the ledger (burning it, leaving it in Quill's box) wait two months instead of one, so the chapter keeps its calendar whichever way it is played.

## The bond

C0-06 puts four numbers on the table. They are checked once, in C0-12's branch, against the state the player actually has:

| | condition | why it is the lesson |
|---|---|---|
| The purse | `treasury>12000` | the crown's share of the realm, less the court |
| The stores | `grain>45000` | the civil pool: food, timber, cloth |
| The peace | `unrest<25` | repression is the fastest way to lose this |
| The people | `peasant_contentment>45` | relief costs goods and buys quiet |

Doing nothing for nine months leaves roughly 16,200 gold and 51,800 in stores (`tools/chapter0_numbers.gd`), so the bond is not a grind — it is a budget. Every choice below is priced against that trajectory.

## Who is who

Everyone in the chapter is a character the game already has (`data/council/roles.csv`, `data/council/founding_council.csv`); no one was invented for it.

| In the story | Character | Why them |
|---|---|---|
| The king | `you` — King Aldric Valorin, 40 | the player |
| The Warden of the Louthton | `char_duke_tomas` — Duke Tomas Valorin, 44 | the half-brother who openly covets the throne; `amb_ruthless`, `silver_tongued` |
| The king's cousin | `char_lady_ysolde` — Lady Ysolde Valorin, 27 | `beloved_of_crowds`, `trusting`: the one who would fund a bread guild and not say so |
| The Brotherhood's voice | `char_prophet_cassian` — Cassian the Barefoot, 33 | already the man rallying the hungry (`game_start.md`); `firebrand_preacher`, `compassionate`, `lowborn` |
| The Spymaster | `char_spymaster` — Quill | the seat; the investigation's branch is `chapter_branches.csv` `c0_br_spy`: a council that was heard first (C0-01) gets C0-03L, else a `schemer` Quill (the founding one is) makes C0-03A |
| The Chancellor | `char_chancellor` — Aldwin Reeve | `venal`, `schemer`: the internal-affairs minister with something hanging over him |
| The Steward | `char_steward` — Mirella of the Weighhouse | `blunt`, `shrewd_trader`: the one who knows what Reeve did, and detests him for it |
| The captain at the door | `char_captain_hale` — Captain Hale Fenwick | his `veteran` trait is what offers "let Hale strip the hall first" at C0-02; taking it is what makes C0-04S rather than C0-04A |
| The old counsellor | `char_lord_malvern` — Lord Malvern, 71 | `sickly`, opinion 70: the tutor who will not see chapter 2 |
| The northern envoy | `char_envoy_petra` — Envoy Petra Kolev | already `{neighbor_realm}`'s envoy; `schemer`, `silver_tongued` |

Places are the pack's own: **Bineterston Department**, the small grain-and-river department that borders the capital's Walbover; the **Louthton**, the river through it; **Wickleby** and **Mandfow**, its two grain manors; **Bineterston**, its walled river port. The grain went north to `{neighbor_realm}`, whose arms are a silver sickle on red — the same mark that seals the smuggler's tallies.

---

## The chain

### C0-01 · The First Council — `chapter · template`
**Trigger:** scheduled at campaign start, tick 1. **Scene:** The table is older than the kingdom and every seat at it was filled by your father. Lord Malvern rises last and slowest, one hand flat on the oak to carry his weight, and says what none of the others will: that the treasury holds what it holds, that your own province pays into your house's purse and the rest of the realm pays a share into the crown's, that the two are not the same coin and a king who confuses them is poor by midsummer. Then he sits, out of breath, and the hall waits to learn what kind of king asks the first question.

**Choices:** ① Let every office speak before I do — the whole council warms to a king who listens. ② Show me the books before the speeches — the Steward is delighted, the Chancellor considerably less so. ③ Swear them to the crown, then let them talk — the Marshal and the Chaplain approve; the Spymaster notes who hesitated.

### C0-02 · The Brotherhood of the Sheaf — `chapter · template`
**Trigger:** chained from C0-01. **Scene:** Quill does not wait to be asked. In Bineterston, he says, in the mill manors along the Louthton, there is a society — the Brotherhood of the Sheaf. Millers and weavers, a bound sheaf scratched on doorposts, and an intercepted letter that reads: when the corn is cut, the granary belongs to those who sowed it. He puts the letter on the table. At the far end, the Warden of the Louthton — your half-brother, who has held the valley's granary keys since your father's war — turns his ring once and says, with great warmth, that he will deal with it himself and the crown need never hear the word again. He is far too calm.

**Choices:** ① Send the Marshal's riders to Wickleby — obedience bought with mills. ② Quill, find out who feeds them — four hundred gold to the informers. ③ Bring their voice to me under safe conduct — the hall does not like it. ④ *(a veteran captain at the door)* Bring him, and let Captain Hale strip the hall first — the only thing standing between C0-04S and C0-04A, and the player is the one who decides it.

### C0-03S · Ashes on the Louthton — `chapter · template`
**Trigger:** chained from C0-02, suppression. **Scene:** It took two nights. The riders came back with the sheaf-marked doorposts hacked out and carried behind the saddles like trophies, and behind them, over the valley, a smear of smoke where the Wickleby mills had been. Nobody was killed, which the Marshal reports as though it were a victory. In the ash of the counting-house a serjeant found something that would not burn through: a ledger, hand-copied, bound in cracked leather, three years of the valley's harvest set down in a clerk's careful hand. He has laid it on your table and is waiting to be dismissed.

**Choices:** ① Burn it with the rest — the Chancellor sleeps well tonight. ② Read it.

### C0-03L · What the Spy Brought Back — `chapter · template`
**Trigger:** chained from C0-02, investigation, loyal Spymaster. **Scene:** Quill comes back thinner and will not sit. The Brotherhood is nine millers, two weavers and a widow who keeps the list, he says; they have been pooling grain for two hungry winters so that the oldest households eat, and there is no plot in it beyond that. Then he sets down a thick hand-copied ledger, bows his head lower than he ever has, and says the part that costs him: this has been going on for three years under his own watch, and he did not see it because he was not looking at the granary. He asks for no credit and offers no excuse.

**Choices:** ① Thank him for bringing it. ② Three years, and you saw nothing.

### C0-03A · Quill's Offer — `chapter · template`
**Trigger:** chained from C0-02, investigation, ambitious Spymaster. **Scene:** Quill finds you in a corridor rather than the council chamber, which is itself an answer. There is a ledger, he says. It is safe. It is very much safer where it is than in a king's hand, because a king must do something with what he holds, and a spymaster need only keep it. He lets the offer sit in the candlelight without naming a price, half-smiling, one hand open toward the brazier as though the whole question could be settled by a small fire and a good night's sleep.

**Choices:** ① Keep it in your strongbox — I may want it. ② I will send my own clerk — six hundred gold and a cold silence.

### C0-04S · The Preacher at the Door — `chapter · template`
**Trigger:** chained from C0-02, summons, a vigilant captain. **Scene:** Captain Hale takes the safe conduct to mean the walls as well as the road. He has the side chamber emptied, the hangings pulled back off the stone, and the barefoot preacher searched twice at the door before he is let through — which is how the second man, in the same road-dirt and the same borrowed coat, is stopped in the corridor with a short knife under his sleeve and no answers at all. So Cassian comes in alone. He does not kneel. He sets a hand-copied ledger on the table between you and says he has been waiting three years for someone to ask.

**Choices:** ① Hear him out. ② Safe conduct ends at my door — hold him.

### C0-04A · The Knife in the Side Chamber — `chapter · template`
**Trigger:** chained from C0-02, summons, no veteran at the door. **Scene:** The barefoot preacher is halfway through his first sentence when the second man comes off the wall. It is very fast and very quiet: a chair goes over, the candle goes over, and the preacher is somehow between you and the blade with both hands closed around a wrist, shouting at you to get back, which is not how either of you imagined this audience. The guards take the man in the doorway. In the mess on the floor, fallen out of the preacher's coat, there is a thick hand-copied ledger, and Cassian is looking at it rather than at his own hands.

**Choices:** ① No reprisals — find who paid him. ② Close Wickleby until the payer is found.

### C0-05 · The Ledger — `chapter · template`
**Trigger:** chained from the path taken. **Scene:** It is not a conspiracy. It is arithmetic. Three years of the Louthton valley's harvest, entered twice: once as it came off the fields, once as it was reported to the crown, and the second column is short of the first by nearly two fifths every autumn. The difference went north by river in the Chancellor's hand, sold to a queen your father died fighting, and the tallies are sealed with a silver sickle on red. The Brotherhood stole nothing. They pooled what was left. And in the margin, in a small elegant hand you have known since childhood, there are notes in blue-black ink — your cousin Ysolde has been quietly paying for the millers' grain out of her own dowry, and never once told you.

**Choices:** ① Put it before the whole council. ② The strongbox — not a word. ③ Send for my cousin first.

### C0-06 · The Duke's Offer — `chapter · template`
**Trigger:** chained from C0-05 or C0-03S/C0-03A. **Scene:** Your half-brother asks for the floor and gets it, because he always does. He has held the valley's granary keys since the northern war and he proposes, reasonably, warmly, with one open palm, to go on holding them — a crown does not count sacks, he says, a warden counts sacks. Then he gives you the way out, and the way out is a number. Let him keep the keys, or take them back and prove by next autumn's harvest that the crown counts better than he does: a full treasury, full stores, a quiet valley and a fed one. The council writes the four figures down. Malvern, who can barely hold the pen, writes them down twice.

**Choices:** ① Keep the wardenship — and show me a better ledger next autumn. ② The granaries answer to the crown from today — twelve hundred gold to install the crown's own officers. ③ Half the keys — the Steward holds the other half.

### C0-07 · The Hungry Gap — `chapter · template`
**Trigger:** chained from C0-06, the last weeks before the harvest. **Scene:** The corn is standing and green and six weeks off, and this is the stretch of the year the valley calls the gap: last autumn's grain eaten, this autumn's not yet cut, and two hungry winters behind them with nothing put by. A letter comes up from the Louthton in a schoolroom hand. It does not ask for alms. It asks for six thousand out of the crown's stores to be carried down and handed out in the mill yards, and promises it back out of the harvest with a tenth on top. The Steward says the part that matters in one sentence: a valley that cannot stand up cannot cut its own corn, and a field left standing in October is worth nothing to anybody.

**Choices:** ① Open the stores — a valley that cannot stand cannot reap. ② They may buy it at the market price. ③ The stores are the crown's.

### C0-08 · The Weavers' Charter — `chapter · template`
**Trigger:** chained from C0-07, Cassian at liberty. **Scene:** They come up the road in their own clothes and wait to be announced, which is new. The petition is a yard of parchment carrying two hundred and eleven marks — signatures, thumbprints, and a great many careful crosses — and it asks for something duller and more dangerous than bread: a charter. Let the millers and weavers of the Louthton hold their pooled grain as a chartered guild, under the crown's seal, with a warehouse and a book anyone may read. Granting it fixes the valley's trade in a season. It also says, in front of the whole court and in writing, that the Warden could not keep his own valley fed.

**Choices:** ① Grant the charter. ② A charter, and a tenth of it to the crown. ③ Refuse — they are a society, not a guild.

### C0-08S · The Prisoner — `chapter · template`
**Trigger:** chained from C0-07, Cassian held. **Scene:** They bring the petition anyway, and it is a yard of parchment with two hundred and eleven marks on it, and the man who would have carried it is in your cells writing names on cheap paper with the sheets stacked at his knee. Not a confession — a list of every household in the valley the Brotherhood fed, with what each was owed, so that if he does not come out somebody else can settle the accounts. The Chaplain has been to see him twice and will not say what was said. The charter is still the question. It is simply being asked through a grate.

**Choices:** ① Release him and grant the charter. ② Grant nothing; he stays where he is. ③ Try him for sedition.

### C0-09 · The Northern Betrothal — `chapter · template`
**Trigger:** chained from the charter. **Scene:** Envoy Petra Kolev arrives with a treaty, a compliment and a coffer. Her queen offers a grain accord, two thousand five hundred gold as a marriage portion, and a match for your cousin Ysolde — a small northern lordship, a mild husband, a long road. It is a good offer and it is meant to be. The seal on the accord is a silver sickle on red, and if you have read the valley's ledger you have seen that seal before, at the foot of every tally of grain that left your kingdom in the dark.

**Choices:** ① Accept the match and the coffer. ② Refuse — she is not a coin. ③ Take the treaty, and name the sickle at the foot of the tallies.

### C0-10 · The Withheld Grain — `chapter · template`
**Trigger:** chained from C0-09, only while the Duke holds the keys. **Scene:** The autumn carts do not come. They are loaded, they are standing in the road outside the valley castle with the oxen unharnessed and the drivers sitting in the shade, and the spearmen at the gate are in the Warden's livery, not yours. The message that comes up instead of the grain is courteous. The valley is anxious about the winter, it says; the Warden judges it prudent to hold the tax grain where it is until the crown has settled certain questions about how the valley is to be governed. Nobody in your council will say the word out loud. The word is rebellion.

**Choices:** ① The Marshal rides — two thousand gold, and the carts move. ② Treat with him — fifteen hundred gold to make the road open again. ③ Send a fair copy of the ledger to every lord in the valley.

### C0-11H · Harvest Day — `chapter · template`
**Trigger:** chained, the harvest, the valley fed through the gap. **Scene:** The bond falls due on the day the last cart comes in, and the carts are coming in heavy. The long table is cleared for the tallies of the four figures your brother made the council write down in the summer: the crown's purse, the crown's stores, the temper of the valley and the state of the people in it. Out in the Louthton they are cutting from first light with every hand that can hold a sickle, which is the difference the stores made and everybody at this table knows it. The Steward has been at the figures since before dawn and reads without looking up, the way she reads everything.

**Choices:** ① Read it out — every column. ② Walk the fields first; the figures will keep. ③ Let the Steward read it to the council without me.

### C0-11T · Harvest Day — `chapter · template`
**Trigger:** chained, the harvest, the valley left to its own gap. **Scene:** The bond falls due on the day the last cart comes in, and there are not many carts. The long table is cleared for the tallies of the four figures your brother made the council write down in the summer: the crown's purse, the crown's stores, the temper of the valley and the state of the people in it. Out in the Louthton the corn stood a week longer than it should have because there were not enough hands upright to cut it, and a field left standing in October is worth nothing to anybody. The Steward has been at the figures since before dawn and reads without looking up, the way she reads everything.

**Choices:** ① Read it out — every column. ② Walk the fields first; the figures will keep. ③ Let the Steward read it to the council without me.

### C0-12 · The Last Reckoning — `chapter · template`
**Trigger:** chained from C0-11, the first month of winter. **Scene:** He comes to you privately, which he has not done since you were boys. There is one candle on the table between you, and his hand with the ring on it lies beside it, not quite still. He does not deny the arithmetic, whether or not you have ever read it. He says — and this is the part you will remember — that he took the valley's grain because somebody had to feed the valley through your father's war, that he sold it because coin keeps and grain does not, and that if that book is ever put on the council table you will be right — and his son, who is seventeen and standing in the corridor outside, will inherit the grudge along with nothing else.

**Choices:** ① Put it on the table in the morning. ② Settle it between us — fifteen hundred gold and his resignation. ③ There is nothing left to settle.

### C0-13 · A Just Beginning — `chapter · template`
**Trigger:** ending, the bond kept and the ledger shown. **Scene:** The book goes down the long table hand to hand and nobody speaks. The Warden sits very straight while it passes him, and when it reaches the end of the table he takes off the chain of his office and sets it on the oak himself, which spares everyone the guards. The Chancellor is taken from the hall before noon. In the valley they toll the mill bells for an hour and nobody can say who started it. By the door, half in the shadow of a pillar, your brother's son watches you with a still, cold, careful face, and says nothing at all, and remembers everything.

**Choices:** ① The reign goes on.

### C0-14 · The Compromising King — `chapter · template`
**Trigger:** ending, the bond kept, the truth buried. **Scene:** It is done quietly and it is done well. The Warden retires to his estates in good health and better standing, the valley is fed, the accounts balance, and the winter passes without a single hard word. In the last week of it a woman from the Louthton comes up with the guild's book to be sealed, and Cassian walks in behind her, and he looks at you for a long moment across an almost empty hall before he asks the only question he has ever asked you: whether the men who did it are still in the room. You seal the book. He thanks you for the book.

**Choices:** ① The reign goes on.

### C0-15 · The Iron Crown — `chapter · template`
**Trigger:** ending, the bond kept from behind a line of spears. **Scene:** The figures are beautiful. The mills are rebuilt in stone at the crown's expense, the tax grain comes in on the day it is due, and the valley is as quiet as a church. Your column rides through Wickleby in the spring and not one door opens; a child watches it from behind a half-shut shutter and is pulled back by the shoulder. On the wall of the rebuilt counting-house somebody has scratched out the bound sheaf, and beside it, low down where a man would have to kneel to cut it, somebody else has scratched a new one.

**Choices:** ① The reign goes on.

### C0-16 · The Empty Winter — `chapter · template`
**Trigger:** ending, the bond broken. **Scene:** The bond was four figures and you are short. It is not a catastrophe and nobody says a word about it, which is worse: the council simply stops bringing you things. In the last week of the year three riders go out from the Warden's town house in the snow under lantern light, each with a different lord's colours on the saddle cloth, and an upper window stays lit long after the horses are gone. Malvern, who can no longer come down to the hall, sends word that you should sleep in the keep this winter and not the lodge.

**Choices:** ① The reign goes on.

---

## Branch tables

`data/story/chapter_branches.csv`, evaluated top to bottom; the first rule whose `requires` holds wins. Every table ends in an `always` rule, so no branch can dead-end.

| branch | rule | goes to |
|---|---|---|
| `c0_br_spy` | `flag=c0_council_heard` | C0-03L |
| | `trait_of=spymaster:schemer` | C0-03A |
| | `always` | C0-03L |
| `c0_br_guard` | `flag=c0_hall_searched` | C0-04S |
| | `always` | C0-04A |
| `c0_br_charter` | `flag=c0_cassian_held` | C0-08S |
| | `always` | C0-08 |
| `c0_br_tax` | `flag=c0_warden_tomas` | C0-10 |
| | `flag=c0_seed_lent` | C0-11H |
| | `always` | C0-11T |
| `c0_br_harvest` | `flag=c0_seed_lent` | C0-11H |
| | `always` | C0-11T |
| `c0_br_ending` | bond kept **and** `flag=c0_path_suppress` | C0-15 The Iron Crown |
| | bond kept **and** `flag=c0_ledger_shown` | C0-13 A Just Beginning |
| | bond kept | C0-14 The Compromising King |
| | `always` | C0-16 The Empty Winter |

Repression is checked before the ledger on purpose: burning the mills cannot be redeemed by producing the truth afterwards.

**No fork is a hidden die.** The design rule the random pool follows — gate the *option*, never roll where the player cannot see (`RANDOM_EVENTS.md`) — holds here. The knife in the side chamber is not bad luck: a veteran captain offers, in the open, to empty the room first, and C0-04A is what happens to a king who did not take him up on it (or has no veteran at his door). And the Spymaster's fork is the first hour of the reign coming back: Quill is `paranoid` and `lowborn`, and a king who let every office speak before he did has earned a straight report, where a king who called for the books and the oaths has taught him to keep his own counsel.

## Paths

Walked exhaustively by `tests/engine/test_chapter_zero.gd`, twice over — once with the year's four figures kept and once with them lost: **140,670 distinct paths**, every one of the 21 beats reached, every one of the four endings reached, no beat that leads nowhere and no beat that can have every choice gated off.

## What the chapter leaves behind

Every flag the chapter sets, and who may read it. The four the chain reads itself are marked; the rest are the record of what the player did, for chapter 1, for the random pool (`trigger: flag=...`) and for the endings' own prose.

| flag | set by | meaning |
|---|---|---|
| `c0_council_heard` | C0-01 ① | **read by `c0_br_spy`** — the king let every office speak before he did |
| `c0_path_suppress` | C0-02 ① | **read by `c0_br_ending`** — the mills were burned |
| `c0_path_investigate` / `c0_path_summon` | C0-02 ②③④ | which road was taken |
| `c0_hall_searched` | C0-02 ④ | **read by `c0_br_guard`** — the captain emptied the room first |
| `c0_ledger_held` | C0-03S ②, C0-03L, C0-03A ②, C0-04S, C0-04A | **read by three choices' `requires`** — the king has the book |
| `c0_ledger_burned` / `c0_ledger_quill` | C0-03S ①, C0-03A ① | the two roads that never open it |
| `c0_ledger_public` / `c0_ledger_secret` / `c0_ysolde_told` | C0-05 | what was done with the truth in summer |
| `c0_cassian_held` | C0-04S ② | **read by `c0_br_charter`** — the preacher is in the cells |
| `c0_attempt` | C0-04A | someone paid for a knife |
| `c0_warden_tomas` | C0-06 ① | **read by `c0_br_tax`** — the granary keys stayed in his hand |
| `c0_warden_crown` / `c0_warden_split` | C0-06 ②③ | who holds them instead |
| `c0_seed_lent` | C0-07 ① | **read by `c0_br_harvest` and `c0_br_tax`** — the valley was fed through the gap |
| `c0_charter` / `c0_charter_tithe` | C0-08, C0-08S | the Louthton weavers hold a crown charter |
| `c0_martyr` | C0-08S ③ | a preacher was tried for preaching |
| `c0_betrothal` / `c0_betrothal_refused` | C0-09 ①② | what was done with the king's cousin |
| `c0_smuggling_cut` | C0-09 ③ | the northern grain road is closed |
| `c0_ledger_shown` | C0-10 ③, C0-12 ① | **read by `c0_br_ending`** — the book was read out |
| `c0_ledger_sold` | C0-12 ② | it was sold back for silence |
| `c0_end_just` / `c0_end_compromise` / `c0_end_iron` / `c0_end_winter` | the endings | which one was reached |
| `aymer_resentful` | C0-13 | the Warden's son saw his father broken in open council |
| `tomas_retired` | C0-14 | he went quietly, with his lands and his health |
| `brotherhood_underground` | C0-15 | the Sheaf went under the floorboards |
| `coup_pending` | C0-16 | three riders, three colours, one lit window |
