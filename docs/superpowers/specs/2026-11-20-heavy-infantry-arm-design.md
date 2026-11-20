# Heavy infantry: a new armoured-foot arm, fielded by every kingdom from the start

Owner 2026-11-20 (Chinese), after the new plate-armoured soldier was rigged and animated
(`heavy_infantry_parts.glb`): "减面并导出，安装入游戏". Asked where it should go (replace the
infantry / a new arm / export only), the owner answered: "修改初始数据，给每个国家依照国家军事实力大小
新增重甲步兵单位，每个国家新增3-4个单位，500 - 1000 人不等，初始驻扎于大城市附近或者大城市内部，
同时给我一个现有步兵和重甲步兵的对比，包括模型，动作，数据". So: **a new arm**, present in every
kingdom's opening army, and a comparison of the two foot arms.

The owner gave no numbers for the arm. Every number below is the builder's **first draft**, shown to
the owner on 2026-11-20 as a side-by-side comparison with the infantry (models, clips, these
numbers); tune after play.

## Intent

The sword-and-shield infantry is the cheap line: quick to raise, quick on the road. The heavy
infantry is the kingdom's **core**: plate from helmet to tasset, raised in towns at three times the
cost, slower on the march, hard to break where it stands and hardest of all behind walls. A player
who meets an enemy host now reads its heavy units as the ones to avoid or to shoot, and keeps the
crown's own near the towns that matter.

**Goals**
- Every kingdom opens with 3 or 4 heavy-infantry regiments of 500–1,000 men, by its military
  strength, standing at its largest towns.
- The arm fights, marches and is raised by its own numbers (all in `data/`), with no new engine rule.
- On the 3D map it is the owner's plate soldier with the infantry's clip set.

**Non-goals**: a new battle rule, a new formation, new UI screens, the card painting, the hand-axe /
longsword / longbow variants of this body.

**Anti-goals**: heavy infantry that is simply better infantry at the same price; numbers hidden in
code; a pack named in code, tools or tests; touching the files `Map3DRoyalCarrierSource._SOURCES` pins.

## The arm

