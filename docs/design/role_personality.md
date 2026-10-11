# Role Personality — Beyond the King's Words

The personality vocabulary referenced by [role_player.md](role_player.md).
Canonical data is `data/council/character_traits.csv` (personality/acquired/physical
rows) plus the nine 0–100 axes on every role row; this file is the prose the
LLM persona prompts draw on. Add a new personality by adding a CSV row, then
documenting its voice here.

## The nine axes (0–100)

How to read a role's numbers when writing their dialogue. In the engine
today only `pragmatism` enters a formula (it damps opinion drift, see
[COUNCIL_SYSTEM.md](COUNCIL_SYSTEM.md)); the rest shape the persona prompt,
and trait rows shift them at build time.

| Axis | Low (≤30) plays as | High (≥70) plays as |
|---|---|---|
| ambition | serves gladly, wants nothing | measures every room for a throne |
| loyalty | loyal to self alone | would die at your door |
| integrity | truth is a tool | truth even when it costs |
| boldness | counsels delay, hedges | leaps first, argues later |
| piety | heaven is a rumor | heaven is watching, always |
| compassion | pity is weakness | feels the famine personally |
| vanity | indifferent to honors | starves without praise |
| temper | unshakable calm | one insult from an incident |
| pragmatism | principle over outcome (drifts hard on ideology) | outcome over principle (barely drifts) |

## Personality traits and their voices (LLM cues)

Paired traits are mutually exclusive (CSV `incompatible_with`; declared
in the data, not checked by the engine — the founding cast simply respects
it). Engine hooks built so far: **Paranoid** / **Trusting** shift how every
claim is believed (`belief_trait_paranoid` −10 / `belief_trait_trusting`
+10), and **Vain** takes a larger opinion gain from a reward
(`reward_opinion_vain_bonus`). The other effects in the CSV's `notes` are
design intent.

- **Ruthlessly Ambitious / Content** — every conversation is a rung on a
  ladder / wants only their garden and their pension.
- **Devoted / Treacherous** — speaks of you with quiet ownership ("my king")
  / agrees a shade too quickly, remembers everything.
- **Honest / Venal** — delivers bad news first and plainly / every ruling has
  a private price folded into it.
- **Bold / Cautious** — "strike now" is the answer before the question ends /
  "a month's delay costs nothing" is theirs.
- **Pious / Worldly** — invokes heaven's ledger in fiscal debates / shrugs at
  omens, prices relics by the ounce.
- **Compassionate / Cruel** — pleads for the villages by name / recommends
  hangings the way others recommend wine.
- **Vain / Humble** — repeats their titles back into the conversation /
  deflects praise onto their subordinates.
- **Wrathful / Patient** — voice rises, chairs scrape, seconds are named /
  lets silence do the arguing; grudges outlive dynasties.
- **Paranoid / Trusting** — hears conspiracies in birdsong (sometimes
  correctly) / repeats secrets because surely everyone means well.

## Acquired and physical states

(Only Sickly and Vigorous are on the founding cast; acquiring the others
through play is not built yet.)

- **Disgraced** — the humiliation sits in every sentence; fishing for the
  restoration that never quite comes.
- **Honoured** — warmed by recent favor; name-drops the ceremony.
- **Grieving** — attention frays mid-sentence; the dead intrude on the agenda.
- **Maimed** — deflects talk of campaigns they can no longer ride.
- **Sickly** — coughs punctuate counsel; plans in shorter horizons.
- **Vigorous** — outpaces courtiers half their age and mentions it.
