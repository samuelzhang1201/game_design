# Militia: ARP short-sword + round-shield townsman

The militiaman: `assets/3D/units/militia/militia.glb` (armature `mil_rig`, one skinned mesh
`militia`, ONE two-sided material on the 2048 atlas `militia_militia_atlas{,_mr,_n}.jpg`; 17,437 tris, 100
bones). Built for the raised town militia of the player siege
(`docs/superpowers/specs/2026-11-18-player-siege-design.md`). It is the `militia` arm's piece (spec
`2026-11-26-militia-arm-design.md`) and a figure: a raised militia's roster
row names it as its `figure` (`TownMilitia.FIGURE`), and the 3D map draws that unit with
`scenes/models/units/militia.tscn` (`army_models.tres` and `army_art.csv` row `militia`,
`Map3DFormation.figure_of`) while its card, footprint and engine bodies stay its first arm's.

The body is the owner's parts Tripo militiaman (kettle hat, coif, knee-length tunic, belt, trousers, leg wraps,
shoes); the sword and shield are the infantry's. The clips are the infantry's first ten, on the infantry's
names, but NOT the infantry's motion: see Clips.

## Source (git-ignored)

`assets/3D/model_wip/blender_output/militia/militia_parts_11_hem.blend`: rig `rig` (Auto-Rig Pro), body
`Militia_body`, the infantry's `Weapon` / `Shield` on `cc_weapon.r / .l`, the ten clips. The build's steps,
gates and the owner's rulings are in that folder's `PLAN_parts_rebuild.md`; its scripts in `scripts/`
(`p1`..`p10`).

- Mesh: `tripo_inbox/units/no-rigging/soldier/militia_parts.glb` (71 parts, 58,374 tris) scaled to 1.8 m. Each
  part is decimated on its own budget through `blender-decimate-quality` (`p2_low.py`); the small fittings
  (buttons, rivets, buckle) are in the maps only. `Militia_body` is ONE object of separate shells, each face's
  part in the mesh attribute `part_id`: 14,138 tris.
- The skirt (the tunic below the belt) is rebuilt as a clean grid, 36 columns by 13 rows, open underneath: the
  material must be drawn two-sided. The trousers are whole legs under it; their seat is drawn in so a leaning
  trunk does not push it through the cloth.
- Maps: colour, metal-rough and normal baked at 2048 from the joined high mesh with the rig at REST
  (`textures_parts/MilitiaP_{base,mr,normal}.png`). Then `p8_skin.py` (the hands' skin matched to the face) and
  `p10_maps.py` (texels the bake missed filled from their neighbours; the kettle hat as iron: metal 1, roughness
  about 0.5, albedo 0.34 in the shield boss's warm grey; a brighter, smoother helmet blows out to chalk white on
  the brim under the sky seen from above).
- Rig: ARP at measured landmarks, bind, limit 4, normalize. 68 deform bones + 30 skirt bones + the two sockets
  = 100: the skeleton is NOT the infantry's.
- Skirt (`p6_skirt.py`): 10 chains of 3 deform bones (`skirt_NN_a/b/c`) under `root.x`. Nothing is simulated at
  run time: per frame a drape is computed (each column hangs from the belt by its cut and lies over the legs,
  taut sideways as a convex hull, with limits on how fast it rises and falls), the chains are marched down it
  and keyed into every clip. A chain's swing beyond its rest slope never grows down the chain, so the hem does
  not kick out like a brim. `exposure()` is the gate (leg faces through the skirt above its hem row),
  `repair()` and `nudge()` swing chains out on the frames a knee still cuts a corner.

## Clips

MARCH, GARRISON, STANDBY, DEFEND, ATTACK, SLASH, ATTACK_VAR1, ATTACK_2, SLASH_2, SLASH_3 (source actions WALK,
IDLE, STANDBY, DEFEND, ...). They are the infantry's shipped actions transferred onto this rig, then changed
for the tunic:

- Every clip but the walk stands NARROWER (`p9_narrow.py`, ankles and pelvis at 0.6 of the infantry's spread,
  pelvis raised, legs re-solved, feet planted): a 1.5 m hem cannot go round the infantry's guard stance.
- SLASH_3 squats less than the infantry's (the knees rose above the belt's pinned rows).
- Sole grounding by the foot vertices (`ground.py`) and gear clearance (`solve_clear.py`; the sword and shield
  may brush the free lower skirt).

No duel clips (BLOCK*, HIT*, DEATH*), so on the map it strikes its chain in place, is never gathered into a
duel, and a loss is freed at once with no fall (`army_art.csv` `militia` has no `duel` / `contact`). A raised
town militia never marches; a regiment of the `militia` arm does, on the pivot pair below.

## Pivots and the locomotion certificate (2026-11-26)

PIVOT_RIGHT / PIVOT_LEFT are appended to the installed GLB by the infantry's pipeline
(`tools/units3d/soldier_arp/README.md`, "Pivot clips") with `pivot_native.gd … militia` and
`pivot_mapping.py --arm militia` (`ARMS`: rig `mil_rig`, bounds 24202 / 2017 µm at k 24.7922, the infantry's
phases: on a 420-phase scan this MARCH has the same events at 8, 181, 182 and 396 of 420), then
`pivot.bake(bare GLB, solve, GLB, 4.0, rig="mil_rig")`. The `.import` names the pivot post-import script.
A re-export (`game_export.py`) writes the bare ten-clip GLB again: re-run all of it and the certificates.
Plan `assets/3D/units/militia/militia_pivot_plan.json`, fixture `tests/fixtures/militia_pivot_mapping.json`
(`test_pivot_mapping.py` re-audits and re-bakes it), provider `Map3DMilitiaLocomotion`, certificate
`docs/reviews/cluster-formations/evidence/locomotion/militia/`. Audit: skin flags introduced 0, penetration
1 µm, hover 278 µm, slide and seam 1 µm.

