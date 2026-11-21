# Cavalry: the ARP heavy knight on the armoured horse (installed 2026-11-21)

THE game cavalry: `assets/3D/units/cavalry/cavalry.glb`, drawn by `scenes/models/units/cavalry.tscn`
(unchanged: its material override still lands on `cavalry_rig/Skeleton3D/cavalry` and reads the same
atlas file names). It replaced the Tripo knight of `tools/units3d/cavalry_tripo/` + `cavalry_rig/`
(owner 2026-11-21: 替换现有骑兵). Spec: `docs/superpowers/specs/2026-11-21-cavalry-heavy-knight-design.md`.

## Source (git-ignored)

`assets/3D/model_wip/blender_output/heavy_cavalry/rider_clips.blend`: the Tripo heavy knight
(`Knight_body`) rigged with Auto-Rig Pro (`rig`), the 2.7 m `Spear` on its `cc_weapon.r` socket, riding
the ARP armoured horse (`Horse_armored` on `horse_rig`); each rider clip is an action on `rig` with its
horse action named in `act["horse"]`. Every authoring step, gate and owner ruling is in that folder's
`README.md` and `scripts/`. The export reads the file and saves nothing into it.

## Install

```
/Applications/Blender.app/Contents/MacOS/Blender -b -y SOURCE.blend \
  --python tools/units3d/cavalry_arp/game_export.py -- ROOT [OUT.json]
```

writes `cavalry.glb` and the three `cavalry_cavalry_atlas{,_mr,_n}.jpg` into
`ROOT/assets/3D/units/cavalry/` and prints (or writes to OUT.json) the measured report. Then a Godot
import, then the pivot / certificate steps below.

- **Skeleton** `cavalry_rig`, 120 bones: the knight's 70 deform bones plus `cc_weapon.r` under a bone
  `Saddle` (on the horse's `spine_02.x`), the horse's 48 deform bones. The pivot solver binds the legs
  by name (`Map3DRoyalPivot._CHAINS`), so the ARP horse legs are renamed: the front leg (ARP's
  `_dupli_001` leg) `c_thigh_b` / `thigh_twist` / `leg_stretch` / `foot` / `toes_01` →
  `FrontScapula` / `FrontUpperArm` / `FrontForearm` / `FrontCannon` / `FrontHoof` .L/.R, the hind leg
  `thigh_twist` / `leg_stretch` / `foot` / `toes_01` → `HindThigh` / `HindShin` / `HindCannon` /
  `HindHoof`. ARP cuts each long bone into two consecutive halves; the half whose origin is the joint is
  the chain bone, the other half rides it as a side child. The rider's `head.x` → `head` (the chip's
  bone, `Map3DUnitRig.head_m`), the horse's `head.x` → `head_h`, every other horse bone `h_<name>`.
  The stirrups (`h_stirrup.*`) ride the `Saddle` (they are the rider's, for the pivot's blend), the
  rein ends (`h_rein_hand.*`) the knight's left hand. Parents are anatomical (ARP hangs many deform
  bones off controls): the pivot blends the rider by its locals, so every joint is its parent's child.
  ARP's bendy bones (5 segments on the horse's thighs, upper arms, lower legs, `spine_02.x`) are plain
  bones in glTF; the difference is the bend's curvature along those bones.
- **Mesh** `cavalry`: knight, horse and spear merged, posed at rest = STANDBY's first frame (mounted,
  lance upright; the map sizes a piece from its rest mesh). ONE material `cavalry_atlas` on a
  4096 x 2048 atlas: knight (0, 0)-(0.5, 1) 2048 px, horse (0.5, 0.25) 1536 px, spear (0.875, 0.75)
  512 px; metallic x `GAME_METAL` 0.45 as the infantry's (a near-pure metal mirrors the dark map).
- **Decimation** (blender-decimate-quality skill, its `decikit`): knight 47,122 → 12,000 tris COLLAPSE
  (two passes, symmetry X, the face, hands, couter wings and every part under 120 vertices protected
  at weight 0.25; normals transferred from the source, which carries `k6_plate_normals.py`'s smoothed
  plates; no Weighted Normal, which would replace them). The skill's weld and normal recalc are not
  run: the knight is cut into parts on purpose (k2: each part owns its border vertices and weights) and
  its corner normals keep the winding they show. Spear: the head and butt cap COLLAPSE to 1,200 tris,
  the shaft between them rebuilt as an 8-sided tube (the skill: never collapse a slender part) on one
  line of the source's own wood texels. The horse (10,525 tris) is in budget and untouched.
- **Clips** (rider clip → game): MARCH ← MARCH (the run), STANDBY, GARRISON, DEFEND (the rear),
  ATTACK ← ATTACK_REAR_LOOP (in place; `ATTACK` / `ATTACK_STAB` gallop), PIVOT_LEFT / PIVOT_RIGHT ←
  the source turns (fixtures the pivot provider seeks, never plays). Keyed from frame 0; a loop whose
  last frame is not its first pose gets its first pose appended (MARCH: 13 frames, frame 14 = 1), else
  the residual is spread over its last 6 frames. Not shipped: DEATH (no cavalry caller; the thrown
  rider would widen the body envelope the footprints are measured from), KICK, HEAD_BUT, GRAZE,
  RIDE_WALK / RIDE_TROT, ATTACK / ATTACK_STAB / ATTACK_REAR, STAND_REST / STAND_RISE.
- **MARCH contacts** (`LOCK`, `_lock`): in the source run the left hind never comes nearer the ground
  than 44 mm, the right hind 11 mm, and the fronts skate (the horse pipeline left the run's fronts
  unpinned). The run is resampled 8 keys a frame (each bone's local interpolated, as Godot would) and
  each hoof's stance is locked: the cyclic run of keys where its lowest sole point is within 25 mm of
  its own lowest (or of the ground), narrowed to the longest part whose hoof stays within 5 cm of a
  straight path at the run's speed (the hinds set that speed); the hoof is held rigid at its
  mid-stance pose set down on the ground and carried straight back, the offset eases out over 16 keys
  either side, the leg follows by two-bone IK (upper arm / forearm, thigh / shin) with the pastern kept,
  and no key leaves a hoof under the ground. The dense MARCH is exported alone at 240 fps and its
  channels moved into the shipped GLB (`_transplant`); `cavalry.glb.import` bakes at `animation/fps`
  240 so Godot keeps them. The stride is the locked speed over the loop's 104 keys.
- **`cavalry.glb.import`**: MARCH, STANDBY, GARRISON, DEFEND and ATTACK loop;
  `animation/remove_immutable_tracks=false` (the reverse grip keys `cc_weapon.r` turned half round,
  constant over ATTACK: dropped, the lance would show the usual grip); the import script
  (`archer_arp/pivot_import.gd`) still re-keys the PIVOT pair exactly.

## Pivots and certificate

The cavalry pivot is the royal solver bound to this rig (`Map3DCavalryLocomotion`, plan
`assets/3D/units/cavalry/cavalry_pivot_plan.json`): it leaves, holds and rejoins MARCH at
`march_phase` 63/104 (the left hind and right fore planted). Its stand is the held MARCH pose with every
hoof seated (`stand_clip` MARCH): STANDBY's horse stands its left fore 22 cm ahead of the right, and
from the run's body the solver could not set that hoof down. Then `tools/units3d/certify_locomotion.py`
on `docs/reviews/cluster-formations/evidence/locomotion/cavalry/certificate.config.json`, and every
other arm's certificate re-issued (they hash `army_art.csv` and the cf01 `measurements.json`).
