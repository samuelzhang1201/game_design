# Militia: a weak standing arm every kingdom keeps near its main towns

Owner 2026-11-26 (Chinese): "请给游戏中所有国家按军队比例新增少量民兵部队，驻防在主要城市附近。" Offered
the builder's default, the owner took it with one addition: "新增 militia 兵种，数值弱于步兵，每国 2–3
个团，规模约为该国军力的 5%。绝对数量也不要太少，至少凑满一个军团". So: **a new arm**, weaker than the
infantry, 2–3 regiments a kingdom, about 5% of its army, and never less than one regiment's worth.

The owner gave no other numbers. Every number below is the builder's **first draft**; tune after play.

## Intent

A kingdom's towns are no longer bare when its field army marches: a few small militia regiments stand
beside the largest ones. They are cheap and poor in the open, and worth about an infantry regiment
only on their own walls.

**Goals**
- A new arm `militia`, raised, marched and fought by its own numbers (all in `data/`), no new engine rule.
- Every kingdom opens a new campaign with 2 or 3 militia regiments near its largest towns, together
  about 5% of its land army and never fewer men than `total_min`.
- On the 3D map it is the installed militiaman (`scenes/models/units/militia.tscn`).

**Non-goals**: a garrison-only rule (the militia can march like any regiment), a new battle rule, a
lower starting training grade, a card painting or wooden piece of its own, any change to the siege's
raised town militia (`TownMilitia`, still infantry and archers wearing the militia figure).

**Anti-goals**: militia as good as infantry in the field; numbers in code; a pack named in code, tools
or tests; changing the heavy infantry's opening regiments; touching a file
`Map3DRoyalCarrierSource._SOURCES` pins without the owner's ruling in that session.

## Approaches

- **A. A full arm plus a rule row (chosen by the owner).** `militia` joins `game_arms.csv` and every
  per-arm table the way the axemen and heavy infantry did; the opening regiments come from
  `game_arm_starts.csv` through `tools/army_starts.gd`. More tables, but the arm has its own numbers
  and a re-import keeps the regiments.
- **B. Infantry regiments wearing the militia figure.** One PR, but "weaker than infantry" would need
  a per-regiment modifier the engine does not have.
- **C. Hand-written rows in the pack's `regiments.csv`.** Lost on the next import.

## The arm

Code `militia`, label `Militia` (民兵), `type` `melee`, `crew` 1, `power` 1, `separate` 0, rates rural
0.2 / urban 0.15 (they only weight where opening personnel come from; a new arm must not enlarge the
recruitable pool). Added as the heavy infantry was
(`docs/superpowers/specs/2026-11-20-heavy-infantry-arm-design.md`, step 1; that PR's file list is the
list of per-arm tables). First-draft numbers, infantry's in brackets:

1. **Weak in the open** (`army_matchups.csv`, attack / defence permille). Militia vs infantry
   800 / 800; vs archers 800 / 900 (900 / 1000); vs cavalry 900 / 1000 (1200 / 1300); vs artillery
   1000 / 800 (1100 / 900); vs axemen 800 / 700 (1000 / 800); vs heavy infantry 700 / 800
   (900 / 900); vs militia 1000 / 1000. The others against it: infantry 1200 / 1100, archers
   1300 / 900, cavalry 1300 / 1100, artillery 1100 / 700, axemen 1300 / 1100, heavy infantry 1300 / 1300.
