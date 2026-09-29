# LEDGER M4 — battle, commanders and spoils — design

Status: designed 2026-09-30 overnight under the owner's standing order (see
`2026-09-30-ledger-supply-design.md`). **Not implementable yet**: it needs
the first hostile force the engine has ever had — the scripted
{raider_realm} raid host of `2026-09-28-intelligence-layer-alignment.md`
§6 (intel P2, PRD Step 8). This spec fixes what the LEDGER's `attacks`,
`commands` and `war_chest` rows will mean, so that P2 and M4 land as one.
**Default** marks every choice the owner has not ruled on.

## 1. What changes for the player

- A **commander** stands at the head of every regiment of the realm
  (intel P1's `commander_bindings.csv`): the LEDGER's `commands` link,
  character → regiment. He is also the regiment's REPORTER (charter rule 4
  again): his letters about the fight carry his distortions (`glory`,
  `blame`, `silence` — intel §5.2), so the LEDGER's `attacks` thread shows
  HIS account of the battle until the debrief.
- A regiment **attacks** a host it can reach: an order `ARMY_ATTACK
  {regiment, target}` — issued like MARCH (aimed at the target's BELIEVED
  position; the courier carries it), resolved when the column reaches the
  host's TRUE position within `army_attack_reach_km`, else it arrives to
  empty ground and reports so.
- The fight is `ArmySystem.battle_odds` made real (today a placeholder
  only its test calls): each side's `power` (arms, training, morale,
  terrain, height difference) → the odds; ONE draw from a hash of (seed,
  both codes, day) — never `GameState.rng` (intel §1's rule: intelligence
  and battle draws must not shift the economy's stream) → the outcome tier
  (rout / repulse / stand-off / victory / rout of the foe), whose losses,
  wounded and morale swings are `data/battle_outcomes.csv` rows.
- **Spoils**: a victory over a raid host returns what it carried —
  `battle_spoils_permille` of the host's plunder (the manors it burned,
  valued by `MapManors.value_of_line`) into the crown's `strategic` pool.
  That closes the charter's virtuous `war_chest` loop (`supplies_out` →
  `attacks` → spoils → `strategic_goods`), whose LEDGER row becomes live.

## 2. The ontology

- `enemy_host` becomes live with P2 (instances `enemy_host:<code>`, their
  figures ALWAYS belief — ghosts, intel §5.5); `attacks` regiment →
  enemy_host (flow = the heads engaged, accounts = the commander's letter,
  the spy's, the debrief's truth once out); `commands` character →
  regiment; a new `spoils` link enemy_host → strategic_goods (flow = the
  spoils of the last victory).
- The loop `war_chest` = `supplies_out|attacks|spoils`, virtuous, running
  while a regiment of the realm has won a fight in the last
  `battle_glory_days` (a TriggerDsl clause `host_victorious`).

## 3. Data

`data/battle_outcomes.csv` (tier by odds band: attacker losses permille,
defender losses permille, wounded share, morale change each side, spoils
yes/no), `balance.csv` `battle_*` (`army_attack_reach_km`,
`battle_spoils_permille`, `battle_glory_days`). The existing `army_*` power
keys stay the only strength formula.

## 4. Tests (when built)

Odds from hand-computed powers; the hash draw identical for the same
(seed, codes, day) and independent of `GameState.rng`; each tier's losses
and morale; spoils into the pool with its reason; an attack on an empty
point; the LEDGER's `attacks` thread carrying the commander's distorted
account and, after the debrief, the truth beside it.

## 5. Order of work

Intel P1 (commanders, sightings) → P2 (the raid host) → **M4** (this
spec) → P3 (reports' prose, the debrief) — PRD Step 8. The `war_chest`
loop and `enemy_host` stay planned on the LEDGER until then, drawn grey
with "lit by battle".
