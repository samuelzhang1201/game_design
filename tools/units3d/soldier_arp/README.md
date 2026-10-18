# ARP knight (no-rig Tripo soldier)

Source: `assets/3D/model_wip/tripo_inbox/units/no-rigging/soldier/tripo/medieval+knight+3d+model no rig.glb`.
Work file (git-ignored): `assets/3D/units/soldier/model_wip/arp_knight_20261018/soldier_knight_arp.blend`
(`soldier_knight_arp_palmfwd_backup.blend` = before the rest-pose fix). Not installed in the game. Game GLBs: `…/arp_knight_20261018/export/` (`export.py`).

Done in the owner's Blender through the MCP (`ctx.py` gives ARP's operators the 3D viewport they need):

1. Mesh scaled 1 m → 1.8 m, doubles merged (10,792 → 5,262 verts), transforms applied; faces −Y.
2. ARP Smart, body markers placed from mesh slices; 3 spine bones, 5 fingers (voxel engine).
   `match_to_rig`, `bind_to_rig` (heat map): no unweighted vertex.
3. **Rest pose fixed**: the Tripo T-pose has the palms FORWARD (thumbs up); Mixamo's is palms down,
   so every retargeted hand faced up. Both `c_hand_fk` turned 90° about world X (forearm twist
   distributes it), `arp.apply_pose_as_rest` (INVOKE: its execute alone has no rig) + `match_to_rig`.
   Smart had also detected the fingers on the palms-forward hand and swapped index and pinky:
   their reference bones were swapped back, then rebound.
   The legs were also turned OUT in the T-pose (toes and knees 20° / 18° outward; Mixamo's are 0°),
   which added 20° of toe-out to every clip: each `c_thigh_fk` turned ~19° inward about the hip–ankle
   axis, applied as rest the same way (`_toeout_backup.blend` = before). WALK now toes out 4–20°.
   The legs also stood apart (hips ±12.6 cm, legs 3.9° out, ankles ±17 cm; Mixamo: legs vertical,
   ankles ±8 cm), which tripled the walk's step width: both `c_thigh_fk` turned 3.23° inward about Y
   (ankles ±12 cm, the thick trousers just touching mid-thigh), applied as rest (`_wide_backup.blend`
   = before). Step width on WALK ~16 cm (was ~27 cm).
   Then every clip is rebuilt by `rebuild.py`: `retarget_all`, `fix_grip`, `WALK_CARRY`, `solve` on
   the three attacks. `arp.apply_pose_as_rest` must run with NO actions in the file (else it opens a
   confirm dialog and returns RUNNING_MODAL without applying).
4. `retarget.py` (`retarget_all()`): each FBX in `assets/3D/model_wip/Motion/` through ARP Remap with
   the built-in `mixamo_fk` map, FK limbs, `auto_scale`, linear keys.
5. `equip.py`: `fix_grip` keys every finger control to IDLE's fist in all clips; `make_sockets` adds
   `cc_weapon.r/.l` (children of `hand.*`, non-deform, `cc_` so ARP keeps them) at the fist hole
   fitted from circles through each finger's joints (+Y thumb side, +Z the knuckles' way); `mount`
   bone-parents `Sword` (short_sword) on `.r` as is and `Shield` (round_shield) on `.l` turned 90°
   about the grip and 3 cm out, so its face is on the back of the hand (Mixamo's shield arm lies
   across the chest, knuckles to the right). `world_offset` + `WALK_CARRY`: the walk's arms kept hanging — 6–8° out at the shoulder, the
   forearm brought 10° back in at the elbow (owner: the forearm flaring out looked ugly; it now sits
   4–15° out, the clip's own ~12°), the forearms turned so the shield hangs flat outside the left leg
   and the blade lies outside the right with its point raised 40°; clear on all 36 frames
   (`WALK_raw` = before). Weapons from
   `tripo_inbox/equip/no-rigging/{short_sword,round_shield}/processed/soldier_ue5/`.
8. `skirt.py`: the fauld (plates) and the mail skirt are ONE fused island; the mail between and
   under the plates followed the thighs, the plates the hips, so the mail slid over the plates.
   `fix_skirt` order: `open_gap` (mail under the plates pushed ≥2 cm in, along the PLATE normal —
   the mail's own normals are inconsistent), `slim_thighs(clearance=0.05, max_slim=0.04)` (trouser
   verts hidden under the skirt pulled toward the thigh bone), `share_weights(radius=0.07,
   band=(0.78, 1.10))` (spatial Gaussian smoothing over the plate height only; the hem below keeps
   following the thighs). Tried and dropped: the whole band (thighs then poked through the plates),
   a procedural L/R field (the front split open), plates copying the mail's weights (no better).
   `_skirt_backup.blend` = before.
9. `metal_map.py` + `metal.py`: the Tripo export had only a colour map (metallic 0, roughness 0.9 —
   the armour read as cloth). `knight_metal_rough.png` (G roughness, B metallic) is authored from it:
   low saturation = metal, plates 0.38 rough, mail (high local contrast) 0.50, the rest 0.78 matte.
   Previews use Blender's `city.exr` studio light (metal needs something to reflect).
10. `export.py` (`export_all()`): a new constraint-free armature with the 67 deform bones and the
   `cc_weapon.l/.r` sockets (`head.x` renamed `head`), each clip baked frame by frame from the ARP
   rig (largest bone error 1e-6 m) into NLA tracks WALK / IDLE / SLASH / ATTACK / ATTACK_VAR1, the
   body skinned linearly (glTF keeps 4 influences), its colour and metal/rough maps at 2048, turned
   to face glTF −Z like the other units. `soldier_knight.glb` carries the sword and shield as
   children of the socket joints (identity local transform — Godot imports them as
   BoneAttachment3D); `soldier_knight_sword.glb` / `_shield.glb` are the gear alone with the socket
   as origin, for swapping. `export.json` records clips, bake error and a summary of each GLB.
   Open: ATTACK_VAR1 keeps its 1.86 m lunge (root travel in the clip).
Previews: `preview.py` (EEVEE, fixed three-quarter camera) → `preview/<CLIP>/` PNGs, GIFs beside them.
6. `check_gear.py`: per-frame polygon overlaps of sword/shield × body (holding hand and forearm
   excluded) and sword × shield.
7. `solve_clear.py` (`solve(clip)`, `report(clip)`): SLASH / ATTACK / ATTACK_VAR1 corrected per frame
   on both arms, relative to `<CLIP>_raw` and written once from it (re-runs never stack): wrist
   flex/deviation within ±40°, the shoulder (about the chest's axes, ±45°) only when the wrist
   cannot clear it, wrist bend past 70° penalised, changes between frames penalised, smoothed.
   Largest corrections: SLASH right hand 66° (wrist 82° vs raw 69°, shoulder 10°); ATTACK_VAR1 right
   hand 47° / shoulder 19°, left shoulder 31°; per-frame change ≤ 26°.

| Action | Source | Frames | Root | Frames clipping (sword·body / shield·body / sword·shield) |
|---|---|---|---|---|
| WALK | general/Standard Walk | 1–36 | in place | 0 / 18 (≤71 faces, shield graze on the thigh) / 0 |
| IDLE | infantry/Sword And Shield Idle | 1–111 | in place | 0 / 0 / 0 |
| SLASH | infantry/Sword And Shield Slash | 1–46 | returns | 0 / 0 / 0 |
| ATTACK | infantry/Sword And Shield Attack | 1–31 | in place | 0 / 0 / 0 |
| ATTACK_VAR1 | infantry/Sword And Shield Attack - var 1 | 1–53 | lunges 1.86 m | 2 / 0 / 0 (frames 7–8: the sword fist crosses the shield fist) |

`Two Hand Club Combo` is not on this figure: it belongs to a longsword, no-shield one (owner).

Open: ATTACK_VAR1 swings the shield flat at frame 9 (as the source clip does); game export
(constraint-free skeleton like `archer_arp/export.py`, the `cc_weapon.*` sockets kept); whether
the lunging clip keeps its travel.
