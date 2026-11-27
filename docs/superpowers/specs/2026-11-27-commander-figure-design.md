# The mounted commander on the map

A unit's commander is drawn: one rider on the armoured horse, carrying his realm's banner. The model was
made on 2026-11-27 from the owner's Tripo commander (source and authoring record:
`assets/3D/model_wip/blender_output/units/commander/`, git-ignored; its `README.md` is the whole
pipeline). The owner approved the motions (动作可以), asked for the decimation and the game export, and
ruled how he enters the game.

## The owner's rulings (2026-11-27)

> 装入游戏的原则：所有指挥官不占用任何人数，平时行进是单独处于整个队伍第一排正前方，两军对峙时也是单独处于队伍
> 第一排正前方。两军交战时移动到队伍面向敌人方向的左边靠后的位置进行指挥。

1. **No headcount** — every commander takes up none of the unit's men.
2. **On the march** — alone, straight in front of the unit's first rank.
3. **In a stand-off between two armies** — likewise alone, straight in front of the first rank.
4. **When the two armies fight** — he moves to the unit's left rear, seen facing the enemy, and commands
   from there.

The banner is a new ruling for the commander only: `scripts/map3d/guide/national_flags.md` keeps the
2026-11-23 ruling that no SOLDIER of a unit carries a standard.

## What a commander is, from the code as it stands

- **State**: `GameState.military_rosters[unit_code].commander_id` (a character id, `""` when the unit has
  none) and `commander_cohort_id` (`MilitaryCommanders`, `MilitaryRoster.assign_commander`). Eligibility
  is `data/army/commanders.csv`. The opening gives every unit of every realm a named commander
  (`MilitaryBootstrap`); `MilitaryCommanders.clear_unfit` empties the appointment when he is wounded,
  captured or dead; a raised town militia has none.
- **In the engine he IS one person**: a one-man noble cohort inside the unit ("A commander occupies one
  noble place, never an additional person", `military_roster.gd`). This spec changes nothing there.
- **Which units get the figure**: a unit that has a 3D piece (`Map3DLayerUnits.has_piece`: land arms, not a
  fleet) and a non-empty `commander_id`. No commander, no figure — a unit whose commander fell is seen
  to be leaderless until a new appointment. The royal piece (`is_royal`): open question Q2.

## Presentation only (不占用任何人数)

The figure is one more node under the unit's piece. It is not a formation slot (`Map3DFormation.fit_tier`
still counts `BattleGroups.counts` of the fit people and nothing else), not a battle group, not a body in
`unit_footprints.csv`, not in the piece's `figs` / `anims`, and it changes no number the engine or a card
shows. Nothing is saved for it; a loaded game draws him from the roster.

## Where he stands, from what the view already knows

The Units layer's piece dictionary already carries everything needed (`Map3DLayerUnits._pieces[code]`):
`action` (the clip the unit plays), `layout`, `extent` (the formation's half extents, model metres; x
right, z to the rear, front is −z), `figure_extent`, and for a battle unit `groups` and `facing_deg`.

| The unit is | How the view knows | Commander | Clip |
|---|---|---|---|
| marching | `action == "MARCH"` | alone, centred, ahead of the first rank: local (0, −(`extent.y` + a gap)) | `MARCH` or `MARCH_WALK` (Q1) |
| in a stand-off | a battle unit (`layout == "physical_groups"`) whose action is not a fighting one — the battle has had no round yet (`BattlePresentation.map_snapshot`: `rounds == 0` → `GARRISON`) | the same place, in the frame of the unit's saved facing | `STANDBY` |
| fighting | a battle unit whose action is `ATTACK` or `DEFEND` (`rounds > 0`) | the unit's left rear seen facing the enemy: outside the left file, level with the rear rank — local (−(`extent.x` + a gap), +`extent.y`) in the facing's frame | `COMMAND` |
| standing outside a battle (standby, garrison, holding a front) | any other action | not ruled — Q3; default: ahead of the first rank | `STANDBY` |

- For a battle unit the extents are the bounding box of its groups' drawn points in the frame of
  `facing_deg`; for an ordinary formation, `extent`.
- The gap is one horse's length (the commander's own `stand_extent`), tuned in the visual review, a
  `data/screens/map3d/balance.csv` key if it needs a number.
- **He rides between the two places** (front ↔ left rear) round the unit's left flank, view-only, on a
  stopped clock too, as the figures walk into a battle (`Map3DBattleGroups._walk`); never after a state
  swap (a loaded save stands him where he belongs).
