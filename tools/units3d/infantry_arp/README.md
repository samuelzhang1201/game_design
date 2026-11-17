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
  taken out (in place). The other batch-2 clips (BLOCK*, HIT*, DEATH*, TURN_*, RUN*, ADVANCE*,
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
