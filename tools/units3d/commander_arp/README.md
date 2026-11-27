# Commander: the mounted commander with his realm's banner

`assets/3D/units/commander/commander.glb`, drawn by `scenes/models/units/commander.tscn`. Spec:
`docs/superpowers/specs/2026-11-27-commander-figure-design.md` (the owner's placement rulings, the steps
that draw him on the map). Not an arm: he is in no `army_models.tres` / `army_art.csv` row.

## Source (git-ignored)

`assets/3D/model_wip/blender_output/units/commander/cmd_rider_clips.blend`: the Tripo parts commander
(`Commander_body`, already at the game budget: 13,623 tris with its own baked maps) rigged with
Auto-Rig Pro (`rig`), riding the heavy cavalry's armoured horse (`Horse_armored` on `horse_rig`), the
banner (`Banner` armature + `Banner_mesh`) on his `cc_weapon.r` socket; each rider clip is an action on
`rig` naming its horse action in `act["horse"]` and its banner action in `act["flag"]`. Every authoring
step, gate and owner ruling is in that folder's `README.md` and `scripts/`. The export reads the file and
saves nothing into it.

## Install

```
/Applications/Blender.app/Contents/MacOS/Blender -b -y SOURCE.blend \
  --python tools/units3d/commander_arp/game_export.py -- ROOT [OUT.json]
```

writes `commander.glb` and the three `commander_commander_atlas{,_mr,_n}.jpg` into
`ROOT/assets/3D/units/commander/` and prints (or writes to OUT.json) the measured report. Then a Godot
import (`Godot --headless --path . --import`), and for a new checkout of the scene
`Godot --headless --path . -s res://tools/units3d/commander_arp/make_scene.gd` (it writes ext_resources by
path alone: put each uid back from its `.import`).

It is the cavalry's exporter (`tools/units3d/cavalry_arp/`, README there for the skeleton contract, the
hoof lock, the atlas and the clip keying) changed where the commander differs:

- **Skeleton** `commander_rig`, 124 bones: the cavalry's contract (horse legs `FrontScapula`..`FrontHoof`,
  `HindThigh`..`HindHoof` .L/.R, the rider under `Saddle`, `head` the rider's, `head_h` the horse's, other
  horse bones `h_*`) plus the cloth's chain `flag_1..6` under `cc_weapon.r`, hoist to fly.
- **Mesh** `commander`, 24,526 tris, TWO surfaces: `commander_atlas` (body 2048 px, horse 1536 px, the
  staff and its gilt finial two flat swatches in the spear's 512 px region; 4096 x 2048, metallic x
  `GAME_METAL` 0.45) and `banner_cloth` (288 tris, two-sided, 1.2 x 0.8 m, UVs spanning one flag picture
  with the hoist on its left edge). The cloth ships with NO texture, so no realm's picture is embedded:
  `Map3DCommanderFigure.set_flag` puts a realm's flag on it. Nothing is decimated here (the body arrives at
  its budget; the horse is the cavalry's).
- **Clips**, all looping, keyed from frame 0 and closed on their own period: `MARCH` (the run, 13
  frames; its hooves locked on 8 keys a frame and moved in at 240 fps as the cavalry's, stride 2.4224 m),
  `MARCH_WALK` (29), `STANDBY` (80), `COMMAND` (160). The cloth's keys are baked: nothing is simulated at
  run time.
- **`commander.glb.import`**: the four clips loop; `animation/fps=240` (MARCH's dense keys);
  `animation/remove_immutable_tracks=false`; mesh compression off. The three atlas `.import` files are the
  cavalry's settings (Basis Universal).

## Look check

```
Godot --path . --resolution 2560x1440 -s tools/units3d/commander_arp/review.gd -- --out DIR
```

A real window (never `--headless`): each clip at four phases under four realms' flags, the installed
cavalry beside the STANDBY row, and the standing figure side-on from both sides (the cloth's two faces),
under the map's environment and sun.

## Not made

No pivot plan, no locomotion certificate, no realm tint mask, no `MARCH_WALK` stride (measure it off the
clip before he walks on the map: spec step 2).
