# The infantry piece becomes the ARP short-sword + round-shield soldier

Owner 2026-11-16: replace the current infantry knight with the short-sword version of the
`infantry-no-rigging` Tripo soldier (rigged with Auto-Rig Pro, the owner's Mixamo clips retargeted
and hand-tuned 11-15/16, body material re-authored). The hand-axe version comes later as a second
model, possibly mixed per figure. The knight before it: `2026-10-19-infantry-arp-knight-design.md`.

## What changes

- `assets/3D/units/infantry/infantry.glb` and its three atlas JPEGs are rebuilt from
  `assets/3D/model_wip/blender_output/infantry/infantry_shortsword_shield.blend` (git-ignored) by
  `tools/units3d/infantry_arp/game_export.py` (moved from `soldier_arp/`, same contract: armature
  `inf_rig`, one skinned mesh `infantry`, gear rigid on `cc_weapon.r / .l`, ONE material on a 2048
  atlas with the old file names, rest = GARRISON frame 1, `head.x` → `head`, `GAME_METAL` 0.45,
  the shield wood toned, see Polish). The body's maps are the authored `body_{base,mr,normal}.png` (the
  body now has a normal map); every source map is found by its `_base / _mr / _normal` suffix.
- `scenes/models/units/infantry.tscn` is unchanged: its material override still lands on
  `inf_rig/Skeleton3D/infantry` and reads the same file names.
- Clips: MARCH (Standard Walk, in place), GARRISON (the guard), STANDBY and DEFEND (the owner's
  authored loops, now real: STANDBY was GARRISON's fallback), ATTACK, SLASH, ATTACK_VAR1, ATTACK_2,
  SLASH_2, SLASH_3 (once each; ATTACK_VAR1's 1.82 m and ATTACK_2's 2.17 m lunges taken out), and the
  regenerated PIVOT_RIGHT / PIVOT_LEFT. STANDBY / DEFEND loop in the `.glb.import`. Not shipped:
  BLOCK*, HIT*, DEATH*, TURN_*, RUN*, ADVANCE*, GARRISON_2, DEFEND_2/3 (they need runtime hooks).
- `army_art.csv` `chains` ATTACK: ATTACK;SLASH;ATTACK_VAR1;ATTACK_2;SLASH_2;SLASH_3.
- The knight GLB is gone from `assets/3D/units/infantry/`; its sources stay where they were.

## Export fixes the certifier found

1. **Loop closure.** The knight export lerped a loop's last 6 frames toward frame 1. These clips
   already end on their first pose (WALK 0.8 mm, IDLE 0.7°), so that pulled five frames of real motion
   toward frame 1 — across MARCH's right-foot touchdown, an 88 mm planted-sole slide. A loop is now
   closed by spreading only the first/last residual over those frames.
2. **Frame 0.** Clips were keyed from Blender frame 1, so the glTF began at t = 1/30 s and Godot held
   the first pose from 0: every loop stalled one frame (a planted foot stopped dead, 44 mm against
   the stride). Clips are keyed from frame 0 (MARCH 35 intervals, 1.167 s).
3. **MARCH contacts re-authored** (owner 2026-11-16, chosen over a `phase_map`, which could not get
   under the bound with a plausible pace: the remaining drift is partly sideways). The right toe
   dragged forward through its push-off (48 mm) and the swing skimmed the ground. `LOCK` pins each
   planted sole to travel back at the walk's own speed (two-bone IK on thigh and shin, offsets up to
   19 mm eased out through the swing) and lifts the first half of each swing to 5 mm clearance (up
   to 7 mm). A pinned point past the leg's reach is pulled back to it, the knee kept bent at least
   2° (up to 2.9 mm): a dead-straight stance knee (0.09°) sat on the IK singularity and the pivot
   helper's native-endpoint test failed there by rounding. Upper body, arms and gear are untouched. Native MARCH's worst planted slide: 11.9 mm.

## Measured