Code `heavy_infantry`, label `Heavy infantry` (重甲步兵 where the table's neighbours are Chinese),
`type` `melee`, `crew` 1, `power` 1, `separate` 0. It is a full separate arm, added the way the
axemen were (`docs/superpowers/specs/2026-11-18-axemen-arm-design.md`, approach A): one row in
`data/army/game_arms.csv` (so `tools/import_azgaar.gd` appends it to the pack's `unit_types.csv` and
gives it a column in `regiments.csv` / `kingdoms.csv`) and its own row in every per-arm table.

First-draft numbers (infantry's value in brackets):

1. **Holds a line** (`data/army/army_matchups.csv`, attack / defence permille). Heavy infantry vs
   infantry 1100 / 1200; vs archers 1000 / 1200 (plate turns arrows; infantry 900 / 1000); vs
   cavalry 1100 / 1300 (as the infantry: the line holds a charge); vs artillery 1100 / 800; vs
   axemen 1100 / 1000 (plate does not split like a shield wall; infantry 1000 / 800); vs heavy
   infantry 1000 / 1000. The existing arms against it: infantry 900 / 900, archers 900 / 800,
   cavalry 800 / 800, artillery 1200 / 700 (a slow close target), axemen 1100 / 900.
2. **Best behind walls** (`army_town_defence.csv`, defend): town 1150, walls 1350, citadel 1450
   (infantry 1100 / 1300 / 1400). The `attack` column, read by nothing yet, is 1000.
3. **Poor in rough ground** (`army_terrain.csv`, defend / attack): jungle 700 / 700 (infantry
   800 / 800), marsh 800 / 800, forest 900 / 900. No other terrain row.
4. **Slow** (`army_speed.csv`): 16 km a day (infantry 20). A regiment marches at its slowest arm,
   so heavy infantry in a mixed host slows it. `army_scouting.csv`: 12 km, 120° (infantry 15).
5. **Dear and town-raised** (`recruitment.csv`, `game_arms.csv`): equipment 3 gold per element
   (infantry 1), `build_days` 8 (infantry 5), commoner / noble / commander gold as the infantry;
   rates rural 0.05, urban 0.15 (infantry 0.25 / 0.2). The builder checks what the rates feed
   (`MilitaryBootstrap`), as for the axemen: a new arm must not enlarge the realm's recruitable pool.
6. **Same body on the ground**: `army_clearance.csv`, `unit_footprints.csv` take the infantry's
   values until the installed model is measured (step 3 re-measures them).

Every other per-arm table gets a `heavy_infantry` row the way `axemen` did (the list is that PR's
file list, #341): `army_split` (ring 1, `heavy` / `Heavy foot`), `commanders` (`unit_kinds` gains it
wherever it has `infantry`), `war_order_words` (`arm_heavy_infantry`), `screens/ui/resource_icons`,
`screens/war_room/war_drills`, `war_equipment` (morion, breastplate with pauldrons and tassets,
puffed sleeves and breeches, round shield, short sword — read off the model), `council_seats` topics,
`realm/world_schema`, `battle/cluster_arms` (`counts_as` `infantry`, word 重甲步兵: a heavy unit
fills any infantry slot). `development_tier_effects` stays as it is.

**Art until step 3**: `army_models.tres`, `army_paintings.tres`, `war_pieces.tres`, `unit_sounds.tres`,
`settle_sounds.tres` rows `heavy_infantry` → the infantry's (editor changes through gdai, never text
edits), with its own `unit_locomotion.csv` row and certificate, as the axemen's stand-in got. The
card painting stays the infantry's until the owner asks for one.

## Opening regiments

The pack's `military/regiments.csv` is written by `tools/import_azgaar.gd` from the Azgaar export, so
the new regiments are **generated by the importer from a rule table**, never hand-written rows (a
re-import would lose those) and never a pack named in code.

`data/army/game_arm_starts.csv` (new, indexed in `data/tables.csv`), one row per game-owned arm that
kingdoms open with:

| column | heavy infantry (first draft) | meaning |
|---|---|---|
| `arm` | `heavy_infantry` | a `game_arms.csv` code |
| `units_min`, `units_max` | 3, 4 | regiments per kingdom |
| `men_min`, `men_max` | 500, 1000 | men per regiment |
| `men_step` | 50 | sizes are rounded to it |
| `place` | `largest_towns` | where they stand |
| `offset_km` | 2 | how far from the town centre a second regiment at one town stands |

The rule, in whole numbers and a fixed order (the importer is a build tool, but its output is game
data, so it must be reproducible byte for byte):

- **Count**: kingdoms are ranked by `kingdoms.csv` `strength` (the Azgaar total, before these
  regiments). The upper half of the ranking gets `units_max`, the rest `units_min` (an odd middle
  kingdom counts as upper).
- **Size**: the strongest kingdom's regiments average `men_max`·0.9 and the weakest's `men_min`·1.1,
  the others linear in between by strength; within a kingdom the regiment at the largest town is
  one `men_step` above that average and the last one `men_step` below, every size clamped to
  `men_min`..`men_max` and rounded to `men_step` (half up). (So sizes differ inside a kingdom, as the owner
  asked: "500 - 1000 人不等".)
- **Place**: the kingdom's towns by population, largest first (ties by code), one regiment each; a
  kingdom with fewer towns than regiments puts the rest at its largest town again, `offset_km`
  apart. A regiment stands at the town's own position, in the town's province; if another regiment
  of the export already stands within `offset_km` it is moved `offset_km` along a fixed bearing
  list until clear. Unit clearance at load is the engine's own business (`army_clearance.csv`).
- **Rows**: `regiment_code` `<kingdom>_<n>_heavy_<town>` and a label in the export's own pattern
  (`1st (<Town>) Heavy Foot`), only the `heavy_infantry` column set, `is_naval` 0. The kingdom's
  `heavy_infantry` total, `regiments` and `strength` in `kingdoms.csv` include them.

On the default pack today the rule gives 4 regiments to the four strongest kingdoms and 3 to the
other three, from 950 / 900 / 900 / 850 men for the strongest down to 600 / 550 / 500 for the weakest.

Implementer's call to show the owner: the rule is literal, so the smallest kingdom (835 men in two
regiments today) also gets three regiments of ~500, tripling its army. If the owner wants small
realms exempt, a `min_strength` column does it.