- **Scale**: he is drawn at the world scale a cavalry figure has at that camera (`army_art.csv` cavalry
  `size` over the cavalry model's height), whatever arm he leads, so a horse is a horse everywhere.
- **Ground**: planted on his own ground like every figure (`Map3DUnitRig.plant`).
- A seen enemy unit in a battle has no `map_snapshot` row of its own (the snapshot is the crown's): its
  state is read from the battle the crown's units share with it; step 3 settles the lookup.

## The realm's flag

The cloth is the model's second surface (`banner_cloth`, 288 triangles, two-sided, UVs spanning one flag
picture, hoist = the picture's left edge). It ships bare. `Map3DCommanderFigure.set_flag(figure, texture)`
puts a realm's flag on it — `Map3DNationalFlag.texture_for(repo, realm_flags, kingdom_code)`, the table
the Units layer already holds — on a copy of the scene's cloth material shared by every commander of that
realm. A realm with no flag art keeps the bare linen. No realm tint mask: the banner tells the side.

The cloth's material lets light through (`backlight`, set in the scene): with none, a flag turned from the
sun is black and a dark realm's charge is lost.

## Sight

He belongs to his unit's piece: drawn only for a unit `Map3DContext.regiments()` admits (the crown's own,
and the foes it SEES), hidden with it, never for a ghost (a ghost reads nothing live) and never in symbol
mode (the far zoom draws no figures). Not in the WAR ROOM. A click on him is a click on his unit.

## Performance

24,526 triangles, 124 bones, 372 animation tracks: one more cavalry-class figure (the cavalry's is 23,929
triangles, 120 bones) per unit that has a commander, beside up to ten figures the unit already draws. No
distance cut is designed in: far out the symbols replace every figure, and an offscreen piece's clips are
stopped (his too). Step 2 measures it — `tools/map3d/bench.gd` at the three zooms, every tier, with every
commander drawn, against the tier's `bench_budget_ms` — and only if a tier fails does it add a camera
distance past which he is not drawn (a balance key), before any second, lighter model is made.

## The royal carrier's pinned files

`map3d_royal_carrier_source.gd` pins `map3d_layer_units.gd`, `map3d_formation.gd`, `map3d_units.gd`,
`map3d_unit_rig.gd`, `map3d_battle_groups.gd`, `map3d_national_flag.gd`, `map3d_context.gd`. The plan
needs none of them edited: `Map3DUnitDress.sync` (not pinned) is already called by the Units layer for
every admitted regiment — never for a ghost — with the piece, the roster row and the realm flag table; it
hangs the commander's node on the piece, and that node places and animates itself each frame from the
piece's dictionary. If a later step finds it must touch a pinned file after all, that session asks the
owner first, renews the SHA and runs `map3d`.

## Steps (one PR each)

1. **The asset** (this PR): `tools/units3d/commander_arp/` (exporter, scene maker, real-window look
   check), `assets/3D/units/commander/`, `scenes/models/units/commander.tscn`, the import settings,
   `Map3DCommanderFigure.set_flag`, `tests/map3d/test_commander_model.gd`. Nothing draws him.
2. **Ahead of the first rank**: the node on every admitted commanded unit, the flag, scale, planting,
   `MARCH` / `STANDBY` by the unit's action, sight, the bench. The walk's stride is measured off
   `MARCH_WALK` first (the gallop's is the cavalry's 2.4224 m). Visual review on the real map.
3. **The battle**: the stand-off place, the ride to the left rear, `COMMAND`, the ride back. Visual
   review through `snapshot_screen --battle-case encounter`.

## Open questions for the owner

- **Q1 — the march clip.** `MARCH` is the gallop (the cavalry's march); `MARCH_WALK` is the same carriage
  at the walk. Proposal: he walks ahead of foot (infantry, heavy infantry, axemen, archers, militia,
  artillery) and gallops ahead of cavalry.
- **Q2 — the king's own unit.** The royal piece is the king himself on horseback. Proposal: no commander
  figure there.
- **Q3 — standing still outside a battle** (standby, garrison, holding a front line). Proposal: ahead of
  the first rank on `STANDBY`, as in a stand-off.
- **Q4 — "不占用任何人数" in the engine.** Today the commander is one of the unit's noble personnel (he
  can be wounded or captured, which empties the appointment). Proposal: leave the engine as it is; the
  ruling is met by the figure taking no formation place and changing no number. Taking him out of the
  unit's personnel would be an engine change with its own spec.
- **Q5 — enemy commanders.** Proposal: a seen enemy unit shows its commander under its own realm's
  banner; a ghost never does.

## Defaults chosen without a ruling

- The cloth with no flag is undyed linen; the scene authors no realm's flag.
- He is not separately clickable, has no card and no name over him (near mode draws nothing over a piece).
- No sound of his own; no dust.
- The ride between the two battle places uses the walk.

## Look review of the installed model (2026-11-27)

Real-window shots by `tools/units3d/commander_arp/review.gd` (each clip at four phases under four realms'
flags, the cavalry beside him, the cloth's two faces in the sun and from behind it), one independent
critic pass: nothing blocks the install. Changed after it: the cloth's backlight, bracketed 0 / 0.3 / 0.45 /
0.6 (0 and 0.3 leave a dark flag black from behind the sun, 0.6 makes a pale one glow; 0.45 kept). Left for
the source file, each needing Blender work on the owner's approved motions:

- `COMMAND`'s lowest sweep folds the cloth into a hard Z (the six-bone chain shears).
- At rest the cloth is a skewed sheet whose ripple is small.
- The feather is white from his right and dark from his left.
- The right fist sits beside the staff more than round it; the staff passes close to the horse's ears at
  the sweep's lowest point; the finial reads cream, not brass.