2. **Worth its place on walls** (`army_town_defence.csv`): the infantry's rows (1100 / 1300 / 1400).
3. **Terrain**: no row (no bonus, no penalty).
4. **March and sight**: `army_speed.csv` 20 km a day, `army_scouting.csv` 15 km, 120° (the infantry's).
5. **Cheap and quick** (`recruitment.csv`): equipment 1 gold per element, `build_days` 3 (infantry 5),
   the other columns the infantry's.
6. **Body**: `army_clearance.csv` and `unit_footprints.csv` take the infantry's values;
   `battle/cluster_arms` `counts_as` `infantry`.

**Art**: `data/screens/map3d/army_art.csv` already has a `militia` row and `army_models.tres` /
`realm_tint.tres` a `militia` key, described as "a FIGURE only, no arm". The arm now uses the same
figure as its piece; the row's notes and `militia.tscn`'s description say so. Painting, war piece and
sounds borrow the infantry's (editor changes through gdai). `unit_locomotion.csv`, its provider and
certificate follow the heavy infantry's pattern; `certify_locomotion.py` hashes tables this step
touches, so every certificate is re-issued in the same PR.

## Opening regiments

`data/army/game_arm_starts.csv` gains two columns and a `militia` row. The heavy infantry's row sets
both new columns 0 and its regiments stay byte-identical.

| column | militia | meaning |
|---|---|---|
| `units_min`, `units_max` | 2, 3 | regiments per kingdom, by strength rank as today |
| `share_permille` | 50 | **new**: the kingdom's regiments together are this share of its land army; 0 = the `avg_*` rule |
| `total_min` | 500 | **new**: the least that total may be (the smallest regiment the export writes) |
| `men_min`, `men_max`, `men_step` | 250, 1000, 50 | one regiment |
| `avg_strongest`, `avg_weakest` | 0, 0 | unread when `share_permille` > 0 |
| `place`, `offset_km`, `bearings` | `largest_towns`, 1, the heavy infantry's list | 1 km, not the heavy infantry's 2: at 2 km a second ring (4 km) is outside a capital's reach and a first ring can cross a province border, and every land regiment must open in a held town in its own province (owner 2026-10-06, `test_army_towns.gd`) |
| `code_word`, `label_word` | `militia`, `Militia` | `<kingdom>_<ordinal>_militia_<town>`, `1st (<Town>) Militia` |

The share rule, whole numbers, fixed order:

- **Army**: the men of the kingdom's non-naval regiments already written when the rule runs (the
  export's and earlier rows' — rules run in file order, so the heavy infantry counts).
- **Total** T = max(army × `share_permille` / 1000, `total_min`), rounded half up to `men_step`.
- **Count** n: `units_max` for the upper half of the strength ranking, else `units_min` (unchanged).
- **Size**: base = T / n rounded half up to `men_step`; the regiment at the largest town one
  `men_step` above it, the last one below, each clamped to `men_min`..`men_max`.
- **Place, code, label, totals in `kingdoms.csv`**: as the heavy infantry's. Its regiments already
  stand on the largest towns, so the militia lands on the first clear ring, `offset_km` out.

On the default pack today (land armies 52,117 / 30,474 / 21,982 / 18,800 / 11,800 / 11,800 / 2,237):
900 / 850 / 800, 550 / 500 / 450, 400 / 350 / 300, 350 / 300 / 250, 350 / 250 (twice), 300 / 250.
The step-2 test derives these from the pack's own tables, never from these figures.

For the owner: the floor makes the smallest kingdom's militia about a quarter of its army (550 men
beside 2,237). `total_min` is the knob.

**The siege**: `TownMilitia` raises townsfolk only for a town with no defenders. Where a standing
militia regiment holds the town, the town fights with it instead; one camped a ring out does not
count. No rule changes; step 2 states which of the two holds on the default pack.

**Saves**: an old save has no militia arm and must still load (the axemen's migrate / reconcile test
is the model). Only a new campaign gets the regiments.

## Steps (one PR each)

1. **The arm**: the `game_arms.csv` row, every per-arm row, pack columns (all 0), art keys and
   certificate, tests. Outcome: the recruitment panel offers Militia; a militia regiment fights by
   its own numbers and is drawn as the militiaman.
2. **Opening regiments**: the two columns, the share rule in `tools/army_starts.gd` with a
   hand-computed test, the `militia` row, the default pack regenerated. Outcome: a new campaign shows
   2–3 militia regiments near each kingdom's largest towns.

## Left to the builder

Every hand-computed test value; which tests list arms; the war-room equipment words read off the
model (kettle hat, tunic, short sword, round shield); how the `militia` figure key and the arm's piece
share one `army_art.csv` row; the visual-review pass for militia regiments on the map.
