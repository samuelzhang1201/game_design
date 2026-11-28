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
  to be leaderless until a new appointment. The royal piece (`is_royal`) gets none: the king himself is
  that rider (R2).

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
| marching | `action == "MARCH"` | alone, centred, ahead of the first rank: local (0, −(`extent.y` + a gap)) | `MARCH_WALK` ahead of foot, `MARCH` ahead of cavalry (R1) |
| in a stand-off | a battle unit (`layout == "physical_groups"`) whose action is not a fighting one — the battle has had no round yet (`BattlePresentation.map_snapshot`: `rounds == 0` → `GARRISON`) | the same place, in the frame of the unit's saved facing | `STANDBY` |
| fighting | a battle unit whose action is `ATTACK` or `DEFEND` (`rounds > 0`) | the unit's left rear seen facing the enemy: outside the left file, level with the rear rank — local (−(`extent.x` + a gap), +`extent.y`) in the facing's frame | `COMMAND` |
| standing outside a battle (standby, garrison, holding a front) | any other action | ahead of the first rank, as in a stand-off (R3) | `STANDBY` |

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
   `MARCH` / `MARCH_WALK` / `STANDBY` by the unit's action and arm, sight, the bench. The walk's stride is measured off
   `MARCH_WALK` first (the gallop's is the cavalry's 2.4224 m). Visual review on the real map.
3. **The battle** (built, "Step 3 as built"): the left rear in the fight, `COMMAND`, the ride there
   round the left flank and the ride back. The stand-off place stays step 2's interim rule, which the
   owner has still to rule on (below).

Steps 1–3 are merged or in review; nothing further is planned in this spec. Follow-ups, each its own
step if the owner wants it: the stand-off rule, a realm tint on the commander's own tunic, a commander
for split-off units, the Blender fixes to the cloth listed under the look review.

## Rulings on the five questions (2026-11-28)

Each was put to the owner with a proposal; he took all five as proposed (都按建议).