| | Knight | Short-sword soldier |
|---|---:|---:|
| MARCH `stride_m` (35 intervals) | 1.765 | 1.618 |
| `steps` (footfall shares) | 0.26;0.77 | 0.34;0.83 |
| Rest height (guard) | 1.604 m | 1.636 m |
| Tris / bones | 15,657 / 69 | 8,604 / 70 |
| Body envelope, every clip (cf01, size 0.62) | 927 m | 912 m |
| k (world m per model m) | 26.352 | 25.844 |
| R-A contact / seam bound | 22769 / 1898 µm | 23217 / 1935 µm |

`size` stays 0.62 (the soldier stands as tall as the knight); the infantry footprint radius 927 m
(`unit_footprints.csv`) stays and the 912 m envelope is inside it. The artillery borrows the same
figure at the same size: its all-clip envelope (912 m) is wider than its 875 m radius, as the
knight's (927 m) already was since the artillery took exact pace; its certified MARCH / pivot
envelope stays inside it.

## Pivots and certificates

The pivot mapping now reads the installed model (a `pivot_native.gd` capture with its skin and
mesh, the template from the GLB's joints) instead of the knight's frozen feasibility capture, which
remains only the mapping port's self-check. Parameters re-derived on this MARCH (owner gates R-A /
R-B of `docs/reviews/cluster-formations/owner-rulings-2026-11-10.md` unchanged): entry = exit
MARCH 13/14 (the passing frame, the same frame of the walk the knight's 25/28 was), NEUTRAL 181/420,
FOOT 168/420 and 387/420. Audit: 0 introduced skin flags, penetration 557 µm, hover / slide / seam
1 µm. The certificate admits stop, start and hold at MARCH 13/14 only.

`Map3DInfantryLocomotion` keeps the clip's own `root.x` (the hips' carrier) at every turn; only the
bones above it ease toward the entry pose for a small turn. Easing the root put the hips out of
reach of the held feet at ±1 µdeg and ±2° (this walk bobs more than the knight's).

Every locomotion certificate hashes `army_art.csv` and the cf01 `measurements.json`, so all five arms
are re-issued (`data/army/unit_locomotion.csv`); only infantry and artillery measure differently.

## Polish (owner 2026-11-17)

The first install's critic found four things; the owner agreed to all of them. All four are done in
the export (`POLISH`, `tools/units3d/infantry_arp/README.md`).

- **Shield up at rest.** At rest the men play STANDBY. Its shield hung at the side and showed edge-on
  from the map's height, so the unit read worse than the knight's ring of raised shields. STANDBY now
  keeps its relaxed body but takes the guard's (GARRISON's) shield arm, held up in front. The face is
  tilted 30° toward the sky so the play camera sees it lit, and the wood is lighter and warmer: held
  upright with the old tone, the raised shields read as black discs.
- **Mail calmed.** At play zoom the arm and leg mail read as dark speckle. The mail texels (the
  authored class mask) now keep a quarter of their ring contrast, a fifth of their normal relief and
  steadier roughness.
- **Thumb folded.** The shield hand's raised thumb (seen in the strikes, and present in every clip)
  now folds over the curled index.
- **MARCH blade out from the knee.** The hanging blade passing the knee is now rolled outward.

The polish took four critic rounds. The last one judged the regiment at rest as legible as the
knight's.

## Body value and resting variety (owner 2026-11-17: both fixed)

- On dark grass the dark mail and green tunic sank into the ground; without its shield a man was
  hard to make out. The export's `body_lift` / `body_sat` lift the authored classes (mail x1.35,
  green leather x1.4 and a richer green, plate x1.15; mail x1.55 read chalky), so the body reads off
  the turf.
- Every man rested at the same shield tilt and heading, so the ring read as identical copies.
  STANDBY's upper body now turns 10 degrees either way over its loop, with the feet planted
  (`rest_sway_deg`). The map already starts each resting man at his own phase of the loop, so at any
  moment each faces his own way. A per-figure turn in the map's code was tried (it read better at
  +/-18 degrees than at +/-8) and withdrawn: `Map3DUnitRig` and `Map3DLayerUnits` are pinned sources
  of the royal carrier proof (`Map3DRoyalCarrierSource._SOURCES`).
