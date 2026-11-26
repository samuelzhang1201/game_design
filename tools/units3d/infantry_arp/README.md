# Infantry: ARP short-sword + round-shield soldier (installed 2026-11-16)

THE game infantry (and the artillery's stand-in): `assets/3D/units/infantry/infantry.glb`, drawn by
`scenes/models/units/infantry.tscn`. It replaced the ARP knight (`tools/units3d/soldier_arp/`, spec
`docs/superpowers/specs/2026-10-19-infantry-arp-knight-design.md`). Spec of this one:
`docs/superpowers/specs/2026-11-16-infantry-arp-shortsword-design.md`.

## Source (git-ignored)

`assets/3D/model_wip/blender_output/infantry/infantry_shortsword_shield.blend`: the Tripo
`infantry-no-rigging.glb` soldier rigged with Auto-Rig Pro (rig `rig`, mesh `Infantry_body`), the
short sword `Weapon` and round shield `Shield` bone-parented to the `cc_weapon.r / .l` sockets, the
owner's Mixamo clips retargeted and hand-tuned there (stance widening, fist grip, carry offsets,
per-frame gear clearance, sole grounding, authored DEFEND loop, STANDBY = the pack's quiet idle). Body maps:
`textures/body_{base,mr,normal}.png` (4096, re-authored metal / leather / cloth classes), gear maps
`textures/ShortSword_*`, `RoundShield_*`. Every authoring step, script and gate number is in that
folder's `README.md` and `scripts/`; they stay beside their .blend files (git-ignored together).

Traps (from the authoring): ARP Smart scales the rig object; never `animation_data_clear()` an ARP
rig (it deletes the IK/FK drivers); never key `c_spine_03.x` (no retargeted clip keys it, so a key
leaks into every clip); a static base needs a key on every frame.

## Install

```
/Applications/Blender.app/Contents/MacOS/Blender -b -y SOURCE.blend \
  --python tools/units3d/infantry_arp/game_export.py -- ROOT [OUT.json]
```

`game_export.py` (nothing saved in the .blend) writes `infantry.glb` and the three
`infantry_infantry_atlas{,_mr,_n}.jpg` into `ROOT/assets/3D/units/infantry/`:

- armature `inf_rig` (68 deform bones + the two sockets, `head.x` renamed `head`), one skinned
  mesh `infantry` (body + gear merged, the gear rigid on its socket), ONE material on a 2048 atlas
  (body lower-left 3/4, sword and shield in the right strip; metallic x `GAME_METAL` 0.45, shield
  wood toned by `shield_tone`, below);
- rest = GARRISON frame 1 (the guard stance; the map sizes a piece from its rest mesh);
- clips WALK→MARCH, IDLE→GARRISON, STANDBY, DEFEND (loops closed by spreading the first/last
  residual over their last 6 frames — lerping those frames toward frame 1 dragged MARCH's planted
  right foot 88 mm), every clip keyed from frame 0 (keyed from 1, Godot held the first pose for a
  frame and each loop stalled), and WALK's ground contacts re-authored (`LOCK`, owner 2026-11-16,
  below),
  ATTACK, SLASH, ATTACK_VAR1, ATTACK_2, SLASH_2, SLASH_3; ATTACK_VAR1's and ATTACK_2's lunges
  taken out (in place); then the front-rank duel's clips (`scripts/map3d/guide/battle_duels.md`),
  appended after the first ten: BLOCK, BLOCK_2, BLOCK_3, BLOCK_4 (the first three's 0.20 / 0.22 /
  0.27 m steps taken out: a duellist blends back to guard in 0.15 s), HIT, HIT_2, HIT_3, DEATH,
  DEATH_2 (their fall kept: 1.13 / 0.92 m back). Their `contact` shares in `army_art.csv` are
  measured off these source clips. The other batch-2 clips (TURN_*, RUN*, ADVANCE*,
  GARRISON_2, DEFEND_2/3) are not shipped until their runtime hooks exist; helper actions
  (`*_retarget`, `*_raw`, `WALK_base`, `STANDBY_src`, `STANDBY_authored`, `ATTACK_swordcut`) never are;
- the .blend's WALK is a copy of the pack's combat walk `ADVANCE` (Pro Sword and Shield Pack
  "sword and shield walk", 34 frames, made in place in batch 2): the sword carried up on the right
  shoulder, the shield before the left side, short guarded steps. Owner 2026-11-18, after seeing it
  beside Standard Walk and "walk (2)"; the Standard Walk (with its sword arm swung out at the
  shoulder, below) is kept as `WALK_standard`, never shipped;