- **R1 — the march clip.** `MARCH` is the gallop (the cavalry's march); `MARCH_WALK` is the same carriage
  at the walk. He walks ahead of foot (infantry, heavy infantry, axemen, archers, militia, artillery) and
  gallops ahead of cavalry.
- **R2 — the king's own unit.** The royal piece is the king himself on horseback: no commander figure
  there.
- **R3 — standing still outside a battle** (standby, garrison, holding a front line): ahead of the first
  rank on `STANDBY`, as in a stand-off.
- **R4 — "不占用任何人数" in the engine.** The engine stays as it is: the commander remains one of the
  unit's noble personnel (he can be wounded or captured, which empties the appointment). The ruling is met
  by the figure taking no formation place and changing no number.
- **R5 — enemy commanders.** A seen enemy unit shows its commander under its own realm's banner; a ghost
  never does.

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

## Step 2 as built (2026-11-28)

`Map3DCommanderRider` (the rule as it stands: `scripts/map3d/guide/national_flags.md`). What the build
settled beyond the plan above:

- **The first rank is the formation's foremost SLOT**, not its half `extent`: a block's ranks stand at
  z 0 and +1 pitch, so `extent.y` overshoots the front by a rank and the first real-window shot stood him
  two horse-lengths clear instead of one.
- **`MARCH_WALK`'s stride is 1.359 m**, measured off the installed clip (the hind hooves' median planted
  speed, 1.4067 m/s, times the clip's 0.96667 s); the same measure reads `MARCH` at 2.4238 m against the
  lock's 2.4224 m.
- **His size key is 1.2382**: the cavalry's 1.075 times his 4.6419 m box (banner tip) over the cavalry's
  4.0300 m.
- **The stand-off is drawn in this step, with a rule the owner has not ruled on.** At one horse-length
  ahead of each first rank the two sides' commanders met nose to nose between lines four lengths apart,
  so in a battle block he stands `map3d_commander_standoff_share` of the clear ground between his first
  rank and the nearest drawn enemy figure, never past his ordinary lead. Where that would back his tail
  into his own rank (two cavalry lines commonly stand closer than that) he is NOT drawn. Step 3 owns the
  final stand-off place.
- **The fight**: he is not drawn once a round is fought (`BattleSystem.battle_of(...).rounds`, read for a
  seen foe as for the crown: the duel driver reads it the same way). Step 3 rides him to the left rear.
- **A click on him picks his unit** with no code of his own: the picker's ray test walks every mesh
  under the piece's node. Joining his screen box to the unit's was tried and dropped (the union claimed
  the empty ground between him and a unit standing diagonally on screen).
  The ray tests his horse and body only (his mesh box cut at his head's height): the whole box, banner
  tip included, took clicks meant for the men standing behind its air.
- **A new rider is unseen until his piece is seated** (his first frame): hung on an unseated piece he
  was sized and placed against a scale of 1, eighteen times too big, and a click in that frame met him.
- **Entering a battle** he is hidden while the figures walk to their points and shown once they stand:
  the room between the lines is not settled until then.
- **Bench** (`bench.tscn`, still camera, every commander drawn, the GPU shared with other sessions' Godot
  runs): low 6.27 ms of 8.5, medium 6.27 of 8.5, high 11.19 of 12, ultra 12.24 of 12.5 — every tier inside
  its budget, so no draw distance was added.
- Split-off units (`…:living:v2:N`) have no `commander_id`, so they ride without a figure.

## Step 3 as built (2026-11-28)

`Map3DCommanderRider` only (no pinned file, no engine file). The rule as it stands:
`scripts/map3d/guide/national_flags.md`. What the build settled beyond the plan:

- **A fight is `rounds > 0`** of the unit's battle (`BattleSystem.battle_of`), for the crown's unit
  and a seen foe's alike — not the unit's action, which a foe's figures do not carry the same way.
- **A figure claimed by a duel or the mixed fight counts where it STANDS**
  (`Map3DBattleGroups.stand_xz`, its saved point drawn in; the claim is its player's `duel` meta),
  every other where it is drawn. Measured off the live nodes alone his place wandered with the mêlée;
  measured off the stand points alone he rode ahead to where a redeploying block was GOING and stood
  alone there for the seconds its men took to walk (the first real-window runs showed both). For the
  same reason `easing` hides him only before the first round.
- **The place**: outside the left file by `map3d_commander_rear_gap` (1) of his own lengths and half
  his width, `map3d_commander_rear_back` (0.5) of his lengths behind the rear rank's own line, facing
  the enemy with his unit, on `COMMAND` at speed 1. The spec's "level with the rear rank" was built
  first and bracketed at gaps 0.25 / 0.5 / 1: the independent critic found that under 1 the banner's
  sweep lands among his own left file, and that level with the rear rank his horse — as long as a
  two-rank block is deep — reaches the first rank, so he read as on the flank, not at the rear.
- **The ride goes round the left flank by corners**: a leg is clear when both its ends are outside
  the left file, both ahead of the first rank or both behind the rear rank. Front to left rear is one
  corner (front-left); a unit whose saved points moved off in the fight (the first real-window run
  showed the archers shifting ground at a day's end, and him jumping to their new left rear) is
  reached round the rear-left corner. Only from the block's right, level with it, is there no way,
  and he is stood at his place at once.
- **He rides the way he faces, turning as he goes**, so a corner is an arc and he never slides
  sideways; the last stretch (two turning radii) he rides straight onto his place, only as far as he
  faces it, and there turns to his unit's facing before he takes `COMMAND` or `STANDBY`. He turns at
  the Units node's `turn_deg_per_s`. (Built first as a pivot on the spot at each corner: the critic
  called it a rook's move.)
- **His hooves are paced off the ground he covers that frame**, held within `map3d_unit_anim_min` /
  `_max`, so the walk slows through a turn and keeps the ground on a block that is itself marching
  off. The ride's own pace is `map3d_commander_ride_pace` times `MARCH_WALK`'s.
- **Out of the battle the piece is REPLACED** (a battle block and an ordinary block are different
  pieces, so his node is freed with the old one). The old rider's world place is handed to the new
  piece's rider in the same refresh, who rides on from there; the same hand-over carries him across a
  formation rebuilt under him. A hand-over is dropped the moment he is not drawn.
- **No ride** under a swapped state (he keeps the `GameState` he last stood under), on first sight,
  after he was not drawn, or when his scale changed (a window resized). A place nearer than
  `map3d_commander_ride_min` of his lengths does not move him at all.
- **He keeps with a block that walks to new points** (the archers shift ground at a day's end and
  walk there over real seconds): while his place moves at `map3d_unit_anim_min` of his walk's pace
  or more he walks beside it at its speed; a slower drift he lets go and commands, and rides after
  it once it is `ride_min` off. Riding always to the exact place instead kept him walking on the
  spot through a whole day of a slow advance, never commanding.
- **A battle block's root jumps to the unit's new place at a day's end** while its figures still
  stand where they were. He is the root's child, so he jumped with it and waited alone, hundreds of
  metres ahead, for his men to arrive (seen in the first real-window runs). He now keeps his own
  ground when the root moves (`_anchor`).
- **Walking in** he keeps step 2's behaviour (not drawn until the block stands): the stand-off place
  depends on the room between two lines that are both still walking.
- **What the real staged battles showed** (`snapshot_screen --battle-case field`, foot against foot
  and archers against foot): under step 2's stand-off rule NEITHER side's commander is drawn in the
  stand-off — the lines the engine draws stand about two of his lengths apart, under the rule's 2.5.
  So in play, as the rule stands, he is not seen from contact until the first round, when he appears
  at the left rear; the ride from the front is seen only where a stand-off is wider. The review's
  ride was shot with `map3d_commander_standoff_share` forced to 0.5 for the shot (one commander then
  has his place between the lines). The stand-off rule is the open question for the owner.
- **Review** (real windows, `snapshot_screen --battle-case field --battle-arm archers --battle-foe
  foot`; sheets and the scratch shot flags in the session's notes folder, `commander-step3-review/`):
  one independent critic pass; its three defects fixable by a number or a placement were fixed (the
  gap, the half length back, the arced corners) and re-shot. Left open, each needing art or a ruling:
  he is not drawn in a close stand-off; both sides' commanders wear the same maroon; the horse stands
  stock-still under `COMMAND`; `MARCH_WALK` is a short, high-kneed step.
- **Bench** (`bench.tscn --battle-arm foot`, still camera, the owner's editor and other sessions'
  Godot running): low 6.31 ms of 8.5, medium 7.21 of 8.5, high 10.18 of 12, ultra 10.61 of 12.5 — no
  draw distance was added.
