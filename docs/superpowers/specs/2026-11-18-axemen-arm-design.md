# Axemen: a new shock-infantry arm

Owner 2026-11-18 (Chinese): "请把手斧和剑盾的新兵人以及动作接入游戏". Asked how the hand-axe soldier
should enter, the owner chose **a new arm** (not a per-figure mix inside the infantry, not the
artillery's stand-in). Asked what it should do, the owner asked for proposals and accepted all six
below, the "first blow" included; the card painting waits until the desktop is on.

## Intent

The sword-and-shield infantry **holds**: it keeps a line and takes a charge. The axemen **break**:
they smash shield walls and town gates, but cannot keep a line and fold under horse. The player
gets a real choice — axes to open the fight and storm towns, swords to hold and to cover the axes'
flanks — instead of a reskin.

**Goals**
- The player raises an axe regiment in the prologue through the existing recruitment panel.
- It fights by its own numbers (all in `data/`), with one new engine rule ("first blow").
- On the 3D map it is the owner's hand-axe + round-shield soldier with its own clips.

**Non-goals**: enemy realms fielding axemen (every pack starts with 0; a raider axe host is a later
idea), a per-figure sword/axe mix, new UI screens, the card painting now.

**Anti-goals**: an axe regiment that is simply better infantry; numbers hidden in code; touching
the files `Map3DRoyalCarrierSource._SOURCES` pins.

## Approaches (owner picked A)

- **A. A full separate arm** (picked): its own row in every per-arm table, an `axemen` column in the
  pack's `kingdoms` / `regiments`, cluster code taught that an axe regiment may fill a foot slot.
  Same as archers / artillery were added; every number visible and tunable.
- B. An "infantry family" with fallback: `unit_types.family`, missing rows inherit the infantry's.
  Fewer rows, but fallback logic in ~15 readers and hard-to-trace numbers. Rejected.
- C. Swords and axes mixed in one regiment: the owner already declined it.

## The arm

Code `axemen`, label `Axemen` (UI words in Chinese where the table's neighbours are: 斧兵),
`type` `melee`, `crew` 1, `power` 1. Every number below is a **first draft** for its CSV; tune after
play.

1. **Shield-breaker** (`data/army/army_matchups.csv`): axemen vs infantry attack 1300, vs archers 1100,
   vs artillery 1200, vs axemen 1000/1000. Infantry's defence against axemen 800.
2. **Fears horse**: axemen's defence vs cavalry 700 (infantry's is 1300); cavalry vs axemen attack
   1300. The sword infantry or archers must guard their flanks.
3. **Gate-breakers** (`data/army/army_town_defence.csv`, attack column): attacking a town 1100,
   walls 1200, citadel 1250 (infantry 1000). Holding one gets about half the infantry's bonus:
   town 1050, walls 1150, citadel 1200.
4. **Woodsmen** (`data/army/army_terrain.csv`): forest 1150 / 1150; no jungle penalty (infantry's is
   800 / 800).
5. **Raised from the countryside** (`recruitment.csv`, pack `unit_types.csv`): equipment 1 gold per
   element, `build_days` 3 (infantry 5), a rural rate above its urban rate (first draft 0.15 /
   0.05). The builder checks what `rural_rate` / `urban_rate` feed (a new arm must not silently
   enlarge the realm's whole recruitable pool) and sets values that keep the total sane.
6. **First blow** (new rule, its own step): an axe unit hits hardest in the first days of a battle
   and tires after. A per-arm table `data/army/army_first_blow.csv` (`arm, peak_days, peak_permille,
   fade_permille_per_day, floor_permille`; first draft axemen 2 / 1250 / 100 / 900) gives an
   `attack`-stance factor by days since **the unit itself** entered the fight (implementer's call:
   a fresh axe regiment marching in as a reinforcement still has its blow; the battle's `start_day`
   would not, since a merge keeps the older one, `battle_merge.gd`). So the battle's unit entry
   saves the day it joined, carried through the merge fold and the save. Weighted by the axe share of the
   unit's equipment power (as `BattleCharge.mounted_share` weights horse). It enters
   `BattleStrength.unit` as one more factor with a reason (`Axemen's first blow (day 1 of battle)`,
   `Axemen's blow is spent`) so the battle report shows why. Hand-computed GUT test.

Every other per-arm table gets an `axemen` row, mostly the infantry's values (same pace, scouting,
clearance and footprint — the soldier is infantry-sized): `army_speed`, `army_scouting`,
`army_clearance`, `unit_footprints`, `army_split` (ring 1, `axe` / `Axemen`), `commanders`
(`unit_kinds` gains `axemen` wherever it has `infantry`), `war_order_words` (`arm_axemen`),
`screens/ui/resource_icons`, `screens/war_room/war_drills` (`arms`), `war_equipment` (helmet,
mail, round shield, hand axe — read off the model), `council_seats` topics (`axemen|axes`).
`development_tier_effects` stays infantry-only (chivalry is the knights' drill).

**Formations**: an axe regiment may fill any infantry slot of `data/battle/cluster_formations.csv`,
recorded in data, not in code (the builder picks the column). `ClusterLayout.ARMS` / `ARM_WORDS`
gain `axemen` / 斧兵. Step 4 adds one formation, "axes forward, swords behind" (斧前剑后): axemen
front, infantry second line.

**Pack data survives a re-import** (implementer's call): `tools/import_azgaar.gd` writes the pack's
`military/unit_types.csv`, `regiments.csv` and `kingdoms.csv` from the Azgaar export, so a hand
edit would be lost. The game's own arms (those Azgaar does not define, `axemen` first) go in a
`data/` table the importer appends to `unit_types` and as 0-count columns to `regiments` /
`kingdoms`; the beria pack is regenerated (or edited to the identical result) in step 1.

**Town seat and royal pick stay literal** (implementer's call): the unit that steps onto a held
town (`army_split.gd` `_seat`, `army_ground.gd`) and the royal unit's pick (`army_split.gd`,
cavalry then infantry) read the infantry count; an axe-only regiment falls through to "largest",
which fits "holds a town worse".

**Art until its own exists**: `army_models.tres` row `axemen` → the infantry scene (as artillery
borrowed it); `army_paintings.tres` row `axemen` → `infantry.png`. Both are editor changes (gdai),
never text edits. The stand-in needs its own `unit_locomotion.csv` row and certificate the way
artillery got its stand-in one (`tools/units3d/certify_locomotion.py`).

## The 3D soldier (step 2)

Source `assets/3D/model_wip/blender_output/infantry/infantry_handaxe_shield.blend` in the main
checkout (git-ignored: never move or delete it; open it headless or in a second Blender, never in
another session's). Install it the way `tools/units3d/infantry_arp/game_export.py` installs the
sword soldier (read that README and `docs/superpowers/specs/2026-11-16-infantry-arp-shortsword-design.md`):
`assets/3D/units/axemen/axemen.glb`, `scenes/models/units/axemen.tscn`, `army_models.tres` row,
`army_art.csv` row (stride and steps measured off its MARCH; chains from its clips: STRIKE = ATTACK
(the owner's chop) / SLASH / ATTACK_VAR1 / ATTACK_2 / SLASH_2 / SLASH_3, BLOCK, HIT, DEATH;
DEFEND; STANDBY = idle 4; WALK/MARCH = the pack walk), `unit_locomotion.csv` + `balance.csv` rows,
PIVOT_LEFT / PIVOT_RIGHT regenerated by `tools/units3d/soldier_arp/` — `pivot_mapping.py`
generalised per arm (phases and GLB path as arguments or a per-arm table), the infantry's output
byte-identical — a provider `scripts/map3d/map3d_axemen_locomotion.gd` (new file), and a certificate
from `certify_locomotion.py`. Goes through `visual-review`.

## Steps (one PR each, PRD §6 size)

1. **The arm**: every data row above, pack columns, cluster fill rule, stand-in model / painting /
   certificate. Outcome: raise an axe regiment in the prologue; it fights by its own numbers.
2. **Matchups against the foe actually faced** (owner 2026-11-18: "全兵种都改"): today
   `ArmySystem._arm_base` averages ALL of an arm's matchup rows into one base, so items 1–2 above
   do nothing situational (the axemen average 1000, the infantry 1050). A new battle factor weights
   each arm's matchup by the opposing side's arm mix, for every arm (existing battles rebalance);
   the "X vs axemen" rows of the existing arms land here, not in step 1. New code outside the pinned
   `army_system.gd` (a `BattleStrength` factor with a reason).
3. **Storming a town**: `army_town_defence.csv`'s `attack` column is read today by nothing
   (`terrain_factor` applies works to the defender only). A new factor gives the attacker of a
   held town its arm's `attack` value for the works there.
4. **3D axe soldier** on the map with its own clips.
5. **First blow** rule and its table, test and report reason.
6. **Formation 斧前剑后**.
7. **Card painting** (`assets/2D/paintings/armies/axemen.png`, a B-row in
   `docs/references/art_prompt_library.md`): when the desktop is on, Z-Image + Qwen batches, the
   owner picks; ask before queuing.

## Left to the builder

Exact column for the formation fill rule; how the matchup table's attack / defence pair is read
(set the rows so the intent above holds); every hand-computed test value; which tests list arms and
need the new one; whether `MapObjects.army_piece` / the war room need an `axemen` piece now (the
war room's wooden piece may borrow the infantry's until step 2).

Note for step 1: `certify_locomotion.py` hashes `army_art.csv`, `unit_footprints.csv` and
`data/army/balance.csv`, so adding the `axemen` rows re-issues all five existing locomotion
certificates in the same PR.