- the .blend's STANDBY is a copy of the pack's quiet guard idle `GARRISON_2` (Pro Sword and Shield
  Pack "idle (4)", 76 frames, retargeted and gripped like the batch-2 clips; the earlier authored
  rest is kept beside it as `STANDBY_authored`; `holds.py standby` would rebuild that one, so never
  rerun it onto STANDBY): shield up before the chest, sword low,
  feet planted, a small breathing sway. Owner 2026-11-17: the authored rest (a neutral stand,
  GARRISON's shield arm grafted on, the wrist tilting the shield up and the chest swaying ±10°)
  read wholly unnatural; take the pack's own. The pack's other idles: `idle` is GARRISON,
  `idle (2)` / `idle (3)` are long flourishes that read as attacks, `block idle` / `crouch block
  idle` are DEFEND_2 / DEFEND_3;
- it returns the MARCH measure for `army_art.csv`: `stride_m` 1.4838 (the locked sole speed x 33
  intervals), `steps` 0.2121;0.9091 (the authored stances' starts), and the rest height 1.636 m,
  8,604 tris.

MARCH contact lock (`LOCK`, `_lock_feet`): in a retargeted in-place walk a planted sole does not
travel back at one speed (the Standard Walk's right toe slid 48 mm through its push-off; the
certifier's bound is 23.2 mm). A foot is planted while its lowest point is within 4 mm of its
lowest in the clip AND its deepest sole points travel back at least half the walk's median planted
speed; then those points are made to travel straight back at that speed (0.0450 m a frame on the
pack walk), the foot moved by the accumulated difference (orientation kept), thigh and shin
following by two-bone IK in their own bend plane; the offset eases to zero through the swing
(largest 36 / 41 mm, left / right). A pinned point past the leg's reach is pulled back to it with
the knee bent at least `min_knee_deg` 2°: clamping the knee straight left the foot off the shin
and the leg on its singular pose, where the pivot helper's native endpoint check fails on float
rounding. The pack walk is a guarded shuffle: its soles rock 5-8 mm off the ground mid-stance and
the right boot taps down mid-swing, so a height test cut its stances into pieces and the certifier
counted the tap as planted (289 mm slide). Its stances are therefore authored (`stance`: left
0.20-0.86, right 0.90-0.35 of the loop), each planted sole is also set on the ground (z = 0), and
the whole swing but its last `land_frames` 2 is lifted until it clears `clear_m` 12 mm (eased
over 3 frames; largest 16 mm). The stride is then exactly the locked speed over the loop, which
the export reports (the ankle-based measure gave 1.40, 6 % under it).

Polish (`POLISH`, owner 2026-11-17, the first install's critic notes; each knob bracketed in
real-window and map shots, two critic rounds; overridable with the `INFANTRY_POLISH` environment
variable as JSON):

- shield wood: planks and rim drawn to `shield_contrast` 0.55 of their spread about the mean
  colour (a light ochre plank stood out), then
  `shield_tone` (1.25, 0.95) (saturation, value shares): the knight's (0.55, 0.8) left the raised
  shields near-black discs on the map, (0.9, 1.2) chalky discs brighter than the banner;
- shield hand: in every clip the thumb chain turns about its base until its tip rests at
  `thumb_tip` in the hand's frame (over the curled index), up to 38°: the retargeted grip laid
  the thumb along the handle (the guard's own grip too, so copying its fist changed nothing);
- MARCH blade: the pack walk carries the sword on the shoulder, 0.55 m from the leg axes at its
  closest (`march.blade_leg_gap`, reported by the export). On the Standard Walk the hanging blade
  passed the knee; `WALK_standard` keeps that walk with its FK sword arm `c_arm_fk.r` swung out at
  the shoulder (blade at least 30° out of the mid-plane; an earlier export-time fix turned the
  wrist alone, a kinked wrist, owner 2026-11-17). Backup of the source before these edits:
  `infantry_shortsword_shield_before_2026-11-17.blend` beside it;
- body value `body_lift` / `body_sat`: the colour of the authored classes multiplied (mail x1.35,
  green leather x1.4 and its saturation x1.35, plate x1.15): on dark grass the dark mail and tunic
  sank into the ground (mail x1.55 read chalky at play zoom);
- mail (class 2 of the authored `textures/body_class.npy`): colour keeps 25 % of its ring contrast
  against a 3 px box blur, the normal 12 % of its relief, roughness 30 % of its variation + 0.3
  (less made it read oily in close-ups).

- plate pieces (owner 2026-11-26: the kettle hat's brim read as camouflage, and the helmet as painted
  cloth): the helmet, pauldrons and knee cops are classed plate by GEOMETRY, not colour
  (`scripts/uvmask_plate.py` beside the source, from `scripts/dump_mesh.py`'s mesh: the helmet is
  grown from the dome over joined faces that are not skin, hair or mail), their off-colour texels
  take the piece's mean plate colour with the old relief flattened, and plate is drawn 0.7 of the
  way to bare steel, value x0.80 (x1.05 clipped the knee cops on the map), roughness 0.40 (`PLATE_STEEL` / `PLATE_VALUE` / `PLATE_ROUGH` in
  `scripts/matmaps.py`; the olive paint and bare cold steel were the other two shown). Grey smooth
  texels anywhere else are mail, never plate. The tunic mask lost the brim's green patches with it.

A texture-only re-author installs without the pivot pipeline: export to a scratch ROOT, copy its
three atlas files and the tunic mask in, then `python3 tools/units3d/infantry_arp/swap_images.py
assets/3D/units/<ARM>/<ARM>.glb assets/3D/units/<ARM>` replaces the GLB's packed images and leaves
every other byte (mesh, skin, clips, the appended pivot pair) as it was.

The new clips' loop modes are the `.glb.import` settings (STANDBY / DEFEND loop). Then the pivot
pair is regenerated (below) and appended to the GLB.

## Pivot clips and certificate

PIVOT_RIGHT / PIVOT_LEFT are the coupled author mapping of `tools/units3d/soldier_arp/`
(`pivot_mapping.py`, its README "Pivot clips"), now read from the installed model, not the frozen
knight capture:

1. `pivot_native.gd` with `"baseline": true` captures the imported skin, mesh and MARCH
   (the 420-phase scan that chose the parameters below);
2. `pivot_mapping.py request BASELINE OUT [NATIVE...]` → `pivot_native.gd` until nothing is
   missing; `build` → `pivot_solve.gd` → `audit` (R-A / R-B) → `pivot.bake(bare GLB, solve, GLB, 4.0)`;
3. `plan` writes `assets/3D/units/infantry/infantry_pivot_plan.json`; `fixture` packs
   `tests/fixtures/infantry_pivot_mapping.json` (baseline, MARCH capture, solve).

Parameters measured on this MARCH (the pack walk): entry = exit 8/420 (the right sole flat at
0.2 mm, the left boot just lifted 8 mm, thighs 13.8° apart: the guarded shuffle never brings them
nearer on that side, the Standard Walk's frame was 5.9°); NEUTRAL 182/420 (thighs 7.1° apart, the
left sole planted); FOOT left 181/420, right 396/420 (flattest planted sole, spread 7.0 / 3.7 mm).
Bounds R-A at k 25.8437 world m per model m: contact 23217 µm, seam 1935 µm. Audit: skin flags
introduced 0, penetration 27 µm, hover / slide / seam 1 µm on both turns. Stop, start and hold
are admitted at MARCH 8/420 only.

Then `tools/units3d/certify_locomotion.py` re-issues the infantry and artillery certificates
(`docs/reviews/cluster-formations/evidence/locomotion/{infantry,artillery}/`) and their rows in
`data/army/unit_locomotion.csv`, `body_locomotion_*_contact_um` in `data/army/balance.csv`.

## Another body on the same contract: the heavy infantry (installed 2026-11-20)

`game_export.py -- ROOT [OUT.json] ARM` installs any source that keeps the contract above (rig
`rig`, body `Infantry_body`, gear `Weapon` / `Shield` on `cc_weapon.r / .l`, body maps
`textures/*_{base,mr,normal}.png`, the same action names) as `assets/3D/units/<ARM>/<ARM>.glb`:
mesh `<ARM>`, atlas files `<ARM>_<ARM>_atlas{,_mr,_n}.jpg`, the armature `inf_rig` for every arm.
With no ARM the infantry's files come out byte for byte as before. A source with no
`textures/body_class.npy` has no authored material classes: the class polish (mail, body lift) is
skipped, the rest (shield wood, thumb, MARCH lock, loops, in-place strikes) applies.

The heavy infantry (`heavy_infantry`, spec `2026-11-20-heavy-infantry-arm-design.md`) is the owner's
Tripo plate soldier, `assets/3D/model_wip/blender_output/heavy_infantry_parts/hip_shortsword_shield.blend`
(README there: 79 parts joined, decimated per part 53,269 → 11,410 tris, maps baked from the high
mesh, the infantry's 30 clips retargeted): 14,709 tris with the gear, 70 bones, rest height
1.599 m, MARCH `stride_m` 1.473 (0.044636 m a frame × 33), `steps` 0.2121;0.9091, foot lock
offsets 73 / 55 mm, blade–leg gap 0.49 m.

Its MARCH lock adds one thing (`ARM_LOCK`, `approach_frames` 1; `INFANTRY_LOCK` overrides it as
JSON for a trial): the last swing frame before each touchdown is moved so the sole already travels
back with the ground to its landing place, its height kept, and the swing before it eases onto
that offset; the stance is not moved. This boot is skinned across the ankle, so its sole sinks
3 mm under the lock's ground and enters the certifier's planting band a sixth of a frame before
the touchdown key, the foot still closing on its landing place at 0.09 m a frame: 12.1 mm of
slide and an 11.6 mm margin against a 22.7 mm bound. With the approach the left foot's worst is
5.2 + 11.8 mm (a pinned approach point 9 mm past the leg's reach is pulled back to it, in the
air). Moving the whole stance back instead (integrating the lock from the approach frame) left
the leg 16 mm short at the end of its stance; two approach frames 36 mm short. A quick reading of
the certifier's MARCH slide without its full run: capture MARCH with `pivot_native.gd` (keys,
quarter points and a 512 grid, `"baseline": true`) and feed each foot's vertices to
`certify_locomotion.vertex_slide`.

Steps after the export:

1. `.import` files: copies of the infantry's (loops, `force_disable_compression`, the pivot
   post-import script) with the paths renamed and `uid` / `path` / `dest_files` removed; one
   `--import` pass fills them.
2. Pivot pair: the same pipeline with `pivot_native.gd … ARM` and `pivot_mapping.py --arm ARM`
   (its `ARMS` table holds what differs: this body keeps the infantry's phases, its bounds are
   22699 / 1892 µm at k 26.4330); `pivot.bake` onto the bare export; `plan` writes
   `assets/3D/units/heavy_infantry/heavy_infantry_pivot_plan.json`, `fixture`
   `tests/fixtures/heavy_infantry_pivot_mapping.json`; `test_pivot_mapping.py` checks both arms.
3. Scene: `make_scene.gd -- ARM` writes `scenes/models/units/<ARM>.tscn` (an inherited scene
   wearing the infantry scene's material with this arm's atlas) and its `army_models.tres` row; a
   script run drops the ext_resource UIDs, put them back and read `git diff`.
4. Provider `scripts/map3d/map3d_heavy_infantry_locomotion.gd` (the infantry's solver on this
   plan), then the certificate, `unit_locomotion.csv` and `balance.csv` rows as above.

## The axemen (installed 2026-11-23)

The axemen's hand-axe soldier (`axemen`, spec `2026-11-18-axemen-arm-design.md` step 4) is this
infantry with the owner's hand axe in place of the sword: `assets/3D/model_wip/blender_output/infantry/infantry_handaxe_shield.blend`
(README there: the axe grip a third up the haft in the walk and the holds, the authored chop as
ATTACK, the batch-2 clips with the axe grip). It keeps the contract and the authored body classes,
so the export is the infantry's with ARM `axemen`: 9,105 tris, 70 bones, rest height 1.636 m,
MARCH `stride_m` 1.4838 and `steps` 0.2121;0.9091 (the same walk: its legs match the infantry's to
2e-7 m over a 420-phase capture), foot-lock offsets 36 / 41 mm, axe–leg gap 0.51 m. Its tunic mask
is the infantry's byte for byte (not shipped twice); its realm tint is
`scenes/map3d/materials/unit_realm_tint_axemen.tres` (the overlay must read the figure's own atlas).
Pivots: `pivot_mapping.py --arm axemen` with every infantry value; plan `axemen_pivot_plan.json`,
fixture `tests/fixtures/axemen_pivot_mapping.json`. Scene `scenes/models/units/axemen.tscn` and the
`army_models.tres` / `realm_tint.tres` rows were made in the editor; provider
`Map3DAxemenLocomotion`. The duel's `contact` shares were measured off the source: ATTACK 0.58 is
the chop's impact (key 18 of 31, where the head stops), ATTACK_2 0.49, SLASH_2 0.53, SLASH_3 0.44;
the rest are the infantry's (the same motions).
