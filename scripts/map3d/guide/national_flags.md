# National standards

Approved originals and their source selections live in `assets/2D/flags/realms/`.
The editor-owned `national_flags.tres` ArtTable maps realm slots to textures;
`Map3DNationalFlag.texture_for` resolves slots through the current pack bindings.
No country or map pack is named in runtime code. Missing art draws no flag.

`scenes/models/flags/national_standard.tscn` owns the wooden pole, cloth mesh,
material and restrained wind. The cloth shader receives light on both faces.
`Map3DCityFlags` is referenced by the Houses layer and takes its admitted
settlement list, so flags share the houses' distance and budget. A pole is seated
on an actual highest vertex of the settlement's landmark (or first house), using
the same baked transform and terrain seat. Province ownership changes refresh
textures on a paused clock. These are physical objects, never camera-facing marks.

No map figure carries a standard: every soldier of a unit is drawn alike (owner
ruling 2026-11-23). `Map3DUnitDress.sync` never
calls `Map3DUnitStandard`; that class and `Map3DStandardBearer` stay only because
the royal carrier's source gate pins `map3d_unit_standard.gd` (its test still
proves a decorated figure rejects as `unproved_source_script`). Re-adding a unit
standard needs a new owner ruling and a better carrier model.

## The commander and his banner

A unit's COMMANDER is drawn: one rider on the armoured horse under his realm's banner (the banner is a
ruling for the commander only and does not reopen the soldiers' standard above; spec
`2026-11-27-commander-figure-design.md`). `Map3DUnitDress.sync` — called by the Units layer for every
ADMITTED regiment, never a ghost — hangs one `Map3DCommanderRider` named `Commander` on the piece's node
(`Map3DCommanderRider.sync`), so he is shown, hidden (symbol mode, a hidden view; his clip stops),
stopped offscreen and freed with the piece, and needs no edit of the royal carrier's pinned files.

- **Who has one** (`leads`): a unit whose `GameState.military_rosters[code].commander_id` is set — the
  crown's and a SEEN foe's alike, each under its own realm's flag. Never the royal piece (`is_royal`:
  the king himself is that rider), never a ghost, never a fleet (no piece). A unit whose commander
  fell stands leaderless until the next appointment.
- **He takes no place**: not a formation slot, not in the piece's `figs` / `anims`, not a battle group,
  no number on any card; nothing is saved. A click on him picks his unit (the picker's ray test,
  `Map3DPicker.ray_depth`, walks every mesh under the piece's node, his too — his box cut at his head's
  height, the mesh meta `Map3DCommanderRider.PICK_TOP`, so the air round his banner takes no click; the
  unit's screen box is the men's alone); he has no card, name or mark of his own.
- **Hung unseen**: a new rider is invisible until his first `stand()` on the next frame, when his piece
  is seated — before that his size and place are not his, and an invisible mesh takes no click.
- **Where he stands** (`_place`, each frame from the live piece; re-solved only when the piece's
  transform, extent or his scale changes, in a battle block, or while he rides): alone, centred on the
  files, straight ahead of the first rank — the foremost slot plus a figure's half depth (`front_of` over
  the piece's `slots`, not its half `extent`: a block's ranks do not straddle its centre), then
  `map3d_commander_gap` of his own lengths clear and half his length (`lead_m`) — facing the unit's way,
  planted on his own ground (`Map3DUnitRig.plant`). The same on the march, standing by, in garrison and
  holding a front line.
- **A battle block before its first round** (`physical_groups`, `BattleSystem.battle_of(...).rounds` 0,
  the stand-off; a block whose battle is gone too): he stands ahead of the foremost drawn figure in the
  frame of the unit's saved `facing_deg`, on STANDBY, `map3d_commander_standoff_share` of the ROOM
  between the lines, never past his ordinary lead — the two sides' commanders keep the middle of that
  ground between them. The room (`_room`, `standoff_lead`) is the clear ground between where his first
  rank and the nearest enemy figure of his battle will STAND (`Map3DBattleGroups.stand_xz`), never the
  drawn figures: it is settled on the first frame of a walk-in, so he takes ONE place and never swaps
  as the lines close. Where that share would
  back his tail into his own rank (lines closer than his half length over that share: the usual
  stand-off) he stands BESIDE THE LEFT END OF HIS FIRST RANK instead (`first_rank_left_of`): outside
  the left file by the fight's `map3d_commander_rear_gap` and half his width, level with the foremost
  figures' own line, facing the enemy. That is the lane he rides down when the fight starts.
- **Walking in** (`piece["easing"]` before the first round): he is DRAWN and comes in with his men.
  The piece is new (a block gone into its battle), so the old block's rider hands him his place; his
  place is measured off the figures as they are DRAWN, so it moves in with them and he keeps with it,
  facing the way he rides, and is on it without a jump when they stand. His gait is the walk; where
  his unit's arm gallops in (`commander_gallops`) it is `MARCH`, the gallop, at its own measured
  stride — a walk cannot keep with galloping cavalry. With no old rider (first sight, a loaded save,
  symbol mode) he stands at his place at once.
