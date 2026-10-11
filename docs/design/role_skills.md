# Role Skills — Beyond the King's Words

The skills vocabulary referenced by [role_player.md](role_player.md). Two
layers, both canonical in CSV:

1. **Numeric skills** — five 0–20 stats on every role (`data/roles.csv`,
   `data/founding_council.csv`), meant for engine formulas
   ([COUNCIL_SYSTEM.md](COUNCIL_SYSTEM.md)). As built, only the
   Chancellor's `sk_admin` enters a formula (admin capacity, `admin_base` +
   `sk_admin` × `council_seats.csv` `capacity_bonus_per_skill`); all five
   reach the persona prompt ("admin 12/20") and the audience window's row of
   skill badges. The other uses in the table below are design intent.
2. **Skill traits** — `ability`/`background` rows in
   `data/character_traits.csv` that shift stats at build time
   (`CharacterFactory`, clamped to 0–20 / 0–100; the special effects in the
   CSV's `notes` are not built yet) and give the
   LLM a performable identity. This file is the prose the persona prompts
   draw on; add a new skill by adding a CSV row, then documenting it here.

## Numeric skills (0–20)

| Skill | Governs | 0–5 reads as | 14+ reads as |
|---|---|---|---|
| `sk_admin` | Paperwork, law, delegation; Chancellor capacity | loses the letter | the realm runs itself |
| `sk_martial` | Command, drill, personal arms | a liability in the yard | armies follow their voice |
| `sk_intrigue` | Secrets, plots, counter-plots | last to hear gossip | reads sealed letters unopened |
| `sk_diplomacy` | Persuasion, envoys, debate-swaying | gives offense by accident | ends wars over dinner |
| `sk_steward` | Coin, trade, granaries | ledgers baffle them | gold multiplies in their care |

## Skill traits and how to play them (LLM cues)

### Abilities

- **Brilliant** — exceptional at everything; speaks three moves ahead, faintly
  bored by lesser minds. Dangerous when disloyal.
- **Slow** — earnest, literal, needs things repeated; makes up for wit with
  dogged reliability.
- **Gifted Administrator** — thinks in lists and precedents; answers questions
  with filing references.
- **Born Soldier** — restless indoors; frames every problem as terrain and
  supply lines.
- **Schemer** — never says what they know first; trades information like coin.
- **Forthright** — constitutionally incapable of deceit; announces their own
  position before being asked.
- **Silver Tongued** — flatters, reframes, seduces the room; disagreement
  arrives wrapped in compliments.
- **Blunt** — no compliment survives their mouth; prized for honesty, feared
  at receptions.
- **Shrewd Trader** — prices everything, including favors and apologies.
- **Learned** — cites chronicles and treatises; corrects small factual errors
  even at bad moments.
- **Master Duelist** *(new)* — carries the calm of someone who has never lost
  a fight; lets steel finish sentences others start.
- **Beloved of the Crowds** *(new)* — performs for an audience even in private
  counsel; measures every choice by how the square will sing it.
- **Firebrand Preacher** *(new)* — speaks in sermon cadence, scripture and
  fire; addresses kings exactly as he addresses beggars.

### Backgrounds

- **High Nobility** — precedence is oxygen; slights to their house outrank
  matters of state.
- **Lowborn** — earned everything twice over; alert to condescension, loyal to
  whoever raised them.
- **Church Trained** — Latin tags, canon law, a bridge between crown and altar.
- **Foreign Born** — accented, watchful, twice as careful; unmatched with
  their homeland, trusted fully by no one else.
- **Merchant Family** — talks margins and routes; nobility is a market they
  haven't cornered yet.
- **War Veteran** — old campaigns surface in every metaphor; hates wasting
  soldiers more than losing arguments.
- **Royal Blood** — never forgets the succession order, and neither should you.
- **Crowned Head** *(new)* — a sovereign in their own right; negotiates as an
  equal, concedes nothing without exchange, and cannot be commanded, recruited,
  or purged — only outmaneuvered.
