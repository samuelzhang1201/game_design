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
shoes); the sword and shield are the infantry's. The clips are the infantry's first ten and its seven BLOCK / HIT
duel clips, on the infantry's names, but NOT the infantry's motion: see Clips.

## Source (git-ignored)

`assets/3D/model_wip/blender_output/militia/militia_parts_12_duel.blend` (its first ten clips are
`militia_parts_11_hem.blend`'s): rig `rig` (Auto-Rig Pro), body `Militia_body`, the infantry's `Weapon` /
`Shield` on `cc_weapon.r / .l`, the ten clips and the seven duel clips. The build's steps,
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

Then the front-rank duel's BLOCK, BLOCK_2, BLOCK_3, BLOCK_4, HIT, HIT_2, HIT_3 (spec
`docs/superpowers/specs/2026-11-26-militia-figure-wiring-design.md` step 1), in the source
`militia_parts_12_duel.blend` (a copy of `_11_hem`; that folder's `PLAN_parts_rebuild.md`, script
`scripts/p11_duel.py`): the infantry's actions transferred by `s12_transfer.py`, narrowed by `narrow_duel`
(p9's 0.6 about the start's ankle midpoint, the pelvis moved with the narrowed feet so a fall would keep its
travel, the raise weighted by how upright the trunk is), the skirt baked and `repair`ed, the shield cleared by
`solve_clear`, the sword cleared out of the crouching blocks' spread skirt by `solve_sword_cloth` (the skirt
counted for the sword hand only). Their `contact` shares in `army_art.csv` are the infantry's: the transfer keeps
the timing. The exporter takes BLOCK..BLOCK_3's steps out, as the infantry's.

No DEATH clips yet (step 1b): the skirt's drape hangs columns round a vertical axis and cannot follow a body on
the ground (face down it stands off the back, on the back the legs come through it), so a loss is freed at once
with no fall. No pivots or locomotion certificate (step 2): a raised town militia never marches; a regiment of
the `militia` arm does, and with no `unit_locomotion.csv` row the candidate locomotion path refuses the arm
until a pivot pair and a certificate are made for this body (the infantry's pipeline,
`tools/units3d/soldier_arp/README.md`, with the skirt's keys to solve for a pivot).

## Install

```
/Applications/Blender.app/Contents/MacOS/Blender -b -y SOURCE.blend \
  --python tools/units3d/militia_arp/game_export.py -- ROOT [OUT.json]
```

`game_export.py` runs the infantry's exporter (`tools/units3d/infantry_arp/game_export.py`) with
`UNIT = "militia"`, `RIG_NAME = "mil_rig"`, `BODY = "Militia_body"`, `BODY_CLASSES = False`, the first ten
clips and the seven duel clips, and the scene at 30 frames a second (the source's scene sits at Blender's 24, and the glTF exporter times
keys by the scene). From the infantry's export it keeps: rest = GARRISON frame 1, loops closed by their seam
residual, ATTACK_VAR1 / ATTACK_2 in place, MARCH's contact lock with the infantry's authored stances, the
shield thumb folded, the shield wood toned, metal at `GAME_METAL` of the authored map. The body has no authored
material classes, so no mail calming. The realm tint's mask `militia_tunic_mask.png` is drawn here from the
body's `part_id`: the tunic's and the skirt's faces where the body sits in the atlas, grown by the bake's
margin without entering another part's island, the bright linen at the neck left out (`LINEN`), softened
outward only and never onto another part's faces; the export reports its coverage and the cloth's mean linear luminance,
the tint material's `tunic_luminance` (0.052). It returns the MARCH measure: `stride_m` 1.3597 (the
militia's own; with the infantry's 1.4838 its feet slide), steps 0.2121; 0.9091.

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
