# The longbowman (archers)

The owner's parts Tripo archer (`assets/3D/model_wip/tripo_inbox/units/no-rigging/archers/archer.glb`,
2026-11-27) on the infantry's rig contract, driven by the supplied Mixamo clips
(`assets/3D/model_wip/Motion/arhcer`). Built in Blender (git-ignored work folder
`assets/3D/model_wip/blender_output/archer/`, its `README.md` and `scripts/`); installed by `game_export.py`
here, which runs the infantry's exporter (`tools/units3d/infantry_arp/game_export.py`) with the archer's names.

## Source

`arc_longbow.blend`: rig `rig` (Auto-Rig Pro, Smart markers, the militia's landmarks), body `Infantry_body`
whose faces carry the Tripo part id in the attribute `part`; gear `Bow` on `cc_weapon.l` (its string on the hook
bone `cc_bow_string`), `Arrow` on `cc_arrow` (scaled to 0 while not drawn), `Quiver` on `spine_02.x`.
`arc_longbow_hi71k.blend` keeps the 71k-triangle version the maps were baked from.

Decimated per Tripo part with decikit (`blender-decimate-quality`), body 70,967 to 14,777 tris (sub-2 cm parts
under 100 tris deleted, baked into the maps), bow 8,130 to 2,000, arrow 13,310 to 1,300, quiver 17,863 to
4,000; the body's maps baked from the 71k at 4096. Audit notes (the gate's three body failures, each a property
of the source): its 367 fins (edges of 3+ faces, eyes and straps glued on) are kept (370 after), the 25 deleted
rivets are the part count's drop (70 to 45), and the flipped share (1.07 %) is layered cloth found under another
part; measured against its own part it is 0.11 %. The arrow's and the quiver's shafts are slivers by nature
(21 % and 14 %, gate widened for them; shape, flips and parts still gated). Run headless with `--factory-startup`:
the ARP add-on's handlers made every operator rebuild the rig's depsgraph.

## Clips (source action -> game clip)

| Source | Game | Loop | Played by the map |
|---|---|---|---|
| WALK | MARCH | yes | marching, and the pivots' body |
| AIM | GARRISON | yes | garrison, hold (DEFEND falls back to it) |
| IDLE | STANDBY | yes | standby; its frame 1 is the rest the map sizes the piece by |
| SHOOT | ATTACK | yes | attack (draw, aim, release, reach back); a unit the engine has firing in battle (Map3DVolleys), each loosing a drawn arrow at its release (`contact` ATTACK 0.8088, frame 55 of 68) |
| DRAW | DRAW | no | — |
| RUN | SPRINT | yes | — |
| HIT, HIT_2, HIT_3 | same | no | — |
| DODGE, DODGE_L, DODGE_R | same | no | — |
| DEATH | DEATH | no | — |

The archers have no `duel` row (`army_art.csv`), so the hit, dodge and death clips ship for a battle hook still
to come. PIVOT_RIGHT / PIVOT_LEFT are appended after the export (below).

## Install

    Blender -b -y --factory-startup arc_longbow.blend --python tools/units3d/archer_parts/game_export.py -- ROOT [OUT.json]

Writes `assets/3D/units/archers/`: `archers.glb` (armature `inf_rig`, one skinned mesh `archers`, bow, quiver and
arrow in its atlas), `archers_archers_atlas{,_mr,_n}.jpg` and `archers_tunic_mask.png` (the gambeson's faces,
parts 0, 10 and 12, coverage 7.8 %; `tunic_luminance` 0.069 in `unit_realm_tint_archers.tres`). The arrow is
kept at a scale of 0.001 while not drawn (a scale of 0 is singular, which the pivot solver refuses).

MARCH's foot lock: the retargeted walk's sole lifts 40 mm mid-stance (right) and drags forward on the ground
before it lifts (left), so the stances are authored from the soles' back-travel (`ARM_LOCK`: left 12-31, right
26-12 of 36 frames). Stride 1.2586 m (0.03496 m a frame over 36), footfalls 0.3333 and 0.7222.

Then, as the militia: `.import` files (MARCH, GARRISON, STANDBY, ATTACK, SPRINT loop; the shared post-import
`archer_arp/pivot_import.gd`), an import pass, the scene by `tools/units3d/infantry_arp/make_scene.gd -- archers`
(its UIDs put back), and the pivot pair.

## Pivots and the locomotion certificate

`pivot_native.gd … archers`, `pivot_mapping.py --arm archers` (`ARMS`: on a 420-phase scan of this MARCH, the thighs most nearly parallel at 400/420, right sole planted, are both the entry/exit and the held frame, and the held feet stand where that frame's soles do (`PLACE_NATIVE`); left foot shape from its flattest planted sole, 160/420. A pivot's step lifts in proportion to the turn but travels whatever the turn, so a mid-stride entry (359/420) slid the right sole 197 mm at a 1 µ° turn and feet held under the hips 118 mm; bounds 23325 / 1944 µm at k 25.7242), `pivot_solve.gd`, `audit` (skin introduced 0, penetration 12 µm, hover 7.7 mm (the left foot up at the entry), slide and seam 1 µm), `pivot.bake`,
`plan` (`archers_pivot_plan.json`), `fixture` (`tests/fixtures/archers_pivot_mapping.json`;
`test_pivot_mapping.py` re-audits and re-bakes it). Provider `Map3DArcherLocomotion`, certificate
`docs/reviews/cluster-formations/evidence/locomotion/archers/`. A re-export writes the bare thirteen-clip GLB
again: re-run all of it and the certificates.

## Known

The full draw's string passes through the cheek; the quiver hangs 26 cm off the spine; DODGE_L turns the bow
flat; the body atlas is a smart-UV pack with many small islands.