Saves: an old save has no heavy infantry anywhere and must still load (the axemen's
`MilitaryBootstrap.migrate` / `MilitaryReorganization.reconcile` test is the model); a NEW campaign
gets the regiments. No migration adds them to an old campaign.

## The 3D soldier

Source (git-ignored, main checkout, never moved or deleted; open it headless or in a second
Blender): `assets/3D/model_wip/blender_output/heavy_infantry_parts/hip_shortsword_shield.blend` —
the owner's Tripo plate soldier on Auto-Rig Pro with the infantry's 30 clips, its body decimated
53,269 → 11,410 tris with maps baked from the high mesh (README there; the 53k file is kept beside
it). It follows the infantry source's contract: rig `rig`, body `Infantry_body`, gear `Weapon` /
`Shield` on `cc_weapon.r / .l`, body maps `textures/Infantry_body_{base,mr,normal}.png`, `WALK` a
copy of the pack walk `ADVANCE`, `STANDBY` a copy of `GARRISON_2`.

A trial run of `tools/units3d/infantry_arp/game_export.py` on it (2026-11-20, its mail-class polish
skipped: this body has no `textures/body_class.npy`) wrote a working GLB: 14,709 tris (infantry
8,604), rest height 1.599 m (1.636), `stride_m` 1.473 (1.4838), `steps` 0.2121;0.9091, MARCH's foot
lock moving the soles up to 66 / 55 mm (36 / 41). The trial files are in that folder's `export/`.

Install: `game_export.py` generalised per arm (output names, node names, the polish classes
optional; the infantry's output byte-identical), `assets/3D/units/heavy_infantry/heavy_infantry.glb`
and its atlas, `scenes/models/units/heavy_infantry.tscn`, the `army_models.tres` row, an
`army_art.csv` row (size, stride and steps MEASURED off its MARCH; chains, duel and contact as the
infantry's, contact re-measured off these clips), `unit_locomotion.csv` + `balance.csv` rows,
PIVOT_LEFT / PIVOT_RIGHT regenerated (`tools/units3d/soldier_arp/` generalised per arm), a provider
`scripts/map3d/map3d_heavy_infantry_locomotion.gd` (new file), a certificate from
`certify_locomotion.py`, footprint and clearance re-measured, the map3d bench run (the figure has
1.7× the infantry's triangles), and `visual-review` in a real window.

## Steps (one PR each)

1. **The arm**: `game_arms.csv` row, every per-arm row above, pack columns (all 0), cluster fill
   rule, stand-in art and certificate, tests (the axemen's as the model). Outcome: the recruitment
   panel offers Heavy infantry; a heavy regiment marches at 16 km a day and fights by its own numbers.
2. **Opening regiments**: `game_arm_starts.csv`, the importer rule, the default pack regenerated (or
   edited to the identical result), a test that derives the expected regiments from the pack's own
   tables. Outcome: a new campaign shows 3–4 heavy regiments at each kingdom's largest towns.
3. **The 3D soldier** on the map with its own model and clips.

`certify_locomotion.py` hashes `army_art.csv`, `unit_footprints.csv` and `data/army/balance.csv`:
steps 1 and 3 re-issue every locomotion certificate in the same PR.

## Left to the builder

Every hand-computed test value; which tests list arms and need the new one; the exact bearing list
and tie rules of the placement (written into the table's notes); whether `power` stays 1 (the arm's
edge is its matchup rows; `power` would also raise its share of supply and loot); the war room's
wooden piece (borrows the infantry's until asked).