- **In the fight** (`rounds > 0`, the crown's unit and a seen foe's alike, each in its own facing's
  frame, so a foe's is on HIS left seen facing the crown): at the unit's LEFT REAR — outside the left
  file by `map3d_commander_rear_gap` of his own lengths and half his width (`side_m`), and
  `map3d_commander_rear_back` of his lengths behind the rear rank's line (`left_rear_of`) — facing the enemy with his unit, on `COMMAND` at its own speed. A figure
  counts where it is DRAWN, except one a duel or the mixed fight has claimed (its player's `duel`
  meta), which counts where it STANDS (`Map3DBattleGroups.stand_xz`): men gone to fight do not move
  him, a block walking to new saved points does. The figures' steps (`easing`) do not hide him.
- **He rides between his places** (`route`, `ride`; view-only, real seconds, so on a stopped clock too):
  a new place further than `map3d_commander_ride_min` of his lengths is ridden to at
  `map3d_commander_ride_pace` times his gait's own pace (a nearer one does not move him), round his
  block and never through it — a leg is clear when both its ends are outside one flank file, both
  ahead of the first rank or both behind the rear rank; the way is the SHORTEST of clear legs through
  the block's four corners (each as far out as the further-out end, his side gap clear of the flank
  files and half his length of the ranks at least; the left wins a tie), every half turn on it and the
  turn to his unit's facing at its end counted as `map3d_commander_about_face` of his lengths. So from
  ahead of the first rank to the left rear it is round the LEFT flank, and to a place beside his block
  he comes up from behind, already facing the enemy, where that is not much the longer way. He rides the way he FACES, turning at the Units node's
  `turn_deg_per_s` as he goes, so a corner is an arc he passes, not a halt; the last stretch he rides
  straight onto his place, only as far as he faces it (a horse does not slide sideways). He plays his gait's clip at the
  ground he covers that frame (within `map3d_unit_anim_min` / `_max`), and at the end turns to his
  unit's facing before he takes his clip. He keeps with a place that walks on (his block going to
  new points) while it covers ground at `map3d_unit_anim_min` of his walk's pace or more; a slower
  drift he lets go, commanding, and rides after it once it is `map3d_commander_ride_min` off. A battle
  block's root that jumps to its unit's new place (a day's end) does not carry him: he keeps his own
  ground (`_anchor`). A piece REPLACED in a refresh (a block gone into its battle or come out of
  it, a formation rebuilt) hands its drawn rider's world place to the new piece's rider (`sync`: the
  old node is still queued for deletion), who rides on from there. NEVER a ride: under a swapped state
  (a loaded save: he keeps the `GameState` he last stood under), on first sight, after he was not
  drawn (symbol mode, a hidden view), when his scale changed, or from INSIDE his block (no clear
  way) — he is stood at his place at once.
- **Size**: `map3d_commander_size` is his `army_art.csv`-style size (his model box, banner tip
  included, over the piece height), measured so his horse is the cavalry's horse at every camera
  whatever arm he leads (`test_map3d_commander_rider.gd` checks it against the two installed models;
  re-measure after a re-export of either).
- **Clip** (`clip_for`): `COMMAND` in a battle block's fight; `MARCH` (the gallop) ahead of an arm
  whose `army_art.csv` `commander_gallops` is 1 (the cavalry), `MARCH_WALK` ahead of every other arm,
  only while an ordinary piece's action is MARCH; `STANDBY` otherwise; `MARCH_WALK` on a ride. His
  march keeps his unit's ground (`march_rate`): the men's plan-timed
  pace (`pace_key`) carried over by the two strides (`map3d_commander_walk_stride_m` measured off
  `MARCH_WALK`, `map3d_commander_gallop_stride_m` the cavalry's lock) and scales. Each clip starts at a
  phase hashed from the unit's code.
- **The banner**: the cloth is the second surface of `scenes/models/units/commander.tscn`
  (`banner_cloth`), bare linen in the scene; `Map3DCommanderFigure.set_flag` puts the realm's texture
  (`Map3DNationalFlag.texture_for`, the Units node's `realm_flags`) on a copy of that material shared by
  the realm's commanders, and a realm with no flag art keeps the linen. The cloth's motion is baked
  into the clips.

## Realm colours on the figures

`Map3DUnitDress.sync` (called by the Units layer after sight admission) dresses
every figure of an arm listed in `GameArt.UNIT_REALM_TINT`
(`assets/3D/units/realm_tint.tres`: the arms on the infantry model) in its realm's
colour, so a mixed fight reads as two sides (spec
`2026-11-21-infantry-melee-scrum-design.md`, step 1). Each figure mesh — never the
carried standard — wears `scenes/map3d/materials/unit_realm_tint.tres` as its
`material_overlay`: it repaints the model's tunic mask
(`infantry_tunic_mask.png`, exported with the atlases by
`tools/units3d/infantry_arp/game_export.py`) in the instance uniform `realm_tint`,
keeping the cloth's shading (atlas luminance over the tunic's mean). The scene's
own material is untouched, so the WAR ROOM's tin and ink are unchanged. The colour
is the realm's political-palette hue at saturation `map3d_unit_tint_sat`,
its value solved for the linear luminance `map3d_unit_tint_lum`: every realm's
tunic equally light, told apart by hue. The cavalry and royal models
have no cloth material in their Tripo atlases: their `<model>_tunic_mask.png` is
baked by `tools/units3d/cloth_mask.py` (an HSV window per atlas on the dyed
cloth; it prints the `tunic_luminance` for the arm's
`unit_realm_tint_<model>.tres`). The axemen's hand-axe soldier is the infantry's body on its own atlas: its
`unit_realm_tint_axemen.tres` is the infantry's overlay reading the axe atlas, with the infantry's tunic mask
(the body's region of the two atlases is the same). The militia's mask comes from its exporter
(`tools/units3d/militia_arp/game_export.py`: the tunic's and skirt's faces by the
source's `part_id`), under `unit_realm_tint_militia.tres`; the archers' likewise
(`tools/units3d/archer_parts/game_export.py`: the gambeson's faces by the source's `part`), under
`unit_realm_tint_archers.tres`. An overlay is painted only on a mesh drawn from
its material's `albedo_atlas`, so a prop on its own texture keeps its colours; a prop
in the figure's own atlas is left untinted by the mask (the archer's bow, quiver, arrow).