The skirt in a pivot. Its keys are baked for MARCH's legs at each frame, and a pivot plays the body through
one MARCH cycle over legs held at the passing frame: played as they are, a leg crosses the cloth in half the
frames. So (`pivot_mapping.py` `HELD`, `NUDGE`):

- the skirt's bones hold the passing frame's keys (182/420) with the legs, eased in over the first two steps
  and out over the last two;
- the two front chains over a leg (`skirt_00` / `01` left, `skirt_08` / `09` right) swing out 15° while that
  leg steps, leading and trailing the step by 3 % of the pivot (the knee rises under them; 9° still crossed on
  two frames, 12° is the least that clears), and the chain on either side of them swings half of that so the
  hem keeps a curve (alone, the two chains kicked the hem out to a corner). The legs cut at a 1° turn as at
  90°, so the swing is not scaled by the turn;
- at run time the plan's `held` list keeps those keys at every turn (a smaller turn eases the arms toward the
  entry pose, never the skirt).

`check_glb.py` prints no crossing on the installed pair, nor on the solver's poses at 1°, 45°, 135° and
179.999999° either way (each solved by `pivot_solve.gd` with the turn set in the case's `op`, baked onto the
bare GLB as the pair and checked the same way). A new MARCH, or new skirt keys, re-runs all of it.

## Install

```
/Applications/Blender.app/Contents/MacOS/Blender -b -y SOURCE.blend \
  --python tools/units3d/militia_arp/game_export.py -- ROOT [OUT.json]
```

`game_export.py` runs the infantry's exporter (`tools/units3d/infantry_arp/game_export.py`) with
`UNIT = "militia"`, `RIG_NAME = "mil_rig"`, `BODY = "Militia_body"`, `BODY_CLASSES = False`, the first ten
clips and the scene at 30 frames a second (the source's scene sits at Blender's 24, and the glTF exporter times
keys by the scene). From the infantry's export it keeps: rest = GARRISON frame 1, loops closed by their seam
residual, ATTACK_VAR1 / ATTACK_2 in place, MARCH's contact lock with the infantry's authored stances, the
shield thumb folded, the shield wood toned, metal at `GAME_METAL` of the authored map. The body has no authored
material classes, so no mail calming. The realm tint's mask `militia_tunic_mask.png` is drawn here from the
body's `part_id`: the tunic's and the skirt's faces where the body sits in the atlas, grown by the bake's
margin without entering another part's island, the bright linen at the neck left out (`LINEN`), softened
outward only and never onto another part's faces; the export reports its coverage and the cloth's mean linear luminance,
the tint material's `tunic_luminance` (0.052). It returns the MARCH measure: `stride_m` 1.5042 (the
lock's planted-sole speed, 0.045583 m a frame, over 33 frames), steps 0.2121; 0.9091.

MARCH's ground contact (2026-11-26, found by the locomotion certifier). The body carries its parts as vertex
groups (`p_shoes`, `p_wraps`, weight 1) beside the bones' groups, so the lock, which takes a foot's vertices by
their heaviest group, saw 79 of the right shoe's vertices and not its heel: the planted right shoe sank to 21 mm
under the ground, its toe scuffed 11 mm under it in the swing, and the stride came out 1.3597. The lock now
takes bone groups only (`_foot_points`), and for this body also sets each frame's height by the SKINNED sole
(`ARM_LOCK` `skin_ground`: the low shoe is skinned across the ankle, so a rigid sole on the ground still leaves
the skin 2 mm off it): every stance frame's lowest sole vertex is on the ground, every swing frame's 12 mm
clear until its last two; and the last swing frame before a touchdown already travels back with the ground
(`approach_frames` 1, as the plate soldier's). The legs moved, so two frames of MARCH crossed the skirt again: `SKIRT_NUDGE` in
`game_export.py` swings those chains out at export, as the source's `nudge` does (chains 8, 9 round frame 22
to 24, chains 3, 4 round 25 to 27), and the source is left as it is.

The `.import` files carry the infantry's settings: mesh compression off, MARCH / GARRISON / STANDBY / DEFEND
set to loop, the atlas textures and the mask as the infantry's.

## Check the installed file

```
/Applications/Blender.app/Contents/MacOS/Blender -b --factory-startup \
  --python tools/units3d/militia_arp/check_glb.py -- GLB FACES.json [SHOT_DIR]
```

`check_glb.py` re-imports the GLB and lists, per clip, the frames in which a leg crosses the skirt, with the
chains those faces hang on. It must print none. The .blend's own gate cannot see this: the export's MARCH foot
lock moves the legs after the skirt's keys were baked (one frame crossed on the first export; `nudge("WALK",
26, (8, 9), 4.0)` in the source cured it). `FACES.json` is the source's `textures_parts/exposure_faces.json`.
